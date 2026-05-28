--!strict
export type CosmeticType = "weapon_skin" | "kill_effect" | "emote" | "title" | "banner"
export type Tier = "Common" | "Rare" | "Epic" | "Legendary" | "Contraband"

export type CosmeticInfo = {
	id: string,
	displayName: string,
	tier: Tier,
	type: CosmeticType,
	color: Color3,           -- main body / receiver color
	weaponId: string?,        -- only set for type = "weapon_skin"
	accentColor: Color3?,     -- accent for highlights (legacy single accent)
	slideColor: Color3?,      -- slide / charging handle override
	gripColor: Color3?,       -- pistol grip override
	stockColor: Color3?,      -- buttstock override
	barrelColor: Color3?,     -- barrel parts override
	isKarambit: boolean?,     -- knife skin: use karambit viewmodel shape (curved hawkbill + finger ring)
	isM9: boolean?,           -- knife skin: use M9 Bayonet viewmodel shape (long straight clip-point + serrations)
	isStiletto: boolean?,     -- knife skin: use stiletto viewmodel shape (long thin double-edged needle)
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local CosmeticRegistry: { CosmeticInfo } = {
	-- =========================================================
	-- GLOCK (5 skins: 3 Common, 1 Legendary, 1 Contraband)
	-- Pattern via body/slide/grip 2-3 tone contrast.
	-- =========================================================
	{ id = "skin_pistol_carbon", displayName = "Carbon Glock", tier = "Common", type = "weapon_skin", weaponId = "pistol",
		color = c(40, 45, 55), slideColor = c(60, 65, 75), gripColor = c(30, 32, 40) },
	{ id = "skin_pistol_ash", displayName = "Ash Glock", tier = "Common", type = "weapon_skin", weaponId = "pistol",
		color = c(120, 120, 130), slideColor = c(160, 160, 170), gripColor = c(90, 90, 100) },
	{ id = "skin_pistol_steel", displayName = "Steel Glock", tier = "Common", type = "weapon_skin", weaponId = "pistol",
		color = c(150, 155, 165), slideColor = c(200, 205, 215), gripColor = c(80, 85, 95) },
	{ id = "skin_pistol_phantom", displayName = "Phantom Glock", tier = "Legendary", type = "weapon_skin", weaponId = "pistol",
		color = c(60, 30, 110), slideColor = c(180, 120, 255), gripColor = c(40, 20, 80), accentColor = c(255, 200, 255) },
	{ id = "skin_pistol_reaper", displayName = "Reaper Glock", tier = "Contraband", type = "weapon_skin", weaponId = "pistol",
		color = c(15, 15, 20), slideColor = c(230, 230, 240), gripColor = c(120, 20, 30), accentColor = c(255, 50, 50) },

	-- =========================================================
	-- AK-47 (5 skins)
	-- =========================================================
	{ id = "skin_rifle_black", displayName = "Onyx Black AK", tier = "Common", type = "weapon_skin", weaponId = "rifle",
		color = c(30, 32, 38), slideColor = c(50, 52, 60), gripColor = c(20, 22, 28), stockColor = c(35, 35, 40) },
	{ id = "skin_rifle_olive", displayName = "Olive AK", tier = "Common", type = "weapon_skin", weaponId = "rifle",
		color = c(95, 105, 70), slideColor = c(60, 70, 50), gripColor = c(80, 90, 60), stockColor = c(110, 120, 85) },
	{ id = "skin_rifle_tan", displayName = "Desert Tan AK", tier = "Common", type = "weapon_skin", weaponId = "rifle",
		color = c(190, 165, 120), slideColor = c(140, 120, 85), gripColor = c(160, 135, 95), stockColor = c(210, 185, 140) },
	{ id = "skin_rifle_inferno", displayName = "Inferno AK", tier = "Legendary", type = "weapon_skin", weaponId = "rifle",
		color = c(255, 90, 30), slideColor = c(255, 220, 0), gripColor = c(60, 10, 10), stockColor = c(200, 50, 20), accentColor = c(255, 200, 0) },
	-- WRAITH: dark crimson body + WHITE slide + crimson wood grip = high-contrast pattern (renamed from Bloodthirst for age-friendly wording)
	{ id = "skin_rifle_bloodthirst", displayName = "Wraith AK", tier = "Contraband", type = "weapon_skin", weaponId = "rifle",
		color = c(80, 15, 20), slideColor = c(240, 240, 240), gripColor = c(50, 5, 10), stockColor = c(220, 220, 220), accentColor = c(200, 0, 0) },

	-- =========================================================
	-- UMP-45 (5 skins) — slot smg
	-- =========================================================
	{ id = "skin_smg_slate", displayName = "Slate UMP", tier = "Common", type = "weapon_skin", weaponId = "smg",
		color = c(70, 75, 90), slideColor = c(50, 55, 70), gripColor = c(60, 65, 80) },
	{ id = "skin_smg_steel", displayName = "Steel UMP", tier = "Common", type = "weapon_skin", weaponId = "smg",
		color = c(120, 125, 135), slideColor = c(180, 185, 195), gripColor = c(80, 85, 95) },
	{ id = "skin_smg_urban", displayName = "Urban Camo UMP", tier = "Common", type = "weapon_skin", weaponId = "smg",
		color = c(95, 100, 115), slideColor = c(50, 55, 70), gripColor = c(120, 125, 140) },
	{ id = "skin_smg_mirage", displayName = "Mirage UMP", tier = "Legendary", type = "weapon_skin", weaponId = "smg",
		color = c(255, 200, 100), slideColor = c(120, 80, 220), gripColor = c(60, 40, 100), accentColor = c(255, 220, 80) },
	-- CYBERPUNK: dark body + NEON PINK slide + cyan grip
	{ id = "skin_smg_cyberpunk", displayName = "Cyberpunk UMP", tier = "Contraband", type = "weapon_skin", weaponId = "smg",
		color = c(25, 5, 40), slideColor = c(255, 30, 180), gripColor = c(0, 200, 220), accentColor = c(0, 255, 220) },

	-- =========================================================
	-- AWP (5 skins) — slot sniper
	-- =========================================================
	{ id = "skin_sniper_dustline", displayName = "Dustline AWP", tier = "Common", type = "weapon_skin", weaponId = "sniper",
		color = c(140, 110, 80), slideColor = c(100, 75, 55), gripColor = c(80, 60, 40), stockColor = c(160, 130, 95) },
	{ id = "skin_sniper_marsh", displayName = "Marsh AWP", tier = "Common", type = "weapon_skin", weaponId = "sniper",
		color = c(60, 90, 65), slideColor = c(40, 70, 50), gripColor = c(50, 75, 55), stockColor = c(70, 100, 70) },
	{ id = "skin_sniper_arctic", displayName = "Arctic AWP", tier = "Common", type = "weapon_skin", weaponId = "sniper",
		color = c(220, 230, 240), slideColor = c(180, 200, 220), gripColor = c(60, 70, 90), stockColor = c(240, 245, 250) },
	{ id = "skin_sniper_eclipse", displayName = "Eclipse AWP", tier = "Legendary", type = "weapon_skin", weaponId = "sniper",
		color = c(40, 40, 80), slideColor = c(200, 220, 255), gripColor = c(30, 30, 60), stockColor = c(60, 60, 110), accentColor = c(200, 220, 255) },
	-- VOIDWALKER: black body + NEON PURPLE slide + dark void grip
	{ id = "skin_sniper_voidwalker", displayName = "Voidwalker AWP", tier = "Contraband", type = "weapon_skin", weaponId = "sniper",
		color = c(15, 5, 25), slideColor = c(180, 0, 255), gripColor = c(40, 0, 60), stockColor = c(25, 0, 40), accentColor = c(255, 100, 255) },

	-- =========================================================
	-- KNIFE (4 skins) — Combat = straight blade; Karambit variants use curved viewmodel (isKarambit).
	-- Only handle (color) + blade (barrelColor) customize. Hand & forearm stay skin-toned.
	-- =========================================================
	{ id = "skin_knife_combat", displayName = "Combat Knife", tier = "Common", type = "weapon_skin", weaponId = "knife",
		color = c(35, 35, 40), barrelColor = c(200, 210, 220) },
	-- FOREST: dark forest green handle + medium green blade (no accent dots — clean forest look)
	{ id = "skin_knife_karambit", displayName = "Karambit Forest", tier = "Rare", type = "weapon_skin", weaponId = "knife",
		color = c(25, 55, 25), barrelColor = c(95, 155, 75), isKarambit = true },
	{ id = "skin_knife_gold", displayName = "Golden Karambit", tier = "Legendary", type = "weapon_skin", weaponId = "knife",
		color = c(80, 60, 20), barrelColor = c(255, 215, 0), accentColor = c(255, 240, 120), isKarambit = true },
	-- MARBLE FADE style — black handle + hot pink/red blade with golden yellow accents
	{ id = "skin_knife_doppler", displayName = "Marble Fade Karambit", tier = "Contraband", type = "weapon_skin", weaponId = "knife",
		color = c(15, 8, 12), barrelColor = c(255, 50, 120), accentColor = c(255, 220, 80), isKarambit = true },
	-- M9 BAYONET — straight long bayonet with clip-point + serrations + wire-cutter hole.
	-- isM9 flag triggers the dedicated viewmodelM9 shape in WeaponConfig.
	{ id = "skin_knife_m9bayonet", displayName = "M9 Bayonet | Vanilla", tier = "Contraband", type = "weapon_skin", weaponId = "knife",
		color = c(25, 25, 28), barrelColor = c(195, 200, 210), isM9 = true },
	-- STILETTO — Italian needle-point dagger: long thin double-edged blade, slim leather grip, small round crossguard.
	-- isStiletto flag triggers the dedicated viewmodelStiletto shape in WeaponConfig.
	{ id = "skin_knife_stiletto", displayName = "Stiletto | Vanilla", tier = "Contraband", type = "weapon_skin", weaponId = "knife",
		color = c(45, 30, 20), barrelColor = c(205, 215, 225), isStiletto = true },
}

local TierColors: { [Tier]: Color3 } = {
	Common = Color3.fromRGB(180, 180, 180),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(200, 80, 255),
	Legendary = Color3.fromRGB(255, 180, 60),
	Contraband = Color3.fromRGB(220, 30, 50), -- forbidden red (CS-style contraband)
}

local byTier: { [Tier]: { CosmeticInfo } } = {
	Common = {}, Rare = {}, Epic = {}, Legendary = {}, Contraband = {},
}
for _, c in CosmeticRegistry do
	table.insert(byTier[c.tier], c)
end

local byId: { [string]: CosmeticInfo } = {}
for _, c in CosmeticRegistry do
	byId[c.id] = c
end

local byType: { [string]: { CosmeticInfo } } = {}
for _, c in CosmeticRegistry do
	local key = c.type
	if c.type == "weapon_skin" and c.weaponId then
		key = "weapon_skin_" .. c.weaponId
	end
	if not byType[key] then
		byType[key] = {}
	end
	table.insert(byType[key], c)
end

-- Helper: get slot key for an equipped cosmetic
local function slotKeyFor(cosmetic: CosmeticInfo): string
	if cosmetic.type == "weapon_skin" and cosmetic.weaponId then
		return "skin_" .. cosmetic.weaponId
	end
	return cosmetic.type
end

return {
	All = CosmeticRegistry,
	ByTier = byTier,
	ById = byId,
	ByType = byType,
	TierColors = TierColors,
	SlotKeyFor = slotKeyFor,
}
