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

local function heart(): { Vector2 }
	-- The classic heart curve, traced from the bottom tip up the left side,
	-- around both lobes, and back down (y points down on screen).
	local raw = {}
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for i = 0, 40 do
		local t = math.pi + (i / 40) * math.pi * 2
		local x = 16 * math.sin(t) ^ 3
		local y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minY, maxY = math.min(minY, y), math.max(maxY, y)
		table.insert(raw, Vector2.new(x, y))
	end
	local points = {}
	for _, p in raw do
		table.insert(
			points,
			Vector2.new((p.X - minX) / (maxX - minX), (p.Y - minY) / (maxY - minY))
		)
	end
	points[#points] = points[1]
	return points
end

local function spiral(): { Vector2 }
	-- Two turns winding outward from the middle.
	local points = {}
	for i = 0, 48 do
		local f = i / 48
		local a = f * math.pi * 4
		local r = 0.06 + f * 0.44
		table.insert(points, Vector2.new(0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r))
	end
	return points
end

local function hook(): { Vector2 }
	-- A "J": straight down the right side, then a half circle round to the left.
	local points = { Vector2.new(0.78, 0), Vector2.new(0.78, 0.5) }
	for i = 1, 10 do
		local a = (i / 10) * math.pi
		table.insert(points, Vector2.new(0.39 + math.cos(a) * 0.39, 0.5 + math.sin(a) * 0.5))
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
	{ id = "heart", name = "Heart", closed = true, points = heart() },
	{ id = "spiral", name = "Spiral", closed = false, points = spiral() },
	{
		id = "zigzag",
		name = "Zigzag (M)",
		closed = false,
		points = {
			Vector2.new(0, 1),
			Vector2.new(0.25, 0),
			Vector2.new(0.5, 0.7),
			Vector2.new(0.75, 0),
			Vector2.new(1, 1),
		},
	},
	{ id = "hook", name = "Hook (J)", closed = false, points = hook() },
	{
		-- One unbroken stroke: down the first diagonal, up the side, down the second.
		id = "x",
		name = "X",
		closed = false,
		points = {
			Vector2.new(0, 0),
			Vector2.new(1, 1),
			Vector2.new(1, 0),
			Vector2.new(0, 1),
		},
	},
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
	support = "heart", -- heals (Heal)
	storm = "zigzag", -- lightning (Lightning)
	summon = "hook", -- things you put down to fight for you (Turret)
	ward = "x", -- shields that block the next hit (Air Shield)
	vortex = "spiral", -- pulling and trapping (Black Hole)
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
	storm = "Storm",
	summon = "Summon",
	ward = "Ward",
	vortex = "Vortex",
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
