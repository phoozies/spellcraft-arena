--!strict
-- The Chest Shop panel (side menu "Chests", or any chest in the hub's Chest
-- Shop): a shelf of the five chests (Common to Legendary, each shown as its
-- 3D chest tinted to its rarity, with its price), and for the picked chest its
-- odds as bars, how many of its spells you own, the pity counter, and Open.
-- Pressing Open only sends OpenChest; the server decides which spell you win
-- and its rarity (ChestService) and replies with ChestOpened, then this
-- controller spins a reel of spell cards that eases to a stop on that result,
-- ticking as each card passes the marker, and reveals the prize with its
-- rarity colour and sound while the hub chest throws its lid open.
-- Display only: coins and spells come from the server's profile summary.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Chests = require(ReplicatedStorage.Shared.Economy.Chests)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
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

local ChestController = {}

local CARD_WIDTH = 92
local CARD_GAP = 8
local CARD_STEP = CARD_WIDTH + CARD_GAP
local REEL_CARDS = 40
local WIN_INDEX = 34 -- the reel lands on this card
local PANEL_WIDTH = 700
local REEL_WIDTH = PANEL_WIDTH - 36 -- in UI offsets (before the HUD's UIScale)
local TILE_WIDTH = 124
local TILE_GAP = 10

type Tile = { button: TextButton, stroke: UIStroke, price: TextLabel }

local panel: Frame
local panelStroke: UIStroke?
local coinsLabel: TextLabel
local chestTitle: TextLabel
local oddsHolder: Frame
local infoLabel: TextLabel
local openButton: TextButton
local reelWindow: Frame
local reelStrip: Frame
local resultLabel: TextLabel
local tiles: { [string]: Tile } = {}
local selected = Chests.LIST[1].id
local spinning = false

local function setButtonEnabled(enabled: boolean)
	openButton.Active = enabled
	openButton.AutoButtonColor = enabled
	openButton.BackgroundTransparency = if enabled then 0 else 0.45
end

-- The chest in 3D inside a tile (falls back to a coloured block with a "?").
local function chestPreview(parent: GuiObject, chestId: string)
	local color = Chests.color(chestId)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(1, -12, 0, 78)
	viewport.Position = UDim2.fromOffset(6, 6)
	viewport.Ambient = Color3.fromRGB(190, 180, 220)
	viewport.LightColor = Color3.fromRGB(255, 244, 220)
	viewport.LightDirection = Vector3.new(-1, -2, -1.5)
	viewport.Active = false
	viewport.Parent = parent
	local model = ModelKit.clone("ShopChest", "effect")
	if not model then
		Theme.label(viewport, "?", { TextColor3 = color })
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and (part.Name == "Chest_Trim" or part.Name == "Chest_Gem") then
			part.Color = color
		end
	end
	model:PivotTo(CFrame.new() * CFrame.Angles(0, math.rad(200), 0))
	model.Parent = viewport
	local camera = Instance.new("Camera")
	local center, size = model:GetBoundingBox()
	local reach = math.max(size.X, size.Y, size.Z)
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(
		center.Position + Vector3.new(reach * 0.9, reach * 0.75, -reach * 1.25),
		center.Position
	)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function oddsBars(chestId: string)
	for _, child in oddsHolder:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, row in Chests.odds(chestId) do
		local color = Rarity.color(row.rarity)
		local line = Instance.new("Frame")
		line.Name = row.rarity
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, 20)
		line.LayoutOrder = index
		line.Parent = oddsHolder
		Theme.label(line, row.rarity, {
			Size = UDim2.fromOffset(92, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
		})
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.BackgroundColor3 = Theme.COLORS.outline
		track.BackgroundTransparency = 0.3
		track.BorderSizePixel = 0
		track.Position = UDim2.fromOffset(96, 4)
		track.Size = UDim2.new(1, -150, 0, 12)
		track.Parent = line
		Theme.corner(track, 12)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = track
		Theme.corner(fill, 12)
		TweenService:Create(
			fill,
			TweenInfo.new(0.35 + index * 0.05, Enum.EasingStyle.Quint),
			{ Size = UDim2.fromScale(math.max(row.percent / 100, 0.02), 1) }
		):Play()
		Theme.label(line, `{math.floor(row.percent + 0.5)}%`, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(48, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
end

local function refresh()
	local profile = ClientState.profile
	local chest = Chests.get(selected)
	if not profile or not chest or spinning then
		return
	end
	coinsLabel.Text = `🪙 {profile.coins}`
	local color = Chests.color(chest.id)
	chestTitle.Text = chest.name
	chestTitle.TextColor3 = color
	for id, tile in tiles do
		local def = Chests.get(id) :: Types.ChestDef
		local isSelected = id == selected
		tile.stroke.Color = if isSelected then Theme.COLORS.accent else Chests.color(id)
		tile.stroke.Thickness = if isSelected then 4 else 2
		tile.button.BackgroundColor3 = if isSelected
			then Theme.COLORS.panelLight
			else Theme.COLORS.panel
		tile.price.TextColor3 = if profile.coins >= def.price
			then Theme.COLORS.heading
			else Theme.COLORS.bad
	end

	local pool = Chests.pool(chest.id)
	local owned = 0
	for _, id in pool do
		if table.find(profile.spells, id) then
			owned += 1
		end
	end
	local lines = { `You own {owned}/{#pool} of its spells.` }
	if chest.noDuplicates then
		table.insert(lines, "Always a spell you don't have yet!")
	elseif Rarity.rank(chest.minRarity) < Rarity.rank(Chests.PITY.RARITY) then
		local untilPity = Chests.spinsToPity(profile.pity)
		table.insert(
			lines,
			if untilPity <= 1
				then `Your next chest is guaranteed {Chests.PITY.RARITY} or better!`
				else `{Chests.PITY.RARITY} or better guaranteed within {untilPity} chests.`
		)
	end
	infoLabel.Text = table.concat(lines, "\n")

	if #profile.elements == 0 then
		openButton.Text = "Pick an element first"
		openButton.BackgroundColor3 = Theme.COLORS.grey
	elseif Chests.ownsAll(profile.spells, chest.id) then
		openButton.Text = "You own all of these!"
		openButton.BackgroundColor3 = Theme.COLORS.grey
	elseif profile.coins >= chest.price then
		openButton.Text = `Open for {chest.price}`
		openButton.BackgroundColor3 = color
	else
		openButton.Text = `Need {chest.price - profile.coins} more coins`
		openButton.BackgroundColor3 = Theme.COLORS.grey
	end
end

local function selectChest(chestId: string)
	if spinning or not Chests.get(chestId) then
		return
	end
	selected = chestId
	oddsBars(chestId)
	refresh()
end

-- A random reel card from the chest's own odds, so the reel looks as stingy
-- as the chest really is.
local function randomSpell(rng: Random, chestId: string): string
	local rows = Chests.odds(chestId)
	local pick = rng:NextNumber(0, 100)
	local rarity = rows[#rows].rarity
	local sum = 0
	for _, row in rows do
		sum += row.percent
		if pick < sum then
			rarity = row.rarity
			break
		end
	end
	local list = Chests.ofRarity(rarity)
	if #list == 0 then
		list = Chests.pool(chestId)
	end
	return list[rng:NextInteger(1, #list)]
end

local function reveal(result: Types.ChestResult)
	local def = SpellDefinitions.get(result.spell)
	local color = Rarity.color(result.rarity)
	resultLabel.TextColor3 = color
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
			then "chestLegendary"
			elseif result.rarity == "Epic" then "chestEpic"
			else "chestReveal"
	)
	-- The panel's outline flashes in the prize's colour.
	if panelStroke then
		local stroke = panelStroke
		stroke.Color = color
		stroke.Thickness = 8
		TweenService:Create(stroke, TweenInfo.new(1.2), { Thickness = 2, Color = Theme.COLORS.rim })
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

local function spin(result: Types.ChestResult)
	local chest = Chests.get(result.chest)
	if not chest then
		return
	end
	selectChest(chest.id)
	MenuController.open("Chests")
	spinning = true
	setButtonEnabled(false)
	resultLabel.Text = `Opening a {chest.name}…`
	resultLabel.TextColor3 = Theme.COLORS.text

	-- Fill the reel with random spells, the result at WIN_INDEX.
	for _, child in reelStrip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local rng = Random.new()
	for i = 1, REEL_CARDS do
		local id = if i == WIN_INDEX then result.spell else randomSpell(rng, chest.id)
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
	local spinTime = Chests.SPIN_TIME - 0.4
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

	task.delay(Chests.SPIN_TIME - 0.3, function()
		reveal(result)
		task.wait(0.3)
		spinning = false
		setButtonEnabled(true)
		refresh()
	end)
end

local function buildTile(shelf: Frame, chest: Types.ChestDef, index: number)
	local color = Chests.color(chest.id)
	local button = Theme.button(shelf, "", {
		Name = chest.id,
		Size = UDim2.fromOffset(TILE_WIDTH, 140),
		LayoutOrder = index,
		BackgroundColor3 = Theme.COLORS.panel,
	})
	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = color
	chestPreview(button, chest.id)
	Theme.label(button, chest.name, {
		Name = "ChestName",
		Position = UDim2.fromOffset(4, 86),
		Size = UDim2.new(1, -8, 0, 22),
		TextColor3 = color,
	})
	local price = Theme.label(button, `🪙 {chest.price}`, {
		Name = "Price",
		Position = UDim2.fromOffset(4, 110),
		Size = UDim2.new(1, -8, 0, 22),
		TextColor3 = Theme.COLORS.heading,
	})
	button.Activated:Connect(function()
		selectChest(chest.id)
	end)
	tiles[chest.id] = { button = button, stroke = stroke, price = price }
end

local function build()
	panel = MenuController.createPanel("Chests", "Chest Shop")
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 600)
	panelStroke = panel:FindFirstChildOfClass("UIStroke")

	coinsLabel = Theme.pill(panel, "🪙 0", Theme.COLORS.accent, {
		Name = "Coins",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -76, 0, 16),
		Size = UDim2.fromOffset(140, 32),
	})

	-- The shelf: one tile per chest.
	local shelf = Instance.new("Frame")
	shelf.Name = "Shelf"
	shelf.BackgroundTransparency = 1
	shelf.Position = UDim2.fromOffset(18, 66)
	shelf.Size = UDim2.new(1, -36, 0, 148)
	shelf.Parent = panel
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, TILE_GAP)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = shelf
	for index, chest in Chests.LIST do
		buildTile(shelf, chest, index)
	end

	-- The picked chest: name, odds, ownership and pity, Open.
	local detail = Theme.frame(panel, {
		Name = "Detail",
		Position = UDim2.fromOffset(18, 224),
		Size = UDim2.new(1, -36, 0, 190),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(detail, 14)
	Theme.stroke(detail, Theme.COLORS.rim, 1)
	chestTitle = Theme.label(detail, "", {
		Name = "ChestTitle",
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(0.5, -14, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	oddsHolder = Instance.new("Frame")
	oddsHolder.Name = "Odds"
	oddsHolder.BackgroundTransparency = 1
	oddsHolder.Position = UDim2.fromOffset(14, 44)
	oddsHolder.Size = UDim2.new(0.5, -14, 1, -54)
	oddsHolder.Parent = detail
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = oddsHolder
	infoLabel = Theme.label(detail, "", {
		Name = "Info",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.new(0.5, -20, 0, 80),
		Font = Theme.BODY_FONT,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.COLORS.subtext,
	})
	openButton = Theme.button(detail, "Open", {
		Name = "OpenButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		Size = UDim2.new(0.5, -20, 0, Theme.TOUCH + 6),
		BackgroundColor3 = Theme.COLORS.accent,
	})
	openButton.Activated:Connect(function()
		if not spinning then
			Remotes.get("OpenChest"):FireServer(selected)
		end
	end)

	-- The reel: a clipped window with a strip of cards and a center marker.
	reelWindow = Theme.frame(panel, {
		Name = "Reel",
		Position = UDim2.fromOffset(18, 424),
		Size = UDim2.fromOffset(REEL_WIDTH, 116),
		BackgroundColor3 = Color3.fromRGB(14, 12, 30),
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

	resultLabel =
		Theme.label(panel, "Win matches to earn coins, then open chests for new spells!", {
			Name = "Result",
			Position = UDim2.new(0, 18, 1, -56),
			Size = UDim2.new(1, -36, 0, 44),
			Font = Theme.BODY_FONT,
			TextColor3 = Theme.COLORS.subtext,
		})
	oddsBars(selected)
end

-- The Open button (the tutorial points at it).
function ChestController.spinButton(): TextButton
	return openButton
end

-- True while the reel is spinning (the tutorial waits for it to stop).
function ChestController.isSpinning(): boolean
	return spinning
end

function ChestController.init()
	build()
end

function ChestController.start()
	ClientState.ProfileChanged:Connect(refresh)
	refresh()
	Remotes.get("ChestOpened").OnClientEvent:Connect(function(result: Types.ChestResult)
		-- The hub chest throws its lid open while the reel spins.
		PropSwap.show(
			`ChestModel_{result.chest}`,
			"ShopChestOpen",
			Chests.SPIN_TIME + 2,
			Chests.color(result.chest)
		)
		spin(result)
	end)
	-- A chest's prompt in the hub opens the shop on that chest.
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local chestId = prompt:GetAttribute("ChestId")
		if prompt.Name == "Chests" and typeof(chestId) == "string" then
			selectChest(chestId)
		end
	end)
end

return ChestController
