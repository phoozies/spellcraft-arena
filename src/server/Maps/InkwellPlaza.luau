--!strict
-- Inkwell Plaza: the central hub, a round FLOATING ISLAND in the sky (grass top,
-- a sand beach around the rim, a dark rock cone hanging underneath, and open
-- ocean far below), built from the look of a marble-and-meadow island: white
-- stepped amphitheatre arcs, leaning marble pillars, a ruined arch, bare trees
-- and a wooden rail. It is centered on the origin with its top at y = 0
-- (Config.HUB.RADIUS wide). Everything is laid out in rings around the wizard
-- statue on the inkwell; angles are in degrees clockwise from north (-Z):
--
--   centre   the sand plaza (r 46): the inkwell and wizard statue, the 4 element
--            shrines (they list what to draw for each spell), the Spellbook and
--            Daily Quests kiosks, the Like & Favourite gift box, and the spawn
--   roads    four marble roads leave the plaza due north, east, south and west
--            and cross the grey ring road (r 84-92); every destination sits on one
--   north    the duel ring: the six team boxes (two 1v1, two 2v2, 3v3, 4v4) in an
--            arc at r 112 facing the centre with the road running through the gap
--            in the middle to the Arena Gate; the winners' podium and the Most
--            Wins board flank the road at r 64
--   south    opposite the duels: the Battleground portal (r 130)
--   west     a Training Grove, and east its mirror twin (both past the ring road,
--            the only places in the hub to draw and cast)
--   diagonals  a half-amphitheatre of stands on each south diagonal (inside the
--            ring, clear of every road); the Chest Shop out on the south-east and
--            a matching pavilion on the south-west
--   rim      a wooden rail, a beach, and four SPECTATE overlooks. Duels are not
--            fought here: ArenaService summons each arena BELOW the island (see
--            Config.ARENA), so players on the rim can look down and watch.
--
-- Tags/attributes HubService relies on:
--   TeamPad   (Mode, Team, Slots)   one side of a team box: players stand on
--                                   a side to pick their team (1v1..4v4)
--   BattlegroundPortal              step on to be teleported to the Battleground
--                                   (BattlegroundService)
--   BuildZone                       placing objects allowed here
--   PracticeZone                    drawing and casting allowed here (both Training Groves)
--   DummySpot (FaceYaw)             training dummies respawn here, facing FaceYaw
--   HubSpawn                        where players appear
--   WinsBoard                       LeaderboardService writes the top wins
--   PodiumSpot (Rank 1-3)           LeaderboardService stands the top-3
--                                   players' avatars on these pedestals (their
--                                   front face, and the avatars, face the centre)
--   ProximityPrompts named "Spellbook", "Quests" and "Chests" open UI on
--   the client (MenuController / ChestController; a chest's prompt carries
--   its ChestId so the shop opens on that chest)
--   LikeGift                        the gift box: its ProximityPrompt claims the
--                                   one-time Like & Favourite coin gift
--                                   (EconomyService)
--
-- The spellbook kiosk uses the imported Grimoire model and the Chest Shop
-- the ShopChest block model (ReplicatedStorage.Models via ModelKit), with plain-shape
-- fallbacks when the place doesn't have them. The warm afternoon light is the
-- client's LightingController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Chests = require(ReplicatedStorage.Shared.Economy.Chests)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local GlyphView = require(ReplicatedStorage.Shared.UI.GlyphView)
local MapKit = require(script.Parent.MapKit)

local BLUE = Color3.fromRGB(66, 165, 245)
local RED = Color3.fromRGB(239, 83, 80)

local STONE = Color3.fromRGB(214, 194, 156) -- sandstone
local STONE_DARK = Color3.fromRGB(160, 136, 100)
local STONE_LIGHT = Color3.fromRGB(240, 232, 214) -- pale marble
local FLOOR = Color3.fromRGB(226, 206, 160) -- arena sand
local GOLD = Color3.fromRGB(255, 202, 40)
local GOLD_GLOW = Color3.fromRGB(255, 210, 90)

-- Layout (studs). The island is centered on the origin; bearings are degrees
-- clockwise from north (-Z).
local RADIUS = Config.HUB.RADIUS
local PLAZA_RADIUS = 46
local BOX_RADIUS = 112 -- the team boxes' arc
local BOX_GAP = 5 -- studs between neighbouring boxes
local BOX_CENTER_GAP = 14 -- extra room in the middle of the arc for the north road
local ROAD_WIDTH = 14
local RING_ROAD_OUTER = 92 -- the grey ring road's outer edge
-- The two Training Groves, mirrored west and east. X is how deep they are
-- (outward from the plaza), Z how wide. Their plaza-side edge stays well
-- clear of the ring road.
local GROVE_X, GROVE_Z = 100, 112
local GROVE_CENTER_X = 152
local RIM_RADIUS = RADIUS - 10 -- the rail
-- The wizard statue on the inkwell (the model is about 21 studs tall at scale 1).
local STATUE_SCALE = 1.5
local ROCK = Color3.fromRGB(78, 72, 86)
local MARBLE = Color3.fromRGB(214, 224, 244) -- cool white, like the video's stonework

-- Team boxes, in the order they stand along the arc (left to right as you face
-- north, with the road to the Arena Gate between the third and fourth): {id,
-- mode, players per team}. The two halves are about the same width. Each box is two side-by-side pads, Blue
-- then Red, one spot per teammate, open to the centre. `id` names the box
-- (HubService keeps one countdown per id), so a mode can have more than one box.
local BOXES = {
	{ id = "4v4_A", mode = "4v4", perTeam = 4 },
	{ id = "2v2_A", mode = "2v2", perTeam = 2 },
	{ id = "1v1_A", mode = "1v1", perTeam = 1 },
	{ id = "1v1_B", mode = "1v1", perTeam = 1 },
	{ id = "2v2_B", mode = "2v2", perTeam = 2 },
	{ id = "3v3_A", mode = "3v3", perTeam = 3 },
}
local BOX_LEFT_COUNT = 3 -- boxes left of the north road
local PAD_DEPTH = 8
local PAD_GAP = 2

-- A point on the ground at `bearing` degrees (0 = north, 90 = east) and
-- `radius` studs from the island's axis.
local function polar(bearing: number, radius: number): Vector3
	local a = math.rad(bearing)
	return Vector3.new(math.sin(a) * radius, 0, -math.cos(a) * radius)
end

-- A frame standing at `position` whose front (-Z) looks at the island's axis.
local function facingCenter(position: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
end

-- A frame at `position` whose BACK (+Z) looks at the axis (it faces outward),
-- so a reader standing toward the centre is on its +Z side.
local function facingOut(position: Vector3): CFrame
	return CFrame.lookAt(position, position * 2 - Vector3.new(0, position.Y, 0))
end

-- `maxDistance` hides the label from far away so crowded signs don't pile up.
local function label(part: BasePart, text: string, offset: number, maxDistance: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
	gui.MaxDistance = maxDistance or 150
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

local function prompt(
	parent: BasePart,
	name: string,
	action: string,
	objectText: string
): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = objectText
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function glow(parent: BasePart, color: Color3, range: number, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1.5
	light.Shadows = false
	light.Parent = parent
end

-- An invisible anchor for a floating sign.
local function signAnchor(model: Instance, name: string, position: Vector3): BasePart
	return MapKit.part(model, {
		name = name,
		size = Vector3.one,
		cframe = CFrame.new(position),
		transparency = 1,
		canCollide = false,
	})
end

-- An upright round column (Cylinders lie along X, so tip it up).
local function column(
	parent: Instance,
	position: Vector3,
	height: number,
	diameter: number,
	color: Color3
): Part
	return MapKit.part(parent, {
		name = "Column",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = CFrame.new(position + Vector3.new(0, height / 2, 0))
			* CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		material = Enum.Material.Limestone,
	})
end

-- A beam from point `a` to point `b` (world space).
local function beam(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	collide: boolean?
): Part
	local length = (b - a).Magnitude
	return MapKit.part(parent, {
		name = "Beam",
		size = Vector3.new(thickness, thickness, length),
		cframe = CFrame.lookAt(a, b) * CFrame.new(0, 0, -length / 2),
		color = color,
		material = Enum.Material.Limestone,
		canCollide = collide or false,
	})
end

-- A pointed (gothic) arch frame: two posts and two slanted beams meeting at
-- the apex. `frame` has local X along the arch's width, Y up, centered on the
-- floor.
local function pointedArch(
	parent: Instance,
	frame: CFrame,
	width: number,
	height: number,
	thickness: number,
	color: Color3
)
	local left = frame:PointToWorldSpace(Vector3.new(-width / 2, 0, 0))
	local right = frame:PointToWorldSpace(Vector3.new(width / 2, 0, 0))
	for _, base in { left, right } do
		MapKit.part(parent, {
			name = "ArchPost",
			size = Vector3.new(thickness, height, thickness),
			cframe = CFrame.new(base + Vector3.new(0, height / 2, 0)) * (frame - frame.Position),
			color = color,
			material = Enum.Material.Limestone,
		})
	end
	local apex = frame:PointToWorldSpace(Vector3.new(0, height + width * 0.45, 0))
	beam(parent, left + Vector3.new(0, height, 0), apex, thickness, color)
	beam(parent, right + Vector3.new(0, height, 0), apex, thickness, color)
end

-- A standing torch with a flame and a warm light.
local function torch(parent: Instance, position: Vector3)
	MapKit.part(parent, {
		name = "TorchPost",
		size = Vector3.new(0.8, 6, 0.8),
		cframe = CFrame.new(position + Vector3.new(0, 3, 0)),
		color = Color3.fromRGB(70, 50, 40),
		material = Enum.Material.Wood,
	})
	local flame = MapKit.part(parent, {
		name = "Flame",
		shape = Enum.PartType.Ball,
		size = Vector3.new(1.8, 2.4, 1.8),
		cframe = CFrame.new(position + Vector3.new(0, 7, 0)),
		color = Color3.fromRGB(255, 150, 40),
		material = Enum.Material.Neon,
		canCollide = false,
	})
	glow(flame, Color3.fromRGB(255, 160, 70), 22, 1.4)
end

-- A round hay bale lying on its side (training-yard dressing).
local function hayBale(parent: Instance, position: Vector3, yaw: number)
	MapKit.part(parent, {
		name = "HayBale",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(4, 3.2, 3.2),
		cframe = CFrame.new(position + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, math.rad(yaw), 0),
		color = Color3.fromRGB(226, 188, 84),
		material = Enum.Material.Fabric,
	})
end

-- An archery-style target on two posts, facing +X (`dir` = 1) or -X (`dir` = -1).
local function targetStand(parent: Instance, position: Vector3, dir: number)
	for _, dz in { -2.2, 2.2 } do
		MapKit.part(parent, {
			name = "TargetPost",
			size = Vector3.new(0.7, 5, 0.7),
			cframe = CFrame.new(position + Vector3.new(0, 2.5, dz)),
			color = Color3.fromRGB(120, 86, 56),
			material = Enum.Material.Wood,
		})
	end
	for index, ring in
		{
			{ 6.4, Color3.fromRGB(240, 240, 240) },
			{ 5, Color3.fromRGB(40, 40, 44) },
			{ 3.6, Color3.fromRGB(60, 150, 235) },
			{ 2.4, Color3.fromRGB(235, 64, 52) },
			{ 1.1, Color3.fromRGB(255, 202, 40) },
		}
	do
		MapKit.part(parent, {
			name = "TargetRing",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.3 + index * 0.05, ring[1], ring[1]),
			cframe = CFrame.new(position + Vector3.new(dir * (0.3 + index * 0.05), 5.2, 0)),
			color = ring[2],
			material = Enum.Material.SmoothPlastic,
			canCollide = index == 1,
		})
	end
end

-- A wooden training fence between two points (rails and posts).
local function fenceLine(parent: Instance, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local center = (from + to) / 2
	for _, height in { 2.2, 3.8 } do
		MapKit.part(parent, {
			name = "FenceRail",
			size = Vector3.new(0.4, 0.5, length),
			cframe = CFrame.lookAt(
				center + Vector3.new(0, height, 0),
				to + Vector3.new(0, height, 0)
			),
			color = Color3.fromRGB(140, 100, 64),
			material = Enum.Material.Wood,
		})
	end
	for i = 0, math.floor(length / 8) do
		local at = from:Lerp(to, math.min(i * 8 / length, 1))
		MapKit.part(parent, {
			name = "FencePost",
			size = Vector3.new(0.9, 4.6, 0.9),
			cframe = CFrame.new(at + Vector3.new(0, 2.3, 0)),
			color = Color3.fromRGB(110, 78, 50),
			material = Enum.Material.Wood,
		})
	end
end

-- A tall flag pole with a banner in a team color.
local function flagPole(parent: Instance, position: Vector3, color: Color3)
	MapKit.part(parent, {
		name = "FlagPole",
		size = Vector3.new(0.7, 18, 0.7),
		cframe = CFrame.new(position + Vector3.new(0, 9, 0)),
		color = STONE_LIGHT,
		material = Enum.Material.Metal,
	})
	MapKit.part(parent, {
		name = "FlagTop",
		shape = Enum.PartType.Ball,
		size = Vector3.new(1.4, 1.4, 1.4),
		cframe = CFrame.new(position + Vector3.new(0, 18.4, 0)),
		color = GOLD,
		material = Enum.Material.Metal,
		canCollide = false,
	})
	MapKit.part(parent, {
		name = "Flag",
		size = Vector3.new(5, 3.4, 0.2),
		cframe = CFrame.new(position + Vector3.new(2.7, 15.8, 0)),
		color = color,
		material = Enum.Material.Fabric,
		canCollide = false,
	})
end

-- A bare, dark-trunked tree (dressing from the island look): a trunk with two
-- angled branches.
local function deadTree(parent: Instance, position: Vector3, yaw: number, scale: number)
	local dark = Color3.fromRGB(58, 48, 56)
	local base = CFrame.new(position) * CFrame.Angles(0, math.rad(yaw), 0)
	MapKit.part(parent, {
		name = "DeadTrunk",
		size = Vector3.new(2.4, 14, 2.4) * scale,
		cframe = base * CFrame.new(0, 7 * scale, 0),
		color = dark,
		material = Enum.Material.Wood,
	})
	for side, tilt in { -38, 44 } do
		MapKit.part(parent, {
			name = "DeadBranch",
			size = Vector3.new(1.2, 8, 1.2) * scale,
			cframe = base
				* CFrame.new(0, (10 + side * 1.5) * scale, 0)
				* CFrame.Angles(0, 0, math.rad(tilt))
				* CFrame.new(0, 3.2 * scale, 0),
			color = dark,
			material = Enum.Material.Wood,
			canCollide = false,
		})
	end
end

-- A marble pillar leaning on its base, with a capital and a foot block.
local function leaningPillar(
	parent: Instance,
	position: Vector3,
	height: number,
	lean: number,
	yaw: number
)
	local base = CFrame.new(position) * CFrame.Angles(0, math.rad(yaw), 0)
	local tilted = base * CFrame.Angles(0, 0, math.rad(lean))
	MapKit.part(parent, {
		name = "PillarFoot",
		size = Vector3.new(9, 3, 9),
		cframe = base * CFrame.new(0, 1.5, 0),
		color = MARBLE,
		material = Enum.Material.Limestone,
	})
	MapKit.part(parent, {
		name = "LeaningPillar",
		size = Vector3.new(5.5, height, 5.5),
		cframe = tilted * CFrame.new(0, 3 + height / 2, 0),
		color = MARBLE,
		material = Enum.Material.Limestone,
	})
	MapKit.part(parent, {
		name = "PillarCap",
		size = Vector3.new(8, 2.4, 8),
		cframe = tilted * CFrame.new(0, 3 + height + 1.2, 0),
		color = MARBLE,
		material = Enum.Material.Limestone,
	})
end

-- A ruined marble arch: two posts (one broken short), a half lintel, and rubble.
local function ruinedArch(parent: Instance, position: Vector3, yaw: number)
	local frame = CFrame.new(position) * CFrame.Angles(0, math.rad(yaw), 0)
	for side, height in { 22, 14 } do
		local x = if side == 1 then -9 else 9
		MapKit.part(parent, {
			name = "RuinPost",
			size = Vector3.new(5, height, 5),
			cframe = frame * CFrame.new(x, height / 2, 0),
			color = MARBLE,
			material = Enum.Material.Limestone,
		})
	end
	MapKit.part(parent, {
		name = "RuinLintel",
		size = Vector3.new(13, 4, 5),
		cframe = frame * CFrame.new(-4.5, 24, 0),
		color = MARBLE,
		material = Enum.Material.Limestone,
	})
	for index, spot in { Vector3.new(4, 0, 6), Vector3.new(-2, 0, 8), Vector3.new(8, 0, -7) } do
		MapKit.part(parent, {
			name = "RuinRubble",
			size = Vector3.new(5 + index, 2.2, 4 + index),
			cframe = frame * CFrame.new(spot + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, index, 0),
			color = Color3.fromRGB(190, 200, 222),
			material = Enum.Material.Limestone,
		})
	end
end

-- A wooden rail around an arc of the rim between two bearings.
local function railArc(parent: Instance, from: number, to: number, step: number)
	local bearing = from
	while bearing < to do
		local nextBearing = math.min(bearing + step, to)
		fenceLine(parent, polar(bearing, RIM_RADIUS), polar(nextBearing, RIM_RADIUS))
		bearing = nextBearing
	end
end

return function(): Model
	local model = Instance.new("Model")
	model.Name = "InkwellPlaza"

	----------------------------------------------------------------------
	-- The floating island: grass top, sand beach, rock cone underneath, and
	-- the ocean far below
	----------------------------------------------------------------------
	MapKit.disc(
		model,
		Vector3.zero,
		RADIUS - 8,
		4,
		Color3.fromRGB(86, 178, 92),
		Enum.Material.Grass,
		"Grass"
	)
	MapKit.disc(
		model,
		Vector3.new(0, -0.15, 0),
		RADIUS,
		4,
		Color3.fromRGB(232, 214, 168),
		Enum.Material.Sand,
		"Beach"
	)
	MapKit.underside(model, -4, RADIUS, 150, ROCK, Enum.Material.Slate)
	-- Stalactites and glowing crystals hanging under the cone.
	local rng = MapKit.rng(42)
	for i = 1, 9 do
		local a = (i / 9) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = rng:NextNumber(20, 70)
		local length = rng:NextNumber(30, 70)
		MapKit.part(model, {
			name = "Stalactite",
			size = Vector3.new(rng:NextNumber(7, 13), length, rng:NextNumber(7, 13)),
			cframe = CFrame.new(math.cos(a) * r, -150 - length / 2 + 8, math.sin(a) * r)
				* CFrame.Angles(0, a, math.rad(rng:NextNumber(-6, 6))),
			color = ROCK,
			material = Enum.Material.Slate,
			canCollide = false,
		})
		if i % 3 == 0 then
			local crystal = MapKit.part(model, {
				name = "Crystal",
				size = Vector3.new(3, 9, 3),
				cframe = CFrame.new(math.cos(a) * r * 0.6, -150 - length, math.sin(a) * r * 0.6)
					* CFrame.Angles(math.rad(180), a, math.rad(12)),
				color = Color3.fromRGB(120, 220, 255),
				material = Enum.Material.Neon,
				canCollide = false,
			})
			glow(crystal, Color3.fromRGB(120, 220, 255), 30, 1.2)
		end
	end
	-- The ocean: a grid of big flat tiles (a part can't be wider than 2048).
	local oceanFolder = MapKit.folder(model, "Ocean")
	for ix = -1, 1 do
		for iz = -1, 1 do
			local tile = MapKit.part(oceanFolder, {
				name = "OceanTile",
				size = Vector3.new(2048, 4, 2048),
				cframe = CFrame.new(ix * 2048, Config.HUB.OCEAN_Y - 2, iz * 2048),
				color = Color3.fromRGB(38, 140, 226),
				material = Enum.Material.SmoothPlastic,
				canCollide = false,
			})
			tile.CastShadow = false
			tile.Reflectance = 0.1
		end
	end

	----------------------------------------------------------------------
	-- The centre: sand plaza, ring road, inlays, the inkwell and the statue
	----------------------------------------------------------------------
	MapKit.disc(
		model,
		Vector3.new(0, 0.1, 0),
		92,
		0.2,
		Color3.fromRGB(226, 232, 244),
		Enum.Material.Marble,
		"RingRoad"
	)
	MapKit.disc(
		model,
		Vector3.new(0, 0.14, 0),
		84,
		0.2,
		Color3.fromRGB(86, 178, 92),
		Enum.Material.Grass,
		"RingRoadInner"
	)
	-- Marble roads (same stone as the ring road) from the plaza to each
	-- destination. Trees keep clear of them.
	local roadSegments: { { Vector3 } } = {}
	local function road(from: Vector3, to: Vector3)
		local lift = Vector3.new(0, 0.1, 0)
		MapKit.part(model, {
			name = "Road",
			size = Vector3.new(ROAD_WIDTH, 0.2, (to - from).Magnitude),
			cframe = CFrame.lookAt((from + to) / 2 + lift, to + lift),
			color = Color3.fromRGB(226, 232, 244),
			material = Enum.Material.Marble,
			canCollide = false,
		})
		table.insert(roadSegments, { from, to })
	end
	local ROAD_START = PLAZA_RADIUS - 2
	local gateZ = -152
	local portalAt = polar(180, 130)
	road(polar(0, ROAD_START), Vector3.new(0, 0, gateZ + 8)) -- north: the Arena Gate
	road(polar(180, ROAD_START), portalAt - Vector3.new(0, 0, 6)) -- south: the Battleground
	for _, side in { -1, 1 } do
		-- west and east: the Training Groves
		road(
			Vector3.new(side * ROAD_START, 0, 0),
			Vector3.new(side * (GROVE_CENTER_X - GROVE_X / 2), 0, 0)
		)
	end
	road(polar(135, RING_ROAD_OUTER - 4), polar(135, 114)) -- to the Chest Shop
	road(polar(225, RING_ROAD_OUTER - 4), polar(225, 114)) -- to the pavilion

	MapKit.disc(
		model,
		Vector3.new(0, 0.4, 0),
		PLAZA_RADIUS,
		0.4,
		FLOOR,
		Enum.Material.Sand,
		"Plaza"
	)
	-- Gold and stone rings inlaid in the plaza, around the inkwell.
	for index, ring in { { 24, 0.9 }, { 19, 0.8 }, { 14, 0.7 } } do
		local inlay = MapKit.disc(
			model,
			Vector3.new(0, 0.5 + index * 0.02, 0),
			ring[1],
			0.12,
			if index == 2 then STONE_DARK else Color3.fromRGB(190, 150, 72),
			if index == 2 then Enum.Material.Limestone else Enum.Material.Metal,
			"PlazaRing"
		)
		inlay.CanCollide = false
	end

	MapKit.part(model, {
		name = "InkwellBase",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(2, 20, 20),
		cframe = CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = STONE,
		material = Enum.Material.Limestone,
	})
	MapKit.part(model, {
		name = "Inkwell",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(8, 16, 16),
		cframe = CFrame.new(0, 5, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = Color3.fromRGB(26, 20, 90),
		material = Enum.Material.Glass,
	})
	local ink = MapKit.part(model, {
		name = "InkGlow",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.3, 13, 13),
		cframe = CFrame.new(0, 9.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = GOLD_GLOW,
		material = Enum.Material.Neon,
		transparency = 0.2,
		canCollide = false,
	})
	glow(ink, GOLD_GLOW, 40, 1.6)
	-- The wizard statue stands on the inkwell: the hub's centerpiece. (Without
	-- the model, the old golden quill stands there instead.)
	local statue = ModelKit.clone("WizardStatue", "solid", STATUE_SCALE)
	if statue then
		statue:PivotTo(CFrame.new(0, 9.2, 0))
		statue.Name = "WizardStatue"
		statue.Parent = model
		label(
			signAnchor(model, "CenterSign", Vector3.new(0, 9.2 + 22 * STATUE_SCALE + 6, 0)),
			"SPELLCRAFT ARENA\nFloating Training Grounds",
			0,
			140
		)
	else
		local quill = MapKit.part(model, {
			name = "Quill",
			size = Vector3.new(1.2, 16, 3),
			cframe = CFrame.new(1.5, 17, 0) * CFrame.Angles(0, 0, math.rad(-15)),
			color = GOLD,
			material = Enum.Material.Metal,
			canCollide = false,
		})
		label(quill, "SPELLCRAFT ARENA", 15)
	end

	local spawn = MapKit.part(model, {
		name = "HubSpawn",
		size = Vector3.new(10, 1, 10),
		cframe = CFrame.new(polar(180, 28) + Vector3.new(0, 0.5, 0)),
		color = Color3.fromRGB(255, 241, 118),
		material = Enum.Material.Neon,
		transparency = 0.82,
		canCollide = false,
	})
	spawn:AddTag("HubSpawn")

	-- Torches around the plaza's edge.
	for bearing = 18, 342, 36 do
		torch(model, polar(bearing, PLAZA_RADIUS - 3))
	end

	-- Element shrines: one standing slab per element around the fountain. Each
	-- lists the element's three base spells with the shape to draw for them and
	-- its price; the prompt opens the Spellbook to pick, buy, or equip it.
	local shrineBearings = { 35, 105, 255, 325 }
	for index, element in Elements.LIST do
		local position = polar(shrineBearings[index] or index * 80, 30)
		local slab = MapKit.part(model, {
			name = `Shrine_{element.id}`,
			size = Vector3.new(13, 9.5, 1.4),
			cframe = CFrame.lookAt(position + Vector3.new(0, 5, 0), Vector3.new(0, 5, 0)),
			color = Color3.fromRGB(38, 46, 78), -- dark slate so the colored text pops
			material = Enum.Material.Concrete,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Spells"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(390, 285)
		gui.LightInfluence = 0
		gui.Parent = slab
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0, 60)
		title.Position = UDim2.fromOffset(0, 8)
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = element.color
		title.Text = string.upper(element.name)
		title.Parent = gui
		for slot, id in element.base do
			local def = SpellDefinitions.get(id)
			if def then
				local x = (slot - 1) * 128 + 4
				-- Glowing ink, like the drawing canvas and the spell sigils.
				GlyphView.glow(
					gui,
					def.glyph,
					68,
					element.color,
					slab.Color,
					{ Position = UDim2.fromOffset(x + 28, 78) }
				)
				local name = Instance.new("TextLabel")
				name.BackgroundTransparency = 1
				name.Size = UDim2.fromOffset(124, 44)
				name.Position = UDim2.fromOffset(x, 150)
				name.Font = Enum.Font.FredokaOne
				name.TextScaled = true
				name.TextWrapped = true
				name.TextColor3 = Color3.new(1, 1, 1)
				name.Text = def.name
				name.Parent = gui
			end
		end
		local hint = Instance.new("TextLabel")
		hint.BackgroundTransparency = 1
		hint.Size = UDim2.new(1, -16, 0, 40)
		hint.Position = UDim2.fromOffset(8, 220)
		hint.Font = Enum.Font.GothamMedium
		hint.TextScaled = true
		hint.TextColor3 = Color3.fromRGB(197, 202, 233)
		hint.Text = `{element.tagline}  ({element.price} coins)`
		hint.Parent = gui
		local light = MapKit.part(model, {
			name = "ShrineGem",
			shape = Enum.PartType.Ball,
			size = Vector3.new(2.6, 2.6, 2.6),
			cframe = slab.CFrame * CFrame.new(0, 6.2, 0),
			color = element.color,
			material = Enum.Material.Neon,
			canCollide = false,
		})
		glow(light, element.color, 22, 1.4)
		prompt(slab, "Spellbook", "Choose element", `{element.name} shrine`)
	end

	----------------------------------------------------------------------
	-- Kiosks on the plaza's south side
	----------------------------------------------------------------------
	-- Spellbook kiosk: the Grimoire model lying open on a lectern.
	local lecternAt = polar(150, 36)
	local lecternFrame = facingOut(lecternAt)
	local lectern = MapKit.part(model, {
		name = "SpellbookKiosk",
		size = Vector3.new(4, 4, 3),
		cframe = lecternFrame * CFrame.new(0, 2.4, 0),
		color = Color3.fromRGB(121, 85, 72),
		material = Enum.Material.Wood,
	})
	local grimoire = ModelKit.clone("Grimoire", "solid", 1.5)
	if grimoire then
		grimoire.Name = "Spellbook"
		-- Open book resting on the lectern, tilted toward the reader (+Z).
		local _, size = grimoire:GetBoundingBox()
		grimoire:PivotTo(
			lecternFrame
				* CFrame.new(0, 4.4 + size.Y / 2 + 0.2, 0)
				* CFrame.Angles(math.rad(-20), 0, 0)
		)
		grimoire.Parent = model
	else
		-- Fallback: a big purple book shape.
		MapKit.part(model, {
			name = "Spellbook",
			size = Vector3.new(5, 1.2, 3.6),
			cframe = lecternFrame * CFrame.new(0, 5.2, 0) * CFrame.Angles(math.rad(-20), 0, 0),
			color = Color3.fromRGB(96, 44, 128),
			material = Enum.Material.Fabric,
		})
	end
	label(lectern, "Spellbook", 7)
	prompt(lectern, "Spellbook", "Open", "Spellbook")

	local chestAt = polar(210, 36)
	local chestFrame = facingOut(chestAt)
	local chest = MapKit.part(model, {
		name = "DailyChest",
		size = Vector3.new(6, 4, 4),
		cframe = chestFrame * CFrame.new(0, 2.4, 0),
		color = Color3.fromRGB(255, 193, 7),
		material = Enum.Material.Wood,
	})
	-- The QuestChest block model (gold-banded wooden chest) stands on the plaza;
	-- the plain block above stays as its invisible prompt anchor (and the fallback).
	local chestModel = ModelKit.clone("QuestChest", "solid", 1.25)
	if chestModel then
		chest.Transparency = 1
		chest.CanCollide = false
		chest.CanQuery = false
		chestModel:PivotTo(chestFrame)
		chestModel.Name = "QuestChestModel"
		chestModel.Parent = model
	end
	label(chest, "Daily Quests", if chestModel then 6.5 else 5)
	prompt(chest, "Quests", "Open", "Daily Quests")

	----------------------------------------------------------------------
	-- Like & Favourite gift box (plaza, south edge): a physical thank-you
	-- for players who like and favourite the game. Holding its prompt claims the
	-- one-time coin gift (EconomyService); the client (SupportController)
	-- disables the prompt once it is claimed and counts down until it opens.
	----------------------------------------------------------------------
	local GIFT = polar(180, 40)
	local giftBase = MapKit.part(model, {
		name = "LikeGiftBox",
		size = Vector3.new(4.4, 3.2, 4.4),
		cframe = CFrame.new(GIFT + Vector3.new(0, 1.6, 0)),
		color = Color3.fromRGB(233, 30, 99),
		material = Enum.Material.SmoothPlastic,
	})
	local giftLid = MapKit.part(model, {
		name = "LikeGiftLid",
		size = Vector3.new(5, 1.1, 5),
		cframe = CFrame.new(GIFT + Vector3.new(0, 3.75, 0)),
		color = Color3.fromRGB(244, 81, 130),
		material = Enum.Material.SmoothPlastic,
	})
	for _, spec in
		{
			{ name = "RibbonA", size = Vector3.new(0.8, 4.8, 4.6) },
			{ name = "RibbonB", size = Vector3.new(4.6, 4.8, 0.8) },
		}
	do
		MapKit.part(model, {
			name = `LikeGift{spec.name}`,
			size = spec.size,
			cframe = CFrame.new(GIFT + Vector3.new(0, 2.7, 0)),
			color = GOLD,
			material = Enum.Material.Neon,
			canCollide = false,
		})
	end
	local bow = MapKit.part(model, {
		name = "LikeGiftBow",
		shape = Enum.PartType.Ball,
		size = Vector3.new(2, 2, 2),
		cframe = CFrame.new(GIFT + Vector3.new(0, 5, 0)),
		color = GOLD,
		material = Enum.Material.Neon,
		canCollide = false,
	})
	bow:AddTag("SpinFx")
	glow(giftLid, GOLD_GLOW, 16, 1.4)
	giftBase:AddTag("LikeGift")
	label(giftBase, "Like & Favourite\nthen claim a gift!", 7, 90)
	local giftPrompt = prompt(giftBase, "LikeGift", "Claim gift", "Like & Favourite gift")
	giftPrompt.HoldDuration = 1.2
	giftPrompt.MaxActivationDistance = 10

	----------------------------------------------------------------------
	-- The amphitheatre: two mirrored half-arcs of stands on the south diagonals,
	-- three tiers of white marble steps each a step up from the last. They sit
	-- between the roads, so nothing is blocked.
	----------------------------------------------------------------------
	for tier = 1, 3 do
		local radius = PLAZA_RADIUS + 1 + tier * 7
		local height = tier * 1.5
		for _, bearing in { 120, 130, 140, 150, 210, 220, 230, 240 } do
			local position = polar(bearing, radius) + Vector3.new(0, height / 2, 0)
			MapKit.part(model, {
				name = "AmphitheatreStep",
				size = Vector3.new(radius * math.rad(10) + 1, height, 7),
				cframe = facingCenter(position),
				color = if (bearing / 10 + tier) % 2 == 0 then MARBLE else STONE_LIGHT,
				material = Enum.Material.Limestone,
			})
		end
	end

	----------------------------------------------------------------------
	-- The Arena Gate (north, behind the team boxes): the same stone portal as the
	-- Battleground's, in red (the ArenaPortal block model). It also leads to the
	-- Battleground. Duels start from the team boxes and are fought on the arenas
	-- summoned below the island. Without the model, a plain red frame stands in.
	----------------------------------------------------------------------
	local gateModel = ModelKit.clone("ArenaPortal", "solid")
	local gate: BasePart
	if gateModel then
		gateModel:PivotTo(CFrame.new(0, 0, gateZ))
		gateModel.Parent = model
		gate = MapKit.part(model, {
			name = "ArenaGate",
			size = Vector3.new(22, 24, 3),
			cframe = CFrame.new(0, 13.5, gateZ),
			transparency = 1,
			canCollide = false,
		})
		gate.CanQuery = false -- spells pass through, but walking in must still trigger it
		gate.CanTouch = true
	else
		for _, side in { -1, 1 } do
			column(model, Vector3.new(side * 15, 0, gateZ), 36, 5, STONE_LIGHT)
			torch(model, Vector3.new(side * 21, 0, gateZ + 2))
		end
		MapKit.part(model, {
			name = "GateLintel",
			size = Vector3.new(38, 4, 5),
			cframe = CFrame.new(0, 38, gateZ),
			color = STONE_LIGHT,
			material = Enum.Material.Limestone,
		})
		gate = MapKit.part(model, {
			name = "ArenaGate",
			size = Vector3.new(26, 36, 1),
			cframe = CFrame.new(0, 18, gateZ - 0.5),
			color = Color3.fromRGB(230, 40, 60),
			material = Enum.Material.Neon,
			transparency = 0.25,
		})
	end
	glow(gate, Color3.fromRGB(255, 70, 90), 60, 1.6)
	gate:AddTag("BattlegroundPortal")
	label(
		signAnchor(model, "GateSign", Vector3.new(0, 44, gateZ + 4)),
		"THE ARENA GATE\nStep through to the Battleground!\n(Duels start from the team boxes)",
		0,
		300
	)

	----------------------------------------------------------------------
	-- Team boxes: stand on the Blue or Red side to pick your team. The match
	-- starts when both sides are full. The boxes sit side by side along an arc
	-- facing the centre, with the north road running between the two halves.
	----------------------------------------------------------------------
	local widths: { number } = {}
	for index, box in BOXES do
		local width = math.max(8, box.perTeam * 5.5)
		widths[index] = width * 2 + PAD_GAP + 6 -- the training mat under both sides
	end
	-- Walk outward from the road in the middle, so the arc is centered on it.
	local centers: { number } = {}
	local gapAngle = math.deg(BOX_CENTER_GAP / 2 / BOX_RADIUS)
	local edge = -gapAngle
	for index = BOX_LEFT_COUNT, 1, -1 do
		local step = math.deg((widths[index] + BOX_GAP) / BOX_RADIUS)
		centers[index] = edge - step / 2
		edge -= step
	end
	edge = gapAngle
	for index = BOX_LEFT_COUNT + 1, #BOXES do
		local step = math.deg((widths[index] + BOX_GAP) / BOX_RADIUS)
		centers[index] = edge + step / 2
		edge += step
	end
	for index, box in BOXES do
		local center = centers[index]
		local frame = facingCenter(polar(center, BOX_RADIUS))
		local width = math.max(8, box.perTeam * 5.5)
		for side, team in { "Blue", "Red" } do
			local color = if team == "Blue" then BLUE else RED
			-- Blue on the left as you walk up to the box from the centre.
			local x = (if side == 1 then 1 else -1) * (width / 2 + PAD_GAP / 2)
			local pad = MapKit.part(model, {
				name = `TeamPad_{box.id}_{team}`,
				size = Vector3.new(width, 0.6, PAD_DEPTH),
				cframe = frame * CFrame.new(x, 0.8, 0),
				color = color,
				material = Enum.Material.Neon,
				transparency = 0.35,
			})
			pad:SetAttribute("Box", box.id)
			pad:SetAttribute("Mode", box.mode)
			pad:SetAttribute("Team", team)
			pad:SetAttribute("Slots", box.perTeam)
			pad:AddTag("TeamPad")
			label(pad, `{string.upper(team)} 0/{box.perTeam}`, 5, 38)
		end
		-- A training mat under the two sides, with hay bales behind it.
		MapKit.part(model, {
			name = "TrainingMat",
			size = Vector3.new(widths[index], 0.3, PAD_DEPTH + 6),
			cframe = frame * CFrame.new(0, 0.15, 0),
			color = Color3.fromRGB(214, 196, 150),
			material = Enum.Material.Fabric,
		})
		for _, side in { -1, 1 } do
			local at = frame:PointToWorldSpace(
				Vector3.new(side * (width + PAD_GAP / 2 + 1), 0, PAD_DEPTH / 2 + 3)
			)
			hayBale(model, at, side * 12)
		end
		local header = MapKit.part(model, {
			name = `TeamBoxHeader_{box.id}`,
			size = Vector3.one,
			cframe = frame * CFrame.new(0, 8, PAD_DEPTH / 2),
			transparency = 1,
			canCollide = false,
		})
		header:SetAttribute("Box", box.id)
		header:SetAttribute("Mode", box.mode)
		header:AddTag("TeamBoxHeader")
		label(header, box.mode, 0, 70)
	end

	-- One instruction sign instead of repeating it over every box.
	label(
		signAnchor(model, "TeamBoxSign", polar(0, 70) + Vector3.new(0, 9, 0)),
		"Pick your team: stand on a Blue or Red side.\nThe match starts when both sides are full.",
		0,
		60
	)

	----------------------------------------------------------------------
	-- The Battleground portal (south, at the end of the south road): a big stone
	-- gateway (the BattlegroundPortal block model) with a swirling blue portal in
	-- it. Walking into the invisible trigger over the opening teleports you to
	-- the drop-in free-for-all (BattlegroundService). Without the model, a plain
	-- blue arch and glowing disc stand in.
	----------------------------------------------------------------------
	local portalModel = ModelKit.clone("BattlegroundPortal", "solid")
	local portal: BasePart
	if portalModel then
		portalModel:PivotTo(CFrame.new(portalAt))
		portalModel.Parent = model
		-- The opening is about 24 studs wide and 26 tall.
		portal = MapKit.part(model, {
			name = "BattlegroundPortal",
			size = Vector3.new(22, 24, 3),
			cframe = CFrame.new(portalAt + Vector3.new(0, 13.5, 0)),
			transparency = 1,
			canCollide = false,
		})
		portal.CanQuery = false -- spells pass through, but walking in must still trigger it
		portal.CanTouch = true
		glow(portal, BLUE, 60, 1.6)
	else
		for _, side in { -1, 1 } do
			column(model, portalAt + Vector3.new(side * 9, 0, 0), 14, 2.4, BLUE)
		end
		pointedArch(model, CFrame.new(portalAt), 18, 14, 1.2, BLUE)
		portal = MapKit.part(model, {
			name = "BattlegroundPortal",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.8, 12, 12),
			cframe = CFrame.new(portalAt + Vector3.new(0, 0.9, 0))
				* CFrame.Angles(0, 0, math.pi / 2),
			color = Color3.fromRGB(80, 160, 255),
			material = Enum.Material.Neon,
			transparency = 0.2,
			canCollide = false,
		})
		glow(portal, BLUE, 24, 1.2)
	end
	portal:AddTag("BattlegroundPortal")
	label(portal, "BATTLEGROUND\nStep in to fight!", if portalModel then 17 else 6, 70)
	label(
		signAnchor(model, "BattlegroundSign", portalAt + Vector3.new(0, 40, 0)),
		"BATTLEGROUND",
		0,
		200
	)

	----------------------------------------------------------------------
	-- Training Groves (west and east, mirrored): build anything, smash dummies.
	-- `side` is -1 for the west grove and 1 for the east. Positions inside are
	-- (u, z): u studs in from the grove's outer edge toward the plaza.
	----------------------------------------------------------------------
	local function buildGrove(side: number)
		local dir = -side -- X direction pointing from the outer edge to the plaza
		local center = Vector3.new(side * GROVE_CENTER_X, 0, 0)
		local outerX = center.X + side * GROVE_X / 2
		local function at(u: number, z: number): Vector3
			return Vector3.new(outerX + dir * u, 0, z)
		end
		local grove = MapKit.part(model, {
			name = "PracticeGrove",
			size = Vector3.new(GROVE_X, 40, GROVE_Z),
			cframe = CFrame.new(center.X, 18, center.Z),
			transparency = 1,
			canCollide = false,
		})
		grove.CanQuery = false
		grove.CanTouch = false
		grove:AddTag("BuildZone")
		-- Drawing and casting work here (shared/Util/PracticeZone).
		grove:AddTag("PracticeZone")
		MapKit.part(model, {
			name = "GroveFloor",
			size = Vector3.new(GROVE_X, 0.4, GROVE_Z),
			cframe = CFrame.new(center.X, 0.2, center.Z),
			color = Color3.fromRGB(196, 170, 122),
			material = Enum.Material.Sand,
		})
		local north, south = -GROVE_Z / 2, GROVE_Z / 2
		-- Corner columns with torches.
		for _, corner in
			{
				Vector3.new(-1, 0, -1),
				Vector3.new(1, 0, -1),
				Vector3.new(-1, 0, 1),
				Vector3.new(1, 0, 1),
			}
		do
			local base = center
				+ Vector3.new(corner.X * (GROVE_X / 2 - 2), 0, corner.Z * (GROVE_Z / 2 - 2))
			column(model, base, 12, 2.6, STONE_LIGHT)
			torch(model, base + Vector3.new(-corner.X * 3, 0, -corner.Z * 3))
		end
		-- A wooden training fence on the outer, north, and south sides (the side
		-- facing the plaza stays open).
		fenceLine(model, at(0, north), at(0, south))
		fenceLine(model, at(0, north), at(GROVE_X - 6, north))
		fenceLine(model, at(0, south), at(GROVE_X - 6, south))
		label(
			signAnchor(model, "GroveSign", at(GROVE_X - 3, 0) + Vector3.new(0, 11, 0)),
			"TRAINING GROVE\nDraw and cast spells here!",
			0,
			140
		)
		-- Dummies in a single row, all facing the plaza, with archery
		-- targets behind them and hay bales along the fences.
		local faceYaw = if dir > 0 then -math.pi / 2 else math.pi / 2
		local function dummySpot(u: number, z: number)
			local spot = MapKit.part(model, {
				name = "DummySpot",
				size = Vector3.new(2, 0.2, 2),
				cframe = CFrame.new(at(u, z) + Vector3.new(0, 0.1, 0)),
				transparency = 1,
				canCollide = false,
			})
			spot:SetAttribute("FaceYaw", faceYaw)
			spot:AddTag("DummySpot")
		end
		for i = 1, 7 do
			dummySpot(40, north + 8 + (i - 1) * 16)
		end
		for i = 1, 5 do
			targetStand(model, at(3, north + 12 + (i - 1) * 22), dir)
		end
		for i = 1, 5 do
			hayBale(model, at(GROVE_X - 14 - (i - 1) * 16, north + 4), i * 17)
			hayBale(model, at(GROVE_X - 14 - (i - 1) * 16, south - 4), i * 31)
		end
	end
	buildGrove(-1)
	buildGrove(1)

	----------------------------------------------------------------------
	-- Chest Shop (south-east, outside the ring road): the five chests, Common to
	-- Legendary, in a row on a stage facing the plaza, each banded and lit in
	-- its rarity's colour with its price above it. A chest's prompt opens the
	-- shop panel with that chest picked (ChestController reads its ChestId).
	----------------------------------------------------------------------
	local SHOP = polar(135, 122)
	local shopFrame = facingCenter(SHOP)
	MapKit.part(model, {
		name = "ChestStage",
		size = Vector3.new(36, 1, 10),
		cframe = shopFrame * CFrame.new(0, 0.5, 0),
		color = Color3.fromRGB(69, 39, 160),
		material = Enum.Material.SmoothPlastic,
	})
	pointedArch(model, shopFrame * CFrame.new(0, 1, 6), 38, 12, 1.4, STONE_LIGHT)
	label(
		signAnchor(model, "ChestShopSign", shopFrame:PointToWorldSpace(Vector3.new(0, 15, 3))),
		"Chest Shop\nOpen chests for new spells!",
		0,
		90
	)
	for index, shopChest in Chests.LIST do
		local color = Chests.color(shopChest.id)
		local spot = shopFrame * CFrame.new((index - 3) * 6.8, 1, 0)
		local holder = MapKit.part(model, {
			name = `Chest_{shopChest.id}`,
			size = Vector3.new(4.6, 4, 3.2),
			cframe = spot * CFrame.new(0, 2, 0),
			color = color,
			material = Enum.Material.WoodPlanks,
		})
		local shopModel = ModelKit.clone("ShopChest", "solid")
		if shopModel then
			-- The model replaces the block; its bands and gem take the rarity colour.
			holder.Transparency = 1
			holder.CanCollide = false
			local _, size = shopModel:GetBoundingBox()
			shopModel:ScaleTo(4.8 / math.max(size.X, 0.01))
			-- Standing on the stage, lid hinge at the back, facing the plaza.
			shopModel:PivotTo(spot)
			for _, part in shopModel:GetDescendants() do
				if
					part:IsA("BasePart") and (part.Name == "Chest_Trim" or part.Name == "Chest_Gem")
				then
					part.Color = color
				end
			end
			shopModel.Name = `ChestModel_{shopChest.id}`
			shopModel.Parent = model
		end
		-- Rarer chests glow brighter.
		glow(holder, color, 10 + index * 2, 0.6 + index * 0.25)
		local priceTag = label(holder, `{shopChest.name}\n{shopChest.price} coins`, 4.5, 60)
		priceTag.TextColor3 = color
		local open = prompt(holder, "Chests", "Open shop", shopChest.name)
		open:SetAttribute("ChestId", shopChest.id)
	end

	----------------------------------------------------------------------
	-- Pavilion (south-west): the Chest Shop's mirror twin, so the hub balances.
	-- A quiet dais under a marble arch, lit by torches.
	----------------------------------------------------------------------
	local pavilionFrame = facingCenter(polar(225, 122))
	MapKit.part(model, {
		name = "PavilionDais",
		size = Vector3.new(34, 1, 10),
		cframe = pavilionFrame * CFrame.new(0, 0.5, 0),
		color = STONE,
		material = Enum.Material.Limestone,
	})
	pointedArch(model, pavilionFrame * CFrame.new(0, 1, 6), 36, 12, 1.4, STONE_LIGHT)
	for _, side in { -1, 1 } do
		torch(model, pavilionFrame:PointToWorldSpace(Vector3.new(side * 14, 1, -3)))
	end

	----------------------------------------------------------------------
	-- Hall of Champions (north of the plaza): winners' podium on the left, the
	-- Most Wins board on the right. Gold in the middle (highest), silver on
	-- its left, bronze on its right, all facing the centre. Each pedestal's front
	-- face shows its rank, name and wins (LeaderboardService writes the "Text"
	-- label and stands the avatars on top, facing the centre).
	----------------------------------------------------------------------
	local podiumFrame = facingCenter(polar(335, 64))
	for rank, spec in
		{
			{ x = 0, height = 6, color = Color3.fromRGB(255, 202, 40) },
			{ x = -9, height = 4.5, color = Color3.fromRGB(207, 216, 220) },
			{ x = 9, height = 3, color = Color3.fromRGB(205, 127, 50) },
		}
	do
		local pedestal = MapKit.part(model, {
			name = `Podium_{rank}`,
			size = Vector3.new(8, spec.height, 7),
			cframe = podiumFrame * CFrame.new(spec.x, spec.height / 2, 0),
			color = spec.color,
			material = Enum.Material.Marble,
		})
		pedestal:SetAttribute("Rank", rank)
		pedestal:AddTag("PodiumSpot")
		local surface = Instance.new("SurfaceGui")
		surface.Name = "Plate"
		surface.Face = Enum.NormalId.Front -- faces the centre
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 40
		surface.Parent = pedestal
		local plate = Instance.new("TextLabel")
		plate.Name = "Text"
		plate.Size = UDim2.fromScale(0.9, 0.9)
		plate.Position = UDim2.fromScale(0.05, 0.05)
		plate.BackgroundTransparency = 1
		plate.Font = Enum.Font.FredokaOne
		plate.TextScaled = true
		plate.TextColor3 = Color3.fromRGB(38, 50, 56)
		plate.Text = `#{rank}\nWin a match to stand here!`
		plate.Parent = surface
	end
	-- Wins board, on the other side of the north approach, facing the centre.
	local boardFrame = facingCenter(polar(25, 64))
	local board = MapKit.part(model, {
		name = "Leaderboard",
		size = Vector3.new(16, 14, 1),
		cframe = boardFrame * CFrame.new(0, 9, 0),
		color = Color3.fromRGB(30, 26, 56),
	})
	board:AddTag("WinsBoard")
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Board"
	surface.Face = Enum.NormalId.Front -- faces the centre
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 30
	surface.Parent = board
	local boardText = Instance.new("TextLabel")
	boardText.Name = "Text"
	boardText.Size = UDim2.fromScale(1, 1)
	boardText.BackgroundTransparency = 1
	boardText.Font = Enum.Font.FredokaOne
	boardText.TextScaled = true
	boardText.TextColor3 = Color3.new(1, 1, 1)
	boardText.Text = "Most Wins\n(win a match!)"
	boardText.Parent = surface
	for _, side in { -1, 1 } do
		MapKit.part(model, {
			name = "BoardPost",
			size = Vector3.new(1.2, 10, 1.2),
			cframe = boardFrame * CFrame.new(side * 7, 5, 0.6),
			color = STONE_DARK,
			material = Enum.Material.Limestone,
		})
	end

	----------------------------------------------------------------------
	-- The rim: a wooden rail, four SPECTATE overlooks, flags, and scenery
	----------------------------------------------------------------------
	railArc(model, 0, 360, 6)
	for index, bearing in { 45, 135, 225, 315 } do
		local at = polar(bearing, RIM_RADIUS - 8)
		MapKit.disc(
			model,
			at + Vector3.new(0, 0.3, 0),
			9,
			0.4,
			MARBLE,
			Enum.Material.Limestone,
			"Overlook"
		)
		label(
			signAnchor(model, `SpectateSign_{index}`, at + Vector3.new(0, 10, 0)),
			"SPECTATE\nLook down: duels are fought on the arenas below!",
			0,
			160
		)
	end

	local flagColors = { Color3.fromRGB(66, 165, 245), Color3.fromRGB(239, 83, 80) }
	for index = 1, 12 do
		flagPole(model, polar(index * 30 + 15, 78), flagColors[(index % 2) + 1])
	end

	-- Leaning marble pillars, a ruined arch, a few crates and bare trees.
	leaningPillar(model, polar(50, 150), 34, 11, 20)
	leaningPillar(model, polar(300, 150), 38, -9, 60)
	leaningPillar(model, polar(160, 120), 30, 8, 100)
	ruinedArch(model, polar(200, 152), 200)
	for index, offset in { Vector3.new(0, 0, 0), Vector3.new(5, 0, 1), Vector3.new(2, 4, 0) } do
		MapKit.part(model, {
			name = "Crate",
			size = Vector3.new(5, 4, 5),
			cframe = CFrame.new(polar(118, 150) + offset + Vector3.new(0, 2, 0))
				* CFrame.Angles(0, index * 0.5, 0),
			color = Color3.fromRGB(70, 56, 56),
			material = Enum.Material.WoodPlanks,
		})
	end
	for index, spec in
		{
			{ 62, 152 },
			{ 250, 140 },
			{ 330, 135 },
			{ 20, 130 },
			{ 150, 150 },
		}
	do
		deadTree(model, polar(spec[1], spec[2]), index * 47, 1.1)
	end

	-- Block-model trees (oak, birch, pine) scattered on the outer meadow, kept
	-- clear of the buildings (grove, shop, gate, portal) and the duel ring.
	local keepClear: { { center: Vector3, radius: number } } = {
		{ center = Vector3.new(-GROVE_CENTER_X, 0, 0), radius = 80 },
		{ center = Vector3.new(GROVE_CENTER_X, 0, 0), radius = 80 },
		{ center = SHOP, radius = 32 },
		{ center = polar(225, 122), radius = 32 },
		{ center = polar(180, 130), radius = 24 },
		{ center = polar(0, 150), radius = 34 },
	}
	local placed = 0
	for _ = 1, 160 do
		if placed >= 28 then
			break
		end
		local bearing = rng:NextNumber(0, 360)
		local radius = rng:NextNumber(112, RIM_RADIUS - 8)
		local pos = polar(bearing, radius)
		local blocked = false
		for _, zone in keepClear do
			if (pos - zone.center).Magnitude < zone.radius then
				blocked = true
			end
		end
		-- The duel ring's arc occupies the north out to about r = 130.
		if (bearing < 75 or bearing > 285) and radius < 132 then
			blocked = true
		end
		-- ...and the roads stay clear.
		for _, segment in roadSegments do
			local from, to = segment[1], segment[2]
			local along = to - from
			local t = math.clamp((pos - from):Dot(along) / along:Dot(along), 0, 1)
			if (pos - (from + along * t)).Magnitude < ROAD_WIDTH then
				blocked = true
			end
		end
		if not blocked then
			placed += 1
			MapKit.tree(model, pos, rng:NextNumber(1.1, 1.5), rng)
		end
	end

	-- Invisible walls just inside the rim so nobody walks off the island.
	-- Spells pass through them (CanQuery off).
	MapKit.barrierRing(model, RADIUS - 4, 100)

	return model
end
