--!strict
-- A spell's sigil: its shape in glowing ink inside a little night-sky magic
-- circle (a ring in the spell's colour, rune stones, a faint inner ring). It
-- is the drawing canvas's look carried to every place a spell is shown: spell
-- cards (Spellbook, chest), the HUD's spell cards, the Spellbook's big picture, and the canvas banner, so a spell
-- always looks like the magic you draw.
--
--   Sigil.create(parent, glyphId, size, color, props?) -> Frame
--   Sigil.blank(parent, size, color, text, props?) -> Frame
--     the same circle with a symbol instead of a shape ("?" for a spell not
--     won yet)
--   Sigil.setSpinning(sigil, on)
--     its rune ring turns (the card being traced,
--     the Spellbook's picture); one RenderStepped turns every spinning ring
--
-- The ink is opaque and blended into the circle's own colour
-- (GlyphView.glow), so it glows without see-through layers. Its layers are
-- stacked with sibling ZIndex, so it needs a ScreenGui with
-- ZIndexBehavior Sibling (every game ScreenGui uses it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GlyphView = require(ReplicatedStorage.Shared.UI.GlyphView)
local Theme = require(script.Parent.Theme)

local Sigil = {}

-- The night inside the circle (the canvas's vignette colour, a little lighter).
Sigil.NIGHT = Color3.fromRGB(30, 20, 62)
local WHITE = Color3.new(1, 1, 1)
local STONES = 8
-- Degrees a second a spinning ring turns.
local SPIN_SPEED = 40

local spinning: { [Frame]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local spinConnection: RBXScriptConnection? = nil

local function round(target: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = target
end

-- The circle without what's inside it: a dark rim, the night disc ringed in
-- `color`, and the rune ring (stones and a faint inner ring) that can spin.
local function base(parent: Instance, size: number, color: Color3, props: { [string]: any }?): Frame
	local ring = math.max(2, math.floor(size * 0.055 + 0.5))
	local holder = Instance.new("Frame")
	holder.Name = "Sigil"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	for key, value in props or {} do
		(holder :: any)[key] = value
	end

	-- A dark edge outside the coloured ring, so pale colours read on pastel.
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.fromScale(0.5, 0.5)
	edge.Size = UDim2.new(1, ring * 2 + 2, 1, ring * 2 + 2)
	edge.BackgroundColor3 = Theme.COLORS.outline
	edge.BorderSizePixel = 0
	edge.ZIndex = 1
	edge.Parent = holder
	round(edge)

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.new(1, ring * 2, 1, ring * 2)
	disc.BackgroundColor3 = color
	disc.BorderSizePixel = 0
	disc.ZIndex = 2
	disc.Parent = holder
	round(disc)

	local night = Instance.new("Frame")
	night.Name = "Night"
	night.AnchorPoint = Vector2.new(0.5, 0.5)
	night.Position = UDim2.fromScale(0.5, 0.5)
	night.Size = UDim2.fromScale(1, 1)
	night.BackgroundColor3 = Sigil.NIGHT
	night.BorderSizePixel = 0
	night.ZIndex = 3
	night.Parent = holder
	round(night)
	-- A soft lift of the spell's colour at the top, like light on glass.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1):Lerp(color, 0.25)),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	gradient.Parent = night

	local runes = Instance.new("Frame")
	runes.Name = "Runes"
	runes.AnchorPoint = Vector2.new(0.5, 0.5)
	runes.Position = UDim2.fromScale(0.5, 0.5)
	runes.Size = UDim2.fromScale(1, 1)
	runes.BackgroundTransparency = 1
	runes.ZIndex = 4
	runes.Parent = holder
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.8, 0.8)
	inner.BackgroundTransparency = 1
	inner.Parent = runes
	round(inner)
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = color:Lerp(Sigil.NIGHT, 0.45)
	innerStroke.Thickness = math.max(1, size * 0.02)
	innerStroke.Parent = inner
	local stone = math.max(3, size * 0.075)
	for i = 0, STONES - 1 do
		local angle = i / STONES * math.pi * 2
		local dot = Instance.new("Frame")
		dot.Name = "Stone"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.45, 0.5 - math.cos(angle) * 0.45)
		dot.Size = UDim2.fromOffset(stone, stone)
		dot.Rotation = 45
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = color:Lerp(if i % 2 == 0 then WHITE else Sigil.NIGHT, 0.35)
		dot.Parent = runes
	end

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
	local holder = base(parent, size, color, props)
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
	local holder = base(parent, size, color, props)
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

function Sigil.setSpinning(sigil: Frame, on: boolean)
	local runes = sigil:FindFirstChild("Runes")
	if not runes or not runes:IsA("Frame") then
		return
	end
	spinning[runes] = if on then true else nil
	if not on then
		runes.Rotation = 0
	end
	if on and not spinConnection then
		spinConnection = RunService.RenderStepped:Connect(function(dt)
			for frame in spinning do
				if frame.Parent then
					frame.Rotation = (frame.Rotation + dt * SPIN_SPEED) % 360
				else
					spinning[frame] = nil
				end
			end
		end)
	end
end

return Sigil
