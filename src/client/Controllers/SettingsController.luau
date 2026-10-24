--!strict
-- Settings panel. Currently: rebind the key that focuses the "type a spell"
-- box. Click "Change", press any key, done — the choice is saved to the
-- player's profile (server validates it and refuses reserved keys like WASD,
-- Space, the hotbar numbers, and "/" which Roblox chat uses).

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

local function refresh()
	if ClientState.capturingKey then
		return
	end
	keyLabel.Text = ClientState.typeKeyName()
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
		Remotes.get("SaveSettings"):FireServer("typeKey", name)
		-- Show it immediately; the server confirms via ProfileUpdated.
		keyLabel.Text = name
		HudController.toast(`"Type a spell" key set to {name}`, "ready")
		-- Let this key press finish before it can open the spell box.
		task.delay(0.2, stopCapture)
	end)
end

function SettingsController.init()
	local panel = MenuController.createPanel("Settings", "Settings")
	local row = Theme.frame(panel, {
		Position = UDim2.fromOffset(16, 76),
		Size = UDim2.new(1, -32, 0, 64),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(row)
	Theme.label(row, "Type-a-spell key", {
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
	keyLabel = Theme.label(keyBox, Config.DEFAULT_TYPE_KEY, {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		TextColor3 = Theme.COLORS.accent,
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
	local reset = Theme.button(panel, `Reset to {Config.DEFAULT_TYPE_KEY}`, {
		Position = UDim2.fromOffset(16, 152),
		Size = UDim2.fromOffset(180, Theme.TOUCH - 8),
	})
	reset.Activated:Connect(function()
		Remotes.get("SaveSettings"):FireServer("typeKey", Config.DEFAULT_TYPE_KEY)
		keyLabel.Text = Config.DEFAULT_TYPE_KEY
	end)
	hint = Theme.label(panel, "Click Change, then press the key you want.", {
		Position = UDim2.fromOffset(16, 210),
		Size = UDim2.new(1, -32, 0, 24),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Theme.label(panel, "Gamepad: Y opens the spell box. Touch: tap the box.", {
		Position = UDim2.fromOffset(16, 240),
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
