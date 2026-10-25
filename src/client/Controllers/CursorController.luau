--!strict
-- The spell cursor. While a spell is readied (you drew it and it is waiting to
-- be cast) the mouse pointer turns into a pulsing crosshair in the spell's
-- colour with the spell's name and "Click to cast" under it, so it is always
-- obvious that your next click throws a spell. It goes red and shows the
-- seconds left while the spell recharges, and gives the normal arrow back over
-- buttons and while a menu or the drawing canvas is open.
--
-- Mouse only: touch and gamepad aim some other way (InputController), so they
-- never see it. Purely visual; InputController still decides what a click does.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local DrawController = require(script.Parent.DrawController)
local MenuController = require(script.Parent.MenuController)

local player = Players.LocalPlayer

local CursorController = {}

local RING = 46
local COOLING = Color3.fromRGB(235, 64, 52)

local gui: ScreenGui
local root: Frame
local ring: Frame
local ringStroke: UIStroke
local dot: Frame
local ticks: { Frame } = {}
local nameLabel: TextLabel
local hintLabel: TextLabel
local shown = false
local overrodeSystemCursor = false

local function setSystemCursor(visible: boolean)
	if visible then
		if overrodeSystemCursor then
			UserInputService.MouseIconEnabled = true
			overrodeSystemCursor = false
		end
	elseif not overrodeSystemCursor then
		UserInputService.MouseIconEnabled = false
		overrodeSystemCursor = true
	end
end

local function hide()
	if shown then
		shown = false
		gui.Enabled = false
	end
	setSystemCursor(true)
end

-- True when the pointer is over a button of ours (so the arrow should show).
local function overButton(position: Vector2): boolean
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	local inset = GuiService:GetGuiInset()
	for _, object in playerGui:GetGuiObjectsAtPosition(position.X - inset.X, position.Y - inset.Y) do
		if object:IsA("GuiButton") and object.Visible and not object:IsDescendantOf(gui) then
			return true
		end
	end
	return false
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "SpellCursor"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	root = Instance.new("Frame")
	root.Name = "Cursor"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(RING, RING)
	root.Active = false
	root.Parent = gui

	ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(RING, RING)
	ring.BackgroundTransparency = 1
	ring.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 4
	ringStroke.Parent = ring

	dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BorderSizePixel = 0
	dot.Parent = root
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(0.5, 0)
	dotCorner.Parent = dot
	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color = Theme.COLORS.outline
	dotStroke.Thickness = 2
	dotStroke.Parent = dot

	-- Four tick marks pointing at the center, like a crosshair.
	for index = 1, 4 do
		local tick = Instance.new("Frame")
		tick.Name = `Tick{index}`
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.BorderSizePixel = 0
		tick.Size = if index % 2 == 1 then UDim2.fromOffset(4, 12) else UDim2.fromOffset(12, 4)
		tick.Parent = root
		table.insert(ticks, tick)
	end

	nameLabel = Theme.label(root, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.fromOffset(170, 24),
	})
	hintLabel = Theme.label(root, "Click to cast", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 34),
		Size = UDim2.fromOffset(170, 18),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
	})
end

local function update()
	local last = UserInputService:GetLastInputType()
	local usingMouse = UserInputService.MouseEnabled
		and last ~= Enum.UserInputType.Touch
		and string.sub(last.Name, 1, 7) ~= "Gamepad"
	local id = ClientState.readied
	local def = id and SpellDefinitions.get(id)
	if not def or not usingMouse or DrawController.isActive() or MenuController.isOpen() then
		hide()
		return
	end
	local position = UserInputService:GetMouseLocation()
	if overButton(position) then
		hide()
		return
	end

	shown = true
	gui.Enabled = true
	setSystemCursor(false)
	root.Position = UDim2.fromOffset(position.X, position.Y)

	local left = ClientState.cooldownLeft(def.id)
	local cooling = left > 0
	-- The ring wears the spell's own colour; red while it recharges.
	local tint = if cooling then COOLING else def.visual.color
	ringStroke.Color = tint
	dot.BackgroundColor3 = tint
	for _, tick in ticks do
		tick.BackgroundColor3 = tint
	end
	-- A steady pulse says "armed"; it stops while cooling down.
	local pulse = if cooling then 0 else math.sin(os.clock() * 7) * 3
	local size = RING + pulse
	ring.Size = UDim2.fromOffset(size, size)
	local reach = size / 2 + 2
	for index, tick in ticks do
		local angle = (index - 1) * math.pi / 2
		tick.Position = UDim2.new(0.5, math.sin(angle) * reach, 0.5, -math.cos(angle) * reach)
	end
	nameLabel.Text = if cooling then `{def.name} {math.ceil(left)}s` else def.name
	nameLabel.TextColor3 = tint
	hintLabel.Text = if cooling then "Recharging…" else "Click to cast"
end

function CursorController.init()
	build()
end

function CursorController.start()
	RunService.RenderStepped:Connect(update)
end

return CursorController
