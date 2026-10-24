--!strict
-- Minimal synchronous signal for server/client module-to-module events.
-- Handlers run in their own thread so one error can't break the others.

export type Connection = { Disconnect: (self: Connection) -> () }

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { [number]: (T...) -> () } = {}
	local nextId = 0

	local self = {}

	function self.Connect(_: any, handler: (T...) -> ()): Connection
		nextId += 1
		local id = nextId
		handlers[id] = handler
		local connection = {}
		function connection.Disconnect(_: any)
			handlers[id] = nil
		end
		return connection :: any
	end

	function self.Fire(_: any, ...: T...)
		for _, handler in handlers do
			task.spawn(handler, ...)
		end
	end

	return self :: any
end

return Signal
