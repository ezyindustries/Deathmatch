--!strict
-- Tier 1 unit test for AnnouncementController._streakTierKey — verifies the
-- streak-count → UITheme.Color-key mapping (pure function, no Roblox APIs).
--
-- The controller exports the mapping function as a string-keyed resolver
-- (returns "success"/"warning"/"danger"/"accentElectric"/"accentPrimary")
-- specifically so it's Lune-testable here. The actual Color3 lookup happens
-- inside the controller via UITheme.Color[key].

local assert_ = require("../assert")

-- We can't `require` the controller directly because it touches Roblox APIs
-- (Players.LocalPlayer, Instance.new, etc.) at top level. Instead, we parse
-- the source file and extract the pure mapping function by re-implementing
-- a tiny loader that strips Roblox-dependent top-level code.
--
-- Strategy: read source, locate `local function streakTierKey`, copy the
-- function body, exec it in an isolated env, then test. This keeps the
-- controller's GREEN state honest — if the function is renamed/moved, the
-- test breaks loudly.

local fs = require("@lune/fs")

local SOURCE_PATH = "src/client/Controllers/AnnouncementController.luau"

local function loadStreakTierKey(): (number) -> string
	local src = fs.readFile(SOURCE_PATH)
	-- Extract: from `local function streakTierKey` until matching `end` at
	-- column 1 (function block end). Simpler: capture the multi-line block
	-- delimited by a sentinel comment we expect the controller to keep.
	local body = string.match(src, "%-%-%s*TIER_KEY_FN_BEGIN(.-)%-%-%s*TIER_KEY_FN_END")
	if not body then
		error("AnnouncementController must contain `-- TIER_KEY_FN_BEGIN` / `-- TIER_KEY_FN_END` markers around the pure streakTierKey() function for Lune testability", 2)
	end
	-- The body declares `local function streakTierKey(...) ... end` plus the
	-- LOCAL_TIER_COLORS table. We wrap it so loadstring exposes the fn.
	local wrapped = body .. "\nreturn streakTierKey"
	local chunk, err = loadstring(wrapped)
	if not chunk then
		error("failed to compile streakTierKey block: " .. tostring(err), 2)
	end
	local ok, fn = pcall(chunk)
	if not ok or typeof(fn) ~= "function" then
		error("streakTierKey block must return the function; got " .. tostring(fn), 2)
	end
	return fn
end

local tests = {}

function tests.streak_1_returns_success_or_default()
	-- Streak of 1 means "FIRST KILL" — not really a streak tier yet, the
	-- spec only covers 2+. We expect the function to still return a string
	-- (default to success for the entry-level case).
	local fn = loadStreakTierKey()
	local result = fn(1)
	assert_.truthy(typeof(result) == "string", "expected string key for streak=1, got " .. typeof(result))
end

function tests.streak_2_maps_to_success()
	local fn = loadStreakTierKey()
	assert_.equals(fn(2), "success", "streak=2 (DOUBLE) should map to success (green)")
end

function tests.streak_4_maps_to_success()
	local fn = loadStreakTierKey()
	assert_.equals(fn(4), "success", "streak=4 (QUADRA) should still be success tier")
end

function tests.streak_5_maps_to_warning()
	local fn = loadStreakTierKey()
	assert_.equals(fn(5), "warning", "streak=5 (PENTA) should map to warning (amber)")
end

function tests.streak_6_maps_to_warning()
	local fn = loadStreakTierKey()
	assert_.equals(fn(6), "warning", "streak=6 (DOMINATOR threshold) should still be warning tier")
end

function tests.streak_7_maps_to_danger()
	local fn = loadStreakTierKey()
	assert_.equals(fn(7), "danger", "streak=7 should map to danger (red)")
end

function tests.streak_9_maps_to_danger()
	local fn = loadStreakTierKey()
	assert_.equals(fn(9), "danger", "streak=9 should still be danger tier")
end

function tests.streak_10_maps_to_accentElectric()
	local fn = loadStreakTierKey()
	assert_.equals(fn(10), "accentElectric", "streak=10 should map to accentElectric (purple)")
end

function tests.streak_14_maps_to_accentElectric()
	local fn = loadStreakTierKey()
	assert_.equals(fn(14), "accentElectric", "streak=14 should still be accentElectric tier")
end

function tests.streak_15_maps_to_accentPrimary()
	local fn = loadStreakTierKey()
	assert_.equals(fn(15), "accentPrimary", "streak=15 should map to accentPrimary (cyan)")
end

function tests.streak_99_maps_to_accentPrimary()
	local fn = loadStreakTierKey()
	assert_.equals(fn(99), "accentPrimary", "streak=99 (any huge value) should clamp to accentPrimary")
end

return tests
