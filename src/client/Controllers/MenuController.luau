--!strict
-- Side menu + panels: Play (queues), Spellbook (Elements tab: pick your first
-- element free, buy others with coins, equip any you own, see each one's three
-- base spells; Loadout tab: the two extra slots and your crate-spell
-- collection), Crates (built by CrateController through createPanel), and
-- Daily Quests. Hub kiosks open the matching panel through ProximityPrompts
-- ("Spellbook", "Crates", "Quests").

local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Glyphs = require(ReplicatedStorage.Shared.Spells.Glyphs)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Loadout = require(ReplicatedStorage.Shared.Spells.Loadout)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local SpellStats = require(ReplicatedStorage.Shared.Spells.SpellStats)
local GlyphView = require(ReplicatedStorage.Shared.UI.GlyphView)
local Types = require(ReplicatedStorage.Shared.Types)
local SpellCard = require(script.Parent.Parent.UI.SpellCard)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)
local ClientState = require(script.Parent.ClientState)
local HudController = require(script.Parent.HudController)
local PropSwap = require(script.Parent.Parent.Fx.PropSwap)

local MenuController = {}

local panels: { [string]: Frame } = {}
local openName: string? = nil
local modeButtons: { [string]: TextButton } = {}
local elementList: Frame
local elementButtons: { [string]: TextButton } = {}
local spellRow: Frame
local headerLabel: TextLabel
local equipButton: TextButton
local detailLabel: TextLabel
local detailGlyph: Frame
local selectedElement = "Fire"
local askedFirstPick = false
local questList: Frame
local sideButtons: { [string]: TextButton } = {}
-- Spellbook tabs and the Loadout tab's widgets.
local bookTab = "Elements"
local tabButtons: { [string]: TextButton } = {}
local elementsPage: Frame
local loadoutPage: Frame
local loadoutHeader: TextLabel
local loadoutRow: Frame
local loadoutCount: TextLabel
local collection: ScrollingFrame
local loadoutDetail: TextLabel
local loadoutButton: TextButton
local selectedSpell: string? = nil -- crate spell tapped in the Loadout tab
local selectedSlot: number? = nil -- extra slot tapped (1..2)
local targetSlot: (profile: ClientState.ProfileSummary) -> number
local setLoadoutDetail: (spellId: string?, profile: ClientState.ProfileSummary) -> ()

local MODE_INFO = {
	{ mode = "1v1", text = "Duel" },
	{ mode = "2v2", text = "Duos" },
	{ mode = "3v3", text = "Trios" },
	{ mode = "4v4", text = "Squads" },
}

local function makePanel(root: Instance, name: string, title: string): Frame
	local panel = Theme.frame(root, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(560, 400),
		Visible = false,
		ZIndex = 10,
	})
	Theme.corner(panel, 18)
	Theme.stroke(panel, Theme.COLORS.accent, 3)
	Theme.label(panel, title, {
		Size = UDim2.new(1, -80, 0, 44),
		Position = UDim2.fromOffset(16, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.heading,
	})
	local close = Theme.button(panel, "X", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(Theme.TOUCH, Theme.TOUCH),
		BackgroundColor3 = Theme.COLORS.bad,
	})
	close.Activated:Connect(function()
		MenuController.close()
	end)
	panels[name] = panel
	return panel
end

function MenuController.open(name: string)
	for key, panel in panels do
		panel.Visible = key == name
	end
	openName = name
	local panel = panels[name]
	if panel and GuiService:IsTenFootInterface() then
		local first = panel:FindFirstChildWhichIsA("TextButton", true)
		GuiService.SelectedObject = first
	end
end

function MenuController.close()
	for _, panel in panels do
		panel.Visible = false
	end
	openName = nil
	GuiService.SelectedObject = nil
end

function MenuController.toggle(name: string)
	if openName == name then
		MenuController.close()
	else
		MenuController.open(name)
	end
end

local function buildPlay(root: Instance)
	local panel = makePanel(root, "Play", "Play")
	local grid = Theme.frame(panel, {
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 1, -140),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -8, 0.5, -8) -- 4 modes: 2 columns, 2 rows
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.Parent = grid
	for _, info in MODE_INFO do
		local button = Theme.button(grid, `{info.mode}\n{info.text}`, { Name = info.mode })
		button.Activated:Connect(function()
			Remotes.get("SetQueue"):FireServer(info.mode)
			MenuController.close()
		end)
		modeButtons[info.mode] = button
	end
	local leave = Theme.button(panel, "Leave queue", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(220, Theme.TOUCH),
		BackgroundColor3 = Theme.COLORS.bad,
	})
	leave.Activated:Connect(function()
		Remotes.get("SetQueue"):FireServer(nil)
	end)
end

local function refreshPlay()
	for _, info in MODE_INFO do
		local button = modeButtons[info.mode]
		if button then
			local waiting = ClientState.queueCounts[info.mode] or 0
			button.Text = `{info.mode}  ·  {info.text}\n{waiting} waiting`
		end
	end
end

local function selectElement(id: string)
	selectedElement = id
	MenuController.refreshSpellbook()
end

local function setTab(tab: string)
	bookTab = tab
	MenuController.refreshSpellbook()
end

local function buildSpellbook(root: Instance)
	local panel = makePanel(root, "Spellbook", "Spellbook")
	panel.Size = UDim2.fromOffset(720, 500)

	-- Tabs next to the title.
	for index, tab in { "Elements", "Loadout" } do
		local button = Theme.button(panel, tab, {
			Name = `Tab{tab}`,
			Position = UDim2.fromOffset(180 + (index - 1) * 150, 12),
			Size = UDim2.fromOffset(140, 40),
		})
		button.Activated:Connect(function()
			setTab(tab)
		end)
		tabButtons[tab] = button
	end

	----------------------------------------------------------------------
	-- Elements tab: the four elements, their base spells, buy / equip.
	----------------------------------------------------------------------
	elementsPage = Theme.frame(panel, {
		Name = "ElementsPage",
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		BackgroundTransparency = 1,
	})
	elementList = Theme.frame(elementsPage, {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(0, 170, 1, -16),
		BackgroundTransparency = 1,
	})
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = elementList
	for index, element in Elements.LIST do
		local button = Theme.button(elementList, element.name, {
			Name = element.id,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 84),
		})
		button.Activated:Connect(function()
			selectElement(element.id)
		end)
		elementButtons[element.id] = button
	end

	local right = Theme.frame(elementsPage, {
		Position = UDim2.fromOffset(200, 0),
		Size = UDim2.new(1, -216, 1, -16),
		BackgroundTransparency = 1,
	})
	headerLabel = Theme.label(right, "", {
		Size = UDim2.new(1, -200, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.BODY_FONT,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 16,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	equipButton = Theme.button(right, "Equip", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(190, Theme.TOUCH),
		BackgroundColor3 = Theme.COLORS.good,
	})
	equipButton.Activated:Connect(function()
		local profile = ClientState.profile
		if not profile then
			return
		end
		if table.find(profile.elements, selectedElement) or #profile.elements == 0 then
			Remotes.get("ChooseElement"):FireServer(selectedElement)
		else
			Remotes.get("BuyElement"):FireServer(selectedElement)
		end
	end)
	Theme.label(right, "BASE SPELLS (come with the element)", {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.subtext,
	})
	spellRow = Theme.frame(right, {
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 108),
		BackgroundTransparency = 1,
	})
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = spellRow

	local detail = Theme.frame(right, {
		Position = UDim2.fromOffset(0, 212),
		Size = UDim2.new(1, 0, 1, -212),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(detail)
	Theme.padding(detail, 10)
	detailGlyph = Theme.frame(detail, {
		Name = "GlyphHolder",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(96, 96),
		BackgroundTransparency = 1,
	})
	detailLabel = Theme.label(detail, "Pick a spell to learn its shape!", {
		Font = Theme.BODY_FONT,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 16,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
	})

	----------------------------------------------------------------------
	-- Loadout tab: base spells (fixed) + two extra slots + your collection.
	----------------------------------------------------------------------
	loadoutPage = Theme.frame(panel, {
		Name = "LoadoutPage",
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		BackgroundTransparency = 1,
		Visible = false,
	})
	loadoutHeader = Theme.label(loadoutPage, "", {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -32, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.BODY_FONT,
		TextScaled = false,
		TextSize = 16,
		RichText = true,
	})
	loadoutRow = Theme.frame(loadoutPage, {
		Position = UDim2.fromOffset(16, 28),
		Size = UDim2.new(1, -32, 0, 108),
		BackgroundTransparency = 1,
	})
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.Padding = UDim.new(0, 8)
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Parent = loadoutRow

	loadoutCount = Theme.label(loadoutPage, "", {
		Position = UDim2.fromOffset(16, 142),
		Size = UDim2.new(1, -32, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.subtext,
	})
	collection = Instance.new("ScrollingFrame")
	collection.Name = "Collection"
	collection.BackgroundTransparency = 1
	collection.BorderSizePixel = 0
	collection.Position = UDim2.fromOffset(16, 166)
	collection.Size = UDim2.new(1, -32, 0, 178)
	collection.CanvasSize = UDim2.new()
	collection.AutomaticCanvasSize = Enum.AutomaticSize.Y
	collection.ScrollBarThickness = 6
	collection.Parent = loadoutPage
	-- Room for the cards' thick rarity rings, so they are not clipped.
	Theme.padding(collection, 8)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(84, 104)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = collection

	local info = Theme.frame(loadoutPage, {
		Position = UDim2.fromOffset(16, 352),
		Size = UDim2.new(1, -32, 0, 72),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(info)
	Theme.padding(info, 8)
	loadoutDetail = Theme.label(info, "Tap a spell to see what it does.", {
		Size = UDim2.new(1, -210, 1, 0),
		Font = Theme.BODY_FONT,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 15,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
	})
	loadoutButton = Theme.button(info, "Equip", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(200, Theme.TOUCH),
		BackgroundColor3 = Theme.COLORS.good,
	})
	loadoutButton.Activated:Connect(function()
		local id = selectedSpell
		local profile = ClientState.profile
		if not id or not profile then
			return
		end
		local slot = table.find(profile.loadout, id)
		if slot then
			Remotes.get("SetLoadout"):FireServer(slot, nil)
		else
			Remotes.get("SetLoadout"):FireServer(targetSlot(profile), id)
		end
		AudioController.play("uiEquip")
	end)
end

local function showSpell(def: Types.SpellDef)
	local school = Elements.school(def.element)
	local shape = Glyphs.get(def.glyph)
	local color = SpellCard.colorOf(def.id)
	detailGlyph:ClearAllChildren()
	GlyphView.create(detailGlyph, def.glyph, 96, color)
	local tag = if def.ultimate then "  <b>ULTIMATE</b>" else ""
	local rarity = if def.rarity then `  <b>{string.upper(def.rarity)}</b>` else ""
	detailLabel.Text = `<b>{def.name}</b>{tag}{rarity}\n{def.description}\n\n`
		.. `<b>Draw:</b> {if shape then shape.name else def.glyph}   {if def.rarity
			then SpellStats.text(def)
			else `<b>Cooldown:</b> {def.cooldown}s`}`
		.. `\n<b>School:</b> {if school then school.name else def.element}`
end

-- Which extra slot a newly equipped spell goes into: the one the player tapped,
-- else the first empty one, else slot 1.
targetSlot = function(profile: ClientState.ProfileSummary): number
	if selectedSlot and selectedSlot >= 1 and selectedSlot <= Loadout.MAX_EXTRA then
		return selectedSlot
	end
	for slot = 1, Loadout.MAX_EXTRA do
		if not profile.loadout[slot] then
			return slot
		end
	end
	return 1
end

local function refreshElementsTab(profile: ClientState.ProfileSummary?)
	local ownedList = if profile then profile.elements else {}
	local equipped = if profile then profile.element else ""
	local firstPick = profile ~= nil and #ownedList == 0

	for id, button in elementButtons do
		local element = Elements.get(id)
		local owned = table.find(ownedList, id) ~= nil
		local mark = if id == equipped
			then "Equipped"
			elseif owned then "Owned"
			elseif firstPick then "Free pick!"
			elseif element then `{element.price} coins`
			else ""
		button.Text = `{id}\n{mark}`
		button.BackgroundColor3 = if id == selectedElement
			then Theme.COLORS.purple
			else Theme.COLORS.panelLight
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke and element then
			stroke.Color = if id == selectedElement
				then element.color
				else Color3.fromRGB(20, 20, 40)
			stroke.Thickness = if id == selectedElement then 4 else 2
		end
	end

	local element = Elements.get(selectedElement)
	if not element then
		return
	end
	local owned = table.find(ownedList, selectedElement) ~= nil
	local color = `#{element.color:Lerp(Color3.new(0, 0, 0), 0.45):ToHex()}`
	headerLabel.Text = `<b><font color="{color}">{element.name}</font></b>  {element.tagline}\n`
		.. (
			if firstPick
				then "Choose your FIRST element for free! Buy more with coins later."
				elseif selectedElement == equipped then "This is your equipped element."
				elseif owned then "You own this element."
				else `Buy it for {element.price} coins to unlock its 3 base spells.`
		)
	if firstPick then
		equipButton.Text = `Choose {element.name}!`
		equipButton.BackgroundColor3 = Theme.COLORS.good
	elseif selectedElement == equipped then
		equipButton.Text = "Equipped"
		equipButton.BackgroundColor3 = Theme.COLORS.panel
	elseif owned then
		equipButton.Text = "Equip"
		equipButton.BackgroundColor3 = Theme.COLORS.good
	else
		local coins = if profile then profile.coins else 0
		equipButton.Text = if coins >= element.price
			then `Buy  {element.price} coins`
			else `{element.price} coins (need {element.price - coins} more)`
		equipButton.BackgroundColor3 = if coins >= element.price
			then Theme.COLORS.accent
			else Theme.COLORS.panel
	end

	for _, child in spellRow:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for slot, def in SpellDefinitions.ofElement(selectedElement) do
		local card = SpellCard.create(spellRow, def.id, { size = UDim2.new(0.333, -6, 1, 0) })
		card.LayoutOrder = slot
		card.Activated:Connect(function()
			showSpell(def)
		end)
	end
end

local function emptySlotCard(parent: Instance, text: string): TextButton
	local card = Theme.button(parent, text, {
		Size = UDim2.fromOffset(128, 104),
		BackgroundColor3 = Theme.COLORS.panel,
		BackgroundTransparency = 0.35,
	})
	return card
end

local function refreshLoadoutTab(profile: ClientState.ProfileSummary?)
	for _, child in loadoutRow:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for _, child in collection:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	if not profile or profile.element == "" then
		loadoutHeader.Text = "Pick your first element on the Elements tab to build a loadout."
		loadoutCount.Text = ""
		loadoutDetail.Text = ""
		loadoutButton.Visible = false
		return
	end
	local element = Elements.get(profile.element)
	if not element then
		return
	end
	loadoutHeader.Text =
		`<b>{element.name}</b> base spells + 2 crate spells. Each spell needs its own shape!`
	-- Base spells (fixed) then the two extra slots.
	for slot, def in SpellDefinitions.ofElement(profile.element) do
		local card = SpellCard.create(loadoutRow, def.id, { size = UDim2.fromOffset(128, 104) })
		card.LayoutOrder = slot
		Theme.label(card, "BASE", {
			Name = "Tag",
			Size = UDim2.fromOffset(40, 14),
			Position = UDim2.fromOffset(4, 3),
			TextColor3 = Theme.COLORS.subtext,
		})
		card.Activated:Connect(function()
			selectedSpell = nil
			selectedSlot = nil
			setLoadoutDetail(def.id, profile)
		end)
	end
	for slot = 1, Loadout.MAX_EXTRA do
		local id = profile.loadout[slot]
		local card: TextButton
		if id then
			card = SpellCard.create(loadoutRow, id, { size = UDim2.fromOffset(128, 104) })
		else
			card = emptySlotCard(loadoutRow, `+\nSlot {slot}`)
		end
		card.LayoutOrder = Elements.BASE_COUNT + slot
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if selectedSlot == slot then
			card.BackgroundColor3 = Theme.COLORS.accent
			if stroke then
				stroke.Thickness = 5
			end
		end
		card.Activated:Connect(function()
			selectedSlot = slot
			selectedSpell = id
			MenuController.refreshSpellbook()
		end)
	end

	-- Collection: every crate spell, owned ones lit, the rest hidden as "?".
	local pool = SpellDefinitions.crateSpells()
	table.sort(pool, function(a, b)
		if Rarity.rank(a.rarity) ~= Rarity.rank(b.rarity) then
			return Rarity.rank(a.rarity) > Rarity.rank(b.rarity)
		end
		return a.name < b.name
	end)
	local have = 0
	-- What a newly equipped spell would sit beside: the base spells and the
	-- extra it would not replace.
	local fitsBeside = Loadout.spells(profile.element, {})
	local replacing = targetSlot(profile)
	for index = 1, Loadout.MAX_EXTRA do
		local other = profile.loadout[index]
		if other and index ~= replacing then
			table.insert(fitsBeside, other)
		end
	end
	for order, def in pool do
		local owned = table.find(profile.spells, def.id) ~= nil
		if owned then
			have += 1
		end
		local card = SpellCard.create(collection, def.id, { owned = owned })
		card.LayoutOrder = order
		local equippedSlot = table.find(profile.loadout, def.id)
		-- A spell whose shape is already in the loadout can't be equipped: dim it.
		if owned and not equippedSlot and Loadout.problem(def.id, fitsBeside) then
			card.BackgroundTransparency = 0.6
			Theme.label(card, "SAME SHAPE", {
				Name = "Clash",
				Size = UDim2.fromOffset(70, 15),
				Position = UDim2.fromOffset(4, 3),
				TextColor3 = Theme.COLORS.bad,
				BackgroundTransparency = 0,
				BackgroundColor3 = Theme.COLORS.outline,
			})
		end
		if equippedSlot then
			Theme.label(card, `SLOT {equippedSlot}`, {
				Name = "Equipped",
				Size = UDim2.fromOffset(48, 15),
				Position = UDim2.new(1, -52, 0, 3),
				TextColor3 = Theme.COLORS.good,
				BackgroundTransparency = 0,
				BackgroundColor3 = Theme.COLORS.outline,
			})
		end
		if selectedSpell == def.id then
			local stroke = card:FindFirstChildOfClass("UIStroke")
			-- Selected: a sunny card, keeping the rarity ring.
			card.BackgroundColor3 = Theme.COLORS.accent
			if stroke then
				stroke.Thickness = 5
			end
		end
		card.Activated:Connect(function()
			selectedSpell = def.id
			selectedSlot = equippedSlot or selectedSlot
			MenuController.refreshSpellbook()
		end)
	end
	loadoutCount.Text =
		`Collection: {have}/{#pool} crate spells. Spin the Spell Crate to find more!`
	setLoadoutDetail(selectedSpell, profile)
end

-- Fills the detail strip (and the equip button) for a spell, or hints at what to do.
setLoadoutDetail = function(spellId: string?, profile: ClientState.ProfileSummary)
	local def = if spellId then SpellDefinitions.get(spellId) else nil
	loadoutButton.Visible = false
	if not def then
		loadoutDetail.Text = if selectedSlot
			then `Slot {selectedSlot} selected: tap a spell you own to put it there.`
			else "Tap a spell to see what it does, then equip it."
		return
	end
	local shape = Glyphs.get(def.glyph)
	local text = `<b>{def.name}</b>  {def.description}  <b>Draw:</b> {if shape
		then shape.name
		else def.glyph}`
	local owned = table.find(profile.spells, def.id) ~= nil
	if not def.rarity then
		loadoutDetail.Text = text .. "  (base spell: always in your loadout)"
		return
	end
	if not owned then
		loadoutDetail.Text = text
			.. '  <font color="#7A5A00">Not won yet: spin the Spell Crate!</font>'
		return
	end
	local equippedSlot = table.find(profile.loadout, def.id)
	loadoutButton.Visible = true
	if equippedSlot then
		loadoutDetail.Text = text
		loadoutButton.Text = "Remove from loadout"
		loadoutButton.BackgroundColor3 = Theme.COLORS.bad
		return
	end
	-- What it would sit beside: the base spells and the extra it does not replace.
	local slot = targetSlot(profile)
	local others = Loadout.spells(profile.element, {})
	for index = 1, Loadout.MAX_EXTRA do
		local other = profile.loadout[index]
		if index ~= slot and other then
			table.insert(others, other)
		end
	end
	local problem = Loadout.problem(def.id, others)
	if problem then
		loadoutDetail.Text = text .. `  <font color="#B3262E">{problem}</font>`
		loadoutButton.Text = "Can't equip"
		loadoutButton.BackgroundColor3 = Theme.COLORS.panel
	else
		loadoutDetail.Text = text
		loadoutButton.Text = `Equip in slot {slot}`
		loadoutButton.BackgroundColor3 = Theme.COLORS.good
	end
end

function MenuController.refreshSpellbook()
	if not spellRow then
		return
	end
	local profile = ClientState.profile
	for tab, button in tabButtons do
		button.BackgroundColor3 = if tab == bookTab
			then Theme.COLORS.accent
			else Theme.COLORS.panelLight
	end
	elementsPage.Visible = bookTab == "Elements"
	loadoutPage.Visible = bookTab == "Loadout"
	if bookTab == "Elements" then
		refreshElementsTab(profile)
	else
		refreshLoadoutTab(profile)
	end
end

-- Opens the Spellbook on a tab ("Elements" or "Loadout").
function MenuController.openSpellbook(tab: string?)
	if tab then
		bookTab = tab
	end
	MenuController.refreshSpellbook()
	MenuController.open("Spellbook")
end

-- Which side-menu panel is open (nil when none).
function MenuController.openPanel(): string?
	return openName
end

-- A side-menu button by panel name ("Play", "Spellbook", "Crates", ...), so
-- the tutorial can point at it.
function MenuController.sideButton(name: string): TextButton?
	return sideButtons[name]
end

-- Spellbook widgets the tutorial points at: "equip" (the Choose / Buy / Equip
-- button) and "elements" (the list of elements).
function MenuController.widget(name: string): GuiObject?
	if name == "equip" then
		return equipButton
	elseif name == "elements" then
		return elementList
	end
	return nil
end

-- The element the Spellbook's Elements tab is showing.
function MenuController.selectedElementId(): string
	return selectedElement
end

local function buildQuests(root: Instance)
	local panel = makePanel(root, "Quests", "Daily Quests")
	questList = Theme.frame(panel, {
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 1, -80),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.Parent = questList
end

local function refreshQuests()
	if not questList then
		return
	end
	for _, child in questList:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local profile = ClientState.profile
	if not profile then
		return
	end
	Theme.label(questList, `Login streak: {profile.streak} day(s)`, {
		Size = UDim2.new(1, 0, 0, 30),
		TextColor3 = Theme.COLORS.heading,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	for _, quest in profile.quests do
		local row = Theme.frame(questList, {
			Size = UDim2.new(1, 0, 0, 70),
			BackgroundColor3 = Theme.COLORS.panelLight,
		})
		Theme.corner(row)
		Theme.label(
			row,
			`{quest.text}  ({quest.progress}/{quest.goal})  +{quest.rewardCoins} coins`,
			{
				Size = UDim2.new(1, -150, 1, -16),
				Position = UDim2.fromOffset(10, 8),
				TextXAlignment = Enum.TextXAlignment.Left,
			}
		)
		local done = quest.progress >= quest.goal
		local claim = Theme.button(
			row,
			if quest.claimed then "Claimed" elseif done then "Claim!" else "In progress",
			{
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(130, Theme.TOUCH),
				BackgroundColor3 = if done and not quest.claimed
					then Theme.COLORS.good
					else Theme.COLORS.panel,
				Active = done and not quest.claimed,
			}
		)
		claim.Activated:Connect(function()
			if done and not quest.claimed then
				Remotes.get("ClaimQuest"):FireServer(quest.id)
				-- The plaza chest opens to hand over the reward.
				PropSwap.show("QuestChestModel", "QuestChestOpen", 2.5)
			end
		end)
	end
end

local function buildSideButtons(root: Instance)
	local holder = Theme.frame(root, {
		Name = "SideMenu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(120, 6 * 62),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = holder
	local buttons = sideButtons
	for _, entry in
		{
			{ "Play", "▶ Play" },
			{ "Spellbook", "Spells" },
			{ "Crates", "Crates" },
			{ "Quests", "Quests" },
			{ "Spectate", "Watch" },
			{ "Settings", "Settings" },
		}
	do
		local button = Theme.button(holder, entry[2], { Size = UDim2.new(1, 0, 0, Theme.TOUCH) })
		button.Activated:Connect(function()
			MenuController.toggle(entry[1])
		end)
		buttons[entry[1]] = button
	end
	-- Only Settings stays available during matches.
	ClientState.MatchChanged:Connect(function()
		local idle = ClientState.match.phase == "Idle"
		for name, button in buttons do
			button.Visible = idle or name == "Settings"
		end
		if not idle and openName ~= "Settings" then
			MenuController.close()
		end
	end)
end

-- Lets other controllers (Settings) add a standard panel.
function MenuController.createPanel(name: string, title: string): Frame
	local root = HudController.getGui():WaitForChild("Root")
	return makePanel(root, name, title)
end

function MenuController.isOpen(): boolean
	return openName ~= nil
end

function MenuController.init()
	local root = HudController.getGui():WaitForChild("Root")
	buildSideButtons(root)
	buildPlay(root)
	buildSpellbook(root)
	buildQuests(root)
end

function MenuController.start()
	ClientState.QueueChanged:Connect(refreshPlay)
	ClientState.ProfileChanged:Connect(function()
		local profile = ClientState.profile
		-- Select what you have equipped (and open the picker on a first visit).
		if profile and profile.element ~= "" and not askedFirstPick then
			selectedElement = profile.element
		end
		MenuController.refreshSpellbook()
		refreshQuests()
		-- A returning player who never picked an element gets the book opened;
		-- new players are walked there by the tutorial instead.
		if profile and #profile.elements == 0 and profile.tutorial.done and not askedFirstPick then
			askedFirstPick = true
			MenuController.openSpellbook("Elements")
		end
	end)
	refreshPlay()
	MenuController.refreshSpellbook()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "Spellbook" then
			MenuController.openSpellbook(nil)
		elseif prompt.Name == "Quests" or prompt.Name == "Crates" then
			MenuController.open(prompt.Name)
		end
	end)
end

return MenuController
