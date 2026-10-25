--!strict
-- Ember Forge — a basalt floor ringed by a moat of glowing lava, with a
-- stepped anvil in the middle and obsidian pillars and brick walls as cover.
-- A wall at the rim keeps everyone on the floor; the lava is scenery. The
-- basalt floor, the dais and the pillars are breakable (a hole in the floor
-- shows the lava glowing below).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local RADIUS = 62
local BASALT = Color3.fromRGB(64, 58, 66)
local OBSIDIAN = Color3.fromRGB(34, 30, 44)
local LAVA = Color3.fromRGB(255, 112, 40)

return function(makeProp: Registrar): Model
	local model = Instance.new("Model")
	model.Name = "EmberForge"

	-- The lava moat: a glowing disc just below the floor, reaching past its edge.
	local lava =
		MapKit.disc(model, Vector3.new(0, -3, 0), RADIUS + 28, 1, LAVA, Enum.Material.Neon, "Lava")
	lava.CanCollide = false
	lava.Transparency = 0.1
	local light = Instance.new("PointLight")
	light.Color = LAVA
	light.Range = 60
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = lava

	MapKit.terrainDisc(
		model,
		Vector3.zero,
		RADIUS,
		6,
		BASALT,
		Enum.Material.Basalt,
		"Floor",
		MapKit.groundTerrain(makeProp)
	)
	MapKit.underside(model, -5.5, RADIUS, 55, Color3.fromRGB(48, 42, 50), Enum.Material.Slate)

	-- A two-step anvil dais in the middle, with a glowing core.
	local slate = Enum.Material.Slate
	MapKit.terrainDisc(
		model,
		Vector3.new(0, 1.5, 0),
		15,
		1.5,
		Color3.fromRGB(88, 80, 90),
		slate,
		"DaisLow",
		MapKit.rockTerrain(makeProp)
	)
	MapKit.terrainDisc(
		model,
		Vector3.new(0, 3, 0),
		9,
		1.5,
		Color3.fromRGB(110, 100, 110),
		slate,
		"DaisHigh",
		MapKit.rockTerrain(makeProp)
	)
	local core = MapKit.part(model, {
		name = "ForgeCore",
		shape = Enum.PartType.Ball,
		size = Vector3.new(4, 4, 4),
		cframe = CFrame.new(0, 6, 0),
		color = LAVA,
		material = Enum.Material.Neon,
		canCollide = false,
	})
	core:AddTag("SpinFx")

	-- Obsidian pillars (breakable) around the dais.
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		local pillar = MapKit.pillar(
			model,
			Vector3.new(math.cos(a) * 32, 0, math.sin(a) * 32),
			15,
			5,
			OBSIDIAN,
			Enum.Material.Basalt
		)
		makeProp(pillar, Config.PROPS.Heavy)
	end

	-- Brick walls across each side lane.
	for _, x in { -40, 40 } do
		MapKit.blockWall(
			model,
			CFrame.new(x, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
			5,
			3,
			Vector3.new(3, 2.5, 2),
			Color3.fromRGB(150, 70, 56),
			Enum.Material.Brick,
			30,
			makeProp
		)
	end

	MapKit.barrierRing(model, RADIUS, 50)

	local spawns = MapKit.folder(model, "Spawns")
	MapKit.teamSpawns(spawns, Vector3.zero, 50, 0.5)
	MapKit.folder(model, "SmallModeWalls")
	MapKit.bounds(model, Vector3.new(140, 60, 140), Vector3.new(0, 25, 0))
	return model
end
