--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)
local WordMatcher = require(ReplicatedStorage.Shared.Spells.WordMatcher)

return function(t: any)
	t.describe("WordMatcher.matchWord", function()
		t.it("matches spell names and aliases", function()
			t.expect(WordMatcher.matchWord("fireball")).toBe("Fireball")
			t.expect(WordMatcher.matchWord("Fire Slash")).toBe("FireSlash")
			t.expect(WordMatcher.matchWord("rock wall")).toBe("EarthWall")
			t.expect(WordMatcher.matchWord("bubble")).toBe("WaterLock")
		end)
		t.it("ignores case, punctuation, and spacing", function()
			t.expect(WordMatcher.matchWord("  FIRE-BALL!! ")).toBe("Fireball")
			t.expect(WordMatcher.matchWord("Water   Lock")).toBe("WaterLock")
			t.expect(WordMatcher.matchWord("waterlock")).toBe("WaterLock")
		end)
		t.it("tolerates one typo in 5+ letter words", function()
			t.expect(WordMatcher.matchWord("firebal")).toBe("Fireball")
			t.expect(WordMatcher.matchWord("tornadoo")).toBe("Tornado")
		end)
		t.it("does not fuzzy-match short words", function()
			t.expect(WordMatcher.matchWord("fir")).toBeNil()
		end)
		t.it("leaves normal chat alone", function()
			t.expect(WordMatcher.matchWord("hello everyone")).toBeNil()
			t.expect(WordMatcher.matchWord("gg")).toBeNil()
			t.expect(WordMatcher.matchWord("")).toBeNil()
		end)
	end)

	t.describe("WordMatcher.findInText", function()
		t.it("finds a spell inside a spoken sentence", function()
			t.expect(WordMatcher.findInText("um I cast fireball")).toBe("Fireball")
		end)
		t.it("prefers two-word spells", function()
			t.expect(WordMatcher.findInText("give me a rock wall please")).toBe("EarthWall")
		end)
		t.it("returns nil when nothing matches", function()
			t.expect(WordMatcher.findInText("what a nice day")).toBeNil()
		end)
	end)

	t.describe("dictionary", function()
		t.it("has no alias claimed by two spells", function()
			local owner: { [string]: string } = {}
			for _, def in SpellDefinitions.list do
				for _, alias in def.aliases do
					local key = WordMatcher.normalize(alias)
					if owner[key] and owner[key] ~= def.id then
						error(`alias "{key}" used by {owner[key]} and {def.id}`)
					end
					owner[key] = def.id
				end
			end
		end)
		t.it("every spell resolves from its own name", function()
			for _, def in SpellDefinitions.list do
				t.expect(WordMatcher.matchWord(def.name)).toBe(def.id)
			end
		end)
	end)
end
