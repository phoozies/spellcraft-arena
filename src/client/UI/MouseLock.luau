--!strict
-- Frees the mouse from the first-person lock while something clickable needs
-- it: a menu, the drawing canvas, a boost pick, a map vote, or the cursor key
-- (CursorController). Roblox releases LockFirstPerson's centred mouse while a
-- visible GuiButton has Modal = true, so this keeps one invisible modal button
-- and shows it whenever any reason is set. Touch and gamepad never lock a
-- mouse, so without a mouse the button stays hidden.
--
--   MouseLock.set(reason, free)     turn one reason on or off
--   MouseLock.isFree()              true while any reason is on
--   MouseLock.heldBesides(reason)   true while any other reason is on

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MouseLock = {}

local reasons: { [string]: boolean } = {}
local modal: TextButton? = nil

local function button(): TextButton
	if modal and modal.Parent then
		return modal
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MouseRelease"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local b = Instance.new("TextButton")
	b.Name = "Modal"
	b.Text = ""
	b.BackgroundTransparency = 1
	b.Size = UDim2.fromOffset(1, 1)
	b.Modal = true
	b.Visible = false
	b.Selectable = false
	b.Parent = gui
	modal = b
	return b
end

local function apply()
	button().Visible = next(reasons) ~= nil and UserInputService.MouseEnabled
end

function MouseLock.set(reason: string, free: boolean)
	if (reasons[reason] == true) == free then
		return
	end
	reasons[reason] = if free then true else nil
	apply()
end

function MouseLock.isFree(): boolean
	return next(reasons) ~= nil
end

function MouseLock.heldBesides(reason: string): boolean
	for other in reasons do
		if other ~= reason then
			return true
		end
	end
	return false
end

-- Frees the mouse whenever `frame` is shown (it and its ScreenGui are visible):
-- for panels with buttons, so players can click them in first person.
local watched = 0
function MouseLock.whileVisible(frame: GuiObject)
	watched += 1
	local reason = `{frame.Name}#{watched}`
	local function update()
		local gui = frame:FindFirstAncestorWhichIsA("ScreenGui")
		local shown = frame.Visible and (gui == nil or gui.Enabled)
		local node = frame.Parent
		while shown and node and node:IsA("GuiObject") do
			shown = node.Visible
			node = node.Parent
		end
		MouseLock.set(reason, shown and frame:IsDescendantOf(game))
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(update)
	frame.AncestryChanged:Connect(function()
		local gui = frame:FindFirstAncestorWhichIsA("ScreenGui")
		if gui then
			gui:GetPropertyChangedSignal("Enabled"):Connect(update)
		end
		update()
	end)
	local gui = frame:FindFirstAncestorWhichIsA("ScreenGui")
	if gui then
		gui:GetPropertyChangedSignal("Enabled"):Connect(update)
	end
	frame.Destroying:Connect(function()
		MouseLock.set(reason, false)
	end)
	update()
end

return MouseLock
