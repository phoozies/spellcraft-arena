--!strict
-- Elements (shared/Spells/Elements), rarities, the chests
-- (shared/Economy/Chests), the loadout rules (shared/Spells/Loadout), and match
-- boosts (shared/Match/Boosts). All pure modules with injectable RNGs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Boosts = require(ReplicatedStorage.Shared.Match.Boosts)
local Chests = require(ReplicatedStorage.Shared.Economy.Chests)
local Elements = require(ReplicatedStorage.Shared.Spells.Elements)
local Loadout = require(ReplicatedStorage.Shared.Spells.Loadout)
local Rarity = require(ReplicatedStorage.Shared.Spells.Rarity)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

return function(t: any)
	t.describe("Elements", function()
		t.it("there are four, each with three base spells in slot order", function()
			t.expect(#Elements.LIST).toBe(4)
			for _, element in Elements.LIST do
				t.expect(#element.base).toBe(Elements.BASE_COUNT)
				t.expect(element.price > 0).toBeTruthy()
				for slot, id in element.base do
					local def = SpellDefinitions.get(id)
					t.expect(def ~= nil and def.element == element.id and def.slot == slot)
						.toBeTruthy()
					t.expect(def ~= nil and def.rarity == nil).toBeTruthy()
				end
			end
		end)
		t.it("each element comes with the base spells it was specified with", function()
			local expected = {
				Fire = { "Fireball", "FireSlash", "FireBoost" },
				Water = { "WaterSlice", "WaterBody", "WaterLock" },
				Earth = { "RockThrow", "EarthWall", "EarthPunch" },
				Air = { "Gust", "Whirlwind", "AirBoost" },
			}
			for id, spells in expected do
				local element = Elements.get(id) :: any
				for slot, spellId in spells do
					t.expect(element.base[slot]).toBe(spellId)
				end
			end
		end)
		t.it("every spell is a base spell or a chest spell with a rarity, never both", function()
			local base: { [string]: boolean } = {}
			for _, element in Elements.LIST do
				for _, id in element.base do
					t.expect(base[id]).toBeNil()
					base[id] = true
				end
			end
			for _, def in SpellDefinitions.list do
				t.expect((base[def.id] == true) ~= (def.rarity ~= nil)).toBeTruthy()
				if def.rarity then
					t.expect(Rarity.get(def.rarity) ~= nil).toBeTruthy()
				end
			end
			t.expect(#SpellDefinitions.chestSpells()).toBe(#SpellDefinitions.list - 12)
		end)
		t.it("the ultimate is always slot 5", function()
			for _, def in SpellDefinitions.list do
				t.expect(def.ultimate == true).toBe(def.slot == 5)
			end
		end)
		t.it("an element costs real coins, at least a match win", function()
			for _, element in Elements.LIST do
				t.expect(element.price >= Config.COINS.MATCH_WIN).toBeTruthy()
			end
		end)
	end)

	t.describe("Rarity", function()
		t.it("has the five rarities in order, with weights that favour the common", function()
			local names = {}
			local last = math.huge
			for _, rarity in Rarity.LIST do
				table.insert(names, rarity.id)
				t.expect(rarity.weight < last).toBeTruthy()
				last = rarity.weight
			end
			t.expect(table.concat(names, ",")).toBe("Common,Uncommon,Rare,Epic,Legendary")
			t.expect(Rarity.TOTAL_WEIGHT).toBe(100)
		end)
		t.it("every rarity has at least one spell in a chest", function()
			for _, rarity in Rarity.LIST do
				t.expect(#Chests.ofRarity(rarity.id) > 0).toBeTruthy()
			end
		end)
		t.it("the spells people asked for are in a chest", function()
			for _, id in { "Heal", "AirShield", "BlackHole", "Turret", "Zap" } do
				local def = SpellDefinitions.get(id)
				t.expect(def ~= nil and def.rarity ~= nil).toBeTruthy()
			end
		end)
	end)

	t.describe("Chests", function()
		t.it("there is one chest per rarity, each pricier than the last", function()
			t.expect(#Chests.LIST).toBe(#Rarity.LIST)
			local last = 0
			for index, chest in Chests.LIST do
				t.expect(chest.id).toBe(Rarity.LIST[index].id)
				t.expect(chest.minRarity).toBe(Rarity.LIST[index].id)
				t.expect(chest.price > last).toBeTruthy()
				last = chest.price
			end
		end)
		t.it("a new player can afford a Common Chest, and one win funds another", function()
			local chest = Chests.get("Common") :: any
			t.expect(Config.COINS.STARTING >= chest.price).toBeTruthy()
			t.expect(Config.COINS.MATCH_WIN >= chest.price).toBeTruthy()
		end)
		t.it("duplicate refunds always cost less than the chest", function()
			for _, chest in Chests.LIST do
				for _, rarity in Rarity.LIST do
					local refund = Chests.refund(chest, rarity.id)
					t.expect(refund > 0 and refund < chest.price).toBeTruthy()
				end
			end
		end)
		t.it("a chest only drops its rarity or better", function()
			local rng = Random.new(7)
			for _, chest in Chests.LIST do
				for _ = 1, 200 do
					local roll = Chests.roll(chest.id, {}, rng) :: any
					t.expect(roll ~= nil).toBeTruthy()
					local def = SpellDefinitions.get(roll.spell) :: any
					t.expect(def.rarity).toBe(roll.rarity)
					t.expect(Rarity.rank(roll.rarity) >= Rarity.rank(chest.minRarity)).toBeTruthy()
					t.expect(roll.duplicate).toBe(false)
				end
			end
		end)
		t.it("each chest's odds add up to 100% and favour its own rarity", function()
			for _, chest in Chests.LIST do
				local rows = Chests.odds(chest.id)
				local total = 0
				for _, row in rows do
					total += row.percent
				end
				t.expect(total).toBeNear(100, 0.001)
				t.expect(rows[1].rarity).toBe(chest.minRarity)
				for i = 2, #rows do
					t.expect(rows[i].percent < rows[i - 1].percent).toBeTruthy()
				end
			end
		end)
		t.it("follows the odds: commons far outnumber legendaries in a Common Chest", function()
			local rng = Random.new(11)
			local counts: { [string]: number } = {}
			for _ = 1, 4000 do
				local roll = Chests.roll("Common", {}, rng)
				if roll then
					counts[roll.rarity] = (counts[roll.rarity] or 0) + 1
				end
			end
			t.expect((counts.Common or 0) > (counts.Uncommon or 0)).toBeTruthy()
			t.expect((counts.Uncommon or 0) > (counts.Rare or 0)).toBeTruthy()
			t.expect((counts.Rare or 0) > (counts.Legendary or 0)).toBeTruthy()
			t.expect((counts.Legendary or 0) > 0).toBeTruthy()
		end)
		t.it("pays a refund for spells you own and flags them", function()
			local rng = Random.new(5)
			local owned = Chests.ofRarity("Common") -- the whole common tier
			local chest = Chests.get("Common") :: any
			local sawDuplicate = false
			for _ = 1, 400 do
				local roll = Chests.roll("Common", owned, rng)
				if roll and roll.duplicate then
					sawDuplicate = true
					t.expect(roll.refund).toBe(Chests.refund(chest, roll.rarity))
					t.expect(table.find(owned, roll.spell) ~= nil).toBeTruthy()
				end
			end
			t.expect(sawDuplicate).toBe(true)
		end)
		t.it(
			"Epic and Legendary chests never give a duplicate while a new spell is left",
			function()
				local rng = Random.new(8)
				for _, id in { "Epic", "Legendary" } do
					local pool = Chests.pool(id)
					local owned = { pool[1] }
					for _ = 1, 200 do
						local roll = Chests.roll(id, owned, rng) :: any
						t.expect(roll.duplicate).toBe(false)
						t.expect(roll.spell ~= pool[1]).toBeTruthy()
					end
				end
			end
		)
		t.it("guarantees an Epic or better when the pity counter is full", function()
			local rng = Random.new(5)
			local pity = Chests.PITY.SPINS - 1
			t.expect(Chests.spinsToPity(pity)).toBe(1)
			for _ = 1, 200 do
				local roll = Chests.roll("Common", {}, rng, pity) :: any
				t.expect(roll.guaranteed).toBe(true)
				t.expect(Rarity.rank(roll.rarity) >= Rarity.rank(Chests.PITY.RARITY)).toBeTruthy()
			end
		end)
		t.it("does not guarantee anything with a fresh counter", function()
			local roll = Chests.roll("Common", {}, Random.new(5), 0) :: any
			t.expect(roll.guaranteed).toBe(false)
			t.expect(Chests.spinsToPity(0)).toBe(Chests.PITY.SPINS)
		end)
		t.it("the pity guarantee prefers a spell you do not own yet", function()
			local owned = {}
			local fresh = nil
			for _, id in Chests.pool() do
				local def = SpellDefinitions.get(id) :: any
				if Rarity.rank(def.rarity) >= Rarity.rank(Chests.PITY.RARITY) and not fresh then
					fresh = id
				else
					table.insert(owned, id)
				end
			end
			local rng = Random.new(9)
			for _ = 1, 50 do
				local roll = Chests.roll("Uncommon", owned, rng, Chests.PITY.SPINS - 1) :: any
				t.expect(roll.spell).toBe(fresh)
				t.expect(roll.duplicate).toBe(false)
			end
		end)
		t.it("the pity counter climbs on misses and resets on an Epic or better", function()
			t.expect(Chests.nextPity(3, "Common")).toBe(4)
			t.expect(Chests.nextPity(3, "Rare")).toBe(4)
			t.expect(Chests.nextPity(3, "Epic")).toBe(0)
			t.expect(Chests.nextPity(9, "Legendary")).toBe(0)
		end)
		t.it("won't sell a chest whose every spell you own", function()
			t.expect(Chests.roll("Common", Chests.pool(), Random.new(1))).toBeNil()
			t.expect(Chests.ownsAll(Chests.pool())).toBe(true)
			t.expect(Chests.ownsAll({})).toBe(false)
			local legendaries = Chests.pool("Legendary")
			t.expect(Chests.ownsAll(legendaries, "Legendary")).toBe(true)
			t.expect(Chests.roll("Legendary", legendaries, Random.new(1))).toBeNil()
			t.expect(Chests.roll("Common", legendaries, Random.new(1)) ~= nil).toBeTruthy()
			t.expect(Chests.roll("NoSuchChest", {}, Random.new(1))).toBeNil()
		end)
	end)

	t.describe("Loadout", function()
		t.it("is the base spells then the extras", function()
			local list = Loadout.spells("Fire", { "Heal", "Zap" })
			t.expect(table.concat(list, ",")).toBe("Fireball,FireSlash,FireBoost,Heal,Zap")
			t.expect(#Loadout.spells("Nope", { "Heal" })).toBe(0)
		end)
		t.it("never holds two spells with the same shape", function()
			-- Heal is a heart, so it fits beside any base trio.
			t.expect(Loadout.problem("Heal", Loadout.spells("Fire", {}))).toBeNil()
			-- Fire Pillar and Earth Pillar are both V shapes.
			t.expect(
				Loadout.problem("EarthPillar", Loadout.spells("Fire", { "FirePillar" })) ~= nil
			)
				.toBeTruthy()
			-- Earth Punch is a bolt, so Water Wave (a bolt too) cannot join Earth.
			t.expect(Loadout.problem("WaterWave", Loadout.spells("Earth", {})) ~= nil).toBeTruthy()
			t.expect(Loadout.problem("WaterWave", Loadout.spells("Fire", {}))).toBeNil()
		end)
		t.it("the Arcane spells and Air Shield have shapes no base spell uses", function()
			for _, element in Elements.LIST do
				local base = Loadout.spells(element.id, {})
				for _, id in { "Heal", "Zap", "Turret", "BlackHole", "AirShield" } do
					t.expect(Loadout.problem(id, base)).toBeNil()
				end
			end
		end)
		t.it("only takes chest spells", function()
			t.expect(Loadout.problem("Fireball", {}) ~= nil).toBeTruthy()
			t.expect(Loadout.problem("NotASpell", {}) ~= nil).toBeTruthy()
		end)
		t.it("sanitizes an untrusted loadout: owned, unique, fitting, at most two", function()
			local owned = { "Heal", "Zap", "Turret", "AirShield", "Tornado" }
			local asked = { "Heal", "Heal", "Fireball", "Turret", "Tornado" }
			local kept = Loadout.sanitize("Fire", asked, owned)
			t.expect(table.concat(kept, ",")).toBe("Heal,Turret")
			t.expect(#Loadout.sanitize("Fire", { "Heal" }, {})).toBe(0)
			t.expect(#Loadout.sanitize("Fire", "nonsense", owned)).toBe(0)
		end)
		t.it("every element can equip a support spell and an ultimate", function()
			-- Chevron and star are free in every element's base trio.
			for _, element in Elements.LIST do
				local base = Loadout.spells(element.id, {})
				t.expect(Loadout.problem("Heal", base)).toBeNil()
				t.expect(Loadout.problem("Tornado", base)).toBeNil()
			end
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
		t.it("is a one-time thank-you worth less than an element, behind a short wait", function()
			local fire = Elements.get("Fire") :: any
			t.expect(Config.SUPPORT.LIKE_FAVORITE_COINS > 0).toBeTruthy()
			t.expect(Config.SUPPORT.LIKE_FAVORITE_COINS < fire.price).toBeTruthy()
			t.expect(Config.SUPPORT.MIN_SECONDS >= 30 and Config.SUPPORT.MIN_SECONDS <= 300)
				.toBeTruthy()
		end)
	end)
end
