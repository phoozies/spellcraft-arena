--!strict
-- The "Like & Favourite" panel: a thank-you gift of coins for players who Like
-- and Favourite the game (once per account). Roblox has no way to check either
-- action, so the claim is on the honor system; the server only opens it after
-- Config.SUPPORT.MIN_SECONDS in the server and grants it once
-- (EconomyService.claimLikeReward). This panel shows the steps, a countdown,
-- and the claim button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)
local ClientState = require(script.Parent.ClientState)
local MenuController = require(script.Parent.MenuController)

local SupportController = {}

local claimButton: TextButton
local statusLabel: TextLabel
-- Whether the gift was claimed at the last profile (nil before the first one), so
-- the thank-you chime plays only for a claim made now, not one from a past visit.
local wasClaimed: boolean? = nil

local function refresh()
	if not claimButton then
		return
	end
	local rewards = ClientState.profile and ClientState.profile.rewards
	local coins = Config.SUPPORT.LIKE_FAVORITE_COINS
	if rewards and rewards.likeFav then
		if wasClaimed == false then
			AudioController.play("claimReward")
		end
		wasClaimed = true
		claimButton.Text = "✓ Thank you!"
		claimButton.BackgroundColor3 = Theme.COLORS.panel
		claimButton.Active = false
		statusLabel.Text = "You already claimed this gift. Thanks for supporting the game!"
		return
	end
	if rewards then
		wasClaimed = false
	end
	local wait = if rewards
		then math.ceil(rewards.likeReadyAt - workspace:GetServerTimeNow())
		else 0
	if wait > 0 then
		claimButton.Text = `Claim in {wait}s`
		claimButton.BackgroundColor3 = Theme.COLORS.panel
		claimButton.Active = false
		statusLabel.Text = "Take your time: like and favourite, then come back here."
	else
		claimButton.Text = `I did it! Claim {coins} coins`
		claimButton.BackgroundColor3 = Theme.COLORS.good
		claimButton.Active = true
		statusLabel.Text = "All done? Claim your gift!"
	end
end

function SupportController.init()
	local panel = MenuController.createPanel("Support", "Like & Favourite")
	panel.Size = UDim2.fromOffset(560, 340)

	Theme.label(panel, "Enjoying Spellcraft Arena? Help it grow and get a gift!", {
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 0, 28),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local steps = Theme.frame(panel, {
		Position = UDim2.fromOffset(16, 100),
		Size = UDim2.new(1, -32, 0, 116),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(steps)
	Theme.label(
		steps,
		"1. Press 👍 Like on this game's page\n2. Press ⭐ Favourite too\n3. Come back and claim your coins!",
		{
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 1, -16),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = false,
			TextSize = 20,
			TextWrapped = true,
		}
	)
	claimButton = Theme.button(panel, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 232),
		Size = UDim2.fromOffset(340, Theme.TOUCH),
		BackgroundColor3 = Theme.COLORS.panel,
	})
	claimButton.Activated:Connect(function()
		local rewards = ClientState.profile and ClientState.profile.rewards
		if
			rewards
			and not rewards.likeFav
			and workspace:GetServerTimeNow() >= rewards.likeReadyAt
		then
			Remotes.get("ClaimLikeReward"):FireServer()
		end
	end)
	statusLabel = Theme.label(panel, "", {
		Position = UDim2.fromOffset(16, 292),
		Size = UDim2.new(1, -32, 0, 26),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
	})
end

function SupportController.start()
	ClientState.ProfileChanged:Connect(refresh)
	-- The countdown ticks while the panel is open.
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
	refresh()
end

return SupportController
