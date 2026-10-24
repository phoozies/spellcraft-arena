--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (remote payloads, profile schema, spell data) live here so both sides agree.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type Archetype =
	"Projectile"
	| "Control"
	| "Placeable"
	| "Zone"
	| "Buff"
	| "Movement"
	| "Summon"

-- Status effects the server can apply to a character.
export type StatusKind = "Root" | "Slow" | "Shrink" | "TimeStop" | "Slippery"

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
	-- this spell is readied, clamped to `range` (Zap).
	reticle: boolean?,
	-- Buff behaviors
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
	aliases: { string }, -- admin names (`;give fire`); players draw `glyph` instead
	glyph: string, -- id in Spells/Glyphs: the shape drawn to ready this spell
	rarity: Rarity,
	archetype: Archetype,
	cooldown: number,
	description: string,
	stats: SpellStats,
	visual: Visual,
	starter: boolean?,
}

export type MatchMode = "1v1" | "2v2" | "3v3" | "4v4" | "FFA"

export type MatchPhase = "Idle" | "Intro" | "Countdown" | "Round" | "Draft" | "Results"

export type RosterEntry = { userId: number, name: string, team: string }

export type DraftCard = {
	spellId: string,
	rarity: Rarity,
}

-- Persisted per-player data. Bump `schema` and add a migration in
-- PlayerDataService when changing this shape.
export type Profile = {
	schema: number,
	coins: number, -- spent on crates (CrateService); earned by winning matches
	ownedSpells: { string }, -- starters + spells unlocked from crates
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
	},
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


-- One crate tier in the shop (shared/Economy/Crates).
export type CrateDef = {
	id: Rarity, -- crates are named after their main rarity
	price: number,
	-- rarity -> weight; the spin lands on a spell of the rolled rarity.
	odds: { [Rarity]: number },
}

-- What the server tells the opener after a crate spin (CrateOpened remote).
export type CrateResult = {
	crate: Rarity,
	spellId: string,
	rarity: Rarity,
	duplicate: boolean, -- already owned: refunded instead
	refund: number,
	coins: number, -- balance after the spin
}

-- One row of the server's wins leaderboard (LeaderboardService).
export type LeaderRow = { userId: number, name: string, wins: number }

return nil
