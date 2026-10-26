--!strict
-- Game feel for casting and fighting: camera shake, field-of-view kicks, a
-- red damage vignette, a pulsing low-health warning, and a hit marker where
-- you aim. Every effect scales with how big the moment is (Config.JUICE).
-- Camera movement (shake and field-of-view kicks) can be switched off in
-- Settings (profile.settings.shake); the screen flashes and sounds stay.
--
-- Display only: the server decides what hit whom. Callers (FxController for
-- hits and casts, PresentationController for knockouts, HealthController for
-- low health) just say what happened.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local player = Players.LocalPlayer

local JuiceController = {}

local GOLD = Color3.fromRGB(255, 214, 64)
local RED = Color3.fromRGB(235, 60, 60)
local WHITE = Color3.fromRGB(255, 255, 255)

local gui: ScreenGui
local flashEdges: { Frame } = {}
local pulseEdges: { Frame } = {}

-- Shake: the camera offset decays to nothing over `shakeDuration`.
local shakePower = 0
local shakeLeft = 0
local shakeDuration = 0.01
-- Field-of-view kick: added on top of whatever the field of view is, decaying.
local fovKick = 0
local appliedKick = 0
local lowHealth = 0 -- 0 = fine, 1 = about to die; drives the pulsing edges

local function motionEnabled(): boolean
	local profile = ClientState.profile
	return not (profile and profile.settings and profile.settings.shake == false)
end

-- Four frames along the screen edges that fade toward the middle.
local function makeEdges(name: string, order: number): { Frame }
	local layer = Instance.new("Frame")
	layer.Name = name
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = order
	layer.Parent = gui
	local edges = {}
	-- {anchor, position, size, gradient rotation}: the gradient runs from the
	-- edge (opaque) inward (clear).
	local specs = {
		{ Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.28), 90 },
		{ Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.28), 270 },
		{ Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.2, 1), 0 },
		{ Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.2, 1), 180 },
	}
	for _, spec in specs do
		local edge = Instance.new("Frame")
		edge.AnchorPoint = spec[1] :: Vector2
		edge.Position = spec[2] :: UDim2
		edge.Size = spec[3] :: UDim2
		edge.BackgroundColor3 = RED
		edge.BackgroundTransparency = 1
		edge.BorderSizePixel = 0
		edge.ZIndex = order
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec[4] :: number
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = edge
		edge.Parent = layer
		table.insert(edges, edge)
	end
	return edges
end

local function setEdges(edges: { Frame }, color: Color3, transparency: number)
	for _, edge in edges do
		edge.BackgroundColor3 = color
		edge.BackgroundTransparency = transparency
	end
end

-- Flashes the screen edges `color` at `strength` (0..1) and fades them out.
local function flash(color: Color3, strength: number, seconds: number)
	setEdges(flashEdges, color, 1 - math.clamp(strength, 0, 1))
	for _, edge in flashEdges do
		TweenService:Create(
			edge,
			TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end
end

-- Shakes the camera: `power` is 0..1 of Config.JUICE.SHAKE_MAX.
local function shake(power: number, seconds: number)
	if not motionEnabled() then
		return
	end
	local strong = math.clamp(power, 0, 1) * Config.JUICE.SHAKE_MAX
	-- A new shake only replaces the current one when it is stronger.
	local remaining = if shakeLeft > 0 then shakePower * (shakeLeft / shakeDuration) else 0
	if strong >= remaining then
		shakePower = strong
		shakeLeft = seconds
		shakeDuration = seconds
	end
end

-- Kicks the field of view out by `degrees` (0..1 of Config.JUICE.FOV_MAX).
local function kick(amount: number)
	if not motionEnabled() then
		return
	end
	fovKick = math.max(fovKick, math.clamp(amount, 0, 1) * Config.JUICE.FOV_MAX)
end

-- A hit marker (an X) where the player is aiming: at the mouse, or the middle
-- of the screen on touch and gamepad.
local function hitMarker(color: Color3, scale: number)
	local viewport = (workspace.CurrentCamera :: Camera).ViewportSize
	local at = if UserInputService.MouseEnabled
		then UserInputService:GetMouseLocation()
		else viewport / 2
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(at.X, at.Y)
	holder.Size = UDim2.fromOffset(34, 34)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 5
	local grow = Instance.new("UIScale")
	grow.Scale = 1.5 * scale
	grow.Parent = holder
	local bars = {}
	for _, angle in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(5, 34)
		bar.Rotation = angle
		bar.BackgroundColor3 = color
		bar.BorderSizePixel = 0
		-- A dark edge so the X reads on any background.
		local outline = Instance.new("UIStroke")
		outline.Color = Color3.fromRGB(20, 20, 40)
		outline.Thickness = 1.5
		outline.Parent = bar
		bar.Parent = holder
		table.insert(bars, bar)
	end
	holder.Parent = gui
	local settle = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(grow, settle, { Scale = scale }):Play()
	task.delay(0.12, function()
		local fade = TweenInfo.new(0.2)
		for _, bar in bars do
			TweenService:Create(bar, fade, { BackgroundTransparency = 1 }):Play()
			local outline = bar:FindFirstChildOfClass("UIStroke")
			if outline then
				TweenService:Create(outline, fade, { Transparency = 1 }):Play()
			end
		end
	end)
	task.delay(0.4, function()
		holder:Destroy()
	end)
end

local function heavy(amount: number): number
	return math.clamp(amount / Config.JUICE.BIG_HIT, 0, 1.5)
end

-- Your spell hit something (the server told us the damage). Heavier hits get a
-- bigger, golden marker and a small camera kick.
function JuiceController.hit(amount: number)
	local size = heavy(amount)
	if size >= 1 then
		hitMarker(GOLD, 1.4)
		kick(0.35)
		shake(0.25, 0.18)
		AudioController.play("heavyHit")
	else
		hitMarker(WHITE, 0.85 + size * 0.3)
		AudioController.play("hitMarker")
	end
end

-- You were hit: red edges and a shake, both scaled by the damage.
function JuiceController.hurt(amount: number)
	local size = heavy(amount)
	flash(RED, 0.35 + 0.5 * math.min(size, 1), 0.5)
	shake(0.2 + 0.5 * math.min(size, 1), 0.15 + 0.2 * math.min(size, 1))
	AudioController.play("hurt")
end

-- You cast a spell: a small kick. Ultimates (long cooldowns) kick harder.
function JuiceController.cast(cooldown: number)
	local big = math.clamp(cooldown / 20, 0, 1)
	kick(0.12 + 0.4 * big)
	shake(0.06 + 0.4 * big, 0.12 + 0.2 * big)
end

-- A well-drawn spell: a golden flash for a Perfect, a smaller one for Great.
function JuiceController.drawn(stars: number)
	if stars >= 4 then
		flash(GOLD, 0.55, 0.6)
		kick(0.3)
	elseif stars == 3 then
		flash(GOLD, 0.25, 0.4)
	end
end

-- You knocked someone out (`killer`), or were knocked out.
function JuiceController.knockout(killer: boolean)
	if killer then
		hitMarker(RED, 2)
		flash(GOLD, 0.6, 0.7)
		kick(0.8)
		shake(0.5, 0.35)
		AudioController.play("knockoutSting")
	else
		flash(RED, 0.9, 1)
		shake(0.9, 0.5)
	end
end

-- 0..1: how close to dying you are, in a match. Above Config.JUICE.LOW_HEALTH
-- the warning is off.
function JuiceController.setLowHealth(fraction: number)
	local low = Config.JUICE.LOW_HEALTH
	lowHealth = if fraction >= low then 0 else 1 - fraction / low
end

function JuiceController.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Juice"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 9
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pulseEdges = makeEdges("LowHealth", 1)
	flashEdges = makeEdges("Flash", 2)
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function step(dt: number)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if shakeLeft > 0 then
		shakeLeft = math.max(0, shakeLeft - dt)
		local fade = shakeLeft / shakeDuration
		local amount = shakePower * fade * fade
		if humanoid then
			humanoid.CameraOffset =
				Vector3.new((math.random() * 2 - 1) * amount, (math.random() * 2 - 1) * amount, 0)
		end
	elseif humanoid and humanoid.CameraOffset ~= Vector3.zero then
		humanoid.CameraOffset = Vector3.zero
	end

	local camera = workspace.CurrentCamera
	if camera then
		-- Take our last kick off before adding the new one, so other changes to
		-- the field of view (zooming) are left alone.
		fovKick = fovKick * math.max(0, 1 - 9 * dt)
		if fovKick < 0.02 then
			fovKick = 0
		end
		camera.FieldOfView = camera.FieldOfView - appliedKick + fovKick
		appliedKick = fovKick
	end

	if lowHealth > 0 then
		local beat = 0.5 + 0.5 * math.sin(os.clock() * (5 + 3 * lowHealth))
		setEdges(pulseEdges, RED, 1 - (0.15 + 0.4 * beat) * lowHealth)
	else
		setEdges(pulseEdges, RED, 1)
	end
end

function JuiceController.start()
	RunService.RenderStepped:Connect(step)
	-- A new character starts with a clear screen.
	player.CharacterAdded:Connect(function()
		lowHealth = 0
		shakeLeft = 0
	end)
end

return JuiceController
