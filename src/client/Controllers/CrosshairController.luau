--!strict
-- The sight: one small dot in the middle of the screen, and nothing else. A
-- spell goes where it points the moment its shape is finished, so it stays up
-- over the drawing canvas. Nothing marks a target: you look, you draw.
--
-- With a keyboard a quiet hint says how to reach the buttons, fights included
-- (Return to Hub has no key).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MouseLock = require(script.Parent.Parent.UI.MouseLock)
local Theme = require(script.Parent.Parent.UI.Theme)
local CursorController = require(script.Parent.CursorController)
local DrawController = require(script.Parent.DrawController)

local player = Players.LocalPlayer

local CrosshairController = {}

local DOT = 5
local HINT_AIMING = "M  menu     Alt  cursor"
local HINT_CURSOR = "Click a button     Alt  back to aiming"

local dot: Frame
local hint: TextLabel

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.Parent = player:WaitForChild("PlayerGui")

	dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(DOT, DOT)
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.Active = false
	dot.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.new(0, 0, 0)
	edge.Transparency = 0.4
	edge.Thickness = 1
	edge.Parent = dot

	hint = Theme.label(gui, HINT_AIMING, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		-- Under the spell cards and their cooldown bar.
		Position = UDim2.new(0.5, 0, 1, -1),
		Size = UDim2.fromOffset(300, 11),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
		TextTransparency = 0.3,
		Visible = false,
	})
end

local function update()
	local drawing = DrawController.isActive()
	local free = MouseLock.isFree() and not drawing
	local cursor = CursorController.isOut()
	dot.Visible = not free
	hint.Text = if cursor then HINT_CURSOR else HINT_AIMING
	hint.Visible = (cursor or not free)
		and not drawing
		and UserInputService.KeyboardEnabled
		and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch
	if free or drawing then
		UserInputService.MouseIconEnabled = true
	elseif UserInputService.MouseEnabled then
		-- The sight replaces the cursor while the mouse is locked.
		UserInputService.MouseIconEnabled = false
	end
end

function CrosshairController.init()
	build()
end

function CrosshairController.start()
	RunService.RenderStepped:Connect(update)
end

return CrosshairController
