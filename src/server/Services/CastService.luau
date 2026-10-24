--!strict
-- Validates CastSpell requests and dispatches to the spell's archetype.
--
-- The client only sends intent: a target point and (for placeables) a
-- rotation. The server checks the character is alive and allowed to act,
-- the spell is readied and off cooldown, clamps the target to range, then
-- builds a CastContext the archetype uses for all world queries.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Types = require(ReplicatedStorage.Shared.Types)
local DestructibleService = require(script.Parent.DestructibleService)
local HandService = require(script.Parent.HandService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local StatusService = require(script.Parent.StatusService)

export type Target = { character: Model?, instance: Instance, player: Player?, position: Vector3 }

export type CastContext = {
	player: Player,
	character: Model,
	root: BasePart,
	def: Types.SpellDef,
	target: Vector3,
	rotationY: number,
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
local toastRemote: RemoteEvent

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
			and (root.Position - position).Magnitude <= radius
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

local function onCast(player: Player, target: any, rotationY: any)
	if not isFiniteVector(target) then
		return
	end
	local rotation = if typeof(rotationY) == "number" and rotationY == rotationY
		then rotationY % (2 * math.pi)
		else 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 or not hooks then
		return
	end
	if StatusService.has(character, "TimeStop") or character:GetAttribute("Frozen") then
		return
	end
	-- Must be holding a copy of the readied spell (typing grants copies).
	local spellId = HandService.getReadied(player)
	local def = spellId and SpellDefinitions.get(spellId)
	if not spellId or not def then
		toastRemote:FireClient(player, "Type a spell word first!", "fizzle")
		return
	end
	if not HandService.checkCastLockout(player) then
		return
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

	local archetype = archetypes[def.archetype]
	if not archetype then
		warn(`[CastService] no archetype handler for {def.archetype}`)
		return
	end

	local activeHooks = hooks :: WorldHooks
	local ctx: CastContext = {
		player = player,
		character = character,
		root = root,
		def = def,
		target = target,
		rotationY = rotation,
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
		return
	end
	if result == false then
		return -- archetype rejected (e.g. invalid placement); the copy is kept
	end

	-- The copy is used up; the word recharges before it can be typed again.
	local recharge = def.cooldown
	if StatusService.has(character, "CooldownCut") then
		recharge *= 0.5
	end
	HandService.consume(player, spellId)
	HandService.startRecharge(player, spellId, recharge)

	local profile = PlayerDataService.get(player)
	if profile then
		profile.stats.casts += 1
	end
	ProgressionService.track(player, "cast")
	if def.archetype == "Placeable" then
		ProgressionService.track(player, "place")
	end
end

function CastService.init()
	toastRemote = Remotes.get("Toast")
	for _, module in script.Parent:WaitForChild("Archetypes"):GetChildren() do
		if module:IsA("ModuleScript") then
			archetypes[module.Name] = require(module) :: any
		end
	end
end

function CastService.start()
	Remotes.get("CastSpell").OnServerEvent:Connect(onCast)
	DestructibleService.Destroyed:Connect(function(_, destroyer)
		if destroyer then
			ProgressionService.track(destroyer, "destroy")
		end
	end)
end

return CastService
