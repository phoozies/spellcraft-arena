--!strict
-- Rarity tiers, the crate shop (shared/Economy/Crates), starters, and the
-- draft roller. All pure modules with injectable RNGs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Crates = require(ReplicatedStorage.Shared.Economy.Crates)
local DraftRoller = require(ReplicatedStorage.Shared.Match.DraftRoller)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

return function(t: any)
	t.describe("Spells and starters", function()
		t.it("everyone starts with Fireball, Water Lock and Rock Wall", function()
			local starters = SpellDefinitions.starters()
			t.expect(#starters).toBe(3)
			t.expect(table.find(starters, "Fireball") ~= nil).toBeTruthy()
			t.expect(table.find(starters, "WaterLock") ~= nil).toBeTruthy()
			t.expect(table.find(starters, "RockWall") ~= nil).toBeTruthy()
		end)
		t.it("every rarity has at least one crate spell", function()
			for _, name in Rarity.ORDER do
				t.expect(#SpellDefinitions.crateDrops(name) >= 1).toBeTruthy()
			end
		end)
		t.it("a new player can afford the Common crate", function()
			local common = Crates.get("Common")
			t.expect(common ~= nil and Config.COINS.STARTING >= common.price).toBeTruthy()
		end)
	end)

	t.describe("Rarity.roll", function()
		t.it("maps the roll range onto the weights (50/25/15/8/2)", function()
			t.expect(Rarity.roll(0)).toBe("Common")
			t.expect(Rarity.roll(0.49)).toBe("Common")
			t.expect(Rarity.roll(0.51)).toBe("Uncommon")
			t.expect(Rarity.roll(0.76)).toBe("Rare")
			t.expect(Rarity.roll(0.91)).toBe("Epic")
			t.expect(Rarity.roll(0.995)).toBe("Legendary")
		end)
	end)

	t.describe("Crates", function()
		t.it("one crate per rarity, pricier as rarity rises", function()
			t.expect(#Crates.LIST).toBe(#Rarity.ORDER)
			local last = 0
			for index, crate in Crates.LIST do
				t.expect(crate.id).toBe(Rarity.ORDER[index])
				t.expect(crate.price > last).toBeTruthy()
				last = crate.price
			end
		end)
		t.it("odds are percentages that add up to 100", function()
			for _, crate in Crates.LIST do
				local total = 0
				for _, weight in crate.odds do
					total += weight
				end
				t.expect(total).toBe(100)
				t.expect((crate.odds[crate.id] or 0) >= 50).toBeTruthy()
			end
		end)
		t.it("rolls only spells the crate can drop, never starters", function()
			local rng = Random.new(7)
			for _, crate in Crates.LIST do
				local possible = Crates.possibleDrops(crate)
				for _ = 1, 200 do
					local spellId, rarity = Crates.roll(crate, rng)
					t.expect(spellId ~= nil and table.find(possible, spellId) ~= nil).toBeTruthy()
					local def = SpellDefinitions.get(spellId :: string)
					t.expect(def ~= nil and not def.starter and def.rarity == rarity).toBeTruthy()
				end
			end
		end)
		t.it("hits the crate's odds", function()
			local rng = Random.new(99)
			local crate = Crates.get("Common") :: any
			local upgrades = 0
			for _ = 1, 4000 do
				local _, rarity = Crates.roll(crate, rng)
				if rarity == "Uncommon" then
					upgrades += 1
				end
			end
			t.expect(upgrades / 4000).toBeNear(0.2, 0.03)
		end)
		t.it("refunds half the price for a duplicate", function()
			t.expect(Crates.refundFor(Crates.get("Rare") :: any)).toBe(250)
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
	end)
end
