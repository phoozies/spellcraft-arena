--!strict
-- Frostbite Fortress — a snowy castle courtyard with corner towers, slippery
-- ice patches, a central keep, and breakable gates guarding each team's
-- base. Tuned for 4v4.

local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local STONE = Color3.fromRGB(176, 190, 197)
local SNOW = Color3.fromRGB(245, 250, 255)

return function(makeProp: Registrar): Model
	local model = Instance.new("Model")
	model.Name = "FrostbiteFortress"

	MapKit.part(model, {
		name = "Floor",
		size = Vector3.new(150, 4, 150),
		cframe = CFrame.new(0, -2, 0),
		color = SNOW,
		material = Enum.Material.Snow,
	})

	-- Outer walls.
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local sx, sz = side[1], side[2]
		MapKit.part(model, {
			name = "CastleWall",
			size = if sx ~= 0 then Vector3.new(6, 22, 150) else Vector3.new(150, 22, 6),
			cframe = CFrame.new(sx * 75, 11, sz * 75),
			color = STONE,
			material = Enum.Material.Cobblestone,
		})
	end

	-- Corner towers with spiral-ish ramps.
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local cx, cz = corner[1] * 58, corner[2] * 58
		MapKit.part(model, {
			name = "Tower",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(18, 16, 16),
			cframe = CFrame.new(cx, 9, cz) * CFrame.Angles(0, 0, math.pi / 2),
			color = STONE,
			material = Enum.Material.Brick,
		})
		local ramp = Instance.new("WedgePart")
		ramp.Name = "TowerRamp"
		ramp.Anchored = true
		ramp.Size = Vector3.new(8, 18, 26)
		ramp.CFrame = CFrame.new(cx - corner[1] * 13, 9, cz - corner[2] * 20)
			* CFrame.Angles(0, if corner[2] > 0 then 0 else math.pi, 0)
		ramp.Color = STONE
		ramp.Material = Enum.Material.Slate
		ramp.Parent = model
	end

	-- Central keep: a raised platform with low crenellations.
	MapKit.part(model, {
		name = "Keep",
		size = Vector3.new(28, 6, 28),
		cframe = CFrame.new(0, 3, 0),
		color = Color3.fromRGB(144, 164, 174),
		material = Enum.Material.Slate,
	})
	for _, dir in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) } do
		local stair = Instance.new("WedgePart")
		stair.Name = "KeepStairs"
		stair.Anchored = true
		stair.Size = Vector3.new(10, 6, 10)
		stair.CFrame = CFrame.lookAt(dir * 19 + Vector3.new(0, 3, 0), Vector3.new(0, 3, 0))
		stair.Color = Color3.fromRGB(144, 164, 174)
		stair.Material = Enum.Material.Slate
		stair.Parent = model
	end

	-- Slippery ice patches.
	for _, pos in
		{
			Vector3.new(-40, 0.1, 0),
			Vector3.new(40, 0.1, 0),
			Vector3.new(0, 0.1, -30),
			Vector3.new(0, 0.1, 30),
		}
	do
		local ice = MapKit.part(model, {
			name = "IcePatch",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.4, 22, 22),
			cframe = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
			color = Color3.fromRGB(178, 235, 242),
			material = Enum.Material.Ice,
			transparency = 0.15,
		})
		ice.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.02, 0, 100, 1)
	end

	-- Breakable gates in front of each base.
	for _, z in { -50, 50 } do
		for _, x in { -24, 0, 24 } do
			local gate = MapKit.part(model, {
				name = "IceGate",
				size = Vector3.new(14, 10, 2),
				cframe = CFrame.new(x, 5, z),
				color = Color3.fromRGB(129, 212, 250),
				material = Enum.Material.Glass,
				transparency = 0.25,
			})
			makeProp(gate, 300)
		end
	end

	-- Snow drifts as soft cover.
	for _, pos in
		{
			Vector3.new(-30, 2, -20),
			Vector3.new(30, 2, 20),
			Vector3.new(-30, 2, 20),
			Vector3.new(30, 2, -20),
		}
	do
		local drift = MapKit.part(model, {
			name = "SnowDrift",
			shape = Enum.PartType.Ball,
			size = Vector3.new(10, 10, 10),
			cframe = CFrame.new(pos),
			color = SNOW,
			material = Enum.Material.Snow,
		})
		makeProp(drift, 150)
	end

	-- Breakable ice-brick walls guarding the keep's flanks.
	for _, z in { -22, 22 } do
		MapKit.blockWall(
			model,
			CFrame.new(0, 0, z),
			6,
			3,
			Vector3.new(3, 2.5, 2),
			Color3.fromRGB(179, 229, 252),
			Enum.Material.Ice,
			35,
			makeProp
		)
	end

	local spawns = MapKit.folder(model, "Spawns")
	MapKit.teamSpawns(spawns, Vector3.new(0, 3, 0), 64)
	MapKit.ffaSpawns(spawns, Vector3.new(0, 3, 0), 45, 8)

	local small = MapKit.folder(model, "SmallModeWalls")
	MapKit.ring(small, Vector3.zero, 48, 14, Color3.fromRGB(129, 212, 250))

	MapKit.bounds(model, Vector3.new(144, 80, 144), Vector3.new(0, 30, 0))
	return model
end
