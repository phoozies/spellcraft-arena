--!strict
-- The Crate Shop panel (side menu "Crates", or any crate's prompt in the hub):
-- one card per crate (rarity, price, odds, Open), your coin balance, and the
-- spin reel. Pressing Open only sends OpenCrate; the server decides the
-- spell (CrateService) and replies with CrateOpened, then this controller
-- spins a reel of spell cards that eases to a stop on that result.
-- Display only: coins and unlocks come from the server's profile summary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Crates = require(ReplicatedStorage.Shared.Economy.Crates)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)
local ClientState = require(script.Parent.ClientState)
local MenuController = require(script.Parent.MenuController)

local CrateController = {}

local CARD_WIDTH = 92
local CARD_GAP = 8
local REEL_CARDS = 40
local WIN_INDEX = 34 -- the reel lands on this card
local PANEL_WIDTH = 600
local REEL_WIDTH = PANEL_WIDTH - 32 -- in UI offsets (before the HUD's UIScale)

local panel: Frame
local coinsLabel: TextLabel
local openButtons: { [string]: TextButton } = {}
local reelWindow: Frame
local reelStrip: Frame
local resultLabel: TextLabel
local spinning = false

local function spellCard(parent: Instance, spellId: string, order: number): Frame
	local def = SpellDefinitions.get(spellId)
	local info = Rarity.INFO[if def then def.rarity else "Common"]
	local card = Theme.frame(parent, {
		Name = `Card{order}`,
		Size = UDim2.new(0, CARD_WIDTH, 1, -12),
		Position = UDim2.new(0, (order - 1) * (CARD_WIDTH + CARD_GAP), 0, 6),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(card, 10)
	Theme.stroke(card, info.color, 3)
	Theme.label(card, info.glyph, {
		Size = UDim2.new(1, 0, 0.45, 0),
		TextColor3 = info.color,
	})
	Theme.label(card, if def then def.name else spellId, {
		Size = UDim2.new(1, -8, 0.35, 0),
		Position = UDim2.new(0, 4, 0.48, 0),
	})
	Theme.label(card, info.name, {
		Size = UDim2.new(1, -8, 0.15, 0),
		Position = UDim2.new(0, 4, 0.82, 0),
		TextColor3 = info.color,
		Font = Theme.BODY_FONT,
	})
	return card
end

local function oddsText(crate: Types.CrateDef): string
	local lines = {}
	for _, name in Rarity.ORDER do
		local weight = crate.odds[name]
		if weight and weight > 0 then
			table.insert(lines, `{Rarity.INFO[name].glyph} {name} {weight}%`)
		end
	end
	return table.concat(lines, "\n")
end

local function setButtonsEnabled(enabled: boolean)
	for _, button in openButtons do
		button.Active = enabled
		button.AutoButtonColor = enabled
		button.BackgroundTransparency = if enabled then 0 else 0.5
	end
end

local function refreshCoins()
	local profile = ClientState.profile
	if not profile or spinning then
		return
	end
	coinsLabel.Text = `💰 {profile.coins} coins`
	for id, button in openButtons do
		local crate = Crates.get(id)
		button.Text = if crate and profile.coins >= crate.price then "Open" else "Need coins"
	end
end

local function spin(result: Types.CrateResult)
	local crate = Crates.get(result.crate)
	if not crate then
		return
	end
	MenuController.open("Crates")
	spinning = true
	setButtonsEnabled(false)
	resultLabel.Text = `Spinning a {crate.id} crate…`
	resultLabel.TextColor3 = Theme.COLORS.text

	-- Fill the reel with random possible drops, the result at WIN_INDEX.
	for _, child in reelStrip:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local pool = Crates.possibleDrops(crate)
	local rng = Random.new()
	for i = 1, REEL_CARDS do
		local id = if i == WIN_INDEX then result.spellId else pool[rng:NextInteger(1, #pool)]
		spellCard(reelStrip, id, i)
	end
	reelWindow.Visible = true

	-- Land the winning card under the center marker, a little off-center so
	-- it doesn't look canned.
	local cardCenter = (WIN_INDEX - 1) * (CARD_WIDTH + CARD_GAP) + CARD_WIDTH / 2
	local jitter = rng:NextNumber(-CARD_WIDTH * 0.3, CARD_WIDTH * 0.3)
	local finalX = REEL_WIDTH / 2 - cardCenter + jitter
	reelStrip.Position = UDim2.fromOffset(0, 0)
	TweenService:Create(
		reelStrip,
		TweenInfo.new(Crates.SPIN_TIME - 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(finalX, 0) }
	):Play()

	task.delay(Crates.SPIN_TIME - 0.3, function()
		local def = SpellDefinitions.get(result.spellId)
		local info = Rarity.INFO[result.rarity]
		local name = if def then def.name else result.spellId
		resultLabel.TextColor3 = info.color
		resultLabel.Text = if result.duplicate
			then `{info.glyph} {name} (duplicate): +{result.refund} coins back`
			else `{info.glyph} NEW SPELL: {name}! Draw its shape to cast it.`
		AudioController.play("crateReveal")
		local winner = reelStrip:FindFirstChild(`Card{WIN_INDEX}`)
		if winner and winner:IsA("Frame") then
			local pop = Instance.new("UIScale")
			pop.Parent = winner
			TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1.12 }):Play()
		end
		task.wait(0.3)
		spinning = false
		setButtonsEnabled(true)
		refreshCoins()
	end)
end

local function build()
	panel = MenuController.createPanel("Crates", "Crate Shop")
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 430)

	coinsLabel = Theme.label(panel, "💰 0 coins", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -76, 0, 14),
		Size = UDim2.fromOffset(200, 34),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.COLORS.accent,
	})

	local row = Theme.frame(panel, {
		Name = "Crates",
		Position = UDim2.fromOffset(16, 60),
		Size = UDim2.new(1, -32, 0, 200),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	for index, crate in Crates.LIST do
		local info = Rarity.INFO[crate.id]
		local card = Theme.frame(row, {
			Name = crate.id,
			LayoutOrder = index,
			Size = UDim2.new(0.2, -7, 1, 0),
			BackgroundColor3 = Theme.COLORS.panelLight,
		})
		Theme.corner(card, 12)
		Theme.stroke(card, info.color, 3)
		Theme.label(card, `{info.glyph} {crate.id}`, {
			Size = UDim2.new(1, -8, 0, 28),
			Position = UDim2.fromOffset(4, 6),
			TextColor3 = info.color,
		})
		Theme.label(card, `💰 {crate.price}`, {
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.fromOffset(4, 36),
			TextColor3 = Theme.COLORS.accent,
		})
		Theme.label(card, oddsText(crate), {
			Size = UDim2.new(1, -8, 0, 60),
			Position = UDim2.fromOffset(4, 64),
			Font = Theme.BODY_FONT,
			TextColor3 = Theme.COLORS.subtext,
		})
		local open = Theme.button(card, "Open", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, Theme.TOUCH),
			BackgroundColor3 = Theme.COLORS.good,
		})
		open.Activated:Connect(function()
			if not spinning then
				Remotes.get("OpenCrate"):FireServer(crate.id)
			end
		end)
		openButtons[crate.id] = open
	end

	-- The reel: a clipped window with a strip of cards and a center marker.
	reelWindow = Theme.frame(panel, {
		Name = "Reel",
		Position = UDim2.fromOffset(16, 272),
		Size = UDim2.fromOffset(REEL_WIDTH, 104),
		BackgroundColor3 = Color3.fromRGB(20, 20, 40),
		ClipsDescendants = true,
		Visible = false,
	})
	Theme.corner(reelWindow, 12)
	reelStrip = Theme.frame(reelWindow, {
		Name = "Strip",
		Size = UDim2.new(0, REEL_CARDS * (CARD_WIDTH + CARD_GAP), 1, 0),
		BackgroundTransparency = 1,
	})
	Theme.frame(reelWindow, {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = Theme.COLORS.accent,
		ZIndex = 20,
	})

	resultLabel = Theme.label(panel, "Win matches to earn coins. Every crate unlocks a spell!", {
		Position = UDim2.new(0, 16, 1, -48),
		Size = UDim2.new(1, -32, 0, 36),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
	})
end

function CrateController.init()
	build()
end

function CrateController.start()
	ClientState.ProfileChanged:Connect(refreshCoins)
	refreshCoins()
	Remotes.get("CrateOpened").OnClientEvent:Connect(spin)
end

return CrateController
