--!strict
-- Frost Hollow — a round sheet of ice with frozen spires and breakable ice
-- cubes for cover. There is no wall at the rim, so knockback ring-outs decide
-- close fights. Compact: good for duels, fine for 4v4. The ice sheet is
-- breakable terrain; cracks drop you onto the rock below.

local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local RADIUS = 70
local ICE = Color3.fromRGB(165, 222, 247)
local ICE_DEEP = Color3.fromRGB(110, 178, 226)
local SNOW = Color3.fromRGB(240, 246, 250)

return function(makeProp: Registrar): Model
	local model = Instance.new("Model")
	model.Name = "FrostHollow"
	local rng = MapKit.rng(2024)

	MapKit.terrainDisc(
		model,
		Vector3.zero,
		RADIUS,
		6,
		ICE,
		Enum.Material.Ice,
		"Floor",
		MapKit.groundTerrain(makeProp)
	)
	-- A painted pond on the ice: not solid, so it never floats over a hole.
	local pond = MapKit.disc(
		model,
		Vector3.new(0, 0.05, 0),
		18,
		0.3,
		ICE_DEEP,
		Enum.Material.Glacier,
		"FrozenPond"
	)
	pond.CanCollide = false
	pond.CanQuery = false
	MapKit.disc(model, Vector3.new(0, -0.5, 0), RADIUS + 5, 5, SNOW, Enum.Material.Snow, "SnowRim")
	MapKit.underside(
		model,
		-5.5,
		RADIUS + 5,
		60,
		Color3.fromRGB(122, 160, 190),
		Enum.Material.Glacier
	)

	-- Frozen spires around the pond.
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + math.pi / 6
		local spire = MapKit.part(model, {
			name = "IceSpire",
			size = Vector3.new(5, 16, 5),
			cframe = CFrame.new(math.cos(a) * 34, 8, math.sin(a) * 34) * CFrame.Angles(0, a, 0),
			color = ICE,
			material = Enum.Material.Ice,
			transparency = 0.15,
		})
		makeProp(spire, 260)
	end

	-- Scattered ice cubes (breakable cover), kept off the spawn lines.
	for _ = 1, 14 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(12, 56)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if math.abs(z) < 44 then
			local size = rng:NextNumber(4, 7)
			local cube = MapKit.part(model, {
				name = "IceCube",
				size = Vector3.new(size, size, size),
				cframe = CFrame.new(x, size / 2, z) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
				color = ICE,
				material = Enum.Material.Ice,
				transparency = 0.1,
			})
			makeProp(cube, 140)
		end
	end

	-- Snow drifts on the rim (decoration).
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2
		MapKit.part(model, {
			name = "Drift",
			shape = Enum.PartType.Ball,
			size = Vector3.new(9, 4, 9),
			cframe = CFrame.new(math.cos(a) * (RADIUS + 1), 0, math.sin(a) * (RADIUS + 1)),
			color = SNOW,
			material = Enum.Material.Snow,
			canCollide = false,
		})
	end

	local spawns = MapKit.folder(model, "Spawns")
	MapKit.teamSpawns(spawns, Vector3.zero, 52, 0.5)
	MapKit.folder(model, "SmallModeWalls")
	MapKit.bounds(model, Vector3.new(160, 80, 160), Vector3.new(0, 30, 0))
	return model
end
