--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local BattlePassConfig = require(Shared.Modules.BattlePassConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)

local BattlePassService = {}

local function tierForXp(xp: number): number
	local achieved = 0
	for _, t in BattlePassConfig.Tiers do
		if xp >= t.xpRequired then
			achieved = t.tier
		else
			break
		end
	end
	return achieved
end

local function applyReward(player: Player, reward: BattlePassConfig.Reward)
	if reward.kind == "coins" then
		PlayerDataService.AddCurrency(player, "coins", reward.value :: number)
	elseif reward.kind == "gems" then
		PlayerDataService.AddCurrency(player, "gems", reward.value :: number)
	elseif reward.kind == "cosmetic" then
		PlayerDataService.GrantCosmetic(player, reward.value :: string)
	end
end

Remotes.ClaimBPReward.OnServerEvent:Connect(function(player: Player, tierNum: any, trackRaw: any)
	if typeof(tierNum) ~= "number" then
		return
	end
	if typeof(trackRaw) ~= "string" then
		return
	end
	local isPremium = trackRaw == "premium"

	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end

	if isPremium and not profile.hasPremiumPass then
		Remotes.BPRewardResult:FireClient(player, { error = "Premium pass not owned" })
		return
	end

	local achievedTier = tierForXp(profile.seasonXp)
	if tierNum > achievedTier then
		Remotes.BPRewardResult:FireClient(player, { error = "Tier not reached yet" })
		return
	end

	local tierData
	for _, t in BattlePassConfig.Tiers do
		if t.tier == tierNum then
			tierData = t
			break
		end
	end
	if not tierData then
		return
	end

	local reward = if isPremium then tierData.premium else tierData.free
	if not reward then
		Remotes.BPRewardResult:FireClient(player, { error = "No reward on this tier" })
		return
	end

	if not PlayerDataService.MarkTierClaimed(player, tierNum, isPremium) then
		Remotes.BPRewardResult:FireClient(player, { error = "Already claimed" })
		return
	end

	applyReward(player, reward)

	Remotes.BPRewardResult:FireClient(player, {
		tier = tierNum,
		track = trackRaw,
		reward = reward,
	})
end)

return BattlePassService
