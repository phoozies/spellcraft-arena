--!strict
-- Checks the imported models in ReplicatedStorage.Models (made by
-- tools/prepare-models.luau). The models live in the place file, so a place
-- built by CI won't have them: every check is skipped when a model is
-- missing, and the game falls back to plain shapes (see ModelKit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

-- Expected mesh parts and the rough size (studs, longest side) of each model.
local EXPECTED = {
	Fireball = { parts = { "Fireball_Core", "Fireball_Outer", "Fireball_Tail" }, maxSize = 12 },
	WaterBubble = { parts = { "Bubble_Shell", "Bubble_Inner", "Bubble_Highlight" }, maxSize = 12 },
	RockWall = { parts = { "Wall_Base", "Wall_Pillars", "Wall_Rubble" }, maxSize = 30 },
	Arena = {
		parts = { "Arena_Floor", "Arena_Pillars", "Arena_RuneRing", "Arena_Seating" },
		maxSize = 90,
	},
	Grimoire = {
		parts = { "Grimoire_Cover", "Grimoire_Pages", "Grimoire_Gold", "Grimoire_Gem" },
		maxSize = 6,
	},
	Gust = { parts = { "Gust_Swirl", "Gust_Core", "Gust_Streaks" }, maxSize = 12 },
	Zap = { parts = { "Zap_Bolt", "Zap_Glow" }, maxSize = 30 },
	Heal = { parts = { "Heal_Cross", "Heal_Ring" }, maxSize = 6 },
	BlackHole = { parts = { "BlackHole_Core", "BlackHole_Disk", "BlackHole_Ring" }, maxSize = 12 },
	Turret = {
		parts = { "Turret_Base", "Turret_Head", "Turret_Barrel", "Turret_Lens" },
		maxSize = 8,
	},
	Crate = { parts = { "Crate_Body", "Crate_Trim", "Crate_Gem" }, maxSize = 6 },
}

-- The default colour of an imported, un-coloured mesh.
local UNCOLOURED = Color3.new(0.639216, 0.635294, 0.647059)

local function nearlyEqual(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.01
end

return function(t: any)
	t.describe("Imported models", function()
		for name, spec in EXPECTED do
			local model = ModelKit.get(name)
			t.it(`{name}: has its parts, game-sized, and is coloured`, function()
				if not model then
					return -- not in this place; the game uses fallbacks
				end
				for _, partName in spec.parts do
					local part = model:FindFirstChild(partName)
					t.expect(part ~= nil and part:IsA("BasePart")).toBeTruthy()
					t.expect(not nearlyEqual((part :: BasePart).Color, UNCOLOURED)).toBeTruthy()
				end
				local _, size = model:GetBoundingBox()
				t.expect(math.max(size.X, size.Y, size.Z) <= spec.maxSize).toBeTruthy()
			end)
		end

		t.it("Rock Wall's visual size matches its model (placement rules fit it)", function()
			local model = ModelKit.get("RockWall")
			local def = SpellDefinitions.get("RockWall")
			if not model or not def then
				return
			end
			local _, size = model:GetBoundingBox()
			t.expect(math.abs(size.X - def.visual.size.X) < 0.2).toBeTruthy()
			t.expect(math.abs(size.Y - def.visual.size.Y) < 0.2).toBeTruthy()
			t.expect(math.abs(size.Z - def.visual.size.Z) < 0.2).toBeTruthy()
		end)

		t.it("every spell's model names exist when models are present", function()
			for _, def in SpellDefinitions.list do
				-- Only check spells whose models were imported into this place.
				local name = def.visual.model or def.stats.model
				if name and ModelKit.get("RockWall") ~= nil and ModelKit.get(name) == nil then
					warn(`[Models] {def.name} uses model "{name}", not in ReplicatedStorage.Models (using the fallback shape)`)
				end
				if def.stats.model and ModelKit.get("RockWall") ~= nil then
					t.expect(ModelKit.get(def.stats.model) ~= nil).toBeTruthy()
				end
			end
		end)
	end)
end
