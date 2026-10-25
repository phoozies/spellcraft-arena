--!strict
-- Drawing quality: how a recognizer score becomes a cast bonus, and that the
-- best possible drawing still stays inside the balance budgets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GlyphRecognizer = require(ReplicatedStorage.Shared.Spells.GlyphRecognizer)
local Glyphs = require(ReplicatedStorage.Shared.Spells.Glyphs)
local Quality = require(ReplicatedStorage.Shared.Spells.Quality)
local SpellDefinitions = require(ReplicatedStorage.Shared.Spells.SpellDefinitions)

local MAX_BURST_DPS = 20
local MAX_HEAL_PER_SEC = 5
local MAX_HARD_CC_UPTIME = 0.6

-- A perfect drawing may exceed Balance.spec budgets by exactly its bonus: power
-- budgets by the POWER multiplier, duration budgets by the TIME multiplier.
local POWER = Config.QUALITY.POWER[2]
local TIME = Config.QUALITY.TIME[2]

local HARD_CC = { Root = true, TimeStop = true, Shrink = true, Stun = true }

return function(t: any)
	t.describe("Quality", function()
		t.it("maps the recognizer score onto 0..1", function()
			local q = Config.QUALITY
			t.expect(Quality.fromScore(q.SCORE_FLOOR)).toBe(0)
			t.expect(Quality.fromScore(0)).toBe(0)
			t.expect(Quality.fromScore(q.SCORE_PERFECT)).toBe(1)
			t.expect(Quality.fromScore(1)).toBe(1)
			t.expect(Quality.fromScore((q.SCORE_FLOOR + q.SCORE_PERFECT) / 2)).toBeNear(0.5, 1e-6)
		end)

		t.it("has ordered tiers that start at zero", function()
			t.expect(Quality.TIERS[1].min).toBe(0)
			for i = 2, #Quality.TIERS do
				t.expect(Quality.TIERS[i].min > Quality.TIERS[i - 1].min).toBeTruthy()
				t.expect(Quality.TIERS[i].stars > Quality.TIERS[i - 1].stars).toBeTruthy()
			end
			t.expect(Quality.tier(0).name).toBe(Quality.TIERS[1].name)
			t.expect(Quality.tier(1).name).toBe(Quality.TIERS[#Quality.TIERS].name)
		end)

		t.it("scales power, size, and time between the configured bounds", function()
			local q = Config.QUALITY
			local worst, best = Quality.multipliers(0), Quality.multipliers(1)
			t.expect(worst.power).toBeNear(q.POWER[1], 1e-6)
			t.expect(best.power).toBeNear(q.POWER[2], 1e-6)
			t.expect(best.size).toBeNear(q.SIZE[2], 1e-6)
			t.expect(worst.time).toBeNear(q.TIME[1], 1e-6)
			-- An average drawing is close to the spell as written (a perfect one
			-- gives the full +50% power, so the middle is a bit above 1).
			local middle = Quality.multipliers(q.DEFAULT)
			t.expect(math.abs(middle.power - 1) < 0.2).toBeTruthy()
			t.expect(math.abs(middle.size - 1) < 0.12).toBeTruthy()
			t.expect(math.abs(middle.time - 1) < 0.12).toBeTruthy()
		end)

		t.it("never changes the original spell, cooldowns, range, or speed", function()
			local fireball = SpellDefinitions.get("Fireball") :: any
			local before = fireball.stats.damage
			local best = Quality.apply(fireball, 1) :: any
			t.expect(fireball.stats.damage).toBe(before)
			t.expect(best.stats.damage > before).toBeTruthy()
			t.expect(best.stats.radius > fireball.stats.radius).toBeTruthy()
			t.expect(best.cooldown).toBe(fireball.cooldown)
			t.expect(best.stats.range).toBe(fireball.stats.range)
			t.expect(best.stats.speed).toBe(fireball.stats.speed)
			local worst = Quality.apply(fireball, 0) :: any
			t.expect(worst.stats.damage < before).toBeTruthy()
		end)

		t.it("a straighter slash scores higher", function()
			local function slash(bend: number): { Vector2 }
				local points = {}
				for i = 0, 20 do
					local f = i / 20
					table.insert(points, Vector2.new(f, 1 - f + math.sin(f * math.pi) * bend))
				end
				return points
			end
			local _, ruler = GlyphRecognizer.recognize(slash(0))
			local _, bent = GlyphRecognizer.recognize(slash(0.12))
			t.expect(ruler > bent).toBeTruthy()
			t.expect(ruler <= 1).toBeTruthy()
		end)

		t.it("a tidier shape scores higher than a sloppy one", function()
			local glyph = Glyphs.get("star") :: any
			local function draw(wobble: number): number
				local rng = Random.new(5)
				local points = {}
				local last = glyph.points[#glyph.points]
				local all = table.clone(glyph.points)
				table.insert(all, last)
				for i = 1, #all - 1 do
					for k = 0, 9 do
						local f = k / 10
						local p = all[i]:Lerp(all[i + 1], f)
						table.insert(
							points,
							p + Vector2.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * wobble
						)
					end
				end
				local _, score = GlyphRecognizer.recognize(points)
				return score
			end
			t.expect(draw(0.01) > draw(0.07)).toBeTruthy()
		end)

		-- The best possible drawing must still respect the balance budgets.
		for _, def in SpellDefinitions.list do
			t.it(`{def.name}: a perfect drawing stays within budget`, function()
				local best = Quality.apply(def, 1)
				local s = best.stats
				local window = math.max(Config.GLOBAL_CAST_LOCKOUT, def.cooldown)
				if s.damage then
					local hit = s.damage * (s.comboMultiplier or 1)
					local share = (if def.ultimate then 0.4 else 0.34) * POWER
					-- No one-shots, even with a perfect drawing.
					t.expect(hit <= Config.PLAYER_MAX_HEALTH * share + 1e-6).toBeTruthy()
					if
						not def.stats.duration
						and not def.stats.hazardDps
						and not def.stats.turret
						and not def.stats.lifetime
					then
						t.expect(hit / window <= MAX_BURST_DPS * POWER + 1e-6).toBeTruthy()
					end
				end
				if s.heal then
					local total = if s.duration then s.heal * s.duration else s.heal
					t.expect(total / window <= MAX_HEAL_PER_SEC * POWER * TIME + 1e-6).toBeTruthy()
				end
				if s.shield then
					t.expect(s.shield / window <= MAX_HEAL_PER_SEC * POWER + 1e-6).toBeTruthy()
				end
				if s.status and HARD_CC[s.status] then
					t.expect((s.statusDuration or 0) / window <= MAX_HARD_CC_UPTIME * TIME + 1e-6)
						.toBeTruthy()
				end
				if def.archetype == "Buff" and s.duration then
					t.expect(s.duration / def.cooldown <= 0.6 * TIME + 1e-6).toBeTruthy()
				end
			end)
		end
	end)
end
