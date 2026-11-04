--!strict
-- The sight: one small dot in the middle of the screen, and nothing else. A
-- spell goes where it points the moment its shape is finished, so it stays up
-- over the drawing canvas. Nothing marks a target: you look, you draw.
--
-- Outside fights a quiet hint says how to reach the menus.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MouseLock = require(script.Parent.Parent.UI.MouseLock)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local DrawController = require(script.Parent.DrawController)

local player = Players.LocalPlayer

local CrosshairController = {}

local DOT = 5

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

	hint = Theme.label(gui, "M  menu     Alt  cursor", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(240, 14),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
		TextTransparency = 0.3,
		Visible = false,
	})
end

local function update()
	local drawing = DrawController.isActive()
	local free = MouseLock.isFree() and not drawing
	dot.Visible = not free
	hint.Visible = not free
		and not drawing
		and UserInputService.KeyboardEnabled
		and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch
		and not ClientState.fighting()
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
