--!strict
-- Client-side spell visuals built only from Roblox's built-in particle
-- textures (no uploaded assets): bolt trails/particles per element, impact
-- bursts with a light flash and shockwave ring, the cast animation (arm
-- raise + magic circle + hand sparkle), block shatter chunks, chips, dust.
--
-- Everything here is cosmetic and local. Every function is safe to call
-- with characters/parts that may be mid-destroy.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local SpellVfx = {}

local TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

-- Per-spell look. Anything not listed uses `default` tinted with the
-- spell's own color.
export type Style = {
	texture: string,
	rate: number,
	size: number,
	speed: number,
	lifetime: number,
	trailWidth: number,
	lightRange: number,
	burst: number,
	tint: Color3?,
	secondary: string?, -- extra emitter texture (e.g. smoke behind fire)
}

local STYLES: { [string]: Style } = {
	default = {
		texture = TEX.sparkle,
		rate = 30,
		size = 0.6,
		speed = 2,
		lifetime = 0.4,
		trailWidth = 0.8,
		lightRange = 8,
		burst = 18,
	},
	Fireball = {
		texture = TEX.fire,
		rate = 60,
		size = 1.4,
		speed = 1,
		lifetime = 0.35,
		trailWidth = 1.4,
		lightRange = 12,
		burst = 30,
		tint = Color3.fromRGB(255, 140, 50),
		secondary = TEX.smoke,
	},
	WaterLock = {
		texture = TEX.sparkle,
		rate = 50,
		size = 0.7,
		speed = 1,
		lifetime = 0.6,
		trailWidth = 1,
		lightRange = 8,
		burst = 24,
		tint = Color3.fromRGB(90, 180, 255),
	},
	Gust = {
		texture = TEX.smoke,
		rate = 60,
		size = 3,
		speed = 4,
		lifetime = 0.45,
		trailWidth = 4,
		lightRange = 0,
		burst = 22,
		tint = Color3.fromRGB(235, 245, 255),
	},
	Zap = {
		texture = TEX.sparkle,
		rate = 120,
		size = 0.8,
		speed = 8,
		lifetime = 0.25,
		trailWidth = 0.6,
		lightRange = 18,
		burst = 34,
		tint = Color3.fromRGB(255, 250, 160),
	},
	Bullet = {
		texture = TEX.sparkle,
		rate = 40,
		size = 0.3,
		speed = 1,
		lifetime = 0.2,
		trailWidth = 0.35,
		lightRange = 5,
		burst = 10,
		tint = Color3.fromRGB(255, 213, 79),
	},
}

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

-- Impact burst: particles + a quick light flash + small shockwave.
function SpellVfx.impact(parent: Instance, position: Vector3, fxKey: string?, color: Color3)
	local style = SpellVfx.styleFor(fxKey)
	local tint = style.tint or color
	local anchor = anchorAt(parent, position)
	local e = emitter(anchor, style.texture, tint, style)
	e.Rate = 0
	e.Speed = NumberRange.new(style.speed * 3, style.speed * 6)
	e:Emit(style.burst)
	if style.lightRange > 0 then
		local light = Instance.new("PointLight")
		light.Color = tint
		light.Range = style.lightRange * 1.5
		light.Brightness = 4
		light.Parent = anchor
		TweenService:Create(light, TweenInfo.new(0.3), { Brightness = 0 }):Play()
	end
	SpellVfx.shockwave(parent, position, 4, tint)
	Debris:AddItem(anchor, 1)
end

-- Cast animation: the right arm snaps up toward the target, a glowing
-- magic circle spins out under the caster, and the hand sparkles.
local raised: { [Motor6D]: number } = setmetatable({}, { __mode = "k" }) :: any

local function shoulderOf(character: Model): (Motor6D?, CFrame)
	local upper = character:FindFirstChild("RightUpperArm")
	local r15 = upper and upper:FindFirstChild("RightShoulder")
	if r15 and r15:IsA("Motor6D") then
		return r15, CFrame.Angles(math.rad(95), 0, 0) -- raise forward
	end
	local torso = character:FindFirstChild("Torso")
	local r6 = torso and torso:FindFirstChild("Right Shoulder")
	if r6 and r6:IsA("Motor6D") then
		return r6, CFrame.Angles(0, 0, math.rad(95))
	end
	return nil, CFrame.identity
end

function SpellVfx.castAnimation(parent: Instance, character: Model, color: Color3)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	-- Arm raise (local C0 offset; every client does this for every caster).
	local motor, raise = shoulderOf(character)
	if motor then
		local base = motor:GetAttribute("BaseC0")
		if typeof(base) ~= "CFrame" then
			base = motor.C0
			motor:SetAttribute("BaseC0", base)
		end
		local token = (raised[motor] or 0) + 1
		raised[motor] = token
		TweenService:Create(motor, TweenInfo.new(0.08), { C0 = (base :: CFrame) * raise }):Play()
		task.delay(0.3, function()
			if raised[motor] == token and motor.Parent then
				TweenService:Create(motor, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { C0 = base })
					:Play()
			end
		end)
	end

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

return SpellVfx
