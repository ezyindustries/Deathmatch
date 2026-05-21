--!strict
-- SessionDirectory
--
-- Handles the ListPublicSessions RemoteFunction. Reads the global MemoryStore
-- SortedMap that SessionAdvertiser populates, filters out unjoinable entries
-- (private, ending, full), and returns a list the client server-browser UI
-- can render.
--
-- Server-side caching: even if 10 players hit the browser button simultaneously,
-- we only hit MemoryStore once per 3 seconds. Cheap protection against
-- accidental request storms.
--
-- Studio Test fallback: MemoryStore throws there, so we return a small stub
-- list of fake sessions so the UI can be developed/tested without a live game.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

-- Lazy require to dodge load-order issues (MatchStateService may not be
-- initialized yet when this module first runs).
local function getMatchStateService()
	local ok, mss = pcall(require, script.Parent.MatchStateService)
	if ok then return mss end
	return nil
end

local SessionDirectory = {}

local SESSION_MAP_NAME = "RoblokFPS_Sessions"
local CACHE_TTL = 3              -- seconds between MemoryStore reads
local MAX_RETURNED = 50          -- never return more than this to a client

export type SessionRow = {
	jobId: string,
	mapId: string,
	state: string,
	gamemode: string?,
	players: number,
	max: number,
	kind: string,
	at: number,
}

-- Cache state
local cachedRows: { SessionRow } = {}
local cachedAt: number = 0
local cacheUsingStub: boolean = false

-- Build a row representing THIS server, based on live MatchStateService data.
-- Returns nil if this server is private (PrivateServerId set) — private servers
-- should never appear in the public browser.
--
-- Used in two places:
--   1. As fallback when MemoryStore is unavailable (Studio Test) — without this
--      a developer testing locally would see ZERO servers in the browser even
--      though the very server they're on is fully joinable.
--   2. Always merged in alongside MemoryStore results so a developer with two
--      Studio Test sessions open (or a brand-new published server whose
--      MemoryStore entry hasn't yet propagated) still sees themselves.
local function buildLocalRow(): SessionRow?
	-- Private/VIP servers never advertise.
	if game.PrivateServerId ~= nil and game.PrivateServerId ~= "" then
		return nil
	end
	local mss = getMatchStateService()
	local state = "LOBBY"
	local gamemode: string? = "deathmatch"
	if mss then
		local ok, payload = pcall(mss.GetState)
		if ok and typeof(payload) == "table" then
			if typeof(payload.state) == "string" then state = payload.state end
			if typeof(payload.gamemode) == "string" then gamemode = payload.gamemode end
		end
	end
	-- Derive mapId from ActiveArena attribute (mirrors SessionAdvertiser).
	local mapId = "lobby"
	local arena = Workspace:FindFirstChild("ActiveArena")
	if arena then
		local id = arena:GetAttribute("mapId")
		if typeof(id) == "string" and id ~= "" then
			mapId = id
		end
	end
	-- JobId is "" in Studio Test. We still want to advertise the local server,
	-- but we need *something* unique-looking. Use a stable Studio sentinel.
	local jobId = game.JobId
	if jobId == nil or jobId == "" then
		jobId = "studio-local-session"
	end
	return {
		jobId = jobId,
		mapId = mapId,
		state = state,
		gamemode = gamemode,
		players = #Players:GetPlayers(),
		max = 21,
		kind = "public",
		at = os.time(),
	}
end

-- Fake stub list for Studio Test where MemoryStore is unavailable. Lets the
-- client UI render real-looking rows so the developer can iterate on layout
-- without needing a published game. The LOCAL server row is added separately
-- via buildLocalRow() so it always shows up first (and is actually joinable).
local function buildStubRows(): { SessionRow }
	local now = os.time()
	return {
		{
			jobId = "stub-job-id-001",
			mapId = "metro",
			state = "MATCH",
			gamemode = "deathmatch",
			players = 14,
			max = 21,
			kind = "public",
			at = now,
		},
		{
			jobId = "stub-job-id-002",
			mapId = "warehouse",
			state = "LOBBY",
			gamemode = "deathmatch",
			players = 3,
			max = 21,
			kind = "public",
			at = now,
		},
		{
			jobId = "stub-job-id-003",
			mapId = "harbor",
			state = "VOTING",
			gamemode = "deathmatch",
			players = 9,
			max = 21,
			kind = "public",
			at = now,
		},
	}
end

-- Decode an entry from MemoryStore. Defensive — entries from older server
-- versions might be missing fields. We coerce + default rather than reject.
local function coerceRow(raw: any): SessionRow?
	if typeof(raw) ~= "table" then return nil end
	local jobId = raw.jobId
	if typeof(jobId) ~= "string" or jobId == "" then return nil end
	local mapId = typeof(raw.mapId) == "string" and raw.mapId or "unknown"
	local state = typeof(raw.state) == "string" and raw.state or "LOBBY"
	local players = typeof(raw.players) == "number" and raw.players or 0
	local max = typeof(raw.max) == "number" and raw.max or 21
	local kind = typeof(raw.kind) == "string" and raw.kind or "public"
	local gamemode = typeof(raw.gamemode) == "string" and raw.gamemode or nil
	local at = typeof(raw.at) == "number" and raw.at or os.time()
	return {
		jobId = jobId,
		mapId = mapId,
		state = state,
		gamemode = gamemode,
		players = players,
		max = max,
		kind = kind,
		at = at,
	}
end

local function isJoinable(row: SessionRow): boolean
	if row.kind ~= "public" then return false end
	if row.state == "ENDING" then return false end
	if row.players >= row.max then return false end
	return true
end

-- Read fresh data from MemoryStore. Returns (rows, ok). On error, `ok` is false
-- and rows is empty — caller falls back to stub data.
local function fetchFromMemoryStore(): ({ SessionRow }, boolean)
	local rows: { SessionRow } = {}
	local ok, result = pcall(function()
		local map = MemoryStoreService:GetSortedMap(SESSION_MAP_NAME)
		return map:GetRangeAsync(Enum.SortDirection.Descending, MAX_RETURNED)
	end)
	if not ok then
		return rows, false
	end
	if typeof(result) ~= "table" then
		return rows, true
	end
	for _, entry in (result :: any) do
		-- Entries come back as { key, value, sortKey? } in newer Roblox APIs,
		-- or sometimes just the value directly in older docs. Try both shapes.
		local value = (entry :: any).value or entry
		local row = coerceRow(value)
		if row then
			table.insert(rows, row)
		end
	end
	return rows, true
end

-- Merge the LOCAL server's row into a fetched list, replacing any existing
-- entry with the same jobId (because MemoryStore's view of us may be stale by
-- up to 8s). Skip if we're a private server. Always insert at the front so
-- the user's own server is the first thing they see in the browser.
local function mergeLocalRow(rows: { SessionRow }): { SessionRow }
	local local_ = buildLocalRow()
	if not local_ then return rows end
	local out: { SessionRow } = { local_ }
	for _, r in rows do
		if r.jobId ~= local_.jobId then
			table.insert(out, r)
		end
	end
	return out
end

local function refresh(): { SessionRow }
	local now = os.clock()
	if (now - cachedAt) < CACHE_TTL and #cachedRows > 0 then
		return cachedRows
	end
	local rows, ok = fetchFromMemoryStore()
	if not ok then
		-- MemoryStore unavailable (Studio Test). Return stub data so UI work
		-- isn't blocked by infrastructure, PLUS the local server row so a
		-- developer running solo Studio sees their own server as joinable.
		-- Cache the merged result so we don't spam failing pcalls.
		cachedRows = mergeLocalRow(buildStubRows())
		cachedAt = now
		cacheUsingStub = true
		return cachedRows
	end
	-- MemoryStore worked. Still merge in the LOCAL row because:
	--   * Our own MemoryStore entry takes up to PUBLISH_INTERVAL (8s) to refresh,
	--     so a player who just hit REFRESH would see a stale snapshot of us.
	--   * In a brand-new server the first publish may not have landed yet.
	cachedRows = mergeLocalRow(rows)
	cachedAt = now
	cacheUsingStub = false
	return cachedRows
end

-- Filter applied at request time (NOT cache time) so a player's view is always
-- consistent with current capacity rules even if the cache is still warm.
local function filterJoinable(rows: { SessionRow }): { SessionRow }
	local filtered: { SessionRow } = {}
	for _, row in rows do
		if isJoinable(row) then
			table.insert(filtered, row)
		end
	end
	return filtered
end

-- RemoteFunction handler. Players call this from the server browser UI.
Remotes.ListPublicSessions.OnServerInvoke = function(_player: Player): { SessionRow }
	local rows = refresh()
	return filterJoinable(rows)
end

-- Public API for sibling services (JoinByCodeService validates jobIds against
-- the directory rather than trusting client input).
function SessionDirectory.GetJoinableSessions(): { SessionRow }
	return filterJoinable(refresh())
end

function SessionDirectory.FindByJobId(jobId: string): SessionRow?
	if typeof(jobId) ~= "string" or jobId == "" then return nil end
	for _, row in refresh() do
		if row.jobId == jobId then
			return row
		end
	end
	return nil
end

function SessionDirectory.IsUsingStub(): boolean
	return cacheUsingStub
end

-- Test helper — flush cache so a subsequent call re-reads.
function SessionDirectory.InvalidateCache()
	cachedAt = 0
	cachedRows = {}
end

return SessionDirectory
