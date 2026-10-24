--!strict
-- The spell dictionary. Every spell in the game is one row here; behavior
-- comes from its `archetype` (see src/server/Services/Archetypes). To add a
-- spell, add a row — no new code needed. Keep docs/SPELLS.md in sync.
--
-- Aliases are what players can type or say. They are matched after
-- normalization (lowercase, no punctuation), so list plain words only.

local Types = require(script.Parent.Parent.Types)

type SpellDef = Types.SpellDef

local M = Enum.Material

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local DEFINITIONS: { SpellDef } = {
	-- Level 1 — starters
	{
		id = "Fireball",
		name = "Fireball",
		aliases = { "fireball", "fire", "flame", "blaze" },
		rarity = "Common",
		unlockLevel = 1,
		starter = true,
		archetype = "Projectile",
		cooldown = 1.2,
		description = "Hurl a ball of fire that burns players and structures.",
		stats = { damage = 22, speed = 90, range = 160, radius = 2, knockback = 25 },
		visual = { shape = "Ball", size = Vector3.new(2, 2, 2), color = rgb(255, 112, 40), material = M.Neon },
	},
	{
		id = "WaterLock",
		name = "Water Lock",
		aliases = { "water lock", "waterlock", "water", "bubble", "trap" },
		rarity = "Common",
		unlockLevel = 1,
		starter = true,
		archetype = "Control",
		cooldown = 6,
		description = "Trap an enemy in a bubble so they can't move for 2 seconds.",
		stats = { damage = 5, speed = 70, range = 120, radius = 2.5, status = "Root", statusDuration = 2 },
		visual = {
			shape = "Ball",
			size = Vector3.new(2.5, 2.5, 2.5),
			color = rgb(64, 164, 255),
			material = M.Glass,
			transparency = 0.3,
		},
	},
	{
		id = "RockWall",
		name = "Rock Wall",
		aliases = { "rock wall", "rockwall", "wall", "rock", "stone" },
		rarity = "Common",
		unlockLevel = 1,
		starter = true,
		archetype = "Placeable",
		cooldown = 5,
		description = "Raise a sturdy stone wall that blocks spells.",
		stats = { health = 300, lifetime = 45, maxActive = 3 },
		visual = { shape = "Block", size = Vector3.new(12, 8, 2), color = rgb(128, 120, 112), material = M.Slate },
	},

	-- Level 2
	{
		id = "WindGust",
		name = "Wind Gust",
		aliases = { "wind gust", "wind", "gust", "push" },
		rarity = "Common",
		unlockLevel = 2,
		archetype = "Projectile",
		cooldown = 3,
		description = "A blast of wind that shoves enemies away.",
		stats = { damage = 6, speed = 110, range = 90, radius = 4, knockback = 110 },
		visual = {
			shape = "Ball",
			size = Vector3.new(4, 4, 4),
			color = rgb(220, 240, 255),
			material = M.ForceField,
			transparency = 0.4,
		},
	},
	{
		id = "WoodenCrate",
		name = "Wooden Crate",
		aliases = { "wooden crate", "crate", "box" },
		rarity = "Common",
		unlockLevel = 2,
		archetype = "Placeable",
		cooldown = 2.5,
		description = "Drop a crate to hide behind or climb on.",
		stats = { health = 150, lifetime = 60, maxActive = 4 },
		visual = { shape = "Block", size = Vector3.new(5, 5, 5), color = rgb(160, 110, 60), material = M.WoodPlanks },
	},
	{
		id = "HealLeaf",
		name = "Heal Leaf",
		aliases = { "heal leaf", "heal", "leaf", "medicine" },
		rarity = "Common",
		unlockLevel = 2,
		archetype = "Buff",
		cooldown = 10,
		description = "Restore some of your health.",
		stats = { heal = 30 },
		visual = { shape = "Ball", size = Vector3.new(1.5, 1.5, 1.5), color = rgb(102, 187, 106), material = M.Neon },
	},
	{
		id = "Spark",
		name = "Spark",
		aliases = { "spark", "zap" },
		rarity = "Common",
		unlockLevel = 2,
		archetype = "Projectile",
		cooldown = 0.5,
		description = "A quick little zap. Low damage, fast fire.",
		stats = { damage = 8, speed = 160, range = 140, radius = 1 },
		visual = { shape = "Ball", size = Vector3.new(1, 1, 1), color = rgb(255, 238, 88), material = M.Neon },
	},

	-- Level 3
	{
		id = "IceShard",
		name = "Ice Shard",
		aliases = { "ice shard", "ice", "shard", "freeze" },
		rarity = "Common",
		unlockLevel = 3,
		archetype = "Projectile",
		cooldown = 2,
		description = "An icy spike that slows whoever it hits.",
		stats = { damage = 14, speed = 120, range = 150, radius = 1.5, status = "Slow", statusDuration = 3 },
		visual = { shape = "Wedge", size = Vector3.new(1, 1, 3), color = rgb(178, 235, 242), material = M.Ice },
	},
	{
		id = "BouncePad",
		name = "Bounce Pad",
		aliases = { "bounce pad", "trampoline", "spring", "bounce" },
		rarity = "Common",
		unlockLevel = 3,
		archetype = "Placeable",
		cooldown = 4,
		description = "A springy pad that launches anyone who steps on it.",
		stats = { health = 80, lifetime = 40, maxActive = 2, bounce = 110 },
		visual = { shape = "Cylinder", size = Vector3.new(1, 8, 8), color = rgb(236, 64, 122), material = M.SmoothPlastic },
	},
	{
		id = "MudPuddle",
		name = "Mud Puddle",
		aliases = { "mud puddle", "mud", "swamp" },
		rarity = "Common",
		unlockLevel = 3,
		archetype = "Zone",
		cooldown = 7,
		description = "A sticky puddle that slows enemies inside it.",
		stats = { radius = 10, duration = 6, status = "Slow", statusDuration = 1, range = 60 },
		visual = { shape = "Cylinder", size = Vector3.new(0.4, 20, 20), color = rgb(109, 76, 65), material = M.Mud },
	},
	{
		id = "Shield",
		name = "Shield",
		aliases = { "shield", "barrier", "protect" },
		rarity = "Rare",
		unlockLevel = 3,
		archetype = "Buff",
		cooldown = 14,
		description = "A bubble that absorbs the next 40 damage.",
		stats = { shield = 40, duration = 8 },
		visual = {
			shape = "Ball",
			size = Vector3.new(7, 7, 7),
			color = rgb(129, 212, 250),
			material = M.ForceField,
			transparency = 0.5,
		},
	},

	-- Level 4
	{
		id = "Lightning",
		name = "Lightning",
		aliases = { "lightning", "thunder", "bolt" },
		rarity = "Rare",
		unlockLevel = 4,
		archetype = "Projectile",
		cooldown = 4,
		description = "A bolt that chains to a nearby enemy. Double damage on bubbled foes!",
		stats = {
			damage = 20,
			speed = 220,
			range = 170,
			radius = 1.5,
			chain = 1,
			comboStatus = "Root",
			comboMultiplier = 2,
		},
		visual = { shape = "Block", size = Vector3.new(0.6, 0.6, 4), color = rgb(255, 241, 118), material = M.Neon },
	},
	{
		id = "Ladder",
		name = "Ladder",
		aliases = { "ladder", "stairs", "steps" },
		rarity = "Common",
		unlockLevel = 4,
		archetype = "Placeable",
		cooldown = 3,
		description = "Climbable steps to reach high ground.",
		stats = { health = 100, lifetime = 45, maxActive = 2 },
		visual = { shape = "Wedge", size = Vector3.new(6, 10, 12), color = rgb(188, 140, 90), material = M.Wood },
	},
	{
		id = "Dash",
		name = "Dash",
		aliases = { "dash", "sprint", "zoom", "run" },
		rarity = "Common",
		unlockLevel = 4,
		archetype = "Movement",
		cooldown = 4,
		description = "Zoom forward in a burst of speed.",
		stats = { dashSpeed = 120 },
		visual = { shape = "Ball", size = Vector3.new(1, 1, 1), color = rgb(255, 255, 255), material = M.Neon },
	},
	{
		id = "Cannon",
		name = "Cannon",
		aliases = { "cannon", "turret" },
		rarity = "Rare",
		unlockLevel = 4,
		archetype = "Placeable",
		cooldown = 12,
		description = "A cannon that fires at the closest enemy.",
		stats = { health = 200, lifetime = 30, maxActive = 1, turret = true, damage = 12, range = 80 },
		visual = { shape = "Cylinder", size = Vector3.new(5, 3, 3), color = rgb(69, 90, 100), material = M.Metal },
	},

	-- Level 5
	{
		id = "Tornado",
		name = "Tornado",
		aliases = { "tornado", "twister", "cyclone" },
		rarity = "Rare",
		unlockLevel = 5,
		archetype = "Zone",
		cooldown = 12,
		description = "A swirling twister that pulls enemies in.",
		stats = { radius = 18, duration = 4, pull = 40, damage = 4, range = 70 },
		visual = {
			shape = "Cylinder",
			size = Vector3.new(24, 10, 10),
			color = rgb(207, 216, 220),
			material = M.ForceField,
			transparency = 0.4,
		},
	},
	{
		id = "Snowman",
		name = "Snowman",
		aliases = { "snowman", "decoy" },
		rarity = "Rare",
		unlockLevel = 5,
		archetype = "Summon",
		cooldown = 12,
		description = "A snowman decoy that cannons and summons target first.",
		stats = { health = 120, lifetime = 20, decoy = true },
		visual = { shape = "Ball", size = Vector3.new(4, 4, 4), color = rgb(250, 250, 250), material = M.Snow },
	},
	{
		id = "Bridge",
		name = "Bridge",
		aliases = { "bridge", "plank" },
		rarity = "Common",
		unlockLevel = 5,
		archetype = "Placeable",
		cooldown = 5,
		description = "A long plank to cross gaps.",
		stats = { health = 120, lifetime = 45, maxActive = 2 },
		visual = { shape = "Block", size = Vector3.new(6, 1, 24), color = rgb(161, 136, 127), material = M.WoodPlanks },
	},
	{
		id = "BananaPeel",
		name = "Banana Peel",
		aliases = { "banana peel", "banana", "slip" },
		rarity = "Common",
		unlockLevel = 5,
		archetype = "Placeable",
		cooldown = 6,
		description = "A sneaky peel. Enemies who step on it slip and slide.",
		stats = { health = 20, lifetime = 40, maxActive = 3, trap = true, status = "Slippery", statusDuration = 2.5 },
		visual = { shape = "Block", size = Vector3.new(2, 0.3, 1.2), color = rgb(255, 235, 59), material = M.SmoothPlastic },
	},

	-- Level 6
	{
		id = "Meteor",
		name = "Meteor",
		aliases = { "meteor", "comet", "asteroid" },
		rarity = "Epic",
		unlockLevel = 6,
		archetype = "Zone",
		cooldown = 14,
		description = "Call down a meteor. Big boom after a short warning.",
		stats = { radius = 14, damage = 45, delay = 1.5, range = 120, knockback = 80, destroysStructures = false },
		visual = { shape = "Ball", size = Vector3.new(8, 8, 8), color = rgb(255, 87, 34), material = M.CrackedLava },
	},
	{
		id = "Teleport",
		name = "Teleport",
		aliases = { "teleport", "blink", "warp" },
		rarity = "Rare",
		unlockLevel = 6,
		archetype = "Movement",
		cooldown = 8,
		description = "Blink to where you're aiming.",
		stats = { teleport = true, range = 50 },
		visual = { shape = "Ball", size = Vector3.new(3, 3, 3), color = rgb(149, 117, 205), material = M.Neon },
	},
	{
		id = "VineSnare",
		name = "Vine Snare",
		aliases = { "vine snare", "vine", "vines", "roots" },
		rarity = "Rare",
		unlockLevel = 6,
		archetype = "Control",
		cooldown = 8,
		description = "Roots grab every enemy in a small area.",
		stats = { radius = 10, status = "Root", statusDuration = 1.5, range = 70, damage = 8 },
		visual = { shape = "Cylinder", size = Vector3.new(0.5, 20, 20), color = rgb(56, 142, 60), material = M.Grass },
	},
	{
		id = "Tower",
		name = "Tower",
		aliases = { "tower", "fort", "watchtower" },
		rarity = "Rare",
		unlockLevel = 6,
		archetype = "Placeable",
		cooldown = 14,
		description = "A tall tower for high ground.",
		stats = { health = 500, lifetime = 50, maxActive = 1 },
		visual = { shape = "Block", size = Vector3.new(8, 18, 8), color = rgb(141, 110, 99), material = M.Brick },
	},

	-- Level 7
	{
		id = "Dragon",
		name = "Dragon",
		aliases = { "dragon", "wyvern" },
		rarity = "Epic",
		unlockLevel = 7,
		archetype = "Summon",
		cooldown = 20,
		description = "A baby dragon that flies at enemies and breathes fire.",
		stats = { health = 150, lifetime = 15, flier = true, damage = 10, range = 60 },
		visual = { shape = "Block", size = Vector3.new(4, 3, 6), color = rgb(229, 57, 53), material = M.SmoothPlastic },
	},
	{
		id = "BlackIce",
		name = "Black Ice",
		aliases = { "black ice", "frost", "glacier", "icy" },
		rarity = "Rare",
		unlockLevel = 7,
		archetype = "Zone",
		cooldown = 10,
		description = "Super slippery ice. Enemies slide around helplessly.",
		stats = { radius = 14, duration = 7, status = "Slippery", statusDuration = 1, range = 60 },
		visual = {
			shape = "Cylinder",
			size = Vector3.new(0.3, 28, 28),
			color = rgb(84, 110, 122),
			material = M.Glacier,
			transparency = 0.2,
		},
	},
	{
		id = "Magnet",
		name = "Magnet",
		aliases = { "magnet", "pull", "attract" },
		rarity = "Rare",
		unlockLevel = 7,
		archetype = "Control",
		cooldown = 9,
		description = "Yank the enemy you hit toward you.",
		stats = { damage = 6, speed = 100, range = 100, radius = 2, knockback = -90 },
		visual = { shape = "Block", size = Vector3.new(2, 2, 1), color = rgb(198, 40, 40), material = M.Metal },
	},
	{
		id = "Balloon",
		name = "Balloon",
		aliases = { "balloon", "float", "fly" },
		rarity = "Common",
		unlockLevel = 7,
		archetype = "Movement",
		cooldown = 7,
		description = "Float upward to escape or get the high ground.",
		stats = { lift = 70 },
		visual = { shape = "Ball", size = Vector3.new(3, 3.5, 3), color = rgb(244, 67, 54), material = M.SmoothPlastic },
	},

	-- Level 8
	{
		id = "Volcano",
		name = "Volcano",
		aliases = { "volcano", "lava", "magma" },
		rarity = "Epic",
		unlockLevel = 8,
		archetype = "Placeable",
		cooldown = 18,
		description = "A mini volcano that burns enemies nearby.",
		stats = { health = 250, lifetime = 20, maxActive = 1, hazardDps = 12, radius = 12 },
		visual = { shape = "Wedge", size = Vector3.new(10, 7, 10), color = rgb(93, 64, 55), material = M.Basalt },
	},
	{
		id = "Mirror",
		name = "Mirror",
		aliases = { "mirror", "reflect" },
		rarity = "Epic",
		unlockLevel = 8,
		archetype = "Buff",
		cooldown = 16,
		description = "For 3 seconds, projectiles that hit you bounce back.",
		stats = { reflect = true, duration = 3 },
		visual = {
			shape = "Ball",
			size = Vector3.new(7, 7, 7),
			color = rgb(224, 224, 224),
			material = M.Glass,
			transparency = 0.5,
		},
	},
	{
		id = "Robot",
		name = "Robot",
		aliases = { "robot", "golem", "bot" },
		rarity = "Epic",
		unlockLevel = 8,
		archetype = "Summon",
		cooldown = 20,
		description = "A clunky robot buddy that punches enemies.",
		stats = { health = 220, lifetime = 18, melee = true, damage = 14, range = 60 },
		visual = { shape = "Block", size = Vector3.new(4, 6, 3), color = rgb(144, 164, 174), material = M.DiamondPlate },
	},
	{
		id = "Giant",
		name = "Giant",
		aliases = { "giant", "grow", "big", "huge" },
		rarity = "Rare",
		unlockLevel = 8,
		archetype = "Buff",
		cooldown = 18,
		description = "Grow huge: bigger, tougher, and harder to knock back.",
		stats = { scale = 1.6, shield = 50, duration = 8 },
		visual = { shape = "Ball", size = Vector3.new(2, 2, 2), color = rgb(255, 167, 38), material = M.Neon },
	},

	-- Level 9
	{
		id = "BlackHole",
		name = "Black Hole",
		aliases = { "black hole", "blackhole", "vortex", "void" },
		rarity = "Legendary",
		unlockLevel = 9,
		archetype = "Zone",
		cooldown = 24,
		description = "A tiny black hole that drags everything in and crushes it.",
		stats = { radius = 22, duration = 4, pull = 70, damage = 10, range = 80 },
		visual = { shape = "Ball", size = Vector3.new(5, 5, 5), color = rgb(20, 0, 40), material = M.Neon },
	},
	{
		id = "Castle",
		name = "Castle",
		aliases = { "castle", "fortress" },
		rarity = "Epic",
		unlockLevel = 9,
		archetype = "Placeable",
		cooldown = 22,
		description = "A big castle wall. Very hard to break.",
		stats = { health = 800, lifetime = 50, maxActive = 1 },
		visual = { shape = "Block", size = Vector3.new(20, 14, 4), color = rgb(176, 168, 160), material = M.Cobblestone },
	},
	{
		id = "Shrink",
		name = "Shrink",
		aliases = { "shrink", "tiny", "small", "mini" },
		rarity = "Epic",
		unlockLevel = 9,
		archetype = "Control",
		cooldown = 14,
		description = "Shrink an enemy so they're tiny and weak for 4 seconds.",
		stats = { damage = 4, speed = 100, range = 110, radius = 2, status = "Shrink", statusDuration = 4 },
		visual = { shape = "Ball", size = Vector3.new(1.5, 1.5, 1.5), color = rgb(240, 98, 146), material = M.Neon },
	},
	{
		id = "Rainbow",
		name = "Rainbow",
		aliases = { "rainbow" },
		rarity = "Rare",
		unlockLevel = 9,
		archetype = "Zone",
		cooldown = 18,
		description = "A rainbow that heals you and your teammates inside it.",
		stats = { radius = 14, duration = 5, heal = 8, teamHeal = true, range = 50 },
		visual = {
			shape = "Cylinder",
			size = Vector3.new(0.4, 28, 28),
			color = rgb(255, 128, 171),
			material = M.Neon,
			transparency = 0.5,
		},
	},

	-- Level 10
	{
		id = "Phoenix",
		name = "Phoenix",
		aliases = { "phoenix", "rebirth", "revive" },
		rarity = "Legendary",
		unlockLevel = 10,
		archetype = "Buff",
		cooldown = 40,
		description = "If you're knocked out in the next 10 seconds, rise again at half health.",
		stats = { revive = true, duration = 10 },
		visual = { shape = "Ball", size = Vector3.new(3, 3, 3), color = rgb(255, 145, 0), material = M.Neon },
	},
	{
		id = "Earthquake",
		name = "Earthquake",
		aliases = { "earthquake", "quake", "tremor" },
		rarity = "Legendary",
		unlockLevel = 10,
		archetype = "Zone",
		cooldown = 30,
		description = "Shake the ground. Smashes structures and knocks players around.",
		stats = { radius = 30, damage = 20, delay = 0.5, knockback = 60, destroysStructures = true, range = 40 },
		visual = { shape = "Cylinder", size = Vector3.new(0.5, 60, 60), color = rgb(121, 85, 72), material = M.Ground },
	},
	{
		id = "TimeStop",
		name = "Time Stop",
		aliases = { "time stop", "timestop", "freeze time", "pause", "stop" },
		rarity = "Legendary",
		unlockLevel = 10,
		archetype = "Control",
		cooldown = 35,
		description = "Freeze every enemy near you for 1.5 seconds.",
		stats = { radius = 30, status = "TimeStop", statusDuration = 1.5, range = 0 },
		visual = {
			shape = "Ball",
			size = Vector3.new(60, 60, 60),
			color = rgb(255, 213, 79),
			material = M.ForceField,
			transparency = 0.6,
		},
	},
	{
		id = "Kraken",
		name = "Kraken",
		aliases = { "kraken", "octopus", "squid" },
		rarity = "Legendary",
		unlockLevel = 10,
		archetype = "Summon",
		cooldown = 30,
		description = "A giant kraken tentacle that slams enemies around it.",
		stats = { health = 300, lifetime = 12, damage = 18, radius = 16, range = 60 },
		visual = { shape = "Cylinder", size = Vector3.new(14, 3, 3), color = rgb(123, 31, 162), material = M.SmoothPlastic },
	},
	{
		id = "WizardHat",
		name = "Wizard Hat",
		aliases = { "wizard hat", "wizard", "hat", "magic" },
		rarity = "Epic",
		unlockLevel = 10,
		archetype = "Buff",
		cooldown = 30,
		description = "All your cooldowns are cut in half for 8 seconds.",
		stats = { cooldownCut = 0.5, duration = 8 },
		visual = { shape = "Wedge", size = Vector3.new(2, 3, 2), color = rgb(63, 81, 181), material = M.Fabric },
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

-- Spells that unlock exactly at `level`.
function SpellDefinitions.unlockedAt(level: number): { string }
	local ids = {}
	for _, def in DEFINITIONS do
		if def.unlockLevel == level then
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

return SpellDefinitions
