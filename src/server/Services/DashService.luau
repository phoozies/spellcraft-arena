--!strict
-- The dash: a quick burst forward on a key (Q) or the Dash button. The client
-- only says which way it is heading (Dash remote); the server decides whether a
-- dash is allowed (alive, free to move, off cooldown), starts the cooldown, tells
-- the dasher to go that way (DashStarted, with the cooldown's end) and tells
-- everyone nearby to play the dash animation and puff (Fx "dash"). The dasher's
-- own client moves its character (DashController), so nothing here teleports or
-- pushes anyone, and a dash never hurts.
--
-- Config.DASH: COOLDOWN, SPEED, DURATION.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local StatusService = require(script.Parent.StatusService)

local DashService = {}

-- Statuses that stop you from moving or acting.
local BLOCKING = { "Stun", "Root", "TimeStop", "Channel" }

local readyAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

-- A flat unit direction from untrusted input, or the way the character faces.
local function flatDirection(raw: any, root: BasePart): Vector3
	if typeof(raw) == "Vector3" and raw.X == raw.X and raw.Z == raw.Z then
		local flat = Vector3.new(raw.X, 0, raw.Z)
		if flat.Magnitude > 0.1 then
			return flat.Unit
		end
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

-- Tries to dash. Returns true when the dash started.
function DashService.dash(player: Player, direction: any): boolean
	local now = os.clock()
	if now < (readyAt[player] or 0) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if not root or not root:IsA("BasePart") or root.Anchored then
		return false -- frozen (countdowns, intros)
	end
	for _, kind in BLOCKING do
		if StatusService.has(character, kind) then
			return false
		end
	end
	local heading = flatDirection(direction, root)
	readyAt[player] = now + Config.DASH.COOLDOWN
	Remotes.get("DashStarted")
		:FireClient(player, workspace:GetServerTimeNow() + Config.DASH.COOLDOWN, heading)
	Remotes.get("Fx"):FireAllClients("dash", character, heading)
	return true
end

function DashService.start()
	Remotes.get("Dash").OnServerEvent:Connect(function(player, direction)
		DashService.dash(player, direction)
	end)
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
	end)
end

return DashService
