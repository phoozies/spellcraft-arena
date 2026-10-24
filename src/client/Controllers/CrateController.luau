--!strict
-- The Crate Shop panel (side menu "Crates", or the crate in the hub): the
-- Element Crate (price, what it does, Open), your coin balance, the elements
-- you already own, and the spin reel. Pressing Open only sends OpenCrate;
-- the server decides which element you win (CrateService) and replies with
-- CrateOpened, then this controller spins a reel of element cards that eases
-- to a stop on that result.
-- Display only: coins and unlocks come from the server's profile summary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Crates = require(ReplicatedStorage.Shared.Economy.Crates)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
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
local ownedLabel: TextLabel
local openButton: TextButton
local reelWindow: Frame
local reelStrip: Frame
local resultLabel: TextLabel
local spinning = false

local function elementCard(parent: Instance, elementId: string, order: number): Frame
	local element = Elements.get(elementId)
	local color = if element then element.color else Theme.COLORS.subtext
	local card = Theme.frame(parent, {
		Name = `Card{order}`,
		Size = UDim2.new(0, CARD_WIDTH, 1, -12),
		Position = UDim2.new(0, (order - 1) * (CARD_WIDTH + CARD_GAP), 0, 6),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(card, 10)
	Theme.stroke(card, color, 3)
	Theme.label(card, if element then element.icon else "?", {
		Size = UDim2.new(1, 0, 0.55, 0),
		TextColor3 = color,
	})
	Theme.label(card, elementId, {
		Size = UDim2.new(1, -8, 0.3, 0),
		Position = UDim2.new(0, 4, 0.62, 0),
		TextColor3 = color,
	})
	return card
end

local function setButtonEnabled(enabled: boolean)
	openButton.Active = enabled
	openButton.AutoButtonColor = enabled
	openButton.BackgroundTransparency = if enabled then 0 else 0.5
end

local function refresh()
	local profile = ClientState.profile
	if not profile or spinning then
		return
	end
	local crate = Crates.LIST[1]
	coinsLabel.Text = `💰 {profile.coins} coins`
	local owned = {}
	for _, id in profile.elements do
		local element = Elements.get(id)
		table.insert(owned, if element then `{element.icon} {id}` else id)
	end
	ownedLabel.Text = if #owned > 0
		then `Your elements: {table.concat(owned, "  ")}`
		else "Pick your first element in the Spellbook, then open crates to unlock more."
	local missing = #Crates.unowned(profile.elements)
	if #profile.elements == 0 then
		openButton.Text = "Pick an element first"
	elseif missing == 0 then
		openButton.Text = "You own every element!"
	elseif profile.coins >= crate.price then
		openButton.Text = `Open  (💰 {crate.price})`
	else
		openButton.Text = `Need {crate.price - profile.coins} more coins`
	end
end

local function spin(result: Types.CrateResult)
	local crate = Crates.get(result.crate)
	if not crate then
		return
	end
	MenuController.open("Crates")
	spinning = true
	setButtonEnabled(false)
	resultLabel.Text = `Spinning an {crate.name}…`
	resultLabel.TextColor3 = Theme.COLORS.text

	-- Fill the reel with random elements, the result at WIN_INDEX.
	for _, child in reelStrip:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local ids = Elements.ids()
	local rng = Random.new()
	for i = 1, REEL_CARDS do
		local id = if i == WIN_INDEX then result.element else ids[rng:NextInteger(1, #ids)]
		elementCard(reelStrip, id, i)
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
		local element = Elements.get(result.element)
		resultLabel.TextColor3 = if element then element.color else Theme.COLORS.accent
		resultLabel.Text = `{if element then element.icon else ""} NEW ELEMENT: {result.element}! Equip it in the Spellbook.`
		AudioController.play("crateReveal")
		local winner = reelStrip:FindFirstChild(`Card{WIN_INDEX}`)
		if winner and winner:IsA("Frame") then
			local pop = Instance.new("UIScale")
			pop.Parent = winner
			TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1.12 }):Play()
		end
		task.wait(0.3)
		spinning = false
		setButtonEnabled(true)
		refresh()
	end)
end

local function build()
	panel = MenuController.createPanel("Crates", "Crate Shop")
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 430)
	local crate = Crates.LIST[1]

	coinsLabel = Theme.label(panel, "💰 0 coins", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -76, 0, 14),
		Size = UDim2.fromOffset(200, 34),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.COLORS.accent,
	})

	local card = Theme.frame(panel, {
		Name = crate.id,
		Position = UDim2.fromOffset(16, 60),
		Size = UDim2.new(1, -32, 0, 190),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(card, 12)
	Theme.stroke(card, Theme.COLORS.accent, 3)
	Theme.label(card, `🎁 {crate.name}`, {
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.fromOffset(8, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.accent,
	})
	Theme.label(card, "Unlocks a brand new element and its five spells. You always win one you don't own yet.", {
		Size = UDim2.new(1, -16, 0, 44),
		Position = UDim2.fromOffset(8, 46),
		Font = Theme.BODY_FONT,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.COLORS.text,
	})
	ownedLabel = Theme.label(card, "", {
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 96),
		Font = Theme.BODY_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.subtext,
	})
	openButton = Theme.button(card, "Open", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, Theme.TOUCH),
		BackgroundColor3 = Theme.COLORS.good,
	})
	openButton.Activated:Connect(function()
		if not spinning then
			Remotes.get("OpenCrate"):FireServer(crate.id)
		end
	end)

	-- The reel: a clipped window with a strip of cards and a center marker.
	reelWindow = Theme.frame(panel, {
		Name = "Reel",
		Position = UDim2.fromOffset(16, 262),
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

	resultLabel = Theme.label(panel, "Win matches to earn coins, then unlock new elements!", {
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
	ClientState.ProfileChanged:Connect(refresh)
	refresh()
	Remotes.get("CrateOpened").OnClientEvent:Connect(spin)
end

return CrateController
