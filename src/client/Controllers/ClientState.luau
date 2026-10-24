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
	hand = {} :: { string },
	readied = nil :: string?,
	cooldowns = {} :: { [string]: number }, -- spellId -> server time ready
	profile = nil :: ProfileSummary?,
	match = { phase = "Idle", round = 0, endsAt = 0, scores = {} } :: Types.MatchState,
	queueCounts = {} :: { [string]: number },

	HandChanged = Signal.new() :: Signal.Signal<>,
	ProfileChanged = Signal.new() :: Signal.Signal<>,
	MatchChanged = Signal.new() :: Signal.Signal<>,
	QueueChanged = Signal.new() :: Signal.Signal<>,
}

function ClientState.cooldownLeft(spellId: string): number
	local readyAt = ClientState.cooldowns[spellId]
	if not readyAt then
		return 0
	end
	return math.max(0, readyAt - workspace:GetServerTimeNow())
end

function ClientState.start()
	Remotes.get("HandUpdated").OnClientEvent:Connect(function(hand, readied)
		ClientState.hand = hand
		ClientState.readied = readied
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
