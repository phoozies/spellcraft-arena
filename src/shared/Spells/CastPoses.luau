--!strict
-- Cast animations as data: a few arm/body poses per kind of move. Client/Fx/
-- CastAnimations plays them by tweening the character's shoulder, elbow, and
-- waist joints (no uploaded Animation assets), the spell registry names one
-- pose per spell (Spells/SpellRegistry), and tests/Registry.spec checks it.
--
-- A pose is a list of keys played in order. Each key tweens the joints to its
-- angles in `d` seconds, then holds `hold` seconds. The last key is followed
-- by a return to the resting pose.
--
-- Angles are degrees. For an arm, `fwd` swings it forward (180 = straight
-- up), `side` swings it out to the side (negative = across the body), and
-- `elbow` bends the forearm forward. `lean` tips the torso forward. Both
-- arms mirror `side`, so left and right use the same numbers. R6 characters
-- only get the `fwd` swing.

local CastPoses = {}

export type Arm = { fwd: number?, side: number?, elbow: number? }

export type Key = {
	d: number,
	hold: number?,
	right: Arm?,
	left: Arm?,
	lean: number?,
}

CastPoses.POSES = {
	-- A round-arm throw: wind back, then whip forward (basic attacks).
	Throw = {
		{ d = 0.08, right = { fwd = -55, elbow = 30 }, left = { fwd = 20 }, lean = -6 },
		{
			d = 0.09,
			hold = 0.18,
			right = { fwd = 100, elbow = 5 },
			left = { fwd = -15 },
			lean = 12,
		},
	},
	-- A cross-body swipe (fast attacks).
	Slash = {
		{ d = 0.07, right = { fwd = 60, side = 70 }, lean = -5 },
		{ d = 0.08, hold = 0.15, right = { fwd = 70, side = -40 }, left = { fwd = 20 }, lean = 8 },
	},
	-- Both fists out and flexed (boosts).
	Flex = {
		{
			d = 0.1,
			hold = 0.35,
			right = { side = 95, elbow = 110 },
			left = { side = 95, elbow = 110 },
			lean = -6,
		},
	},
	-- Both forearms crossed in front (defense).
	Guard = {
		{
			d = 0.1,
			hold = 0.35,
			right = { fwd = 90, side = -25, elbow = 60 },
			left = { fwd = 90, side = -25, elbow = 60 },
		},
	},
	-- Both palms thrust forward (stuns and traps).
	Point = {
		{
			d = 0.09,
			hold = 0.25,
			right = { fwd = 95, elbow = 5 },
			left = { fwd = 95, elbow = 5 },
			lean = 6,
		},
	},
	-- One arm overhead, then a hammer blow down (heavy attacks).
	Smash = {
		{ d = 0.12, right = { fwd = 170 }, left = { fwd = 20 }, lean = -12 },
		{ d = 0.07, hold = 0.2, right = { fwd = 70 }, left = { fwd = 10 }, lean = 18 },
	},
	-- Both arms swept up and out, then pulled down (area attacks).
	Sweep = {
		{ d = 0.12, right = { fwd = 150, side = 40 }, left = { fwd = 150, side = 40 }, lean = -8 },
		{
			d = 0.1,
			hold = 0.2,
			right = { fwd = 40, side = 60 },
			left = { fwd = 40, side = 60 },
			lean = 10,
		},
	},
	-- Both arms reach for the sky, hold, then slam forward (ultimates).
	Ascend = {
		{
			d = 0.2,
			hold = 0.45,
			right = { fwd = 170, side = 15 },
			left = { fwd = 170, side = 15 },
			lean = -14,
		},
		{ d = 0.08, hold = 0.25, right = { fwd = 80 }, left = { fwd = 80 }, lean = 16 },
	},
	-- The dash (not a spell): arms thrown back, body tipped far forward.
	Dash = {
		{
			d = 0.07,
			hold = 0.14,
			right = { fwd = -70, elbow = 20 },
			left = { fwd = -70, elbow = 20 },
			lean = 30,
		},
	},
	-- Arms low and wide, torso bent, planted: shaking the ground. The held
	-- time grows with the spell's channel (Earthquake).
	Stomp = {
		{
			d = 0.15,
			hold = 0.4,
			right = { fwd = 20, side = 60, elbow = 20 },
			left = { fwd = 20, side = 60, elbow = 20 },
			lean = 14,
		},
	},
} :: { [string]: { Key } }

return CastPoses
