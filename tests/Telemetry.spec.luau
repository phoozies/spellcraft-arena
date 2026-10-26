--!strict
-- The analytics funnel and the game-feel settings: funnel steps are named and
-- ordered once, the service records each onboarding step once per player, and
-- the juice numbers and sounds are sane.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Audio.Cues)
local Funnels = require(ReplicatedStorage.Shared.Analytics.Funnels)

return function(t: any)
	t.describe("Analytics funnel", function()
		t.it("onboarding steps are unique, start at Joined, and are found by name", function()
			local seen: { [string]: boolean } = {}
			for i, step in Funnels.ONBOARDING do
				t.expect(seen[step]).toBeNil()
				seen[step] = true
				t.expect(Funnels.onboardingIndex(step)).toBe(i)
			end
			t.expect(Funnels.ONBOARDING[1]).toBe("Joined")
			t.expect(Funnels.onboardingIndex("Nope")).toBeNil()
		end)

		t.it("the match funnel runs Started, Round1Done, Finished", function()
			t.expect(Funnels.matchIndex("Started")).toBe(1)
			t.expect(Funnels.matchIndex("Round1Done")).toBe(2)
			t.expect(Funnels.matchIndex("Finished")).toBe(3)
		end)

		t.it("custom event names are distinct", function()
			local seen: { [string]: boolean } = {}
			for key, name in Funnels.EVENTS do
				t.expect(key).toBe(name)
				t.expect(seen[name]).toBeNil()
				seen[name] = true
			end
		end)

		t.it("the service logs a step once per player and ignores unknown ones", function()
			local server = ServerScriptService:FindFirstChild("Server")
			local services = server and server:FindFirstChild("Services")
			local module = services and services:FindFirstChild("TelemetryService")
			if not module then
				return
			end
			local telemetry = require(module :: ModuleScript) :: any
			local player = {} :: any
			local function count(): number
				local n = 0
				for _, entry in telemetry.recent() do
					if entry.kind == "onboarding" and entry.name == "TutorialDone" then
						n += 1
					end
				end
				return n
			end
			local before = count()
			telemetry.onboarding(player, "TutorialDone")
			telemetry.onboarding(player, "TutorialDone")
			t.expect(count()).toBe(before + 1)
			local events = telemetry.recent()
			t.expect(events[#events].value).toBe(2)
			telemetry.event(player, "WaterRescue", 30)
			t.expect(telemetry.recent()[#telemetry.recent()].name).toBe("WaterRescue")
		end)
	end)

	t.describe("Game feel", function()
		t.it("the juice settings are in range", function()
			local juice = Config.JUICE
			t.expect(juice.SHAKE_MAX > 0 and juice.SHAKE_MAX <= 3).toBeTruthy()
			t.expect(juice.FOV_MAX > 0 and juice.FOV_MAX <= 20).toBeTruthy()
			t.expect(juice.BIG_HIT > 0).toBeTruthy()
			t.expect(juice.LOW_HEALTH > 0 and juice.LOW_HEALTH < 1).toBeTruthy()
		end)

		t.it("every sound the juice plays exists", function()
			for _, name in { "hitMarker", "heavyHit", "hurt", "knockoutSting", "waterSplash" } do
				t.expect(Cues[name] ~= nil).toBeTruthy()
			end
		end)
	end)
end
