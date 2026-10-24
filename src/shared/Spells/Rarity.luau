--!strict
-- Rarity tiers (Common < Uncommon < Rare < Epic < Legendary): draft weights, UI colors, and a shape glyph so rarity is
-- readable without relying on color alone (colorblind-friendly).

local Types = require(script.Parent.Parent.Types)

export type RarityInfo = {
	name: Types.Rarity,
	weight: number,
	color: Color3,
	glyph: string,
	order: number,
}

local Rarity = {}

Rarity.ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" } :: { Types.Rarity }

Rarity.INFO = table.freeze({
	Common = {
		name = "Common",
		weight = 50,
		color = Color3.fromRGB(176, 190, 197),
		glyph = "●",
		order = 1,
	},
	Uncommon = {
		name = "Uncommon",
		weight = 25,
		color = Color3.fromRGB(102, 187, 106),
		glyph = "▲",
		order = 2,
	},
	Rare = {
		name = "Rare",
		weight = 15,
		color = Color3.fromRGB(66, 165, 245),
		glyph = "◆",
		order = 3,
	},
	Epic = {
		name = "Epic",
		weight = 8,
		color = Color3.fromRGB(171, 71, 188),
		glyph = "★",
		order = 4,
	},
	Legendary = {
		name = "Legendary",
		weight = 2,
		color = Color3.fromRGB(255, 179, 0),
		glyph = "👑",
		order = 5,
	},
} :: { [Types.Rarity]: RarityInfo })

-- Rolls a rarity using the weights above. `roll` is a number in [0, 1);
-- injectable so tests can be deterministic.
function Rarity.roll(roll: number): Types.Rarity
	local total = 0
	for _, name in Rarity.ORDER do
		total += Rarity.INFO[name].weight
	end
	local pick = roll * total
	for _, name in Rarity.ORDER do
		pick -= Rarity.INFO[name].weight
		if pick < 0 then
			return name
		end
	end
	return "Common"
end

return Rarity
