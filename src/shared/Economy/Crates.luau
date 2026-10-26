--!strict
-- The crate shop. A Spell Crate costs coins and "spins" a gacha reel that lands
-- on one CRATE spell: first a rarity is rolled by weight (Spells/Rarity), then
-- a spell of that rarity at random. Landing on a spell you already own pays
-- back a few coins instead (always less than a spin). Pure module (no
-- services, an injectable RNG) so tests are deterministic; the server's
-- CrateService is the only caller that spends coins or grants spells, and the
-- client's CrateController only animates the result the server sends.
--
-- Pity: every spin that doesn't land on PITY.RARITY or better adds one to the
-- player's pity counter (profile.pity, owned by CrateService); when the counter
-- reaches PITY.SPINS - 1 the next spin is guaranteed to be PITY.RARITY or
-- better, and a hit resets the counter. The guarantee also prefers a spell the
-- player doesn't own yet, so it is never wasted on a duplicate while an unowned
-- one of that rarity exists.
--
-- Elements are NOT in the crate: a base element is bought directly with coins
-- (ElementService.buy, price in Spells/Elements).

local Rarity = require(script.Parent.Parent.Spells.Rarity)
local SpellDefinitions = require(script.Parent.Parent.Spells.SpellDefinitions)
local Types = require(script.Parent.Parent.Types)

type CrateDef = Types.CrateDef

local Crates = {}

-- Seconds the client's reel spins; the server won't accept another open
-- from the same player until this has passed.
Crates.SPIN_TIME = 4

Crates.PITY = table.freeze({
	SPINS = 10, -- a spin of this many without PITY.RARITY or better is guaranteed to hit it
	RARITY = "Epic" :: Types.RarityId,
})

-- Spins left until the guaranteed hit, given the player's pity counter
-- (1 means the very next spin is the guaranteed one).
function Crates.spinsToPity(pity: number): number
	return math.max(1, Crates.PITY.SPINS - math.max(0, math.floor(pity)))
end

-- The counter after a spin that landed on `rarityId`.
function Crates.nextPity(pity: number, rarityId: string): number
	if Rarity.rank(rarityId) >= Rarity.rank(Crates.PITY.RARITY) then
		return 0
	end
	return math.max(0, math.floor(pity)) + 1
end

Crates.LIST = table.freeze({
	{ id = "Spell", name = "Spell Crate", price = 100 },
} :: { CrateDef })

local byId: { [string]: CrateDef } = {}
for _, crate in Crates.LIST do
	byId[crate.id] = crate
end

-- Crate spells grouped by rarity.
local byRarity: { [string]: { string } } = {}
for _, def in SpellDefinitions.crateSpells() do
	local list = byRarity[def.rarity :: string] or {}
	byRarity[def.rarity :: string] = list
	table.insert(list, def.id)
end

function Crates.get(id: string): CrateDef?
	return byId[id]
end

-- The ids of every spell a crate can drop.
function Crates.pool(): { string }
	local ids = {}
	for _, def in SpellDefinitions.crateSpells() do
		table.insert(ids, def.id)
	end
	return ids
end

-- Spell ids of one rarity.
function Crates.ofRarity(rarityId: string): { string }
	return byRarity[rarityId] or {}
end

-- Shown in the shop: each rarity's chance in percent and how many spells it holds.
function Crates.odds(): { { rarity: string, percent: number, count: number } }
	local rows = {}
	for _, rarity in Rarity.LIST do
		table.insert(rows, {
			rarity = rarity.id,
			percent = rarity.weight / Rarity.TOTAL_WEIGHT * 100,
			count = #Crates.ofRarity(rarity.id),
		})
	end
	return rows
end

-- True when the player already owns every crate spell (nothing left to win).
function Crates.ownsAll(owned: { string }): boolean
	for _, id in Crates.pool() do
		if not table.find(owned, id) then
			return false
		end
	end
	return true
end

export type Roll = {
	spell: string,
	rarity: Types.RarityId,
	duplicate: boolean,
	refund: number,
	guaranteed: boolean, -- the pity guarantee decided the rarity
}

-- Decides a spin: a rarity by weight, then a spell of it. nil only when the
-- player owns every crate spell (the shop refuses to sell the spin then).
function Crates.roll(owned: { string }, rng: Random, pity: number?): Roll?
	if Crates.ownsAll(owned) then
		return nil
	end
	local guaranteed = Crates.spinsToPity(pity or 0) <= 1
	local rarityId = Rarity.roll(rng, if guaranteed then Crates.PITY.RARITY else nil)
	local list = byRarity[rarityId]
	if guaranteed then
		-- Prefer a spell the player doesn't own yet, of this rarity or better.
		local fresh = {}
		for _, id in Crates.pool() do
			local def = SpellDefinitions.get(id)
			if
				def
				and Rarity.rank(def.rarity) >= Rarity.rank(Crates.PITY.RARITY)
				and not table.find(owned, id)
			then
				table.insert(fresh, id)
			end
		end
		if #fresh > 0 then
			local spell = fresh[rng:NextInteger(1, #fresh)]
			local def = SpellDefinitions.get(spell) :: Types.SpellDef
			return {
				spell = spell,
				rarity = def.rarity :: Types.RarityId,
				duplicate = false,
				refund = 0,
				guaranteed = true,
			}
		end
	end
	while not list or #list == 0 do
		-- A rarity with no spells yet: fall back to the next one down.
		local rank = Rarity.rank(rarityId) - 1
		if rank < 1 then
			return nil
		end
		rarityId = Rarity.LIST[rank].id
		list = byRarity[rarityId]
	end
	local spell = list[rng:NextInteger(1, #list)]
	local duplicate = table.find(owned, spell) ~= nil
	local rarity = Rarity.byId[rarityId]
	return {
		spell = spell,
		rarity = rarityId,
		duplicate = duplicate,
		refund = if duplicate then rarity.refund else 0,
		guaranteed = guaranteed,
	}
end

return Crates
