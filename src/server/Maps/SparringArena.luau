--!strict
-- Sparring Arena — a colosseum map built from the imported "Arena" model
-- (marble pillars, sandstone seating, a slate floor with a neon rune ring).
-- A compact 46-stud fighting floor: great for 1v1 and 2v2, still fine for 3v3
-- and FFA. If the model isn't in the place, a plain round platform with
-- pillars stands in.
--
-- The fighting floor is 46 studs wide; the seating and the gaps in it have no
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

local FLOOR_DIAMETER = 46
local WALL_RADIUS = 24.2 -- inner face at ~23.2, just past the floor's edge (radius 23)
local WALL_SEGMENTS = 24
local WALL_HEIGHT = 40

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
			cframe = CFrame.new(math.cos(a) * 22.5, 6, math.sin(a) * 22.5),
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
	MapKit.teamSpawns(spawns, Vector3.zero, 16, 0.5)
	MapKit.ffaSpawns(spawns, Vector3.new(0, 0.5, 0), 14, 8)

	-- Already compact, so there's nothing to close off for the small modes.
	MapKit.folder(model, "SmallModeWalls")

	MapKit.bounds(model, Vector3.new(FLOOR_DIAMETER, 40, FLOOR_DIAMETER), Vector3.new(0, 15, 0))
	return model
end
