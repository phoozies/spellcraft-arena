#!/usr/bin/env node
// Fallback sync for machines without the Rojo CLI.
//
// Serves the Rojo tree described in default.project.json as JSON on
// http://localhost:34873/manifest (and a hash of it on /version). The
// Spellcraft Sync plugin (tools/studio-sync-plugin.lua) polls /version and
// syncs the place in Edit mode whenever the repo changes, like `rojo serve`.
// Code run through the Studio MCP can't reach localhost (the Assistant HTTP
// allowlist), so the plugin is how the MCP-driven workflow syncs.
// tools/studio-sync.luau is a one-off fallback for the command bar. Prefer
// Rojo when installed.
//
// Usage: node tools/studio-sync.js                    serve
//        node tools/studio-sync.js --install-plugin   install or update the
//                                                     plugin (once), then serve

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const http = require("http");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const PORT = 34873;

// Rojo file conventions -> Roblox class + instance name.
function classify(fileName) {
	if (fileName.endsWith(".server.luau")) return { className: "Script", name: fileName.slice(0, -12) };
	if (fileName.endsWith(".client.luau")) return { className: "LocalScript", name: fileName.slice(0, -12) };
	if (fileName.endsWith(".luau")) return { className: "ModuleScript", name: fileName.slice(0, -5) };
	return null;
}

// Walks a directory into a list of { path: [...segments], className, source }.
// `root` marks a $path mapping: only these subtrees are cleaned up on sync.
function walk(dir, segments, out, root) {
	const entries = fs.readdirSync(dir, { withFileTypes: true });
	const init = entries.find((e) => e.isFile() && /^init\.(server|client)?\.?luau$/.test(e.name));
	if (init) {
		const info = classify(init.name);
		out.push({
			path: segments,
			className: info.className,
			source: fs.readFileSync(path.join(dir, init.name), "utf8"),
			root,
		});
	} else {
		out.push({ path: segments, className: "Folder", root });
	}
	for (const entry of entries) {
		if (init && entry.name === init.name) continue;
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			walk(full, segments.concat(entry.name), out, false);
		} else {
			const info = classify(entry.name);
			if (info) {
				out.push({
					path: segments.concat(info.name),
					className: info.className,
					source: fs.readFileSync(full, "utf8"),
				});
			}
		}
	}
}

function collect(node, segments, out) {
	for (const [key, child] of Object.entries(node)) {
		if (key.startsWith("$") || typeof child !== "object") continue;
		const childSegments = segments.concat(key);
		if (child.$path) {
			const full = path.join(ROOT, child.$path);
			if (fs.statSync(full).isFile()) {
				// A single file mapped to a named instance (e.g. ReplicatedFirst.LoadingScreen).
				const info = classify(path.basename(full));
				out.push({
					path: childSegments,
					className: info.className,
					source: fs.readFileSync(full, "utf8"),
					root: false,
				});
			} else {
				walk(full, childSegments, out, true);
			}
		} else {
			collect(child, childSegments, out);
		}
	}
}

function manifest() {
	const project = JSON.parse(fs.readFileSync(path.join(ROOT, "default.project.json"), "utf8"));
	const out = [];
	collect(project.tree, [], out);
	return out;
}

// Studio's local Plugins folder (Windows, then macOS).
function pluginsFolder() {
	if (process.env.LOCALAPPDATA) return path.join(process.env.LOCALAPPDATA, "Roblox", "Plugins");
	return path.join(os.homedir(), "Documents", "Roblox", "Plugins");
}

// Copies the sync plugin into Studio's Plugins folder when it is missing or
// out of date (only when asked: --install-plugin).
function installPlugin() {
	const source = fs.readFileSync(path.join(__dirname, "studio-sync-plugin.lua"), "utf8");
	const folder = pluginsFolder();
	const target = path.join(folder, "SpellcraftSync.lua");
	try {
		if (fs.existsSync(target) && fs.readFileSync(target, "utf8") === source) return;
		fs.mkdirSync(folder, { recursive: true });
		fs.writeFileSync(target, source);
		console.log(`studio-sync installed the Spellcraft Sync plugin at ${target}`);
	} catch (err) {
		console.log(`studio-sync could not install the plugin (${err.message}); use tools/studio-sync.luau`);
	}
}

if (process.argv.includes("--install-plugin")) installPlugin();

http
	.createServer((req, res) => {
		if (req.url === "/version") {
			try {
				const hash = crypto.createHash("sha1").update(JSON.stringify(manifest())).digest("hex");
				res.writeHead(200, { "Content-Type": "text/plain" });
				res.end(hash);
			} catch (err) {
				res.writeHead(500);
				res.end(String(err));
			}
		} else if (req.url === "/manifest") {
			try {
				const body = JSON.stringify(manifest());
				res.writeHead(200, { "Content-Type": "application/json" });
				res.end(body);
			} catch (err) {
				res.writeHead(500);
				res.end(String(err));
			}
		} else {
			res.writeHead(404);
			res.end();
		}
	})
	.listen(PORT, "127.0.0.1", () => {
		console.log(`studio-sync serving ${ROOT} on http://localhost:${PORT}/manifest`);
	});
