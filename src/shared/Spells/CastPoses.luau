--!strict
-- Cast animations as data: arm/leg/body poses, one per kind of move. Client/Fx/
-- CastAnimations plays them by tweening the character's shoulder, elbow, hip,
-- knee, and waist joints (no uploaded Animation assets), the spell registry
-- names one pose per spell (Spells/SpellRegistry), and tests/Registry.spec
-- checks it.
--
-- A pose is a list of keys played in order. Each key tweens the joints to its
-- angles in `d` seconds, then holds `hold` seconds. The last key is followed
-- by a return to the resting pose.
--
-- Angles are degrees. For an arm, `fwd` swings it forward (180 = straight
-- up), `side` swings it out to the side (negative = across the body), and
-- `elbow` bends the forearm forward. A leg takes the same `fwd` and `side`,
-- and `knee` bends the shin backward. `lean` tips the torso forward and
-- `twist` turns it about the spine (positive = to the caster's right). Both
-- arms and legs mirror `side`, so left and right use the same numbers. R6
-- characters only get the `fwd` swing of arms and legs. A pose that names no
-- leg leaves the legs to the walk cycle.
--
-- BEATS are the body effects that ride on a pose (Fx/SpellVfx.castBeat): the
-- fireball that gathers over the hand, the trail a slash leaves, the dust a
-- stomp kicks up. `at` is the second the move lands (the end of the swing).

local CastPoses = {}

export type Arm = { fwd: number?, side: number?, elbow: number? }
export type Leg = { fwd: number?, side: number?, knee: number? }

export type Key = {
	d: number,
	hold: number?,
	right: Arm?,
	left: Arm?,
	rightLeg: Leg?,
	leftLeg: Leg?,
	lean: number?,
	twist: number?,
	-- Degrees the whole body has somersaulted forward (360 = one full flip);
	-- list each quarter turn as its own key so the spin takes the long way round.
	flip: number?,
}

-- orb     a ball gathers in the hand(s) and is released at `at` (`material`
--         picks neon fire or slate rock, `two` holds it in both hands)
-- trail   the hand leaves a glowing streak from `at` for a moment
-- stomp   a dust ring and shockwave burst at the feet (or `reach` studs ahead)
-- gather  sparks stream into the raised hand (`two`: the middle of both), then flash at `at`
-- build   sparks fly off both hands and dust kicks up (setting a turret down)
-- swirl   rings of wind spin out around the body
-- splash  droplets spray from the hands
-- push    a ring of wind shoves out in front of the caster
export type Beat = {
	kind: string,
	at: number,
	material: string?,
	two: boolean?,
	reach: number?,
	cue: string?,
}

CastPoses.POSES = {
	-- The default round-arm throw: wind back, then whip forward.
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

	-- FIRE ----------------------------------------------------------------
	-- A fireball held high over the head, then hurled with a lunge (Fireball).
	Fireball = {
		{
			d = 0.12,
			hold = 0.1,
			right = { fwd = 165, side = 10, elbow = 50 },
			left = { fwd = 40, elbow = 30 },
			lean = -8,
		},
		{
			d = 0.07,
			hold = 0.18,
			right = { fwd = 95, elbow = 5 },
			left = { fwd = -15 },
			rightLeg = { fwd = -20 },
			leftLeg = { fwd = 30, knee = 20 },
			lean = 14,
		},
	},
	-- A diagonal chop from high on one side to low on the other (Fire Slash).
	Slash = {
		{
			d = 0.07,
			right = { fwd = 150, side = 50, elbow = 20 },
			left = { fwd = 20 },
			twist = 35,
			lean = -6,
		},
		{
			d = 0.08,
			hold = 0.15,
			right = { fwd = 60, side = -45 },
			left = { fwd = 20 },
			twist = -40,
			lean = 14,
		},
	},
	-- Both fists out and flexed (Fire Boost).
	Flex = {
		{
			d = 0.1,
			hold = 0.35,
			right = { side = 95, elbow = 110 },
			left = { side = 95, elbow = 110 },
			lean = -6,
		},
	},
	-- Palms low, then both arms heaved to the sky as the ground erupts (Fire Pillar).
	Erupt = {
		{
			d = 0.12,
			right = { fwd = 15, side = 25, elbow = 10 },
			left = { fwd = 15, side = 25, elbow = 10 },
			lean = 14,
		},
		{
			d = 0.1,
			hold = 0.22,
			right = { fwd = 165, side = 20 },
			left = { fwd = 165, side = 20 },
			lean = -14,
		},
	},
	-- Both arms reach for the sky, hold, then slam forward (Fire Bomb).
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

	-- WATER ---------------------------------------------------------------
	-- A flat sweep across the body, like drawing a blade of water (Water Slice).
	Slice = {
		{
			d = 0.07,
			right = { fwd = 85, side = 75, elbow = 10 },
			left = { fwd = 60, side = 40 },
			twist = 50,
		},
		{
			d = 0.08,
			hold = 0.15,
			right = { fwd = 90, side = -30 },
			left = { fwd = 60, side = 20 },
			twist = -55,
			lean = 6,
		},
	},
	-- Arms ripple up and over, one then the other, like a swimmer's wave (Water Body).
	Flow = {
		{
			d = 0.14,
			right = { fwd = 150, side = 30, elbow = 20 },
			left = { fwd = 20, side = 30 },
			twist = 25,
			lean = -4,
		},
		{
			d = 0.14,
			hold = 0.22,
			right = { fwd = 20, side = 30 },
			left = { fwd = 150, side = 30, elbow = 20 },
			twist = -25,
		},
	},
	-- Both palms thrust forward (Water Lock).
	Point = {
		{
			d = 0.09,
			hold = 0.25,
			right = { fwd = 95, elbow = 5 },
			left = { fwd = 95, elbow = 5 },
			lean = 6,
		},
	},
	-- Crouch back with the arms low, then heave a wall of water up and out (Water Wave).
	Wave = {
		{
			d = 0.12,
			right = { fwd = -35, side = 25 },
			left = { fwd = -35, side = 25 },
			rightLeg = { fwd = -25 },
			leftLeg = { fwd = 30, knee = 25 },
			lean = 20,
		},
		{
			d = 0.09,
			hold = 0.22,
			right = { fwd = 105, side = 10 },
			left = { fwd = 105, side = 10 },
			rightLeg = { fwd = -25 },
			leftLeg = { fwd = 30, knee = 25 },
			lean = -6,
		},
	},
	-- Arms flung up and out to call the storm, then brought down like rain (Water Nebula).
	Downpour = {
		{
			d = 0.18,
			hold = 0.15,
			right = { fwd = 160, side = 60, elbow = 10 },
			left = { fwd = 160, side = 60, elbow = 10 },
			lean = -12,
		},
		{
			d = 0.1,
			hold = 0.25,
			right = { fwd = 45, side = 25, elbow = 40 },
			left = { fwd = 45, side = 25, elbow = 40 },
			lean = 16,
		},
	},

	-- EARTH ---------------------------------------------------------------
	-- Scoop a boulder up, lift it overhead, and heave it (Rock Throw).
	Heave = {
		{
			d = 0.1,
			right = { fwd = 35, elbow = 75 },
			left = { fwd = 35, elbow = 75 },
			lean = 22,
		},
		{
			d = 0.12,
			hold = 0.06,
			right = { fwd = 160, elbow = 20 },
			left = { fwd = 160, elbow = 20 },
			lean = -12,
		},
		{
			d = 0.07,
			hold = 0.18,
			right = { fwd = 90, elbow = 5 },
			left = { fwd = 90, elbow = 5 },
			lean = 16,
		},
	},
	-- Stomp a foot down, then push both palms out to raise the wall (Earth Wall).
	Bulwark = {
		{
			d = 0.12,
			right = { fwd = 20, side = 20, elbow = 30 },
			left = { fwd = 20, side = 20, elbow = 30 },
			rightLeg = { fwd = 70, knee = 80 },
			lean = -4,
		},
		{
			d = 0.07,
			hold = 0.3,
			right = { fwd = 110, elbow = 10 },
			left = { fwd = 110, elbow = 10 },
			rightLeg = { fwd = 0 },
			lean = 10,
		},
	},
	-- Fist overhead, then a lunging punch into the ground (Earth Punch).
	GroundPunch = {
		{
			d = 0.14,
			right = { fwd = 175, elbow = 30 },
			left = { fwd = 30 },
			rightLeg = { fwd = -20 },
			leftLeg = { fwd = 25 },
			lean = -14,
		},
		{
			d = 0.06,
			hold = 0.28,
			right = { fwd = 35 },
			left = { fwd = 40, elbow = 40 },
			rightLeg = { fwd = -20 },
			leftLeg = { fwd = 25 },
			lean = 32,
		},
	},
	-- One foot stamps and the other arm points down the line of spikes (Earth Pillar).
	StompRise = {
		{
			d = 0.12,
			right = { fwd = 30, side = 50, elbow = 20 },
			left = { fwd = 30, side = 50, elbow = 20 },
			rightLeg = { fwd = 75, knee = 85 },
			lean = -6,
		},
		{
			d = 0.06,
			hold = 0.3,
			right = { fwd = 95 },
			left = { fwd = 25, side = 40 },
			rightLeg = { fwd = 0 },
			lean = 14,
		},
	},
	-- Foot raised high and stamped down, feet wide, arms low: shaking the ground.
	-- The held time grows with the spell's channel (Earthquake).
	Stomp = {
		{
			d = 0.14,
			right = { fwd = 130, side = 40 },
			left = { fwd = 130, side = 40 },
			rightLeg = { fwd = 80, knee = 90 },
			lean = -10,
		},
		{
			d = 0.08,
			hold = 0.4,
			right = { fwd = 20, side = 60, elbow = 20 },
			left = { fwd = 20, side = 60, elbow = 20 },
			rightLeg = { side = 20, knee = 15 },
			leftLeg = { side = 20, knee = 15 },
			lean = 18,
		},
	},

	-- AIR -----------------------------------------------------------------
	-- A sideways fan of the hand that sends a puff of wind (Gust).
	Fan = {
		{ d = 0.08, right = { fwd = 85, side = 80, elbow = 20 }, twist = 35 },
		{ d = 0.08, hold = 0.18, right = { fwd = 95, side = 5 }, left = { fwd = 20 }, twist = -30 },
	},
	-- Arms out flat while the whole body spins (Whirlwind).
	Spin = {
		{
			d = 0.12,
			right = { fwd = 85, side = 95 },
			left = { fwd = 85, side = 95 },
			twist = 70,
			lean = 6,
		},
		{
			d = 0.16,
			hold = 0.25,
			right = { fwd = 85, side = 95 },
			left = { fwd = 85, side = 95 },
			twist = -70,
		},
	},
	-- Arms thrown back, body tipped forward, ready to rush (Air Boost).
	Surge = {
		{
			d = 0.08,
			hold = 0.35,
			right = { fwd = -50, side = 25 },
			left = { fwd = -50, side = 25 },
			rightLeg = { fwd = -30, knee = 30 },
			leftLeg = { fwd = 35 },
			lean = 25,
		},
	},
	-- Both forearms crossed in front (Air Shield).
	Guard = {
		{
			d = 0.1,
			hold = 0.35,
			right = { fwd = 90, side = -25, elbow = 60 },
			left = { fwd = 90, side = -25, elbow = 60 },
		},
	},
	-- Arms high, torso wound one way and then the other, like a screw (Tornado).
	Cyclone = {
		{
			d = 0.15,
			right = { fwd = 160, side = 35 },
			left = { fwd = 160, side = 35 },
			twist = 60,
			lean = -8,
		},
		{
			d = 0.2,
			hold = 0.35,
			right = { fwd = 160, side = 35 },
			left = { fwd = 160, side = 35 },
			twist = -60,
			lean = -8,
		},
	},

	-- ARCANE --------------------------------------------------------------
	-- Both palms lifted and opened toward the sky (Heal).
	Offer = {
		{
			d = 0.15,
			hold = 0.4,
			right = { fwd = 110, side = 35, elbow = 40 },
			left = { fwd = 110, side = 35, elbow = 40 },
			lean = -6,
		},
	},
	-- Feet planted wide, arms flung out, then dragged together as if pulling the
	-- air (and everything in it) into a point (Black Hole).
	Conjure = {
		{
			d = 0.12,
			right = { fwd = 80, side = 95 },
			left = { fwd = 80, side = 95 },
			rightLeg = { side = 14 },
			leftLeg = { side = 14 },
			lean = -6,
		},
		{
			d = 0.12,
			hold = 0.3,
			right = { fwd = 100, side = 5, elbow = 20 },
			left = { fwd = 100, side = 5, elbow = 20 },
			rightLeg = { side = 14 },
			leftLeg = { side = 14 },
			lean = 8,
		},
	},
	-- Down on one knee, hands to the ground to bolt a turret in place (Turret).
	Deploy = {
		{
			d = 0.12,
			right = { fwd = 60, side = 15, elbow = 40 },
			left = { fwd = 60, side = 15, elbow = 40 },
			rightLeg = { fwd = 35, knee = 75 },
			leftLeg = { fwd = -15, knee = 30 },
			lean = 24,
		},
		{
			d = 0.08,
			hold = 0.3,
			right = { fwd = 35, elbow = 10 },
			left = { fwd = 35, elbow = 10 },
			rightLeg = { fwd = 35, knee = 75 },
			leftLeg = { fwd = -15, knee = 30 },
			lean = 28,
		},
	},
	-- One arm shot to the sky, then thrown down at the target (Lightning).
	Call = {
		{ d = 0.1, right = { fwd = 178 }, left = { fwd = 10 }, lean = -10 },
		{ d = 0.06, hold = 0.2, right = { fwd = 85 }, left = { fwd = 10 }, lean = 16 },
	},

	-- The dash (not a spell): a leap with the arms flung wide, then a full
	-- forward somersault in four quarter turns (about Config.DASH.DURATION).
	Dash = {
		{
			d = 0.04,
			right = { fwd = -30, side = 70, elbow = 10 },
			left = { fwd = -30, side = 70, elbow = 10 },
		},
		{
			d = 0.09,
			right = { fwd = -30, side = 70, elbow = 10 },
			left = { fwd = -30, side = 70, elbow = 10 },
			flip = 90,
		},
		{
			d = 0.09,
			right = { fwd = -30, side = 70, elbow = 10 },
			left = { fwd = -30, side = 70, elbow = 10 },
			flip = 180,
		},
		{
			d = 0.09,
			right = { fwd = -30, side = 70, elbow = 10 },
			left = { fwd = -30, side = 70, elbow = 10 },
			flip = 270,
		},
		{
			d = 0.09,
			right = { fwd = -30, side = 70, elbow = 10 },
			left = { fwd = -30, side = 70, elbow = 10 },
			flip = 360,
		},
	},
} :: { [string]: { Key } }

-- Body effects that ride on a pose. A pose without a beat just moves.
CastPoses.BEATS = {
	Fireball = { kind = "orb", at = 0.22, cue = "orbCharge" },
	Heave = { kind = "orb", at = 0.28, material = "Slate", two = true, cue = "orbCharge" },
	Slash = { kind = "trail", at = 0.07 },
	Slice = { kind = "trail", at = 0.07 },
	Erupt = { kind = "gather", at = 0.22, cue = "orbCharge" },
	Ascend = { kind = "gather", at = 0.65, cue = "orbCharge" },
	Call = { kind = "gather", at = 0.16, cue = "orbCharge" },
	Flow = { kind = "splash", at = 0.28 },
	Wave = { kind = "splash", at = 0.21 },
	Downpour = { kind = "splash", at = 0.43 },
	Bulwark = { kind = "stomp", at = 0.19, cue = "stompThud" },
	GroundPunch = { kind = "stomp", at = 0.2, reach = 4, cue = "stompThud" },
	StompRise = { kind = "stomp", at = 0.18, cue = "stompThud" },
	Stomp = { kind = "stomp", at = 0.22, cue = "stompThud" },
	Fan = { kind = "push", at = 0.16, cue = "pushWhoosh" },
	Spin = { kind = "swirl", at = 0.12, cue = "spinWhoosh" },
	Cyclone = { kind = "swirl", at = 0.15, cue = "spinWhoosh" },
	Surge = { kind = "swirl", at = 0.08, cue = "spinWhoosh" },
	Conjure = { kind = "gather", at = 0.24, two = true, cue = "voidPull" },
	Deploy = { kind = "build", at = 0.2, cue = "buildClank" },
} :: { [string]: Beat }

CastPoses.BEAT_KINDS = { "orb", "trail", "stomp", "gather", "swirl", "splash", "push", "build" }

return CastPoses
