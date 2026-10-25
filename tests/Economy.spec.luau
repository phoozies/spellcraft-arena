--!strict
-- Elements (shared/Spells/Elements), the Element Crate (shared/Economy/
-- Crates), and match boosts (shared/Match/Boosts). All pure modules with
-- injectable RNGs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Boosts = require(ReplicatedStorage.Shared.Match.Boosts)
local Crates = require(ReplicatedStorage.Shared.Economy.Crates)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

return function(t: any)
	t.describe("Elements", function()
		t.it("there are four, with five spells each in slot order", function()
			t.expect(#Elements.LIST).toBe(4)
			for _, element in Elements.LIST do
				t.expect(#element.spells).toBe(5)
				for slot, id in element.spells do
					local def = SpellDefinitions.get(id)
					t.expect(def ~= nil and def.element == element.id and def.slot == slot)
						.toBeTruthy()
				end
			end
		end)
		t.it("every spell belongs to exactly one element's list", function()
			local seen: { [string]: boolean } = {}
			for _, element in Elements.LIST do
				for _, id in element.spells do
					t.expect(seen[id]).toBeNil()
					seen[id] = true
				end
			end
			t.expect(#SpellDefinitions.list).toBe(20)
			for _, def in SpellDefinitions.list do
				t.expect(seen[def.id]).toBe(true)
			end
		end)
		t.it("the ultimate is always slot 5", function()
			for _, def in SpellDefinitions.list do
				t.expect(def.ultimate == true).toBe(def.slot == 5)
			end
		end)
	end)

	t.describe("Element Crate", function()
		t.it("a new player can't afford it right away, but can after a win or two", function()
			local crate = Crates.get("Element") :: any
			t.expect(crate ~= nil).toBeTruthy()
			t.expect(Config.COINS.STARTING < crate.price).toBeTruthy()
			t.expect(Config.COINS.STARTING + Config.COINS.MATCH_WIN * 2 >= crate.price).toBeTruthy()
		end)
		t.it("only ever rolls elements you don't own", function()
			local rng = Random.new(7)
			for _ = 1, 200 do
				local owned = { "Fire" }
				local rolled = Crates.roll(owned, rng)
				t.expect(rolled ~= nil and rolled ~= "Fire" and Elements.get(rolled) ~= nil)
					.toBeTruthy()
			end
		end)
		t.it("can land on every element you're missing", function()
			local rng = Random.new(3)
			local seen: { [string]: boolean } = {}
			for _ = 1, 300 do
				local rolled = Crates.roll({ "Fire" }, rng)
				if rolled then
					seen[rolled] = true
				end
			end
			t.expect(seen.Water).toBe(true)
			t.expect(seen.Earth).toBe(true)
			t.expect(seen.Air).toBe(true)
		end)
		t.it("has nothing to roll once you own every element", function()
			t.expect(Crates.roll(Elements.ids(), Random.new(1))).toBeNil()
			t.expect(#Crates.unowned(Elements.ids())).toBe(0)
		end)
	end)

	t.describe("Boosts", function()
		t.it("offers 3 distinct boosts", function()
			local rng = Random.new(1)
			for _ = 1, 100 do
				local picks = Boosts.roll({}, rng)
				t.expect(#picks).toBe(Boosts.CARD_COUNT)
				local seen: { [string]: boolean } = {}
				for _, id in picks do
					t.expect(seen[id]).toBeNil()
					seen[id] = true
					t.expect(Boosts.get(id) ~= nil).toBeTruthy()
				end
			end
		end)
		t.it("stops offering a boost at its stack cap", function()
			local rng = Random.new(2)
			local owned = { Power = Boosts.MAX_STACKS }
			for _ = 1, 100 do
				t.expect(table.find(Boosts.roll(owned, rng), "Power")).toBeNil()
			end
		end)
		t.it("offers fewer cards when almost everything is maxed out", function()
			local owned = {}
			for _, boost in Boosts.LIST do
				owned[boost.id] = Boosts.MAX_STACKS
			end
			owned.Focus = 0
			t.expect(#Boosts.roll(owned, Random.new(1))).toBe(1)
		end)
		t.it("totals stack and respect the cooldown floor", function()
			local none = Boosts.totals({})
			t.expect(none.damage).toBe(1)
			t.expect(none.cooldownFactor).toBe(1)
			local lots = Boosts.totals({
				Power = 2,
				Vitality = 3,
				Swiftness = 1,
				Focus = 3,
				HealthPotion = 2,
			})
			t.expect(lots.damage).toBeNear(1.3, 0.001)
			t.expect(lots.maxHealth).toBe(60)
			t.expect(lots.speed).toBe(3)
			t.expect(lots.cooldownFactor).toBeNear(0.64, 0.001)
			t.expect(#lots.potions).toBe(2)
			local capped = Boosts.totals({ Focus = 99 })
			t.expect(capped.cooldownFactor >= Boosts.MIN_COOLDOWN_FACTOR).toBeTruthy()
		end)
	end)

	t.describe("Like & Favourite gift", function()
		t.it("is a one-time thank-you worth at most one crate, behind a short wait", function()
			local crate = Crates.get("Element") :: any
			t.expect(Config.SUPPORT.LIKE_FAVORITE_COINS > 0).toBeTruthy()
			t.expect(Config.SUPPORT.LIKE_FAVORITE_COINS <= crate.price).toBeTruthy()
			t.expect(Config.SUPPORT.MIN_SECONDS >= 30 and Config.SUPPORT.MIN_SECONDS <= 300)
				.toBeTruthy()
		end)
	end)
end
