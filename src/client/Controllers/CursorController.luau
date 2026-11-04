--!strict
-- The cursor key: gets the mouse out of the first-person lock so the always-on
-- buttons (spell cards, side menu, Party, Return to Hub) can be clicked. Tap
-- Left Alt and the cursor stays out for one click; hold it and the cursor is
-- out until you let go. The rules are in Util/CursorMode, the tunables in
-- Config.CURSOR. Windows and the canvas free the mouse themselves
-- (UI/MouseLock), and touch has no mouse to free, so this only matters on PC.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local CursorMode = require(ReplicatedStorage.Shared.Util.CursorMode)
local MouseLock = require(script.Parent.Parent.UI.MouseLock)

local CursorController = {}

local REASON = "cursor"

local state = CursorMode.new()
local keyWasDown = false

-- True while the cursor is out because of this key (the sight's hint says so).
function CursorController.isOut(): boolean
	return CursorMode.isFree(state)
end

local function step()
	local keyDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
	if keyDown ~= keyWasDown then
		keyWasDown = keyDown
		if keyDown then
			CursorMode.press(state, os.clock())
		else
			CursorMode.release(state, os.clock(), Config.CURSOR.TAP_SECONDS)
		end
	end
	-- A window or the canvas took over: when it closes, you are back to aiming.
	if MouseLock.heldBesides(REASON) then
		CursorMode.clear(state)
	end
	MouseLock.set(REASON, CursorMode.isFree(state))
end

function CursorController.start()
	RunService.RenderStepped:Connect(step)
	-- Alt-Tab: that press was not meant for the game.
	UserInputService.WindowFocusReleased:Connect(function()
		CursorMode.cancel(state)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- A little later: re-locking moves the mouse, and the button under it
			-- still has to see the click finish.
			task.delay(Config.CURSOR.CLICK_RELEASE, CursorMode.click, state)
		end
	end)
end

return CursorController
