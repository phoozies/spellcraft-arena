--!strict
-- The pre-match map vote. Owns: running one vote for a group of players
-- (Config.MAP_VOTE.MODES say which modes vote, e.g. duels), counting it, and
-- telling each voter the choices and the running tally.
--
--   * MatchService.startMatch calls `run`, which yields until the vote ends
--     (the time is up, or everyone has voted) and returns the winning map name.
--     Ties are broken at random; if nobody votes, the pick is random.
--   * The client only ever sends intent (MapVote: a map name). The server
--     checks that the sender is in the vote and the map is real, and
--     rate-limits it. A player can change their vote until the vote closes.
--   * MapVoteState goes to each voter on every change: the choices with their
--     vote counts, that player's own pick, and when the vote ends (server
--     time); `nil` closes the screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local ArenaService = require(script.Parent.ArenaService)

local MapVoteService = {}

local POLL_INTERVAL = 0.25
local VOTE_COOLDOWN = 0.15

type Vote = {
	mode: string,
	players: { Player },
	picks: { [Player]: string },
	endsAt: number,
}

local active: { [Player]: Vote } = {}
local lastVote: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local stateRemote: RemoteEvent

function MapVoteService.isVoting(player: Player): boolean
	return active[player] ~= nil
end

local function tally(vote: Vote): { [string]: number }
	local counts: { [string]: number } = {}
	for _, name in ArenaService.MAP_NAMES do
		counts[name] = 0
	end
	for _, name in vote.picks do
		counts[name] += 1
	end
	return counts
end

local function push(vote: Vote)
	local counts = tally(vote)
	local maps = {}
	for _, name in ArenaService.MAP_NAMES do
		table.insert(maps, {
			id = name,
			name = ArenaService.DISPLAY_NAMES[name] or name,
			votes = counts[name],
		})
	end
	for _, player in vote.players do
		if player.Parent then
			stateRemote:FireClient(player, {
				mode = vote.mode,
				maps = maps,
				myPick = vote.picks[player],
				endsAt = vote.endsAt,
			})
		end
	end
end

local function winner(vote: Vote): string
	local counts = tally(vote)
	local best = 0
	local leaders: { string } = {}
	for _, name in ArenaService.MAP_NAMES do
		if counts[name] > best then
			best, leaders = counts[name], { name }
		elseif counts[name] == best then
			table.insert(leaders, name)
		end
	end
	return leaders[math.random(#leaders)]
end

local function everyoneVoted(vote: Vote): boolean
	for _, player in vote.players do
		if player.Parent and not vote.picks[player] then
			return false
		end
	end
	return true
end

-- Yields until the vote is over; returns the winning map name.
function MapVoteService.run(players: { Player }, mode: string): string
	local vote: Vote = {
		mode = mode,
		players = table.clone(players),
		picks = {},
		endsAt = workspace:GetServerTimeNow() + Config.MAP_VOTE.SECONDS,
	}
	for _, player in players do
		active[player] = vote
	end
	push(vote)

	local deadline = os.clock() + Config.MAP_VOTE.SECONDS
	while os.clock() < deadline and not everyoneVoted(vote) do
		task.wait(POLL_INTERVAL)
	end
	-- Let the last pick show for a moment before the screen closes.
	if everyoneVoted(vote) then
		task.wait(1)
	end

	local result = winner(vote)
	for _, player in players do
		active[player] = nil
		if player.Parent then
			stateRemote:FireClient(player, nil)
		end
	end
	return result
end

function MapVoteService.init()
	stateRemote = Remotes.get("MapVoteState")
end

function MapVoteService.start()
	Remotes.get("MapVote").OnServerEvent:Connect(function(player, mapName: unknown)
		local vote = active[player]
		if
			not vote
			or typeof(mapName) ~= "string"
			or not table.find(ArenaService.MAP_NAMES, mapName)
		then
			return
		end
		local now = os.clock()
		if now - (lastVote[player] or 0) < VOTE_COOLDOWN then
			return
		end
		lastVote[player] = now
		if vote.picks[player] ~= mapName then
			vote.picks[player] = mapName
			push(vote)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local vote = active[player]
		if vote then
			vote.picks[player] = nil
			active[player] = nil
			table.remove(vote.players, table.find(vote.players, player))
			push(vote)
		end
	end)
end

return MapVoteService
