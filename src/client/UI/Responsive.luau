--!strict
-- One rule for how big the UI is on every screen, from a phone held upright
-- to a TV. UI is designed at 1280x720; a UIScale shrinks or grows it:
--   * phones and other short screens (short side under 600px) are designed at
--     a smaller 960x540 so text and buttons stay big enough to read and tap;
--   * the scale is capped so a 700x470 area always fits, which keeps every
--     menu panel (the widest is 660x440) fully on screen in portrait too;
--   * touch screens get a little extra size for fingers.
-- Controllers call Responsive.bind(uiScale) once; it follows the viewport.

local UserInputService = game:GetService("UserInputService")

local Responsive = {}

local DESIGN = Vector2.new(1280, 720)
local COMPACT_DESIGN = Vector2.new(960, 540)
local COMPACT_BELOW = 600
-- The area every full-screen panel must fit inside (design pixels).
local PANEL_FIT = Vector2.new(700, 470)
local MIN_SCALE = 0.45
local MAX_SCALE = 1.4

function Responsive.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- A phone-sized viewport (either orientation).
function Responsive.isCompact(size: Vector2): boolean
	return math.min(size.X, size.Y) < COMPACT_BELOW
end

function Responsive.scaleFor(size: Vector2, touch: boolean): number
	local design = if Responsive.isCompact(size) then COMPACT_DESIGN else DESIGN
	local scale = math.min(size.X / design.X, size.Y / design.Y)
	if touch then
		scale *= 1.05
	end
	scale = math.min(scale, size.X / PANEL_FIT.X, size.Y / PANEL_FIT.Y)
	return math.clamp(scale, MIN_SCALE, MAX_SCALE)
end

-- Keeps `scale` (a UIScale) matched to the screen. Returns the connection.
function Responsive.bind(scale: UIScale): RBXScriptConnection?
	local function update()
		local camera = workspace.CurrentCamera
		if camera then
			scale.Scale = Responsive.scaleFor(camera.ViewportSize, Responsive.isTouch())
		end
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		return camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return nil
end

return Responsive
