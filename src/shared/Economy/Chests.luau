--!strict
-- The Chest Shop. Five chests, one per rarity (Common, Uncommon, Rare, Epic,
-- Legendary): a chest costs coins and wins one CHEST spell of its rarity or
-- better. First a rarity is rolled by weight (Spells/Rarity) among the ones
-- the chest can drop, then a spell of that rarity at random, so a Rare Chest
-- is a Rare 60% of the time, an Epic 30%, a Legendary 10%. Landing on a spell
-- you already own pays back some coins instead (always less than the chest).
-- Epic and Legendary chests never give a duplicate while a spell they can drop
-- is still unowned. Pure module (no services, an injectable RNG) so tests are
-- deterministic; the server's ChestService is the only caller that spends
-- coins or grants spells, and the client's ChestController only animates the
-- result the server sends.
--
-- Pity: every chest that doesn't land on PITY.RARITY or better adds one to the
-- player's pity counter (profile.pity, owned by ChestService); when the counter
-- reaches PITY.SPINS - 1 the next chest is guaranteed to be PITY.RARITY or
-- better (and a spell the player doesn't own yet, if one is left), and a hit
-- resets the counter. Epic and Legendary chests always reset it.
--
-- Elements are NOT in chests: a base element is bought directly with coins
-- (ElementService.buy, price in Spells/Elements).

local Rarity = require(script.Parent.Parent.Spells.Rarity)
local SpellDefinitions = require(script.Parent.Parent.Spells.SpellDefinitions)
local Types = require(script.Parent.Parent.Types)

type ChestDef = Types.ChestDef

local Chests = {}

-- Seconds the client's reel spins; the server won't accept another open
-- from the same player until this has passed.
Chests.SPIN_TIME = 4

-- Share of the chest's price a duplicate pays back (at least the rarity's own
-- `refund`, never the whole price).
Chests.REFUND_SHARE = 0.3

Chests.PITY = table.freeze({
	SPINS = 10, -- this many chests without PITY.RARITY or better guarantees it
	RARITY = "Epic" :: Types.RarityId,
})

Chests.LIST = table.freeze({
	{ id = "Common", name = "Common Chest", price = 100, minRarity = "Common" },
	{ id = "Uncommon", name = "Uncommon Chest", price = 250, minRarity = "Uncommon" },
	{ id = "Rare", name = "Rare Chest", price = 500, minRarity = "Rare" },
	{ id = "Epic", name = "Epic Chest", price = 1000, minRarity = "Epic", noDuplicates = true },
	{
		id = "Legendary",
		name = "Legendary Chest",
		price = 2000,
		minRarity = "Legendary",
		noDuplicates = true,
	},
} :: { ChestDef })

local byId: { [string]: ChestDef } = {}
for _, chest in Chests.LIST do
	byId[chest.id] = chest
	table.freeze(chest)
end

-- Chest spells grouped by rarity.
local byRarity: { [string]: { string } } = {}
for _, def in SpellDefinitions.chestSpells() do
	local list = byRarity[def.rarity :: string] or {}
	byRarity[def.rarity :: string] = list
	table.insert(list, def.id)
end

-- Spins left until the guaranteed hit, given the player's pity counter
-- (1 means the very next chest is the guaranteed one).
function Chests.spinsToPity(pity: number): number
	return math.max(1, Chests.PITY.SPINS - math.max(0, math.floor(pity)))
end

-- The counter after a chest that landed on `rarityId`.
function Chests.nextPity(pity: number, rarityId: string): number
	if Rarity.rank(rarityId) >= Rarity.rank(Chests.PITY.RARITY) then
		return 0
	end
	return math.max(0, math.floor(pity)) + 1
end

function Chests.get(id: string): ChestDef?
	return byId[id]
end

-- The chest's colour (its rarity's).
function Chests.color(id: string): Color3
	local chest = byId[id]
	return Rarity.color(if chest then chest.minRarity else nil)
end

-- Spell ids of one rarity.
function Chests.ofRarity(rarityId: string): { string }
	return byRarity[rarityId] or {}
end

-- The rarities a chest can drop (its own and every rarer one that has spells).
local function raritiesFrom(minRarity: string): { string }
	local ids = {}
	for index, rarity in Rarity.LIST do
		if index >= Rarity.rank(minRarity) and #Chests.ofRarity(rarity.id) > 0 then
			table.insert(ids, rarity.id)
		end
	end
	return ids
end

-- The ids of every spell `chestId` can drop; every chest spell without one.
function Chests.pool(chestId: string?): { string }
	local chest = if chestId then byId[chestId] else nil
	local minRank = if chest then Rarity.rank(chest.minRarity) else 1
	local ids = {}
	for _, def in SpellDefinitions.chestSpells() do
		if Rarity.rank(def.rarity) >= minRank then
			table.insert(ids, def.id)
		end
	end
	return ids
end

-- Shown in the shop: each rarity a chest can drop, its chance in percent and
-- how many spells it holds.
function Chests.odds(chestId: string): { { rarity: string, percent: number, count: number } }
	local chest = byId[chestId]
	local rows = {}
	if not chest then
		return rows
	end
	local ids = raritiesFrom(chest.minRarity)
	local total = 0
	for _, id in ids do
		total += Rarity.byId[id].weight
	end
	for _, id in ids do
		table.insert(rows, {
			rarity = id,
			percent = Rarity.byId[id].weight / total * 100,
			count = #Chests.ofRarity(id),
		})
	end
	return rows
end

-- True when the player owns every spell `chestId` can drop (every chest spell
-- without one): nothing left to win, so the shop won't sell it.
function Chests.ownsAll(owned: { string }, chestId: string?): boolean
	for _, id in Chests.pool(chestId) do
		if not table.find(owned, id) then
			return false
		end
	end
	return true
end

-- Coins a duplicate of `rarityId` pays back from `chest`.
function Chests.refund(chest: ChestDef, rarityId: string): number
	local rarity = Rarity.byId[rarityId]
	local base = if rarity then rarity.refund else 0
	return math.min(chest.price - 1, math.max(base, math.floor(chest.price * Chests.REFUND_SHARE)))
end

export type Roll = {
	spell: string,
	rarity: Types.RarityId,
	duplicate: boolean,
	refund: number,
	guaranteed: boolean, -- the pity guarantee decided the rarity
}

-- A rarity from `ids`, by weight.
local function pickRarity(rng: Random, ids: { string }): string
	local total = 0
	for _, id in ids do
		total += Rarity.byId[id].weight
	end
	local pick = rng:NextNumber(0, total)
	local sum = 0
	for _, id in ids do
		sum += Rarity.byId[id].weight
		if pick < sum then
			return id
		end
	end
	return ids[#ids]
end

local function unowned(list: { string }, owned: { string }): { string }
	local fresh = {}
	for _, id in list do
		if not table.find(owned, id) then
			table.insert(fresh, id)
		end
	end
	return fresh
end

-- Decides what a chest gives: a rarity by weight among the ones it can drop,
-- then a spell of it. nil for an unknown chest, or when the player owns every
-- spell it can drop (the shop refuses to sell it then).
function Chests.roll(chestId: string, owned: { string }, rng: Random, pity: number?): Roll?
	local chest = byId[chestId]
	if not chest or Chests.ownsAll(owned, chestId) then
		return nil
	end
	-- The guarantee only matters for chests that can still miss it.
	local canMiss = Rarity.rank(chest.minRarity) < Rarity.rank(Chests.PITY.RARITY)
	local guaranteed = canMiss and Chests.spinsToPity(pity or 0) <= 1
	local floorId = if guaranteed then Chests.PITY.RARITY else chest.minRarity
	local rarities = raritiesFrom(floorId)
	if #rarities == 0 then
		rarities = raritiesFrom(chest.minRarity)
		guaranteed = false
	end

	-- The guarantee and the Epic/Legendary chests skip spells you already own
	-- (while any are left): only rarities with an unowned spell are rolled.
	local fresh = guaranteed or chest.noDuplicates == true
	if fresh then
		local open = {}
		for _, id in rarities do
			if #unowned(Chests.ofRarity(id), owned) > 0 then
				table.insert(open, id)
			end
		end
		if #open > 0 then
			rarities = open
		else
			fresh = false
		end
	end

	local rarityId = pickRarity(rng, rarities)
	local list = Chests.ofRarity(rarityId)
	if fresh then
		list = unowned(list, owned)
	end
	local spell = list[rng:NextInteger(1, #list)]
	local duplicate = table.find(owned, spell) ~= nil
	return {
		spell = spell,
		rarity = rarityId :: Types.RarityId,
		duplicate = duplicate,
		refund = if duplicate then Chests.refund(chest, rarityId) else 0,
		guaranteed = guaranteed,
	}
end

return Chests
