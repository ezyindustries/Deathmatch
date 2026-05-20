--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Modules.MatchState)
local MapRegistry = require(Shared.Modules.MapRegistry)
local Remotes = require(Shared.Modules.Remotes)
local GameConfig = require(Shared.Constants.GameConfig)

local MatchStateService = require(script.Parent.MatchStateService)
local CasualQueueService = require(script.Parent.CasualQueueService)

local VotingService = {}

local function supportsMode(map: MapRegistry.MapInfo, mode: string): boolean
	for _, m in map.supportedModes do
		if m == mode then return true end
	end
	return false
end

local function findMapInfo(mapId: string): MapRegistry.MapInfo?
	for _, m in MapRegistry do
		if m.id == mapId then return m end
	end
	return nil
end

local activeMaps: { MapRegistry.MapInfo } = {}
local votes: { [number]: string } = {}
local lastWinner: string? = nil

local function shuffleIndices(n: number): { number }
	local arr = {}
	for i = 1, n do
		arr[i] = i
	end
	for i = n, 2, -1 do
		local j = math.random(i)
		arr[i], arr[j] = arr[j], arr[i]
	end
	return arr
end

local function pickRandomMaps(): { MapRegistry.MapInfo }
	-- DM-only build (casual hidden). Always pick from the deathmatch map pool.
	local mode: string = "deathmatch"
	local _ = CasualQueueService -- silence unused warning
	local pool: { MapRegistry.MapInfo } = {}
	for _, m in MapRegistry do
		if supportsMode(m, mode) then
			table.insert(pool, m)
		end
	end
	if #pool == 0 then
		-- Safety fallback: no maps for the picked mode → use all maps
		pool = MapRegistry
	end
	local count = math.min(GameConfig.MapsPerVote, #pool)
	local shuffled = shuffleIndices(#pool)
	local picks = {}
	for i = 1, count do
		picks[i] = pool[shuffled[i]]
	end
	return picks
end

local function startVoting()
	activeMaps = pickRandomMaps()
	votes = {}
	Remotes.MapVoteOptions:FireAllClients(activeMaps)
	print(string.format("[Voting] Started with %d maps.", #activeMaps))
end

local function endVoting()
	local tally: { [string]: number } = {}
	for _, mapId in votes do
		tally[mapId] = (tally[mapId] or 0) + 1
	end

	local winner: string
	if next(votes) == nil then
		winner = activeMaps[math.random(#activeMaps)].id
	else
		local maxVotes = -1
		for _, m in activeMaps do
			local count = tally[m.id] or 0
			if count > maxVotes then
				maxVotes = count
				winner = m.id
			end
		end
	end

	lastWinner = winner
	-- Lock gamemode based on the winning map's metadata so MatchStateService
	-- and downstream services (CasualService, DeathmatchBotService) know what
	-- to run when STARTING/MATCH transitions fire.
	local info = findMapInfo(winner)
	if info then
		-- Prefer the first supportedMode (maps are mode-specific in v1)
		local mode = info.supportedModes[1] or "deathmatch"
		MatchStateService.SetGamemode(mode :: any)
	end
	Remotes.MapVoteResult:FireAllClients({ winner = winner, tally = tally })
	print(string.format("[Voting] Winner: %s", winner))
end

Remotes.CastVote.OnServerEvent:Connect(function(player: Player, mapId: any)
	if MatchStateService.GetState().state ~= MatchState.States.VOTING then
		return
	end
	if typeof(mapId) ~= "string" then
		return
	end
	local valid = false
	for _, m in activeMaps do
		if m.id == mapId then
			valid = true
			break
		end
	end
	if not valid then
		return
	end
	votes[player.UserId] = mapId
end)

Players.PlayerRemoving:Connect(function(player: Player)
	votes[player.UserId] = nil
end)

MatchStateService.StateChanged:Connect(function(newState: MatchState.State)
	if newState == MatchState.States.VOTING then
		startVoting()
	end
end)

function VotingService.EndVoting(): string?
	endVoting()
	return lastWinner
end

function VotingService.GetLastWinner(): string?
	return lastWinner
end

-- Force a default map for the given gamemode (used when MatchStateService picks
-- the next mode based on queues, bypassing the voting cycle). Picks the first
-- map in the registry that supports `mode`, falls back to current lastWinner.
function VotingService.SetDefaultMapFor(mode: string)
	for _, m in MapRegistry do
		if supportsMode(m, mode) then
			lastWinner = m.id
			return
		end
	end
	-- No map for this mode; keep current winner
end

return VotingService
