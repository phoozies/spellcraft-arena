--!strict
-- Parties for the Battleground. Owns: who is in which party, invites, and the
-- `PartyId` player attribute clients use to tint allies.
--
--   * Any player can invite any other (up to Config.PARTY.MAX_SIZE in a party);
--     the first invite makes the inviter the leader. Only the leader invites
--     or kicks. An invite expires after Config.PARTY.INVITE_SECONDS.
--   * Party members can't hurt each other in the Battleground and their
--     healing/buff spells reach each other (MatchService.relation / areAllies
--     ask `sameParty`). Matches keep their own teams; a party doesn't change them.
--   * Joining the Battleground drops you next to a party member already inside
--     (BattlegroundService.spawnCFrame asks `membersOf`).
--   * The server sends each member a PartyState snapshot on every change; the
--     client only ever sends intent (PartyAction: invite/accept/decline/leave/kick).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local PartyService = {}

local ACTION_COOLDOWN = 0.3

type Party = {
	id: number,
	leader: Player,
	members: { Player },
}

local parties: { [Player]: Party } = {}
-- invitee -> { inviter -> expiry (os.clock) }
local invites: { [Player]: { [Player]: number } } = {}
local lastAction: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local nextPartyId = 0

local stateRemote: RemoteEvent
local toastRemote: RemoteEvent

local function toast(player: Player, message: string, kind: string?)
	toastRemote:FireClient(player, message, kind or "info")
end

function PartyService.partyOf(player: Player): Party?
	return parties[player]
end

-- Everyone in the player's party (including them); just them if solo.
function PartyService.membersOf(player: Player): { Player }
	local party = parties[player]
	return if party then table.clone(party.members) else { player }
end

function PartyService.sameParty(a: Player, b: Player): boolean
	local party = parties[a]
	return party ~= nil and party == parties[b]
end

local function pruneInvites(invitee: Player)
	local list = invites[invitee]
	if not list then
		return
	end
	local now = os.clock()
	for inviter, expiry in list do
		if expiry <= now or inviter.Parent == nil then
			list[inviter] = nil
		end
	end
	if next(list) == nil then
		invites[invitee] = nil
	end
end

-- Sends one player their view: their party (if any) and pending invites.
local function push(player: Player)
	if player.Parent == nil then
		return
	end
	pruneInvites(player)
	local party = parties[player]
	local members = {}
	if party then
		for _, member in party.members do
			table.insert(members, { userId = member.UserId, name = member.DisplayName })
		end
	end
	local pending = {}
	for inviter, expiry in invites[player] or {} do
		table.insert(pending, {
			userId = inviter.UserId,
			name = inviter.DisplayName,
			secondsLeft = math.max(0, math.ceil(expiry - os.clock())),
		})
	end
	stateRemote:FireClient(player, {
		leaderId = if party then party.leader.UserId else nil,
		members = members,
		invites = pending,
	})
	player:SetAttribute("PartyId", if party then party.id else nil)
end

local function pushParty(party: Party)
	for _, member in party.members do
		push(member)
	end
end

local function leave(player: Player, reason: string?)
	local party = parties[player]
	if not party then
		return
	end
	parties[player] = nil
	table.remove(party.members, table.find(party.members, player))
	push(player)
	if #party.members <= 1 then
		-- A party of one is no party.
		for _, last in party.members do
			parties[last] = nil
			toast(last, "Your party disbanded.")
			push(last)
		end
		return
	end
	if party.leader == player then
		party.leader = party.members[1]
		toast(party.leader, "You're the party leader now.")
	end
	for _, member in party.members do
		toast(member, `{player.DisplayName} {reason or "left the party"}.`)
	end
	pushParty(party)
end

local function invite(inviter: Player, targetId: any)
	if typeof(targetId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(targetId)
	if not target or target == inviter then
		return
	end
	local party = parties[inviter]
	if party and party.leader ~= inviter then
		return toast(inviter, "Only the party leader can invite.", "fizzle")
	end
	if party and #party.members >= Config.PARTY.MAX_SIZE then
		return toast(inviter, "Your party is full.", "fizzle")
	end
	if party and parties[target] == party then
		return
	end
	if parties[target] then
		return toast(inviter, `{target.DisplayName} is already in a party.`, "fizzle")
	end
	pruneInvites(target)
	local list = invites[target] or {}
	invites[target] = list
	list[inviter] = os.clock() + Config.PARTY.INVITE_SECONDS
	toast(inviter, `Invited {target.DisplayName}.`)
	toast(target, `{inviter.DisplayName} invited you to a party!`, "round")
	push(target)
	task.delay(Config.PARTY.INVITE_SECONDS + 0.1, push, target)
end

local function accept(player: Player, inviterId: any)
	if typeof(inviterId) ~= "number" then
		return
	end
	local inviter = Players:GetPlayerByUserId(inviterId)
	pruneInvites(player)
	local list = invites[player]
	if not inviter or not list or not list[inviter] then
		return toast(player, "That invite has expired.", "fizzle")
	end
	list[inviter] = nil
	local party = parties[inviter]
	if party and #party.members >= Config.PARTY.MAX_SIZE then
		return toast(player, "That party is full.", "fizzle")
	end
	if parties[player] == party and party then
		return
	end
	leave(player)
	if not party then
		nextPartyId += 1
		party = { id = nextPartyId, leader = inviter, members = { inviter } }
		parties[inviter] = party
	end
	local joined = party :: Party
	table.insert(joined.members, player)
	parties[player] = joined
	invites[player] = nil
	for _, member in joined.members do
		if member ~= player then
			toast(member, `{player.DisplayName} joined the party!`, "ready")
		end
	end
	toast(player, "You joined the party!", "ready")
	pushParty(joined)
end

local function decline(player: Player, inviterId: any)
	if typeof(inviterId) ~= "number" then
		return
	end
	local inviter = Players:GetPlayerByUserId(inviterId)
	local list = invites[player]
	if inviter and list then
		list[inviter] = nil
		push(player)
	end
end

local function kick(leader: Player, targetId: any)
	if typeof(targetId) ~= "number" then
		return
	end
	local party = parties[leader]
	local target = Players:GetPlayerByUserId(targetId)
	if
		not party
		or party.leader ~= leader
		or not target
		or target == leader
		or parties[target] ~= party
	then
		return
	end
	toast(target, "You were removed from the party.", "fizzle")
	leave(target, "was removed from the party")
end

function PartyService.init()
	stateRemote = Remotes.get("PartyState")
	toastRemote = Remotes.get("Toast")
end

function PartyService.start()
	Remotes.get("PartyAction").OnServerEvent:Connect(function(player, action: unknown, arg: unknown)
		local now = os.clock()
		if typeof(action) ~= "string" or now - (lastAction[player] or 0) < ACTION_COOLDOWN then
			return
		end
		lastAction[player] = now
		if action == "invite" then
			invite(player, arg)
		elseif action == "accept" then
			accept(player, arg)
		elseif action == "decline" then
			decline(player, arg)
		elseif action == "leave" then
			leave(player)
		elseif action == "kick" then
			kick(player, arg)
		end
	end)

	Players.PlayerAdded:Connect(push)
	for _, player in Players:GetPlayers() do
		push(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		leave(player, "left the game")
		invites[player] = nil
		for invitee in invites do
			if invites[invitee] and invites[invitee][player] then
				invites[invitee][player] = nil
				push(invitee)
			end
		end
	end)
end

return PartyService
