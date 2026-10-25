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
local MapKit = require(MapsFolder:WaitForChild("MapKit")) :: any

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

ArenaService.MAP_NAMES = {
	"CrayonCanyon",
	"SparringArena",
	"FrostHollow",
	"EmberForge",
	"MossRuins",
	"TidalTemple",
	"SkyBridge",
}
ArenaService.DISPLAY_NAMES = {
	CrayonCanyon = "Crayon Canyon",
	SparringArena = "Sparring Arena",
	FrostHollow = "Frost Hollow",
	EmberForge = "Ember Forge",
	MossRuins = "Moss Ruins",
	TidalTemple = "Tidal Temple",
	SkyBridge = "Sky Bridge",
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

-- Where arena `slot` (1, 2, ...) is summoned: below the hub island, in rings
-- around its axis (Config.ARENA), so hub players can look over the rim and
-- watch the fights. The first ring is full before the next one outward is used.
function ArenaService.slotOrigin(slot: number): CFrame
	local ring = (slot - 1) // Config.ARENA.PER_RING
	local index = (slot - 1) % Config.ARENA.PER_RING
	local radius = Config.ARENA.RADIUS + ring * Config.ARENA.RING_STEP
	-- Stagger each ring by half a step so arenas don't stack behind each other.
	local angle = (index + (ring % 2) * 0.5) / Config.ARENA.PER_RING * math.pi * 2
	return CFrame.new(math.sin(angle) * radius, Config.ARENA.Y, -math.cos(angle) * radius)
end

-- A floating sign over an arena so hub spectators can tell the fights apart.
local function addSpectatorSign(model: Model, mapName: string, mode: string)
	local bounds = model:FindFirstChild("Bounds")
	local height = 60
	if bounds and bounds:IsA("BasePart") then
		height = bounds.Position.Y - model:GetPivot().Position.Y + bounds.Size.Y / 2 + 12
	end
	local anchor = Instance.new("Part")
	anchor.Name = "SpectatorSign"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = model:GetPivot() + Vector3.new(0, height, 0)
	anchor.Parent = model
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 60)
	gui.MaxDistance = 1500
	gui.AlwaysOnTop = true
	gui.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = `⚔ {mode} · {ArenaService.DISPLAY_NAMES[mapName] or mapName}`
	text.Parent = gui
end

-- Picks a map suited to the mode.
function ArenaService.pickMap(mode: string): string
	local weights: { [string]: number } = {
		CrayonCanyon = 1,
		-- The roomy round floor: favored for small duels, skipped for 4v4.
		SparringArena = if mode == "1v1" or mode == "2v2" then 2 elseif mode == "4v4" then 0 else 1,
		FrostHollow = 1,
		EmberForge = 1,
		MossRuins = 1,
		TidalTemple = 1,
		-- Two 30-stud platforms: great for duels, tight for 4v4.
		SkyBridge = if mode == "4v4" then 0.5 else 1,
	}
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = math.random() * total
	for _, name in ArenaService.MAP_NAMES do
		roll -= weights[name] or 1
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

	local origin = ArenaService.slotOrigin(slot)
	local model = template:Clone()
	model:PivotTo(origin)
	-- Hub players watch from far away, so the arena must always be streamed in.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

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

	local spawns: { [string]: { BasePart } } = { Team1 = {}, Team2 = {} }
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
	addSpectatorSign(model, mapName, mode)
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
		MapKit.scale(model, Config.ARENA_SCALE)
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
