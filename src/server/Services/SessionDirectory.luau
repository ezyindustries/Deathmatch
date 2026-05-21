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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

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

-- Fake stub list for Studio Test where MemoryStore is unavailable. Lets the
-- client UI render real-looking rows so the developer can iterate on layout
-- without needing a published game.
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

local function refresh(): { SessionRow }
	local now = os.clock()
	if (now - cachedAt) < CACHE_TTL and #cachedRows > 0 then
		return cachedRows
	end
	local rows, ok = fetchFromMemoryStore()
	if not ok then
		-- MemoryStore unavailable (Studio Test). Return stub data so UI work
		-- isn't blocked by infrastructure. Cache it too so we don't spam
		-- failing pcalls every request.
		cachedRows = buildStubRows()
		cachedAt = now
		cacheUsingStub = true
		return cachedRows
	end
	cachedRows = rows
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
