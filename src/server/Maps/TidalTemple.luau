--!strict
-- Tidal Temple: a sandy temple floor ringed by shallow sea. Coral pillars and
-- giant clam blocks are the cover, with a sunken pearl glowing over the
-- centre. Walled in. Built by FlatArena (flat board, mirrored cover, spawn
-- pads, edge lights); the sea and the pearl don't collide.

local FlatArena = require(script.Parent.FlatArena)
local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local SEA = Color3.fromRGB(64, 180, 220)

local THEME: FlatArena.Theme = {
	name = "TidalTemple",
	seed = 909,
	shape = "round",
	radius = 60,
	floor = Color3.fromRGB(240, 222, 170),
	floorMaterial = Enum.Material.Sand,
	accent = Color3.fromRGB(72, 210, 200),
	curb = Color3.fromRGB(214, 200, 160),
	curbMaterial = Enum.Material.Sandstone,
	underside = Color3.fromRGB(150, 130, 96),
	undersideMaterial = Enum.Material.Sandstone,
	cover = Color3.fromRGB(230, 214, 176),
	coverMaterial = Enum.Material.Sandstone,
	pillar = Color3.fromRGB(255, 128, 150),
	pillarMaterial = Enum.Material.Pebble,
	walled = true,
	spawnDistance = 44,
	layout = {
		{ kind = "pillar", x = -18, z = -18 },
		{ kind = "pillar", x = 18, z = -18 },
		{ kind = "block", x = -34, z = -30 },
		{ kind = "block", x = 34, z = -30 },
		{ kind = "low", x = 0, z = -30, length = 4 },
		{ kind = "wall", x = -40, z = -4, angle = 90, length = 3 },
		{ kind = "wall", x = 40, z = -4, angle = 90, length = 3 },
	},
	decor = function(model: Model, _rng: Random, _makeProp: Registrar)
		-- Shallow sea beyond the curb.
		local sea =
			MapKit.disc(model, Vector3.new(0, -0.6, 0), 96, 1, SEA, Enum.Material.Glass, "Sea")
		sea.Transparency = 0.35
		sea.CanCollide = false
		sea.CanQuery = false
		-- The pearl over the centre mark.
		local pearl = MapKit.part(model, {
			name = "Pearl",
			shape = Enum.PartType.Ball,
			size = Vector3.new(4, 4, 4),
			cframe = CFrame.new(0, 15, 0),
			color = Color3.fromRGB(250, 246, 255),
			material = Enum.Material.Neon,
			canCollide = false,
		})
		pearl.CanQuery = false
		pearl:AddTag("SpinFx")
	end,
}

return function(makeProp: Registrar): Model
	return FlatArena.build(THEME, makeProp)
end
