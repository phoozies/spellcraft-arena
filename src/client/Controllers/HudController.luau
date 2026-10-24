--!strict
-- The always-on HUD: hotbar (hand), spell box + mic button, level/XP bar,
-- match bar (phase, timer, scores), toasts, and kill feed.
-- Layout is scale-based with a UIScale clamp so it fits phones through TVs,
-- and respects device safe areas (ScreenInsets).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local HudController = {}

local gui: ScreenGui
local slots: {
	{
		button: TextButton,
		cooldown: Frame,
		cooldownText: TextLabel,
		icon: TextLabel,
		name: TextLabel,
		stroke: UIStroke,
	}
} =
	{}
local spellBox: TextBox
local micButton: TextButton
local levelLabel: TextLabel
local xpFill: Frame
local matchBar: Frame
local matchText: TextLabel
local scoreText: TextLabel
local toastHolder: Frame
local feedHolder: Frame
local heardLabel: TextLabel

local TOAST_COLORS: { [string]: Color3 } = {
	fizzle = Color3.fromRGB(120, 144, 156),
	ready = Color3.fromRGB(102, 187, 106),
	cooldown = Color3.fromRGB(255, 167, 38),
	levelup = Color3.fromRGB(255, 202, 40),
	reward = Color3.fromRGB(255, 202, 40),
	victory = Color3.fromRGB(255, 202, 40),
	round = Color3.fromRGB(66, 165, 245),
	streak = Color3.fromRGB(236, 64, 122),
	info = Color3.fromRGB(57, 55, 98),
}

function HudController.getGui(): ScreenGui
	return gui
end

function HudController.toast(message: string, kind: string?)
	local frame = Theme.frame(toastHolder, {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = TOAST_COLORS[kind or "info"] or Theme.COLORS.panelLight,
		BackgroundTransparency = 0.1,
	})
	Theme.corner(frame, 10)
	Theme.stroke(frame, Color3.fromRGB(20, 20, 40), 2)
	Theme.label(
		frame,
		message,
		{ Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) }
	)
	-- Keep at most 4 toasts.
	local count = 0
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 4 then
		for _, child in toastHolder:GetChildren() do
			if child:IsA("Frame") and child ~= frame then
				child:Destroy()
				break
			end
		end
	end
	task.delay(3, function()
		if frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.3)
			frame:Destroy()
		end
	end)
end

function HudController.focusSpellBox()
	spellBox:CaptureFocus()
end

local function submitSpellBox()
	local text = spellBox.Text
	spellBox.Text = ""
	if #text == 0 then
		return
	end
	-- Admin commands aren't words, so they skip the typing cooldown.
	if string.sub(text, 1, #Config.ADMIN_PREFIX) == Config.ADMIN_PREFIX then
		Remotes.get("SubmitWord"):FireServer(string.sub(text, 1, 120))
		return
	end
	local now = os.clock()
	if now < ClientState.typeReadyAt then
		HudController.toast(
			`Typing cooldown ({math.ceil((ClientState.typeReadyAt - now) * 10) / 10}s)`,
			"cooldown"
		)
		return
	end
	ClientState.typeReadyAt = now + Config.TYPE_COOLDOWN
	Remotes.get("SubmitWord"):FireServer(string.sub(text, 1, 64))
end

-- Blocks pasting: a real keystroke changes the text by at most one
-- character, so any bigger jump (Ctrl+V, right-click paste, drag-drop) is
-- undone. The server's 1s typing cooldown backs this up for chat and voice.
local function guardAgainstPaste(box: TextBox)
	local lastText = box.Text
	local reverting = false
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if reverting then
			return
		end
		local text = box.Text
		if #text - #lastText > 1 and text ~= "" then
			reverting = true
			box.Text = lastText
			box.CursorPosition = #lastText + 1
			reverting = false
			HudController.toast("No pasting — type it out!", "fizzle")
			return
		end
		lastText = text
	end)
	box.Focused:Connect(function()
		lastText = box.Text
	end)
end

-- Chips above the spell box: your match spellbook (the words you can type
-- this match) or, in the hub, any spell still recharging.
local wordsRow: Frame
local wordChips: { [string]: TextLabel } = {}

local function refreshWords()
	for _, chip in wordChips do
		chip.Parent:Destroy()
	end
	table.clear(wordChips)
	local ids: { string } = {}
	if ClientState.spellbook then
		ids = table.clone(ClientState.spellbook)
	else
		for id in ClientState.cooldowns do
			if ClientState.cooldownLeft(id) > 0 then
				table.insert(ids, id)
			end
		end
	end
	for order, id in ids do
		local def = SpellDefinitions.get(id)
		if def then
			local chip = Theme.frame(wordsRow, {
				Size = UDim2.fromOffset(96, 26),
				LayoutOrder = order,
				BackgroundTransparency = 0.2,
			})
			Theme.corner(chip, 13)
			local stroke = Theme.stroke(chip, Rarity.INFO[def.rarity].color, 2)
			stroke.Transparency = 0.2
			wordChips[id] = Theme.label(chip, string.lower(def.name), {
				Size = UDim2.new(1, -10, 1, -4),
				Position = UDim2.fromOffset(5, 2),
			})
		end
	end
end

local function tickWords()
	for id, label in wordChips do
		local def = SpellDefinitions.get(id)
		local left = ClientState.cooldownLeft(id)
		local held = table.find(ClientState.hand, id) ~= nil
		if def then
			label.Text = if left > 0
				then `{string.lower(def.name)} {math.ceil(left)}s`
				else string.lower(def.name)
			label.TextColor3 = if left > 0
				then Theme.COLORS.bad
				elseif held then Theme.COLORS.subtext
				else Theme.COLORS.text
		end
	end
end

local function buildHotbar(root: Frame)
	local bar = Theme.frame(root, {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(5 * 76 + 8, 84),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = bar

	for i = 1, Config.MAX_HAND do
		local button = Theme.button(bar, "", {
			Name = `Slot{i}`,
			Size = UDim2.fromOffset(70, 80),
			LayoutOrder = i,
		})
		local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Thickness = 3
		local icon = Theme.label(button, "", {
			Name = "Glyph",
			Size = UDim2.new(1, 0, 0.45, 0),
			Position = UDim2.fromScale(0, 0.08),
		})
		local name = Theme.label(button, "", {
			Name = "SpellName",
			Size = UDim2.new(1, -6, 0.3, 0),
			Position = UDim2.new(0, 3, 0.55, 0),
		})
		Theme.label(button, tostring(i), {
			Name = "Key",
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.fromOffset(4, 2),
			TextColor3 = Theme.COLORS.subtext,
		})
		local cooldown = Theme.frame(button, {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			ZIndex = 3,
		})
		Theme.corner(cooldown)
		local cooldownText = Theme.label(button, "", { Name = "CooldownText", ZIndex = 4 })
		button.Activated:Connect(function()
			Remotes.get("SelectSlot"):FireServer(i)
		end)
		slots[i] = {
			button = button,
			cooldown = cooldown,
			cooldownText = cooldownText,
			icon = icon,
			name = name,
			stroke = stroke,
		}
	end
end

local function refreshHotbar()
	for i, slot in slots do
		local id = ClientState.hand[i]
		local def = id and SpellDefinitions.get(id)
		if def then
			local info = Rarity.INFO[def.rarity]
			slot.button.Visible = true
			slot.icon.Text = info.glyph
			slot.icon.TextColor3 = def.visual.color
			slot.name.Text = def.name
			slot.name.TextColor3 = Theme.COLORS.text
			slot.stroke.Color = if id == ClientState.readied
				then Theme.COLORS.accent
				else info.color
			slot.stroke.Thickness = if id == ClientState.readied then 5 else 3
			slot.button.BackgroundColor3 = if id == ClientState.readied
				then Color3.fromRGB(84, 80, 140)
				else Theme.COLORS.panelLight
		else
			-- Empty slot: hint that typing a word fills it.
			local slotsShown = math.max(
				#ClientState.hand + 1,
				if ClientState.spellbook then #ClientState.spellbook else Config.STARTING_HAND
			)
			slot.button.Visible = i <= math.min(slotsShown, Config.MAX_HAND)
			slot.icon.Text = ""
			slot.name.Text = if i == #ClientState.hand + 1 then "type!" else ""
			slot.name.TextColor3 = Theme.COLORS.subtext
			slot.stroke.Color = Color3.fromRGB(20, 20, 40)
			slot.stroke.Thickness = 3
			slot.button.BackgroundColor3 = Theme.COLORS.panel
		end
	end
	refreshWords()
end

local typeBar: Frame

local function tickCooldowns()
	-- Held copies are always castable; recharges show on the word chips.
	tickWords()
	local typeLeft = math.max(0, ClientState.typeReadyAt - os.clock())
	typeBar.Size = UDim2.new(math.clamp(typeLeft / Config.TYPE_COOLDOWN, 0, 1), 0, 0, 4)
	local state = ClientState.match
	if state.phase ~= "Idle" and state.endsAt > 0 then
		local left = math.max(0, math.ceil(state.endsAt - workspace:GetServerTimeNow()))
		local phaseText = if state.phase == "Countdown"
			then `Round {state.round} starts in {left}`
			elseif state.phase == "Round" then `Round {state.round} — {left}s`
			elseif state.phase == "Draft" then `Draft a spell! {left}s`
			else "Match over"
		matchText.Text = phaseText
	end
end

local function buildSpellBox(root: Frame)
	local holder = Theme.frame(root, {
		Name = "SpellInput",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -104),
		Size = UDim2.fromOffset(360, Theme.TOUCH),
		BackgroundTransparency = 1,
	})
	spellBox = Instance.new("TextBox")
	spellBox.Name = "SpellBox"
	spellBox.Size = UDim2.new(1, -(Theme.TOUCH + 8), 1, 0)
	spellBox.BackgroundColor3 = Theme.COLORS.panel
	spellBox.BackgroundTransparency = 0.15
	spellBox.TextColor3 = Theme.COLORS.text
	spellBox.PlaceholderText = "Type a spell... (T)"
	spellBox.PlaceholderColor3 = Theme.COLORS.subtext
	spellBox.Font = Theme.FONT
	spellBox.TextScaled = true
	spellBox.ClearTextOnFocus = true
	spellBox.Text = ""
	Theme.corner(spellBox, 14)
	Theme.stroke(spellBox, Theme.COLORS.accent, 2)
	Theme.padding(spellBox, 8)
	spellBox.Parent = holder
	guardAgainstPaste(spellBox)
	-- Thin bar under the box that drains during the typing cooldown.
	typeBar = Theme.frame(holder, {
		Name = "TypeCooldown",
		Position = UDim2.new(0, 0, 1, 2),
		Size = UDim2.new(0, 0, 0, 4),
		BackgroundColor3 = Theme.COLORS.accent,
	})
	Theme.corner(typeBar, 2)
	wordsRow = Theme.frame(root, {
		Name = "Words",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -164),
		Size = UDim2.fromOffset(520, 26),
		BackgroundTransparency = 1,
	})
	local wordsLayout = Instance.new("UIListLayout")
	wordsLayout.FillDirection = Enum.FillDirection.Horizontal
	wordsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	wordsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	wordsLayout.Padding = UDim.new(0, 6)
	wordsLayout.Parent = wordsRow
	spellBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitSpellBox()
		end
	end)

	micButton = Theme.button(holder, "🎤", {
		Name = "Mic",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(Theme.TOUCH, Theme.TOUCH),
	})
	local function setListening(on: boolean)
		Remotes.get("VoiceListen"):FireServer(on)
		micButton.BackgroundColor3 = if on then Theme.COLORS.bad else Theme.COLORS.panelLight
	end
	micButton.MouseButton1Down:Connect(function()
		setListening(true)
	end)
	micButton.MouseButton1Up:Connect(function()
		setListening(false)
	end)
	micButton.MouseLeave:Connect(function()
		if micButton.BackgroundColor3 == Theme.COLORS.bad then
			setListening(false)
		end
	end)
	local function syncMic()
		micButton.Visible = ReplicatedStorage:GetAttribute("VoiceSpellsEnabled") == true
	end
	ReplicatedStorage:GetAttributeChangedSignal("VoiceSpellsEnabled"):Connect(syncMic)
	syncMic()

	heardLabel = Theme.label(holder, "", {
		Name = "Heard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.COLORS.subtext,
	})
end

local function buildLevel(root: Frame)
	local holder = Theme.frame(root, {
		Name = "Level",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(220, 44),
		BackgroundTransparency = 0.15,
	})
	Theme.corner(holder)
	levelLabel = Theme.label(holder, "Lv 1", {
		Size = UDim2.new(0, 60, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		TextColor3 = Theme.COLORS.accent,
	})
	local back = Theme.frame(holder, {
		Position = UDim2.new(0, 70, 0.5, -7),
		Size = UDim2.new(1, -80, 0, 14),
		BackgroundColor3 = Color3.fromRGB(20, 20, 40),
	})
	Theme.corner(back, 7)
	xpFill = Theme.frame(back, {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.COLORS.accent,
	})
	Theme.corner(xpFill, 7)
end

local function refreshLevel()
	local profile = ClientState.profile
	if not profile then
		return
	end
	levelLabel.Text = `Lv {profile.level}`
	local ratio = if profile.xpNeeded > 0 then profile.xpInto / profile.xpNeeded else 1
	TweenService
		:Create(xpFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1) })
		:Play()
end

local function buildMatchBar(root: Frame)
	matchBar = Theme.frame(root, {
		Name = "MatchBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(420, 64),
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	Theme.corner(matchBar)
	matchText = Theme.label(
		matchBar,
		"",
		{ Size = UDim2.new(1, -16, 0.5, 0), Position = UDim2.fromOffset(8, 2) }
	)
	scoreText = Theme.label(matchBar, "", {
		Size = UDim2.new(1, -16, 0.45, 0),
		Position = UDim2.new(0, 8, 0.52, 0),
		TextColor3 = Theme.COLORS.subtext,
		RichText = true,
	})
end

local function refreshMatch()
	local state = ClientState.match
	matchBar.Visible = state.phase ~= "Idle"
	local parts = {}
	for team, wins in state.scores do
		local color = if team == "Blue"
			then "#42A5F5"
			elseif team == "Red" then "#EF5350"
			else "#FFCA28"
		local mine = if team == state.myTeam then " (you)" else ""
		table.insert(parts, `<font color="{color}">{team}{mine}: {wins}</font>`)
	end
	table.sort(parts)
	local mapPrefix = if state.mapName then `{state.mapName} · ` else ""
	scoreText.Text = mapPrefix .. table.concat(parts, "   ")
	if state.phase == "Results" then
		matchText.Text = "Match over!"
	end
end

local function buildFeed(root: Frame)
	feedHolder = Theme.frame(root, {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 60),
		Size = UDim2.fromOffset(260, 160),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = feedHolder
end

local function addFeed(killer: string?, victim: string, spell: string?)
	local text = if killer then `{killer} ✦ {victim}` else `{victim} was knocked out`
	if killer and spell then
		text = `{killer} [{spell}] {victim}`
	end
	local row =
		Theme.frame(feedHolder, { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 0.3 })
	Theme.corner(row, 8)
	Theme.label(row, text, { Size = UDim2.new(1, -10, 1, -4), Position = UDim2.fromOffset(5, 2) })
	task.delay(5, function()
		row:Destroy()
	end)
end

local function updateScale(scale: UIScale)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local s = math.min(size.X / 1280, size.Y / 720)
	-- Touch screens get slightly larger UI for finger-sized targets.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		s *= 1.15
	end
	scale.Scale = math.clamp(s, 0.6, 1.4)
end

function HudController.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "WordcraftHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Theme.frame(gui, {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = gui

	buildHotbar(root)
	buildSpellBox(root)
	buildLevel(root)
	buildMatchBar(root)
	buildFeed(root)

	toastHolder = Theme.frame(root, {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(460, 180),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = toastHolder

	updateScale(scale)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			updateScale(scale)
		end)
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	GuiService.AutoSelectGuiEnabled = true
end

function HudController.start()
	ClientState.HandChanged:Connect(refreshHotbar)
	ClientState.ProfileChanged:Connect(refreshLevel)
	ClientState.MatchChanged:Connect(refreshMatch)
	Remotes.get("Toast").OnClientEvent:Connect(HudController.toast)
	Remotes.get("Knockout").OnClientEvent:Connect(addFeed)
	Remotes.get("VoiceHeard").OnClientEvent:Connect(function(text)
		heardLabel.Text = `Heard: "{text}"`
		task.delay(2.5, function()
			if heardLabel.Text == `Heard: "{text}"` then
				heardLabel.Text = ""
			end
		end)
	end)
	refreshHotbar()
	RunService.Heartbeat:Connect(tickCooldowns)
end

return HudController
