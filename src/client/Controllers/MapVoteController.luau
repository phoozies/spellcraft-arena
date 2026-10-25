--!strict
-- The pre-match map vote screen (duels). Shows one card per map with its
-- running vote count and a countdown; tapping a card sends your pick
-- (MapVote). The server owns the vote: this only displays MapVoteState and
-- closes when the server sends nil.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Theme = require(script.Parent.Parent.UI.Theme)
local HudController = require(script.Parent.HudController)

local MapVoteController = {}

type MapChoice = { id: string, name: string, votes: number }
type State = { mode: string, maps: { MapChoice }, myPick: string?, endsAt: number }

local panel: Frame
local title: TextLabel
local timerLabel: TextLabel
local grid: Frame
local cards: { [string]: { button: TextButton, votes: TextLabel, stroke: UIStroke } } = {}
local endsAt = 0
local voteRemote: RemoteEvent

local function cardFor(choice: MapChoice, order: number)
	local existing = cards[choice.id]
	if existing then
		return existing
	end
	local button = Theme.button(grid, "", {
		Name = choice.id,
		LayoutOrder = order,
		BackgroundColor3 = Theme.COLORS.panelLight,
	})
	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke
	Theme.label(button, choice.name, {
		Size = UDim2.new(1, -12, 0.55, 0),
		Position = UDim2.fromOffset(6, 6),
	})
	local votes = Theme.label(button, "", {
		Size = UDim2.new(1, -12, 0.3, 0),
		Position = UDim2.new(0, 6, 0.62, 0),
		TextColor3 = Theme.COLORS.accent,
	})
	button.Activated:Connect(function()
		voteRemote:FireServer(choice.id)
	end)
	local card = { button = button, votes = votes, stroke = stroke }
	cards[choice.id] = card
	return card
end

local function show(state: State?)
	if not state then
		panel.Visible = false
		return
	end
	panel.Visible = true
	endsAt = state.endsAt
	title.Text = `Vote for the {state.mode} map!`
	for order, choice in state.maps do
		local card = cardFor(choice, order)
		card.votes.Text = if choice.votes == 0
			then ""
			else if choice.votes == 1 then "1 vote" else `{choice.votes} votes`
		local mine = state.myPick == choice.id
		card.stroke.Color = if mine then Theme.COLORS.accent else Color3.fromRGB(20, 20, 40)
		card.stroke.Thickness = if mine then 5 else 2
		card.button.BackgroundColor3 = if mine then Color3.fromRGB(84, 80, 140) else Theme.COLORS.panelLight
	end
end

function MapVoteController.init()
	voteRemote = Remotes.get("MapVote")
	local root = HudController.getGui():FindFirstChild("Root") :: Frame

	panel = Theme.frame(root, {
		Name = "MapVote",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(440, 270),
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 20,
	})
	Theme.corner(panel, 14)
	Theme.stroke(panel, Color3.fromRGB(20, 20, 40), 3)
	Theme.padding(panel, 10)

	title = Theme.label(panel, "", {
		Size = UDim2.new(0.7, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	timerLabel = Theme.label(panel, "", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.25, 0, 0, 36),
		TextColor3 = Theme.COLORS.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	grid = Theme.frame(panel, {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -6, 0.5, -6)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
end

function MapVoteController.start()
	Remotes.get("MapVoteState").OnClientEvent:Connect(show)
	RunService.Heartbeat:Connect(function()
		if panel.Visible then
			timerLabel.Text = `{math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))}s`
		end
	end)
end

return MapVoteController
