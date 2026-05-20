--!strict
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local ProductsConfig = require(Shared.Modules.ProductsConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)

local MonetizationService = {}

local function applyGamepassBenefits(player: Player, gpKey: string, info: ProductsConfig.GamepassInfo)
	PlayerDataService.SetGamepassOwned(player, gpKey, true)
	if info.xpMultiplier and info.xpMultiplier > 1 then
		local profile = PlayerDataService.Get(player)
		if profile and profile.xpMultiplier < info.xpMultiplier then
			PlayerDataService.SetXpMultiplier(player, info.xpMultiplier)
		end
	end
	if info.coinMultiplier and info.coinMultiplier > 1 then
		local profile = PlayerDataService.Get(player)
		if profile and (profile.coinMultiplier or 1) < info.coinMultiplier then
			PlayerDataService.SetCoinMultiplier(player, info.coinMultiplier)
		end
	end
	if info.grantsPremiumPass then
		PlayerDataService.SetPremiumPass(player, true)
	end
	-- One-time coin bonus: only granted on first detection. Mutate the profile
	-- directly so the claim flag persists alongside the gamepass itself.
	if info.coinGrant and info.coinGrant > 0 then
		local profile = PlayerDataService.Get(player)
		if profile then
			local granted = (profile :: any).grantedCoinBonuses
			if not granted then
				granted = {}
				(profile :: any).grantedCoinBonuses = granted
			end
			if not granted[gpKey] then
				granted[gpKey] = true
				PlayerDataService.AddCurrency(player, "coins", info.coinGrant)
			end
		end
	end
end

local function checkOwnedGamepasses(player: Player)
	for key, info in ProductsConfig.Gamepasses do
		local ok, owned = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, info.id)
		end)
		if ok and owned then
			applyGamepassBenefits(player, key, info)
		end
	end
end

-- Client requests purchase prompt
Remotes.PromptPurchase.OnServerEvent:Connect(function(player: Player, kindRaw: any, keyRaw: any)
	if typeof(kindRaw) ~= "string" or typeof(keyRaw) ~= "string" then
		return
	end
	if kindRaw == "gamepass" then
		local info = ProductsConfig.Gamepasses[keyRaw]
		if info then
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, info.id)
			end)
		end
	elseif kindRaw == "product" then
		local info = ProductsConfig.Products[keyRaw]
		if info then
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, info.id)
			end)
		end
	end
end)

-- Listen for gamepass purchase completion
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end
	local entry = ProductsConfig.GamepassByAssetId[gamePassId]
	if not entry then
		return
	end
	applyGamepassBenefits(player, entry.key, entry.info)
end)

-- Handle dev product receipts (consumables)
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local entry = ProductsConfig.ProductByAssetId[receiptInfo.ProductId]
	if not entry then
		warn(string.format("[Monetization] Unknown product: %d", receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local reward = entry.info.reward
	if reward.kind == "coins" then
		PlayerDataService.AddCurrency(player, "coins", reward.amount)
	elseif reward.kind == "gems" then
		PlayerDataService.AddCurrency(player, "gems", reward.amount)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

Players.PlayerAdded:Connect(function(player: Player)
	task.wait(1)
	checkOwnedGamepasses(player)
end)

return MonetizationService
