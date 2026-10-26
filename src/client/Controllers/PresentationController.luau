--!strict
-- The "show" around matches, driven entirely by MatchStateChanged:
--   Intro      VS screen (mode, map, both teams with avatars), then a fade
--              to black while the server moves everyone into the arena
--   Countdown  fade back in, big 3 · 2 · 1 numbers
--   Round      "FIGHT!"
--   Draft      round banner ("BLUE WINS ROUND 1" / "DRAW")
--   Results    VICTORY (confetti) / DEFEAT / DRAW, coins counting up (wins
--              only), then a fade out back to the hub
-- Plus KO pop-ups (you knocked someone out / you got knocked out).
-- Cosmetic only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local JuiceController = require(script.Parent.JuiceController)

local player = Players.LocalPlayer

local PresentationController = {}

local gui: ScreenGui
local fader: Frame
local stage: Frame -- holds the current big presentation (cleared between phases)
local lastPhase: Types.MatchPhase = "Idle"
local lastRound = 0
local countdownThread: thread? = nil

local GOLD = Color3.fromRGB(255, 202, 40)
local TEAM_COLORS: { [string]: Color3 } = {
	Blue = Theme.COLORS.blue,
	Red = Theme.COLORS.red,
}

local function teamColor(team: string?): Color3
	return (team and TEAM_COLORS[team]) or GOLD
end

local function clearStage()
	for _, child in stage:GetChildren() do
		child:Destroy()
	end
end

local function fade(toBlack: boolean, seconds: number)
	TweenService:Create(fader, TweenInfo.new(seconds, Enum.EasingStyle.Quad), {
		BackgroundTransparency = if toBlack then 0 else 1,
	}):Play()
end

-- Big text that pops in (scale overshoot), holds, then fades.
local function popText(
	text: string,
	color: Color3,
	hold: number,
	sizeY: number?,
	posY: number?
): TextLabel
	local label = Theme.label(stage, text, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, posY or 0.4),
		Size = UDim2.new(0.8, 0, 0, sizeY or 120),
		TextColor3 = color,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(20, 20, 40),
	})
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit.MaxTextSize = 110
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = label
	TweenService:Create(
		scale,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
	task.delay(hold, function()
		if label.Parent then
			TweenService
				:Create(
					label,
					TweenInfo.new(0.3),
					{ TextTransparency = 1, TextStrokeTransparency = 1 }
				)
				:Play()
			TweenService:Create(scale, TweenInfo.new(0.3), { Scale = 1.3 }):Play()
			task.wait(0.3)
			label:Destroy()
		end
	end)
	return label
end

-- Paper confetti raining over the screen.
local function confetti(count: number)
	local colors = {
		GOLD,
		Theme.COLORS.blue,
		Theme.COLORS.red,
		Theme.COLORS.good,
		Color3.fromRGB(171, 71, 188),
	}
	for _ = 1, count do
		local bit = Instance.new("Frame")
		bit.BorderSizePixel = 0
		bit.BackgroundColor3 = colors[math.random(1, #colors)]
		bit.Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22))
		bit.Position = UDim2.new(math.random(), 0, -0.05, -math.random(0, 200))
		bit.Rotation = math.random(0, 360)
		bit.ZIndex = 30
		bit.Parent = stage
		local duration = 1.8 + math.random() * 1.4
		TweenService
			:Create(bit, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Position = UDim2.new(bit.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0),
				Rotation = bit.Rotation + math.random(-540, 540),
			})
			:Play()
		task.delay(duration, function()
			bit:Destroy()
		end)
	end
end

---------------------------------------------------------------------------
-- Intro (VS screen)
---------------------------------------------------------------------------

local function avatarCard(parent: Instance, entry: Types.RosterEntry, order: number, color: Color3)
	local card = Theme.frame(parent, {
		Size = UDim2.fromOffset(120, 150),
		LayoutOrder = order,
		BackgroundColor3 = Theme.COLORS.panel,
	})
	Theme.corner(card, 14)
	Theme.stroke(card, color, 3)
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromOffset(100, 100)
	image.Position = UDim2.fromOffset(10, 8)
	image.Parent = card
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				entry.userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if ok and image.Parent then
			image.Image = content
		end
	end)
	Theme.label(card, entry.name, {
		Size = UDim2.new(1, -10, 0, 28),
		Position = UDim2.fromOffset(5, 114),
		TextColor3 = if entry.userId == player.UserId then GOLD else Theme.COLORS.text,
	})
	-- Slide in from below with a stagger.
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = card
	TweenService:Create(
		scale,
		TweenInfo.new(
			0.35,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out,
			0,
			false,
			0.2 + order * 0.08
		),
		{ Scale = 1 }
	):Play()
end

local function showIntro(state: Types.MatchState)
	clearStage()
	local backdrop = Theme.frame(stage, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 18, 40),
		BackgroundTransparency = 0.15,
	})
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(60, 50, 120), Color3.fromRGB(15, 12, 30))
	gradient.Parent = backdrop
	Theme.label(backdrop, `{state.mode or ""} · {state.mapName or ""}`, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.new(0.8, 0, 0, 44),
		TextColor3 = GOLD,
	})

	-- Group the roster by team, in a stable order.
	local teams: { string } = {}
	local byTeam: { [string]: { Types.RosterEntry } } = {}
	for _, entry in state.roster or {} do
		if not byTeam[entry.team] then
			byTeam[entry.team] = {}
			table.insert(teams, entry.team)
		end
		table.insert(byTeam[entry.team], entry)
	end
	table.sort(teams)

	local row = Theme.frame(backdrop, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.95, 0, 0, 200),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row

	local order = 0
	for index, team in teams do
		if index > 1 then
			order += 1
			local vs = Theme.label(row, "VS", {
				Size = UDim2.fromOffset(90, 90),
				LayoutOrder = order,
				TextColor3 = GOLD,
				TextStrokeTransparency = 0,
			})
		end
		for _, entry in byTeam[team] do
			order += 1
			avatarCard(row, entry, order, teamColor(team))
		end
	end

	Theme.label(backdrop, "Draw spells to fight — best of 3!", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.88),
		Size = UDim2.new(0.8, 0, 0, 34),
		TextColor3 = Theme.COLORS.onDark,
	})

	-- Fade to black right before the server teleports us.
	local untilEnd = state.endsAt - workspace:GetServerTimeNow()
	task.delay(math.max(0, untilEnd - 0.6), function()
		if lastPhase == "Intro" then
			fade(true, 0.5)
		end
	end)
end

---------------------------------------------------------------------------
-- Countdown / fight / banners / results
---------------------------------------------------------------------------

local function showCountdown(state: Types.MatchState)
	clearStage()
	fade(false, 0.6)
	if state.round > 1 then
		popText(`ROUND {state.round}`, GOLD, 1, 90, 0.3)
	end
	local thread = task.spawn(function()
		while true do
			local left = math.ceil(state.endsAt - workspace:GetServerTimeNow())
			if left <= 0 or lastPhase ~= "Countdown" then
				break
			end
			if left <= 3 then
				popText(tostring(left), Theme.COLORS.text, 0.6, 160)
			end
			task.wait(state.endsAt - workspace:GetServerTimeNow() - (left - 1))
		end
	end)
	countdownThread = thread
end

local function showFight()
	if countdownThread then
		pcall(task.cancel, countdownThread)
		countdownThread = nil
	end
	clearStage()
	popText("FIGHT!", GOLD, 0.7, 150)
end

local function showRoundBanner(state: Types.MatchState)
	clearStage()
	local text = if state.roundWinner
		then `{string.upper(state.roundWinner)} WINS ROUND {state.round}`
		else `ROUND {state.round} — DRAW`
	local color = if state.roundWinner == state.myTeam
		then GOLD
		elseif state.roundWinner then teamColor(state.roundWinner)
		else Theme.COLORS.subtext
	local banner = Theme.frame(stage, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.5, 0.28),
		Size = UDim2.new(1, 0, 0, 90),
		BackgroundColor3 = Color3.fromRGB(20, 18, 40),
		BackgroundTransparency = 0.2,
	})
	Theme.label(
		banner,
		text,
		{ Size = UDim2.new(1, 0, 1, -16), Position = UDim2.fromOffset(0, 8), TextColor3 = color }
	)
	TweenService
		:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.28),
		})
		:Play()
	task.delay(2.2, function()
		if banner.Parent then
			TweenService
				:Create(banner, TweenInfo.new(0.3), { Position = UDim2.fromScale(1.5, 0.28) })
				:Play()
			task.wait(0.3)
			banner:Destroy()
		end
	end)
end

local function showResults(state: Types.MatchState)
	clearStage()
	local won = state.won == true
	local draw = state.winner == nil
	local title = if won then "VICTORY!" elseif draw then "DRAW" else "DEFEAT"
	local color = if won
		then GOLD
		elseif draw then Theme.COLORS.subtext
		else Color3.fromRGB(176, 190, 197)

	local backdrop = Theme.frame(stage, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
	})
	TweenService:Create(backdrop, TweenInfo.new(0.5), { BackgroundTransparency = 0.45 }):Play()
	popText(title, color, 6, 150, 0.32)
	if won then
		confetti(90)
		task.delay(1.2, confetti, 50)
	end
	if state.winner and not won then
		Theme.label(backdrop, `{state.winner} wins the match`, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.new(0.6, 0, 0, 34),
			TextColor3 = teamColor(state.winner),
		})
	end

	-- Coins earned (winners only) count up.
	local coinsLabel = Theme.label(backdrop, "+0 coins", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(0.5, 0, 0, 56),
		TextColor3 = GOLD,
	})
	local target = state.coinsGained or 0
	coinsLabel.Visible = target > 0
	task.spawn(function()
		local start = os.clock()
		while coinsLabel.Parent do
			local t = math.min(1, (os.clock() - start) / 1.2)
			coinsLabel.Text = `+{math.floor(target * t)} coins`
			if t >= 1 then
				break
			end
			task.wait()
		end
	end)

	-- Fade out right before the server sends us back to the hub.
	local untilEnd = state.endsAt - workspace:GetServerTimeNow()
	task.delay(math.max(0, untilEnd - 0.6), function()
		if lastPhase == "Results" then
			fade(true, 0.5)
		end
	end)
end

local function onState()
	local state = ClientState.match
	local phase = state.phase
	if phase == lastPhase and state.round == lastRound then
		return
	end
	local previous = lastPhase
	lastPhase = phase
	lastRound = state.round
	if phase == "Intro" then
		showIntro(state)
	elseif phase == "Countdown" then
		showCountdown(state)
	elseif phase == "Round" then
		showFight()
	elseif phase == "Draft" and previous == "Round" then
		showRoundBanner(state)
	elseif phase == "Results" then
		if previous == "Round" then
			showRoundBanner(state)
			task.delay(1.6, function()
				if lastPhase == "Results" then
					showResults(state)
				end
			end)
		else
			showResults(state)
		end
	elseif phase == "Idle" then
		clearStage()
		fade(false, 0.6)
	end
end

---------------------------------------------------------------------------
-- KO pop-ups
---------------------------------------------------------------------------

local function onKnockout(killer: string?, victim: string, _spell: string?)
	if killer == player.DisplayName and victim ~= player.DisplayName then
		JuiceController.knockout(true)
		local label = popText("KNOCKOUT!", GOLD, 0.8, 80, 0.22)
		label.Rotation = -6
	elseif victim == player.DisplayName then
		JuiceController.knockout(false)
		popText("KNOCKED OUT", Theme.COLORS.bad, 1.4, 80, 0.3)
		if killer then
			popText(`by {killer}`, Theme.COLORS.subtext, 1.4, 40, 0.4)
		end
	end
end

function PresentationController.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Presentation"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	stage = Theme.frame(gui, {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	fader = Theme.frame(gui, {
		Name = "Fader",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 50,
	})
	fader.Active = false
	gui.Parent = player:WaitForChild("PlayerGui")
end

function PresentationController.start()
	ClientState.MatchChanged:Connect(onState)
	Remotes.get("Knockout").OnClientEvent:Connect(onKnockout)
end

return PresentationController
