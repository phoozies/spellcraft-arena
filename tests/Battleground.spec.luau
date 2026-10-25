--!strict
-- The Battleground map's contract with BattlegroundService: NPC spots,
-- exit gates, a build zone, and the config it is built from.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Npcs = require(ReplicatedStorage.Shared.Battleground.Npcs)

return function(t: any)
	t.describe("Battleground", function()
		local maps = ServerScriptService:FindFirstChild("Server") and ServerScriptService.Server:FindFirstChild("Maps")
		local builder = if maps and maps:FindFirstChild("Battleground")
			then require(maps.Battleground :: ModuleScript) :: any
			else nil

		t.it("has a center, a world size, a respawn delay, and NPC rules", function()
			local config = Config.BATTLEGROUND
			t.expect(typeof(config.CENTER)).toBe("Vector3")
			t.expect(config.HALF_SIZE >= 200).toBeTruthy()
			t.expect(config.RESPAWN_DELAY >= 1).toBeTruthy()
			t.expect(config.NPC.RESPAWN >= 10).toBeTruthy()
			t.expect(config.NPC.COIN_CAP > 0).toBeTruthy()
			-- Far enough from the hub (which spans about +-170 studs) not to overlap it.
			t.expect(math.abs(config.CENTER.X) - config.HALF_SIZE > 200).toBeTruthy()
		end)

		t.it("builds NPC spots, exit gates, and one build zone, with no arena spawns", function()
			if not builder then
				return -- server scripts aren't present in this context
			end
			local center = Config.BATTLEGROUND.CENTER
			local half = Config.BATTLEGROUND.HALF_SIZE
			local model = builder(center) :: Model
			local spots, exits, zones, spawns = 0, 0, 0, 0
			local byType: { [string]: number } = {}
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					if part:HasTag("NpcSpot") then
						spots += 1
						local id = part:GetAttribute("NpcType") :: string
						t.expect(Npcs.get(id) ~= nil).toBeTruthy()
						byType[id] = (byType[id] or 0) + 1
						t.expect(math.abs(part.Position.X - center.X) < half).toBeTruthy()
						t.expect(math.abs(part.Position.Z - center.Z) < half).toBeTruthy()
					elseif part:HasTag("BattlegroundExit") then
						exits += 1
					elseif part:HasTag("BuildZone") then
						zones += 1
					elseif part:HasTag("BattlegroundSpawn") then
						spawns += 1
					end
				end
			end
			t.expect(spots >= 15).toBeTruthy()
			t.expect(byType.Raider >= 6).toBeTruthy()
			t.expect(byType.Mage >= 3).toBeTruthy()
			t.expect(byType.Brute >= 1).toBeTruthy()
			t.expect(byType.Warlord).toBe(1)
			t.expect(exits >= 2).toBeTruthy()
			t.expect(zones).toBe(1)
			t.expect(spawns).toBe(0) -- players drop in at random spots
			model:Destroy()
		end)

		t.it("FFA is gone from the queued modes", function()
			t.expect((Config.MODES :: any).FFA).toBeNil()
			t.expect(Config.MODES["1v1"] ~= nil).toBeTruthy()
		end)
	end)
end
