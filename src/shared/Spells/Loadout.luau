--!strict
-- The loadout: the spells a player can draw. It is the equipped element's
-- three base spells plus up to MAX_EXTRA crate spells they own and chose to
-- equip. Pure rules (no Instances) so the server enforces them, the client
-- UI explains them, and tests check them.
--
-- One shape per spell: the server tells spells apart by the shape drawn, so
-- two spells in a loadout can't share a glyph (Glyphs.ROLE). A crate spell
-- that clashes with the base spells or the other extra is not equippable.

local Elements = require(script.Parent.Elements)
local SpellDefinitions = require(script.Parent.SpellDefinitions)

local Loadout = {}

Loadout.MAX_EXTRA = 2

-- Base spells, then extras: the draw list for an element and its extras.
function Loadout.spells(elementId: string, extras: { string }): { string }
	local list: { string } = {}
	local element = Elements.get(elementId)
	if element then
		for _, id in element.base do
			table.insert(list, id)
		end
		for _, id in extras do
			table.insert(list, id)
		end
	end
	return list
end

-- The spell in `spellIds` that shares a shape with `candidateId`, if any.
function Loadout.clash(spellIds: { string }, candidateId: string): string?
	local candidate = SpellDefinitions.get(candidateId)
	if not candidate then
		return nil
	end
	for _, id in spellIds do
		local def = SpellDefinitions.get(id)
		if def and id ~= candidateId and def.glyph == candidate.glyph then
			return id
		end
	end
	return nil
end

-- Why `spellId` can't go into an extra slot next to `others` (the element's
-- base spells and the other extra), or nil when it can.
function Loadout.problem(spellId: string, others: { string }): string?
	local def = SpellDefinitions.get(spellId)
	if not def or not def.rarity then
		return "Only crate spells go in the loadout."
	end
	local clashing = Loadout.clash(others, spellId)
	if clashing then
		local other = SpellDefinitions.get(clashing)
		return `{def.name} is drawn like {if other then other.name else clashing}. Each spell needs its own shape!`
	end
	return nil
end

-- Cleans an untrusted extras list: owned crate spells only, no repeats, no
-- shape clashes with the base spells or each other, at most MAX_EXTRA.
function Loadout.sanitize(elementId: string, extras: any, owned: { string }): { string }
	local kept: { string } = {}
	if typeof(extras) ~= "table" then
		return kept
	end
	local drawn = Loadout.spells(elementId, {})
	for _, id in extras do
		if
			#kept < Loadout.MAX_EXTRA
			and typeof(id) == "string"
			and table.find(owned, id)
			and not table.find(kept, id)
			and Loadout.problem(id, drawn) == nil
		then
			table.insert(kept, id)
			table.insert(drawn, id)
		end
	end
	return kept
end

return Loadout
