--!strict
-- A quiet aim assist for bolts (Config.AUTO_AIM). A spell goes where the sight
-- points; nothing on screen marks a target, so the assist has to do what the
-- player expects: help the bolt reach whoever they were looking at.
--
--   pick   chooses the target: every candidate inside the aim cone (narrow at
--          range, wider up close, never narrower than the target itself) is
--          scored by how far it is off the sight, so the opponent CLOSEST TO
--          THE SIGHT wins, and distance only settles near-ties. Line of sight
--          is only checked (raycast) for candidates in score order, so a
--          crowded fight costs few raycasts.
--   lead   where to throw a bolt so it meets a moving target (an intercept,
--          softened by LEAD and with vertical speed damped, since jumps come
--          back down).
--   steer  turns a bolt's heading toward its target by at most an angle, so
--          locked bolts track slightly (Projectile homing) but a hard
--          sidestep still dodges them.
--
-- Pure module (no Instances): CastService runs it on the server to decide the
-- shot, and tests/AutoAim.spec checks it.

local Config = require(script.Parent.Parent.Config)

local AutoAim = {}

export type Candidate = {
	position: Vector3,
	velocity: Vector3?,
	-- Half the target's width in studs (players are about 2).
	radius: number?,
	-- Whatever the caller needs back (a character, an NPC model).
	key: any?,
}

export type Options = {
	range: number,
	-- Clear line of sight from the caster to the candidate (raycast). Omitted:
	-- everything is visible.
	visible: ((candidate: Candidate) -> boolean)?,
}

local function settings()
	return Config.AUTO_AIM
end

-- The aim cone's half-angle (radians) at `distance`: CLOSE_CONE at point blank,
-- narrowing linearly to CONE at CLOSE_RANGE and beyond.
function AutoAim.cone(distance: number): number
	local s = settings()
	local t = math.clamp(distance / s.CLOSE_RANGE, 0, 1)
	return math.rad(s.CLOSE_CONE + (s.CONE - s.CLOSE_CONE) * t)
end

-- Angle in radians between two directions (any length).
function AutoAim.angleBetween(a: Vector3, b: Vector3): number
	if a.Magnitude < 1e-6 or b.Magnitude < 1e-6 then
		return math.pi
	end
	return math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
end

-- How the candidate ranks (lower is better), or nil when it is out of range
-- or outside the cone. Also returns its angle off the crosshair.
function AutoAim.score(
	origin: Vector3,
	forward: Vector3,
	candidate: Candidate,
	range: number
): (number?, number)
	local offset = candidate.position - origin
	local distance = offset.Magnitude
	if distance > range or distance < 1e-3 then
		return nil, math.pi
	end
	local angle = AutoAim.angleBetween(forward, offset)
	-- A big target up close fills more of the view than the cone does.
	local size = math.asin(math.clamp((candidate.radius or 2) / distance, 0, 1))
	local limit = math.max(AutoAim.cone(distance), size)
	if angle > limit then
		return nil, angle
	end
	return angle / limit + settings().DISTANCE_WEIGHT * distance / range, angle
end

-- The best target in front of `origin` looking along `forward`, or nil.
function AutoAim.pick(
	origin: Vector3,
	forward: Vector3,
	candidates: { Candidate },
	options: Options
): Candidate?
	if not settings().ASSIST or forward.Magnitude < 1e-6 then
		return nil
	end
	local ranked: { { candidate: Candidate, score: number } } = {}
	for _, candidate in candidates do
		local score = AutoAim.score(origin, forward, candidate, options.range)
		if score then
			table.insert(ranked, { candidate = candidate, score = score })
		end
	end
	table.sort(ranked, function(a, b)
		return a.score < b.score
	end)
	for _, entry in ranked do
		if not options.visible or options.visible(entry.candidate) then
			return entry.candidate
		end
	end
	return nil
end

-- Where to aim a bolt flying at `speed` (studs/s) from `origin` so it meets a
-- target at `position` moving at `velocity`. Instant spells pass speed = nil
-- and get the position back unchanged.
function AutoAim.lead(
	origin: Vector3,
	position: Vector3,
	velocity: Vector3?,
	speed: number?
): Vector3
	if not velocity or not speed or speed <= 0 then
		return position
	end
	local s = settings()
	-- Jumps come back down: only part of the vertical speed is led.
	local v = Vector3.new(velocity.X, velocity.Y * s.LEAD_VERTICAL, velocity.Z)
	local r = position - origin
	-- |r + v t| = speed * t  ->  (v.v - s^2) t^2 + 2 (r.v) t + r.r = 0
	local a = v:Dot(v) - speed * speed
	local b = 2 * r:Dot(v)
	local c = r:Dot(r)
	local t: number
	if math.abs(a) < 1e-6 then
		t = if math.abs(b) > 1e-6 then -c / b else 0
	else
		local disc = b * b - 4 * a * c
		if disc < 0 then
			t = r.Magnitude / speed -- the target outruns the bolt: aim at it
		else
			local root = math.sqrt(disc)
			local t1, t2 = (-b - root) / (2 * a), (-b + root) / (2 * a)
			t = math.huge
			for _, candidate in { t1, t2 } do
				if candidate > 0 and candidate < t then
					t = candidate
				end
			end
			if t == math.huge then
				t = r.Magnitude / speed
			end
		end
	end
	t = math.clamp(t, 0, s.MAX_LEAD_SECONDS)
	return position + v * t * s.LEAD
end

-- `direction` turned toward `desired` by at most `maxAngle` radians (both unit).
function AutoAim.steer(direction: Vector3, desired: Vector3, maxAngle: number): Vector3
	local angle = AutoAim.angleBetween(direction, desired)
	if angle <= maxAngle then
		return desired.Unit
	end
	local axis = direction:Cross(desired)
	if axis.Magnitude < 1e-6 then
		return direction -- exactly opposite: no sensible way to turn
	end
	return (CFrame.fromAxisAngle(axis.Unit, maxAngle) * direction).Unit
end

return AutoAim
