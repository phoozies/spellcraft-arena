--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DraftRoller = require(ReplicatedStorage.Shared.Match.DraftRoller)
local LevelCurve = require(ReplicatedStorage.Shared.Progression.LevelCurve)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

return function(t: any)
	t.describe("LevelCurve", function()
		t.it("starts at level 1 and caps at 10", function()
			t.expect(LevelCurve.levelForXp(0)).toBe(1)
			t.expect(LevelCurve.levelForXp(99)).toBe(1)
			t.expect(LevelCurve.levelForXp(100)).toBe(2)
			t.expect(LevelCurve.levelForXp(999999)).toBe(Config.MAX_LEVEL)
		end)
		t.it("reports progress within a level", function()
			local into, needed = LevelCurve.progress(175)
			t.expect(into).toBe(75)
			t.expect(needed).toBe(150)
		end)
		t.it("every level 1..10 unlocks at least one spell", function()
			for level = 1, Config.MAX_LEVEL do
				t.expect(#SpellDefinitions.unlockedAt(level) > 0).toBeTruthy()
			end
		end)
		t.it("starters are exactly Fireball, Water Lock, Rock Wall", function()
			local starters = SpellDefinitions.starters()
			t.expect(#starters).toBe(3)
			t.expect(table.find(starters, "Fireball") ~= nil).toBeTruthy()
			t.expect(table.find(starters, "WaterLock") ~= nil).toBeTruthy()
			t.expect(table.find(starters, "RockWall") ~= nil).toBeTruthy()
		end)
	end)

	t.describe("Rarity.roll", function()
		t.it("maps the roll range onto the weights", function()
			t.expect(Rarity.roll(0)).toBe("Common")
			t.expect(Rarity.roll(0.59)).toBe("Common")
			t.expect(Rarity.roll(0.61)).toBe("Rare")
			t.expect(Rarity.roll(0.95)).toBe("Epic")
			t.expect(Rarity.roll(0.999)).toBe("Legendary")
		end)
	end)

	t.describe("DraftRoller", function()
		t.it("offers 3 distinct cards not already in hand", function()
			local rng = Random.new(1)
			for _ = 1, 200 do
				local hand = { "Fireball", "WaterLock", "RockWall" }
				local cards = DraftRoller.roll(hand, rng)
				t.expect(#cards).toBe(3)
				local seen = {}
				for _, card in cards do
					t.expect(table.find(hand, card.spellId)).toBeNil()
					t.expect(seen[card.spellId]).toBeNil()
					seen[card.spellId] = true
					local def = SpellDefinitions.get(card.spellId)
					t.expect(def ~= nil and def.rarity == card.rarity).toBeTruthy()
				end
			end
		end)
		t.it("rolls rarities close to their weights", function()
			local rng = Random.new(42)
			local counts = { Common = 0, Rare = 0, Epic = 0, Legendary = 0 }
			local total = 0
			for _ = 1, 3000 do
				for _, card in DraftRoller.roll({}, rng) do
					counts[card.rarity] += 1
					total += 1
				end
			end
			t.expect(counts.Common / total).toBeNear(0.60, 0.04)
			t.expect(counts.Rare / total).toBeNear(0.28, 0.04)
			t.expect(counts.Epic / total).toBeNear(0.10, 0.03)
			t.expect(counts.Legendary / total).toBeNear(0.02, 0.015)
		end)
	end)
end
