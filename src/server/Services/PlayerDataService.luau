--!strict
-- Loads, session-locks, autosaves, and releases player profiles.
--
-- * Session lock: the profile record stores {lockJobId, lockTime}. A server
--   only loads a profile whose lock is free, its own, or stale (> LOCK_STALE),
--   which prevents two servers writing the same player (dupes / rollbacks).
-- * Every DataStore call is retried with exponential backoff.
-- * BindToClose flushes all profiles before shutdown.
-- * In Studio without API access the service falls back to a temporary
--   in-memory profile and never saves it (warns once).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Loadout = require(ReplicatedStorage.Shared.Spells.Loadout)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

type Profile = Types.Profile

local STORE_NAME = "PlayerProfiles_v1"
-- 2: levels/XP removed; coins added (crates unlock spells).
-- 3: spells come from elements: ownedSpells is gone, profile.elements and
--    profile.element replace it (players pick their first element again).
-- 4: settings.music (background music on/off) and rewards.likeFav (the
--    one-time Like & Favourite gift); both just get their defaults.
-- 5: elements are bought with coins and crates win SPELLS: profile.spells
--    (crate spells owned), profile.loadout (up to 2 equipped), and
--    profile.tutorial.done (players who already picked an element skip it).
-- 6: profile.pity (crate spins since the last Epic or better).
local SCHEMA = 6
-- Locks are refreshed every autosave, so a lock older than ~3 autosaves
-- means its server crashed; take it over.
local LOCK_STALE = 5 * 60
local MAX_RETRIES = 5

local PlayerDataService = {}

PlayerDataService.ProfileLoaded = Signal.new() :: Signal.Signal<Player, Profile>

local profiles: { [Player]: Profile } = {}
local persistent: { [Player]: boolean } = {}
local store: DataStore? = nil

local function defaultProfile(): Profile
	return {
		schema = SCHEMA,
		coins = Config.COINS.STARTING,
		elements = {},
		element = "",
		spells = {},
		loadout = {},
		tutorial = { done = false },
		cosmetics = {},
		stats = { matches = 0, wins = 0, knockouts = 0, casts = 0 },
		daily = { lastLoginDay = 0, streak = 0, lastFirstWinDay = 0, questDay = 0, quests = {} },
		settings = {
			drawKey = Config.DEFAULT_DRAW_KEY,
			music = true,
			sfx = true,
			shake = true,
		},
		rewards = { likeFav = false },
		pity = 0,
	}
end

-- Fills fields added after a profile was first saved; bump SCHEMA for
-- breaking changes and transform here.
local function reconcile(data: any): Profile
	local base = defaultProfile()
	if typeof(data) ~= "table" then
		return base
	end
	local previousSchema: number = data.schema or 1
	local hadTutorial = typeof(data.tutorial) == "table"
	if (data.schema or 1) < 2 then
		-- Schema 1 had levels: XP/level are gone, quests rewarded XP (re-roll
		-- them), and unlocked spells that no longer exist are dropped below.
		data.xp = nil
		data.level = nil
		if typeof(data.daily) == "table" then
			data.daily.questDay = 0
			data.daily.quests = {}
		end
	end
	for key, value in base :: any do
		if data[key] == nil then
			data[key] = value
		end
	end
	for key, value in base.stats :: any do
		if data.stats[key] == nil then
			data.stats[key] = value
		end
	end
	for key, value in base.daily :: any do
		if data.daily[key] == nil then
			data.daily[key] = value
		end
	end
	for key, value in base.settings :: any do
		if data.settings[key] == nil then
			data.settings[key] = value
		end
	end
	if typeof(data.rewards) ~= "table" then
		data.rewards = table.clone(base.rewards)
	end
	for key, value in base.rewards :: any do
		if data.rewards[key] == nil then
			data.rewards[key] = value
		end
	end
	if typeof(data.pity) ~= "number" or data.pity ~= data.pity or data.pity < 0 then
		data.pity = 0
	end
	data.pity = math.floor(data.pity)
	-- Spells are drawn now, not typed: the old "type a spell" key setting is gone.
	data.settings.typeKey = nil
	-- Elements: keep real, unique ones; the equipped element must be owned.
	data.ownedSpells = nil -- schema 2's spell list
	local owned = {}
	for _, id in data.elements do
		if typeof(id) == "string" and Elements.get(id) and not table.find(owned, id) then
			table.insert(owned, id)
		end
	end
	data.elements = owned
	if typeof(data.element) ~= "string" or not table.find(owned, data.element) then
		data.element = owned[1] or ""
	end
	-- Crate spells: real crate spells only, no repeats; the loadout is the owned
	-- ones that still fit next to the equipped element's base spells.
	local spells = {}
	if typeof(data.spells) == "table" then
		for _, id in data.spells do
			local def = if typeof(id) == "string" then SpellDefinitions.get(id) else nil
			if def and def.rarity and not table.find(spells, id) then
				table.insert(spells, id)
			end
		end
	end
	data.spells = spells
	data.loadout = Loadout.sanitize(data.element, data.loadout, spells)
	-- Players from before the tutorial existed have already found their way around.
	if not hadTutorial then
		data.tutorial = { done = previousSchema < 5 and data.element ~= "" }
	end
	data.tutorial.done = data.tutorial.done == true
	data.schema = SCHEMA
	return data :: Profile
end

local function retry<T>(label: string, fn: () -> T): (boolean, T | string)
	local delay = 1
	local lastError: any = nil
	-- Studio usually lacks API access; fail fast there instead of stalling ~30s.
	local attempts = if RunService:IsStudio() then 1 else MAX_RETRIES
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warn(`[PlayerData] {label} failed (attempt {attempt}): {result}`)
		task.wait(delay)
		delay = math.min(delay * 2, 16)
	end
	return false, tostring(lastError)
end

local function keyFor(player: Player): string
	return `u_{player.UserId}`
end

local function loadProfile(player: Player)
	local profile: Profile? = nil
	if store then
		local activeStore = store
		local ok, result = retry("load", function()
			local loaded: any = nil
			activeStore:UpdateAsync(keyFor(player), function(record: any)
				record = record or {}
				local lockFree = record.lockJobId == nil
					or record.lockJobId == game.JobId
					or os.time() - (record.lockTime or 0) > LOCK_STALE
				if not lockFree then
					error("profile locked by another server")
				end
				record.lockJobId = game.JobId
				record.lockTime = os.time()
				record.data = reconcile(record.data)
				loaded = record.data
				return record
			end)
			return loaded
		end)
		if ok then
			profile = result :: any
			persistent[player] = true
		else
			-- Don't risk overwriting real data: kick if we can't lock it.
			if not RunService:IsStudio() then
				player:Kick("We couldn't load your spellbook. Please rejoin in a moment!")
				return
			end
		end
	end
	if player.Parent == nil then
		-- Left while we were loading: release the lock we just took so they
		-- aren't locked out on rejoin.
		if persistent[player] and store then
			local activeStore = store
			pcall(function()
				activeStore:UpdateAsync(keyFor(player), function(record: any)
					if record and record.lockJobId == game.JobId then
						record.lockJobId = nil
						record.lockTime = nil
						return record
					end
					return nil
				end)
			end)
		end
		persistent[player] = nil
		return
	end
	if not profile then
		profile = defaultProfile()
	end
	local resolved = profile :: Profile
	profiles[player] = resolved
	PlayerDataService.ProfileLoaded:Fire(player, resolved)
end

local released: { [Player]: boolean } = {}

local function saveProfile(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not persistent[player] or not store or released[player] then
		return
	end
	if release then
		-- PlayerRemoving and BindToClose both release; only do it once.
		released[player] = true
	end
	local activeStore = store
	retry("save", function()
		activeStore:UpdateAsync(keyFor(player), function(record: any)
			record = record or {}
			if record.lockJobId ~= nil and record.lockJobId ~= game.JobId then
				-- Another server owns this profile now; never clobber it.
				return nil
			end
			record.data = profile
			if release then
				record.lockJobId = nil
				record.lockTime = nil
			else
				record.lockTime = os.time()
			end
			return record
		end)
		return true
	end)
end

function PlayerDataService.get(player: Player): Profile?
	return profiles[player]
end

-- Waits (up to `timeout` seconds) for a player's profile to load.
function PlayerDataService.await(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)
	while profiles[player] == nil and player.Parent ~= nil and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

function PlayerDataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStores unavailable, using temporary profiles: " .. tostring(result))
	end
end

function PlayerDataService.start()
	-- Deferred so every service's start() has connected to ProfileLoaded first.
	Players.PlayerAdded:Connect(function(player)
		task.defer(loadProfile, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(loadProfile, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		saveProfile(player, true)
		profiles[player] = nil
		persistent[player] = nil
		released[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(saveProfile, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveProfile(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerDataService
