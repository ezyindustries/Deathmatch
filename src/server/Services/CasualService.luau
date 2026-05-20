--!strict
-- CasualService — orchestrates CS-style 5v5 plant/defuse matches.
--
-- Owns:
--   * Team assignment (auto-balance + bot fill via CasualBotService)
--   * Round loop (BUY → LIVE → POST) running INSIDE the global MATCH state.
--     We HoldAutoAdvance on MatchStateService so the global MATCH duration
--     doesn't trample our variable-length round loop, then AdvanceTo("ENDING")
--     when the match resolves.
--   * Bomb state machine (held → dropped → planted → defused/exploded)
--   * Plant / defuse hold validation (PlantBomb / DefuseBomb remotes)
--   * Round-win resolution via the SINGLE function CheckRoundEnd(), called
--     from every event that could change the outcome — no other code path
--     decides who wins a round.
--   * Match end: first team to MatchWinScore (12) wins; halftime role swap
--     at HalftimeRound (12) if neither team has won.
--
-- Actor keys: players are keyed by UserId (number→string); bots by Name.
-- Everything (teams, aliveSet, scoring) uses these string keys so the same
-- code paths work for both.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local MatchState = require(Shared.Modules.MatchState)
local Teams = require(Shared.Modules.Teams)
local CasualConfig = require(Shared.Constants.CasualConfig)

local MatchStateService = require(script.Parent.MatchStateService)
local ArenaService = require(script.Parent.ArenaService)
local CasualQueueService = require(script.Parent.CasualQueueService)

local CasualService = {}

-- ================================================================
-- STATE
-- ================================================================
type Phase = "IDLE" | "BUY" | "LIVE" | "POST"
type BombStatus = "held" | "dropped" | "planted" | "defused" | "exploded"

local roundNumber = 0
local scoreT = 0
local scoreCT = 0
local phase: Phase = "IDLE"
local phaseEndsAt = 0
-- Map each actor key (UserId-as-string for players, bot Name for bots) to a team
local teams: { [string]: Teams.TeamId } = {}
local aliveSet: { [string]: boolean } = {}
-- Bomb state
local bombStatus: BombStatus = "held"
local bombHolder: string? = nil  -- actor key currently carrying
local bombPosition: Vector3? = nil
local bombPlantedAt: number? = nil  -- os.clock when planted
local bombModel: Model? = nil
local bombSiteName: string? = nil  -- "A" or "B"
local defuser: string? = nil  -- actor key currently defusing
local defuseStartedAt: number? = nil
local defuseEndedAt: number? = nil

-- Cached reference to CasualBotService (lazy require to avoid circular dep)
local CasualBotService: any = nil
local function getBotService()
	if not CasualBotService then
		CasualBotService = require(script.Parent.CasualBotService)
	end
	return CasualBotService
end

-- Respawn guard handle (returned by ArenaService.RegisterRespawnGuard) so we
-- can un-register when leaving casual.
local removeRespawnGuard: (() -> ())? = nil

-- ================================================================
-- HELPERS
-- ================================================================
local function actorKeyForPlayer(player: Player): string
	return tostring(player.UserId)
end

local function isBotKey(key: string): boolean
	return tonumber(key) == nil
end

local function playerFromKey(key: string): Player?
	local uid = tonumber(key)
	if not uid then return nil end
	for _, p in Players:GetPlayers() do
		if p.UserId == uid then return p end
	end
	return nil
end

local function characterFor(key: string): Model?
	if isBotKey(key) then
		local arena = ArenaService.GetArenaFolder()
		if not arena then return nil end
		return arena:FindFirstChild(key) :: Model?
	end
	local p = playerFromKey(key)
	return p and p.Character or nil
end

local function rootPosFor(key: string): Vector3?
	local char = characterFor(key)
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.Position
end

local function aliveCount(team: Teams.TeamId): number
	local n = 0
	for key, t in teams do
		if t == team and aliveSet[key] then
			n += 1
		end
	end
	return n
end

local function broadcastRoundState()
	Remotes.CasualRoundState:FireAllClients({
		round = roundNumber,
		scoreT = scoreT,
		scoreCT = scoreCT,
		phase = phase,
		phaseEndsAt = phaseEndsAt,
		teams = teams,
		halftimeRound = CasualConfig.HalftimeRound,
		matchWinScore = CasualConfig.MatchWinScore,
	})
end

local function broadcastBombState()
	Remotes.BombStateChanged:FireAllClients({
		status = bombStatus,
		position = bombPosition,
		holderUserId = bombHolder,
		site = bombSiteName,
		countdown = if bombPlantedAt
			then math.max(0, CasualConfig.BombTimer - (os.clock() - bombPlantedAt))
			else nil,
	})
end

-- ================================================================
-- PUBLIC QUERIES (used by WeaponService, ScoringService, BotService)
-- ================================================================
function CasualService.GetTeamFor(key: any): Teams.TeamId?
	return teams[tostring(key)]
end

function CasualService.IsAlive(key: any): boolean
	return aliveSet[tostring(key)] == true
end

function CasualService.IsActive(): boolean
	return MatchStateService.GetGamemode() == "casual"
		and MatchStateService.GetCurrentState() == MatchState.States.MATCH
end

function CasualService.IsLivePhase(): boolean
	return phase == "LIVE" and CasualService.IsActive()
end

function CasualService.AreOpponents(keyA: any, keyB: any): boolean
	local tA = teams[tostring(keyA)]
	local tB = teams[tostring(keyB)]
	if not tA or not tB then return true end -- default: count as opponents if unknown
	return tA ~= tB
end

-- Bomb introspection (used by CasualBotService AI for plant/defuse decisions)
function CasualService.GetBombHolder(): string?
	return bombHolder
end

function CasualService.GetBombPosition(): Vector3?
	return bombPosition
end

function CasualService.GetBombStatus(): BombStatus
	return bombStatus
end

-- ================================================================
-- TEAM ASSIGNMENT
-- ================================================================
local function clearTeams()
	table.clear(teams)
	table.clear(aliveSet)
end

local function autoBalancePlayers()
	clearTeams()
	-- Distribute queued players alternately to keep teams balanced.
	local queued = CasualQueueService.GetAll()
	local nextTeam: Teams.TeamId = "T"
	for _, uid in queued do
		local p: Player? = nil
		for _, candidate in Players:GetPlayers() do
			if candidate.UserId == uid then p = candidate; break end
		end
		if p then
			teams[actorKeyForPlayer(p)] = nextTeam
			nextTeam = if nextTeam == "T" then "CT" else "T"
		end
	end
end

-- Swap queued players into bot slots. Called at the start of every round so
-- new players join at the next round boundary (not next match). Picks the bot
-- on the team with the most members so teams stay balanced post-swap.
local function swapInQueuedPlayers()
	local queued = CasualQueueService.GetAll()
	for _, uid in queued do
		-- Already on a team? skip.
		local key = tostring(uid)
		if teams[key] then continue end
		local p: Player? = nil
		for _, candidate in Players:GetPlayers() do
			if candidate.UserId == uid then p = candidate; break end
		end
		if not p then continue end
		-- Pick the team that currently has the LARGER head count so we shrink
		-- the bigger side and grow the smaller. Tie → put player on T.
		local tCount, ctCount = 0, 0
		for _, t in teams do
			if t == "T" then tCount += 1 elseif t == "CT" then ctCount += 1 end
		end
		local targetTeam: Teams.TeamId = if tCount >= ctCount then "T" else "CT"
		local botName = getBotService().PickBotToReplace(targetTeam)
		if not botName then
			-- No bot available on that team — try the other side.
			targetTeam = if targetTeam == "T" then "CT" else "T"
			botName = getBotService().PickBotToReplace(targetTeam)
		end
		if not botName then
			-- No bot anywhere — shouldn't happen if teams are full, but bail safely.
			continue
		end
		local removedTeam = getBotService().RemoveBot(botName)
		if not removedTeam then continue end
		teams[botName] = nil
		aliveSet[botName] = nil
		teams[key] = removedTeam
		print(string.format("[Casual] Player %s swapped in for bot %s on team %s", p.Name, botName, removedTeam))
	end
end

-- Remove a player from teams (called when they exit). The bot fill on next
-- runMatch will rebalance; for mid-match leaves, the freed slot stays empty
-- until next match (acceptable simplification — bots are already full count
-- per side, removing a player just makes the team 4v5 until round end).
local function removePlayerFromTeams(player: Player)
	local key = actorKeyForPlayer(player)
	teams[key] = nil
	aliveSet[key] = nil
end

local function swapTeamsHalftime()
	for key, t in teams do
		teams[key] = Teams.Other(t)
	end
end

-- ================================================================
-- SPAWN / RESPAWN
-- ================================================================
local function spawnPlayerAtTeamSpawn(player: Player, team: Teams.TeamId)
	local spawns = ArenaService.GetTeamSpawns(team)
	if #spawns == 0 then return end
	local sp = spawns[math.random(#spawns)]
	-- Wait for the fresh character via CharacterAdded:Wait() so we don't race on
	-- the LoadCharacter return (player.Character can briefly be nil or the old
	-- destroyed model). Use a timeout fallback so a stuck spawn can't deadlock
	-- the round loop.
	local newCharSignal = player.CharacterAdded
	player:LoadCharacter()
	local char: Model? = player.Character
	if not char then
		local conn: RBXScriptConnection? = nil
		local done = false
		conn = newCharSignal:Connect(function(c)
			char = c
			done = true
			if conn then conn:Disconnect() end
		end)
		local waited = 0
		while not done and waited < 2 do
			task.wait(0.1)
			waited += 0.1
		end
		if conn then conn:Disconnect() end
	end
	if not char then return end
	-- Force full HP explicitly — defensive in case the StarterCharacter template
	-- has a custom max or some prior life's damage leaked.
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = hum.MaxHealth
	end
	ArenaService.TeleportPlayerTo(player, sp.CFrame + Vector3.new(0, 5, 0))
	ArenaService.GrantSpawnProtection(player)
end

local function spawnAllAliveForRound()
	-- Reset alive set: everyone on a team is alive at round start
	table.clear(aliveSet)
	for key, team in teams do
		aliveSet[key] = true
		if not isBotKey(key) then
			local p = playerFromKey(key)
			if p then
				spawnPlayerAtTeamSpawn(p, team)
			end
		else
			-- Bot respawn handled by CasualBotService
			getBotService().RespawnBot(key, team)
		end
	end
end

-- ================================================================
-- BOMB
-- ================================================================
local function assignBombHolder()
	local tKeys: { string } = {}
	for key, t in teams do
		if t == "T" and aliveSet[key] then
			table.insert(tKeys, key)
		end
	end
	bombHolder = if #tKeys > 0 then tKeys[math.random(#tKeys)] else nil
	bombStatus = if bombHolder then "held" else "dropped"
	bombPosition = nil
	bombPlantedAt = nil
	bombSiteName = nil
	defuser = nil
	defuseStartedAt = nil
	defuseEndedAt = nil
	if bombModel then
		bombModel:Destroy()
		bombModel = nil
	end
	broadcastBombState()
end

local function isInsideBombSite(position: Vector3): (boolean, string?, BasePart?)
	for _, site in ArenaService.GetBombSites() do
		local rel = (site.CFrame:PointToObjectSpace(position))
		local half = site.Size * 0.5
		if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
			return true, site:GetAttribute("BombSite") :: string?, site
		end
	end
	return false, nil, nil
end

local function spawnBombModel(at: Vector3)
	if bombModel then bombModel:Destroy() end
	local m = Instance.new("Model")
	m.Name = "PlantedBomb"
	local part = Instance.new("Part")
	part.Name = "BombPart"
	part.Size = Vector3.new(2, 0.8, 1.2)
	part.Position = at
	part.Anchored = true
	part.Color = Color3.fromRGB(200, 40, 40)
	part.Material = Enum.Material.Metal
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = m
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 50, 30)
	light.Range = 12
	light.Brightness = 2
	light.Parent = part
	m.PrimaryPart = part
	m.Parent = ArenaService.GetArenaFolder()
	bombModel = m
end

local plantInFlight: { [string]: boolean } = {}  -- actor keys currently doing plant hold

-- Internal plant flow (called by both player remote + bot AI)
function CasualService.TryStartPlant(actorKey: string): boolean
	if phase ~= "LIVE" then return false end
	if bombStatus ~= "held" and bombStatus ~= "dropped" then return false end
	if not aliveSet[actorKey] then return false end
	if teams[actorKey] ~= "T" then return false end
	if plantInFlight[actorKey] then return false end
	local pos = rootPosFor(actorKey)
	if not pos then return false end
	local inside, siteName = isInsideBombSite(pos)
	if not inside then return false end

	plantInFlight[actorKey] = true
	local player = if not isBotKey(actorKey) then playerFromKey(actorKey) else nil
	local startedAt = os.clock()

	task.spawn(function()
		while os.clock() - startedAt < CasualConfig.PlantTime do
			task.wait(0.1)
			-- Cancel if any precondition fails
			if phase ~= "LIVE" or not aliveSet[actorKey] or bombStatus == "planted" then
				plantInFlight[actorKey] = false
				return
			end
			local curPos = rootPosFor(actorKey)
			if not curPos then
				plantInFlight[actorKey] = false
				return
			end
			local stillInside = isInsideBombSite(curPos)
			if not stillInside then
				plantInFlight[actorKey] = false
				return
			end
			if player then
				local prog = math.clamp((os.clock() - startedAt) / CasualConfig.PlantTime, 0, 1)
				Remotes.CasualPlantProgress:FireClient(player, { progress = prog })
			end
		end
		-- Plant completed
		plantInFlight[actorKey] = false
		if phase ~= "LIVE" or bombStatus == "planted" then return end
		local curPos = rootPosFor(actorKey)
		if not curPos then return end
		local stillInside, finalSite = isInsideBombSite(curPos)
		if not stillInside then return end
		bombStatus = "planted"
		bombPosition = Vector3.new(curPos.X, curPos.Y - 2, curPos.Z)
		bombPlantedAt = os.clock()
		bombSiteName = finalSite
		bombHolder = nil
		spawnBombModel(bombPosition :: Vector3)
		broadcastBombState()
		print(string.format("[Casual] Bomb planted at site %s by %s", tostring(finalSite), actorKey))
	end)
	return true
end

local defuseInFlight: { [string]: boolean } = {}

function CasualService.TryStartDefuse(actorKey: string): boolean
	if phase ~= "LIVE" then return false end
	if bombStatus ~= "planted" then return false end
	if not aliveSet[actorKey] then return false end
	if teams[actorKey] ~= "CT" then return false end
	if defuseInFlight[actorKey] then return false end
	if not bombPosition then return false end
	local pos = rootPosFor(actorKey)
	if not pos then return false end
	if (pos - bombPosition).Magnitude > CasualConfig.BombSiteRadius then return false end

	defuseInFlight[actorKey] = true
	defuser = actorKey
	defuseStartedAt = os.clock()
	defuseEndedAt = nil
	local player = if not isBotKey(actorKey) then playerFromKey(actorKey) else nil
	local startedAt = os.clock()

	task.spawn(function()
		while os.clock() - startedAt < CasualConfig.DefuseTime do
			task.wait(0.1)
			if phase ~= "LIVE" or not aliveSet[actorKey] or bombStatus ~= "planted" then
				defuseInFlight[actorKey] = false
				if defuser == actorKey then defuser = nil end
				return
			end
			local curPos = rootPosFor(actorKey)
			if not curPos or not bombPosition then
				defuseInFlight[actorKey] = false
				if defuser == actorKey then defuser = nil end
				return
			end
			if (curPos - bombPosition).Magnitude > CasualConfig.BombSiteRadius then
				defuseInFlight[actorKey] = false
				if defuser == actorKey then defuser = nil end
				return
			end
			if player then
				local prog = math.clamp((os.clock() - startedAt) / CasualConfig.DefuseTime, 0, 1)
				Remotes.CasualDefuseProgress:FireClient(player, { progress = prog })
			end
		end
		defuseInFlight[actorKey] = false
		if phase ~= "LIVE" or bombStatus ~= "planted" then return end
		-- Defuse succeeded
		bombStatus = "defused"
		defuseEndedAt = os.clock()
		broadcastBombState()
		print(string.format("[Casual] Bomb defused by %s", actorKey))
		CasualService.CheckRoundEnd("defused")
	end)
	return true
end

-- ================================================================
-- CHECK ROUND END — single source of truth
-- ================================================================
local roundResolved = false
local liveEndedAt: number? = nil

function CasualService.CheckRoundEnd(triggeredBy: string?)
	if roundResolved then return end
	if phase ~= "LIVE" then return end

	local tAlive = aliveCount("T")
	local ctAlive = aliveCount("CT")

	-- Simplified casual (no bomb): round ends on team wipe or time expiry.
	-- 1. All CT dead → T wins
	-- 2. All T dead → CT wins
	-- 3. Both alive at time expiry → side with more survivors wins; tie = CT (defenders) by default
	local winner: Teams.TeamId? = nil
	local reason = ""

	if ctAlive == 0 and tAlive == 0 then
		winner = "CT"; reason = "Both teams wiped (tie → CT)"
	elseif ctAlive == 0 then
		winner = "T"; reason = "CT team eliminated"
	elseif tAlive == 0 then
		winner = "CT"; reason = "T team eliminated"
	elseif liveEndedAt and os.clock() >= liveEndedAt then
		if tAlive > ctAlive then
			winner = "T"; reason = "Time expired — T has more survivors"
		elseif ctAlive > tAlive then
			winner = "CT"; reason = "Time expired — CT has more survivors"
		else
			winner = "CT"; reason = "Time expired (tie → CT)"
		end
	end

	if winner then
		roundResolved = true
		if winner == "T" then scoreT += 1 else scoreCT += 1 end
		Remotes.CasualRoundResult:FireAllClients({
			winner = winner, reason = reason,
			scoreT = scoreT, scoreCT = scoreCT, round = roundNumber,
		})
		print(string.format("[Casual] Round %d → %s wins (%s) | %d-%d", roundNumber, winner, reason, scoreT, scoreCT))
	end
end

-- ================================================================
-- BOMB EXPLOSION TIMER (started post-plant)
-- ================================================================
local function bombTickerLoop()
	while phase == "LIVE" do
		task.wait(0.5)
		if bombStatus == "planted" and bombPlantedAt then
			broadcastBombState()  -- keep clients in sync with countdown
			if os.clock() - bombPlantedAt >= CasualConfig.BombTimer then
				bombStatus = "exploded"
				broadcastBombState()
				print("[Casual] Bomb EXPLODED")
				CasualService.CheckRoundEnd("exploded")
				return
			end
		end
	end
end

-- ================================================================
-- DEATH NOTIFICATION
-- ================================================================
function CasualService.NotifyDeath(actorKey: any)
	local key = tostring(actorKey)
	if not teams[key] then return end
	if not aliveSet[key] then return end
	aliveSet[key] = false
	CasualService.CheckRoundEnd("death")
end

-- ================================================================
-- ROUND LIFECYCLE
-- ================================================================
local function startBuyPhase()
	phase = "BUY"
	phaseEndsAt = os.clock() + CasualConfig.BuyDuration
	-- Swap any queued players into bot slots BEFORE broadcasting + spawning,
	-- so the new player shows up in the round state payload + spawns this round.
	swapInQueuedPlayers()
	broadcastRoundState()
	-- Reset / respawn everyone for the round
	spawnAllAliveForRound()
	roundResolved = false
	liveEndedAt = nil
	print(string.format("[Casual] BUY phase round %d", roundNumber))
	task.wait(CasualConfig.BuyDuration)
end

local function startLivePhase()
	phase = "LIVE"
	phaseEndsAt = os.clock() + CasualConfig.RoundDuration
	liveEndedAt = phaseEndsAt
	broadcastRoundState()
	print(string.format("[Casual] LIVE phase round %d", roundNumber))
	-- No bomb ticker — round resolves on team wipe or time expiry.
	while not roundResolved do
		task.wait(0.25)
		if phase ~= "LIVE" then return end
		CasualService.CheckRoundEnd("tick")
	end
end

local function startPostPhase()
	phase = "POST"
	phaseEndsAt = os.clock() + CasualConfig.PostRoundDuration
	broadcastRoundState()
	print(string.format("[Casual] POST phase round %d", roundNumber))
	task.wait(CasualConfig.PostRoundDuration)
end

local function runRound(n: number)
	roundNumber = n
	startBuyPhase()
	startLivePhase()
	startPostPhase()
end

local function isMatchOver(): boolean
	return scoreT >= CasualConfig.MatchWinScore or scoreCT >= CasualConfig.MatchWinScore
end

-- ================================================================
-- MATCH LIFECYCLE
-- ================================================================
local function runMatch()
	scoreT = 0
	scoreCT = 0
	roundNumber = 0

	autoBalancePlayers()
	-- Fill bots so each team reaches TeamSize
	local tCount, ctCount = 0, 0
	for _, t in teams do
		if t == "T" then tCount += 1 elseif t == "CT" then ctCount += 1 end
	end
	getBotService().FillBots(CasualConfig.TeamSize - tCount, CasualConfig.TeamSize - ctCount, function(botName, team)
		teams[botName] = team
	end)
	broadcastRoundState()

	-- Run rounds until winner is determined
	while not isMatchOver() do
		runRound(roundNumber + 1)
		-- Halftime role swap: after HalftimeRound played with no winner, swap
		if roundNumber == CasualConfig.HalftimeRound and not isMatchOver() then
			print("[Casual] HALFTIME — swapping team roles")
			swapTeamsHalftime()
			broadcastRoundState()
		end
		-- Hard cap to prevent infinite loop in pathological scenarios (e.g., draws)
		if roundNumber >= CasualConfig.HalftimeRound * 2 + 1 then
			print("[Casual] Round cap reached — ending match")
			break
		end
	end

	local winner: string
	if scoreT > scoreCT then winner = "T"
	elseif scoreCT > scoreT then winner = "CT"
	else winner = "DRAW" end

	Remotes.CasualMatchResult:FireAllClients({
		winner = winner, finalScoreT = scoreT, finalScoreCT = scoreCT,
	})
	print(string.format("[Casual] MATCH END — winner=%s (%d-%d)", winner, scoreT, scoreCT))
end

-- ================================================================
-- MATCH STATE HOOK
-- ================================================================
local function shutdownCasual()
	-- Tear down: clear teams, bots, respawn guard, remove bomb model
	phase = "IDLE"
	if bombModel then bombModel:Destroy(); bombModel = nil end
	if removeRespawnGuard then removeRespawnGuard(); removeRespawnGuard = nil end
	getBotService().ClearBots()
	clearTeams()
end

-- Player exit (M key / leave queue). Removes them from teams/alive so the
-- round-end check doesn't wait for a ghost. Their freed slot stays empty until
-- next match's bot fill (acceptable simplification — team gets temporarily smaller).
function CasualService.PlayerExited(player: Player)
	local key = actorKeyForPlayer(player)
	if not teams[key] then return end
	teams[key] = nil
	aliveSet[key] = nil
	print(string.format("[Casual] Player %s exited mid-match", player.Name))
	if phase == "LIVE" then
		CasualService.CheckRoundEnd("exit")
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	CasualService.PlayerExited(player)
end)

MatchStateService.StateChanged:Connect(function(newState: MatchState.State)
	if newState == MatchState.States.MATCH and MatchStateService.GetGamemode() == "casual" then
		-- Take over the global MATCH window so our round loop drives timing
		MatchStateService.HoldAutoAdvance(true)
		-- Block ArenaService auto-respawn for dead-in-round players (CasualService
		-- manages all spawn placement explicitly via spawnAllAliveForRound).
		removeRespawnGuard = ArenaService.RegisterRespawnGuard(function(player: Player)
			local key = actorKeyForPlayer(player)
			-- Allow respawn only if the player is alive in the current round
			-- (or no round is active — e.g., game-state transitions outside a round)
			if phase == "IDLE" then return true end
			return aliveSet[key] == true
		end)
		task.spawn(function()
			runMatch()
			shutdownCasual()
			MatchStateService.HoldAutoAdvance(false)
			MatchStateService.AdvanceTo(MatchState.States.ENDING)
		end)
	elseif newState == MatchState.States.ENDING then
		-- Defensive cleanup in case shutdown didn't run
		if phase ~= "IDLE" then shutdownCasual() end
		MatchStateService.HoldAutoAdvance(false)
	end
end)

-- ================================================================
-- REMOTE HANDLERS
-- ================================================================
Remotes.PlantBomb.OnServerEvent:Connect(function(player: Player)
	CasualService.TryStartPlant(actorKeyForPlayer(player))
end)

Remotes.DefuseBomb.OnServerEvent:Connect(function(player: Player)
	CasualService.TryStartDefuse(actorKeyForPlayer(player))
end)

-- Hook player death so CasualService is notified even if the kill came from
-- something other than a tracked source. (Bot deaths are notified by
-- CasualBotService directly.)
Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(char: Model)
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		if not hum then return end
		hum.Died:Connect(function()
			if CasualService.IsActive() then
				CasualService.NotifyDeath(actorKeyForPlayer(player))
			end
		end)
	end)
end)

return CasualService
