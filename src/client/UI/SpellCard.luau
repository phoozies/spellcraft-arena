--!strict
-- A tappable spell card: the spell's shape, its name, and an outline in its
-- rarity colour (crate spells) or element colour (base spells). Used by the
-- Spellbook (base spells, loadout, collection) and the Spell Crate (reel and
-- reveal), so a spell always looks the same wherever you meet it.
--
--   SpellCard.create(parent, spellId, { size = UDim2, owned = false })
--     owned = false dims the card and hides the shape ("?"), for a spell you
--     have not won yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local GlyphView = require(ReplicatedStorage.Shared.UI.GlyphView)
local Theme = require(script.Parent.Theme)

local SpellCard = {}

export type Options = {
	size: UDim2?,
	owned: boolean?,
	glyphSize: number?,
	[string]: any,
}

-- The accent colour of a spell: its rarity (crate spells) or its element.
function SpellCard.colorOf(spellId: string): Color3
	local def = SpellDefinitions.get(spellId)
	if not def then
		return Theme.COLORS.subtext
	end
	return if def.rarity then Rarity.color(def.rarity) else Elements.color(def.element)
end

function SpellCard.create(parent: Instance, spellId: string, options: Options?): TextButton
	local opts = options or {}
	local def = SpellDefinitions.get(spellId)
	local owned = opts.owned ~= false
	local color = SpellCard.colorOf(spellId)
	local glyphSize = opts.glyphSize or 54

	local card = Theme.button(parent, "", {
		Name = spellId,
		Size = opts.size or UDim2.fromOffset(96, 104),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = if def and def.rarity and Rarity.rank(def.rarity) >= 4 then 4 else 3
	end
	if not def then
		return card
	end

	if owned then
		GlyphView.create(
			card,
			def.glyph,
			glyphSize,
			color,
			{ Position = UDim2.new(0.5, -glyphSize / 2, 0, 6) }
		)
	else
		Theme.label(card, "?", {
			Size = UDim2.new(1, 0, 0, glyphSize),
			Position = UDim2.fromOffset(0, 6),
			TextColor3 = Theme.COLORS.subtext,
		})
		card.BackgroundTransparency = 0.45
	end
	Theme.label(card, def.name, {
		Size = UDim2.new(1, -6, 0, 28),
		Position = UDim2.new(0, 3, 1, -50),
		TextColor3 = if owned then Theme.COLORS.text else Theme.COLORS.subtext,
	})
	if def.rarity then
		Theme.label(card, string.upper(def.rarity), {
			Name = "Rarity",
			Size = UDim2.new(1, -6, 0, 14),
			Position = UDim2.new(0, 3, 1, -20),
			TextColor3 = color,
		})
	end
	return card
end

return SpellCard
