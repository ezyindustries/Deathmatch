--!strict
export type MissionType = "kills" | "wins" | "headshots" | "matches" | "deaths"

export type MissionInfo = {
	id: string,
	displayName: string,
	description: string,
	target: number,
	type: MissionType,
	rewardCoins: number,
	rewardGems: number,
}

local Missions: { MissionInfo } = {
	{
		id = "daily_kills_10",
		displayName = "Killer",
		description = "Get 10 kills",
		target = 10,
		type = "kills",
		rewardCoins = 120,
		rewardGems = 0,
	},
	{
		id = "daily_headshots_3",
		displayName = "Precision",
		description = "Get 3 headshots",
		target = 3,
		type = "headshots",
		rewardCoins = 100,
		rewardGems = 5,
	},
	{
		id = "daily_matches_2",
		displayName = "Participation",
		description = "Play 2 matches",
		target = 2,
		type = "matches",
		rewardCoins = 80,
		rewardGems = 0,
	},
}

local byId: { [string]: MissionInfo } = {}
for _, m in Missions do
	byId[m.id] = m
end

return {
	All = Missions,
	ById = byId,
	ResetIntervalSeconds = 86400, -- 24 hours
}
