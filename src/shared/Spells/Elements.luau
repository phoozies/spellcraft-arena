--!strict
-- The four elements. Every spell belongs to one (SpellDefinitions `element`)
-- and every element has the same five spell slots:
--
--   1  the basic attack         (glyph: circle)
--   2  a second move            (glyph: wave)
--   3  a utility or boost       (glyph: triangle)
--   4  a heavy move             (glyph: lightning bolt)
--   5  the ultimate             (glyph: star)
--
-- A player equips one element at a time (profile.element); its five spells
-- are what they can draw, in the hub and in every match. The first element is
-- a free pick; the other three are unlocked from crates (shared/Economy/Crates).
--
-- Pure data: the server (ElementService), the client UI, and the hub build
-- from this one table.

local Types = require(script.Parent.Parent.Types)

export type Element = {
	id: Types.ElementId,
	name: string,
	color: Color3,
	icon: string,
	tagline: string,
	-- Spell ids by slot (1..5); filled in by SpellDefinitions' own data.
	spells: { string },
}

local Elements = {}

-- The shape drawn for each slot, the same in every element so there is only
-- one set of shapes to learn.
Elements.SLOT_GLYPHS = table.freeze({ "circle", "wave", "triangle", "bolt", "star" })
Elements.SLOT_COUNT = 5

Elements.LIST = {
	{
		id = "Fire",
		name = "Fire",
		color = Color3.fromRGB(255, 112, 40),
		icon = "🔥",
		tagline = "Hit hard and burn bright.",
		spells = { "Fireball", "FireSlash", "FireBoost", "FirePillar", "FireBomb" },
	},
	{
		id = "Water",
		name = "Water",
		color = Color3.fromRGB(64, 164, 255),
		icon = "💧",
		tagline = "Flow around attacks and trap your foes.",
		spells = { "WaterSlice", "WaterBody", "WaterLock", "WaterWave", "WaterNebula" },
	},
	{
		id = "Earth",
		name = "Earth",
		color = Color3.fromRGB(176, 128, 80),
		icon = "⛰",
		tagline = "Walls, boulders, and ground-shaking power.",
		spells = { "RockThrow", "EarthWall", "EarthPunch", "EarthPillar", "Earthquake" },
	},
	{
		id = "Air",
		name = "Air",
		color = Color3.fromRGB(176, 232, 220),
		icon = "🌪",
		tagline = "Fast, slippery, and full of wind.",
		spells = { "Gust", "Whirlwind", "AirBoost", "AirShield", "Tornado" },
	},
} :: { Element }

local byId: { [string]: Element } = {}
for _, element in Elements.LIST do
	assert(byId[element.id] == nil, `duplicate element {element.id}`)
	assert(#element.spells == Elements.SLOT_COUNT, `{element.id} needs {Elements.SLOT_COUNT} spells`)
	byId[element.id] = element
	table.freeze(element.spells)
	table.freeze(element)
end
Elements.byId = byId

function Elements.get(id: string): Element?
	return byId[id]
end

function Elements.color(id: string): Color3
	local element = byId[id]
	return if element then element.color else Color3.fromRGB(176, 190, 197)
end

-- Ids of every element, in display order.
function Elements.ids(): { string }
	local ids = {}
	for _, element in Elements.LIST do
		table.insert(ids, element.id)
	end
	return ids
end

return Elements
