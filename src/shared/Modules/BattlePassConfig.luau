--!strict
export type Reward = {
	kind: "coins" | "gems" | "cosmetic",
	value: number | string,
}

export type Tier = {
	tier: number,
	xpRequired: number,
	free: Reward?,
	premium: Reward?,
}

local XP_PER_TIER = 500

local function tier(index: number, free: Reward?, premium: Reward?): Tier
	return {
		tier = index,
		xpRequired = index * XP_PER_TIER,
		free = free,
		premium = premium,
	}
end

local Tiers: { Tier } = {
	tier(1, { kind = "coins", value = 50 }, { kind = "coins", value = 150 }),
	tier(2, nil, { kind = "cosmetic", value = "skin_pistol_red" }),
	tier(3, { kind = "coins", value = 75 }, { kind = "coins", value = 200 }),
	tier(4, nil, { kind = "cosmetic", value = "kfx_smoke" }),
	tier(5, { kind = "coins", value = 100 }, { kind = "cosmetic", value = "skin_pistol_blue" }),
	tier(6, nil, { kind = "coins", value = 250 }),
	tier(7, { kind = "coins", value = 100 }, { kind = "cosmetic", value = "title_rookie" }),
	tier(8, nil, { kind = "cosmetic", value = "kfx_dust" }),
	tier(9, { kind = "coins", value = 125 }, { kind = "coins", value = 300 }),
	tier(10, { kind = "gems", value = 10 }, { kind = "cosmetic", value = "skin_pistol_carbon" }),
	tier(11, nil, { kind = "coins", value = 300 }),
	tier(12, { kind = "coins", value = 150 }, { kind = "cosmetic", value = "kfx_fire" }),
	tier(13, nil, { kind = "cosmetic", value = "kfx_ice" }),
	tier(14, { kind = "coins", value = 150 }, { kind = "coins", value = 400 }),
	tier(15, { kind = "gems", value = 15 }, { kind = "cosmetic", value = "skin_pistol_neon" }),
	tier(16, nil, { kind = "cosmetic", value = "title_hunter" }),
	tier(17, { kind = "coins", value = 200 }, { kind = "coins", value = 500 }),
	tier(18, nil, { kind = "cosmetic", value = "kfx_lightning" }),
	tier(19, { kind = "gems", value = 25 }, { kind = "cosmetic", value = "skin_pistol_gold" }),
	tier(20, { kind = "gems", value = 50 }, { kind = "cosmetic", value = "skin_pistol_celestial" }),
}

return {
	Tiers = Tiers,
	XpPerTier = XP_PER_TIER,
	MaxTier = #Tiers,
	SeasonName = "Season 1: Genesis",
}
