--!strict
-- Device-agnostic input. Every action has a binding per device:
--
--   Action        Keyboard/Mouse   Gamepad          Touch                 VR
--   Spell guide   1-5 (loadout     D-pad ←/→        Tap a spell card      D-pad / cards
--                 order)
--   Draw a spell  F (rebindable)   X (right stick)  Draw button, drag   F / X
--   Rotate        R                L1 / R1          ⟳ button              L1 / R1
--
--   Menu          M                n/a              Side buttons          n/a
--
-- There is no cast button: finishing a shape casts its spell (DrawController
-- sends aimPoint with the stroke). First person, so every device aims from the
-- middle of the screen (the sight) and players never aim with the cursor; VR
-- uses the right controller's pointing ray. The server decides the rest
-- (CastService).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

local Config = require(ReplicatedStorage.Shared.Config)
local ClientState = require(script.Parent.ClientState)
local DrawController = require(script.Parent.DrawController)
local MenuController = require(script.Parent.MenuController)
local PlacementController = require(script.Parent.PlacementController)
local ReticleController = require(script.Parent.ReticleController)

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

-- World point under the sight. A placeable's ghost looks through characters,
-- as the server does; everything else stops on them.
function InputController.aimPoint(throughCharacters: boolean?): Vector3?
	local ray = aimRay()
	if not ray then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character and (throughCharacters or other == Players.LocalPlayer) then
			table.insert(ignore, other.Character)
		end
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

-- D-pad: open the guide of the next (or previous) spell.
local function cycleSpell(direction: number)
	local spells = ClientState.drawableSpells()
	if #spells == 0 then
		return
	end
	local index = (ClientState.aiming and table.find(spells, ClientState.aiming))
		or (if direction > 0 then 0 else 1)
	ClientState.DrawRequested:Fire(spells[((index - 1 + direction) % #spells) + 1])
end

local SLOT_KEYS =
	{ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

-- Key N is the Nth spell of the loadout (the Nth spell card): the canvas opens
-- with its shape to trace, and the key again closes it.
local function pressSpellKey(number: number)
	if UserInputService:GetFocusedTextBox() or MenuController.isOpen() then
		return
	end
	local spellId = ClientState.drawableSpells()[number]
	if spellId then
		ClientState.DrawRequested:Fire(spellId)
	end
end

function InputController.start()
	DrawController.setAimProvider(function()
		return InputController.aimPoint(), PlacementController.getRotation()
	end)
	PlacementController.setAimProvider(function()
		return InputController.aimPoint(true), nil
	end)
	ReticleController.setAimProvider(function()
		return InputController.aimPoint()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or ClientState.capturingKey then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			PlacementController.rotate(math.pi / 4)
		elseif input.KeyCode == Enum.KeyCode.M then
			if not DrawController.isActive() then
				-- In a match only Settings is available.
				MenuController.toggle(
					if ClientState.match.phase == "Idle" then "Play" else "Settings"
				)
			end
		else
			for number, key in SLOT_KEYS do
				if input.KeyCode == key then
					pressSpellKey(number)
				end
			end
		end
	end)

	ContextActionService:BindAction("SpellcraftSpellGuide", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			cycleSpell(if input.KeyCode == Enum.KeyCode.DPadLeft then -1 else 1)
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
