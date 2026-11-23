--!strict
-- The wand: its block model has the parts the game tints and aims from, it
-- never collides, it sits in the hand pointing forward, and the air canvas
-- maps a stroke and a glyph to the right place in front of the caster.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Audio.Cues)
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)
local CastPoses = require(ReplicatedStorage.Shared.Spells.CastPoses)
local WandAir = require(ReplicatedStorage.Shared.Util.WandAir)

return function(t: any)
	t.describe("Wand", function()
		t.it("is a block model with a tip, a halo and runes", function()
			t.expect(ModelKit.isBlock(Config.WAND.MODEL)).toBeTruthy()
			local wand = ModelKit.get(Config.WAND.MODEL) :: Model
			t.expect(wand ~= nil).toBeTruthy()
			for _, name in { "Tip", "TipGlow", "Rune", "Grip", "Shaft" } do
				t.expect(wand:FindFirstChild(name) ~= nil).toBeTruthy()
			end
		end)

		t.it("is small and never collides", function()
			local wand = ModelKit.clone(Config.WAND.MODEL, "attached") :: Model
			local _, size = wand:GetBoundingBox()
			t.expect(size.Z < 4.5 and size.X < 1 and size.Y < 1).toBeTruthy()
			for _, part in wand:GetDescendants() do
				if part:IsA("BasePart") then
					t.expect(part.CanCollide).toBe(false)
					t.expect(part.CanQuery).toBe(false)
					t.expect(part.Anchored).toBe(false)
				end
			end
			-- The tip is out in front of the grip (forward is -Z).
			local tip = wand:FindFirstChild("Tip") :: BasePart
			t.expect(tip.Position.Z < -2.5).toBeTruthy()
			wand:Destroy()
		end)

		t.it("points down the forearm, tipped forward", function()
			for _, isR15 in { true, false } do
				local grip = WandAir.grip(
					isR15,
					if isR15 then Vector3.new(1, 0.3, 1) else Vector3.new(1, 2, 1)
				)
				t.expect(grip.LookVector.Y < -0.7).toBeTruthy()
				t.expect(grip.LookVector.Z < -0.2).toBeTruthy()
				t.expect(grip.Position.Y <= 0).toBeTruthy()
			end
		end)

		t.it("puts the air canvas in front of the chest", function()
			local root = Vector3.new(10, 5, 20)
			-- Even with the camera looking steeply down, the canvas stays level
			-- and AIR_DISTANCE ahead.
			local look = Vector3.new(0, -0.9, -0.4).Unit
			local frame = WandAir.frame(root, look, Vector3.xAxis, Vector3.yAxis)
			local flat = Vector3.new(frame.Position.X - root.X, 0, frame.Position.Z - root.Z)
			t.expect(flat.Magnitude).toBeNear(Config.WAND.AIR_DISTANCE, 1e-3)
			t.expect(frame.Position.Y).toBeNear(root.Y + Config.WAND.AIR_HEIGHT, 1e-3)
			t.expect(frame.Position.Z < root.Z).toBeTruthy()
		end)

		t.it("maps the on-screen stroke onto the canvas", function()
			local view = Vector2.new(1600, 900)
			local center =
				Vector2.new(view.X * WandAir.SCREEN_CENTER.X, view.Y * WandAir.SCREEN_CENTER.Y)
			local zero = WandAir.fromScreen(center, view)
			t.expect(zero.Magnitude).toBeNear(0, 1e-6)
			-- Half the guide's span above the centre is half the canvas up.
			local up =
				WandAir.fromScreen(center - Vector2.new(0, view.Y * WandAir.SCREEN_SPAN / 2), view)
			t.expect(up.Y).toBeNear(Config.WAND.AIR_SIZE / 2, 1e-3)
			t.expect(up.X).toBeNear(0, 1e-6)
			local right = WandAir.fromScreen(center + Vector2.new(100, 0), view)
			t.expect(right.X > 0).toBeTruthy()
			-- Far off the guide is held to the edge.
			local far = WandAir.fromScreen(Vector2.new(-10000, 10000), view)
			t.expect(far.X).toBeNear(-Config.WAND.AIR_SIZE * 0.75, 1e-3)
			t.expect(far.Y).toBeNear(-Config.WAND.AIR_SIZE * 0.75, 1e-3)
		end)

		t.it("maps glyph points onto the canvas the right way up", function()
			t.expect(WandAir.fromGlyph(Vector2.new(0.5, 0.5)).Magnitude).toBeNear(0, 1e-6)
			local topRight = WandAir.fromGlyph(Vector2.new(1, 0))
			t.expect(topRight.X).toBeNear(Config.WAND.AIR_SIZE / 2, 1e-6)
			t.expect(topRight.Y).toBeNear(Config.WAND.AIR_SIZE / 2, 1e-6)
			local frame = CFrame.new(0, 10, 0)
			local world = WandAir.toWorld(frame, Vector2.new(1, 2))
			t.expect((world - Vector3.new(1, 12, 0)).Magnitude).toBeNear(0, 1e-6)
		end)

		t.it("has its poses and sounds", function()
			t.expect(CastPoses.POSES.WandDraw ~= nil).toBeTruthy()
			t.expect(CastPoses.POSES.WandFlick ~= nil).toBeTruthy()
			t.expect((Cues :: any).wandCharge ~= nil).toBeTruthy()
			t.expect((Cues :: any).wandAbsorb ~= nil).toBeTruthy()
		end)

		t.it("has sane tunables", function()
			local w = Config.WAND
			t.expect(w.AIR_DISTANCE > 2 and w.AIR_DISTANCE < 12).toBeTruthy()
			t.expect(w.AIR_SIZE > 2 and w.AIR_SIZE < 12).toBeTruthy()
			t.expect(w.TRACE_SECONDS > 0 and w.TRACE_SECONDS <= 1).toBeTruthy()
			t.expect(w.TILT >= 0 and w.TILT <= 60).toBeTruthy()
			t.expect(w.DRAW_STATE_RATE > 0 and w.DRAW_STATE_RATE < 1).toBeTruthy()
			-- The magic circle frames the drawing without swallowing the scene.
			t.expect(w.CIRCLE_RADIUS > w.AIR_SIZE / 2 and w.CIRCLE_RADIUS < w.AIR_SIZE).toBeTruthy()
			-- A live stroke: batches the server accepts at the rate they're sent.
			t.expect(w.STROKE_SEND_RATE >= w.STROKE_RATE).toBeTruthy()
			t.expect(w.STROKE_BATCH >= 8 and w.STROKE_BATCH <= 64).toBeTruthy()
			t.expect(w.STROKE_MAX_POINTS >= w.STROKE_BATCH).toBeTruthy()
			t.expect(w.RELAY_RANGE > 50).toBeTruthy()
		end)

		t.it("puts the first-person wand's tip under the pen", function()
			local grip = Config.WAND.VIEW_GRIP
			local length = Config.WAND.VIEW_LENGTH
			-- The hand moves VIEW_HAND_FOLLOW of the way to the pen's ray, so it is
			-- at most (1 - follow) * |grip| from it: within reach, any pen pixel works.
			local follow = Config.WAND.VIEW_HAND_FOLLOW
			t.expect(follow >= 0 and follow < 1).toBeTruthy()
			t.expect((1 - follow) * grip.Magnitude < length).toBeTruthy()
			for _, dir in
				{ Vector3.new(0, 0, -1), Vector3.new(-0.6, 0.4, -1), Vector3.new(0.5, -0.5, -1) }
			do
				local hand = WandAir.viewHand(Vector3.zero, dir, grip, follow)
				t.expect(hand.Z).toBeNear(grip.Z, 1e-4)
				local tip = WandAir.viewTip(Vector3.zero, dir, hand, length) :: Vector3
				t.expect(tip ~= nil).toBeTruthy()
				t.expect((tip - hand).Magnitude).toBeNear(length, 1e-4)
				t.expect(tip.Unit:Dot(dir.Unit)).toBeNear(1, 1e-4)
			end
			-- Out of reach: a short wand far from the eye.
			t.expect(WandAir.viewTip(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(5, 0, 0), 1))
				.toBeNil()
			t.expect(Config.WAND.VIEW_SCALE > 0 and Config.WAND.VIEW_SCALE <= 1).toBeTruthy()
			t.expect(Config.WAND.VIEW_RAISE > 0 and Config.WAND.VIEW_RAISE < 1).toBeTruthy()
		end)

		t.it("stands the circle upright, facing where the drawer looks", function()
			local frame = WandAir.facing(Vector3.zero, Vector3.new(0, -0.5, -2))
			t.expect((frame.LookVector - Vector3.new(0, 0, -1)).Magnitude).toBeNear(0, 1e-6)
			t.expect((frame.UpVector - Vector3.yAxis).Magnitude).toBeNear(0, 1e-6)
			t.expect((frame.RightVector - Vector3.xAxis).Magnitude).toBeNear(0, 1e-6)
			local ahead = Vector3.new(0, Config.WAND.AIR_HEIGHT, -Config.WAND.AIR_DISTANCE)
			t.expect((frame.Position - ahead).Magnitude).toBeNear(0, 1e-6)
			-- Looking straight down still gives an upright canvas.
			local down = WandAir.facing(Vector3.zero, Vector3.new(0, -1, 0))
			t.expect((down.UpVector - Vector3.yAxis).Magnitude).toBeNear(0, 1e-6)
		end)

		t.it("only relays clean facing and stroke data", function()
			t.expect(WandAir.cleanLook(Vector3.new(3, 9, 4)) :: any).toBeTruthy()
			local look = WandAir.cleanLook(Vector3.new(3, 9, 4)) :: Vector3
			t.expect(look.Magnitude).toBeNear(1, 1e-6)
			t.expect(look.Y).toBeNear(0, 1e-9)
			t.expect(WandAir.cleanLook("north")).toBe(nil)
			t.expect(WandAir.cleanLook(Vector3.new(0, 1, 0))).toBe(nil)
			t.expect(WandAir.cleanLook(Vector3.new(0 / 0, 0, 1))).toBe(nil)
			t.expect(WandAir.cleanLook(Vector3.new(math.huge, 0, 1))).toBe(nil)

			local ok = WandAir.cleanPoints({ Vector2.new(1, -2), Vector2.zero }, 24)
			t.expect(ok ~= nil and #ok == 2).toBeTruthy()
			t.expect(WandAir.cleanPoints({}, 24)).toBe(nil)
			t.expect(WandAir.cleanPoints("points", 24)).toBe(nil)
			t.expect(WandAir.cleanPoints({ Vector2.zero, Vector2.zero, Vector2.zero }, 2)).toBe(nil)
			t.expect(WandAir.cleanPoints({ Vector3.zero }, 24)).toBe(nil)
			t.expect(WandAir.cleanPoints({ Vector2.new(0 / 0, 0) }, 24)).toBe(nil)
			t.expect(WandAir.cleanPoints({ Vector2.new(Config.WAND.AIR_SIZE * 2, 0) }, 24))
				.toBe(nil)
		end)
	end)
end
