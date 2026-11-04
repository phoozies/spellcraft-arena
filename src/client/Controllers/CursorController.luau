--!strict
-- The cursor key: gets the mouse out of the first-person lock so the always-on
-- buttons (spell cards, side menu, Party, Return to Hub) can be clicked. Shift
-- works like Roblox's shift lock, turned around: press it and the cursor is out,
-- press it again and you are back to aiming (keys in Config.CURSOR). Windows and
-- the canvas free the mouse themselves (UI/MouseLock), and touch has no mouse to
-- free, so this only matters on PC.
--
-- Roblox's shift lock icon sits in the bottom left: blue while the mouse is
-- locked, white while the cursor is out (click it to go back to aiming).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MouseLock = require(script.Parent.Parent.UI.MouseLock)
local Responsive = require(script.Parent.Parent.UI.Responsive)
local Theme = require(script.Parent.Parent.UI.Theme)

local CursorController = {}

local REASON = "cursor"
local ICON_LOCKED = "rbxasset://textures/ui/mouseLock_on@2x.png"
local ICON_CURSOR = "rbxasset://textures/ui/mouseLock_off@2x.png"
local ICON_SIZE = 44

local out = false
local icon: ImageButton

-- True while the cursor is out because of this key (the sight's hint says so).
function CursorController.isOut(): boolean
	return out
end

local function step()
	-- A window or the canvas took over: when it closes, you are back to aiming.
	local heldElsewhere = MouseLock.heldBesides(REASON)
	if heldElsewhere then
		out = false
	end
	MouseLock.set(REASON, out)
	icon.Visible = not heldElsewhere and not Responsive.isTouch()
	icon.Image = if out then ICON_CURSOR else ICON_LOCKED
end

function CursorController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpellcraftCursor"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	Responsive.bind(scale)
	icon = Instance.new("ImageButton")
	icon.Name = "ShiftLock"
	icon.AnchorPoint = Vector2.new(0, 1)
	-- Level with the spell cards' bottom edge.
	icon.Position = UDim2.new(0, 10, 1, -20)
	icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	icon.BackgroundTransparency = 1
	icon.Image = ICON_LOCKED
	icon.Selectable = false
	icon.Parent = gui
	Theme.juice(icon)
	icon.Activated:Connect(function()
		out = false
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function CursorController.start()
	RunService.RenderStepped:Connect(step)
	UserInputService.InputBegan:Connect(function(input, processed)
		-- Processed: a capital letter typed in chat.
		if not processed and table.find(Config.CURSOR.KEYS, input.KeyCode.Name) then
			out = not out
		end
	end)
end

return CursorController
