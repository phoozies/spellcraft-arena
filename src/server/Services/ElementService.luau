--!strict
-- Which elements and chest spells a player owns, which element is equipped,
-- and the loadout of extra spells.
--
--   * The FIRST element is a free pick (ChooseElement), any of the four.
--   * Every other element is BOUGHT with coins (BuyElement, price in
--     Spells/Elements). Owned elements can be switched in the hub.
--   * Chest spells are won from the Chest Shop (ChestService calls
--     ElementService.grantSpell) and equipped in the loadout's two extra
--     slots (SetLoadout), next to the equipped element's three base spells.
--     A spell can't join a loadout that already holds a spell with the same
--     shape (Spells/Loadout).
--   * In a match the loadout is locked in: it is the match spellbook.
--
-- Owns profile.elements, profile.element, profile.spells and profile.loadout
-- (EconomyService only mirrors them to the client in its profile summary).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Loadout = require(ReplicatedStorage.Shared.Spells.Loadout)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local EconomyService = require(script.Parent.EconomyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local TelemetryService = require(script.Parent.TelemetryService)

local ElementService = {}

-- Fired with (player) whenever their owned or equipped elements or spells change.
ElementService.Changed = Signal.new() :: Signal.Signal<Player>

local toastRemote: RemoteEvent
-- Set by HandService: true while the player is locked into a match.
local lockCheck: ((Player) -> boolean)? = nil

function ElementService.setLockCheck(fn: (Player) -> boolean)
	lockCheck = fn
end

function ElementService.owned(player: Player): { string }
	local profile = PlayerDataService.get(player)
	return if profile then profile.elements else {}
end

function ElementService.owns(player: Player, elementId: string): boolean
	return table.find(ElementService.owned(player), elementId) ~= nil
end

-- The equipped element id, or nil before the first pick.
function ElementService.equipped(player: Player): string?
	local profile = PlayerDataService.get(player)
	if profile and profile.element ~= "" and Elements.get(profile.element) then
		return profile.element
	end
	return nil
end

-- Chest spells the player owns.
function ElementService.ownedSpells(player: Player): { string }
	local profile = PlayerDataService.get(player)
	return if profile then profile.spells else {}
end

-- The spells the player can draw: the equipped element's base spells, then
-- their loadout extras. Empty before the first element pick.
function ElementService.loadout(player: Player): { string }
	local profile = PlayerDataService.get(player)
	local elementId = ElementService.equipped(player)
	if not profile or not elementId then
		return {}
	end
	return Loadout.spells(elementId, profile.loadout)
end

local function lockedReason(player: Player): string?
	if lockCheck and lockCheck(player) then
		return "You can't change your spells during a match."
	end
	return nil
end

-- Unlocks an element (and equips it when it's the player's first). Returns
-- false if they already had it or it doesn't exist. The caller sends the
-- profile summary when it wants the client to see it.
function ElementService.grant(player: Player, elementId: string): boolean
	local profile = PlayerDataService.get(player)
	if not profile or not Elements.get(elementId) or table.find(profile.elements, elementId) then
		return false
	end
	table.insert(profile.elements, elementId)
	if profile.element == "" then
		profile.element = elementId
		profile.loadout = Loadout.sanitize(elementId, profile.loadout, profile.spells)
	end
	ElementService.Changed:Fire(player)
	return true
end

-- Buys an element with coins. Returns (ok, reason).
function ElementService.buy(player: Player, elementId: string): (boolean, string?)
	local profile = PlayerDataService.get(player)
	local element = Elements.get(elementId)
	if not profile then
		return false, "Your spellbook is still loading."
	end
	if not element then
		return false, "That element doesn't exist."
	end
	if #profile.elements == 0 then
		return false, "Your first element is free: just choose it!"
	end
	if table.find(profile.elements, elementId) then
		return false, `You already own {elementId}.`
	end
	local locked = lockedReason(player)
	if locked then
		return false, locked
	end
	if profile.coins < element.price then
		return false, `You need {element.price - profile.coins} more coins for {elementId}.`
	end
	if not EconomyService.spend(player, element.price, `element:{elementId}`) then
		return false, "Not enough coins."
	end
	ElementService.grant(player, elementId)
	TelemetryService.onboarding(player, "FirstElementBought")
	return true, nil
end

-- Equips an owned element. Extras that no longer fit its base spells (same
-- shape) drop out of the loadout. Returns (ok, reason).
function ElementService.equip(player: Player, elementId: string): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Your spellbook is still loading."
	end
	if not Elements.get(elementId) then
		return false, "That element doesn't exist."
	end
	local locked = lockedReason(player)
	if locked then
		return false, locked
	end
	if not table.find(profile.elements, elementId) then
		return false, `You don't own {elementId} yet. Buy it in the Spellbook!`
	end
	if profile.element ~= elementId then
		profile.element = elementId
		profile.loadout = Loadout.sanitize(elementId, profile.loadout, profile.spells)
		ElementService.Changed:Fire(player)
	end
	return true, nil
end

-- Puts `spellId` into extra slot `slot` (1..MAX_EXTRA), or empties the slot when
-- it is nil. Returns (ok, reason).
function ElementService.setExtra(player: Player, slot: number, spellId: string?): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Your spellbook is still loading."
	end
	local elementId = ElementService.equipped(player)
	if not elementId then
		return false, "Pick your first element first!"
	end
	if slot < 1 or slot > Loadout.MAX_EXTRA or slot ~= math.floor(slot) then
		return false, "That loadout slot doesn't exist."
	end
	local locked = lockedReason(player)
	if locked then
		return false, locked
	end
	-- Work on a copy; slot positions stay put until the list is packed below.
	local extras: { [number]: string? } = {}
	for index = 1, Loadout.MAX_EXTRA do
		extras[index] = profile.loadout[index]
	end
	if spellId == nil then
		extras[slot] = nil
	else
		local def = SpellDefinitions.get(spellId)
		if not def or not def.rarity then
			return false, "Only chest spells go in the loadout."
		end
		if not table.find(profile.spells, spellId) then
			return false, `You don't own {def.name} yet. Open a chest!`
		end
		-- The other extra and the base spells are what it has to fit beside.
		local others = Loadout.spells(elementId, {})
		for index = 1, Loadout.MAX_EXTRA do
			local other = extras[index]
			if index ~= slot and other and other ~= spellId then
				table.insert(others, other)
			end
		end
		local problem = Loadout.problem(spellId, others)
		if problem then
			return false, problem
		end
		extras[slot] = spellId
	end
	local packed: { string } = {}
	for index = 1, Loadout.MAX_EXTRA do
		local id = extras[index]
		if id and not table.find(packed, id) then
			table.insert(packed, id)
		end
	end
	profile.loadout = packed
	ElementService.Changed:Fire(player)
	return true, nil
end

-- Adds a won chest spell to the collection. Returns (isNew, equipped): `isNew` is
-- false for a duplicate; `equipped` is true when it went straight into an
-- empty loadout slot (so a first spin is usable right away).
function ElementService.grantSpell(player: Player, spellId: string): (boolean, boolean)
	local profile = PlayerDataService.get(player)
	local def = SpellDefinitions.get(spellId)
	if not profile or not def or not def.rarity then
		return false, false
	end
	if table.find(profile.spells, spellId) then
		return false, false
	end
	table.insert(profile.spells, spellId)
	local equipped = false
	local elementId = ElementService.equipped(player)
	if elementId and #profile.loadout < Loadout.MAX_EXTRA and not lockedReason(player) then
		local others = Loadout.spells(elementId, profile.loadout)
		if Loadout.problem(spellId, others) == nil then
			table.insert(profile.loadout, spellId)
			equipped = true
		end
	end
	ElementService.Changed:Fire(player)
	return true, equipped
end

-- Admin reset: "elements" forgets every owned element (the next pick is free
-- again), "spells" forgets every chest spell and empties the loadout.
-- Returns false for an unknown scope.
function ElementService.reset(player: Player, scope: string): boolean
	local profile = PlayerDataService.get(player)
	if not profile then
		return false
	end
	if scope == "elements" then
		profile.elements = {}
		profile.element = ""
	elseif scope == "spells" then
		profile.spells = {}
		profile.loadout = {}
	else
		return false
	end
	ElementService.Changed:Fire(player)
	EconomyService.sendSummary(player)
	return true
end

function ElementService.init()
	toastRemote = Remotes.get("Toast")
end

function ElementService.start()
	-- (elementId) -> picks the free first element, or equips an owned one.
	Remotes.get("ChooseElement").OnServerEvent:Connect(function(player, elementId)
		if typeof(elementId) ~= "string" or #elementId > 16 then
			return
		end
		local profile = PlayerDataService.get(player)
		if not profile or not Elements.get(elementId) then
			return
		end
		if #profile.elements == 0 then
			ElementService.grant(player, elementId)
			TelemetryService.onboarding(player, "ElementPicked")
			toastRemote:FireClient(
				player,
				`You chose {elementId}! Draw its shapes to cast.`,
				"reward"
			)
		else
			local ok, reason = ElementService.equip(player, elementId)
			if not ok and reason then
				toastRemote:FireClient(player, reason, "fizzle")
				return
			end
			toastRemote:FireClient(player, `{elementId} equipped.`, "ready")
		end
		EconomyService.sendSummary(player)
	end)

	-- (elementId) -> buys an element with coins.
	Remotes.get("BuyElement").OnServerEvent:Connect(function(player, elementId)
		if typeof(elementId) ~= "string" or #elementId > 16 then
			return
		end
		local ok, reason = ElementService.buy(player, elementId)
		if ok then
			toastRemote:FireClient(
				player,
				`{elementId} is yours! Equip it in the Spellbook.`,
				"reward"
			)
		elseif reason then
			toastRemote:FireClient(player, reason, "fizzle")
		end
		EconomyService.sendSummary(player)
	end)

	-- (slot, spellId?) -> equips a chest spell in an extra slot, or empties it.
	Remotes.get("SetLoadout").OnServerEvent:Connect(function(player, slot, spellId)
		if typeof(slot) ~= "number" or slot ~= slot then
			return
		end
		if spellId ~= nil and (typeof(spellId) ~= "string" or #spellId > 32) then
			return
		end
		local ok, reason = ElementService.setExtra(player, slot, spellId)
		if not ok and reason then
			toastRemote:FireClient(player, reason, "fizzle")
		end
		EconomyService.sendSummary(player)
	end)
end

return ElementService
