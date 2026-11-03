--!strict
-- Ember Forge: a basalt board ringed by glowing lava, with obsidian pillars
-- and brick walls for cover and a forge core burning in the middle. Walled in
-- (the lava is scenery). Built by FlatArena (flat board, mirrored cover, spawn
-- pads, edge lights); the lava moat and the spinning core don't collide.

local FlatArena = require(script.Parent.FlatArena)
local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local LAVA = Color3.fromRGB(255, 112, 40)

local THEME: FlatArena.Theme = {
	name = "EmberForge",
	seed = 451,
	shape = "round",
	radius = 64,
	floor = Color3.fromRGB(70, 62, 66),
	floorMaterial = Enum.Material.Basalt,
	accent = LAVA,
	curb = Color3.fromRGB(44, 38, 44),
	curbMaterial = Enum.Material.Basalt,
	underside = Color3.fromRGB(52, 44, 48),
	undersideMaterial = Enum.Material.Basalt,
	cover = Color3.fromRGB(150, 74, 60),
	coverMaterial = Enum.Material.Brick,
	pillar = Color3.fromRGB(34, 28, 44),
	pillarMaterial = Enum.Material.Glass,
	walled = true,
	spawnDistance = 46,
	layout = {
		{ kind = "pillar", x = -24, z = -10 },
		{ kind = "pillar", x = 24, z = -10 },
		{ kind = "wall", x = 0, z = -26, length = 4 },
		{ kind = "low", x = -38, z = -26, angle = 60, length = 3 },
		{ kind = "low", x = 38, z = -26, angle = -60, length = 3 },
		{ kind = "block", x = -12, z = -40 },
		{ kind = "block", x = 12, z = -40 },
	},
	decor = function(model: Model, _rng: Random, _makeProp: Registrar)
		-- A ring of lava glowing beyond the curb.
		for i = 1, 32 do
			local a = (i / 32) * math.pi * 2
			local lava = MapKit.part(model, {
				name = "Lava",
				size = Vector3.new(15, 1, 8),
				cframe = CFrame.new(math.cos(a) * 82, -1, math.sin(a) * 82)
					* CFrame.Angles(0, -a + math.pi / 2, 0),
				color = LAVA,
				material = Enum.Material.Neon,
				canCollide = false,
			})
			lava.CanQuery = false
		end
		-- The forge core: a floating ember over the centre mark.
		local core = MapKit.part(model, {
			name = "ForgeCore",
			size = Vector3.new(3, 3, 3),
			cframe = CFrame.new(0, 16, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			color = LAVA,
			material = Enum.Material.Neon,
			canCollide = false,
		})
		core.CanQuery = false
		core:AddTag("SpinFx")
		local light = Instance.new("PointLight")
		light.Color = LAVA
		light.Range = 40
		light.Brightness = 2
		light.Parent = core
	end,
}

return function(makeProp: Registrar): Model
	return FlatArena.build(THEME, makeProp)
end
