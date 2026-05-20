--!strict
-- Sample unit test — proves Lune test runner is wired. Use this pattern only
-- for PURE Luau (no Roblox APIs like Color3 / Instance / game:GetService).
-- For UI / Roblox-API logic, use Studio MCP integration tests instead.

local assert_ = require("../assert")

local tests = {}

function tests.assert_equals_works()
	assert_.equals(2 + 2, 4)
end

function tests.assert_truthy_works()
	assert_.truthy(true)
	assert_.truthy("non-empty string")
	assert_.truthy(1)
end

function tests.assert_errors_catches_runtime_error()
	assert_.errors(function()
		error("intentional failure")
	end, "intentional failure")
end

function tests.string_helpers()
	-- Just sanity-checking Luau stdlib
	assert_.equals(string.upper("kill"), "KILL")
	assert_.equals(string.format("%d kills", 5), "5 kills")
end

return tests
