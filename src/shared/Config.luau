--!strict
-- Tunable gameplay values. NOTE: replicated to clients — nothing secret here,
-- and the server never trusts a client-reported value from this file.

local Config = {
	STARTING_HAND = 3,
	MAX_HAND = 5,

	-- Seconds. Spells cannot be cast faster than this regardless of cooldowns.
	GLOBAL_CAST_LOCKOUT = 0.35,
	-- Seconds between typed/spoken words (chat + box + voice combined). Each
	-- word adds one copy of a spell (up to MAX_HAND held, duplicates allowed).
	TYPE_COOLDOWN = 1,

	-- Movement & aiming. Players move faster than Roblox's default (16) to
	-- keep fights lively; projectiles are sped up by the same ratio and get
	-- a bigger hitbox so they still land.
	WALK_SPEED = 24,
	JUMP_POWER = 55,
	PROJECTILE_SPEED_SCALE = 1.5,
	-- Studs added to every projectile's hit radius (spherecast) and to
	-- area-of-effect checks against players.
	HITBOX_BONUS = 1.5,

	-- Health regenerates only in the hub. In arenas the only healing is spells.
	HUB_REGEN_PER_SECOND = 5,

	-- Seconds the hub's team boxes wait once both sides are full, so someone
	-- can still step off before the match starts.
	TEAM_BOX_COUNTDOWN = 5,

	-- Seconds of the "VS" intro before players are moved into the arena.
	INTRO_TIME = 4,

	-- Settings: the default key that focuses the "type a spell" box, and keys
	-- that can't be bound to it (movement, chat, hotbar, menus).
	DEFAULT_TYPE_KEY = "T",
	RESERVED_KEYS = {
		"W",
		"A",
		"S",
		"D",
		"Space",
		"Escape",
		"Slash",
		"Backquote",
		"Tab",
		"Return",
		"One",
		"Two",
		"Three",
		"Four",
		"Five",
		"R",
		"LeftShift",
		"RightShift",
		"Up",
		"Down",
		"Left",
		"Right",
	} :: { string },
	-- After a hard crowd-control effect (Root, TimeStop, Shrink) ends, the
	-- target can't be hit by that kind again for this long. Stops CC chains
	-- now that spells can be re-typed every second.
	CC_IMMUNITY = 2.5,

	PLAYER_MAX_HEALTH = 100,
	SPAWN_PROTECTION = 3,
	-- Characters below this Y inside an arena are knocked out (ring-outs).
	ARENA_VOID_DEPTH = -60,

	COUNTDOWN_TIME = 5,
	ROUND_TIME = 120,
	DRAFT_TIME = 15,
	RESULTS_TIME = 8,
	ROUNDS_TO_WIN = 2, -- best of 3

	MAX_PLACED_PER_PLAYER = 6,
	PLACE_RANGE = 40,
	AIM_RANGE = 200,

	-- Players needed for each mode, as {teamCount, playersPerTeam}.
	-- FFA is 2..8 players, each on their own "team".
	MODES = {
		["1v1"] = { teams = 2, perTeam = 1 },
		["2v2"] = { teams = 2, perTeam = 2 },
		["3v3"] = { teams = 2, perTeam = 3 },
		["4v4"] = { teams = 2, perTeam = 4 },
		["FFA"] = { teams = 0, perTeam = 1, minPlayers = 2, maxPlayers = 8 },
	},
	-- FFA waits this long after reaching the minimum before starting.
	FFA_FILL_WAIT = 15,

	-- Distance between instanced arenas so concurrent matches never overlap.
	ARENA_SPACING = 2000,

	AUTOSAVE_INTERVAL = 90,

	-- Coins: earned by winning matches (plus daily login and quests), spent
	-- on crates (shared/Economy/Crates). There are no levels or XP.
	COINS = {
		STARTING = 150, -- a new player can open a Common crate right away
		MATCH_WIN = 100,
		FIRST_WIN_OF_DAY = 50,
		DAILY_LOGIN = 25, -- x streak day, capped at 7
	},

	-- Hub wins podium + board (LeaderboardService): seconds between refreshes
	-- and how many rows the board lists.
	LEADERBOARD_REFRESH = 10,
	LEADERBOARD_ROWS = 10,

	-- Shown when a word doesn't match any spell.
	FIZZLE_HINTS = {
		"Fizzle! Try a spell from your hand.",
		"The magic didn't understand that word.",
		"Hmm... try 'fireball' or 'rock wall'!",
	},

	-- Set true only in Studio test sessions; enables gated debug remotes.
	DEBUG_COMMANDS_IN_STUDIO = true,

	-- Admin commands (see docs/ADMIN.md). UserIds listed here, the place
	-- owner (or group owner, rank 255), and anyone testing in Studio are admins.
	ADMIN_PREFIX = ";",
	ADMIN_USER_IDS = { 118721190 } :: { number },
	ADMIN_GROUP_MIN_RANK = 255,
}

return table.freeze(Config)
