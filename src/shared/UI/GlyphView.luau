--!strict
-- Draws a glyph (shared/Spells/Glyphs) as a line on screen: the spell cards'
-- icons, the spellbook's "how to draw it" picture, the hub's glyph stones,
-- and the player's own stroke while drawing. Used by client and server. A line is a chain of thin rotated Frames, so it
-- needs no uploaded images.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Glyphs = require(ReplicatedStorage.Shared.Spells.Glyphs)

local GlyphView = {}

local MAX_SEGMENTS = 40

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

-- A square frame of `size` pixels showing the glyph. Returns the frame, or
-- nil for an unknown glyph id.
function GlyphView.create(
	parent: Instance,
	glyphId: string,
	size: number,
	color: Color3,
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
	local step = math.max(1, math.ceil(#glyph.points / MAX_SEGMENTS))
	local inset = size * 0.14
	local span = size - inset * 2
	local previous: Vector2? = nil
	for i = 1, #glyph.points, step do
		local p = glyph.points[i]
		local point = Vector2.new(inset + p.X * span, inset + p.Y * span)
		if previous then
			GlyphView.segment(holder, previous, point, math.max(2, size * 0.07), color)
		end
		previous = point
	end
	-- Always finish on the glyph's last point.
	local last = glyph.points[#glyph.points]
	local lastPoint = Vector2.new(inset + last.X * span, inset + last.Y * span)
	if previous and (previous - lastPoint).Magnitude > 0.5 then
		GlyphView.segment(holder, previous, lastPoint, math.max(2, size * 0.07), color)
	end
	holder.Parent = parent
	return holder
end

return GlyphView
