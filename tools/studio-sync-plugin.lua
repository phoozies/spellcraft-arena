--!strict
-- Spellcraft Sync: a local Studio plugin that keeps the open place in step
-- with the repo while `node tools/studio-sync.js` runs (that script installs
-- this file into Studio's Plugins folder). In Edit mode it polls the server's
-- /version once a second and, when the repo changed, pulls /manifest and
-- creates or updates every script (scripts open in the editor are updated in
-- place) and removes scripts and folders under the synced roots that the repo
-- no longer has, the same as tools/studio-sync.luau.
--
-- The "Sync" button on the Spellcraft toolbar turns it on and off (remembered).
-- Studio asks once whether this plugin may reach localhost: allow it.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ScriptEditorService = game:GetService("ScriptEditorService")

if not RunService:IsEdit() then
	return
end

local URL = "http://localhost:34873"
local POLL_SECONDS = 1
local SETTING = "SpellcraftSyncOn"

type Entry = { path: { string }, className: string, source: string?, root: boolean? }

local enabled = plugin:GetSetting(SETTING) ~= false
local lastVersion: string? = nil
local reachable = true

local toolbar = plugin:CreateToolbar("Spellcraft")
local button = toolbar:CreateButton(
	"SpellcraftSync",
	"Live-sync the repo into this place (node tools/studio-sync.js)",
	"rbxasset://textures/StudioToolbox/AssetPreview/rotate.png",
	"Sync"
)
button.ClickableWhenViewportHidden = true
button:SetActive(enabled)

local function ensure(parent: Instance, name: string, className: string, isLeaf: boolean): Instance
	local existing = parent:FindFirstChild(name)
	-- Intermediate containers (StarterPlayerScripts, etc.) are reused as-is.
	if existing and className ~= "Folder" and existing.ClassName ~= className and isLeaf then
		-- Class changed (e.g. Folder -> Script): keep children, swap the node.
		local replacement = Instance.new(className)
		replacement.Name = name
		for _, child in existing:GetChildren() do
			child.Parent = replacement
		end
		existing:Destroy()
		replacement.Parent = parent
		return replacement
	end
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

-- Sets a script's source, through the editor when it is open there.
local function setSource(script: LuaSourceContainer, source: string)
	local current = (script :: any).Source :: string
	if current:gsub("\r\n", "\n") == source:gsub("\r\n", "\n") then
		return false
	end
	if ScriptEditorService:FindScriptDocument(script) then
		local ok = pcall(function()
			ScriptEditorService:UpdateSourceAsync(script, function()
				return source
			end)
		end)
		if ok then
			return true
		end
	end
	(script :: any).Source = source
	return true
end

local function apply(entries: { Entry }): (number, number)
	local synced: { [Instance]: boolean } = {}
	local roots: { [Instance]: boolean } = {}
	local changed = 0
	for _, entry in entries do
		local node: Instance = game:GetService(entry.path[1])
		for i = 2, #entry.path do
			local isLast = i == #entry.path
			node = ensure(node, entry.path[i], if isLast then entry.className else "Folder", isLast)
		end
		if entry.root then
			roots[node] = true
		end
		if entry.source and node:IsA("LuaSourceContainer") and setSource(node, entry.source) then
			changed += 1
		end
		synced[node] = true
	end
	-- Remove scripts/folders under synced roots that the repo no longer has.
	local removed = 0
	for root in roots do
		for _, descendant in root:GetDescendants() do
			if
				(descendant:IsA("LuaSourceContainer") or descendant:IsA("Folder"))
				and not synced[descendant]
				and descendant.Parent
			then
				descendant:Destroy()
				removed += 1
			end
		end
	end
	return changed, removed
end

local function poll()
	local ok, version = pcall(HttpService.GetAsync, HttpService, URL .. "/version", true)
	if not ok then
		if reachable then
			reachable = false
			print("[Spellcraft Sync] waiting for node tools/studio-sync.js")
		end
		lastVersion = nil
		return
	end
	reachable = true
	if version == lastVersion then
		return
	end
	local fetched, body = pcall(HttpService.GetAsync, HttpService, URL .. "/manifest", true)
	if not fetched then
		warn("[Spellcraft Sync] could not read the manifest: " .. tostring(body))
		return
	end
	local recording = ChangeHistoryService:TryBeginRecording("Spellcraft Sync")
	local applied, changed, removed = pcall(apply, HttpService:JSONDecode(body))
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if applied then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if applied then
		lastVersion = version
		print(`[Spellcraft Sync] synced {version:sub(1, 8)}: {changed} changed, {removed} removed`)
	else
		warn("[Spellcraft Sync] sync failed: " .. tostring(changed))
	end
end

button.Click:Connect(function()
	enabled = not enabled
	plugin:SetSetting(SETTING, enabled)
	button:SetActive(enabled)
	lastVersion = nil
	print(`[Spellcraft Sync] {if enabled then "on" else "off"}`)
end)

local alive = true
plugin.Unloading:Connect(function()
	alive = false
end)

task.spawn(function()
	while alive do
		if enabled then
			poll()
		end
		task.wait(POLL_SECONDS)
	end
end)
