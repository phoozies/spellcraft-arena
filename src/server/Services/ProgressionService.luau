--!strict
-- XP, levels (1..10), spell unlocks, daily login streak, first-win bonus,
-- and daily quests. The only place that mutates profile.xp / level / owned.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LevelCurve = require(ReplicatedStorage.Shared.Progression.LevelCurve)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerDataService = require(script.Parent.PlayerDataService)

local ProgressionService = {}

-- Quest templates; three are picked per day. `event` matches ProgressionService.track().
local QUEST_POOL = {
	{ id = "cast25", text = "Cast 25 spells", event = "cast", goal = 25, rewardXp = 60 },
	{ id = "ko5", text = "Knock out 5 opponents", event = "knockout", goal = 5, rewardXp = 80 },
	{ id = "win2", text = "Win 2 matches", event = "win", goal = 2, rewardXp = 100 },
	{ id = "play3", text = "Play 3 matches", event = "match", goal = 3, rewardXp = 60 },
	{ id = "place10", text = "Place 10 objects", event = "place", goal = 10, rewardXp = 50 },
	{ id = "break10", text = "Destroy 10 objects", event = "destroy", goal = 10, rewardXp = 60 },
	{
		id = "draft3",
		text = "Draft 3 Rare or better spells",
		event = "draftRare",
		goal = 3,
		rewardXp = 70,
	},
}

local questEvents: { [string]: string } = {}
for _, q in QUEST_POOL do
	questEvents[q.id] = q.event
end

local toastRemote: RemoteEvent
local profileRemote: RemoteEvent

local function today(): number
	return math.floor(os.time() / 86400)
end

local function sendSummary(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	local into, needed = LevelCurve.progress(profile.xp)
	profileRemote:FireClient(player, {
		level = profile.level,
		xp = profile.xp,
		xpInto = into,
		xpNeeded = needed,
		ownedSpells = profile.ownedSpells,
		quests = profile.daily.quests,
		streak = profile.daily.streak,
		stats = profile.stats,
	})
end
ProgressionService.sendSummary = sendSummary

local function refreshDaily(player: Player, profile: Types.Profile)
	local day = today()
	if profile.daily.lastLoginDay ~= day then
		if profile.daily.lastLoginDay == day - 1 then
			profile.daily.streak += 1
		else
			profile.daily.streak = 1
		end
		profile.daily.lastLoginDay = day
		local bonus = Config.XP.DAILY_LOGIN * math.min(profile.daily.streak, 7)
		task.delay(3, function()
			if player.Parent then
				toastRemote:FireClient(
					player,
					`Daily chest! Day {profile.daily.streak} streak: +{bonus} XP`,
					"reward"
				)
				ProgressionService.addXp(player, bonus, "daily")
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
					rewardXp = q.rewardXp,
					claimed = false,
				})
			end
		end
		profile.daily.quests = quests
	end
end

-- Makes sure the profile owns every spell its level grants (also repairs
-- profiles if spells get added to earlier levels later).
local function syncUnlocks(profile: Types.Profile): { string }
	local owned: { [string]: boolean } = {}
	for _, id in profile.ownedSpells do
		owned[id] = true
	end
	local newlyUnlocked = {}
	for _, id in LevelCurve.spellsForLevel(profile.level) do
		if not owned[id] then
			table.insert(profile.ownedSpells, id)
			table.insert(newlyUnlocked, id)
		end
	end
	-- Drop ids that no longer exist in the dictionary.
	for i = #profile.ownedSpells, 1, -1 do
		if SpellDefinitions.get(profile.ownedSpells[i]) == nil then
			table.remove(profile.ownedSpells, i)
		end
	end
	return newlyUnlocked
end

function ProgressionService.addXp(player: Player, amount: number, _reason: string)
	local profile = PlayerDataService.get(player)
	if not profile or amount <= 0 then
		return
	end
	local before = profile.level
	profile.xp += math.floor(amount)
	profile.level = LevelCurve.levelForXp(profile.xp)
	if profile.level > before then
		local unlocked = syncUnlocks(profile)
		local names = {}
		for _, id in unlocked do
			local def = SpellDefinitions.get(id)
			if def then
				table.insert(names, def.name)
			end
		end
		local suffix = if #names > 0 then " New spells: " .. table.concat(names, ", ") else ""
		toastRemote:FireClient(player, `Level up! You're level {profile.level}.{suffix}`, "levelup")
	end
	sendSummary(player)
end

-- Progresses daily quests; `event` is one of the QUEST_POOL event names.
function ProgressionService.track(player: Player, event: string, amount: number?)
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
function ProgressionService.consumeFirstWin(player: Player): boolean
	local profile = PlayerDataService.get(player)
	if not profile or profile.daily.lastFirstWinDay == today() then
		return false
	end
	profile.daily.lastFirstWinDay = today()
	return true
end

function ProgressionService.init()
	toastRemote = Remotes.get("Toast")
	profileRemote = Remotes.get("ProfileUpdated")
end

function ProgressionService.start()
	PlayerDataService.ProfileLoaded:Connect(function(player, profile)
		profile.level = LevelCurve.levelForXp(profile.xp)
		syncUnlocks(profile)
		refreshDaily(player, profile)
		sendSummary(player)
	end)

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
				ProgressionService.addXp(player, quest.rewardXp, "quest")
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

return ProgressionService
