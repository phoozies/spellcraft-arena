--!strict
-- The cursor key: gets the mouse out of the first-person lock so the always-on
-- buttons (spell cards, side menu, Party, Return to Hub) can be clicked. Shift
-- works like Roblox's shift lock, turned around: press it and the cursor is out,
-- press it again and you are back to aiming (keys in Config.CURSOR). Windows and
-- the canvas free the mouse themselves (UI/MouseLock), and touch has no mouse to
-- free, so this only matters on PC.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MouseLock = require(script.Parent.Parent.UI.MouseLock)

local CursorController = {}

local REASON = "cursor"

local out = false

-- True while the cursor is out because of this key (the sight's hint says so).
function CursorController.isOut(): boolean
	return out
end

local function step()
	-- A window or the canvas took over: when it closes, you are back to aiming.
	if MouseLock.heldBesides(REASON) then
		out = false
	end
	MouseLock.set(REASON, out)
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
