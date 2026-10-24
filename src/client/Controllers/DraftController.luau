--!strict
-- Between-round draft: shows the 3 server-rolled cards (each with its own
-- rarity) and sends the pick. The server auto-picks on timeout.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Parent.UI.Theme)
local HudController = require(script.Parent.HudController)

local DraftController = {}

local overlay: Frame
local row: Frame

local function hide()
	overlay.Visible = false
	GuiService.SelectedObject = nil
end

local function show(cards: { Types.DraftCard })
	for _, child in row:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local first: GuiObject? = nil
	for index, card in cards do
		local def = SpellDefinitions.get(card.spellId)
		if def then
			local info = Rarity.INFO[card.rarity]
			local button = Theme.button(row, "", {
				Name = `Card{index}`,
				Size = UDim2.fromOffset(170, 240),
				LayoutOrder = index,
				BackgroundColor3 = Theme.COLORS.panelLight,
			})
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = info.color
				stroke.Thickness = 4 + info.order
			end
			Theme.label(button, `{info.glyph} {card.rarity}`, {
				Size = UDim2.new(1, -12, 0, 26),
				Position = UDim2.fromOffset(6, 8),
				TextColor3 = info.color,
			})
			Theme.label(button, info.glyph, {
				Size = UDim2.new(1, 0, 0, 60),
				Position = UDim2.fromOffset(0, 40),
				TextColor3 = def.visual.color,
			})
			Theme.label(button, def.name, {
				Size = UDim2.new(1, -12, 0, 30),
				Position = UDim2.fromOffset(6, 104),
			})
			Theme.label(button, def.description, {
				Size = UDim2.new(1, -16, 0, 90),
				Position = UDim2.fromOffset(8, 140),
				Font = Theme.BODY_FONT,
				TextWrapped = true,
				TextScaled = false,
				TextSize = 15,
				TextColor3 = Theme.COLORS.subtext,
				TextYAlignment = Enum.TextYAlignment.Top,
			})
			button.Activated:Connect(function()
				Remotes.get("PickDraft"):FireServer(index)
				HudController.toast(`Drafted {def.name}!`, "ready")
				hide()
			end)
			-- Pop-in animation, higher rarity pops later for suspense.
			local uiScale = Instance.new("UIScale")
			uiScale.Scale = 0.2
			uiScale.Parent = button
			TweenService:Create(
				uiScale,
				TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, index * 0.12),
				{ Scale = 1 }
			):Play()
			first = first or button
		end
	end
	overlay.Visible = true
	if GuiService:IsTenFootInterface() and first then
		GuiService.SelectedObject = first
	end
end

function DraftController.init()
	local root = HudController.getGui():WaitForChild("Root")
	overlay = Theme.frame(root, {
		Name = "Draft",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 20,
	})
	Theme.label(overlay, "Choose a spell for your hand!", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.18, 0),
		Size = UDim2.fromOffset(520, 44),
		TextColor3 = Theme.COLORS.accent,
	})
	row = Theme.frame(overlay, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(560, 250),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 16)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
end

function DraftController.start()
	Remotes.get("DraftOffered").OnClientEvent:Connect(function(cards)
		if typeof(cards) ~= "table" or #cards == 0 then
			hide()
		else
			show(cards)
		end
	end)
end

return DraftController
