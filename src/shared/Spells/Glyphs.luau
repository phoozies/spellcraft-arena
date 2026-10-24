--!strict
-- The shapes players draw to ready a spell. One glyph per spell
-- (SpellDefinitions `glyph`), each a single stroke so a finger or mouse can
-- trace it without lifting. Points are in a 0..1 box with +Y pointing DOWN
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

local function infinity(): { Vector2 }
	-- A figure eight on its side (lemniscate), crossing itself in the middle.
	local points = {}
	for i = 0, 48 do
		local t = (i / 48) * math.pi * 2
		local denom = 1 + math.sin(t) ^ 2
		table.insert(points, Vector2.new(0.5 + 0.5 * math.cos(t) / denom, 0.5 + 0.9 * math.sin(t) * math.cos(t) / denom))
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

local function wave(): { Vector2 }
	local points = {}
	for i = 0, 40 do
		local x = i / 40
		table.insert(points, Vector2.new(x, 0.5 - math.sin(x * math.pi * 4) * 0.5))
	end
	return points
end

local function spiral(): { Vector2 }
	local points = {}
	for i = 0, 60 do
		local f = i / 60
		local a = f * math.pi * 4
		local r = 0.06 + f * 0.44
		table.insert(points, Vector2.new(0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r))
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
	{ id = "wave", name = "Wave", closed = false, points = wave() },
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
	{ id = "infinity", name = "Infinity", closed = true, points = infinity() },
	{ id = "star", name = "Star", closed = true, points = star() },
	{ id = "spiral", name = "Spiral", closed = false, points = spiral() },
} :: { Glyph }

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
