--!strict
-- JoinByCodeService
--
-- Handles JoinSessionByJobId — when a player picks a specific running server
-- from the SessionDirectory-backed server browser, this teleports them into
-- that exact game instance via TeleportService:TeleportToPlaceInstance.
--
-- Trust boundary: the client passes the jobId it wants to join, but we
-- re-validate against the current SessionDirectory snapshot. Reasons:
--   1. Client could send a stale jobId for a server that's now full/ended
--   2. Client could send a fake jobId hoping to crash the teleport flow
--   3. Client could try to join private servers via JobId — those should
--      only be reachable through PrivateLobbyService's accessCode path
--
-- The directory's `kind="public"` + `players<max` + `state!=ENDING` filter
-- runs against the cached snapshot, so worst-case the player attempts a join
-- against a session that JUST filled up — TeleportService will then surface
-- a "server is full" error on the client side, which is fine.

local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

-- Lazy require: SessionDirectory may not be loaded yet when this service first
-- runs. ServerScriptService.Server.Services iteration order isn't deterministic,
-- and lazy-require dodges any chance of circular load.
local function getDirectory()
	return require(script.Parent.SessionDirectory)
end

local JoinByCodeService = {}

export type JoinResult = {
	ok: boolean,
	error: string?,
}

local function validateJobId(raw: any): string?
	if typeof(raw) ~= "string" then return nil end
	if raw == "" then return nil end
	if #raw > 64 then return nil end    -- JobIds are ~36 chars (UUID-ish), reject pathological inputs
	return raw
end

Remotes.JoinSessionByJobId.OnServerInvoke = function(player: Player, rawJobId: any): JoinResult
	local jobId = validateJobId(rawJobId)
	if not jobId then
		return { ok = false, error = "Invalid jobId" }
	end

	-- Trying to teleport to the server we're currently on is a no-op / error.
	if jobId == game.JobId then
		return { ok = false, error = "Already on that server" }
	end

	-- Re-check the directory: is this jobId currently a public, joinable session?
	local directory = getDirectory()
	local row = directory.FindByJobId(jobId)
	if not row then
		return { ok = false, error = "Server full or doesn't exist" }
	end
	if row.kind ~= "public" then
		return { ok = false, error = "That server is private" }
	end
	if row.state == "ENDING" then
		return { ok = false, error = "That match is ending" }
	end
	if row.players >= row.max then
		return { ok = false, error = "Server is full" }
	end

	-- All good; attempt the teleport. TeleportService throws on bad inputs and
	-- can return TeleportInitFailed asynchronously on the client — we only get
	-- to surface the synchronous failure here.
	local teleOk, teleErr = pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, { player })
	end)
	if not teleOk then
		return { ok = false, error = "Teleport failed: " .. tostring(teleErr) }
	end
	return { ok = true }
end

-- Public/test API.
function JoinByCodeService.ValidateJobIdForTest(raw: any): string?
	return validateJobId(raw)
end

return JoinByCodeService
