--!strict
-- Which spells each player can draw right now, and their cast cooldowns.
--
-- Nothing is ever stored: a recognized drawing casts its spell at once
-- (SpellInputService -> CastService). This service only answers "may this
-- spell be cast now?":
-- * Outside a match: the player's loadout (their element's three base spells
--   plus up to two equipped chest spells).
-- * Match: the same loadout (MatchService sets the spellbook at the start).
-- * Every spell has its own cast cooldown, plus a short global lockout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local ElementService = require(script.Parent.ElementService)
local PlayerDataService = require(script.Parent.PlayerDataService)

type State = {
	spellbook: { string }?,
	cooldowns: { [string]: number }, -- spellId -> os.clock() when it can be cast again
	lastCast: number,
	freeCasting: boolean, -- admin: no cooldowns
}

local SpellbookService = {}

local states: { [Player]: State } = {}
local spellbookRemote: RemoteEvent
local cooldownRemote: RemoteEvent

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = {
			spellbook = nil,
			cooldowns = {},
			lastCast = 0,
			freeCasting = false,
		}
		states[player] = state
	end
	return state
end

local function push(player: Player)
	spellbookRemote:FireClient(player, stateOf(player).spellbook)
end

-- The spells this player can draw: this match's spellbook, or their loadout.
function SpellbookService.drawable(player: Player): { string }
	return stateOf(player).spellbook or ElementService.loadout(player)
end

function SpellbookService.isInMatch(player: Player): boolean
	return stateOf(player).spellbook ~= nil
end

function SpellbookService.setSpellbook(player: Player, spellbook: { string })
	local state = stateOf(player)
	state.spellbook = table.clone(spellbook)
	state.cooldowns = {}
	push(player)
end

function SpellbookService.clearMatch(player: Player)
	-- A player leaving mid-match lands here after PlayerRemoving may have
	-- dropped their state: don't create it again.
	local state = states[player]
	if not state then
		return
	end
	state.spellbook = nil
	state.cooldowns = {}
	push(player)
end

-- Global cast lockout (anti-macro) + the spell's cast cooldown.
-- Returns (ok, secondsLeft).
function SpellbookService.checkCast(player: Player, spellId: string): (boolean, number)
	local state = stateOf(player)
	local now = os.clock()
	local since = now - state.lastCast
	if since < Config.GLOBAL_CAST_LOCKOUT then
		return false, Config.GLOBAL_CAST_LOCKOUT - since
	end
	local readyAt = state.cooldowns[spellId] or 0
	if now < readyAt then
		return false, readyAt - now
	end
	return true, 0
end

-- Records a cast: starts the lockout and the spell's cooldown.
function SpellbookService.startCooldown(player: Player, spellId: string, seconds: number)
	local state = stateOf(player)
	local now = os.clock()
	state.lastCast = now
	if state.freeCasting then
		seconds = 0
	end
	state.cooldowns[spellId] = now + seconds
	if seconds > 0 then
		-- Server-time timestamp the client compares against workspace:GetServerTimeNow().
		cooldownRemote:FireClient(player, spellId, workspace:GetServerTimeNow() + seconds)
	end
end

function SpellbookService.resetCooldowns(player: Player)
	stateOf(player).cooldowns = {}
end

-- Admin: no cast cooldowns for this player.
function SpellbookService.setFreeCasting(player: Player, enabled: boolean)
	local state = stateOf(player)
	state.freeCasting = enabled
	if enabled then
		state.cooldowns = {}
	end
end

function SpellbookService.init()
	ElementService.setLockCheck(SpellbookService.isInMatch)
	spellbookRemote = Remotes.get("SpellbookUpdated")
	cooldownRemote = Remotes.get("CooldownStarted")
end

function SpellbookService.start()
	PlayerDataService.ProfileLoaded:Connect(push)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return SpellbookService
