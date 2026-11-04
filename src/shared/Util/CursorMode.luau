--!strict
-- The rules of the first-person cursor key (CursorController reads the keyboard
-- and the clock). Pure logic, so tests can check it:
--   tap the key      the cursor stays out until the next click or another tap
--   hold the key     the cursor is out only while the key is down
--   cancel           the key press never finishes (the window lost focus)
--   clear            something else took over the mouse (a window, the canvas)

local CursorMode = {}

export type State = {
	toggled: boolean, -- out after a tap
	pressedAt: number?, -- the key is down, since this time
	clicked: boolean, -- a click landed during this key press
}

function CursorMode.new(): State
	return { toggled = false, pressedAt = nil, clicked = false }
end

function CursorMode.press(state: State, now: number)
	state.pressedAt = now
	state.clicked = false
end

function CursorMode.release(state: State, now: number, tapSeconds: number)
	local pressedAt = state.pressedAt
	if not pressedAt then
		return
	end
	state.pressedAt = nil
	local tapped = now - pressedAt < tapSeconds and not state.clicked
	state.toggled = tapped and not state.toggled
end

function CursorMode.click(state: State)
	state.toggled = false
	state.clicked = state.pressedAt ~= nil
end

function CursorMode.cancel(state: State)
	state.pressedAt = nil
end

function CursorMode.clear(state: State)
	state.toggled = false
end

function CursorMode.isFree(state: State): boolean
	return state.toggled or state.pressedAt ~= nil
end

return CursorMode
