--!strict
-- Balance budgets. Every player has Config.PLAYER_MAX_HEALTH (100) HP and
-- can stockpile up to 5 copies of a spell, so what matters is value per
-- max(GLOBAL_CAST_LOCKOUT, cast cooldown). These tests keep tuning honest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

-- Budgets per second of re-cast time.
local MAX_BURST_DPS = 20 -- direct damage (incl. combos) per cast window
local MAX_ZONE_DPS = 12 -- lingering zone damage, totalled over its duration
local MAX_HEAL_PER_SEC = 5
local MAX_SHIELD_PER_SEC = 5
local MAX_HARD_CC_UPTIME = 0.6 -- statusDuration / window for Root/TimeStop/Shrink

local HARD_CC = { Root = true, TimeStop = true, Shrink = true, Stun = true }

return function(t: any)
	t.describe("Balance (copy model, ~1s re-type)", function()
		for _, def in SpellDefinitions.list do
			local s = def.stats
			-- Copies can be stockpiled (5 held), so the fastest a spell can be
			-- re-cast is its shared cast cooldown (or the global lockout).
			local window = math.max(Config.GLOBAL_CAST_LOCKOUT, def.cooldown)

			t.it(`{def.name}: burst damage within budget`, function()
				if
					s.damage
					and not s.duration
					and not s.hazardDps
					and not s.turret
					and not s.lifetime
				then
					local hit = s.damage * (s.comboMultiplier or 1)
					t.expect(hit / window <= MAX_BURST_DPS).toBeTruthy()
				end
			end)

			t.it(`{def.name}: no one-shots (ultimates may take up to 40% of a player's HP)`, function()
				if s.damage then
					local hit = s.damage * (s.comboMultiplier or 1)
					local share = if def.ultimate then 0.4 else 0.34
					t.expect(hit <= Config.PLAYER_MAX_HEALTH * share).toBeTruthy()
				end
			end)

			t.it(`{def.name}: lingering damage within budget`, function()
				if s.damage and s.duration then
					t.expect(s.damage * s.duration / window <= MAX_ZONE_DPS * 2).toBeTruthy()
				end
			end)

			t.it(`{def.name}: healing and shields within budget`, function()
				if s.heal then
					local total = if s.duration then s.heal * s.duration else s.heal
					t.expect(total / window <= MAX_HEAL_PER_SEC).toBeTruthy()
				end
				if s.shield then
					t.expect(s.shield / window <= MAX_SHIELD_PER_SEC).toBeTruthy()
				end
			end)

			t.it(`{def.name}: hard crowd control can't be chained`, function()
				if s.status and HARD_CC[s.status] then
					t.expect((s.statusDuration or 0) / window <= MAX_HARD_CC_UPTIME).toBeTruthy()
					t.expect(def.cooldown >= 2).toBeTruthy()
				end
			end)

			t.it(`{def.name}: spammable placeables and summons are capped`, function()
				if def.archetype == "Placeable" then
					t.expect((s.maxActive or 0) >= 1 and (s.maxActive or 0) <= 3).toBeTruthy()
					t.expect(s.lifetime ~= nil).toBeTruthy()
				end
				if def.archetype == "Summon" then
					t.expect(def.cooldown >= 5).toBeTruthy()
				end
			end)

			t.it(`{def.name}: ultimates are big and slow, everything else isn't`, function()
				t.expect(def.ultimate == true).toBe(def.slot == 5)
				if def.ultimate then
					t.expect(def.cooldown >= 15).toBeTruthy()
					-- Every ultimate either hits for 30+ or is a game-changing buff.
					t.expect((s.damage or 0) >= 30).toBeTruthy()
				else
					t.expect((s.damage or 0) <= 30).toBeTruthy()
				end
			end)

			t.it(`{def.name}: timed buffs can't be up all the time`, function()
				if def.archetype == "Buff" and s.duration then
					t.expect(s.duration / def.cooldown <= 0.6).toBeTruthy()
				end
			end)
		end
	end)
end
