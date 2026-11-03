--!strict
-- First person, everywhere (Config.AUTO_AIM): the camera is locked in first
-- person with a wider field of view, so the crosshair is always the middle of
-- the screen and spells fly where you look (InputController aims from the
-- screen centre; CastService adds the auto-aim lock).
--
-- Each frame, after Roblox's camera has run:
--   * the mouse is let go while the drawing canvas is open or Left Alt is held
--     (UI/MouseLock; open windows free it themselves through whileVisible), so
--     shapes can be traced and buttons clicked;
--   * your right arm and wand stay visible (first person hides your own body),
--     so you see the wand raise and the magic circle open when you draw.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MouseLock = require(script.Parent.Parent.UI.MouseLock)
local DrawController = require(script.Parent.DrawController)

local player = Players.LocalPlayer

local CameraController = {}

-- The body parts kept visible in first person (R15 and R6 names).
local VIEW_PARTS = { "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" }

local function showViewParts(character: Model)
	for _, name in VIEW_PARTS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.LocalTransparencyModifier = 0
		end
	end
	local wand = character:FindFirstChild(Config.WAND.MODEL)
	if wand then
		for _, part in wand:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
			end
		end
	end
end

local function step()
	MouseLock.set("draw", DrawController.isActive())
	MouseLock.set("alt", UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt))
	local character = player.Character
	if character then
		showViewParts(character)
	end
end

local function applyCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = Config.AUTO_AIM.FOV
	end
end

function CameraController.init()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
end

function CameraController.start()
	applyCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyCamera)
	RunService:BindToRenderStep("SpellcraftFirstPerson", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
