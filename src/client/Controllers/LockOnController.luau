--!strict
-- The first-person crosshair and the auto-aim lock-on marker.
--
--   * A crosshair sits in the middle of the screen, also while the drawing
--     canvas is open: the spell flies from here the moment its shape is
--     finished. While a spell's shape is being traced it wears the spell's
--     colour with its name under it, turns red with the seconds left while the
--     spell recharges, and is a small white dot otherwise.
--   * Wherever you can draw, the opponent auto-aim would pick right now gets
--     four corner brackets that close in on them, so you know who your next
--     spell will hit (none for a traced spell that doesn't lock on, like a wall).
--     The pick is the same shared/Util/AutoAim rule the server uses (nearest
--     opponent in sight near the crosshair); the server still decides the shot.
--
-- getLock() gives the locked character or NPC to ReticleController, which
-- snaps ground-strike circles onto it. Purely visual.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local AutoAim = require(ReplicatedStorage.Shared.Util.AutoAim)
local MouseLock = require(script.Parent.Parent.UI.MouseLock)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local DrawController = require(script.Parent.DrawController)

local player = Players.LocalPlayer

local LockOnController = {}

-- The archetypes CastService locks on for (see AIMED_ARCHETYPES there).
local AIMED = { Projectile = true, Control = true, Line = true, Zone = true }
local COOLING = Color3.fromRGB(242, 104, 116)
local RING = 30
local BRACKET = 14
-- Seconds between lock picks, and between scans for dummies and NPCs.
local PICK_INTERVAL = 0.1
local TARGET_SCAN_INTERVAL = 2
local NO_SPELL_COLOR = Color3.new(1, 1, 1)

local gui: ScreenGui
local cross: Frame
local ring: Frame
local ringStroke: UIStroke
local dot: Frame
local nameLabel: TextLabel
local altHint: TextLabel
local marker: Frame
local brackets: { Frame } = {}
local lock: Model? = nil
local lockedSince = 0
local lastPick = 0
local trainingTargets: { Model } = {} -- dummies and NPCs, from the last scan
local lastTargetScan = -math.huge
local tinted: Color3? = nil

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return if root and root:IsA("BasePart") then root else nil
end

-- Whether `other` is someone your spells can hurt right now (mirrors the
-- server's relation rules closely enough for a marker).
local function isEnemy(other: Player): boolean
	local character = other.Character
	if not character then
		return false
	end
	if player:GetAttribute("InBattleground") then
		if not other:GetAttribute("InBattleground") then
			return false
		end
		local party = other:GetAttribute("PartyId")
		return party == nil or party ~= player:GetAttribute("PartyId")
	end
	local state = ClientState.match
	if state.phase == "Idle" then
		return false
	end
	local team = character:GetAttribute("Team")
	return team ~= nil and team ~= state.myTeamId
end

local function candidates(): { AutoAim.Candidate }
	local list: { AutoAim.Candidate } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and rootOf(character)
		if
			other ~= player
			and character
			and root
			and humanoid
			and humanoid.Health > 0
			and isEnemy(other)
		then
			table.insert(list, {
				position = root.Position,
				velocity = root.AssemblyLinearVelocity,
				radius = 2,
				key = character,
			})
		end
	end
	-- Finding them walks every breakable in the arena, so it runs far less often
	-- than the pick itself.
	local now = os.clock()
	if now - lastTargetScan >= TARGET_SCAN_INTERVAL then
		lastTargetScan = now
		table.clear(trainingTargets)
		for _, thing in CollectionService:GetTagged("Destructible") do
			if
				thing:IsA("Model")
				and (thing:GetAttribute("Dummy") == true or thing:GetAttribute("NpcType") ~= nil)
			then
				table.insert(trainingTargets, thing)
			end
		end
	end
	for _, thing in trainingTargets do
		local root = if thing.Parent then rootOf(thing) else nil
		local humanoid = thing:FindFirstChildOfClass("Humanoid")
		if root and (not humanoid or humanoid.Health > 0) then
			table.insert(list, {
				position = root.Position,
				radius = math.max(2, thing:GetExtentsSize().X / 2),
				key = thing,
			})
		end
	end
	return list
end

local function inSight(eye: Vector3, candidate: AutoAim.Candidate): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { candidate.key :: Instance }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return workspace:Raycast(eye, candidate.position - eye, params) == nil
end

-- The lock a spell would get (no spell yet: any bolt), or nil.
local function pickLock(def: any?): Model?
	local camera = workspace.CurrentCamera
	if not camera or (def and (not AIMED[def.archetype] or (def.stats.range or 1) <= 0)) then
		return nil
	end
	local eye = camera.CFrame.Position
	local pick = AutoAim.pick(eye, camera.CFrame.LookVector, candidates(), {
		range = (def and def.stats.range) or Config.AIM_RANGE,
		visible = function(candidate)
			return inSight(eye, candidate)
		end,
	})
	return if pick then pick.key :: Model else nil
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.Parent = player:WaitForChild("PlayerGui")

	cross = Instance.new("Frame")
	cross.Name = "Cross"
	cross.BackgroundTransparency = 1
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Size = UDim2.fromOffset(RING, RING)
	cross.Active = false
	cross.Parent = gui

	ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(RING, RING)
	ring.BackgroundTransparency = 1
	ring.Parent = cross
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 3
	ringStroke.Parent = ring

	dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.Parent = cross
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(0.5, 0)
	dotCorner.Parent = dot
	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color = Theme.COLORS.outline
	dotStroke.Thickness = 1.5
	dotStroke.Parent = dot

	nameLabel = Theme.label(cross, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 14),
		Size = UDim2.fromOffset(200, 22),
		TextStrokeTransparency = 0.2,
	})

	-- Outside fights the side menu needs the mouse: say how to get it.
	altHint = Theme.label(gui, "Hold Left Alt for the mouse", {
		Name = "AltHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(300, 18),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.onDark,
		TextStrokeTransparency = 0.3,
		TextTransparency = 0.25,
		Visible = false,
	})

	-- Four corner brackets around the locked target (placed in screen space).
	marker = Instance.new("Frame")
	marker.Name = "LockOn"
	marker.BackgroundTransparency = 1
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Visible = false
	marker.Active = false
	marker.Parent = gui
	for index = 1, 4 do
		local holder = Instance.new("Frame")
		holder.Name = `Bracket{index}`
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(BRACKET, BRACKET)
		holder.AnchorPoint = Vector2.new((index - 1) % 2, if index > 2 then 1 else 0)
		holder.Position = UDim2.fromScale((index - 1) % 2, if index > 2 then 1 else 0)
		holder.Parent = marker
		for _, horizontal in { true, false } do
			local bar = Instance.new("Frame")
			bar.BorderSizePixel = 0
			bar.Size = if horizontal then UDim2.new(1, 0, 0, 3) else UDim2.new(0, 3, 1, 0)
			bar.AnchorPoint = holder.AnchorPoint
			bar.Position = UDim2.fromScale(holder.AnchorPoint.X, holder.AnchorPoint.Y)
			bar.Parent = holder
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.COLORS.outline
			stroke.Thickness = 1
			stroke.Parent = bar
		end
		table.insert(brackets, holder)
	end
end

local function tint(color: Color3)
	if color == tinted then
		return
	end
	tinted = color
	ringStroke.Color = color
	for _, holder in brackets do
		for _, bar in holder:GetChildren() do
			if bar:IsA("Frame") then
				bar.BackgroundColor3 = color
			end
		end
	end
end

local function placeMarker(target: Model, color: Color3)
	local camera = workspace.CurrentCamera
	local root = rootOf(target)
	if not camera or not root then
		marker.Visible = false
		return
	end
	local _, size = target:GetBoundingBox()
	local top = camera:WorldToViewportPoint(root.Position + Vector3.new(0, size.Y / 2, 0))
	local bottom, onScreen =
		camera:WorldToViewportPoint(root.Position - Vector3.new(0, size.Y / 2, 0))
	if not onScreen then
		marker.Visible = false
		return
	end
	local height = math.clamp(math.abs(bottom.Y - top.Y), 24, 400)
	-- Brackets start wide and snap in over a moment when a new target is locked.
	local settle = math.clamp((os.clock() - lockedSince) / 0.18, 0, 1)
	local pad = (1 - settle) * 30
	local width = height * 0.6 + pad
	marker.Size = UDim2.fromOffset(width, height + pad)
	marker.Position = UDim2.fromOffset((top.X + bottom.X) / 2, (top.Y + bottom.Y) / 2)
	marker.Visible = true
	tint(color)
end

-- Who the lock is right now, re-picked every PICK_INTERVAL.
local function refreshLock(def: any?, hidden: boolean)
	local now = os.clock()
	if now - lastPick < PICK_INTERVAL then
		return
	end
	lastPick = now
	local picked = if hidden or not ClientState.canDraw() then nil else pickLock(def)
	if picked ~= lock then
		lock = picked
		lockedSince = now
	end
end

local function update()
	local id = ClientState.aiming
	local def = id and SpellDefinitions.get(id)
	local drawing = DrawController.isActive()
	-- The canvas frees the mouse too, but the crosshair stays: it is the aim.
	local hidden = MouseLock.isFree() and not drawing
	cross.Visible = not hidden
	altHint.Visible = not hidden
		and not drawing
		and UserInputService.KeyboardEnabled
		and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch
		and not ClientState.fighting()
	if hidden or drawing then
		UserInputService.MouseIconEnabled = true
	elseif UserInputService.MouseEnabled then
		-- The crosshair replaces the cursor while the mouse is locked.
		UserInputService.MouseIconEnabled = false
	end
	local color = NO_SPELL_COLOR
	if def then
		local left = ClientState.cooldownLeft(def.id)
		local cooling = left > 0
		color = if cooling then COOLING else def.visual.color
		local pulse = if cooling then 0 else math.sin(os.clock() * 7) * 2
		ring.Size = UDim2.fromOffset(RING + pulse, RING + pulse)
		nameLabel.Text = if cooling then `{def.name} {math.ceil(left)}s` else def.name
		nameLabel.TextColor3 = color
	else
		nameLabel.Text = ""
	end
	ring.Visible = def ~= nil
	tint(color)
	dot.BackgroundColor3 = color

	refreshLock(def, hidden)
	if lock then
		placeMarker(lock, color)
	else
		marker.Visible = false
	end
end

-- The character or NPC the next spell would lock onto right now.
function LockOnController.getLock(): Model?
	return lock
end

function LockOnController.init()
	build()
end

function LockOnController.start()
	RunService.RenderStepped:Connect(update)
end

return LockOnController
