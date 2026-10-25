--!strict
-- The "Like & Favourite" gift box in the hub (tag "LikeGift", built by
-- Maps/InkwellPlaza): a thank-you gift of coins for players who Like and
-- Favourite the game (once per account). Roblox has no way to check either
-- action, so the claim is on the honor system; the server only opens it after
-- Config.SUPPORT.MIN_SECONDS in the server and grants it once
-- (EconomyService.claimLikeReward, triggered by the box's ProximityPrompt).
--
-- There is no menu button or panel for it any more: this controller only keeps
-- the physical box honest for this player. Its prompt is turned off once the
-- gift is claimed, counts down while the claim is not open yet, and the thank-you
-- chime plays on a claim made now (not one from a past visit).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local AudioController = require(script.Parent.AudioController)
local ClientState = require(script.Parent.ClientState)

local SupportController = {}

local TAG = "LikeGift"

-- Whether the gift was claimed at the last profile (nil before the first one).
local wasClaimed: boolean? = nil

local function prompts(): { ProximityPrompt }
	local list = {}
	for _, box in CollectionService:GetTagged(TAG) do
		local prompt = box:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			table.insert(list, prompt)
		end
	end
	return list
end

-- Seconds until the claim opens for this player (0 = open now), or nil when
-- the profile has not arrived.
function SupportController.secondsUntilReady(): number?
	local rewards = ClientState.profile and ClientState.profile.rewards
	if not rewards then
		return nil
	end
	return math.max(0, math.ceil(rewards.likeReadyAt - workspace:GetServerTimeNow()))
end

local function refresh()
	local rewards = ClientState.profile and ClientState.profile.rewards
	if not rewards then
		return
	end
	if rewards.likeFav then
		if wasClaimed == false then
			AudioController.play("claimReward")
		end
		wasClaimed = true
	else
		wasClaimed = false
	end
	local wait = SupportController.secondsUntilReady() or 0
	for _, prompt in prompts() do
		prompt.Enabled = not rewards.likeFav
		prompt.ActionText = if wait > 0
			then `Like & Favourite first (ready in {wait}s)`
			else `Claim {Config.SUPPORT.LIKE_FAVORITE_COINS} coins`
	end
end

function SupportController.start()
	ClientState.ProfileChanged:Connect(refresh)
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function()
		task.defer(refresh)
	end)
	-- The countdown ticks on the prompt while the player stands at the box.
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
	refresh()
end

return SupportController
