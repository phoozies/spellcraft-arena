--!strict
-- Shared UI look and small builders. Minimal and quiet: flat near-black
-- surfaces, off-white text, one warm accent, soft corners, hairlines instead of
-- outlines, and a single typeface. Colour is kept for meaning (health, rarity, a
-- spell's own colour). Every button picks its text colour from its background,
-- so any colour a caller gives it stays readable.

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.FONT = Enum.Font.BuilderSansBold
Theme.BODY_FONT = Enum.Font.BuilderSansMedium

Theme.COLORS = {
	panel = Color3.fromRGB(16, 17, 22), -- windows and surfaces
	panelLight = Color3.fromRGB(36, 38, 46), -- rows, cards, plain buttons
	accent = Color3.fromRGB(232, 200, 120), -- the one accent: primary, selected
	text = Color3.fromRGB(240, 240, 243),
	subtext = Color3.fromRGB(150, 152, 162),
	heading = Color3.fromRGB(240, 240, 243),
	onDark = Color3.fromRGB(255, 255, 255), -- text over the world or dark overlays
	ink = Color3.fromRGB(16, 17, 22), -- dark text on bright colours
	good = Color3.fromRGB(110, 200, 150),
	bad = Color3.fromRGB(224, 104, 104),
	blue = Color3.fromRGB(110, 160, 240),
	red = Color3.fromRGB(224, 104, 104),
	purple = Color3.fromRGB(165, 130, 235),
	peach = Color3.fromRGB(235, 170, 130),
	turquoise = Color3.fromRGB(100, 205, 195),
	yellow = Color3.fromRGB(235, 215, 130),
	grey = Color3.fromRGB(100, 102, 112), -- disabled
	outline = Color3.fromRGB(0, 0, 0), -- an outline in this colour is left out
	rim = Color3.fromRGB(58, 60, 70), -- the hairline around windows
}

-- Minimum touch target in pixels (before UIScale).
Theme.TOUCH = 52

local function luminance(color: Color3): number
	return 0.3 * color.R + 0.59 * color.G + 0.11 * color.B
end

-- The text colour that reads on `background`: dark ink on bright colours,
-- light text on dark ones.
function Theme.inkFor(background: Color3): Color3
	return if luminance(background) > 0.55 then Theme.COLORS.ink else Theme.COLORS.text
end

function Theme.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, math.clamp(math.floor((radius or 12) * 0.5), 4, 10))
	c.Parent = parent
end

-- A hairline, whatever thickness is asked for: thick rings (3 and up) just stay
-- a little heavier, so a colour reads. In COLORS.outline it is invisible, until a
-- caller colours it (a selected card).
function Theme.stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local function fit()
		local thin = if s.Thickness >= 3 then 1.5 else math.min(s.Thickness, 1)
		if s.Thickness ~= thin then
			s.Thickness = thin
		end
		s.Transparency = if s.Color == Theme.COLORS.outline then 1 else 0
	end
	s.Color = color or Theme.COLORS.outline
	s.Thickness = thickness or 1
	fit()
	s:GetPropertyChangedSignal("Color"):Connect(fit)
	s:GetPropertyChangedSignal("Thickness"):Connect(fit)
	s.Parent = parent
	return s
end

function Theme.padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

-- A small rounded pill (a tag such as a rarity or a price).
function Theme.pill(
	parent: Instance,
	text: string,
	color: Color3,
	props: { [string]: any }?
): TextLabel
	local pill = Instance.new("TextLabel")
	pill.Name = "Pill"
	pill.BackgroundColor3 = color
	pill.BorderSizePixel = 0
	pill.Font = Theme.FONT
	pill.TextScaled = true
	pill.Text = text
	pill.TextColor3 = Theme.inkFor(color)
	pill.Size = UDim2.fromOffset(90, 24)
	for key, value in props or {} do
		(pill :: any)[key] = value
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = pill
	pill.Parent = parent
	return pill
end

function Theme.frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Theme.COLORS.panel
	f.BorderSizePixel = 0
	for key, value in props do
		(f :: any)[key] = value
	end
	f.Parent = parent
	return f
end

function Theme.label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Theme.FONT
	l.TextColor3 = Theme.COLORS.text
	l.TextStrokeColor3 = Theme.COLORS.outline
	l.TextStrokeTransparency = 1
	l.TextScaled = true
	l.Text = text
	l.Size = UDim2.fromScale(1, 1)
	for key, value in props or {} do
		(l :: any)[key] = value
	end
	-- Plain ink on a bright surface (a pill or band) turns dark so it stays
	-- readable; deliberate colours (rarity tints) stay.
	if
		(l.TextColor3 == Theme.COLORS.text or l.TextColor3 == Theme.COLORS.subtext)
		and parent:IsA("GuiObject")
		and parent.BackgroundTransparency < 0.5
		and luminance(parent.BackgroundColor3) > 0.55
	then
		l.TextColor3 = Theme.COLORS.ink
	end
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 24
	limit.MinTextSize = 10
	limit.Parent = l
	l.Parent = parent
	return l
end

-- The visible text lives in a child label, so it keeps its own size cap and
-- padding; the button's text properties are mirrored into it, so callers keep
-- using `button.Text` and friends as usual.
local MIRRORED = {
	"Text",
	"TextColor3",
	"TextSize",
	"TextScaled",
	"TextWrapped",
	"Font",
	"RichText",
	"TextXAlignment",
	"TextYAlignment",
	"LineHeight",
}

local function addFace(button: TextButton)
	local face = Instance.new("TextLabel")
	face.Name = "Face"
	face.BackgroundTransparency = 1
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.new(1, -12, 1, -12)
	face.Active = false
	face.TextStrokeColor3 = Theme.COLORS.outline
	face.TextStrokeTransparency = 1
	for _, prop in MIRRORED do
		(face :: any)[prop] = (button :: any)[prop]
		button:GetPropertyChangedSignal(prop):Connect(function()
			(face :: any)[prop] = (button :: any)[prop]
		end)
	end
	-- Readable on any colour: the text follows the background (a caller can
	-- opt out with the KeepTextColor attribute).
	local function contrast()
		if not button:GetAttribute("KeepTextColor") then
			face.TextColor3 = Theme.inkFor(button.BackgroundColor3)
		end
	end
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(contrast)
	button:GetPropertyChangedSignal("TextColor3"):Connect(contrast)
	contrast()
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.MinTextSize = 8
	limit.Parent = face
	button.TextTransparency = 1
	button.TextStrokeTransparency = 1
	face.Parent = button
end

function Theme.button(parent: Instance, text: string, props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = Theme.COLORS.panelLight
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Theme.FONT
	b.TextColor3 = Theme.COLORS.text
	b.TextScaled = true
	b.Text = text
	b.Selectable = true
	for key, value in props or {} do
		(b :: any)[key] = value
	end
	Theme.corner(b)
	Theme.stroke(b)
	addFace(b)
	Theme.juice(b)
	b.Parent = parent
	return b
end

-- A press gives a small, quick give (ignored while the button is inactive).
local PRESS = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Theme.juice(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Name = "Juice"
	scale.Parent = button
	local function to(value: number)
		-- A caller that animates the button with its own UIScale wins.
		for _, child in button:GetChildren() do
			if child:IsA("UIScale") and child ~= scale then
				scale.Scale = 1
				return
			end
		end
		TweenService:Create(scale, PRESS, { Scale = value }):Play()
	end
	button.MouseButton1Down:Connect(function()
		if button.Active then
			to(0.97)
		end
	end)
	button.MouseButton1Up:Connect(function()
		to(1)
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
end

return Theme
