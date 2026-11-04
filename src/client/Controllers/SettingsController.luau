--!strict
-- Settings panel: the camera speed, the key that opens the drawing canvas (click
-- "Change", press any key, done), and the background music, the sound effects
-- and the screen shake on or off.
-- Both choices are saved to the player's profile; the server validates them
-- (and refuses reserved keys like WASD, Space, the spell keys 1-5, and "/"
-- which Roblox chat uses).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local HudController = require(script.Parent.HudController)
local MenuController = require(script.Parent.MenuController)

local SettingsController = {}

local keyLabel: TextLabel
local changeButton: TextButton
local hint: TextLabel
local musicButton: TextButton
local sfxButton: TextButton
local shakeButton: TextButton
local cameraLabel: TextLabel

local function cameraSpeed(): number
	local profile = ClientState.profile
	return (profile and profile.settings and profile.settings.camera) or Config.CAMERA.SENSITIVITY
end

local function musicOn(): boolean
	local profile = ClientState.profile
	return not (profile and profile.settings and profile.settings.music == false)
end

local function sfxOn(): boolean
	local profile = ClientState.profile
	return not (profile and profile.settings and profile.settings.sfx == false)
end

local function shakeOn(): boolean
	local profile = ClientState.profile
	return not (profile and profile.settings and profile.settings.shake == false)
end

local function styleSwitch(button: TextButton, on: boolean, onText: string?, offText: string?)
	button.Text = if on then onText or "On" else offText or "Off"
	button.BackgroundColor3 = if on then Theme.COLORS.accent else Theme.COLORS.panelLight
end

local function refreshSwitches()
	styleSwitch(musicButton, musicOn())
	styleSwitch(sfxButton, sfxOn())
	styleSwitch(shakeButton, shakeOn(), "On", "Off")
end

local function refresh()
	refreshSwitches()
	cameraLabel.Text = `{math.floor(cameraSpeed() * 100 + 0.5)}%`
	if ClientState.capturingKey then
		return
	end
	keyLabel.Text = ClientState.drawKeyName()
	changeButton.Text = "Change"
end

local function stopCapture()
	ClientState.capturingKey = false
	hint.Text = "Click Change, then press the key you want."
	refresh()
end

local function startCapture()
	ClientState.capturingKey = true
	changeButton.Text = "Press…"
	hint.Text = "Press the key you want (Esc cancels)."
	local connection: RBXScriptConnection
	connection = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		connection:Disconnect()
		local name = input.KeyCode.Name
		if input.KeyCode == Enum.KeyCode.Escape then
			stopCapture()
			return
		end
		if table.find(Config.RESERVED_KEYS, name) then
			HudController.toast(`{name} is already used for something else.`, "fizzle")
			stopCapture()
			return
		end
		Remotes.get("SaveSettings"):FireServer("drawKey", name)
		-- Show it immediately; the server confirms via ProfileUpdated.
		keyLabel.Text = name
		HudController.toast(`"Draw a spell" key set to {name}`, "ready")
		-- Let this key press finish before it can open the canvas.
		task.delay(0.2, stopCapture)
	end)
end

function SettingsController.init()
	local panel = MenuController.createPanel("Settings", "Settings")
	panel.Size = UDim2.fromOffset(460, 372)

	local function newRow(title: string, y: number): Frame
		local row = Theme.frame(panel, {
			Position = UDim2.fromOffset(16, y),
			Size = UDim2.new(1, -32, 0, 44),
			BackgroundTransparency = 1,
		})
		Theme.label(row, title, {
			Size = UDim2.new(0.5, 0, 0, 18),
			Position = UDim2.fromOffset(0, 13),
			Font = Theme.BODY_FONT,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		return row
	end

	local function rowButton(row: Frame, text: string, right: number, width: number): TextButton
		return Theme.button(row, text, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -right, 0.5, 0),
			Size = UDim2.fromOffset(width, 34),
		})
	end

	-- Camera speed: mouse look, saved to the profile.
	local cameraRow = newRow("Camera speed", 60)
	local function stepCamera(direction: number)
		local limits = Config.CAMERA
		local speed = math.clamp(cameraSpeed() + direction * limits.STEP, limits.MIN, limits.MAX)
		speed = math.floor(speed * 100 + 0.5) / 100
		Remotes.get("SaveSettings"):FireServer("camera", speed)
		-- Switch right away; the server confirms via ProfileUpdated.
		local profile = ClientState.profile
		if profile and profile.settings then
			profile.settings.camera = speed
			ClientState.ProfileChanged:Fire()
		end
	end
	rowButton(cameraRow, "+", 0, 34).Activated:Connect(function()
		stepCamera(1)
	end)
	cameraLabel = Theme.label(cameraRow, "", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -40, 0.5, 0),
		Size = UDim2.fromOffset(50, 18),
		Font = Theme.BODY_FONT,
	})
	rowButton(cameraRow, "−", 96, 34).Activated:Connect(function()
		stepCamera(-1)
	end)

	local keyRow = newRow("Draw key", 110)
	keyLabel = Theme.label(keyRow, Config.DEFAULT_DRAW_KEY, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -196, 0.5, 0),
		Size = UDim2.fromOffset(50, 18),
		TextColor3 = Theme.COLORS.accent,
	})
	changeButton = rowButton(keyRow, "Change", 0, 90)
	changeButton.Activated:Connect(function()
		if not ClientState.capturingKey then
			startCapture()
		end
	end)
	rowButton(keyRow, "Reset", 96, 90).Activated:Connect(function()
		Remotes.get("SaveSettings"):FireServer("drawKey", Config.DEFAULT_DRAW_KEY)
		keyLabel.Text = Config.DEFAULT_DRAW_KEY
	end)

	local function addSwitch(
		title: string,
		y: number,
		key: "music" | "sfx" | "shake",
		isOn: () -> boolean
	): TextButton
		local button = rowButton(newRow(title, y), "On", 0, 90)
		button.Activated:Connect(function()
			local on = not isOn()
			Remotes.get("SaveSettings"):FireServer(key, on)
			-- Switch right away; the server confirms via ProfileUpdated.
			local profile = ClientState.profile
			if profile and profile.settings then
				profile.settings[key] = on
				ClientState.ProfileChanged:Fire()
			end
			refreshSwitches()
		end)
		return button
	end
	musicButton = addSwitch("Music", 160, "music", musicOn)
	sfxButton = addSwitch("Sound effects", 210, "sfx", sfxOn)
	shakeButton = addSwitch("Screen shake", 260, "shake", shakeOn)

	hint = Theme.label(panel, "Click Change, then press the key you want.", {
		Position = UDim2.fromOffset(16, 322),
		Size = UDim2.new(1, -32, 0, 16),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

function SettingsController.start()
	ClientState.ProfileChanged:Connect(refresh)
	refresh()
end

return SettingsController
