--!strict
-- Moss Ruins: an overgrown courtyard. Mossy brick walls, broken columns and
-- trees give the most cover of any map, so it rewards flanking. Walled in.
-- Built by FlatArena (flat board, mirrored cover, spawn pads, edge lights).

local FlatArena = require(script.Parent.FlatArena)

type Registrar = (instance: Instance, health: number) -> ()

local THEME: FlatArena.Theme = {
	name = "MossRuins",
	seed = 77,
	shape = "round",
	radius = 66,
	floor = Color3.fromRGB(106, 168, 84),
	floorMaterial = Enum.Material.Grass,
	accent = Color3.fromRGB(240, 232, 214),
	curb = Color3.fromRGB(150, 156, 140),
	curbMaterial = Enum.Material.Cobblestone,
	underside = Color3.fromRGB(110, 96, 80),
	undersideMaterial = Enum.Material.Rock,
	cover = Color3.fromRGB(128, 150, 112),
	coverMaterial = Enum.Material.Cobblestone,
	pillar = Color3.fromRGB(214, 224, 244),
	pillarMaterial = Enum.Material.Marble,
	walled = true,
	spawnDistance = 48,
	layout = {
		{ kind = "wall", x = -26, z = -14, angle = 90, length = 3 },
		{ kind = "wall", x = 26, z = -14, angle = 90, length = 3 },
		{ kind = "pillar", x = -10, z = -24 },
		{ kind = "pillar", x = 10, z = -24 },
		{ kind = "tree", x = -42, z = -26 },
		{ kind = "tree", x = 42, z = -26 },
		{ kind = "low", x = 0, z = -36, length = 4 },
		{ kind = "block", x = -50, z = -6 },
		{ kind = "block", x = 50, z = -6 },
	},
}

return function(makeProp: Registrar): Model
	return FlatArena.build(THEME, makeProp)
end
