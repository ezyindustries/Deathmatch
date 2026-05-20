--!strict
-- IMPORTANT: All IDs here are PLACEHOLDERS (1000000+). Upload Gamepasses and
-- Developer Products to Roblox via Create Dashboard, then replace each `id`
-- with the real asset ID. Until then, purchase prompts will fail silently.

export type RewardKind = "coins" | "gems" | "cosmetic"

export type GamepassInfo = {
	id: number,
	displayName: string,
	description: string,
	priceRobux: number,
	-- Optional persistent benefits applied on grant
	xpMultiplier: number?,
	coinMultiplier: number?,
	grantsPremiumPass: boolean?,
	coinGrant: number?, -- one-time coin grant on first ownership detection (idempotent via profile.grantedCoinBonuses)
}

export type ProductInfo = {
	id: number,
	displayName: string,
	description: string,
	priceRobux: number,
	reward: { kind: RewardKind, amount: number },
}

-- Gamepasses — anti-P2W: only Battle Pass Premium, which unlocks the premium
-- track AND grants 3000 coins instantly (one-time, idempotent across rejoins).
-- 170 R$ vs 198 R$ (raw coin price for 3000 via packs) = 14% discount + premium
-- track access bundled = clear best-value framing.
local Gamepasses: { [string]: GamepassInfo } = {
	premiumPass = {
		id = 1841687013,
		displayName = "Battle Pass Premium",
		description = "Unlocks premium track rewards + instant 3,000 coins bonus.",
		priceRobux = 170,
		grantsPremiumPass = true,
		coinGrant = 3000,
	},
}

-- Coin packs (Developer Products — consumable, repurchasable). Pricing follows
-- a progressive-discount curve so each step up feels like a better deal than
-- the last, with badges on the two tiers that drive most revenue in F2P
-- shops (mid-tier "Most Popular", top-tier "Best Value" + charm 99 price).
local Products: { [string]: ProductInfo } = {
	coins_100 = {
		id = 3594019570,
		displayName = "100 Coins",
		description = "Starter pack — first taste of upgrades.",
		priceRobux = 10,
		reward = { kind = "coins", amount = 100 },
	},
	coins_300 = {
		id = 3594020926,
		displayName = "300 Coins",
		description = "17% off vs Starter — small step up.",
		priceRobux = 25,
		reward = { kind = "coins", amount = 300 },
	},
	coins_500 = {
		id = 3594021662,
		displayName = "500 Coins",
		description = "20% off — enough for 5 gacha pulls.",
		priceRobux = 40,
		reward = { kind = "coins", amount = 500 },
	},
	coins_1000 = {
		id = 3594022496,
		displayName = "1,000 Coins",
		description = "🔥 MOST POPULAR — 25% off, 10 gacha pulls.",
		priceRobux = 75,
		reward = { kind = "coins", amount = 1000 },
	},
	coins_1500 = {
		id = 3594023049,
		displayName = "1,500 Coins",
		description = "⭐ BEST VALUE — 34% off, hunt that karambit.",
		priceRobux = 99,
		reward = { kind = "coins", amount = 1500 },
	},
}

-- Reverse lookup: id → key
local productsByAssetId: { [number]: { key: string, info: ProductInfo } } = {}
for key, info in Products do
	productsByAssetId[info.id] = { key = key, info = info }
end

local gamepassesByAssetId: { [number]: { key: string, info: GamepassInfo } } = {}
for key, info in Gamepasses do
	gamepassesByAssetId[info.id] = { key = key, info = info }
end

return {
	Gamepasses = Gamepasses,
	Products = Products,
	ProductByAssetId = productsByAssetId,
	GamepassByAssetId = gamepassesByAssetId,
}
