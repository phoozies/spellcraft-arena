--!strict
-- Finds out whether a player is trapped at the bottom of a hole carved into
-- the terrain, and which way out is nearest. The ray cast is passed in, so the
-- server uses real raycasts and tests use made-up walls.
--
-- A player is trapped when, from head height above a jump's reach, every one of
-- eight horizontal rays hits a terrain cell within `reach` studs: walls all
-- around that a jump cannot clear. Anything else (open air, scenery, a gap)
-- means there is a way out, so nobody is rescued by mistake.

local Pit = {}

export type Hit = { distance: number, isTerrain: boolean }
export type Cast = (origin: Vector3, direction: Vector3, length: number) -> Hit?

export type Enclosure = {
	direction: Vector3, -- unit, horizontal: toward the nearest wall
	distance: number,
}

local DIRECTIONS: { Vector3 } = {}
for i = 0, 7 do
	local angle = i / 8 * math.pi * 2
	table.insert(DIRECTIONS, Vector3.new(math.sin(angle), 0, -math.cos(angle)))
end
Pit.DIRECTIONS = DIRECTIONS

-- `origin` is the point to look from: the player's feet plus the climb height.
-- Returns nil unless every direction is walled in by terrain.
function Pit.enclosure(origin: Vector3, reach: number, cast: Cast): Enclosure?
	local nearest: Enclosure? = nil
	for _, direction in DIRECTIONS do
		local hit = cast(origin, direction, reach)
		if not hit or not hit.isTerrain then
			return nil
		end
		if nearest == nil or hit.distance < nearest.distance then
			nearest = { direction = direction, distance = hit.distance }
		end
	end
	return nearest
end

return Pit
