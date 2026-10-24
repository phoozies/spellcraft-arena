--!strict
-- Inkwell Plaza — the central hub. Players can be playing within seconds:
-- queue pads are right in front of the spawn.
--
-- Tags/attributes HubService relies on:
--   QueuePad  (Mode attribute)      step on to join that queue
--   BuildZone                       placing objects allowed here
--   SparringZone                    PvP allowed between players inside
--   DummySpot                       training dummies respawn here
--   HubSpawn                        where players appear
--   ProximityPrompts named "Spellbook" and "Quests" open UI on the client

local MapKit = require(script.Parent.MapKit)

local MODES = {
	{ mode = "1v1", color = Color3.fromRGB(66, 165, 245) },
	{ mode = "2v2", color = Color3.fromRGB(102, 187, 106) },
	{ mode = "4v4", color = Color3.fromRGB(255, 167, 38) },
	{ mode = "FFA", color = Color3.fromRGB(236, 64, 122) },
}

local function label(part: BasePart, text: string, offset: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
	gui.MaxDistance = 150
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

	-- Queue pads in an arc in front of spawn.
	for i, info in MODES do
		local x = (i - 2.5) * 18
		local pad = MapKit.part(model, {
			name = `Queue_{info.mode}`,
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(1, 12, 12),
			cframe = CFrame.new(x, 0.5, -24) * CFrame.Angles(0, 0, math.pi / 2),
			color = info.color,
			material = Enum.Material.Neon,
		})
		pad:SetAttribute("Mode", info.mode)
		pad:AddTag("QueuePad")
		label(pad, `{info.mode}\n0 waiting`, 6)
	end

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

	-- Sparring Ring (east): opt-in PvP.
	local ring = MapKit.part(model, {
		name = "SparringRing",
		size = Vector3.new(50, 30, 50),
		cframe = CFrame.new(80, 15, 0),
		transparency = 1,
		canCollide = false,
	})
	ring.CanQuery = false
	ring.CanTouch = false
	ring:AddTag("SparringZone")
	ring:AddTag("BuildZone")
	MapKit.part(model, {
		name = "RingFloor",
		size = Vector3.new(50, 1, 50),
		cframe = CFrame.new(80, 0.5, 0),
		color = Color3.fromRGB(239, 83, 80),
		material = Enum.Material.Fabric,
	})
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		MapKit.part(model, {
			name = "RingPost",
			size = Vector3.new(2, 6, 2),
			cframe = CFrame.new(80 + corner[1] * 24, 3, corner[2] * 24),
			color = Color3.fromRGB(255, 255, 255),
		})
	end
	local ringSign = MapKit.part(model, {
		name = "RingSign",
		size = Vector3.new(1, 1, 1),
		cframe = CFrame.new(80, 10, -26),
		transparency = 1,
		canCollide = false,
	})
	label(ringSign, "Sparring Ring\nPvP inside!", 0)

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
