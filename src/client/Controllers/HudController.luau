--!strict
-- The always-on HUD: spell cards (what to draw), coins/wins wallet,
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
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Responsive = require(script.Parent.Parent.UI.Responsive)
local Sigil = require(script.Parent.Parent.UI.Sigil)
local SpellCard = require(script.Parent.Parent.UI.SpellCard)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local HudController = {}

local gui: ScreenGui
local coinsLabel: TextLabel
local winsLabel: TextLabel
local walletFrame: Frame
local matchBar: Frame
local matchText: TextLabel
local scoreText: TextLabel
local toastHolder: Frame
local feedHolder: Frame
local boostsLabel: TextLabel
local battleLeave: TextButton

local TOAST_COLORS: { [string]: Color3 } = {
	fizzle = Theme.COLORS.subtext,
	ready = Theme.COLORS.good,
	reward = Theme.COLORS.accent,
	victory = Theme.COLORS.accent,
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

-- A refusal (a spell that can't be drawn or cast right now) is a buzz and one
-- quiet line under the sight, gone in a moment. Everything else is a small toast.
local refusalLabel: TextLabel
local refusalShown = 0

function HudController.toast(message: string, kind: string?)
	if kind == "error" then
		AudioController.play("uiError")
		refusalShown += 1
		local shown = refusalShown
		refusalLabel.Text = message
		refusalLabel.TextTransparency = 0
		task.delay(1.2, function()
			if shown == refusalShown then
				TweenService:Create(refusalLabel, TweenInfo.new(0.3), { TextTransparency = 1 })
					:Play()
			end
		end)
		return
	end
	local frame = Theme.frame(toastHolder, {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 0.2,
	})
	Theme.corner(frame, 10)
	Theme.label(frame, message, {
		Size = UDim2.new(1, -16, 1, -12),
		Position = UDim2.fromOffset(8, 6),
		Font = Theme.BODY_FONT,
		TextColor3 = TOAST_COLORS[kind or "info"] or Theme.COLORS.text,
	})
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

-- The spell row: one small disc per spell you can cast, showing its shape and
-- its key. Key N or a tap opens the Nth shape on the canvas (the better you
-- trace it, the stronger the spell: Spells/Quality), and finishing it casts the
-- spell at once. A disc dims with the seconds left while its spell recharges.
local glyphRow: Frame
local CARD_SIZE, CARD_GAP = 48, 6
local MAX_CARDS = 5
type WordCard = {
	card: Frame,
	cover: TextLabel,
	stroke: UIStroke,
}
local glyphCards: { [string]: WordCard } = {}
local tracing: string? = nil

local function styleWord(id: string, entry: WordCard)
	entry.stroke.Transparency = if tracing == id then 0 else 1
end

-- The spell whose canvas is open (nil when it closes); DrawController calls it.
function HudController.setTracing(spellId: string?)
	tracing = spellId
	for id, entry in glyphCards do
		styleWord(id, entry)
	end
end

local function refreshWords()
	for _, entry in glyphCards do
		entry.card:Destroy()
	end
	table.clear(glyphCards)
	for order, id in ClientState.drawableSpells() do
		local def = SpellDefinitions.get(id)
		if def then
			local card = Theme.frame(glyphRow, {
				Name = def.id,
				Size = UDim2.fromOffset(CARD_SIZE, CARD_SIZE),
				LayoutOrder = order,
				BackgroundTransparency = 0.25,
			})
			Theme.corner(card, 12)
			local stroke = Theme.stroke(card, Theme.COLORS.accent, 3)
			Sigil.create(card, def.glyph, CARD_SIZE - 12, SpellCard.colorOf(def.id), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundTransparency = 1,
			})
			Theme.label(card, tostring(order), {
				Name = "Key",
				Size = UDim2.fromOffset(12, 12),
				Position = UDim2.fromOffset(3, 2),
				Font = Theme.BODY_FONT,
				TextColor3 = Theme.COLORS.subtext,
				ZIndex = 8,
			})
			local cover = Theme.label(card, "", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.COLORS.panel,
				BackgroundTransparency = 1,
				TextColor3 = Theme.COLORS.text,
				ZIndex = 9,
			})
			Theme.corner(cover, 12)
			local hit = Instance.new("TextButton")
			hit.Name = "Draw"
			hit.Text = ""
			hit.BackgroundTransparency = 1
			hit.Size = UDim2.fromScale(1, 1)
			hit.ZIndex = 10
			hit.Parent = card
			hit.Activated:Connect(function()
				ClientState.DrawRequested:Fire(id)
			end)
			local entry: WordCard = { card = card, cover = cover, stroke = stroke }
			glyphCards[id] = entry
			styleWord(id, entry)
		end
	end
end

local function tickWords()
	for id, entry in glyphCards do
		local left = ClientState.cooldownLeft(id)
		if left > 0 then
			entry.cover.BackgroundTransparency = 0.2
			entry.cover.Text = if left >= 1 then tostring(math.ceil(left)) else ""
		else
			entry.cover.BackgroundTransparency = 1
			entry.cover.Text = ""
		end
	end
end

local drawBar: Frame

local function tickCooldowns()
	tickWords()
	local drawLeft = math.max(0, ClientState.drawReadyAt - os.clock())
	drawBar.Size = UDim2.new(
		0,
		HudController.cardRowWidth() * math.clamp(drawLeft / Config.DRAW_COOLDOWN, 0, 1),
		0,
		2
	)
	local state = ClientState.match
	if state.phase ~= "Idle" and state.endsAt > 0 then
		local left = math.max(0, math.ceil(state.endsAt - workspace:GetServerTimeNow()))
		local phaseText = if state.phase == "Countdown"
			then `Round {state.round} in {left}`
			elseif state.phase == "Round" then `Round {state.round}  ·  {left}s`
			elseif state.phase == "Draft" then `Pick a boost  ·  {left}s`
			elseif state.phase == "Intro" then "Starting"
			else "Match over"
		matchText.Text = phaseText
	end
end

-- The width the spell cards span on screen (the health bar matches it).
function HudController.cardRowWidth(): number
	return MAX_CARDS * CARD_SIZE + (MAX_CARDS - 1) * CARD_GAP
end

local function buildGlyphRow(root: Frame)
	glyphRow = Theme.frame(root, {
		Name = "Glyphs",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(HudController.cardRowWidth(), CARD_SIZE),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.Parent = glyphRow
	-- Thin bar under the cards that drains during the drawing cooldown.
	drawBar = Theme.frame(root, {
		Name = "DrawCooldown",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = Theme.COLORS.accent,
	})
end

-- The row of spell cards (visible where drawing is allowed).
function HudController.getGlyphRow(): Frame
	return glyphRow
end

-- Top right, plain text: coins (spent on chests) and wins (the leaderboard stat).
local function buildWallet(root: Frame)
	walletFrame = Theme.frame(root, {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(180, 28),
		BackgroundTransparency = 0.35,
	})
	Theme.corner(walletFrame, 12)
	Theme.padding(walletFrame, 6)
	coinsLabel = Theme.label(walletFrame, "0 coins", {
		Size = UDim2.fromScale(0.58, 1),
		Font = Theme.BODY_FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.COLORS.accent,
	})
	winsLabel = Theme.label(walletFrame, "0 wins", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.38, 1),
		Font = Theme.BODY_FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.COLORS.subtext,
	})
end

local shownCoins = 0
local function refreshWallet()
	local profile = ClientState.profile
	if not profile then
		return
	end
	winsLabel.Text = `{profile.stats.wins} wins`
	-- Count up/down to the new balance so earning and spending are felt.
	local from, to = shownCoins, profile.coins
	shownCoins = to
	local start = os.clock()
	task.spawn(function()
		while coinsLabel.Parent and shownCoins == to do
			local t = math.min((os.clock() - start) / 0.5, 1)
			coinsLabel.Text = `{math.floor(from + (to - from) * t + 0.5)} coins`
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
		Size = UDim2.fromOffset(360, 28),
		BackgroundTransparency = 0.35,
		Visible = false,
	})
	Theme.corner(matchBar, 12)
	matchText = Theme.label(matchBar, "", {
		Size = UDim2.new(0.42, -12, 1, -10),
		Position = UDim2.fromOffset(12, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	scoreText = Theme.label(matchBar, "", {
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.new(0.58, -12, 1, -10),
		Position = UDim2.new(1, -12, 0, 5),
		Font = Theme.BODY_FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
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
			then "#6EA0F0"
			elseif team == "Red" then "#E06868"
			else "#E8C878"
		local mine = if team == state.myTeam then " (you)" else ""
		table.insert(parts, `<font color="{color}">{team}{mine}: {wins}</font>`)
	end
	table.sort(parts)
	scoreText.Text = table.concat(parts, "   ")
	if state.phase == "Results" then
		matchText.Text = "Match over!"
	end
end

-- The top-centre stack: the match bar or Return to Hub, then the boost icons.
local function buildBattleBanner(root: Frame)
	battleLeave = Theme.button(root, "Return to Hub", {
		Name = "BattleLeave",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(120, 26),
		BackgroundColor3 = Theme.COLORS.panel,
		BackgroundTransparency = 0.35,
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
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(300, 16),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
		Visible = false,
	})
end

local function buildFeed(root: Frame)
	feedHolder = Theme.frame(root, {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 42),
		Size = UDim2.fromOffset(260, 120),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = feedHolder
end

local function addFeed(killer: string?, victim: string, spell: string?)
	local text = if killer then `{killer} defeated {victim}` else `{victim} was knocked out`
	if killer and spell then
		text = `{killer} [{spell}] {victim}`
	end
	local row =
		Theme.frame(feedHolder, { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1 })
	Theme.label(row, text, {
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	task.delay(5, function()
		row:Destroy()
	end)
end

function HudController.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SpellcraftHud"
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

	buildGlyphRow(root)
	buildWallet(root)
	buildMatchBar(root)
	buildBoosts(root)
	buildBattleBanner(root)
	buildFeed(root)

	toastHolder = Theme.frame(root, {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(360, 140),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = toastHolder

	refusalLabel = Theme.label(root, "", {
		Name = "Refusal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 18),
		Size = UDim2.fromOffset(360, 16),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.onDark,
		TextStrokeTransparency = 0.5,
		TextTransparency = 1,
	})

	Responsive.bind(scale)
	gui.Parent = player:WaitForChild("PlayerGui")
	GuiService.AutoSelectGuiEnabled = true
end

function HudController.start()
	ClientState.SpellbookChanged:Connect(refreshWords)
	ClientState.ProfileChanged:Connect(refreshWallet)
	ClientState.ProfileChanged:Connect(refreshWords)
	ClientState.MatchChanged:Connect(refreshMatch)
	player:GetAttributeChangedSignal("Boosts"):Connect(refreshBoosts)
	local function refreshBattle()
		local inside = player:GetAttribute("InBattleground") == true
		battleLeave.Visible = inside
	end
	player:GetAttributeChangedSignal("InBattleground"):Connect(refreshBattle)
	refreshBattle()
	-- The spell cards (tap to trace) only show where drawing is allowed.
	local function refreshDrawable()
		local allowed = ClientState.canDraw()
		glyphRow.Visible = allowed
		drawBar.Visible = allowed
	end
	ClientState.PresenceChanged:Connect(refreshDrawable)
	refreshDrawable()
	refreshBoosts()
	Remotes.get("Toast").OnClientEvent:Connect(HudController.toast)
	Remotes.get("Knockout").OnClientEvent:Connect(addFeed)
	refreshWords()
	RunService.Heartbeat:Connect(tickCooldowns)
end

return HudController
