--!strict
-- Rolls draft cards: each card's rarity is rolled independently, then a spell
-- of that rarity the player isn't already holding is chosen. Pure module with
-- an injectable RNG so tests are deterministic.

local Types = require(script.Parent.Parent.Types)
local Rarity = require(script.Parent.Parent.Spells.Rarity)
local SpellDefinitions = require(script.Parent.Parent.Spells.SpellDefinitions)

local DraftRoller = {}

local CARD_COUNT = 3

function DraftRoller.roll(hand: { string }, rng: Random): { Types.DraftCard }
	local excluded: { [string]: boolean } = {}
	for _, id in hand do
		excluded[id] = true
	end

	local cards: { Types.DraftCard } = {}
	for _ = 1, CARD_COUNT do
		local rarity = Rarity.roll(rng:NextNumber())
		local pool = {}
		-- Fall back to lower rarities if every spell of this tier is excluded.
		local tier = Rarity.INFO[rarity].order
		while #pool == 0 and tier >= 1 do
			local tierName = Rarity.ORDER[tier]
			for _, id in SpellDefinitions.ofRarity(tierName) do
				if not excluded[id] then
					table.insert(pool, id)
				end
			end
			if #pool == 0 then
				tier -= 1
			else
				rarity = tierName
			end
		end
		if #pool > 0 then
			local spellId = pool[rng:NextInteger(1, #pool)]
			excluded[spellId] = true
			table.insert(cards, { spellId = spellId, rarity = rarity })
		end
	end
	return cards
end

return DraftRoller
