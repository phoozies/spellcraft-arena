--!strict
-- The dash: press Q (keyboard), B (gamepad), or the Dash button to burst
-- forward. This asks the server (Dash remote with the way you are heading); if
-- it allows the dash (DashService: alive, free to move, off cooldown) it
-- answers DashStarted with the direction and when the dash is ready again, and
-- this controller then drives the player's own character at Config.DASH.SPEED
-- for Config.DASH.DURATION seconds, popping it up Config.DASH.HOP so the dash
-- is a low leap. The button shows the cooldown. The dash animation, wind
-- streaks and puff are played for everyone by FxController ("dash").

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Responsive = require(script.Parent.Parent.UI.Responsive)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local DashController = {}

local KEY = Enum.KeyCode.Q
local PAD_KEY = Enum.KeyCode.ButtonB

local button: TextButton
local cooldownText: TextLabel
local readyAt = 0 -- server time the dash is ready again
local dashing = false

local function cooldownLeft(): number
	return math.max(0, readyAt - workspace:GetServerTimeNow())
end

-- The way the player is heading: their move direction, else where the camera
-- faces (flattened).
local function heading(): Vector3
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		return humanoid.MoveDirection.Unit
	end
	local camera = workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			return flat.Unit
		end
	end
	return Vector3.new(0, 0, -1)
end

local function request()
	if UserInputService:GetFocusedTextBox() or ClientState.capturingKey or dashing then
		return
	end
	if cooldownLeft() > 0 then
		return
	end
	Remotes.get("Dash"):FireServer(heading())
end

-- Moves the player's own character for the length of a dash.
local function go(direction: Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or dashing then
		return
	end
	dashing = true
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = math.huge
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Config.DASH.SPEED
	velocity.Parent = root
	-- Face the way you dash, and leave the ground in a low arc.
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	local launched = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(launched.X, Config.DASH.HOP, launched.Z)
	task.delay(Config.DASH.DURATION, function()
		velocity:Destroy()
		attachment:Destroy()
		dashing = false
	end)
end

local LABEL = "Dash"

-- On cooldown the button shows only the countdown (its own word is hidden).
local function refresh()
	local left = cooldownLeft()
	if left > 0 then
		cooldownText.Text = string.format("%.1f", left)
		cooldownText.Visible = true
		button.Text = ""
		button.BackgroundColor3 = Theme.COLORS.panel
	else
		cooldownText.Visible = false
		button.Text = LABEL
		button.BackgroundColor3 = Theme.COLORS.accent
	end
end

local function buildButton()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpellcraftDash"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	Responsive.bind(scale)
	-- Sits under the Draw button, bottom right.
	button = Theme.button(gui, LABEL, {
		Name = "Dash",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -226),
		Size = UDim2.fromOffset(120, 64),
		BackgroundColor3 = Theme.COLORS.accent,
	})
	Theme.label(button, "Q", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 2),
		Size = UDim2.fromOffset(22, 18),
		TextColor3 = Theme.COLORS.text,
		ZIndex = 5,
	})
	cooldownText = Theme.label(button, "", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6),
		ZIndex = 6,
		Visible = false,
	})
	button.Activated:Connect(request)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function DashController.init()
	buildButton()
end

function DashController.start()
	Remotes.get("DashStarted").OnClientEvent:Connect(function(endsAt: number, direction: Vector3)
		if typeof(endsAt) ~= "number" or typeof(direction) ~= "Vector3" then
			return
		end
		readyAt = endsAt
		go(direction)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == KEY then
			request()
		end
	end)
	ContextActionService:BindAction("SpellcraftDash", function(_, state)
		if state == Enum.UserInputState.Begin then
			request()
		end
		return Enum.ContextActionResult.Pass
	end, false, PAD_KEY)

	RunService.Heartbeat:Connect(refresh)
end

return DashController
