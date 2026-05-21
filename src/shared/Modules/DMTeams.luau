--!strict
-- 10v10 Team Deathmatch team constants + pure helpers.
-- Kept separate from Casual mode's T/CT teams (Teams.luau) so we don't conflate
-- gamemodes. Server logic uses raw "A"/"B"; clients show "Tim Kawan"/"Tim Lawan"
-- where "Kawan" is always whatever team the local player is on (resolved client-
-- side — this module ships RAW labels only).

export type TeamId = "A" | "B"

local DMTeams = {}

DMTeams.Teams = {
	A = "A" :: TeamId,
	B = "B" :: TeamId,
}

-- Display strings sent to clients in TeamStateChanged payloads / HUD. The UI
-- swaps these at render time based on local player's team (your team = Kawan,
-- enemy = Lawan), but the server-side label is fixed per team id.
DMTeams.Display = {
	A = "Tim Kawan",
	B = "Tim Lawan",
}

DMTeams.Colors = {
	A = Color3.fromRGB(96, 165, 250),  -- friendly blue
	B = Color3.fromRGB(248, 113, 113), -- enemy red
}

-- Total combatants per server (player + bot). Solo player = 1 + 19 bots = 20.
DMTeams.TARGET = 20
-- Per-side cap. 10 + 10 = TARGET.
DMTeams.TEAM_SIZE = 10
-- Cooldown (seconds) after a successful team switch before the same player can
-- swap again. Prevents griefing via rapid-fire team flipping.
DMTeams.SWITCH_COOLDOWN_SEC = 30

-- Pure: are these two team ids on opposing sides?
function DMTeams.isEnemy(teamA: string, teamB: string): boolean
	return teamA ~= teamB
end

-- Pure: pick the team with fewer combatants. Tie -> "A" (deterministic).
function DMTeams.pickSmaller(aCount: number, bCount: number): TeamId
	if aCount <= bCount then
		return "A"
	end
	return "B"
end

return DMTeams
