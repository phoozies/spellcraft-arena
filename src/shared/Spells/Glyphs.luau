--!strict
-- The shapes players draw to ready a spell. Each spell has one glyph
-- (SpellDefinitions `glyph`, chosen by the spell's role), each a single stroke
-- so a finger or mouse can trace it without lifting. Points are in a 0..1 box with +Y pointing DOWN
-- (screen space), and the recognizer ignores size, position, rotation, and
-- drawing direction, so only the SHAPE matters.
--
-- Pure module (no Instances): the server recognizes strokes with it and the
-- client draws the same shapes as the on-screen cheat sheet.

local Glyphs = {}

export type Glyph = {
	id: string,
	name: string,
	-- A closed shape can be started anywhere on its outline.
	closed: boolean,
	-- A straight line: recognized by straightness, not by template matching.
	line: boolean?,
	points: { Vector2 },
}

local function circle(): { Vector2 }
	local points = {}
	for i = 0, 32 do
		local a = -math.pi / 2 + (i / 32) * math.pi * 2
		table.insert(points, Vector2.new(0.5 + math.cos(a) * 0.5, 0.5 + math.sin(a) * 0.5))
	end
	return points
end

local function star(): { Vector2 }
	local points = {}
	for k = 0, 5 do
		local a = -math.pi / 2 + k * (4 * math.pi / 5)
		table.insert(points, Vector2.new(0.5 + math.cos(a) * 0.5, 0.5 + math.sin(a) * 0.5))
	end
	return points
end

Glyphs.LIST = {
	{ id = "circle", name = "Circle", closed = true, points = circle() },
	{
		id = "triangle",
		name = "Triangle",
		closed = true,
		points = { Vector2.new(0.5, 0), Vector2.new(1, 1), Vector2.new(0, 1), Vector2.new(0.5, 0) },
	},
	{
		id = "square",
		name = "Square",
		closed = true,
		points = {
			Vector2.new(0, 0),
			Vector2.new(1, 0),
			Vector2.new(1, 1),
			Vector2.new(0, 1),
			Vector2.new(0, 0),
		},
	},
	{
		id = "slash",
		name = "Slash",
		closed = false,
		line = true,
		points = { Vector2.new(0.1, 0.9), Vector2.new(0.9, 0.1) },
	},
	{
		id = "chevron",
		name = "Chevron",
		closed = false,
		points = { Vector2.new(0, 0), Vector2.new(0.5, 1), Vector2.new(1, 0) },
	},
	{
		id = "bolt",
		name = "Lightning",
		closed = false,
		points = {
			Vector2.new(0.75, 0),
			Vector2.new(0.2, 0.55),
			Vector2.new(0.8, 0.45),
			Vector2.new(0.25, 1),
		},
	},
	{ id = "star", name = "Star", closed = true, points = star() },
} :: { Glyph }

-- Which shape each KIND of move uses, the same in every element, so a shape
-- always means the same thing: a circle is a basic attack, a diagonal slash a
-- fast attack, a square a boost, a triangle a stun or a defense, and so on.
-- SpellDefinitions gives every spell a `role`; tests/Glyphs.spec checks that
-- its `glyph` is this table's shape for the role.
Glyphs.ROLE = table.freeze({
	basic = "circle",
	fast = "slash",
	boost = "square", -- self buffs (Fire Boost, Water Body, Air Boost)
	defense = "triangle", -- walls and shields (Earth Wall, Air Shield)
	stun = "triangle",
	heavy = "bolt",
	area = "chevron",
	support = "chevron", -- heals and helpers (Heal)
	ultimate = "star",
})

Glyphs.ROLE_NAMES = table.freeze({
	basic = "Basic attack",
	fast = "Fast attack",
	boost = "Boost",
	defense = "Defense",
	stun = "Stun",
	heavy = "Heavy attack",
	area = "Area attack",
	support = "Support",
	ultimate = "Ultimate",
})

local byId: { [string]: Glyph } = {}
for _, glyph in Glyphs.LIST do
	assert(byId[glyph.id] == nil, `duplicate glyph id {glyph.id}`)
	byId[glyph.id] = glyph
	table.freeze(glyph)
end
Glyphs.byId = byId

function Glyphs.get(id: string): Glyph?
	return byId[id]
end

return Glyphs
