--!strict
-- Frost Hollow: a round sheet of ice with frozen spires and ice cubes for
-- cover. No wall at the rim, so knockback ring-outs decide close fights.
-- Compact: good for duels, fine for 4v4. Built by FlatArena (flat board,
-- mirrored cover, spawn pads, edge lights); the snow drifts on the curb are
-- scenery that doesn't collide.

local FlatArena = require(script.Parent.FlatArena)
local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local ICE = Color3.fromRGB(165, 222, 247)
local SNOW = Color3.fromRGB(240, 246, 250)

local THEME: FlatArena.Theme = {
	name = "FrostHollow",
	seed = 2024,
	shape = "round",
	radius = 66,
	floor = ICE,
	floorMaterial = Enum.Material.Ice,
	accent = Color3.fromRGB(110, 178, 226),
	curb = SNOW,
	curbMaterial = Enum.Material.Snow,
	underside = Color3.fromRGB(122, 160, 190),
	undersideMaterial = Enum.Material.Glacier,
	cover = Color3.fromRGB(200, 236, 252),
	coverMaterial = Enum.Material.Ice,
	pillar = Color3.fromRGB(190, 230, 250),
	pillarMaterial = Enum.Material.Glacier,
	walled = false,
	spawnDistance = 48,
	layout = {
		{ kind = "pillar", x = -30, z = -18 },
		{ kind = "pillar", x = 30, z = -18 },
		{ kind = "pillar", x = 0, z = -14 },
		{ kind = "block", x = -16, z = -32 },
		{ kind = "block", x = 16, z = -32 },
		{ kind = "low", x = -42, z = -36, angle = 35, length = 3 },
		{ kind = "low", x = 42, z = -36, angle = -35, length = 3 },
	},
	decor = function(model: Model, _rng: Random, _makeProp: Registrar)
		-- Snow drifts heaped on the curb (decoration).
		for i = 1, 20 do
			local a = (i / 20) * math.pi * 2
			local drift = MapKit.part(model, {
				name = "Drift",
				shape = Enum.PartType.Ball,
				size = Vector3.new(9, 4, 9),
				cframe = CFrame.new(math.cos(a) * 75, 1.5, math.sin(a) * 75),
				color = SNOW,
				material = Enum.Material.Snow,
				canCollide = false,
			})
			drift.CanQuery = false
		end
	end,
}

return function(makeProp: Registrar): Model
	return FlatArena.build(THEME, makeProp)
end
