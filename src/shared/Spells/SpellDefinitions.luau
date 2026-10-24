--!strict
-- The spell dictionary. Every spell in the game is one row here; behavior
-- comes from its `archetype` (see src/server/Services/Archetypes). To add a
-- spell, add a row — no new code needed. Keep docs/SPELLS.md in sync.
--
-- Players DRAW each spell's `glyph` (shared/Spells/Glyphs) to ready it; every
-- spell needs a different one (tests/Glyphs.spec). Aliases are admin names
-- (`;give fire`), matched after normalization (lowercase, no punctuation).
--
-- Getting spells: every player starts with the `starter` spells. Every
-- other spell is unlocked from a crate of its rarity (shared/Economy/Crates,
-- server CrateService). In a match any spell can also be drafted.
--
-- Copy model: drawing a glyph adds one copy of the spell to the hotbar
-- (up to 5 held, duplicates allowed); casting uses a copy up. `cooldown` is
-- the spell's CAST cooldown, shared by every copy of that spell. Players
-- have 100 HP and can stockpile copies, so damage per cast cooldown is the
-- budget that matters (~16-20 DPS for the best spammable spells, a ~6s
-- time-to-kill). Numbers here are base values: projectile speed is scaled
-- by Config.PROJECTILE_SPEED_SCALE. tests/Balance.spec.luau enforces it.

local Types = require(script.Parent.Parent.Types)

type SpellDef = Types.SpellDef

local M = Enum.Material

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local DEFINITIONS: { SpellDef } = {
	-- Starters: every player owns these.
	{
		id = "Fireball",
		name = "Fireball",
		aliases = { "fireball", "fire", "flame", "blaze" },
		glyph = "circle",
		rarity = "Common",
		starter = true,
		archetype = "Projectile",
		cooldown = 0.9,
		description = "Hurl a ball of fire that burns players and structures.",
		-- radius is the bolt's hit radius (plus Config.HITBOX_BONUS against targets):
		-- a big, forgiving fireball. The visual is sized to match.
		stats = { damage = 16, speed = 95, range = 160, radius = 3.5, knockback = 18 },
		visual = {
			shape = "Ball",
			size = Vector3.new(3.2, 3.2, 3.2),
			color = rgb(255, 112, 40),
			material = M.Neon,
			model = "Fireball",
		},
	},
	{
		id = "WaterLock",
		name = "Water Lock",
		aliases = { "water lock", "waterlock", "water", "bubble", "trap" },
		glyph = "wave",
		rarity = "Common",
		starter = true,
		archetype = "Control",
		cooldown = 3,
		description = "Trap an enemy in a bubble so they can't move for 1.5 seconds.",
		stats = {
			damage = 4,
			speed = 75,
			range = 120,
			radius = 2.5,
			status = "Root",
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
		id = "RockWall",
		name = "Rock Wall",
		aliases = { "rock wall", "rockwall", "wall", "rock", "stone" },
		glyph = "triangle",
		rarity = "Common",
		starter = true,
		archetype = "Placeable",
		cooldown = 1,
		description = "Raise a rocky earth wall that blocks spells. It breaks apart piece by piece.",
		stats = {
			health = 50, -- total damage the whole wall takes before it's gone
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

	-- Crate spells: one per rarity (Common → Legendary crate).
	{
		id = "Gust",
		name = "Gust",
		aliases = { "gust", "wind", "push", "blow" },
		glyph = "chevron",
		rarity = "Common",
		archetype = "Projectile",
		cooldown = 1.5,
		description = "A wide blast of wind that shoves enemies far away. Low damage, huge hitbox.",
		-- A 6-stud radius (7.5 against players) makes it very hard to miss.
		stats = { damage = 5, speed = 90, range = 90, radius = 6, knockback = 95 },
		visual = {
			shape = "Ball",
			size = Vector3.new(7, 7, 7),
			color = rgb(220, 240, 255),
			material = M.ForceField,
			transparency = 0.4,
			model = "Gust",
		},
	},
	{
		id = "Zap",
		name = "Zap",
		aliases = { "zap", "thunder", "lightning", "strike" },
		glyph = "bolt",
		rarity = "Uncommon",
		archetype = "Zone",
		cooldown = 2.5,
		description = "Point and click: a thunderbolt strikes the ground where you aim after a short flash. Range 60.",
		-- A telegraphed burst (Zone with `delay`). `range` is the click
		-- limit (the server clamps to it); `reticle` shows the hit circle
		-- on the ground while Zap is readied (client ReticleController).
		stats = { delay = 0.45, damage = 18, radius = 5, range = 60, knockback = 20, reticle = true },
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
		glyph = "infinity",
		rarity = "Rare",
		archetype = "Buff",
		cooldown = 4,
		description = "Restore 10 health.",
		stats = { heal = 10 },
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
		glyph = "spiral",
		rarity = "Epic",
		archetype = "Zone",
		cooldown = 10,
		description = "A black hole sucks enemies in, traps them for 3 seconds, and deals 10 damage over time.",
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
		glyph = "star",
		rarity = "Legendary",
		archetype = "Placeable",
		cooldown = 12,
		description = "Summon a 30-health turret that shoots bullets at the nearest enemy player.",
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

function SpellDefinitions.get(id: string): SpellDef?
	return byId[id]
end

function SpellDefinitions.starters(): { string }
	local ids = {}
	for _, def in DEFINITIONS do
		if def.starter then
			table.insert(ids, def.id)
		end
	end
	return ids
end

-- All spell ids with the given rarity.
function SpellDefinitions.ofRarity(rarity: Types.Rarity): { string }
	local ids = {}
	for _, def in DEFINITIONS do
		if def.rarity == rarity then
			table.insert(ids, def.id)
		end
	end
	return ids
end

-- Spells a crate of the given rarity can drop (starters never drop).
function SpellDefinitions.crateDrops(rarity: Types.Rarity): { string }
	local ids = {}
	for _, def in DEFINITIONS do
		if def.rarity == rarity and not def.starter then
			table.insert(ids, def.id)
		end
	end
	return ids
end

return SpellDefinitions
