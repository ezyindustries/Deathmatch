--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local GameConfig = require(Shared.Constants.GameConfig)

local PlayerDataService = {}

export type Profile = {
	coins: number,
	totalKills: number,
	totalDeaths: number,
	totalWins: number,
	matchesPlayed: number,
	level: number,
	xp: number,
	seasonXp: number,
	hasPremiumPass: boolean,
	claimedFreeTiers: { [string]: boolean },
	claimedPremiumTiers: { [string]: boolean },
	inventory: { [string]: boolean },
	equipped: { [string]: string? },
	pityCounter: number,
	lastDailyClaim: number,
	dailyStreak: number,
	missionProgress: { [string]: number },
	missionClaimed: { [string]: boolean },
	missionsResetAt: number,
	tutorialCompleted: boolean,
	xpMultiplier: number,
	coinMultiplier: number,
	ownedGamepasses: { [string]: boolean },
	grantedCoinBonuses: { [string]: boolean }, -- gamepass key -> claimed flag for one-time coinGrant payouts
	loadout: { primary: string, secondary: string },
	settings: { masterVolume: number, baseFov: number, killstreakAnnouncements: boolean },
}

local function defaultProfile(): Profile
	return {
		coins = GameConfig.StartingCoins,
		totalKills = 0,
		totalDeaths = 0,
		totalWins = 0,
		matchesPlayed = 0,
		level = 1,
		xp = 0,
		seasonXp = 0,
		hasPremiumPass = false, -- granted by Battle Pass Premium gamepass purchase only
		claimedFreeTiers = {},
		claimedPremiumTiers = {},
		-- Starter pack: everyone gets the Common combat knife so they always have
		-- a melee equipped. Combat knife is excluded from the gacha pool because
		-- it's auto-granted here.
		inventory = { skin_knife_combat = true },
		equipped = {
			skin_pistol = nil,
			skin_rifle = nil,
			skin_smg = nil,
			skin_sniper = nil,
			skin_knife = "skin_knife_combat",
			kill_effect = nil,
			emote = nil,
			title = nil,
		},
		pityCounter = 0,
		lastDailyClaim = 0,
		dailyStreak = 0,
		missionProgress = {},
		missionClaimed = {},
		missionsResetAt = 0,
		tutorialCompleted = false,
		xpMultiplier = 1.0,
		coinMultiplier = 1.0,
		ownedGamepasses = {},
		grantedCoinBonuses = {},
		loadout = { primary = "rifle", secondary = "pistol", melee = "knife" },
		settings = {
			masterVolume = 70,
			baseFov = 70,
			killstreakAnnouncements = true,
			sensitivity = 100,
			leftHanded = 0,              -- 0 = right (default), 1 = left (mirror viewmodel)
			adsMode = "hold",            -- "hold" (default) or "toggle" — how MB2 enters scope
			-- Mobile HUD button positions (X,Y screen-pixel offsets from default).
			-- 0,0 = use built-in default position from WeaponController.
			hudFireX = 0, hudFireY = 0,
			hudAdsX = 0, hudAdsY = 0,
			hudReloadX = 0, hudReloadY = 0,
			hudSwapX = 0, hudSwapY = 0,
			hudSprintX = 0, hudSprintY = 0,
			-- Crosshair (CS2-style editor)
			crosshair_length = 6,        -- line length px
			crosshair_thickness = 2,     -- line thickness px
			crosshair_offset = 7,        -- gap from center px
			crosshair_dot = 1,           -- center dot 0/1
			crosshair_outline = 0,       -- outline 0/1
			crosshair_r = 255,
			crosshair_g = 255,
			crosshair_b = 255,
		},
	}
end

local profiles: { [number]: Profile } = {}

-- ============ DataStore (graceful fallback) ============
local DATA_STORE_NAME = "RoblokFPS_PlayerData_v1"
local KEY_PREFIX = "user_"
local SAVE_INTERVAL = 60

local dataStore: DataStore? = nil
local apiAvailable = false

do
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(DATA_STORE_NAME)
	end)
	if ok and ds then
		dataStore = ds
		apiAvailable = true
		print("[PlayerData] DataStore connected.")
	else
		print("[PlayerData] DataStore unavailable - using in-memory only.")
	end
end

local function keyFor(userId: number): string
	return KEY_PREFIX .. tostring(userId)
end

local function mergeDefaults(saved: any): Profile
	local default = defaultProfile()
	for key, value in default :: any do
		if saved[key] == nil then
			(saved :: any)[key] = value
		elseif typeof(value) == "table" and typeof((saved :: any)[key]) == "table" then
			for subKey, subValue in value do
				if (saved :: any)[key][subKey] == nil then
					(saved :: any)[key][subKey] = subValue
				end
			end
		end
	end
	return saved :: Profile
end

local function loadProfile(userId: number): Profile
	if not apiAvailable or not dataStore then
		return defaultProfile()
	end
	local ok, saved = pcall(function()
		return dataStore:GetAsync(keyFor(userId))
	end)
	if not ok then
		warn(string.format("[PlayerData] Load failed for %d: %s", userId, tostring(saved)))
		return defaultProfile()
	end
	if not saved then
		return defaultProfile()
	end
	return mergeDefaults(saved)
end

local function saveProfile(userId: number, profile: Profile): boolean
	if not apiAvailable or not dataStore then
		return false
	end
	local ok, err = pcall(function()
		dataStore:UpdateAsync(keyFor(userId), function(_old)
			return profile
		end)
	end)
	if not ok then
		warn(string.format("[PlayerData] Save failed for %d: %s", userId, tostring(err)))
	end
	return ok
end

function PlayerDataService.Get(player: Player): Profile?
	return profiles[player.UserId]
end

local function broadcastTo(player: Player)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	Remotes.PlayerDataChanged:FireClient(player, profile)
end

function PlayerDataService.AddCurrency(player: Player, currency: string, amount: number)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	if currency ~= "coins" then
		return
	end
	local mul = profile.coinMultiplier or 1
	profile.coins = profile.coins + math.floor(amount * mul)
	broadcastTo(player)
end

function PlayerDataService.IncrementStat(player: Player, stat: string, amount: number)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	if (profile :: any)[stat] == nil then
		return
	end
	(profile :: any)[stat] = (profile :: any)[stat] + amount
	broadcastTo(player)
end

function PlayerDataService.SpendCurrency(player: Player, currency: string, amount: number): boolean
	local profile = profiles[player.UserId]
	if not profile then
		return false
	end
	if currency ~= "coins" then
		return false
	end
	if profile.coins < amount then
		return false
	end
	profile.coins -= amount
	broadcastTo(player)
	return true
end

function PlayerDataService.GrantCosmetic(player: Player, cosmeticId: string): boolean
	local profile = profiles[player.UserId]
	if not profile then
		return false
	end
	local already = profile.inventory[cosmeticId] == true
	profile.inventory[cosmeticId] = true
	broadcastTo(player)
	return not already
end

function PlayerDataService.SetPity(player: Player, value: number)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.pityCounter = value
	broadcastTo(player)
end

function PlayerDataService.MarkTierClaimed(player: Player, tierNum: number, isPremium: boolean): boolean
	local profile = profiles[player.UserId]
	if not profile then
		return false
	end
	local key = tostring(tierNum)
	local bucket = if isPremium then profile.claimedPremiumTiers else profile.claimedFreeTiers
	if bucket[key] then
		return false
	end
	bucket[key] = true
	broadcastTo(player)
	return true
end

function PlayerDataService.SetDailyClaim(player: Player, timestamp: number, streak: number)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.lastDailyClaim = timestamp
	profile.dailyStreak = streak
	broadcastTo(player)
end

function PlayerDataService.IncrementMissionProgress(player: Player, missionId: string, amount: number)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.missionProgress[missionId] = (profile.missionProgress[missionId] or 0) + amount
	broadcastTo(player)
end

function PlayerDataService.ClaimMission(player: Player, missionId: string): boolean
	local profile = profiles[player.UserId]
	if not profile then
		return false
	end
	if profile.missionClaimed[missionId] then
		return false
	end
	profile.missionClaimed[missionId] = true
	broadcastTo(player)
	return true
end

function PlayerDataService.UpdateSetting(player: Player, key: string, value: any)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	if profile.settings[key] == nil then
		return
	end
	local current = profile.settings[key]
	if typeof(value) ~= typeof(current) then
		return
	end
	if typeof(value) == "number" then
		-- HUD position offsets allow wider range (-4000..4000 covers any phone/tablet).
		if string.sub(key, 1, 3) == "hud" then
			if value < -4000 or value > 4000 then return end
		else
			if value < 0 or value > 300 then return end
		end
	end
	-- Per-key value whitelists for string-typed settings.
	if key == "adsMode" and value ~= "hold" and value ~= "toggle" then
		return
	end
	profile.settings[key] = value
	broadcastTo(player)
end

function PlayerDataService.SetLoadout(player: Player, primary: string?, secondary: string?, melee: string?)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	if primary then
		profile.loadout.primary = primary
	end
	if secondary then
		profile.loadout.secondary = secondary
	end
	if melee then
		(profile.loadout :: any).melee = melee
	end
	broadcastTo(player)
end

function PlayerDataService.SetGamepassOwned(player: Player, key: string, owned: boolean)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.ownedGamepasses[key] = owned or nil
	broadcastTo(player)
end

function PlayerDataService.SetXpMultiplier(player: Player, mul: number)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.xpMultiplier = mul
	broadcastTo(player)
end

function PlayerDataService.SetCoinMultiplier(player: Player, mul: number)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.coinMultiplier = mul
	broadcastTo(player)
end

function PlayerDataService.SetPremiumPass(player: Player, value: boolean)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.hasPremiumPass = value
	broadcastTo(player)
end

function PlayerDataService.MarkTutorialDone(player: Player)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.tutorialCompleted = true
	broadcastTo(player)
end

function PlayerDataService.ResetMissions(player: Player, resetAt: number)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.missionProgress = {}
	profile.missionClaimed = {}
	profile.missionsResetAt = resetAt
	broadcastTo(player)
end

local VALID_EQUIP_SLOTS: { [string]: boolean } = {
	skin_pistol = true,
	skin_rifle = true,
	skin_smg = true,
	skin_sniper = true,
	skin_knife = true,
	kill_effect = true,
	emote = true,
	title = true,
}

function PlayerDataService.SetEquipped(player: Player, slot: string, cosmeticId: string?)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	if not VALID_EQUIP_SLOTS[slot] then
		return
	end
	if cosmeticId and not profile.inventory[cosmeticId] then
		return
	end
	profile.equipped[slot] = cosmeticId
	broadcastTo(player)
end

Remotes.CompleteTutorial.OnServerEvent:Connect(function(player: Player)
	PlayerDataService.MarkTutorialDone(player)
end)

Remotes.UpdateSetting.OnServerEvent:Connect(function(player: Player, keyRaw: any, valueRaw: any)
	if typeof(keyRaw) ~= "string" then
		return
	end
	PlayerDataService.UpdateSetting(player, keyRaw, valueRaw)
end)

-- Legacy migration: profiles that saved with the old testing override value
-- (exactly 9_999_999_999) get reset to default. Uses exact-match so legitimate
-- redeem grants (e.g. "ABCDEF" → 999_999_999) aren't accidentally wiped.
local LEGACY_TESTING_COIN_VALUE = 9999999999

Players.PlayerAdded:Connect(function(player: Player)
	local profile = loadProfile(player.UserId)
	profiles[player.UserId] = profile
	if profile.coins == LEGACY_TESTING_COIN_VALUE then
		print(string.format("[PlayerData] Resetting legacy corrupted balance %d → %d for %s",
			profile.coins, GameConfig.StartingCoins, player.Name))
		profile.coins = GameConfig.StartingCoins
	end
	-- Reset legacy hasPremiumPass=true (saved from the old default before BP
	-- Premium gamepass existed). MonetizationService.checkOwnedGamepasses runs
	-- ~1s later and re-flips to true for actual gamepass owners.
	profile.hasPremiumPass = false
	-- Ensure starter combat knife is always granted (covers existing profiles
	-- saved before the starter-pack was added to defaults).
	if not profile.inventory["skin_knife_combat"] then
		profile.inventory["skin_knife_combat"] = true
	end
	if not profile.equipped.skin_knife then
		profile.equipped.skin_knife = "skin_knife_combat"
	end
	task.wait(0.5)
	broadcastTo(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local profile = profiles[player.UserId]
	if profile then
		saveProfile(player.UserId, profile)
	end
	profiles[player.UserId] = nil
end)

-- Periodic auto-save
task.spawn(function()
	while true do
		task.wait(SAVE_INTERVAL)
		for userId, profile in profiles do
			saveProfile(userId, profile)
		end
	end
end)

-- Save all on server shutdown (BindToClose blocks shutdown up to 30s)
game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	for userId, profile in profiles do
		saveProfile(userId, profile)
	end
end)

return PlayerDataService
