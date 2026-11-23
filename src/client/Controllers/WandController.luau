--!strict
-- The wand on every character, client side.
--   * Anyone whose "Drawing" attribute is set (WandService, from that player's
--     DrawingState) raises their wand (CastPoses WandDraw, held): its tip
--     glows, a rune circle turns at their feet, and a magic circle opens in
--     the air in front of them, facing their "DrawLook" (WandVfx.charge).
--   * Your own stroke is written in the air on that circle as you draw
--     (DrawController calls strokeBegin / strokePoint / strokeSent /
--     strokeCancel / verdict) and streamed to the server in small batches
--     (AirStroke), which relays it to the players near you. Your own circle and
--     ribbon are for them: on your screen they'd only cover what you are aiming
--     at, and the canvas already shows your line. You see your wand instead,
--     held in first person with its tip writing under your pen (Fx/WandView).
--   * Other players' live strokes arrive the same way (AirStroke): everyone
--     watches the shape being drawn on the drawer's circle. The Fx "glyph"
--     (FxController -> onGlyph) flashes it in its quality colour and pulls it
--     into the wand; "glyphFail" crumbles it. A glyph from someone whose
--     stroke you didn't see (you came close later) is traced cleanly instead.
--   * A circle stays open until its drawing's verdict, then closes.
--
-- Display only: the server recognizes drawings and owns the wand itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Quality = require(ReplicatedStorage.Shared.Spells.Quality)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local WandAir = require(ReplicatedStorage.Shared.Util.WandAir)
local CastAnimations = require(script.Parent.Parent.Fx.CastAnimations)
local WandVfx = require(script.Parent.Parent.Fx.WandVfx)
local WandView = require(script.Parent.Parent.Fx.WandView)
local AudioController = require(script.Parent.AudioController)

local player = Players.LocalPlayer

local WandController = {}

local unseen: Folder

-- Seconds WandDraw is held at most (it is stopped as soon as drawing ends).
local DRAW_HOLD = 60
-- Wand effects for characters farther than this from the camera are skipped.
local NEAR = 250
-- How long a sent stroke waits for the server's verdict.
local VERDICT_TIMEOUT = 1.5
-- How long a circle stays open after its drawing's verdict.
local LINGER = 0.55

type Live = { ribbon: WandVfx.Ribbon, ended: boolean }

local folder: Folder
local airRemote: RemoteEvent
local charging: { [Model]: WandVfx.Charge } = setmetatable({}, { __mode = "k" }) :: any
local live: { [Model]: Live } = setmetatable({}, { __mode = "k" }) :: any
local ribbon: WandVfx.Ribbon? = nil -- your stroke while you draw it
local pending: WandVfx.Ribbon? = nil -- your stroke sent to the server
local drawingOn = false -- your canvas is open
local myLook: Vector3? = nil -- the way you faced when it opened
local outbox: { Vector2 } = {} -- stroke points not yet sent
local sentCount = 0
local lastSend = 0

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

-- The way a character's circle faces: yours from your camera, others' from
-- their DrawLook attribute.
local function lookOf(character: Model): Vector3?
	if character == player.Character then
		return myLook
	end
	return WandVfx.lookOf(character)
end

-- True while a character's drawing is still waiting to land or crumble, so its
-- circle stays open after the canvas closes.
local function awaiting(character: Model): boolean
	if character == player.Character then
		return pending ~= nil
	end
	return live[character] ~= nil
end

local function shouldCharge(character: Model): boolean
	if character.Parent == nil then
		return false
	end
	if character == player.Character then
		return drawingOn
	end
	return character:GetAttribute("Drawing") == true
end

local function setCharging(character: Model, on: boolean)
	local handle = charging[character]
	if on and not handle then
		CastAnimations.play(character, "WandDraw", DRAW_HOLD)
		if isNear(character) and character ~= player.Character then
			charging[character] = WandVfx.charge(
				folder,
				character,
				WandVfx.colorOf(character),
				function()
					return lookOf(character)
				end
			)
			local root = rootOf(character)
			AudioController.play("wandCharge", if root then root.Position else nil)
		elseif character == player.Character then
			WandView.show(character, WandVfx.colorOf(character))
			charging[character] = { stop = WandView.hide, flash = function(_: Color3) end }
		else
			charging[character] = { stop = function() end, flash = function(_: Color3) end }
		end
	elseif not on and handle and (character.Parent == nil or not awaiting(character)) then
		charging[character] = nil
		handle.stop()
		CastAnimations.stop(character, "WandDraw")
	end
end

local function refresh(character: Model)
	setCharging(character, shouldCharge(character))
end

-- Closes a character's circle a moment after its drawing's verdict (unless
-- they opened the canvas again).
local function closeLater(character: Model)
	task.delay(LINGER, refresh, character)
end

local function watchCharacter(character: Model)
	local function changed()
		refresh(character)
	end
	character:GetAttributeChangedSignal("Drawing"):Connect(changed)
	character.AncestryChanged:Connect(changed)
	changed()
end

local function watchPlayer(other: Player)
	other.CharacterAdded:Connect(watchCharacter)
	if other.Character then
		watchCharacter(other.Character)
	end
end

-- Sends the points drawn since the last batch (at most one batch a call).
local function flush()
	if #outbox == 0 then
		return
	end
	local batch: { Vector2 } = {}
	local room = math.min(Config.WAND.STROKE_BATCH, Config.WAND.STROKE_MAX_POINTS - sentCount)
	for i = 1, math.min(room, #outbox) do
		batch[i] = outbox[i]
	end
	table.clear(outbox)
	if #batch > 0 then
		sentCount += #batch
		lastSend = os.clock()
		airRemote:FireServer("points", batch)
	end
end

-- Your drawing starts: a fresh ribbon on your magic circle.
function WandController.strokeBegin(color: Color3)
	WandView.penDown(color)
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
	local frame = WandAir.facing(root.Position, myLook or camera.CFrame.LookVector)
	ribbon = WandVfx.ribbon(unseen, character, frame, color)
	table.clear(outbox)
	sentCount = 0
	airRemote:FireServer("begin", color)
end

-- A point of your stroke, in screen pixels.
function WandController.strokePoint(screen: Vector2)
	WandView.point(screen)
	local camera = workspace.CurrentCamera
	if not ribbon or not camera then
		return
	end
	local offset = WandAir.fromScreen(screen, camera.ViewportSize)
	if ribbon:add(offset) and #outbox < Config.WAND.STROKE_BATCH then
		table.insert(outbox, offset)
	end
end

-- Your stroke is about to go to the server: send the rest of it, and keep it
-- in the air until the verdict.
function WandController.strokeSent()
	WandView.penUp()
	if pending then
		pending:cancel()
	end
	local sent = ribbon
	pending = sent
	ribbon = nil
	if not sent then
		return
	end
	flush()
	airRemote:FireServer("end")
	task.delay(VERDICT_TIMEOUT, function()
		if pending == sent then
			pending = nil
			sent:cancel()
			local character = player.Character
			if character then
				refresh(character)
			end
		end
	end)
end

-- Your stroke was thrown away before it was sent (too small, cancelled).
function WandController.strokeCancel()
	WandView.penUp()
	if ribbon then
		ribbon:cancel()
		ribbon = nil
		table.clear(outbox)
		airRemote:FireServer("cancel")
	end
end

-- The server's verdict on your last stroke.
function WandController.verdict(ok: boolean, color: Color3?)
	local sent = pending
	pending = nil
	if sent then
		sent:finish(ok, color)
	end
	WandView.flick(ok, color)
	local character = player.Character
	if not character then
		return
	end
	if ok then
		CastAnimations.play(character, "WandFlick")
		local handle = charging[character]
		if handle and color then
			handle.flash(color)
		end
	end
	closeLater(character)
end

-- AirStroke from the server: a piece of another player's live stroke.
local function onAirStroke(character: any, kind: any, data: any)
	if
		typeof(character) ~= "Instance"
		or not character:IsA("Model")
		or character == player.Character
	then
		return
	end
	local model = character :: Model
	local entry = live[model]
	if kind == "begin" then
		if entry then
			entry.ribbon:cancel()
			live[model] = nil
		end
		local root = rootOf(model)
		if not root or not isNear(model) then
			return
		end
		local frame = WandAir.facing(root.Position, WandVfx.lookOf(model) or root.CFrame.LookVector)
		local color = if typeof(data) == "Color3" then data else WandVfx.colorOf(model)
		live[model] = { ribbon = WandVfx.ribbon(folder, model, frame, color), ended = false }
	elseif not entry then
		return
	elseif kind == "points" and typeof(data) == "table" then
		for _, point in data do
			if typeof(point) == "Vector2" then
				entry.ribbon:add(point)
			end
		end
	elseif kind == "end" then
		-- Sent to be recognized: wait for its glyph / glyphFail.
		entry.ended = true
		task.delay(VERDICT_TIMEOUT, function()
			if live[model] == entry then
				live[model] = nil
				entry.ribbon:finish(false)
				refresh(model)
			end
		end)
	elseif kind == "cancel" then
		live[model] = nil
		entry.ribbon:cancel()
		refresh(model)
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
	local finalColor = if quality then Quality.tier(quality).color else color
	local entry = live[character]
	local delay = 0
	if entry then
		-- You watched it being drawn: that stroke lands.
		live[character] = nil
		entry.ribbon:finish(true, finalColor)
	else
		WandVfx.airGlyph(folder, character, glyphId, color, quality)
		delay = Config.WAND.TRACE_SECONDS
	end
	local handle = charging[character]
	if handle then
		handle.flash(finalColor)
	end
	task.delay(delay, function()
		if character.Parent then
			CastAnimations.play(character, "WandFlick")
			local root = rootOf(character)
			AudioController.play("wandAbsorb", if root then root.Position else nil)
		end
	end)
	closeLater(character)
end

-- Fx "glyphFail": somebody's drawing fizzled.
function WandController.onGlyphFail(character: Model)
	if typeof(character) ~= "Instance" or character == player.Character then
		return
	end
	local entry = live[character]
	if entry then
		live[character] = nil
		entry.ribbon:finish(false)
	end
	closeLater(character)
end

-- Tells the server whether your canvas is open (everyone sees the wand raised
-- and your magic circle), and opens or closes your own circle right away.
function WandController.setDrawing(on: boolean)
	drawingOn = on
	local camera = workspace.CurrentCamera
	if on and camera then
		local look = camera.CFrame.LookVector
		myLook = WandAir.cleanLook(look)
	end
	Remotes.get("DrawingState"):FireServer(on, myLook)
	local character = player.Character
	if character then
		refresh(character)
	end
end

function WandController.init()
	-- Never parented: your own ribbon still runs here, but isn't rendered.
	unseen = Instance.new("Folder")
	folder = Instance.new("Folder")
	folder.Name = "SpellcraftWandFx"
	folder.Parent = workspace
end

function WandController.start()
	airRemote = Remotes.get("AirStroke")
	airRemote.OnClientEvent:Connect(onAirStroke)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	-- Your stroke goes out in small batches while you draw.
	RunService.Heartbeat:Connect(function()
		if ribbon and os.clock() - lastSend >= Config.WAND.STROKE_SEND_RATE then
			flush()
		end
	end)
end

return WandController
