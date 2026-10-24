--!strict
-- Queues and the match state machine.
--
--   Queue -> Countdown -> Round -> (Draft -> Countdown -> Round)* -> Results -> Hub
--
-- * Best of 3 rounds (Config.ROUNDS_TO_WIN). Each player's hand starts as 3
--   random owned spells and gains +1 from the draft after each round (max 5).
-- * Teams: "Blue" / "Red" for 1v1, 2v2, 4v4; FFA puts every player on their
--   own team (their name).
-- * Owns the PvP relation rules used by DestructibleService and the world
--   hooks used by CastService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local DraftRoller = require(ReplicatedStorage.Shared.Match.DraftRoller)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local ArenaService = require(script.Parent.ArenaService)
local CastService = require(script.Parent.CastService)
local DestructibleService = require(script.Parent.DestructibleService)
local HandService = require(script.Parent.HandService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local StatusService = require(script.Parent.StatusService)

type Match = {
	id: number,
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
	knockouts: { [Player]: number },
	xp: { [Player]: number },
	offers: { [Player]: { Types.DraftCard } },
	ended: boolean,
	lastRoundWinner: string?,
	winner: string?,
}

local MatchService = {}

-- Fired with (player, mode) when someone joins/leaves a queue, for UI.
MatchService.QueueChanged = Signal.new()

local queues: { [string]: { Player } } = { ["1v1"] = {}, ["2v2"] = {}, ["4v4"] = {}, ["FFA"] = {} }
local ffaReadySince: number? = nil
local playerMatch: { [Player]: Match } = {}
local matchCounter = 0

-- Session leaderboard (resets when the server restarts).
MatchService.sessionKnockouts = {} :: { [Player]: number }

local stateRemote: RemoteEvent
local draftRemote: RemoteEvent
local toastRemote: RemoteEvent
local knockoutRemote: RemoteEvent
local countsRemote: RemoteEvent

local TEAM_SPAWN_GROUP = { Blue = "Team1", Red = "Team2" }

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

function MatchService.spawnInHub(player: Player)
	spawnAt(player, hubSpawnCFrame(), false)
	local character = player.Character
	if character then
		character:SetAttribute("Team", nil)
	end
end

-- Team ids: "Blue"/"Red", or a player's UserId in FFA (display names aren't unique).
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
				xpGained = if results then match.xp[player] or 0 else nil,
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

local function grantXp(match: Match, player: Player, amount: number)
	match.xp[player] = (match.xp[player] or 0) + amount
end

----------------------------------------------------------------------
-- Relations (who can hurt whom) and world hooks for casting
----------------------------------------------------------------------

local function inSparring(player: Player): boolean
	return player:GetAttribute("InSparring") == true
end

local function relation(attacker: Player?, victimOwner: Player?, target: Instance): boolean
	if victimOwner == nil then
		if target:GetAttribute("Dummy") then
			return true
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
	local a, b = playerMatch[attacker], playerMatch[victimOwner]
	if a or b then
		return a == b
			and a ~= nil
			and a.phase == "Round"
			and a.teams[attacker] ~= a.teams[victimOwner]
	end
	-- Hub: PvP only inside the sparring ring.
	return inSparring(attacker) and inSparring(victimOwner)
end

local function areAllies(a: Player, b: Player): boolean
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
		local group = if match.mode == "FFA" then "FFA" else TEAM_SPAWN_GROUP[team]
		indexByGroup[group] = (indexByGroup[group] or 0) + 1
		spawnAt(player, ArenaService.spawnCFrame(match.arena, group, indexByGroup[group]), true)
		match.alive[player] = true
		local character = player.Character
		if character then
			character:SetAttribute("Team", team)
		end
		-- Every round starts empty-handed: type to summon your spells.
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
		task.wait(0.25)
	end
end

local function runDraft(match: Match)
	local rng = Random.new()
	local anyOffers = false
	for _, player in connected(match) do
		local hand = HandService.getSpellbook(player) or {}
		if #hand < Config.MAX_HAND then
			local cards = DraftRoller.roll(hand, rng)
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
			HandService.addToSpellbook(player, card.spellId)
			local def = SpellDefinitions.get(card.spellId)
			toastRemote:FireClient(
				player,
				`Auto-picked {if def then def.name else card.spellId}`,
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
		-- Ring-outs: anyone who fell into the void is knocked out.
		for _, player in connected(match) do
			local root = player.Character
				and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if
				root
				and humanoid
				and humanoid.Health > 0
				and ArenaService.isBelowVoid(match.arena, root.Position)
			then
				humanoid.Health = 0
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
		grantXp(match, player, Config.XP.PARTICIPATION)
		local won = winner ~= nil and match.teams[player] == winner
		local profile = PlayerDataService.get(player)
		if profile then
			profile.stats.matches += 1
			profile.stats.knockouts += match.knockouts[player] or 0
		end
		ProgressionService.track(player, "match")
		if won then
			grantXp(match, player, Config.XP.MATCH_WIN)
			if profile then
				profile.stats.wins += 1
			end
			ProgressionService.track(player, "win")
			if ProgressionService.consumeFirstWin(player) then
				grantXp(match, player, Config.XP.FIRST_WIN_OF_DAY)
				toastRemote:FireClient(
					player,
					`First win of the day! +{Config.XP.FIRST_WIN_OF_DAY} XP`,
					"reward"
				)
			end
		end
		-- The Victory/Defeat screen (client PresentationController) shows the
		-- result and XP from the Results state below.
		ProgressionService.addXp(player, match.xp[player] or 0, "match")
	end
	sendState(match)

	task.delay(Config.RESULTS_TIME, function()
		for _, player in match.players do
			if playerMatch[player] == match then
				playerMatch[player] = nil
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
		-- Clients show the round banner ("BLUE WINS ROUND 1" / "DRAW") from this.
		match.lastRoundWinner = roundWinner
		if roundWinner then
			match.roundWins[roundWinner] = (match.roundWins[roundWinner] or 0) + 1
			for _, player in connected(match) do
				if match.teams[player] == roundWinner then
					grantXp(match, player, Config.XP.ROUND_WIN)
				end
			end
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

function MatchService.startMatch(
	mode: Types.MatchMode,
	players: { Player },
	options: { solo: boolean? }?
)
	matchCounter += 1
	local arena = ArenaService.create(ArenaService.pickMap(mode), mode)
	local match: Match = {
		id = matchCounter,
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
		knockouts = {},
		xp = {},
		offers = {},
		ended = false,
	}
	if mode == "FFA" then
		for _, player in players do
			local id = tostring(player.UserId)
			match.teams[player] = id
			match.teamNames[id] = player.DisplayName
			table.insert(match.teamOrder, id)
		end
	else
		match.teamOrder = { "Blue", "Red" }
		for i, player in shuffle(players) do
			match.teams[player] = if i % 2 == 1 then "Blue" else "Red"
		end
	end

	for _, player in players do
		MatchService.leaveQueue(player)
		playerMatch[player] = match
		local profile = PlayerDataService.get(player)
		local owned = if profile then profile.ownedSpells else SpellDefinitions.starters()
		local hand = {}
		for _, id in shuffle(owned) do
			if #hand >= Config.STARTING_HAND then
				break
			end
			table.insert(hand, id)
		end
		HandService.setSpellbook(player, hand)
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
	if not queues[mode] or playerMatch[player] then
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

function MatchService.isInMatch(player: Player): boolean
	return playerMatch[player] ~= nil
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
		if mode == "FFA" then
			if #list >= info.minPlayers then
				ffaReadySince = ffaReadySince or os.clock()
				if
					#list >= info.maxPlayers
					or os.clock() - (ffaReadySince :: number) >= Config.FFA_FILL_WAIT
				then
					local group = {}
					for i = 1, math.min(#list, info.maxPlayers) do
						table.insert(group, list[i])
					end
					ffaReadySince = nil
					MatchService.startMatch("FFA", group)
				end
			else
				ffaReadySince = nil
			end
		else
			local needed = info.teams * info.perTeam
			while #list >= needed do
				local group = {}
				for i = 1, needed do
					table.insert(group, list[i])
				end
				MatchService.startMatch(mode :: Types.MatchMode, group)
			end
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
		HandService.addToSpellbook(player, card.spellId)
		if Rarity.INFO[card.rarity].order >= 2 then
			ProgressionService.track(player, "draftRare")
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
			MatchService.sessionKnockouts[killer] = (MatchService.sessionKnockouts[killer] or 0) + 1
			grantXp(match, killer, Config.XP.KNOCKOUT)
			ProgressionService.track(killer, "knockout")
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
		MatchService.sessionKnockouts[player] = nil
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
