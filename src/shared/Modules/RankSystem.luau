--!strict
-- Rank progression for Deathmatch.
-- 7 tiers × 3 sub-levels = 21 total levels. Per-kill = 20 XP.
-- Per-level XP requirement scales with tier:
--   Bronze   = 1000 XP/level
--   Silver   = 1500 XP/level
--   Gold     = 2000 XP/level
--   Platinum = 2500 XP/level
--   Diamond  = 3000 XP/level
--   Eagle    = 3500 XP/level
--   Immortal = 4000 XP/level
-- The cost of advancing FROM level L is the cost of L's current tier. So
-- Bronze 3 → Silver 1 still costs 1000 (player is still Bronze when leveling).

local RankSystem = {}

RankSystem.XP_PER_KILL = 20
RankSystem.MAX_LEVEL = 21 -- 7 tiers × 3 sub-levels

local TIER_NAMES = { "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Eagle", "Immortal" }
local TIER_COLORS = {
	Bronze   = Color3.fromRGB(180, 110, 60),    -- bronzy orange-brown
	Silver   = Color3.fromRGB(170, 175, 185),   -- gray (abu-abu)
	Gold     = Color3.fromRGB(245, 200, 80),    -- yellow (kuning)
	Platinum = Color3.fromRGB(80, 140, 235),    -- blue (biru)
	Diamond  = Color3.fromRGB(170, 95, 230),    -- purple (ungu)
	Eagle    = Color3.fromRGB(85, 200, 110),    -- green (hijau)
	Immortal = Color3.fromRGB(230, 70, 70),     -- red (merah)
}

-- Per-tier XP cost to advance ONE level (within or out of the tier).
local TIER_LEVEL_COST = { 1000, 1500, 2000, 2500, 3000, 3500, 4000 }

export type RankInfo = {
	level: number,        -- 1-21
	tier: string,         -- "Bronze" | "Silver" | ... | "Immortal"
	sub: number,          -- 1, 2, or 3
	displayName: string,  -- e.g., "Bronze 1", "Immortal 3"
	short: string,        -- e.g., "B1", "S2", "I3"
	color: Color3,        -- tier accent color
}

local function tierIdxForLevel(level: number): number
	return math.floor((level - 1) / 3) + 1
end

-- Cost to advance FROM `level` to `level+1`. Uses the current level's tier.
local function costFromLevel(level: number): number
	local idx = math.clamp(tierIdxForLevel(level), 1, #TIER_LEVEL_COST)
	return TIER_LEVEL_COST[idx]
end

-- Precompute cumulative XP required to REACH each level (lookup table).
-- CUMULATIVE_XP[L] = total XP needed to be at exactly level L.
local CUMULATIVE_XP: { number } = { 0 } -- level 1 starts at 0 XP
for L = 2, RankSystem.MAX_LEVEL do
	CUMULATIVE_XP[L] = CUMULATIVE_XP[L - 1] + costFromLevel(L - 1)
end

function RankSystem.LevelFromXp(xp: number): number
	if xp < 0 then xp = 0 end
	-- Linear search from top (max 21 iterations — fine for runtime cost)
	for L = RankSystem.MAX_LEVEL, 1, -1 do
		if xp >= CUMULATIVE_XP[L] then return L end
	end
	return 1
end

-- Total XP needed to be at exactly `level`. Used by IMMORTAL redeem grant.
function RankSystem.XpForLevel(level: number): number
	return CUMULATIVE_XP[math.clamp(level, 1, RankSystem.MAX_LEVEL)]
end

function RankSystem.RankFromLevel(level: number): RankInfo
	level = math.clamp(level, 1, RankSystem.MAX_LEVEL)
	local zeroBased = level - 1
	local tierIdx = math.floor(zeroBased / 3) + 1
	local subIdx = (zeroBased % 3) + 1
	local tier = TIER_NAMES[tierIdx]
	return {
		level = level,
		tier = tier,
		sub = subIdx,
		displayName = tier .. " " .. tostring(subIdx),
		short = string.sub(tier, 1, 1) .. tostring(subIdx),
		color = TIER_COLORS[tier] or Color3.new(1, 1, 1),
	}
end

function RankSystem.RankFromXp(xp: number): RankInfo
	return RankSystem.RankFromLevel(RankSystem.LevelFromXp(xp))
end

-- Returns the player's progress within their current level.
-- At MAX_LEVEL (Immortal 3) progress is locked at 100%.
function RankSystem.LevelProgress(xp: number): { xpInLevel: number, xpNeeded: number, progress: number }
	local level = RankSystem.LevelFromXp(xp)
	if level >= RankSystem.MAX_LEVEL then
		local capCost = costFromLevel(RankSystem.MAX_LEVEL - 1)
		return { xpInLevel = capCost, xpNeeded = capCost, progress = 1 }
	end
	local levelBaseXp = CUMULATIVE_XP[level]
	local xpInLevel = xp - levelBaseXp
	local xpNeeded = costFromLevel(level)
	return {
		xpInLevel = xpInLevel,
		xpNeeded = xpNeeded,
		progress = xpInLevel / xpNeeded,
	}
end

-- Backward-compatible alias for ProgressionController.
RankSystem.Compute = RankSystem.RankFromXp

return RankSystem
