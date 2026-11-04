--!strict
-- Settings panel: rebind the key that opens the drawing canvas (click
-- "Change", press any key, done) and switch the background music, the sound
-- effects and the screen shake on or off.
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
	button.BackgroundColor3 = if on then Theme.COLORS.good else Theme.COLORS.bad
end

local function refreshSwitches()
	styleSwitch(musicButton, musicOn())
	styleSwitch(sfxButton, sfxOn())
	styleSwitch(shakeButton, shakeOn(), "On", "Off")
end

local function refresh()
	refreshSwitches()
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
	changeButton.Text = "Press a key… (Esc to cancel)"
	hint.Text = "Waiting for a key…"
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
	panel.Size = UDim2.fromOffset(560, 470)
	local row = Theme.frame(panel, {
		Position = UDim2.fromOffset(16, 76),
		Size = UDim2.new(1, -32, 0, 64),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(row)
	Theme.label(row, "Draw-a-spell key", {
		Size = UDim2.new(0.42, 0, 1, -16),
		Position = UDim2.fromOffset(12, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local keyBox = Theme.frame(row, {
		Position = UDim2.new(0.44, 0, 0.5, -20),
		Size = UDim2.fromOffset(70, 40),
		BackgroundColor3 = Theme.COLORS.panel,
	})
	Theme.corner(keyBox, 8)
	Theme.stroke(keyBox, Theme.COLORS.accent, 2)
	keyLabel = Theme.label(keyBox, Config.DEFAULT_DRAW_KEY, {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		TextColor3 = Theme.COLORS.heading,
	})
	changeButton = Theme.button(row, "Change", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(170, Theme.TOUCH - 8),
	})
	changeButton.Activated:Connect(function()
		if not ClientState.capturingKey then
			startCapture()
		end
	end)
	-- Background music and sound effects: one big switch each.
	local function addSwitch(
		title: string,
		y: number,
		key: "music" | "sfx" | "shake",
		isOn: () -> boolean
	): TextButton
		local switchRow = Theme.frame(panel, {
			Position = UDim2.fromOffset(16, y),
			Size = UDim2.new(1, -32, 0, 64),
			BackgroundColor3 = Theme.COLORS.panelLight,
		})
		Theme.corner(switchRow)
		Theme.label(switchRow, title, {
			Size = UDim2.new(0.5, 0, 1, -16),
			Position = UDim2.fromOffset(12, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local button = Theme.button(switchRow, "On", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(170, Theme.TOUCH - 8),
		})
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
	musicButton = addSwitch("Background music", 146, "music", musicOn)
	sfxButton = addSwitch("Sound effects", 216, "sfx", sfxOn)
	shakeButton = addSwitch("Screen shake", 286, "shake", shakeOn)

	local reset = Theme.button(panel, `Reset to {Config.DEFAULT_DRAW_KEY}`, {
		Position = UDim2.fromOffset(16, 360),
		Size = UDim2.fromOffset(180, Theme.TOUCH - 8),
	})
	reset.Activated:Connect(function()
		Remotes.get("SaveSettings"):FireServer("drawKey", Config.DEFAULT_DRAW_KEY)
		keyLabel.Text = Config.DEFAULT_DRAW_KEY
	end)
	hint = Theme.label(panel, "Click Change, then press the key you want.", {
		Position = UDim2.fromOffset(16, 410),
		Size = UDim2.new(1, -32, 0, 24),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Theme.label(panel, "Gamepad: X, then draw with the right stick. Touch: tap Draw, then drag.", {
		Position = UDim2.fromOffset(16, 436),
		Size = UDim2.new(1, -32, 0, 24),
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
