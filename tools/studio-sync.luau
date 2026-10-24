--!strict
-- Paste into the Studio command bar (or run via the Studio MCP) while
-- `node tools/studio-sync.js` is running. Creates/updates every script from
-- the repo and removes scripts under the synced roots that no longer exist.

local HttpService = game:GetService("HttpService")

type Entry = { path: { string }, className: string, source: string?, root: boolean? }

local entries: { Entry } = HttpService:JSONDecode(HttpService:GetAsync("http://localhost:34873/manifest"))

local synced: { [Instance]: boolean } = {}
local roots: { [Instance]: boolean } = {}

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

for _, entry in entries do
	local node: Instance = game:GetService(entry.path[1])
	for i = 2, #entry.path do
		local isLast = i == #entry.path
		node = ensure(node, entry.path[i], if isLast then entry.className else "Folder", isLast)
	end
	if entry.root then
		roots[node] = true
	end
	if entry.source and node:IsA("LuaSourceContainer") then
		(node :: any).Source = entry.source
	end
	synced[node] = true
end

-- Remove scripts/folders under synced roots that the repo no longer has.
local removed = 0
for root in roots do
	for _, descendant in root:GetDescendants() do
		if (descendant:IsA("LuaSourceContainer") or descendant:IsA("Folder")) and not synced[descendant] then
			descendant:Destroy()
			removed += 1
		end
	end
end

print(`[studio-sync] synced {#entries} entries, removed {removed}`)
