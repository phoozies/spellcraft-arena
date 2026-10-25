--!strict
-- The Battleground: a drop-in free-for-all arena (Maps/Battleground) far from
-- the hub. Step into the hub's Battleground portal to be teleported there;
-- step on a green exit pad to go back.
--
--   * Anyone inside can hurt anyone else inside (MatchService.relation reads
--     the player attribute "InBattleground"); nobody outside can hurt them.
--   * When you're knocked out you respawn at a random spawn after a few
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
local PlayerDataService = require(script.Parent.PlayerDataService)

local buildBattleground = require(script.Parent.Parent:WaitForChild("Maps"):WaitForChild("Battleground")) :: any

local BattlegroundService = {}

local TOUCH_COOLDOWN = 2

local toastRemote: RemoteEvent
local spawns: { BasePart } = {}
local lastTouch: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

function BattlegroundService.isIn(player: Player): boolean
	return player:GetAttribute("InBattleground") == true
end

-- Picks a spawn, preferring one away from the other fighters.
local function spawnCFrame(): CFrame
	if #spawns == 0 then
		return CFrame.new(Config.BATTLEGROUND.CENTER + Vector3.new(0, 5, 0))
	end
	local others: { Vector3 } = {}
	for _, other in Players:GetPlayers() do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and BattlegroundService.isIn(other) then
			table.insert(others, root.Position)
		end
	end
	local best: BasePart = spawns[math.random(1, #spawns)]
	local bestDistance = -1
	for _ = 1, 5 do
		local candidate = spawns[math.random(1, #spawns)]
		local nearest = math.huge
		for _, position in others do
			nearest = math.min(nearest, (position - candidate.Position).Magnitude)
		end
		if nearest > bestDistance then
			best, bestDistance = candidate, nearest
		end
	end
	return best.CFrame + Vector3.new(0, 3, 0)
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
	MatchService.teleport(player, spawnCFrame())
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
	local map = buildBattleground(Config.BATTLEGROUND.CENTER) :: Model
	map.Parent = workspace
	for _, part in map:GetDescendants() do
		if part:IsA("BasePart") and part:HasTag("BattlegroundSpawn") then
			table.insert(spawns, part)
		end
	end
end

function BattlegroundService.start()
	wire("BattlegroundPortal", function(player)
		local ok, reason = BattlegroundService.enter(player)
		if not ok and reason then
			toastRemote:FireClient(player, reason, "fizzle")
		end
	end)
	wire("BattlegroundExit", function(player)
		BattlegroundService.leave(player)
	end)

	-- Knocked out in the battleground: back in after a short wait.
	DestructibleService.Knockout:Connect(function(victim)
		if not BattlegroundService.isIn(victim) then
			return
		end
		task.delay(Config.BATTLEGROUND.RESPAWN_DELAY, function()
			if victim.Parent and BattlegroundService.isIn(victim) and not MatchService.isInMatch(victim) then
				MatchService.respawnAt(victim, spawnCFrame())
				markCharacter(victim)
			end
		end)
	end)
end

return BattlegroundService
