--!strict
-- Renders cosmetic effects the server only announces (Fx remote):
--   projectile     (id, origin, direction, speed, range, visual)  flying bolt
--   projectileEnd  (id, position)                                  remove bolt
--   poof           (position, color)                               debris burst
--   beam           (from, to, color)                               chain flash
--   number         (position, amount, kind)                        floating damage/heal/shield number
--   cast           (character, spellId, target)                    cast pose + magic circle (+ buff aura)
--   shatter        (cframe, size, color, material)                 block breaks into chunks
--   chip           (position, color)                               chips off a damaged block
--   dust           (position, width, color)                        dust ring under a placed object
--   shockwave      (position, radius, color)                       ground ring for slams/bursts
--   strike         (center, radius, delay, modelName, color, spellId?)  a bolt model slams down after `delay`
--   modelPop       (character, modelName, color)                   a model pops up over a head and fades
--   glyph          (character, glyphId, color)                     the drawn glyph pops over a head
--   dash           (character, direction)                          dash pose, dust puff, and whoosh
--   pillar         (center, radius, color, elementId, spellId)     element column erupts (Fire Pillar...)
--   rise           (center, radius, delay, color, kind, height, model?)  boulder/pillar rises from the ground
--   quake          (center, radius, duration, color, model?)       Earthquake wind-up rumble and cracks
--   vortex         (center, radius, duration, color, coreHeight, spellId)  Black Hole swirl, hum, and collapse
--   suck           (victim, center, seconds, color, coreHeight)    streaming motes off something caught by a Black Hole
--   muzzle         (position, direction, spellId)                  turret muzzle flash and shot sound
--   deploy         (position, color, spellId)                      turret online: scan ring, radar sweep, chime
-- and spins parts/models tagged "SpinFx" locally.
-- The looks live in Fx/SpellVfx.
--
-- The server stays authoritative for hits; visuals here are a straight-line
-- prediction that is removed when the server says the projectile ended.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CastPoses = require(ReplicatedStorage.Shared.Spells.CastPoses)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local SpellRegistry = require(ReplicatedStorage.Shared.Spells.SpellRegistry)
local Types = require(ReplicatedStorage.Shared.Types)
local CastAnimations = require(script.Parent.Parent.Fx.CastAnimations)
local SpellVfx = require(script.Parent.Parent.Fx.SpellVfx)
local AudioController = require(script.Parent.AudioController)
local JuiceController = require(script.Parent.JuiceController)
local Theme = require(script.Parent.Parent.UI.Theme)

local NUMBER_COLORS: { [string]: Color3 } = {
	damage = Color3.fromRGB(255, 241, 118),
	heal = Color3.fromRGB(129, 199, 132),
	shield = Color3.fromRGB(129, 212, 250),
}

local player = Players.LocalPlayer

local FxController = {}

-- Don't draw effects in arenas far from us (matches run side by side). Wide
-- enough that the hub's far rim still sees the duels fought below the island.
local DRAW_DISTANCE = 900
local MAX_DEBRIS = 120

-- A bolt whose visual has `model` is drawn with that imported model
-- (ReplicatedStorage.Models) instead of a plain shape. Its width is the
-- spell's visual size times this factor (default 1).
-- Seconds a bolt takes to swell from a small spark to full size as it leaves
-- the caster. Turret bullets are born full size.
local BOLT_GROW = 0.25
local BOLT_GROW_FROM = 0.2

local BOLT_WIDTH: { [string]: number } = {
	Fireball = 1.6,
	WaterBubble = 1.3,
	Gust = 1,
}

type Bolt = {
	part: BasePart, -- the part particles/trails hang on (the model's Root)
	model: Model?,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	born: number,
	fxKey: string?,
	color: Color3,
	baseScale: number, -- the model's full scale, or 1 for a plain shape
	baseSize: Vector3, -- a plain shape's full size
}

local bolts: { [number]: Bolt } = {}
local debrisCount = 0
local folder: Folder

local function near(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= DRAW_DISTANCE
end

local function shapeOf(shape: string): Enum.PartType
	return if shape == "Ball"
		then Enum.PartType.Ball
		elseif shape == "Cylinder" then Enum.PartType.Cylinder
		elseif shape == "Wedge" then Enum.PartType.Wedge
		else Enum.PartType.Block
end

local function onProjectile(
	id: number,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	visual: Types.Visual,
	fxKey: string?
)
	if not near(origin) then
		return
	end
	local facing = CFrame.lookAt(origin, origin + direction)
	local part: BasePart? = nil
	local model: Model? = nil
	local modelName = visual.model
	if modelName then
		model = ModelKit.clone(modelName, "effect")
		if model then
			local width = model:GetExtentsSize().X
			model:ScaleTo((visual.size.X * (BOLT_WIDTH[modelName] or 1)) / math.max(width, 0.01))
			model:PivotTo(facing)
			part = model.PrimaryPart
			model.Parent = folder
		end
	end
	if not part then
		-- No imported model in this place: a plain shape from the spell's visual.
		local shape = Instance.new("Part")
		shape.Shape = shapeOf(visual.shape)
		shape.Size = visual.size
		shape.Color = visual.color
		shape.Material = visual.material
		shape.Transparency = visual.transparency or 0
		shape.Anchored = true
		shape.CanCollide = false
		shape.CanQuery = false
		shape.CanTouch = false
		shape.CastShadow = false
		shape.CFrame = facing
		shape.Parent = folder
		part = shape
	end
	SpellVfx.decorateBolt(part :: BasePart, fxKey, visual.color)
	local baseScale = if model then model:GetScale() else 1
	local baseSize = (part :: BasePart).Size
	if fxKey ~= "Bullet" then
		if model then
			model:ScaleTo(baseScale * BOLT_GROW_FROM)
		else
			(part :: BasePart).Size = baseSize * BOLT_GROW_FROM
		end
	end
	bolts[id] = {
		part = part :: BasePart,
		model = model,
		origin = origin,
		direction = direction,
		speed = speed,
		range = range,
		born = os.clock(),
		fxKey = fxKey,
		color = visual.color,
		baseScale = baseScale,
		baseSize = baseSize,
	}
end

local function onProjectileEnd(id: number, position: Vector3)
	local bolt = bolts[id]
	if bolt then
		bolts[id] = nil
		local facing = CFrame.lookAt(position, position + bolt.direction)
		if bolt.model then
			bolt.model:PivotTo(facing)
			-- Hide the meshes; the Root stays a moment so the trail can fade.
			for _, child in bolt.model:GetDescendants() do
				if child:IsA("BasePart") and child ~= bolt.part then
					child.Transparency = 1
				end
			end
		else
			bolt.part.CFrame = facing
			bolt.part.Transparency = 1
		end
		-- Let the trail/particles finish before removing the bolt.
		for _, child in bolt.part:GetChildren() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		Debris:AddItem(bolt.model or bolt.part, 0.4)
		if near(position) then
			SpellVfx.impact(folder, position, bolt.fxKey, bolt.color)
			if bolt.fxKey then
				AudioController.playSpell(bolt.fxKey, "impact", position)
				-- Bolts with no spell of their own (turret bullets) use their style's cue.
				local hitCue = SpellVfx.styleFor(bolt.fxKey).hitCue
				if hitCue then
					AudioController.play(hitCue, position)
				end
			end
		end
	end
end

local function onCast(character: Model, spellId: string, _target: Vector3)
	if typeof(character) ~= "Instance" or not character.Parent then
		return
	end
	local def = SpellDefinitions.get(spellId)
	local root = character:FindFirstChild("HumanoidRootPart")
	if def and root and root:IsA("BasePart") and near(root.Position) then
		-- A channelled spell (Earthquake) holds its pose for the whole channel.
		local channel = if def.stats.channel then def.stats.delay else nil
		SpellVfx.castAnimation(
			folder,
			character,
			def.visual.color,
			def.glyph,
			SpellRegistry.animationFor(spellId),
			channel
		)
		AudioController.playSpell(spellId, "cast", root.Position)
		if character == player.Character then
			JuiceController.cast(def.cooldown)
		end
		-- The sound of the pose's beat (a stomp's thud lands when the foot does).
		local beat = CastPoses.BEATS[SpellRegistry.animationFor(spellId) or ""]
		if beat and beat.cue then
			local cue = beat.cue
			task.delay(beat.at, function()
				if root.Parent then
					AudioController.play(cue, root.Position)
				end
			end)
		end
		-- Buffs (Fire Boost, Water Body, Air Boost, Air Shield) glow on the caster.
		local styleKey = SpellRegistry.vfxFor(spellId)
		if def.archetype == "Buff" and styleKey and def.stats.duration then
			SpellVfx.buffAura(character, styleKey, def.stats.duration)
		end
	end
end

-- Elemental column (Fire Pillar, Water Nebula, Earthquake).
local function onPillar(
	center: Vector3,
	radius: number,
	color: Color3,
	elementId: string,
	spellId: string?
)
	if not near(center) then
		return
	end
	-- A channelled column (Earthquake) has no column model: its model is the
	-- cracks drawn during the wind-up.
	local def = if spellId then SpellDefinitions.get(spellId) else nil
	local modelName = if def and not def.stats.channel then def.visual.model else nil
	SpellVfx.pillar(folder, center, radius, color, elementId, modelName)
	if spellId then
		AudioController.playSpell(spellId, "impact", center)
	end
end

-- A boulder / stone pillar rises out of the ground (Earth Punch, Earth Pillar).
local function onRise(
	center: Vector3,
	radius: number,
	delay: number,
	color: Color3,
	kind: string,
	height: number,
	modelName: string?
)
	if not near(center) then
		return
	end
	SpellVfx.rise(folder, center, radius, delay, color, kind, height, modelName)
	task.delay(delay, function()
		AudioController.play("rockBreak", center)
	end)
end

-- Earthquake wind-up.
local function onQuake(
	center: Vector3,
	radius: number,
	duration: number,
	color: Color3,
	modelName: string?
)
	if near(center) then
		SpellVfx.quake(folder, center, radius, duration, color, modelName)
	end
end

-- Black Hole: the vortex, its hum while open, and the collapse boom at the end.
local function onVortex(
	center: Vector3,
	radius: number,
	duration: number,
	color: Color3,
	coreHeight: number,
	spellId: string?
)
	if not near(center) then
		return
	end
	SpellVfx.blackHole(folder, center, radius, duration, color, coreHeight)
	AudioController.loop("blackHoleHum", center, duration)
	if spellId then
		task.delay(duration + 0.15, function()
			AudioController.playSpell(spellId, "impact", center)
		end)
	end
end

-- Something was caught by a Black Hole: motes stream off it into the core.
local function onSuck(
	victim: Model,
	center: Vector3,
	seconds: number,
	color: Color3,
	coreHeight: number
)
	if typeof(victim) ~= "Instance" or not victim:IsA("Model") or not victim.Parent then
		return
	end
	if not near(center) then
		return
	end
	SpellVfx.suck(folder, victim, center, math.min(seconds, 10), color, coreHeight)
	AudioController.play("voidPull", victim:GetPivot().Position)
end

-- A turret fired.
local function onMuzzle(position: Vector3, direction: Vector3, spellId: string?)
	if not near(position) then
		return
	end
	SpellVfx.muzzle(folder, position, direction)
	if spellId then
		AudioController.playSpell(spellId, "impact", position)
	end
end

-- A turret finished rising.
local function onDeploy(position: Vector3, color: Color3, _spellId: string?)
	if not near(position) then
		return
	end
	SpellVfx.deploy(folder, position, color)
	AudioController.play("turretOnline", position)
end

-- A player dashed: the somersault pose, a puff at their feet, and a whoosh;
-- when the leap ends, a smaller puff and a thud where they land.
local function onDash(character: Model, direction: Vector3)
	local root = typeof(character) == "Instance" and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not near(root.Position) then
		return
	end
	CastAnimations.play(character, "Dash")
	SpellVfx.windStreaks(character, Config.DASH.TRAILS, Config.DASH.DURATION)
	local dustColor = Color3.fromRGB(220, 220, 230)
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	SpellVfx.dust(folder, feet, 5, dustColor)
	SpellVfx.dust(folder, feet - direction * 3, 4, dustColor)
	AudioController.play("dash", root.Position)
	task.delay(Config.DASH.DURATION, function()
		if root.Parent then
			local land = root.Position - Vector3.new(0, 2.8, 0)
			SpellVfx.dust(folder, land, 4, dustColor)
			AudioController.play("dashLand", land)
		end
	end)
end

-- A player just drew a glyph: show it over their head.
local function onGlyph(character: Model, glyphId: string, color: Color3)
	local root = typeof(character) == "Instance" and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and near(root.Position) then
		SpellVfx.glyphEmblem(folder, character, glyphId, color)
	end
end

local function onPoof(position: Vector3, color: Color3)
	if not near(position) then
		return
	end
	for _ = 1, 6 do
		if debrisCount >= MAX_DEBRIS then
			return
		end
		debrisCount += 1
		local bit = Instance.new("Part")
		bit.Size = Vector3.one * math.random(6, 14) / 10
		bit.Color = color
		bit.Material = Enum.Material.SmoothPlastic
		bit.CanCollide = false
		bit.CanQuery = false
		bit.CanTouch = false
		bit.CastShadow = false
		bit.CFrame = CFrame.new(
			position + Vector3.new(math.random(-2, 2), math.random(0, 2), math.random(-2, 2))
		)
		bit.AssemblyLinearVelocity =
			Vector3.new(math.random(-20, 20), math.random(15, 35), math.random(-20, 20))
		bit.Parent = folder
		bit.Destroying:Connect(function()
			debrisCount -= 1
		end)
		Debris:AddItem(bit, 1.2)
	end
end

local function onBeam(from: Vector3, to: Vector3, color: Color3)
	if not near(from) then
		return
	end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(0.4, 0.4, (to - from).Magnitude)
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Parent = folder
	Debris:AddItem(beam, 0.2)
end

-- Floating number: pops up with a little random spread, rises, and fades.
local function onNumber(position: Vector3, amount: number, kind: string, role: string?)
	-- Game feel: "dealt" = our spell landed, "taken" = we were hit (damage only).
	if kind == "damage" then
		if role == "dealt" then
			JuiceController.hit(amount)
		elseif role == "taken" then
			JuiceController.hurt(amount)
		end
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	local spread = Vector3.new(math.random(-15, 15) / 10, 0, math.random(-15, 15) / 10)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 3, 0) + spread)
	anchor.Parent = folder

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 40)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 150
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.FONT
	label.TextScaled = true
	label.TextColor3 = NUMBER_COLORS[kind] or NUMBER_COLORS.damage
	label.TextStrokeTransparency = 0.2
	label.Text = if kind == "heal"
		then `+{amount}`
		elseif kind == "shield" then `({amount})`
		else tostring(amount)
	label.Parent = gui
	-- Bigger hits get bigger numbers.
	local scale = Instance.new("UIScale")
	local size = math.clamp(0.8 + amount / 40, 0.8, 1.6)
	-- Pops in big and settles, so a hit lands with a bit of punch.
	scale.Scale = size * 1.5
	scale.Parent = label
	TweenService:Create(
		scale,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = size }
	):Play()

	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { CFrame = anchor.CFrame + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1)
end

-- Strike: after the server's telegraph delay, the bolt model drops from the
-- sky onto the circle, flashes, and fades.
local function onStrike(
	center: Vector3,
	radius: number,
	delay: number,
	modelName: string,
	color: Color3,
	spellId: string?
)
	if not near(center) then
		return
	end
	task.delay(math.max(0, delay - 0.12), function()
		local bolt = ModelKit.clone(modelName, "effect")
		local height = radius * 4.5
		local landing = CFrame.new(center + Vector3.new(0, height / 2, 0))
		if bolt then
			local _, size = bolt:GetBoundingBox()
			bolt:ScaleTo(height / math.max(size.Y, 0.01))
			bolt:PivotTo(landing + Vector3.new(0, height, 0))
			bolt.Parent = folder
			-- Slam down in a blink, then fade out.
			local start = os.clock()
			local connection: RBXScriptConnection
			connection = RunService.RenderStepped:Connect(function()
				local t = math.min((os.clock() - start) / 0.12, 1)
				bolt:PivotTo(landing + Vector3.new(0, height * (1 - t), 0))
				if t >= 1 then
					connection:Disconnect()
				end
			end)
			task.delay(0.15, function()
				for _, part in bolt:GetDescendants() do
					if part:IsA("BasePart") then
						TweenService:Create(part, TweenInfo.new(0.35), { Transparency = 1 }):Play()
					end
				end
			end)
			Debris:AddItem(bolt, 0.6)
		else
			-- Fallback: a plain neon column.
			local column = Instance.new("Part")
			column.Anchored = true
			column.CanCollide = false
			column.CanQuery = false
			column.CanTouch = false
			column.Material = Enum.Material.Neon
			column.Color = color
			column.Size = Vector3.new(1.2, height, 1.2)
			column.CFrame = landing
			column.Parent = folder
			TweenService:Create(column, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			Debris:AddItem(column, 0.5)
		end
		task.delay(0.12, function()
			SpellVfx.impact(folder, center, spellId, color)
			if spellId then
				AudioController.playSpell(spellId, "impact", center)
			end
		end)
	end)
end

-- Model pop: the model pops up over the character's head, bobs, and fades.
local function onModelPop(character: Model, modelName: string, color: Color3)
	local head = typeof(character) == "Instance" and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or not near(head.Position) then
		return
	end
	local look = ModelKit.clone(modelName, "effect")
	if not look then
		SpellVfx.impact(folder, head.Position + Vector3.new(0, 2, 0), nil, color)
		return
	end
	local _, size = look:GetBoundingBox()
	look:ScaleTo(2.5 / math.max(size.X, size.Y, size.Z, 0.01))
	look.Parent = folder
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if not head.Parent or t > 1.2 then
			connection:Disconnect()
			look:Destroy()
			return
		end
		-- Rise, spin, and shrink away in the last third.
		local rise = 2.5 + math.min(t, 0.4) * 5 + t * 0.6
		look:PivotTo(
			CFrame.new(head.Position + Vector3.new(0, rise, 0))
				* CFrame.Angles(0, t * math.pi * 2, 0)
		)
		if t > 0.8 then
			look:ScaleTo(math.max(look:GetScale() * 0.9, 0.05))
		end
	end)
	SpellVfx.impact(folder, head.Position, nil, color)
end

local function step(dt: number)
	local now = os.clock()
	for id, bolt in bolts do
		local travelled = math.min((now - bolt.born) * bolt.speed, bolt.range)
		local position = bolt.origin + bolt.direction * travelled
		local facing = CFrame.lookAt(position, position + bolt.direction)
		-- Swells to full size over its first moments (turret bullets skip this).
		local age = now - bolt.born
		if age < BOLT_GROW + dt and bolt.fxKey ~= "Bullet" then
			local grow = BOLT_GROW_FROM + (1 - BOLT_GROW_FROM) * math.min(age / BOLT_GROW, 1)
			if bolt.model then
				bolt.model:ScaleTo(bolt.baseScale * grow)
			else
				bolt.part.Size = bolt.baseSize * grow
			end
		end
		if bolt.model then
			bolt.model:PivotTo(facing)
		else
			bolt.part.CFrame = facing
		end
		-- Safety net if the end event is lost: drop it shortly after max range.
		if travelled >= bolt.range and now - bolt.born > bolt.range / bolt.speed + 0.5 then
			bolts[id] = nil;
			(bolt.model or bolt.part):Destroy()
		end
	end
	local spin = CFrame.Angles(math.pi * dt, 0, 0)
	local turn = CFrame.Angles(0, math.pi * 1.5 * dt, 0)
	for _, thing in CollectionService:GetTagged("SpinFx") do
		if thing:IsA("BasePart") then
			thing.CFrame *= spin
		elseif thing:IsA("Model") then
			-- Imported swirls turn about their vertical axis.
			thing:PivotTo(thing:GetPivot() * turn)
		end
	end
end

function FxController.init()
	folder = Instance.new("Folder")
	folder.Name = "ClientFx"
	folder.Parent = workspace
end

function FxController.start()
	Remotes.get("Fx").OnClientEvent:Connect(function(kind: string, ...)
		if kind == "projectile" then
			onProjectile(...)
		elseif kind == "projectileEnd" then
			onProjectileEnd(...)
		elseif kind == "poof" then
			onPoof(...)
		elseif kind == "beam" then
			onBeam(...)
		elseif kind == "number" then
			onNumber(...)
		elseif kind == "cast" then
			onCast(...)
		elseif kind == "strike" then
			onStrike(...)
		elseif kind == "modelPop" then
			onModelPop(...)
		elseif kind == "sfx" then
			-- A one-off world sound (a turret shot): (cueName, position)
			local cueName, position = ...
			if typeof(cueName) == "string" and typeof(position) == "Vector3" and near(position) then
				AudioController.play(cueName, position)
			end
		elseif kind == "pillar" then
			onPillar(...)
		elseif kind == "rise" then
			onRise(...)
		elseif kind == "quake" then
			onQuake(...)
		elseif kind == "vortex" then
			onVortex(...)
		elseif kind == "suck" then
			onSuck(...)
		elseif kind == "muzzle" then
			onMuzzle(...)
		elseif kind == "deploy" then
			onDeploy(...)
		elseif kind == "glyph" then
			onGlyph(...)
		elseif kind == "dash" then
			onDash(...)
		elseif kind == "shatter" then
			local cframe: CFrame = (...)
			if near(cframe.Position) then
				SpellVfx.shatter(folder, ...)
			end
		elseif kind == "chip" then
			local position: Vector3 = (...)
			if near(position) then
				SpellVfx.chip(folder, ...)
			end
		elseif kind == "dust" then
			local position: Vector3 = (...)
			if near(position) then
				SpellVfx.dust(folder, ...)
			end
		elseif kind == "shockwave" then
			local position: Vector3 = (...)
			if near(position) then
				SpellVfx.shockwave(folder, ...)
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return FxController
