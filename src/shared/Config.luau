--!strict
-- Tunable gameplay values. NOTE: replicated to clients — nothing secret here,
-- and the server never trusts a client-reported value from this file.

local Config = {
	-- Seconds. Spells cannot be cast faster than this regardless of cooldowns.
	GLOBAL_CAST_LOCKOUT = 0.35,
	-- Seconds between drawn spells. Each recognized drawing casts its spell at once.
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

	-- The wand every player holds (WandService welds the "Wand" block model to
	-- the right hand; client Fx/WandVfx draws the spell in the air with it).
	--   MODEL          block model name (Models/BlockModels, Blender spec)
	--   TILT           degrees the wand leans forward from the forearm's line
	--   AIR_DISTANCE   studs in front of the chest where a drawing appears
	--   AIR_SIZE       studs across a full-size drawing in the air
	--   AIR_HEIGHT     studs above the root part the drawing is centred
	--   TRACE_SECONDS  how long other players' glyphs take to trace in the air
	--   DRAW_STATE_RATE  least seconds between DrawingState messages a client
	--                  may send (more are ignored)
	--   CIRCLE_RADIUS  studs: the magic circle behind a drawing in the air
	--   STROKE_SEND_RATE  seconds between batches of a live stroke sent to the
	--                  server (relayed so others watch you draw)
	--   STROKE_BATCH   most points in one batch; STROKE_MAX_POINTS per stroke
	--   STROKE_RATE    least seconds between batches the server accepts
	--   RELAY_RANGE    studs: players farther away aren't sent your stroke
	--   VIEW_*         your own wand in first person while you draw
	--                  (Fx/WandView): its scale, where it is held (camera
	--                  space: right, up, forward is -Z), how fast its tip
	--                  follows the pen (higher = snappier), and the seconds it
	--                  takes to rise in and drop away
	WAND = {
		MODEL = "Wand",
		TILT = 30,
		AIR_DISTANCE = 5,
		AIR_SIZE = 6,
		AIR_HEIGHT = 1.6,
		TRACE_SECONDS = 0.35,
		DRAW_STATE_RATE = 0.1,
		CIRCLE_RADIUS = 3.7,
		STROKE_SEND_RATE = 0.1,
		STROKE_BATCH = 24,
		STROKE_MAX_POINTS = 300,
		STROKE_RATE = 0.05,
		RELAY_RANGE = 250,
		VIEW_SCALE = 0.6,
		VIEW_GRIP = Vector3.new(0.7, -0.7, -0.9),
		VIEW_FOLLOW = 22,
		VIEW_RAISE = 0.22,
	},

	-- Movement & aiming. Players move faster than Roblox's default (16) to
	-- keep fights lively. Bolts stay slow enough to see coming, and track a
	-- little (AUTO_AIM.HOMING) and have a bigger hitbox so they still land.
	WALK_SPEED = 24,
	JUMP_POWER = 55,
	PROJECTILE_SPEED_SCALE = 1,
	-- Studs added to every projectile's hit radius (spherecast) and to
	-- area-of-effect checks against players.
	HITBOX_BONUS = 2,

	-- The hub heals fast. Everywhere else (matches, the Battleground) there is
	-- no passive regeneration: healing comes from spells and boosts.
	HUB_REGEN_PER_SECOND = 5,

	-- Seconds the hub's team boxes wait once both sides are full, so someone
	-- can still step off before the match starts.
	TEAM_BOX_COUNTDOWN = 5,

	-- Seconds of the "VS" intro before players are moved into the arena.
	INTRO_TIME = 4,

	-- Mouse look speed: UserInputService.MouseDeltaSensitivity for the default
	-- setting and the range and step of the Settings control (saved per player).
	CAMERA = { SENSITIVITY = 0.25, MIN = 0.05, MAX = 1, STEP = 0.05 },

	-- Settings: the default key that starts drawing a spell, and keys that
	-- can't be bound to it (movement, chat, the spell keys, cancel, menus).
	DEFAULT_DRAW_KEY = "F",
	RESERVED_KEYS = {
		"M",
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
		"Q",
	} :: { string },
	-- After a hard crowd-control effect (Root, TimeStop, Shrink) ends, the
	-- target can't be hit by that kind again for this long. Stops CC chains
	-- now that spells can be re-typed every second.
	CC_IMMUNITY = 2.5,

	PLAYER_MAX_HEALTH = 100,
	SPAWN_PROTECTION = 3,
	-- Characters below this Y inside an arena are knocked out (ring-outs). Only
	-- a fallback for a player with no spawn pad: everyone else is caught by the
	-- arena's water (RESCUE.WATER_SURFACE), however far past it they have fallen.
	ARENA_VOID_DEPTH = -60,

	-- Never stuck, never lost (server/Services/Rescue). Y values are studs from
	-- the arena's floor (its origin).
	--   WATER_SURFACE  the water under every arena; fall into it and it launches
	--                  you back onto your team's spawn pad
	--   WATER_DAMAGE   what the splash costs (it can still finish a weak player,
	--                  and the last enemy who hit you gets the credit)
	--   WATER_STUN     seconds you cannot cast after the splash
	--   WATER_APEX     studs the arc peaks above the pad
	--   WATER_REPEAT   a second splash within this many seconds skips the arc and
	--                  just puts you on the pad
	--   PIT_*          a player standing at the bottom of a hole that is walled in
	--                  on every side by terrain cells taller than PIT_CLIMB (a jump
	--                  clears about 7.7 studs) is thrown out over the nearest rim
	--                  after PIT_SECONDS, looking out PIT_REACH studs; the arc
	--                  peaks PIT_APEX over the rim, and a rim higher than
	--                  PIT_MAX_RIM puts the player back on the spawn pad instead
	RESCUE = {
		WATER_SURFACE = -50,
		WATER_DAMAGE = 30,
		WATER_STUN = 1.2,
		WATER_APEX = 40,
		WATER_REPEAT = 4,
		PIT_CLIMB = 9,
		PIT_REACH = 36,
		PIT_SECONDS = 1.5,
		PIT_APEX = 6,
		PIT_MAX_RIM = 45,
	},

	-- Juice (client Fx/Juice): screen shake, field-of-view kicks, hit markers and
	-- the damage vignette. Every effect scales with the hit; the Screen shake
	-- setting turns the camera movement off.
	--   SHAKE_MAX      most the camera can be offset, in studs
	--   FOV_MAX        most the field of view can be kicked, in degrees
	--   BIG_HIT        damage that counts as a heavy hit (bigger marker and kick)
	--   LOW_HEALTH     health fraction below which the screen edges pulse red
	JUICE = {
		SHAKE_MAX = 1.1,
		FOV_MAX = 9,
		BIG_HIT = 25,
		LOW_HEALTH = 0.3,
	},

	COUNTDOWN_TIME = 5,
	ROUND_TIME = 120,
	DRAFT_TIME = 15,
	RESULTS_TIME = 8,
	ROUNDS_TO_WIN = 2, -- best of 3

	MAX_PLACED_PER_PLAYER = 6,
	-- A spell is cast as soon as it is drawn, with the camera still: looking
	-- straight ahead puts a wall this far away, close enough to take cover at.
	PLACE_RANGE = 20,
	AIM_RANGE = 200,

	-- First person and the sight (CameraController, CastService, shared/Util/AutoAim).
	-- A spell goes where the sight points. Bolts (and only bolts) also get a quiet
	-- assist, since the camera can't turn while drawing: the opponent closest to
	-- the sight, in plain sight and inside the cone, is aimed at, led and tracked.
	-- ASSIST = false makes every bolt fly dead straight. CONE and CLOSE_CONE:
	-- half-angles in degrees at CLOSE_RANGE and beyond, and at point blank.
	-- DISTANCE_WEIGHT: how much being nearer counts against being closer to the
	-- sight. LEAD: how much of a target's motion a bolt leads, LEAD_VERTICAL of
	-- its vertical speed, up to MAX_LEAD_SECONDS. HOMING: degrees a second a bolt
	-- turns toward its target, until it is HOMING_GIVE_UP off course (dodged).
	-- MAX_YAW_ERROR: how far an aim may be from where the character faces.
	AUTO_AIM = {
		ASSIST = true,
		CONE = 15,
		CLOSE_CONE = 25,
		CLOSE_RANGE = 15,
		DISTANCE_WEIGHT = 0.25,
		LEAD = 0.8,
		LEAD_VERTICAL = 0.25,
		MAX_LEAD_SECONDS = 1.2,
		HOMING = 60,
		HOMING_GIVE_UP = 75,
		MAX_YAW_ERROR = 70,
		FOV = 80,
	},

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
		-- Far enough from the hub (and beyond its haze) that you cannot see the
		-- Battleground from the island: the portal is the only way there.
		CENTER = Vector3.new(15000, 0, 0),
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

	-- Dash (DashService, client DashController): a quick leap forward on a
	-- key (Q) or the Dash button. The server checks the cooldown and the
	-- player's state and tells the client which way to go; the client moves its
	-- own character at SPEED studs/s for DURATION seconds (about 28 studs) and
	-- pops it HOP studs/s upward, so the dash is a low arc with three wind
	-- streaks (TRAILS) behind it.
	DASH = {
		COOLDOWN = 8,
		SPEED = 70,
		DURATION = 0.4,
		HOP = 38,
		TRAILS = 3,
	},

	-- The hub is a floating island (Maps/InkwellPlaza) centered on the origin
	-- with its top at y = 0. RADIUS is the grass disc; the ocean far below it is
	-- OCEAN_Y. Match arenas are summoned BELOW it (ArenaService) so hub players
	-- can look over the rim and watch duels.
	HUB = {
		RADIUS = 240,
		OCEAN_Y = -450,
	},

	-- Where match arenas appear: in rings around the hub's axis, ARENA.Y studs
	-- below it. Slot 1..PER_RING sit on the first ring (RADIUS from the axis),
	-- the next PER_RING on a second ring RING_STEP further out, and so on.
	ARENA = {
		Y = -300,
		RADIUS = 560,
		RING_STEP = 600,
		PER_RING = 8,
	},

	-- Every match arena is built at design size, then scaled up by this factor
	-- (ArenaService.init).
	ARENA_SCALE = 2,

	-- Breakable terrain (MapKit.terrain, DestructibleService): ground, mesas and
	-- outcrops are made of cells that take spell damage like any other prop, so
	-- the harder a spell hits the faster it carves through. Cells come back with
	-- the next round's fresh arena.
	--   CELL     design-size width of one cell, in studs (before ARENA_SCALE)
	--   HEALTH   what a cell can take: Ground (the baseplate: floors and island
	--            tops) is very tough, so a fight can't dig through it quickly;
	--            Rock (cliffs, mesas, steps, boulders) is scenery and gives way
	--            in a few hits
	--   SPLASH   share of a hit's damage that also lands on every cell touching
	--            the one that was hit, so heavy spells open wider craters
	TERRAIN = {
		CELL = 10,
		HEALTH = { Ground = 240, Rock = 45 },
		SPLASH = 0.75,
	},

	-- Health of the scenery on the maps (trees, pillars, spires, ice cubes,
	-- columns, bridges, torches, brick cover). It is meant to be easy to break:
	-- Light is a couple of hits, Heavy a handful (a Fireball does 15).
	PROPS = { Brick = 15, Light = 25, Medium = 45, Heavy = 70 },

	AUTOSAVE_INTERVAL = 90,

	-- Coins: earned by winning matches (plus daily login and quests), spent
	-- on chests (shared/Economy/Chests). There are no levels or XP.
	COINS = {
		STARTING = 150, -- a new player can open a Common chest right away
		MATCH_WIN = 100,
		FIRST_WIN_OF_DAY = 50,
		DAILY_LOGIN = 25, -- x streak day, capped at 7
	},

	-- Support reward (EconomyService.claimLikeReward): a one-time coin gift for
	-- players who Like and Favourite the game. Roblox has no way to check either,
	-- so it is a thank-you on the honor system: the claim opens after MIN_SECONDS
	-- in the server (time to actually play, like, and favourite) and works once
	-- per account.
	SUPPORT = {
		LIKE_FAVORITE_COINS = 250,
		MIN_SECONDS = 90,
	},

	-- Background music (client AudioController, tracks in shared/Audio/Music):
	-- the music group's volume (0..1) and the seconds a track fades in/out.
	MUSIC = {
		VOLUME = 0.3,
		FADE_SECONDS = 2,
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
