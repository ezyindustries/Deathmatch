--!strict
-- Lune-based unit test runner. Run via: `lune run tests/runner.luau`
-- Discovers all *_test.luau files under tests/, runs them, reports pass/fail.

local fs = require("@lune/fs")
local process = require("@lune/process")

type TestResult = { name: string, passed: boolean, error: string? }

local results: { TestResult } = {}
local startedAt = os.clock()

-- Each test file exposes a table { [name: string]: function }. Runner invokes
-- each function in pcall and records result.

local function discoverTests(dir: string): { string }
	local found: { string } = {}
	if not fs.isDir(dir) then return found end
	-- Integration tests return Luau code strings to ship to Studio via MCP
	-- execute_luau — they are NOT runnable under Lune, so skip the dir.
	if string.match(dir, "/integration$") or string.match(dir, "^integration$") then
		return found
	end
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			for _, sub in discoverTests(full) do
				table.insert(found, sub)
			end
		elseif string.match(entry, "_test%.luau$") then
			table.insert(found, full)
		end
	end
	return found
end

local function runFile(path: string)
	-- runner.luau is in tests/, path is like "tests/unit/uitheme_test.luau".
	-- Strip "tests/" prefix so require resolves relative to this file.
	local relPath = string.gsub(path, "^tests/", "./")
	-- Lune require needs path without extension
	relPath = string.gsub(relPath, "%.luau$", "")
	local ok, mod = pcall(require, relPath)
	if not ok then
		table.insert(results, {
			name = path .. " [LOAD]",
			passed = false,
			error = tostring(mod),
		})
		return
	end
	if typeof(mod) ~= "table" then
		table.insert(results, {
			name = path .. " [SHAPE]",
			passed = false,
			error = "Test file must return a table of { [name] = function }; got " .. typeof(mod),
		})
		return
	end
	for name, fn in mod do
		if typeof(fn) == "function" then
			local ok2, err = pcall(fn)
			table.insert(results, {
				name = path .. " :: " .. name,
				passed = ok2,
				error = ok2 and nil or tostring(err),
			})
		end
	end
end

local files = discoverTests("tests")
for _, f in files do
	runFile(f)
end

-- Report
local passCount, failCount = 0, 0
for _, r in results do
	if r.passed then
		passCount += 1
	else
		failCount += 1
	end
end

print(string.format("\n========================================"))
print(string.format("Test results: %d passed, %d failed (%d total)", passCount, failCount, #results))
print(string.format("Elapsed: %.3fs", os.clock() - startedAt))
print("========================================\n")

if failCount > 0 then
	print("FAILURES:")
	for _, r in results do
		if not r.passed then
			print(string.format("  ✗ %s", r.name))
			if r.error then
				print(string.format("      %s", r.error))
			end
		end
	end
	process.exit(1)
end

for _, r in results do
	if r.passed then
		print(string.format("  ✓ %s", r.name))
	end
end
