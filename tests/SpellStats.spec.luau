--!strict
-- The numbers shown for a crate spell (Spells/SpellStats) match its definition.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local SpellStats = require(ReplicatedStorage.Shared.Spells.SpellStats)

return function(t: any)
	t.describe("SpellStats", function()
		t.it("lists damage, cooldown and range for a projectile", function()
			local tornado = SpellDefinitions.get("Tornado") :: any
			t.expect(SpellStats.text(tornado)).toBe("Damage 30   Cooldown 18s   Range 120")
		end)

		t.it("shows Black Hole's damage as a total over its duration", function()
			local hole = SpellDefinitions.get("BlackHole") :: any
			t.expect(SpellStats.text(hole)).toBe("Damage 10 over 3s   Cooldown 20s   Range 70")
		end)

		t.it("shows Turret's health and lifetime, and Heal's amount", function()
			local turret = SpellDefinitions.get("Turret") :: any
			t.expect(SpellStats.text(turret))
				.toBe("Damage 6   Health 30   Cooldown 20s   Duration 20s   Range 80")
			local heal = SpellDefinitions.get("Heal") :: any
			t.expect(SpellStats.text(heal)).toBe("Heal 20   Cooldown 60s")
		end)
	end)
end
