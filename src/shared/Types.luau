--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (remote payloads, profile schema, spell data) live here so both sides agree.

-- The four elements. Every spell belongs to one; a player equips one at a time.
export type ElementId = "Fire" | "Water" | "Earth" | "Air"

-- A spell's school: one of the four elements, or "Arcane" for the neutral
-- spells that only come from chests (Lightning, Heal, Black Hole, Turret).
export type SchoolId = ElementId | "Arcane"

export type RarityId = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type Archetype =
	"Projectile"
	| "Control"
	| "Placeable"
	| "Zone"
	| "Buff"
	| "Movement"
	| "Summon"
	| "Line"

-- Status effects the server can apply to a character. Stun is Water Lock's:
-- no moving and no casting. Haste, Invincible, and Channel are buffs.
export type StatusKind = "Root" | "Slow" | "Shrink" | "TimeStop" | "Slippery" | "Stun"

-- Procedural look of a spell's projectile / placed object / summon body.
-- Everything is built from primitives so the game needs no uploaded assets.
export type Visual = {
	shape: "Block" | "Ball" | "Cylinder" | "Wedge",
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	neon: boolean?,
	-- Name of an imported model in ReplicatedStorage.Models (see ModelKit)
	-- that replaces the primitive look: the bolt for projectiles, the body
	-- for placeables (Turret), the swirl for zones (Black Hole), the strike
	-- for Zap, the pop-up for buffs (Heal). The primitive above is always
	-- the fallback and the hitbox.
	model: string?,
}

-- Archetype-specific tuning. Every field is optional; each archetype
-- documents which ones it reads (see docs/SPELLS.md).
export type SpellStats = {
	damage: number?,
	speed: number?,
	range: number?,
	radius: number?,
	knockback: number?,
	duration: number?,
	health: number?,
	heal: number?,
	status: StatusKind?,
	statusDuration: number?,
	strength: number?,
	chain: number?,
	delay: number?,
	lifetime: number?,
	maxActive: number?,
	-- Placeable behaviors
	turret: boolean?,
	fireInterval: number?, -- turret: seconds between shots (default 1.5)
	trap: boolean?,
	bounce: number?,
	hazardDps: number?,
	-- Build as a grid of separately breakable blocks ({x = columns, y = rows});
	-- `health` is split evenly between them.
	segments: { x: number, y: number }?,
	-- Name of an imported model in ReplicatedStorage.Models (see ModelKit).
	-- Placeables (Rock Wall) build from it when present, each mesh part its
	-- own breakable chunk, with `segments` as the fallback; Water Lock uses
	-- it for the bubble around its victim.
	model: string?,
	-- Placeables only: every spell hits it, the owner's and allies' too (walls).
	hitByAll: boolean?,
	-- Zone behaviors
	pull: number?,
	destroysStructures: boolean?,
	teamHeal: boolean?,
	-- Black Hole: enemies pulled into the core are Rooted at the center
	-- until the zone ends.
	hold: boolean?,
	-- Show the hit circle (radius) on the ground at the aim point while
	-- this spell is being traced, clamped to `range` (Zap).
	reticle: boolean?,
	-- Projectiles: pass through players (each is hit once) instead of stopping
	-- on the first one (Water Wave, Tornado).
	pierce: boolean?,
	-- Zone bursts: a boulder rises out of the ground at the target (Earth
	-- Punch); `pillar` draws a column of the spell's element erupting there
	-- (Fire Pillar, Water Nebula, Earthquake).
	rise: boolean?,
	pillar: boolean?,
	-- Zone bursts: the caster is locked in place for `delay` (Earthquake's
	-- long cast time).
	channel: boolean?,
	-- Line (Earth Pillar): `count` bursts spaced `spacing` studs apart, each
	-- `step` seconds after the last, along the way the caster aims.
	count: number?,
	spacing: number?,
	step: number?,
	-- Buff behaviors
	damageMult: number?, -- Fire Boost: the caster's damage is multiplied for `duration`
	invincible: boolean?, -- Water Body: no damage or effects for `duration`
	barrier: boolean?, -- Air Shield: blocks the next hit (spell or damage) for `duration`
	haste: boolean?, -- Air Boost: faster and higher jumps for `duration`
	shield: number?,
	reflect: boolean?,
	scale: number?,
	revive: boolean?,
	cooldownCut: number?,
	-- Movement behaviors
	dashSpeed: number?,
	teleport: boolean?,
	lift: number?,
	-- Summon behaviors
	melee: boolean?,
	flier: boolean?,
	decoy: boolean?,
	-- Combo: bonus multiplier when the target already has this status
	comboStatus: StatusKind?,
	comboMultiplier: number?,
}

export type SpellDef = {
	id: string,
	name: string,
	aliases: { string }, -- admin names (`;cast me fire`); players draw `glyph` instead
	glyph: string, -- id in Spells/Glyphs: the shape drawn to ready this spell
	-- Names in Audio/Cues: `cast` plays when it's cast, `impact` where it lands.
	sfx: { cast: string?, impact: string? }?,
	element: SchoolId,
	slot: number, -- display order in its school: 1-3 are an element's base spells, 4 a chest spell, 5 an ultimate
	-- Set on chest spells only (everything that is not one of an element's
	-- three base spells): how rare it is in the Chest Shop.
	rarity: RarityId?,
	role: string, -- the kind of move (Glyphs.ROLE): decides its glyph
	ultimate: boolean?, -- slot 5: the element's big, slow spell
	archetype: Archetype,
	cooldown: number,
	description: string,
	stats: SpellStats,
	visual: Visual,
}

export type MatchMode = "1v1" | "2v2" | "3v3" | "4v4"

export type MatchPhase = "Idle" | "Intro" | "Countdown" | "Round" | "Draft" | "Results"

export type RosterEntry = { userId: number, name: string, team: string }

-- A round-draft card: one match boost (shared/Match/Boosts).
export type DraftCard = {
	boostId: string,
}

-- Persisted per-player data. Bump `schema` and add a migration in
-- PlayerDataService when changing this shape.
export type Profile = {
	schema: number,
	coins: number, -- spent on chests (ChestService); earned by winning matches
	elements: { string }, -- elements owned (the first is picked free, the rest are bought with coins)
	element: string, -- the equipped element ("" until the first pick)
	spells: { string }, -- chest spells owned (ids of spells with a rarity)
	loadout: { string }, -- up to Loadout.MAX_EXTRA owned chest spells equipped beside the element's base spells
	tutorial: { done: boolean }, -- the first-join walkthrough was finished or skipped
	cosmetics: { string },
	stats: {
		matches: number,
		wins: number,
		knockouts: number,
		casts: number,
	},
	daily: {
		lastLoginDay: number,
		streak: number,
		lastFirstWinDay: number,
		questDay: number,
		quests: { DailyQuest },
	},
	settings: {
		drawKey: string, -- Enum.KeyCode name that starts drawing a spell
		music: boolean, -- background music on or off
		sfx: boolean, -- sound effects on or off
		shake: boolean, -- camera shake and field-of-view kicks on or off
	},
	rewards: {
		likeFav: boolean, -- the one-time Like & Favourite coin gift was claimed
	},
	pity: number, -- chests opened since the last Epic or better (ChestService; see Economy/Chests PITY)
}

export type DailyQuest = {
	id: string,
	text: string,
	goal: number,
	progress: number,
	rewardCoins: number,
	claimed: boolean,
}

-- Snapshot the server sends to each client describing their match state.
export type MatchState = {
	phase: MatchPhase,
	mode: MatchMode?,
	mapName: string?,
	round: number,
	endsAt: number,
	scores: { [string]: number },
	myTeam: string?, -- display name (matches `scores` keys)
	myTeamId: string?, -- matches characters' "Team" attribute
	-- For the intro/VS screen and banners:
	roster: { RosterEntry }?, -- team = display name
	roundWinner: string?, -- display name of the last round's winner
	winner: string?, -- set in Results: display name of the match winner
	won: boolean?, -- set in Results for this player
	coinsGained: number?, -- set in Results for this player
}

-- A chest in the Chest Shop (shared/Economy/Chests): opening one wins a chest
-- spell of `minRarity` or better, picked by rarity weight.
export type ChestDef = {
	id: RarityId, -- a chest is named after the least rarity it can drop
	name: string,
	price: number,
	minRarity: RarityId,
	-- Never a duplicate while a spell this chest can drop is still unowned.
	noDuplicates: boolean?,
}

-- What the server tells the opener after opening a chest (ChestOpened remote).
export type ChestResult = {
	chest: string,
	spell: string, -- the spell id the spin landed on
	rarity: RarityId,
	duplicate: boolean, -- already owned: paid back as `refund` coins instead
	refund: number,
	equipped: boolean, -- the spell went straight into an empty loadout slot
	pity: number, -- the pity counter after this spin
	coins: number, -- balance after the spin (the refund is added when the reel stops)
}

-- One row of the server's wins leaderboard (LeaderboardService).
export type LeaderRow = { userId: number, name: string, wins: number }

return nil
