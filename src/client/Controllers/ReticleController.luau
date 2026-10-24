--!strict
-- Hover hitbox for point-and-click spells (stats.reticle, e.g. Zap). While
-- such a spell is readied:
--   * a glowing circle the size of the spell's hit radius (+ the player
--     hitbox bonus) follows the aim point on the ground, and
--   * a faint ring around the player shows the spell's range limit.
-- The aim point is clamped to the range exactly like CastService clamps it,
-- and InputController casts at getTarget(), so the circle is where the
-- strike lands. Local-only parts; other players never see them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local ReticleController = {}

local folder: Folder? = nil
local circle: Part
local core: Part
local rangeRing: Part
local target: Vector3? = nil
local activeSpell: string? = nil

-- Set by InputController: returns the world point the player is aiming at.
local aimProvider: (() -> Vector3?)? = nil

function ReticleController.setAimProvider(fn: () -> Vector3?)
	aimProvider = fn
end

function ReticleController.isActive(): boolean
	return activeSpell ~= nil
end

-- The clamped, ground-snapped point the circle is drawn at (cast here).
function ReticleController.getTarget(): Vector3?
	return target
end

local function disc(name: string, transparency: number, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Transparency = transparency
	part.Size = Vector3.new(0.2, 1, 1)
	return part
end

local function hide()
	if folder then
		folder.Parent = nil
	end
	activeSpell = nil
	target = nil
end

local function groundBelow(point: Vector3, character: Model): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(point + Vector3.new(0, 8, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else point
end

local function place(part: Part, center: Vector3, radius: number)
	part.Size = Vector3.new(part.Size.X, radius * 2, radius * 2)
	part.CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
end

local function update()
	local id = ClientState.readied
	local def = id and SpellDefinitions.get(id)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not def or not def.stats.reticle or not root or not character or not aimProvider then
		if activeSpell then
			hide()
		end
		return
	end
	local point = aimProvider()
	if not point then
		hide()
		return
	end
	activeSpell = def.id
	local range = def.stats.range or Config.AIM_RANGE
	local offset = point - root.Position
	local clamped = offset.Magnitude > range
	if clamped then
		point = root.Position + offset.Unit * range
	end
	local ground = groundBelow(point, character)
	target = ground

	local radius = (def.stats.radius or 4) + Config.HITBOX_BONUS
	local ready = ClientState.cooldownLeft(def.id) <= 0
	-- Yellow when it'll strike right where you point; orange at the range
	-- limit (it's been pulled in); red while cooling down.
	local color = if not ready
		then Theme.COLORS.bad
		elseif clamped then Color3.fromRGB(255, 167, 38)
		else def.visual.color
	circle.Color = color
	core.Color = color
	place(circle, ground, radius)
	place(core, ground, math.max(radius * 0.25, 0.6))
	place(rangeRing, groundBelow(root.Position, character), range)
	if folder and folder.Parent == nil then
		folder.Parent = workspace
	end
end

function ReticleController.init()
	local f = Instance.new("Folder")
	f.Name = "SpellReticle"
	circle = disc("HitCircle", 0.55, Enum.Material.Neon)
	circle.Parent = f
	core = disc("HitCore", 0.2, Enum.Material.Neon)
	core.Size = Vector3.new(0.25, 1, 1)
	core.Parent = f
	rangeRing = disc("RangeRing", 0.9, Enum.Material.ForceField)
	rangeRing.Size = Vector3.new(0.1, 1, 1)
	rangeRing.Color = Color3.fromRGB(255, 255, 255)
	rangeRing.Parent = f
	folder = f
end

function ReticleController.start()
	RunService.RenderStepped:Connect(update)
end

return ReticleController
