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
		end)
	end)
end
