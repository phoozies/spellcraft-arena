--!strict
-- The Battleground map's contract with BattlegroundService: spawns around the
-- edge, exit pads, a build zone, and the config it is built from.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)

return function(t: any)
	t.describe("Battleground", function()
		local maps = ServerScriptService:FindFirstChild("Server") and ServerScriptService.Server:FindFirstChild("Maps")
		local builder = if maps and maps:FindFirstChild("Battleground")
			then require(maps.Battleground :: ModuleScript) :: any
			else nil

		t.it("has a center, a radius, and a respawn delay", function()
			t.expect(typeof(Config.BATTLEGROUND.CENTER)).toBe("Vector3")
			t.expect(Config.BATTLEGROUND.RADIUS >= 60).toBeTruthy()
			t.expect(Config.BATTLEGROUND.RESPAWN_DELAY >= 1).toBeTruthy()
			-- Far enough from the hub (which spans about +-170 studs) not to overlap it.
			t.expect(math.abs(Config.BATTLEGROUND.CENTER.X) - Config.BATTLEGROUND.RADIUS > 200).toBeTruthy()
		end)

		t.it("builds spawns inside the floor, exit pads, and a build zone", function()
			if not builder then
				return -- server scripts aren't present in this context
			end
			local center = Config.BATTLEGROUND.CENTER
			local model = builder(center) :: Model
			local spawns, exits, zones = 0, 0, 0
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					if part:HasTag("BattlegroundSpawn") then
						spawns += 1
						local flat = Vector3.new(part.Position.X - center.X, 0, part.Position.Z - center.Z)
						t.expect(flat.Magnitude < Config.BATTLEGROUND.RADIUS - 5).toBeTruthy()
					elseif part:HasTag("BattlegroundExit") then
						exits += 1
					elseif part:HasTag("BuildZone") then
						zones += 1
					end
				end
			end
			t.expect(spawns >= 12).toBeTruthy()
			t.expect(exits >= 1).toBeTruthy()
			t.expect(zones).toBe(1)
			model:Destroy()
		end)

		t.it("FFA is gone from the queued modes", function()
			t.expect((Config.MODES :: any).FFA).toBeNil()
			t.expect(Config.MODES["1v1"] ~= nil).toBeTruthy()
		end)
	end)
end
