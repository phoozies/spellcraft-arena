--!strict
-- Crayon Canyon: a long paper board split into three lanes by rows of giant
-- crayon blocks and brick walls. Fight down your lane or cut across through
-- the gaps. Walled in (no ring-outs). Tuned for 8 players. Built by FlatArena
-- (flat board, mirrored cover, spawn pads, edge lights); the crayons along the
-- sides are its own breakable props.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FlatArena = require(script.Parent.FlatArena)
local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local CRAYONS = {
	Color3.fromRGB(239, 83, 80),
	Color3.fromRGB(255, 167, 38),
	Color3.fromRGB(255, 238, 88),
	Color3.fromRGB(102, 187, 106),
	Color3.fromRGB(66, 165, 245),
	Color3.fromRGB(171, 71, 188),
}

local THEME: FlatArena.Theme = {
	name = "CrayonCanyon",
	seed = 1337,
	shape = "rect",
	halfX = 50,
	halfZ = 85,
	floor = Color3.fromRGB(255, 243, 224),
	floorMaterial = Enum.Material.Sand,
	accent = Color3.fromRGB(171, 71, 188),
	curb = Color3.fromRGB(255, 204, 128),
	curbMaterial = Enum.Material.Sandstone,
	underside = Color3.fromRGB(141, 110, 99),
	undersideMaterial = Enum.Material.Sandstone,
	cover = Color3.fromRGB(239, 154, 154),
	coverMaterial = Enum.Material.Brick,
	pillar = Color3.fromRGB(255, 183, 77),
	pillarMaterial = Enum.Material.SmoothPlastic,
	walled = true,
	spawnDistance = 72,
	layout = {
		-- The two lane dividers (crayon blocks with gaps to slip through).
		{ kind = "block", x = -18, z = -12 },
		{ kind = "block", x = 18, z = -12 },
		{ kind = "block", x = -18, z = -36 },
		{ kind = "block", x = 18, z = -36 },
		{ kind = "pillar", x = -18, z = -56 },
		{ kind = "pillar", x = 18, z = -56 },
		-- Brick cover in each lane.
		{ kind = "wall", x = -36, z = -24, length = 4 },
		{ kind = "low", x = 0, z = -22, length = 5 },
		{ kind = "wall", x = 36, z = -46, length = 4 },
		{ kind = "low", x = 0, z = -50, length = 3 },
	},
	decor = function(model: Model, _rng: Random, makeProp: Registrar)
		-- Giant crayons lying along both long sides (breakable).
		for i = 0, 9 do
			for _, side in { -1, 1 } do
				local crayon = MapKit.part(model, {
					name = "Crayon",
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(14, 3, 3),
					cframe = CFrame.new(side * 45, 1.5, -76 + i * 17)
						* CFrame.Angles(0, math.pi / 2, 0),
					color = CRAYONS[(i % #CRAYONS) + 1],
					material = Enum.Material.SmoothPlastic,
				})
				makeProp(crayon, Config.PROPS.Light)
			end
		end
	end,
}

return function(makeProp: Registrar): Model
	return FlatArena.build(THEME, makeProp)
end
