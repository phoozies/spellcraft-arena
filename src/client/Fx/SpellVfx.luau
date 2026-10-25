--!strict
-- Client-side spell visuals built only from Roblox's built-in particle
-- textures (no uploaded assets): bolt trails/particles per element, a
-- distinct impact per spell kind (explosion, splash, rubble, ...), the cast
-- animation (pose + the beat that rides on it + magic circle + hand sparkle), block shatter chunks, chips, dust.
--
-- Everything here is cosmetic and local. Every function is safe to call
-- with characters/parts that may be mid-destroy.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GlyphView = require(ReplicatedStorage.Shared.UI.GlyphView)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local CastPoses = require(ReplicatedStorage.Shared.Spells.CastPoses)
local VfxStyles = require(ReplicatedStorage.Shared.Spells.VfxStyles)
local CastAnimations = require(script.Parent.CastAnimations)

local SpellVfx = {}

local TEX = VfxStyles.TEX
local STYLES = VfxStyles.STYLES

export type Style = VfxStyles.Style

function SpellVfx.styleFor(fxKey: string?): Style
	return (fxKey and STYLES[fxKey]) or STYLES.default
end

local function anchorAt(parent: Instance, position: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(position)
	p.Parent = parent
	return p
end

local function emitter(
	parent: Instance,
	texture: string,
	color: Color3,
	style: Style
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.4))
	e.LightEmission = 0.8
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, style.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(style.lifetime * 0.6, style.lifetime)
	e.Speed = NumberRange.new(style.speed * 0.5, style.speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = style.rate
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = parent
	return e
end

-- Decorates a flying bolt part with a trail, particles, and a light.
function SpellVfx.decorateBolt(part: BasePart, fxKey: string?, color: Color3)
	local style = SpellVfx.styleFor(fxKey)
	local tint = style.tint or color
	emitter(part, style.texture, tint, style)
	if style.secondary then
		local smoke = emitter(part, style.secondary, Color3.fromRGB(80, 70, 70), style)
		smoke.Rate = style.rate / 3
		smoke.LightEmission = 0
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, style.trailWidth / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -style.trailWidth / 2, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(tint)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.25
	trail.LightEmission = 0.7
	trail.FaceCamera = true
	trail.Parent = part
	if style.lightRange > 0 then
		local light = Instance.new("PointLight")
		light.Color = tint
		light.Range = style.lightRange
		light.Brightness = 2
		light.Parent = part
	end
end

-- Spawns a copy of a block model (ModelKit) for an effect, or nil when the
-- place has no such model. `width` is the width (studs, X) it is scaled to.
local function spawnModel(parent: Instance, modelName: string?, width: number): Model?
	if not modelName then
		return nil
	end
	local model = ModelKit.clone(modelName, "effect")
	if not model then
		return nil
	end
	local _, size = model:GetBoundingBox()
	model:ScaleTo(width / math.max(size.X, 0.01))
	model.Parent = parent
	return model
end

-- Fades every part of a model out over `seconds`.
local function fadeModel(model: Model, seconds: number)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			TweenService:Create(part, TweenInfo.new(seconds), { Transparency = 1 }):Play()
		end
	end
end

-- Runs `step(elapsed)` every frame for `seconds`, then stops (and stops early
-- if `step` returns false).
local function every(seconds: number, step: (number) -> boolean?)
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		if t >= seconds or step(t) == false then
			connection:Disconnect()
		end
	end)
end

-- Expanding flat ring on the ground (impacts, slams, zone pops).
function SpellVfx.shockwave(parent: Instance, position: Vector3, radius: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = parent
	TweenService
		:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, radius * 2, radius * 2),
			Transparency = 1,
		})
		:Play()
	Debris:AddItem(ring, 0.4)
end

local WHITE = Color3.new(1, 1, 1)

-- A glowing ball that swells from `from` to `to` studs and fades out.
local function flash(
	parent: Instance,
	position: Vector3,
	from: number,
	to: number,
	seconds: number,
	color: Color3,
	transparency: number
)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.one * from
	p.Position = position
	p.Parent = parent
	TweenService
		:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * to,
			Transparency = 1,
		})
		:Play()
	Debris:AddItem(p, seconds + 0.1)
end

-- A bit (droplet, rock chunk) flung out, falling under gravity, gone after
-- `life` seconds. Never collides, so it can't shove anybody.
local function fling(
	parent: Instance,
	position: Vector3,
	velocity: Vector3,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	life: number,
	round: boolean
)
	local bit = Instance.new("Part")
	bit.Shape = if round then Enum.PartType.Ball else Enum.PartType.Block
	bit.Size = size
	bit.Color = color
	bit.Material = material
	bit.CanCollide = false
	bit.CanQuery = false
	bit.CanTouch = false
	bit.CastShadow = false
	bit.CFrame = CFrame.new(position)
	bit.AssemblyLinearVelocity = velocity
	bit.AssemblyAngularVelocity =
		Vector3.new(math.random(-9, 9), math.random(-9, 9), math.random(-9, 9))
	bit.Parent = parent
	task.delay(life * 0.65, function()
		if bit.Parent then
			TweenService:Create(bit, TweenInfo.new(life * 0.35), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(bit, life)
end

-- A thin glowing bar from `a` to `b` that shrinks and fades (cuts, lightning).
local function bar(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	seconds: number
)
	local length = (b - a).Magnitude
	if length < 0.05 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(thickness, thickness, length)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	p.Parent = parent
	TweenService
		:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(thickness * 0.2, thickness * 0.2, length),
			Transparency = 1,
		})
		:Play()
	Debris:AddItem(p, seconds + 0.1)
end

-- An expanding translucent disc facing the camera (a ring of air, a pop).
local function airRing(
	parent: Instance,
	position: Vector3,
	radius: number,
	color: Color3,
	delay: number,
	seconds: number
)
	task.delay(delay, function()
		local camera = workspace.CurrentCamera
		local facing = if camera
			then CFrame.lookAt(position, camera.CFrame.Position)
			else CFrame.new(position)
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = 0.5
		ring.Size = Vector3.new(0.12, 1, 1)
		ring.CFrame = facing * CFrame.Angles(0, math.pi / 2, 0)
		ring.Parent = parent
		TweenService
			:Create(ring, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.12, radius * 2, radius * 2),
				Transparency = 1,
			})
			:Play()
		Debris:AddItem(ring, seconds + 0.1)
	end)
end

-- A random unit vector on the upper half of a sphere.
local function randomUp(): Vector3
	local angle = math.random() * math.pi * 2
	return Vector3.new(math.cos(angle), math.random() * 0.9, math.sin(angle)).Unit
end

type HitDraw = (Instance, Vector3, Color3, number, Style) -> ()

-- One drawing per kind in VfxStyles.HITS. `tint` is the spell's color and
-- `scale` the style's hitScale. Each also gets the style's particle burst and
-- light from SpellVfx.impact.
local HIT_KINDS: { [string]: HitDraw } = {}

-- Fireball / Fire Bomb: a white-hot flash inside an orange blast, flames,
-- rolling smoke, and embers thrown outward.
function HIT_KINDS.explosion(parent, position, tint, scale, style)
	flash(parent, position, 2 * scale, 9 * scale, 0.32, tint, 0.15)
	flash(parent, position, 1 * scale, 5 * scale, 0.2, Color3.fromRGB(255, 244, 214), 0)
	local anchor = anchorAt(parent, position)
	local smoke = emitter(anchor, TEX.smoke, Color3.fromRGB(70, 62, 60), style)
	smoke.Rate = 0
	smoke.LightEmission = 0
	smoke.Size = NumberSequence.new(2 * scale, 5 * scale)
	smoke.Lifetime = NumberRange.new(0.8, 1.2)
	smoke.Speed = NumberRange.new(3, 9 * scale)
	smoke.Acceleration = Vector3.new(0, 5, 0)
	smoke:Emit(math.floor(8 * scale))
	local embers = emitter(anchor, TEX.sparkle, Color3.fromRGB(255, 190, 80), style)
	embers.Rate = 0
	embers.Size = NumberSequence.new(0.5 * scale, 0)
	embers.Lifetime = NumberRange.new(0.6, 1)
	embers.Speed = NumberRange.new(18, 40)
	embers.Acceleration = Vector3.new(0, -45, 0)
	embers:Emit(math.floor(14 * scale))
	SpellVfx.shockwave(parent, position, 5 * scale, tint)
	Debris:AddItem(anchor, 1.4)
end

-- Fire Slash: two cut marks cross where the blade landed, with sparks.
function HIT_KINDS.slashCut(parent, position, tint, scale, style)
	local camera = workspace.CurrentCamera
	local facing = if camera
		then CFrame.lookAt(position, camera.CFrame.Position)
		else CFrame.new(position)
	local roll = math.random() * math.pi
	for i, length in { 8 * scale, 5.5 * scale } do
		local angle = roll + (if i == 1 then 0.6 else -0.7)
		local reach = facing:VectorToWorldSpace(Vector3.new(math.cos(angle), math.sin(angle), 0))
			* (length / 2)
		bar(
			parent,
			position - reach,
			position + reach,
			if i == 1 then 0.4 else 0.28,
			if i == 1 then WHITE else tint,
			0.3
		)
	end
	local anchor = anchorAt(parent, position)
	local sparks = emitter(anchor, TEX.sparkle, tint, style)
	sparks.Rate = 0
	sparks.Size = NumberSequence.new(0.45, 0)
	sparks.Speed = NumberRange.new(14, 30)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks:Emit(14)
	SpellVfx.shockwave(parent, position, 2.5 * scale, tint)
	Debris:AddItem(anchor, 1)
end

-- Water Slice / Water Wave: droplets thrown up and out, mist, and ripples.
function HIT_KINDS.splash(parent, position, tint, scale, style)
	local drop = tint:Lerp(WHITE, 0.3)
	for _ = 1, math.floor(14 * scale) do
		local angle = math.random() * math.pi * 2
		local speed = (8 + math.random() * 12) * math.sqrt(scale)
		fling(
			parent,
			position,
			Vector3.new(math.cos(angle) * speed, 16 + math.random() * 14, math.sin(angle) * speed),
			Vector3.one * (0.3 + math.random() * 0.35) * math.sqrt(scale),
			drop,
			Enum.Material.SmoothPlastic,
			0.75,
			true
		)
	end
	local anchor = anchorAt(parent, position)
	local mist = emitter(anchor, TEX.smoke, tint:Lerp(WHITE, 0.6), style)
	mist.Rate = 0
	mist.LightEmission = 0.25
	mist.Size = NumberSequence.new(1.5 * scale, 4 * scale)
	mist.Lifetime = NumberRange.new(0.5, 0.8)
	mist.Speed = NumberRange.new(4, 11)
	mist:Emit(math.floor(8 * scale))
	SpellVfx.shockwave(parent, position, 4.5 * scale, tint)
	task.delay(0.1, function()
		SpellVfx.shockwave(parent, position, 3 * scale, drop)
	end)
	Debris:AddItem(anchor, 1.2)
end

-- Water Lock: a bubble swells and pops, leaving small bubbles drifting up.
function HIT_KINDS.bubble(parent, position, tint, scale, style)
	local shell = Instance.new("Part")
	shell.Shape = Enum.PartType.Ball
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.Material = Enum.Material.Glass
	shell.Color = Color3.fromRGB(190, 235, 255)
	shell.Transparency = 0.35
	shell.Size = Vector3.one * 2 * scale
	shell.Position = position
	shell.Parent = parent
	TweenService
		:Create(shell, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = Vector3.one * 6.5 * scale,
			Transparency = 0.55,
		})
		:Play()
	task.delay(0.16, function()
		-- Pop: the shell bursts outward and vanishes.
		TweenService:Create(shell, TweenInfo.new(0.1), {
			Size = Vector3.one * 8.5 * scale,
			Transparency = 1,
		}):Play()
		SpellVfx.shockwave(parent, position, 4 * scale, tint)
		local anchor = anchorAt(parent, position)
		local spray = emitter(anchor, TEX.sparkle, WHITE, style)
		spray.Rate = 0
		spray.Size = NumberSequence.new(0.5, 0)
		spray.Speed = NumberRange.new(10, 20)
		spray:Emit(16)
		Debris:AddItem(anchor, 1)
	end)
	Debris:AddItem(shell, 0.5)
	for _ = 1, 9 do
		local small = Instance.new("Part")
		small.Shape = Enum.PartType.Ball
		small.Anchored = true
		small.CanCollide = false
		small.CanQuery = false
		small.CanTouch = false
		small.CastShadow = false
		small.Material = Enum.Material.Glass
		small.Color = Color3.fromRGB(190, 235, 255)
		small.Transparency = 0.3
		small.Size = Vector3.one * (0.4 + math.random() * 0.6)
		small.Position = position
		small.Parent = parent
		local drift = randomUp() * (2 + math.random() * 3) + Vector3.new(0, 2.5, 0)
		TweenService
			:Create(small, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = position + drift,
				Transparency = 1,
			})
			:Play()
		Debris:AddItem(small, 0.9)
	end
end

-- Rock Throw: the boulder cracks into chunks that tumble away, with dust.
function HIT_KINDS.rubble(parent, position, tint, scale, _style)
	local rock = tint:Lerp(Color3.fromRGB(120, 120, 120), 0.35)
	for _ = 1, math.floor(7 * scale) do
		local angle = math.random() * math.pi * 2
		local speed = 8 + math.random() * 14
		local side = 0.4 + math.random() * 0.5
		fling(
			parent,
			position,
			Vector3.new(math.cos(angle) * speed, 12 + math.random() * 12, math.sin(angle) * speed),
			Vector3.new(side, side * (0.7 + math.random() * 0.6), side),
			rock,
			Enum.Material.Slate,
			0.9,
			false
		)
	end
	SpellVfx.dust(parent, position, 3 * scale, tint)
end

-- Gust / Whirlwind: rings of air push out, with puffs and streaking lines.
function HIT_KINDS.wind(parent, position, tint, scale, style)
	local air = tint:Lerp(WHITE, 0.5)
	airRing(parent, position, 5 * scale, air, 0, 0.4)
	airRing(parent, position, 8 * scale, air, 0.08, 0.45)
	local camera = workspace.CurrentCamera
	local facing = if camera
		then CFrame.lookAt(position, camera.CFrame.Position)
		else CFrame.new(position)
	for i = 1, 7 do
		local angle = i / 7 * math.pi * 2 + math.random() * 0.4
		local dir = facing:VectorToWorldSpace(Vector3.new(math.cos(angle), math.sin(angle), 0))
		local streak = Instance.new("Part")
		streak.Anchored = true
		streak.CanCollide = false
		streak.CanQuery = false
		streak.CanTouch = false
		streak.CastShadow = false
		streak.Material = Enum.Material.Neon
		streak.Color = air
		streak.Transparency = 0.2
		streak.Size = Vector3.new(0.14, 0.14, 2.6 * scale)
		streak.CFrame = CFrame.lookAt(position + dir, position + dir * 2)
		streak.Parent = parent
		TweenService
			:Create(streak, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.lookAt(position + dir * 6 * scale, position + dir * 7 * scale),
				Transparency = 1,
			})
			:Play()
		Debris:AddItem(streak, 0.45)
	end
	local anchor = anchorAt(parent, position)
	local puffs = emitter(anchor, TEX.smoke, air, style)
	puffs.Rate = 0
	puffs.LightEmission = 0.1
	puffs.Size = NumberSequence.new(1.2 * scale, 3.5 * scale)
	puffs.Lifetime = NumberRange.new(0.4, 0.7)
	puffs.Speed = NumberRange.new(10, 18)
	puffs:Emit(math.floor(14 * scale))
	Debris:AddItem(anchor, 1)
end

-- Tornado: the wind rings, plus debris torn up and flung away.
function HIT_KINDS.storm(parent, position, tint, scale, style)
	HIT_KINDS.wind(parent, position, tint, scale * 0.8, style)
	airRing(parent, position, 11 * scale, tint:Lerp(WHITE, 0.5), 0.18, 0.5)
	for _ = 1, math.floor(8 * scale) do
		local angle = math.random() * math.pi * 2
		local speed = 12 + math.random() * 16
		local side = 0.4 + math.random() * 0.6
		fling(
			parent,
			position,
			Vector3.new(math.cos(angle) * speed, 14 + math.random() * 16, math.sin(angle) * speed),
			Vector3.new(side, side * 0.5, side * 1.4),
			if math.random() < 0.5
				then Color3.fromRGB(139, 112, 82)
				else Color3.fromRGB(150, 160, 150),
			Enum.Material.Slate,
			1,
			false
		)
	end
end

-- Lightning: a white flash, jagged forks crackling outward, and a ground ring.
function HIT_KINDS.bolt(parent, position, tint, scale, style)
	flash(parent, position, 2 * scale, 10 * scale, 0.22, WHITE, 0)
	for _ = 1, 6 do
		local dir = randomUp()
		local point = position
		for _ = 1, 3 do
			local nextPoint = point
				+ dir * (2 + math.random() * 1.5) * scale
				+ Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
					* 2
					* scale
			bar(parent, point, nextPoint, 0.5, tint, 0.32)
			bar(parent, point, nextPoint, 0.2, WHITE, 0.2)
			point = nextPoint
		end
	end
	local anchor = anchorAt(parent, position)
	local sparks = emitter(anchor, TEX.sparkle, tint, style)
	sparks.Rate = 0
	sparks.Size = NumberSequence.new(0.6, 0)
	sparks.Speed = NumberRange.new(20, 45)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks:Emit(math.floor(18 * scale))
	SpellVfx.shockwave(parent, position, 6 * scale, tint)
	Debris:AddItem(anchor, 1)
end

-- Bullets: a quick pop of sparks, no ring.
function HIT_KINDS.spark(parent, position, tint, _scale, style)
	flash(parent, position, 0.4, 1.6, 0.12, tint, 0.2)
	local anchor = anchorAt(parent, position)
	local sparks = emitter(anchor, TEX.sparkle, tint, style)
	sparks.Rate = 0
	sparks.Size = NumberSequence.new(0.3, 0)
	sparks.Speed = NumberRange.new(8, 18)
	sparks:Emit(6)
	Debris:AddItem(anchor, 0.8)
end

-- Impact: the style's particle burst and light flash, then the drawing for its
-- `hit` kind (an explosion, a splash, rubble, ...). A style without a kind
-- gets a plain ring.
function SpellVfx.impact(parent: Instance, position: Vector3, fxKey: string?, color: Color3)
	local style = SpellVfx.styleFor(fxKey)
	local tint = style.tint or color
	local scale = style.hitScale or 1
	local anchor = anchorAt(parent, position)
	local e = emitter(anchor, style.texture, tint, style)
	e.Rate = 0
	e.Speed = NumberRange.new(style.speed * 3, style.speed * 6)
	e:Emit(math.floor(style.burst * math.sqrt(scale)))
	if style.lightRange > 0 then
		local light = Instance.new("PointLight")
		light.Color = tint
		light.Range = style.lightRange * 1.5 * scale
		light.Brightness = 4
		light.Parent = anchor
		TweenService:Create(light, TweenInfo.new(0.3), { Brightness = 0 }):Play()
	end
	local draw = if style.hit then HIT_KINDS[style.hit] else nil
	if draw then
		draw(parent, position, tint, scale, style)
	else
		SpellVfx.shockwave(parent, position, 4, tint)
	end
	Debris:AddItem(anchor, 1)
end

-- Cast beats: the body effect that rides on a cast pose (Spells/CastPoses
-- BEATS). Each runs from the moment of the cast and lands at beat.at seconds.
local BEATS: { [string]: (Instance, Model, CastPoses.Beat, Color3) -> () } = {}

local function handOf(character: Model, side: string): BasePart?
	local part = character:FindFirstChild(side .. "Hand")
		or character:FindFirstChild(side .. " Arm")
	return if part and part:IsA("BasePart") then part else nil
end

-- Fireball overhead / boulder lifted: a ball swells above the hand(s) and is
-- released as the arm comes down.
function BEATS.orb(parent, character, beat, color)
	local right = handOf(character, "Right")
	local left = if beat.two then handOf(character, "Left") else nil
	if not right then
		return
	end
	local rock = beat.material == "Slate"
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Material = if rock then Enum.Material.Slate else Enum.Material.Neon
	orb.Color = if rock then color:Lerp(Color3.fromRGB(120, 120, 120), 0.3) else color
	orb.Size = Vector3.one * 0.3
	orb.Parent = parent
	local size = if rock then 3.4 else 2.4
	if not rock then
		local fire = emitter(orb, TEX.fire, color, STYLES.Fireball)
		fire.Rate = 40
		fire.Size = NumberSequence.new(1.2, 0)
		fire.Speed = NumberRange.new(1, 3)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 12
		light.Brightness = 3
		light.Parent = orb
	end
	every(beat.at, function(t)
		if not right.Parent then
			orb:Destroy()
			return false
		end
		local grow = math.min(t / (beat.at * 0.8), 1)
		orb.Size = Vector3.one * math.max(size * grow, 0.3)
		local base = if left and left.Parent
			then (right.Position + left.Position) / 2
			else right.Position
		orb.Position = base + Vector3.new(0, 0.6 + size * grow * 0.4, 0)
		return true
	end)
	-- Released: the ball drops away into the throw.
	task.delay(beat.at, function()
		if not orb.Parent then
			return
		end
		for _, child in orb:GetChildren() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		TweenService
			:Create(orb, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.one * size * 1.5,
				Transparency = 1,
			})
			:Play()
	end)
	Debris:AddItem(orb, beat.at + 0.4)
end

-- Slashes: the hand leaves a glowing streak as it cuts across.
function BEATS.trail(parent, character, beat, color)
	local hand = handOf(character, "Right")
	if not hand then
		return
	end
	task.delay(beat.at, function()
		if not hand.Parent then
			return
		end
		local near = Instance.new("Attachment")
		near.Position = Vector3.new(0, -0.5, 0)
		near.Parent = hand
		local far = Instance.new("Attachment")
		far.Position = Vector3.new(0, -3, 0)
		far.Parent = hand
		local trail = Instance.new("Trail")
		trail.Attachment0 = near
		trail.Attachment1 = far
		trail.Color = ColorSequence.new(WHITE, color)
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.Lifetime = 0.28
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Parent = hand
		task.delay(0.22, function()
			trail.Enabled = false
		end)
		Debris:AddItem(trail, 0.7)
		Debris:AddItem(near, 0.7)
		Debris:AddItem(far, 0.7)
	end)
end

-- Stomps and ground punches: dust, chips, and a ring where the foot (or fist) lands.
function BEATS.stomp(parent, character, beat, color)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	task.delay(beat.at, function()
		if not root.Parent then
			return
		end
		local feet = root.Position
			- Vector3.new(0, 2.8, 0)
			+ root.CFrame.LookVector * (beat.reach or 0)
		SpellVfx.dust(parent, feet, 4, color)
		SpellVfx.chip(
			parent,
			feet + Vector3.new(0, 0.3, 0),
			color:Lerp(Color3.fromRGB(120, 110, 100), 0.4)
		)
		SpellVfx.shockwave(parent, feet + Vector3.new(0, 0.2, 0), 6, color)
	end)
end

-- Big spells: sparks stream into the raised hand, then flash as it comes down.
function BEATS.gather(parent, character, beat, color)
	local hand = handOf(character, "Right")
	if not hand then
		return
	end
	local zone = Instance.new("Part")
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Size = Vector3.one * 7
	zone.Position = hand.Position
	zone.Parent = parent
	local stream = Instance.new("ParticleEmitter")
	stream.Texture = TEX.sparkle
	stream.Color = ColorSequence.new(color, WHITE)
	stream.LightEmission = 1
	stream.Shape = Enum.ParticleEmitterShape.Sphere
	stream.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	stream.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	stream.Speed = NumberRange.new(-14, -10)
	stream.Lifetime = NumberRange.new(0.3, 0.4)
	stream.Rate = 70
	stream.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	stream.Parent = zone
	every(beat.at, function()
		if not hand.Parent then
			zone:Destroy()
			return false
		end
		zone.Position = hand.Position + Vector3.new(0, 1, 0)
		return true
	end)
	task.delay(beat.at, function()
		stream.Enabled = false
		if hand.Parent then
			local at = hand.Position + Vector3.new(0, 1, 0)
			flash(parent, at, 0.8, 4.5, 0.22, color:Lerp(WHITE, 0.4), 0.2)
			stream.Speed = NumberRange.new(12, 22)
			stream:Emit(14)
		end
	end)
	Debris:AddItem(zone, beat.at + 0.6)
end

-- Spinning moves: flat rings of wind whirl out around the body.
function BEATS.swirl(parent, character, beat, color)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local air = color:Lerp(WHITE, 0.55)
	for i = 0, 2 do
		task.delay(beat.at + i * 0.08, function()
			if not root.Parent then
				return
			end
			local ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Cylinder
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.CastShadow = false
			ring.Material = Enum.Material.Neon
			ring.Color = air
			ring.Transparency = 0.55
			ring.Size = Vector3.new(0.12, 3, 3)
			local center = root.Position + Vector3.new(0, 1.5 - i * 1.5, 0)
			ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Parent = parent
			TweenService
				:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = Vector3.new(0.12, 11, 11),
					Transparency = 1,
					CFrame = ring.CFrame * CFrame.Angles(math.pi, 0, 0),
				})
				:Play()
			Debris:AddItem(ring, 0.6)
		end)
	end
end

-- Water moves: droplets spray from both hands.
function BEATS.splash(parent, character, beat, color)
	task.delay(beat.at, function()
		local drop = color:Lerp(WHITE, 0.3)
		for _, side in { "Right", "Left" } do
			local hand = handOf(character, side)
			if hand then
				for _ = 1, 7 do
					local out = hand.CFrame.LookVector * 0
					local angle = math.random() * math.pi * 2
					fling(
						parent,
						hand.Position,
						out
							+ Vector3.new(
								math.cos(angle) * 9,
								10 + math.random() * 9,
								math.sin(angle) * 9
							),
						Vector3.one * (0.25 + math.random() * 0.25),
						drop,
						Enum.Material.SmoothPlastic,
						0.7,
						true
					)
				end
			end
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			SpellVfx.shockwave(parent, root.Position - Vector3.new(0, 2.7, 0), 5, color)
		end
	end)
end

-- Gust: a ring of wind and puffs shoves out in front of the caster.
function BEATS.push(parent, character, beat, color)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	task.delay(beat.at, function()
		if not root.Parent then
			return
		end
		local look = root.CFrame.LookVector
		local front = root.Position + look * 3 + Vector3.new(0, 0.5, 0)
		local air = color:Lerp(WHITE, 0.55)
		for i = 0, 1 do
			task.delay(i * 0.07, function()
				local ring = Instance.new("Part")
				ring.Shape = Enum.PartType.Cylinder
				ring.Anchored = true
				ring.CanCollide = false
				ring.CanQuery = false
				ring.CanTouch = false
				ring.CastShadow = false
				ring.Material = Enum.Material.Neon
				ring.Color = air
				ring.Transparency = 0.45
				ring.Size = Vector3.new(0.12, 2, 2)
				ring.CFrame = CFrame.lookAt(front, front + look) * CFrame.Angles(0, math.pi / 2, 0)
				ring.Parent = parent
				TweenService
					:Create(
						ring,
						TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{
							Size = Vector3.new(0.12, 8, 8),
							Transparency = 1,
							CFrame = ring.CFrame + look * 6,
						}
					)
					:Play()
				Debris:AddItem(ring, 0.5)
			end)
		end
		local anchor = anchorAt(parent, front)
		anchor.CFrame = CFrame.lookAt(front, front + look)
		local puffs = emitter(anchor, TEX.smoke, air, STYLES.Gust)
		puffs.Rate = 0
		puffs.LightEmission = 0.1
		puffs.Size = NumberSequence.new(1.2, 3)
		puffs.Lifetime = NumberRange.new(0.4, 0.6)
		puffs.Speed = NumberRange.new(14, 22)
		puffs.SpreadAngle = Vector2.new(22, 22)
		puffs.EmissionDirection = Enum.NormalId.Front
		puffs:Emit(12)
		Debris:AddItem(anchor, 1)
	end)
end

function SpellVfx.castBeat(parent: Instance, character: Model, poseName: string, color: Color3)
	local beat = CastPoses.BEATS[poseName]
	local run = if beat then BEATS[beat.kind] else nil
	if beat and run then
		run(parent, character, beat, color)
	end
end

-- Cast animation: the caster strikes the spell's pose (Spells/CastPoses via
-- CastAnimations), a glowing magic circle spins out under their feet, the glyph
-- they drew is imprinted on the ground, and the hand sparkles.
function SpellVfx.castAnimation(
	parent: Instance,
	character: Model,
	color: Color3,
	glyphId: string?,
	animation: string?,
	holdSeconds: number?
)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	-- Body pose (every client does this for every caster).
	CastAnimations.play(character, animation or "Throw", holdSeconds)
	-- The effect that rides on the pose (a fireball overhead, a slash trail, ...).
	SpellVfx.castBeat(parent, character, animation or "Throw", color)

	-- Magic circle under the feet.
	local circle = Instance.new("Part")
	circle.Shape = Enum.PartType.Cylinder
	circle.Anchored = true
	circle.CanCollide = false
	circle.CanQuery = false
	circle.CanTouch = false
	circle.Material = Enum.Material.Neon
	circle.Color = color
	circle.Transparency = 0.35
	circle.Size = Vector3.new(0.15, 2, 2)
	local feet = root.Position - Vector3.new(0, 2.9, 0)
	circle.CFrame = CFrame.new(feet) * CFrame.Angles(0, 0, math.pi / 2)
	circle.Parent = parent
	local inner = circle:Clone()
	inner.Color = Color3.new(1, 1, 1)
	inner.Transparency = 0.6
	inner.Size = Vector3.new(0.17, 1, 1)
	inner.Parent = parent
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(circle, info, {
		Size = Vector3.new(0.15, 7, 7),
		Transparency = 1,
		CFrame = circle.CFrame * CFrame.Angles(math.pi, 0, 0),
	}):Play()
	TweenService:Create(inner, info, { Size = Vector3.new(0.17, 4.5, 4.5), Transparency = 1 })
		:Play()
	Debris:AddItem(circle, 0.5)
	Debris:AddItem(inner, 0.5)

	-- The glyph you drew, imprinted on the ground under the caster.
	if glyphId then
		local plate = Instance.new("Part")
		plate.Name = "GlyphImprint"
		plate.Anchored = true
		plate.CanCollide = false
		plate.CanQuery = false
		plate.CanTouch = false
		plate.Transparency = 1
		plate.Size = Vector3.new(7, 0.1, 7)
		plate.CFrame = CFrame.new(feet + Vector3.new(0, 0.15, 0))
			* CFrame.Angles(0, math.rad(root.Orientation.Y), 0)
		plate.Parent = parent
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(220, 220)
		gui.LightInfluence = 0
		gui.Brightness = 3
		gui.Parent = plate
		local view =
			GlyphView.create(gui, glyphId, 200, color, { Position = UDim2.fromOffset(10, 10) })
		if view then
			task.delay(0.15, function()
				for _, line in view:GetChildren() do
					if line:IsA("Frame") then
						TweenService:Create(
							line,
							TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{
								BackgroundTransparency = 1,
							}
						):Play()
					end
				end
			end)
		end
		TweenService:Create(plate, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {
			CFrame = plate.CFrame * CFrame.Angles(0, math.rad(80), 0),
		}):Play()
		Debris:AddItem(plate, 0.8)
	end

	-- Hand sparkle.
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		local attachment = Instance.new("Attachment")
		attachment.Parent = hand
		local style = STYLES.default
		local e = emitter(attachment, TEX.sparkle, color, style)
		e.Rate = 0
		e:Emit(14)
		Debris:AddItem(attachment, 0.6)
	end
end

-- A buff's lingering look on the caster (Fire Boost, Water Body, Air Boost, Air
-- Shield): particles rising from or swirling round them and an outline, until
-- the buff ends. A recast replaces the previous aura.
function SpellVfx.buffAura(character: Model, styleKey: string, duration: number)
	local aura = VfxStyles.AURAS[styleKey]
	local root = character:FindFirstChild("HumanoidRootPart")
	if not aura or not root or not root:IsA("BasePart") then
		return
	end
	local name = "Aura_" .. styleKey
	for _, old in { root:FindFirstChild(name), character:FindFirstChild(name) } do
		old:Destroy()
	end

	local holder = Instance.new("Attachment")
	holder.Name = name
	holder.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Texture = aura.texture
	e.Color = ColorSequence.new(aura.color, aura.color:Lerp(Color3.new(1, 1, 1), 0.5))
	e.LightEmission = 0.8
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, aura.size * 0.4),
		NumberSequenceKeypoint.new(0.3, aura.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(aura.lifetime * 0.6, aura.lifetime)
	e.Speed = NumberRange.new(aura.speed * 0.5, aura.speed)
	e.SpreadAngle = Vector2.new(30, 30)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, aura.lift, 0)
	e.Rate = aura.rate
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Parent = holder
	if aura.light then
		local light = Instance.new("PointLight")
		light.Color = aura.color
		light.Range = aura.light
		light.Brightness = 2
		light.Parent = holder
	end

	local highlight: Highlight? = nil
	if aura.outline then
		local h = Instance.new("Highlight")
		h.Name = name
		h.FillColor = aura.color
		h.OutlineColor = aura.outline
		h.FillTransparency = aura.fill or 1
		h.OutlineTransparency = 0.1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = character
		highlight = h
	end

	-- Four small blocks orbit the caster (water bubbles, wind blades).
	local orbiters: { Part } = {}
	if aura.spin then
		for i = 1, 4 do
			local bit = Instance.new("Part")
			bit.Name = name
			bit.Anchored = true
			bit.CanCollide = false
			bit.CanQuery = false
			bit.CanTouch = false
			bit.CastShadow = false
			bit.Material = Enum.Material.Neon
			bit.Color = aura.color
			bit.Transparency = 0.2
			bit.Size = Vector3.new(0.7, 0.7, 0.7)
			bit.Parent = character
			orbiters[i] = bit
		end
	end

	local function cleanup()
		holder:Destroy()
		if highlight then
			highlight:Destroy()
		end
		for _, bit in orbiters do
			bit:Destroy()
		end
	end
	every(duration, function(t)
		if not root.Parent or not holder.Parent then
			cleanup()
			return false
		end
		for i, bit in orbiters do
			local angle = t * 3.2 + i * math.pi / 2
			bit.CFrame = root.CFrame
				* CFrame.new(
					math.cos(angle) * 3.4,
					math.sin(t * 2 + i) * 1.4,
					math.sin(angle) * 3.4
				)
				* CFrame.Angles(t * 2, t * 3, 0)
		end
		return true
	end)
	task.delay(duration, cleanup)
end

-- Breaks a block into tumbling chunks that fade out.
function SpellVfx.shatter(
	parent: Instance,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material
)
	local nx = math.clamp(math.round(size.X / 1.5), 1, 3)
	local ny = math.clamp(math.round(size.Y / 1.5), 1, 3)
	local nz = math.clamp(math.round(size.Z / 1.5), 1, 2)
	local chunk = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
	for x = 1, nx do
		for y = 1, ny do
			for z = 1, nz do
				local piece = Instance.new("Part")
				piece.Size = chunk * (0.7 + math.random() * 0.25)
				piece.Color = color
				piece.Material = material
				piece.CanCollide = true
				piece.CanQuery = false
				piece.CanTouch = false
				piece.Massless = true
				local offset = Vector3.new(
					(x - (nx + 1) / 2) * chunk.X,
					(y - (ny + 1) / 2) * chunk.Y,
					(z - (nz + 1) / 2) * chunk.Z
				)
				piece.CFrame = cframe * CFrame.new(offset)
				local outward = cframe:VectorToWorldSpace(offset)
				if outward.Magnitude < 0.01 then
					outward = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
				end
				piece.AssemblyLinearVelocity = outward.Unit * math.random(12, 26)
					+ Vector3.new(0, math.random(10, 22), 0)
				piece.AssemblyAngularVelocity =
					Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
				piece.Parent = parent
				task.delay(1.2, function()
					if piece.Parent then
						TweenService:Create(piece, TweenInfo.new(0.5), { Transparency = 1 }):Play()
					end
				end)
				Debris:AddItem(piece, 1.8)
			end
		end
	end
	local dust = anchorAt(parent, cframe.Position)
	local e = emitter(dust, TEX.smoke, color:Lerp(Color3.new(0.6, 0.6, 0.6), 0.5), STYLES.default)
	e.Rate = 0
	e.LightEmission = 0
	e.Size = NumberSequence.new(1.5, 3)
	e.Lifetime = NumberRange.new(0.6, 0.9)
	e:Emit(10)
	Debris:AddItem(dust, 1)
end

-- A couple of small chips knocked off a block that took a hit.
function SpellVfx.chip(parent: Instance, position: Vector3, color: Color3)
	for _ = 1, 3 do
		local bit = Instance.new("Part")
		bit.Size = Vector3.one * (0.25 + math.random() * 0.3)
		bit.Color = color
		bit.CanCollide = false
		bit.CanQuery = false
		bit.CanTouch = false
		bit.CFrame = CFrame.new(
			position
				+ Vector3.new(
					math.random(-10, 10) / 10,
					math.random(0, 15) / 10,
					math.random(-10, 10) / 10
				)
		)
		bit.AssemblyLinearVelocity =
			Vector3.new(math.random(-12, 12), math.random(8, 18), math.random(-12, 12))
		bit.Parent = parent
		Debris:AddItem(bit, 0.8)
	end
end

-- Dust ring when something rises out of the ground.
function SpellVfx.dust(parent: Instance, position: Vector3, width: number, color: Color3)
	local anchor = anchorAt(parent, position + Vector3.new(0, 0.5, 0))
	local style = table.clone(STYLES.default)
	style.size = 2
	style.speed = 6
	style.lifetime = 0.7
	local e = emitter(anchor, TEX.smoke, color:Lerp(Color3.fromRGB(160, 140, 120), 0.6), style)
	e.Rate = 0
	e.LightEmission = 0
	e.SpreadAngle = Vector2.new(10, 180)
	e.EmissionDirection = Enum.NormalId.Top
	e:Emit(math.clamp(math.floor(width * 2), 8, 30))
	SpellVfx.shockwave(
		parent,
		position + Vector3.new(0, 0.2, 0),
		width * 0.7,
		color:Lerp(Color3.new(1, 1, 1), 0.4)
	)
	Debris:AddItem(anchor, 1)
end

-- Thin pale wind streaks that trail behind a character while it dashes: `count`
-- ribbons spread across its back that curve with the dash's arc, then fade out.
function SpellVfx.windStreaks(character: Model, count: number, seconds: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local lifetime = 0.45
	for i = 1, count do
		local spread = if count > 1 then (i - 1) / (count - 1) * 2 - 1 else 0 -- -1..1
		local x = spread * 1.5
		local y = 0.4 - math.abs(spread) * 0.5
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(x, y + 0.12, 0.6)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(x, y - 0.12, 0.6)
		bottom.Parent = root
		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = lifetime
		trail.FaceCamera = true
		trail.LightEmission = 0.5
		trail.Color = ColorSequence.new(Color3.fromRGB(235, 250, 240))
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		trail.Parent = root
		task.delay(seconds, function()
			trail.Enabled = false
		end)
		Debris:AddItem(trail, seconds + lifetime + 0.2)
		Debris:AddItem(top, seconds + lifetime + 0.2)
		Debris:AddItem(bottom, seconds + lifetime + 0.2)
	end
end

-- The glyph a player just drew pops up over their head, rises, and fades,
-- so everyone can see which spell they readied.
function SpellVfx.glyphEmblem(parent: Instance, character: Model, glyphId: string, color: Color3)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local anchor = anchorAt(parent, head.Position + Vector3.new(0, 4.5, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(110, 110)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Parent = anchor
	local view = GlyphView.create(gui, glyphId, 100, color, { Position = UDim2.fromOffset(5, 5) })
	if view then
		local pop = Instance.new("UIScale")
		pop.Scale = 0.2
		pop.Parent = view
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(0.55, function()
			for _, line in view:GetChildren() do
				if line:IsA("Frame") then
					TweenService:Create(line, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
						:Play()
				end
			end
		end)
	end
	TweenService
		:Create(anchor, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = anchor.CFrame + Vector3.new(0, 3, 0),
		})
		:Play()
	local sparks = emitter(anchor, TEX.sparkle, color, STYLES.default)
	sparks.Rate = 0
	sparks:Emit(16)
	Debris:AddItem(anchor, 1.2)
end

-- Elemental column erupting out of the ground (Fire Pillar, Water Nebula,
-- Earthquake): a tall glowing cylinder shoots up, then fades, with spray,
-- sparks, or rubble depending on the element.
function SpellVfx.pillar(
	parent: Instance,
	center: Vector3,
	radius: number,
	color: Color3,
	elementId: string?,
	modelName: string?
)
	local height = 70
	local width = math.max(radius * 1.5, 4)
	local column = Instance.new("Part")
	column.Name = "Pillar"
	column.Shape = Enum.PartType.Cylinder
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	column.CastShadow = false
	column.Material = if elementId == "Earth" then Enum.Material.Slate else Enum.Material.Neon
	column.Color = color
	column.Transparency = if elementId == "Earth" then 0.3 else 0.15
	column.Size = Vector3.new(height, 0.5, 0.5)
	column.CFrame = CFrame.new(center + Vector3.new(0, height / 2, 0))
		* CFrame.Angles(0, 0, math.pi / 2)
	column.Parent = parent
	-- The blocky model is the body of the column; the neon cylinder is its glow.
	local body = spawnModel(parent, modelName, width)
	if body then
		column.Transparency = 0.6
		local scale = body:GetScale()
		body:ScaleTo(scale * 0.2)
		body:PivotTo(CFrame.new(center))
		every(0.9, function(t)
			local grow = math.min(t / 0.14, 1)
			body:ScaleTo(scale * (0.2 + 0.8 * grow))
			body:PivotTo(CFrame.new(center) * CFrame.Angles(0, t * 3, 0))
			return body.Parent ~= nil
		end)
		task.delay(0.35, function()
			if body.Parent then
				fadeModel(body, 0.55)
			end
		end)
		Debris:AddItem(body, 1)
	end
	TweenService
		:Create(column, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(height, width, width),
		})
		:Play()
	task.delay(0.35, function()
		if column.Parent then
			TweenService
				:Create(
					column,
					TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{
						Size = Vector3.new(height, width * 1.3, width * 1.3),
						Transparency = 1,
					}
				)
				:Play()
		end
	end)
	-- A white-hot core inside the column.
	local core = column:Clone()
	core.Name = "PillarCore"
	core.Color = Color3.new(1, 1, 1)
	core.Material = Enum.Material.Neon
	core.Size = Vector3.new(height, 0.3, 0.3)
	core.Parent = parent
	TweenService:Create(core, TweenInfo.new(0.14, Enum.EasingStyle.Quad), {
		Size = Vector3.new(height, width * 0.45, width * 0.45),
	}):Play()
	TweenService:Create(core, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
	}):Play()

	local anchor = anchorAt(parent, center + Vector3.new(0, 1, 0))
	anchor.Size = Vector3.new(width, 2, width)
	local style = table.clone(STYLES.default)
	style.size = if elementId == "Earth" then 1.8 else 2.4
	style.speed = 22
	style.lifetime = 0.9
	local texture = if elementId == "Fire"
		then TEX.fire
		elseif elementId == "Earth" then TEX.smoke
		else TEX.sparkle
	local spray = emitter(anchor, texture, color, style)
	spray.Rate = 0
	spray.EmissionDirection = Enum.NormalId.Top
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.Acceleration = Vector3.new(0, -12, 0)
	spray.Shape = Enum.ParticleEmitterShape.Cylinder
	spray:Emit(60)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = radius * 3
	light.Brightness = 5
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	SpellVfx.shockwave(parent, center + Vector3.new(0, 0.3, 0), radius, color)
	if elementId == "Earth" then
		SpellVfx.dust(parent, center, radius, color)
	end
	Debris:AddItem(column, 1)
	Debris:AddItem(core, 1)
	Debris:AddItem(anchor, 1.4)
end

-- A boulder or stone pillar bursts up out of the ground after `delay`
-- seconds, holds a moment, and sinks back (Earth Punch, Earth Pillar).
function SpellVfx.rise(
	parent: Instance,
	center: Vector3,
	radius: number,
	delay: number,
	color: Color3,
	kind: string,
	height: number,
	modelName: string?
)
	task.delay(delay, function()
		-- The blocky model (Earth Punch's boulder, Earth Pillar's spike) rises
		-- instead of the plain shape.
		local model =
			spawnModel(parent, modelName, if kind == "boulder" then radius * 1.7 else radius * 1.2)
		if model then
			if kind ~= "boulder" then
				-- Spikes match the spell's height rather than its width.
				local _, tall = model:GetBoundingBox()
				model:ScaleTo(model:GetScale() * height / math.max(tall.Y, 0.01))
			end
			local _, size = model:GetBoundingBox()
			local depth = size.Y
			local yaw = math.random() * math.pi
			model:PivotTo(CFrame.new(center - Vector3.new(0, depth, 0)) * CFrame.Angles(0, yaw, 0))
			every(1.5, function(t)
				local lift = if t < 0.12
					then t / 0.12
					elseif t < 0.9 then 1
					else math.max(1 - (t - 0.9) / 0.45, 0)
				model:PivotTo(
					CFrame.new(center - Vector3.new(0, depth * (1 - lift), 0))
						* CFrame.Angles(0, yaw, 0)
				)
				return model.Parent ~= nil
			end)
			SpellVfx.dust(parent, center, radius * 0.8, color)
			Debris:AddItem(model, 1.5)
			return
		end
		local rock = Instance.new("Part")
		rock.Name = "RisingRock"
		rock.Anchored = true
		rock.CanCollide = false
		rock.CanQuery = false
		rock.CanTouch = false
		rock.Color = color
		rock.Material = Enum.Material.Slate
		local top: number
		if kind == "boulder" then
			rock.Shape = Enum.PartType.Ball
			rock.Size = Vector3.one * radius * 1.7
			top = center.Y + radius * 0.55
			rock.CFrame = CFrame.new(center.X, center.Y - radius, center.Z)
		else
			rock.Size = Vector3.new(radius * 0.9, height, radius * 0.9)
			top = center.Y + height / 2 - 0.5
			rock.CFrame = CFrame.new(center.X, center.Y - height / 2, center.Z)
				* CFrame.Angles(0, math.random() * math.pi, 0)
		end
		rock.Parent = parent
		TweenService
			:Create(rock, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(center.X, top, center.Z) * rock.CFrame.Rotation,
			})
			:Play()
		SpellVfx.dust(parent, center, radius * 0.8, color)
		task.delay(0.9, function()
			if rock.Parent then
				TweenService
					:Create(
						rock,
						TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{
							CFrame = rock.CFrame - Vector3.new(
								0,
								if kind == "boulder" then radius * 1.4 else height,
								0
							),
							Transparency = 1,
						}
					)
					:Play()
			end
		end)
		Debris:AddItem(rock, 1.5)
	end)
end

-- Earthquake wind-up: the ground pulses with rings and kicks up dust for
-- the whole cast, so everyone can see the blast zone and get out of it.
function SpellVfx.quake(
	parent: Instance,
	center: Vector3,
	radius: number,
	duration: number,
	color: Color3,
	modelName: string?
)
	-- Cracks spread over the blast zone while the caster channels.
	local cracks = spawnModel(parent, modelName, radius * 2)
	if cracks then
		cracks:PivotTo(CFrame.new(center + Vector3.new(0, 0.1, 0)))
		for _, part in cracks:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Root" then
				part.Transparency = 1
				TweenService
					:Create(
						part,
						TweenInfo.new(math.max(duration * 0.4, 0.2)),
						{ Transparency = 0 }
					)
					:Play()
			end
		end
		task.delay(duration + 0.2, function()
			if cracks.Parent then
				fadeModel(cracks, 0.8)
			end
		end)
		Debris:AddItem(cracks, duration + 1.2)
	end
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			SpellVfx.shockwave(
				parent,
				center + Vector3.new(0, 0.3, 0),
				radius * (0.35 + 0.65 * elapsed / duration),
				color
			)
			local angle = math.random() * math.pi * 2
			local distance = math.random() * radius * 0.9
			SpellVfx.dust(
				parent,
				center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance),
				6,
				color
			)
			task.wait(0.35)
			elapsed += 0.35
		end
	end)
end

return SpellVfx
