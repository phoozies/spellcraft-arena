--!strict
-- Sparring Arena: the training ring. A round slate board with a gold centre
-- mark, four marble pillars and two low walls per side: simple sight lines,
-- made for learning to duel. Open edge, so knockback can ring you out into the
-- water below. Roomy: favoured for 1v1 and 2v2, skipped for 4v4. Built by
-- FlatArena (flat board, mirrored cover, spawn pads, edge lights).

local FlatArena = require(script.Parent.FlatArena)

type Registrar = (instance: Instance, health: number) -> ()

local THEME: FlatArena.Theme = {
	name = "SparringArena",
	seed = 46,
	shape = "round",
	radius = 64,
	floor = Color3.fromRGB(120, 128, 146),
	floorMaterial = Enum.Material.Slate,
	accent = Color3.fromRGB(255, 202, 40),
	curb = Color3.fromRGB(226, 220, 204),
	curbMaterial = Enum.Material.Marble,
	underside = Color3.fromRGB(96, 92, 104),
	undersideMaterial = Enum.Material.Rock,
	cover = Color3.fromRGB(214, 206, 186),
	coverMaterial = Enum.Material.Brick,
	pillar = Color3.fromRGB(236, 232, 222),
	pillarMaterial = Enum.Material.Marble,
	walled = false,
	spawnDistance = 46,
	layout = {
		{ kind = "pillar", x = -22, z = -16 },
		{ kind = "pillar", x = 22, z = -16 },
		{ kind = "low", x = 0, z = -30, length = 5 },
		{ kind = "block", x = -38, z = -6 },
		{ kind = "block", x = 38, z = -6 },
	},
}

return function(makeProp: Registrar): Model
	return FlatArena.build(THEME, makeProp)
end
