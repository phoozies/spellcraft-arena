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

local Cues: { [string]: Cue } = {
	-- Spells (heard in the world)
	fireballCast = sound(7106659874, 0.6, true),
	fireballHit = sound(93530870983093, 0.7, true, 1, 1.6),
	waterCast = sound(9120587396, 0.5, true, 1.15, 1),
	waterTrap = sound(9120585252, 0.6, true, 1, 1.5),
	rockRaise = sound(9118666800, 0.7, true, 1, 2),
	rockBreak = sound(9118586430, 0.6, true, 1.1, 1.6),
	gustCast = sound(9120721247, 0.7, true),
	zapCharge = sound(111136222998842, 0.6, true),
	zapStrike = sound(9126068434, 0.9, true, 1, 2),
	healChime = sound(124113820339492, 0.6, true, 1.1, 2),
	blackHoleOpen = sound(9126232116, 0.8, true, 0.8, 3),
	turretDeploy = sound(9114544104, 0.5, true, 1.2, 1.2),
	turretShot = sound(126902544332139, 0.35, true, 1.3, 0.6),
	hit = sound(9113513576, 0.45, true, 1.3, 0.4),

	-- Drawing and crates (heard in your ears)
	glyphGood = sound(135385970610304, 0.6, false, 1, 1),
	glyphBad = sound(135385970610304, 0.5, false, 0.55, 0.9),
	crateReveal = sound(124113820339492, 0.7, false, 1.3, 2.5),

	-- Hub ambience (a quiet loop of crickets and night air)
	hubNight = { id = "rbxassetid://9112764546", volume = 0.35, world = false, loop = true },
}

return table.freeze(Cues)
