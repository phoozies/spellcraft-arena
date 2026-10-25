--!strict
-- Shared UI look and small builders: the classic studded-Roblox style in a
-- pastel palette. Pastel panels and buttons with a faint grid of studs, a
-- lighter top edge and slightly darker bottom edge (a bevel), small square-ish
-- corners, thick near-black borders, bold dark ink text, and yellow / green /
-- red for primary / go / stop. Dark text on pastel is 7.5:1 or better, so it
-- reads well for all ages and on small phone screens. Text over the world or a
-- dark overlay uses COLORS.onDark (white) with a dark stroke instead.
--
-- Studs are one tiled image (assets/ui/studs.png, made by
-- tools/make-stud-texture.py) laid over any opaque panel or button; they hide
-- themselves on small, see-through, or dark frames (health bars, overlays).
-- If the image can't load the UI is simply flat pastel.

local Theme = {}

Theme.FONT = Enum.Font.FredokaOne
Theme.BODY_FONT = Enum.Font.GothamMedium

-- Uploaded stud tile (a single white/black-shaded stud on transparent).
Theme.STUD_IMAGE = "rbxassetid://111722228846947"
-- Size of one stud on screen, in pixels (before UIScale).
Theme.STUD_SIZE = 22

Theme.COLORS = {
	-- Pastel palette (all take dark text: 7.5:1 to 19:1 against black).
	panel = Color3.fromRGB(219, 225, 241), -- Blue Grey #DBE1F1: panels, disabled buttons
	panelLight = Color3.fromRGB(150, 173, 252), -- Blue #96ADFC: buttons, rows, cards
	accent = Color3.fromRGB(237, 221, 110), -- Orange #EDDD6E: primary buttons, highlights, selected
	text = Color3.fromRGB(24, 24, 36), -- ink: all text on pastel panels
	subtext = Color3.fromRGB(50, 58, 84), -- dark slate: secondary text on pastel
	heading = Color3.fromRGB(72, 44, 128), -- deep purple: titles on pastel
	onDark = Color3.fromRGB(255, 255, 255), -- text over the world or dark overlays
	good = Color3.fromRGB(168, 242, 154), -- Green #A8F29A
	bad = Color3.fromRGB(224, 166, 170), -- Red #E0A6AA
	blue = Color3.fromRGB(150, 173, 252),
	red = Color3.fromRGB(224, 166, 170),
	purple = Color3.fromRGB(185, 135, 220), -- Purple #B987DC
	peach = Color3.fromRGB(237, 209, 176), -- Peach #EDD1B0
	turquoise = Color3.fromRGB(165, 247, 225), -- Turquoise #A5F7E1
	yellow = Color3.fromRGB(248, 253, 137), -- Yellow #F8FD89
	grey = Color3.fromRGB(216, 211, 214), -- Grey #D8D3D6
	outline = Color3.fromRGB(20, 20, 28), -- thick near-black borders
}

-- Minimum touch target in pixels (before UIScale).
Theme.TOUCH = 52

local function luminance(color: Color3): number
	return 0.3 * color.R + 0.59 * color.G + 0.11 * color.B
end

-- Rounded corners, kept small so panels stay blocky.
function Theme.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, math.clamp(math.floor((radius or 12) * 0.5), 4, 10))
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

function Theme.padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

-- A lighter top and darker bottom edge on a panel or button.
function Theme.bevel(target: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Bevel"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(247, 248, 252)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 220, 236)),
	})
	gradient.Parent = target
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
	Theme.stroke(b, Theme.COLORS.outline, 3)
	addFace(b)
	b.Parent = parent
	return b
end

return Theme
