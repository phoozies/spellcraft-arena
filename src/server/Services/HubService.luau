--!strict
-- The central hub (Inkwell Plaza): builds it, spawns players there, and runs
-- the team boxes, and training dummies. (The wins board
-- and podium are LeaderboardService; the crate shop is CrateService.)

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DestructibleService = require(script.Parent.DestructibleService)
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local Config = require(ReplicatedStorage.Shared.Config)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local MapsFolder = script.Parent.Parent:WaitForChild("Maps")
local buildHub = require(MapsFolder:WaitForChild("InkwellPlaza")) :: any

local HUB_RESPAWN_DELAY = 3
local DUMMY_HEALTH = 250

local HubService = {}

local hub: Model
local toastRemote: RemoteEvent

-- Health regenerates fast in the hub, and slowly everywhere else once you
-- have gone Config.PASSIVE_REGEN_DELAY seconds without taking damage.
-- (The default Roblox regen script is replaced by StarterCharacterScripts.Health.)
local lastHealth: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastDamaged: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function regenTick(dt: number)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			-- Any drop in health (from anything) restarts the out-of-combat timer.
			if humanoid.Health < (lastHealth[player] or humanoid.Health) then
				lastDamaged[player] = now
			end
			if humanoid.Health < humanoid.MaxHealth then
				local perSecond = 0
				if
					not MatchService.isInMatch(player)
					and not player:GetAttribute("InBattleground")
				then
					perSecond = Config.HUB_REGEN_PER_SECOND
				elseif now - (lastDamaged[player] or 0) >= Config.PASSIVE_REGEN_DELAY then
					perSecond = Config.PASSIVE_REGEN_PER_SECOND
				end
				if perSecond > 0 then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + perSecond * dt)
				end
			end
			lastHealth[player] = humanoid.Health
		else
			lastHealth[player] = nil
		end
	end
end

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

-- A plain straw-coloured dummy for when the TrainingDummy block model is missing.
local function buildFallbackDummy(spot: BasePart): (Model, BasePart)
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 5, 2)
	body.Color = Color3.fromRGB(255, 204, 128)
	body.Material = Enum.Material.Fabric
	body.Anchored = true
	body.CFrame = CFrame.new(spot.Position + Vector3.new(0, 2.5, 0))
		* CFrame.Angles(0, -math.pi / 2, 0)
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
	return model, body
end

local function spawnDummy(spot: BasePart)
	-- The block-model dummy (a straw man on a post), facing east into the grove.
	local model = ModelKit.clone("TrainingDummy", "solid")
	local body: BasePart
	if model then
		model:PivotTo(
			CFrame.new(spot.Position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, -math.pi / 2, 0)
		)
		body = model:FindFirstChild("Body") :: BasePart
	else
		model, body = buildFallbackDummy(spot)
	end
	model.Name = "TrainingDummy"
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

----------------------------------------------------------------------
-- Team boxes
--
-- Each team mode (1v1..4v4) has a box with a Blue side and a Red side, one
-- spot per teammate. Players stand on a side to pick their team, so friends
-- can line up together before the match. When both sides are full a short
-- countdown runs (it resets if anyone steps off or swaps), then the match
-- starts with exactly those teams.
----------------------------------------------------------------------

type Pad = {
	part: BasePart,
	team: string,
	slots: number,
	members: { Player },
	label: TextLabel?,
}

type Box = {
	mode: string,
	pads: { Pad },
	header: TextLabel?,
	signature: string,
	startsAt: number?,
}

local boxes: { [string]: Box } = {}
local lastFullToast: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function labelOf(part: Instance): TextLabel?
	local label = part:FindFirstChild("Text", true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function collectBoxes()
	table.clear(boxes)
	for _, instance in CollectionService:GetTagged("TeamPad") do
		local mode = instance:GetAttribute("Mode")
		local team = instance:GetAttribute("Team")
		local slots = instance:GetAttribute("Slots")
		if
			instance:IsA("BasePart")
			and typeof(mode) == "string"
			and typeof(team) == "string"
			and typeof(slots) == "number"
		then
			-- A mode can have several boxes; each pad names its box.
			local boxAttribute = instance:GetAttribute("Box")
			local boxId = if typeof(boxAttribute) == "string" then boxAttribute else mode
			local box = boxes[boxId]
			if not box then
				box = { mode = mode, pads = {}, header = nil, signature = "", startsAt = nil }
				boxes[boxId] = box
			end
			table.insert(box.pads, {
				part = instance,
				team = team,
				slots = slots,
				members = {},
				label = labelOf(instance),
			})
		end
	end
	for _, header in CollectionService:GetTagged("TeamBoxHeader") do
		local boxAttribute = header:GetAttribute("Box")
		local mode = header:GetAttribute("Mode")
		local key = if typeof(boxAttribute) == "string" then boxAttribute else mode
		local box = if typeof(key) == "string" then boxes[key] else nil
		if box then
			box.header = labelOf(header)
		end
	end
end

-- True when a point is over a pad (and not far above it).
local function onPad(position: Vector3, pad: BasePart): boolean
	local p = pad.CFrame:PointToObjectSpace(position)
	local half = pad.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y > -2 and p.Y < 8
end

local function eligibleRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or MatchService.isInMatch(player) then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function startBox(box: Box)
	local players: { Player } = {}
	local teams: { [Player]: string } = {}
	for _, pad in box.pads do
		for _, player in pad.members do
			table.insert(players, player)
			teams[player] = pad.team
		end
		pad.members = {}
	end
	box.startsAt = nil
	box.signature = ""
	local ok, err = pcall(MatchService.startMatch, box.mode :: any, players, { teams = teams })
	if not ok then
		warn(`[Hub] couldn't start {box.mode} from its box: {err}`)
	end
end

local function updateBoxes()
	local now = os.clock()
	for _, box in boxes do
		local allFull = true
		local ids: { string } = {}
		for _, pad in box.pads do
			-- Re-read the size every tick so a pad's Slots attribute can be
			-- tuned (or overridden for testing) while the game runs.
			local attribute = pad.part:GetAttribute("Slots")
			pad.slots = if typeof(attribute) == "number" then attribute else pad.slots
			-- Keep who's still standing here (in arrival order), then add newcomers.
			local kept: { Player } = {}
			for _, player in pad.members do
				local root = eligibleRoot(player)
				if root and onPad(root.Position, pad.part) then
					table.insert(kept, player)
				end
			end
			for _, player in Players:GetPlayers() do
				local root = eligibleRoot(player)
				if root and not table.find(kept, player) and onPad(root.Position, pad.part) then
					if #kept < pad.slots then
						table.insert(kept, player)
					elseif (lastFullToast[player] or 0) + 3 < now then
						lastFullToast[player] = now
						toastRemote:FireClient(
							player,
							`The {pad.team} side is full. Try the other side!`,
							"fizzle"
						)
					end
				end
			end
			pad.members = kept
			if #kept < pad.slots then
				allFull = false
			end
			for _, player in kept do
				table.insert(ids, `{pad.team}:{player.UserId}`)
			end
			if pad.label then
				pad.label.Text = `{string.upper(pad.team)} {#kept}/{pad.slots}`
			end
		end

		if allFull then
			table.sort(ids)
			local signature = table.concat(ids, ",")
			if box.startsAt == nil or box.signature ~= signature then
				-- First time full, or someone swapped sides: restart the countdown.
				box.signature = signature
				box.startsAt = now + Config.TEAM_BOX_COUNTDOWN
				for _, pad in box.pads do
					for _, player in pad.members do
						toastRemote:FireClient(
							player,
							`{box.mode} starts in {Config.TEAM_BOX_COUNTDOWN}s: stay on your side!`,
							"round"
						)
					end
				end
			end
			local left = math.max(0, math.ceil((box.startsAt :: number) - now))
			if box.header then
				box.header.Text = `{box.mode}\nStarting in {left}…`
			end
			if now >= (box.startsAt :: number) then
				startBox(box)
			end
		else
			if box.startsAt ~= nil then
				box.startsAt = nil
				box.signature = ""
			end
			if box.header then
				box.header.Text = box.mode
			end
		end
	end
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
	toastRemote = Remotes.get("Toast")
end

function HubService.start()
	for _, spot in CollectionService:GetTagged("DummySpot") do
		if spot:IsA("BasePart") then
			spawnDummy(spot)
		end
	end
	collectBoxes()

	PlayerDataService.ProfileLoaded:Connect(function(player)
		MatchService.spawnInHub(player)
	end)

	DestructibleService.Knockout:Connect(function(victim)
		-- (The Battleground respawns its own fighters.)
		if not MatchService.isInMatch(victim) and not victim:GetAttribute("InBattleground") then
			task.delay(HUB_RESPAWN_DELAY, function()
				if
					victim.Parent
					and not MatchService.isInMatch(victim)
					and not victim:GetAttribute("InBattleground")
				then
					MatchService.spawnInHub(victim)
				end
			end)
		end
	end)

	task.spawn(function()
		local tick = 0
		while true do
			local dt = task.wait(0.25)
			tick += 1
			updateBoxes()
			if tick % 2 == 0 then
				regenTick(dt * 2)
			end
		end
	end)
end

return HubService
