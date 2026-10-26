--!strict
-- The analytics funnel. Sends how players move through the game to Roblox's
-- AnalyticsService (Creator Hub > Analytics): a new-player onboarding funnel,
-- a per-match funnel, a coin economy flow, and a few custom events (session
-- length, daily returns, abandoned matches, rescues). Owns nothing in the
-- game: other services call it, and it never reads or changes a profile.
--
-- Every call is wrapped in pcall (the service is missing or rate-limited in
-- Studio tests), and each onboarding step is only sent once per player per
-- session. Step names and order live in Shared/Analytics/Funnels.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Funnels = require(ReplicatedStorage.Shared.Analytics.Funnels)
local PlayerDataService = require(script.Parent.PlayerDataService)

local TelemetryService = {}

local CURRENCY = "Coins"

-- Every event the last call made, for tests (newest last, capped).
local recent: { { kind: string, name: string, value: number? } } = {}
local RECENT_LIMIT = 50

local sentSteps: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local joinedAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

-- The AnalyticsService methods are newer than Luau's built-in types.
local service: any = AnalyticsService

local function record(kind: string, name: string, value: number?)
	table.insert(recent, { kind = kind, name = name, value = value })
	if #recent > RECENT_LIMIT then
		table.remove(recent, 1)
	end
end

-- The most recent logged events, oldest first (tests only).
function TelemetryService.recent(): { { kind: string, name: string, value: number? } }
	return recent
end

-- One onboarding step ("Joined", "FirstWin", ...), once per player per session.
function TelemetryService.onboarding(player: Player, step: string)
	local index = Funnels.onboardingIndex(step)
	if not index then
		warn(`[Telemetry] unknown onboarding step {step}`)
		return
	end
	local sent = sentSteps[player]
	if not sent then
		sent = {}
		sentSteps[player] = sent
	end
	if sent[step] then
		return
	end
	sent[step] = true
	record("onboarding", step, index)
	pcall(function()
		service:LogOnboardingFunnelStepEvent(player, index, step)
	end)
end

-- A step of a match's funnel; `sessionId` identifies one match.
function TelemetryService.matchStep(player: Player, sessionId: string, step: string)
	local index = Funnels.matchIndex(step)
	if not index then
		warn(`[Telemetry] unknown match step {step}`)
		return
	end
	record("match", step, index)
	pcall(function()
		service:LogFunnelStepEvent(player, Funnels.MATCH_NAME, sessionId, index, step)
	end)
end

-- A fresh id for one match's funnel session.
function TelemetryService.newSessionId(): string
	return HttpService:GenerateGUID(false)
end

-- Coins entering the economy (`reason`: match, daily, quest, npc, ...).
function TelemetryService.coinsEarned(
	player: Player,
	amount: number,
	balance: number,
	reason: string
)
	record("economy", `source:{reason}`, amount)
	pcall(function()
		service:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Source,
			CURRENCY,
			balance,
			amount,
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			reason
		)
	end)
end

-- Coins leaving the economy (`item`: what they bought, e.g. a crate id).
function TelemetryService.coinsSpent(player: Player, amount: number, balance: number, item: string)
	record("economy", `sink:{item}`, amount)
	pcall(function()
		service:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			CURRENCY,
			balance,
			amount,
			Enum.AnalyticsEconomyTransactionType.Shop.Name,
			item
		)
	end)
end

-- A one-off event with an optional number (see Funnels.EVENTS).
function TelemetryService.event(player: Player, name: string, value: number?)
	record("event", name, value)
	pcall(function()
		service:LogCustomEvent(player, name, value or 1)
	end)
end

function TelemetryService.init() end

function TelemetryService.start()
	PlayerDataService.ProfileLoaded:Connect(function(player, profile)
		joinedAt[player] = os.clock()
		TelemetryService.onboarding(player, "Joined")
		-- Streak day 2 or more means they came back on a later day.
		if profile.daily.streak >= 2 then
			TelemetryService.event(player, Funnels.EVENTS.DailyReturn, profile.daily.streak)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local start = joinedAt[player]
		if start then
			TelemetryService.event(
				player,
				Funnels.EVENTS.SessionEnd,
				math.floor(os.clock() - start)
			)
		end
		sentSteps[player] = nil
		joinedAt[player] = nil
	end)
end

return TelemetryService
