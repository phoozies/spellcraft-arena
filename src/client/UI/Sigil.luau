--!strict
-- A spell's sigil: its shape in its colour on a small dark disc, the one way a
-- spell is shown everywhere: spell cards (Spellbook, chest), the HUD's spell
-- row, the Spellbook's big picture.
--
--   Sigil.create(parent, glyphId, size, color, props?) -> Frame
--   Sigil.blank(parent, size, color, text, props?) -> Frame
--     the same disc with a symbol instead of a shape ("?" for a spell not won
--     yet)
--
-- The ink is opaque and blended into the disc's colour (GlyphView.glow). Its
-- layers are stacked with sibling ZIndex, so it needs a ScreenGui with
-- ZIndexBehavior Sibling (every game ScreenGui uses it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GlyphView = require(ReplicatedStorage.Shared.UI.GlyphView)
local Theme = require(script.Parent.Theme)

local Sigil = {}

Sigil.NIGHT = Color3.fromRGB(24, 25, 32)
local WHITE = Color3.new(1, 1, 1)

-- The disc a shape sits on.
local function base(parent: Instance, size: number, props: { [string]: any }?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Sigil"
	holder.BackgroundColor3 = Sigil.NIGHT
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(size, size)
	for key, value in props or {} do
		(holder :: any)[key] = value
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = holder
	holder.Parent = parent
	return holder
end

function Sigil.create(
	parent: Instance,
	glyphId: string,
	size: number,
	color: Color3,
	props: { [string]: any }?
): Frame
	local holder = base(parent, size, props)
	local inside = math.floor(size * 0.84)
	GlyphView.glow(holder, glyphId, inside, color, Sigil.NIGHT, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 5,
	})
	return holder
end

function Sigil.blank(
	parent: Instance,
	size: number,
	color: Color3,
	text: string,
	props: { [string]: any }?
): Frame
	local holder = base(parent, size, props)
	Theme.label(holder, text, {
		Name = "Symbol",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6),
		TextColor3 = color:Lerp(WHITE, 0.4),
		ZIndex = 5,
	})
	return holder
end

return Sigil
