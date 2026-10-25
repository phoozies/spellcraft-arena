--!strict
-- The crate shop. An Element Crate costs coins and "spins" a reel that lands
-- on one element you don't own yet; opening it unlocks that element's five
-- spells. Pure module (no services, an injectable RNG) so tests are
-- deterministic; the server's CrateService is the only caller that spends
-- coins or grants elements, and the client's CrateController only animates
-- the result the server sends.
--
-- How a spin is decided:
--   1. Collect the elements the player doesn't own yet.
--   2. Pick one uniformly. If they own every element there is nothing to
--      win, and the crate can't be opened (the shop says so).

local Elements = require(script.Parent.Parent.Spells.Elements)
local Types = require(script.Parent.Parent.Types)

type CrateDef = Types.CrateDef

local Crates = {}

-- Seconds the client's reel spins; the server won't accept another open
-- from the same player until this has passed.
Crates.SPIN_TIME = 4

Crates.LIST = table.freeze({
	{ id = "Element", name = "Element Crate", price = 250 },
} :: { CrateDef })

local byId: { [string]: CrateDef } = {}
for _, crate in Crates.LIST do
	byId[crate.id] = crate
end

function Crates.get(id: string): CrateDef?
	return byId[id]
end

-- Elements this player could still win.
function Crates.unowned(owned: { string }): { string }
	local list = {}
	for _, element in Elements.LIST do
		if not table.find(owned, element.id) then
			table.insert(list, element.id)
		end
	end
	return list
end

-- Decides a spin: a random element the player doesn't own, or nil when they
-- own them all.
function Crates.roll(owned: { string }, rng: Random): string?
	local pool = Crates.unowned(owned)
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

return Crates
