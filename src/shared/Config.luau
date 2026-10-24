--!strict
-- Tunable gameplay values. NOTE: replicated to clients — nothing secret here,
-- and the server never trusts a client-reported value from this file.

local Config = {
	MAX_LEVEL = 10,
	STARTING_HAND = 3,
	MAX_HAND = 5,

	-- Seconds. Spells cannot be cast faster than this regardless of cooldowns.
	GLOBAL_CAST_LOCKOUT = 0.35,
	-- Max words a player may submit per second (chat + box + voice combined).
	WORD_RATE_PER_SECOND = 4,

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
		["4v4"] = { teams = 2, perTeam = 4 },
		["FFA"] = { teams = 0, perTeam = 1, minPlayers = 2, maxPlayers = 8 },
	},
	-- FFA waits this long after reaching the minimum before starting.
	FFA_FILL_WAIT = 15,

	-- Distance between instanced arenas so concurrent matches never overlap.
	ARENA_SPACING = 2000,

	AUTOSAVE_INTERVAL = 90,

	XP = {
		PARTICIPATION = 40,
		ROUND_WIN = 20,
		MATCH_WIN = 40,
		KNOCKOUT = 10,
		FIRST_WIN_OF_DAY = 100,
		DAILY_LOGIN = 25,
	},

	-- Shown when a word doesn't match any spell.
	FIZZLE_HINTS = {
		"Fizzle! Try a spell from your hand.",
		"The magic didn't understand that word.",
		"Hmm... try 'fireball' or 'rock wall'!",
	},

	-- Set true only in Studio test sessions; enables gated debug remotes.
	DEBUG_COMMANDS_IN_STUDIO = true,
}

return table.freeze(Config)
