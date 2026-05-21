--!strict
-- PrivateLobbyService
--
-- Handles private-party lifecycle:
--   * CreatePrivateLobby — reserves a server via TeleportService:ReserveServer,
--     generates a human-friendly 6-char code, stores (code → accessCode +
--     privateServerId + hostUserId) in a MemoryStore HashMap with 30-min TTL,
--     then teleports the host to the reserved server.
--   * JoinSessionByCode — look up code, teleport caller to the reserved server.
--   * LeavePrivateLobby — best-effort cleanup of the caller's pending lobby
--     entry (we don't actually need to do much: the code TTL expires anyway).
--
-- Code charset excludes 0/O/I/l/1 to avoid confusion when reading from voice
-- chat or screenshots. 6 chars from a 31-char alphabet = ~30 bits of entropy,
-- plenty for a 30-min collision window.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

local PrivateLobbyService = {}

local CODES_HASH_NAME = "RoblokFPS_Codes"
local CODE_TTL = 1800            -- 30 minutes
local CODE_LENGTH = 6
local CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   -- no 0/O/I/l/1
local CODE_GEN_RETRIES = 5       -- if generated code collides with existing key, retry

-- Defaults / bounds for the host-configurable lobby settings (passed as the
-- optional `config` arg to CreatePrivateLobby).
local DEFAULT_WITH_BOTS = true
local DEFAULT_MAX_PLAYERS = 20
local MIN_MAX_PLAYERS = 2
local MAX_MAX_PLAYERS = 20

export type LobbyConfig = {
	withBots: boolean,
	maxPlayers: number,
}

export type CreateResult = {
	ok: boolean,
	code: string?,
	error: string?,
}

export type JoinResult = {
	ok: boolean,
	error: string?,
}

export type LeaveResult = {
	ok: boolean,
}

export type StoredCode = {
	accessCode: string,
	privateServerId: string,
	hostUserId: number,
	createdAt: number,
	withBots: boolean,
	maxPlayers: number,
}

-- Coerce/validate an arbitrary client-supplied config payload into a safe
-- LobbyConfig. Missing/invalid fields fall back to defaults; maxPlayers is
-- clamped + integerized to keep the reserved server within engine limits.
local function normalizeConfig(raw: any): LobbyConfig
	local withBots = DEFAULT_WITH_BOTS
	local maxPlayers = DEFAULT_MAX_PLAYERS
	if typeof(raw) == "table" then
		local t = raw :: any
		if typeof(t.withBots) == "boolean" then
			withBots = t.withBots
		end
		if typeof(t.maxPlayers) == "number" then
			local mp = math.floor(t.maxPlayers)
			if mp < MIN_MAX_PLAYERS then mp = MIN_MAX_PLAYERS end
			if mp > MAX_MAX_PLAYERS then mp = MAX_MAX_PLAYERS end
			maxPlayers = mp
		end
	end
	return { withBots = withBots, maxPlayers = maxPlayers }
end

function PrivateLobbyService.NormalizeConfigForTest(raw: any): LobbyConfig
	return normalizeConfig(raw)
end

-- Track lobbies created by this server so LeavePrivateLobby has something to
-- key off of. The HashMap is the source of truth; this is a local convenience
-- index from userId → code.
local hostUserIdToCode: { [number]: string } = {}

local function generateCode(): string
	local chars: { string } = {}
	for i = 1, CODE_LENGTH do
		local idx = math.random(1, #CODE_ALPHABET)
		chars[i] = string.sub(CODE_ALPHABET, idx, idx)
	end
	return table.concat(chars)
end

-- Try to atomically claim a code key in the HashMap. Returns the code on
-- success, or nil if all retries collided (vanishingly unlikely with 30-bit
-- entropy and a 30-min window).
local function claimUniqueCode(payload: StoredCode): (string?, string?)
	for _attempt = 1, CODE_GEN_RETRIES do
		local code = generateCode()
		local ok, err = pcall(function()
			local hash = MemoryStoreService:GetHashMap(CODES_HASH_NAME)
			-- UpdateAsync returns the previous value; if nil, we won the slot.
			-- If non-nil, the slot was taken — return nil to abort the update.
			local won = false
			hash:UpdateAsync(code, function(existing)
				if existing == nil then
					won = true
					return payload
				end
				return nil    -- abort: don't overwrite
			end, CODE_TTL)
			return won
		end)
		if not ok then
			return nil, tostring(err)
		end
		-- pcall captured the closure; check the hash via a follow-up Get to
		-- confirm we actually claimed it. Simpler than threading the boolean
		-- back out of the closure across pcall boundary.
		local readOk, value = pcall(function()
			local hash = MemoryStoreService:GetHashMap(CODES_HASH_NAME)
			return hash:GetAsync(code)
		end)
		if readOk and typeof(value) == "table" and (value :: any).hostUserId == payload.hostUserId then
			return code, nil
		end
	end
	return nil, "Failed to generate unique code after retries"
end

local function lookupCode(code: string): (StoredCode?, string?)
	local ok, value = pcall(function()
		local hash = MemoryStoreService:GetHashMap(CODES_HASH_NAME)
		return hash:GetAsync(code)
	end)
	if not ok then
		return nil, tostring(value)
	end
	if typeof(value) ~= "table" then
		return nil, "Code not found"
	end
	local v = value :: any
	if typeof(v.accessCode) ~= "string" or typeof(v.privateServerId) ~= "string" then
		return nil, "Code entry malformed"
	end
	local withBots = if typeof(v.withBots) == "boolean" then v.withBots else DEFAULT_WITH_BOTS
	local maxPlayers = DEFAULT_MAX_PLAYERS
	if typeof(v.maxPlayers) == "number" then
		local mp = math.floor(v.maxPlayers)
		if mp < MIN_MAX_PLAYERS then mp = MIN_MAX_PLAYERS end
		if mp > MAX_MAX_PLAYERS then mp = MAX_MAX_PLAYERS end
		maxPlayers = mp
	end
	return {
		accessCode = v.accessCode,
		privateServerId = v.privateServerId,
		hostUserId = typeof(v.hostUserId) == "number" and v.hostUserId or 0,
		createdAt = typeof(v.createdAt) == "number" and v.createdAt or os.time(),
		withBots = withBots,
		maxPlayers = maxPlayers,
	}, nil
end

-- Sanitize user-typed code (uppercase, strip whitespace/dashes). Be liberal
-- in what we accept since players will type these from chat / voice.
local function normalizeCode(raw: any): string?
	if typeof(raw) ~= "string" then return nil end
	local cleaned = string.upper(raw):gsub("[%s%-]", "")
	if #cleaned == 0 or #cleaned > 16 then return nil end
	return cleaned
end

-- ============================================================================
-- CreatePrivateLobby
-- ============================================================================
-- Signature: Remotes.CreatePrivateLobby:InvokeServer(config?)
--   config = { withBots: boolean, maxPlayers: number } (both optional)
-- Old call-sites with no args still work — `normalizeConfig` returns defaults
-- (withBots=true, maxPlayers=20) for any non-table or partial payload.
Remotes.CreatePrivateLobby.OnServerInvoke = function(player: Player, rawConfig: any): CreateResult
	local config = normalizeConfig(rawConfig)

	-- Step 1: reserve a server slot from Roblox.
	local reserveOk, accessCode, privateServerId = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not reserveOk then
		return { ok = false, error = "Failed to reserve server: " .. tostring(accessCode) }
	end
	if typeof(accessCode) ~= "string" or typeof(privateServerId) ~= "string" then
		return { ok = false, error = "ReserveServer returned unexpected shape" }
	end

	-- Step 2: claim a unique code mapping in MemoryStore.
	local payload: StoredCode = {
		accessCode = accessCode :: string,
		privateServerId = privateServerId :: string,
		hostUserId = player.UserId,
		createdAt = os.time(),
		withBots = config.withBots,
		maxPlayers = config.maxPlayers,
	}
	local code, claimErr = claimUniqueCode(payload)
	if not code then
		-- In Studio test MemoryStore fails entirely. We still have a reserved
		-- accessCode from Roblox (when network up) but no way to share it,
		-- so surface the error rather than half-create a lobby.
		return { ok = false, error = "Code storage unavailable: " .. tostring(claimErr) }
	end

	hostUserIdToCode[player.UserId] = code

	-- Step 3: teleport the host to their new reserved server. We forward the
	-- lobby config via TeleportData so the receiving server can read it on
	-- PlayerAdded and stamp it onto Workspace attributes. Fire-and-forget;
	-- if the teleport fails the client will surface TeleportInitFailed and
	-- can retry via JoinSessionByCode (which also forwards the config).
	task.spawn(function()
		local teleOk, teleErr = pcall(function()
			local teleportData = {
				withBots = config.withBots,
				maxPlayers = config.maxPlayers,
			}
			TeleportService:TeleportToPrivateServer(
				game.PlaceId,
				accessCode :: string,
				{ player },
				nil,
				teleportData
			)
		end)
		if not teleOk then
			warn(string.format("[PrivateLobby] Host teleport failed for %s: %s", player.Name, tostring(teleErr)))
		end
	end)

	return { ok = true, code = code }
end

-- ============================================================================
-- JoinSessionByCode
-- ============================================================================
Remotes.JoinSessionByCode.OnServerInvoke = function(player: Player, rawCode: any): JoinResult
	local code = normalizeCode(rawCode)
	if not code then
		return { ok = false, error = "Invalid code format" }
	end
	local entry, err = lookupCode(code)
	if not entry then
		-- Distinguish "store unavailable" (Studio test) from "real miss" so
		-- the client UI can show a useful message.
		if err and err ~= "Code not found" then
			return { ok = false, error = "Lookup failed: " .. err }
		end
		return { ok = false, error = "Code not found" }
	end

	-- Teleport caller into the reserved server. Forward the stored config as
	-- TeleportData so the receiving server can stamp Workspace attributes
	-- consistently for joiners too (host already does this on their teleport).
	local teleOk, teleErr = pcall(function()
		local teleportData = {
			withBots = entry.withBots,
			maxPlayers = entry.maxPlayers,
		}
		TeleportService:TeleportToPrivateServer(
			game.PlaceId,
			entry.accessCode,
			{ player },
			nil,
			teleportData
		)
	end)
	if not teleOk then
		return { ok = false, error = "Teleport failed: " .. tostring(teleErr) }
	end
	return { ok = true }
end

-- ============================================================================
-- LeavePrivateLobby
-- ============================================================================
-- Mostly a no-op from MemoryStore's perspective: the entry expires on its own
-- after CODE_TTL. We just clear our local index so a host who created and
-- abandoned a lobby on the same server can create a fresh one without confusion.
Remotes.LeavePrivateLobby.OnServerInvoke = function(player: Player): LeaveResult
	hostUserIdToCode[player.UserId] = nil
	return { ok = true }
end

-- ============================================================================
-- Receive lobby config on the reserved server side
-- ============================================================================
-- When players teleport INTO a private server we read the TeleportData payload
-- they brought with them (set by CreatePrivateLobby / JoinSessionByCode above)
-- and stamp the lobby config onto Workspace attributes. Other services
-- (DeathmatchBotService etc.) read those attributes to honor host preferences
-- without having to reach into PrivateLobbyService directly.
--
-- All teleported players bring the same config along, but we only need to
-- set the attribute once per server life — guarded with a flag. If for some
-- reason the first player arrived with malformed/no data we still try the
-- next arriving player.
local IS_PRIVATE_SERVER_BOOT = game.PrivateServerId ~= ""
local lobbyConfigApplied = false

local function applyTeleportDataToWorkspace(player: Player)
	if not IS_PRIVATE_SERVER_BOOT then return end
	if lobbyConfigApplied then return end
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then return end
	local teleportData = (joinData :: any).TeleportData
	if typeof(teleportData) ~= "table" then return end
	local cfg = normalizeConfig(teleportData)
	Workspace:SetAttribute("WithBots", cfg.withBots)
	Workspace:SetAttribute("MaxPlayers", cfg.maxPlayers)
	lobbyConfigApplied = true
	print(string.format(
		"[PrivateLobby] Applied lobby config from %s — WithBots=%s, MaxPlayers=%d",
		player.Name, tostring(cfg.withBots), cfg.maxPlayers
	))
end

if IS_PRIVATE_SERVER_BOOT then
	Players.PlayerAdded:Connect(applyTeleportDataToWorkspace)
	-- Also handle any player who joined before this service registered.
	for _, p in Players:GetPlayers() do
		task.spawn(applyTeleportDataToWorkspace, p)
	end
end

-- Public API for sibling services / tests.
function PrivateLobbyService.GenerateCodeForTest(): string
	return generateCode()
end

function PrivateLobbyService.NormalizeCodeForTest(raw: any): string?
	return normalizeCode(raw)
end

function PrivateLobbyService.GetHostCode(userId: number): string?
	return hostUserIdToCode[userId]
end

return PrivateLobbyService
