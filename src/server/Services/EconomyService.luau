--!strict
-- Coins, wins, daily login streak, first-win bonus, daily quests, and
-- player settings. The ONLY place that mutates profile.coins or
-- profile.stats.wins (chests spend through EconomyService.spend).
--
-- There are no levels or XP: players earn coins by winning matches
-- (Config.COINS.MATCH_WIN, + FIRST_WIN_OF_DAY), from the daily login chest,
-- and from quests, then spend them on chests (ChestService) to unlock spells.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerDataService = require(script.Parent.PlayerDataService)
local TelemetryService = require(script.Parent.TelemetryService)

local EconomyService = {}

-- Fired with (player) whenever coins or wins change (LeaderboardService
-- mirrors them into leaderstats and the hub podium).
EconomyService.Changed = Signal.new() :: Signal.Signal<Player>

-- Quest templates; three are picked per day. `event` matches EconomyService.track().
local QUEST_POOL = {
	{ id = "cast25", text = "Cast 25 spells", event = "cast", goal = 25, rewardCoins = 30 },
	{ id = "ko5", text = "Knock out 5 opponents", event = "knockout", goal = 5, rewardCoins = 40 },
	{ id = "win2", text = "Win 2 matches", event = "win", goal = 2, rewardCoins = 60 },
	{ id = "play3", text = "Play 3 matches", event = "match", goal = 3, rewardCoins = 30 },
	{ id = "place10", text = "Place 10 objects", event = "place", goal = 10, rewardCoins = 25 },
	{ id = "break10", text = "Destroy 10 objects", event = "destroy", goal = 10, rewardCoins = 30 },
	{
		id = "draft3",
		text = "Pick 3 match boosts",
		event = "boost",
		goal = 3,
		rewardCoins = 35,
	},
}

local questEvents: { [string]: string } = {}
for _, q in QUEST_POOL do
	questEvents[q.id] = q.event
end

local toastRemote: RemoteEvent
local profileRemote: RemoteEvent

-- Server time each player's profile loaded (the Like & Favourite gift unlocks
-- Config.SUPPORT.MIN_SECONDS later).
local joinedAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function today(): number
	return math.floor(os.time() / 86400)
end

local function sendSummary(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	profileRemote:FireClient(player, {
		coins = profile.coins,
		elements = profile.elements,
		element = profile.element,
		spells = profile.spells,
		loadout = profile.loadout,
		tutorial = profile.tutorial,
		quests = profile.daily.quests,
		streak = profile.daily.streak,
		settings = profile.settings,
		stats = profile.stats,
		pity = profile.pity,
		rewards = {
			likeFav = profile.rewards.likeFav,
			likeReadyAt = (joinedAt[player] or workspace:GetServerTimeNow())
				+ Config.SUPPORT.MIN_SECONDS,
		},
	})
end
EconomyService.sendSummary = sendSummary

-- Adds coins (amount > 0). `reason` is for logs/analytics only. `quiet`
-- skips the client summary (chest refunds are revealed after the spin).
function EconomyService.addCoins(player: Player, amount: number, reason: string, quiet: boolean?)
	local profile = PlayerDataService.get(player)
	if not profile or amount <= 0 or amount ~= amount then
		return
	end
	profile.coins += math.floor(amount)
	-- Admin and debug grants are test money, not part of the real economy.
	if reason ~= "admin" and reason ~= "debug" then
		TelemetryService.coinsEarned(player, math.floor(amount), profile.coins, reason)
	end
	if not quiet then
		sendSummary(player)
	end
	EconomyService.Changed:Fire(player)
end

-- Spends coins if the player has enough. Returns true when spent. `item` is
-- what they bought (for the analytics economy flow).
function EconomyService.spend(player: Player, amount: number, item: string?): boolean
	local profile = PlayerDataService.get(player)
	if not profile or amount < 0 or profile.coins < amount then
		return false
	end
	profile.coins -= amount
	if item and amount > 0 then
		TelemetryService.coinsSpent(player, amount, profile.coins, item)
	end
	sendSummary(player)
	EconomyService.Changed:Fire(player)
	return true
end

function EconomyService.coins(player: Player): number
	local profile = PlayerDataService.get(player)
	return if profile then profile.coins else 0
end

function EconomyService.wins(player: Player): number
	local profile = PlayerDataService.get(player)
	return if profile then profile.stats.wins else 0
end

-- Records a match win (the leaderboard stat). Coins are granted separately
-- by the caller so the Results screen can show the total.
function EconomyService.recordWin(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	profile.stats.wins += 1
	sendSummary(player)
	EconomyService.Changed:Fire(player)
end

-- Sets the win count (leaderboard, board, podium follow). Admin tools only.
function EconomyService.setWins(player: Player, wins: number)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	profile.stats.wins = math.max(0, math.floor(wins))
	sendSummary(player)
	EconomyService.Changed:Fire(player)
end

-- Admin reset of the economy-owned parts of a profile. `scope` is one of
-- "coins" (back to the starting coins), "wins", "stats" (every counter),
-- "rewards" (the Like & Favourite gift can be claimed again) or "tutorial"
-- (shows again). Returns false for an unknown scope.
function EconomyService.reset(player: Player, scope: string): boolean
	local profile = PlayerDataService.get(player)
	if not profile then
		return false
	end
	if scope == "coins" then
		profile.coins = Config.COINS.STARTING
	elseif scope == "wins" then
		profile.stats.wins = 0
	elseif scope == "stats" then
		profile.stats = { matches = 0, wins = 0, knockouts = 0, casts = 0 }
	elseif scope == "rewards" then
		profile.rewards.likeFav = false
	elseif scope == "tutorial" then
		profile.tutorial.done = false
	else
		return false
	end
	sendSummary(player)
	EconomyService.Changed:Fire(player)
	return true
end

local function refreshDaily(player: Player, profile: Types.Profile)
	local day = today()
	if profile.daily.lastLoginDay ~= day then
		if profile.daily.lastLoginDay == day - 1 then
			profile.daily.streak += 1
		else
			profile.daily.streak = 1
		end
		profile.daily.lastLoginDay = day
		local bonus = Config.COINS.DAILY_LOGIN * math.min(profile.daily.streak, 7)
		task.delay(3, function()
			if player.Parent then
				toastRemote:FireClient(
					player,
					`Daily chest! Day {profile.daily.streak} streak: +{bonus} coins`,
					"reward"
				)
				EconomyService.addCoins(player, bonus, "daily")
			end
		end)
	end
	if profile.daily.questDay ~= day then
		profile.daily.questDay = day
		local rng = Random.new(day * 7919 + player.UserId % 1000)
		local pool = table.clone(QUEST_POOL)
		local quests = {}
		for _ = 1, 3 do
			local q = table.remove(pool, rng:NextInteger(1, #pool))
			if q then
				table.insert(quests, {
					id = q.id,
					text = q.text,
					goal = q.goal,
					progress = 0,
					rewardCoins = q.rewardCoins,
					claimed = false,
				})
			end
		end
		profile.daily.quests = quests
	end
end

-- Progresses daily quests; `event` is one of the QUEST_POOL event names.
function EconomyService.track(player: Player, event: string, amount: number?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	local changed = false
	for _, quest in profile.daily.quests do
		if questEvents[quest.id] == event and quest.progress < quest.goal then
			quest.progress = math.min(quest.goal, quest.progress + (amount or 1))
			changed = true
			if quest.progress >= quest.goal then
				toastRemote:FireClient(
					player,
					`Quest complete: {quest.text}! Claim it in Quests.`,
					"reward"
				)
			end
		end
	end
	if changed then
		sendSummary(player)
	end
end

-- Returns true if this is the player's first win today (and records it).
function EconomyService.consumeFirstWin(player: Player): boolean
	local profile = PlayerDataService.get(player)
	if not profile or profile.daily.lastFirstWinDay == today() then
		return false
	end
	profile.daily.lastFirstWinDay = today()
	return true
end

-- The one-time Like & Favourite gift. Nothing on Roblox can confirm a like or a
-- favourite, so this trusts the player but only after they've spent
-- Config.SUPPORT.MIN_SECONDS here, and only once per account.
function EconomyService.claimLikeReward(player: Player): boolean
	local profile = PlayerDataService.get(player)
	if not profile or profile.rewards.likeFav then
		return false
	end
	local ready = (joinedAt[player] or workspace:GetServerTimeNow()) + Config.SUPPORT.MIN_SECONDS
	if workspace:GetServerTimeNow() < ready then
		toastRemote:FireClient(player, "Play a little longer, then claim your gift!", "fizzle")
		return false
	end
	profile.rewards.likeFav = true
	toastRemote:FireClient(
		player,
		`Thanks for the support! +{Config.SUPPORT.LIKE_FAVORITE_COINS} coins`,
		"reward"
	)
	EconomyService.addCoins(player, Config.SUPPORT.LIKE_FAVORITE_COINS, "likeFav")
	return true
end

-- Studio QA only (DebugService "likefav"): sets whether the gift counts as claimed.
function EconomyService.setLikeRewardClaimed(player: Player, claimed: boolean)
	local profile = PlayerDataService.get(player)
	if profile then
		profile.rewards.likeFav = claimed
		sendSummary(player)
	end
end

function EconomyService.init()
	toastRemote = Remotes.get("Toast")
	profileRemote = Remotes.get("ProfileUpdated")
end

function EconomyService.start()
	PlayerDataService.ProfileLoaded:Connect(function(player, profile)
		joinedAt[player] = workspace:GetServerTimeNow()
		refreshDaily(player, profile)
		sendSummary(player)
		EconomyService.Changed:Fire(player)
	end)

	-- Player settings (saved with the profile). Only known keys with valid
	-- values are accepted.
	Remotes.get("SaveSettings").OnServerEvent:Connect(function(player, key, value)
		local profile = PlayerDataService.get(player)
		if not profile or typeof(key) ~= "string" then
			return
		end
		if key == "music" or key == "sfx" or key == "shake" then
			if typeof(value) == "boolean" then
				profile.settings[key] = value
				sendSummary(player)
			end
			return
		end
		if typeof(value) ~= "string" or #value > 32 then
			return
		end
		if key == "drawKey" then
			local ok, keyCode = pcall(function()
				return (Enum.KeyCode :: any)[value]
			end)
			if not ok or keyCode == nil or table.find(Config.RESERVED_KEYS, value) then
				toastRemote:FireClient(player, `Can't bind {value}; pick another key.`, "fizzle")
				return
			end
			profile.settings.drawKey = value
			sendSummary(player)
		end
	end)

	-- The first-join tutorial finished (or was skipped): never show it again.
	Remotes.get("TutorialDone").OnServerEvent:Connect(function(player)
		local profile = PlayerDataService.get(player)
		if profile and not profile.tutorial.done then
			profile.tutorial.done = true
			TelemetryService.onboarding(player, "TutorialDone")
			sendSummary(player)
		end
	end)

	-- The hub's gift box (tag "LikeGift", built by Maps/InkwellPlaza): standing
	-- at it and holding its prompt claims the Like & Favourite gift. The prompt
	-- only fires for a player in range; the claim itself is idempotent.
	local lastClaimTry: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
	local function hookGift(box: Instance)
		local prompt = box:FindFirstChildWhichIsA("ProximityPrompt", true)
		if not prompt then
			return
		end
		prompt.Triggered:Connect(function(player)
			local now = os.clock()
			if now - (lastClaimTry[player] or 0) < 1 then
				return
			end
			lastClaimTry[player] = now
			EconomyService.claimLikeReward(player)
		end)
	end
	for _, box in CollectionService:GetTagged("LikeGift") do
		hookGift(box)
	end
	CollectionService:GetInstanceAddedSignal("LikeGift"):Connect(hookGift)

	Remotes.get("ClaimQuest").OnServerEvent:Connect(function(player, questId)
		if typeof(questId) ~= "string" then
			return
		end
		local profile = PlayerDataService.get(player)
		if not profile then
			return
		end
		for _, quest in profile.daily.quests do
			if quest.id == questId and quest.progress >= quest.goal and not quest.claimed then
				quest.claimed = true
				TelemetryService.event(player, "QuestClaimed", quest.rewardCoins)
				EconomyService.addCoins(player, quest.rewardCoins, "quest")
				return
			end
		end
	end)

	-- Re-check the day roll-over for long sessions.
	task.spawn(function()
		while true do
			task.wait(300)
			for _, player in Players:GetPlayers() do
				local profile = PlayerDataService.get(player)
				if profile then
					refreshDaily(player, profile)
				end
			end
		end
	end)
end

return EconomyService
