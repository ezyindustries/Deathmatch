--!strict
-- Minimal assertion helpers for unit tests. Pure Luau, no Roblox dependency.

local assertion = {}

function assertion.equals(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(string.format("%s\n  expected: %s\n  actual:   %s",
			msg or "values differ", tostring(expected), tostring(actual)), 2)
	end
end

function assertion.truthy(value: any, msg: string?)
	if not value then
		error((msg or "expected truthy value") .. "\n  got: " .. tostring(value), 2)
	end
end

function assertion.falsy(value: any, msg: string?)
	if value then
		error((msg or "expected falsy value") .. "\n  got: " .. tostring(value), 2)
	end
end

function assertion.errors(fn: () -> (), substring: string?, msg: string?)
	local ok, err = pcall(fn)
	if ok then
		error((msg or "expected function to error") .. ", but it returned without error", 2)
	end
	if substring and not string.find(tostring(err), substring, 1, true) then
		error(string.format("%s\n  expected error containing: %s\n  got: %s",
			msg or "error substring mismatch", substring, tostring(err)), 2)
	end
end

function assertion.deepEquals(actual: any, expected: any, msg: string?)
	local function eq(a: any, b: any): boolean
		if typeof(a) ~= typeof(b) then return false end
		if typeof(a) ~= "table" then return a == b end
		for k, v in a do if not eq(v, b[k]) then return false end end
		for k, v in b do if not eq(v, a[k]) then return false end end
		return true
	end
	if not eq(actual, expected) then
		error((msg or "tables differ") .. "\n  expected: " .. tostring(expected) .. "\n  actual:   " .. tostring(actual), 2)
	end
end

return assertion
