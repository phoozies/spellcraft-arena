--!strict
-- Side menu + panels: Play (queues), Spellbook (collection, shows locked
-- spells and their unlock level), and Daily Quests. Hub kiosks open the
-- matching panel through ProximityPrompts.

local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local HudController = require(script.Parent.HudController)

local MenuController = {}

local panels: { [string]: Frame } = {}
local openName: string? = nil
local modeButtons: { [string]: TextButton } = {}
local spellbookGrid: ScrollingFrame
local detailLabel: TextLabel
local questList: Frame

local MODE_INFO = {
	{ mode = "1v1", text = "Duel" },
	{ mode = "2v2", text = "Duos" },
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
	local close = Theme.button(panel, "✕", {
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
	layout.CellSize = UDim2.new(0.5, -8, 0.5, -8)
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

local function buildSpellbook(root: Instance)
	local panel = makePanel(root, "Spellbook", "Spellbook")
	spellbookGrid = Instance.new("ScrollingFrame")
	spellbookGrid.Position = UDim2.fromOffset(16, 64)
	spellbookGrid.Size = UDim2.new(0.62, -16, 1, -80)
	spellbookGrid.BackgroundTransparency = 1
	spellbookGrid.BorderSizePixel = 0
	spellbookGrid.ScrollBarThickness = 8
	spellbookGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	spellbookGrid.CanvasSize = UDim2.new()
	spellbookGrid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(100, 64)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = spellbookGrid

	local detail = Theme.frame(panel, {
		Position = UDim2.new(0.62, 8, 0, 64),
		Size = UDim2.new(0.38, -24, 1, -80),
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	Theme.corner(detail)
	Theme.padding(detail, 10)
	detailLabel = Theme.label(detail, "Pick a spell to learn its words!", {
		Font = Theme.BODY_FONT,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 16,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
	})
end

local function refreshSpellbook()
	if not spellbookGrid then
		return
	end
	for _, child in spellbookGrid:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local owned: { [string]: boolean } = {}
	local profile = ClientState.profile
	for _, id in if profile then profile.ownedSpells else {} do
		owned[id] = true
	end
	for index, def in SpellDefinitions.list do
		local info = Rarity.INFO[def.rarity]
		local has = owned[def.id] == true
		local button =
			Theme.button(spellbookGrid, if has then def.name else `🔒 Lv {def.unlockLevel}`, {
				LayoutOrder = def.unlockLevel * 100 + index,
				BackgroundColor3 = if has
					then Theme.COLORS.panelLight
					else Color3.fromRGB(45, 45, 60),
				TextColor3 = if has then Theme.COLORS.text else Theme.COLORS.subtext,
			})
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = info.color
		end
		button.Activated:Connect(function()
			local words = table.concat(def.aliases, ", ")
			detailLabel.Text = `<b>{def.name}</b>  <font color="#{info.color:ToHex()}">{info.glyph} {def.rarity}</font>\n`
				.. `Level {def.unlockLevel} · {def.archetype}\n\n{def.description}\n\n`
				.. `<b>Say or type:</b> {words}\n<b>Cooldown:</b> {def.cooldown}s`
				.. (if has then "" else "\n\n<i>Locked — or draft it in a match!</i>")
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
		Theme.label(row, `{quest.text}  ({quest.progress}/{quest.goal})  +{quest.rewardXp} XP`, {
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
		Size = UDim2.fromOffset(120, 3 * 62),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = holder
	for _, entry in
		{ { "Play", "▶ Play" }, { "Spellbook", "📖 Spells" }, { "Quests", "⭐ Quests" } }
	do
		local button = Theme.button(holder, entry[2], { Size = UDim2.new(1, 0, 0, Theme.TOUCH) })
		button.Activated:Connect(function()
			MenuController.toggle(entry[1])
		end)
	end
	-- Hide the Play button during matches.
	ClientState.MatchChanged:Connect(function()
		holder.Visible = ClientState.match.phase == "Idle"
		if not holder.Visible then
			MenuController.close()
		end
	end)
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
		refreshSpellbook()
		refreshQuests()
	end)
	refreshPlay()
	refreshSpellbook()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "Spellbook" or prompt.Name == "Quests" then
			MenuController.open(prompt.Name)
		end
	end)
end

return MenuController
