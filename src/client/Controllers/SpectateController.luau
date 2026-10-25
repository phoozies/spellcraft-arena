--!strict
-- Spectate: watch any other player. The "👁 Watch" menu button opens a list of
-- the players in the server (with where each one is: the hub, a match, or the
-- Battleground); picking one points the camera at them, and a bar at the top
-- shows who you are watching with Previous / Next / Stop buttons.
--
-- It is purely a camera: nothing is sent to the server. Spectating stops by
-- itself when the target leaves, when you join a match or enter the
-- Battleground, or when you press Stop. It follows the target through respawns.

local Players = game:GetService("Players")

local Theme = require(script.Parent.Parent.UI.Theme)
local Responsive = require(script.Parent.Parent.UI.Responsive)
local ClientState = require(script.Parent.ClientState)
local HudController = require(script.Parent.HudController)
local MenuController = require(script.Parent.MenuController)

local player = Players.LocalPlayer

local SpectateController = {}

local target: Player? = nil
local list: ScrollingFrame
local bar: Frame
local barLabel: TextLabel
local panel: Frame

local function humanoidOf(p: Player?): Humanoid?
	local character = p and p.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Where a player is, for the list.
local function whereIs(p: Player): string
	if p:GetAttribute("InBattleground") then
		return "⚔ Battleground"
	end
	local character = p.Character
	if character and typeof(character:GetAttribute("Team")) == "string" then
		return "🏟 In a match"
	end
	return "🏛 Hub"
end

local function others(): { Player }
	local result = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			table.insert(result, p)
		end
	end
	table.sort(result, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	return result
end

local function pointCamera()
	local camera = workspace.CurrentCamera
	local humanoid = humanoidOf(target)
	if camera and humanoid then
		camera.CameraSubject = humanoid
	end
end

function SpectateController.stop()
	if not target then
		return
	end
	target = nil
	bar.Visible = false
	local camera = workspace.CurrentCamera
	local own = humanoidOf(player)
	if camera and own then
		camera.CameraSubject = own
	end
end

function SpectateController.watch(p: Player)
	if p == player or ClientState.fighting() then
		return
	end
	target = p
	bar.Visible = true
	barLabel.Text = `👁 Watching {p.DisplayName}`
	pointCamera()
	MenuController.close()
end

local function step(direction: number)
	local players = others()
	if #players == 0 then
		SpectateController.stop()
		return
	end
	local index = if target then table.find(players, target) else nil
	local nextIndex = if index then ((index - 1 + direction) % #players) + 1 else 1
	SpectateController.watch(players[nextIndex])
end

local function refreshList()
	for _, child in list:GetChildren() do
		if child:IsA("GuiButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local players = others()
	if #players == 0 then
		Theme.label(list, "Nobody else is here yet.", {
			Size = UDim2.new(1, 0, 0, 40),
			Font = Theme.BODY_FONT,
			TextColor3 = Theme.COLORS.subtext,
		})
		return
	end
	for index, p in players do
		local row = Theme.button(list, `{p.DisplayName}   ·   {whereIs(p)}`, {
			LayoutOrder = index,
			Size = UDim2.new(1, -8, 0, 48),
			BackgroundColor3 = if p == target then Theme.COLORS.accent else Theme.COLORS.panelLight,
		})
		row.Activated:Connect(function()
			SpectateController.watch(p)
		end)
	end
end

function SpectateController.init()
	panel = MenuController.createPanel("Spectate", "Spectate a player")
	panel.Size = UDim2.fromOffset(560, 400)
	list = Instance.new("ScrollingFrame")
	list.Name = "Players"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(16, 64)
	list.Size = UDim2.new(1, -32, 1, -80)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- The "now watching" bar, top center.
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpellcraftSpectate"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	Responsive.bind(scale)
	bar = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(430, 56),
		Visible = false,
	})
	Theme.corner(bar, 12)
	Theme.stroke(bar, Theme.COLORS.accent, 3)
	local previous = Theme.button(bar, "◀", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(44, 44),
	})
	barLabel = Theme.label(bar, "", {
		Position = UDim2.fromOffset(56, 4),
		Size = UDim2.new(1, -240, 1, -8),
	})
	local nextButton = Theme.button(bar, "▶", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -112, 0, 6),
		Size = UDim2.fromOffset(44, 44),
	})
	local stop = Theme.button(bar, "Stop", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(100, 44),
		BackgroundColor3 = Theme.COLORS.bad,
	})
	previous.Activated:Connect(function()
		step(-1)
	end)
	nextButton.Activated:Connect(function()
		step(1)
	end)
	stop.Activated:Connect(SpectateController.stop)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function SpectateController.start()
	-- Keep following the target (through respawns) and stop when we should.
	task.spawn(function()
		while true do
			task.wait(0.4)
			if panel.Visible then
				refreshList()
			end
			if target then
				if target.Parent == nil then
					HudController.toast(`{target.DisplayName} left the game.`, "info")
					SpectateController.stop()
				elseif ClientState.fighting() then
					SpectateController.stop()
				else
					local camera = workspace.CurrentCamera
					local humanoid = humanoidOf(target)
					if camera and humanoid and camera.CameraSubject ~= humanoid then
						camera.CameraSubject = humanoid
					end
				end
			end
		end
	end)
	-- Joining a match or the Battleground ends spectating right away.
	ClientState.PresenceChanged:Connect(function()
		if ClientState.fighting() then
			SpectateController.stop()
		end
	end)
	-- Our own character respawning snaps the camera back to us; keep watching.
	player.CharacterAdded:Connect(function()
		if target then
			task.defer(pointCamera)
		end
	end)
end

return SpectateController
