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
--   loop     true = a looping cue that AudioController.loop plays (not AudioController.play)
--   with     other cues played together with this one (a splash plus a thud);
--            those cues may not layer further
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
	with: { string }?,
}

local function sound(
	id: number,
	volume: number,
	world: boolean,
	pitch: number?,
	length: number?
): Cue
	return {
		id = `rbxassetid://{id}`,
		volume = volume,
		world = world,
		pitch = pitch,
		length = length,
	}
end

-- The same cue with other cues layered under it.
local function layered(cue: Cue, ...: string): Cue
	local copy = table.clone(cue)
	copy.with = { ... }
	return copy
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
	fireballHit = layered(sound(EXPLOSION, 0.7, true, 1, 1.6), "emberCrackle"),
	emberCrackle = sound(WHOOSH_FIRE, 0.35, true, 2, 0.6),
	slashHit = layered(sound(HIT, 0.6, true, 1.8, 0.3), "emberCrackle"),
	orbCharge = sound(WHOOSH_FIRE, 0.3, true, 0.7, 0.5),
	slashCast = sound(WHOOSH_FIRE, 0.5, true, 1.5, 0.7),
	boostCast = sound(CHIME, 0.6, true, 0.7, 1.8),
	pillarCast = sound(RUMBLE, 0.6, true, 1.1, 1),
	pillarBoom = sound(EXPLOSION, 0.9, true, 0.8, 2.2),
	bombCast = sound(WHOOSH_FIRE, 0.8, true, 0.6, 1.4),
	bombBoom = layered(sound(EXPLOSION, 1, true, 0.6, 2.8), "emberCrackle", "thump"),

	-- Water
	sliceCast = sound(SPLASH, 0.45, true, 1.6, 0.6),
	bodyCast = sound(BUBBLE, 0.6, true, 0.8, 1.8),
	waterCast = sound(SPLASH, 0.5, true, 1.15, 1),
	waterTrap = sound(BUBBLE, 0.6, true, 1, 1.5),
	sliceHit = layered(sound(SPLASH, 0.55, true, 1.7, 0.5), "dripSplash"),
	dripSplash = sound(SPLASH, 0.3, true, 2, 0.3),
	lockPop = layered(sound(BUBBLE, 0.6, true, 1.6, 0.6), "dripSplash"),
	waveCrash = layered(sound(SPLASH, 0.9, true, 0.75, 1.6), "waveRumble"),
	waveRumble = sound(RUMBLE, 0.4, true, 1.4, 0.8),
	waveCast = sound(BUBBLE, 0.8, true, 0.7, 2),
	nebulaCast = sound(RUMBLE, 0.6, true, 1.2, 1.2),
	nebulaBoom = sound(BUBBLE, 1, true, 0.6, 2.6),

	-- Earth
	throwCast = sound(GRIND, 0.55, true, 1.6, 0.9),
	rockRaise = sound(GRIND, 0.7, true, 1, 2),
	wallHit = sound(RUBBLE, 0.5, true, 1.4, 0.6),
	rockBreak = sound(RUBBLE, 0.6, true, 1.1, 1.6),
	rockSmash = layered(sound(RUBBLE, 0.7, true, 1.25, 0.9), "thump"),
	thump = sound(HIT, 0.5, true, 0.7, 0.35),
	stompThud = layered(sound(RUBBLE, 0.6, true, 0.6, 0.5), "thump"),
	punchCast = sound(GRIND, 0.75, true, 0.8, 1.4),
	quakeRumble = sound(GRIND, 0.9, true, 0.55, 3.2),
	quakeBoom = sound(RUBBLE, 1, true, 0.55, 3),

	-- Air
	pushWhoosh = sound(WIND, 0.5, true, 1.7, 0.4),
	spinWhoosh = sound(WIND, 0.55, true, 1.2, 0.7),
	gustCast = sound(WIND, 0.7, true),
	gustHit = sound(WIND, 0.6, true, 1.6, 0.5),
	whirlCast = sound(WIND, 0.8, true, 0.8, 1.8),
	whirlHit = sound(WIND, 0.8, true, 0.6, 1.2),
	airBoostCast = sound(WIND, 0.6, true, 1.4, 0.9),
	shieldCast = sound(CHIME, 0.55, true, 0.9, 1.4),
	tornadoCast = sound(RUMBLE, 0.9, true, 1, 2.6),
	tornadoHit = sound(RUMBLE, 0.8, true, 1.3, 1.2),

	-- Arcane (chest spells that belong to no element)
	zapCharge = sound(TWINKLE, 0.7, true, 2, 0.6),
	zapStrike = layered(sound(EXPLOSION, 0.8, true, 1.9, 0.9), "zapCrackle"),
	zapCrackle = sound(TWINKLE, 0.5, true, 2, 0.5),
	healChime = sound(CHIME, 0.7, true, 1.6, 1.6),
	blackHoleOpen = sound(RUMBLE, 0.8, true, 0.5, 2.5),
	-- The hum while the hole is open: AudioController.loop repeats it for the
	-- hole's whole life, so `loop` keeps AudioController.play from using it.
	blackHoleHum = {
		id = `rbxassetid://{RUMBLE}`,
		volume = 0.5,
		pitch = 0.5,
		world = true,
		loop = true,
	},
	voidPull = sound(WIND, 0.5, true, 0.5, 1),
	blackHoleCollapse = layered(sound(EXPLOSION, 0.9, true, 0.45, 2.2), "waveRumble", "thump"),
	turretDeploy = sound(GRIND, 0.6, true, 1.9, 0.9),
	turretOnline = sound(TWINKLE, 0.6, true, 1.6, 0.8),
	buildClank = sound(HIT, 0.5, true, 1.1, 0.3),
	turretShot = layered(sound(HIT, 0.4, true, 2, 0.3), "shotCrack"),
	shotCrack = sound(EXPLOSION, 0.22, true, 2, 0.22),
	bulletHit = layered(sound(HIT, 0.35, true, 1.6, 0.2), "zapCrackle"),

	-- Movement
	dash = sound(WIND, 0.6, true, 1.9, 0.5),
	dashLand = sound(RUBBLE, 0.3, true, 1.7, 0.25),

	-- Fights
	hit = sound(HIT, 0.45, true, 1.3, 0.4),
	-- Game feel (heard in your ears; client Fx/Juice)
	hitMarker = sound(HIT, 0.4, false, 2, 0.12),
	heavyHit = layered(sound(HIT, 0.65, false, 1, 0.3), "thump"),
	hurt = layered(sound(HIT, 0.5, false, 0.8, 0.3), "thump"),
	knockoutSting = layered(sound(CHIME, 0.8, false, 0.9, 1.5), "thump"),
	-- The arena's water catching a fallen player (heard from where it splashes).
	waterSplash = layered(sound(SPLASH, 0.8, true, 0.9, 1.2), "dripSplash"),

	-- Drawing and chests (heard in your ears)
	glyphGood = sound(TWINKLE, 0.6, false, 1, 1),
	glyphBad = sound(TWINKLE, 0.5, false, 0.55, 0.9),
	-- The wand (heard by everyone nearby): its tip lights up as a drawing starts,
	-- and a finished glyph is pulled into it.
	wandCharge = sound(TWINKLE, 0.35, true, 1.4, 0.5),
	wandAbsorb = sound(CHIME, 0.5, true, 1.8, 0.9),
	chestReveal = sound(CHIME, 0.7, false, 1.3, 2.5),
	claimReward = sound(CHIME, 0.8, false, 1.5, 2),
	reelTick = sound(HIT, 0.25, false, 2, 0.15),
	chestEpic = sound(CHIME, 0.85, false, 1, 3),
	chestLegendary = sound(CHIME, 1, false, 0.75, 3.5),
	-- The low buzz for a spell that can't be drawn or cast (replaces text popups).
	uiError = sound(HIT, 0.5, false, 0.5, 0.3),
	uiStep = sound(TWINKLE, 0.5, false, 1.4, 0.8),
	uiEquip = sound(HIT, 0.45, false, 1.6, 0.3),
}

return table.freeze(Cues)
