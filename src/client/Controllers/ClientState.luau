--!strict
-- Client-side mirror of what the server tells us (spellbook, cooldowns, profile,
-- match state). Display only — the server re-validates every action.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PracticeZone = require(ReplicatedStorage.Shared.Util.PracticeZone)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Loadout = require(ReplicatedStorage.Shared.Spells.Loadout)
local Types = require(ReplicatedStorage.Shared.Types)

export type ProfileSummary = {
	coins: number,
	elements: { string },
	element: string, -- the equipped element ("" before the first pick)
	spells: { string }, -- chest spells owned
	loadout: { string }, -- chest spells equipped beside the element's base spells
	tutorial: { done: boolean },
	quests: { Types.DailyQuest },
	streak: number,
	stats: { matches: number, wins: number, knockouts: number, casts: number },
	settings: { drawKey: string, music: boolean, sfx: boolean, shake: boolean, camera: number? },
	-- likeReadyAt: server time (workspace:GetServerTimeNow) the gift can be claimed.
	rewards: { likeFav: boolean, likeReadyAt: number },
	pity: number, -- chests opened since the last Epic or better
}

local ClientState = {
	-- The spell whose shape the drawing canvas is showing (nil = closed or blank).
	-- The crosshair, hit circle, and placement ghost preview where it will land.
	aiming = nil :: string?,
	-- How many of this player's drawings have been cast this session.
	casts = 0,
	-- Match only: the spells this player may draw this match (nil in the hub).
	spellbook = nil :: { string }?,
	cooldowns = {} :: { [string]: number }, -- spellId -> server time it can be cast again
	-- Local mirror of the 1s drawing cooldown (os.clock() when drawing is allowed).
	drawReadyAt = 0,
	profile = nil :: ProfileSummary?,
	match = { phase = "Idle", round = 0, endsAt = 0, scores = {} } :: Types.MatchState,
	queueCounts = {} :: { [string]: number },

	SpellbookChanged = Signal.new(),
	-- Fired with a spell id when the player taps that spell's card: DrawController
	-- opens the canvas with a preview of its shape.
	DrawRequested = Signal.new(),
	ProfileChanged = Signal.new(),
	MatchChanged = Signal.new(),
	-- Fired when where the player is changes: a match phase, or entering or
	-- leaving the Battleground.
	PresenceChanged = Signal.new(),
	QueueChanged = Signal.new(),
}

-- The spells the player can draw right now: this match's spellbook, or (in the
-- hub and Battleground) their element's base spells plus equipped chest spells.
function ClientState.drawableSpells(): { string }
	if ClientState.spellbook then
		return table.clone(ClientState.spellbook)
	end
	local profile = ClientState.profile
	if profile and profile.element ~= "" then
		return Loadout.spells(profile.element, profile.loadout)
	end
	return {}
end

-- The key that opens the drawing canvas (player setting).
function ClientState.drawKeyName(): string
	local profile = ClientState.profile
	return if profile
			and profile.settings
			and profile.settings.drawKey
		then profile.settings.drawKey
		else Config.DEFAULT_DRAW_KEY
end

function ClientState.drawKeyCode(): Enum.KeyCode
	local ok, keyCode = pcall(function()
		return (Enum.KeyCode :: any)[ClientState.drawKeyName()]
	end)
	return if ok and keyCode then keyCode else Enum.KeyCode.F
end

-- True while the player stands in the hub's Training Grove (PracticeZone).
ClientState.inPractice = false

-- True while the player is in a match (any phase) or in the Battleground.
function ClientState.fighting(): boolean
	return ClientState.match.phase ~= "Idle"
		or Players.LocalPlayer:GetAttribute("InBattleground") == true
end

-- True when drawing is allowed: during a match's rounds, in the Battleground, and in
-- the hub's Training Grove (not elsewhere in the hub, and not during the intro,
-- countdown, draft, or results).
-- The server enforces the same rule (MatchService.canDraw).
function ClientState.canDraw(): boolean
	return ClientState.match.phase == "Round"
		or Players.LocalPlayer:GetAttribute("InBattleground") == true
		or (ClientState.match.phase == "Idle" and ClientState.inPractice)
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
	Remotes.get("SpellbookUpdated").OnClientEvent:Connect(function(spellbook)
		ClientState.spellbook = spellbook
		ClientState.SpellbookChanged:Fire()
	end)
	Remotes.get("CooldownStarted").OnClientEvent:Connect(function(spellId, readyAt)
		ClientState.cooldowns[spellId] = readyAt
	end)
	Remotes.get("GlyphResult").OnClientEvent:Connect(function(spellId)
		if spellId then
			ClientState.casts += 1
		end
	end)
	Remotes.get("ProfileUpdated").OnClientEvent:Connect(function(summary)
		ClientState.profile = summary
		ClientState.ProfileChanged:Fire()
	end)
	Remotes.get("MatchStateChanged").OnClientEvent:Connect(function(state)
		ClientState.match = state
		ClientState.MatchChanged:Fire()
		ClientState.PresenceChanged:Fire()
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("InBattleground"):Connect(function()
		ClientState.PresenceChanged:Fire()
	end)
	-- Walking into or out of the Training Grove changes where drawing works.
	task.spawn(function()
		while true do
			task.wait(0.2)
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local inside = root ~= nil and PracticeZone.contains(root.Position)
			if inside ~= ClientState.inPractice then
				ClientState.inPractice = inside
				ClientState.PresenceChanged:Fire()
			end
		end
	end)
	Remotes.get("QueueCounts").OnClientEvent:Connect(function(counts)
		ClientState.queueCounts = counts
		ClientState.QueueChanged:Fire()
	end)
end

return ClientState
