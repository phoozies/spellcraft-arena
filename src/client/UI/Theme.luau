--!strict
-- Shared UI look and small builders: "spellbook at night". Deep indigo
-- panels with a soft top-lit gradient, gold headings and accents, white ink,
-- rounded corners, a thin glowing rim, and bright gem-coloured buttons (gold /
-- green / red for primary / go / stop) that lift when hovered and squash when
-- pressed. Every button picks its own text colour from its background (dark
-- ink on bright gems, white on indigo), so any colour a caller gives it stays
-- readable (4.5:1 or better), for all ages and on small phone screens.
--
-- Studs are one tiled image (assets/ui/studs.png, made by
-- tools/make-stud-texture.py) laid over bright panels and buttons; they hide
-- themselves on small, see-through, or dark frames, so the indigo panels are
-- smooth and the gem buttons keep a faint classic-Roblox texture.

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.FONT = Enum.Font.FredokaOne
Theme.BODY_FONT = Enum.Font.BuilderSansBold

-- Uploaded stud tile (a single white/black-shaded stud on transparent).
Theme.STUD_IMAGE = "rbxassetid://111722228846947"
-- Size of one stud on screen, in pixels (before UIScale).
Theme.STUD_SIZE = 22

Theme.COLORS = {
	-- Night palette: indigo surfaces take white text (11:1 or better); the
	-- bright gem colours take dark ink (buttons pick automatically).
	panel = Color3.fromRGB(32, 28, 64), -- deep indigo: panels, windows
	panelLight = Color3.fromRGB(58, 52, 112), -- lifted indigo: rows, cards, plain buttons
	accent = Color3.fromRGB(255, 200, 64), -- gold: primary buttons, highlights, selected
	text = Color3.fromRGB(246, 244, 255), -- ink on indigo
	subtext = Color3.fromRGB(190, 184, 228), -- soft lavender: secondary text
	heading = Color3.fromRGB(255, 214, 110), -- gold titles
	onDark = Color3.fromRGB(255, 255, 255), -- text over the world or dark overlays
	ink = Color3.fromRGB(22, 18, 40), -- dark text on bright gem colours
	good = Color3.fromRGB(92, 220, 140), -- emerald
	bad = Color3.fromRGB(242, 104, 116), -- ruby
	blue = Color3.fromRGB(96, 152, 255), -- sapphire
	red = Color3.fromRGB(242, 104, 116),
	purple = Color3.fromRGB(176, 118, 255), -- amethyst
	peach = Color3.fromRGB(255, 176, 128),
	turquoise = Color3.fromRGB(72, 226, 210),
	yellow = Color3.fromRGB(255, 232, 96),
	grey = Color3.fromRGB(122, 118, 156), -- disabled
	outline = Color3.fromRGB(12, 10, 26), -- near-black edges
	rim = Color3.fromRGB(122, 108, 214), -- the thin glowing rim on panels
}

-- Minimum touch target in pixels (before UIScale).
Theme.TOUCH = 52

local function luminance(color: Color3): number
	return 0.3 * color.R + 0.59 * color.G + 0.11 * color.B
end

-- The text colour that reads on `background`: dark ink on bright colours,
-- white on dark ones.
function Theme.inkFor(background: Color3): Color3
	return if luminance(background) > 0.55 then Theme.COLORS.ink else Theme.COLORS.text
end

-- Rounded corners, soft but not bubbly.
function Theme.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, math.clamp(math.floor((radius or 12) * 0.75), 6, 16))
	c.Parent = parent
	-- Studs follow the panel's shape.
	local studs = parent:FindFirstChild("Studs")
	if studs then
		local clone = c:Clone()
		clone.Parent = studs
	end
end

function Theme.stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.COLORS.outline
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- A dark outer edge around a card whose own stroke is a bright colour (a
-- rarity ring): the ring then reads on any background. `gap` is the ring's
-- thickness in pixels; callers keep the card's UIStroke at that thickness or
-- a little more. Make sure the parent has `gap + 2` pixels of room around the
-- card, or the edge is clipped.
function Theme.rim(target: GuiObject, gap: number, radius: number?): Frame
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.BackgroundTransparency = 1
	rim.BorderSizePixel = 0
	rim.Active = false
	rim.Position = UDim2.fromOffset(-gap, -gap)
	rim.Size = UDim2.new(1, gap * 2, 1, gap * 2)
	rim.ZIndex = target.ZIndex
	Theme.corner(rim, (radius or 12) + gap * 2)
	Theme.stroke(rim, Theme.COLORS.outline, 2)
	rim.Parent = target
	return rim
end

function Theme.padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

-- Lit from above: the top of a panel or button is its full colour and the
-- bottom sinks into shadow, so flat colour reads as a raised surface.
function Theme.bevel(target: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Bevel"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(236, 234, 248)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(176, 170, 206)),
	})
	gradient.Parent = target
end

-- A soft drop shadow under a window or card (a blurred dark frame behind it).
function Theme.shadow(target: GuiObject, spread: number?): Frame
	local px = spread or 10
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.Active = false
	shadow.AnchorPoint = target.AnchorPoint
	shadow.Position = target.Position + UDim2.fromOffset(0, px * 0.6)
	shadow.Size = target.Size + UDim2.fromOffset(px, px)
	shadow.ZIndex = math.max(target.ZIndex - 1, 0)
	shadow.Visible = target.Visible
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = shadow
	local function follow()
		shadow.Position = target.Position + UDim2.fromOffset(0, px * 0.6)
		shadow.Size = target.Size + UDim2.fromOffset(px, px)
		shadow.Visible = target.Visible
	end
	target:GetPropertyChangedSignal("Position"):Connect(follow)
	target:GetPropertyChangedSignal("Size"):Connect(follow)
	target:GetPropertyChangedSignal("Visible"):Connect(follow)
	shadow.Parent = target.Parent
	return shadow
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

-- Lays the stud pattern over a panel or button. It shows only while the object
-- is opaque enough, big enough, and bright enough for studs to look right.
function Theme.studs(target: GuiObject, tile: number?): ImageLabel?
	if Theme.STUD_IMAGE == "" then
		return nil
	end
	local studs = Instance.new("ImageLabel")
	studs.Name = "Studs"
	studs.BackgroundTransparency = 1
	studs.BorderSizePixel = 0
	studs.Size = UDim2.fromScale(1, 1)
	studs.Image = Theme.STUD_IMAGE
	studs.ScaleType = Enum.ScaleType.Tile
	studs.TileSize = UDim2.fromOffset(tile or Theme.STUD_SIZE, tile or Theme.STUD_SIZE)
	studs.ImageTransparency = 0.55 -- faint on pastel so text stays crisp
	studs.Active = false
	studs.Selectable = false
	studs.Visible = false
	studs.Parent = target

	local function refresh()
		local size = target.AbsoluteSize
		studs.Visible = target.BackgroundTransparency <= 0.6
			and size.X >= 56
			and size.Y >= 28
			and luminance(target.BackgroundColor3) > 0.18
	end
	target:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	target:GetPropertyChangedSignal("BackgroundTransparency"):Connect(refresh)
	target:GetPropertyChangedSignal("BackgroundColor3"):Connect(refresh)
	refresh()
	return studs
end

function Theme.frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Theme.COLORS.panel
	f.BorderSizePixel = 0
	for key, value in props do
		(f :: any)[key] = value
	end
	Theme.bevel(f)
	Theme.studs(f)
	f.Parent = parent
	return f
end

function Theme.label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Theme.FONT
	l.TextColor3 = Theme.COLORS.text
	l.TextStrokeColor3 = Theme.COLORS.outline
	l.TextStrokeTransparency = 1 -- dark ink on pastel needs no outline
	l.TextScaled = true
	l.Text = text
	l.Size = UDim2.fromScale(1, 1)
	for key, value in props or {} do
		(l :: any)[key] = value
	end
	-- Plain ink on a bright surface (a gem-coloured pill or band) turns dark so
	-- it stays readable; deliberate colours (gold headings, rarity tints) stay.
	if
		(l.TextColor3 == Theme.COLORS.text or l.TextColor3 == Theme.COLORS.subtext)
		and parent:IsA("GuiObject")
		and parent.BackgroundTransparency < 0.5
		and luminance(parent.BackgroundColor3) > 0.55
	then
		l.TextColor3 = Theme.COLORS.ink
	end
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 32
	limit.MinTextSize = 10
	limit.Parent = l
	l.Parent = parent
	return l
end

-- The button's own text would draw under its studs, so the visible text lives
-- in a child label above them. The button's text properties are mirrored into
-- it, so callers keep using `button.Text` and friends as usual.
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
	face.Size = UDim2.new(1, -10, 1, -6)
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
	limit.MaxTextSize = 28
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
	Theme.bevel(b)
	Theme.studs(b, 18)
	Theme.corner(b)
	Theme.stroke(b, Theme.COLORS.outline, 2)
	addFace(b)
	Theme.juice(b)
	b.Parent = parent
	return b
end

-- Hover lifts a button a little and a press squashes it (ignored while the
-- button is inactive).
local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Theme.juice(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Name = "Juice"
	scale.Parent = button
	local hovered = false
	local function to(value: number, info: TweenInfo)
		-- A caller that animates the button with its own UIScale wins.
		for _, child in button:GetChildren() do
			if child:IsA("UIScale") and child ~= scale then
				scale.Scale = 1
				return
			end
		end
		TweenService:Create(scale, info, { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		hovered = true
		if button.Active then
			to(1.05, HOVER)
		end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		to(1, HOVER)
	end)
	button.MouseButton1Down:Connect(function()
		if button.Active then
			to(0.94, PRESS)
		end
	end)
	button.MouseButton1Up:Connect(function()
		to(if hovered then 1.05 else 1, HOVER)
	end)
end

return Theme
