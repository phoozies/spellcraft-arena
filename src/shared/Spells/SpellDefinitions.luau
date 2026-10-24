--!strict
-- The spell dictionary. Every spell in the game is one row here; behavior
-- comes from its `archetype` (see src/server/Services/Archetypes). To add a
-- spell, add a row — no new code needed. Keep docs/SPELLS.md in sync.
--
-- Elements: every spell belongs to one of four elements (shared/Spells/
-- Elements) and fills one of its five slots. The slot decides the glyph the
-- player draws (the same five shapes in every element), so within an element
-- every spell has its own shape. Slot 5 is the element's ultimate.
--
-- Aliases are admin names (`;give fireball`), matched after normalization
-- (lowercase, no punctuation), so list plain words only.
--
-- Getting spells: a player equips one element and can draw its five spells.
-- The first element is a free pick; the others are unlocked from crates.
--
-- Copy model: drawing a glyph adds one copy of the spell to the hotbar
-- (up to 5 held, duplicates allowed); casting uses a copy up. `cooldown` is
-- the spell's CAST cooldown, shared by every copy of that spell. Players
-- have 100 HP and can stockpile copies, so damage per cast cooldown is the
-- budget that matters (~16-20 DPS for the best spammable spells). Ultimates
-- hit for 30-40 on long cooldowns. Numbers here are base values: projectile
-- speed is scaled by Config.PROJECTILE_SPEED_SCALE. tests/Balance.spec.luau
-- enforces the budgets.
--
-- Hitbox sizes (`radius`, studs; players add Config.HITBOX_BONUS):
--   medium 3-3.5 · large 4-5 · wide 6-8 · huge 10+

local Elements = require(script.Parent.Elements)
local Types = require(script.Parent.Parent.Types)

type SpellDef = Types.SpellDef

local M = Enum.Material

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local GLYPH = Elements.SLOT_GLYPHS

local DEFINITIONS: { SpellDef } = {
	----------------------------------------------------------------------
	-- Fire
	----------------------------------------------------------------------
	{
		id = "Fireball",
		name = "Fireball",
		aliases = { "fireball", "fire ball", "fire" },
		element = "Fire",
		slot = 1,
		glyph = GLYPH[1],
		sfx = { cast = "fireballCast", impact = "fireballHit" },
		archetype = "Projectile",
		cooldown = 0.9,
		description = "Hurl a ball of fire with a medium hitbox. 15 damage.",
		stats = { damage = 15, speed = 95, range = 160, radius = 3.5, knockback = 18 },
		visual = {
			shape = "Ball",
			size = Vector3.new(3.2, 3.2, 3.2),
			color = rgb(255, 112, 40),
			material = M.Neon,
			model = "Fireball",
		},
	},
	{
		id = "FireSlash",
		name = "Fire Slash",
		aliases = { "fire slash", "fireslash", "slash" },
		element = "Fire",
		slot = 2,
		glyph = GLYPH[2],
		sfx = { cast = "slashCast", impact = "fireballHit" },
		archetype = "Projectile",
		cooldown = 0.55,
		description = "A fast crescent of fire with a medium hitbox. 10 damage, recharges quickly.",
		stats = { damage = 10, speed = 150, range = 130, radius = 3, knockback = 8 },
		visual = {
			shape = "Block",
			size = Vector3.new(5, 0.8, 1.2),
			color = rgb(255, 150, 50),
			material = M.Neon,
		},
	},
	{
		id = "FireBoost",
		name = "Fire Boost",
		aliases = { "fire boost", "fireboost" },
		element = "Fire",
		slot = 3,
		glyph = GLYPH[3],
		sfx = { cast = "boostCast" },
		archetype = "Buff",
		cooldown = 14,
		description = "Your fire burns hotter: +25% damage for 8 seconds.",
		stats = { damageMult = 1.25, duration = 8 },
		visual = {
			shape = "Ball",
			size = Vector3.new(7, 7, 7),
			color = rgb(255, 120, 40),
			material = M.ForceField,
			transparency = 0.5,
		},
	},
	{
		id = "FirePillar",
		name = "Fire Pillar",
		aliases = { "fire pillar", "firepillar" },
		element = "Fire",
		slot = 4,
		glyph = GLYPH[4],
		sfx = { cast = "pillarCast", impact = "pillarBoom" },
		archetype = "Zone",
		cooldown = 7,
		description = "Point and click: a huge pillar of fire erupts where you aim after a short warning. 30 damage in a large area. Range 70.",
		stats = {
			delay = 0.7,
			damage = 30,
			radius = 9,
			range = 70,
			knockback = 22,
			reticle = true,
			pillar = true,
		},
		visual = {
			shape = "Cylinder",
			size = Vector3.new(2, 2, 2),
			color = rgb(255, 120, 40),
			material = M.Neon,
		},
	},
	{
		id = "FireBomb",
		name = "Fire Bomb",
		aliases = { "fire bomb", "firebomb", "bomb" },
		element = "Fire",
		slot = 5,
		ultimate = true,
		glyph = GLYPH[5],
		sfx = { cast = "bombCast", impact = "bombBoom" },
		archetype = "Projectile",
		cooldown = 16,
		description = "ULTIMATE: a huge fireball with a very large hitbox. 35 damage.",
		stats = { damage = 35, speed = 60, range = 120, radius = 7, knockback = 40 },
		visual = {
			shape = "Ball",
			size = Vector3.new(8, 8, 8),
			color = rgb(255, 80, 30),
			material = M.Neon,
			model = "Fireball",
		},
	},

	----------------------------------------------------------------------
	-- Water
	----------------------------------------------------------------------
	{
		id = "WaterSlice",
		name = "Water Slice",
		aliases = { "water slice", "waterslice", "slice" },
		element = "Water",
		slot = 1,
		glyph = GLYPH[1],
		sfx = { cast = "sliceCast", impact = "waterTrap" },
		archetype = "Projectile",
		cooldown = 0.55,
		description = "A fast slice of water with a medium hitbox. 10 damage.",
		stats = { damage = 10, speed = 150, range = 130, radius = 3, knockback = 8 },
		visual = {
			shape = "Block",
			size = Vector3.new(5, 0.8, 1.2),
			color = rgb(80, 180, 255),
			material = M.Neon,
		},
	},
	{
		id = "WaterBody",
		name = "Water Body",
		aliases = { "water body", "waterbody" },
		element = "Water",
		slot = 2,
		glyph = GLYPH[2],
		sfx = { cast = "bodyCast" },
		archetype = "Buff",
		cooldown = 22,
		description = "Turn to flowing water: you can't be hurt or affected by spells for 7 seconds.",
		stats = { invincible = true, duration = 7 },
		visual = {
			shape = "Ball",
			size = Vector3.new(7, 7, 7),
			color = rgb(64, 164, 255),
			material = M.ForceField,
			transparency = 0.4,
		},
	},
	{
		id = "WaterLock",
		name = "Water Lock",
		aliases = { "water lock", "waterlock", "bubble", "trap" },
		element = "Water",
		slot = 3,
		glyph = GLYPH[3],
		sfx = { cast = "waterCast", impact = "waterTrap" },
		archetype = "Control",
		cooldown = 4,
		description = "Trap an enemy in a bubble: 5 damage and a 1.5 second stun (no moving or casting).",
		stats = {
			damage = 5,
			speed = 75,
			range = 120,
			radius = 2.5,
			status = "Stun",
			statusDuration = 1.5,
			model = "WaterBubble", -- the trap bubble around the victim
		},
		visual = {
			shape = "Ball",
			size = Vector3.new(2.5, 2.5, 2.5),
			color = rgb(64, 164, 255),
			material = M.Glass,
			transparency = 0.3,
			model = "WaterBubble",
		},
	},
	{
		id = "WaterWave",
		name = "Water Wave",
		aliases = { "water wave", "waterwave", "wave" },
		element = "Water",
		slot = 4,
		glyph = GLYPH[4],
		sfx = { cast = "waveCast", impact = "waterTrap" },
		archetype = "Projectile",
		cooldown = 8,
		description = "Send a large wave rolling forward through everything in its path. 25 damage.",
		stats = { damage = 25, speed = 70, range = 110, radius = 8, knockback = 25, pierce = true },
		visual = {
			shape = "Block",
			size = Vector3.new(14, 6, 2.5),
			color = rgb(60, 150, 255),
			material = M.Glass,
			transparency = 0.25,
		},
	},
	{
		id = "WaterNebula",
		name = "Water Nebula",
		aliases = { "water nebula", "waternebula", "nebula" },
		element = "Water",
		slot = 5,
		ultimate = true,
		glyph = GLYPH[5],
		sfx = { cast = "nebulaCast", impact = "nebulaBoom" },
		archetype = "Zone",
		cooldown = 18,
		description = "ULTIMATE: point and click: a towering water pillar crashes down in a large area. 35 damage. Range 70.",
		stats = {
			delay = 0.9,
			damage = 35,
			radius = 10,
			range = 70,
			knockback = 28,
			reticle = true,
			pillar = true,
		},
		visual = {
			shape = "Cylinder",
			size = Vector3.new(2, 2, 2),
			color = rgb(70, 160, 255),
			material = M.Neon,
		},
	},

	----------------------------------------------------------------------
	-- Earth
	----------------------------------------------------------------------
	{
		id = "RockThrow",
		name = "Rock Throw",
		aliases = { "rock throw", "rockthrow", "rock" },
		element = "Earth",
		slot = 1,
		glyph = GLYPH[1],
		sfx = { cast = "throwCast", impact = "rockBreak" },
		archetype = "Projectile",
		cooldown = 1.1,
		description = "Hurl a large boulder. 15 damage and a solid shove.",
		stats = { damage = 15, speed = 80, range = 130, radius = 4.2, knockback = 22 },
		visual = {
			shape = "Ball",
			size = Vector3.new(4.5, 4.5, 4.5),
			color = rgb(150, 118, 86),
			material = M.Slate,
		},
	},
	{
		id = "EarthWall",
		name = "Earth Wall",
		aliases = { "earth wall", "earthwall", "wall", "rock wall", "rockwall" },
		element = "Earth",
		slot = 2,
		glyph = GLYPH[2],
		sfx = { cast = "rockRaise" },
		archetype = "Placeable",
		cooldown = 4,
		description = "Raise a rocky wall with 35 health that blocks spells. It breaks apart piece by piece.",
		stats = {
			health = 35, -- total damage the whole wall takes before it's gone
			lifetime = 20,
			maxActive = 3,
			hitByAll = true, -- every spell hits it, your own included
			model = "RockWall",
			segments = { x = 3, y = 2 }, -- fallback when the model isn't in the place
		},
		visual = {
			shape = "Block",
			-- Matches the RockWall model's size so placement rules fit it.
			size = Vector3.new(23.04, 12.38, 9.72),
			color = rgb(140, 112, 84),
			material = M.Ground,
		},
	},
	{
		id = "EarthPunch",
		name = "Earth Punch",
		aliases = { "earth punch", "earthpunch", "punch" },
		element = "Earth",
		slot = 3,
		glyph = GLYPH[3],
		sfx = { cast = "punchCast", impact = "rockBreak" },
		archetype = "Zone",
		cooldown = 5,
		description = "Point and click: a boulder bursts out of the ground beneath your target. 20 damage. Range 60.",
		stats = {
			delay = 0.4,
			damage = 20,
			radius = 5,
			range = 60,
			knockback = 28,
			reticle = true,
			rise = true,
		},
		visual = {
			shape = "Ball",
			size = Vector3.new(6, 6, 6),
			color = rgb(150, 118, 86),
			material = M.Slate,
		},
	},
	{
		id = "EarthPillar",
		name = "Earth Pillar",
		aliases = { "earth pillar", "earthpillar" },
		element = "Earth",
		slot = 4,
		glyph = GLYPH[4],
		sfx = { cast = "rockRaise", impact = "rockBreak" },
		archetype = "Line",
		cooldown = 9,
		description = "A wave of stone pillars erupts in a line in front of you. 30 damage to anyone it catches.",
		stats = {
			damage = 30,
			radius = 4.5,
			count = 6,
			spacing = 7,
			step = 0.12,
			delay = 0.35,
			knockback = 24,
		},
		visual = {
			shape = "Block",
			size = Vector3.new(4, 12, 4),
			color = rgb(150, 118, 86),
			material = M.Slate,
		},
	},
	{
		id = "Earthquake",
		name = "Earthquake",
		aliases = { "earthquake", "quake" },
		element = "Earth",
		slot = 5,
		ultimate = true,
		glyph = GLYPH[5],
		sfx = { cast = "quakeRumble", impact = "quakeBoom" },
		archetype = "Zone",
		cooldown = 22,
		description = "ULTIMATE: the ground shakes around you, then bursts. A long 2 second cast leaves you rooted, but it deals 40 damage in a huge area.",
		stats = {
			delay = 2,
			damage = 40,
			radius = 22,
			range = 0, -- centered on the caster
			knockback = 40,
			channel = true,
			pillar = true,
		},
		visual = {
			shape = "Cylinder",
			size = Vector3.new(2, 2, 2),
			color = rgb(176, 128, 80),
			material = M.Slate,
		},
	},

	----------------------------------------------------------------------
	-- Air
	----------------------------------------------------------------------
	{
		id = "Gust",
		name = "Gust",
		aliases = { "gust", "wind" },
		element = "Air",
		slot = 1,
		glyph = GLYPH[1],
		sfx = { cast = "gustCast" },
		archetype = "Projectile",
		cooldown = 0.9,
		description = "A fast gust of air. 15 damage.",
		stats = { damage = 15, speed = 140, range = 140, radius = 3.2, knockback = 12 },
		visual = {
			shape = "Ball",
			size = Vector3.new(3.5, 3.5, 3.5),
			color = rgb(220, 240, 255),
			material = M.ForceField,
			transparency = 0.4,
			model = "Gust",
		},
	},
	{
		id = "Whirlwind",
		name = "Whirlwind",
		aliases = { "whirlwind", "whirl" },
		element = "Air",
		slot = 2,
		glyph = GLYPH[2],
		sfx = { cast = "whirlCast" },
		archetype = "Projectile",
		cooldown = 5,
		description = "A wide gust that blows everyone it hits far away. 15 damage.",
		stats = { damage = 15, speed = 75, range = 90, radius = 7, knockback = 95 },
		visual = {
			shape = "Ball",
			size = Vector3.new(9, 9, 9),
			color = rgb(220, 240, 255),
			material = M.ForceField,
			transparency = 0.4,
			model = "Gust",
		},
	},
	{
		id = "AirBoost",
		name = "Air Boost",
		aliases = { "air boost", "airboost" },
		element = "Air",
		slot = 3,
		glyph = GLYPH[3],
		sfx = { cast = "airBoostCast" },
		archetype = "Buff",
		cooldown = 16,
		description = "Ride the wind: much faster and a higher jump for 6 seconds.",
		stats = { haste = true, duration = 6 },
		visual = {
			shape = "Ball",
			size = Vector3.new(6, 6, 6),
			color = rgb(190, 240, 225),
			material = M.ForceField,
			transparency = 0.5,
		},
	},
	{
		id = "AirShield",
		name = "Air Shield",
		aliases = { "air shield", "airshield", "shield" },
		element = "Air",
		slot = 4,
		glyph = GLYPH[4],
		sfx = { cast = "shieldCast" },
		archetype = "Buff",
		cooldown = 14,
		description = "A swirling shield for 4 seconds that blocks the next spell or damage that hits you.",
		stats = { barrier = true, duration = 4 },
		visual = {
			shape = "Ball",
			size = Vector3.new(7, 7, 7),
			color = rgb(190, 240, 235),
			material = M.ForceField,
			transparency = 0.45,
		},
	},
	{
		id = "Tornado",
		name = "Tornado",
		aliases = { "tornado", "twister" },
		element = "Air",
		slot = 5,
		ultimate = true,
		glyph = GLYPH[5],
		sfx = { cast = "tornadoCast", impact = "waterTrap" },
		archetype = "Projectile",
		cooldown = 18,
		description = "ULTIMATE: a tornado tears forward, blowing away everything it hits. 30 damage.",
		stats = { damage = 30, speed = 55, range = 120, radius = 6, knockback = 105, pierce = true },
		visual = {
			shape = "Block",
			size = Vector3.new(7, 14, 7),
			color = rgb(205, 235, 230),
			material = M.ForceField,
			transparency = 0.35,
		},
	},
}

local SpellDefinitions = {}

SpellDefinitions.list = DEFINITIONS

local byId: { [string]: SpellDef } = {}
for _, def in DEFINITIONS do
	assert(byId[def.id] == nil, `duplicate spell id {def.id}`)
	byId[def.id] = def
	table.freeze(def.stats)
	table.freeze(def.aliases)
end
SpellDefinitions.byId = byId

-- Every element's spell list in Elements must match the rows above.
for _, element in Elements.LIST do
	for slot, id in element.spells do
		local def = byId[id]
		assert(def, `{element.id} lists unknown spell {id}`)
		assert(def.element == element.id and def.slot == slot, `{id} is in the wrong element or slot`)
	end
end

function SpellDefinitions.get(id: string): SpellDef?
	return byId[id]
end

-- The five spells of an element, by slot.
function SpellDefinitions.ofElement(elementId: string): { SpellDef }
	local list: { SpellDef } = {}
	local element = Elements.get(elementId)
	if element then
		for _, id in element.spells do
			table.insert(list, byId[id])
		end
	end
	return list
end

return SpellDefinitions
