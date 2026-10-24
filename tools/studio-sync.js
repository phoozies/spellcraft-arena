#!/usr/bin/env node
// Fallback sync for machines without the Rojo CLI.
//
// Serves the Rojo tree described in default.project.json as JSON on
// http://localhost:34873/manifest. tools/studio-sync.luau (run in the
// Studio command bar, or via the Studio MCP) pulls it and creates or updates
// the scripts. Prefer `rojo serve` when Rojo is installed.
//
// Usage: node tools/studio-sync.js

const fs = require("fs");
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

http
	.createServer((req, res) => {
		if (req.url === "/manifest") {
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
