--!strict
-- Shared UI look and small builders. Bright, rounded, high-contrast text
-- that reads well for all ages and on small phone screens.

local Theme = {}

Theme.FONT = Enum.Font.FredokaOne
Theme.BODY_FONT = Enum.Font.GothamMedium

Theme.COLORS = {
	panel = Color3.fromRGB(33, 33, 58),
	panelLight = Color3.fromRGB(57, 55, 98),
	accent = Color3.fromRGB(255, 202, 40),
	text = Color3.fromRGB(255, 255, 255),
	subtext = Color3.fromRGB(197, 202, 233),
	good = Color3.fromRGB(102, 187, 106),
	bad = Color3.fromRGB(239, 83, 80),
	blue = Color3.fromRGB(66, 165, 245),
	red = Color3.fromRGB(239, 83, 80),
}

-- Minimum touch target in pixels (before UIScale).
Theme.TOUCH = 52

function Theme.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
end

function Theme.stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
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
	Theme.stroke(b, Color3.fromRGB(20, 20, 40), 2)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 28
	limit.Parent = b
	b.Parent = parent
	return b
end

return Theme
