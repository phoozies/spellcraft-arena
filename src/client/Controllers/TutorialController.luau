--!strict
-- The first-join tutorial: a short guided walk through the whole loop, with
-- glowing arrows pointing at exactly where to go and what to press.
--
--   1. Choose an element   Spellbook kiosk / "Spells" button, then Choose
--   2. Open a chest        Chest Shop / "Chests" button, then Open
--   3. Cast a spell        Training Grove, look at a dummy, press a spell's key,
--                          trace the shape (finishing it casts the spell)
--   4. Earn coins          the Battleground portal or a Duel pad
--
-- It runs once per account (profile.tutorial.done, saved through the
-- TutorialDone remote) and can be skipped at any time. Every step finishes by
-- watching what the server already tells us (profile, casts), so the
-- tutorial never changes any rules: it only points. The arrows come from
-- Fx/GuideArrow. If a fight starts (a match or the Battleground) the tutorial
-- ends, since the player has clearly found the game.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Chests = require(ReplicatedStorage.Shared.Economy.Chests)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Responsive = require(script.Parent.Parent.UI.Responsive)
local MouseLock = require(script.Parent.Parent.UI.MouseLock)
local Theme = require(script.Parent.Parent.UI.Theme)
local GuideArrow = require(script.Parent.Parent.Fx.GuideArrow)
local AudioController = require(script.Parent.AudioController)
local ClientState = require(script.Parent.ClientState)
local ChestController = require(script.Parent.ChestController)
local HudController = require(script.Parent.HudController)
local MenuController = require(script.Parent.MenuController)

local player = Players.LocalPlayer

local TutorialController = {}

local GREEN = Color3.fromRGB(60, 185, 70)
local RED = Color3.fromRGB(235, 64, 52)

type Step = {
	id: string,
	title: string,
	-- Instruction text (rich text) for right now; may depend on what is open.
	text: () -> string,
	-- Starts this step's arrows; returns their handles.
	guide: () -> { GuideArrow.Handle },
	-- True once the step is finished.
	done: () -> boolean,
	-- True when the step does not apply to this player (skipped silently).
	skip: (() -> boolean)?,
	-- What to say for a moment when the step is finished.
	praise: () -> string,
	-- Shows a "Got it" button that finishes the step (the last one).
	manual: boolean?,
}

local gui: ScreenGui
local card: Frame
local cardStroke: UIStroke
local pips: Frame
local titleLabel: TextLabel
local bodyLabel: TextLabel
local gotItButton: TextButton
local welcome: Frame

local running = false
local finished = false
local stepIndex = 0
local handles: { GuideArrow.Handle } = {}
local stepStartedAt = 0
local startCasts = 0
local advancing = false

----------------------------------------------------------------------
-- Finding things in the world
----------------------------------------------------------------------

local function playerPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function positionOf(thing: Instance?): Vector3?
	if not thing then
		return nil
	end
	if thing:IsA("BasePart") then
		return thing.Position
	elseif thing:IsA("Model") then
		return thing:GetPivot().Position
	end
	return nil
end

-- The closest tagged thing to the player that passes `accept`.
local function nearestTagged(tag: string, accept: ((Instance) -> boolean)?): Instance?
	local origin = playerPosition()
	local best: Instance? = nil
	local bestDistance = math.huge
	for _, thing in CollectionService:GetTagged(tag) do
		local position = positionOf(thing)
		if position and (not accept or accept(thing)) then
			local distance = if origin then (position - origin).Magnitude else 0
			if distance < bestDistance then
				best, bestDistance = thing, distance
			end
		end
	end
	return best
end

local function named(name: string): Instance?
	return workspace:FindFirstChild(name, true)
end

-- The middle of the Training Grove nearest the player (there is one on each side).
local function groveCenter(): Vector3?
	local zone = nearestTagged("PracticeZone", function(thing)
		return thing:IsA("BasePart")
	end) :: BasePart?
	if zone then
		return zone.Position - Vector3.new(0, zone.Size.Y / 2, 0)
	end
	return nil
end

local function nearestDummy(): Instance?
	return nearestTagged("Destructible", function(thing)
		return thing:GetAttribute("Dummy") == true
	end)
end

local function duelPad(): Instance?
	return nearestTagged("TeamPad", function(thing)
		return thing:GetAttribute("Mode") == "1v1"
	end)
end

local function panelOpen(name: string): boolean
	return MenuController.openPanel() == name
end

-- A guide for a side-menu button, shown only while its panel is closed.
local function sideGuide(panelName: string, text: string): GuideArrow.Handle
	return GuideArrow.gui(function()
		if panelOpen(panelName) then
			return nil
		end
		return MenuController.sideButton(panelName)
	end, { text = text, side = "right" })
end

----------------------------------------------------------------------
-- The steps
----------------------------------------------------------------------

-- First person locks the mouse, so a coach line about a button says how to reach it.
local function useGlowingButton(): string
	if Responsive.isTouch() then
		return "tap the glowing button"
	end
	return "tap <b>Alt</b> and click the glowing button"
end

local STEPS: { Step } = {
	{
		id = "element",
		title = "Choose your element",
		text = function()
			if panelOpen("Spellbook") then
				return "Tap an element you like, then press <b>Choose</b>. Your first one is <b>free</b>!"
			end
			return `Open your <b>Spellbook</b>: {useGlowingButton()} or walk to the book on the plaza.`
		end,
		guide = function()
			return {
				GuideArrow.world(function()
					if panelOpen("Spellbook") then
						return nil
					end
					return positionOf(named("SpellbookKiosk"))
				end, {
					label = "Spellbook",
					trail = true,
					highlight = function()
						return named("SpellbookKiosk")
					end,
				}),
				sideGuide("Spellbook", "Open me!"),
				GuideArrow.gui(function()
					if not panelOpen("Spellbook") then
						return nil
					end
					return MenuController.widget("elements")
				end, { text = "Pick one", side = "right" }),
				GuideArrow.gui(function()
					if not panelOpen("Spellbook") then
						return nil
					end
					return MenuController.widget("equip")
				end, { text = "Then press this!", side = "left" }),
			}
		end,
		done = function()
			local profile = ClientState.profile
			return profile ~= nil and profile.element ~= ""
		end,
		praise = function()
			local profile = ClientState.profile
			return `{if profile then profile.element else "Your element"} is yours! It comes with 3 base spells.`
		end,
	},
	{
		id = "spin",
		title = "Open a chest",
		text = function()
			if panelOpen("Chests") then
				return "The Common Chest is picked. Press <b>Open</b> to win a random spell. The rarer, the stronger!"
			end
			return "Spells come from <b>chests</b>. You have coins for a Common Chest: go to the Chest Shop!"
		end,
		guide = function()
			return {
				GuideArrow.world(function()
					if panelOpen("Chests") then
						return nil
					end
					return positionOf(named("Chest_Common"))
				end, {
					label = "chest",
					trail = true,
					highlight = function()
						return named("ChestModel_Common") or named("Chest_Common")
					end,
				}),
				sideGuide("Chests", "Open me!"),
				GuideArrow.gui(function()
					if not panelOpen("Chests") then
						return nil
					end
					return ChestController.spinButton()
				end, { text = "Open!", side = "top" }),
			}
		end,
		done = function()
			local profile = ClientState.profile
			return profile ~= nil and #profile.spells > 0 and not ChestController.isSpinning()
		end,
		skip = function()
			-- No coins and no spells: nothing to open a chest with, so move on.
			local profile = ClientState.profile
			return profile ~= nil
				and #profile.spells == 0
				and profile.coins < Chests.LIST[1].price
				and not ChestController.isSpinning()
		end,
		praise = function()
			local profile = ClientState.profile
			if profile and #profile.loadout > 0 then
				return "A new spell! It's already equipped in your loadout."
			end
			return "A new spell! Equip it in the Spellbook's Loadout tab."
		end,
	},
	{
		id = "cast",
		title = "Draw to cast",
		text = function()
			if ClientState.inPractice then
				return "<b>Look at a training dummy</b>, press <b>1</b> (or tap a spell card) and trace its shape. It casts the moment you finish. The closer you trace, the stronger it is!"
			end
			return "You draw spells in fights and in the <b>Training Grove</b>. Follow the arrows and step inside!"
		end,
		guide = function()
			return {
				GuideArrow.world(function()
					if ClientState.inPractice then
						return nil
					end
					return groveCenter()
				end, { label = "Training Grove", trail = true }),
				GuideArrow.gui(function()
					if not ClientState.inPractice then
						return nil
					end
					return HudController.getGlyphRow()
				end, { text = "Your spells", side = "top" }),
				GuideArrow.world(function()
					if not ClientState.inPractice then
						return nil
					end
					return positionOf(nearestDummy())
				end, {
					label = "Hit the dummy!",
					highlight = function()
						return nearestDummy()
					end,
				}),
			}
		end,
		done = function()
			return ClientState.casts > startCasts
		end,
		praise = function()
			return "Boom! Draw a shape and it flies where you look."
		end,
	},
	{
		id = "earn",
		title = "Earn coins!",
		text = function()
			return "Win a <b>Duel</b> (stand on a pad in the Concourse) or enter the <b>Battleground</b> and defeat enemies. Coins buy new elements and spells!"
		end,
		guide = function()
			return {
				GuideArrow.world(function()
					return positionOf(nearestTagged("BattlegroundPortal"))
				end, {
					label = "Battleground",
					trail = true,
					color = GREEN,
					highlight = function()
						return nearestTagged("BattlegroundPortal")
					end,
				}),
				GuideArrow.world(function()
					return positionOf(duelPad())
				end, {
					label = "Duel pad",
					trail = true,
					color = RED,
					highlight = function()
						return duelPad()
					end,
				}),
			}
		end,
		done = function()
			return ClientState.fighting()
		end,
		manual = true,
		praise = function()
			return "You're ready, wizard. Good luck!"
		end,
	},
}

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------

local function clearGuides()
	for _, handle in handles do
		handle.destroy()
	end
	table.clear(handles)
end

local function refreshPips()
	for _, pip in pips:GetChildren() do
		if pip:IsA("Frame") then
			local order = pip.LayoutOrder
			pip.BackgroundColor3 = if order < stepIndex
				then GREEN
				elseif order == stepIndex then Theme.COLORS.accent
				else Theme.COLORS.outline
			pip.Size = if order == stepIndex
				then UDim2.fromOffset(34, 10)
				else UDim2.fromOffset(22, 10)
		end
	end
end

local function refreshText()
	local step = STEPS[stepIndex]
	if not step or advancing then
		return
	end
	local text = step.text()
	if bodyLabel.Text ~= text then
		bodyLabel.Text = text
	end
end

local function showCard(visible: boolean)
	card.Visible = true
	local target = if visible then UDim2.new(0.5, 0, 0, 6) else UDim2.new(0.5, 0, 0, -140)
	TweenService:Create(
		card,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = target }
	):Play()
	if not visible then
		task.delay(0.5, function()
			card.Visible = false
		end)
	end
end

local function buildUi()
	gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 140
	gui.Enabled = false
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	Responsive.bind(scale)

	-- The coach card at the top of the screen.
	card = Theme.frame(root, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -140),
		Size = UDim2.fromOffset(600, 96),
		Visible = false,
	})
	Theme.corner(card, 14)
	cardStroke = Theme.stroke(card, Theme.COLORS.accent, 4)
	titleLabel = Theme.label(card, "", {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -150, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLORS.heading,
	})
	bodyLabel = Theme.label(card, "", {
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -28, 0, 52),
		Font = Theme.BODY_FONT,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 17,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	pips = Theme.frame(card, {
		Name = "Pips",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -92, 0, 14),
		Size = UDim2.fromOffset(#STEPS * 28, 10),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = pips
	for index = 1, #STEPS do
		local pip = Theme.frame(pips, {
			Name = `Pip{index}`,
			LayoutOrder = index,
			Size = UDim2.fromOffset(22, 10),
			BackgroundColor3 = Theme.COLORS.outline,
		})
		Theme.corner(pip, 4)
	end
	local skip = Theme.button(card, "Skip", {
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, if Responsive.isTouch() then 4 else 8),
		Size = if Responsive.isTouch() then UDim2.fromOffset(84, 36) else UDim2.fromOffset(70, 30),
		BackgroundColor3 = Theme.COLORS.panel,
	})
	skip.Activated:Connect(function()
		TutorialController.finish(false)
	end)
	gotItButton = Theme.button(card, "Got it!", {
		Name = "GotIt",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -6),
		Size = UDim2.fromOffset(120, 34),
		BackgroundColor3 = Theme.COLORS.good,
		Visible = false,
	})
	gotItButton.Activated:Connect(function()
		TutorialController.finish(true)
	end)
	-- First person: the mouse is free while there is a button to press (the
	-- welcome screen and the last step's "Got it!"); Skip is a tap of Left Alt.
	MouseLock.whileVisible(gotItButton)

	-- The welcome screen shown before step one.
	welcome = Theme.frame(root, {
		Name = "Welcome",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 14, 40),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local bevel = welcome:FindFirstChild("Bevel")
	if bevel then
		bevel:Destroy()
	end
	MouseLock.whileVisible(welcome)
	local title = Theme.label(welcome, "Welcome to Spellcraft Arena!", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(760, 90),
		TextColor3 = Theme.COLORS.yellow,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	title.Name = "Title"
	local titleLimit = title:FindFirstChildOfClass("UITextSizeConstraint")
	if titleLimit then
		titleLimit.MaxTextSize = 56
	end
	local subtitle = Theme.label(
		welcome,
		"Draw magic shapes to cast spells, duel other wizards, and earn coins.\nLet's get you ready in a minute!",
		{
			Name = "Subtitle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(700, 70),
			Font = Theme.BODY_FONT,
			TextWrapped = true,
			TextScaled = false,
			TextSize = 24,
			TextColor3 = Theme.COLORS.onDark,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	subtitle.Name = "Subtitle"
	local start = Theme.button(welcome, "Let's go!", {
		Name = "Start",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromOffset(260, 64),
		BackgroundColor3 = Theme.COLORS.good,
		Visible = false,
	})
	local skipAll = Theme.button(welcome, "Skip tutorial", {
		Name = "SkipAll",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromOffset(200, 40),
		BackgroundColor3 = Theme.COLORS.panel,
		Visible = false,
	})
	start.Activated:Connect(function()
		TutorialController.beginSteps()
	end)
	skipAll.Activated:Connect(function()
		TutorialController.finish(false)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function showWelcome()
	gui.Enabled = true
	welcome.Visible = true
	local title = welcome:FindFirstChild("Title") :: TextLabel
	local subtitle = welcome:FindFirstChild("Subtitle") :: TextLabel
	local start = welcome:FindFirstChild("Start") :: TextButton
	local skipAll = welcome:FindFirstChild("SkipAll") :: TextButton
	TweenService:Create(welcome, TweenInfo.new(0.8), { BackgroundTransparency = 0.35 }):Play()
	local fade = TweenInfo.new(0.8)
	TweenService:Create(title, fade, { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
	task.delay(0.6, function()
		TweenService:Create(subtitle, fade, { TextTransparency = 0, TextStrokeTransparency = 0.5 })
			:Play()
	end)
	task.delay(1.4, function()
		start.Visible = true
		skipAll.Visible = true
		AudioController.play("uiStep")
	end)
end

local function hideWelcome()
	TweenService:Create(welcome, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	for _, child in welcome:GetChildren() do
		if child:IsA("TextLabel") then
			TweenService
				:Create(
					child,
					TweenInfo.new(0.4),
					{ TextTransparency = 1, TextStrokeTransparency = 1 }
				)
				:Play()
		elseif child:IsA("TextButton") then
			child.Visible = false
		end
	end
	task.delay(0.6, function()
		welcome.Visible = false
	end)
end

----------------------------------------------------------------------
-- Running the steps
----------------------------------------------------------------------

local function enterStep(index: number)
	clearGuides()
	stepIndex = index
	local step = STEPS[index]
	if not step then
		return
	end
	stepStartedAt = os.clock()
	startCasts = ClientState.casts
	titleLabel.Text = `{index}. {step.title}`
	bodyLabel.Text = step.text()
	gotItButton.Visible = step.manual == true
	cardStroke.Color = Theme.COLORS.accent
	refreshPips()
	showCard(true)
	AudioController.play("uiStep")
	handles = step.guide()
end

local function advance()
	if advancing or finished then
		return
	end
	advancing = true
	local step = STEPS[stepIndex]
	local last = stepIndex >= #STEPS
	if step and not last then
		-- A moment of praise: the card turns green with a check.
		clearGuides()
		titleLabel.Text = `{step.title}`
		bodyLabel.Text = step.praise()
		cardStroke.Color = GREEN
		gotItButton.Visible = false
		AudioController.play("claimReward")
		task.wait(2)
		if finished then
			return
		end
		advancing = false
		-- Skip steps that do not apply (e.g. no coins to spin with).
		local nextIndex = stepIndex + 1
		while
			STEPS[nextIndex]
			and STEPS[nextIndex].skip
			and (STEPS[nextIndex].skip :: () -> boolean)()
		do
			nextIndex += 1
		end
		if STEPS[nextIndex] then
			enterStep(nextIndex)
		else
			TutorialController.finish(true)
		end
	else
		advancing = false
		TutorialController.finish(true)
	end
end

-- Ends the tutorial: `celebrate` shows the send-off, otherwise it just goes.
function TutorialController.finish(celebrate: boolean)
	if finished then
		return
	end
	finished = true
	running = false
	clearGuides()
	Remotes.get("TutorialDone"):FireServer()
	hideWelcome()
	if celebrate then
		local step = STEPS[#STEPS]
		titleLabel.Text = "You're ready!"
		bodyLabel.Text = step.praise()
		cardStroke.Color = GREEN
		gotItButton.Visible = false
		AudioController.play("claimReward")
		task.delay(3.5, function()
			showCard(false)
			task.delay(0.6, function()
				gui.Enabled = false
			end)
		end)
	else
		showCard(false)
		task.delay(0.6, function()
			gui.Enabled = false
		end)
	end
end

function TutorialController.beginSteps()
	hideWelcome()
	local first = 1
	while STEPS[first] and STEPS[first].skip and (STEPS[first].skip :: () -> boolean)() do
		first += 1
	end
	enterStep(first)
end

local function tick()
	if not running or finished or stepIndex == 0 or advancing then
		return
	end
	-- Joining a fight means the player has found the game: stop here.
	if ClientState.fighting() then
		TutorialController.finish(stepIndex >= #STEPS)
		return
	end
	local step = STEPS[stepIndex]
	if not step then
		return
	end
	refreshText()
	if os.clock() - stepStartedAt > 0.6 and step.done() and not step.manual then
		task.spawn(advance)
	end
end

function TutorialController.start()
	-- Wait for the profile; show the tutorial only to players who have not done it.
	while not ClientState.profile do
		task.wait(0.25)
	end
	local profile = ClientState.profile
	if not profile or profile.tutorial.done then
		return
	end
	-- Let the loading screen and the first frames settle.
	task.wait(2.5)
	if ClientState.fighting() then
		return
	end
	running = true
	showWelcome()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			tick()
		end
	end)
end

function TutorialController.init()
	buildUi()
end

return TutorialController
