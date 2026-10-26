--!strict
-- Admin panel: a classic Roblox-style admin window you can open, drag, and
-- close. Pick a target on the left (me / all / others / any player), pick a tab,
-- and click: every button runs one admin command (the buttons come from
-- Shared/Admin/Catalog). There is also a command box for typing commands, and a
-- log of what the server replied.
--
-- Shown only to admins (the server sets the player attribute "IsAdmin"); that is
-- cosmetic: the server checks admin status again on every AdminCommand.
-- Open it with the 🛡 Admin button or the ` (backquote) key.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Catalog = require(ReplicatedStorage.Shared.Admin.Catalog)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Responsive = require(script.Parent.Parent.UI.Responsive)
local Theme = require(script.Parent.Parent.UI.Theme)

local player = Players.LocalPlayer

local WIDTH = 640
local HEIGHT = 460
local TITLE_H = 40
local SIDE_W = 150
local LOG_H = 74
local BAR_H = 34
local MAX_LOG = 60
local TOGGLE_KEY = Enum.KeyCode.Backquote

local AdminController = {}

local gui: ScreenGui
local scale: UIScale
local window: Frame
local openButton: TextButton
local content: ScrollingFrame
local targetList: ScrollingFrame
local targetLabel: TextLabel
local logList: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}

local tabs = Catalog.tabs()
local currentTab = "Player"
local target = "me"
local logCount = 0
local armed: TextButton? = nil -- a danger button waiting for its second click

local function colorFor(key: string?): Color3
	local colors = Theme.COLORS :: any
	local color = if key then colors[key] else nil
	return if typeof(color) == "Color3" then color else Theme.COLORS.panelLight
end

-- A transparent container (Theme.frame would add a bevel and studs).
local function holder(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for key, value in props do
		(f :: any)[key] = value
	end
	f.Parent = parent
	return f
end

local function list(parent: Instance, padding: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

local function scroller(parent: Instance, props: { [string]: any }): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollBarThickness = 6
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	for key, value in props do
		(s :: any)[key] = value
	end
	s.Parent = parent
	return s
end

-- A white text field with an ink outline.
local function textBox(parent: Instance, placeholder: string, default: string?): TextBox
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	box.BorderSizePixel = 0
	box.Font = Theme.BODY_FONT
	box.TextSize = 16
	box.TextColor3 = Theme.COLORS.text
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(110, 116, 140)
	box.Text = default or ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	Theme.corner(box, 8)
	Theme.stroke(box, Theme.COLORS.outline, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = box
	box.Parent = parent
	return box
end

----------------------------------------------------------------------
-- Log + running commands
----------------------------------------------------------------------

local function addLog(message: string, color: Color3?)
	logCount += 1
	local line = Instance.new("TextLabel")
	line.Name = tostring(logCount)
	line.LayoutOrder = logCount
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(1, -6, 0, 0)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.Font = Theme.BODY_FONT
	line.TextSize = 14
	line.TextWrapped = true
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = color or Theme.COLORS.text
	line.Text = message
	line.Parent = logList
	local old = logList:FindFirstChild(tostring(logCount - MAX_LOG))
	if old then
		old:Destroy()
	end
	task.delay(0.05, function()
		logList.CanvasPosition =
			Vector2.new(0, math.max(0, logList.AbsoluteCanvasSize.Y - logList.AbsoluteSize.Y))
	end)
end

local function run(command: string)
	addLog("> " .. command, Theme.COLORS.subtext)
	Remotes.get("AdminCommand"):FireServer(command)
end

-- Fills {t} (the picked target) and {v} (typed text) into a command.
-- Returns nil when it needs a value and none was typed.
local function expand(template: string, value: string?): string?
	local text = string.gsub(template, "{t}", function()
		return target
	end)
	if string.find(text, "{v}", 1, true) then
		local typed = if value then string.gsub(value, "^%s*(.-)%s*$", "%1") else ""
		if typed == "" then
			return nil
		end
		text = string.gsub(text, "{v}", function()
			return typed
		end)
	end
	return text
end

----------------------------------------------------------------------
-- Targets (left column)
----------------------------------------------------------------------

local function refreshTargets()
	for _, child in targetList:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local entries: { { word: string, text: string } } = {
		{ word = "me", text = "👤 Me" },
		{ word = "all", text = "👥 All" },
		{ word = "others", text = "👥 Others" },
	}
	local found = target == "me" or target == "all" or target == "others"
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(entries, { word = other.Name, text = other.Name })
			found = found or other.Name == target
		end
	end
	if not found then
		target = "me"
	end
	targetLabel.Text = `Target: {target}`
	for order, entry in entries do
		local button = Theme.button(targetList, entry.text, {
			Name = entry.word,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 32),
			BackgroundColor3 = if entry.word == target
				then Theme.COLORS.accent
				else Theme.COLORS.panelLight,
		})
		button.Activated:Connect(function()
			target = entry.word
			refreshTargets()
		end)
	end
end

----------------------------------------------------------------------
-- Tabs (right side)
----------------------------------------------------------------------

-- A command button; danger buttons ask for a second click.
local function commandButton(parent: Instance, entry: Catalog.Entry): TextButton
	local button = Theme.button(parent, entry.label, { BackgroundColor3 = colorFor(entry.color) })
	button.Activated:Connect(function()
		if entry.confirm then
			if armed ~= button then
				armed = button
				button.Text = "Sure?"
				task.delay(2, function()
					if armed == button then
						armed = nil
						button.Text = entry.label
					end
				end)
				return
			end
			armed = nil
			button.Text = entry.label
		end
		local command = expand(entry.cmd, nil)
		if command then
			run(command)
		end
	end)
	return button
end

-- A row with a label, a text field, and a button that runs the command with it.
local function inputRow(parent: Instance, entry: Catalog.Entry): Frame
	local row = holder(parent, { Size = UDim2.new(1, 0, 0, 36) })
	Theme.label(row, entry.label, {
		Size = UDim2.new(0, 120, 1, -8),
		Position = UDim2.fromOffset(0, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local box = textBox(row, entry.placeholder or "", entry.default)
	box.Position = UDim2.fromOffset(126, 2)
	box.Size = UDim2.new(1, -126 - 96, 1, -4)
	local go = Theme.button(row, entry.button or "Run", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.fromOffset(88, 32),
		BackgroundColor3 = Theme.COLORS.good,
	})
	local function submit()
		local command = expand(entry.cmd, box.Text)
		if command then
			run(command)
		else
			addLog("Type a value first.", Theme.COLORS.subtext)
		end
	end
	go.Activated:Connect(submit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)
	return row
end

local function renderTab(id: string)
	currentTab = id
	armed = nil
	for _, child in content:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	for tabId, button in tabButtons do
		button.BackgroundColor3 = if tabId == id
			then Theme.COLORS.accent
			else Theme.COLORS.panelLight
	end
	for _, tab in tabs do
		if tab.id ~= id then
			continue
		end
		for index, group in tab.groups do
			local box = holder(content, {
				LayoutOrder = index,
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			})
			list(box, 6)
			local header = Theme.label(box, group.title, {
				LayoutOrder = 0,
				Size = UDim2.new(1, 0, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.COLORS.heading,
			})
			header.TextScaled = false
			header.TextSize = 18
			local flow: Frame? = nil
			for order, entry in group.entries do
				if entry.kind == "input" then
					flow = nil
					inputRow(box, entry).LayoutOrder = order
				else
					if not flow then
						flow = holder(box, {
							LayoutOrder = order,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
						})
						local grid = Instance.new("UIGridLayout")
						grid.CellSize = UDim2.fromOffset(112, 34)
						grid.CellPadding = UDim2.fromOffset(6, 6)
						grid.SortOrder = Enum.SortOrder.LayoutOrder
						grid.Parent = flow
					end
					local button = commandButton(flow :: Frame, entry)
					button.LayoutOrder = order
				end
			end
		end
	end
	content.CanvasPosition = Vector2.zero
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

local function setOpen(open: boolean)
	window.Visible = open
	if open then
		refreshTargets()
	end
end

local function refreshAdmin()
	local isAdmin = player:GetAttribute("IsAdmin") == true
	openButton.Visible = isAdmin
	if not isAdmin then
		window.Visible = false
	end
end

local function makeDraggable(handle: GuiObject)
	local dragging = false
	local dragStart = Vector3.zero
	local startPosition = window.Position
	handle.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragStart = input.Position
			startPosition = window.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local delta = (input.Position - dragStart) / scale.Scale
			window.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + delta.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + delta.Y
			)
		end
	end)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "SpellcraftAdmin"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	scale = Instance.new("UIScale")
	scale.Parent = gui
	Responsive.bind(scale)

	openButton = Theme.button(gui, "🛡 Admin", {
		Name = "OpenAdmin",
		Position = UDim2.fromOffset(12, 64),
		Size = UDim2.fromOffset(120, 36),
		BackgroundColor3 = Theme.COLORS.purple,
		Visible = false,
	})
	openButton.Activated:Connect(function()
		setOpen(not window.Visible)
	end)

	window = Theme.frame(gui, {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		Active = true, -- clicks on the window never reach the world
		Visible = false,
	})
	Theme.corner(window, 14)
	Theme.stroke(window, Theme.COLORS.outline, 4)

	-- Title bar: drag it to move the window, X closes it.
	local titleBar = Theme.frame(window, {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, TITLE_H),
		BackgroundColor3 = Theme.COLORS.purple,
	})
	Theme.corner(titleBar, 14)
	Theme.label(titleBar, "🛡 Admin Panel", {
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -70, 1, -8),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local close = Theme.button(titleBar, "X", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(32, 30),
		BackgroundColor3 = Theme.COLORS.bad,
	})
	close.Activated:Connect(function()
		setOpen(false)
	end)
	makeDraggable(titleBar)

	local bodyTop = TITLE_H + 8
	local bodyHeight = HEIGHT - bodyTop - LOG_H - BAR_H - 20

	-- Left: who the buttons act on.
	local side = Theme.frame(window, {
		Name = "Targets",
		Position = UDim2.fromOffset(8, bodyTop),
		Size = UDim2.fromOffset(SIDE_W, bodyHeight),
		BackgroundColor3 = Theme.COLORS.grey,
	})
	Theme.corner(side, 10)
	Theme.stroke(side, Theme.COLORS.outline, 2)
	targetLabel = Theme.label(side, "Target: me", {
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.heading,
	})
	targetList = scroller(side, {
		Position = UDim2.fromOffset(4, 30),
		Size = UDim2.new(1, -8, 1, -34),
	})
	list(targetList, 4)

	-- Right: tabs and the picked tab's buttons.
	local rightX = SIDE_W + 16
	local rightW = WIDTH - rightX - 8
	local tabRow = holder(window, {
		Position = UDim2.fromOffset(rightX, bodyTop),
		Size = UDim2.fromOffset(rightW, 34),
	})
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow
	for order, tab in tabs do
		local button = Theme.button(tabRow, tab.label, {
			Name = tab.id,
			LayoutOrder = order,
			Size = UDim2.new(1 / #tabs, -4, 1, 0),
		})
		button.Activated:Connect(function()
			renderTab(tab.id)
		end)
		tabButtons[tab.id] = button
	end
	local contentBox = Theme.frame(window, {
		Name = "Content",
		Position = UDim2.fromOffset(rightX, bodyTop + 40),
		Size = UDim2.fromOffset(rightW, bodyHeight - 40),
		BackgroundColor3 = Theme.COLORS.panel,
	})
	Theme.corner(contentBox, 10)
	Theme.stroke(contentBox, Theme.COLORS.outline, 2)
	content = scroller(contentBox, {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
	})
	list(content, 10)

	-- Bottom: the server's replies, then a box to type commands.
	local logBox = Theme.frame(window, {
		Name = "Log",
		Position = UDim2.new(0, 8, 1, -(LOG_H + BAR_H + 14)),
		Size = UDim2.new(1, -16, 0, LOG_H),
		BackgroundColor3 = Theme.COLORS.yellow,
	})
	Theme.corner(logBox, 8)
	Theme.stroke(logBox, Theme.COLORS.outline, 2)
	logList = scroller(logBox, {
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 1, -8),
	})
	list(logList, 2)

	local bar = holder(window, {
		Position = UDim2.new(0, 8, 1, -(BAR_H + 6)),
		Size = UDim2.new(1, -16, 0, BAR_H),
	})
	local box = textBox(bar, "Type a command, e.g. give me fireball (press Enter)", nil)
	box.Size = UDim2.new(1, -96, 1, 0)
	local runButton = Theme.button(bar, "Run", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(88, BAR_H),
		BackgroundColor3 = Theme.COLORS.good,
	})
	local function submit()
		local text = string.gsub(box.Text, "^[%s;]+", "")
		if text ~= "" then
			run(text)
			box.Text = ""
		end
	end
	runButton.Activated:Connect(submit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
			box:CaptureFocus()
		end
	end)

	renderTab(currentTab)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function AdminController.init()
	build()
end

function AdminController.start()
	player:GetAttributeChangedSignal("IsAdmin"):Connect(refreshAdmin)
	refreshAdmin()
	Players.PlayerAdded:Connect(function()
		if window.Visible then
			refreshTargets()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if window.Visible then
			task.defer(refreshTargets)
		end
	end)
	Remotes.get("AdminLog").OnClientEvent:Connect(function(message: string)
		addLog(message)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= TOGGLE_KEY then
			return
		end
		if player:GetAttribute("IsAdmin") == true then
			setOpen(not window.Visible)
		end
	end)
	addLog(
		"Pick a target, then click a command. Danger buttons need two clicks.",
		Theme.COLORS.subtext
	)
end

return AdminController
