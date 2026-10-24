--!strict
-- Inkwell Plaza — the central hub. Players can be playing within seconds:
-- the team boxes are right in front of the spawn.
--
-- Tags/attributes HubService relies on:
--   TeamPad   (Mode, Team, Slots)   one side of a team box: players stand on
--                                   a side to pick their team (1v1..4v4)
--   QueuePad  (Mode attribute)      step on to join that queue (FFA)
--   BuildZone                       placing objects allowed here
--   DummySpot                       training dummies respawn here
--   HubSpawn                        where players appear
--   ProximityPrompts named "Spellbook" and "Quests" open UI on the client

local MapKit = require(script.Parent.MapKit)

local BLUE = Color3.fromRGB(66, 165, 245)
local RED = Color3.fromRGB(239, 83, 80)

-- Team boxes: {mode, players per team, center x, center z}. Each box is two
-- side-by-side pads, Blue then Red, one spot per teammate. Their open front
-- faces the spawn (+Z).
local BOXES = {
	{ mode = "1v1", perTeam = 1, x = -38, z = -30 },
	{ mode = "2v2", perTeam = 2, x = -6, z = -30 },
	{ mode = "3v3", perTeam = 3, x = 30, z = -30 },
	{ mode = "4v4", perTeam = 4, x = 0, z = -60 },
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

return function(): Model
	local model = Instance.new("Model")
	model.Name = "InkwellPlaza"

	-- Ground: grass ring with a cobblestone plaza.
	MapKit.part(model, {
		name = "Grass",
		size = Vector3.new(260, 4, 260),
		cframe = CFrame.new(0, -2, 0),
		color = Color3.fromRGB(124, 179, 66),
		material = Enum.Material.Grass,
	})
	MapKit.part(model, {
		name = "Plaza",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.4, 90, 90),
		cframe = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = Color3.fromRGB(215, 204, 200),
		material = Enum.Material.Cobblestone,
	})
	-- Low hedge around the hub edge.
	MapKit.ring(model, Vector3.zero, 128, 6, Color3.fromRGB(56, 142, 60))
	for _, wall in model:GetChildren() do
		if wall.Name == "RingWall" and wall:IsA("BasePart") then
			wall.Name = "Hedge"
			wall.Material = Enum.Material.Grass
			wall.Transparency = 0
		end
	end

	-- The giant inkwell fountain.
	MapKit.part(model, {
		name = "Inkwell",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(8, 16, 16),
		cframe = CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = Color3.fromRGB(26, 35, 126),
		material = Enum.Material.Glass,
	})
	local quill = MapKit.part(model, {
		name = "Quill",
		size = Vector3.new(1.5, 22, 4),
		cframe = CFrame.new(2, 16, 0) * CFrame.Angles(0, 0, math.rad(-15)),
		color = Color3.fromRGB(255, 255, 255),
		material = Enum.Material.SmoothPlastic,
	})
	label(quill, "WORDCRAFT ARENA", 14)

	local spawn = MapKit.part(model, {
		name = "HubSpawn",
		size = Vector3.new(10, 1, 10),
		cframe = CFrame.new(0, 0.5, 30),
		color = Color3.fromRGB(255, 241, 118),
		material = Enum.Material.Neon,
		transparency = 0.5,
		canCollide = false,
	})
	spawn:AddTag("HubSpawn")

	-- Team boxes: stand on the Blue or Red side to pick your team. The match
	-- starts when both sides are full.
	for _, box in BOXES do
		local width = math.max(8, box.perTeam * 5.5)
		for side, team in { "Blue", "Red" } do
			local color = if team == "Blue" then BLUE else RED
			local x = box.x + (if side == 1 then -1 else 1) * (width / 2 + PAD_GAP / 2)
			local pad = MapKit.part(model, {
				name = `TeamPad_{box.mode}_{team}`,
				size = Vector3.new(width, 0.6, PAD_DEPTH),
				cframe = CFrame.new(x, 0.5, box.z),
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
						offset = Vector3.new(0, 1.8, -PAD_DEPTH / 2),
					},
					{
						size = Vector3.new(0.6, 3, PAD_DEPTH),
						offset = Vector3.new(-width / 2, 1.8, 0),
					},
					{
						size = Vector3.new(0.6, 3, PAD_DEPTH),
						offset = Vector3.new(width / 2, 1.8, 0),
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
	local boxSign = MapKit.part(model, {
		name = "TeamBoxSign",
		size = Vector3.one,
		cframe = CFrame.new(0, 7, -14),
		transparency = 1,
		canCollide = false,
	})
	label(
		boxSign,
		"Pick your team: stand on a Blue or Red side.\nThe match starts when both sides are full.",
		0,
		60
	)

	-- Free-for-all: step on the pad to join the queue.
	local ffa = MapKit.part(model, {
		name = "Queue_FFA",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1, 12, 12),
		cframe = CFrame.new(-50, 0.5, -60) * CFrame.Angles(0, 0, math.pi / 2),
		color = Color3.fromRGB(236, 64, 122),
		material = Enum.Material.Neon,
	})
	ffa:SetAttribute("Mode", "FFA")
	ffa:AddTag("QueuePad")
	label(ffa, "FFA\n0 waiting", 6, 60)

	-- Practice Grove (west): build anything, smash dummies.
	local grove = MapKit.part(model, {
		name = "PracticeGrove",
		size = Vector3.new(70, 40, 80),
		cframe = CFrame.new(-80, 18, 0),
		transparency = 1,
		canCollide = false,
	})
	grove.CanQuery = false
	grove.CanTouch = false
	grove:AddTag("BuildZone")
	MapKit.part(model, {
		name = "GroveFloor",
		size = Vector3.new(70, 0.4, 80),
		cframe = CFrame.new(-80, 0.2, 0),
		color = Color3.fromRGB(165, 214, 167),
		material = Enum.Material.Grass,
	})
	local groveSign = MapKit.part(model, {
		name = "GroveSign",
		size = Vector3.new(1, 1, 1),
		cframe = CFrame.new(-48, 6, 0),
		transparency = 1,
		canCollide = false,
	})
	label(groveSign, "Practice Grove\nType any spell you own!", 0)
	for i = 1, 4 do
		local spot = MapKit.part(model, {
			name = "DummySpot",
			size = Vector3.new(2, 0.2, 2),
			cframe = CFrame.new(-100, 0.1, -30 + i * 12),
			transparency = 1,
			canCollide = false,
		})
		spot:AddTag("DummySpot")
	end

	-- Spellbook kiosk and Daily chest (south).
	local kiosk = MapKit.part(model, {
		name = "SpellbookKiosk",
		size = Vector3.new(6, 8, 2),
		cframe = CFrame.new(-16, 4, 50),
		color = Color3.fromRGB(121, 85, 72),
		material = Enum.Material.Wood,
	})
	label(kiosk, "Spellbook", 6)
	prompt(kiosk, "Spellbook", "Open", "Spellbook")

	local chest = MapKit.part(model, {
		name = "DailyChest",
		size = Vector3.new(6, 4, 4),
		cframe = CFrame.new(16, 2, 50),
		color = Color3.fromRGB(255, 193, 7),
		material = Enum.Material.Wood,
	})
	label(chest, "Daily Quests", 5)
	prompt(chest, "Quests", "Open", "Daily Quests")

	-- Leaderboard board (north-east).
	local board = MapKit.part(model, {
		name = "Leaderboard",
		size = Vector3.new(20, 12, 1),
		cframe = CFrame.new(40, 8, -50) * CFrame.Angles(0, math.rad(-20), 0),
		color = Color3.fromRGB(38, 50, 56),
	})
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Board"
	surface.Face = Enum.NormalId.Front
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
	boardText.Text = "Top Spellcasters\n(play a match!)"
	boardText.Parent = surface

	-- Trees for flavor.
	local rng = MapKit.rng(42)
	for _ = 1, 18 do
		local a = rng:NextNumber() * math.pi * 2
		local r = rng:NextNumber(70, 115)
		local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if math.abs(pos.X) < 55 or math.abs(pos.Z) > 45 then
			MapKit.part(model, {
				name = "Trunk",
				size = Vector3.new(2, 8, 2),
				cframe = CFrame.new(pos + Vector3.new(0, 4, 0)),
				color = Color3.fromRGB(121, 85, 72),
				material = Enum.Material.Wood,
			})
			MapKit.part(model, {
				name = "Leaves",
				shape = Enum.PartType.Ball,
				size = Vector3.new(9, 9, 9),
				cframe = CFrame.new(pos + Vector3.new(0, 10, 0)),
				color = Color3.fromRGB(67, 160, 71),
				material = Enum.Material.Grass,
			})
		end
	end

	return model
end
