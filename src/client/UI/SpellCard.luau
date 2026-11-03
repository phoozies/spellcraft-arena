--!strict
-- A tappable spell card, styled like the drawing canvas: a band of the
-- spell's colour across the top, its sigil (the shape in glowing ink inside a
-- little magic circle, UI/Sigil) over the band, its name, and a pill naming
-- its rarity (chest spells) or element (base spells), all ringed in that
-- colour. Used by the Spellbook (base spells, loadout, collection) and the
-- chest (reel and reveal), so a spell always looks the same wherever
-- you meet it.
--
--   SpellCard.create(parent, spellId, { size = UDim2, owned = false })
--     owned = false greys the card and shows "?" in its sigil, for a spell
--     you have not won yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Sigil = require(script.Parent.Sigil)
local Theme = require(script.Parent.Theme)

local SpellCard = {}

export type Options = {
	size: UDim2?,
	owned: boolean?,
	glyphSize: number?,
	[string]: any,
}

-- The accent colour of a spell: its rarity (chest spells) or its element.
function SpellCard.colorOf(spellId: string): Color3
	local def = SpellDefinitions.get(spellId)
	if not def then
		return Theme.COLORS.subtext
	end
	return if def.rarity then Rarity.color(def.rarity) else Elements.color(def.element)
end

-- A small rounded tag with ink text on a colour.
function SpellCard.pill(
	parent: Instance,
	text: string,
	color: Color3,
	props: { [string]: any }?
): Frame
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.BackgroundColor3 = color
	pill.BorderSizePixel = 0
	for key, value in props or {} do
		(pill :: any)[key] = value
	end
	Theme.corner(pill, 16)
	Theme.stroke(pill, Theme.COLORS.outline, 2)
	Theme.label(pill, text, {
		Size = UDim2.new(1, -6, 1, -2),
		Position = UDim2.fromOffset(3, 1),
		ZIndex = pill.ZIndex,
	})
	pill.Parent = parent
	return pill
end

function SpellCard.create(parent: Instance, spellId: string, options: Options?): TextButton
	local opts = options or {}
	local def = SpellDefinitions.get(spellId)
	local owned = opts.owned ~= false
	local color = if owned then SpellCard.colorOf(spellId) else Theme.COLORS.grey
	local sigilSize = opts.glyphSize or 50

	local card = Theme.button(parent, "", {
		Name = spellId,
		Size = opts.size or UDim2.fromOffset(96, 104),
		BackgroundColor3 = Theme.COLORS.panel,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = 4
	end
	Theme.rim(card, 4)
	if not def then
		return card
	end

	local band = Theme.frame(card, {
		Name = "Band",
		Size = UDim2.new(1, 0, 0, math.floor(sigilSize * 0.62)),
		BackgroundColor3 = color,
		Active = false,
	})
	Theme.corner(band, 10)
	local props = {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 5),
	}
	if owned then
		Sigil.create(card, def.glyph, sigilSize, color, props)
	else
		Sigil.blank(card, sigilSize, Theme.COLORS.subtext, "?", props)
		card.BackgroundTransparency = 0.45
	end
	Theme.label(card, def.name, {
		Name = "SpellName",
		Size = UDim2.new(1, -6, 0, 24),
		Position = UDim2.new(0, 3, 1, -46),
		TextColor3 = if owned then Theme.COLORS.text else Theme.COLORS.subtext,
	})
	local school = Elements.school(def.element)
	local tag = string.upper(def.rarity or (if school then school.name else def.element))
	SpellCard.pill(card, tag, if def.rarity then Rarity.color(def.rarity) else color, {
		Name = if def.rarity then "Rarity" else "School",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(0.84, 0, 0, 16),
	})
	return card
end

return SpellCard
