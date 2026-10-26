--!strict
-- The water under every arena and the way out of terrain pits: the arc math
-- lands where it should, the settings make sense next to the player's jump and
-- health, and hole detection only fires when every way out is walled in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ballistic = require(ReplicatedStorage.Shared.Util.Ballistic)
local Pit = require(ReplicatedStorage.Shared.Util.Pit)

local GRAVITY = 196.2

-- A fake world: terrain walls at these distances (nil = open) in each of the
-- eight directions, in Pit.DIRECTIONS order.
local function wallsAt(distances: { number? }, terrain: boolean?): Pit.Cast
	return function(_origin, direction, length)
		for i, d in Pit.DIRECTIONS do
			if (d - direction).Magnitude < 0.01 then
				local distance = distances[i]
				if distance and distance <= length then
					return { distance = distance, isTerrain = terrain ~= false }
				end
			end
		end
		return nil
	end
end

return function(t: any)
	t.describe("Ballistic arcs", function()
		t.it("an arc lands on its target", function()
			local from = Vector3.new(120, -80, -40)
			local to = Vector3.new(0, 3, 0)
			local velocity, time = Ballistic.velocity(from, to, 16, GRAVITY)
			local x = from.X + velocity.X * time
			local z = from.Z + velocity.Z * time
			t.expect(x).toBeNear(to.X, 0.01)
			t.expect(z).toBeNear(to.Z, 0.01)
			t.expect(Ballistic.heightAt(from.Y, velocity.Y, GRAVITY, time)).toBeNear(to.Y, 0.01)
		end)

		t.it("the arc peaks the asked height over the higher end", function()
			local from = Vector3.new(0, 0, 0)
			local to = Vector3.new(30, 20, 0)
			local velocity = Ballistic.velocity(from, to, 6, GRAVITY)
			local peakTime = velocity.Y / GRAVITY
			t.expect(Ballistic.heightAt(0, velocity.Y, GRAVITY, peakTime)).toBeNear(26, 0.01)
		end)

		t.it("the body is above the target's height the whole way down", function()
			local velocity, time =
				Ballistic.velocity(Vector3.new(0, 0, 0), Vector3.new(10, 20, 0), 6, GRAVITY)
			local near = Ballistic.heightAt(0, velocity.Y, GRAVITY, time - 0.05)
			t.expect(near > 20).toBeTruthy()
		end)
	end)

	t.describe("Water rescue", function()
		local rescue = Config.RESCUE

		t.it("the water catches people before the void kills them", function()
			t.expect(rescue.WATER_SURFACE > Config.ARENA_VOID_DEPTH).toBeTruthy()
			t.expect(rescue.WATER_SURFACE < 0).toBeTruthy()
		end)

		t.it("the splash hurts but does not kill a healthy player", function()
			t.expect(rescue.WATER_DAMAGE > 0).toBeTruthy()
			t.expect(rescue.WATER_DAMAGE < Config.PLAYER_MAX_HEALTH / 2).toBeTruthy()
			t.expect(rescue.WATER_STUN > 0 and rescue.WATER_STUN <= 3).toBeTruthy()
		end)

		t.it("a launch from the water to a far pad is slower than the client allows", function()
			-- The client keeps at most 250 studs per second of any launch; a fall
			-- from farther out than this is simply put back on the pad.
			local from = Vector3.new(210, rescue.WATER_SURFACE - 10, 0)
			local to = Vector3.new(0, 3, 0)
			local velocity = Ballistic.velocity(from, to, rescue.WATER_APEX, GRAVITY)
			t.expect(velocity.Magnitude < 245).toBeTruthy()
		end)
	end)

	t.describe("Pit rescue", function()
		local rescue = Config.RESCUE

		t.it("a wall that blocks the ray is taller than a jump", function()
			local jump = Ballistic.jumpHeight(Config.JUMP_POWER, GRAVITY)
			t.expect(rescue.PIT_CLIMB > jump).toBeTruthy()
		end)

		t.it("walls on all eight sides is a pit; the nearest wall is the way out", function()
			local found =
				Pit.enclosure(Vector3.zero, 36, wallsAt({ 20, 14, 20, 20, 20, 20, 20, 20 }))
			t.expect(found ~= nil).toBeTruthy()
			t.expect((found :: Pit.Enclosure).distance).toBe(14)
			t.expect((found :: Pit.Enclosure).direction).toBe(Pit.DIRECTIONS[2])
		end)

		t.it("one open side means there is a way out", function()
			t.expect(Pit.enclosure(Vector3.zero, 36, wallsAt({ 20, 20, 20, nil, 20, 20, 20, 20 })))
				.toBeNil()
		end)

		t.it("a wall past the look-out distance does not count", function()
			t.expect(Pit.enclosure(Vector3.zero, 36, wallsAt({ 20, 20, 20, 50, 20, 20, 20, 20 })))
				.toBeNil()
		end)

		t.it("scenery that is not terrain is never treated as a pit wall", function()
			t.expect(
				Pit.enclosure(Vector3.zero, 36, wallsAt({ 20, 20, 20, 20, 20, 20, 20, 20 }, false))
			)
				.toBeNil()
		end)

		t.it("the rescue is quick enough to be fair and slow enough to jump out first", function()
			t.expect(rescue.PIT_SECONDS >= 1 and rescue.PIT_SECONDS <= 3).toBeTruthy()
			t.expect(rescue.PIT_MAX_RIM > rescue.PIT_CLIMB).toBeTruthy()
		end)
	end)
end
