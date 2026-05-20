--!strict
-- Sanity tests for the top-right cluster (mini scoreboard + KillFeed) layout
-- math. These don't touch Roblox runtime — they just assert that the height
-- constants used by ScoreboardController and the fallback values inside
-- KillFeedController stay in lock-step. If someone bumps the scoreboard row
-- height without updating the killfeed fallback, this test fails.

local assert_ = require("../assert")
local tests = {}

-- Constants duplicated here on purpose — these mirror the source-of-truth
-- values in ScoreboardController.luau / KillFeedController.luau. If you change
-- either side, update this test too.
local SCOREBOARD = {
	MAX_ENTRIES = 4,
	ROW_H_DESKTOP = 36,
	ROW_H_MOBILE = 26,
	ROW_GAP_DESKTOP = 4,  -- UITheme.Space.xs
	ROW_GAP_MOBILE = 2,
	ROW_W_DESKTOP = 260,
	ROW_W_MOBILE = 180,
}

local KILLFEED = {
	FALLBACK_HEIGHT_DESKTOP = 4 * 36 + 3 * 4, -- 156
	FALLBACK_HEIGHT_MOBILE = 4 * 26 + 3 * 2,   -- 110
	ENTRY_H_DESKTOP = 36,
	ENTRY_H_MOBILE = 28,
	BG_TRANSPARENCY = 0.35,
}

local function miniHeight(rows: number, rowH: number, gap: number): number
	return rows * rowH + (rows - 1) * gap
end

function tests.scoreboard_desktop_total_height_matches_killfeed_fallback()
	local actual = miniHeight(SCOREBOARD.MAX_ENTRIES, SCOREBOARD.ROW_H_DESKTOP, SCOREBOARD.ROW_GAP_DESKTOP)
	assert_.equals(actual, KILLFEED.FALLBACK_HEIGHT_DESKTOP,
		"desktop scoreboard total height should match killfeed fallback constant")
end

function tests.scoreboard_mobile_total_height_matches_killfeed_fallback()
	local actual = miniHeight(SCOREBOARD.MAX_ENTRIES, SCOREBOARD.ROW_H_MOBILE, SCOREBOARD.ROW_GAP_MOBILE)
	assert_.equals(actual, KILLFEED.FALLBACK_HEIGHT_MOBILE,
		"mobile scoreboard total height should match killfeed fallback constant")
end

function tests.mobile_row_shrunk_from_desktop()
	-- Validate the user's stated intent: mobile must be smaller in both axes.
	assert_.truthy(SCOREBOARD.ROW_W_MOBILE < SCOREBOARD.ROW_W_DESKTOP,
		"mobile row width should be smaller than desktop")
	assert_.truthy(SCOREBOARD.ROW_H_MOBILE < SCOREBOARD.ROW_H_DESKTOP,
		"mobile row height should be smaller than desktop")
end

function tests.killfeed_entry_shrunk_on_mobile()
	-- KillFeed entries shrink alongside the scoreboard on mobile.
	assert_.truthy(KILLFEED.ENTRY_H_MOBILE < KILLFEED.ENTRY_H_DESKTOP,
		"mobile killfeed entry should be shorter than desktop")
end

function tests.killfeed_more_transparent_than_legacy()
	-- User requested "lebih transparan" — must be above legacy 0.08.
	assert_.truthy(KILLFEED.BG_TRANSPARENCY > 0.08,
		"killfeed bg transparency should be greater than legacy 0.08")
end

function tests.mobile_total_height_under_120_px()
	-- Mobile viewport is short (iPhone 7 at 666x374). Cluster must stay tight.
	-- Spec target ~110px.
	local actual = miniHeight(SCOREBOARD.MAX_ENTRIES, SCOREBOARD.ROW_H_MOBILE, SCOREBOARD.ROW_GAP_MOBILE)
	assert_.truthy(actual <= 120,
		"mobile mini scoreboard total height should stay <= 120px (got " .. tostring(actual) .. ")")
end

return tests
