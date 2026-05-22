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
	-- lobby config + access code via TeleportData so the receiving server can
	-- read it on PlayerAdded and stamp it onto Workspace attributes. The
	-- `code` field is what makes the host's modal stay in Stage B post-teleport
	-- (otherwise their PrivateLobbyController loses state and re-renders
	-- Stage A "Create" — the exact "code flashes then disappears" bug we're
	-- fixing). Fire-and-forget; if the teleport fails the client will surface
	-- TeleportInitFailed and can retry via JoinSessionByCode.
	--
	-- We also defer the teleport by a frame so the InvokeServer return value
	-- (the `code`) has a chance to reach the client BEFORE the teleport begins
	-- to tear down their controller state. This is belt-and-suspenders on top
	-- of the TeleportData mechanism.
	task.spawn(function()
		task.wait(0.1)
		local teleOk, teleErr = pcall(function()
			local teleportData = {
				code = code,
				accessCode = accessCode,
				withBots = config.withBots,
				maxPlayers = config.maxPlayers,
				hostUserId = player.UserId,
				isHost = true,
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

	-- Teleport caller into the reserved server. Forward the stored config +
	-- the code itself as TeleportData so the receiving server can stamp
	-- Workspace attributes consistently for joiners (host already does this on
	-- their teleport). Joiners need the code too so the lobby UI shows it
	-- prominently — they typed it in, but if they re-open the lobby modal
	-- from in-game we want it visible without a round-trip.
	local teleOk, teleErr = pcall(function()
		local teleportData = {
			code = code,
			accessCode = entry.accessCode,
			withBots = entry.withBots,
			maxPlayers = entry.maxPlayers,
			hostUserId = entry.hostUserId,
			isHost = false,
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
-- Equally important: we set `InPrivateServer=true` + `PrivateServerCode=<code>`
-- on the Workspace so client controllers (PrivateLobbyController, MainMenu)
-- can render the "you're in a private lobby" UX (badge, auto-open Stage B,
-- dim buttons that would teleport you away). Without these the host arrives
-- at the reserved server with NO indication that anything special happened —
-- which is the "code flashes then disappears" bug from the user's POV.
--
-- All teleported players bring the same config along, but we only need to
-- set the WithBots/MaxPlayers attributes once per server life — guarded with
-- a flag. The InPrivateServer/PrivateServerCode attributes are set once and
-- never change for the lifetime of the reserved server.
local IS_PRIVATE_SERVER_BOOT = game.PrivateServerId ~= ""
local lobbyConfigApplied = false
local privateServerCode: string? = nil

-- Tracked member list for this reserved server. Updated on PlayerAdded /
-- PlayerRemoving and broadcast via Remotes.PrivateLobbyUpdate so every client
-- in the lobby sees a live roster + the shared code.
local memberReady: { [number]: boolean } = {}

-- Resolve who the "host" is for the current server. In a published
-- reserved server this comes from TeleportData (stamped on Workspace).
-- In Studio test mode (or any unset case) we fall back to "first player
-- in the server" so the lobby still has a clear host who can click START.
local function getHostUserId(): number?
	local attrHost = Workspace:GetAttribute("PrivateServerHostUserId")
	if typeof(attrHost) == "number" then return attrHost end
	local players = Players:GetPlayers()
	if #players > 0 then return players[1].UserId end
	return nil
end

local function buildMembersPayload(): { { userId: number, name: string, ready: boolean } }
	local out: { { userId: number, name: string, ready: boolean } } = {}
	local hostId = getHostUserId()
	for _, p in Players:GetPlayers() do
		-- Host is implicitly ready (they're the one driving the lobby — they
		-- click START rather than READY). Non-host members must toggle ready
		-- explicitly via PrivateLobbyReady.
		local isHost = hostId == p.UserId
		table.insert(out, {
			userId = p.UserId,
			name = p.Name,
			ready = isHost or memberReady[p.UserId] == true,
		})
	end
	return out
end

local function broadcastLobbyUpdate()
	-- Was gated on IS_PRIVATE_SERVER_BOOT — that hid the lobby state in
	-- Studio test mode (where game.PrivateServerId is always ""), making
	-- the START button stuck-disabled because clients never received the
	-- members payload. Always broadcast: clients that aren't in a private
	-- lobby just ignore (their UI keeps InPrivateServer=false visible state).
	local payload = {
		code = privateServerCode,
		hostUserId = getHostUserId(),
		members = buildMembersPayload(),
	}
	pcall(function()
		Remotes.PrivateLobbyUpdate:FireAllClients(payload)
	end)
end

local function applyTeleportDataToWorkspace(player: Player)
	if not IS_PRIVATE_SERVER_BOOT then return end
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then return end
	local teleportData = (joinData :: any).TeleportData
	if typeof(teleportData) ~= "table" then
		-- No teleport data: still publish a basic InPrivateServer flag so the
		-- client UI knows where it is, even without a code.
		if Workspace:GetAttribute("InPrivateServer") ~= true then
			Workspace:SetAttribute("InPrivateServer", true)
		end
		return
	end
	-- Apply WithBots/MaxPlayers (once per server) from the first valid payload.
	if not lobbyConfigApplied then
		local cfg = normalizeConfig(teleportData)
		Workspace:SetAttribute("WithBots", cfg.withBots)
		Workspace:SetAttribute("MaxPlayers", cfg.maxPlayers)
		lobbyConfigApplied = true
		print(string.format(
			"[PrivateLobby] Applied lobby config from %s — WithBots=%s, MaxPlayers=%d",
			player.Name, tostring(cfg.withBots), cfg.maxPlayers
		))
	end
	-- Stamp the code/host info onto Workspace so any client (or service) can
	-- discover the lobby state without round-tripping the server.
	if typeof((teleportData :: any).code) == "string" and Workspace:GetAttribute("PrivateServerCode") == nil then
		privateServerCode = (teleportData :: any).code
		Workspace:SetAttribute("PrivateServerCode", privateServerCode)
	end
	if typeof((teleportData :: any).hostUserId) == "number" and Workspace:GetAttribute("PrivateServerHostUserId") == nil then
		Workspace:SetAttribute("PrivateServerHostUserId", (teleportData :: any).hostUserId)
	end
	if Workspace:GetAttribute("InPrivateServer") ~= true then
		Workspace:SetAttribute("InPrivateServer", true)
		-- Pause the LOBBY→VOTING auto-advance until host explicitly clicks
		-- START MATCH. Otherwise the standard 2s LOBBY timer fires and the
		-- party-lobby state is gone before anyone is ready.
		pcall(function()
			local MSS = require(script.Parent.MatchStateService)
			MSS.HoldAutoAdvance(true)
			print("[PrivateLobby] Held MatchState auto-advance — waiting for host START")
		end)
	end
end

-- Always register the lobby handlers (gate removed). In Studio test the
-- TeleportData / Workspace attr flow is inert but the member tracking +
-- broadcasts still need to run so the START button can light up.
do
	Players.PlayerAdded:Connect(function(p: Player)
		applyTeleportDataToWorkspace(p)
		memberReady[p.UserId] = memberReady[p.UserId] == true
		-- Fire on next frame so the client's PrivateLobbyController has finished
		-- mounting + connected its OnClientEvent handler before we send.
		task.defer(broadcastLobbyUpdate)
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		memberReady[p.UserId] = nil
		task.defer(broadcastLobbyUpdate)
	end)
	-- Also handle any player who joined before this service registered.
	for _, p in Players:GetPlayers() do
		task.spawn(function()
			applyTeleportDataToWorkspace(p)
			memberReady[p.UserId] = memberReady[p.UserId] == true
			task.defer(broadcastLobbyUpdate)
		end)
	end
	-- Listen for client-side ready toggles (Remotes.PrivateLobbyReady fires
	-- (bool)). We just record + rebroadcast — actual "start match" gating
	-- happens in the PrivateLobbyStart handler below.
	-- Hold the match-state cycle once we know a player is in lobby flow.
	-- This makes the START button work in Studio test (where the public
	-- server otherwise cycles freely through LOBBY→VOTING→...). One-shot.
	local autoHoldFired = false
	local function maybeHoldCycle()
		if autoHoldFired then return end
		autoHoldFired = true
		pcall(function()
			local MSS = require(script.Parent.MatchStateService)
			MSS.HoldAutoAdvance(true)
			-- Bring the cycle back to LOBBY so the host can choose when to
			-- start. AdvanceTo is a hard set, fine to call from any state.
			if MSS.GetCurrentState() ~= "LOBBY" then
				MSS.AdvanceTo("LOBBY")
			end
			print("[PrivateLobby] Auto-held cycle at LOBBY for private lobby flow")
		end)
	end
	pcall(function()
		Remotes.PrivateLobbyReady.OnServerEvent:Connect(function(p: Player, ready: any)
			memberReady[p.UserId] = ready == true
			maybeHoldCycle()
			broadcastLobbyUpdate()
		end)
	end)

	-- HOST CLICKS START MATCH → fast-forward the match state machine to
	-- VOTING so the round begins. Validates: caller is host, ≥1 member, all
	-- members ready. If gates pass, force-advance via MatchStateService.
	pcall(function()
		Remotes.PrivateLobbyStart.OnServerEvent:Connect(function(p: Player)
			-- Caller must be the host. In Studio test (no Workspace attr set
			-- because there's no real teleport), fall back to "first player
			-- in the server is the host" so the flow still works.
			local hostId = getHostUserId()
			if hostId and hostId ~= p.UserId then
				print(string.format(
					"[PrivateLobby] %s tried to start match but is not host (host=%s)",
					p.Name, tostring(hostId)
				))
				return
			end
			-- All members must be ready before we kick the round off.
			-- Host is implicitly "ready by clicking START" — count them too.
			local players = Players:GetPlayers()
			if #players == 0 then return end
			for _, member in players do
				local isHost = member.UserId == p.UserId
				if not isHost and memberReady[member.UserId] ~= true then
					print(string.format(
						"[PrivateLobby] Cannot start — %s not ready",
						member.Name
					))
					return
				end
			end
			-- Gate the current state: only advance from LOBBY (the natural
			-- starting state in a fresh reserved server).
			local okMSS, MatchStateService = pcall(require, script.Parent.MatchStateService)
			if not okMSS then
				warn("[PrivateLobby] MatchStateService unavailable")
				return
			end
			-- Accept any state except active MATCH (where the host clicking
			-- "start" doesn't make sense — combat is already running).
			-- LOBBY/ENDING → AdvanceTo("VOTING") (full cycle).
			-- VOTING → AdvanceTo("STARTING") (skip the map vote).
			-- STARTING → ignore (match is about to start anyway).
			-- MATCH → ignore (already mid-match).
			local current = MatchStateService.GetCurrentState()
			if current == "MATCH" or current == "STARTING" then
				print(string.format(
					"[PrivateLobby] Start ignored — match already in state %s",
					tostring(current)
				))
				return
			end
			print(string.format(
				"[PrivateLobby] Host %s started match (was state=%s) with %d members",
				p.Name, tostring(current), #players
			))
			-- Release the auto-advance hold so the cycle flows normally
			-- from whatever state we transition into.
			MatchStateService.HoldAutoAdvance(false)
			if current == "VOTING" then
				-- Skip ahead — host doesn't want to wait for vote timer.
				MatchStateService.AdvanceTo("STARTING")
			else
				-- LOBBY / ENDING / anything else → fresh cycle through voting.
				MatchStateService.AdvanceTo("VOTING")
			end
		end)
	end)
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
