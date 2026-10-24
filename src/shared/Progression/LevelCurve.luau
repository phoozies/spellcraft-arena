--!strict
-- XP thresholds for levels 1..10 and what each level unlocks.
-- Pure module; tuning lives here only.

local Config = require(script.Parent.Parent.Config)
local SpellDefinitions = require(script.Parent.Parent.Spells.SpellDefinitions)

local LevelCurve = {}

-- Total XP required to *reach* each level (index = level).
LevelCurve.THRESHOLDS = table.freeze({ 0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200 })

assert(#LevelCurve.THRESHOLDS == Config.MAX_LEVEL, "LevelCurve thresholds must cover every level")

function LevelCurve.levelForXp(xp: number): number
	local level = 1
	for lvl, needed in LevelCurve.THRESHOLDS do
		if xp >= needed then
			level = lvl
		end
	end
	return level
end

-- Returns (xpIntoLevel, xpNeededForNextLevel); needed is 0 at max level.
function LevelCurve.progress(xp: number): (number, number)
	local level = LevelCurve.levelForXp(xp)
	if level >= Config.MAX_LEVEL then
		return 0, 0
	end
	local floor = LevelCurve.THRESHOLDS[level]
	local ceiling = LevelCurve.THRESHOLDS[level + 1]
	return xp - floor, ceiling - floor
end

-- Every spell a player of `level` owns through leveling.
function LevelCurve.spellsForLevel(level: number): { string }
	local ids = {}
	for _, def in SpellDefinitions.list do
		if def.unlockLevel <= level then
			table.insert(ids, def.id)
		end
	end
	return ids
end

return LevelCurve
