--!strict
-- Wand geometry, shared by the server (WandService welds the wand) and the
-- client (Fx/WandVfx draws spells in the air with it). Pure math, so tests
-- can check it:
--   grip       where the wand sits in the right hand
--   frame      the "air canvas" in front of a character where a drawing shows
--   fromScreen a point of the on-screen stroke -> studs on the air canvas
--   fromGlyph  a point of a glyph shape (Spells/Glyphs, 0..1 box) -> studs

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

return WandAir
