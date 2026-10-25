--!strict
-- Drawing a spell. Two ways to open the drawing canvas:
--   * TAP A SPELL CARD (above the hotbar): the canvas shows that spell's
--     shape as a faint guide with a dot tracing it; you trace over it. The
--     closer your line follows the shape, the better the quality (and the
--     stronger the cast; see Spells/Quality).
--   * Press the draw key (default F, changeable in Settings), tap the Draw
--     button, or press X on a gamepad: a blank canvas; draw any of your
--     element's shapes from memory.
-- Then drag a mouse/finger (or push the right stick). When you let go the
-- stroke is sent to the server (DrawSpell), which decides what it is and how
-- well it followed the shape; the answer (GlyphResult) colors the line by
-- quality tier. G / Escape / the draw key again cancels.
--
-- Everything here is input and feedback. The server owns recognition,
-- ownership, cooldown, and the hotbar.

local ContextActionService = game:GetService("ContextActionService")
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
local Responsive = require(script.Parent.Parent.UI.Responsive)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local HudController = require(script.Parent.HudController)

local player = Players.LocalPlayer

local DrawController = {}

type InputKind = "mouse" | "touch" | "pad"

-- Pixels between recorded points.
local SAMPLE_SPACING = 4
local STICK_RADIUS = 0.3 -- of the screen height
local LINE_THICKNESS = 8
-- How long a sent line waits for the server's verdict before fading anyway.
local VERDICT_TIMEOUT = 1.5

local PEN = Color3.fromRGB(105, 240, 130)
local GOOD = Color3.fromRGB(255, 214, 64)
local BAD = Color3.fromRGB(239, 83, 80)

local gui: ScreenGui
local dim: Frame -- the input surface + dimmed backdrop, visible while drawing
local banner: TextLabel
local inkLayer: Frame -- always on top, so a sent line outlives the canvas
local ink: Frame -- the line being drawn
local drawButton: TextButton
local keyCap: TextLabel

-- The spell whose shape the canvas is showing (nil = a blank canvas).
local target: Types.SpellDef? = nil
local previewHolder: Frame -- the faint guide shape + tracer dot, under the ink
local tracer: Frame -- a dot that runs along the guide to show how to draw it
local tracerPath: { Vector2 } = {}
local tracerLength = 0

local active = false
local drawing = false
local inputKind: InputKind = "mouse"
local stroke: { Vector2 } = {}
local strokeStart = 0
local touchInput: InputObject? = nil
local pendingInk: Frame? = nil -- the line sent to the server, awaiting its verdict

function DrawController.isActive(): boolean
	return active
end

local function viewportHeight(): number
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize.Y else 720
end

local function newInk()
	ink = Instance.new("Frame")
	ink.Name = "Ink"
	ink.BackgroundTransparency = 1
	ink.Size = UDim2.fromScale(1, 1)
	ink.Parent = inkLayer
end

local function addPoint(position: Vector2)
	local last = stroke[#stroke]
	if last and (position - last).Magnitude < SAMPLE_SPACING then
		return
	end
	table.insert(stroke, position)
	if last then
		GlyphView.segment(ink, last, position, LINE_THICKNESS, PEN)
	end
end

-- Shows (or clears) the guide for `def`'s shape in the middle of the canvas.
local function showPreview(def: Types.SpellDef?)
	tracer.Visible = false
	tracer.Parent = nil -- keep it out of the clear below
	previewHolder:ClearAllChildren()
	table.clear(tracerPath)
	tracerLength = 0
	local glyph = if def then Glyphs.get(def.glyph) else nil
	if not def or not glyph then
		return
	end
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	-- The shape fills the middle 72% of its frame: size the frame to the screen.
	local size = math.floor(math.min(viewport.X * 0.82, viewport.Y * 0.8))
	local color = Elements.color(def.element)
	local holder = GlyphView.create(previewHolder, def.glyph, size, color, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
	}, math.max(6, size * 0.035))
	if not holder then
		return
	end
	for _, child in holder:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundTransparency = 0.4
		end
	end
	-- The tracer's route, in the holder's own pixels.
	for _, point in glyph.points do
		table.insert(tracerPath, GlyphView.pointAt(point, size))
	end
	for i = 2, #tracerPath do
		tracerLength += (tracerPath[i] - tracerPath[i - 1]).Magnitude
	end
	tracer.Parent = holder
	tracer.BackgroundColor3 = color
	tracer.Visible = true
end

-- Moves the tracer dot along the guide (every frame while it is showing).
local function stepTracer()
	if not tracer.Visible or tracerLength <= 0 then
		return
	end
	-- 2.4s per lap, then a short pause before it starts again.
	local lap = (os.clock() % 3) / 2.4
	if lap >= 1 or drawing then
		tracer.BackgroundTransparency = 1 -- gone while you draw, so it doesn't distract
		return
	end
	tracer.BackgroundTransparency = 0.05
	local distance = lap * tracerLength
	for i = 2, #tracerPath do
		local from, to = tracerPath[i - 1], tracerPath[i]
		local segment = (to - from).Magnitude
		if distance <= segment or i == #tracerPath then
			local point = from + (to - from) * math.clamp(distance / math.max(segment, 1e-6), 0, 1)
			tracer.Position = UDim2.fromOffset(point.X, point.Y)
			break
		end
		distance -= segment
	end
end

local function setActive(on: boolean, spellId: string?)
	local def = if on and spellId then SpellDefinitions.get(spellId) else nil
	if on and not ClientState.canDraw() then
		HudController.toast(
			if ClientState.fighting()
				then "Hold on, you can draw when the round starts!"
				else "You can only draw in the Training Grove, duels, and the Battleground.",
			"fizzle"
		)
		return
	end
	if active == on and (not on or target == def) then
		return
	end
	active = on
	target = def
	drawing = false
	touchInput = nil
	table.clear(stroke)
	dim.Visible = on
	-- Opening, switching, or cancelling mid-stroke wipes the unsent line.
	ink:ClearAllChildren()
	showPreview(def)
	if on then
		if def then
			banner.Text = `Trace the {def.name}! Closer = stronger.`
		else
			banner.Text = `✏ Draw a spell!  [{ClientState.drawKeyName()}] to cancel`
		end
	end
	drawButton.BackgroundColor3 = if on then Theme.COLORS.accent else Theme.COLORS.panelLight
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
	table.clear(stroke)

	local extent = math.max(high.X - low.X, high.Y - low.Y)
	if #points < GlyphRecognizer.MIN_POINTS or extent < GlyphRecognizer.MIN_EXTENT then
		HudController.toast("Draw a bigger shape!", "fizzle")
		ink:ClearAllChildren()
		return -- stay on the canvas for another try
	end
	local now = os.clock()
	if now < ClientState.drawReadyAt then
		HudController.toast(
			`Draw again in {math.ceil((ClientState.drawReadyAt - now) * 10) / 10}s`,
			"cooldown"
		)
		setActive(false)
		return
	end
	ClientState.drawReadyAt = now + Config.DRAW_COOLDOWN
	Remotes.get("DrawSpell"):FireServer(points, if target then target.id else nil)

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

-- A short "Perfect! +50% power" note over the canvas.
local function showQuality(quality: number)
	local tier = Quality.tier(quality)
	local text = `{string.rep("★", tier.stars)} {tier.name}! {Quality.describe(quality)}`
	local note = Theme.label(inkLayer, text, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(0.9, 0, 0, 52),
		TextColor3 = tier.color,
		TextStrokeTransparency = 0.2,
		ZIndex = 8,
	})
	local fade = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(note, fade, {
		Position = UDim2.fromScale(0.5, 0.3),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.3, function()
		note:Destroy()
	end)
end

local function onVerdict(spellId: string?, _glyphId: string?, quality: number?)
	local line = pendingInk
	pendingInk = nil
	if spellId and quality then
		showQuality(quality)
	end
	if not line or not line.Parent then
		return
	end
	local color = if spellId then (if quality then Quality.tier(quality).color else GOOD) else BAD
	for _, child in line:GetChildren() do
		if child:IsA("Frame") then
			TweenService:Create(child, TweenInfo.new(0.12), { BackgroundColor3 = color }):Play()
		end
	end
	task.delay(0.35, function()
		if not line.Parent then
			return
		end
		for _, child in line:GetChildren() do
			if child:IsA("Frame") then
				TweenService:Create(
					child,
					TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ BackgroundTransparency = 1 }
				):Play()
			end
		end
		task.delay(0.45, function()
			line:Destroy()
		end)
	end)
end

local function startStroke(position: Vector2, kind: InputKind)
	if not active or drawing then
		return
	end
	drawing = true
	inputKind = kind
	strokeStart = os.clock()
	table.clear(stroke)
	ink:ClearAllChildren()
	addPoint(position)
end

local function touchPosition(input: InputObject): Vector2
	-- Touch positions leave out the top bar; the canvas ignores that inset.
	return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
end

local function buildCanvas()
	gui = Instance.new("ScreenGui")
	gui.Name = "SpellcraftDraw"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	dim = Instance.new("Frame")
	dim.Name = "Canvas"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(10, 6, 30)
	dim.BackgroundTransparency = 0.6
	dim.BorderSizePixel = 0
	dim.Active = true -- swallows clicks so drawing never casts a spell
	dim.Visible = false
	dim.Parent = gui

	previewHolder = Instance.new("Frame")
	previewHolder.Name = "Preview"
	previewHolder.Size = UDim2.fromScale(1, 1)
	previewHolder.BackgroundTransparency = 1
	previewHolder.Parent = dim

	tracer = Instance.new("Frame")
	tracer.Name = "Tracer"
	tracer.AnchorPoint = Vector2.new(0.5, 0.5)
	tracer.Size = UDim2.fromOffset(22, 22)
	tracer.BorderSizePixel = 0
	tracer.Visible = false
	tracer.ZIndex = 3
	local tracerCorner = Instance.new("UICorner")
	tracerCorner.CornerRadius = UDim.new(0.5, 0)
	tracerCorner.Parent = tracer
	Theme.stroke(tracer, Color3.new(1, 1, 1), 3)

	-- 90% of the width on a phone, capped on a big screen; near the top.
	banner = Theme.label(dim, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.new(0.9, 0, 0, 44),
		TextStrokeTransparency = 0.4,
		ZIndex = 4,
	})
	local bannerLimit = Instance.new("UISizeConstraint")
	bannerLimit.MaxSize = Vector2.new(720, 52)
	bannerLimit.Parent = banner

	inkLayer = Instance.new("Frame")
	inkLayer.Name = "InkLayer"
	inkLayer.Size = UDim2.fromScale(1, 1)
	inkLayer.BackgroundTransparency = 1
	inkLayer.Active = false
	inkLayer.ZIndex = 5
	inkLayer.Parent = gui
	newInk()

	dim.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			startStroke(UserInputService:GetMouseLocation(), "mouse")
		elseif input.UserInputType == Enum.UserInputType.Touch and not touchInput then
			touchInput = input
			startStroke(touchPosition(input), "touch")
		end
	end)
	dim.InputChanged:Connect(function(input)
		if drawing and input == touchInput then
			addPoint(touchPosition(input))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and inputKind == "mouse" then
			finishStroke()
		elseif input == touchInput then
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
	drawButton = Theme.button(buttonGui, "✏ Draw", {
		Name = "Draw",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -150),
		Size = UDim2.fromOffset(120, 64),
	})
	keyCap = Theme.label(drawButton, ClientState.drawKeyName(), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 2),
		Size = UDim2.fromOffset(22, 18),
		TextColor3 = Theme.COLORS.accent,
		ZIndex = 5,
	})
	drawButton.Activated:Connect(function()
		setActive(not active)
	end)
	buttonGui.Parent = player:WaitForChild("PlayerGui")
end

function DrawController.init()
	buildCanvas()
	buildButton()
end

function DrawController.start()
	ClientState.ProfileChanged:Connect(function()
		keyCap.Text = ClientState.drawKeyName()
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
	RunService.RenderStepped:Connect(function()
		stepTracer()
		if drawing and inputKind == "mouse" then
			addPoint(UserInputService:GetMouseLocation())
		elseif active and UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad" then
			local stick = Vector2.zero
			for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
				if state.KeyCode == Enum.KeyCode.Thumbstick2 then
					stick = Vector2.new(state.Position.X, -state.Position.Y)
				end
			end
			local camera = workspace.CurrentCamera
			if camera then
				if stick.Magnitude > 0.5 then
					local point = camera.ViewportSize / 2 + stick * viewportHeight() * STICK_RADIUS
					if drawing then
						addPoint(point)
					else
						startStroke(point, "pad")
					end
				elseif drawing and inputKind == "pad" and stick.Magnitude < 0.2 then
					finishStroke()
				end
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
