--!strict
-- Team constants for Casual mode. Kept tiny + shared so HUD, server scoring,
-- and spawn filtering all use the same string ids.

export type TeamId = "T" | "CT"

local Teams = {
	T = "T" :: TeamId,
	CT = "CT" :: TeamId,
}

-- Display info for HUD / scoreboards
Teams.Info = {
	T = {
		shortName = "T",
		displayName = "Terrorist",
		color = Color3.fromRGB(220, 140, 50),  -- amber/orange
	},
	CT = {
		shortName = "CT",
		displayName = "Counter-Terrorist",
		color = Color3.fromRGB(80, 140, 220),   -- blue
	},
}

function Teams.IsValid(id: any): boolean
	return id == "T" or id == "CT"
end

function Teams.Other(id: TeamId): TeamId
	return if id == "T" then "CT" else "T"
end

return Teams
