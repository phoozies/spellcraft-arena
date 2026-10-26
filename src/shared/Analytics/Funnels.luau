--!strict
-- The names and order of every analytics funnel step and event. Pure data, so
-- the funnel can be read (and tested) without the server: TelemetryService
-- sends them to Roblox's AnalyticsService, where the Creator Hub shows the
-- drop-off between steps.

local Funnels = {}

-- New-player funnel. Roblox keeps each step once per player for life, so the
-- order here is the order a new player meets them. Never renumber a step that
-- has shipped: add new ones at the end.
Funnels.ONBOARDING = {
	"Joined", -- profile loaded
	"TutorialDone", -- finished or skipped the walkthrough
	"ElementPicked", -- chose the free first element
	"FirstSpellDrawn", -- a drawing was recognized as a spell
	"FirstCast", -- cast a spell for the first time
	"FirstMatchStarted",
	"FirstMatchFinished",
	"FirstWin",
	"FirstCrateSpin",
	"FirstElementBought",
} :: { string }

-- Per-match funnel (one session id per match), to see where duels are left.
Funnels.MATCH_NAME = "Match"
Funnels.MATCH = {
	"Started", -- the arena was built and everyone moved in
	"Round1Done",
	"Finished", -- someone won (or it was a draw)
} :: { string }

-- Custom events (the value is in the comment).
Funnels.EVENTS = {
	SessionEnd = "SessionEnd", -- seconds in the server
	DailyReturn = "DailyReturn", -- the login streak day (2+ means a returning player)
	MatchAbandoned = "MatchAbandoned", -- round the player was on when they left
	BattlegroundJoined = "BattlegroundJoined",
	QuestClaimed = "QuestClaimed", -- coins
	WaterRescue = "WaterRescue", -- damage taken
	PitRescue = "PitRescue",
} :: { [string]: string }

function Funnels.onboardingIndex(step: string): number?
	return table.find(Funnels.ONBOARDING, step)
end

function Funnels.matchIndex(step: string): number?
	return table.find(Funnels.MATCH, step)
end

return Funnels
