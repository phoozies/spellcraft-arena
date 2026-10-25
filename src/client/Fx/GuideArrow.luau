--!strict
-- Guiding arrows for the tutorial. Everything here is local to this player:
--
--   GuideArrow.world(target, options)  points at a place in the world:
--     * a bobbing arrow (and label) hovering over it, seen through walls,
--     * a glowing outline on the thing itself (options.highlight),
--     * a trail of chevrons on the ground that flows from the player toward it,
--     * an arrow on the screen's edge while it is out of view, with the distance.
--   GuideArrow.gui(target, options)    points at a button or panel on screen: a
--     bouncing arrow beside it and a pulsing outline on it.
--
-- Both return a handle; call handle.destroy() to take the arrows away. The
-- targets are functions so they can follow moving or late-loading things (a
-- nil result hides the arrow until it exists).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local GuideArrow = {}

export type Handle = { destroy: () -> () }

export type WorldOptions = {
	label: string?,
	-- A part or model to outline.
	highlight: (() -> Instance?)?,
	-- Draw the chevron trail on the ground from the player to the target.
	trail: boolean?,
	color: Color3?,
}

export type GuiOptions = {
	text: string?,
	color: Color3?,
	-- Which side of the target the arrow sits on ("left" | "right" | "top" | "bottom").
	side: string?,
}

local ACCENT = Color3.fromRGB(255, 200, 40)
local CHEVRONS = 7
local SPACING = 7
local STOP_SHORT = 7 -- the trail ends this far from the target
local MIN_TRAIL = 16 -- no trail when the player is closer than this

local folder: Folder? = nil
local screen: ScreenGui? = nil

local function guideFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "TutorialGuides"
	f.Parent = workspace
	folder = f
	return f
end

local function guideScreen(): ScreenGui
	if screen and screen.Parent then
		return screen
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialGuides"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 150
	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui
	return gui
end

local function arrowLabel(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(10, 48, 110)
	label.TextStrokeTransparency = 0
	label.Parent = parent
	return label
end

local function positionOf(thing: Instance?): Vector3?
	if not thing then
		return nil
	end
	if thing:IsA("BasePart") then
		return thing.Position
	elseif thing:IsA("Model") then
		return thing:GetPivot().Position
	end
	return nil
end

local function groundAt(point: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(point + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return if hit then hit.Position else point
end

-- One V-shaped chevron laid flat, its tip along -Z (two thin neon bars).
local function chevron(parent: Instance, color: Color3): { Part }
	local bars = {}
	for _, angle in { -45, 45 } do
		local bar = Instance.new("Part")
		bar.Anchored = true
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CanTouch = false
		bar.CastShadow = false
		bar.Material = Enum.Material.Neon
		bar.Color = color
		bar.Size = Vector3.new(0.7, 0.2, 2.6)
		bar:SetAttribute("Angle", angle)
		bar.Parent = parent
		table.insert(bars, bar)
	end
	return bars
end

function GuideArrow.world(target: () -> Vector3?, options: WorldOptions?): Handle
	local opts = options or {}
	local color = opts.color or ACCENT
	local root = Instance.new("Folder")
	root.Name = "WorldGuide"
	root.Parent = guideFolder()

	-- The hovering arrow.
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = root
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(240, 150)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 1000
	billboard.Parent = anchor
	local arrow = arrowLabel(billboard, "▼", 84, color)
	arrow.Size = UDim2.new(1, 0, 0, 84)
	if opts.label then
		local text = arrowLabel(billboard, opts.label, 24, Color3.new(1, 1, 1))
		text.Size = UDim2.new(1, 0, 0, 60)
		text.Position = UDim2.fromOffset(0, 84)
		text.TextWrapped = true
	end

	local outline: Highlight? = nil
	if opts.highlight then
		local light = Instance.new("Highlight")
		light.FillColor = color
		light.FillTransparency = 0.75
		light.OutlineColor = color
		light.OutlineTransparency = 0
		light.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		light.Parent = root
		outline = light
	end

	-- The trail on the ground.
	local bars: { { Part } } = {}
	if opts.trail then
		for _ = 1, CHEVRONS do
			table.insert(bars, chevron(root, color))
		end
	end

	-- The arrow on the edge of the screen while the target is out of view.
	local pointer = Instance.new("Frame")
	pointer.BackgroundTransparency = 1
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Size = UDim2.fromOffset(120, 90)
	pointer.Visible = false
	pointer.Parent = guideScreen()
	local pointerArrow = arrowLabel(pointer, "➤", 64, color)
	pointerArrow.AnchorPoint = Vector2.new(0.5, 0)
	pointerArrow.Position = UDim2.new(0.5, 0, 0, 0)
	pointerArrow.Size = UDim2.fromOffset(70, 64)
	local pointerText = arrowLabel(pointer, "", 22, Color3.new(1, 1, 1))
	pointerText.Position = UDim2.new(0, 0, 0, 62)
	pointerText.Size = UDim2.new(1, 0, 0, 26)

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		local point = target()
		if not point or not camera then
			anchor.Parent = nil
			pointer.Visible = false
			for _, pair in bars do
				for _, bar in pair do
					bar.Parent = nil
				end
			end
			return
		end
		if anchor.Parent == nil then
			anchor.Parent = root
		end
		local now = os.clock()
		anchor.Position = point + Vector3.new(0, 8 + math.sin(now * 4) * 0.8, 0)
		arrow.TextTransparency = 0.05 + (math.sin(now * 6) + 1) * 0.08
		if outline and opts.highlight then
			local thing = opts.highlight()
			if outline.Adornee ~= thing then
				outline.Adornee = thing
			end
			outline.OutlineTransparency = 0.1 + (math.sin(now * 5) + 1) * 0.15
		end

		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local from = if rootPart and rootPart:IsA("BasePart") then rootPart.Position else nil

		-- Edge pointer: only while the target is off screen.
		local viewport, onScreen = camera:WorldToViewportPoint(point + Vector3.new(0, 4, 0))
		local size = camera.ViewportSize
		if onScreen and viewport.Z > 0 then
			pointer.Visible = false
		else
			local center = size / 2
			local direction = Vector2.new(viewport.X, viewport.Y) - center
			if viewport.Z < 0 then
				direction = -direction -- behind the camera: flip so it points the right way
			end
			if direction.Magnitude < 1 then
				direction = Vector2.new(0, 1)
			end
			local unit = direction.Unit
			local scale = math.min(
				(size.X / 2 - 80) / math.max(math.abs(unit.X), 0.001),
				(size.Y / 2 - 90) / math.max(math.abs(unit.Y), 0.001)
			)
			pointer.Position =
				UDim2.fromOffset(center.X + unit.X * scale, center.Y + unit.Y * scale)
			pointerArrow.Rotation = math.deg(math.atan2(unit.Y, unit.X))
			pointerText.Text = if from then `{math.floor((point - from).Magnitude)} studs` else ""
			pointer.Visible = true
		end

		-- Ground trail, flowing toward the target.
		if #bars > 0 then
			local show = from ~= nil and (point - (from :: Vector3)).Magnitude > MIN_TRAIL
			if not show or not from then
				for _, pair in bars do
					for _, bar in pair do
						bar.Parent = nil
					end
				end
				return
			end
			local flat = Vector3.new(point.X - from.X, 0, point.Z - from.Z)
			local length = flat.Magnitude
			local direction = flat.Unit
			local ignore: { Instance } = { root }
			if character then
				table.insert(ignore, character)
			end
			local flow = (now * 5) % SPACING
			for index, pair in bars do
				local along = 6 + (index - 1) * SPACING + flow
				if along > length - STOP_SHORT then
					for _, bar in pair do
						bar.Parent = nil
					end
				else
					local base = Vector3.new(from.X, from.Y, from.Z) + direction * along
					local ground = groundAt(base, ignore) + Vector3.new(0, 0.15, 0)
					local fade = math.clamp(along / 14, 0, 1)
						* math.clamp((length - STOP_SHORT - along) / 10, 0, 1)
					for _, bar in pair do
						bar.Parent = root
						local angle = bar:GetAttribute("Angle") :: number
						bar.CFrame = CFrame.lookAt(ground, ground + direction)
							* CFrame.Angles(0, math.rad(angle), 0)
							* CFrame.new(0, 0, 1.3)
						bar.Transparency = 0.15 + (1 - fade) * 0.85
					end
				end
			end
		end
	end)

	return {
		destroy = function()
			connection:Disconnect()
			root:Destroy()
			pointer:Destroy()
		end,
	}
end

function GuideArrow.gui(target: () -> GuiObject?, options: GuiOptions?): Handle
	local opts = options or {}
	local color = opts.color or ACCENT
	local holder = Instance.new("Frame")
	holder.Name = "GuiGuide"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(200, 70)
	holder.Visible = false
	holder.Parent = guideScreen()
	local arrow = arrowLabel(holder, "", 56, color)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(60, 60)
	local text: TextLabel? = nil
	if opts.text then
		local label = arrowLabel(holder, opts.text, 20, Color3.new(1, 1, 1))
		label.Size = UDim2.fromOffset(200, 26)
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 1, 0)
		text = label
	end

	-- The target's own outline pulses (restored when the guide is removed).
	local pulsed: UIStroke? = nil
	local originalColor: Color3? = nil
	local originalThickness = 0

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local object = target()
		if not object or not object.Visible or object.AbsoluteSize.X <= 0 then
			holder.Visible = false
			return
		end
		local screenGui = object:FindFirstAncestorOfClass("ScreenGui")
		local inset = if screenGui and not screenGui.IgnoreGuiInset
			then GuiService:GetGuiInset()
			else Vector2.zero
		local topLeft = object.AbsolutePosition + inset
		local size = object.AbsoluteSize
		local center = topLeft + size / 2
		local viewport = guideScreen().AbsoluteSize
		local side = opts.side
		if not side then
			side = if center.X < viewport.X / 2 then "right" else "left"
		end
		local now = os.clock()
		local bob = math.sin(now * 6) * 8
		local gap = 40
		if side == "right" then
			arrow.Text = "◀"
			holder.Position = UDim2.fromOffset(topLeft.X + size.X + gap + bob, center.Y)
		elseif side == "left" then
			arrow.Text = "▶"
			holder.Position = UDim2.fromOffset(topLeft.X - gap - bob, center.Y)
		elseif side == "top" then
			arrow.Text = "▼"
			holder.Position = UDim2.fromOffset(center.X, topLeft.Y - gap - bob)
		else
			arrow.Text = "▲"
			holder.Position = UDim2.fromOffset(center.X, topLeft.Y + size.Y + gap + bob)
		end
		holder.Visible = true
		if text then
			text.Visible = true
		end

		local stroke = object:FindFirstChildOfClass("UIStroke")
		if stroke ~= pulsed then
			if pulsed and originalColor then
				pulsed.Color = originalColor
				pulsed.Thickness = originalThickness
			end
			pulsed = stroke
			if stroke then
				originalColor = stroke.Color
				originalThickness = stroke.Thickness
			end
		end
		if stroke then
			local wave = (math.sin(now * 6) + 1) / 2
			stroke.Color = (originalColor or color):Lerp(color, wave)
			stroke.Thickness = originalThickness + wave * 4
		end
	end)

	return {
		destroy = function()
			connection:Disconnect()
			if pulsed and originalColor then
				pulsed.Color = originalColor
				pulsed.Thickness = originalThickness
			end
			holder:Destroy()
		end,
	}
end

return GuideArrow
