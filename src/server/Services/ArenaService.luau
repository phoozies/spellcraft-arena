--!strict
-- Builds map templates once at startup (from src/server/Maps) and hands out
-- instanced copies at far-apart offsets so several matches can run at once
-- in one server. Also wires jump pads (tag "JumpPad") everywhere.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local DestructibleService = require(script.Parent.DestructibleService)

local MapsFolder = script.Parent.Parent:WaitForChild("Maps")

export type Arena = {
	id: number,
	mapName: string,
	mode: string,
	model: Model,
	origin: CFrame,
	bounds: BasePart,
	structures: Folder,
	spawns: { [string]: { BasePart } },
}

local ArenaService = {}

ArenaService.MAP_NAMES = { "CrayonCanyon", "FrostbiteFortress", "SkyIslands", "SparringArena" }
ArenaService.DISPLAY_NAMES = {
	CrayonCanyon = "Crayon Canyon",
	FrostbiteFortress = "Frostbite Fortress",
	SkyIslands = "Sky Islands",
	SparringArena = "Sparring Arena",
}

local templates: Folder
local slots: { [number]: boolean } = {}
local nextId = 0

local function makeProp(instance: Instance, health: number)
	-- Map props are recreated per arena, so tag on the template copy.
	instance:SetAttribute("PropHealth", health)
end

local function wireJumpPad(pad: Instance)
	if not pad:IsA("BasePart") then
		return
	end
	local debounce: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		if
			not character
			or not character:IsA("Model")
			or not Players:GetPlayerFromCharacter(character)
		then
			return
		end
		local now = os.clock()
		if (debounce[character] or 0) > now then
			return
		end
		debounce[character] = now + 1
		local velocity = pad:GetAttribute("LaunchVelocity")
		if typeof(velocity) == "Vector3" then
			DestructibleService.boost(character, velocity)
		end
	end)
end

-- Picks a map suited to the mode (Fortress favors teams, Sky Islands FFA).
function ArenaService.pickMap(mode: string): string
	local weights: { [string]: number } = {
		CrayonCanyon = 1,
		FrostbiteFortress = if mode == "4v4" then 2 else 1,
		SkyIslands = if mode == "FFA" then 2 else 1,
		-- A compact 46-stud floor: favored for small duels, skipped for 4v4.
		SparringArena = if mode == "1v1" or mode == "2v2" then 2 elseif mode == "4v4" then 0 else 1,
	}
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = math.random() * total
	for _, name in ArenaService.MAP_NAMES do
		roll -= weights[name]
		if roll <= 0 then
			return name
		end
	end
	return "CrayonCanyon"
end

function ArenaService.create(mapName: string, mode: string): Arena
	local template = templates:FindFirstChild(mapName) :: Model
	assert(template, `unknown map {mapName}`)
	local slot = 1
	while slots[slot] do
		slot += 1
	end
	slots[slot] = true
	nextId += 1

	local origin = CFrame.new(slot * Config.ARENA_SPACING, 400, 0)
	local model = template:Clone()
	model:PivotTo(origin)

	for _, descendant in model:GetDescendants() do
		local health = descendant:GetAttribute("PropHealth")
		if typeof(health) == "number" then
			DestructibleService.makeProp(descendant, health)
		end
	end
	local smallWalls = model:FindFirstChild("SmallModeWalls")
	if smallWalls and mode ~= "1v1" and mode ~= "2v2" then
		smallWalls:Destroy()
	end

	local structures = Instance.new("Folder")
	structures.Name = "Structures"
	structures.Parent = model

	local spawns: { [string]: { BasePart } } = { Team1 = {}, Team2 = {}, FFA = {} }
	local spawnFolder = model:FindFirstChild("Spawns")
	if spawnFolder then
		for _, part in spawnFolder:GetChildren() do
			if part:IsA("BasePart") then
				local group = string.match(part.Name, "^(%w+)_")
				if group and spawns[group] then
					table.insert(spawns[group], part)
				end
			end
		end
	end
	for _, list in spawns do
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
	end

	model.Name = `Arena{nextId}_{mapName}`
	model.Parent = workspace
	for _, pad in model:GetDescendants() do
		if CollectionService:HasTag(pad, "JumpPad") then
			wireJumpPad(pad)
		end
	end

	local arena: Arena = {
		id = slot,
		mapName = mapName,
		mode = mode,
		model = model,
		origin = origin,
		bounds = model:FindFirstChild("Bounds") :: BasePart,
		structures = structures,
		spawns = spawns,
	}
	return arena
end

function ArenaService.destroy(arena: Arena)
	slots[arena.id] = nil
	arena.model:Destroy()
end

-- Fresh copy of the same map (restores broken props, clears placed objects)
-- for the next round.
function ArenaService.rebuild(arena: Arena): Arena
	ArenaService.destroy(arena)
	return ArenaService.create(arena.mapName, arena.mode)
end

function ArenaService.spawnCFrame(arena: Arena, group: string, index: number): CFrame
	local list = arena.spawns[group]
	if not list or #list == 0 then
		return arena.origin + Vector3.new(0, 5, 0)
	end
	local part = list[((index - 1) % #list) + 1]
	local center = arena.origin.Position
	local position = part.Position + Vector3.new(0, 3, 0)
	-- Face the arena center.
	local look = Vector3.new(center.X, position.Y, center.Z)
	if (look - position).Magnitude < 1 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, look)
end

function ArenaService.isBelowVoid(arena: Arena, position: Vector3): boolean
	return position.Y < arena.origin.Position.Y + Config.ARENA_VOID_DEPTH
end

function ArenaService.init()
	templates = Instance.new("Folder")
	templates.Name = "MapTemplates"
	for _, name in ArenaService.MAP_NAMES do
		local builder = require(MapsFolder:WaitForChild(name)) :: any
		local model: Model = builder(makeProp)
		model.Name = name
		model.WorldPivot = CFrame.new()
		model.Parent = templates
	end
	templates.Parent = ServerStorage
end

function ArenaService.start()
	for _, pad in CollectionService:GetTagged("JumpPad") do
		wireJumpPad(pad)
	end
end

return ArenaService
