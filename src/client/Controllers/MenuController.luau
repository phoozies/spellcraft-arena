--!strict
-- Side menu + panels: Play (queues), Spellbook (the four elements: pick your
-- first one free, equip any you own, see each one's five spells and the shape
-- to draw for them), Crates (built by CrateController through createPanel),
-- and Daily Quests. Hub kiosks open the matching
-- panel through ProximityPrompts ("Spellbook", "Crates", "Quests").

local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Glyphs = require(ReplicatedStorage.Shared.Spells.Glyphs)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local GlyphView = require(ReplicatedStorage.Shared.UI.GlyphView)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local HudController = require(script.Parent.HudController)

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

local MODE_INFO = {
	{ mode = "1v1", text = "Duel" },
	{ mode = "2v2", text = "Duos" },
	{ mode = "3v3", text = "Trios" },
	{ mode = "4v4", text = "Squads" },
	{ mode = "FFA", text = "Free-for-all" },
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
		TextColor3 = Theme.COLORS.accent,
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
	layout.CellSize = UDim2.new(0.5, -8, 0.33, -8) -- 5 modes: 2 columns, 3 rows
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

local function buildSpellbook(root: Instance)
	local panel = makePanel(root, "Spellbook", "Spellbook")
	panel.Size = UDim2.fromOffset(660, 440)

	-- Left: the four elements.
	elementList = Theme.frame(panel, {
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(0, 170, 1, -80),
		BackgroundTransparency = 1,
	})
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = elementList
	for index, element in Elements.LIST do
		local button = Theme.button(elementList, `{element.icon} {element.name}`, {
			Name = element.id,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 78),
		})
		button.Activated:Connect(function()
			selectElement(element.id)
		end)
		elementButtons[element.id] = button
	end

	-- Right: the selected element's header, equip button, five spells, details.
	local right = Theme.frame(panel, {
		Position = UDim2.fromOffset(200, 64),
		Size = UDim2.new(1, -216, 1, -80),
		BackgroundTransparency = 1,
	})
	headerLabel = Theme.label(right, "", {
		Size = UDim2.new(1, -190, 0, 56),
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
		Size = UDim2.fromOffset(180, Theme.TOUCH),
		BackgroundColor3 = Theme.COLORS.good,
	})
	equipButton.Activated:Connect(function()
		local profile = ClientState.profile
		local owned = profile ~= nil and table.find(profile.elements, selectedElement) ~= nil
		local first = profile ~= nil and #profile.elements == 0
		if owned or first then
			Remotes.get("ChooseElement"):FireServer(selectedElement)
		else
			MenuController.open("Crates")
		end
	end)

	spellRow = Theme.frame(right, {
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 108),
		BackgroundTransparency = 1,
	})
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = spellRow

	local detail = Theme.frame(right, {
		Position = UDim2.fromOffset(0, 184),
		Size = UDim2.new(1, 0, 1, -184),
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
end

local function showSpell(def: Types.SpellDef)
	local element = Elements.get(def.element)
	local shape = Glyphs.get(def.glyph)
	detailGlyph:ClearAllChildren()
	GlyphView.create(detailGlyph, def.glyph, 96, if element then element.color else def.visual.color)
	local tag = if def.ultimate then "  <b>ULTIMATE</b>" else ""
	detailLabel.Text = `<b>{def.name}</b>{tag}\n{def.description}\n\n`
		.. `<b>Draw:</b> {if shape then shape.name else def.glyph}\n<b>Cooldown:</b> {def.cooldown}s`
end

function MenuController.refreshSpellbook()
	if not spellRow then
		return
	end
	local profile = ClientState.profile
	local ownedList = if profile then profile.elements else {}
	local equipped = if profile then profile.element else ""
	local firstPick = profile ~= nil and #ownedList == 0

	for id, button in elementButtons do
		local element = Elements.get(id)
		local owned = table.find(ownedList, id) ~= nil
		local mark = if id == equipped then "✓ Equipped" elseif owned or firstPick then "" else "🔒"
		button.Text = `{if element then element.icon else ""} {id}\n{mark}`
		button.BackgroundColor3 = if id == selectedElement
			then Color3.fromRGB(84, 80, 140)
			else Theme.COLORS.panelLight
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke and element then
			stroke.Color = if id == selectedElement then element.color else Color3.fromRGB(20, 20, 40)
			stroke.Thickness = if id == selectedElement then 4 else 2
		end
	end

	local element = Elements.get(selectedElement)
	if not element then
		return
	end
	local owned = table.find(ownedList, selectedElement) ~= nil
	local color = `#{element.color:ToHex()}`
	headerLabel.Text = `<b><font color="{color}">{element.icon} {element.name}</font></b>  {element.tagline}\n`
		.. (if firstPick
			then "Choose your FIRST element for free! More are unlocked from Element Crates."
			elseif selectedElement == equipped then "This is your equipped element."
			elseif owned then "You own this element."
			else "Locked. Open an Element Crate to unlock a new element.")
	if firstPick then
		equipButton.Text = `Choose {element.name}!`
		equipButton.BackgroundColor3 = Theme.COLORS.good
	elseif selectedElement == equipped then
		equipButton.Text = "✓ Equipped"
		equipButton.BackgroundColor3 = Theme.COLORS.panel
	elseif owned then
		equipButton.Text = "Equip"
		equipButton.BackgroundColor3 = Theme.COLORS.good
	else
		equipButton.Text = "🎁 Get crates"
		equipButton.BackgroundColor3 = Theme.COLORS.accent
	end

	for _, child in spellRow:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for slot, def in SpellDefinitions.ofElement(selectedElement) do
		local card = Theme.button(spellRow, "", {
			LayoutOrder = slot,
			Size = UDim2.new(0.2, -5, 1, 0),
			BackgroundColor3 = Theme.COLORS.panelLight,
		})
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = element.color
			stroke.Thickness = if def.ultimate then 4 else 2
		end
		GlyphView.create(card, def.glyph, 54, element.color, { Position = UDim2.new(0.5, -27, 0, 6) })
		Theme.label(card, def.name, {
			Size = UDim2.new(1, -6, 0, 30),
			Position = UDim2.new(0, 3, 1, -36),
			TextColor3 = if def.ultimate then Theme.COLORS.accent else Theme.COLORS.text,
		})
		card.Activated:Connect(function()
			showSpell(def)
		end)
	end
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
	Theme.label(questList, `🔥 Login streak: {profile.streak} day(s)`, {
		Size = UDim2.new(1, 0, 0, 30),
		TextColor3 = Theme.COLORS.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	for _, quest in profile.quests do
		local row = Theme.frame(questList, {
			Size = UDim2.new(1, 0, 0, 70),
			BackgroundColor3 = Theme.COLORS.panelLight,
		})
		Theme.corner(row)
		Theme.label(row, `{quest.text}  ({quest.progress}/{quest.goal})  +{quest.rewardCoins} coins`, {
			Size = UDim2.new(1, -150, 1, -16),
			Position = UDim2.fromOffset(10, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
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
			end
		end)
	end
end

local function buildSideButtons(root: Instance)
	local holder = Theme.frame(root, {
		Name = "SideMenu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(120, 5 * 62),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = holder
	local buttons: { [string]: TextButton } = {}
	for _, entry in
		{
			{ "Play", "▶ Play" },
			{ "Spellbook", "📖 Spells" },
			{ "Crates", "🎁 Crates" },
			{ "Quests", "⭐ Quests" },
			{ "Settings", "⚙ Settings" },
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
		if profile and #profile.elements == 0 and not askedFirstPick then
			askedFirstPick = true
			MenuController.open("Spellbook")
		end
	end)
	refreshPlay()
	MenuController.refreshSpellbook()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "Spellbook" or prompt.Name == "Quests" or prompt.Name == "Crates" then
			MenuController.open(prompt.Name)
		end
	end)
end

return MenuController
