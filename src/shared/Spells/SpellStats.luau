--!strict
-- Reads a spell's numbers (damage, healing, cooldown, duration, range, ...)
-- out of its SpellDefinitions row for display. The Spellbook detail and the
-- chest reveal both show this, so a chest spell's metadata is always
-- the same wherever you meet it. Pure data, nothing is stored.
--
--   SpellStats.list(def)  -> { { label, value } } in display order
--   SpellStats.text(def)  -> "Damage 30  Cooldown 18s  ..." (one line)

local Types = require(script.Parent.Parent.Types)

local SpellStats = {}

export type Stat = { label: string, value: string }

local function num(n: number): string
	local rounded = math.floor(n * 10 + 0.5) / 10
	return if rounded == math.floor(rounded)
		then tostring(math.floor(rounded))
		else tostring(rounded)
end

function SpellStats.list(def: Types.SpellDef): { Stat }
	local s: any = def.stats
	local out: { Stat } = {}
	local function add(label: string, value: string)
		table.insert(out, { label = label, value = value })
	end
	if s.damage then
		-- A lingering zone (Black Hole) stores damage per second.
		if def.archetype == "Zone" and s.duration and not s.delay then
			add("Damage", `{num(s.damage * s.duration)} over {num(s.duration)}s`)
		else
			add("Damage", num(s.damage))
		end
	end
	if s.heal then
		add("Heal", num(s.heal))
	end
	if s.health then
		add("Health", num(s.health))
	end
	add("Cooldown", `{num(def.cooldown)}s`)
	-- Heal's `duration` is only how long its glow lasts, so only lifetimes count.
	if s.lifetime then
		add("Duration", `{num(s.lifetime)}s`)
	end
	if s.range then
		add("Range", num(s.range))
	end
	return out
end

function SpellStats.text(def: Types.SpellDef): string
	local parts = {}
	for _, stat in SpellStats.list(def) do
		table.insert(parts, `{stat.label} {stat.value}`)
	end
	return table.concat(parts, "   ")
end

return SpellStats
