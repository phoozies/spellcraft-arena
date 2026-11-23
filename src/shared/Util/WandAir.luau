--!strict
-- Wand geometry, shared by the server (WandService welds the wand) and the
-- client (Fx/WandVfx draws spells in the air with it). Pure math, so tests
-- can check it:
--   grip       where the wand sits in the right hand
--   frame      the "air canvas" in front of a character where a drawing shows
--   facing     that canvas standing upright, facing where the drawer looks
--   cleanLook / cleanPoints   validate relayed drawing data (WandService)
--   fromScreen a point of the on-screen stroke -> studs on the air canvas
--   fromGlyph  a point of a glyph shape (Spells/Glyphs, 0..1 box) -> studs
--   viewTip    where your first-person wand's tip goes to sit on the pen

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WandAir = {}

-- The on-screen guide spans about this share of the screen height, so a stroke
-- that size fills the air canvas (Config.WAND.AIR_SIZE).
WandAir.SCREEN_SPAN = 0.8
-- Where the on-screen guide is centred (fractions of the viewport).
WandAir.SCREEN_CENTER = Vector2.new(0.5, 0.56)

-- The wand's pivot relative to the hand part. The wand's forward (-Z) runs down
-- the forearm's line (the hand's -Y), tipped Config.WAND.TILT degrees towards
-- the palm's front so it reads as held, not hanging.
function WandAir.grip(isR15: boolean, handSize: Vector3): CFrame
	-- R15's RightHand is the fist; R6's "Right Arm" is the whole arm, so its
	-- grip sits near the bottom.
	local down = if isR15 then handSize.Y * 0.15 else handSize.Y * 0.42
	return CFrame.new(0, -down, 0) * CFrame.Angles(math.rad(-90 + Config.WAND.TILT), 0, 0)
end

-- The air canvas for a character whose root part is at `root`: centred
-- AIR_DISTANCE studs ahead along `look` (flattened) and AIR_HEIGHT above the
-- root, with its right and up axes taken from `right` and `up` (the camera's
-- for your own drawing, the character's for everyone else's).
function WandAir.frame(root: Vector3, look: Vector3, right: Vector3, up: Vector3): CFrame
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local center = root
		+ Vector3.new(0, Config.WAND.AIR_HEIGHT, 0)
		+ flat * Config.WAND.AIR_DISTANCE
	local r = if right.Magnitude > 1e-3 then right.Unit else Vector3.new(1, 0, 0)
	local u = if up.Magnitude > 1e-3 then up.Unit else Vector3.yAxis
	return CFrame.fromMatrix(center, r, u)
end

-- The upright air canvas (and magic circle) of a player drawing while facing
-- `look`: the same for the drawer and everyone watching, so a stroke relayed
-- as canvas studs lands in the same place on every screen.
function WandAir.facing(root: Vector3, look: Vector3): CFrame
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	return WandAir.frame(root, flat, flat:Cross(Vector3.yAxis), Vector3.yAxis)
end

-- A facing direction from the network: a finite Vector3 with some horizontal
-- length, returned flattened to a unit vector, or nil.
function WandAir.cleanLook(raw: any): Vector3?
	if typeof(raw) ~= "Vector3" then
		return nil
	end
	local flat = Vector3.new(raw.X, 0, raw.Z)
	local length = flat.Magnitude
	if length ~= length or length == math.huge or length < 1e-3 then
		return nil
	end
	return flat / length
end

-- A batch of air-canvas points from the network (1 to `max` finite Vector2s
-- inside the canvas's clamp), or nil.
function WandAir.cleanPoints(raw: any, max: number): { Vector2 }?
	if typeof(raw) ~= "table" or #raw < 1 or #raw > max then
		return nil
	end
	local limit = Config.WAND.AIR_SIZE * 0.75 + 1e-3
	local points: { Vector2 } = {}
	for i = 1, #raw do
		local p = raw[i]
		if typeof(p) ~= "Vector2" or p.X ~= p.X or p.Y ~= p.Y then
			return nil
		end
		if math.abs(p.X) > limit or math.abs(p.Y) > limit then
			return nil
		end
		points[i] = p
	end
	return points
end

-- A stroke point in screen pixels -> (right, up) studs on the air canvas.
-- Points far off the guide are clamped to the canvas edge.
function WandAir.fromScreen(point: Vector2, viewport: Vector2): Vector2
	local height = math.max(viewport.Y, 1)
	local center =
		Vector2.new(viewport.X * WandAir.SCREEN_CENTER.X, height * WandAir.SCREEN_CENTER.Y)
	local scale = Config.WAND.AIR_SIZE / WandAir.SCREEN_SPAN
	local offset = (point - center) / height * scale
	local limit = Config.WAND.AIR_SIZE * 0.75
	return Vector2.new(math.clamp(offset.X, -limit, limit), math.clamp(-offset.Y, -limit, limit))
end

-- A glyph point (0..1 box, y down) -> (right, up) studs on the air canvas.
function WandAir.fromGlyph(point: Vector2): Vector2
	local size = Config.WAND.AIR_SIZE
	return Vector2.new((point.X - 0.5) * size, -(point.Y - 0.5) * size)
end

-- Canvas studs -> a world position on `frame`.
function WandAir.toWorld(frame: CFrame, offset: Vector2): Vector3
	return frame.Position + frame.RightVector * offset.X + frame.UpVector * offset.Y
end

-- Your first-person wand (Fx/WandView): the point on the ray from `origin`
-- along `direction` (the pen's pixel) that is `length` studs from the grip, so
-- the tip of a wand held at `grip` sits right under the pen. Nil when the ray
-- passes out of reach.
function WandAir.viewTip(
	origin: Vector3,
	direction: Vector3,
	grip: Vector3,
	length: number
): Vector3?
	local d = direction.Unit
	local o = origin - grip
	-- |o + t*d| = length, the farther root.
	local b = o:Dot(d)
	local c = o:Dot(o) - length * length
	local disc = b * b - c
	if disc < 0 then
		return nil
	end
	local t = -b + math.sqrt(disc)
	return if t > 0 then origin + d * t else nil
end

return WandAir
