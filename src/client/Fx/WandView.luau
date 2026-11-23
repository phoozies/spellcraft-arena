--!strict
-- Your own wand in first person while you draw (client only, cosmetic).
-- First person hides your body, and your raised arm would only cover what you
-- aim at, so while the canvas is open a copy of your wand is held in the
-- bottom right of the screen instead (Config.WAND.VIEW_*):
--   * it rises in when the canvas opens and drops away when the circle closes;
--   * it is a small, slim copy: scaled down, with its shaft stretched so the
--     tip still reaches every pen pixel from the grip;
--   * its tip follows your pen (or the cursor, before you press) and sits
--     right under it, so you watch the wand write the line; the hand moves
--     part of the way toward the pen (so the wand stays short on screen),
--     lags a touch behind, and twists with the stroke, like a wrist;
--   * the tip glows brighter and sparks in the ink's colour while the pen is
--     down;
--   * when the drawing lands it flicks forward with a burst in the quality
--     colour; when it fizzles it shakes.
-- WandController drives it. The copy lives under the camera, can't be hit or
-- queried (so the sight's raycasts pass through it), and a plain stick with a
-- glowing ball stands in when your character has no wand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local VfxStyles = require(ReplicatedStorage.Shared.Spells.VfxStyles)
local WandAir = require(ReplicatedStorage.Shared.Util.WandAir)

local WandView = {}

local WHITE = Color3.new(1, 1, 1)
local BAD = Color3.fromRGB(239, 83, 80)
local STEP_NAME = "SpellcraftWandView"
-- Where the wand drops to when lowered (camera space, from its grip).
local LOWERED = Vector3.new(0.25, -0.9, 0.35)
-- Where the tip rests on a touch screen before the first stroke (viewport
-- fractions).
local REST = Vector2.new(0.62, 0.66)
-- The wrist: radians of twist per stud/second of sideways tip speed, at most.
local TWIST = 0.05
local TWIST_MAX = 0.45
-- A flick (drawing landed) or a shake (it fizzled): how long it takes.
local FLICK_SECONDS = 0.35
-- Tip light and sparkles, pen up / pen down.
local LIGHT_IDLE, LIGHT_DRAW = 0.8, 2.4
local SPARKS_IDLE, SPARKS_DRAW = 4, 40

type View = {
	model: Model,
	tip: BasePart,
	-- Turns the wand's own pivot -> tip line onto -Z.
	axis: CFrame,
	length: number,
	light: PointLight,
	sparks: ParticleEmitter,
	color: Color3,
}

local view: View? = nil
local raised = false
local raise = 0 -- 0 = lowered out of sight, 1 = held up
local penDown = false
local pen: Vector2? = nil
local tipNow: Vector3? = nil -- camera space, smoothed
local handNow: Vector3? = nil
local roll = 0
local flickAt = -math.huge
local flickOk = true
local clock = 0

-- A plain wand when the character has none: a stick and a glowing ball, its
-- pivot at the grip, pointing down -Z.
local function fallbackWand(color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "WandView"
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Size = Vector3.new(0.28, 0.28, 3.2)
	shaft.CFrame = CFrame.new(0, 0, -1.2)
	shaft.Color = Color3.fromRGB(150, 100, 62)
	shaft.Material = Enum.Material.Wood
	shaft.Parent = model
	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Shape = Enum.PartType.Ball
	tip.Size = Vector3.one * 0.5
	tip.CFrame = CFrame.new(0, 0, -2.95)
	tip.Material = Enum.Material.Neon
	tip.Color = color
	tip.Parent = model
	model.WorldPivot = CFrame.new()
	return model
end

-- A copy of the character's wand, unwelded and inert, scaled for the view.
local function copyWand(character: Model, color: Color3): Model
	local source = character:FindFirstChild(Config.WAND.MODEL)
	local copy = if source and source:IsA("Model") then source:Clone() else nil
	local model = if copy and copy:FindFirstChild("Tip") then copy else fallbackWand(color)
	if copy and model ~= copy then
		copy:Destroy()
	end
	model.Name = "WandView"
	-- The welded wand's WorldPivot stays where it was equipped (its parts
	-- follow the hand, the pivot doesn't), so take the grip from the hand.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
	local hand = character:FindFirstChild(if isR15 then "RightHand" else "Right Arm")
	if model == copy and hand and hand:IsA("BasePart") then
		model.WorldPivot = hand.CFrame * WandAir.grip(isR15, hand.Size)
	end
	for _, item in model:GetDescendants() do
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.CastShadow = false
			item.LocalTransparencyModifier = 0
		end
	end
	model:ScaleTo(Config.WAND.VIEW_SCALE)
	return model
end

-- Stretches the shaft (only) so the wand is Config.WAND.VIEW_LENGTH from its
-- pivot to its tip: parts before the shaft stay, parts on it spread along it,
-- parts past it slide out by the extra length.
local function stretch(model: Model)
	local tip = model:FindFirstChild("Tip")
	local shaft = model:FindFirstChild("Shaft")
	if not tip or not tip:IsA("BasePart") or not shaft or not shaft:IsA("BasePart") then
		return
	end
	local pivot = model:GetPivot()
	local tipLocal = pivot:PointToObjectSpace(tip.Position)
	local extra = Config.WAND.VIEW_LENGTH - tipLocal.Magnitude
	if extra <= 0 or tipLocal.Magnitude < 1e-3 then
		return
	end
	local dir = tipLocal.Unit
	local size = shaft.Size
	local long = math.max(size.X, size.Y, size.Z)
	local center = pivot:PointToObjectSpace(shaft.Position):Dot(dir)
	local from, to = center - long / 2, center + long / 2
	local k = (long + extra) / long
	local worldDir = pivot:VectorToWorldSpace(dir)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local a = pivot:PointToObjectSpace(part.Position):Dot(dir)
			local moved = if a <= from then a elseif a < to then from + (a - from) * k else a + extra
			part.CFrame += worldDir * (moved - a)
		end
	end
	shaft.Size = Vector3.new(
		if size.X == long then size.X * k else size.X,
		if size.Y == long and size.X ~= long then size.Y * k else size.Y,
		if size.Z == long and size.X ~= long and size.Y ~= long then size.Z * k else size.Z
	)
end

local function build(character: Model, color: Color3, parent: Instance): View
	local model = copyWand(character, color)
	stretch(model)
	local tip = model:FindFirstChild("Tip") :: BasePart
	local tipLocal = model:GetPivot():PointToObjectSpace(tip.Position)
	local length = math.max(tipLocal.Magnitude, 0.1)
	local dir = tipLocal / length
	-- lookAt needs an up that isn't along the wand.
	local up = if math.abs(dir.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 5
	light.Brightness = LIGHT_IDLE
	light.Shadows = false
	light.Parent = tip
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = VfxStyles.TEX.sparkle
	sparks.Color = ColorSequence.new(color:Lerp(WHITE, 0.5), color)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.25, 0.5)
	sparks.Speed = NumberRange.new(0.6, 2)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rotation = NumberRange.new(0, 360)
	sparks.RotSpeed = NumberRange.new(-200, 200)
	sparks.Rate = SPARKS_IDLE
	sparks.Parent = tip
	model.Parent = parent
	return {
		model = model,
		tip = tip,
		axis = CFrame.lookAt(Vector3.zero, dir, up):Inverse(),
		length = length,
		light = light,
		sparks = sparks,
		color = color,
	}
end

-- The pixel the tip follows: the pen while it's down, else the cursor, else
-- where the pen last was, else a resting spot.
local function aimPixel(camera: Camera): Vector2
	if penDown and pen then
		return pen
	end
	if UserInputService.MouseEnabled then
		return UserInputService:GetMouseLocation()
	end
	return pen or camera.ViewportSize * REST
end

local function clear()
	RunService:UnbindFromRenderStep(STEP_NAME)
	if view then
		view.model:Destroy()
		view = nil
	end
	tipNow = nil
	handNow = nil
	pen = nil
	penDown = false
	roll = 0
	flickAt = -math.huge
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local v = view
	if not v or not camera then
		clear()
		return
	end
	clock += dt
	raise = math.clamp(raise + (if raised then dt else -dt) / Config.WAND.VIEW_RAISE, 0, 1)
	if raise <= 0 and not raised then
		clear()
		return
	end

	-- The hand moves part of the way toward the pen's ray (at the grip's
	-- depth); the tip sits on that ray, the wand's length from the hand.
	local rest = Config.WAND.VIEW_GRIP
	local pixel = aimPixel(camera)
	local ray = camera:ViewportPointToRay(pixel.X, pixel.Y)
	local origin = camera.CFrame:PointToObjectSpace(ray.Origin)
	local direction = camera.CFrame:VectorToObjectSpace(ray.Direction).Unit
	local hand = WandAir.viewHand(origin, direction, rest, Config.WAND.VIEW_HAND_FOLLOW)
	local follow = 1 - math.exp(-Config.WAND.VIEW_FOLLOW * dt)
	local grip = (handNow or rest):Lerp(hand, follow)
	handNow = grip
	local target = WandAir.viewTip(origin, direction, grip, v.length)
		or grip + (origin + direction * 2 - grip).Unit * v.length
	local last = tipNow or target
	local tip = last:Lerp(target, follow)
	tipNow = tip

	-- The wrist twists with the stroke's sideways speed.
	local sideways = if dt > 0 then (tip.X - last.X) / dt else 0
	local twist = math.clamp(-sideways * TWIST, -TWIST_MAX, TWIST_MAX)
	roll += (twist - roll) * math.min(1, dt * 12)

	-- Flick forward (landed) or shake (fizzled).
	local push = Vector3.zero
	local shake = 0
	local since = os.clock() - flickAt
	if since < FLICK_SECONDS then
		local k = since / FLICK_SECONDS
		if flickOk then
			push = Vector3.new(-0.08, 0.12, -0.3) * math.sin(math.pi * k)
		else
			shake = math.sin(k * 40) * 0.25 * (1 - k)
		end
	end
	-- A gentle bob while the pen is up.
	local bob = if penDown then 0 else math.sin(clock * 2.2) * 0.015
	local eased = TweenService:GetValue(raise, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local lowered = LOWERED * (1 - eased) + Vector3.new(0, bob, 0) + push
	local from = grip + lowered
	local to = tip + lowered + Vector3.new(0, -0.35, 0) * (1 - eased)

	local held = CFrame.lookAt(from, to, Vector3.yAxis) * CFrame.Angles(0, 0, roll + shake)
	v.model:PivotTo(camera.CFrame * held * v.axis)
end

-- Raises your wand into view (the canvas opened).
function WandView.show(character: Model, color: Color3)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	raised = true
	if view then
		return
	end
	raise = 0
	view = build(character, color, camera)
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, step)
end

-- Lowers it out of view (the circle closed); it is removed once out of sight.
function WandView.hide()
	raised = false
	penDown = false
end

-- True while the wand is anywhere on screen.
function WandView.isShown(): boolean
	return view ~= nil
end

-- The pen touched the canvas: the tip lights up and sparks in `color`.
function WandView.penDown(color: Color3)
	penDown = true
	local v = view
	if v then
		v.light.Color = color
		v.light.Brightness = LIGHT_DRAW
		v.sparks.Color = ColorSequence.new(color:Lerp(WHITE, 0.5), color)
		v.sparks.Rate = SPARKS_DRAW
	end
end

-- The pen moved to `screen` (viewport pixels, top bar included).
function WandView.point(screen: Vector2)
	pen = screen
end

-- The pen lifted.
function WandView.penUp()
	penDown = false
	local v = view
	if v then
		v.light.Brightness = LIGHT_IDLE
		v.sparks.Rate = SPARKS_IDLE
	end
end

-- The drawing's verdict: a flick and a burst in `color` when it landed, a
-- shake and a red puff when it fizzled.
function WandView.flick(ok: boolean, color: Color3?)
	flickAt = os.clock()
	flickOk = ok
	local v = view
	if not v then
		return
	end
	local burst = if ok then color or v.color else BAD
	v.sparks.Color = ColorSequence.new(burst:Lerp(WHITE, 0.4), burst)
	v.sparks:Emit(if ok then 28 else 12)
	v.light.Color = burst
	v.light.Brightness = 4
	TweenService:Create(v.light, TweenInfo.new(0.4), { Brightness = LIGHT_IDLE }):Play()
end

return WandView
