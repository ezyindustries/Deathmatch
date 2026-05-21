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
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

local PrivateLobbyService = {}

local CODES_HASH_NAME = "RoblokFPS_Codes"
local CODE_TTL = 1800            -- 30 minutes
local CODE_LENGTH = 6
local CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   -- no 0/O/I/l/1
local CODE_GEN_RETRIES = 5       -- if generated code collides with existing key, retry

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
}

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
	return {
		accessCode = v.accessCode,
		privateServerId = v.privateServerId,
		hostUserId = typeof(v.hostUserId) == "number" and v.hostUserId or 0,
		createdAt = typeof(v.createdAt) == "number" and v.createdAt or os.time(),
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
Remotes.CreatePrivateLobby.OnServerInvoke = function(player: Player): CreateResult
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
	}
	local code, claimErr = claimUniqueCode(payload)
	if not code then
		-- In Studio test MemoryStore fails entirely. We still have a reserved
		-- accessCode from Roblox (when network up) but no way to share it,
		-- so surface the error rather than half-create a lobby.
		return { ok = false, error = "Code storage unavailable: " .. tostring(claimErr) }
	end

	hostUserIdToCode[player.UserId] = code

	-- Step 3: teleport the host to their new reserved server. Fire-and-forget;
	-- if the teleport fails the client will surface a TeleportInitFailed error
	-- and can retry via JoinSessionByCode using the returned code.
	task.spawn(function()
		local teleOk, teleErr = pcall(function()
			TeleportService:TeleportToPrivateServer(
				game.PlaceId,
				accessCode :: string,
				{ player }
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

	-- Teleport caller into the reserved server.
	local teleOk, teleErr = pcall(function()
		TeleportService:TeleportToPrivateServer(
			game.PlaceId,
			entry.accessCode,
			{ player }
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
