--!strict
-- The Battleground: a drop-in open world (Maps/Battleground) far from the
-- hub. Step into the hub's Battleground portal to be teleported to a random
-- open spot there; step on a green gate pad (or press the HUD button) to go
-- back. NpcService fills the world with hostile NPCs worth coins.
--
--   * Anyone inside can hurt anyone else inside (MatchService.relation reads
--     the player attribute "InBattleground"); nobody outside can hurt them.
--     Party members (PartyService) are the exception: they are allies, and
--     drop in beside each other.
--   * When you're knocked out you respawn at a random spot after a few
--     seconds, with the usual spawn protection.
--   * No coins, wins, or boosts: it's for practice and fun. You use your
--     equipped element's spells, with no health regen (like a match).
--   * Leaving the hub's queue/match flow: you can't join a queue from here.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local DestructibleService = require(script.Parent.DestructibleService)
local ElementService = require(script.Parent.ElementService)
local MatchService = require(script.Parent.MatchService)
local PartyService = require(script.Parent.PartyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local buildBattleground = require(script.Parent.Parent:WaitForChild("Maps"):WaitForChild("Battleground")) :: any

local BattlegroundService = {}

local TOUCH_COOLDOWN = 2
-- A random drop-in stops searching once it is this far from NPCs / other fighters.
local SAFE_NPC_DISTANCE = 70
local SAFE_FIGHTER_DISTANCE = 80

local toastRemote: RemoteEvent
local mapModel: Model
local lastTouch: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

function BattlegroundService.isIn(player: Player): boolean
	return player:GetAttribute("InBattleground") == true
end

-- Where a fighter drops in: a random open spot in the world, away from every
-- NPC camp and from the other fighters, not inside scenery.
local function spawnCFrame(player: Player): CFrame
	local center = Config.BATTLEGROUND.CENTER
	local reach = Config.BATTLEGROUND.HALF_SIZE - 40
	local others: { Vector3 } = {}
	local friends: { Vector3 } = {}
	for _, other in Players:GetPlayers() do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and other ~= player and BattlegroundService.isIn(other) then
			if PartyService.sameParty(player, other) then
				table.insert(friends, root.Position)
			else
				table.insert(others, root.Position)
			end
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { mapModel }
	-- Drop in beside a party member who is already out there.
	if #friends > 0 then
		local anchor = friends[math.random(#friends)]
		for _ = 1, 12 do
			local angle = math.random() * math.pi * 2
			local position = anchor + Vector3.new(math.cos(angle) * 10, 2, math.sin(angle) * 10)
			if #workspace:GetPartBoundsInBox(CFrame.new(position + Vector3.new(0, 3, 0)), Vector3.new(6, 8, 6), overlap) == 0 then
				return CFrame.lookAt(position, Vector3.new(anchor.X, position.Y, anchor.Z))
			end
		end
	end
	local best = center + Vector3.new(0, 4, 0)
	local bestScore = -math.huge
	for _ = 1, 25 do
		local position = center + Vector3.new(math.random(-reach, reach), 4, math.random(-reach, reach))
		local nearestNpc = math.huge
		for _, spot in CollectionService:GetTagged("NpcSpot") do
			nearestNpc = math.min(nearestNpc, (spot.Position - position).Magnitude)
		end
		local nearestFighter = math.huge
		for _, point in others do
			nearestFighter = math.min(nearestFighter, (point - position).Magnitude)
		end
		local clear = #workspace:GetPartBoundsInBox(CFrame.new(position + Vector3.new(0, 3, 0)), Vector3.new(6, 8, 6), overlap) == 0
		local score = math.min(nearestNpc, 120) + math.min(nearestFighter, 120)
		if clear and score > bestScore then
			best, bestScore = position, score
			if nearestNpc >= SAFE_NPC_DISTANCE and nearestFighter >= SAFE_FIGHTER_DISTANCE then
				break
			end
		end
	end
	return CFrame.new(best) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
end

local function markCharacter(player: Player)
	local character = player.Character
	if character then
		character:SetAttribute("Battleground", true)
	end
end

-- Drops a player into the battleground. Returns (ok, reason).
function BattlegroundService.enter(player: Player): (boolean, string?)
	if BattlegroundService.isIn(player) then
		return false, nil
	end
	if not PlayerDataService.get(player) then
		return false, "Your spellbook is still loading."
	end
	if MatchService.isInMatch(player) then
		return false, "Finish your match first."
	end
	if MatchService.queuedMode(player) then
		MatchService.leaveQueue(player)
	end
	if not ElementService.equipped(player) then
		return false, "Pick your first element in the Spellbook before you fight!"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, nil
	end
	player:SetAttribute("InBattleground", true)
	MatchService.teleport(player, spawnCFrame(player))
	markCharacter(player)
	toastRemote:FireClient(player, "Battleground! Everyone here is an enemy. Good luck!", "round")
	return true, nil
end

-- Sends a player back to the hub.
function BattlegroundService.leave(player: Player)
	if not BattlegroundService.isIn(player) then
		return
	end
	player:SetAttribute("InBattleground", nil)
	MatchService.spawnInHub(player)
end

local function playerFromHit(hit: BasePart): Player?
	local character = hit.Parent
	return if character then Players:GetPlayerFromCharacter(character) else nil
end

local function wire(tag: string, action: (Player) -> ())
	local function hook(part: Instance)
		if not part:IsA("BasePart") then
			return
		end
		part.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if not player then
				return
			end
			local now = os.clock()
			if now - (lastTouch[player] or 0) < TOUCH_COOLDOWN then
				return
			end
			lastTouch[player] = now
			action(player)
		end)
	end
	for _, part in CollectionService:GetTagged(tag) do
		hook(part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(hook)
end

function BattlegroundService.init()
	toastRemote = Remotes.get("Toast")
	mapModel = buildBattleground(Config.BATTLEGROUND.CENTER) :: Model
	mapModel.Parent = workspace
end

local lastLeave: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

function BattlegroundService.start()
	-- "Return to hub" button on the HUD.
	Remotes.get("LeaveBattleground").OnServerEvent:Connect(function(player)
		local now = os.clock()
		if now - (lastLeave[player] or 0) < 1 then
			return
		end
		lastLeave[player] = now
		BattlegroundService.leave(player)
	end)
	wire("BattlegroundPortal", function(player)
		local ok, reason = BattlegroundService.enter(player)
		if not ok and reason then
			toastRemote:FireClient(player, reason, "fizzle")
		end
	end)
	wire("BattlegroundExit", function(player)
		BattlegroundService.leave(player)
	end)

	-- Safety net: anyone who still ends up below the world or outside the
	-- walls is put back at a random spot.
	task.spawn(function()
		local center = Config.BATTLEGROUND.CENTER
		local limit = Config.BATTLEGROUND.HALF_SIZE + 6
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and BattlegroundService.isIn(player) then
					local offset = root.Position - center
					if offset.Y < -40 or math.abs(offset.X) > limit or math.abs(offset.Z) > limit then
						root.AssemblyLinearVelocity = Vector3.zero
						root.CFrame = spawnCFrame(player)
					end
				end
			end
		end
	end)

	-- Knocked out in the battleground: back in after a short wait.
	DestructibleService.Knockout:Connect(function(victim)
		if not BattlegroundService.isIn(victim) then
			return
		end
		task.delay(Config.BATTLEGROUND.RESPAWN_DELAY, function()
			if victim.Parent and BattlegroundService.isIn(victim) and not MatchService.isInMatch(victim) then
				MatchService.respawnAt(victim, spawnCFrame(victim))
				markCharacter(victim)
			end
		end)
	end)
end

return BattlegroundService
