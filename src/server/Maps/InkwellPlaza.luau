--!strict
-- Inkwell Plaza — the central hub, a sunlit sandstone arena: a round sand
-- plaza with a grandstand behind it that opens into the Champions' Concourse.
-- Everything is on one axis so players always know where to go (north is -Z):
--
--   Spawn plaza (round, inkwell fountain, 4 element shrines that list what to
--   draw for each spell) ── kiosks on the south arc (Spellbook, Daily Quests)
--   ├─ west: Spell Practice pavilion (dummies, build anything)
--   ├─ east: Crate Shop stage
--   └─ north: the Concourse — pointed-arch bays with sky-glass windows
--        and glyph banners, a red carpet, the team boxes (1v1..4v4), the
--        Battleground portal, and the red Arena Gate at the far end. The winners'
--        podium and the Most Wins board stand at its entrance.
--
-- Tags/attributes HubService relies on:
--   TeamPad   (Mode, Team, Slots)   one side of a team box: players stand on
--                                   a side to pick their team (1v1..4v4)
--   BattlegroundPortal              step on to be teleported to the Battleground
--                                   (BattlegroundService)
--   BuildZone                       placing objects allowed here
--   DummySpot                       training dummies respawn here
--   HubSpawn                        where players appear
--   WinsBoard                       LeaderboardService writes the top wins
--   PodiumSpot (Rank 1-3)           LeaderboardService stands the top-3
--                                   players' avatars on these pedestals
--   ProximityPrompts named "Spellbook", "Quests" and "Crates" open UI on
--   the client (MenuController / CrateController)
--
-- The spellbook kiosk uses the imported Grimoire model and the crate shop
-- the Crate model (ReplicatedStorage.Models via ModelKit), with plain-shape
-- fallbacks when the place doesn't have them. The warm afternoon light is the
-- client's LightingController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crates = require(ReplicatedStorage.Shared.Economy.Crates)
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
local CARPET = Color3.fromRGB(160, 36, 40)
local GOLD = Color3.fromRGB(255, 202, 40)
local SKY_GLASS = Color3.fromRGB(140, 200, 255)
local GOLD_GLOW = Color3.fromRGB(255, 210, 90)

-- Layout (studs). North is -Z.
local PLAZA = Vector3.new(0, 0, 38) -- center of the spawn plaza
local PLAZA_RADIUS = 46
local HALL_HALF_WIDTH = 40 -- the walls stand at x = ±HALL_HALF_WIDTH
local HALL_START = -4 -- z of the hall entrance
local HALL_END = -190 -- z of the Arena Gate
local WALL_HEIGHT = 26
local BAY = 20 -- spacing of the arches along the walls

-- Team boxes: {mode, players per team, center x, center z}. Each box is two
-- side-by-side pads, Blue then Red, one spot per teammate. Their open front
-- faces the spawn (+Z).
local BOXES = {
	{ mode = "1v1", perTeam = 1, x = -27, z = -62 },
	{ mode = "2v2", perTeam = 2, x = 22, z = -62 },
	{ mode = "3v3", perTeam = 3, x = -19, z = -112 },
	{ mode = "4v4", perTeam = 4, x = 0, z = -152 },
}
local PAD_DEPTH = 8
local PAD_GAP = 2

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

local function prompt(parent: BasePart, name: string, action: string, objectText: string)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = objectText
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = parent
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
		cframe = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
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

-- A sky-blue glass diamond window set into a wall; `frame` faces out of the
-- wall (local -Z is the way the window looks).
local function runeWindow(parent: Instance, frame: CFrame, size: number)
	MapKit.part(parent, {
		name = "ArenaWindow",
		size = Vector3.new(size, size, 0.6),
		cframe = frame * CFrame.Angles(0, 0, math.pi / 4),
		color = SKY_GLASS,
		material = Enum.Material.Glass,
		transparency = 0.25,
		canCollide = false,
	})
	for _, cross in {
		Vector3.new(size * 0.07, size * 0.9, 0.8),
		Vector3.new(size * 0.9, size * 0.07, 0.8),
	} do
		MapKit.part(parent, {
			name = "WindowBar",
			size = cross,
			cframe = frame,
			color = GOLD,
			material = Enum.Material.Metal,
			canCollide = false,
		})
	end
end

-- A hanging cloth banner showing a spell's glyph.
local function glyphBanner(parent: Instance, frame: CFrame, spellIndex: number)
	local def = SpellDefinitions.list[((spellIndex - 1) % #SpellDefinitions.list) + 1]
	local cloth = MapKit.part(parent, {
		name = "GlyphBanner",
		size = Vector3.new(6, 10, 0.4),
		cframe = frame,
		color = Color3.fromRGB(34, 48, 104),
		material = Enum.Material.Fabric,
		canCollide = false,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Glyph"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(120, 200)
	gui.LightInfluence = 0
	gui.Parent = cloth
	GlyphView.create(gui, def.glyph, 96, Elements.color(def.element), { Position = UDim2.fromOffset(12, 20) })
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 36)
	name.Position = UDim2.fromOffset(0, 130)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextColor3 = Elements.color(def.element)
	name.Text = def.name
	name.Parent = gui
	MapKit.part(parent, {
		name = "BannerRod",
		size = Vector3.new(7, 0.5, 0.6),
		cframe = frame * CFrame.new(0, 5.1, 0),
		color = GOLD,
		material = Enum.Material.Metal,
		canCollide = false,
	})
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

return function(): Model
	local model = Instance.new("Model")
	model.Name = "InkwellPlaza"

	----------------------------------------------------------------------
	-- Ground: dark meadow, the round plaza, and the hall floor
	----------------------------------------------------------------------
	MapKit.part(model, {
		name = "Grass",
		size = Vector3.new(340, 4, 340),
		cframe = CFrame.new(0, -2, -40),
		color = Color3.fromRGB(98, 168, 74),
		material = Enum.Material.Grass,
	})
	MapKit.part(model, {
		name = "Plaza",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.4, PLAZA_RADIUS * 2, PLAZA_RADIUS * 2),
		cframe = CFrame.new(PLAZA.X, 0.2, PLAZA.Z) * CFrame.Angles(0, 0, math.pi / 2),
		color = FLOOR,
		material = Enum.Material.Sand,
	})
	-- Gold and stone rings inlaid in the arena floor, around the inkwell.
	for index, ring in { { 24, 0.9 }, { 19, 0.8 }, { 14, 0.7 } } do
		MapKit.part(model, {
			name = "PlazaRing",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.12, ring[1] * 2, ring[1] * 2),
			cframe = CFrame.new(PLAZA.X, 0.42 + index * 0.02, PLAZA.Z) * CFrame.Angles(0, 0, math.pi / 2),
			color = if index == 2 then STONE_DARK else Color3.fromRGB(190, 150, 72),
			material = if index == 2 then Enum.Material.Limestone else Enum.Material.Metal,
			transparency = 0,
			canCollide = false,
		})
	end
	local hallLength = math.abs(HALL_END - HALL_START) + 14
	MapKit.part(model, {
		name = "HallFloor",
		size = Vector3.new(HALL_HALF_WIDTH * 2 + 4, 0.4, hallLength),
		cframe = CFrame.new(0, 0.2, HALL_START + 10 - hallLength / 2),
		color = FLOOR,
		material = Enum.Material.Sandstone,
	})
	MapKit.part(model, {
		name = "HallInlay",
		size = Vector3.new(HALL_HALF_WIDTH * 2 - 10, 0.1, hallLength - 12),
		cframe = CFrame.new(0, 0.42, HALL_START + 10 - hallLength / 2),
		color = STONE_DARK,
		material = Enum.Material.Limestone,
		canCollide = false,
	})
	MapKit.part(model, {
		name = "Carpet",
		size = Vector3.new(9, 0.1, math.abs(HALL_END - HALL_START) - 8),
		cframe = CFrame.new(0, 0.5, (HALL_START + HALL_END) / 2),
		color = CARPET,
		material = Enum.Material.Fabric,
		canCollide = false,
	})
	for _, side in { -1, 1 } do
		MapKit.part(model, {
			name = "CarpetTrim",
			size = Vector3.new(0.6, 0.12, math.abs(HALL_END - HALL_START) - 8),
			cframe = CFrame.new(side * 4.8, 0.52, (HALL_START + HALL_END) / 2),
			color = GOLD,
			material = Enum.Material.Metal,
			canCollide = false,
		})
	end

	-- Low wall around the whole hub so nobody wanders off into the dark.
	MapKit.ring(model, Vector3.new(0, 0, -40), 168, 8, STONE_DARK)
	for _, wall in model:GetChildren() do
		if wall.Name == "RingWall" and wall:IsA("BasePart") then
			wall.Name = "OuterWall"
			wall.Material = Enum.Material.Limestone
			wall.Transparency = 0
		end
	end

	----------------------------------------------------------------------
	-- The inkwell fountain
	----------------------------------------------------------------------
	MapKit.part(model, {
		name = "InkwellBase",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(2, 20, 20),
		cframe = CFrame.new(PLAZA.X, 1, PLAZA.Z) * CFrame.Angles(0, 0, math.pi / 2),
		color = STONE,
		material = Enum.Material.Limestone,
	})
	MapKit.part(model, {
		name = "Inkwell",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(8, 16, 16),
		cframe = CFrame.new(PLAZA.X, 5, PLAZA.Z) * CFrame.Angles(0, 0, math.pi / 2),
		color = Color3.fromRGB(26, 20, 90),
		material = Enum.Material.Glass,
	})
	local ink = MapKit.part(model, {
		name = "InkGlow",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.3, 13, 13),
		cframe = CFrame.new(PLAZA.X, 9.1, PLAZA.Z) * CFrame.Angles(0, 0, math.pi / 2),
		color = GOLD_GLOW,
		material = Enum.Material.Neon,
		transparency = 0.2,
		canCollide = false,
	})
	glow(ink, GOLD_GLOW, 40, 1.6)
	local quill = MapKit.part(model, {
		name = "Quill",
		size = Vector3.new(1.2, 16, 3),
		cframe = CFrame.new(PLAZA.X + 1.5, 17, PLAZA.Z) * CFrame.Angles(0, 0, math.rad(-15)),
		color = GOLD,
		material = Enum.Material.Metal,
		canCollide = false,
	})
	label(quill, "SPELLCRAFT ARENA", 15)

	local spawn = MapKit.part(model, {
		name = "HubSpawn",
		size = Vector3.new(10, 1, 10),
		cframe = CFrame.new(0, 0.5, 58),
		color = Color3.fromRGB(255, 241, 118),
		material = Enum.Material.Neon,
		transparency = 0.82,
		canCollide = false,
	})
	spawn:AddTag("HubSpawn")

	-- Element shrines: one standing slab per element around the fountain. Each
	-- lists the element's five spells with the shape to draw for them; the
	-- prompt opens the Spellbook to pick or equip it.
	for index, element in Elements.LIST do
		local angle = math.rad(55 + (index - 1) * 70 + (if index > 2 then 20 else 0))
		local position = PLAZA + Vector3.new(math.sin(angle) * 29, 0, math.cos(angle) * 29)
		local slab = MapKit.part(model, {
			name = `Shrine_{element.id}`,
			size = Vector3.new(13, 9.5, 1.4),
			cframe = CFrame.lookAt(position + Vector3.new(0, 5, 0), PLAZA + Vector3.new(0, 5, 0)),
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
		title.Text = `{element.icon} {string.upper(element.name)}`
		title.Parent = gui
		for slot, id in element.spells do
			local def = SpellDefinitions.get(id)
			if def then
				local x = (slot - 1) * 76 + 6
				GlyphView.create(gui, def.glyph, 64, element.color, { Position = UDim2.fromOffset(x + 2, 80) })
				local name = Instance.new("TextLabel")
				name.BackgroundTransparency = 1
				name.Size = UDim2.fromOffset(74, 44)
				name.Position = UDim2.fromOffset(x, 150)
				name.Font = Enum.Font.FredokaOne
				name.TextScaled = true
				name.TextWrapped = true
				name.TextColor3 = if def.ultimate then GOLD else Color3.new(1, 1, 1)
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
		hint.Text = element.tagline
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
	-- The Great Hall: walls, arched bays with rune windows, banners, ribs
	----------------------------------------------------------------------
	local wallLength = math.abs(HALL_END - HALL_START)
	for _, side in { -1, 1 } do
		MapKit.part(model, {
			name = "HallWall",
			size = Vector3.new(4, WALL_HEIGHT, wallLength),
			cframe = CFrame.new(side * (HALL_HALF_WIDTH + 2), WALL_HEIGHT / 2, (HALL_START + HALL_END) / 2),
			color = STONE,
			material = Enum.Material.Sandstone,
		})
		MapKit.part(model, {
			name = "WallCap",
			size = Vector3.new(6, 2, wallLength + 2),
			cframe = CFrame.new(
				side * (HALL_HALF_WIDTH + 2),
				WALL_HEIGHT + 1,
				(HALL_START + HALL_END) / 2
			),
			color = STONE_LIGHT,
			material = Enum.Material.Limestone,
		})
		-- Arched bays: frame, window, banner. The arch looks into the hall.
		local innerX = side * (HALL_HALF_WIDTH - 0.6)
		local facing = if side < 0 then -math.pi / 2 else math.pi / 2
		local bayIndex = 0
		for z = HALL_START - BAY, HALL_END + BAY, -BAY do
			bayIndex += 1
			local frame = CFrame.new(innerX, 0, z) * CFrame.Angles(0, math.pi / 2, 0)
			pointedArch(model, frame, 15, 15, 1.4, STONE_LIGHT)
			runeWindow(model, CFrame.new(innerX, 17.5, z) * CFrame.Angles(0, facing, 0), 8)
			glyphBanner(
				model,
				CFrame.new(innerX, 7, z) * CFrame.Angles(0, facing, 0),
				bayIndex + (if side < 0 then 0 else 4)
			)
			-- Buttress between bays.
			column(model, Vector3.new(innerX, 0, z - BAY / 2), WALL_HEIGHT - 2, 2.6, STONE_LIGHT)
		end
		-- Torches along the foot of the walls.
		for z = HALL_START - 30, HALL_END + 20, -40 do
			torch(model, Vector3.new(side * (HALL_HALF_WIDTH - 3), 0, z))
		end
	end
	-- Closing wall behind the Arena Gate.
	MapKit.part(model, {
		name = "HallEndWall",
		size = Vector3.new(HALL_HALF_WIDTH * 2 + 8, WALL_HEIGHT + 6, 4),
		cframe = CFrame.new(0, (WALL_HEIGHT + 6) / 2, HALL_END - 2),
		color = STONE,
		material = Enum.Material.Sandstone,
	})
	-- Big pointed ribs across the hall, high overhead (no collision).
	for _, z in { -34, -92, -150 } do
		local left = Vector3.new(-HALL_HALF_WIDTH - 1, WALL_HEIGHT, z)
		local right = Vector3.new(HALL_HALF_WIDTH + 1, WALL_HEIGHT, z)
		local apex = Vector3.new(0, WALL_HEIGHT + 22, z)
		beam(model, left, apex, 2.2, STONE_LIGHT)
		beam(model, right, apex, 2.2, STONE_LIGHT)
		local lantern = MapKit.part(model, {
			name = "HangingLantern",
			shape = Enum.PartType.Ball,
			size = Vector3.new(3, 3, 3),
			cframe = CFrame.new(0, WALL_HEIGHT + 8, z),
			color = GOLD_GLOW,
			material = Enum.Material.Neon,
			canCollide = false,
		})
		glow(lantern, GOLD_GLOW, 44, 1.4)
		MapKit.part(model, {
			name = "LanternChain",
			size = Vector3.new(0.3, 14, 0.3),
			cframe = CFrame.new(0, WALL_HEIGHT + 15.5, z),
			color = Color3.fromRGB(40, 36, 60),
			material = Enum.Material.Metal,
			canCollide = false,
		})
	end

	-- Entrance pylons and a floating welcome sign.
	for _, side in { -1, 1 } do
		MapKit.part(model, {
			name = "EntrancePylon",
			size = Vector3.new(7, WALL_HEIGHT + 8, 7),
			cframe = CFrame.new(side * (HALL_HALF_WIDTH + 2), (WALL_HEIGHT + 8) / 2, HALL_START + 3),
			color = STONE_LIGHT,
			material = Enum.Material.Limestone,
		})
		local orb = MapKit.part(model, {
			name = "PylonOrb",
			shape = Enum.PartType.Ball,
			size = Vector3.new(4, 4, 4),
			cframe = CFrame.new(side * (HALL_HALF_WIDTH + 2), WALL_HEIGHT + 11, HALL_START + 3),
			color = GOLD_GLOW,
			material = Enum.Material.Neon,
			canCollide = false,
		})
		glow(orb, GOLD_GLOW, 36, 1.4)
	end
	label(signAnchor(model, "HallSign", Vector3.new(0, 36, HALL_START + 3)), "THE ARENA\nChampions' Concourse", 0, 260)

	----------------------------------------------------------------------
	-- The Arena Gate (end of the hall): a red portal frame
	----------------------------------------------------------------------
	local gateZ = HALL_END + 2
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
	local portal = MapKit.part(model, {
		name = "ArenaGate",
		size = Vector3.new(26, 36, 1),
		cframe = CFrame.new(0, 18, gateZ - 0.5),
		color = Color3.fromRGB(230, 40, 60),
		material = Enum.Material.Neon,
		transparency = 0.25,
	})
	glow(portal, Color3.fromRGB(255, 70, 90), 60, 1.6)
	for i = 1, 3 do
		MapKit.part(model, {
			name = "GateRing",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.4, 6 + i * 6, 6 + i * 6),
			cframe = CFrame.new(0, 18, gateZ + 0.4 + i * 0.05) * CFrame.Angles(0, math.pi / 2, 0),
			color = Color3.fromRGB(255, 120, 130),
			material = Enum.Material.Neon,
			transparency = 0.4 + i * 0.1,
			canCollide = false,
		})
	end
	label(
		signAnchor(model, "GateSign", Vector3.new(0, 44, gateZ + 4)),
		"THE ARENA GATE\nPick a team box to duel!",
		0,
		260
	)

	----------------------------------------------------------------------
	-- Team boxes: stand on the Blue or Red side to pick your team. The match
	-- starts when both sides are full.
	----------------------------------------------------------------------
	for _, box in BOXES do
		local width = math.max(8, box.perTeam * 5.5)
		for side, team in { "Blue", "Red" } do
			local color = if team == "Blue" then BLUE else RED
			local x = box.x + (if side == 1 then -1 else 1) * (width / 2 + PAD_GAP / 2)
			local pad = MapKit.part(model, {
				name = `TeamPad_{box.mode}_{team}`,
				size = Vector3.new(width, 0.6, PAD_DEPTH),
				cframe = CFrame.new(x, 0.8, box.z),
				color = color,
				material = Enum.Material.Neon,
				transparency = 0.35,
			})
			pad:SetAttribute("Mode", box.mode)
			pad:SetAttribute("Team", team)
			pad:SetAttribute("Slots", box.perTeam)
			pad:AddTag("TeamPad")
			label(pad, `{string.upper(team)} 0/{box.perTeam}`, 5, 38)
			-- Low glass walls on the back and sides; the front stays open.
			for _, wall in
				{
					{
						size = Vector3.new(width, 3, 0.6),
						offset = Vector3.new(0, 2.1, -PAD_DEPTH / 2),
					},
					{
						size = Vector3.new(0.6, 3, PAD_DEPTH),
						offset = Vector3.new(-width / 2, 2.1, 0),
					},
					{
						size = Vector3.new(0.6, 3, PAD_DEPTH),
						offset = Vector3.new(width / 2, 2.1, 0),
					},
				}
			do
				MapKit.part(model, {
					name = "TeamBoxWall",
					size = wall.size,
					cframe = CFrame.new(Vector3.new(x, 0, box.z) + wall.offset),
					color = color,
					material = Enum.Material.Glass,
					transparency = 0.6,
				})
			end
		end
		local header = MapKit.part(model, {
			name = `TeamBoxHeader_{box.mode}`,
			size = Vector3.one,
			cframe = CFrame.new(box.x, 8, box.z - PAD_DEPTH / 2),
			transparency = 1,
			canCollide = false,
		})
		header:SetAttribute("Mode", box.mode)
		header:AddTag("TeamBoxHeader")
		label(header, box.mode, 0, 70)
	end

	-- One instruction sign instead of repeating it over every box.
	label(
		signAnchor(model, "TeamBoxSign", Vector3.new(0, 9, -26)),
		"Pick your team: stand on a Blue or Red side.\nThe match starts when both sides are full.",
		0,
		60
	)

	-- The Battleground portal: a blue gateway on the right of the concourse.
	-- Stepping into it teleports you to the drop-in free-for-all arena
	-- (BattlegroundService).
	local portalX, portalZ = 24, -112
	for _, side in { -1, 1 } do
		column(model, Vector3.new(portalX + side * 9, 0, portalZ), 14, 2.4, BLUE)
	end
	pointedArch(model, CFrame.new(portalX, 0, portalZ), 18, 14, 1.2, BLUE)
	local portal = MapKit.part(model, {
		name = "BattlegroundPortal",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.8, 12, 12),
		cframe = CFrame.new(portalX, 0.9, portalZ) * CFrame.Angles(0, 0, math.pi / 2),
		color = Color3.fromRGB(80, 160, 255),
		material = Enum.Material.Neon,
		transparency = 0.2,
		canCollide = false,
	})
	portal:AddTag("BattlegroundPortal")
	glow(portal, BLUE, 24, 1.2)
	label(portal, "BATTLEGROUND\nStep in to fight!", 6, 70)
	label(signAnchor(model, "BattlegroundSign", Vector3.new(portalX, 27, portalZ)), "BATTLEGROUND", 0, 140)

	----------------------------------------------------------------------
	-- Spell Practice pavilion (west): build anything, smash dummies
	----------------------------------------------------------------------
	local PRACTICE = Vector3.new(-90, 0, 38)
	local grove = MapKit.part(model, {
		name = "PracticeGrove",
		size = Vector3.new(64, 40, 76),
		cframe = CFrame.new(PRACTICE.X, 18, PRACTICE.Z),
		transparency = 1,
		canCollide = false,
	})
	grove.CanQuery = false
	grove.CanTouch = false
	grove:AddTag("BuildZone")
	MapKit.part(model, {
		name = "GroveFloor",
		size = Vector3.new(64, 0.4, 76),
		cframe = CFrame.new(PRACTICE.X, 0.2, PRACTICE.Z),
		color = Color3.fromRGB(204, 186, 148),
		material = Enum.Material.Limestone,
	})
	for _, corner in {
		Vector3.new(-1, 0, -1),
		Vector3.new(1, 0, -1),
		Vector3.new(-1, 0, 1),
		Vector3.new(1, 0, 1),
	} do
		local base = PRACTICE + Vector3.new(corner.X * 31, 0, corner.Z * 37)
		column(model, base, 12, 2.6, STONE_LIGHT)
		torch(model, base + Vector3.new(-corner.X * 3, 0, -corner.Z * 3))
	end
	label(
		signAnchor(model, "GroveSign", Vector3.new(PRACTICE.X + 30, 9, PRACTICE.Z)),
		"SPELL PRACTICE\nDraw any spell you own!",
		0,
		120
	)
	for i = 1, 4 do
		local spot = MapKit.part(model, {
			name = "DummySpot",
			size = Vector3.new(2, 0.2, 2),
			cframe = CFrame.new(PRACTICE.X - 14, 0.1, PRACTICE.Z - 27 + i * 12),
			transparency = 1,
			canCollide = false,
		})
		spot:AddTag("DummySpot")
	end

	----------------------------------------------------------------------
	-- Kiosks on the plaza's south arc
	----------------------------------------------------------------------
	-- Spellbook kiosk: the Grimoire model lying open on a lectern.
	local lectern = MapKit.part(model, {
		name = "SpellbookKiosk",
		size = Vector3.new(4, 4, 3),
		cframe = CFrame.new(-22, 2.4, 70),
		color = Color3.fromRGB(121, 85, 72),
		material = Enum.Material.Wood,
	})
	local grimoire = ModelKit.clone("Grimoire", "solid", 1.5)
	if grimoire then
		grimoire.Name = "Spellbook"
		-- Open book resting on the lectern, tilted toward the reader (+Z).
		local _, size = grimoire:GetBoundingBox()
		grimoire:PivotTo(
			CFrame.new(-22, 4.4 + size.Y / 2 + 0.2, 70) * CFrame.Angles(math.rad(-20), 0, 0)
		)
		grimoire.Parent = model
	else
		-- Fallback: a big purple book shape.
		MapKit.part(model, {
			name = "Spellbook",
			size = Vector3.new(5, 1.2, 3.6),
			cframe = CFrame.new(-22, 5.2, 70) * CFrame.Angles(math.rad(-20), 0, 0),
			color = Color3.fromRGB(96, 44, 128),
			material = Enum.Material.Fabric,
		})
	end
	label(lectern, "Spellbook", 7)
	prompt(lectern, "Spellbook", "Open", "Spellbook")

	local chest = MapKit.part(model, {
		name = "DailyChest",
		size = Vector3.new(6, 4, 4),
		cframe = CFrame.new(22, 2.4, 70),
		color = Color3.fromRGB(255, 193, 7),
		material = Enum.Material.Wood,
	})
	label(chest, "Daily Quests", 5)
	prompt(chest, "Quests", "Open", "Daily Quests")

	----------------------------------------------------------------------
	-- Crate shop (east): one Element Crate on a stage with the four element
	-- orbs around it. The crate's prompt opens the shop panel.
	----------------------------------------------------------------------
	local SHOP = Vector3.new(76, 0, 36)
	MapKit.part(model, {
		name = "CrateStage",
		size = Vector3.new(34, 1, 10),
		cframe = CFrame.new(SHOP + Vector3.new(0, 0.5, 0)),
		color = Color3.fromRGB(69, 39, 160),
		material = Enum.Material.SmoothPlastic,
	})
	pointedArch(model, CFrame.new(SHOP + Vector3.new(0, 1, -6)), 36, 12, 1.4, STONE_LIGHT)
	label(
		signAnchor(model, "CrateShopSign", SHOP + Vector3.new(0, 15, -3)),
		"Crate Shop\nUnlock new elements!",
		0,
		90
	)
	local crate = Crates.LIST[1]
	local holder = MapKit.part(model, {
		name = `Crate_{crate.id}`,
		size = Vector3.new(5, 5, 5),
		cframe = CFrame.new(SHOP + Vector3.new(0, 3.5, 0)),
		color = GOLD,
		material = Enum.Material.WoodPlanks,
	})
	local crateModel = ModelKit.clone("Crate", "solid")
	if crateModel then
		-- The model replaces the block; its trim and gem are tinted gold.
		holder.Transparency = 1
		local _, size = crateModel:GetBoundingBox()
		crateModel:ScaleTo(5.5 / math.max(size.X, 0.01))
		crateModel:PivotTo(CFrame.new(SHOP + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, math.rad(-10), 0))
		for _, part in crateModel:GetDescendants() do
			if part:IsA("BasePart") and (part.Name == "Crate_Trim" or part.Name == "Crate_Gem") then
				part.Color = GOLD
			end
		end
		crateModel.Name = `CrateModel_{crate.id}`
		crateModel.Parent = model
	end
	glow(holder, GOLD, 16, 1.2)
	local priceTag = label(holder, `🎁 {crate.name}\n💰 {crate.price}`, 5.5, 60)
	priceTag.TextColor3 = GOLD
	prompt(holder, "Crates", "Open shop", crate.name)
	for index, element in Elements.LIST do
		local orb = MapKit.part(model, {
			name = `ElementOrb_{element.id}`,
			shape = Enum.PartType.Ball,
			size = Vector3.new(3, 3, 3),
			cframe = CFrame.new(SHOP + Vector3.new((index - 2.5) * 7.5, 3.2, 1)),
			color = element.color,
			material = Enum.Material.Neon,
			canCollide = false,
		})
		glow(orb, element.color, 12, 1)
		label(orb, `{element.icon} {element.name}`, 3.2, 50)
	end

	----------------------------------------------------------------------
	-- Hall of Champions (hall entrance): winners' podium on the left, the
	-- Most Wins board on the right. Gold in the middle (highest), silver on
	-- its left, bronze on its right, all facing the plaza (+Z). Each
	-- pedestal's front face shows its rank, name and wins (LeaderboardService
	-- writes the "Text" label).
	----------------------------------------------------------------------
	local PODIUM = Vector3.new(-23, 0, -20)
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
			cframe = CFrame.new(PODIUM + Vector3.new(spec.x, spec.height / 2, 0)),
			color = spec.color,
			material = Enum.Material.Marble,
		})
		pedestal:SetAttribute("Rank", rank)
		pedestal:AddTag("PodiumSpot")
		local surface = Instance.new("SurfaceGui")
		surface.Name = "Plate"
		surface.Face = Enum.NormalId.Back -- faces +Z, toward the plaza
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
	-- Wins board, right side of the entrance, angled toward the plaza.
	local board = MapKit.part(model, {
		name = "Leaderboard",
		size = Vector3.new(16, 14, 1),
		cframe = CFrame.new(23, 9, -20) * CFrame.Angles(0, math.rad(-12), 0),
		color = Color3.fromRGB(30, 26, 56),
	})
	board:AddTag("WinsBoard")
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Board"
	surface.Face = Enum.NormalId.Back -- faces +Z, toward the plaza
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
	boardText.Text = "🏆 Most Wins\n(win a match!)"
	boardText.Parent = surface
	for _, side in { -1, 1 } do
		MapKit.part(model, {
			name = "BoardPost",
			size = Vector3.new(1.2, 10, 1.2),
			cframe = CFrame.new(23 + side * 7, 5, -20.6) * CFrame.Angles(0, math.rad(-12), 0),
			color = STONE_DARK,
			material = Enum.Material.Limestone,
		})
	end

	----------------------------------------------------------------------
	-- Arena dressing: a grandstand behind the plaza, flag poles, and trees
	----------------------------------------------------------------------
	-- Three tiers of stepped seating around the south side of the plaza.
	for tier = 1, 3 do
		local radius = PLAZA_RADIUS + 8 + tier * 7
		local height = tier * 3
		for degrees = -50, 50, 10 do
			local a = math.rad(degrees)
			local position = Vector3.new(PLAZA.X + math.sin(a) * radius, height / 2, PLAZA.Z + math.cos(a) * radius)
			MapKit.part(model, {
				name = "Grandstand",
				size = Vector3.new(radius * math.rad(10) + 1, height, 7),
				cframe = CFrame.lookAt(position, Vector3.new(PLAZA.X, position.Y, PLAZA.Z)),
				color = if (degrees / 10 + tier) % 2 == 0 then STONE_LIGHT else STONE,
				material = Enum.Material.Limestone,
			})
		end
		-- A colored pennant band along the front of each tier.
		for degrees = -50, 50, 20 do
			local a = math.rad(degrees)
			local inner = radius - 3.6
			MapKit.part(model, {
				name = "StandBanner",
				size = Vector3.new(radius * math.rad(10) * 0.9, 1.4, 0.3),
				cframe = CFrame.lookAt(
					Vector3.new(PLAZA.X + math.sin(a) * inner, height - 0.2, PLAZA.Z + math.cos(a) * inner),
					Vector3.new(PLAZA.X, height - 0.2, PLAZA.Z)
				),
				color = if (degrees / 20 + tier) % 2 == 0 then Color3.fromRGB(66, 120, 220) else Color3.fromRGB(220, 70, 60),
				material = Enum.Material.Fabric,
				canCollide = false,
			})
		end
	end

	local rng = MapKit.rng(42)
	local flagColors = { Color3.fromRGB(66, 165, 245), Color3.fromRGB(239, 83, 80) }
	for index, spot in {
		Vector3.new(-12, 0, 76),
		Vector3.new(12, 0, 76),
		Vector3.new(-37, 0, 62),
		Vector3.new(37, 0, 62),
		Vector3.new(-37, 0, -8),
		Vector3.new(37, 0, -8),
		Vector3.new(-6, 0, -12),
		Vector3.new(6, 0, -14),
		Vector3.new(58, 0, 24),
		Vector3.new(92, 0, 24),
		Vector3.new(-56, 0, 8),
		Vector3.new(-122, 0, 8),
	} do
		flagPole(model, spot, flagColors[(index % 2) + 1])
	end
	for _ = 1, 22 do
		local a = rng:NextNumber() * math.pi * 2
		local r = rng:NextNumber(110, 150)
		local pos = Vector3.new(math.cos(a) * r, 0, PLAZA.Z + math.sin(a) * r * 0.9 - 40)
		local outsideHall = math.abs(pos.X) > 52 or pos.Z > 12
		if outsideHall and math.abs(pos.X) < 160 and pos.Z > -190 and pos.Z < 150 then
			MapKit.part(model, {
				name = "Trunk",
				size = Vector3.new(2, 10, 2),
				cframe = CFrame.new(pos + Vector3.new(0, 5, 0)),
				color = Color3.fromRGB(110, 80, 56),
				material = Enum.Material.Wood,
			})
			MapKit.part(model, {
				name = "Leaves",
				shape = Enum.PartType.Ball,
				size = Vector3.new(11, 9, 11),
				cframe = CFrame.new(pos + Vector3.new(0, 12, 0)),
				color = Color3.fromRGB(72, 150, 72),
				material = Enum.Material.Grass,
			})
		end
	end

	-- Invisible walls along the edge of the grass so nobody can walk off the
	-- hub. Spells pass through them (CanQuery off).
	local walls = MapKit.folder(model, "Barriers")
	for _, edge in {
		{ pos = Vector3.new(0, 50, -40 + 170 + 4), size = Vector3.new(356, 100, 8) },
		{ pos = Vector3.new(0, 50, -40 - 170 - 4), size = Vector3.new(356, 100, 8) },
		{ pos = Vector3.new(170 + 4, 50, -40), size = Vector3.new(8, 100, 356) },
		{ pos = Vector3.new(-170 - 4, 50, -40), size = Vector3.new(8, 100, 356) },
	} do
		local wall = MapKit.part(walls, {
			name = "HubBarrier",
			size = edge.size,
			cframe = CFrame.new(edge.pos),
			transparency = 1,
		})
		wall.CanQuery = false
	end

	return model
end
