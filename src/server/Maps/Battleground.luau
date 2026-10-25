--!strict
-- The Battleground: a big open sand arena where anyone can drop in from the
-- hub and fight everyone else (BattlegroundService). It is built far from the
-- hub in the same place, so a "teleport" is just a move.
--
--   * a round sand floor with a tall sandstone rim and flag poles
--   * cover to fight around: a raised center platform, ruined walls,
--     pillars, and boulders
--   * 16 drop-in spawns around the edge (tag "BattlegroundSpawn")
--   * green exit pads that return you to the hub (tag "BattlegroundExit")
--   * a "BuildZone" volume, so Earth Walls can be raised here
--
-- `center` is the middle of the floor; the floor's top is at center.Y.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapKit = require(script.Parent.MapKit)

local SAND = Color3.fromRGB(226, 206, 160)
local STONE = Color3.fromRGB(214, 194, 156)
local STONE_LIGHT = Color3.fromRGB(240, 232, 214)
local GOLD = Color3.fromRGB(255, 202, 40)

local function label(part: BasePart, text: string, offset: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(240, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
	gui.MaxDistance = 200
	gui.Parent = part
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Text"
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0.3
	textLabel.Text = text
	textLabel.Parent = gui
	return textLabel
end

return function(center: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Battleground"
	local radius = Config.BATTLEGROUND.RADIUS

	-- The floor (a cylinder lies along X, so tip it up).
	MapKit.part(model, {
		name = "BattleFloor",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(2, radius * 2, radius * 2),
		cframe = CFrame.new(center - Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color = SAND,
		material = Enum.Material.Sand,
	})
	-- A darker ring and a gold ring painted on the sand.
	for _, ring in { { 72, STONE, 0.12 }, { 40, GOLD, 0.14 } } do
		MapKit.part(model, {
			name = "FloorRing",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.1, ring[1] * 2, ring[1] * 2),
			cframe = CFrame.new(center + Vector3.new(0, ring[3] - 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			color = ring[2] :: Color3,
			material = Enum.Material.Sandstone,
			canCollide = false,
		})
	end
	MapKit.part(model, {
		name = "FloorCore",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.1, 80 * 2 - 6, 80 * 2 - 6),
		cframe = CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color = SAND,
		material = Enum.Material.Sand,
		canCollide = false,
	})

	-- The rim: tall wall segments around the edge, with a flag every fourth.
	local segments = 36
	local segmentLength = 2 * math.pi * (radius + 2) / segments + 1
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		local position = center + Vector3.new(math.cos(a) * (radius + 2), 0, math.sin(a) * (radius + 2))
		MapKit.part(model, {
			name = "Rim",
			size = Vector3.new(segmentLength, 18, 4),
			cframe = CFrame.lookAt(position + Vector3.new(0, 9, 0), center + Vector3.new(0, 9, 0)),
			color = if i % 2 == 0 then STONE else STONE_LIGHT,
			material = Enum.Material.Sandstone,
		})
		if i % 4 == 0 then
			local base = position + Vector3.new(0, 18, 0)
			MapKit.part(model, {
				name = "FlagPole",
				size = Vector3.new(0.6, 12, 0.6),
				cframe = CFrame.new(base + Vector3.new(0, 6, 0)),
				color = STONE_LIGHT,
				material = Enum.Material.Metal,
				canCollide = false,
			})
			MapKit.part(model, {
				name = "Flag",
				size = Vector3.new(4.5, 3, 0.2),
				cframe = CFrame.new(base + Vector3.new(2.4, 10, 0)),
				color = if (i / 4) % 2 == 0 then Color3.fromRGB(66, 120, 220) else Color3.fromRGB(220, 70, 60),
				material = Enum.Material.Fabric,
				canCollide = false,
			})
		end
	end

	-- A raised platform in the middle with four pillars.
	MapKit.part(model, {
		name = "CenterPlatform",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(3, 36, 36),
		cframe = CFrame.new(center + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color = STONE_LIGHT,
		material = Enum.Material.Limestone,
	})
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		MapKit.part(model, {
			name = "CenterPillar",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(15, 4, 4),
			cframe = CFrame.new(center + Vector3.new(math.cos(a) * 12, 3 + 7.5, math.sin(a) * 12))
				* CFrame.Angles(0, 0, math.pi / 2),
			color = STONE_LIGHT,
			material = Enum.Material.Limestone,
		})
	end
	local sign = MapKit.part(model, {
		name = "BattleSign",
		size = Vector3.one,
		cframe = CFrame.new(center + Vector3.new(0, 24, 0)),
		transparency = 1,
		canCollide = false,
	})
	label(sign, "BATTLEGROUND\nEveryone for themselves!", 0)

	-- Ruined walls in a ring, set tangent to it (cover to duck behind).
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local position = center + Vector3.new(math.cos(a) * 52, 0, math.sin(a) * 52)
		MapKit.part(model, {
			name = "RuinedWall",
			size = Vector3.new(18, 9, 3),
			cframe = CFrame.lookAt(position + Vector3.new(0, 4.5, 0), center + Vector3.new(0, 4.5, 0)),
			color = STONE,
			material = Enum.Material.Sandstone,
		})
	end
	-- Pillars between them, and boulders closer in.
	for i = 1, 8 do
		local a = ((i - 0.5) / 8) * math.pi * 2
		MapKit.part(model, {
			name = "Pillar",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(16, 5, 5),
			cframe = CFrame.new(center + Vector3.new(math.cos(a) * 76, 8, math.sin(a) * 76))
				* CFrame.Angles(0, 0, math.pi / 2),
			color = STONE_LIGHT,
			material = Enum.Material.Limestone,
		})
	end
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		MapKit.part(model, {
			name = "Boulder",
			shape = Enum.PartType.Ball,
			size = Vector3.new(13, 11, 13),
			cframe = CFrame.new(center + Vector3.new(math.cos(a) * 30, 4, math.sin(a) * 30)),
			color = Color3.fromRGB(176, 150, 112),
			material = Enum.Material.Slate,
		})
	end

	-- Drop-in spawns around the edge, facing the middle.
	local spawns = MapKit.folder(model, "Spawns")
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2
		local position = center + Vector3.new(math.cos(a) * (radius - 14), 3, math.sin(a) * (radius - 14))
		local spawn = MapKit.part(spawns, {
			name = `BattleSpawn_{i}`,
			size = Vector3.new(4, 1, 4),
			cframe = CFrame.lookAt(position, center + Vector3.new(0, 3, 0)),
			transparency = 1,
			canCollide = false,
		})
		spawn:AddTag("BattlegroundSpawn")
	end

	-- Exit pads back to the hub, on opposite sides.
	for _, side in { -1, 1 } do
		local position = center + Vector3.new(0, 0.3, side * (radius - 8))
		local pad = MapKit.part(model, {
			name = "ExitPad",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.6, 12, 12),
			cframe = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2),
			color = Color3.fromRGB(80, 200, 110),
			material = Enum.Material.Neon,
			transparency = 0.25,
			canCollide = false,
		})
		pad:AddTag("BattlegroundExit")
		label(pad, "EXIT TO HUB", 6)
	end

	-- Anyone here may raise Earth Walls.
	local zone = MapKit.part(model, {
		name = "BattleBuildZone",
		size = Vector3.new(radius * 2, 60, radius * 2),
		cframe = CFrame.new(center + Vector3.new(0, 28, 0)),
		transparency = 1,
		canCollide = false,
	})
	zone.CanQuery = false
	zone.CanTouch = false
	zone:AddTag("BuildZone")

	return model
end
