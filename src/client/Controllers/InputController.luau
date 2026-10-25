--!strict
-- Device-agnostic input. Every action has a binding per device:
--
--   Action        Keyboard/Mouse   Gamepad          Touch                 VR
--   Cast          Left click       R2               Tap the world         Right trigger
--   Ready slot    1-5              D-pad ←/→        Tap hotbar            D-pad / hotbar
--   Draw a spell  F (rebindable)   X (right stick)  ✏ Draw button, drag   F / X
--   Rotate        R                L1 / R1          ⟳ button              L1 / R1
--
-- Aim: mouse cursor (PC), screen center (gamepad), tap point (touch), or
-- the right controller's pointing ray (VR).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local ClientState = require(script.Parent.ClientState)
local DrawController = require(script.Parent.DrawController)
local HudController = require(script.Parent.HudController)
local MenuController = require(script.Parent.MenuController)
local PlacementController = require(script.Parent.PlacementController)
local ReticleController = require(script.Parent.ReticleController)

local player = Players.LocalPlayer

local InputController = {}

local AIM_DISTANCE = Config.AIM_RANGE + 50
local lastScreenPoint: Vector2? = nil

local function usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

local function aimRay(screenPoint: Vector2?): Ray?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	if VRService.VREnabled then
		local hand = UserInputService:GetUserCFrame(Enum.UserCFrame.RightHand)
		local world = camera.CFrame * hand
		return Ray.new(world.Position, world.LookVector)
	end
	local point = screenPoint
	if not point then
		if usingGamepad() then
			point = camera.ViewportSize / 2
		elseif UserInputService.MouseEnabled then
			point = UserInputService:GetMouseLocation()
		else
			point = lastScreenPoint or camera.ViewportSize / 2
		end
	end
	return camera:ViewportPointToRay(point.X, point.Y)
end

-- World point under the aim, ignoring our own character and the ghost.
function InputController.aimPoint(screenPoint: Vector2?): Vector3?
	local ray = aimRay(screenPoint)
	if not ray then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local ghost = PlacementController.getGhost()
	if ghost then
		table.insert(ignore, ghost)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin, ray.Direction.Unit * AIM_DISTANCE, params)
	if hit then
		return hit.Position
	end
	return ray.Origin + ray.Direction.Unit * AIM_DISTANCE
end

local function cast(screenPoint: Vector2?)
	if
		UserInputService:GetFocusedTextBox()
		or MenuController.isOpen()
		or DrawController.isActive()
	then
		return
	end
	local id = ClientState.readied
	local def = id and SpellDefinitions.get(id)
	if not def then
		HudController.toast("Draw a spell first!", "fizzle")
		return
	end
	if PlacementController.isActive() then
		local point, rotation, ok = PlacementController.getPlacement()
		if not point or not ok then
			HudController.toast("Can't place that there.", "fizzle")
			return
		end
		Remotes.get("CastSpell"):FireServer(point, rotation)
		return
	end
	-- Point-and-click spells (Fire Pillar, Earth Punch, ...) land on the reticle's clamped point.
	local target = if ReticleController.isActive() and not screenPoint
		then ReticleController.getTarget()
		else InputController.aimPoint(screenPoint)
	if target then
		Remotes.get("CastSpell"):FireServer(target)
	end
end

local function cycleSlot(direction: number)
	local hand = ClientState.hand
	if #hand == 0 then
		return
	end
	local index = ClientState.readiedSlot or 1
	index = ((index - 1 + direction) % #hand) + 1
	Remotes.get("SelectSlot"):FireServer(index)
end

local SLOT_KEYS =
	{ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

function InputController.start()
	PlacementController.setAimProvider(function()
		return InputController.aimPoint(nil), nil
	end)
	ReticleController.setAimProvider(function()
		return InputController.aimPoint(nil)
	end)

	-- Mouse clicks go through UserInputService so clicks on GUI are ignored.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or ClientState.capturingKey then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			cast(nil)
		elseif input.KeyCode == Enum.KeyCode.R then
			PlacementController.rotate(math.pi / 4)
		else
			for slot, key in SLOT_KEYS do
				if input.KeyCode == key then
					Remotes.get("SelectSlot"):FireServer(slot)
				end
			end
		end
	end)

	UserInputService.TouchTapInWorld:Connect(function(position, processedByUI)
		if not processedByUI then
			lastScreenPoint = position
			cast(position)
		end
	end)

	ContextActionService:BindAction("SpellcraftCast", function(_, state)
		if state == Enum.UserInputState.Begin then
			cast(nil)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonR2)

	ContextActionService:BindAction("SpellcraftSlot", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			cycleSlot(if input.KeyCode == Enum.KeyCode.DPadLeft then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)

	ContextActionService:BindAction("SpellcraftRotate", function(_, state, input)
		if state == Enum.UserInputState.Begin and PlacementController.isActive() then
			PlacementController.rotate(
				if input.KeyCode == Enum.KeyCode.ButtonL1 then -math.pi / 4 else math.pi / 4
			)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
end

return InputController
