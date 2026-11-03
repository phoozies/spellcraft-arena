--!strict
-- Spellcraft Arena server entry point. Two-phase bootstrap: init() every
-- service (wire up state, no cross-service calls that yield), then start()
-- every service. Services are plain ModuleScripts under ./Services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

-- We spawn characters ourselves so dead players don't pop back into the hub
-- mid-round (MatchService / HubService call LoadCharacter).
Players.CharacterAutoLoads = false

Remotes.setup()

-- Order matters only for init(); start() runs in the same order.
local ORDER = {
	"PlayerDataService",
	"TelemetryService",
	"EconomyService",
	"ElementService",
	"StatusService",
	"DestructibleService",
	"BoostService",
	"HandService",
	"CastService",
	"DashService",
	"SpellInputService",
	"WandService",
	"ArenaService",
	"PartyService",
	"MapVoteService",
	"MatchService",
	"HubService",
	"BattlegroundService",
	"NpcService",
	"CrateService",
	"LeaderboardService",
	"AdminService",
	"DebugService",
}

local Services = script:WaitForChild("Services")
local loaded: { any } = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `missing service {name}`)
	table.insert(loaded, require(module) :: any)
end

for _, service in loaded do
	if typeof(service.init) == "function" then
		service.init()
	end
end

for _, service in loaded do
	if typeof(service.start) == "function" then
		task.spawn(service.start)
	end
end

print("[SpellcraftArena] server started")
