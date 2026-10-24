--!strict
-- The single damage path for everything: players, placed objects, summons,
-- and destructible map props. Anything tagged "Destructible" has Health /
-- MaxHealth attributes and a health bar; players use their Humanoid.
--
-- Who may hurt whom is decided by a relation resolver that MatchService
-- installs (teams in matches, sparring ring in the hub).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local Placement = require(ReplicatedStorage.Shared.Spells.Placement)
local StatusService = require(script.Parent.StatusService)

local TAG = "Destructible"
local ASSIST_WINDOW = 6

local DestructibleService = {}

-- (victim, killer?, spellName?)
DestructibleService.Knockout = Signal.new() :: Signal.Signal<Player, Player?, string?>
-- (structure, destroyer?)
DestructibleService.Destroyed = Signal.new() :: Signal.Signal<Instance, Player?>

-- Returns true if `attacker` may damage `victimOwner` (a player, or nil for
-- unowned things like dummies and map props). Replaced by MatchService.
local relation: (attacker: Player?, victimOwner: Player?, target: Instance) -> boolean = function(
	_attacker: Player?,
	_victimOwner: Player?,
	_target: Instance
)
	return true
end

function DestructibleService.setRelationResolver(fn: (Player?, Player?, Instance) -> boolean)
	relation = fn
end

local MAX_PUSH = 250
-- How long the server holds a pushed character's physics before returning it.
local PUSH_OWNERSHIP_TIME = 0.45

local lastHit: { [Player]: { by: Player, at: number, spell: string? } } = {}
local impulseRemote: RemoteEvent
local fxRemote: RemoteEvent

-- Resolves any part/model to the thing that owns health: a player character
-- or a Destructible-tagged model/part. Returns (target, ownerPlayer?, isCharacter).
function DestructibleService.resolve(instance: Instance): (Instance?, Player?, boolean)
	local node: Instance? = instance
	while node and node ~= workspace do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
			local player = Players:GetPlayerFromCharacter(node)
			if player then
				return node, player, true
			end
		end
		if CollectionService:HasTag(node, TAG) then
			local ownerId = node:GetAttribute("OwnerUserId")
			local owner = if typeof(ownerId) == "number"
				then Players:GetPlayerByUserId(ownerId)
				else nil
			return node, owner, false
		end
		node = node.Parent
	end
	return nil, nil, false
end

function DestructibleService.canHarm(attacker: Player?, target: Instance): boolean
	local resolved, owner, _ = DestructibleService.resolve(target)
	if not resolved then
		return false
	end
	if attacker and owner == attacker then
		return false
	end
	return relation(attacker, owner, resolved)
end

local function updateBar(target: Instance)
	local bar = target:FindFirstChild("HealthBar", true)
	if bar and bar:IsA("BillboardGui") then
		local fill = bar:FindFirstChild("Fill", true)
		local health = target:GetAttribute("Health") :: number? or 0
		local max = target:GetAttribute("MaxHealth") :: number? or 1
		if fill and fill:IsA("Frame") then
			fill.Size = UDim2.fromScale(math.clamp(health / max, 0, 1), 1)
		end
		bar.Enabled = health < max
	end
end

-- Cosmetic burst of debris. Rendered by each client (FxController) so the
-- server never replicates throwaway physics parts.
local function poof(position: Vector3, color: Color3)
	fxRemote:FireAllClients("poof", position, color)
end
DestructibleService.poof = poof

local function breakStructure(target: Instance, destroyer: Player?)
	if target:GetAttribute("Broken") then
		return
	end
	target:SetAttribute("Broken", true)
	local position = if target:IsA("Model")
		then target:GetPivot().Position
		elseif target:IsA("BasePart") then target.Position
		else Vector3.zero
	local color = Color3.fromRGB(200, 200, 200)
	local part = if target:IsA("BasePart")
		then target
		else target:FindFirstChildWhichIsA("BasePart", true)
	if part then
		color = part.Color
	end
	poof(position, color)
	DestructibleService.Destroyed:Fire(target, destroyer)
	target:Destroy()
end

-- Applies damage. Returns the damage actually dealt (0 if not allowed).
function DestructibleService.damage(
	target: Instance,
	amount: number,
	attacker: Player?,
	spellName: string?
): number
	local resolved, owner, isCharacter = DestructibleService.resolve(target)
	if not resolved or amount <= 0 then
		return 0
	end
	if attacker and owner == attacker then
		return 0
	end
	if not relation(attacker, owner, resolved) then
		return 0
	end

	if isCharacter and owner then
		local character = resolved :: Model
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return 0
		end
		if character:FindFirstChildOfClass("ForceField") then
			return 0
		end
		-- Shrunk players take extra damage; giants take less.
		if StatusService.has(character, "Shrink") then
			amount *= 1.25
		elseif StatusService.has(character, "Giant") then
			amount *= 0.75
		end
		local shield = character:GetAttribute("Shield") :: number? or 0
		if shield > 0 then
			local absorbed = math.min(shield, amount)
			amount -= absorbed
			character:SetAttribute(
				"Shield",
				if shield - absorbed > 0 then shield - absorbed else nil
			)
		end
		if attacker then
			lastHit[owner] = { by = attacker, at = os.clock(), spell = spellName }
		end
		if amount >= humanoid.Health and StatusService.has(character, "Revive") then
			StatusService.clear(character, "Revive")
			humanoid.Health = humanoid.MaxHealth / 2
			poof(character:GetPivot().Position, Color3.fromRGB(255, 145, 0))
			return amount
		end
		humanoid:TakeDamage(amount)
		return amount
	end

	-- Structures / summons / props
	local health = (resolved:GetAttribute("Health") :: number?) or 0
	health -= amount
	resolved:SetAttribute("Health", health)
	updateBar(resolved)
	if health <= 0 then
		breakStructure(resolved, attacker)
	end
	return amount
end

function DestructibleService.heal(character: Model, amount: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

-- Knockback, server-authoritative. Clients own their character's physics,
-- so the server briefly takes network ownership of the victim's root,
-- applies the velocity itself, then hands ownership back. A client that
-- ignores remotes can't dodge knockback, pulls, traps, or ring-outs.
local pushTokens: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

function DestructibleService.push(target: Instance, velocity: Vector3)
	local resolved, owner, isCharacter = DestructibleService.resolve(target)
	if not (isCharacter and owner and resolved) or velocity.Magnitude ~= velocity.Magnitude then
		return
	end
	local character = resolved :: Model
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or root.Anchored then
		return
	end
	if StatusService.has(character, "Giant") then
		velocity *= 0.5
	end
	if velocity.Magnitude > MAX_PUSH then
		velocity = velocity.Unit * MAX_PUSH
	end
	local token = (pushTokens[character] or 0) + 1
	pushTokens[character] = token
	local took = pcall(function()
		root:SetNetworkOwner(nil)
	end)
	if velocity.Y > 20 then
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	root.AssemblyLinearVelocity = root.AssemblyLinearVelocity * 0.25 + velocity
	if took then
		-- Only the latest push returns ownership (overlapping pushes extend it).
		task.delay(PUSH_OWNERSHIP_TIME, function()
			if
				pushTokens[character] == token
				and root.Parent
				and owner.Parent
				and not root.Anchored
			then
				pcall(function()
					root:SetNetworkOwner(owner)
				end)
			end
		end)
	end
end

-- Movement that only helps its owner (dash, balloon, jump/bounce pads) is
-- applied by the owning client for responsiveness: skipping it only hurts
-- the cheater, so it doesn't need to be authoritative.
function DestructibleService.boost(character: Model, velocity: Vector3)
	local owner = Players:GetPlayerFromCharacter(character)
	if owner then
		impulseRemote:FireClient(owner, velocity)
	end
end

-- Who last hit this player (within the assist window), for ring-out credit.
function DestructibleService.recentAttacker(victim: Player): (Player?, string?)
	local info = lastHit[victim]
	if info and os.clock() - info.at <= ASSIST_WINDOW and info.by.Parent then
		return info.by, info.spell
	end
	return nil, nil
end

-- Builds a primitive-based object from a spell visual, tags it Destructible,
-- and gives it a health bar. Used for placeables and summons.
function DestructibleService.build(
	name: string,
	visual: Types.Visual,
	health: number,
	owner: Player?,
	teamName: string?
): Model
	local model = Instance.new("Model")
	model.Name = name
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Shape = if visual.shape == "Ball"
		then Enum.PartType.Ball
		elseif visual.shape == "Cylinder" then Enum.PartType.Cylinder
		elseif visual.shape == "Wedge" then Enum.PartType.Wedge
		else Enum.PartType.Block
	part.Size = visual.size
	part.Color = visual.color
	part.Material = visual.material
	part.Transparency = visual.transparency or 0
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	model.PrimaryPart = part

	local bar = Instance.new("BillboardGui")
	bar.Name = "HealthBar"
	bar.Size = UDim2.fromOffset(80, 10)
	bar.StudsOffsetWorldSpace = Vector3.new(0, Placement.height(visual) / 2 + 1.5, 0)
	bar.AlwaysOnTop = true
	bar.MaxDistance = 120
	bar.Enabled = false
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	back.BorderSizePixel = 0
	back.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(102, 187, 106)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	bar.Parent = part

	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	if owner then
		model:SetAttribute("OwnerUserId", owner.UserId)
	end
	if teamName then
		model:SetAttribute("Team", teamName)
	end
	CollectionService:AddTag(model, TAG)
	return model
end

-- Registers an existing map prop as destructible (used by map builders).
function DestructibleService.makeProp(instance: Instance, health: number)
	instance:SetAttribute("Health", health)
	instance:SetAttribute("MaxHealth", health)
	CollectionService:AddTag(instance, TAG)
end

function DestructibleService.init()
	impulseRemote = Remotes.get("Impulse")
	fxRemote = Remotes.get("Fx")
end

function DestructibleService.start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.Died:Connect(function()
				local killer, spell = DestructibleService.recentAttacker(player)
				lastHit[player] = nil
				poof(character:GetPivot().Position, Color3.fromRGB(80, 60, 160))
				DestructibleService.Knockout:Fire(player, killer, spell)
			end)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
	end)
end

return DestructibleService
