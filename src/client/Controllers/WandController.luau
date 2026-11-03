--!strict
-- The wand on every character, client side.
--   * Anyone whose "Drawing" attribute is set (WandService, from that player's
--     DrawingState) raises their wand (CastPoses WandDraw, held), and its tip
--     glows over a turning rune circle (WandVfx.charge).
--   * Your own stroke is written in the air in front of you as you draw
--     (DrawController calls strokeBegin / strokePoint / strokeSent /
--     strokeCancel / verdict); the server's verdict flashes it and pulls it into
--     the wand, or crumbles it.
--   * Other players' drawings arrive as Fx "glyph" (FxController -> onGlyph):
--     their wand traces the clean glyph in the air, then absorbs it.
--
-- Display only: the server recognizes drawings and owns the wand itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local WandAir = require(ReplicatedStorage.Shared.Util.WandAir)
local CastAnimations = require(script.Parent.Parent.Fx.CastAnimations)
local WandVfx = require(script.Parent.Parent.Fx.WandVfx)
local AudioController = require(script.Parent.AudioController)

local player = Players.LocalPlayer

local WandController = {}

-- Seconds WandDraw is held at most (it is stopped as soon as drawing ends).
local DRAW_HOLD = 60
-- Wand effects for characters farther than this from the camera are skipped.
local NEAR = 250
-- How long a sent stroke waits for the server's verdict.
local VERDICT_TIMEOUT = 1.5

local folder: Folder
local charging: { [Model]: () -> () } = setmetatable({}, { __mode = "k" }) :: any
local ribbon: WandVfx.Ribbon? = nil -- your stroke while you draw it
local pending: WandVfx.Ribbon? = nil -- your stroke sent to the server
local canvas: CFrame? = nil

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isNear(character: Model): boolean
	local root = rootOf(character)
	local camera = workspace.CurrentCamera
	return root ~= nil
		and camera ~= nil
		and (root.Position - camera.CFrame.Position).Magnitude <= NEAR
end

local function setCharging(character: Model, on: boolean)
	local stop = charging[character]
	if on and not stop then
		CastAnimations.play(character, "WandDraw", DRAW_HOLD)
		if isNear(character) then
			charging[character] = WandVfx.charge(folder, character, WandVfx.colorOf(character))
			local root = rootOf(character)
			AudioController.play("wandCharge", if root then root.Position else nil)
		else
			charging[character] = function() end
		end
	elseif not on and stop then
		charging[character] = nil
		stop()
		CastAnimations.stop(character, "WandDraw")
	end
end

local function watchCharacter(character: Model)
	local function refresh()
		setCharging(
			character,
			character.Parent ~= nil and character:GetAttribute("Drawing") == true
		)
	end
	character:GetAttributeChangedSignal("Drawing"):Connect(refresh)
	character.AncestryChanged:Connect(refresh)
	refresh()
end

local function watchPlayer(other: Player)
	other.CharacterAdded:Connect(watchCharacter)
	if other.Character then
		watchCharacter(other.Character)
	end
end

-- Your drawing starts: a fresh ribbon on an air canvas facing your camera.
function WandController.strokeBegin(color: Color3)
	if ribbon then
		ribbon:cancel()
		ribbon = nil
	end
	local character = player.Character
	local root = character and rootOf(character)
	local camera = workspace.CurrentCamera
	if not character or not root or not camera then
		return
	end
	local view = camera.CFrame
	canvas = WandAir.frame(root.Position, view.LookVector, view.RightVector, view.UpVector)
	ribbon = WandVfx.ribbon(folder, character, canvas :: CFrame, color)
end

-- A point of your stroke, in screen pixels.
function WandController.strokePoint(screen: Vector2)
	local camera = workspace.CurrentCamera
	if ribbon and camera then
		ribbon:add(WandAir.fromScreen(screen, camera.ViewportSize))
	end
end

-- Your stroke went to the server: keep it in the air until the verdict.
function WandController.strokeSent()
	if pending then
		pending:cancel()
	end
	local sent = ribbon
	pending = sent
	ribbon = nil
	if sent then
		task.delay(VERDICT_TIMEOUT, function()
			if pending == sent then
				pending = nil
				sent:cancel()
			end
		end)
	end
end

-- Your stroke was thrown away before it was sent (too small, cancelled).
function WandController.strokeCancel()
	if ribbon then
		ribbon:cancel()
		ribbon = nil
	end
end

-- The server's verdict on your last stroke.
function WandController.verdict(ok: boolean, color: Color3?)
	local sent = pending
	pending = nil
	if sent then
		sent:finish(ok, color)
	end
	local character = player.Character
	if ok and character then
		CastAnimations.play(character, "WandFlick")
	end
end

-- Fx "glyph": somebody drew a spell. Your own is already in the air.
function WandController.onGlyph(character: Model, glyphId: string, color: Color3, quality: number?)
	if
		typeof(character) ~= "Instance"
		or character == player.Character
		or not isNear(character)
	then
		return
	end
	WandVfx.airGlyph(folder, character, glyphId, color, quality)
	task.delay(Config.WAND.TRACE_SECONDS, function()
		if character.Parent then
			CastAnimations.play(character, "WandFlick")
			local root = rootOf(character)
			AudioController.play("wandAbsorb", if root then root.Position else nil)
		end
	end)
end

-- Tells the server whether your canvas is open (everyone sees the wand raised).
function WandController.setDrawing(on: boolean)
	Remotes.get("DrawingState"):FireServer(on)
end

function WandController.init()
	folder = Instance.new("Folder")
	folder.Name = "SpellcraftWandFx"
	folder.Parent = workspace
end

function WandController.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
end

return WandController
