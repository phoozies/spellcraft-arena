--!strict
-- Renders cosmetic effects the server only announces (Fx remote):
--   projectile     (id, origin, direction, speed, range, visual)  flying bolt
--   projectileEnd  (id, position)                                  remove bolt
--   poof           (position, color)                               debris burst
--   beam           (from, to, color)                               chain flash
--   number         (position, amount, kind)                        floating damage/heal/shield number
--   cast           (character, spellId, target)                    arm raise + magic circle
--   shatter        (cframe, size, color, material)                 block breaks into chunks
--   chip           (position, color)                               chips off a damaged block
--   dust           (position, width, color)                        dust ring under a placed object
--   shockwave      (position, radius, color)                       ground ring for slams/bursts
-- and spins parts tagged "SpinFx" (Tornado, Black Hole) locally.
-- The looks live in Fx/SpellVfx.
--
-- The server stays authoritative for hits; visuals here are a straight-line
-- prediction that is removed when the server says the projectile ended.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Types = require(ReplicatedStorage.Shared.Types)
local SpellVfx = require(script.Parent.Parent.Fx.SpellVfx)
local Theme = require(script.Parent.Parent.UI.Theme)

local NUMBER_COLORS: { [string]: Color3 } = {
	damage = Color3.fromRGB(255, 241, 118),
	heal = Color3.fromRGB(129, 199, 132),
	shield = Color3.fromRGB(129, 212, 250),
}

local FxController = {}

-- Don't draw effects in arenas far from us (matches run side by side).
local DRAW_DISTANCE = 600
local MAX_DEBRIS = 120

type Bolt = {
	part: BasePart,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	born: number,
	fxKey: string?,
	color: Color3,
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
	local part = Instance.new("Part")
	part.Shape = shapeOf(visual.shape)
	part.Size = visual.size
	part.Color = visual.color
	part.Material = visual.material
	part.Transparency = visual.transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(origin, origin + direction)
	SpellVfx.decorateBolt(part, fxKey, visual.color)
	part.Parent = folder
	bolts[id] = {
		part = part,
		origin = origin,
		direction = direction,
		speed = speed,
		range = range,
		born = os.clock(),
		fxKey = fxKey,
		color = visual.color,
	}
end

local function onProjectileEnd(id: number, position: Vector3)
	local bolt = bolts[id]
	if bolt then
		bolts[id] = nil
		bolt.part.CFrame = CFrame.lookAt(position, position + bolt.direction)
		bolt.part.Transparency = 1
		-- Let the trail/particles finish before removing the part.
		for _, child in bolt.part:GetChildren() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		Debris:AddItem(bolt.part, 0.4)
		if near(position) then
			SpellVfx.impact(folder, position, bolt.fxKey, bolt.color)
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
		SpellVfx.castAnimation(folder, character, def.visual.color)
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
local function onNumber(position: Vector3, amount: number, kind: string)
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
	scale.Scale = math.clamp(0.8 + amount / 40, 0.8, 1.6)
	scale.Parent = label

	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { CFrame = anchor.CFrame + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1)
end

local function step(dt: number)
	local now = os.clock()
	for id, bolt in bolts do
		local travelled = math.min((now - bolt.born) * bolt.speed, bolt.range)
		local position = bolt.origin + bolt.direction * travelled
		bolt.part.CFrame = CFrame.lookAt(position, position + bolt.direction)
		-- Safety net if the end event is lost: drop it shortly after max range.
		if travelled >= bolt.range and now - bolt.born > bolt.range / bolt.speed + 0.5 then
			bolts[id] = nil
			bolt.part:Destroy()
		end
	end
	local spin = CFrame.Angles(math.pi * dt, 0, 0)
	for _, part in CollectionService:GetTagged("SpinFx") do
		if part:IsA("BasePart") then
			part.CFrame *= spin
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
