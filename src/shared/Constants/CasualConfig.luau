--!strict
-- Tunables for Casual (CS-style 5v5 plant/defuse) mode. Centralized so the
-- round/bomb/defuse durations can be tweaked without hunting through services.

local CasualConfig = {
	-- Per-round phase durations (seconds). TEST MODE: durations shortened
	-- for fast iteration on mechanics; production values in comments.
	BuyDuration = 1,         -- prod: 5 (freeze + spawn-in window before LIVE)
	RoundDuration = 90,      -- prod: 90 (1:30 round timer)
	PostRoundDuration = 2,   -- prod: 4 ("ROUND WON" banner + reset)
	BombTimer = 40,          -- prod: 40 (detonation countdown once T plants)
	PlantTime = 3,           -- prod: 3 (E-hold seconds to plant)
	DefuseTime = 7,          -- prod: 7 (E-hold seconds to defuse)

	-- Team / match shape
	TeamSize = 5,            -- bots fill until 5 per side
	MatchWinScore = 8,       -- first team to 8 round wins ends the match (was 12)
	HalftimeRound = 8,       -- swap roles after round 8 if neither team has won

	-- World gameplay tunables
	BombSiteRadius = 8,      -- T must be within this stud radius of a BombSite to plant; CT must be this close to defuse
	BombDropPickupRadius = 4,
	-- If the match reaches HalftimeRound played with both teams below MatchWinScore,
	-- roles swap and the loop continues. If both teams are tied at 11-11 going
	-- into the final possible round, last round decides (no formal overtime in v1).
}

return CasualConfig
