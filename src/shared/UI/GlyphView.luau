--!strict
-- Draws a glyph (shared/Spells/Glyphs) as a line on screen: the spell cards'
-- icons, the spellbook's "how to draw it" picture, the hub's glyph stones,
-- and the player's own stroke while drawing. Used by client and server. A line is a chain of thin rotated Frames, so it
-- needs no uploaded images. create() draws an outlined line for pastel
-- panels; glow() draws glowing ink (the drawing canvas's look) for the dark
-- spell sigils (client UI/Sigil) and the hub's shrines.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Glyphs = require(ReplicatedStorage.Shared.Spells.Glyphs)

local GlyphView = {}

local MAX_SEGMENTS = 40
local OUTLINE = Color3.fromRGB(20, 20, 28)

-- One straight piece of line between two pixel points.
function GlyphView.segment(
	parent: Instance,
	from: Vector2,
	to: Vector2,
	thickness: number,
	color: Color3
): Frame
	local delta = to - from
	local length = delta.Magnitude
	local frame = Instance.new("Frame")
	frame.Name = "Segment"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
	-- A little extra length so joints don't show gaps.
	frame.Size = UDim2.fromOffset(length + thickness * 0.6, thickness)
	frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	return frame
end

-- The glyph's line as pixel points inside a `size` square frame, thinned to
-- at most MAX_SEGMENTS pieces and always ending on the glyph's last point.
local function pathOf(glyph: Glyphs.Glyph, size: number): { Vector2 }
	local step = math.max(1, math.ceil(#glyph.points / MAX_SEGMENTS))
	local points: { Vector2 } = {}
	for i = 1, #glyph.points, step do
		table.insert(points, GlyphView.pointAt(glyph.points[i], size))
	end
	local last = GlyphView.pointAt(glyph.points[#glyph.points], size)
	if (points[#points] - last).Magnitude > 0.5 then
		table.insert(points, last)
	end
	return points
end

-- A square frame of `size` pixels showing the glyph (line `thickness` pixels,
-- default 12% of the size: a fat, bubbly line, drawn over a dark outline so
-- any colour, even pale ones, stays readable). Returns the frame, or nil for an unknown glyph id.
-- The shape fills the middle 72% of the frame; GlyphView.pointAt maps a glyph
-- point into the frame.
function GlyphView.create(
	parent: Instance,
	glyphId: string,
	size: number,
	color: Color3,
	props: { [string]: any }?,
	thickness: number?
): Frame?
	local glyph = Glyphs.get(glyphId)
	if not glyph then
		return nil
	end
	local holder = Instance.new("Frame")
	holder.Name = "Glyph"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	for key, value in props or {} do
		(holder :: any)[key] = value
	end
	local line = thickness or math.max(3, size * 0.12)
	local border = math.max(1.5, line * 0.28)
	local points = pathOf(glyph, size)
	-- Outline pass first, then the colour on top.
	for pass = 1, 2 do
		for i = 2, #points do
			if pass == 1 then
				GlyphView.segment(holder, points[i - 1], points[i], line + border * 2, OUTLINE).Name =
					"Outline"
			else
				GlyphView.segment(holder, points[i - 1], points[i], line, color)
			end
		end
	end
	holder.Parent = parent
	return holder
end

-- The glyph as glowing ink, the look of the drawing canvas: a wide soft halo,
-- a glow, a solid core in `color`, and a white shine down the middle. Every
-- pass is opaque and the glow is `color` blended into `background` (the
-- colour behind the glyph), so it glows without see-through pieces stacking
-- into beads at the joints. Same frame and layout as create().
function GlyphView.glow(
	parent: Instance,
	glyphId: string,
	size: number,
	color: Color3,
	background: Color3,
	props: { [string]: any }?
): Frame?
	local glyph = Glyphs.get(glyphId)
	if not glyph then
		return nil
	end
	local holder = Instance.new("Frame")
	holder.Name = "Glyph"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	for key, value in props or {} do
		(holder :: any)[key] = value
	end
	local core = math.max(2.5, size * 0.085)
	local passes: { { name: string, thickness: number, color: Color3 } } = {
		{ name = "Halo", thickness = core * 3.2, color = color:Lerp(background, 0.8) },
		{ name = "Glow", thickness = core * 2, color = color:Lerp(background, 0.5) },
		{ name = "Core", thickness = core, color = color },
		{
			name = "Shine",
			thickness = math.max(1, core * 0.34),
			color = color:Lerp(Color3.new(1, 1, 1), 0.75),
		},
	}
	local points = pathOf(glyph, size)
	for _, pass in passes do
		for i = 2, #points do
			GlyphView.segment(holder, points[i - 1], points[i], pass.thickness, pass.color).Name =
				pass.name
		end
	end
	holder.Parent = parent
	return holder
end

-- Where a glyph point (0..1 box) lands inside a frame made with create().
function GlyphView.pointAt(point: Vector2, size: number): Vector2
	local inset = size * 0.14
	local span = size - inset * 2
	return Vector2.new(inset + point.X * span, inset + point.Y * span)
end

return GlyphView
