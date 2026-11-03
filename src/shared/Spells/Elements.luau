--!strict
-- The four elements. Each has three BASE spells that come with it (the
-- "base element"): a player picks their first element free and buys the
-- others with coins (`price`). Every other spell is a chest spell, won from the
-- chest (shared/Economy/Chests) and equipped in the loadout's two extra
-- slots (shared/Spells/Loadout).
--
-- A spell's shape comes from its role (a circle for a basic attack, a
-- diagonal slash for a fast attack, a square for a boost, ...; see
-- Glyphs.ROLE), so it is the same in every element, and a loadout never
-- repeats a shape.
--
-- Pure data: the server (ElementService), the client UI, and the hub build
-- from this one table.

local Types = require(script.Parent.Parent.Types)

export type Element = {
	id: Types.ElementId,
	name: string,
	color: Color3,
	tagline: string,
	-- Coins to buy it (the first element a player picks is free).
	price: number,
	-- The three base spell ids, in slot order.
	base: { string },
}

-- The neutral school of spells that belong to no element (Lightning, Heal,
-- Black Hole, Turret). They only come from chests.
export type School = {
	id: string,
	name: string,
	color: Color3,
}

local Elements = {}

Elements.BASE_COUNT = 3

Elements.ARCANE = table.freeze({
	id = "Arcane",
	name = "Arcane",
	color = Color3.fromRGB(190, 130, 255),
}) :: School

Elements.LIST = {
	{
		id = "Fire",
		name = "Fire",
		color = Color3.fromRGB(255, 112, 40),
		tagline = "Hit hard and burn bright.",
		price = 400,
		base = { "Fireball", "FireSlash", "FireBoost" },
	},
	{
		id = "Water",
		name = "Water",
		color = Color3.fromRGB(64, 164, 255),
		tagline = "Flow around attacks and trap your foes.",
		price = 400,
		base = { "WaterSlice", "WaterBody", "WaterLock" },
	},
	{
		id = "Earth",
		name = "Earth",
		color = Color3.fromRGB(176, 128, 80),
		tagline = "Walls, boulders, and ground-shaking power.",
		price = 400,
		base = { "RockThrow", "EarthWall", "EarthPunch" },
	},
	{
		id = "Air",
		name = "Air",
		color = Color3.fromRGB(176, 232, 220),
		tagline = "Fast, slippery, and full of wind.",
		price = 400,
		base = { "Gust", "Whirlwind", "AirBoost" },
	},
} :: { Element }

local byId: { [string]: Element } = {}
for _, element in Elements.LIST do
	assert(byId[element.id] == nil, `duplicate element {element.id}`)
	assert(#element.base == Elements.BASE_COUNT, `{element.id} needs {Elements.BASE_COUNT} spells`)
	byId[element.id] = element
	table.freeze(element.base)
	table.freeze(element)
end
Elements.byId = byId

function Elements.get(id: string): Element?
	return byId[id]
end

-- The element or the Arcane school, for anything that shows a spell's colour;
-- nil for an unknown id.
function Elements.school(id: string): School?
	if id == Elements.ARCANE.id then
		return Elements.ARCANE
	end
	return byId[id]
end

function Elements.color(id: string): Color3
	local school = Elements.school(id)
	return if school then school.color else Color3.fromRGB(176, 190, 197)
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
