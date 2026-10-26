--!strict
-- Client-side effects the server delegates: self-beneficial boosts (dash,
-- balloon, jump/bounce pads) on our own character, slippery friction, and
-- team outlines (allies blue, enemies red) during matches. Hostile
-- knockback is applied by the server (DestructibleService.push), not here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local EffectsController = {}

local MAX_IMPULSE = 250
-- Longest an impulse may keep steering, in seconds.
local MAX_HOLD = 3
local SLIPPERY = PhysicalProperties.new(0.7, 0, 0, 100, 1)

local steering: RBXScriptConnection? = nil

-- `hold` (seconds, optional) makes the impulse an arc: for that long the
-- character's velocity follows the launch velocity under gravity exactly, so the
-- humanoid's air control and its fall speed can't bend the flight (rescue arcs).
-- Without it the impulse is a single push (dash, jump pads).
local function applyImpulse(velocity: Vector3, hold: number?)
	if typeof(velocity) ~= "Vector3" or velocity.Magnitude ~= velocity.Magnitude then
		return
	end
	if velocity.Magnitude > MAX_IMPULSE then
		velocity = velocity.Unit * MAX_IMPULSE
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or root.Anchored then
		return
	end
	if velocity.Y > 20 then
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	if steering then
		steering:Disconnect()
		steering = nil
	end
	if typeof(hold) == "number" and hold > 0 and hold == hold then
		local start = os.clock()
		local duration = math.min(hold, MAX_HOLD)
		root.AssemblyLinearVelocity = velocity
		steering = RunService.Heartbeat:Connect(function()
			local elapsed = os.clock() - start
			if elapsed > duration or not root.Parent or root.Anchored then
				if steering then
					steering:Disconnect()
					steering = nil
				end
				return
			end
			root.AssemblyLinearVelocity = velocity - Vector3.new(0, workspace.Gravity * elapsed, 0)
		end)
		return
	end
	root.AssemblyLinearVelocity = root.AssemblyLinearVelocity * 0.25 + velocity
end

local function watchSlippery(character: Model)
	character:GetAttributeChangedSignal("Status_Slippery"):Connect(function()
		local slippery = character:GetAttribute("Status_Slippery") == true
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.CustomPhysicalProperties = if slippery then SLIPPERY else nil
			end
		end
	end)
end

local function updateOutlines()
	local myTeam = ClientState.match.myTeamId
	local inMatch = ClientState.match.phase ~= "Idle"
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and other ~= player then
			local existing = character:FindFirstChild("TeamOutline") :: Highlight?
			local team = character:GetAttribute("Team")
			if inMatch and typeof(team) == "string" then
				local h = existing or Instance.new("Highlight")
				h.Name = "TeamOutline"
				h.FillTransparency = 1
				h.OutlineColor = if team == myTeam then Theme.COLORS.blue else Theme.COLORS.red
				h.DepthMode = Enum.HighlightDepthMode.Occluded
				h.Parent = character
			elseif existing then
				existing:Destroy()
			end
		end
	end
end

-- The server moves new characters to their spawn right after loading them,
-- so snap the camera behind the character once it lands there.
local function resetCamera(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return
	end
	task.wait(0.2)
	camera.CFrame = CFrame.lookAt(
		root.Position - root.CFrame.LookVector * 14 + Vector3.new(0, 6, 0),
		root.Position
	)
end

function EffectsController.start()
	Remotes.get("Impulse").OnClientEvent:Connect(applyImpulse)
	player.CharacterAdded:Connect(resetCamera)
	player.CharacterAdded:Connect(watchSlippery)
	if player.Character then
		watchSlippery(player.Character)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.5 then
			elapsed = 0
			updateOutlines()
		end
	end)
end

return EffectsController
