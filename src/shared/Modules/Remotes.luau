--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"
local REMOTE_NAMES = {
	"MatchStateChanged",
	"MapVoteOptions",
	"CastVote",
	"MapVoteResult",
	"FireRequest",
	"HitConfirm",
	"WeaponEquipped",
	"SwitchWeapon",
	"RequestReload",
	"AmmoUpdate",
	"KillFeedEntry",
	"ShotFired",
	"PlayerDataChanged",
	"ScoreChanged",
	"MatchResults",
	"OpenCrate",
	"CrateOpened",
	"EquipCosmetic",
	"ClaimBPReward",
	"BPRewardResult",
	"ClaimDaily",
	"DailyResult",
	"ClaimMission",
	"MissionResult",
	"CompleteTutorial",
	"PromptPurchase",
	"GamepassesUpdated",
	"SetLoadout",
	"UpdateSetting",
	"KillstreakAnnouncement",
	"DeathInfo",
	"DamageTaken",
	"RequestSpawn",
	"EnterTrainingMode",
	"ExitToMainMenu",
	"RedeemCode",
	"RedeemResult",
	-- Casual mode
	"CasualRoundState",   -- server → all clients: { round, scoreT, scoreCT, phase, phaseEndsAt, teams: { [uid]=teamId } }
	"BombStateChanged",   -- server → all clients: { status: "held"|"dropped"|"planted"|"defused"|"exploded", position?, holderUserId?, countdown? }
	"PlantBomb",          -- client → server: request to begin plant (server validates location + gates plant hold)
	"DefuseBomb",         -- client → server: request to begin defuse (server validates range + gates defuse hold)
	"CasualRoundResult",  -- server → all clients: { winner: "T"|"CT", reason, scoreT, scoreCT, round }
	"CasualMatchResult",  -- server → all clients: { winner: "T"|"CT"|"DRAW", finalScoreT, finalScoreCT }
	"CasualPlantProgress",   -- server → client: { progress 0..1 } (sent to planting T)
	"CasualDefuseProgress",  -- server → client: { progress 0..1 } (sent to defusing CT)
	"CasualWaitingForMatch", -- server → client: boolean. true = show "waiting for next casual match" overlay, false = hide
	-- Multiplayer (server browser + private party + join-by-code)
	"PrivateLobbyUpdate",    -- server → all clients in lobby: { code, hostUserId, members: { {userId, name, ready} } }
	"PrivateLobbyReady",     -- client → server: bool — toggle ready state in private lobby
	"PrivateLobbyStart",     -- client (host only) → server: start the match from private lobby
	"PartyInviteReceived",   -- server → client: { fromName, code } — notification when invited
	-- Team Deathmatch (10v10)
	"ChooseTeam",            -- client → server: "A" | "B" | "AUTO"
	"TeamAssigned",          -- server → client: { team: "A"|"B", lockedUntil: number } — confirmation + switch cooldown
	"TeamStateChanged",      -- server → all clients: { teamA: { players, kills, deaths }, teamB: { players, kills, deaths } } — sent on every team change + every kill
	"OpenTeamSelect",        -- server → client: force-open the team select modal (e.g. at match start)
}

-- RemoteFunction names. Used for request/response (RPC-style) where the
-- client needs a value back from the server: list sessions, create lobby,
-- join by code, etc. Kept separate from RemoteEvents above for type safety.
local REMOTE_FUNCTION_NAMES = {
	"ListPublicSessions",    -- () → { { jobId, code?, mapId, state, players: int, max: int, kind: "public"|"private" } }
	"CreatePrivateLobby",    -- () → { ok: bool, code?, accessCode?, error? }
	"JoinSessionByCode",     -- (code: string) → { ok: bool, error? } (teleports the player on success)
	"JoinSessionByJobId",    -- (jobId: string) → { ok: bool, error? }
	"LeavePrivateLobby",     -- () → { ok: bool }
}

local isServer = RunService:IsServer()

local function getOrCreateFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing :: Folder
	end
	if isServer then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) :: Folder
end

local function getOrCreateRemote(folder: Folder, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing :: RemoteEvent
	end
	if isServer then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name, 30) :: RemoteEvent
end

local function getOrCreateFunction(folder: Folder, name: string): RemoteFunction
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing :: RemoteFunction
	end
	if isServer then
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = folder
		return fn
	end
	return folder:WaitForChild(name, 30) :: RemoteFunction
end

local folder = getOrCreateFolder()
local Remotes: { [string]: any } = {}
for _, name in REMOTE_NAMES do
	Remotes[name] = getOrCreateRemote(folder, name)
end
for _, name in REMOTE_FUNCTION_NAMES do
	Remotes[name] = getOrCreateFunction(folder, name)
end

return Remotes
