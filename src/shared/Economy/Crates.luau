--!strict
-- The crate shop: five crates, one per rarity. Opening a crate costs coins
-- and "spins" a reel that lands on one spell. Pure module (no services, an
-- injectable RNG) so tests are deterministic; the server's CrateService is
-- the only caller that spends coins or grants spells, and the client's
-- CrateController only animates the result the server sends.
--
-- How a spin is decided:
--   1. Roll the crate's rarity odds (mostly its own tier, a small chance of
--      one tier higher: a "lucky" upgrade).
--   2. Pick a spell of that rarity that a crate can drop (starters never
--      drop; see SpellDefinitions.crateDrops). If that tier has none, fall
--      back to lower tiers.
--   3. Already own it? It's a duplicate: refund DUPLICATE_REFUND of the price.

local Types = require(script.Parent.Parent.Types)
local Rarity = require(script.Parent.Parent.Spells.Rarity)
local SpellDefinitions = require(script.Parent.Parent.Spells.SpellDefinitions)

type CrateDef = Types.CrateDef

local Crates = {}

-- Share of the price refunded when the spin lands on a spell you own.
Crates.DUPLICATE_REFUND = 0.5

-- Seconds the client's reel spins; the server won't accept another open
-- from the same player until this has passed.
Crates.SPIN_TIME = 4

Crates.LIST = table.freeze({
	{ id = "Common", price = 100, odds = { Common = 80, Uncommon = 20 } },
	{ id = "Uncommon", price = 250, odds = { Uncommon = 80, Rare = 20 } },
	{ id = "Rare", price = 500, odds = { Rare = 80, Epic = 20 } },
	{ id = "Epic", price = 1000, odds = { Epic = 85, Legendary = 15 } },
	{ id = "Legendary", price = 2000, odds = { Legendary = 100 } },
} :: { CrateDef })

local byId: { [string]: CrateDef } = {}
for _, crate in Crates.LIST do
	byId[crate.id] = crate
	table.freeze(crate.odds)
end

function Crates.get(id: string): CrateDef?
	return byId[id]
end

-- Rolls one of the crate's rarities by weight. `roll` is in [0, 1).
function Crates.rollRarity(crate: CrateDef, roll: number): Types.Rarity
	local total = 0
	for _, name in Rarity.ORDER do
		total += crate.odds[name] or 0
	end
	local pick = roll * total
	for _, name in Rarity.ORDER do
		local weight = crate.odds[name] or 0
		if weight > 0 then
			pick -= weight
			if pick < 0 then
				return name
			end
		end
	end
	return crate.id
end

-- Spells a crate can land on, grouped by rarity, for the reel's filler and
-- the shop's "possible drops" list.
function Crates.possibleDrops(crate: CrateDef): { string }
	local ids = {}
	for _, name in Rarity.ORDER do
		if (crate.odds[name] or 0) > 0 then
			for _, id in SpellDefinitions.crateDrops(name) do
				table.insert(ids, id)
			end
		end
	end
	return ids
end

-- Decides a spin. Returns (spellId, rarity), or nil if nothing can drop.
function Crates.roll(crate: CrateDef, rng: Random): (string?, Types.Rarity?)
	local rarity = Crates.rollRarity(crate, rng:NextNumber())
	local tier = Rarity.INFO[rarity].order
	while tier >= 1 do
		local name = Rarity.ORDER[tier]
		local pool = SpellDefinitions.crateDrops(name)
		if #pool > 0 then
			return pool[rng:NextInteger(1, #pool)], name
		end
		tier -= 1
	end
	return nil, nil
end

-- Coins refunded for a duplicate from this crate.
function Crates.refundFor(crate: CrateDef): number
	return math.floor(crate.price * Crates.DUPLICATE_REFUND)
end

return Crates
