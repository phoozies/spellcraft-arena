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
		-- If every spell of this tier is excluded, try lower tiers, then
		-- higher ones (tiers are small: one or two spells each).
		local rolled = Rarity.INFO[rarity].order
		local tiers = {}
		for tier = rolled, 1, -1 do
			table.insert(tiers, tier)
		end
		for tier = rolled + 1, #Rarity.ORDER do
			table.insert(tiers, tier)
		end
		for _, tier in tiers do
			local tierName = Rarity.ORDER[tier]
			for _, id in SpellDefinitions.ofRarity(tierName) do
				if not excluded[id] then
					table.insert(pool, id)
				end
			end
			if #pool > 0 then
				rarity = tierName
				break
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
