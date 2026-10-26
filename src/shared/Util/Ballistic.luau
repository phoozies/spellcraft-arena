--!strict
-- Launch velocities for arcs under gravity, used by the water and pit rescues
-- to throw a player to a landing spot. Pure math so tests can check it.

local Ballistic = {}

-- The velocity that carries a body from `from` to `to`, peaking `apexAbove`
-- studs above the higher of the two points. Also returns the flight time.
function Ballistic.velocity(
	from: Vector3,
	to: Vector3,
	apexAbove: number,
	gravity: number
): (Vector3, number)
	local apexY = math.max(from.Y, to.Y) + math.max(apexAbove, 0.1)
	local up = math.sqrt(2 * gravity * (apexY - from.Y))
	local rise = up / gravity
	local fall = math.sqrt(2 * (apexY - to.Y) / gravity)
	local time = rise + fall
	return Vector3.new((to.X - from.X) / time, up, (to.Z - from.Z) / time), time
end

-- Height of the body `t` seconds after launch.
function Ballistic.heightAt(startY: number, velocityY: number, gravity: number, t: number): number
	return startY + velocityY * t - 0.5 * gravity * t * t
end

-- How high a jump of `jumpPower` (studs per second) lifts a body.
function Ballistic.jumpHeight(jumpPower: number, gravity: number): number
	return jumpPower * jumpPower / (2 * gravity)
end

return Ballistic
