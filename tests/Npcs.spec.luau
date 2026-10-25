--!strict
-- The Battleground NPC data: every kind can fight, pays a sensible reward,
-- and stays inside the same budgets as player spells.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Npcs = require(ReplicatedStorage.Shared.Battleground.Npcs)

return function(t: any)
	t.describe("Npcs", function()
		t.it("has unique ids and looks them up", function()
			t.expect(#Npcs.LIST >= 4).toBeTruthy()
			for _, npc in Npcs.LIST do
				t.expect(Npcs.get(npc.id)).toBe(npc)
			end
			t.expect(Npcs.get("Nobody")).toBeNil()
		end)

		t.it("every kind can fight and is fair", function()
			for _, npc in Npcs.LIST do
				t.expect(npc.melee ~= nil or npc.ranged ~= nil).toBeTruthy()
				t.expect(npc.health > 0).toBeTruthy()
				t.expect(npc.leash > npc.aggro).toBeTruthy()
				-- No one-shots: a full-health player has 100 health.
				if npc.melee then
					t.expect(npc.melee.damage < 40).toBeTruthy()
					t.expect(npc.melee.windup >= 0.3).toBeTruthy()
					t.expect(npc.melee.interval > npc.melee.windup).toBeTruthy()
				end
				if npc.ranged then
					t.expect(npc.ranged.damage < 30).toBeTruthy()
					t.expect(npc.ranged.windup >= 0.4).toBeTruthy()
					t.expect(npc.ranged.interval >= 2).toBeTruthy()
				end
			end
		end)

		t.it("tougher kinds pay more, and the cap allows at least a few kills", function()
			local cap = Config.BATTLEGROUND.NPC
			local lowest = math.huge
			for _, npc in Npcs.LIST do
				t.expect(npc.reward > 0).toBeTruthy()
				t.expect(npc.reward <= cap.COIN_CAP).toBeTruthy()
				lowest = math.min(lowest, npc.reward)
			end
			t.expect(cap.COIN_CAP >= lowest * 10).toBeTruthy()
			local raider, brute, warlord = Npcs.get("Raider"), Npcs.get("Brute"), Npcs.get("Warlord")
			t.expect((raider :: any).reward < (brute :: any).reward).toBeTruthy()
			t.expect((brute :: any).reward < (warlord :: any).reward).toBeTruthy()
			t.expect((raider :: any).health < (brute :: any).health).toBeTruthy()
		end)
	end)
end
