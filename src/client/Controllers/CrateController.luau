--!strict
-- The Crate Shop panel (side menu "Crates", or the crate in the hub): the
-- Spell Crate (price, the chance of each rarity, Open), your coin balance, and
-- the gacha reel. Pressing Open only sends OpenCrate; the server decides which
-- spell you win and its rarity (CrateService) and replies with CrateOpened,
-- then this controller spins a reel of spell cards that eases to a stop on
-- that result, ticking as each card passes the marker, and reveals the prize
-- with its rarity colour and sound.
-- Display only: coins and spells come from the server's profile summary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Crates = require(ReplicatedStorage.Shared.Economy.Crates)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local SpellStats = require(ReplicatedStorage.Shared.Spells.SpellStats)
local Types = require(ReplicatedStorage.Shared.Types)
local SpellCard = require(script.Parent.Parent.UI.SpellCard)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)
local ClientState = require(script.Parent.ClientState)
local PropSwap = require(script.Parent.Parent.Fx.PropSwap)
local MenuController = require(script.Parent.MenuController)

local CrateController = {}

local CARD_WIDTH = 92
local CARD_GAP = 8
local CARD_STEP = CARD_WIDTH + CARD_GAP
local REEL_CARDS = 40
local WIN_INDEX = 34 -- the reel lands on this card
local PANEL_WIDTH = 600
local REEL_WIDTH = PANEL_WIDTH - 32 -- in UI offsets (before the HUD's UIScale)

local panel: Frame
local panelStroke: UIStroke?
local coinsLabel: TextLabel
local infoLabel: TextLabel
local openButton: TextButton
local reelWindow: Frame
local reelStrip: Frame
local resultLabel: TextLabel
local spinning = false

local function setButtonEnabled(enabled: boolean)
	openButton.Active = enabled
	openButton.AutoButtonColor = enabled
	openButton.BackgroundTransparency = if enabled then 0 else 0.5
end

local function oddsText(): string
	local parts = {}
	for _, row in Crates.odds() do
		local color = Rarity.color(row.rarity)
		table.insert(
			parts,
			`<font color="#{color:ToHex()}">●</font> <b>{row.rarity} {math.floor(
				row.percent + 0.5
			)}%</b>`
		)
	end
	return table.concat(parts, "   ")
end

local function refresh()
	local profile = ClientState.profile
	if not profile or spinning then
		return
	end
	local crate = Crates.LIST[1]
	coinsLabel.Text = `{profile.coins} coins`
	local untilPity = Crates.spinsToPity(profile.pity)
	infoLabel.Text = `Spells you have: {#profile.spells}/{#Crates.pool()}\n{if untilPity <= 1
		then `Your next spin is guaranteed {Crates.PITY.RARITY} or better!`
		else `Guaranteed {Crates.PITY.RARITY} or better within {untilPity} spins`}`
	if #profile.elements == 0 then
		openButton.Text = "Pick an element first"
	elseif Crates.ownsAll(profile.spells) then
		openButton.Text = "You own every spell!"
	elseif profile.coins >= crate.price then
		openButton.Text = `Spin!  ({crate.price})`
	else
		openButton.Text = `Need {crate.price - profile.coins} more coins`
	end
end

-- A random reel card: a rarity by the real odds, then a spell of it, so the
-- reel looks as stingy as the crate really is.
local function randomSpell(rng: Random): string
	local list = Crates.ofRarity(Rarity.roll(rng))
	if #list == 0 then
		list = Crates.pool()
	end
	return list[rng:NextInteger(1, #list)]
end

local function reveal(result: Types.CrateResult)
	local def = SpellDefinitions.get(result.spell)
	local color = Rarity.color(result.rarity)
	resultLabel.TextColor3 = Theme.COLORS.text
	local name = if def then def.name else result.spell
	resultLabel.Text = if result.duplicate
		then `Duplicate {name}! +{result.refund} coins back.`
		elseif
			result.equipped
		then `NEW {string.upper(result.rarity)}: {name}! Equipped in your loadout.`
		else `NEW {string.upper(result.rarity)}: {name}! Equip it in the Spellbook.`
	if def then
		-- The spell's numbers (damage, cooldown, duration, ...) under the headline.
		resultLabel.Text ..= `\n{SpellStats.text(def)}`
	end
	AudioController.play(
		if result.rarity == "Legendary"
			then "crateLegendary"
			elseif result.rarity == "Epic" then "crateEpic"
			else "crateReveal"
	)
	-- The panel's outline flashes in the prize's colour.
	if panelStroke then
		local stroke = panelStroke
		stroke.Color = color
		stroke.Thickness = 8
		TweenService
			:Create(stroke, TweenInfo.new(1.2), { Thickness = 3, Color = Theme.COLORS.accent })
			:Play()
	end
	local winner = reelStrip:FindFirstChild(`Card{WIN_INDEX}`)
	if winner and winner:IsA("GuiObject") then
		local pop = Instance.new("UIScale")
		pop.Parent = winner
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1.15 })
			:Play()
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
	resultLabel.Text = `Spinning a {crate.name}…`
	resultLabel.TextColor3 = Theme.COLORS.text

	-- Fill the reel with random spells, the result at WIN_INDEX.
	for _, child in reelStrip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local rng = Random.new()
	for i = 1, REEL_CARDS do
		local id = if i == WIN_INDEX then result.spell else randomSpell(rng)
		local card = SpellCard.create(reelStrip, id, { size = UDim2.new(0, CARD_WIDTH, 1, -12) })
		card.Name = `Card{i}`
		card.Position = UDim2.new(0, (i - 1) * CARD_STEP, 0, 6)
		card.Active = false
	end
	reelWindow.Visible = true

	-- Land the winning card under the center marker, a little off-center so
	-- it doesn't look canned.
	local cardCenter = (WIN_INDEX - 1) * CARD_STEP + CARD_WIDTH / 2
	local jitter = rng:NextNumber(-CARD_WIDTH * 0.3, CARD_WIDTH * 0.3)
	local finalX = REEL_WIDTH / 2 - cardCenter + jitter
	reelStrip.Position = UDim2.fromOffset(0, 0)
	local spinTime = Crates.SPIN_TIME - 0.4
	TweenService:Create(
		reelStrip,
		TweenInfo.new(spinTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(finalX, 0) }
	):Play()

	-- A tick each time a card passes the marker.
	task.spawn(function()
		local startedAt = os.clock()
		local lastIndex = 0
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function()
			if os.clock() - startedAt > spinTime then
				connection:Disconnect()
				return
			end
			local under = math.floor((REEL_WIDTH / 2 - reelStrip.Position.X.Offset) / CARD_STEP)
			if under ~= lastIndex then
				lastIndex = under
				AudioController.play("reelTick")
			end
		end)
	end)

	task.delay(Crates.SPIN_TIME - 0.3, function()
		reveal(result)
		task.wait(0.3)
		spinning = false
		setButtonEnabled(true)
		refresh()
	end)
end

local function build()
	panel = MenuController.createPanel("Crates", "Spell Crate")
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 500)
	panelStroke = panel:FindFirstChildOfClass("UIStroke")
	local crate = Crates.LIST[1]

	coinsLabel = Theme.label(panel, "0 coins", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -76, 0, 14),
		Size = UDim2.fromOffset(200, 34),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.COLORS.heading,
	})

	local card = Theme.frame(panel, {
		Name = crate.id,
		Position = UDim2.fromOffset(16, 60),
		Size = UDim2.new(1, -32, 0, 240),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(card, 12)
	Theme.stroke(card, Theme.COLORS.accent, 3)
	Theme.label(card, `{crate.name}`, {
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.fromOffset(8, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.heading,
	})
	Theme.label(
		card,
		"Spin for a random spell! Rarer spells are stronger or stranger. Equip two of them beside your element's base spells in the Spellbook's Loadout tab.",
		{
			Size = UDim2.new(1, -16, 0, 60),
			Position = UDim2.fromOffset(8, 44),
			Font = Theme.BODY_FONT,
			TextWrapped = true,
			TextScaled = false,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Theme.COLORS.text,
		}
	)
	Theme.label(card, oddsText(), {
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 108),
		Font = Theme.BODY_FONT,
		TextScaled = false,
		TextSize = 15,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	infoLabel = Theme.label(card, "", {
		TextWrapped = true,
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.fromOffset(8, 138),
		Font = Theme.BODY_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.subtext,
	})
	openButton = Theme.button(card, "Spin!", {
		Name = "OpenButton",
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
		Position = UDim2.fromOffset(16, 312),
		Size = UDim2.fromOffset(REEL_WIDTH, 116),
		BackgroundColor3 = Color3.fromRGB(20, 20, 40),
		ClipsDescendants = true,
		Visible = false,
	})
	Theme.corner(reelWindow, 12)
	reelStrip = Theme.frame(reelWindow, {
		Name = "Strip",
		Size = UDim2.new(0, REEL_CARDS * CARD_STEP, 1, 0),
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

	resultLabel = Theme.label(panel, "Win matches to earn coins, then spin for new spells!", {
		Position = UDim2.new(0, 16, 1, -58),
		Size = UDim2.new(1, -32, 0, 44),
		Font = Theme.BODY_FONT,
		TextColor3 = Theme.COLORS.subtext,
	})
end

-- The Spin button (the tutorial points at it).
function CrateController.spinButton(): TextButton
	return openButton
end

-- True while the reel is spinning (the tutorial waits for it to stop).
function CrateController.isSpinning(): boolean
	return spinning
end

function CrateController.init()
	build()
end

function CrateController.start()
	ClientState.ProfileChanged:Connect(refresh)
	refresh()
	Remotes.get("CrateOpened").OnClientEvent:Connect(function(result)
		-- The shop crate in the hub throws its lid open while the reel spins.
		PropSwap.show("CrateModel_Spell", "ElementCrateOpen", Crates.SPIN_TIME + 2)
		spin(result)
	end)
end

return CrateController
