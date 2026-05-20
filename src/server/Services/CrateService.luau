--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local CosmeticRegistry = require(Shared.Modules.CosmeticRegistry)
local GameConfig = require(Shared.Constants.GameConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)

local CrateService = {}

-- Rare melee IDs (excluded from normal tier pool — have their own roll branch).
-- Naming: kept "KARAMBIT_*" for the karambit-specific entries; M9 added alongside.
local KARAMBIT_FOREST_ID = "skin_knife_karambit"
local KARAMBIT_GOLD_ID = "skin_knife_gold"
local KARAMBIT_MARBLE_ID = "skin_knife_doppler"
local M9_VANILLA_ID = "skin_knife_m9bayonet"
local KARAMBIT_IDS: { [string]: boolean } = {
	[KARAMBIT_FOREST_ID] = true,
	[KARAMBIT_GOLD_ID] = true,
	[KARAMBIT_MARBLE_ID] = true,
	[M9_VANILLA_ID] = true,
}

-- Starter knife — granted to every new player as the default melee. Excluded
-- from the gacha pool so getting it as a duplicate is impossible.
local STARTER_KNIFE_ID = "skin_knife_combat"

local KARAMBIT_OVERALL_RATE = 0.005 -- 0.5% chance to land in karambit pool (separate from Contraband rate)

local function pickRandomFromTier(tier: CosmeticRegistry.Tier): CosmeticRegistry.CosmeticInfo
	-- Exclude karambits (rare-melee pool) + starter combat knife (auto-granted)
	local pool: { CosmeticRegistry.CosmeticInfo } = {}
	for _, c in CosmeticRegistry.ByTier[tier] do
		if not KARAMBIT_IDS[c.id] and c.id ~= STARTER_KNIFE_ID then
			table.insert(pool, c)
		end
	end
	if #pool == 0 then
		return CosmeticRegistry.ByTier[tier][1] -- fallback (shouldn't happen)
	end
	return pool[math.random(#pool)]
end

-- Within the rare-melee pool: 90% Forest / 4.5% Gold / 0.5% Marble / 5% M9 Vanilla
-- Absolute drop rate per gacha = KARAMBIT_OVERALL_RATE × (slot %).
-- M9 absolute = 0.5% × 5% = 0.025% per pull.
local function rollKarambit(): CosmeticRegistry.CosmeticInfo
	local r = math.random()
	if r < 0.005 then
		return CosmeticRegistry.ById[KARAMBIT_MARBLE_ID]
	elseif r < 0.005 + 0.045 then
		return CosmeticRegistry.ById[KARAMBIT_GOLD_ID]
	elseif r < 0.005 + 0.045 + 0.05 then
		return CosmeticRegistry.ById[M9_VANILLA_ID]
	else
		return CosmeticRegistry.ById[KARAMBIT_FOREST_ID]
	end
end

local function rollTier(): CosmeticRegistry.Tier
	local r = math.random()
	local cumulative = 0
	cumulative += GameConfig.DropRates.Common
	if r < cumulative then
		return "Common"
	end
	cumulative += GameConfig.DropRates.Legendary
	if r < cumulative then
		return "Legendary"
	end
	return "Contraband"
end

local function rollWithPity(profile: PlayerDataService.Profile): (CosmeticRegistry.CosmeticInfo, boolean)
	-- Karambit chance: 0.05% absolute — overrides pity/normal pool
	if math.random() < KARAMBIT_OVERALL_RATE then
		return rollKarambit(), false
	end
	if profile.pityCounter + 1 >= GameConfig.PityThreshold then
		local forcedTier: CosmeticRegistry.Tier = if math.random() < 0.85 then "Legendary" else "Contraband"
		return pickRandomFromTier(forcedTier), true
	end
	local tier = rollTier()
	return pickRandomFromTier(tier), false
end

Remotes.OpenCrate.OnServerEvent:Connect(function(player: Player)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end

	if profile.coins < GameConfig.CratePrice then
		Remotes.CrateOpened:FireClient(player, { error = "Not enough coins" })
		return
	end

	if not PlayerDataService.SpendCurrency(player, "coins", GameConfig.CratePrice) then
		return
	end

	local cosmetic, wasPity = rollWithPity(profile)

	local isNew = PlayerDataService.GrantCosmetic(player, cosmetic.id)
	local isDuplicate = not isNew
	local refund = 0
	if isDuplicate then
		refund = GameConfig.DuplicateRefund[cosmetic.tier]
		if refund > 0 then
			PlayerDataService.AddCurrency(player, "coins", refund)
		end
	end

	-- Refresh profile reference since SpendCurrency / GrantCosmetic mutated it
	local updatedProfile = PlayerDataService.Get(player)
	if not updatedProfile then
		return
	end

	if cosmetic.tier == "Legendary" or cosmetic.tier == "Contraband" or wasPity then
		PlayerDataService.SetPity(player, 0)
	else
		PlayerDataService.SetPity(player, updatedProfile.pityCounter + 1)
	end

	Remotes.CrateOpened:FireClient(player, {
		cosmetic = cosmetic,
		isDuplicate = isDuplicate,
		refund = refund,
		wasPity = wasPity,
	})
end)

Remotes.EquipCosmetic.OnServerEvent:Connect(function(player: Player, slot: any, cosmeticId: any)
	if typeof(slot) ~= "string" then
		return
	end
	if cosmeticId ~= nil and typeof(cosmeticId) ~= "string" then
		return
	end
	PlayerDataService.SetEquipped(player, slot, cosmeticId)
end)

return CrateService
