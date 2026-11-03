--!strict
-- The wand's 3D visuals (client only, local and cosmetic):
--   charge     while a player's canvas is open: the wand tip glows and sparks,
--              a rune circle turns at their feet, and a magic circle opens in
--              the air in front of them (rings, rune stones, and a star that
--              turn against each other), the backdrop their stroke is drawn on
--   ribbon     a drawing written in the air in front of the caster: a glowing
--              ribbon of light that follows the stroke, fed by a beam from the
--              wand tip; when it is done it flashes in its quality colour and
--              is pulled into the wand (or, if the magic couldn't read it,
--              turns red and crumbles)
--   airGlyph   the clean glyph traced by another player's wand (Fx "glyph")
--
-- The air canvas and its maths live in Util/WandAir; tunables in Config.WAND.
-- Everything here is safe with characters that are mid-destroy and works
-- without the wand model (the right hand stands in for the tip).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Glyphs = require(ReplicatedStorage.Shared.Spells.Glyphs)
local Quality = require(ReplicatedStorage.Shared.Spells.Quality)
local VfxStyles = require(ReplicatedStorage.Shared.Spells.VfxStyles)
local WandAir = require(ReplicatedStorage.Shared.Util.WandAir)

local WandVfx = {}

local TEX = VfxStyles.TEX
local BAD = Color3.fromRGB(239, 83, 80)
local WHITE = Color3.new(1, 1, 1)

-- Ribbon: core thickness, the halo around it, studs between points, and the
-- most segments one drawing may have.
local CORE = 0.2
local HALO = 0.55
local MIN_STEP = 0.22
local MAX_SEGMENTS = 240

-- Rune circle at the feet while drawing.
local RING_RADIUS = 3.4
local RING_BLOCKS = 20
local INNER_RADIUS = 2.3
local INNER_BLOCKS = 12

-- The magic circle in the air: blocks in its outer ring, its inner ring, its
-- rune stones, and the small ring in the middle of its star. It sits a little
-- behind the drawing, and spins up fast when it opens, then settles.
local CIRCLE_OUTER = 28
local CIRCLE_INNER = 20
local CIRCLE_STONES = 8
local CIRCLE_CORE = 12
local CIRCLE_BEHIND = 0.35
local SPIN_FAST = 7
local SPIN_SLOW = 0.5

export type Charge = {
	stop: () -> (),
	-- Lights the whole circle up in `color` (a drawing landed).
	flash: (color: Color3) -> (),
}

export type Ribbon = {
	-- True when the point was used (far enough from the last one).
	add: (self: Ribbon, offset: Vector2) -> boolean,
	finish: (self: Ribbon, ok: boolean, color: Color3?) -> (),
	cancel: (self: Ribbon) -> (),
}

-- The wand's crystal tip, or nil when the character has no wand.
function WandVfx.tipOf(character: Model): BasePart?
	local wand = character:FindFirstChild(Config.WAND.MODEL)
	local tip = wand and wand:FindFirstChild("Tip")
	return if tip and tip:IsA("BasePart") then tip else nil
end

-- Where the magic comes out: the wand tip, else the right hand, else the head.
local function sourceOf(character: Model): BasePart?
	local tip = WandVfx.tipOf(character)
	if tip then
		return tip
	end
	for _, name in { "RightHand", "Right Arm", "Head" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- The colour the server tinted the wand's tip (the player's element).
function WandVfx.colorOf(character: Model): Color3
	local tip = WandVfx.tipOf(character)
	return if tip then tip.Color else Color3.fromRGB(190, 130, 255)
end

-- The way a drawing player faces (WandService's DrawLook attribute), or nil.
function WandVfx.lookOf(character: Model): Vector3?
	local look = character:GetAttribute("DrawLook")
	return if typeof(look) == "Vector3" then look else nil
end

local function glowPart(parent: Instance, size: Vector3, color: Color3, ball: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	if ball then
		p.Shape = Enum.PartType.Ball
	end
	p.Parent = parent
	return p
end

local function sparkles(
	parent: Instance,
	color: Color3,
	size: number,
	rate: number
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX.sparkle
	e.Color = ColorSequence.new(color:Lerp(WHITE, 0.5), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.35, 0.7)
	e.Speed = NumberRange.new(1, 4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Rate = rate
	e.Parent = parent
	return e
end

local function fadeOut(part: BasePart, seconds: number)
	TweenService:Create(part, TweenInfo.new(seconds), { Transparency = 1 }):Play()
	Debris:AddItem(part, seconds + 0.05)
end

-- Where the feet are, for the rune circle.
local function feetOf(character: Model): Vector3?
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return nil
	end
	local below = if humanoid.RigType == Enum.HumanoidRigType.R15
		then humanoid.HipHeight + root.Size.Y / 2
		else root.Size.Y / 2 + 2
	return root.Position - Vector3.new(0, below - 0.08, 0)
end

-- A ring of neon blocks welded to an anchored hub, so turning the hub turns
-- the whole circle with one CFrame write a frame.
local function runeCircle(parent: Instance, color: Color3): (Part, { BasePart })
	local hub = Instance.new("Part")
	hub.Name = "WandRunes"
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CanTouch = false
	hub.Transparency = 1
	hub.Size = Vector3.one * 0.2
	hub.Parent = parent
	local parts: { BasePart } = {}
	local function ring(
		radius: number,
		count: number,
		size: Vector3,
		transparency: number,
		offset: number
	)
		for i = 1, count do
			local angle = (i + offset) / count * math.pi * 2
			local block = glowPart(hub, size, color)
			block.Anchored = false
			block.Massless = true
			block.Transparency = 1
			block:SetAttribute("Target", transparency)
			block.CFrame = hub.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hub
			weld.Part1 = block
			weld.Parent = block
			table.insert(parts, block)
		end
	end
	ring(RING_RADIUS, RING_BLOCKS, Vector3.new(RING_RADIUS * 6.3 / RING_BLOCKS, 0.1, 0.16), 0.15, 0)
	ring(
		INNER_RADIUS,
		INNER_BLOCKS,
		Vector3.new(INNER_RADIUS * 6.3 / INNER_BLOCKS * 0.6, 0.1, 0.12),
		0.45,
		0.5
	)
	-- Four rune stones on the outer ring.
	for i = 0, 3 do
		local stone = glowPart(hub, Vector3.new(0.5, 0.14, 0.5), color:Lerp(WHITE, 0.35))
		stone.Anchored = false
		stone.Massless = true
		stone.Transparency = 1
		stone:SetAttribute("Target", 0)
		stone.CFrame = hub.CFrame
			* CFrame.Angles(0, i * math.pi / 2, 0)
			* CFrame.new(0, 0.02, -RING_RADIUS)
			* CFrame.Angles(0, math.pi / 4, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hub
		weld.Part1 = stone
		weld.Parent = stone
		table.insert(parts, stone)
	end
	return hub, parts
end

-- Welds `part` to an anchored hub (moving the hub moves the part) and marks
-- the transparency it fades in to.
local function onHub(hub: BasePart, part: BasePart, cframe: CFrame, target: number)
	part.Anchored = false
	part.Massless = true
	part.Transparency = 1
	part:SetAttribute("Target", target)
	part:SetAttribute("Base", part.Color)
	part.CFrame = hub.CFrame * cframe
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hub
	weld.Part1 = part
	weld.Parent = part
end

local function hubPart(parent: Instance, name: string): Part
	local hub = Instance.new("Part")
	hub.Name = name
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CanTouch = false
	hub.Transparency = 1
	hub.Size = Vector3.one * 0.2
	hub.Parent = parent
	return hub
end

-- A ring of `count` blocks of `radius` in a hub's XY plane (its face).
local function airRing(
	hub: BasePart,
	parts: { BasePart },
	color: Color3,
	radius: number,
	count: number,
	width: number,
	target: number
)
	local chord = radius * math.pi * 2 / count * 1.06
	for i = 1, count do
		local angle = i / count * math.pi * 2
		local block = glowPart(hub, Vector3.new(width, chord, 0.06), color)
		onHub(hub, block, CFrame.Angles(0, 0, angle) * CFrame.new(radius, 0, 0), target)
		table.insert(parts, block)
	end
end

-- The magic circle in the air: an outer hub (glass disc, two rings, rune
-- stones) and a star hub (a six-pointed star and a small ring) that turn
-- against each other. Both hubs face along their -Z.
local function magicCircle(parent: Instance, color: Color3): (Part, Part, { BasePart }, PointLight)
	local radius = Config.WAND.CIRCLE_RADIUS
	local outer = hubPart(parent, "MagicCircle")
	local star = hubPart(parent, "MagicStar")
	local parts: { BasePart } = {}

	local disc = glowPart(outer, Vector3.new(0.04, radius * 2, radius * 2), color)
	disc.Shape = Enum.PartType.Cylinder
	onHub(outer, disc, CFrame.Angles(0, math.pi / 2, 0), 0.9)
	table.insert(parts, disc)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 0
	light.Shadows = false
	light.Parent = disc

	airRing(outer, parts, color:Lerp(WHITE, 0.15), radius, CIRCLE_OUTER, 0.16, 0.05)
	airRing(outer, parts, color, radius * 0.86, CIRCLE_INNER, 0.08, 0.35)
	for i = 1, CIRCLE_STONES do
		local angle = (i + 0.5) / CIRCLE_STONES * math.pi * 2
		local stone = glowPart(outer, Vector3.new(0.3, 0.3, 0.08), color:Lerp(WHITE, 0.45))
		onHub(
			outer,
			stone,
			CFrame.Angles(0, 0, angle)
				* CFrame.new(radius * 0.93, 0, 0)
				* CFrame.Angles(0, 0, math.pi / 4),
			0
		)
		table.insert(parts, stone)
	end

	-- Two triangles make the star; its points touch the inner ring.
	local tip = radius * 0.86
	for flip = 0, 1 do
		local corners: { Vector3 } = {}
		for k = 0, 2 do
			local angle = math.pi / 2 + flip * math.pi + k * math.pi * 2 / 3
			table.insert(corners, Vector3.new(math.cos(angle) * tip, math.sin(angle) * tip, 0))
		end
		for k = 1, 3 do
			local from, to = corners[k], corners[k % 3 + 1]
			local delta = to - from
			local bar = glowPart(star, Vector3.new(delta.Magnitude, 0.07, 0.05), color)
			onHub(
				star,
				bar,
				CFrame.new((from + to) / 2) * CFrame.Angles(0, 0, math.atan2(delta.Y, delta.X)),
				0.5
			)
			table.insert(parts, bar)
		end
	end
	airRing(star, parts, color, tip * 0.5, CIRCLE_CORE, 0.06, 0.55)
	return outer, star, parts, light
end

-- Lights a character's wand while their canvas is open, and opens the magic
-- circle on the upright air canvas facing `look()` (WandAir.facing). Returns
-- a handle that puts it all out or flashes it.
function WandVfx.charge(
	parent: Instance,
	character: Model,
	color: Color3,
	look: () -> Vector3?
): Charge
	local source = sourceOf(character)
	local light: PointLight? = nil
	local emitter: ParticleEmitter? = nil
	if source then
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = 9
		l.Brightness = 0
		l.Shadows = false
		l.Parent = source
		TweenService:Create(l, TweenInfo.new(0.25), { Brightness = 3 }):Play()
		light = l
		emitter = sparkles(source, color, 0.35, 28)
	end

	local hub, parts = runeCircle(parent, color)
	local circle, star, circleParts, circleLight = magicCircle(parent, color)
	for _, part in circleParts do
		table.insert(parts, part)
	end
	for _, part in parts do
		TweenService
			:Create(part, TweenInfo.new(0.35), { Transparency = part:GetAttribute("Target") or 0 })
			:Play()
	end
	TweenService:Create(circleLight, TweenInfo.new(0.35), { Brightness = 1.6 }):Play()

	local opened = os.clock()
	local angle = 0
	local spin = 0
	local function place(dt: number)
		local feet = feetOf(character)
		local root = character:FindFirstChild("HumanoidRootPart")
		if not feet or not root or not root:IsA("BasePart") or not character.Parent then
			return
		end
		angle += dt * 0.9
		hub.CFrame = CFrame.new(feet) * CFrame.Angles(0, angle, 0)
		-- Spins up fast as it opens (or flashes), then settles to a slow turn.
		local speed = SPIN_SLOW + (SPIN_FAST - SPIN_SLOW) * math.exp(-(os.clock() - opened) * 3)
		spin += dt * speed
		local frame = WandAir.facing(root.Position, look() or root.CFrame.LookVector)
			* CFrame.new(0, 0, -CIRCLE_BEHIND)
		circle.CFrame = frame * CFrame.Angles(0, 0, spin)
		star.CFrame = frame * CFrame.Angles(0, 0, -spin * 1.6)
	end
	local connection = RunService.Heartbeat:Connect(place)
	place(0)

	local stopped = false
	local handle = {}
	function handle.stop()
		if stopped then
			return
		end
		stopped = true
		connection:Disconnect()
		if emitter then
			emitter.Enabled = false
			Debris:AddItem(emitter, 0.8)
		end
		if light then
			TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 0 }):Play()
			Debris:AddItem(light, 0.3)
		end
		TweenService:Create(circleLight, TweenInfo.new(0.3), { Brightness = 0 }):Play()
		for _, part in parts do
			TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
		Debris:AddItem(hub, 0.35)
		Debris:AddItem(circle, 0.35)
		Debris:AddItem(star, 0.35)
	end
	function handle.flash(flashColor: Color3)
		if stopped then
			return
		end
		opened = os.clock() -- a burst of spin
		local bright = flashColor:Lerp(WHITE, 0.3)
		for _, part in circleParts do
			part.Color = bright
			local base = part:GetAttribute("Base")
			TweenService:Create(part, TweenInfo.new(0.5), {
				Color = if typeof(base) == "Color3" then base else color,
			}):Play()
		end
		circleLight.Color = flashColor
		circleLight.Brightness = 5
		TweenService:Create(circleLight, TweenInfo.new(0.5), { Brightness = 1.6, Color = color })
			:Play()
	end
	return handle :: Charge
end

-- The flash and sparks when a glyph lands in the wand.
local function absorbBurst(parent: Instance, at: Vector3, color: Color3)
	local flash = glowPart(parent, Vector3.one * 0.5, color:Lerp(WHITE, 0.3), true)
	flash.CFrame = CFrame.new(at)
	flash.Transparency = 0.1
	TweenService
		:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * 3.2,
			Transparency = 1,
		})
		:Play()
	Debris:AddItem(flash, 0.35)
	local anchor = glowPart(parent, Vector3.one * 0.2, color)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(at)
	local burst = sparkles(anchor, color, 0.5, 0)
	burst.Speed = NumberRange.new(6, 14)
	burst:Emit(36)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 5
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	Debris:AddItem(anchor, 1)
end

-- A smoky fizzle where a drawing failed.
local function fizzle(parent: Instance, at: Vector3)
	local anchor = glowPart(parent, Vector3.one * 0.2, BAD)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(at)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = TEX.smoke
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 80, 100))
	smoke.Size = NumberSequence.new(1.2, 3)
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Lifetime = NumberRange.new(0.6, 1)
	smoke.Speed = NumberRange.new(1, 3)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = anchor
	smoke:Emit(10)
	Debris:AddItem(anchor, 1.2)
end

-- Starts a drawing in the air on `frame` (see WandAir.frame). Call add() with
-- each stroke point (studs on the canvas), then finish() or cancel().
function WandVfx.ribbon(parent: Instance, character: Model, frame: CFrame, color: Color3): Ribbon
	local folder = Instance.new("Folder")
	folder.Name = "WandRibbon"
	folder.Parent = parent
	local pieces: { BasePart } = {}
	local last: Vector3? = nil
	local done = false

	-- The spark at the pen, and the beam that feeds it from the wand tip.
	local spark = glowPart(folder, Vector3.one * 0.45, color:Lerp(WHITE, 0.4), true)
	spark.Transparency = 1
	local sparkEmitter = sparkles(spark, color, 0.3, 40)
	sparkEmitter.Enabled = false
	local sparkLight = Instance.new("PointLight")
	sparkLight.Color = color
	sparkLight.Range = 8
	sparkLight.Brightness = 2
	sparkLight.Parent = spark
	local sparkAttachment = Instance.new("Attachment")
	sparkAttachment.Parent = spark

	local tipAttachment: Attachment? = nil
	local beam: Beam? = nil
	local tip = WandVfx.tipOf(character)
	if tip then
		local a = Instance.new("Attachment")
		a.Name = "WandBeamTip"
		a.Parent = tip
		tipAttachment = a
		local b = Instance.new("Beam")
		b.Attachment0 = a
		b.Attachment1 = sparkAttachment
		b.Color = ColorSequence.new(color:Lerp(WHITE, 0.5), color)
		b.LightEmission = 1
		b.LightInfluence = 0
		b.FaceCamera = true
		b.Width0 = 0.12
		b.Width1 = 0.22
		b.CurveSize0 = 1.2
		b.CurveSize1 = -0.6
		b.Segments = 12
		b.Transparency = NumberSequence.new(0.15, 0.35)
		b.Enabled = false
		b.Parent = folder
		beam = b
	end

	local self = {} :: any

	function self.add(_: any, offset: Vector2): boolean
		if done then
			return false
		end
		local point = WandAir.toWorld(frame, offset)
		spark.CFrame = CFrame.new(point)
		if not last then
			last = point
			spark.Transparency = 0
			sparkEmitter.Enabled = true
			if beam then
				beam.Enabled = true
			end
			local dot = glowPart(folder, Vector3.one * CORE * 1.3, color, true)
			dot.CFrame = CFrame.new(point)
			table.insert(pieces, dot)
			return true
		end
		local from = last :: Vector3
		local length = (point - from).Magnitude
		if length < MIN_STEP or #pieces >= MAX_SEGMENTS * 3 then
			return false
		end
		local mid = (from + point) / 2
		local cframe = CFrame.lookAt(mid, point)
		local core =
			glowPart(folder, Vector3.new(CORE, CORE, length + CORE * 0.5), color:Lerp(WHITE, 0.25))
		core.CFrame = cframe
		local halo = glowPart(folder, Vector3.new(HALO, HALO, length + HALO * 0.3), color)
		halo.Transparency = 0.72
		halo.CFrame = cframe
		local joint = glowPart(folder, Vector3.one * CORE * 1.3, color:Lerp(WHITE, 0.25), true)
		joint.CFrame = CFrame.new(point)
		table.insert(pieces, core)
		table.insert(pieces, halo)
		table.insert(pieces, joint)
		-- New ink pops in slightly thick, then settles.
		core.Size = Vector3.new(CORE * 2, CORE * 2, core.Size.Z)
		TweenService
			:Create(core, TweenInfo.new(0.15), { Size = Vector3.new(CORE, CORE, core.Size.Z) })
			:Play()
		last = point
		return true
	end

	local function stopFeed()
		sparkEmitter.Enabled = false
		if beam then
			beam:Destroy()
		end
		if tipAttachment then
			tipAttachment:Destroy()
		end
		TweenService:Create(sparkLight, TweenInfo.new(0.2), { Brightness = 0 }):Play()
		TweenService:Create(spark, TweenInfo.new(0.2), { Transparency = 1 }):Play()
	end

	function self.finish(_: any, ok: boolean, finalColor: Color3?)
		if done then
			return
		end
		done = true
		stopFeed()
		if #pieces == 0 then
			Debris:AddItem(folder, 0.3)
			return
		end
		if not ok then
			-- The magic couldn't read it: it turns red and crumbles.
			for _, piece in pieces do
				piece.Color = BAD
				piece.Anchored = false
				piece.AssemblyLinearVelocity =
					Vector3.new(math.random() * 4 - 2, math.random() * 3, math.random() * 4 - 2)
				fadeOut(piece, 0.6)
			end
			fizzle(folder, frame.Position)
			Debris:AddItem(folder, 1.3)
			return
		end
		-- It worked: flash in the quality colour, then pull it into the wand.
		local flashColor = finalColor or color
		for _, piece in pieces do
			piece.Color = flashColor:Lerp(WHITE, if piece.Transparency > 0.5 then 0 else 0.3)
		end
		task.delay(0.12, function()
			local source = sourceOf(character)
			local target = if source then source.Position else frame.Position
			local count = #pieces
			for index, piece in pieces do
				local delay = (index / count) * 0.18
				TweenService:Create(
					piece,
					TweenInfo.new(
						0.28,
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.In,
						0,
						false,
						delay
					),
					{ CFrame = CFrame.new(target), Size = Vector3.one * 0.05, Transparency = 1 }
				):Play()
			end
			task.delay(0.45, function()
				local now = sourceOf(character)
				absorbBurst(parent, if now then now.Position else target, flashColor)
			end)
			Debris:AddItem(folder, 0.6)
		end)
	end

	function self.cancel(_: any)
		if done then
			return
		end
		done = true
		stopFeed()
		for _, piece in pieces do
			fadeOut(piece, 0.15)
		end
		Debris:AddItem(folder, 0.3)
	end

	return self :: Ribbon
end

-- Another player's drawing: the clean glyph traced by their wand in the air
-- in front of them over Config.WAND.TRACE_SECONDS, then pulled into the wand.
function WandVfx.airGlyph(
	parent: Instance,
	character: Model,
	glyphId: string,
	color: Color3,
	quality: number?
)
	local glyph = Glyphs.get(glyphId)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not glyph or not root or not root:IsA("BasePart") then
		return
	end
	local frame = WandAir.facing(root.Position, WandVfx.lookOf(character) or root.CFrame.LookVector)
	local ribbon = WandVfx.ribbon(parent, character, frame, color)
	local points: { Vector2 } = {}
	for _, p in glyph.points do
		table.insert(points, WandAir.fromGlyph(p))
	end
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	local finalColor = if quality then Quality.tier(quality).color else color
	if total <= 0 then
		ribbon:finish(true, finalColor)
		return
	end
	ribbon:add(points[1])
	local elapsed = 0
	local index = 2
	local walked = 0 -- distance up to points[index - 1]
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local goal = math.min(1, elapsed / Config.WAND.TRACE_SECONDS) * total
		while index <= #points do
			local from, to = points[index - 1], points[index]
			local segment = (to - from).Magnitude
			if walked + segment <= goal then
				ribbon:add(to)
				walked += segment
				index += 1
			else
				local along = math.max(0, goal - walked)
				if segment > 0 then
					ribbon:add(from + (to - from) * (along / segment))
				end
				break
			end
		end
		if index > #points or not character.Parent then
			connection:Disconnect()
			ribbon:finish(character.Parent ~= nil, finalColor)
		end
	end)
end

return WandVfx
