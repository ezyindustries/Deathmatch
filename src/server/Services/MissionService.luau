--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local MissionConfig = require(Shared.Modules.MissionConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)
local WeaponService = require(script.Parent.WeaponService)

local MissionService = {}

local function maybeResetMissions(player: Player)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local now = os.time()
	if now - profile.missionsResetAt >= MissionConfig.ResetIntervalSeconds then
		PlayerDataService.ResetMissions(player, now)
	end
end

local function incrementByType(player: Player, missionType: MissionConfig.MissionType, amount: number)
	maybeResetMissions(player)
	for _, m in MissionConfig.All do
		if m.type == missionType then
			PlayerDataService.IncrementMissionProgress(player, m.id, amount)
		end
	end
end

function MissionService.OnMatchPlayed(player: Player)
	incrementByType(player, "matches", 1)
end

function MissionService.OnMatchWon(player: Player)
	incrementByType(player, "wins", 1)
end

WeaponService.PlayerKilled:Connect(function(killer: Player, _victim: Player, _weapon: any, isHeadshot: boolean)
	incrementByType(killer, "kills", 1)
	if isHeadshot then
		incrementByType(killer, "headshots", 1)
	end
end)

Remotes.ClaimMission.OnServerEvent:Connect(function(player: Player, missionIdRaw: any)
	if typeof(missionIdRaw) ~= "string" then
		return
	end
	maybeResetMissions(player)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end

	local mission = MissionConfig.ById[missionIdRaw]
	if not mission then
		return
	end

	if profile.missionClaimed[missionIdRaw] then
		Remotes.MissionResult:FireClient(player, { error = "Already claimed" })
		return
	end

	local progress = profile.missionProgress[missionIdRaw] or 0
	if progress < mission.target then
		Remotes.MissionResult:FireClient(player, { error = "Not complete" })
		return
	end

	if not PlayerDataService.ClaimMission(player, missionIdRaw) then
		return
	end

	if mission.rewardCoins > 0 then
		PlayerDataService.AddCurrency(player, "coins", mission.rewardCoins)
	end
	if mission.rewardGems > 0 then
		PlayerDataService.AddCurrency(player, "gems", mission.rewardGems)
	end

	Remotes.MissionResult:FireClient(player, {
		missionId = missionIdRaw,
		rewardCoins = mission.rewardCoins,
		rewardGems = mission.rewardGems,
	})
end)

Players.PlayerAdded:Connect(function(player: Player)
	task.wait(1)
	maybeResetMissions(player)
end)

return MissionService
