--!strict
-- Wins leaderboard for everyone in this server:
--   * leaderstats (Wins, Coins) on every player, so the Roblox player list
--     shows how many wins each player has;
--   * the hub's "Leaderboard" board (top Config.LEADERBOARD_ROWS by wins);
--   * the hub's winners' podium: avatars of the top 3 players by wins on the
--     gold / silver / bronze pedestals (parts tagged "PodiumSpot", Rank 1-3,
--     built by Maps/InkwellPlaza), with rank, name and wins on each
--     pedestal's front ("Text" label).
-- Wins and coins come from the saved profile (EconomyService is the only
-- writer); this service only displays them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local EconomyService = require(script.Parent.EconomyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local LeaderboardService = {}

-- Avatar rigs are fetched from the web once per user and reused.
local avatarCache: { [number]: Model } = {}
-- Rank -> userId currently standing on that pedestal (0 = empty).
local shown: { [number]: number } = {}
local dirty = true

local function statOf(player: Player, name: string): IntValue?
	local folder = player:FindFirstChild("leaderstats")
	local value = folder and folder:FindFirstChild(name)
	return if value and value:IsA("IntValue") then value else nil
end

local function ensureStats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, name in { "Wins", "Coins" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = folder
	end
	folder.Parent = player
end

local function syncStats(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile or not player.Parent then
		return
	end
	ensureStats(player)
	local wins, coins = statOf(player, "Wins"), statOf(player, "Coins")
	if wins then
		wins.Value = profile.stats.wins
	end
	if coins then
		coins.Value = profile.coins
	end
	dirty = true
end

-- Everyone in the server, most wins first (ties: alphabetical).
function LeaderboardService.ranking(): { Types.LeaderRow }
	local rows: { Types.LeaderRow } = {}
	for _, player in Players:GetPlayers() do
		local profile = PlayerDataService.get(player)
		if profile then
			table.insert(rows, {
				userId = player.UserId,
				name = player.DisplayName,
				wins = profile.stats.wins,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.wins ~= b.wins then
			return a.wins > b.wins
		end
		return a.name < b.name
	end)
	return rows
end

local function updateBoard(rows: { Types.LeaderRow })
	for _, board in CollectionService:GetTagged("WinsBoard") do
		local label = board:FindFirstChild("Text", true)
		if label and label:IsA("TextLabel") then
			local lines = { "🏆 Most Wins" }
			for i = 1, math.min(Config.LEADERBOARD_ROWS, #rows) do
				table.insert(lines, `{i}. {rows[i].name}: {rows[i].wins}`)
			end
			if #rows == 0 then
				table.insert(lines, "(win a match!)")
			end
			label.Text = table.concat(lines, "\n")
		end
	end
end

local function avatarFor(userId: number): Model?
	local cached = avatarCache[userId]
	if cached then
		return cached
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not model then
		return nil
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
		elseif part:IsA("Script") or part:IsA("LocalScript") then
			part:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	avatarCache[userId] = model
	return model
end

local function spotLabel(spot: BasePart): TextLabel?
	local label = spot:FindFirstChild("Text", true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function updatePodium(rows: { Types.LeaderRow })
	for _, spot in CollectionService:GetTagged("PodiumSpot") do
		local rank = spot:GetAttribute("Rank")
		if not spot:IsA("BasePart") or typeof(rank) ~= "number" then
			continue
		end
		local row = rows[rank]
		-- Only players with at least one win earn a pedestal.
		if row and row.wins <= 0 then
			row = nil
		end
		local label = spotLabel(spot)
		if label then
			label.Text = if row
				then `#{rank} {row.name}\n{row.wins} wins`
				else `#{rank}\nWin a match to stand here!`
		end
		local userId = if row then row.userId else 0
		if shown[rank] == userId then
			continue
		end
		shown[rank] = userId
		local old = spot:FindFirstChild("Avatar")
		if old then
			-- Keep it cached (it may stand on another pedestal later) unless
			-- its player has left the server.
			old.Parent = nil
			local oldId = old:GetAttribute("UserId")
			if typeof(oldId) == "number" and not Players:GetPlayerByUserId(oldId) then
				avatarCache[oldId] = nil
				old:Destroy()
			end
		end
		if row then
			local avatar = avatarFor(row.userId)
			if avatar and shown[rank] == row.userId then
				avatar.Name = "Avatar"
				avatar:SetAttribute("UserId", row.userId)
				-- Stand on the pedestal top, facing the plaza (+Z): place it,
				-- then lift it so its feet touch the top.
				local top = spot.Position + Vector3.new(0, spot.Size.Y / 2, 0)
				avatar:PivotTo(CFrame.lookAt(top, top + Vector3.new(0, 0, 1)))
				local box, size = avatar:GetBoundingBox()
				local lift = top.Y - (box.Position.Y - size.Y / 2)
				avatar:PivotTo(avatar:GetPivot() + Vector3.new(0, lift, 0))
				avatar.Parent = spot
			end
		end
	end
end

function LeaderboardService.refresh()
	dirty = false
	local rows = LeaderboardService.ranking()
	updateBoard(rows)
	updatePodium(rows)
end

function LeaderboardService.start()
	EconomyService.Changed:Connect(syncStats)
	PlayerDataService.ProfileLoaded:Connect(function(player)
		syncStats(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty = true
		-- Free the cached rig unless it's on a pedestal right now.
		local rig = avatarCache[player.UserId]
		if rig and rig.Parent == nil then
			rig:Destroy()
			avatarCache[player.UserId] = nil
		end
	end)
	task.spawn(function()
		while true do
			if dirty then
				-- Avatar fetches yield; never let one failure stop the loop.
				local ok, err = pcall(LeaderboardService.refresh)
				if not ok then
					warn(`[Leaderboard] refresh failed: {err}`)
				end
			end
			task.wait(Config.LEADERBOARD_REFRESH)
		end
	end)
end

return LeaderboardService
