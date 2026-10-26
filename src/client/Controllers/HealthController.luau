--!strict
-- Health display:
--   * a big HUD bar for your own HP (with a blue shield overlay and a
--     trailing "recent damage" bar that drains after a hit);
--   * overhead bars above other players: red for enemies, blue for allies,
--     grey in the hub (shown when damaged or during matches).
-- Replaces Roblox's default top-bar health.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.UI.Theme)
local ClientState = require(script.Parent.ClientState)
local HudController = require(script.Parent.HudController)
local JuiceController = require(script.Parent.JuiceController)

local player = Players.LocalPlayer

local HealthController = {}

local fill: Frame
local trail: Frame
local shieldFill: Frame
local hpText: TextLabel
local lastHealth = 100
local holder: Frame

local function humanoidOf(character: Model?): Humanoid?
	return character and character:FindFirstChildOfClass("Humanoid")
end

local HOTBAR_LIFT = -114 -- bottom edge: clear of the hotbar and its cooldown bar
local GLYPH_LIFT = -192 -- bottom edge when the spell-card row is showing

-- Sits right above the hotbar, or above the spell cards when they are up
-- (fights, the Battleground, the Training Groves).
local function layoutOwn()
	local cards = HudController.getGlyphRow()
	holder.Position = UDim2.new(0.5, 0, 1, if cards.Visible then GLYPH_LIFT else HOTBAR_LIFT)
end

local function buildHud()
	local root = HudController.getGui():WaitForChild("Root")
	holder = Theme.frame(root, {
		Name = "Health",
		-- Just above the hotbar; layoutOwn() lifts it over the spell cards.
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, HOTBAR_LIFT),
		Size = UDim2.fromOffset(260, 30),
		BackgroundTransparency = 0.15,
	})
	Theme.corner(holder, 10)
	local back = Theme.frame(holder, {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		BackgroundColor3 = Color3.fromRGB(20, 20, 40),
		ClipsDescendants = true,
	})
	Theme.corner(back, 8)
	trail = Theme.frame(back, {
		Name = "Trail",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 241, 118),
	})
	Theme.corner(trail, 8)
	fill = Theme.frame(back, {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLORS.good,
	})
	Theme.corner(fill, 8)
	shieldFill = Theme.frame(back, {
		Name = "Shield",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(129, 212, 250),
		BackgroundTransparency = 0.25,
	})
	Theme.corner(shieldFill, 8)
	hpText = Theme.label(back, "100 / 100", {
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		TextColor3 = Theme.COLORS.onDark,
		TextStrokeTransparency = 0.3,
		ZIndex = 5,
	})
	HudController.getGlyphRow():GetPropertyChangedSignal("Visible"):Connect(layoutOwn)
	layoutOwn()
end

local function colorFor(ratio: number): Color3
	if ratio > 0.5 then
		return Theme.COLORS.good
	elseif ratio > 0.25 then
		return Color3.fromRGB(255, 193, 7)
	end
	return Theme.COLORS.bad
end

local function refreshOwn()
	local humanoid = humanoidOf(player.Character)
	if not humanoid then
		return
	end
	local max = math.max(humanoid.MaxHealth, 1)
	local hp = math.max(humanoid.Health, 0)
	local ratio = hp / max
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = colorFor(ratio)
	local shield = (player.Character :: Model):GetAttribute("Shield") :: number? or 0
	shieldFill.Size = UDim2.fromScale(math.clamp(shield / max, 0, 1), 1)
	hpText.Text = if shield > 0
		then `{math.ceil(hp)} / {math.floor(max)}  (+{math.floor(shield)})`
		else `{math.ceil(hp)} / {math.floor(max)}`
	if hp < lastHealth then
		-- The yellow trail lingers, then drains: shows how big the hit was.
		task.delay(0.35, function()
			TweenService:Create(trail, TweenInfo.new(0.4), { Size = fill.Size }):Play()
		end)
	else
		trail.Size = fill.Size
	end
	lastHealth = hp
	-- The screen edges pulse red when you are nearly out, but only in a fight.
	local fighting = ClientState.match.phase ~= "Idle"
		or player:GetAttribute("InBattleground") == true
	JuiceController.setLowHealth(if fighting and hp > 0 then ratio else 1)
end

local function watchOwn(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(refreshOwn)
	character:GetAttributeChangedSignal("Shield"):Connect(refreshOwn)
	refreshOwn()
end

-- Overhead bars for other players --------------------------------------

local overhead: { [Model]: { gui: BillboardGui, fill: Frame } } = {}

local function overheadFor(character: Model)
	if overhead[character] then
		return overhead[character]
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "OverheadHealth"
	gui.Size = UDim2.fromOffset(70, 9)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.Adornee = head
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	back.BorderSizePixel = 0
	back.Parent = gui
	Theme.corner(back, 4)
	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = back
	Theme.corner(bar, 4)
	gui.Parent = HudController.getGui()
	local entry = { gui = gui, fill = bar }
	overhead[character] = entry
	character.Destroying:Connect(function()
		gui:Destroy()
		overhead[character] = nil
	end)
	return entry
end

local function updateOverheads()
	local state = ClientState.match
	local inMatch = state.phase ~= "Idle"
	local inBattle = player:GetAttribute("InBattleground") == true
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local humanoid = humanoidOf(character)
		if other ~= player and character and humanoid then
			local entry = overheadFor(character)
			if entry then
				local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
				entry.fill.Size = UDim2.fromScale(ratio, 1)
				local team = character:GetAttribute("Team")
				-- In the Battleground every other fighter is an enemy.
				local fighter = inBattle and other:GetAttribute("InBattleground") == true
				local partyId = other:GetAttribute("PartyId")
				local partyMate = fighter
					and partyId ~= nil
					and partyId == player:GetAttribute("PartyId")
				entry.fill.BackgroundColor3 = if partyMate
					then Theme.COLORS.blue
					elseif fighter then Theme.COLORS.red
					elseif not inMatch then Color3.fromRGB(176, 190, 197)
					elseif team == state.myTeamId then Theme.COLORS.blue
					else Theme.COLORS.red
				-- In the hub only show bars on hurt players to keep it calm.
				entry.gui.Enabled = humanoid.Health > 0 and (inMatch or fighter or ratio < 1)
			end
		end
	end
end

function HealthController.init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	buildHud()
end

function HealthController.start()
	player.CharacterAdded:Connect(watchOwn)
	if player.Character then
		task.spawn(watchOwn, player.Character)
	end
	ClientState.MatchChanged:Connect(refreshOwn)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.15 then
			elapsed = 0
			updateOverheads()
		end
	end)
end

return HealthController
