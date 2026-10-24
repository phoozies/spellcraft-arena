--!strict
-- Client-side mirror of what the server tells us (hand, cooldowns, profile,
-- match state). Display only — the server re-validates every action.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
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
	settings: { typeKey: string },
}

local ClientState = {
	hand = {} :: { string }, -- spell copies held (hotbar slots, duplicates allowed)
	readiedSlot = nil :: number?,
	readied = nil :: string?, -- spell id in the readied slot
	-- Match only: the words this player may type this match (nil in the hub).
	spellbook = nil :: { string }?,
	cooldowns = {} :: { [string]: number }, -- spellId -> server time it can be cast again
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

-- The key that focuses the "type a spell" box (player setting).
function ClientState.typeKeyName(): string
	local profile = ClientState.profile
	return if profile
			and profile.settings
			and profile.settings.typeKey
		then profile.settings.typeKey
		else Config.DEFAULT_TYPE_KEY
end

function ClientState.typeKeyCode(): Enum.KeyCode
	local ok, keyCode = pcall(function()
		return (Enum.KeyCode :: any)[ClientState.typeKeyName()]
	end)
	return if ok and keyCode then keyCode else Enum.KeyCode.T
end

-- True while the settings panel is waiting for a key press to rebind.
ClientState.capturingKey = false

function ClientState.cooldownLeft(spellId: string): number
	local readyAt = ClientState.cooldowns[spellId]
	if not readyAt then
		return 0
	end
	return math.max(0, readyAt - workspace:GetServerTimeNow())
end

function ClientState.start()
	Remotes.get("HandUpdated").OnClientEvent:Connect(function(hand, readiedSlot, spellbook)
		ClientState.hand = hand
		ClientState.readiedSlot = readiedSlot
		ClientState.readied = if readiedSlot then hand[readiedSlot] else nil
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
