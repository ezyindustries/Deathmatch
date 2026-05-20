--!strict
-- Redeem code system. Codes are case-insensitive. Each code can only be redeemed once per player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

local PlayerDataService = require(script.Parent.PlayerDataService)
local RankSystem = require(Shared.Modules.RankSystem)

local RedeemService = {}

-- Per-player redeem tracking (each player can only redeem each code once).
local redeemedCodes: { [number]: { [string]: boolean } } = {}

-- Global redeem counts per code (across ALL players, server-wide).
-- Note: resets on server restart. For persistent global limits, would need DataStore.
local globalRedeemCounts: { [string]: number } = {}

-- Per-code global usage limits (across all players, server-wide). nil = no limit.
-- NOTE: counter is in-memory — resets on server restart. For TRUE single-use
-- across all servers + restarts, would need DataStore-backed counter.
local CODE_GLOBAL_LIMITS: { [string]: number? } = {
	["ABCDEF"]   = 1, -- only the FIRST player globally to redeem gets infinity coins
	["IMMORTAL"] = 1, -- only the FIRST player globally to redeem gets max rank
}

local function fireResult(player: Player, success: boolean, message: string)
	Remotes.RedeemResult:FireClient(player, { success = success, message = message })
end

-- "Infinity money" grant. Uses AddCurrency so DataStore auto-save persists the
-- coins — even after this code is later disabled, redeemed players keep them.
local function grantInfinityCoins(player: Player): (boolean, string)
	PlayerDataService.AddCurrency(player, "coins", 999999999)
	return true, "999,999,999 coins added — enjoy!"
end

-- Bump player straight to Immortal 3 (max rank, level 21). Calculates the
-- exact XP delta from current to MAX_LEVEL threshold and increments. DataStore
-- auto-save persists the new XP value.
local function grantImmortalRank(player: Player): (boolean, string)
	local profile = PlayerDataService.Get(player)
	if not profile then return false, "Player data not loaded — try again." end
	local current = profile.xp or 0
	local target = RankSystem.XpForLevel(RankSystem.MAX_LEVEL)
	local delta = target - current
	if delta > 0 then
		PlayerDataService.IncrementStat(player, "xp", delta)
	end
	return true, "Promoted to Immortal 3 — max rank achieved!"
end

local CODES: { [string]: (Player) -> (boolean, string) } = {
	-- ABCDEF re-enabled — limited to 1 redeem globally (CODE_GLOBAL_LIMITS).
	-- IMMORTAL kept disabled.
	["ABCDEF"]   = grantInfinityCoins,
	-- ["IMMORTAL"] = grantImmortalRank,
}

Remotes.RedeemCode.OnServerEvent:Connect(function(player: Player, codeRaw: any)
	if typeof(codeRaw) ~= "string" then
		fireResult(player, false, "Invalid code.")
		return
	end
	local code = string.upper(string.gsub(codeRaw, "%s", "")) -- normalize: uppercase + no whitespace
	if code == "" then
		fireResult(player, false, "Code cannot be empty.")
		return
	end
	local handler = CODES[code]
	if not handler then
		fireResult(player, false, "Invalid or disabled code.")
		return
	end
	-- Per-player redemption check
	local playerCodes = redeemedCodes[player.UserId]
	if not playerCodes then
		playerCodes = {}
		redeemedCodes[player.UserId] = playerCodes
	end
	if playerCodes[code] then
		fireResult(player, false, "Code already redeemed.")
		return
	end
	-- Global usage limit check (e.g., 828648637 max 2 total uses)
	local globalLimit = CODE_GLOBAL_LIMITS[code]
	if globalLimit then
		local count = globalRedeemCounts[code] or 0
		if count >= globalLimit then
			fireResult(player, false, "Code limit reached — no longer available.")
			return
		end
	end
	local ok, msg = handler(player)
	-- Only consume per-player + global slot if handler succeeded
	if ok then
		playerCodes[code] = true
		if globalLimit then
			globalRedeemCounts[code] = (globalRedeemCounts[code] or 0) + 1
		end
	end
	fireResult(player, ok, msg)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	redeemedCodes[player.UserId] = nil
end)

return RedeemService
