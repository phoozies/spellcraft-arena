--!strict
-- Every sound the game plays, by name. Spells point at their cues from
-- SpellDefinitions (`sfx = { cast = "...", impact = "..." }`); the client's
-- AudioController plays them. To swap a sound, change its `id` here: nothing
-- else needs touching. An empty id means "silent" and is skipped.
--
--   volume   0..1 before distance falloff
--   pitch    playback speed (1 = as recorded; lower sounds bigger/sadder)
--   length   play only the first N seconds (long recordings, short moments)
--   world    true = heard from a place in the world, false = plays in your ears
--   loop     true = ambience that AudioController starts/stops itself
--
-- Most ids are from Roblox's free Pro Sound Effects library and the Creator
-- Store; tests/Audio.spec checks every cue's shape (not that it sounds good,
-- which only ears can).

export type Cue = {
	id: string,
	volume: number,
	pitch: number?,
	length: number?,
	world: boolean,
	loop: boolean?,
}

local function sound(id: number, volume: number, world: boolean, pitch: number?, length: number?): Cue
	return { id = `rbxassetid://{id}`, volume = volume, world = world, pitch = pitch, length = length }
end

-- Ids reused across spells with different pitch/length so a handful of
-- recordings cover every element: fire (whoosh + explosion), water (splash +
-- bubble), earth (grinding + rubble), air (whoosh), and chimes.
local WHOOSH_FIRE = 7106659874
local EXPLOSION = 93530870983093
local SPLASH = 9120587396
local BUBBLE = 9120585252
local GRIND = 9118666800
local RUBBLE = 9118586430
local WIND = 9120721247
local RUMBLE = 9126232116
local CHIME = 124113820339492
local TWINKLE = 135385970610304
local HIT = 9113513576

local Cues: { [string]: Cue } = {
	-- Fire (heard in the world)
	fireballCast = sound(WHOOSH_FIRE, 0.6, true),
	fireballHit = sound(EXPLOSION, 0.7, true, 1, 1.6),
	slashCast = sound(WHOOSH_FIRE, 0.5, true, 1.5, 0.7),
	boostCast = sound(CHIME, 0.6, true, 0.7, 1.8),
	pillarCast = sound(RUMBLE, 0.6, true, 1.1, 1),
	pillarBoom = sound(EXPLOSION, 0.9, true, 0.8, 2.2),
	bombCast = sound(WHOOSH_FIRE, 0.8, true, 0.6, 1.4),
	bombBoom = sound(EXPLOSION, 1, true, 0.6, 2.8),

	-- Water
	sliceCast = sound(SPLASH, 0.45, true, 1.6, 0.6),
	bodyCast = sound(BUBBLE, 0.6, true, 0.8, 1.8),
	waterCast = sound(SPLASH, 0.5, true, 1.15, 1),
	waterTrap = sound(BUBBLE, 0.6, true, 1, 1.5),
	waveCast = sound(BUBBLE, 0.8, true, 0.7, 2),
	nebulaCast = sound(RUMBLE, 0.6, true, 1.2, 1.2),
	nebulaBoom = sound(BUBBLE, 1, true, 0.6, 2.6),

	-- Earth
	throwCast = sound(GRIND, 0.55, true, 1.6, 0.9),
	rockRaise = sound(GRIND, 0.7, true, 1, 2),
	rockBreak = sound(RUBBLE, 0.6, true, 1.1, 1.6),
	punchCast = sound(GRIND, 0.75, true, 0.8, 1.4),
	quakeRumble = sound(GRIND, 0.9, true, 0.55, 3.2),
	quakeBoom = sound(RUBBLE, 1, true, 0.55, 3),

	-- Air
	gustCast = sound(WIND, 0.7, true),
	whirlCast = sound(WIND, 0.8, true, 0.8, 1.8),
	airBoostCast = sound(WIND, 0.6, true, 1.4, 0.9),
	shieldCast = sound(CHIME, 0.55, true, 0.9, 1.4),
	tornadoCast = sound(RUMBLE, 0.9, true, 1, 2.6),

	-- Fights
	hit = sound(HIT, 0.45, true, 1.3, 0.4),

	-- Drawing and crates (heard in your ears)
	glyphGood = sound(TWINKLE, 0.6, false, 1, 1),
	glyphBad = sound(TWINKLE, 0.5, false, 0.55, 0.9),
	crateReveal = sound(CHIME, 0.7, false, 1.3, 2.5),

	-- Hub ambience (a distant arena crowd, kept quiet)
	hubCrowd = { id = "rbxassetid://9119562311", volume = 0.22, world = false, loop = true },
}

return table.freeze(Cues)
