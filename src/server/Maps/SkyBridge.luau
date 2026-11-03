--!strict
-- Sky Bridge: one long, narrow plank board over the void, a lane map. Little
-- cover and no rails, so every knockback can ring someone out. Teams start at
-- the two ends. Built by FlatArena (flat board, mirrored cover, spawn pads,
-- edge lights).

local FlatArena = require(script.Parent.FlatArena)

type Registrar = (instance: Instance, health: number) -> ()

local THEME: FlatArena.Theme = {
	name = "SkyBridge",
	seed = 5150,
	shape = "rect",
	halfX = 24,
	halfZ = 88,
	floor = Color3.fromRGB(170, 120, 78),
	floorMaterial = Enum.Material.WoodPlanks,
	accent = Color3.fromRGB(150, 220, 255),
	curb = Color3.fromRGB(120, 84, 56),
	curbMaterial = Enum.Material.Wood,
	underside = Color3.fromRGB(96, 104, 120),
	undersideMaterial = Enum.Material.Rock,
	cover = Color3.fromRGB(150, 110, 74),
	coverMaterial = Enum.Material.WoodPlanks,
	pillar = Color3.fromRGB(196, 206, 220),
	pillarMaterial = Enum.Material.Cobblestone,
	walled = false,
	spawnDistance = 74,
	layout = {
		{ kind = "low", x = -10, z = -20, length = 3 },
		{ kind = "block", x = 12, z = -34 },
		{ kind = "low", x = 0, z = -52, length = 4 },
		{ kind = "pillar", x = 0, z = 0, center = true },
	},
}

return function(makeProp: Registrar): Model
	return FlatArena.build(THEME, makeProp)
end
