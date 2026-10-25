--!strict
-- The Battleground: a big open world that players drop into from the hub
-- (BattlegroundService) at a random open spot. It is built far from the
-- hub in the same place, so a "teleport" is just a move.
--
-- A 600 x 600 stud square of land, one open world with distant mountain
-- scenery and invisible walls at its edge, split into four
-- biomes (forest, meadow, desert, rocky highlands) dotted with block-model
-- trees (oak, pine, birch), cacti, and rocks. In it:
--   * six Raider camps (tents, campfire, banner) and two ruined stone circles
--     guarded by NPCs, and the Warlord's Keep in the middle (the boss)
--   * "NpcSpot" parts (tag) that name an NPC type in their `NpcType`
--     attribute; NpcService spawns one NPC at each
--   * four green exit pads at the gates (tag "BattlegroundExit") back to the hub
--   * a "BuildZone" volume, so Earth Walls can be raised anywhere
-- There is no spawn point: BattlegroundService picks a random open spot.
--
-- `center` is the middle of the land; the ground's top is at center.Y.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local MapKit = require(script.Parent.MapKit)

local GRASS = Color3.fromRGB(98, 168, 74)
local FOREST = Color3.fromRGB(62, 128, 62)
local MEADOW = Color3.fromRGB(128, 190, 92)
local DESERT = Color3.fromRGB(226, 202, 150)
local ROCKY = Color3.fromRGB(150, 148, 142)
local STONE = Color3.fromRGB(214, 194, 156)
local STONE_LIGHT = Color3.fromRGB(240, 232, 214)
local GOLD = Color3.fromRGB(255, 202, 40)

-- {x, z} offsets from the center.
local CAMPS =
	{ { -190, -170 }, { 185, -190 }, { -215, 45 }, { 205, 70 }, { -70, 215 }, { 95, 205 } }
local RUINS = { { -110, -45 }, { 120, -70 } }
local KEEP_RADIUS = 52

local function label(part: BasePart, text: string, offset: number, distance: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(240, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
	gui.MaxDistance = distance or 160
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
	local half = Config.BATTLEGROUND.HALF_SIZE
	local rng = MapKit.rng(7)

	local function at(x: number, z: number, y: number?): Vector3
		return center + Vector3.new(x, y or 0, z)
	end

	-- Places that props must stay out of: {x, z, radius}.
	local reserved: { { number } } = {}
	for _, camp in CAMPS do
		table.insert(reserved, { camp[1], camp[2], 30 })
	end
	for _, ruin in RUINS do
		table.insert(reserved, { ruin[1], ruin[2], 24 })
	end
	table.insert(reserved, { 0, 0, KEEP_RADIUS + 10 })
	for _, gate in { { 0, half - 22 }, { 0, -(half - 22) }, { half - 22, 0 }, { -(half - 22), 0 } } do
		table.insert(reserved, { gate[1], gate[2], 22 })
	end
	local function free(x: number, z: number, margin: number?): boolean
		for _, spot in reserved do
			local dx, dz = x - spot[1], z - spot[2]
			if math.sqrt(dx * dx + dz * dz) < spot[3] + (margin or 0) then
				return false
			end
		end
		return true
	end
	-- A random free point inside a rectangle (x0..x1, z0..z1), or nil.
	local function pick(x0: number, x1: number, z0: number, z1: number): (number?, number?)
		for _ = 1, 20 do
			local x, z = rng:NextNumber(x0, x1), rng:NextNumber(z0, z1)
			if free(x, z, 4) then
				return x, z
			end
		end
		return nil, nil
	end

	----------------------------------------------------------------------
	-- Land: grass, four biome patches, mountains, and the edge walls
	----------------------------------------------------------------------
	MapKit.part(model, {
		name = "Ground",
		size = Vector3.new(half * 2 + 80, 4, half * 2 + 80),
		cframe = CFrame.new(center - Vector3.new(0, 2, 0)),
		color = GRASS,
		material = Enum.Material.Grass,
	})
	for index, biome in
		{
			{ x = -150, z = -150, color = FOREST, material = Enum.Material.Grass },
			{ x = -150, z = 150, color = MEADOW, material = Enum.Material.Grass },
			{ x = 150, z = 150, color = DESERT, material = Enum.Material.Sand },
			{ x = 150, z = -150, color = ROCKY, material = Enum.Material.Slate },
		}
	do
		MapKit.part(model, {
			name = "Biome",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.2, 300, 300),
			cframe = CFrame.new(at(biome.x, biome.z, 0.05 + index * 0.02))
				* CFrame.Angles(0, 0, math.pi / 2),
			color = biome.color,
			material = biome.material,
			canCollide = false,
		})
	end

	-- Sides 1 and 2 are the west and east edges, 3 and 4 the north and south.
	-- Scenery mountains far beyond the edge (nothing to climb or hit), and
	-- invisible walls at the edge of the land so nobody can walk off the map.
	for side = 1, 4 do
		local along = Vector3.new(if side <= 2 then 0 else 1, 0, if side <= 2 then 1 else 0)
		local out = Vector3.new(
			if side == 1 then -1 elseif side == 2 then 1 else 0,
			0,
			if side == 3 then -1 elseif side == 4 then 1 else 0
		)
		for i = 1, 14 do
			local t = (i - 7.5) / 7 * (half + 20)
			local height = rng:NextNumber(55, 100)
			local width = rng:NextNumber(46, 62)
			local position = center
				+ along * t
				+ out * (half + 75)
				+ Vector3.new(0, height / 2 - 4, 0)
			MapKit.part(model, {
				name = "Mountain",
				size = if side <= 2
					then Vector3.new(40, height, width)
					else Vector3.new(width, height, 40),
				cframe = CFrame.new(position),
				color = if i % 3 == 0
					then Color3.fromRGB(122, 116, 108)
					else Color3.fromRGB(150, 140, 126),
				material = Enum.Material.Slate,
				canCollide = false,
			})
		end
		local wall = MapKit.part(model, {
			name = "EdgeWall",
			size = if side <= 2
				then Vector3.new(8, 200, half * 2 + 100)
				else Vector3.new(half * 2 + 100, 200, 8),
			cframe = CFrame.new(center + out * (half + 4) + Vector3.new(0, 100, 0)),
			transparency = 1,
		})
		wall.CanQuery = false
		wall.CanTouch = false
	end

	----------------------------------------------------------------------
	-- Scenery: trees, cacti, rocks
	----------------------------------------------------------------------
	local scenicFolder = MapKit.folder(model, "Scenery")
	-- Block-model scenery (TreeOak, TreePine, TreeBirch, Cactus); the plain
	-- trunk-and-ball look stays as the fallback when a model is missing.
	local function scenery(names: { string }, x: number, z: number, scale: number): boolean
		local art = ModelKit.clone(names[rng:NextInteger(1, #names)], "solid", scale * 1.15)
		if not art then
			return false
		end
		art:PivotTo(CFrame.new(at(x, z)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		art.Parent = scenicFolder
		return true
	end
	local function tree(x: number, z: number, scale: number, kinds: { string })
		if scenery(kinds, x, z, scale) then
			return
		end
		local base = at(x, z)
		MapKit.part(model, {
			name = "Trunk",
			size = Vector3.new(2, 10, 2) * scale,
			cframe = CFrame.new(base + Vector3.new(0, 5 * scale, 0)),
			color = Color3.fromRGB(110, 80, 56),
			material = Enum.Material.Wood,
		})
		MapKit.part(model, {
			name = "Leaves",
			shape = Enum.PartType.Ball,
			size = Vector3.new(12, 10, 12) * scale,
			cframe = CFrame.new(base + Vector3.new(0, 13 * scale, 0)),
			color = Color3.fromRGB(56 + rng:NextInteger(0, 30), 130 + rng:NextInteger(0, 30), 60),
			material = Enum.Material.Grass,
			canCollide = false,
		})
	end
	local function cactus(x: number, z: number)
		if scenery({ "Cactus" }, x, z, rng:NextNumber(0.8, 1.3)) then
			return
		end
		local base = at(x, z)
		local height = rng:NextNumber(7, 12)
		MapKit.part(model, {
			name = "Cactus",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(height, 2.4, 2.4),
			cframe = CFrame.new(base + Vector3.new(0, height / 2, 0))
				* CFrame.Angles(0, 0, math.pi / 2),
			color = Color3.fromRGB(80, 150, 80),
			material = Enum.Material.Grass,
		})
		MapKit.part(model, {
			name = "CactusArm",
			size = Vector3.new(4, 1.6, 1.6),
			cframe = CFrame.new(base + Vector3.new(2.2, height * 0.6, 0)),
			color = Color3.fromRGB(80, 150, 80),
			material = Enum.Material.Grass,
			canCollide = false,
		})
	end
	local function rock(x: number, z: number, size: number)
		MapKit.part(model, {
			name = "Rock",
			shape = Enum.PartType.Ball,
			size = Vector3.new(size, size * 0.75, size * rng:NextNumber(0.8, 1.1)),
			cframe = CFrame.new(at(x, z, size * 0.3))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			color = Color3.fromRGB(
				150 + rng:NextInteger(-14, 14),
				146 + rng:NextInteger(-14, 14),
				138
			),
			material = Enum.Material.Slate,
		})
	end
	local m = half - 30
	for _ = 1, 70 do -- forest (north-west)
		local x, z = pick(-m, -20, -m, -20)
		if x and z then
			tree(x, z, rng:NextNumber(0.9, 1.4), { "TreeOak", "TreePine", "TreePine", "TreeBirch" })
		end
	end
	for _ = 1, 24 do -- meadow (south-west): a few trees
		local x, z = pick(-m, -20, 20, m)
		if x and z then
			tree(x, z, rng:NextNumber(0.8, 1.2), { "TreeOak", "TreeBirch" })
		end
	end
	for _ = 1, 36 do -- desert (south-east)
		local x, z = pick(20, m, 20, m)
		if x and z then
			cactus(x, z)
		end
	end
	for _ = 1, 40 do -- rocky highlands (north-east)
		local x, z = pick(20, m, -m, -20)
		if x and z then
			rock(x, z, rng:NextNumber(5, 15))
		end
	end
	for _ = 1, 30 do -- loose rocks everywhere
		local x, z = pick(-m, m, -m, m)
		if x and z then
			rock(x, z, rng:NextNumber(3, 7))
		end
	end

	----------------------------------------------------------------------
	-- NPC spots and the places they live
	----------------------------------------------------------------------
	local spots = MapKit.folder(model, "NpcSpots")
	local function npcSpot(x: number, z: number, npcType: string)
		local spot = MapKit.part(spots, {
			name = `Spot_{npcType}`,
			size = Vector3.new(2, 0.2, 2),
			cframe = CFrame.new(at(x, z, 0.1)),
			transparency = 1,
			canCollide = false,
		})
		spot:SetAttribute("NpcType", npcType)
		spot:AddTag("NpcSpot")
	end

	-- Raider camps: tents around a campfire, crates, and a banner.
	local tentColors =
		{ Color3.fromRGB(200, 70, 56), Color3.fromRGB(70, 110, 200), Color3.fromRGB(226, 196, 90) }
	for index, camp in CAMPS do
		local cx, cz = camp[1], camp[2]
		-- Campfire: a ring of stones, two logs, and a flame with a warm light.
		for i = 1, 6 do
			local a = (i / 6) * math.pi * 2
			MapKit.part(model, {
				name = "FireStone",
				shape = Enum.PartType.Ball,
				size = Vector3.new(1.4, 1.1, 1.4),
				cframe = CFrame.new(at(cx + math.cos(a) * 2.4, cz + math.sin(a) * 2.4, 0.5)),
				color = Color3.fromRGB(130, 126, 120),
				material = Enum.Material.Slate,
			})
		end
		local flame = MapKit.part(model, {
			name = "CampFlame",
			shape = Enum.PartType.Ball,
			size = Vector3.new(1.8, 2.6, 1.8),
			cframe = CFrame.new(at(cx, cz, 1.6)),
			color = Color3.fromRGB(255, 150, 40),
			material = Enum.Material.Neon,
			canCollide = false,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 80)
		light.Range = 22
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = flame
		-- Tents: two leaning planks make an A-frame.
		for tentIndex = 1, 3 do
			local a = (tentIndex / 3) * math.pi * 2 + index
			local tx, tz = cx + math.cos(a) * 12, cz + math.sin(a) * 12
			local facing = CFrame.new(at(tx, tz)) * CFrame.Angles(0, a + math.pi / 2, 0)
			for _, side in { -1, 1 } do
				MapKit.part(model, {
					name = "Tent",
					size = Vector3.new(0.4, 6.6, 8),
					cframe = facing
						* CFrame.new(side * 1.9, 3.1, 0)
						* CFrame.Angles(0, 0, side * math.rad(-32)),
					color = tentColors[tentIndex],
					material = Enum.Material.Fabric,
				})
			end
		end
		-- Crates and a banner pole.
		for crate = 1, 3 do
			MapKit.part(model, {
				name = "Crate",
				size = Vector3.new(3, 3, 3),
				cframe = CFrame.new(at(cx - 6 + crate * 2.2, cz + 7, 1.5))
					* CFrame.Angles(0, crate, 0),
				color = Color3.fromRGB(160, 120, 70),
				material = Enum.Material.WoodPlanks,
			})
		end
		local pole = MapKit.part(model, {
			name = "CampPole",
			size = Vector3.new(0.7, 16, 0.7),
			cframe = CFrame.new(at(cx + 16, cz, 8)),
			color = Color3.fromRGB(100, 76, 54),
			material = Enum.Material.Wood,
		})
		MapKit.part(model, {
			name = "CampFlag",
			size = Vector3.new(5, 3.4, 0.2),
			cframe = CFrame.new(at(cx + 18.6, cz, 13.5)),
			color = Color3.fromRGB(200, 40, 40),
			material = Enum.Material.Fabric,
			canCollide = false,
		})
		label(pole, "Raider Camp", 11, 120)
		npcSpot(cx - 8, cz - 4, "Raider")
		npcSpot(cx + 8, cz - 6, "Raider")
		npcSpot(cx, cz - 12, "Mage")
	end

	-- Ruined stone circles with a Stone Brute in the middle.
	for _, ruin in RUINS do
		local rx, rz = ruin[1], ruin[2]
		for i = 1, 7 do
			local a = (i / 7) * math.pi * 2
			local height = rng:NextNumber(6, 15)
			MapKit.part(model, {
				name = "RuinPillar",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(height, 4, 4),
				cframe = CFrame.new(at(rx + math.cos(a) * 13, rz + math.sin(a) * 13, height / 2))
					* CFrame.Angles(0, 0, math.pi / 2),
				color = STONE_LIGHT,
				material = Enum.Material.Limestone,
			})
		end
		MapKit.part(model, {
			name = "RuinSlab",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(1, 18, 18),
			cframe = CFrame.new(at(rx, rz, 0.5)) * CFrame.Angles(0, 0, math.pi / 2),
			color = STONE,
			material = Enum.Material.Sandstone,
		})
		npcSpot(rx, rz, "Brute")
	end

	-- The Warlord's Keep: a broken ring wall and four towers around a dais.
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2
		-- Leave gaps to the north, south, east, and west.
		local gap = math.abs(math.sin(a * 2)) < 0.22
		if not gap then
			local position = at(math.cos(a) * 40, math.sin(a) * 40)
			MapKit.part(model, {
				name = "KeepWall",
				size = Vector3.new(16, 13, 3),
				cframe = CFrame.lookAt(
					position + Vector3.new(0, 6.5, 0),
					center + Vector3.new(0, 6.5, 0)
				),
				color = STONE,
				material = Enum.Material.Sandstone,
			})
		end
	end
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		MapKit.part(model, {
			name = "KeepTower",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(26, 9, 9),
			cframe = CFrame.new(at(corner[1] * 30, corner[2] * 30, 13))
				* CFrame.Angles(0, 0, math.pi / 2),
			color = STONE_LIGHT,
			material = Enum.Material.Limestone,
		})
		MapKit.part(model, {
			name = "KeepBanner",
			size = Vector3.new(4, 9, 0.3),
			cframe = CFrame.new(at(corner[1] * 30, corner[2] * 30 + 4.8, 20)),
			color = Color3.fromRGB(170, 36, 36),
			material = Enum.Material.Fabric,
			canCollide = false,
		})
	end
	MapKit.part(model, {
		name = "KeepDais",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(2, 24, 24),
		cframe = CFrame.new(at(0, 0, 1)) * CFrame.Angles(0, 0, math.pi / 2),
		color = STONE_LIGHT,
		material = Enum.Material.Limestone,
	})
	local keepSign = MapKit.part(model, {
		name = "KeepSign",
		size = Vector3.one,
		cframe = CFrame.new(at(0, 0, 32)),
		transparency = 1,
		canCollide = false,
	})
	label(keepSign, "WARLORD'S KEEP", 0, 200)
	npcSpot(0, 0, "Warlord")

	----------------------------------------------------------------------
	-- Exit gates (north, south, east, west): green pads back to the hub
	----------------------------------------------------------------------
	for _, gate in { { 0, half - 22 }, { 0, -(half - 22) }, { half - 22, 0 }, { -(half - 22), 0 } } do
		local gx, gz = gate[1], gate[2]
		local facing = CFrame.new(at(gx, gz))
			* CFrame.Angles(0, if gx == 0 then 0 else math.pi / 2, 0)
		for _, side in { -1, 1 } do
			MapKit.part(model, {
				name = "GatePillar",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(20, 4.4, 4.4),
				cframe = facing * CFrame.new(side * 9, 10, 0) * CFrame.Angles(0, 0, math.pi / 2),
				color = STONE_LIGHT,
				material = Enum.Material.Limestone,
			})
		end
		MapKit.part(model, {
			name = "GateLintel",
			size = Vector3.new(24, 3.4, 4.8),
			cframe = facing * CFrame.new(0, 21, 0),
			color = GOLD,
			material = Enum.Material.Metal,
		})
		local pad = MapKit.part(model, {
			name = "ExitPad",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.6, 11, 11),
			cframe = CFrame.new(at(gx, gz, 0.3)) * CFrame.Angles(0, 0, math.pi / 2),
			color = Color3.fromRGB(80, 200, 110),
			material = Enum.Material.Neon,
			transparency = 0.25,
			canCollide = false,
		})
		pad:AddTag("BattlegroundExit")
		label(pad, "EXIT TO HUB", 7, 150)
	end

	-- Anyone here may raise Earth Walls.
	local zone = MapKit.part(model, {
		name = "BattleBuildZone",
		size = Vector3.new(half * 2, 80, half * 2),
		cframe = CFrame.new(center + Vector3.new(0, 38, 0)),
		transparency = 1,
		canCollide = false,
	})
	zone.CanQuery = false
	zone.CanTouch = false
	zone:AddTag("BuildZone")

	return model
end
