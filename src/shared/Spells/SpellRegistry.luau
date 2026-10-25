--!strict
-- The spell registry: for every spell, which 3D model, particle style, cast
-- animation, and sounds give it its look and feel. SpellDefinitions holds the
-- numbers (damage, cooldown, ...); this holds the presentation, in one table
-- so a person or an AI can see at a glance what each spell has and what is
-- missing. Mirrored for reading in docs/semantic/spell_registry.yaml and
-- docs/SPELLS.md; tests/Registry.spec checks that every spell is listed and
-- that everything it names exists (model, style, pose, cues).
--
--   model      the 3D model (Models/BlockModels, or an imported mesh in the
--              place) taken from the definition's `visual.model` / `stats.model`
--   vfx        the particle style in Spells/VfxStyles (bolt trail, impact burst,
--              buff aura)
--   fx         the Fx events the spell triggers on clients (see FxController)
--   animation  the cast pose in Spells/CastPoses (arm/body animation)
--   sfx        cast and impact cues from the definition (Audio/Cues); a buff
--              has no impact (nothing hits)
--
-- Adding a spell: add its definition, then one entry here, then run the tests.

local SpellDefinitions = require(script.Parent.SpellDefinitions)

local SpellRegistry = {}

export type Entry = {
	vfx: string,
	fx: { string },
	animation: string,
	-- True when the spell is a buff/self effect with no impact sound by design.
	noImpact: boolean?,
	note: string,
}

export type Row = {
	id: string,
	name: string,
	element: string,
	slot: number,
	role: string,
	archetype: string,
	model: string?,
	vfx: string,
	fx: { string },
	animation: string,
	sfxCast: string?,
	sfxImpact: string?,
	note: string,
}

local ENTRIES: { [string]: Entry } = {
	-- Fire
	Fireball = {
		vfx = "Fireball",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Throw",
		note = "Flaming ball with a smoky trail; bursts on impact",
	},
	FireSlash = {
		vfx = "FireSlash",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Slash",
		note = "Block crescent blade with a fiery trail",
	},
	FireBoost = {
		vfx = "FireBoost",
		fx = { "modelPop", "cast", "aura" },
		animation = "Flex",
		noImpact = true,
		note = "Flame emblem over the head; embers and an orange outline while it lasts",
	},
	FirePillar = {
		vfx = "FirePillar",
		fx = { "pillar", "shockwave", "cast" },
		animation = "Sweep",
		note = "Red warning circle, then a layered fire column erupts",
	},
	FireBomb = {
		vfx = "FireBomb",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Ascend",
		note = "Huge fireball with heavy smoke and a big flash",
	},

	-- Water
	WaterSlice = {
		vfx = "WaterSlice",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Slash",
		note = "Block crescent of water with a sparkling trail",
	},
	WaterBody = {
		vfx = "WaterBody",
		fx = { "modelPop", "cast", "aura" },
		animation = "Flex",
		noImpact = true,
		note = "Water drop emblem over the head; a blue shimmer while you are untouchable",
	},
	WaterLock = {
		vfx = "WaterLock",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Point",
		note = "Bubble bolt; a bubble traps the victim (TrapBubble)",
	},
	WaterWave = {
		vfx = "WaterWave",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Smash",
		note = "Blocky breaking wave with foam, rolling through everything",
	},
	WaterNebula = {
		vfx = "WaterNebula",
		fx = { "pillar", "shockwave", "cast" },
		animation = "Ascend",
		note = "Warning circle, then a swirling water column with stars crashes down",
	},

	-- Earth
	RockThrow = {
		vfx = "RockThrow",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Throw",
		note = "Chunky boulder with a dust trail",
	},
	EarthWall = {
		vfx = "EarthWall",
		fx = { "dust", "chip", "shatter", "cast" },
		animation = "Guard",
		noImpact = true,
		note = "Wall rises with dust; chips fly when hit and it shatters piece by piece",
	},
	EarthPunch = {
		vfx = "EarthPunch",
		fx = { "rise", "dust", "shockwave", "cast" },
		animation = "Smash",
		note = "Warning circle, then a boulder cluster bursts out of the ground",
	},
	EarthPillar = {
		vfx = "EarthPillar",
		fx = { "rise", "dust", "shockwave", "cast" },
		animation = "Sweep",
		note = "A row of stone spikes erupts one after another",
	},
	Earthquake = {
		vfx = "Earthquake",
		fx = { "quake", "pillar", "dust", "shockwave", "cast" },
		animation = "Stomp",
		note = "Ground cracks and pulsing rings while the caster channels, then a huge burst",
	},

	-- Air
	Gust = {
		vfx = "Gust",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Throw",
		note = "Swirling puff with wind streaks",
	},
	Whirlwind = {
		vfx = "Whirlwind",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Smash",
		note = "Wide swirl of wind that blows everyone away",
	},
	AirBoost = {
		vfx = "AirBoost",
		fx = { "modelPop", "cast", "aura" },
		animation = "Flex",
		noImpact = true,
		note = "Winged emblem over the head; wind streaks trail you while you are fast",
	},
	AirShield = {
		vfx = "AirShield",
		fx = { "modelPop", "cast", "aura" },
		animation = "Guard",
		noImpact = true,
		note = "Kite shield emblem over the head; a swirling white outline until it blocks",
	},
	Tornado = {
		vfx = "Tornado",
		fx = { "projectile", "projectileEnd", "cast" },
		animation = "Ascend",
		note = "Stacked, turning slabs with flying debris tearing forward",
	},

	-- Arcane (crate spells; models are imported meshes with plain-shape fallbacks)
	Zap = {
		vfx = "Zap",
		fx = { "strike", "shockwave", "cast" },
		animation = "Call",
		note = "Yellow flash on the ground, then a thunderbolt slams down with a bright burst",
	},
	Heal = {
		vfx = "Heal",
		fx = { "modelPop", "cast", "aura" },
		animation = "Offer",
		noImpact = true,
		note = "Green cross and ring rise over the head; healing sparkles and green numbers",
	},
	BlackHole = {
		vfx = "BlackHole",
		fx = { "spin", "shockwave", "cast" },
		animation = "Conjure",
		note = "Purple warning circle, then a spinning black hole drags enemies in and holds them",
	},
	Turret = {
		vfx = "Turret",
		fx = { "projectile", "dust", "cast" },
		animation = "Deploy",
		noImpact = true,
		note = "A metal turret rises from the ground, turns to its target and fires yellow bullets",
	},
}

SpellRegistry.entries = ENTRIES

function SpellRegistry.entry(spellId: string): Entry?
	return ENTRIES[spellId]
end

-- The cast pose of a spell (a key of Spells/CastPoses), if it has one.
function SpellRegistry.animationFor(spellId: string): string?
	local entry = ENTRIES[spellId]
	return entry and entry.animation
end

-- The particle style key of a spell (a key of Spells/VfxStyles).
function SpellRegistry.vfxFor(spellId: string): string?
	local entry = ENTRIES[spellId]
	return entry and entry.vfx
end

-- The 3D model name of a spell, from its definition.
function SpellRegistry.modelFor(spellId: string): string?
	local def = SpellDefinitions.get(spellId)
	return def and (def.visual.model or def.stats.model)
end

-- One merged row per spell (definition + registry), in element and slot order.
function SpellRegistry.rows(): { Row }
	local rows: { Row } = {}
	for _, def in SpellDefinitions.list do
		local entry = ENTRIES[def.id]
		if entry then
			table.insert(rows, {
				id = def.id,
				name = def.name,
				element = def.element,
				slot = def.slot,
				role = def.role,
				archetype = def.archetype,
				model = def.visual.model or def.stats.model,
				vfx = entry.vfx,
				fx = entry.fx,
				animation = entry.animation,
				sfxCast = def.sfx and def.sfx.cast,
				sfxImpact = def.sfx and def.sfx.impact,
				note = entry.note,
			})
		end
	end
	return rows
end

return SpellRegistry
