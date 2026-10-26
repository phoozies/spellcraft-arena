--!strict
-- Match boosts. In a duel you don't earn more spells; after each round you
-- pick one of three boosts that last for the rest of the match and stack.
-- Pure data plus a roller with an injectable RNG (tests are deterministic);
-- the server's BoostService applies them.
--
-- Effects (read by BoostService):
--   damage     +N% damage dealt (multiplies: 1 + damage * stacks)
--   maxHealth  +N max health (and heals that much)
--   speed      +N walk speed
--   cooldown   spell cooldowns shortened by N% per stack (min 50% total)
--   potion     once per round, when you fall below `below` of your health,
--              heal `heal` HP

export type Boost = {
	id: string,
	name: string,
	icon: string,
	description: string,
	damage: number?,
	maxHealth: number?,
	speed: number?,
	cooldown: number?,
	potion: { below: number, heal: number }?,
}

local Boosts = {}

-- A boost can be picked at most this many times in one match.
Boosts.MAX_STACKS = 3
-- Cards offered each round.
Boosts.CARD_COUNT = 3
-- Cooldowns can't be cut below this fraction, however many boosts stack.
Boosts.MIN_COOLDOWN_FACTOR = 0.5

Boosts.LIST = {
	{
		id = "Power",
		name = "Power",
		icon = "PWR",
		description = "+15% damage",
		damage = 0.15,
	},
	{
		id = "Vitality",
		name = "Vitality",
		icon = "HP",
		description = "+20 max health",
		maxHealth = 20,
	},
	{
		id = "Swiftness",
		name = "Swiftness",
		icon = "SPD",
		description = "+3 move speed",
		speed = 3,
	},
	{
		id = "Focus",
		name = "Focus",
		icon = "FOC",
		description = "Spells recharge 12% faster",
		cooldown = 0.12,
	},
	{
		id = "HealthPotion",
		name = "Health Potion",
		icon = "POT",
		description = "Once a round, heal 35 when you fall below 35% health",
		potion = { below = 0.35, heal = 35 },
	},
} :: { Boost }

local byId: { [string]: Boost } = {}
for _, boost in Boosts.LIST do
	assert(byId[boost.id] == nil, `duplicate boost {boost.id}`)
	byId[boost.id] = boost
	table.freeze(boost)
end
Boosts.byId = byId

function Boosts.get(id: string): Boost?
	return byId[id]
end

-- Rolls up to CARD_COUNT different boosts the player can still stack.
-- `owned` maps boost id -> times picked so far.
function Boosts.roll(owned: { [string]: number }, rng: Random): { string }
	local pool: { string } = {}
	for _, boost in Boosts.LIST do
		if (owned[boost.id] or 0) < Boosts.MAX_STACKS then
			table.insert(pool, boost.id)
		end
	end
	local picks: { string } = {}
	while #picks < Boosts.CARD_COUNT and #pool > 0 do
		table.insert(picks, table.remove(pool, rng:NextInteger(1, #pool)) :: string)
	end
	return picks
end

-- Totals for a player's picks (boost id -> stacks).
export type Totals = {
	damage: number, -- multiplier, 1 = none
	maxHealth: number,
	speed: number,
	cooldownFactor: number, -- multiplier on cooldowns, 1 = none
	potions: { { below: number, heal: number } },
}

function Boosts.totals(owned: { [string]: number }): Totals
	local totals: Totals =
		{ damage = 1, maxHealth = 0, speed = 0, cooldownFactor = 1, potions = {} }
	local cut = 0
	for id, stacks in owned do
		local boost = byId[id]
		if boost and stacks > 0 then
			stacks = math.min(stacks, Boosts.MAX_STACKS)
			totals.damage += (boost.damage or 0) * stacks
			totals.maxHealth += (boost.maxHealth or 0) * stacks
			totals.speed += (boost.speed or 0) * stacks
			cut += (boost.cooldown or 0) * stacks
			if boost.potion then
				for _ = 1, stacks do
					table.insert(totals.potions, boost.potion)
				end
			end
		end
	end
	totals.cooldownFactor = math.max(Boosts.MIN_COOLDOWN_FACTOR, 1 - cut)
	return totals
end

return Boosts
