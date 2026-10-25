--!strict
-- The Battleground's hostile NPCs: what each kind looks like, how tough it
-- is, how it fights, and what it pays when a player knocks it out.
-- Pure data (NpcService builds and runs them; tests/Npcs.spec checks the
-- numbers). Maps place them: every "NpcSpot" part in Maps/Battleground names
-- one of these ids in its `NpcType` attribute.
--
--   health    hit points (spells hurt them like any other target)
--   speed     walk speed
--   aggro     studs at which it notices a player and starts chasing
--   leash     studs from home at which it gives up, goes home, and heals
--   melee     { damage, range, interval, windup, knockback? } swings when close
--   ranged    { damage, range, interval, speed, windup } shoots bolts from afar
--             (a type may have both: it shoots at range and swings up close)
--   reward    coins paid to the player who knocks it out (capped per player,
--             see Config.BATTLEGROUND.NPC)
--   respawn   seconds until a new one appears at its spot (default Config)
--   scale     body size multiplier

local Npcs = {}

export type Melee = {
	damage: number,
	range: number,
	interval: number,
	windup: number,
	knockback: number?,
}
export type Ranged = {
	damage: number,
	range: number,
	interval: number,
	speed: number,
	windup: number,
}

export type NpcType = {
	id: string,
	name: string,
	health: number,
	speed: number,
	aggro: number,
	leash: number,
	melee: Melee?,
	ranged: Ranged?,
	reward: number,
	respawn: number?,
	scale: number,
	-- Look: skin, shirt and trousers, and an accent glow (staffs, eyes).
	skin: Color3,
	shirt: Color3,
	pants: Color3,
	accent: Color3,
}

Npcs.LIST = {
	{
		id = "Raider",
		name = "Sand Raider",
		health = 60,
		speed = 13,
		aggro = 55,
		leash = 110,
		melee = { damage = 8, range = 5.5, interval = 1.3, windup = 0.35 },
		reward = 3,
		scale = 1,
		skin = Color3.fromRGB(224, 172, 120),
		shirt = Color3.fromRGB(196, 150, 84),
		pants = Color3.fromRGB(110, 84, 60),
		accent = Color3.fromRGB(255, 120, 60),
	},
	{
		id = "Mage",
		name = "Ember Mage",
		health = 45,
		speed = 11,
		aggro = 70,
		leash = 120,
		ranged = { damage = 11, range = 75, interval = 2.2, speed = 60, windup = 0.45 },
		reward = 5,
		scale = 1,
		skin = Color3.fromRGB(240, 200, 160),
		shirt = Color3.fromRGB(200, 70, 40),
		pants = Color3.fromRGB(110, 40, 30),
		accent = Color3.fromRGB(255, 150, 50),
	},
	{
		id = "Brute",
		name = "Stone Brute",
		health = 160,
		speed = 10,
		aggro = 45,
		leash = 100,
		melee = { damage = 18, range = 7, interval = 2, windup = 0.55, knockback = 45 },
		reward = 12,
		scale = 1.55,
		skin = Color3.fromRGB(150, 150, 156),
		shirt = Color3.fromRGB(120, 116, 112),
		pants = Color3.fromRGB(88, 84, 82),
		accent = Color3.fromRGB(255, 200, 80),
	},
	{
		id = "Warlord",
		name = "Dune Warlord",
		health = 420,
		speed = 12,
		aggro = 80,
		leash = 140,
		melee = { damage = 22, range = 7.5, interval = 1.8, windup = 0.5, knockback = 55 },
		ranged = { damage = 14, range = 70, interval = 3, speed = 55, windup = 0.6 },
		reward = 40,
		respawn = 180,
		scale = 1.9,
		skin = Color3.fromRGB(170, 120, 90),
		shirt = Color3.fromRGB(150, 36, 36),
		pants = Color3.fromRGB(60, 40, 40),
		accent = Color3.fromRGB(255, 214, 64),
	},
} :: { NpcType }

local byId: { [string]: NpcType } = {}
for _, npc in Npcs.LIST do
	assert(byId[npc.id] == nil, `duplicate npc {npc.id}`)
	assert(npc.melee ~= nil or npc.ranged ~= nil, `{npc.id} can't fight`)
	byId[npc.id] = npc
	if npc.melee then
		table.freeze(npc.melee)
	end
	if npc.ranged then
		table.freeze(npc.ranged)
	end
	table.freeze(npc)
end
Npcs.byId = byId

function Npcs.get(id: string): NpcType?
	return byId[id]
end

return Npcs
