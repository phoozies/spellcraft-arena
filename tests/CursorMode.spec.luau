--!strict
-- The first-person cursor key: a tap keeps the cursor out for one click, a hold
-- only while the key is down, and Alt-Tab never leaves it out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CursorMode = require(ReplicatedStorage.Shared.Util.CursorMode)

local TAP = Config.CURSOR.TAP_SECONDS

return function(t: any)
	t.describe("CursorMode", function()
		t.it("keeps the cursor out after a tap, until another tap", function()
			local state = CursorMode.new()
			t.expect(CursorMode.isFree(state)).toBe(false)
			CursorMode.press(state, 0)
			CursorMode.release(state, TAP / 2, TAP)
			t.expect(CursorMode.isFree(state)).toBe(true)
			CursorMode.press(state, 1)
			CursorMode.release(state, 1 + TAP / 2, TAP)
			t.expect(CursorMode.isFree(state)).toBe(false)
		end)

		t.it("ends a tapped cursor on the next click", function()
			local state = CursorMode.new()
			CursorMode.press(state, 0)
			CursorMode.release(state, TAP / 2, TAP)
			CursorMode.click(state)
			t.expect(CursorMode.isFree(state)).toBe(false)
		end)

		t.it("frees the cursor only while the key is held", function()
			local state = CursorMode.new()
			CursorMode.press(state, 0)
			t.expect(CursorMode.isFree(state)).toBe(true)
			CursorMode.release(state, TAP * 2, TAP)
			t.expect(CursorMode.isFree(state)).toBe(false)
		end)

		t.it("keeps a held cursor out through a click, then re-locks on release", function()
			local state = CursorMode.new()
			CursorMode.press(state, 0)
			CursorMode.click(state)
			t.expect(CursorMode.isFree(state)).toBe(true)
			CursorMode.release(state, TAP / 2, TAP)
			t.expect(CursorMode.isFree(state)).toBe(false)
		end)

		t.it("ignores a key press cut off by losing focus", function()
			local state = CursorMode.new()
			CursorMode.press(state, 0)
			CursorMode.cancel(state)
			t.expect(CursorMode.isFree(state)).toBe(false)
			CursorMode.release(state, TAP / 2, TAP)
			t.expect(CursorMode.isFree(state)).toBe(false)
		end)

		t.it("gives way when a window takes over the mouse", function()
			local state = CursorMode.new()
			CursorMode.press(state, 0)
			CursorMode.release(state, TAP / 2, TAP)
			CursorMode.clear(state)
			t.expect(CursorMode.isFree(state)).toBe(false)
		end)
	end)
end
