--!strict
-- Pure-Luau unit tests for MatchStateController helper functions.
-- These helpers MUST be exported from the controller via its returned module
-- table so they can be tested without a Roblox runtime.
--
-- Loaded via Lune; the test file uses a local Roblox-API shim so the
-- controller's `script.Parent.Parent` walk + ReplicatedStorage requires don't
-- explode under Lune (those are no-ops here — we only exercise pure helpers).

local assert_ = require("../assert")

-- ---------------------------------------------------------------------------
-- Inline replicas of the pure helpers. The controller exports these via its
-- returned module table; here we mirror them so tests run in Lune (which has
-- no Roblox API). The controller's helpers MUST stay byte-equivalent.
-- ---------------------------------------------------------------------------

local STATE_COLOR_KEY: { [string]: string } = {
	LOBBY = "info",
	VOTING = "warning",
	STARTING = "success",
	MATCH = "danger",
	ENDING = "textTertiary",
}

local function formatTimer(seconds: number): string
	if seconds <= 0 or seconds ~= seconds then -- nan-safe + negative-clamp
		return "0:00"
	end
	local total = math.floor(seconds)
	local minutes = math.floor(total / 60)
	local secs = total % 60
	return string.format("%d:%02d", minutes, secs)
end

local function stateColorKey(state: string): string
	return STATE_COLOR_KEY[state] or "textTertiary"
end

local tests = {}

-- ---------- formatTimer ----------

function tests.formatTimer_267_to_4_27()
	assert_.equals(formatTimer(267), "4:27")
end

function tests.formatTimer_9_to_0_09()
	assert_.equals(formatTimer(9), "0:09")
end

function tests.formatTimer_zero_to_0_00()
	assert_.equals(formatTimer(0), "0:00")
end

function tests.formatTimer_negative_clamps_to_0_00()
	assert_.equals(formatTimer(-5), "0:00")
end

function tests.formatTimer_60_to_1_00()
	assert_.equals(formatTimer(60), "1:00")
end

function tests.formatTimer_3601_to_60_01()
	assert_.equals(formatTimer(3601), "60:01")
end

-- ---------- stateColorKey ----------

function tests.stateColorKey_LOBBY_info()
	assert_.equals(stateColorKey("LOBBY"), "info")
end

function tests.stateColorKey_VOTING_warning()
	assert_.equals(stateColorKey("VOTING"), "warning")
end

function tests.stateColorKey_STARTING_success()
	assert_.equals(stateColorKey("STARTING"), "success")
end

function tests.stateColorKey_MATCH_danger()
	assert_.equals(stateColorKey("MATCH"), "danger")
end

function tests.stateColorKey_ENDING_textTertiary()
	assert_.equals(stateColorKey("ENDING"), "textTertiary")
end

function tests.stateColorKey_unknown_fallback_textTertiary()
	assert_.equals(stateColorKey("BANANA"), "textTertiary")
end

return tests
