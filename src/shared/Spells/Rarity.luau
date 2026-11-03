--!strict
-- Spell rarities for the Chest Shop gacha. Every chest spell has one
-- (SpellDefinitions `rarity`); a spin first picks a rarity by `weight`, then
-- a spell of that rarity at random (shared/Economy/Chests). Pure data.
--
--   weight   relative chance of the rarity on a spin (they sum to 100)
--   refund   coins paid back when the spin lands on a spell you already own
--            (always less than a spin, so rolling duplicates never pays)

local Types = require(script.Parent.Parent.Types)

export type Rarity = {
	id: Types.RarityId,
	name: string,
	color: Color3,
	weight: number,
	refund: number,
}

local Rarity = {}

Rarity.LIST = {
	{
		id = "Common",
		name = "Common",
		color = Color3.fromRGB(176, 190, 197),
		weight = 55,
		refund = 20,
	},
	{
		id = "Uncommon",
		name = "Uncommon",
		color = Color3.fromRGB(102, 214, 110),
		weight = 25,
		refund = 35,
	},
	{
		id = "Rare",
		name = "Rare",
		color = Color3.fromRGB(70, 160, 255),
		weight = 12,
		refund = 55,
	},
	{
		id = "Epic",
		name = "Epic",
		color = Color3.fromRGB(190, 100, 255),
		weight = 6,
		refund = 75,
	},
	{
		id = "Legendary",
		name = "Legendary",
		color = Color3.fromRGB(255, 190, 40),
		weight = 2,
		refund = 90,
	},
} :: { Rarity }

local byId: { [string]: Rarity } = {}
local order: { [string]: number } = {}
local totalWeight = 0
for index, rarity in Rarity.LIST do
	byId[rarity.id] = rarity
	order[rarity.id] = index
	totalWeight += rarity.weight
	table.freeze(rarity)
end
Rarity.byId = byId
Rarity.TOTAL_WEIGHT = totalWeight

function Rarity.get(id: string): Rarity?
	return byId[id]
end

-- 1 (Common) .. 5 (Legendary); 0 for an unknown id. Used to sort spells.
function Rarity.rank(id: string?): number
	return if id then order[id] or 0 else 0
end

function Rarity.color(id: string?): Color3
	local rarity = if id then byId[id] else nil
	return if rarity then rarity.color else Color3.fromRGB(176, 190, 197)
end

-- Picks a rarity by weight. With `minId`, only that rarity or better can be
-- picked (the weights of the rest are kept, so Epic stays 3x likelier than
-- Legendary); used by the chest's pity guarantee.
function Rarity.roll(rng: Random, minId: string?): Types.RarityId
	local minRank = Rarity.rank(minId)
	local total = 0
	for index, rarity in Rarity.LIST do
		if index >= minRank then
			total += rarity.weight
		end
	end
	local pick = rng:NextNumber(0, total)
	local sum = 0
	for index, rarity in Rarity.LIST do
		if index < minRank then
			continue
		end
		sum += rarity.weight
		if pick < sum then
			return rarity.id
		end
	end
	return Rarity.LIST[1].id
end

return Rarity
