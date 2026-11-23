--!strict
-- Drawing a spell with your wand. Two ways to open the drawing canvas:
--   * TAP A SPELL CARD or press its key (1-5): the canvas shows
--     that spell's shape as a glowing guide with a comet tracing it; you trace
--     over it. The closer your line follows the shape, the better the quality
--     (and the stronger the cast; see Spells/Quality).
--   * Press the draw key (default F, changeable in Settings), tap the Draw
--     button, or press X on a gamepad: a blank canvas; draw any of your
--     loadout's shapes from memory.
-- Then drag a mouse/finger (or push the right stick). The line glows in the
-- spell's colour with a sparking pen tip, and your wand writes the same stroke
-- in the air in front of you (WandController). When you let go the stroke is
-- sent to the server (DrawSpell) with the point under the sight. The server
-- decides what it is and how well it followed the shape and casts the spell at
-- once, with no click: aim first, then draw. The answer (GlyphResult) flashes
-- the line in its quality colour and pulls it into the wand, or turns it red.
-- G / Escape / the draw key again cancels.
--
-- Everything here is input and feedback. The server owns recognition,
-- ownership, cooldown, and the cast.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local GlyphRecognizer = require(ReplicatedStorage.Shared.Spells.GlyphRecognizer)
local Glyphs = require(ReplicatedStorage.Shared.Spells.Glyphs)
local Quality = require(ReplicatedStorage.Shared.Spells.Quality)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Types = require(ReplicatedStorage.Shared.Types)
local GlyphView = require(ReplicatedStorage.Shared.UI.GlyphView)
local WandAir = require(ReplicatedStorage.Shared.Util.WandAir)
local Responsive = require(script.Parent.Parent.UI.Responsive)
local SpellCard = require(script.Parent.Parent.UI.SpellCard)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local HudController = require(script.Parent.HudController)
local JuiceController = require(script.Parent.JuiceController)
local WandController = require(script.Parent.WandController)

local player = Players.LocalPlayer

local DrawController = {}

type InputKind = "mouse" | "touch" | "pad"

-- Pixels between recorded points, and between drawn line pieces.
local SAMPLE_SPACING = 4
local DRAW_SPACING = 8
local STICK_RADIUS = 0.3 -- of the screen height
-- The ink: a wide soft glow, a solid core, and a white shine down the middle.
local GLOW_THICKNESS = 16
local CORE_THICKNESS = 6
local SHINE_THICKNESS = 2
-- How long a sent line waits for the server's verdict before fading anyway.
local VERDICT_TIMEOUT = 1.5
-- Pen-tip sparkles: at most this many on screen.
local MAX_SPARKS = 50
-- The comet behind the guide's tracer dot: how many trailing dots, how far apart.
local COMET_DOTS = 6
local COMET_GAP = 14

local WHITE = Color3.new(1, 1, 1)
local GOOD = Color3.fromRGB(255, 214, 64)
local BAD = Color3.fromRGB(239, 83, 80)

local gui: ScreenGui
local dim: Frame -- the clear input surface, visible while drawing
local bannerFrame: Frame
local bannerTitle: TextLabel
local bannerHint: TextLabel
local runes: Frame -- the turning rune circle behind the guide
local runesInner: Frame
local runesScale: UIScale
local inkLayer: Frame -- always on top, so a sent line outlives the canvas
local ink: Frame -- the line being drawn (glow, core and shine layers)
local pen: Frame -- the glowing orb at the pen tip
local sparkLayer: Frame
local drawButton: TextButton
local drawTouch = false

-- The spell whose shape the canvas is showing (nil = a blank canvas).
local target: Types.SpellDef? = nil
local inkColor = WHITE
local previewHolder: Frame -- the guide shape + tracer comet, under the ink
local tracer: Frame -- a dot that runs along the guide to show how to draw it
local comet: { Frame } = {}
local tracerPath: { Vector2 } = {}
local tracerLength = 0

-- Set by InputController: the point under the sight, and how a placeable
-- would be turned.
local aimProvider: (() -> (Vector3?, number?))? = nil

local active = false
local drawing = false
local inputKind: InputKind = "mouse"
local stroke: { Vector2 } = {}
local lastDrawn: Vector2? = nil
local strokeStart = 0
local touchInput: InputObject? = nil
local pendingInk: Frame? = nil -- the line sent to the server, awaiting its verdict
local sparkCount = 0

function DrawController.isActive(): boolean
	return active
end

function DrawController.setAimProvider(fn: () -> (Vector3?, number?))
	aimProvider = fn
end

local function sinkAction(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

local function viewportHeight(): number
	return viewport().Y
end

-- The colour of a blank canvas: your element's (the same as your wand's tip).
local function elementColor(): Color3
	local profile = ClientState.profile
	if profile and Elements.get(profile.element) then
		return Elements.color(profile.element)
	end
	return Elements.ARCANE.color
end

local function layer(parent: Instance, name: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- A full-size see-through group: everything inside is drawn opaque and the
-- group fades as one, so overlapping line pieces don't stack up into beads.
local function group(parent: Instance, name: string, transparency: number): CanvasGroup
	local g = Instance.new("CanvasGroup")
	g.Name = name
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromScale(1, 1)
	g.GroupTransparency = transparency
	g.Parent = parent
	return g
end

local function newInk()
	ink = Instance.new("Frame")
	ink.Name = "Ink"
	ink.BackgroundTransparency = 1
	-- Anchored in the middle so a UIScale collapses it towards the centre.
	ink.AnchorPoint = Vector2.new(0.5, 0.5)
	ink.Position = UDim2.fromScale(0.5, 0.5)
	ink.Size = UDim2.fromScale(1, 1)
	ink.Parent = inkLayer
	group(ink, "Glow", 0.78).ZIndex = 1
	layer(ink, "Core", 2)
	layer(ink, "Shine", 3)
	local scale = Instance.new("UIScale")
	scale.Parent = ink
end

-- Every line piece of an ink frame (all three layers).
local function inkPieces(line: Frame): { Frame }
	local pieces = {}
	for _, piece in line:GetDescendants() do
		if piece:IsA("Frame") and piece.Name == "Segment" then
			table.insert(pieces, piece)
		end
	end
	return pieces
end

local function drawPiece(from: Vector2, to: Vector2)
	-- Every piece is opaque (the Glow group fades as one), so joints don't bead.
	GlyphView.segment(ink:FindFirstChild("Glow") :: Instance, from, to, GLOW_THICKNESS, inkColor)
	GlyphView.segment(ink:FindFirstChild("Core") :: Instance, from, to, CORE_THICKNESS, inkColor)
	local shine = GlyphView.segment(
		ink:FindFirstChild("Shine") :: Instance,
		from,
		to,
		SHINE_THICKNESS,
		inkColor:Lerp(WHITE, 0.75)
	)
	shine:SetAttribute("Shine", true)
end

-- A tiny spark that flies off the pen tip and fades.
local function spark(at: Vector2)
	if sparkCount >= MAX_SPARKS then
		return
	end
	sparkCount += 1
	local size = math.random(6, 11)
	local s = Instance.new("Frame")
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.fromOffset(at.X, at.Y)
	s.Size = UDim2.fromOffset(size, size)
	s.Rotation = 45
	s.BorderSizePixel = 0
	s.BackgroundColor3 = inkColor:Lerp(WHITE, math.random() * 0.6)
	s.Parent = sparkLayer
	local drift = Vector2.new(math.random(-40, 40), math.random(-10, 45))
	TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(at.X + drift.X, at.Y + drift.Y),
		Size = UDim2.fromOffset(0, 0),
		Rotation = 45 + math.random(-180, 180),
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.5, function()
		sparkCount -= 1
		s:Destroy()
	end)
end

local function addPoint(position: Vector2)
	local last = stroke[#stroke]
	if last and (position - last).Magnitude < SAMPLE_SPACING then
		return
	end
	table.insert(stroke, position)
	pen.Position = UDim2.fromOffset(position.X, position.Y)
	WandController.strokePoint(position)
	if not lastDrawn then
		lastDrawn = position
		return
	end
	local from = lastDrawn :: Vector2
	if (position - from).Magnitude >= DRAW_SPACING then
		drawPiece(from, position)
		lastDrawn = position
		spark(position)
	end
end

-- The point `distance` pixels along the guide (looping is up to the caller).
local function pointAlong(distance: number): Vector2?
	for i = 2, #tracerPath do
		local from, to = tracerPath[i - 1], tracerPath[i]
		local segment = (to - from).Magnitude
		if distance <= segment or i == #tracerPath then
			return from + (to - from) * math.clamp(distance / math.max(segment, 1e-6), 0, 1)
		end
		distance -= segment
	end
	return nil
end

-- Shows (or clears) the guide for `def`'s shape in the middle of the canvas.
local function showPreview(def: Types.SpellDef?)
	tracer.Visible = false
	tracer.Parent = nil -- keep it (and its comet) out of the clear below
	for _, dot in comet do
		dot.Parent = nil
	end
	previewHolder:ClearAllChildren()
	table.clear(tracerPath)
	tracerLength = 0
	local glyph = if def then Glyphs.get(def.glyph) else nil
	if not def or not glyph then
		return
	end
	local view = viewport()
	-- The shape fills the middle 72% of its frame: size the frame to the screen.
	local size = math.floor(math.min(view.X * 0.82, view.Y * 0.8))
	local props = {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(WandAir.SCREEN_CENTER.X, WandAir.SCREEN_CENTER.Y),
	}
	-- The guide is drawn opaque inside see-through groups, so the overlapping
	-- line pieces fade as one shape (no darker beads where they overlap).
	local glowGroup = group(previewHolder, "GuideGlow", 0.9)
	local glow =
		GlyphView.create(glowGroup, def.glyph, size, inkColor, props, math.max(10, size * 0.045))
	if glow then
		for _, child in glow:GetChildren() do
			if child:IsA("Frame") then
				child.BackgroundColor3 = inkColor
			end
		end
	end
	local lineGroup = group(previewHolder, "GuideLine", 0.42)
	local holder =
		GlyphView.create(lineGroup, def.glyph, size, inkColor, props, math.max(4, size * 0.016))
	if not holder then
		return
	end
	-- A soft darker edge in the spell's own colour instead of black.
	for _, child in holder:GetChildren() do
		if child:IsA("Frame") and child.Name == "Outline" then
			child.BackgroundColor3 = inkColor:Lerp(Color3.new(0, 0, 0), 0.45)
		end
	end
	-- The tracer and its comet ride above the groups at the same place.
	local tracerHost = Instance.new("Frame")
	tracerHost.Name = "TracerHost"
	tracerHost.BackgroundTransparency = 1
	tracerHost.Size = UDim2.fromOffset(size, size)
	tracerHost.AnchorPoint = props.AnchorPoint
	tracerHost.Position = props.Position
	tracerHost.ZIndex = 3
	tracerHost.Parent = previewHolder
	-- The tracer's route, in the holder's own pixels.
	for _, point in glyph.points do
		table.insert(tracerPath, GlyphView.pointAt(point, size))
	end
	for i = 2, #tracerPath do
		tracerLength += (tracerPath[i] - tracerPath[i - 1]).Magnitude
	end
	for _, dot in comet do
		dot.BackgroundColor3 = inkColor:Lerp(WHITE, 0.3)
		dot.Parent = tracerHost
	end
	tracer.Parent = tracerHost
	tracer.BackgroundColor3 = inkColor
	tracer.Visible = true
end

-- Moves the tracer comet along the guide (every frame while it is showing).
local function stepTracer()
	if not tracer.Visible or tracerLength <= 0 then
		return
	end
	-- 2.4s per lap, then a short pause before it starts again.
	local lap = (os.clock() % 3) / 2.4
	local hidden = lap >= 1 or drawing -- gone while you draw, so it doesn't distract
	tracer.BackgroundTransparency = if hidden then 1 else 0.05
	local distance = lap * tracerLength
	local head = pointAlong(distance)
	if head then
		tracer.Position = UDim2.fromOffset(head.X, head.Y)
	end
	for index, dot in comet do
		local behind = distance - index * COMET_GAP
		local p = if behind > 0 then pointAlong(behind) else nil
		dot.Visible = not hidden and p ~= nil
		if p then
			dot.Position = UDim2.fromOffset(p.X, p.Y)
		end
	end
end

local function updateBanner(def: Types.SpellDef?)
	bannerTitle.Text = if def then def.name else "Draw any of your spells"
	bannerTitle.TextColor3 = inkColor
	bannerHint.Text = if def
		then `Trace it closely. {ClientState.drawKeyName()} cancels.`
		else `{ClientState.drawKeyName()} cancels.`
end

-- Pops the canvas pieces in when it opens.
local function playOpen()
	runesScale.Scale = 0.6
	TweenService:Create(runesScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 })
		:Play()
	local bannerScale = bannerFrame:FindFirstChildOfClass("UIScale")
	if bannerScale then
		bannerScale.Scale = 0.85
		TweenService:Create(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 })
			:Play()
	end
end

local function setActive(on: boolean, spellId: string?)
	local def = if on and spellId then SpellDefinitions.get(spellId) else nil
	if on and not ClientState.canDraw() then
		HudController.toast(
			if ClientState.fighting()
				then "Hold on, you can draw when the round starts!"
				else "You can only draw in the Training Grove, duels, and the Battleground.",
			"error"
		)
		return
	end
	if active == on and (not on or target == def) then
		return
	end
	local wasActive = active
	active = on
	target = def
	ClientState.aiming = if def then def.id else nil
	-- A gamepad draws with the right stick: it must not swing the camera (the
	-- spell's aim) while it does.
	if on and not wasActive then
		ContextActionService:BindActionAtPriority(
			"SpellcraftDrawHoldCamera",
			sinkAction,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Thumbstick2
		)
	elseif wasActive and not on then
		ContextActionService:UnbindAction("SpellcraftDrawHoldCamera")
	end
	if drawing then
		WandController.strokeCancel()
	end
	drawing = false
	touchInput = nil
	table.clear(stroke)
	lastDrawn = nil
	pen.Visible = false
	dim.Visible = on
	inkColor = if def then SpellCard.colorOf(def.id) else elementColor()
	-- Opening, switching, or cancelling mid-stroke wipes the unsent line.
	for _, piece in inkPieces(ink) do
		piece:Destroy()
	end
	showPreview(def)
	if on then
		updateBanner(def)
		for _, ring in { runes, runesInner } do
			local s = ring:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = inkColor
			end
		end
		pen.BackgroundColor3 = inkColor
		if not wasActive then
			playOpen()
		end
	end
	if wasActive ~= on then
		WandController.setDrawing(on)
	end
	HudController.setTracing(if def then def.id else nil)
	drawButton.BackgroundColor3 = if on then Theme.COLORS.accent else Theme.COLORS.panel
end

-- Opens the canvas for one spell (a tapped card), or closes it if that
-- spell's canvas is already open.
function DrawController.begin(spellId: string)
	if active and target and target.id == spellId then
		setActive(false)
	else
		setActive(true, spellId)
	end
end

-- Evenly thins a stroke that has more points than the server accepts.
local function thinned(points: { Vector2 }): { Vector2 }
	local max = Config.DRAW_MAX_POINTS
	if #points <= max then
		return points
	end
	local out = {}
	for i = 1, max do
		out[i] = points[math.floor(1 + (i - 1) * (#points - 1) / (max - 1) + 0.5)]
	end
	return out
end

-- A line the magic couldn't use: shake it, turn it red, and fade it.
local function rejectLine(line: Frame)
	for _, piece in inkPieces(line) do
		if not piece:GetAttribute("Shine") then
			TweenService:Create(piece, TweenInfo.new(0.1), { BackgroundColor3 = BAD }):Play()
		end
	end
	task.spawn(function()
		for i = 1, 6 do
			if not line.Parent then
				return
			end
			line.Position = UDim2.new(0.5, (if i % 2 == 0 then 1 else -1) * (8 - i), 0.5, 0)
			task.wait(0.035)
		end
		line.Position = UDim2.fromScale(0.5, 0.5)
		for _, piece in inkPieces(line) do
			TweenService:Create(piece, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
		task.wait(0.4)
		line:Destroy()
	end)
end

-- A line that worked: flash it in its quality colour, then collapse it
-- inward while the wand pulls the air copy in.
local function acceptLine(line: Frame, color: Color3)
	for _, piece in inkPieces(line) do
		if not piece:GetAttribute("Shine") then
			piece.BackgroundColor3 = color:Lerp(WHITE, 0.35)
			TweenService:Create(piece, TweenInfo.new(0.2), { BackgroundColor3 = color }):Play()
		end
	end
	task.delay(0.25, function()
		if not line.Parent then
			return
		end
		local scale = line:FindFirstChildOfClass("UIScale")
		if scale then
			TweenService:Create(
				scale,
				TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Scale = 0.05 }
			):Play()
		end
		for _, piece in inkPieces(line) do
			TweenService:Create(
				piece,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ BackgroundTransparency = 1 }
			):Play()
		end
		Debris:AddItem(line, 0.4)
	end)
end

local function finishStroke()
	if not drawing then
		return
	end
	local height = viewportHeight()
	local points: { Vector2 } = {}
	local low, high = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, p in thinned(stroke) do
		local scaled = p / height
		table.insert(points, scaled)
		low = Vector2.new(math.min(low.X, scaled.X), math.min(low.Y, scaled.Y))
		high = Vector2.new(math.max(high.X, scaled.X), math.max(high.Y, scaled.Y))
	end
	drawing = false
	touchInput = nil
	pen.Visible = false
	table.clear(stroke)
	lastDrawn = nil

	local extent = math.max(high.X - low.X, high.Y - low.Y)
	if #points < GlyphRecognizer.MIN_POINTS or extent < GlyphRecognizer.MIN_EXTENT then
		HudController.toast("Draw a bigger shape!", "error")
		WandController.strokeCancel()
		for _, piece in inkPieces(ink) do
			piece:Destroy()
		end
		return -- stay on the canvas for another try
	end
	local now = os.clock()
	if now < ClientState.drawReadyAt then
		HudController.toast(
			`Draw again in {math.ceil((ClientState.drawReadyAt - now) * 10) / 10}s`,
			"error"
		)
		WandController.strokeCancel()
		setActive(false)
		return
	end
	ClientState.drawReadyAt = now + Config.DRAW_COOLDOWN
	-- The rest of the live stroke goes first, so watchers have all of it
	-- before the verdict lands.
	WandController.strokeSent()
	local aim, rotation = nil, nil
	if aimProvider then
		aim, rotation = aimProvider()
	end
	Remotes.get("DrawSpell"):FireServer(points, if target then target.id else nil, aim, rotation)

	-- Close the canvas but keep the line until the server says what it was.
	local sent = ink
	pendingInk = sent
	newInk()
	setActive(false) -- clears the NEW ink, not the one just sent
	task.delay(VERDICT_TIMEOUT, function()
		if pendingInk == sent then
			pendingInk = nil
		end
		if sent.Parent then
			sent:Destroy()
		end
	end)
end

local function onVerdict(spellId: string?, _glyphId: string?, quality: number?)
	local line = pendingInk
	pendingInk = nil
	-- No text popup: it covers too much of a phone screen. The line's colour,
	-- the wand, and the screen juice show how well it was drawn.
	local color = if spellId then (if quality then Quality.tier(quality).color else GOOD) else BAD
	WandController.verdict(spellId ~= nil, color)
	if spellId and quality then
		JuiceController.drawn(Quality.tier(quality).stars)
	end
	if not line or not line.Parent then
		return
	end
	if spellId then
		acceptLine(line, color)
	else
		rejectLine(line)
	end
end

local function startStroke(position: Vector2, kind: InputKind)
	if not active or drawing then
		return
	end
	drawing = true
	inputKind = kind
	strokeStart = os.clock()
	table.clear(stroke)
	lastDrawn = nil
	for _, piece in inkPieces(ink) do
		piece:Destroy()
	end
	pen.Visible = true
	WandController.strokeBegin(inkColor)
	addPoint(position)
end

local function touchPosition(input: InputObject): Vector2
	-- Touch positions leave out the top bar; the canvas ignores that inset.
	return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
end

-- True when a visible button outside the canvas is under `at` (viewport
-- pixels, top bar included).
local function overButton(at: Vector2): boolean
	local inset = GuiService:GetGuiInset()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	for _, object in playerGui:GetGuiObjectsAtPosition(at.X - inset.X, at.Y - inset.Y) do
		if object:IsA("GuiButton") and object.Visible and not object:IsDescendantOf(gui) then
			return true
		end
	end
	return false
end

local function circle(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	for key, value in props do
		(f :: any)[key] = value
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	f.Parent = parent
	return f
end

local function buildRunes()
	runes = circle(dim, {
		Name = "Runes",
		Position = UDim2.fromScale(WandAir.SCREEN_CENTER.X, WandAir.SCREEN_CENTER.Y),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundTransparency = 1,
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = runes
	runesScale = Instance.new("UIScale")
	runesScale.Parent = runes
	local outer = Instance.new("UIStroke")
	outer.Thickness = 3
	outer.Transparency = 0.88
	outer.Color = WHITE
	outer.Parent = runes
	runesInner = circle(runes, {
		Name = "Inner",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundTransparency = 1,
	})
	local inner = Instance.new("UIStroke")
	inner.Thickness = 2
	inner.Transparency = 1
	inner.Color = WHITE
	inner.Parent = runesInner
end

local function buildBanner()
	bannerFrame = Theme.frame(dim, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(420, 46),
		BackgroundTransparency = 1,
		ZIndex = 6,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = bannerFrame
	bannerTitle = Theme.label(bannerFrame, "", {
		Size = UDim2.new(1, 0, 0, 26),
		TextStrokeTransparency = 0.6,
		ZIndex = 7,
	})
	bannerHint = Theme.label(bannerFrame, "", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 16),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.onDark,
		TextStrokeTransparency = 0.6,
		ZIndex = 7,
	})
end

local function buildCanvas()
	gui = Instance.new("ScreenGui")
	gui.Name = "SpellcraftDraw"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Under the HUD, so the spell row and the Draw button stay tappable: the
	-- canvas swallows input to keep a finger's stroke from turning the camera.
	gui.DisplayOrder = -1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	dim = Instance.new("Frame")
	dim.Name = "Canvas"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundTransparency = 1 -- the world stays in full view while drawing
	dim.BorderSizePixel = 0
	dim.Active = true -- swallows clicks so drawing never casts a spell
	dim.Visible = false
	dim.Parent = gui
	buildRunes()

	previewHolder = Instance.new("Frame")
	previewHolder.Name = "Preview"
	previewHolder.Size = UDim2.fromScale(1, 1)
	previewHolder.BackgroundTransparency = 1
	previewHolder.ZIndex = 2
	previewHolder.Parent = dim

	tracer = circle(gui, {
		Name = "Tracer",
		Size = UDim2.fromOffset(24, 24),
		Visible = false,
		ZIndex = 4,
	})
	Theme.stroke(tracer, WHITE, 3)
	tracer.Parent = nil
	for index = 1, COMET_DOTS do
		local size = 20 - index * 2.5
		local dot = circle(gui, {
			Name = "Comet",
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 0.2 + index * 0.12,
			ZIndex = 3,
		})
		dot.Parent = nil
		table.insert(comet, dot)
	end

	buildBanner()

	inkLayer = Instance.new("Frame")
	inkLayer.Name = "InkLayer"
	inkLayer.Size = UDim2.fromScale(1, 1)
	inkLayer.BackgroundTransparency = 1
	inkLayer.Active = false
	inkLayer.ZIndex = 5
	inkLayer.Parent = gui
	newInk()

	sparkLayer = layer(gui, "Sparks", 6)
	pen = circle(gui, {
		Name = "Pen",
		Size = UDim2.fromOffset(26, 26),
		Visible = false,
		ZIndex = 7,
	})
	Theme.stroke(pen, WHITE, 3)
	local penHalo = circle(pen, {
		Name = "Halo",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(2.2, 2.2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82,
		ZIndex = 6,
	})
	penHalo.Active = false

	-- Strokes start from UserInputService rather than the canvas frame: the ink
	-- and spark layers lie over the canvas and would keep GUI input events from
	-- reaching it. A press on a button (Draw, the spell cards, menus) is left alone.
	UserInputService.InputBegan:Connect(function(input)
		if not active or drawing then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 then
			local at = UserInputService:GetMouseLocation()
			if not overButton(at) then
				startStroke(at, "mouse")
			end
		elseif kind == Enum.UserInputType.Touch and not touchInput then
			local at = touchPosition(input)
			if not overButton(at) then
				touchInput = input
				startStroke(at, "touch")
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if drawing and input == touchInput then
			addPoint(touchPosition(input))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			(input.UserInputType == Enum.UserInputType.MouseButton1 and inputKind == "mouse")
			or input == touchInput
		then
			finishStroke()
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function buildButton()
	local buttonGui = Instance.new("ScreenGui")
	buttonGui.Name = "SpellcraftDrawButton"
	buttonGui.ResetOnSpawn = false
	buttonGui.DisplayOrder = 5
	buttonGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	buttonGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local buttonScale = Instance.new("UIScale")
	buttonScale.Parent = buttonGui
	Responsive.bind(buttonScale)
	-- On touch a big thumb button; with keys a small chip left of the spell row.
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	drawButton = Theme.button(buttonGui, "Draw", {
		Name = "Draw",
		AnchorPoint = Vector2.new(1, 1),
		Position = if touch
			then UDim2.new(1, -16, 1, -90)
			else UDim2.new(0.5, -(HudController.cardRowWidth() / 2 + 10), 1, -20),
		Size = if touch then UDim2.fromOffset(96, 60) else UDim2.fromOffset(48, 48),
		BackgroundColor3 = Theme.COLORS.panel,
		BackgroundTransparency = 0.25,
	})
	drawTouch = touch
	drawButton.Activated:Connect(function()
		setActive(not active)
	end)
	buttonGui.Parent = player:WaitForChild("PlayerGui")
end

function DrawController.init()
	buildCanvas()
	buildButton()
	if not drawTouch then
		drawButton.Text = ClientState.drawKeyName()
	end
end

function DrawController.start()
	ClientState.ProfileChanged:Connect(function()
		if not drawTouch then
			drawButton.Text = ClientState.drawKeyName()
		end
	end)
	-- The Draw button only exists where drawing does; close the canvas when
	-- drawing stops being allowed (the round ends).
	local function refreshPresence()
		local allowed = ClientState.canDraw()
		drawButton.Visible = allowed
		if not allowed then
			setActive(false)
		end
	end
	ClientState.PresenceChanged:Connect(refreshPresence)
	refreshPresence()

	Remotes.get("GlyphResult").OnClientEvent:Connect(onVerdict)
	ClientState.DrawRequested:Connect(DrawController.begin)

	UserInputService.InputBegan:Connect(function(input, processed)
		if ClientState.capturingKey or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if active and (input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.Escape) then
			setActive(false)
			return
		end
		if not processed and input.KeyCode == ClientState.drawKeyCode() then
			setActive(not active)
		end
	end)

	ContextActionService:BindAction("SpellcraftDrawPad", function(_, state)
		if state == Enum.UserInputState.Begin then
			setActive(not active)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonX)

	-- A mouse drag is sampled every frame (the canvas only reports the
	-- button going down); a gamepad draws with the right stick.
	RunService.RenderStepped:Connect(function(dt)
		stepTracer()
		if active then
			runes.Rotation = (runes.Rotation + dt * 10) % 360
			runesInner.Rotation = (runesInner.Rotation - dt * 25) % 360
			if drawing then
				local pulse = 1 + math.sin(os.clock() * 14) * 0.12
				pen.Size = UDim2.fromOffset(26 * pulse, 26 * pulse)
			end
		end
		if drawing and inputKind == "mouse" then
			addPoint(UserInputService:GetMouseLocation())
		elseif active and UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad" then
			local stick = Vector2.zero
			for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
				if state.KeyCode == Enum.KeyCode.Thumbstick2 then
					stick = Vector2.new(state.Position.X, -state.Position.Y)
				end
			end
			if stick.Magnitude > 0.5 then
				local point = viewport() / 2 + stick * viewportHeight() * STICK_RADIUS
				if drawing then
					addPoint(point)
				else
					startStroke(point, "pad")
				end
			elseif drawing and inputKind == "pad" and stick.Magnitude < 0.2 then
				finishStroke()
			end
		end
		-- A stroke that never ends (stuck button) is submitted after a while.
		if drawing and os.clock() - strokeStart > Config.DRAW_MAX_SECONDS then
			finishStroke()
		end
	end)

	-- Don't leave the canvas up across a death or respawn.
	player.CharacterRemoving:Connect(function()
		setActive(false)
	end)
end

return DrawController
