--!strict
-- Sky Bridge — two round platforms joined by a long plank bridge over the
-- void, a small island in the middle, and no rim walls: knock people off. The
-- bridge planks are breakable, so the middle can be cut away, and so are the
-- platform floors. Teams start on opposite platforms (the Z ends).

local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local PLATFORM_RADIUS = 30
local PLATFORM_Z = 66
local ISLAND_RADIUS = 13
local PLANKS_PER_SIDE = 4
local STONE = Color3.fromRGB(190, 192, 200)
local PLANK = Color3.fromRGB(168, 128, 86)
local ROCK = Color3.fromRGB(120, 112, 108)

-- A round floor at (0, 0, z) with its rock hanging underneath.
local function floorAt(
	parent: Instance,
	z: number,
	radius: number,
	depth: number,
	name: string,
	color: Color3,
	material: Enum.Material,
	makeProp: Registrar
)
	MapKit.terrainDisc(
		parent,
		Vector3.new(0, 0, z),
		radius,
		6,
		color,
		material,
		name,
		MapKit.groundTerrain(makeProp)
	)
	MapKit.underside(parent, -5.5, radius, depth, ROCK, Enum.Material.Rock, Vector3.new(0, 0, z))
end

return function(makeProp: Registrar): Model
	local model = Instance.new("Model")
	model.Name = "SkyBridge"

	for _, sign in { -1, 1 } do
		local z = sign * PLATFORM_Z
		floorAt(
			model,
			z,
			PLATFORM_RADIUS,
			40,
			if sign < 0 then "PlatformA" else "PlatformB",
			STONE,
			Enum.Material.Slate,
			makeProp
		)
		-- A painted inlay: not solid, so it never floats over a hole.
		local inlay = MapKit.disc(
			model,
			Vector3.new(0, 0.1, z),
			PLATFORM_RADIUS - 6,
			0.3,
			Color3.fromRGB(150, 152, 164),
			Enum.Material.Cobblestone,
			"Inlay"
		)
		inlay.CanCollide = false
		inlay.CanQuery = false
	end

	-- A small grassy island in the middle of the bridge.
	floorAt(
		model,
		0,
		ISLAND_RADIUS,
		28,
		"MidIsland",
		Color3.fromRGB(120, 176, 104),
		Enum.Material.Grass,
		makeProp
	)

	-- Breakable planks between each platform and the middle island.
	local length = (PLATFORM_Z - PLATFORM_RADIUS - ISLAND_RADIUS) / PLANKS_PER_SIDE
	for _, sign in { -1, 1 } do
		for i = 1, PLANKS_PER_SIDE do
			local plank = MapKit.part(model, {
				name = "BridgePlank",
				size = Vector3.new(14, 1.5, length - 0.2),
				cframe = CFrame.new(0, -0.75, sign * (ISLAND_RADIUS + (i - 0.5) * length)),
				color = PLANK,
				material = Enum.Material.WoodPlanks,
			})
			makeProp(plank, 300)
		end
	end

	-- Cover on each platform and on the island.
	for _, z in { -PLATFORM_Z + 14, PLATFORM_Z - 14, 0 } do
		MapKit.blockWall(
			model,
			CFrame.new(0, 0, z),
			4,
			2,
			Vector3.new(3, 2.5, 2),
			Color3.fromRGB(214, 216, 226),
			Enum.Material.Concrete,
			25,
			makeProp
		)
	end

	local spawns = MapKit.folder(model, "Spawns")
	MapKit.teamSpawns(spawns, Vector3.zero, PLATFORM_Z, 0.5)
	MapKit.folder(model, "SmallModeWalls")
	MapKit.bounds(model, Vector3.new(90, 90, 190), Vector3.new(0, 30, 0))
	return model
end
