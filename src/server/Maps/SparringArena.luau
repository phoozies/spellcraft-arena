--!strict
-- Sparring Arena — a colosseum map built from the imported "Arena" model
-- (marble pillars, sandstone seating, a slate floor with a neon rune ring).
-- A roomy fighting floor (the model's 46-stud floor scaled up by SCALE, about
-- 184 studs): built for duels; bigger teams just get more room. If the model isn't
-- in the place, a plain round platform with pillars stands in.
--
-- The fighting floor is ~184 studs wide; the seating and the gaps in it have no
-- ground beyond the floor's edge, so walking off the floor means falling into
-- the void. A ring of invisible walls just outside the floor edge keeps
-- everyone on the floor (the pillars stand inside it, as cover). The walls
-- ignore spells (CanQuery off), so bolts still fly over the seating.
--
-- Follows the arena contract documented in MapKit (Bounds, Spawns,
-- SmallModeWalls); the floor top is at y = 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local MapKit = require(script.Parent.MapKit)

-- How much bigger than the imported model's design size the arena is built.
local SCALE = 4
local FLOOR_DIAMETER = 46 * SCALE
local WALL_RADIUS = 24.2 * SCALE -- inner face just past the floor's edge (radius 23 * SCALE)
local WALL_SEGMENTS = 24
local WALL_HEIGHT = 40

-- Scales everything in `model` about the arena's origin (the floor's center,
-- top at y = 0), so the floor top stays at y = 0.
local function scaleAboutOrigin(model: Instance, factor: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local cframe = descendant.CFrame
			descendant.Size *= factor
			descendant.CFrame = cframe.Rotation + cframe.Position * factor
		elseif descendant:IsA("Attachment") then
			descendant.Position *= factor
		end
	end
end

local function buildFallbackArt(model: Model)
	MapKit.part(model, {
		name = "Floor",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1.2, FLOOR_DIAMETER, FLOOR_DIAMETER),
		cframe = CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = Color3.fromRGB(88, 84, 100),
		material = Enum.Material.Slate,
	})
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		MapKit.part(model, {
			name = "Pillar",
			size = Vector3.new(2, 12, 2),
			cframe = CFrame.new(math.cos(a) * 22.5 * SCALE, 6, math.sin(a) * 22.5 * SCALE),
			color = Color3.fromRGB(240, 232, 220),
			material = Enum.Material.Marble,
		})
	end
end

return function(_makeProp: (Instance, number) -> ()): Model
	local model = Instance.new("Model")
	model.Name = "SparringArena"

	local art = ModelKit.clone("Arena", "solid")
	if art then
		for _, child in art:GetChildren() do
			child.Parent = model
		end
		art:Destroy()
		scaleAboutOrigin(model, SCALE)
	else
		buildFallbackArt(model)
	end

	-- Invisible wall ring.
	local barriers = MapKit.folder(model, "Barriers")
	local segmentWidth = 2 * math.pi * WALL_RADIUS / WALL_SEGMENTS + 1
	for i = 1, WALL_SEGMENTS do
		local a = (i / WALL_SEGMENTS) * math.pi * 2
		local position =
			Vector3.new(math.cos(a) * WALL_RADIUS, WALL_HEIGHT / 2, math.sin(a) * WALL_RADIUS)
		local wall = MapKit.part(barriers, {
			name = "Barrier",
			size = Vector3.new(segmentWidth, WALL_HEIGHT, 2),
			cframe = CFrame.lookAt(position, Vector3.new(0, position.Y, 0)),
			transparency = 1,
		})
		wall.CanQuery = false
	end

	local spawns = MapKit.folder(model, "Spawns")
	MapKit.teamSpawns(spawns, Vector3.zero, 16 * SCALE, 0.5)

	-- Already compact, so there's nothing to close off for the small modes.
	MapKit.folder(model, "SmallModeWalls")

	MapKit.bounds(model, Vector3.new(FLOOR_DIAMETER, 40, FLOOR_DIAMETER), Vector3.new(0, 15, 0))
	return model
end
