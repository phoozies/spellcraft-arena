--!strict
-- Tidal Temple — a sandy island around a three-step temple, ringed by shallow
-- sea. Coral pillars and giant clams are breakable cover, and torches light the
-- shore. A wall at the rim keeps everyone on the sand.

local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local RADIUS = 58
local SAND = Color3.fromRGB(238, 214, 160)
local STONE = Color3.fromRGB(196, 190, 176)
local CORAL = Color3.fromRGB(255, 120, 130)

return function(makeProp: Registrar): Model
	local model = Instance.new("Model")
	model.Name = "TidalTemple"
	local rng = MapKit.rng(909)

	MapKit.disc(model, Vector3.zero, RADIUS, 6, SAND, Enum.Material.Sand, "Floor")
	MapKit.underside(model, -5.5, RADIUS, 55, Color3.fromRGB(150, 128, 98), Enum.Material.Sandstone)

	-- The shallow sea around the island (scenery).
	local sea = MapKit.disc(
		model,
		Vector3.new(0, -1.5, 0),
		RADIUS + 36,
		1,
		Color3.fromRGB(64, 170, 220),
		Enum.Material.Glass,
		"Sea"
	)
	sea.CanCollide = false
	sea.Transparency = 0.35

	-- Three temple steps with a glowing pearl on top.
	local limestone = Enum.Material.Limestone
	MapKit.disc(model, Vector3.new(0, 1.5, 0), 20, 1.5, STONE, limestone, "StepLow")
	MapKit.disc(model, Vector3.new(0, 3, 0), 14, 1.5, STONE, limestone, "StepMid")
	MapKit.disc(
		model,
		Vector3.new(0, 4.5, 0),
		8,
		1.5,
		Color3.fromRGB(232, 226, 210),
		Enum.Material.Marble,
		"StepHigh"
	)
	local pearl = MapKit.part(model, {
		name = "Pearl",
		shape = Enum.PartType.Ball,
		size = Vector3.new(3.5, 3.5, 3.5),
		cframe = CFrame.new(0, 7, 0),
		color = Color3.fromRGB(190, 240, 255),
		material = Enum.Material.Neon,
		canCollide = false,
	})
	pearl:AddTag("SpinFx")

	-- Coral pillars (breakable).
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		local base = Vector3.new(math.cos(a) * 38, 0, math.sin(a) * 38)
		makeProp(MapKit.pillar(model, base, 12, 4, CORAL, Enum.Material.Marble), 250)
	end

	-- Giant clams (breakable).
	for _ = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(24, 50)
		local clam = MapKit.part(model, {
			name = "Clam",
			shape = Enum.PartType.Ball,
			size = Vector3.new(7, 5, 7),
			cframe = CFrame.new(math.cos(a) * r, 2, math.sin(a) * r),
			color = Color3.fromRGB(250, 230, 236),
			material = Enum.Material.SmoothPlastic,
		})
		makeProp(clam, 140)
	end

	-- Shore torches.
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local base = Vector3.new(math.cos(a) * (RADIUS - 3), 0, math.sin(a) * (RADIUS - 3))
		MapKit.part(model, {
			name = "TorchPost",
			size = Vector3.new(0.8, 6, 0.8),
			cframe = CFrame.new(base + Vector3.new(0, 3, 0)),
			color = Color3.fromRGB(110, 78, 50),
			material = Enum.Material.Wood,
		})
		local flame = MapKit.part(model, {
			name = "Flame",
			shape = Enum.PartType.Ball,
			size = Vector3.new(1.8, 2.4, 1.8),
			cframe = CFrame.new(base + Vector3.new(0, 7, 0)),
			color = Color3.fromRGB(255, 150, 40),
			material = Enum.Material.Neon,
			canCollide = false,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 160, 70)
		light.Range = 22
		light.Shadows = false
		light.Parent = flame
	end

	MapKit.barrierRing(model, RADIUS, 50)

	local spawns = MapKit.folder(model, "Spawns")
	MapKit.teamSpawns(spawns, Vector3.zero, 46, 0.5)
	MapKit.folder(model, "SmallModeWalls")
	MapKit.bounds(model, Vector3.new(130, 60, 130), Vector3.new(0, 25, 0))
	return model
end
