--!strict
-- Declutters phones and tablets during fights. While a touch-only device is in
-- a match or the Battleground, the menu buttons, wallet, party button and panel,
-- kill feed, and boost icons are hidden, so the screen is left for the game:
-- the hotbar, spell cards, Draw and Dash buttons, health bar, the match bar, and
-- (in the Battleground) the Return to Hub button. They come back afterwards.

local UserInputService = game:GetService("UserInputService")

local HudController = require(script.Parent.HudController)
local ClientState = require(script.Parent.ClientState)

local MobileController = {}

-- Names of HUD root children to hide while fighting on a touch device.
local HIDDEN = { "SideMenu", "Wallet", "PartyToggle", "PartyPanel", "KillFeed", "Boosts" }

-- What each hidden element's Visible was before we hid it.
local saved: { [GuiObject]: boolean } = {}

local function touchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function apply()
	local root = HudController.getGui():FindFirstChild("Root")
	if not root then
		return
	end
	local minimal = touchOnly() and ClientState.fighting()
	for _, name in HIDDEN do
		local object = root:FindFirstChild(name)
		if object and object:IsA("GuiObject") then
			if minimal then
				if saved[object] == nil then
					saved[object] = object.Visible
				end
				object.Visible = false
			elseif saved[object] ~= nil then
				object.Visible = saved[object]
				saved[object] = nil
			end
		end
	end
end

function MobileController.start()
	ClientState.PresenceChanged:Connect(apply)
	apply()
end

return MobileController
