--!strict
-- Queues and the match state machine.
--
--   Queue -> Countdown -> Round -> (Draft -> Countdown -> Round)* -> Results -> Hub
--
-- * Best of 3 rounds (Config.ROUNDS_TO_WIN). Each player's spellbook is the
--   five spells of their equipped element. The draft after each round
--   offers match boosts (Power, Vitality, ...), not spells (BoostService).
-- * Teams: "Blue" / "Red".
-- * Owns the PvP relation rules used by DestructibleService and the world
--   hooks used by CastService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Boosts = require(ReplicatedStorage.Shared.Match.Boosts)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local ArenaService = require(script.Parent.ArenaService)
local BoostService = require(script.Parent.BoostService)
local ElementService = require(script.Parent.ElementService)
local CastService = require(script.Parent.CastService)
local DestructibleService = require(script.Parent.DestructibleService)
local HandService = require(script.Parent.HandService)
local MapVoteService = require(script.Parent.MapVoteService)
local PartyService = require(script.Parent.PartyService)
local SpellInputService = require(script.Parent.SpellInputService)
local PracticeZone = require(ReplicatedStorage.Shared.Util.PracticeZone)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local StatusService = require(script.Parent.StatusService)
local Rescue = require(script.Parent.Rescue)
local TelemetryService = require(script.Parent.TelemetryService)
local Funnels = require(ReplicatedStorage.Shared.Analytics.Funnels)

type Match = {
	id: number,
	sessionId: string, -- the analytics funnel's id for this match
	mode: Types.MatchMode,
	solo: boolean,
	arena: ArenaService.Arena,
	players: { Player },
	teams: { [Player]: string },
	teamNames: { [string]: string },
	teamOrder: { string },
	phase: Types.MatchPhase,
	round: number,
	endsAt: number,
	roundWins: { [string]: number },
	alive: { [Player]: boolean },
	pads: { [Player]: Vector3 }, -- where each player spawned this round (water and pit rescues land here)
	knockouts: { [Player]: number },
	coins: { [Player]: number }, -- coins earned this match (shown on Results)
	offers: { [Player]: { Types.DraftCard } },
	ended: boolean,
	lastRoundWinner: string?,
	winner: string?,
}

local MatchService = {}

-- Fired with (player, mode) when someone joins/leaves a queue, for UI.
MatchService.QueueChanged = Signal.new()

local queues: { [string]: { Player } } = { ["1v1"] = {}, ["2v2"] = {}, ["3v3"] = {}, ["4v4"] = {} }
local ffaReadySince: number? = nil
local playerMatch: { [Player]: Match } = {}
-- Players waiting on a map vote before their match is created.
local votingPlayers: { [Player]: boolean } = {}
local matchCounter = 0

local stateRemote: RemoteEvent
local draftRemote: RemoteEvent
local toastRemote: RemoteEvent
local knockoutRemote: RemoteEvent
local countsRemote: RemoteEvent

local TEAM_SPAWN_GROUP = { Blue = "Team1", Red = "Team2" }
-- Seconds between checks while a round is on (waitPhase's wait).
local ROUND_TICK = 0.25

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function shuffle<T>(list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function hubSpawnCFrame(): CFrame
	local spawn = CollectionService:GetTagged("HubSpawn")[1]
	if spawn and spawn:IsA("BasePart") then
		local offset = Vector3.new(math.random(-4, 4), 4, math.random(-4, 4))
		return CFrame.new(spawn.Position + offset)
	end
	return CFrame.new(0, 10, 0)
end

local function protect(character: Model)
	local field = Instance.new("ForceField")
	field.Visible = true
	field.Parent = character
	Debris:AddItem(field, Config.SPAWN_PROTECTION)
end

-- Loads a fresh character and moves it to `cframe` once it exists.
local function spawnAt(player: Player, cframe: CFrame, frozen: boolean)
	if player.Parent == nil then
		return
	end
	player:LoadCharacter()
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(cframe)
	protect(character)
	-- Everyone fights at the same 100 HP; our HUD and overhead bars replace
	-- Roblox's default health display.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = Config.PLAYER_MAX_HEALTH
		humanoid.Health = Config.PLAYER_MAX_HEALTH
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.WalkSpeed = Config.WALK_SPEED
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Config.JUMP_POWER
	end
	if frozen then
		StatusService.setFrozen(character, true)
	end
end

-- Moves a living character somewhere (a Battleground drop-in) with a short
-- spawn shield, without reloading it.
function MatchService.teleport(player: Player, cframe: CFrame)
	local character = player.Character
	if character then
		character:PivotTo(cframe)
		protect(character)
		character:SetAttribute("Team", nil)
	end
end

-- Reloads a player's character at `cframe` (a Battleground respawn).
function MatchService.respawnAt(player: Player, cframe: CFrame)
	spawnAt(player, cframe, false)
end

function MatchService.spawnInHub(player: Player)
	spawnAt(player, hubSpawnCFrame(), false)
	local character = player.Character
	if character then
		character:SetAttribute("Team", nil)
	end
end

-- Team ids: "Blue" / "Red".
local function teamDisplay(match: Match, team: string): string
	return match.teamNames[team] or team
end

local function sendState(match: Match)
	local scores: { [string]: number } = {}
	for _, team in match.teamOrder do
		scores[teamDisplay(match, team)] = match.roundWins[team] or 0
	end
	local roster: { Types.RosterEntry } = {}
	for _, player in match.players do
		table.insert(roster, {
			userId = player.UserId,
			name = player.DisplayName,
			team = teamDisplay(match, match.teams[player]),
		})
	end
	local results = match.phase == "Results"
	for _, player in match.players do
		if player.Parent then
			local state: Types.MatchState = {
				phase = match.phase,
				mode = match.mode,
				mapName = ArenaService.DISPLAY_NAMES[match.arena.mapName],
				round = match.round,
				endsAt = match.endsAt,
				scores = scores,
				myTeam = teamDisplay(match, match.teams[player]),
				myTeamId = match.teams[player],
				roster = roster,
				roundWinner = if match.lastRoundWinner
					then teamDisplay(match, match.lastRoundWinner)
					else nil,
				winner = if results and match.winner then teamDisplay(match, match.winner) else nil,
				won = if results
					then match.winner ~= nil and match.teams[player] == match.winner
					else nil,
				coinsGained = if results then match.coins[player] or 0 else nil,
			}
			stateRemote:FireClient(player, state)
		end
	end
end

local function toastAll(match: Match, message: string, kind: string)
	for _, player in match.players do
		if player.Parent then
			toastRemote:FireClient(player, message, kind)
		end
	end
end

local function connected(match: Match): { Player }
	local list = {}
	for _, player in match.players do
		if player.Parent and playerMatch[player] == match then
			table.insert(list, player)
		end
	end
	return list
end

local function aliveTeams(match: Match): { string }
	local seen: { [string]: boolean } = {}
	local list = {}
	for _, player in connected(match) do
		if match.alive[player] then
			local team = match.teams[player]
			if not seen[team] then
				seen[team] = true
				table.insert(list, team)
			end
		end
	end
	return list
end

local function teamHealth(match: Match, team: string): number
	local total = 0
	for _, player in connected(match) do
		if match.teams[player] == team and match.alive[player] then
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				total += humanoid.Health
			end
		end
	end
	return total
end

local function grantCoins(match: Match, player: Player, amount: number)
	match.coins[player] = (match.coins[player] or 0) + amount
end

----------------------------------------------------------------------
-- Relations (who can hurt whom) and world hooks for casting
----------------------------------------------------------------------

local function relation(attacker: Player?, victimOwner: Player?, target: Instance): boolean
	if victimOwner == nil then
		if target:GetAttribute("Dummy") then
			return true
		end
		-- Battleground NPCs: fair game for anyone inside the Battleground.
		if target:GetAttribute("Hostile") then
			return attacker == nil or attacker:GetAttribute("InBattleground") == true
		end
		-- Unowned map props: breakable only by players in that arena's match.
		if attacker then
			local match = playerMatch[attacker]
			return match ~= nil
				and match.phase == "Round"
				and target:IsDescendantOf(match.arena.model)
		end
		return true
	end
	if attacker == nil then
		return true
	end
	-- Everyone inside the Battleground may hurt everyone else inside it,
	-- except their own party.
	if attacker:GetAttribute("InBattleground") and victimOwner:GetAttribute("InBattleground") then
		return not PartyService.sameParty(attacker, victimOwner)
	end
	local a, b = playerMatch[attacker], playerMatch[victimOwner]
	if a or b then
		return a == b
			and a ~= nil
			and a.phase == "Round"
			and a.teams[attacker] ~= a.teams[victimOwner]
	end
	-- No PvP in the hub; players fight in matches and in the Battleground.
	return false
end

local function areAllies(a: Player, b: Player): boolean
	if a:GetAttribute("InBattleground") and b:GetAttribute("InBattleground") then
		return PartyService.sameParty(a, b)
	end
	local match = playerMatch[a]
	return match ~= nil and match == playerMatch[b] and match.teams[a] == match.teams[b]
end

local hubStructures: Folder

local function buildZones(): { BasePart }
	local zones = {}
	for _, zone in CollectionService:GetTagged("BuildZone") do
		if zone:IsA("BasePart") then
			table.insert(zones, zone)
		end
	end
	return zones
end

----------------------------------------------------------------------
-- Match flow
----------------------------------------------------------------------

local function spawnRound(match: Match)
	local indexByGroup: { [string]: number } = {}
	for _, player in connected(match) do
		local team = match.teams[player]
		local group = TEAM_SPAWN_GROUP[team]
		indexByGroup[group] = (indexByGroup[group] or 0) + 1
		local spawn = ArenaService.spawnCFrame(match.arena, group, indexByGroup[group])
		match.pads[player] = spawn.Position
		spawnAt(player, spawn, true)
		BoostService.applyToCharacter(player)
		match.alive[player] = true
		local character = player.Character
		if character then
			character:SetAttribute("Team", team)
		end
		-- Every round starts empty-handed: draw to summon your spells.
		HandService.resetCooldowns(player)
		HandService.clearCopies(player)
	end
end

local function waitPhase(
	match: Match,
	phase: Types.MatchPhase,
	seconds: number,
	stopEarly: (() -> boolean)?
)
	match.phase = phase
	match.endsAt = workspace:GetServerTimeNow() + seconds
	sendState(match)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and not match.ended do
		if stopEarly and stopEarly() then
			break
		end
		task.wait(ROUND_TICK)
	end
end

local function runDraft(match: Match)
	local rng = Random.new()
	local anyOffers = false
	for _, player in connected(match) do
		local ids = BoostService.roll(player, rng)
		if #ids > 0 then
			local cards: { Types.DraftCard } = {}
			for _, id in ids do
				table.insert(cards, { boostId = id })
			end
			match.offers[player] = cards
			anyOffers = true
			draftRemote:FireClient(player, cards, workspace:GetServerTimeNow() + Config.DRAFT_TIME)
		end
	end
	if not anyOffers then
		return
	end
	waitPhase(match, "Draft", Config.DRAFT_TIME, function()
		return next(match.offers) == nil
	end)
	-- Auto-pick for anyone who didn't choose.
	for player, cards in match.offers do
		if player.Parent and #cards > 0 then
			local card = cards[math.random(1, #cards)]
			BoostService.pick(player, card.boostId)
			local boost = Boosts.get(card.boostId)
			toastRemote:FireClient(
				player,
				`Auto-picked {if boost then boost.name else card.boostId}`,
				"ready"
			)
		end
	end
	table.clear(match.offers)
	for _, player in connected(match) do
		draftRemote:FireClient(player, {}, 0) -- closes any open draft UI
	end
end

local function playRound(match: Match): string?
	waitPhase(match, "Countdown", Config.COUNTDOWN_TIME)
	if match.ended then
		return nil
	end
	for _, player in connected(match) do
		if player.Character then
			StatusService.setFrozen(player.Character, false)
		end
	end
	local winner: string? = nil
	waitPhase(match, "Round", Config.ROUND_TIME, function()
		for _, player in connected(match) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local pad = match.pads[player]
			if character and root and humanoid and humanoid.Health > 0 then
				if pad and ArenaService.isInWater(match.arena, root.Position) then
					-- Fell off the edge (however far past the water by now): splash,
					-- then thrown back onto the spawn pad.
					Rescue.water(player, character, pad + Vector3.new(0, 3, 0))
				elseif ArenaService.isBelowVoid(match.arena, root.Position) then
					-- No pad to return to: a plain ring-out.
					humanoid.Health = 0
				elseif pad then
					-- Stuck at the bottom of a hole in the terrain: thrown out.
					Rescue.checkPit(player, character, pad + Vector3.new(0, 3, 0), ROUND_TICK)
				end
			end
		end
		local teams = aliveTeams(match)
		if match.solo then
			return #teams == 0
		end
		if #teams <= 1 then
			winner = teams[1]
			return true
		end
		return false
	end)
	if match.ended then
		return nil
	end
	if winner == nil then
		-- Time ran out (or solo test): most remaining health wins.
		local best = -1
		for _, team in aliveTeams(match) do
			local hp = teamHealth(match, team)
			if hp > best then
				best, winner = hp, team
			end
		end
	end
	return winner
end

local function finishMatch(match: Match, winner: string?)
	if match.ended then
		return
	end
	match.ended = true
	match.winner = winner
	match.phase = "Results"
	match.endsAt = workspace:GetServerTimeNow() + Config.RESULTS_TIME

	for _, player in connected(match) do
		local won = winner ~= nil and match.teams[player] == winner
		local profile = PlayerDataService.get(player)
		if profile then
			profile.stats.matches += 1
			profile.stats.knockouts += match.knockouts[player] or 0
		end
		EconomyService.track(player, "match")
		Rescue.clear(player)
		TelemetryService.matchStep(player, match.sessionId, "Finished")
		if not match.solo then
			TelemetryService.onboarding(player, "FirstMatchFinished")
			if won then
				TelemetryService.onboarding(player, "FirstWin")
			end
		end
		-- Coins are earned by winning (no XP or levels). A solo test match
		-- (admin/debug) never pays out.
		if won and not match.solo then
			grantCoins(match, player, Config.COINS.MATCH_WIN)
			EconomyService.recordWin(player)
			EconomyService.track(player, "win")
			if EconomyService.consumeFirstWin(player) then
				grantCoins(match, player, Config.COINS.FIRST_WIN_OF_DAY)
				toastRemote:FireClient(
					player,
					`First win of the day! +{Config.COINS.FIRST_WIN_OF_DAY} bonus coins`,
					"reward"
				)
			end
		end
		-- The Victory/Defeat screen (client PresentationController) shows the
		-- result and coins from the Results state below.
		EconomyService.addCoins(player, match.coins[player] or 0, "match")
	end
	sendState(match)

	task.delay(Config.RESULTS_TIME, function()
		for _, player in match.players do
			if playerMatch[player] == match then
				playerMatch[player] = nil
				BoostService.reset(player)
				if player.Parent then
					HandService.clearMatch(player)
					MatchService.spawnInHub(player)
					stateRemote:FireClient(
						player,
						{
							phase = "Idle",
							round = 0,
							endsAt = 0,
							scores = {},
						} :: Types.MatchState
					)
				end
			end
		end
		ArenaService.destroy(match.arena)
	end)
end

local function runMatch(match: Match)
	local winner: string? = nil
	-- VS intro while everyone is still in the hub; clients fade to black
	-- at the end of it, then we move them into the arena.
	waitPhase(match, "Intro", Config.INTRO_TIME)
	if match.ended then
		return
	end
	for _, player in connected(match) do
		TelemetryService.matchStep(player, match.sessionId, "Started")
		if not match.solo then
			TelemetryService.onboarding(player, "FirstMatchStarted")
		end
	end
	while not match.ended do
		match.round += 1
		if match.round > 1 then
			match.arena = ArenaService.rebuild(match.arena)
		end
		spawnRound(match)
		local roundWinner = playRound(match)
		if match.ended then
			return
		end
		if match.round == 1 then
			for _, player in connected(match) do
				TelemetryService.matchStep(player, match.sessionId, "Round1Done")
			end
		end
		-- Clients show the round banner ("BLUE WINS ROUND 1" / "DRAW") from this.
		match.lastRoundWinner = roundWinner
		if roundWinner then
			match.roundWins[roundWinner] = (match.roundWins[roundWinner] or 0) + 1
			if match.roundWins[roundWinner] >= Config.ROUNDS_TO_WIN then
				winner = roundWinner
				break
			end
		end
		if match.round >= Config.ROUNDS_TO_WIN * 2 + 1 then
			break -- safety cap for repeated draws
		end
		sendState(match)
		runDraft(match)
	end
	finishMatch(match, winner)
end

-- `options.teams` (team modes only) maps each player to "Blue" or "Red", for
-- premade teams (the hub's team boxes); otherwise teams are shuffled.
function MatchService.startMatch(
	mode: Types.MatchMode,
	players: { Player },
	options: { solo: boolean?, teams: { [Player]: string }?, map: string? }?
)
	-- Duels (Config.MAP_VOTE.MODES) vote on the map first; the match then
	-- starts again with the winner. Solo tests and forced maps skip the vote.
	if (Config.MAP_VOTE.MODES :: any)[mode] and not (options and (options.solo or options.map)) then
		for _, player in players do
			MatchService.leaveQueue(player)
			votingPlayers[player] = true
		end
		task.spawn(function()
			local map = MapVoteService.run(players, mode)
			local here = true
			for _, player in players do
				votingPlayers[player] = nil
				if
					player.Parent == nil
					or playerMatch[player]
					or player:GetAttribute("InBattleground")
				then
					here = false
				end
			end
			if not here then
				for _, player in players do
					if player.Parent then
						toastRemote:FireClient(
							player,
							"Your opponent left, so the match was cancelled.",
							"fizzle"
						)
					end
				end
				return
			end
			local forced: { teams: { [Player]: string }?, map: string? } =
				{ teams = options and options.teams, map = map }
			MatchService.startMatch(mode, players, forced)
		end)
		return
	end

	matchCounter += 1
	local requested = options and options.map
	local mapName = if requested and table.find(ArenaService.MAP_NAMES, requested)
		then requested :: string
		else ArenaService.pickMap(mode)
	local arena = ArenaService.create(mapName, mode)
	local match: Match = {
		id = matchCounter,
		sessionId = TelemetryService.newSessionId(),
		mode = mode,
		solo = options ~= nil and options.solo == true,
		arena = arena,
		players = players,
		teams = {},
		teamNames = {},
		teamOrder = {},
		phase = "Countdown",
		round = 0,
		endsAt = 0,
		roundWins = {},
		alive = {},
		pads = {},
		knockouts = {},
		coins = {},
		offers = {},
		ended = false,
	}
	match.teamOrder = { "Blue", "Red" }
	local chosen = options and options.teams
	for i, player in shuffle(players) do
		local team = chosen and chosen[player]
		match.teams[player] = if team == "Blue" or team == "Red"
			then team
			else if i % 2 == 1 then "Blue" else "Red"
	end

	for _, player in players do
		MatchService.leaveQueue(player)
		player:SetAttribute("InBattleground", nil) -- a match pulls you out of the Battleground
		playerMatch[player] = match
		-- Everyone fights with their equipped element; anyone who never picked
		-- one gets a random element for now.
		local elementId = ElementService.equipped(player)
		if not elementId then
			local all = Elements.ids()
			elementId = all[math.random(1, #all)]
			ElementService.grant(player, elementId)
			EconomyService.sendSummary(player)
			toastRemote:FireClient(player, `You fight with {elementId}!`, "reward")
		end
		BoostService.reset(player)
		-- The match spellbook is the player's loadout: their element's base
		-- spells plus their equipped crate spells.
		HandService.setSpellbook(player, ElementService.loadout(player))
		toastRemote:FireClient(
			player,
			`Match found: {mode} on {ArenaService.DISPLAY_NAMES[arena.mapName]}!`,
			"round"
		)
	end
	task.spawn(runMatch, match)
end

----------------------------------------------------------------------
-- Queues
----------------------------------------------------------------------

local lastCounts = ""

local function broadcastCounts()
	local counts: { [string]: number } = {}
	local key = ""
	for mode, list in queues do
		counts[mode] = #list
		key ..= mode .. #list
	end
	if key ~= lastCounts then
		lastCounts = key
		countsRemote:FireAllClients(counts)
		MatchService.QueueChanged:Fire()
	end
end

function MatchService.queueCounts(): { [string]: number }
	local counts = {}
	for mode, list in queues do
		counts[mode] = #list
	end
	return counts
end

function MatchService.queuedMode(player: Player): string?
	for mode, list in queues do
		if table.find(list, player) then
			return mode
		end
	end
	return nil
end

function MatchService.leaveQueue(player: Player)
	for _, list in queues do
		local index = table.find(list, player)
		if index then
			table.remove(list, index)
		end
	end
	broadcastCounts()
end

function MatchService.joinQueue(player: Player, mode: string): boolean
	if not queues[mode] or playerMatch[player] or votingPlayers[player] then
		return false
	end
	if player:GetAttribute("InBattleground") then
		toastRemote:FireClient(
			player,
			"Leave the Battleground first (use a green gate or Return to Hub).",
			"fizzle"
		)
		return false
	end
	if MatchService.queuedMode(player) == mode then
		return true
	end
	MatchService.leaveQueue(player)
	table.insert(queues[mode], player)
	toastRemote:FireClient(player, `Joined the {mode} queue`, "info")
	broadcastCounts()
	return true
end

-- Where drawing is allowed: in the Battleground, in the hub's Training Grove, and
-- in a match once the round is on (not elsewhere in the hub, nor in the intro,
-- the countdown, the draft, or the results).
-- Installed into SpellInputService as its draw gate.
function MatchService.canDraw(player: Player): (boolean, string?)
	if player:GetAttribute("InBattleground") then
		return true, nil
	end
	local match = playerMatch[player]
	if match and match.phase == "Round" then
		return true, nil
	end
	if match then
		return false, "Hold on, you can draw when the round starts!"
	end
	-- The hub's Training Grove.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and not votingPlayers[player] and PracticeZone.contains(root.Position) then
		return true, nil
	end
	return false, "You can only draw in the Training Grove, duels, and the Battleground."
end

-- True from the map vote until the match ends, so nothing else (a queue, a
-- team box, the Battleground) can grab a player the match is waiting on.
function MatchService.isInMatch(player: Player): boolean
	return playerMatch[player] ~= nil or votingPlayers[player] == true
end

-- Takes a player out of their match (leaving the game, or the admin ;hub
-- command). If only one team is left it wins by forfeit; if nobody is
-- left the match just ends.
function MatchService.removeFromMatch(player: Player)
	local match = playerMatch[player]
	if not match then
		return
	end
	playerMatch[player] = nil
	match.alive[player] = false
	match.offers[player] = nil
	Rescue.clear(player)
	if not match.ended and not match.solo then
		TelemetryService.event(player, Funnels.EVENTS.MatchAbandoned, match.round)
	end
	BoostService.reset(player)
	if player.Parent then
		HandService.clearMatch(player)
		stateRemote:FireClient(player, { phase = "Idle", round = 0, endsAt = 0, scores = {} })
	end
	local remaining: { [string]: boolean } = {}
	local count = 0
	for _, other in connected(match) do
		if not remaining[match.teams[other]] then
			remaining[match.teams[other]] = true
			count += 1
		end
	end
	if count == 0 then
		finishMatch(match, nil)
	elseif count == 1 and not match.solo then
		local winner = next(remaining)
		toastAll(match, "Opponent left — you win by forfeit!", "victory")
		finishMatch(match, winner)
	end
end

-- Admin: end the match a player is in, with no winner.
function MatchService.endMatchOf(player: Player)
	local match = playerMatch[player]
	if match then
		toastAll(match, "An admin ended this match.", "round")
		finishMatch(match, nil)
	end
end

local function processQueues()
	for mode, list in queues do
		for i = #list, 1, -1 do
			if list[i].Parent == nil or playerMatch[list[i]] then
				table.remove(list, i)
			end
		end
		local info = (Config.MODES :: any)[mode]
		local needed = info.teams * info.perTeam
		while #list >= needed do
			local group = {}
			for i = 1, needed do
				table.insert(group, list[i])
			end
			MatchService.startMatch(mode :: Types.MatchMode, group)
		end
	end
	broadcastCounts()
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function MatchService.init()
	stateRemote = Remotes.get("MatchStateChanged")
	draftRemote = Remotes.get("DraftOffered")
	toastRemote = Remotes.get("Toast")
	knockoutRemote = Remotes.get("Knockout")
	countsRemote = Remotes.get("QueueCounts")

	hubStructures = Instance.new("Folder")
	hubStructures.Name = "HubStructures"
	hubStructures.Parent = workspace

	DestructibleService.setRelationResolver(relation)
	SpellInputService.setDrawGate(MatchService.canDraw)
	CastService.setWorldHooks({
		teamOf = function(player)
			local match = playerMatch[player]
			return if match then match.teams[player] else nil
		end,
		structuresFolderFor = function(player)
			local match = playerMatch[player]
			return if match then match.arena.structures else hubStructures
		end,
		buildRegionsFor = function(player)
			local match = playerMatch[player]
			return if match then { match.arena.bounds } else buildZones()
		end,
		areAllies = areAllies,
	})
end

function MatchService.start()
	-- Throttled: each change broadcasts queue counts to every player.
	local lastQueueChange: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
	Remotes.get("SetQueue").OnServerEvent:Connect(function(player, mode)
		local now = os.clock()
		if now - (lastQueueChange[player] or 0) < 1 then
			return
		end
		lastQueueChange[player] = now
		if mode == nil then
			MatchService.leaveQueue(player)
			toastRemote:FireClient(player, "Left the queue", "info")
		elseif typeof(mode) == "string" then
			MatchService.joinQueue(player, mode)
		end
	end)

	Remotes.get("PickDraft").OnServerEvent:Connect(function(player, index)
		local match = playerMatch[player]
		if not match or match.phase ~= "Draft" or typeof(index) ~= "number" then
			return
		end
		local cards = match.offers[player]
		local card = cards and cards[math.floor(index)]
		if not card then
			return
		end
		match.offers[player] = nil
		if BoostService.pick(player, card.boostId) then
			local boost = Boosts.get(card.boostId)
			toastRemote:FireClient(
				player,
				`{if boost then boost.name else card.boostId} boost! {if boost
					then boost.description
					else ""}`,
				"reward"
			)
			EconomyService.track(player, "boost")
		end
	end)

	DestructibleService.Knockout:Connect(function(victim, killer, spellName)
		local match = playerMatch[victim]
		if not match then
			return
		end
		match.alive[victim] = false
		if killer and playerMatch[killer] == match and killer ~= victim then
			match.knockouts[killer] = (match.knockouts[killer] or 0) + 1
			EconomyService.track(killer, "knockout")
			local streak = match.knockouts[killer]
			if streak == 3 then
				toastAll(match, `{killer.DisplayName} is on a SPELL STREAK!`, "streak")
			end
		end
		for _, player in connected(match) do
			knockoutRemote:FireClient(
				player,
				if killer then killer.DisplayName else nil,
				victim.DisplayName,
				spellName
			)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		MatchService.leaveQueue(player)
		MatchService.removeFromMatch(player)
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			processQueues()
		end
	end)
end

return MatchService
