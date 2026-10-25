--!strict
-- Tunable gameplay values. NOTE: replicated to clients — nothing secret here,
-- and the server never trusts a client-reported value from this file.

local Config = {
	MAX_HAND = 5,

	-- Seconds. Spells cannot be cast faster than this regardless of cooldowns.
	GLOBAL_CAST_LOCKOUT = 0.35,
	-- Seconds between drawn spells. Each recognized drawing adds one copy of
	-- a spell (up to MAX_HAND held, duplicates allowed).
	DRAW_COOLDOWN = 1,
	-- Largest stroke the server will look at (points), and how far from the
	-- screen a point may be (in screen heights). Clients send ~4px samples.
	DRAW_MAX_POINTS = 200,
	DRAW_MAX_COORD = 6,
	-- Longest a single stroke may take on the client before it auto-submits.
	DRAW_MAX_SECONDS = 6,
	-- Drawing quality: how closely a stroke follows its shape. The recognizer's
	-- score (0..1; 0.8 is the least that counts as the shape at all) maps from
	-- SCORE_FLOOR (quality 0, a sloppy stroke) to SCORE_PERFECT (quality 1),
	-- and quality scales a cast between these
	-- {worst, best} multipliers: POWER (damage, healing, shields, health,
	-- boosts), SIZE (hit radius), TIME (durations and lifetimes). DEFAULT is the
	-- quality of a copy that wasn't drawn (admin gives).
	QUALITY = {
		SCORE_FLOOR = 0.85,
		SCORE_PERFECT = 0.975,
		DEFAULT = 0.5,
		POWER = { 0.85, 1.5 },
		SIZE = { 0.9, 1.25 },
		TIME = { 0.85, 1.3 },
	},

	-- Movement & aiming. Players move faster than Roblox's default (16) to
	-- keep fights lively; projectiles are sped up by the same ratio and get
	-- a bigger hitbox so they still land.
	WALK_SPEED = 24,
	JUMP_POWER = 55,
	PROJECTILE_SPEED_SCALE = 1.5,
	-- Studs added to every projectile's hit radius (spherecast) and to
	-- area-of-effect checks against players.
	HITBOX_BONUS = 2,

	-- The hub heals fast. Everywhere else (matches, the Battleground) health
	-- slowly regenerates, but only after PASSIVE_REGEN_DELAY seconds without
	-- taking damage, so it never helps in the middle of a fight.
	HUB_REGEN_PER_SECOND = 5,
	PASSIVE_REGEN_PER_SECOND = 1,
	PASSIVE_REGEN_DELAY = 5,

	-- Seconds the hub's team boxes wait once both sides are full, so someone
	-- can still step off before the match starts.
	TEAM_BOX_COUNTDOWN = 5,

	-- Seconds of the "VS" intro before players are moved into the arena.
	INTRO_TIME = 4,

	-- Settings: the default key that starts drawing a spell, and keys that
	-- can't be bound to it (movement, chat, hotbar, cancel, menus).
	DEFAULT_DRAW_KEY = "F",
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
		"G",
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

	-- Players needed for each queued mode, as {teamCount, playersPerTeam}.
	MODES = {
		["1v1"] = { teams = 2, perTeam = 1 },
		["2v2"] = { teams = 2, perTeam = 2 },
		["3v3"] = { teams = 2, perTeam = 3 },
		["4v4"] = { teams = 2, perTeam = 4 },
	},

	-- The Battleground: a drop-in open world (Maps/Battleground,
	-- BattlegroundService) built far from the hub. Players spawn at a random
	-- open spot, fight each other and the hostile NPCs there (NpcService), and
	-- respawn `RESPAWN_DELAY` seconds after a knockout.
	--   CENTER     the middle of the world (the ground's top is at CENTER.Y)
	--   HALF_SIZE  half the width of the square world, in studs
	--   NPC        RESPAWN: seconds until a defeated NPC returns (types can
	--              override it); COIN_CAP: most coins one player can earn from
	--              NPCs in any COIN_WINDOW seconds, so farming them can't
	--              outpay winning matches.
	BATTLEGROUND = {
		CENTER = Vector3.new(900, 0, 0),
		HALF_SIZE = 300,
		RESPAWN_DELAY = 3,
		NPC = {
			RESPAWN = 45,
			COIN_CAP = 120,
			COIN_WINDOW = 300,
		},
	},

	-- Map vote before a match (MapVoteService): which modes vote, and how long.
	MAP_VOTE = {
		MODES = { ["1v1"] = true },
		SECONDS = 12,
	},

	-- Parties (PartyService): players grouped in the Battleground.
	PARTY = {
		MAX_SIZE = 4,
		INVITE_SECONDS = 30,
	},

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
		"Fizzle! The magic couldn't read that drawing.",
		"Draw one smooth shape, big and slow.",
		"Not quite! Check the glyph cards and trace the shape.",
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
