--!strict
-- Drawing a spell. Press the draw key (default F, changeable in Settings),
-- tap the ✏ Draw button, or press X on a gamepad to open the drawing canvas,
-- then drag a mouse/finger (or push the right stick) to trace a glyph. When
-- you let go the stroke is sent to the server (DrawSpell), which decides
-- what it is; the server's answer (GlyphResult) lights the line up gold or
-- red. G / Escape / the draw key again cancels.
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
local GlyphRecognizer = require(ReplicatedStorage.Shared.Spells.GlyphRecognizer)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local GlyphView = require(script.Parent.Parent.UI.GlyphView)
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

local function setActive(on: boolean)
	if active == on then
		return
	end
	active = on
	drawing = false
	touchInput = nil
	table.clear(stroke)
	dim.Visible = on
	if on then
		ink:ClearAllChildren()
		banner.Text = `✏ Draw a spell!  [{ClientState.drawKeyName()}] to cancel`
	else
		-- Cancelled mid-stroke: wipe the unsent line.
		ink:ClearAllChildren()
	end
	drawButton.BackgroundColor3 = if on then Theme.COLORS.accent else Theme.COLORS.panelLight
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
	Remotes.get("DrawSpell"):FireServer(points)

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

local function onVerdict(spellId: string?, _glyphId: string?)
	local line = pendingInk
	pendingInk = nil
	if not line or not line.Parent then
		return
	end
	local color = if spellId then GOOD else BAD
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
	gui.Name = "WordcraftDraw"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	dim = Instance.new("Frame")
	dim.Name = "Canvas"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(10, 6, 30)
	dim.BackgroundTransparency = 0.72
	dim.BorderSizePixel = 0
	dim.Active = true -- swallows clicks so drawing never casts a spell
	dim.Visible = false
	dim.Parent = gui

	banner = Theme.label(dim, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(620, 44),
		TextStrokeTransparency = 0.4,
	})

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
	buttonGui.Name = "WordcraftDrawButton"
	buttonGui.ResetOnSpawn = false
	buttonGui.DisplayOrder = 5
	buttonGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	buttonGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
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

	Remotes.get("GlyphResult").OnClientEvent:Connect(onVerdict)

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

	ContextActionService:BindAction("WordcraftDrawPad", function(_, state)
		if state == Enum.UserInputState.Begin then
			setActive(not active)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonX)

	-- A mouse drag is sampled every frame (the canvas only reports the
	-- button going down); a gamepad draws with the right stick.
	RunService.RenderStepped:Connect(function()
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
