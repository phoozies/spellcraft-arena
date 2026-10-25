--!strict
-- The particle look of every spell, as plain data. Client/Fx/SpellVfx reads
-- these to decorate bolts, impacts, and buff auras; the spell registry
-- (Spells/SpellRegistry) names one style per spell and tests/Registry.spec
-- checks the style exists. Built only from Roblox's own particle textures, so
-- nothing here needs uploading.
--
--   bolt styles   trail + particles on a flying bolt, burst on impact
--   auras         particles + an outline that ride on a caster while a buff lasts
--
-- To give a new spell its own look, add a style here and name it in the
-- spell's registry entry.

local VfxStyles = {}

VfxStyles.TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}
local TEX = VfxStyles.TEX

-- The kinds of impact SpellVfx.impact can draw:
--   explosion  fireball flash, flames, smoke, embers
--   slashCut   a crossed pair of cut marks and sparks
--   splash     flying droplets, mist, and a ripple
--   bubble     a bubble that swells and pops, shedding small bubbles
--   rubble     rock chunks, dust, and a ground ring
--   wind       an expanding ring of air and puffs
--   storm      wind rings with debris flung out
--   bolt       a white flash with jagged lightning forks
--   spark      a few quick sparks (small bullets)
VfxStyles.HITS =
	{ "explosion", "slashCut", "splash", "bubble", "rubble", "wind", "storm", "bolt", "spark" }

export type Style = {
	texture: string,
	rate: number,
	size: number,
	speed: number,
	lifetime: number,
	trailWidth: number,
	lightRange: number,
	burst: number,
	tint: Color3?,
	secondary: string?, -- extra emitter texture (e.g. smoke behind fire)
	hit: string?, -- how it looks on impact, one of VfxStyles.HITS (nil = plain burst)
	hitScale: number?, -- how big that impact is (default 1)
}

-- Buff aura on the caster for the buff's duration.
export type Aura = {
	texture: string,
	rate: number,
	size: number,
	speed: number,
	lifetime: number,
	lift: number, -- upward acceleration of the particles (studs/s^2)
	color: Color3,
	outline: Color3?, -- Highlight outline around the whole character
	fill: number?, -- Highlight fill transparency (1 = outline only)
	light: number?, -- PointLight range
	spin: boolean?, -- particles swirl around the caster instead of rising
}

-- Anything not listed uses `default` tinted with the spell's own color.
VfxStyles.STYLES = {
	default = {
		texture = TEX.sparkle,
		rate = 30,
		size = 0.6,
		speed = 2,
		lifetime = 0.4,
		trailWidth = 0.8,
		lightRange = 8,
		burst = 18,
	},
	Fireball = {
		texture = TEX.fire,
		rate = 60,
		size = 1.4,
		speed = 1,
		lifetime = 0.35,
		trailWidth = 1.4,
		lightRange = 12,
		burst = 30,
		tint = Color3.fromRGB(255, 140, 50),
		hit = "explosion",
		secondary = TEX.smoke,
	},
	WaterLock = {
		texture = TEX.sparkle,
		rate = 50,
		size = 0.7,
		speed = 1,
		lifetime = 0.6,
		trailWidth = 1,
		lightRange = 8,
		burst = 24,
		tint = Color3.fromRGB(90, 180, 255),
		hit = "bubble",
	},
	Gust = {
		texture = TEX.smoke,
		rate = 60,
		size = 3,
		speed = 4,
		lifetime = 0.45,
		trailWidth = 4,
		lightRange = 0,
		burst = 22,
		tint = Color3.fromRGB(235, 245, 255),
		hit = "wind",
	},
	FireSlash = {
		texture = TEX.fire,
		rate = 50,
		size = 1.0,
		speed = 1,
		lifetime = 0.25,
		trailWidth = 2.5,
		lightRange = 10,
		burst = 22,
		tint = Color3.fromRGB(255, 150, 50),
		hit = "slashCut",
	},
	FireBomb = {
		texture = TEX.fire,
		rate = 90,
		size = 3.2,
		speed = 2,
		lifetime = 0.5,
		trailWidth = 4,
		lightRange = 22,
		burst = 60,
		tint = Color3.fromRGB(255, 90, 30),
		hit = "explosion",
		hitScale = 2.3,
		secondary = TEX.smoke,
	},
	WaterSlice = {
		texture = TEX.sparkle,
		rate = 60,
		size = 0.8,
		speed = 1,
		lifetime = 0.35,
		trailWidth = 2.5,
		lightRange = 8,
		burst = 20,
		tint = Color3.fromRGB(80, 180, 255),
		hit = "splash",
	},
	WaterWave = {
		texture = TEX.sparkle,
		rate = 120,
		size = 1.6,
		speed = 3,
		lifetime = 0.6,
		trailWidth = 6,
		lightRange = 8,
		burst = 50,
		tint = Color3.fromRGB(80, 170, 255),
		hit = "splash",
		hitScale = 2.2,
	},
	RockThrow = {
		texture = TEX.smoke,
		rate = 40,
		size = 2.2,
		speed = 1,
		lifetime = 0.5,
		trailWidth = 2.5,
		lightRange = 0,
		burst = 28,
		tint = Color3.fromRGB(140, 110, 80),
		hit = "rubble",
	},
	Whirlwind = {
		texture = TEX.smoke,
		rate = 80,
		size = 5,
		speed = 6,
		lifetime = 0.6,
		trailWidth = 7,
		lightRange = 0,
		burst = 36,
		tint = Color3.fromRGB(235, 245, 255),
		hit = "wind",
		hitScale = 1.8,
	},
	Tornado = {
		texture = TEX.smoke,
		rate = 120,
		size = 6,
		speed = 8,
		lifetime = 0.8,
		trailWidth = 8,
		lightRange = 0,
		burst = 50,
		tint = Color3.fromRGB(205, 235, 230),
		hit = "storm",
		hitScale = 2.2,
	},
	Bullet = {
		texture = TEX.sparkle,
		rate = 40,
		size = 0.3,
		speed = 1,
		lifetime = 0.2,
		trailWidth = 0.35,
		lightRange = 5,
		burst = 10,
		tint = Color3.fromRGB(255, 213, 79),
		hit = "spark",
	},

	-- Zones, lines, walls, and buffs: these have no bolt, so the style colors
	-- their impact burst (and the pillar/rise/quake Fx lean on the element).
	FirePillar = {
		texture = TEX.fire,
		rate = 80,
		size = 2.6,
		speed = 3,
		lifetime = 0.6,
		trailWidth = 3,
		lightRange = 20,
		burst = 50,
		tint = Color3.fromRGB(255, 110, 40),
		secondary = TEX.smoke,
	},
	WaterNebula = {
		texture = TEX.sparkle,
		rate = 90,
		size = 2,
		speed = 4,
		lifetime = 0.7,
		trailWidth = 3,
		lightRange = 18,
		burst = 50,
		tint = Color3.fromRGB(90, 170, 255),
	},
	Earthquake = {
		texture = TEX.smoke,
		rate = 70,
		size = 4,
		speed = 5,
		lifetime = 0.8,
		trailWidth = 4,
		lightRange = 0,
		burst = 60,
		tint = Color3.fromRGB(150, 118, 86),
	},
	EarthPunch = {
		texture = TEX.smoke,
		rate = 60,
		size = 3,
		speed = 4,
		lifetime = 0.6,
		trailWidth = 3,
		lightRange = 0,
		burst = 40,
		tint = Color3.fromRGB(150, 118, 86),
	},
	EarthPillar = {
		texture = TEX.smoke,
		rate = 50,
		size = 2.4,
		speed = 3,
		lifetime = 0.5,
		trailWidth = 2.5,
		lightRange = 0,
		burst = 28,
		tint = Color3.fromRGB(150, 118, 86),
	},
	EarthWall = {
		texture = TEX.smoke,
		rate = 40,
		size = 2.2,
		speed = 3,
		lifetime = 0.5,
		trailWidth = 2,
		lightRange = 0,
		burst = 24,
		tint = Color3.fromRGB(140, 112, 84),
	},
	FireBoost = {
		texture = TEX.fire,
		rate = 40,
		size = 1.6,
		speed = 3,
		lifetime = 0.5,
		trailWidth = 1.5,
		lightRange = 14,
		burst = 36,
		tint = Color3.fromRGB(255, 130, 40),
	},
	WaterBody = {
		texture = TEX.sparkle,
		rate = 50,
		size = 1.2,
		speed = 3,
		lifetime = 0.6,
		trailWidth = 1.5,
		lightRange = 10,
		burst = 36,
		tint = Color3.fromRGB(90, 180, 255),
	},
	AirBoost = {
		texture = TEX.smoke,
		rate = 50,
		size = 1.8,
		speed = 5,
		lifetime = 0.5,
		trailWidth = 2,
		lightRange = 0,
		burst = 30,
		tint = Color3.fromRGB(215, 245, 235),
	},
	AirShield = {
		texture = TEX.sparkle,
		rate = 50,
		size = 1.1,
		speed = 3,
		lifetime = 0.6,
		trailWidth = 1.5,
		lightRange = 8,
		burst = 30,
		tint = Color3.fromRGB(200, 245, 240),
	},
	Zap = {
		texture = TEX.sparkle,
		rate = 90,
		size = 1.4,
		speed = 9,
		lifetime = 0.35,
		trailWidth = 2.5,
		lightRange = 26,
		burst = 60,
		tint = Color3.fromRGB(255, 240, 110),
		hit = "bolt",
		hitScale = 1.5,
	},
	Heal = {
		texture = TEX.sparkle,
		rate = 50,
		size = 1.2,
		speed = 3,
		lifetime = 0.8,
		trailWidth = 1.5,
		lightRange = 12,
		burst = 40,
		tint = Color3.fromRGB(120, 230, 130),
	},
	BlackHole = {
		texture = TEX.smoke,
		rate = 70,
		size = 3,
		speed = 6,
		lifetime = 0.7,
		trailWidth = 3,
		lightRange = 10,
		burst = 50,
		tint = Color3.fromRGB(120, 50, 200),
	},
	Turret = {
		texture = TEX.sparkle,
		rate = 40,
		size = 1,
		speed = 3,
		lifetime = 0.4,
		trailWidth = 1,
		lightRange = 8,
		burst = 24,
		tint = Color3.fromRGB(180, 200, 215),
	},
} :: { [string]: Style }

-- Buff auras, by the same style key.
VfxStyles.AURAS = {
	FireBoost = {
		texture = TEX.fire,
		rate = 38,
		size = 1.8,
		speed = 2,
		lifetime = 0.7,
		lift = 7,
		color = Color3.fromRGB(255, 130, 40),
		outline = Color3.fromRGB(255, 150, 60),
		fill = 0.85,
		light = 14,
	},
	WaterBody = {
		texture = TEX.sparkle,
		rate = 50,
		size = 1.1,
		speed = 3,
		lifetime = 0.9,
		lift = 2,
		color = Color3.fromRGB(100, 190, 255),
		outline = Color3.fromRGB(120, 210, 255),
		fill = 0.55,
		light = 10,
		spin = true,
	},
	AirBoost = {
		texture = TEX.smoke,
		rate = 55,
		size = 1.5,
		speed = 1,
		lifetime = 0.45,
		lift = 0,
		color = Color3.fromRGB(225, 250, 240),
		outline = Color3.fromRGB(190, 245, 225),
		fill = 1,
	},
	AirShield = {
		texture = TEX.sparkle,
		rate = 45,
		size = 1.2,
		speed = 4,
		lifetime = 0.8,
		lift = 0,
		color = Color3.fromRGB(210, 248, 244),
		outline = Color3.fromRGB(255, 255, 255),
		fill = 0.8,
		light = 8,
		spin = true,
	},
	Heal = {
		texture = TEX.sparkle,
		rate = 60,
		size = 1.3,
		speed = 2,
		lifetime = 0.9,
		lift = 6,
		color = Color3.fromRGB(130, 235, 140),
		outline = Color3.fromRGB(150, 255, 160),
		fill = 0.8,
		light = 12,
	},
} :: { [string]: Aura }

return VfxStyles
