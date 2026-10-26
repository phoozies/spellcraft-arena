--!strict
-- The party panel: a "Party" button under the wallet opens a list of your
-- party (kick / leave), pending invites (accept / decline), and the other
-- players on the server (invite). All it does is send intent (PartyAction);
-- PartyService decides everything and sends back PartyState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Theme = require(script.Parent.Parent.UI.Theme)
local HudController = require(script.Parent.HudController)

local player = Players.LocalPlayer

local PartyController = {}

type Member = { userId: number, name: string }
type Invite = { userId: number, name: string, secondsLeft: number }
type State = { leaderId: number?, members: { Member }, invites: { Invite } }

local ROW_HEIGHT = 36

local state: State = { leaderId = nil, members = {}, invites = {} }
local toggle: TextButton
local panel: Frame
local list: ScrollingFrame
local actionRemote: RemoteEvent

local function send(action: string, userId: number?)
	actionRemote:FireServer(action, userId)
end

local function row(order: number): Frame
	local frame = Theme.frame(list, {
		Name = `Row{order}`,
		LayoutOrder = order,
		Size = UDim2.new(1, -6, 0, ROW_HEIGHT),
		BackgroundColor3 = Theme.COLORS.panelLight,
		BackgroundTransparency = 0.3,
	})
	Theme.corner(frame, 8)
	return frame
end

local function heading(text: string, order: number)
	Theme.label(list, text, {
		LayoutOrder = order,
		Size = UDim2.new(1, -6, 0, 22),
		TextColor3 = Theme.COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function nameLabel(parent: Frame, text: string, width: number)
	Theme.label(parent, text, {
		Size = UDim2.new(1, -width, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function smallButton(
	parent: Frame,
	text: string,
	offset: number,
	color: Color3,
	onClick: () -> ()
): TextButton
	local button = Theme.button(parent, text, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -offset, 0.5, 0),
		Size = UDim2.fromOffset(64, ROW_HEIGHT - 8),
		BackgroundColor3 = color,
	})
	button.Activated:Connect(onClick)
	return button
end

local function rebuild()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local inParty = #state.members > 0
	local iLead = state.leaderId == player.UserId
	local memberIds: { [number]: boolean } = {}
	for _, member in state.members do
		memberIds[member.userId] = true
	end

	if #state.invites > 0 then
		heading("Invites", nextOrder())
		for _, invite in state.invites do
			local frame = row(nextOrder())
			nameLabel(frame, invite.name, 140)
			smallButton(frame, "Join", 4, Theme.COLORS.good, function()
				send("accept", invite.userId)
			end)
			smallButton(frame, "No", 72, Theme.COLORS.bad, function()
				send("decline", invite.userId)
			end)
		end
	end

	if inParty then
		heading(`Your party ({#state.members}/{Config.PARTY.MAX_SIZE})`, nextOrder())
		for _, member in state.members do
			local frame = row(nextOrder())
			local crown = if member.userId == state.leaderId then "👑 " else ""
			nameLabel(frame, crown .. member.name, 76)
			if iLead and member.userId ~= player.UserId then
				smallButton(frame, "Kick", 4, Theme.COLORS.bad, function()
					send("kick", member.userId)
				end)
			end
		end
		local leave = Theme.button(list, "Leave party", {
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -6, 0, ROW_HEIGHT),
			BackgroundColor3 = Theme.COLORS.panelLight,
		})
		leave.Activated:Connect(function()
			send("leave", nil)
		end)
	end

	local canInvite = not inParty or iLead
	heading("Players", nextOrder())
	local others = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and not memberIds[other.UserId] then
			others += 1
			local frame = row(nextOrder())
			nameLabel(frame, other.DisplayName, 76)
			if other:GetAttribute("PartyId") ~= nil then
				Theme.label(frame, "in a party", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.fromOffset(80, ROW_HEIGHT - 14),
					TextColor3 = Theme.COLORS.subtext,
				})
			elseif canInvite then
				smallButton(frame, "Invite", 4, Theme.COLORS.blue, function()
					send("invite", other.UserId)
				end)
			end
		end
	end
	if others == 0 then
		Theme.label(list, "No one else is here yet.", {
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -6, 0, 28),
			TextColor3 = Theme.COLORS.subtext,
		})
	end

	toggle.Text = if inParty
		then `👥 Party {#state.members}/{Config.PARTY.MAX_SIZE}`
		else "👥 Party"
	toggle.BackgroundColor3 = if #state.invites > 0
		then Theme.COLORS.accent
		else Theme.COLORS.panelLight
	toggle.TextColor3 = if #state.invites > 0 then Theme.COLORS.panel else Theme.COLORS.text
end

local function watch(other: Player)
	other:GetAttributeChangedSignal("PartyId"):Connect(rebuild)
end

function PartyController.init()
	actionRemote = Remotes.get("PartyAction")
	local root = HudController.getGui():FindFirstChild("Root") :: Frame

	toggle = Theme.button(root, "👥 Party", {
		Name = "PartyToggle",
		-- Under the Admin button (12, 12, 36 tall), so neither covers the other.
		Position = UDim2.fromOffset(12, 54),
		Size = UDim2.fromOffset(150, 34),
	})

	panel = Theme.frame(root, {
		Name = "PartyPanel",
		-- Beside the side menu (12-132 wide), not on top of it.
		Position = UDim2.fromOffset(140, 54),
		Size = UDim2.fromOffset(300, 330),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	Theme.corner(panel, 12)
	Theme.stroke(panel, Color3.fromRGB(20, 20, 40), 2)
	Theme.padding(panel, 8)

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			rebuild()
		end
	end)
end

function PartyController.start()
	Remotes.get("PartyState").OnClientEvent:Connect(function(new: State)
		local hadInvites = #state.invites
		state = new
		-- A new invite opens the panel so it can't be missed.
		if #state.invites > hadInvites then
			panel.Visible = true
		end
		rebuild()
	end)
	Players.PlayerAdded:Connect(function(other)
		watch(other)
		rebuild()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(rebuild)
	end)
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	rebuild()
end

return PartyController
