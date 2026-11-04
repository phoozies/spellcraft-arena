--!strict
-- Casts a spell the moment it is drawn, dispatching to the spell's archetype.
--
-- The client only sends intent, with its drawing (SpellInputService): the point
-- under its first-person crosshair and (for placeables) a rotation. The server
-- checks the character is alive and allowed to act and the spell is off
-- cooldown, clamps the target to range, follows the sight (resolveAim: nothing
-- lands through a wall, and bolts get the quiet aim assist in ctx.lock), then
-- builds a CastContext the archetype uses for all world queries.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Quality = require(ReplicatedStorage.Shared.Spells.Quality)
local Types = require(ReplicatedStorage.Shared.Types)
local AutoAim = require(ReplicatedStorage.Shared.Util.AutoAim)
local DestructibleService = require(script.Parent.DestructibleService)
local SpellbookService = require(script.Parent.SpellbookService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local BoostService = require(script.Parent.BoostService)
local StatusService = require(script.Parent.StatusService)
local TelemetryService = require(script.Parent.TelemetryService)

export type Target = { character: Model?, instance: Instance, player: Player?, position: Vector3 }

export type CastContext = {
	player: Player,
	character: Model,
	root: BasePart,
	-- The spell, already scaled by the drawing's quality (Spells/Quality).
	def: Types.SpellDef,
	quality: number,
	target: Vector3,
	-- The aim assist's pick (a character or NPC), for bolts only.
	lock: Model?,
	rotationY: number,
	-- Every living character: ground checks look through them.
	characters: { Instance },
	team: string?,
	-- Folder new structures/summons go into (arena or hub).
	structures: Instance,
	-- Parts whose volume allows building (arena bounds or hub build zones).
	buildRegions: { BasePart },
	enemiesNear: (position: Vector3, radius: number) -> { Target },
	alliesNear: (position: Vector3, radius: number) -> { Model },
	structuresNear: (position: Vector3, radius: number) -> { Instance },
}

-- Hooks MatchService provides (kept as injected functions to avoid a
-- require cycle: MatchService depends on CastService's dependencies).
export type WorldHooks = {
	teamOf: (player: Player) -> string?,
	structuresFolderFor: (player: Player) -> Instance,
	buildRegionsFor: (player: Player) -> { BasePart },
	areAllies: (a: Player, b: Player) -> boolean,
}

local CastService = {}

local hooks: WorldHooks? = nil
local archetypes: { [string]: any } = {}
local fxRemote: RemoteEvent

function CastService.setWorldHooks(newHooks: WorldHooks)
	hooks = newHooks
end

local function enemiesNear(caster: Player, position: Vector3, radius: number): { Target }
	local results: { Target } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			character
			and root
			and humanoid
			and humanoid.Health > 0
			-- Bigger hitbox: areas reach a little past their visual edge.
			and (root.Position - position).Magnitude <= radius + Config.HITBOX_BONUS
			and DestructibleService.canHarm(caster, character)
		then
			table.insert(results, {
				character = character,
				instance = character,
				player = other,
				position = root.Position,
			})
		end
	end
	for _, thing in CollectionService:GetTagged("Destructible") do
		if thing:IsA("Model") or thing:IsA("BasePart") then
			local pos = if thing:IsA("Model")
				then thing:GetPivot().Position
				else (thing :: BasePart).Position
			if
				(pos - position).Magnitude <= radius and DestructibleService.canHarm(caster, thing)
			then
				table.insert(
					results,
					{ character = nil, instance = thing, player = nil, position = pos }
				)
			end
		end
	end
	return results
end

local function alliesNear(caster: Player, position: Vector3, radius: number): { Model }
	local results = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and root and (root.Position - position).Magnitude <= radius then
			if other == caster or (hooks and hooks.areAllies(caster, other)) then
				table.insert(results, character)
			end
		end
	end
	return results
end

local function structuresNear(position: Vector3, radius: number): { Instance }
	local results = {}
	for _, thing in CollectionService:GetTagged("Destructible") do
		if thing:IsA("Model") and thing:GetAttribute("OwnerUserId") ~= nil then
			if (thing:GetPivot().Position - position).Magnitude <= radius then
				table.insert(results, thing)
			end
		end
	end
	return results
end

local function isFiniteVector(v: any): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

-- Every living character: a sight or a spell's ground check passes through them.
local function allCharacters(): { Instance }
	local list: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	return list
end

-- Only bolts get the aim assist: they have to fly there and can be dodged.
-- Anything that lands (strikes, lines, walls, turrets) lands on the sight.
local function isBolt(def: Types.SpellDef): boolean
	return def.archetype == "Projectile" or (def.archetype == "Control" and def.stats.speed ~= nil)
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return if root and root:IsA("BasePart") then root else nil
end

-- Everything the caster could lock onto: enemy players, hostile NPCs and
-- training dummies (never props, walls or allies).
local function aimCandidates(caster: Player): { AutoAim.Candidate }
	local candidates: { AutoAim.Candidate } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and rootOf(character)
		if
			other ~= caster
			and character
			and root
			and humanoid
			and humanoid.Health > 0
			and DestructibleService.canHarm(caster, character)
		then
			table.insert(candidates, {
				position = root.Position,
				velocity = root.AssemblyLinearVelocity,
				radius = 2,
				key = character,
			})
		end
	end
	for _, thing in CollectionService:GetTagged("Destructible") do
		if
			thing:IsA("Model")
			and DestructibleService.isTrainingTarget(thing)
			and DestructibleService.canHarm(caster, thing)
		then
			local root = rootOf(thing)
			local humanoid = thing:FindFirstChildOfClass("Humanoid")
			if root and (not humanoid or humanoid.Health > 0) then
				table.insert(candidates, {
					position = root.Position,
					velocity = root.AssemblyLinearVelocity,
					radius = math.max(2, thing:GetExtentsSize().X / 2),
					key = thing,
				})
			end
		end
	end
	return candidates
end

-- Nothing solid between the caster's eyes and the candidate.
local function inSight(eye: Vector3, character: Model, candidate: AutoAim.Candidate): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, candidate.key :: Instance }
	params.RespectCanCollide = true
	local offset = candidate.position - eye
	return workspace:Raycast(eye, offset, params) == nil
end

-- The way the player looks: toward the point under their crosshair, unless
-- that is far from where their character faces (a lagging or lying client),
-- in which case the character's facing is used with the sent pitch.
local function lookDirection(eye: Vector3, root: BasePart, target: Vector3): Vector3
	local look = target - eye
	if look.Magnitude < 1e-3 then
		return root.CFrame.LookVector
	end
	look = look.Unit
	local flat = Vector3.new(look.X, 0, look.Z)
	local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if
		flat.Magnitude > 1e-3
		and AutoAim.angleBetween(flat, facing) > math.rad(Config.AUTO_AIM.MAX_YAW_ERROR)
	then
		return (facing.Unit * flat.Magnitude + Vector3.new(0, look.Y, 0)).Unit
	end
	return look
end

-- How far the sight reaches along `look` before something solid stops it (never
-- through a wall, whatever the client says): the end of the ray, or the hit.
local function sightPoint(eye: Vector3, look: Vector3, reach: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = allCharacters()
	params.RespectCanCollide = true
	local hit = workspace:Raycast(eye, look * reach, params)
	return if hit then hit.Position else eye + look * reach
end

-- Decides where the spell goes. Every spell follows the sight:
--   * self-centred spells (buffs, Earthquake) ignore it;
--   * placeables stand on the first solid thing along it, up to PLACE_RANGE, and
--     look through characters so a wall aimed past someone doesn't entomb them;
--   * strikes, lines and area spells land where the sight stops;
--   * bolts fly along it, led at the opponent the aim assist picks, if any.
local function resolveAim(
	player: Player,
	character: Model,
	root: BasePart,
	def: Types.SpellDef,
	target: Vector3,
	maxRange: number
): (Vector3, Model?)
	local head = character:FindFirstChild("Head")
	local eye = if head and head:IsA("BasePart")
		then head.Position
		else root.Position + Vector3.new(0, 1.5, 0)
	if def.archetype == "Buff" or (def.stats.range or 1) <= 0 then
		return target, nil
	end
	local look = lookDirection(eye, root, target)
	if def.archetype == "Placeable" then
		return sightPoint(eye, look, maxRange), nil
	end
	local reach = math.max(math.min((target - eye).Magnitude, maxRange), 1)
	if not isBolt(def) then
		return sightPoint(eye, look, reach), nil
	end
	local straight = eye + look * reach
	local lock = AutoAim.pick(eye, look, aimCandidates(player), {
		range = maxRange,
		visible = function(candidate)
			return inSight(eye, character, candidate)
		end,
	})
	if not lock then
		return straight, nil
	end
	local speed = def.stats.speed
	local aimPoint = if speed
		then AutoAim.lead(eye, lock.position, lock.velocity, speed * Config.PROJECTILE_SPEED_SCALE)
		else lock.position
	return aimPoint, lock.key :: Model
end

-- Casts a spell right now at the point under the player's crosshair. Called
-- for a recognized drawing (SpellInputService), which already checked the
-- spell is theirs. `force` (admin) skips the cooldown check. Returns (ok,
-- reason); on false nothing happened and `reason`, if any, says why.
function CastService.cast(
	player: Player,
	spellId: string,
	target: any,
	rotationY: any,
	quality: number,
	force: boolean?
): (boolean, string?)
	if not isFiniteVector(target) then
		return false, nil
	end
	-- Finite only: an infinite number would come out of the % as NaN.
	local rotation = if typeof(rotationY) == "number" and math.abs(rotationY) < 1e6
		then rotationY % (2 * math.pi)
		else 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 or not hooks then
		return false, nil
	end
	if StatusService.has(character, "TimeStop") or character:GetAttribute("Frozen") then
		return false, nil
	end
	-- Stunned (Water Lock) or mid-channel (Earthquake): no casting.
	if StatusService.has(character, "Stun") or StatusService.has(character, "Channel") then
		return false, "You can't cast right now!"
	end
	local def = SpellDefinitions.get(spellId)
	if not def then
		return false, "Unknown spell."
	end
	if not force then
		local ready, left = SpellbookService.checkCast(player, spellId)
		if not ready then
			return false, `{def.name} cooling down ({math.ceil(left * 10) / 10}s)`
		end
	end

	-- Clamp the target to the spell's range (or the general aim range).
	local maxRange = def.stats.range or Config.AIM_RANGE
	if def.archetype == "Placeable" then
		maxRange = Config.PLACE_RANGE
	end
	local offset = (target :: Vector3) - root.Position
	if offset.Magnitude > maxRange then
		target = root.Position + offset.Unit * maxRange
	end
	-- First person: the spell goes where the sight points.
	local lock: Model? = nil
	target, lock = resolveAim(player, character, root, def, target :: Vector3, maxRange)

	local archetype = archetypes[def.archetype]
	if not archetype then
		warn(`[CastService] no archetype handler for {def.archetype}`)
		return false, nil
	end

	-- A well-drawn spell hits harder, wider, and lasts longer.
	local activeHooks = hooks :: WorldHooks
	local ctx: CastContext = {
		player = player,
		character = character,
		root = root,
		def = Quality.apply(def, quality),
		quality = quality,
		target = target,
		lock = lock,
		rotationY = rotation,
		characters = allCharacters(),
		team = activeHooks.teamOf(player),
		structures = activeHooks.structuresFolderFor(player),
		buildRegions = activeHooks.buildRegionsFor(player),
		enemiesNear = function(position, radius)
			return enemiesNear(player, position, radius)
		end,
		alliesNear = function(position, radius)
			return alliesNear(player, position, radius)
		end,
		structuresNear = structuresNear,
	}

	local castOk, result = pcall(archetype.cast, ctx)
	if not castOk then
		warn(`[CastService] {def.id} failed: {result}`)
		return false, nil
	end
	if result == false then
		return false, "Can't cast that there." -- archetype rejected (e.g. invalid placement)
	end

	-- The Focus match boost shortens every spell's cooldown.
	local cooldown = def.cooldown * BoostService.cooldownFactor(player)
	if StatusService.has(character, "CooldownCut") then
		cooldown *= 0.5
	end
	SpellbookService.startCooldown(player, spellId, cooldown)
	-- Everyone nearby plays the cast animation + magic circle.
	fxRemote:FireAllClients("cast", character, spellId, target)

	local profile = PlayerDataService.get(player)
	if profile then
		profile.stats.casts += 1
	end
	EconomyService.track(player, "cast")
	TelemetryService.onboarding(player, "FirstCast")
	if def.archetype == "Placeable" then
		EconomyService.track(player, "place")
	end
	return true, nil
end

-- Admin (";cast"): casts a spell for a player where they are facing, at an
-- average drawing's quality, whether or not they own it or it is cooling down.
function CastService.castForced(player: Player, spellId: string): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local target = root.Position + root.CFrame.LookVector * Config.PLACE_RANGE
	return (CastService.cast(player, spellId, target, 0, Config.QUALITY.DEFAULT, true))
end

-- Studio QA (DebugService "cast"): casts a spell at `target` through the normal
-- pipeline, so range, cooldowns, placement and every archetype rule still apply.
function CastService.castFor(player: Player, spellId: string, target: Vector3): boolean
	return (CastService.cast(player, spellId, target, 0, Config.QUALITY.DEFAULT))
end

function CastService.init()
	fxRemote = Remotes.get("Fx")
	for _, module in script.Parent:WaitForChild("Archetypes"):GetChildren() do
		if module:IsA("ModuleScript") then
			archetypes[module.Name] = require(module) :: any
		end
	end
end

function CastService.start()
	DestructibleService.Destroyed:Connect(function(_, destroyer)
		if destroyer then
			EconomyService.track(destroyer, "destroy")
		end
	end)
end

return CastService
