--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (remote payloads, profile schema, spell data) live here so both sides agree.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

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
	trap: boolean?,
	bounce: number?,
	hazardDps: number?,
	-- Build as a grid of separately breakable blocks ({x = columns, y = rows});
	-- `health` is split evenly between them.
	segments: { x: number, y: number }?,
	-- Zone behaviors
	pull: number?,
	destroysStructures: boolean?,
	teamHeal: boolean?,
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
	aliases: { string },
	rarity: Rarity,
	unlockLevel: number,
	archetype: Archetype,
	cooldown: number,
	description: string,
	stats: SpellStats,
	visual: Visual,
	starter: boolean?,
}

export type MatchMode = "1v1" | "2v2" | "4v4" | "FFA"

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
	xp: number,
	level: number,
	ownedSpells: { string },
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
		typeKey: string, -- Enum.KeyCode name that focuses the "type a spell" box
	},
}

export type DailyQuest = {
	id: string,
	text: string,
	goal: number,
	progress: number,
	rewardXp: number,
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
	xpGained: number?, -- set in Results for this player
}

return nil
