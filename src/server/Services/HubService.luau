--!strict
-- The central hub (Inkwell Plaza): builds it, spawns players there, and runs
-- queue pads, training dummies, the sparring ring, and the leaderboard.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Placement = require(ReplicatedStorage.Shared.Spells.Placement)
local DestructibleService = require(script.Parent.DestructibleService)
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local buildHub = require(script.Parent.Parent:WaitForChild("Maps"):WaitForChild("InkwellPlaza")) :: any

local HUB_RESPAWN_DELAY = 3
local DUMMY_HEALTH = 250

local HubService = {}

local hub: Model

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 160)
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Haze = 0.6
		atmosphere.Color = Color3.fromRGB(199, 220, 255)
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("Sky") then
		Instance.new("Sky").Parent = Lighting
	end
end

local function spawnDummy(spot: BasePart)
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 5, 2)
	body.Color = Color3.fromRGB(255, 204, 128)
	body.Material = Enum.Material.Fabric
	body.Anchored = true
	body.CFrame = CFrame.new(spot.Position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, math.pi / 2, 0)
	body.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(2.4, 2.4, 2.4)
	head.Color = Color3.fromRGB(255, 224, 178)
	head.Material = Enum.Material.Fabric
	head.Anchored = true
	head.CFrame = body.CFrame * CFrame.new(0, 3.7, 0)
	head.Parent = model
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	model.PrimaryPart = body

	local bar = Instance.new("BillboardGui")
	bar.Name = "HealthBar"
	bar.Size = UDim2.fromOffset(80, 10)
	bar.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	bar.AlwaysOnTop = true
	bar.Enabled = false
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	back.BorderSizePixel = 0
	back.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(239, 83, 80)
	fill.BorderSizePixel = 0
	fill.Parent = back
	bar.Parent = body

	model:SetAttribute("Dummy", true)
	DestructibleService.makeProp(model, DUMMY_HEALTH)
	model.Parent = hub
	model.Destroying:Connect(function()
		task.delay(3, function()
			if spot.Parent then
				spawnDummy(spot)
			end
		end)
	end)
end

local function wireQueuePad(pad: BasePart)
	local mode = pad:GetAttribute("Mode")
	if typeof(mode) ~= "string" then
		return
	end
	local debounce: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local now = os.clock()
		if (debounce[player] or 0) > now then
			return
		end
		debounce[player] = now + 2
		MatchService.joinQueue(player, mode)
	end)
end

local function refreshPadLabels()
	local counts = MatchService.queueCounts()
	for _, pad in CollectionService:GetTagged("QueuePad") do
		local mode = pad:GetAttribute("Mode")
		local label = pad:FindFirstChild("Text", true)
		if typeof(mode) == "string" and label and label:IsA("TextLabel") then
			label.Text = `{mode}\n{counts[mode] or 0} waiting`
		end
	end
end

local function updateSparring()
	local zones = {}
	for _, zone in CollectionService:GetTagged("SparringZone") do
		if zone:IsA("BasePart") then
			table.insert(zones, zone)
		end
	end
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local inside = root ~= nil and not MatchService.isInMatch(player) and Placement.inRegions(root.Position, zones)
		if (player:GetAttribute("InSparring") == true) ~= inside then
			player:SetAttribute("InSparring", if inside then true else nil)
		end
	end
end

local function updateLeaderboard()
	local board = hub:FindFirstChild("Leaderboard")
	local label = board and board:FindFirstChild("Text", true)
	if not label or not label:IsA("TextLabel") then
		return
	end
	local rows = {}
	for player, kos in MatchService.sessionKnockouts do
		if player.Parent then
			table.insert(rows, { name = player.DisplayName, kos = kos })
		end
	end
	table.sort(rows, function(a, b)
		return a.kos > b.kos
	end)
	local lines = { "Top Spellcasters" }
	for i = 1, math.min(5, #rows) do
		table.insert(lines, `{i}. {rows[i].name} — {rows[i].kos} KOs`)
	end
	if #rows == 0 then
		table.insert(lines, "(play a match!)")
	end
	label.Text = table.concat(lines, "\n")
end

function HubService.init()
	-- Replace the template baseplate at runtime (the saved place is untouched).
	for _, name in { "Baseplate", "SpawnLocation" } do
		local default = workspace:FindFirstChild(name)
		if default then
			default:Destroy()
		end
	end
	hub = buildHub()
	hub.Parent = workspace
	setupLighting()
end

function HubService.start()
	for _, pad in CollectionService:GetTagged("QueuePad") do
		if pad:IsA("BasePart") then
			wireQueuePad(pad)
		end
	end
	for _, spot in CollectionService:GetTagged("DummySpot") do
		if spot:IsA("BasePart") then
			spawnDummy(spot)
		end
	end
	MatchService.QueueChanged:Connect(refreshPadLabels)

	PlayerDataService.ProfileLoaded:Connect(function(player)
		MatchService.spawnInHub(player)
	end)

	DestructibleService.Knockout:Connect(function(victim)
		if not MatchService.isInMatch(victim) then
			task.delay(HUB_RESPAWN_DELAY, function()
				if victim.Parent and not MatchService.isInMatch(victim) then
					MatchService.spawnInHub(victim)
				end
			end)
		end
	end)

	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.5)
			tick += 1
			updateSparring()
			if tick % 10 == 0 then
				updateLeaderboard()
			end
		end
	end)
end

return HubService
