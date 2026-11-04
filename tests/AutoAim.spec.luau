--!strict
-- The bolts' quiet aim assist (shared/Util/AutoAim): who gets locked, how far a
-- bolt is led, and how far a locked bolt may turn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoAim = require(ReplicatedStorage.Shared.Util.AutoAim)
local Config = require(ReplicatedStorage.Shared.Config)

local ORIGIN = Vector3.zero
local FORWARD = Vector3.new(0, 0, -1)

-- A candidate `distance` studs away, `degrees` to the right of the crosshair.
local function at(distance: number, degrees: number, key: string): AutoAim.Candidate
	local a = math.rad(degrees)
	return { position = Vector3.new(math.sin(a), 0, -math.cos(a)) * distance, key = key }
end

return function(t)
	t.describe("Auto-aim target", function()
		t.it("locks the opponent under the crosshair", function()
			local pick = AutoAim.pick(ORIGIN, FORWARD, { at(60, 1, "A") }, { range = 200 })
			t.expect(pick and pick.key).toBe("A")
		end)

		t.it("prefers the opponent closest to the sight, even a further one", function()
			local pick = AutoAim.pick(
				ORIGIN,
				FORWARD,
				{ at(90, 2, "far"), at(40, 4, "near"), at(140, 0, "dead centre") },
				{ range = 200 }
			)
			t.expect(pick and pick.key).toBe("dead centre")
		end)

		t.it("distance settles a tie on the sight", function()
			local pick = AutoAim.pick(
				ORIGIN,
				FORWARD,
				{ at(120, 3, "far"), at(40, 3, "near") },
				{ range = 200 }
			)
			t.expect(pick and pick.key).toBe("near")
		end)

		t.it("locks nobody when the assist is off", function()
			Config.AUTO_AIM.ASSIST = false
			local pick = AutoAim.pick(ORIGIN, FORWARD, { at(60, 0, "A") }, { range = 200 })
			Config.AUTO_AIM.ASSIST = true
			t.expect(pick).toBeNil()
		end)

		t.it(
			"a slightly further opponent dead centre beats a near one at the cone's edge",
			function()
				local edge = Config.AUTO_AIM.CONE - 0.5
				local pick = AutoAim.pick(
					ORIGIN,
					FORWARD,
					{ at(40, edge, "edge"), at(46, 0, "centre") },
					{ range = 200 }
				)
				t.expect(pick and pick.key).toBe("centre")
			end
		)

		t.it("ignores opponents outside the cone, behind you, or out of range", function()
			local pick = AutoAim.pick(ORIGIN, FORWARD, {
				at(60, Config.AUTO_AIM.CONE + 6, "side"),
				at(30, 180, "behind"),
				at(260, 0, "far"),
			}, { range = 200 })
			t.expect(pick).toBeNil()
		end)

		t.it("the cone is wider up close", function()
			t.expect(AutoAim.cone(0) > AutoAim.cone(100)).toBeTruthy()
			local pick = AutoAim.pick(ORIGIN, FORWARD, { at(5, 20, "close") }, { range = 200 })
			t.expect(pick and pick.key).toBe("close")
		end)

		t.it("skips a nearer opponent hidden behind a wall", function()
			local pick = AutoAim.pick(ORIGIN, FORWARD, { at(30, 0, "hidden"), at(70, 2, "open") }, {
				range = 200,
				visible = function(candidate)
					return candidate.key ~= "hidden"
				end,
			})
			t.expect(pick and pick.key).toBe("open")
		end)

		t.it("only checks line of sight until a visible target is found", function()
			local checks = 0
			AutoAim.pick(ORIGIN, FORWARD, { at(30, 0, "a"), at(50, 1, "b"), at(70, 2, "c") }, {
				range = 200,
				visible = function()
					checks += 1
					return true
				end,
			})
			t.expect(checks).toBe(1)
		end)
	end)

	t.describe("Auto-aim lead and tracking", function()
		t.it("aims ahead of a running target so the bolt meets it", function()
			local position = Vector3.new(0, 0, -100)
			local velocity = Vector3.new(24, 0, 0)
			local speed = 120
			local aim = AutoAim.lead(ORIGIN, position, velocity, speed)
			t.expect(aim.X > 0).toBeTruthy()
			-- With full lead the bolt would arrive exactly; LEAD keeps it a bit short.
			local time = (aim - ORIGIN).Magnitude / speed
			local target = position + velocity * time
			t.expect((target - aim).Magnitude < 24 * time).toBeTruthy()
		end)

		t.it("does not lead instant spells or still targets", function()
			local position = Vector3.new(10, 0, -50)
			t.expect(AutoAim.lead(ORIGIN, position, Vector3.new(20, 0, 0), nil)).toBe(position)
			t.expect(AutoAim.lead(ORIGIN, position, Vector3.zero, 100)).toBe(position)
		end)

		t.it("barely leads a jump", function()
			local position = Vector3.new(0, 0, -60)
			local aim = AutoAim.lead(ORIGIN, position, Vector3.new(0, 50, 0), 120)
			t.expect(aim.Y < 50 * 0.5 * Config.AUTO_AIM.LEAD_VERTICAL + 1).toBeTruthy()
		end)

		-- Flies a Fireball-speed bolt at a player walking sideways, the way the
		-- server does: led at launch, then turning at `turnRate` degrees a second
		-- until the target is too far off its heading. True if it connects.
		local function connects(distance: number, turnRate: number, reverses: boolean): boolean
			local walk = Vector3.new(Config.WALK_SPEED, 0, 0)
			local speed = 95 * Config.PROJECTILE_SPEED_SCALE
			local target = Vector3.new(0, 0, -distance)
			local position = ORIGIN
			local direction = (AutoAim.lead(ORIGIN, target, walk, speed) - ORIGIN).Unit
			local velocity = if reverses then -walk else walk
			local dt = 1 / 60
			for _ = 1, 300 do
				local desired = target - position
				if
					AutoAim.angleBetween(direction, desired)
					> math.rad(Config.AUTO_AIM.HOMING_GIVE_UP)
				then
					return false
				end
				direction = AutoAim.steer(direction, desired.Unit, math.rad(turnRate) * dt)
				position += direction * speed * dt
				target += velocity * dt
				if (target - position).Magnitude < 4 then
					return true
				end
			end
			return false
		end

		t.it("a slow bolt tracks a player walking steadily, at any range", function()
			for _, distance in { 30, 60, 100 } do
				t.expect(connects(distance, Config.AUTO_AIM.HOMING, false)).toBe(true)
			end
		end)

		t.it("needs the tracking: without it a far walker gets away", function()
			t.expect(connects(100, 0, false)).toBe(false)
		end)

		t.it("a hard sidestep up close still dodges", function()
			t.expect(connects(30, Config.AUTO_AIM.HOMING, true)).toBe(false)
		end)

		t.it("turns a bolt by at most the allowed angle", function()
			local turned = AutoAim.steer(FORWARD, Vector3.new(1, 0, 0), math.rad(10))
			t.expect(math.deg(AutoAim.angleBetween(FORWARD, turned))).toBeNear(10, 0.01)
			local small = AutoAim.steer(FORWARD, Vector3.new(0.05, 0, -1).Unit, math.rad(10))
			t.expect(AutoAim.angleBetween(small, Vector3.new(0.05, 0, -1))).toBeNear(0, 1e-4)
		end)
	end)
end
