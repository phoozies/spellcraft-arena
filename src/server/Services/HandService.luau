--!strict
-- Each player's hand (the spells they can say right now), which spell is
-- readied, and cooldowns.
--
-- * In the hub the hand is a rolling set of the player's OWNED spells:
--   saying any owned spell adds it (oldest drops off past MAX_HAND).
-- * In a match the hand is fixed by MatchService (3 random owned, +1 per
--   draft); saying a spell outside it fizzles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local PlayerDataService = require(script.Parent.PlayerDataService)

type State = {
	hubHand: { string },
	matchHand: { string }?,
	readied: string?,
	cooldowns: { [string]: number },
	lastCast: number,
}

local HandService = {}

local states: { [Player]: State } = {}
local handRemote: RemoteEvent
local cooldownRemote: RemoteEvent

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = { hubHand = {}, matchHand = nil, readied = nil, cooldowns = {}, lastCast = 0 }
		states[player] = state
	end
	return state
end

function HandService.getHand(player: Player): { string }
	local state = stateOf(player)
	return state.matchHand or state.hubHand
end

function HandService.isInMatch(player: Player): boolean
	return stateOf(player).matchHand ~= nil
end

local function push(player: Player)
	local state = stateOf(player)
	handRemote:FireClient(player, HandService.getHand(player), state.readied)
end

local function owns(player: Player, spellId: string): boolean
	local profile = PlayerDataService.get(player)
	return profile ~= nil and table.find(profile.ownedSpells, spellId) ~= nil
end

function HandService.setMatchHand(player: Player, hand: { string })
	local state = stateOf(player)
	state.matchHand = table.clone(hand)
	state.readied = hand[1]
	state.cooldowns = {}
	push(player)
end

function HandService.addToMatchHand(player: Player, spellId: string): boolean
	local state = stateOf(player)
	local hand = state.matchHand
	if not hand or #hand >= Config.MAX_HAND or table.find(hand, spellId) then
		return false
	end
	table.insert(hand, spellId)
	push(player)
	return true
end

function HandService.clearMatchHand(player: Player)
	local state = stateOf(player)
	state.matchHand = nil
	state.readied = state.hubHand[1]
	state.cooldowns = {}
	push(player)
end

-- Readies a spell by id. Returns (ok, reason).
function HandService.ready(player: Player, spellId: string): (boolean, string?)
	local def = SpellDefinitions.get(spellId)
	if not def then
		return false, "Unknown spell."
	end
	local state = stateOf(player)
	local hand = HandService.getHand(player)
	if not table.find(hand, spellId) then
		if state.matchHand then
			return false, `{def.name} isn't in your hand this match. Draft it next round!`
		end
		if not owns(player, spellId) then
			return false, `You haven't unlocked {def.name} yet (level {def.unlockLevel}).`
		end
		table.insert(state.hubHand, spellId)
		while #state.hubHand > Config.MAX_HAND do
			table.remove(state.hubHand, 1)
		end
	end
	state.readied = spellId
	push(player)
	return true, nil
end

function HandService.selectSlot(player: Player, slot: number)
	local hand = HandService.getHand(player)
	local id = hand[slot]
	if id then
		stateOf(player).readied = id
		push(player)
	end
end

function HandService.getReadied(player: Player): string?
	return stateOf(player).readied
end

-- Checks global lockout + per-spell cooldown. Returns (ok, secondsLeft).
function HandService.checkCooldown(player: Player, spellId: string): (boolean, number)
	local state = stateOf(player)
	local now = os.clock()
	if now - state.lastCast < Config.GLOBAL_CAST_LOCKOUT then
		return false, Config.GLOBAL_CAST_LOCKOUT - (now - state.lastCast)
	end
	local readyAt = state.cooldowns[spellId] or 0
	if now < readyAt then
		return false, readyAt - now
	end
	return true, 0
end

function HandService.startCooldown(player: Player, spellId: string, seconds: number)
	local state = stateOf(player)
	local now = os.clock()
	state.lastCast = now
	state.cooldowns[spellId] = now + seconds
	-- Send as a server-time timestamp the client can compare against workspace:GetServerTimeNow().
	cooldownRemote:FireClient(player, spellId, workspace:GetServerTimeNow() + seconds)
end

function HandService.resetCooldowns(player: Player)
	stateOf(player).cooldowns = {}
end

function HandService.refresh(player: Player)
	push(player)
end

function HandService.init()
	handRemote = Remotes.get("HandUpdated")
	cooldownRemote = Remotes.get("CooldownStarted")
end

function HandService.start()
	PlayerDataService.ProfileLoaded:Connect(function(player, profile)
		local state = stateOf(player)
		state.hubHand = {}
		for i = 1, math.min(Config.STARTING_HAND, #profile.ownedSpells) do
			table.insert(state.hubHand, profile.ownedSpells[i])
		end
		state.readied = state.hubHand[1]
		push(player)
	end)

	local lastSelect: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
	Remotes.get("SelectSlot").OnServerEvent:Connect(function(player, slot)
		local now = os.clock()
		if now - (lastSelect[player] or 0) < 0.08 then
			return
		end
		lastSelect[player] = now
		if typeof(slot) == "number" and slot == slot and slot >= 1 and slot <= Config.MAX_HAND then
			HandService.selectSlot(player, math.floor(slot))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return HandService
