--!strict
-- Each player's held spell COPIES (the hotbar), which slot is readied, and
-- per-spell cast cooldowns.
--
-- Copy model:
-- * The hotbar has MAX_HAND fixed slots; slot N belongs to the Nth spell of
--   the loadout (the number keys 1-5). Drawing a spell's glyph puts ONE copy
--   of it in its own slot, even if the slots before it are empty. A player
--   holds at most ONE copy of each spell. Empty slots are "" (so the array
--   survives the trip to the client).
-- * Casting uses the copy up; draw it again to get another.
-- * SpellInputService adds a 1s cooldown between drawings.
-- * Every copy remembers how well it was drawn (quality 0..1, see
--   Spells/Quality); CastService scales the spell by it when the copy is cast.
--
-- Which spells work:
-- * Outside a match: the player's loadout (their element's three base spells
--   plus up to two equipped chest spells).
-- * Match: the same loadout (MatchService sets the spellbook at the start).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local ElementService = require(script.Parent.ElementService)
local PlayerDataService = require(script.Parent.PlayerDataService)

type State = {
	copies: { string }, -- hotbar slots (MAX_HAND long, "" = empty)
	qualities: { number }, -- drawing quality of each copy (parallel to copies, 0 = empty)
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

local function emptySlots(fill: any): any
	local slots = {}
	for i = 1, Config.MAX_HAND do
		slots[i] = fill
	end
	return slots
end

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = {
			copies = emptySlots(""),
			qualities = emptySlots(0),
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

-- A spell is drawable outside a match when it is in the player's loadout: the
-- equipped element's base spells and their equipped chest spells.
local function owns(player: Player, spellId: string): boolean
	return table.find(ElementService.loadout(player), spellId) ~= nil
end

-- The spells the hotbar slots follow: this match's spellbook, or the loadout.
local function slotOrder(player: Player, state: State): { string }
	return state.spellbook or ElementService.loadout(player)
end

local function firstHeld(state: State): number?
	for i, id in state.copies do
		if id ~= "" then
			return i
		end
	end
	return nil
end

-- Spell copies the player is holding (hotbar order, no empty slots).
function HandService.getCopies(player: Player): { string }
	local held = {}
	for _, id in stateOf(player).copies do
		if id ~= "" then
			table.insert(held, id)
		end
	end
	return held
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
	state.copies = emptySlots("")
	state.qualities = emptySlots(0)
	state.readiedSlot = nil
	state.cooldowns = {}
	push(player)
end

function HandService.clearMatch(player: Player)
	local state = stateOf(player)
	state.spellbook = nil
	state.copies = emptySlots("")
	state.qualities = emptySlots(0)
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
			if def.rarity then
				return false,
					`{def.name} isn't in your loadout. Equip it in the Spellbook, or open a chest!`
			end
			return false,
				`{def.name} is a {def.element} spell. Buy or equip {def.element} in the Spellbook!`
		end
	end
	if table.find(state.copies, spellId) then
		return false, `You already hold {def.name}. Cast it first!`
	end
	-- The copy goes in its spell's own slot (a spell outside the loadout, from
	-- an admin give, takes the first free one).
	local slot = table.find(slotOrder(player, state), spellId)
	if not slot or slot > Config.MAX_HAND or state.copies[slot] ~= "" then
		slot = table.find(state.copies, "")
	end
	if not slot then
		return false, `Your hands are full ({Config.MAX_HAND} spells). Cast one first!`
	end
	state.copies[slot] = spellId
	state.qualities[slot] = math.clamp(quality or Config.QUALITY.DEFAULT, 0, 1)
	state.readiedSlot = slot
	push(player)
	return true, nil
end

-- Uses up the readied copy after a successful cast. The slot stays where it
-- is (now empty) and the next held copy is readied.
function HandService.consume(player: Player)
	local state = stateOf(player)
	local slot = state.readiedSlot
	if not slot or (state.copies[slot] or "") == "" then
		return
	end
	state.copies[slot] = ""
	state.qualities[slot] = 0
	state.readiedSlot = firstHeld(state)
	push(player)
end

function HandService.clearCopies(player: Player)
	local state = stateOf(player)
	state.copies = emptySlots("")
	state.qualities = emptySlots(0)
	state.readiedSlot = nil
	push(player)
end

function HandService.selectSlot(player: Player, slot: number)
	local state = stateOf(player)
	if (state.copies[slot] or "") ~= "" then
		state.readiedSlot = slot
		push(player)
	end
end

-- The spell in the readied slot, if any.
function HandService.getReadied(player: Player): string?
	local state = stateOf(player)
	local slot = state.readiedSlot
	local id = if slot then state.copies[slot] else nil
	return if id and id ~= "" then id else nil
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

	-- Changing element or loadout outside a match drops held copies of spells
	-- that are no longer drawable.
	ElementService.Changed:Connect(function(player)
		local state = stateOf(player)
		if state.spellbook then
			return
		end
		-- Re-seat the copies still in the loadout in their new slots.
		local loadout = ElementService.loadout(player)
		local copies, qualities = emptySlots(""), emptySlots(0)
		local changed = false
		for index, id in state.copies do
			if id ~= "" then
				local slot = table.find(loadout, id)
				if slot and slot <= Config.MAX_HAND then
					copies[slot] = id
					qualities[slot] = state.qualities[index]
				end
				changed = changed or slot ~= index
			end
		end
		if changed then
			state.copies, state.qualities = copies, qualities
			state.readiedSlot = firstHeld(state)
			push(player)
		end
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
