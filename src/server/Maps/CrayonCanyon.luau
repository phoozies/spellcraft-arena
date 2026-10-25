--!strict
-- Crayon Canyon — a 3-lane canyon with two raised mesas and destructible
-- rope bridges. Rewards walls and high ground. Tuned for 8 players. The floor,
-- mesas and ramps are breakable terrain; the cliffs and end walls are not.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapKit = require(script.Parent.MapKit)

type Registrar = (instance: Instance, health: number) -> ()

local COLORS = {
	Color3.fromRGB(239, 83, 80),
	Color3.fromRGB(255, 167, 38),
	Color3.fromRGB(255, 238, 88),
	Color3.fromRGB(102, 187, 106),
	Color3.fromRGB(66, 165, 245),
	Color3.fromRGB(171, 71, 188),
}

return function(makeProp: Registrar): Model
	local model = Instance.new("Model")
	model.Name = "CrayonCanyon"
	local rng = MapKit.rng(1337)

	-- Floor: a paper-colored canyon bed, breakable cell by cell (blast a hole
	-- and anyone standing there falls). The cliffs and end walls below stay
	-- solid: they are the arena's edge.
	MapKit.terrain(model, {
		name = "Floor",
		size = Vector3.new(110, 4, 180),
		cframe = CFrame.new(0, -2, 0),
		color = Color3.fromRGB(255, 243, 224),
		material = Enum.Material.Sand,
	}, {
		cell = Config.TERRAIN.CELL,
		health = Config.TERRAIN.HEALTH.Ground,
		makeProp = makeProp,
		ground = true,
	})

	-- Tall striped cliffs on both sides.
	for _, side in { -1, 1 } do
		for i = 0, 8 do
			MapKit.part(model, {
				name = "Cliff",
				size = Vector3.new(10, 40 + rng:NextInteger(-4, 6), 20),
				cframe = CFrame.new(side * 58, 18, -80 + i * 20),
				color = COLORS[(i % #COLORS) + 1],
				material = Enum.Material.Sandstone,
			})
		end
	end
	-- End caps.
	for _, z in { -94, 94 } do
		MapKit.part(model, {
			name = "EndWall",
			size = Vector3.new(126, 40, 8),
			cframe = CFrame.new(0, 18, z),
			color = Color3.fromRGB(141, 110, 99),
			material = Enum.Material.Sandstone,
		})
	end

	-- Two mesas splitting the canyon into 3 lanes, with ramps at each end.
	for _, x in { -22, 22 } do
		MapKit.terrain(model, {
			name = "Mesa",
			size = Vector3.new(16, 14, 90),
			cframe = CFrame.new(x, 7, 0),
			color = Color3.fromRGB(255, 204, 128),
			material = Enum.Material.Sandstone,
		}, {
			cell = Config.TERRAIN.CELL,
			health = Config.TERRAIN.HEALTH.Rock,
			makeProp = makeProp,
		})
		for _, z in { -1, 1 } do
			local ramp = Instance.new("WedgePart")
			ramp.Name = "Ramp"
			ramp.Anchored = true
			ramp.Size = Vector3.new(16, 14, 22)
			ramp.CFrame = CFrame.new(x, 7, z * 56)
				* CFrame.Angles(0, if z > 0 then math.pi else 0, 0)
			ramp.Color = Color3.fromRGB(255, 183, 77)
			ramp.Material = Enum.Material.Sandstone
			ramp.Parent = model
			ramp:SetAttribute("Terrain", true)
			makeProp(ramp, Config.TERRAIN.HEALTH.Rock)
		end
	end

	-- Destructible rope bridges between the mesas (over the middle lane).
	for _, z in { -24, 24 } do
		local bridge = MapKit.part(model, {
			name = "RopeBridge",
			size = Vector3.new(28, 1, 8),
			cframe = CFrame.new(0, 13.5, z),
			color = Color3.fromRGB(161, 136, 127),
			material = Enum.Material.WoodPlanks,
		})
		makeProp(bridge, 250)
	end

	-- Giant crayons as cover (breakable).
	for i = 1, 10 do
		local x = rng:NextInteger(-45, 45)
		local z = rng:NextInteger(-60, 60)
		if math.abs(math.abs(x) - 22) > 10 then
			local crayon = MapKit.part(model, {
				name = "Crayon",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(12, 3, 3),
				cframe = CFrame.new(x, 6, z) * CFrame.Angles(0, 0, math.pi / 2),
				color = COLORS[(i % #COLORS) + 1],
				material = Enum.Material.SmoothPlastic,
			})
			makeProp(crayon, 180)
		end
	end

	-- Breakable brick cover: one wall in each lane, offset so teams meet them.
	for _, lane in { { x = -38, z = -14 }, { x = 0, z = 0 }, { x = 38, z = 14 } } do
		MapKit.blockWall(
			model,
			CFrame.new(lane.x, 0, lane.z),
			4,
			3,
			Vector3.new(3, 2.5, 2),
			COLORS[(lane.x // 19 % #COLORS) + 1],
			Enum.Material.Brick,
			30,
			makeProp
		)
	end

	local spawns = MapKit.folder(model, "Spawns")
	MapKit.teamSpawns(spawns, Vector3.new(0, 3, 0), 78)

	local small = MapKit.folder(model, "SmallModeWalls")
	for _, z in { -55, 55 } do
		MapKit.part(small, {
			name = "LaneGate",
			size = Vector3.new(106, 16, 2),
			cframe = CFrame.new(0, 8, z),
			color = Color3.fromRGB(129, 212, 250),
			material = Enum.Material.Glass,
			transparency = 0.6,
		})
	end

	MapKit.bounds(model, Vector3.new(106, 80, 180), Vector3.new(0, 30, 0))
	return model
end
