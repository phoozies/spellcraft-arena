--!strict
-- Client-side mirror of what the server tells us (hand, cooldowns, profile,
-- match state). Display only — the server re-validates every action.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

export type ProfileSummary = {
	level: number,
	xp: number,
	xpInto: number,
	xpNeeded: number,
	ownedSpells: { string },
	quests: { Types.DailyQuest },
	streak: number,
	stats: { matches: number, wins: number, knockouts: number, casts: number },
}

local ClientState = {
	hand = {} :: { string }, -- spell copies held (hotbar)
	readied = nil :: string?,
	-- Match only: the words this player may type this match (nil in the hub).
	spellbook = nil :: { string }?,
	cooldowns = {} :: { [string]: number }, -- spellId -> server time its word recharges
	-- Local mirror of the 1s typing cooldown (os.clock() when typing is allowed).
	typeReadyAt = 0,
	profile = nil :: ProfileSummary?,
	match = { phase = "Idle", round = 0, endsAt = 0, scores = {} } :: Types.MatchState,
	queueCounts = {} :: { [string]: number },

	HandChanged = Signal.new(),
	ProfileChanged = Signal.new(),
	MatchChanged = Signal.new(),
	QueueChanged = Signal.new(),
}

function ClientState.cooldownLeft(spellId: string): number
	local readyAt = ClientState.cooldowns[spellId]
	if not readyAt then
		return 0
	end
	return math.max(0, readyAt - workspace:GetServerTimeNow())
end

function ClientState.start()
	Remotes.get("HandUpdated").OnClientEvent:Connect(function(hand, readied, spellbook)
		ClientState.hand = hand
		ClientState.readied = readied
		ClientState.spellbook = spellbook
		ClientState.HandChanged:Fire()
	end)
	Remotes.get("CooldownStarted").OnClientEvent:Connect(function(spellId, readyAt)
		ClientState.cooldowns[spellId] = readyAt
		ClientState.HandChanged:Fire()
	end)
	Remotes.get("ProfileUpdated").OnClientEvent:Connect(function(summary)
		ClientState.profile = summary
		ClientState.ProfileChanged:Fire()
	end)
	Remotes.get("MatchStateChanged").OnClientEvent:Connect(function(state)
		ClientState.match = state
		ClientState.MatchChanged:Fire()
	end)
	Remotes.get("QueueCounts").OnClientEvent:Connect(function(counts)
		ClientState.queueCounts = counts
		ClientState.QueueChanged:Fire()
	end)
end

return ClientState
