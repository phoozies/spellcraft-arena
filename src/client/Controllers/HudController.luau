--!strict
-- The always-on HUD: hotbar (hand), glyph cards (what to draw), coins/wins wallet,
-- match bar (phase, timer, scores), toasts, and kill feed.
-- Layout is scale-based with a UIScale clamp so it fits phones through TVs,
-- and respects device safe areas (ScreenInsets).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Boosts = require(ReplicatedStorage.Shared.Match.Boosts)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Quality = require(ReplicatedStorage.Shared.Spells.Quality)
local GlyphView = require(ReplicatedStorage.Shared.UI.GlyphView)
local Responsive = require(script.Parent.Parent.UI.Responsive)
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
		stars: TextLabel,
		stroke: UIStroke,
	}
} =
	{}
local coinsLabel: TextLabel
local winsLabel: TextLabel
local matchBar: Frame
local matchText: TextLabel
local scoreText: TextLabel
local toastHolder: Frame
local feedHolder: Frame
local boostsLabel: TextLabel
local battleLabel: TextLabel
local battleLeave: TextButton

local TOAST_COLORS: { [string]: Color3 } = {
	fizzle = Color3.fromRGB(120, 144, 156),
	ready = Color3.fromRGB(102, 187, 106),
	cooldown = Color3.fromRGB(255, 167, 38),
	reward = Color3.fromRGB(255, 202, 40),
	victory = Color3.fromRGB(255, 202, 40),
	round = Color3.fromRGB(66, 165, 245),
	streak = Color3.fromRGB(236, 64, 122),
	info = Color3.fromRGB(57, 55, 98),
}

function HudController.getGui(): ScreenGui
	return gui
end

-- How many times you've picked a match boost (the server mirrors your picks
-- to the player attribute "Boosts", e.g. "Power:2,Focus:1").
function HudController.boostStacks(boostId: string): number
	local text = player:GetAttribute("Boosts")
	if typeof(text) ~= "string" then
		return 0
	end
	for id, stacks in string.gmatch(text, "(%w+):(%d+)") do
		if id == boostId then
			return tonumber(stacks) or 0
		end
	end
	return 0
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

-- Glyph cards above the hotbar: what to draw for each spell you can ready.
-- In a match that is your match spellbook; in the hub, every spell you own.
-- A card shows the spell's cooldown while it recharges. Tapping a card opens
-- the drawing canvas with a preview of its shape to trace (the better you
-- follow it, the stronger the spell: Spells/Quality).
local glyphRow: Frame
local glyphCards: { [string]: { card: Frame, name: TextLabel, cover: TextLabel } } = {}

local function refreshWords()
	for _, entry in glyphCards do
		entry.card:Destroy()
	end
	table.clear(glyphCards)
	local ids: { string } = {}
	if ClientState.spellbook then
		ids = table.clone(ClientState.spellbook)
	else
		local profile = ClientState.profile
		if profile and profile.element ~= "" then
			for _, def in SpellDefinitions.ofElement(profile.element) do
				table.insert(ids, def.id)
			end
		end
	end
	for order, id in ids do
		local def = SpellDefinitions.get(id)
		if def then
			local color = Elements.color(def.element)
			local card = Theme.frame(glyphRow, {
				Name = def.id,
				Size = UDim2.fromOffset(62, 74),
				LayoutOrder = order,
				BackgroundTransparency = 0.2,
			})
			Theme.corner(card, 10)
			local stroke = Theme.stroke(card, color, if def.ultimate then 4 else 2)
			stroke.Transparency = 0.2
			GlyphView.create(card, def.glyph, 46, color, { Position = UDim2.fromOffset(8, 2) })
			local name = Theme.label(card, def.name, {
				Size = UDim2.new(1, -4, 0, 16),
				Position = UDim2.new(0, 2, 1, -18),
			})
			local cover = Theme.label(card, "", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 1,
				TextColor3 = Theme.COLORS.bad,
				ZIndex = 4,
			})
			Theme.corner(cover, 10)
			local hit = Instance.new("TextButton")
			hit.Name = "Draw"
			hit.Text = ""
			hit.BackgroundTransparency = 1
			hit.Size = UDim2.fromScale(1, 1)
			hit.ZIndex = 6
			hit.Parent = card
			hit.Activated:Connect(function()
				ClientState.DrawRequested:Fire(id)
			end)
			glyphCards[id] = { card = card, name = name, cover = cover }
		end
	end
end

local function tickWords()
	for id, entry in glyphCards do
		local left = ClientState.cooldownLeft(id)
		if left > 0 then
			entry.cover.BackgroundTransparency = 0.45
			entry.cover.Text = if left >= 1 then tostring(math.ceil(left)) else ""
		else
			entry.cover.BackgroundTransparency = 1
			entry.cover.Text = ""
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
		local stars = Theme.label(button, "", {
			Name = "Quality",
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(40, 14),
			Position = UDim2.new(1, -3, 0, 3),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 2,
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
			stars = stars,
			stroke = stroke,
		}
	end
end

local function refreshHotbar()
	for i, slot in slots do
		local id = ClientState.hand[i]
		local def = id and SpellDefinitions.get(id)
		if def then
			local color = Elements.color(def.element)
			local element = Elements.get(def.element)
			slot.button.Visible = true
			slot.icon.Text = if element then element.icon else ""
			slot.icon.TextColor3 = color
			slot.name.Text = def.name
			slot.name.TextColor3 = Theme.COLORS.text
			-- How well this copy was drawn: 1 to 4 stars.
			local quality = ClientState.qualities[i]
			if quality then
				local tier = Quality.tier(quality)
				slot.stars.Text = string.rep("★", tier.stars)
				slot.stars.TextColor3 = tier.color
			else
				slot.stars.Text = ""
			end
			local isReadied = i == ClientState.readiedSlot
			slot.stroke.Color = if isReadied then Theme.COLORS.accent else color
			slot.stroke.Thickness = if isReadied then 5 else 3
			slot.button.BackgroundColor3 = if isReadied
				then Color3.fromRGB(84, 80, 140)
				else Theme.COLORS.panelLight
		else
			-- Empty slot: hint that drawing a glyph fills it. All 5 slots
			-- show, since you can stockpile up to 5 copies.
			slot.button.Visible = true
			slot.icon.Text = ""
			slot.stars.Text = ""
			slot.name.Text = if i == #ClientState.hand + 1 then "draw!" else ""
			slot.name.TextColor3 = Theme.COLORS.subtext
			slot.stroke.Color = Color3.fromRGB(20, 20, 40)
			slot.stroke.Thickness = 3
			slot.button.BackgroundColor3 = Theme.COLORS.panel
		end
	end
	refreshWords()
end

local drawBar: Frame

local function tickCooldowns()
	-- Copies of the same spell share one cooldown, so every slot holding
	-- that spell shows the same sweep.
	for i, slot in slots do
		local id = ClientState.hand[i]
		local def = id and SpellDefinitions.get(id)
		local left = if id then ClientState.cooldownLeft(id) else 0
		if def and left > 0 and def.cooldown > 0 then
			slot.cooldown.Size = UDim2.fromScale(1, math.clamp(left / def.cooldown, 0, 1))
			slot.cooldownText.Text = if left >= 1 then tostring(math.ceil(left)) else ""
		else
			slot.cooldown.Size = UDim2.fromScale(1, 0)
			slot.cooldownText.Text = ""
		end
	end
	tickWords()
	local drawLeft = math.max(0, ClientState.drawReadyAt - os.clock())
	drawBar.Size = UDim2.new(math.clamp(drawLeft / Config.DRAW_COOLDOWN, 0, 1), 0, 0, 4)
	local state = ClientState.match
	if state.phase ~= "Idle" and state.endsAt > 0 then
		local left = math.max(0, math.ceil(state.endsAt - workspace:GetServerTimeNow()))
		local phaseText = if state.phase == "Countdown"
			then `Round {state.round} starts in {left}`
			elseif state.phase == "Round" then `Round {state.round} — {left}s`
			elseif state.phase == "Draft" then `Draft a spell! {left}s`
			elseif state.phase == "Intro" then "Match starting…"
			else "Match over"
		matchText.Text = phaseText
	end
end

local function buildGlyphRow(root: Frame)
	glyphRow = Theme.frame(root, {
		Name = "Glyphs",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(560, 74),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = glyphRow
	-- Thin bar under the cards that drains during the drawing cooldown.
	drawBar = Theme.frame(root, {
		Name = "DrawCooldown",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -104),
		Size = UDim2.new(0, 0, 0, 4),
		BackgroundColor3 = Theme.COLORS.accent,
	})
	Theme.corner(drawBar, 2)
end

-- Top-left wallet: coins (spent on crates) and wins (the leaderboard stat).
local function buildWallet(root: Frame)
	local holder = Theme.frame(root, {
		Name = "Wallet",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(240, 44),
		BackgroundTransparency = 0.15,
	})
	Theme.corner(holder)
	coinsLabel = Theme.label(holder, "💰 0", {
		Size = UDim2.new(0.55, -8, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.accent,
	})
	winsLabel = Theme.label(holder, "🏆 0", {
		Size = UDim2.new(0.45, -8, 1, -8),
		Position = UDim2.new(0.55, 0, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local shownCoins = 0
local function refreshWallet()
	local profile = ClientState.profile
	if not profile then
		return
	end
	winsLabel.Text = `🏆 {profile.stats.wins}`
	-- Count up/down to the new balance so earning and spending are felt.
	local from, to = shownCoins, profile.coins
	shownCoins = to
	local start = os.clock()
	task.spawn(function()
		while coinsLabel.Parent and shownCoins == to do
			local t = math.min((os.clock() - start) / 0.5, 1)
			coinsLabel.Text = `💰 {math.floor(from + (to - from) * t + 0.5)}`
			if t >= 1 then
				break
			end
			task.wait()
		end
	end)
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

-- Your picked match boosts as a row of icons under the match bar.
local function refreshBoosts()
	local parts = {}
	for _, boost in Boosts.LIST do
		local stacks = HudController.boostStacks(boost.id)
		if stacks > 0 then
			table.insert(parts, `{boost.icon}x{stacks}`)
		end
	end
	boostsLabel.Text = table.concat(parts, "  ")
	boostsLabel.Visible = #parts > 0
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

local function buildBattleBanner(root: Frame)
	battleLabel = Theme.label(root, "⚔ BATTLEGROUND: beat raiders for coins!", {
		Name = "BattleBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(560, 36),
		TextColor3 = Theme.COLORS.accent,
		TextStrokeTransparency = 0.3,
		Visible = false,
	})
	battleLeave = Theme.button(root, "Return to Hub", {
		Name = "BattleLeave",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 48),
		Size = UDim2.fromOffset(150, 30),
		BackgroundColor3 = Theme.COLORS.panel,
		Visible = false,
	})
	battleLeave.Activated:Connect(function()
		Remotes.get("LeaveBattleground"):FireServer()
	end)
end

local function buildBoosts(root: Frame)
	boostsLabel = Theme.label(root, "", {
		Name = "Boosts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.fromOffset(300, 28),
		TextStrokeTransparency = 0.4,
		Visible = false,
	})
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
	local text = if killer then `{killer} ★ {victim}` else `{victim} was knocked out`
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
	buildGlyphRow(root)
	buildWallet(root)
	buildMatchBar(root)
	buildBoosts(root)
	buildBattleBanner(root)
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

	Responsive.bind(scale)
	gui.Parent = player:WaitForChild("PlayerGui")
	GuiService.AutoSelectGuiEnabled = true
end

function HudController.start()
	ClientState.HandChanged:Connect(refreshHotbar)
	ClientState.ProfileChanged:Connect(refreshWallet)
	ClientState.ProfileChanged:Connect(refreshWords)
	ClientState.MatchChanged:Connect(refreshMatch)
	player:GetAttributeChangedSignal("Boosts"):Connect(refreshBoosts)
	local function refreshBattle()
		local inside = player:GetAttribute("InBattleground") == true
		battleLabel.Visible = inside
		battleLeave.Visible = inside
	end
	player:GetAttributeChangedSignal("InBattleground"):Connect(refreshBattle)
	refreshBattle()
	refreshBoosts()
	Remotes.get("Toast").OnClientEvent:Connect(HudController.toast)
	Remotes.get("Knockout").OnClientEvent:Connect(addFeed)
	refreshHotbar()
	RunService.Heartbeat:Connect(tickCooldowns)
end

return HudController
