--!strict
-- Each player's held spell COPIES, which one is readied, and recharges.
--
-- Copy model:
-- * Typing (or saying) a spell word grants ONE copy of that spell. A player
--   can never hold two copies of the same spell.
-- * Casting uses the copy up; type the word again to get it back.
-- * After a cast the spell recharges (its `cooldown`) before its word works
--   again. SpellInputService adds a 1s typing cooldown between any words.
--
-- Which words work:
-- * Hub: any spell the player owns. Holding is capped at MAX_HAND copies;
--   the oldest copy drops when a new one is added.
-- * Match: only words in the player's match spellbook (3 random owned
--   spells, +1 per draft, max 5). MatchService sets it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local PlayerDataService = require(script.Parent.PlayerDataService)

type State = {
	copies: { string },
	spellbook: { string }?,
	readied: string?,
	recharges: { [string]: number }, -- spellId -> os.clock() when it can be typed again
	lastCast: number,
	freeCasting: boolean, -- admin: no recharges
}

local HandService = {}

local states: { [Player]: State } = {}
local handRemote: RemoteEvent
local rechargeRemote: RemoteEvent

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = {
			copies = {},
			spellbook = nil,
			readied = nil,
			recharges = {},
			lastCast = 0,
			freeCasting = false,
		}
		states[player] = state
	end
	return state
end

local function push(player: Player)
	local state = stateOf(player)
	handRemote:FireClient(player, state.copies, state.readied, state.spellbook)
end

local function owns(player: Player, spellId: string): boolean
	local profile = PlayerDataService.get(player)
	return profile ~= nil and table.find(profile.ownedSpells, spellId) ~= nil
end

-- Spell copies the player is holding (hotbar order).
function HandService.getCopies(player: Player): { string }
	return stateOf(player).copies
end

-- Words allowed this match, or nil in the hub (any owned spell).
function HandService.getSpellbook(player: Player): { string }?
	return stateOf(player).spellbook
end

function HandService.isInMatch(player: Player): boolean
	return stateOf(player).spellbook ~= nil
end

function HandService.setSpellbook(player: Player, spellbook: { string })
	local state = stateOf(player)
	state.spellbook = table.clone(spellbook)
	state.copies = {}
	state.readied = nil
	state.recharges = {}
	push(player)
end

function HandService.addToSpellbook(player: Player, spellId: string): boolean
	local state = stateOf(player)
	local book = state.spellbook
	if not book or #book >= Config.MAX_HAND or table.find(book, spellId) then
		return false
	end
	table.insert(book, spellId)
	push(player)
	return true
end

function HandService.clearMatch(player: Player)
	local state = stateOf(player)
	state.spellbook = nil
	state.copies = {}
	state.readied = nil
	state.recharges = {}
	push(player)
end

function HandService.rechargeLeft(player: Player, spellId: string): number
	local state = stateOf(player)
	return math.max(0, (state.recharges[spellId] or 0) - os.clock())
end

-- Grants one copy of a spell (from typing/voice) and readies it.
-- Returns (ok, reason). Holding a copy already just readies it.
-- `bypass` (admin give) skips spellbook/ownership/recharge checks.
function HandService.grant(player: Player, spellId: string, bypass: boolean?): (boolean, string?)
	local def = SpellDefinitions.get(spellId)
	if not def then
		return false, "Unknown spell."
	end
	local state = stateOf(player)
	if table.find(state.copies, spellId) then
		state.readied = spellId
		push(player)
		return true, `You already have {def.name}!`
	end
	if not bypass then
		if state.spellbook then
			if not table.find(state.spellbook, spellId) then
				return false, `{def.name} isn't in your spellbook this match. Draft it next round!`
			end
		elseif not owns(player, spellId) then
			return false, `You haven't unlocked {def.name} yet (level {def.unlockLevel}).`
		end
		local left = HandService.rechargeLeft(player, spellId)
		if left > 0 then
			return false, `{def.name} is recharging ({math.ceil(left * 10) / 10}s)`
		end
	end
	table.insert(state.copies, spellId)
	while #state.copies > Config.MAX_HAND do
		table.remove(state.copies, 1)
	end
	state.readied = spellId
	push(player)
	return true, nil
end

-- Uses up the copy after a successful cast and readies the next one.
function HandService.consume(player: Player, spellId: string)
	local state = stateOf(player)
	local index = table.find(state.copies, spellId)
	if index then
		table.remove(state.copies, index)
	end
	if state.readied == spellId then
		state.readied = state.copies[math.min(index or 1, #state.copies)]
	end
	push(player)
end

function HandService.clearCopies(player: Player)
	local state = stateOf(player)
	state.copies = {}
	state.readied = nil
	push(player)
end

function HandService.selectSlot(player: Player, slot: number)
	local state = stateOf(player)
	local id = state.copies[slot]
	if id then
		state.readied = id
		push(player)
	end
end

-- The readied spell, only if a copy is actually held.
function HandService.getReadied(player: Player): string?
	local state = stateOf(player)
	local id = state.readied
	if id and table.find(state.copies, id) then
		return id
	end
	return nil
end

-- Global cast lockout (anti-macro). Returns (ok, secondsLeft).
function HandService.checkCastLockout(player: Player): (boolean, number)
	local state = stateOf(player)
	local since = os.clock() - state.lastCast
	if since < Config.GLOBAL_CAST_LOCKOUT then
		return false, Config.GLOBAL_CAST_LOCKOUT - since
	end
	return true, 0
end

-- Records a cast: starts the lockout and the spell's recharge.
function HandService.startRecharge(player: Player, spellId: string, seconds: number)
	local state = stateOf(player)
	local now = os.clock()
	state.lastCast = now
	if state.freeCasting then
		seconds = 0
	end
	state.recharges[spellId] = now + seconds
	if seconds > 0 then
		-- Server-time timestamp the client compares against workspace:GetServerTimeNow().
		rechargeRemote:FireClient(player, spellId, workspace:GetServerTimeNow() + seconds)
	end
end

function HandService.resetRecharges(player: Player)
	stateOf(player).recharges = {}
end

-- Admin: no recharges for this player.
function HandService.setFreeCasting(player: Player, enabled: boolean)
	local state = stateOf(player)
	state.freeCasting = enabled
	if enabled then
		state.recharges = {}
	end
end

function HandService.refresh(player: Player)
	push(player)
end

function HandService.init()
	handRemote = Remotes.get("HandUpdated")
	rechargeRemote = Remotes.get("CooldownStarted")
end

function HandService.start()
	PlayerDataService.ProfileLoaded:Connect(function(player)
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
