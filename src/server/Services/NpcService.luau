--!strict
-- The Battleground's hostile NPCs. Owns: building their bodies, their AI
-- (notice, chase, swing, shoot, give up, heal, wander), the coin reward for
-- knocking one out, and respawning them at their spots.
--
--   * Every part tagged "NpcSpot" (Maps/Battleground) names an NPC type in
--     its `NpcType` attribute (see Shared/Battleground/Npcs); one NPC stands
--     there, and a new one appears there `respawn` seconds after it falls.
--   * An NPC is a Destructible model, so every spell hurts it through
--     DestructibleService like a dummy; MatchService.relation lets players
--     inside the Battleground hurt anything with the `Hostile` attribute.
--     (NPCs aren't knocked back or stunned by spells: they have no player
--     physics owner.)
--   * NPCs only target players inside the Battleground, and only think while
--     one is nearby, so an empty world costs nothing.
--   * Rewards go through EconomyService, capped per player per window
--     (Config.BATTLEGROUND.NPC) so farming a respawning camp can't flood
--     the economy.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Npcs = require(ReplicatedStorage.Shared.Battleground.Npcs)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Projectile = require(script.Parent.Archetypes.Projectile)
local DestructibleService = require(script.Parent.DestructibleService)
local EconomyService = require(script.Parent.EconomyService)

local NpcService = {}

local THINK_INTERVAL = 0.2
-- An NPC sleeps when no Battleground player is this close.
local WAKE_DISTANCE = 260
local WALK_ANIMATION = "rbxassetid://180426354"
local IDLE_ANIMATION = "rbxassetid://180435571"

type Npc = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	head: BasePart,
	def: Npcs.NpcType,
	spot: BasePart,
	home: Vector3,
	target: Player?,
	nextMelee: number,
	nextShot: number,
	-- Set while a swing/shot is winding up; the NPC stands still.
	busyUntil: number,
	wanderAt: number,
	stuckAt: Vector3,
	stuckSince: number,
	highlight: Highlight,
	walk: AnimationTrack?,
	idle: AnimationTrack?,
}

local npcs: { [Model]: Npc } = {}
local folder: Folder
local toastRemote: RemoteEvent
-- player -> { coins earned in this window, when the window began }
local earned: { [Player]: { total: number, since: number } } = setmetatable({}, { __mode = "k" }) :: any

----------------------------------------------------------------------
-- Building a body
----------------------------------------------------------------------

local function limb(model: Model, name: string, size: Vector3, color: Color3, offset: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(offset)
	part.Parent = model
	return part
end

local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = part0
end

local function label(head: BasePart, text: string, color: Color3, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NpcLabel"
	gui.Size = UDim2.fromOffset(180, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 90
	gui.Parent = head
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.TextColor3 = color
	textLabel.TextStrokeTransparency = 0.2
	textLabel.Text = text
	textLabel.Parent = gui
end

-- A blocky R6-style body so the stock walk/idle animations drive it.
local function buildBody(def: Npcs.NpcType, position: Vector3): (Model, Humanoid, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = def.name

	local root = limb(model, "HumanoidRootPart", Vector3.new(2, 2, 1), def.shirt, Vector3.zero)
	root.Transparency = 1
	local torso = limb(model, "Torso", Vector3.new(2, 2, 1), def.shirt, Vector3.zero)
	local head = limb(model, "Head", Vector3.new(2, 1, 1), def.skin, Vector3.new(0, 1.5, 0))
	local rightArm = limb(model, "Right Arm", Vector3.new(1, 2, 1), def.skin, Vector3.new(1.5, 0, 0))
	local leftArm = limb(model, "Left Arm", Vector3.new(1, 2, 1), def.skin, Vector3.new(-1.5, 0, 0))
	local rightLeg = limb(model, "Right Leg", Vector3.new(1, 2, 1), def.pants, Vector3.new(0.5, -2, 0))
	local leftLeg = limb(model, "Left Leg", Vector3.new(1, 2, 1), def.pants, Vector3.new(-0.5, -2, 0))

	-- Glowing eyes and a belt in the accent color.
	for _, side in { -0.45, 0.45 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.35, 0.25, 0.1)
		eye.Color = def.accent
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		eye.Massless = true
		eye.CFrame = head.CFrame * CFrame.new(side, 0.1, -0.52)
		eye.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = eye
		weld.Parent = eye
	end
	local belt = Instance.new("Part")
	belt.Name = "Belt"
	belt.Size = Vector3.new(2.1, 0.35, 1.1)
	belt.Color = def.accent
	belt.Material = Enum.Material.Neon
	belt.CanCollide = false
	belt.Massless = true
	belt.CFrame = torso.CFrame * CFrame.new(0, -0.8, 0)
	belt.Parent = model
	local beltWeld = Instance.new("WeldConstraint")
	beltWeld.Part0 = torso
	beltWeld.Part1 = belt
	beltWeld.Parent = belt

	local rootPose = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	joint("RootJoint", root, torso, rootPose, rootPose)
	joint(
		"Neck",
		torso,
		head,
		CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	)
	joint(
		"Right Shoulder",
		torso,
		rightArm,
		CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	)
	joint(
		"Left Shoulder",
		torso,
		leftArm,
		CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	)
	joint(
		"Right Hip",
		torso,
		rightLeg,
		CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	)
	joint(
		"Left Hip",
		torso,
		leftLeg,
		CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(-0.5, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.WalkSpeed = def.speed
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	model.PrimaryPart = root
	if def.scale ~= 1 then
		pcall(function()
			model:ScaleTo(def.scale)
		end)
	end
	-- Stand on the ground: legs (2) + half the root (1), scaled.
	model:PivotTo(CFrame.new(position + Vector3.new(0, 3 * def.scale + 0.3, 0)))
	label(head, def.name, def.accent, 2.2 * def.scale)
	return model, humanoid, root, head
end

local function loadTrack(humanoid: Humanoid, id: string, looped: boolean): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local ok, track = pcall(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local loaded = animator:LoadAnimation(animation)
		loaded.Looped = looped
		return loaded
	end)
	return if ok then track else nil
end

----------------------------------------------------------------------
-- Health bar upkeep (the damage code owns the numbers; this resets them)
----------------------------------------------------------------------

local function restoreHealth(npc: Npc)
	local model = npc.model
	local max = model:GetAttribute("MaxHealth") :: number
	if (model:GetAttribute("Health") :: number) >= max then
		return
	end
	model:SetAttribute("Health", max)
	local bar = model:FindFirstChild("HealthBar", true)
	if bar and bar:IsA("BillboardGui") then
		bar.Enabled = false
		local fill = bar:FindFirstChild("Fill", true)
		if fill and fill:IsA("Frame") then
			fill.Size = UDim2.fromScale(1, 1)
		end
	end
end

----------------------------------------------------------------------
-- Attacks
----------------------------------------------------------------------

local function targetRoot(player: Player?): (BasePart?, Humanoid?)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 and player and player:GetAttribute("InBattleground") then
		return root, humanoid
	end
	return nil, nil
end

local function face(npc: Npc, position: Vector3)
	local from = npc.root.Position
	local flat = Vector3.new(position.X - from.X, 0, position.Z - from.Z)
	if flat.Magnitude > 0.1 then
		npc.root.CFrame = CFrame.lookAt(from, from + flat)
	end
end

local function telegraph(npc: Npc, seconds: number)
	npc.highlight.Enabled = true
	task.delay(seconds, function()
		npc.highlight.Enabled = false
	end)
end

local function alive(npc: Npc): boolean
	return npc.model.Parent ~= nil and npcs[npc.model] == npc
end

local function swing(npc: Npc, player: Player)
	local melee = npc.def.melee :: Npcs.Melee
	local now = os.clock()
	npc.nextMelee = now + melee.interval
	npc.busyUntil = now + melee.windup
	face(npc, (targetRoot(player) :: BasePart).Position)
	telegraph(npc, melee.windup)
	task.delay(melee.windup, function()
		if not alive(npc) then
			return
		end
		local root = targetRoot(player)
		if not root then
			return
		end
		if (root.Position - npc.root.Position).Magnitude > melee.range * 1.5 + 2 then
			return -- the player stepped away: a miss
		end
		local dealt = DestructibleService.damage(root.Parent :: Instance, melee.damage, nil, npc.def.name)
		if dealt > 0 and melee.knockback then
			local away = root.Position - npc.root.Position
			local flat = Vector3.new(away.X, 0, away.Z)
			if flat.Magnitude > 0.1 then
				DestructibleService.push(
					root.Parent :: Instance,
					flat.Unit * melee.knockback + Vector3.new(0, melee.knockback * 0.35, 0)
				)
			end
		end
	end)
end

local function hasLineOfSight(npc: Npc, root: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc.model, folder }
	params.RespectCanCollide = true
	local origin = npc.head.Position
	local hit = workspace:Raycast(origin, root.Position - origin, params)
	return hit == nil or hit.Instance:IsDescendantOf(root.Parent :: Instance)
end

local function shoot(npc: Npc, player: Player)
	local ranged = npc.def.ranged :: Npcs.Ranged
	local now = os.clock()
	npc.nextShot = now + ranged.interval
	npc.busyUntil = now + ranged.windup
	face(npc, (targetRoot(player) :: BasePart).Position)
	telegraph(npc, ranged.windup)
	task.delay(ranged.windup, function()
		if not alive(npc) then
			return
		end
		local root = targetRoot(player)
		if not root then
			return
		end
		local origin = npc.head.Position + npc.root.CFrame.LookVector * 2
		local aim = root.Position + root.AssemblyLinearVelocity * 0.15
		local ignore: { Instance } = { folder }
		for model in npcs do
			table.insert(ignore, model)
		end
		Projectile.launch({
			caster = nil,
			origin = origin,
			direction = aim - origin,
			stats = { damage = ranged.damage, speed = ranged.speed, range = ranged.range + 25, radius = 2 },
			visual = {
				shape = "Ball",
				size = Vector3.new(3, 3, 3),
				color = npc.def.accent,
				material = Enum.Material.Neon,
			},
			spellName = npc.def.name,
			fxKey = "Fireball",
			ignore = ignore,
		} :: any)
	end)
end

----------------------------------------------------------------------
-- Thinking
----------------------------------------------------------------------

local function nearestFighter(npc: Npc, maxDistance: number): (Player?, number)
	local best: Player? = nil
	local bestDistance = maxDistance
	for _, player in Players:GetPlayers() do
		local root = targetRoot(player)
		if root and not (root.Parent :: Instance):FindFirstChildOfClass("ForceField") then
			local distance = (root.Position - npc.root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best, bestDistance
end

local function anyoneNear(npc: Npc): boolean
	for _, player in Players:GetPlayers() do
		local root = targetRoot(player)
		if root and (root.Position - npc.root.Position).Magnitude < WAKE_DISTANCE then
			return true
		end
	end
	return false
end

local function setWalking(npc: Npc, walking: boolean)
	if npc.walk then
		if walking and not npc.walk.IsPlaying then
			npc.walk:Play(0.15)
		elseif not walking and npc.walk.IsPlaying then
			npc.walk:Stop(0.2)
		end
	end
end

local function think(npc: Npc, now: number)
	local def = npc.def
	local position = npc.root.Position

	-- Keep or drop the current target.
	if npc.target then
		local root = targetRoot(npc.target)
		if
			not root
			or (root.Position - npc.home).Magnitude > def.leash
			or (root.Position - position).Magnitude > def.aggro * 2
		then
			npc.target = nil
		end
	end
	if not npc.target then
		local player = nearestFighter(npc, def.aggro)
		if player and ((targetRoot(player) :: BasePart).Position - npc.home).Magnitude <= def.leash then
			npc.target = player
		end
	end

	-- Stuck on scenery? Hop.
	if (position - npc.stuckAt).Magnitude > 2 then
		npc.stuckAt, npc.stuckSince = position, now
	elseif now - npc.stuckSince > 1.2 and npc.humanoid.MoveDirection.Magnitude > 0 then
		npc.humanoid.Jump = true
		npc.stuckSince = now
	end

	if now < npc.busyUntil then
		npc.humanoid:Move(Vector3.zero)
		setWalking(npc, false)
		return
	end

	local player = npc.target
	local root = targetRoot(player)
	if player and root then
		local distance = (root.Position - position).Magnitude
		local melee, ranged = def.melee, def.ranged
		if melee and distance <= melee.range then
			setWalking(npc, false)
			npc.humanoid:Move(Vector3.zero)
			if now >= npc.nextMelee then
				swing(npc, player)
			else
				face(npc, root.Position)
			end
			return
		end
		if ranged and distance <= ranged.range and hasLineOfSight(npc, root) then
			-- Mages hold their ground at range; warlords keep closing in to swing.
			if now >= npc.nextShot then
				shoot(npc, player)
			end
			if melee == nil and distance < ranged.range * 0.8 then
				npc.humanoid:Move(Vector3.zero)
				face(npc, root.Position)
				setWalking(npc, false)
				return
			end
		end
		npc.humanoid:MoveTo(root.Position)
		setWalking(npc, true)
		return
	end

	-- No target: head home, heal, and loiter around it.
	local toHome = (npc.home - position)
	toHome = Vector3.new(toHome.X, 0, toHome.Z)
	if toHome.Magnitude > 25 then
		npc.humanoid:MoveTo(npc.home)
		setWalking(npc, true)
		return
	end
	restoreHealth(npc)
	if now >= npc.wanderAt then
		npc.wanderAt = now + 3 + math.random() * 4
		if math.random() < 0.6 then
			local angle = math.random() * math.pi * 2
			local radius = 4 + math.random() * 10
			npc.humanoid:MoveTo(npc.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		else
			npc.humanoid:Move(Vector3.zero)
		end
	end
	setWalking(npc, npc.humanoid.MoveDirection.Magnitude > 0.1)
end

----------------------------------------------------------------------
-- Spawning and rewards
----------------------------------------------------------------------

local function respawnDelay(def: Npcs.NpcType): number
	return def.respawn or Config.BATTLEGROUND.NPC.RESPAWN
end

local function spawnAt(spot: BasePart)
	local def = Npcs.get(spot:GetAttribute("NpcType") :: string)
	if not def or not spot.Parent then
		return
	end
	local home = spot.Position
	local model, humanoid, root, head = buildBody(def, home)
	model:SetAttribute("NpcType", def.id)
	model:SetAttribute("Hostile", true)
	DestructibleService.wrap(model, head, def.health, nil, nil, 5.5 * def.scale)
	-- Wider than the model: the health bar sits above the name tag.
	local bar = head:FindFirstChild("HealthBar")
	if bar and bar:IsA("BillboardGui") then
		bar.StudsOffsetWorldSpace = Vector3.new(0, 3.2 * def.scale, 0)
	end

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 60, 40)
	highlight.FillTransparency = 0.45
	highlight.OutlineColor = Color3.fromRGB(255, 220, 120)
	highlight.Enabled = false
	highlight.Parent = model

	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local npc: Npc = {
		model = model,
		humanoid = humanoid,
		root = root,
		head = head,
		def = def,
		spot = spot,
		home = home,
		target = nil,
		nextMelee = 0,
		nextShot = 0,
		busyUntil = 0,
		wanderAt = os.clock() + math.random() * 3,
		stuckAt = root.Position,
		stuckSince = os.clock(),
		highlight = highlight,
		walk = loadTrack(humanoid, WALK_ANIMATION, true),
		idle = loadTrack(humanoid, IDLE_ANIMATION, true),
	}
	if npc.idle then
		npc.idle:Play()
	end
	npcs[model] = npc

	model.Destroying:Connect(function()
		if npcs[model] == npc then
			npcs[model] = nil
			task.delay(respawnDelay(def), function()
				spawnAt(spot)
			end)
		end
	end)
end

-- Pays the knockout reward, within the per-player cap.
local function payReward(player: Player, def: Npcs.NpcType)
	local cap = Config.BATTLEGROUND.NPC
	local now = os.clock()
	local record = earned[player]
	if not record or now - record.since > cap.COIN_WINDOW then
		record = { total = 0, since = now }
		earned[player] = record
	end
	local amount = math.min(def.reward, cap.COIN_CAP - record.total)
	if amount <= 0 then
		toastRemote:FireClient(player, `{def.name} down! (No more NPC coins for a few minutes.)`, "info")
	else
		record.total += amount
		EconomyService.addCoins(player, amount, "npc", true)
		toastRemote:FireClient(player, `{def.name} down! +{amount} coins`, "coin")
	end
	EconomyService.track(player, "knockout")
end

function NpcService.count(): number
	local total = 0
	for _ in npcs do
		total += 1
	end
	return total
end

function NpcService.init()
	toastRemote = Remotes.get("Toast")
	folder = Instance.new("Folder")
	folder.Name = "Npcs"
	folder.Parent = workspace
end

function NpcService.start()
	DestructibleService.Destroyed:Connect(function(instance, destroyer)
		local id = instance:GetAttribute("NpcType")
		if typeof(id) ~= "string" or not destroyer or not destroyer.Parent then
			return
		end
		local def = Npcs.get(id)
		if def then
			payReward(destroyer, def)
		end
	end)

	local function hook(spot: Instance)
		if spot:IsA("BasePart") and Npcs.get(spot:GetAttribute("NpcType") :: string) then
			spawnAt(spot)
		end
	end
	for _, spot in CollectionService:GetTagged("NpcSpot") do
		hook(spot)
	end
	CollectionService:GetInstanceAddedSignal("NpcSpot"):Connect(hook)

	task.spawn(function()
		while true do
			task.wait(THINK_INTERVAL)
			local now = os.clock()
			for _, npc in npcs do
				if npc.model.Parent and anyoneNear(npc) then
					local ok, err = pcall(think, npc, now)
					if not ok then
						warn(`[NpcService] {npc.def.id} think failed: {err}`)
					end
				end
			end
		end
	end)
end

return NpcService
