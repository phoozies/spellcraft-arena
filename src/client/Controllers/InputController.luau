--!strict
-- Device-agnostic input. Every action has a binding per device:
--
--   Action        Keyboard/Mouse   Gamepad          Touch                 VR
--   Cast          Left click       R2               Tap the world         Right trigger
--   Spell 1-5     1-5 (loadout     D-pad ←/→        Tap hotbar            D-pad / hotbar
--                 order; draws it
--                 if you hold none)
--   Draw a spell  F (rebindable)   X (right stick)  Draw button, drag   F / X
--   Rotate        R                L1 / R1          ⟳ button              L1 / R1
--
-- Aim: first person, so every device aims from the middle of the screen (the
-- crosshair) and players never aim with the mouse; VR uses the right
-- controller's pointing ray. The server adds the auto-aim lock (CastService).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local MouseLock = require(script.Parent.Parent.UI.MouseLock)
local ClientState = require(script.Parent.ClientState)
local DrawController = require(script.Parent.DrawController)
local HudController = require(script.Parent.HudController)
local LockOnController = require(script.Parent.LockOnController)
local MenuController = require(script.Parent.MenuController)
local PlacementController = require(script.Parent.PlacementController)
local ReticleController = require(script.Parent.ReticleController)

local player = Players.LocalPlayer

local InputController = {}

local AIM_DISTANCE = Config.AIM_RANGE + 50

-- The crosshair's ray: straight out of the camera (the screen's centre).
local function aimRay(): Ray?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	if VRService.VREnabled then
		local hand = UserInputService:GetUserCFrame(Enum.UserCFrame.RightHand)
		local world = camera.CFrame * hand
		return Ray.new(world.Position, world.LookVector)
	end
	return Ray.new(camera.CFrame.Position, camera.CFrame.LookVector)
end

-- World point under the crosshair, ignoring our own character and the ghost.
function InputController.aimPoint(): Vector3?
	local ray = aimRay()
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

local function cast()
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
		HudController.toast("Draw a spell first!", "error")
		return
	end
	if PlacementController.isActive() then
		local point, rotation, ok = PlacementController.getPlacement()
		if not point or not ok then
			HudController.toast("Can't place that there.", "error")
			return
		end
		Remotes.get("CastSpell"):FireServer(point, rotation)
		return
	end
	-- Ground strikes (Fire Pillar, Earth Punch, ...) land on the reticle's
	-- clamped point; everything else goes where the crosshair points.
	local target = if ReticleController.isActive()
		then ReticleController.getTarget()
		else InputController.aimPoint()
	if target then
		Remotes.get("CastSpell"):FireServer(target)
	end
end

local function cycleSlot(direction: number)
	local hand = ClientState.hand
	local index = ClientState.readiedSlot or 0
	-- The next held copy in that direction (empty slots are skipped).
	for _ = 1, #hand do
		index = ((index - 1 + direction) % #hand) + 1
		if hand[index] ~= "" then
			Remotes.get("SelectSlot"):FireServer(index)
			return
		end
	end
end

local SLOT_KEYS =
	{ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

-- Key N is hotbar slot N, which belongs to the Nth spell of the loadout (the
-- glyph cards above the hotbar). Holding a copy of it readies that copy;
-- otherwise the canvas opens with the spell's shape to trace.
local function pressSpellKey(number: number)
	if UserInputService:GetFocusedTextBox() or MenuController.isOpen() then
		return
	end
	local spellId = ClientState.drawableSpells()[number]
	if not spellId then
		return
	end
	if (ClientState.hand[number] or "") ~= "" then
		if not DrawController.isActive() then
			Remotes.get("SelectSlot"):FireServer(number)
		end
	else
		ClientState.DrawRequested:Fire(spellId)
	end
end

function InputController.start()
	PlacementController.setAimProvider(function()
		return InputController.aimPoint(), nil
	end)
	-- A ground strike snaps onto the auto-aim lock (LockOnController), the
	-- same opponent the server will aim it at.
	ReticleController.setAimProvider(function()
		local lock = LockOnController.getLock()
		local root = lock and (lock:FindFirstChild("HumanoidRootPart") or lock.PrimaryPart)
		if root and root:IsA("BasePart") then
			return root.Position
		end
		return InputController.aimPoint()
	end)

	-- Mouse clicks go through UserInputService so clicks on GUI are ignored.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or ClientState.capturingKey then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- A free mouse (menus, Left Alt) clicks UI, never casts.
			if not MouseLock.isFree() then
				cast()
			end
		elseif input.KeyCode == Enum.KeyCode.R then
			PlacementController.rotate(math.pi / 4)
		else
			for number, key in SLOT_KEYS do
				if input.KeyCode == key then
					pressSpellKey(number)
				end
			end
		end
	end)

	-- A tap anywhere in the world casts at the crosshair (not at the tap).
	UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
		if not processedByUI then
			cast()
		end
	end)

	ContextActionService:BindAction("SpellcraftCast", function(_, state)
		if state == Enum.UserInputState.Begin then
			cast()
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
