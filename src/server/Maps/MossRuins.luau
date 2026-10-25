--!strict
-- Moss Ruins — an overgrown courtyard: broken marble arches, toppled columns,
-- mossy blocks and trees ringing a stone dais. Lots of cover (some of it
-- breakable). A wall at the rim keeps everyone on the grass. The grass floor
-- is breakable terrain.

local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local RADIUS = 66
local GRASS = Color3.fromRGB(96, 160, 84)
local MARBLE = Color3.fromRGB(226, 228, 222)
local MOSS = Color3.fromRGB(104, 138, 88)

return function(makeProp: Registrar): Model
	local model = Instance.new("Model")
	model.Name = "MossRuins"
	local rng = MapKit.rng(77)

	MapKit.terrainDisc(
		model,
		Vector3.zero,
		RADIUS,
		6,
		GRASS,
		Enum.Material.Grass,
		"Floor",
		MapKit.groundTerrain(makeProp)
	)
	MapKit.underside(model, -5.5, RADIUS, 55, Color3.fromRGB(110, 90, 72), Enum.Material.Rock)
	MapKit.disc(model, Vector3.new(0, 0.9, 0), 14, 1, MARBLE, Enum.Material.Marble, "Dais")
	-- Painted flagstones: not solid, so they never float over a hole.
	local flagstones = MapKit.disc(
		model,
		Vector3.new(0, 0.12, 0),
		24,
		0.3,
		Color3.fromRGB(176, 168, 150),
		Enum.Material.Cobblestone,
		"Flagstones"
	)
	flagstones.CanCollide = false
	flagstones.CanQuery = false

	-- Four broken arches (two posts and a half-lintel) facing the dais.
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2
		local frame = CFrame.new(math.cos(a) * 36, 0, math.sin(a) * 36)
			* CFrame.Angles(0, -a + math.pi / 2, 0)
		for _, side in { -1, 1 } do
			local height = if side < 0 then 16 else 10
			MapKit.part(model, {
				name = "ArchPost",
				size = Vector3.new(3.5, height, 3.5),
				cframe = frame * CFrame.new(side * 7, height / 2, 0),
				color = MARBLE,
				material = Enum.Material.Marble,
			})
		end
		MapKit.part(model, {
			name = "ArchLintel",
			size = Vector3.new(10, 3, 3.5),
			cframe = frame * CFrame.new(-3, 17.5, 0),
			color = MARBLE,
			material = Enum.Material.Marble,
		})
	end

	-- Toppled columns (breakable cover).
	for i = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(18, 50)
		local column = MapKit.part(model, {
			name = "FallenColumn",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(14, 3.2, 3.2),
			cframe = CFrame.new(math.cos(a) * r, 1.6, math.sin(a) * r)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			color = MARBLE,
			material = Enum.Material.Marble,
		})
		makeProp(column, 220 + i)
	end

	-- Mossy blocks (breakable).
	for _ = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(10, 54)
		local size = rng:NextNumber(3.5, 6)
		local block = MapKit.part(model, {
			name = "MossBlock",
			size = Vector3.new(size, size, size),
			cframe = CFrame.new(math.cos(a) * r, size / 2, math.sin(a) * r)
				* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			color = MOSS,
			material = Enum.Material.Slate,
		})
		makeProp(block, 150)
	end

	-- Trees along the rim.
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local at = Vector3.new(math.cos(a) * (RADIUS - 5), 0, math.sin(a) * (RADIUS - 5))
		MapKit.tree(model, at, 1.2, rng)
	end

	MapKit.barrierRing(model, RADIUS, 50)

	local spawns = MapKit.folder(model, "Spawns")
	MapKit.teamSpawns(spawns, Vector3.zero, 50, 0.5)
	MapKit.folder(model, "SmallModeWalls")
	MapKit.bounds(model, Vector3.new(140, 60, 140), Vector3.new(0, 25, 0))
	return model
end
