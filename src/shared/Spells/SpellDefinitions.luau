--!strict
-- The spell dictionary. Every spell in the game is one row here; behavior
-- comes from its `archetype` (see src/server/Services/Archetypes). To add a
-- spell, add a row — no new code needed. Keep docs/SPELLS.md in sync.
--
-- Schools: every spell belongs to one of four elements (shared/Spells/
-- Elements) or to Arcane. Its `role` (basic, fast, boost, defense, stun,
-- heavy, area, support, ultimate) decides the shape the player draws
-- (Glyphs.ROLE), the same everywhere, and a loadout never repeats a shape.
--
-- Aliases are admin names (`;give fireball`), matched after normalization
-- (lowercase, no punctuation), so list plain words only.
--
-- Getting spells: an element's three BASE spells (slots 1-3, no `rarity`)
-- come with the element: the first is a free pick, the others are bought with
-- coins. Every other spell is a CRATE spell (it has a `rarity`) won from the
-- Spell Crate and equipped in the loadout's two extra slots (shared/Spells/
-- Loadout). Slot 4 is a crate spell, slot 5 an ultimate. Neutral crate spells
-- belong to the "Arcane" school instead of an element.
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
-- Hitbox sizes (`radius`, studs; players add Config.HITBOX_BONUS = 2):
--   medium 4.5-5 · large 6-7 · wide 8.5-11 · huge 12-25 (areas)

local Elements = require(script.Parent.Elements)
local Glyphs = require(script.Parent.Glyphs)
local Types = require(script.Parent.Parent.Types)

type SpellDef = Types.SpellDef

local M = Enum.Material

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local ROLE = Glyphs.ROLE

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
		role = "basic",
		glyph = ROLE.basic,
		sfx = { cast = "fireballCast", impact = "fireballHit" },
		archetype = "Projectile",
		cooldown = 3,
		description = "Hurl a ball of fire with a medium hitbox. 15 damage.",
		stats = { damage = 15, speed = 95, range = 160, radius = 5, knockback = 18 },
		visual = {
			shape = "Ball",
			size = Vector3.new(4.5, 4.5, 4.5),
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
		role = "fast",
		glyph = ROLE.fast,
		sfx = { cast = "slashCast", impact = "slashHit" },
		archetype = "Projectile",
		cooldown = 2,
		description = "A fast crescent of fire with a medium hitbox. 10 damage, 2 second cooldown.",
		stats = { damage = 10, speed = 150, range = 130, radius = 4.5, knockback = 8 },
		visual = {
			shape = "Block",
			size = Vector3.new(7, 1, 1.6),
			color = rgb(255, 150, 50),
			material = M.Neon,
			model = "FireSlash",
		},
	},
	{
		id = "FireBoost",
		name = "Fire Boost",
		aliases = { "fire boost", "fireboost" },
		element = "Fire",
		slot = 3,
		role = "boost",
		glyph = ROLE.boost,
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
			model = "FireBoost",
		},
	},
	{
		id = "FirePillar",
		name = "Fire Pillar",
		aliases = { "fire pillar", "firepillar" },
		element = "Fire",
		slot = 4,
		rarity = "Uncommon",
		role = "area",
		glyph = ROLE.area,
		sfx = { cast = "pillarCast", impact = "pillarBoom" },
		archetype = "Zone",
		cooldown = 7,
		description = "Point and click: a huge pillar of fire erupts where you aim after a short warning. 30 damage in a large area. Range 70.",
		stats = {
			delay = 0.7,
			damage = 30,
			radius = 12,
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
			model = "FirePillar",
		},
	},
	{
		id = "FireBomb",
		name = "Fire Bomb",
		aliases = { "fire bomb", "firebomb", "bomb" },
		element = "Fire",
		slot = 5,
		rarity = "Epic",
		role = "ultimate",
		ultimate = true,
		glyph = ROLE.ultimate,
		sfx = { cast = "bombCast", impact = "bombBoom" },
		archetype = "Projectile",
		cooldown = 16,
		description = "ULTIMATE: a huge fireball with a very large hitbox. 35 damage.",
		stats = { damage = 35, speed = 60, range = 120, radius = 10, knockback = 40 },
		visual = {
			shape = "Ball",
			size = Vector3.new(11, 11, 11),
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
		role = "fast",
		glyph = ROLE.fast,
		sfx = { cast = "sliceCast", impact = "sliceHit" },
		archetype = "Projectile",
		cooldown = 2,
		description = "A fast slice of water with a medium hitbox. 10 damage.",
		stats = { damage = 10, speed = 150, range = 130, radius = 4.5, knockback = 8 },
		visual = {
			shape = "Block",
			size = Vector3.new(7, 1, 1.6),
			color = rgb(80, 180, 255),
			material = M.Neon,
			model = "WaterSlice",
		},
	},
	{
		id = "WaterBody",
		name = "Water Body",
		aliases = { "water body", "waterbody" },
		element = "Water",
		slot = 2,
		role = "boost",
		glyph = ROLE.boost,
		sfx = { cast = "bodyCast" },
		archetype = "Buff",
		cooldown = 22,
		description = "Turn to flowing water: you can't be hurt or affected by spells for 3 seconds.",
		stats = { invincible = true, duration = 3 },
		visual = {
			shape = "Ball",
			size = Vector3.new(7, 7, 7),
			color = rgb(64, 164, 255),
			material = M.ForceField,
			transparency = 0.4,
			model = "WaterBody",
		},
	},
	{
		id = "WaterLock",
		name = "Water Lock",
		aliases = { "water lock", "waterlock", "bubble", "trap" },
		element = "Water",
		slot = 3,
		role = "stun",
		glyph = ROLE.stun,
		sfx = { cast = "waterCast", impact = "lockPop" },
		archetype = "Control",
		cooldown = 4,
		description = "Trap an enemy in a bubble: 5 damage and a 1.5 second stun (no moving or casting).",
		stats = {
			damage = 5,
			speed = 75,
			range = 120,
			radius = 4,
			status = "Stun",
			statusDuration = 1.5,
			model = "WaterBubble", -- the trap bubble around the victim
		},
		visual = {
			shape = "Ball",
			size = Vector3.new(3.5, 3.5, 3.5),
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
		rarity = "Rare",
		role = "heavy",
		glyph = ROLE.heavy,
		sfx = { cast = "waveCast", impact = "waveCrash" },
		archetype = "Projectile",
		cooldown = 8,
		description = "Send a large wave rolling forward through everything in its path. 25 damage.",
		stats = { damage = 25, speed = 70, range = 110, radius = 11, knockback = 25, pierce = true },
		visual = {
			shape = "Block",
			size = Vector3.new(19, 8, 3),
			color = rgb(60, 150, 255),
			material = M.Glass,
			transparency = 0.25,
			model = "WaterWave",
		},
	},
	{
		id = "WaterNebula",
		name = "Water Nebula",
		aliases = { "water nebula", "waternebula", "nebula" },
		element = "Water",
		slot = 5,
		rarity = "Legendary",
		role = "ultimate",
		ultimate = true,
		glyph = ROLE.ultimate,
		sfx = { cast = "nebulaCast", impact = "nebulaBoom" },
		archetype = "Zone",
		cooldown = 18,
		description = "ULTIMATE: point and click: a towering water pillar crashes down in a large area. 35 damage. Range 70.",
		stats = {
			delay = 0.9,
			damage = 35,
			radius = 13,
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
			model = "WaterNebula",
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
		role = "basic",
		glyph = ROLE.basic,
		sfx = { cast = "throwCast", impact = "rockSmash" },
		archetype = "Projectile",
		cooldown = 3,
		description = "Hurl a large boulder. 15 damage and a solid shove.",
		stats = { damage = 15, speed = 80, range = 130, radius = 6, knockback = 22 },
		visual = {
			shape = "Ball",
			size = Vector3.new(6.3, 6.3, 6.3),
			color = rgb(150, 118, 86),
			material = M.Slate,
			model = "RockThrow",
		},
	},
	{
		id = "EarthWall",
		name = "Earth Wall",
		aliases = { "earth wall", "earthwall", "wall", "rock wall", "rockwall" },
		element = "Earth",
		slot = 2,
		role = "defense",
		glyph = ROLE.defense,
		sfx = { cast = "rockRaise", impact = "wallHit" },
		archetype = "Placeable",
		cooldown = 4,
		description = "Raise a rocky wall with 35 health that blocks spells. It breaks apart piece by piece.",
		stats = {
			health = 35, -- total damage the whole wall takes before it's gone
			lifetime = 20,
			maxActive = 3,
			model = "EarthWall",
			segments = { x = 3, y = 2 }, -- fallback when the model isn't in the place
		},
		visual = {
			shape = "Block",
			-- Matches the EarthWall model's size so placement rules fit it.
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
		role = "heavy",
		glyph = ROLE.heavy,
		sfx = { cast = "punchCast", impact = "rockBreak" },
		archetype = "Zone",
		cooldown = 5,
		description = "Point and click: a boulder bursts out of the ground beneath your target. 20 damage. Range 60.",
		stats = {
			delay = 0.4,
			damage = 20,
			radius = 7,
			range = 60,
			knockback = 28,
			reticle = true,
			rise = true,
		},
		visual = {
			shape = "Ball",
			size = Vector3.new(8, 8, 8),
			color = rgb(150, 118, 86),
			material = M.Slate,
			model = "EarthPunch",
		},
	},
	{
		id = "EarthPillar",
		name = "Earth Pillar",
		aliases = { "earth pillar", "earthpillar" },
		element = "Earth",
		slot = 4,
		rarity = "Uncommon",
		role = "area",
		glyph = ROLE.area,
		sfx = { cast = "rockRaise", impact = "rockBreak" },
		archetype = "Line",
		cooldown = 9,
		description = "A wave of stone pillars erupts in a line in front of you. 30 damage to anyone it catches.",
		stats = {
			damage = 30,
			radius = 13,
			count = 6,
			spacing = 18,
			step = 0.12,
			delay = 0.35,
			knockback = 24,
		},
		visual = {
			shape = "Block",
			size = Vector3.new(5.5, 14, 5.5),
			color = rgb(150, 118, 86),
			material = M.Slate,
			model = "EarthPillar",
		},
	},
	{
		id = "Earthquake",
		name = "Earthquake",
		aliases = { "earthquake", "quake" },
		element = "Earth",
		slot = 5,
		rarity = "Legendary",
		role = "ultimate",
		ultimate = true,
		glyph = ROLE.ultimate,
		sfx = { cast = "quakeRumble", impact = "quakeBoom" },
		archetype = "Zone",
		cooldown = 22,
		description = "ULTIMATE: the ground shakes around you, then bursts. A quick 1.2 second cast leaves you rooted, but it deals 40 damage in a huge area.",
		stats = {
			delay = 1.2,
			damage = 40,
			radius = 50,
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
			model = "Earthquake",
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
		role = "basic",
		glyph = ROLE.basic,
		sfx = { cast = "gustCast", impact = "gustHit" },
		archetype = "Projectile",
		cooldown = 3,
		description = "A fast gust of air. 15 damage.",
		stats = { damage = 15, speed = 140, range = 140, radius = 4.6, knockback = 12 },
		visual = {
			shape = "Ball",
			size = Vector3.new(5, 5, 5),
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
		role = "heavy",
		glyph = ROLE.heavy,
		sfx = { cast = "whirlCast", impact = "whirlHit" },
		archetype = "Projectile",
		cooldown = 5,
		description = "A wide gust that blows everyone it hits far away. 15 damage.",
		stats = { damage = 15, speed = 75, range = 90, radius = 10, knockback = 95 },
		visual = {
			shape = "Ball",
			size = Vector3.new(12.5, 12.5, 12.5),
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
		role = "boost",
		glyph = ROLE.boost,
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
			model = "AirBoost",
		},
	},
	{
		id = "AirShield",
		name = "Air Shield",
		aliases = { "air shield", "airshield", "shield" },
		element = "Air",
		slot = 4,
		rarity = "Common",
		role = "ward",
		glyph = ROLE.ward,
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
			model = "AirShield",
		},
	},
	{
		id = "Tornado",
		name = "Tornado",
		aliases = { "tornado", "twister" },
		element = "Air",
		slot = 5,
		rarity = "Epic",
		role = "ultimate",
		ultimate = true,
		glyph = ROLE.ultimate,
		sfx = { cast = "tornadoCast", impact = "tornadoHit" },
		archetype = "Projectile",
		cooldown = 18,
		description = "ULTIMATE: a tornado tears forward, blowing away everything it hits. 30 damage.",
		stats = {
			damage = 30,
			speed = 55,
			range = 120,
			radius = 8.5,
			knockback = 105,
			pierce = true,
		},
		visual = {
			shape = "Block",
			size = Vector3.new(9.5, 17, 9.5),
			color = rgb(205, 235, 230),
			material = M.ForceField,
			transparency = 0.35,
			model = "Tornado",
		},
	},

	----------------------------------------------------------------------
	-- Arcane (crate spells that belong to no element)
	----------------------------------------------------------------------
	{
		id = "Zap",
		name = "Lightning",
		aliases = { "lightning", "zap", "thunder", "strike", "bolt" },
		element = "Arcane",
		slot = 4,
		rarity = "Rare",
		role = "storm",
		glyph = ROLE.storm,
		sfx = { cast = "zapCharge", impact = "zapStrike" },
		archetype = "Zone",
		cooldown = 2.5,
		description = "Point and click: a thunderbolt strikes where you aim after a short flash. 18 damage. Range 60.",
		stats = {
			delay = 0.45,
			damage = 18,
			radius = 5,
			range = 60,
			knockback = 20,
			reticle = true,
		},
		visual = {
			shape = "Cylinder",
			size = Vector3.new(2, 2, 2),
			color = rgb(255, 238, 88),
			material = M.Neon,
			model = "Zap",
		},
	},
	{
		id = "Heal",
		name = "Heal",
		aliases = { "heal", "medic", "health", "cure" },
		element = "Arcane",
		slot = 4,
		rarity = "Common",
		role = "support",
		glyph = ROLE.support,
		sfx = { cast = "healChime" },
		archetype = "Buff",
		cooldown = 60,
		description = "A warm light mends you: restore 25 health. It takes a full minute to recharge.",
		stats = { heal = 25, duration = 1.5 }, -- `duration` is just how long the green glow lasts
		visual = {
			shape = "Ball",
			size = Vector3.new(1.5, 1.5, 1.5),
			color = rgb(102, 187, 106),
			material = M.Neon,
			model = "Heal",
		},
	},
	{
		id = "BlackHole",
		name = "Black Hole",
		aliases = { "black hole", "blackhole", "vortex", "void" },
		element = "Arcane",
		slot = 4,
		rarity = "Legendary",
		role = "vortex",
		glyph = ROLE.vortex,
		sfx = { cast = "blackHoleOpen", impact = "blackHoleCollapse" },
		archetype = "Zone",
		cooldown = 10,
		description = "Point and click: a black hole drags every enemy it catches to its center and holds them there for 3 seconds (they can still cast spells), dealing 10 damage over time. Training dummies and Battleground NPCs get sucked in and hurt too. Range 70.",
		-- `hold`: enemies pulled into the core are Rooted (trapped) at the
		-- center until the hole closes. 10 damage over its 3 seconds.
		stats = {
			radius = 16,
			duration = 3,
			pull = 60,
			damage = 10 / 3,
			range = 70,
			maxActive = 1,
			hold = true,
			reticle = true,
		},
		visual = {
			shape = "Ball",
			size = Vector3.new(6, 6, 6),
			color = rgb(40, 0, 70),
			material = M.Neon,
			model = "BlackHole",
		},
	},
	{
		id = "Turret",
		name = "Turret",
		aliases = { "turret", "sentry", "gun" },
		element = "Arcane",
		slot = 4,
		rarity = "Rare",
		role = "summon",
		glyph = ROLE.summon,
		sfx = { cast = "turretDeploy", impact = "turretShot" },
		archetype = "Placeable",
		cooldown = 12,
		description = "Summon a 30-health turret that shoots bullets at the nearest enemy, training dummy, or Battleground NPC for 20 seconds.",
		stats = {
			health = 30,
			lifetime = 20,
			maxActive = 1,
			turret = true,
			damage = 6,
			range = 80,
			fireInterval = 1,
		},
		visual = {
			shape = "Block",
			-- Matches the Turret model's size so placement rules fit it.
			size = Vector3.new(4, 5, 4),
			color = rgb(84, 110, 122),
			material = M.Metal,
			model = "Turret",
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

-- Every element's base spells in Elements must match the rows above, and a
-- spell has a rarity exactly when it is not a base spell.
local isBase: { [string]: boolean } = {}
for _, element in Elements.LIST do
	for slot, id in element.base do
		local def = byId[id]
		assert(def, `{element.id} lists unknown spell {id}`)
		assert(
			def.element == element.id and def.slot == slot and def.rarity == nil,
			`{id} is not base slot {slot} of {element.id}`
		)
		isBase[id] = true
	end
end
for _, def in DEFINITIONS do
	assert(isBase[def.id] ~= nil or def.rarity ~= nil, `{def.id} needs a rarity (a crate spell)`)
	assert(
		def.element == "Arcane" or Elements.get(def.element) ~= nil,
		`{def.id} is in an unknown school`
	)
end

function SpellDefinitions.get(id: string): SpellDef?
	return byId[id]
end

-- The three base spells of an element, by slot.
function SpellDefinitions.ofElement(elementId: string): { SpellDef }
	local list: { SpellDef } = {}
	local element = Elements.get(elementId)
	if element then
		for _, id in element.base do
			table.insert(list, byId[id])
		end
	end
	return list
end

-- Every crate spell: the Spell Crate's prize pool.
function SpellDefinitions.crateSpells(): { SpellDef }
	local list: { SpellDef } = {}
	for _, def in DEFINITIONS do
		if def.rarity then
			table.insert(list, def)
		end
	end
	return list
end

return SpellDefinitions
