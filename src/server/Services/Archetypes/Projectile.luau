--!strict
-- Projectile archetype: a server-simulated sphere-cast that flies toward
-- the target and hits the first player/structure/wall in its path.
--
-- Reads stats: damage, speed, range, radius, knockback, status,
-- statusDuration, chain, pierce, comboStatus, comboMultiplier.
-- Also used by Control (status projectiles) and by turrets/summons via
-- Projectile.launch(). A bolt cast with an auto-aim lock (ctx.lock) homes
-- slightly on its target (Config.AUTO_AIM.HOMING); clients steer their copy the
-- same way and get a "projectileTurn" correction every HOMING_SYNC seconds.
--
-- Performance: every live projectile is stepped by ONE shared Heartbeat
-- loop, and the server creates no Parts for them. Clients draw the visual
-- from a single "projectile" Fx event and remove it on "projectileEnd", so
-- nothing replicates per frame.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local AutoAim = require(ReplicatedStorage.Shared.Util.AutoAim)
local DestructibleService = require(script.Parent.Parent.DestructibleService)
local StatusService = require(script.Parent.Parent.StatusService)
local TrapBubble = require(script.Parent.Parent.TrapBubble)

export type LaunchOptions = {
	caster: Player?,
	origin: Vector3,
	direction: Vector3,
	stats: Types.SpellStats,
	visual: Types.Visual,
	spellName: string,
	ignore: { Instance },
	-- Which client VFX to use (a spell id, or e.g. "Cannonball"); defaults to spellName.
	fxKey: string?,
	-- The auto-aim lock (CastService): the bolt turns slightly toward it as it
	-- flies (Config.AUTO_AIM.HOMING) until it has been dodged.
	homing: Model?,
}

type Live = {
	id: number,
	opts: LaunchOptions,
	position: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	radius: number,
	travelled: number,
	ignore: { Instance },
	params: RaycastParams,
	homing: Model?,
	-- os.clock() of the last course correction sent to clients.
	syncedAt: number,
}

local Projectile = {}

-- Seconds between course corrections sent for a homing bolt (clients steer
-- it the same way in between, so these only fix drift).
local HOMING_SYNC = 0.2

-- Hard cap so a flood of turrets/reflections can't grow the loop unbounded.
local MAX_LIVE = 300
-- Radius used against plain map geometry (walls, floors, cliffs).
local WORLD_RADIUS = 0.75
-- Breakable things, fetched once per frame and shared by every bolt.
local frameDestructibles: { Instance } = {}

local fxRemote = Remotes.get("Fx")
local live: { Live } = {}
local nextId = 0
local loop: RBXScriptConnection? = nil

local function applyHit(opts: LaunchOptions, hitInstance: Instance, direction: Vector3)
	local stats = opts.stats
	local target, _, isCharacter = DestructibleService.resolve(hitInstance)
	if not target then
		return
	end
	local damage = stats.damage or 0
	if
		isCharacter
		and stats.comboStatus
		and StatusService.has(target :: Model, stats.comboStatus)
	then
		damage *= stats.comboMultiplier or 1
	end
	local dealt = DestructibleService.damage(target, damage, opts.caster, opts.spellName)
	if dealt <= 0 and damage > 0 then
		return -- not allowed to hit (ally/self)
	end
	-- Status effects (Water Lock's stun, ...) work on players and on hostile NPCs.
	local affected = StatusService.targetOf(target)
	if affected and stats.status then
		local applied = StatusService.apply(affected, stats.status, stats.statusDuration or 1)
		-- Water Lock wraps its victim in the imported bubble model.
		if applied and stats.model then
			TrapBubble.show(affected, stats.statusDuration or 1, opts.visual.color, stats.model)
		end
	end
	-- Wind and other knockback shoves players and Battleground NPCs alike.
	local pushed = if isCharacter then target else affected
	if pushed and stats.knockback and stats.knockback ~= 0 then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		local push = if flat.Magnitude > 0 then flat.Unit else Vector3.zero
		DestructibleService.push(
			pushed,
			push * stats.knockback + Vector3.new(0, math.abs(stats.knockback) * 0.35, 0)
		)
	end
end

local function chainFrom(
	opts: LaunchOptions,
	from: Vector3,
	already: { [Instance]: boolean },
	remaining: number
)
	if remaining <= 0 or not opts.caster then
		return
	end
	local best: Model? = nil
	local bestDist = 25
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if
			character
			and root
			and not already[character]
			and DestructibleService.canHarm(opts.caster, character)
		then
			local d = (root.Position - from).Magnitude
			if d < bestDist then
				best, bestDist = character, d
			end
		end
	end
	if best then
		local root = best:FindFirstChild("HumanoidRootPart") :: BasePart
		fxRemote:FireAllClients("beam", from, root.Position, opts.visual.color)
		already[best] = true
		applyHit(opts, best, root.Position - from)
		chainFrom(opts, root.Position, already, remaining - 1)
	end
end

-- Where a homing bolt is heading: its target's middle, or nil once the target
-- is gone or down.
function Projectile.homingPoint(target: Model?): Vector3?
	if not target or not target.Parent then
		return nil
	end
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return nil
	end
	local root = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
	return if root and root:IsA("BasePart") then root.Position else target:GetPivot().Position
end

-- Slight tracking toward the auto-aim lock. Drops the lock once the target is
-- far off the bolt's heading (it sidestepped), so a good dodge still works.
local function steerHoming(p: Live, dt: number)
	if not p.homing then
		return
	end
	local point = Projectile.homingPoint(p.homing)
	local aim = Config.AUTO_AIM
	local desired = if point then point - p.position else nil
	if
		not desired
		or desired.Magnitude < 1
		or AutoAim.angleBetween(p.direction, desired) > math.rad(aim.HOMING_GIVE_UP)
	then
		p.homing = nil
	else
		p.direction = AutoAim.steer(p.direction, desired.Unit, math.rad(aim.HOMING) * dt)
	end
	local now = os.clock()
	if not p.homing or now - p.syncedAt >= HOMING_SYNC then
		p.syncedAt = now
		fxRemote:FireAllClients(
			"projectileTurn",
			p.id,
			p.position,
			p.direction,
			p.travelled,
			p.homing
		)
	end
end

-- Advances one projectile; returns true when it is finished.
local function step(p: Live, dt: number): boolean
	local opts = p.opts
	local caster = opts.caster
	steerHoming(p, dt)
	local stepLength = math.min(p.speed * dt, p.range - p.travelled)
	local result: RaycastResult? = nil
	-- World sweep uses a thin sphere so bolts glide over floors and ledges;
	-- the generous hitbox is applied to targets in the "fat" sweep below.
	local worldRadius = math.min(p.radius, WORLD_RADIUS)
	-- Up to 3 passes so we can skip allied structures in the same frame.
	for _ = 1, 3 do
		result = workspace:Spherecast(p.position, worldRadius, p.direction * stepLength, p.params)
		if not result then
			break
		end
		local hitTarget, owner, isCharacter = DestructibleService.resolve(result.Instance)
		local passThrough = hitTarget ~= nil
			and caster ~= nil
			and (
				(not isCharacter and not DestructibleService.canHarm(caster, hitTarget))
				or (isCharacter and owner == caster)
			)
		if passThrough then
			table.insert(p.ignore, hitTarget :: Instance)
			p.params.FilterDescendantsInstances = p.ignore
			result = nil
		else
			break
		end
	end

	-- Bigger hitbox for targets only (a wide world sweep would snag bolts on
	-- floors): sweep a fat sphere that only sees other characters and
	-- breakable things this caster can hurt, and take whichever hit is first.
	local targets: { Instance } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if other ~= caster and character and not table.find(p.ignore, character) then
			table.insert(targets, character)
		end
	end
	local reach = stepLength + p.radius + Config.HITBOX_BONUS + 12
	for _, thing in frameDestructibles do
		local pos = if thing:IsA("BasePart")
			then thing.Position
			elseif thing:IsA("Model") then thing:GetPivot().Position
			else nil
		if
			pos
			-- Floors are only broken by a direct strike, never by a bolt skimming over.
			and not thing:GetAttribute("GroundTile")
			and (pos - p.position).Magnitude <= reach
			and not table.find(p.ignore, thing)
			and (caster == nil or DestructibleService.canHarm(caster, thing))
		then
			table.insert(targets, thing)
		end
	end
	if #targets > 0 then
		local fat = RaycastParams.new()
		fat.FilterType = Enum.RaycastFilterType.Include
		fat.FilterDescendantsInstances = targets
		local targetHit = workspace:Spherecast(
			p.position,
			p.radius + Config.HITBOX_BONUS,
			p.direction * stepLength,
			fat
		)
		if targetHit and (not result or targetHit.Distance < result.Distance) then
			result = targetHit
		end
	end

	if not result then
		p.position += p.direction * stepLength
		p.travelled += stepLength
		return p.travelled >= p.range
	end

	p.position = result.Position
	local hitTarget, _, isCharacter = DestructibleService.resolve(result.Instance)
	-- Mirror buff: send it back at the caster.
	if hitTarget and isCharacter and StatusService.has(hitTarget :: Model, "Reflect") then
		local back = table.clone(opts)
		back.caster = Players:GetPlayerFromCharacter(hitTarget)
		back.origin = p.position - p.direction * 2
		back.direction = -p.direction
		back.ignore = { hitTarget }
		back.homing = nil
		task.defer(Projectile.launch, back)
	else
		applyHit(opts, result.Instance, p.direction)
		if opts.stats.chain and hitTarget then
			chainFrom(opts, p.position, { [hitTarget] = true }, opts.stats.chain)
		end
		-- Piercing bolts (Water Wave, Tornado) keep flying after they hit a
		-- player, and hit each player only once.
		if opts.stats.pierce and isCharacter and hitTarget then
			table.insert(p.ignore, hitTarget)
			p.params.FilterDescendantsInstances = p.ignore
			p.travelled += result.Distance
			return p.travelled >= p.range
		end
	end
	return true
end

local function finish(p: Live)
	-- Clients play the impact burst for this bolt (per-element VFX).
	fxRemote:FireAllClients("projectileEnd", p.id, p.position)
end

local function tick(dt: number)
	frameDestructibles = CollectionService:GetTagged("Destructible")
	for i = #live, 1, -1 do
		local p = live[i]
		local ok, done = pcall(step, p, dt)
		if not ok then
			warn(`[Projectile] {p.opts.spellName} step failed: {done}`)
		end
		if not ok or done then
			-- Swap-remove keeps this O(1); order doesn't matter.
			live[i] = live[#live]
			live[#live] = nil
			finish(p)
		end
	end
	if #live == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

function Projectile.launch(opts: LaunchOptions)
	if #live >= MAX_LIVE then
		return
	end
	local direction = if opts.direction.Magnitude > 0 then opts.direction.Unit else Vector3.zAxis
	local ignore = table.clone(opts.ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true

	nextId += 1
	local p: Live = {
		id = nextId,
		opts = opts,
		position = opts.origin,
		direction = direction,
		speed = (opts.stats.speed or 80) * Config.PROJECTILE_SPEED_SCALE,
		range = opts.stats.range or 150,
		radius = opts.stats.radius or 1,
		travelled = 0,
		ignore = ignore,
		params = params,
		homing = opts.homing,
		syncedAt = os.clock(),
	}
	table.insert(live, p)
	fxRemote:FireAllClients(
		"projectile",
		p.id,
		p.position,
		direction,
		p.speed,
		p.range,
		opts.visual,
		opts.fxKey or opts.spellName,
		p.homing
	)
	if not loop then
		loop = RunService.Heartbeat:Connect(tick)
	end
end

-- Number of projectiles in flight (for tests/diagnostics).
function Projectile.liveCount(): number
	return #live
end

-- Standard origin: in front of the caster's chest.
function Projectile.originFor(root: BasePart, target: Vector3): (Vector3, Vector3)
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local direction = target - origin
	if direction.Magnitude < 1 then
		direction = root.CFrame.LookVector
	end
	return origin + direction.Unit * 2.5, direction.Unit
end

function Projectile.cast(ctx: any): boolean?
	local origin, direction = Projectile.originFor(ctx.root, ctx.target)
	Projectile.launch({
		caster = ctx.player,
		origin = origin,
		direction = direction,
		stats = ctx.def.stats,
		visual = ctx.def.visual,
		spellName = ctx.def.name,
		fxKey = ctx.def.id,
		ignore = { ctx.character },
		homing = ctx.lock,
	})
	return true
end

return Projectile
