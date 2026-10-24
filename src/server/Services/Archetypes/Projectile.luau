--!strict
-- Projectile archetype: a server-simulated sphere-cast that flies toward
-- the target and hits the first player/structure/wall in its path.
--
-- Reads stats: damage, speed, range, radius, knockback, status,
-- statusDuration, chain, comboStatus, comboMultiplier.
-- Also used by Control (status projectiles) and by turrets/summons via
-- Projectile.launch().
--
-- Performance: every live projectile is stepped by ONE shared Heartbeat
-- loop, and the server creates no Parts for them. Clients draw the visual
-- from a single "projectile" Fx event and remove it on "projectileEnd", so
-- nothing replicates per frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DestructibleService = require(script.Parent.Parent.DestructibleService)
local StatusService = require(script.Parent.Parent.StatusService)

export type LaunchOptions = {
	caster: Player?,
	origin: Vector3,
	direction: Vector3,
	stats: Types.SpellStats,
	visual: Types.Visual,
	spellName: string,
	ignore: { Instance },
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
}

local Projectile = {}

-- Hard cap so a flood of turrets/reflections can't grow the loop unbounded.
local MAX_LIVE = 300

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
	if isCharacter then
		local character = target :: Model
		if stats.status then
			StatusService.apply(character, stats.status, stats.statusDuration or 1)
		end
		if stats.knockback and stats.knockback ~= 0 then
			local flat = Vector3.new(direction.X, 0, direction.Z)
			local push = if flat.Magnitude > 0 then flat.Unit else Vector3.zero
			DestructibleService.push(
				character,
				push * stats.knockback + Vector3.new(0, math.abs(stats.knockback) * 0.35, 0)
			)
		end
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

-- Advances one projectile; returns true when it is finished.
local function step(p: Live, dt: number): boolean
	local opts = p.opts
	local caster = opts.caster
	local stepLength = math.min(p.speed * dt, p.range - p.travelled)
	local result: RaycastResult? = nil
	-- Up to 3 passes so we can skip allied structures in the same frame.
	for _ = 1, 3 do
		result = workspace:Spherecast(p.position, p.radius, p.direction * stepLength, p.params)
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
		task.defer(Projectile.launch, back)
	else
		applyHit(opts, result.Instance, p.direction)
		if opts.stats.chain and hitTarget then
			chainFrom(opts, p.position, { [hitTarget] = true }, opts.stats.chain)
		end
	end
	return true
end

local function finish(p: Live)
	fxRemote:FireAllClients("projectileEnd", p.id, p.position)
	DestructibleService.poof(p.position, p.opts.visual.color)
end

local function tick(dt: number)
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
		speed = opts.stats.speed or 80,
		range = opts.stats.range or 150,
		radius = opts.stats.radius or 1,
		travelled = 0,
		ignore = ignore,
		params = params,
	}
	table.insert(live, p)
	fxRemote:FireAllClients(
		"projectile",
		p.id,
		p.position,
		direction,
		p.speed,
		p.range,
		opts.visual
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
		ignore = { ctx.character },
	})
	return true
end

return Projectile
