--!strict
-- SessionAdvertiser
--
-- Every 8 seconds, publish this server's state (jobId, map, match state, player
-- count, capacity, kind) into a MemoryStoreService SortedMap so the global
-- session directory can list it. 30-second TTL means dead/crashed servers age
-- out automatically without us having to clean anything up.
--
-- Private (reserved) servers don't advertise — they're joined via access code
-- through PrivateLobbyService, not the public browser.
--
-- All MemoryStore calls are pcall-wrapped: Studio test sessions don't have
-- MemoryStore access, so we silently no-op instead of spamming warnings.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MatchStateService = require(script.Parent.MatchStateService)

local SessionAdvertiser = {}

local SESSION_MAP_NAME = "RoblokFPS_Sessions"
local PUBLISH_INTERVAL = 8           -- seconds between heartbeats
local ENTRY_TTL = 30                 -- seconds until entry expires from MemoryStore
local TARGET_PLAYER_COUNT = 21       -- mirrors DeathmatchBotService cap

-- A reserved (or VIP) server has a non-empty PrivateServerId. We tag private
-- servers differently and skip advertising so they don't show up in the public
-- browser. Reserved-via-TeleportService and VIP servers both flag here, which
-- is what we want: neither should be publicly listable.
local function isPrivate(): boolean
	return game.PrivateServerId ~= nil and game.PrivateServerId ~= ""
end

local function getMapId(): string
	local arena = Workspace:FindFirstChild("ActiveArena")
	if arena then
		local id = arena:GetAttribute("mapId")
		if typeof(id) == "string" and id ~= "" then
			return id
		end
	end
	return "lobby"
end

local function buildPayload(): { [string]: any }
	local payload = MatchStateService.GetState()
	return {
		jobId = game.JobId,
		mapId = getMapId(),
		state = payload.state,
		gamemode = payload.gamemode or "deathmatch",
		players = #Players:GetPlayers(),
		max = TARGET_PLAYER_COUNT,
		kind = isPrivate() and "private" or "public",
		at = os.time(),
	}
end

-- Single publish. Logs at most once per failure category to avoid spam.
local warnedNoMemoryStore = false

local function publish(): boolean
	if isPrivate() then
		-- Private servers don't advertise; the host's PrivateLobbyService entry
		-- in the Codes hashmap is the only way in.
		return false
	end
	-- JobId is empty in Studio edit + test mode. Without a unique key, MemoryStore
	-- would either reject the call or overwrite a shared sentinel across all
	-- sessions. Skip silently — Studio Test is for unit-level testing, not for
	-- cross-server lobby flow.
	if game.JobId == nil or game.JobId == "" then
		return false
	end
	local ok, err = pcall(function()
		local map = MemoryStoreService:GetSortedMap(SESSION_MAP_NAME)
		map:SetAsync(game.JobId, buildPayload(), ENTRY_TTL)
	end)
	if not ok then
		if not warnedNoMemoryStore then
			warnedNoMemoryStore = true
			warn(string.format("[SessionAdvertiser] MemoryStore unavailable: %s", tostring(err)))
		end
		return false
	end
	return true
end

-- Heartbeat loop. Wrapped in task.spawn so it runs alongside the match cycle.
-- IMMEDIATE first publish so the server appears in the browser within ~0s of
-- boot rather than ~2-10s (previously: random 0-2s jitter + 8s heartbeat). The
-- jitter was protecting MemoryStore from a thundering-herd at fleet-wide boot,
-- but the cost is the very first solo Studio Test session looks invisible for
-- 8 seconds — which is exactly the user complaint we're fixing.
task.spawn(function()
	publish()
	while true do
		task.wait(PUBLISH_INTERVAL)
		publish()
	end
end)

-- Republish on every match state change so the browser reflects LOBBY → VOTING
-- → STARTING → MATCH → ENDING transitions promptly (otherwise a server stuck
-- in ENDING for up to 8s would still look joinable, and a server that just
-- entered LOBBY would still show ENDING for up to 8s). MatchStateService is
-- the source of truth.
task.spawn(function()
	-- Lazy require to dodge any chance of load-order issues with sibling services.
	local ok, MSS = pcall(require, script.Parent.MatchStateService)
	if not ok or not MSS or not MSS.StateChanged then return end
	MSS.StateChanged:Connect(function()
		task.defer(publish)
	end)
end)

-- When the last player leaves, push one final update with players=0 so the
-- directory reflects empty servers quickly (don't wait for the 8s heartbeat).
-- This makes party-rejoin scenarios feel instant.
Players.PlayerRemoving:Connect(function()
	-- PlayerRemoving fires BEFORE the player is removed from :GetPlayers(),
	-- so a "last player leaving" check needs to subtract 1.
	if #Players:GetPlayers() - 1 <= 0 then
		task.defer(publish)
	end
end)

-- BindToClose: best-effort final publish so the entry doesn't linger 30s past
-- shutdown. Roblox gives us up to 30s here in production servers.
game:BindToClose(function()
	if isPrivate() then return end
	if game.JobId == nil or game.JobId == "" then return end
	pcall(function()
		local map = MemoryStoreService:GetSortedMap(SESSION_MAP_NAME)
		-- Best effort: a 5-second TTL forces fast expiry vs RemoveAsync which can
		-- be slower / fail mid-shutdown. Either way, dead entry ages out.
		map:SetAsync(game.JobId, { state = "ENDING", players = 0, at = os.time() }, 5)
	end)
end)

-- Public API (used by tests / debug; SessionDirectory reads MemoryStore directly).
function SessionAdvertiser.PublishNow(): boolean
	return publish()
end

function SessionAdvertiser.IsPrivate(): boolean
	return isPrivate()
end

function SessionAdvertiser.BuildPayloadForTest(): { [string]: any }
	return buildPayload()
end

return SessionAdvertiser
