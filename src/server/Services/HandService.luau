--!strict
-- Each player's held spell COPIES (the hotbar), which slot is readied, and
-- per-spell cast cooldowns.
--
-- Copy model:
-- * Drawing a spell's glyph adds ONE copy of that spell to the
--   hotbar. A player can hold up to MAX_HAND (5) copies in any mix —
--   including five of the same spell.
-- * Casting uses a copy up; draw it again to get more.
-- * All copies of the same spell share one cast cooldown (its `cooldown`):
--   after casting a Fireball, your other Fireballs wait for it.
-- * SpellInputService adds a 1s cooldown between drawings.
-- * Every copy remembers how well it was drawn (quality 0..1, see
--   Spells/Quality); CastService scales the spell by it when the copy is cast.
--
-- Which spells work:
-- * Hub: the five spells of the player's equipped element.
-- * Match: the same five (MatchService sets the spellbook at the start).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local ElementService = require(script.Parent.ElementService)
local PlayerDataService = require(script.Parent.PlayerDataService)

type State = {
	copies: { string }, -- hotbar slots, duplicates allowed
	qualities: { number }, -- drawing quality of each copy (parallel to copies)
	spellbook: { string }?,
	readiedSlot: number?,
	cooldowns: { [string]: number }, -- spellId -> os.clock() when it can be cast again
	lastCast: number,
	freeCasting: boolean, -- admin: no cooldowns
}

local HandService = {}

local states: { [Player]: State } = {}
local handRemote: RemoteEvent
local cooldownRemote: RemoteEvent

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = {
			copies = {},
			qualities = {},
			spellbook = nil,
			readiedSlot = nil,
			cooldowns = {},
			lastCast = 0,
			freeCasting = false,
		}
		states[player] = state
	end
	return state
end

local function push(player: Player)
	local state = stateOf(player)
	handRemote:FireClient(player, state.copies, state.readiedSlot, state.spellbook, state.qualities)
end

-- A spell is drawable in the hub when it belongs to the equipped element.
local function owns(player: Player, spellId: string): boolean
	local def = SpellDefinitions.get(spellId)
	return def ~= nil and ElementService.equipped(player) == def.element
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
	state.qualities = {}
	state.readiedSlot = nil
	state.cooldowns = {}
	push(player)
end

function HandService.clearMatch(player: Player)
	local state = stateOf(player)
	state.spellbook = nil
	state.copies = {}
	state.qualities = {}
	state.readiedSlot = nil
	state.cooldowns = {}
	push(player)
end

function HandService.cooldownLeft(player: Player, spellId: string): number
	local state = stateOf(player)
	return math.max(0, (state.cooldowns[spellId] or 0) - os.clock())
end

-- Adds one copy of a spell (from a drawing) and readies it. `quality` (0..1,
-- default Config.QUALITY.DEFAULT) is how well it was drawn.
-- Returns (ok, reason). `bypass` (admin give) skips spellbook/ownership.
function HandService.grant(
	player: Player,
	spellId: string,
	bypass: boolean?,
	quality: number?
): (boolean, string?)
	local def = SpellDefinitions.get(spellId)
	if not def then
		return false, "Unknown spell."
	end
	local state = stateOf(player)
	if not bypass then
		if state.spellbook then
			if not table.find(state.spellbook, spellId) then
				return false, `{def.name} isn't in your spellbook this match. Draft it next round!`
			end
		elseif not owns(player, spellId) then
			if not ElementService.equipped(player) then
				return false, "Pick your first element in the Spellbook!"
			end
			if ElementService.owns(player, def.element) then
				return false, `{def.name} is a {def.element} spell. Equip {def.element} in the Spellbook!`
			end
			return false, `You haven't unlocked {def.element} yet. Open an Element Crate in the hub!`
		end
	end
	if #state.copies >= Config.MAX_HAND then
		return false, `Your hands are full ({Config.MAX_HAND} spells). Cast one first!`
	end
	table.insert(state.copies, spellId)
	table.insert(state.qualities, math.clamp(quality or Config.QUALITY.DEFAULT, 0, 1))
	state.readiedSlot = #state.copies
	push(player)
	return true, nil
end

-- Uses up the readied copy after a successful cast. Readies another copy
-- of the same spell if there is one (so you can keep firing), otherwise
-- the slot that slid into place.
function HandService.consume(player: Player)
	local state = stateOf(player)
	local slot = state.readiedSlot
	if not slot or not state.copies[slot] then
		return
	end
	local spellId = table.remove(state.copies, slot)
	table.remove(state.qualities, slot)
	local nextSame = table.find(state.copies, spellId)
	if nextSame then
		state.readiedSlot = nextSame
	elseif #state.copies > 0 then
		state.readiedSlot = math.min(slot, #state.copies)
	else
		state.readiedSlot = nil
	end
	push(player)
end

function HandService.clearCopies(player: Player)
	local state = stateOf(player)
	state.copies = {}
	state.qualities = {}
	state.readiedSlot = nil
	push(player)
end

function HandService.selectSlot(player: Player, slot: number)
	local state = stateOf(player)
	if state.copies[slot] then
		state.readiedSlot = slot
		push(player)
	end
end

-- The spell in the readied slot, if any.
function HandService.getReadied(player: Player): string?
	local state = stateOf(player)
	local slot = state.readiedSlot
	return if slot then state.copies[slot] else nil
end

-- How well the readied copy was drawn (0..1).
function HandService.getReadiedQuality(player: Player): number
	local state = stateOf(player)
	local slot = state.readiedSlot
	return (if slot then state.qualities[slot] else nil) or Config.QUALITY.DEFAULT
end

-- Global cast lockout (anti-macro) + the spell's shared cast cooldown.
-- Returns (ok, secondsLeft).
function HandService.checkCast(player: Player, spellId: string): (boolean, number)
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

-- Records a cast: starts the lockout and the spell's shared cooldown.
function HandService.startCooldown(player: Player, spellId: string, seconds: number)
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

function HandService.resetCooldowns(player: Player)
	stateOf(player).cooldowns = {}
end

-- Admin: no cast cooldowns for this player.
function HandService.setFreeCasting(player: Player, enabled: boolean)
	local state = stateOf(player)
	state.freeCasting = enabled
	if enabled then
		state.cooldowns = {}
	end
end

function HandService.refresh(player: Player)
	push(player)
end

function HandService.init()
	ElementService.setLockCheck(HandService.isInMatch)
	handRemote = Remotes.get("HandUpdated")
	cooldownRemote = Remotes.get("CooldownStarted")
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
