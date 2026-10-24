--!strict
-- Minimal dependency-free test runner (TestEZ-style describe/it/expect).
-- Run from the Studio command bar or the MCP, in Edit or Server mode:
--   require(game.ServerScriptService.Tests.Runner)()
-- Returns (passed, failed) and prints a report.

export type Expect = {
	toBe: (expected: any) -> (),
	toBeNil: () -> (),
	toBeTruthy: () -> (),
	toBeNear: (expected: number, tolerance: number) -> (),
}

export type TestApi = {
	describe: (name: string, fn: () -> ()) -> (),
	it: (name: string, fn: () -> ()) -> (),
	expect: (value: any) -> Expect,
}

local function expect(value: any): Expect
	return {
		toBe = function(expected: any)
			if value ~= expected then
				error(`expected {tostring(expected)}, got {tostring(value)}`, 2)
			end
		end,
		toBeNil = function()
			if value ~= nil then
				error(`expected nil, got {tostring(value)}`, 2)
			end
		end,
		toBeTruthy = function()
			if not value then
				error(`expected truthy, got {tostring(value)}`, 2)
			end
		end,
		toBeNear = function(expected: number, tolerance: number)
			if math.abs(value - expected) > tolerance then
				error(`expected {expected} ± {tolerance}, got {value}`, 2)
			end
		end,
	}
end

return function(): (number, number)
	local passed, failed = 0, 0
	local prefix = ""
	local failures = {}
	local api: TestApi = {
		describe = function(name, fn)
			local previous = prefix
			prefix = prefix .. name .. " › "
			fn()
			prefix = previous
		end,
		it = function(name, fn)
			local ok, err = pcall(fn)
			if ok then
				passed += 1
			else
				failed += 1
				table.insert(failures, `✗ {prefix}{name}\n    {err}`)
			end
		end,
		expect = expect,
	}
	for _, module in script.Parent:GetChildren() do
		if module:IsA("ModuleScript") and string.match(module.Name, "%.spec$") then
			local ok, spec = pcall(require, module)
			if ok and typeof(spec) == "function" then
				spec(api)
			else
				failed += 1
				table.insert(failures, `✗ {module.Name} failed to load: {spec}`)
			end
		end
	end
	for _, line in failures do
		warn(line)
	end
	print(`[Tests] {passed} passed, {failed} failed`)
	return passed, failed
end
