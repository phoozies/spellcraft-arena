--!strict
-- Drawing quality: the better a stroke follows its shape, the stronger the
-- spell. Pure module, shared by the server (which scores and applies it) and
-- the client (which names the tier and colors the stroke).
--
--   score (GlyphRecognizer, 0..1) ──fromScore──► quality (0..1)
--   quality ──multipliers──► { power, size, time }
--   Quality.apply(def, quality) ──► a copy of the spell def with its stats scaled:
--     power: damage, heal, shield, health, hazardDps, and Fire Boost's damageMult bonus
--     size:  radius (the hit area)
--     time:  duration, statusDuration, lifetime
--   Cooldowns, range, speed, and costs never change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local Quality = {}

export type Tier = { name: string, min: number, color: Color3, stars: number }

-- Lowest quality first.
Quality.TIERS = table.freeze({
	{ name = "Rough", min = 0, color = Color3.fromRGB(239, 83, 80), stars = 1 },
	{ name = "Good", min = 0.35, color = Color3.fromRGB(255, 167, 38), stars = 2 },
	{ name = "Great", min = 0.7, color = Color3.fromRGB(129, 199, 132), stars = 3 },
	{ name = "Perfect", min = 0.92, color = Color3.fromRGB(255, 214, 64), stars = 4 },
} :: { Tier })

function Quality.fromScore(score: number): number
	local q = Config.QUALITY
	return math.clamp((score - q.SCORE_FLOOR) / (q.SCORE_PERFECT - q.SCORE_FLOOR), 0, 1)
end

function Quality.tier(quality: number): Tier
	local found = Quality.TIERS[1]
	for _, tier in Quality.TIERS do
		if quality >= tier.min then
			found = tier
		end
	end
	return found
end

local function between(range: { number }, quality: number): number
	return range[1] + (range[2] - range[1]) * math.clamp(quality, 0, 1)
end

function Quality.multipliers(quality: number): { power: number, size: number, time: number }
	local q = Config.QUALITY
	return {
		power = between(q.POWER, quality),
		size = between(q.SIZE, quality),
		time = between(q.TIME, quality),
	}
end

-- Whole-number percent bonus (or penalty) text, e.g. "+12% power".
function Quality.describe(quality: number): string
	local power = Quality.multipliers(quality).power
	local percent = math.floor((power - 1) * 100 + 0.5)
	return `{if percent >= 0 then "+" else ""}{percent}% power`
end

local POWER_KEYS = { "damage", "heal", "shield", "health", "hazardDps" }
local SIZE_KEYS = { "radius" }
local TIME_KEYS = { "duration", "statusDuration", "lifetime" }

-- A scaled copy of `def` (the original is never touched).
function Quality.apply(def: Types.SpellDef, quality: number): Types.SpellDef
	local m = Quality.multipliers(quality)
	local stats: any = table.clone(def.stats)
	for _, key in POWER_KEYS do
		if stats[key] then
			stats[key] *= m.power
		end
	end
	for _, key in SIZE_KEYS do
		if stats[key] then
			stats[key] *= m.size
		end
	end
	for _, key in TIME_KEYS do
		if stats[key] then
			stats[key] *= m.time
		end
	end
	-- A damage multiplier buff (Fire Boost) scales its bonus, not the whole.
	if stats.damageMult then
		stats.damageMult = 1 + (stats.damageMult - 1) * m.power
	end
	local scaled: any = table.clone(def)
	scaled.stats = stats
	return scaled
end

return Quality
