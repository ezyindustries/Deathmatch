--!strict
-- Server-side authority for 10v10 Team Deathmatch team membership.
--
-- Responsibilities:
--   * Track which team each player + bot belongs to ("A" or "B")
--   * Honor a 30s switch cooldown to prevent rapid-flip griefing
--   * AUTO-balance: when a player picks "AUTO", or a bot is being assigned,
--     pick the side with fewer current combatants
--   * Tag each character with a "Team" attribute so client-side code can
--     trivially read the local player's team and other characters' teams
--   * Broadcast team-aggregate stats (players, kills, deaths per side) to
--     clients on every team change AND every kill — drives the team score
--     widget in the HUD
--   * Provide AreEnemies(charA, charB) for WeaponService friendly-fire gating
--   * Tint character body parts subtly by team color (armband on torso) so
--     players can identify teammates at a glance
--
-- Lazy-required by WeaponService + DeathmatchBotService (init-time circular
-- dep would otherwise happen because both call into us, and we may want to
-- call back via ScoringService in the future).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local DMTeams = require(Shared.Modules.DMTeams)
local MatchState = require(Shared.Modules.MatchState)

local MatchStateService = require(script.Parent.MatchStateService)

local DeathmatchTeamService = {}

-- =====================================================================
-- STATE
-- =====================================================================
-- teamOf keys: either Player.UserId (number) OR bot Model (Instance).
-- We keep them in the same table so AreEnemies works uniformly for any
-- character (player- or bot-owned).
local teamOf: { [any]: DMTeams.TeamId } = {}
-- Switch cooldown keyed by Player.UserId — bot reassignment is server-driven
-- so we don't gate it. Value = os.time() when the cooldown expires.
local cooldownUntil: { [number]: number } = {}
-- Per-team kill/death tally for THIS MATCH. Reset on LOBBY/ENDING.
local teamStats = {
	A = { kills = 0, deaths = 0 },
	B = { kills = 0, deaths = 0 },
}

-- =====================================================================
-- INTERNAL HELPERS
-- =====================================================================
local function botRoster(): { Model }
	-- Snapshot of currently-assigned bot models. We can't keep a separate
	-- registry because DeathmatchBotService destroys + rebuilds bots on
	-- respawn; instead we scan teamOf for Model keys.
	local result: { Model } = {}
	for key, _ in teamOf do
		if typeof(key) == "Instance" and (key :: Instance):IsA("Model") then
			table.insert(result, key :: Model)
		end
	end
	return result
end

local function getCounts()
	local players = { A = 0, B = 0 }
	local bots = { A = 0, B = 0 }
	for _, p in Players:GetPlayers() do
		local t = teamOf[p.UserId]
		if t then players[t] += 1 end
	end
	for _, b in botRoster() do
		local t = teamOf[b]
		if t then bots[t] += 1 end
	end
	return { players = players, bots = bots }
end

-- Apply the "Team" attribute to a character + paint a colored armband on the
-- torso so teammates are visually distinguishable at a glance. Armband is
-- a small welded Part so it survives R6 limb rebuilds. Idempotent —
-- removes any prior "TeamArmband" before adding the new one.
local function tintCharacter(character: Model, team: DMTeams.TeamId)
	character:SetAttribute("Team", team)

	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then return end

	-- Remove any prior armband (in case the character switched teams).
	local prior = torso:FindFirstChild("TeamArmband")
	if prior then prior:Destroy() end

	local color = DMTeams.Colors[team]
	local armband = Instance.new("Part")
	armband.Name = "TeamArmband"
	armband.Size = Vector3.new(2.1, 0.35, 1.1)
	armband.Material = Enum.Material.SmoothPlastic
	armband.Color = color
	armband.CanCollide = false
	armband.CanQuery = false
	armband.CanTouch = false
	armband.Massless = true
	armband.TopSurface = Enum.SurfaceType.Smooth
	armband.BottomSurface = Enum.SurfaceType.Smooth
	armband.Parent = torso

	-- Weld so it follows the torso through R6 motion. Place at upper chest.
	local weld = Instance.new("Weld")
	weld.Part0 = torso
	weld.Part1 = armband
	weld.C0 = CFrame.new(0, 0.7, 0)
	weld.C1 = CFrame.new()
	weld.Parent = armband
end

-- =====================================================================
-- PUBLIC API
-- =====================================================================

function DeathmatchTeamService.GetTeam(playerOrBot: any): DMTeams.TeamId?
	if not playerOrBot then return nil end
	-- Player object → look up by UserId
	if typeof(playerOrBot) == "Instance" then
		local inst = playerOrBot :: Instance
		if inst:IsA("Player") then
			return teamOf[(inst :: Player).UserId]
		end
		if inst:IsA("Model") then
			-- Could be a player's character OR a bot model.
			-- Try character → player lookup first.
			local maybePlayer = Players:GetPlayerFromCharacter(inst :: Model)
			if maybePlayer then
				return teamOf[maybePlayer.UserId]
			end
			-- Bot model — direct key
			return teamOf[inst]
		end
	elseif typeof(playerOrBot) == "number" then
		return teamOf[playerOrBot]
	end
	return nil
end

-- Resolve a character Model (player or bot) → team id.
local function teamOfCharacter(character: Model?): DMTeams.TeamId?
	if not character then return nil end
	local maybePlayer = Players:GetPlayerFromCharacter(character)
	if maybePlayer then
		return teamOf[maybePlayer.UserId]
	end
	return teamOf[character]
end

function DeathmatchTeamService.AreEnemies(charA: Model?, charB: Model?): boolean
	local tA = teamOfCharacter(charA)
	local tB = teamOfCharacter(charB)
	-- If either side is untagged, treat as NOT enemies — fails closed so an
	-- un-assigned bot or pre-spawn player can't be friendly-fire'd. Caller
	-- (WeaponService) can override for non-DM modes.
	if not tA or not tB then return false end
	return DMTeams.isEnemy(tA, tB)
end

function DeathmatchTeamService.GetCounts()
	return getCounts()
end

function DeathmatchTeamService.BroadcastState()
	local counts = getCounts()
	Remotes.TeamStateChanged:FireAllClients({
		teamA = {
			players = counts.players.A + counts.bots.A,
			kills = teamStats.A.kills,
			deaths = teamStats.A.deaths,
		},
		teamB = {
			players = counts.players.B + counts.bots.B,
			kills = teamStats.B.kills,
			deaths = teamStats.B.deaths,
		},
	})
end

-- Pick a team for a new combatant — AUTO picks whichever side currently has
-- fewer total combatants (players + bots). Includes the caller's prior team
-- so a re-assignment doesn't double-count them.
local function autoPickTeam(excludeKey: any?): DMTeams.TeamId
	local counts = getCounts()
	local aTotal = counts.players.A + counts.bots.A
	local bTotal = counts.players.B + counts.bots.B
	if excludeKey ~= nil and teamOf[excludeKey] then
		local cur = teamOf[excludeKey]
		if cur == "A" then aTotal -= 1 else bTotal -= 1 end
	end
	return DMTeams.pickSmaller(aTotal, bTotal)
end

function DeathmatchTeamService.AssignPlayer(player: Player, choice: string): DMTeams.TeamId
	local team: DMTeams.TeamId
	if choice == "A" or choice == "B" then
		team = choice :: DMTeams.TeamId
	else
		team = autoPickTeam(player.UserId)
	end

	teamOf[player.UserId] = team

	-- Tint the player's current character if one exists.
	if player.Character then
		tintCharacter(player.Character, team)
	end

	-- Confirmation to the assignee. lockedUntil reflects the next legal
	-- switch time (now + cooldown).
	local lockedUntil = os.time() + DMTeams.SWITCH_COOLDOWN_SEC
	cooldownUntil[player.UserId] = lockedUntil
	Remotes.TeamAssigned:FireClient(player, {
		team = team,
		lockedUntil = lockedUntil,
	})

	DeathmatchTeamService.BroadcastState()
	return team
end

function DeathmatchTeamService.AssignBot(botModel: Model, team: DMTeams.TeamId?)
	-- If caller passes nil, auto-balance. Otherwise honor the explicit team.
	local chosen: DMTeams.TeamId
	if team == "A" or team == "B" then
		chosen = team :: DMTeams.TeamId
	else
		chosen = autoPickTeam(botModel)
	end
	teamOf[botModel] = chosen
	botModel:SetAttribute("Team", chosen)
	tintCharacter(botModel, chosen)
	DeathmatchTeamService.BroadcastState()
end

function DeathmatchTeamService.UnassignBot(botModel: Model)
	if teamOf[botModel] ~= nil then
		teamOf[botModel] = nil
		DeathmatchTeamService.BroadcastState()
	end
end

-- Called by ScoringService after a confirmed kill so team aggregates update
-- in lockstep with per-player K/D. Accepts character Models (player or bot).
function DeathmatchTeamService.OnKill(killerChar: Model?, victimChar: Model?)
	-- Only count team kills in deathmatch mode — casual mode uses CasualService.
	if MatchStateService.GetGamemode() ~= "deathmatch" then return end
	local killerTeam = teamOfCharacter(killerChar)
	local victimTeam = teamOfCharacter(victimChar)
	if killerTeam then
		teamStats[killerTeam].kills += 1
	end
	if victimTeam then
		teamStats[victimTeam].deaths += 1
	end
	DeathmatchTeamService.BroadcastState()
end

-- =====================================================================
-- REMOTE HANDLER: ChooseTeam (client → server)
-- =====================================================================
Remotes.ChooseTeam.OnServerEvent:Connect(function(player: Player, choiceRaw: any)
	if typeof(choiceRaw) ~= "string" then return end
	if choiceRaw ~= "A" and choiceRaw ~= "B" and choiceRaw ~= "AUTO" then return end

	local current = teamOf[player.UserId]
	-- Switching to the OPPOSITE team while on cooldown is blocked. First-time
	-- assignment + AUTO + re-confirming same team are NOT cooldown-gated.
	if current and choiceRaw ~= "AUTO" and choiceRaw ~= current then
		local until_ = cooldownUntil[player.UserId]
		if until_ and os.time() < until_ then
			-- Re-fire TeamAssigned so client knows the request was rejected and
			-- can re-show the locked timer (without changing team).
			Remotes.TeamAssigned:FireClient(player, {
				team = current,
				lockedUntil = until_,
			})
			return
		end
	end

	DeathmatchTeamService.AssignPlayer(player, choiceRaw)
end)

-- =====================================================================
-- CHARACTER HOOK: re-apply team tag + tint on every spawn
-- =====================================================================
local function hookPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		local team = teamOf[player.UserId]
		if team then
			-- Slight delay so other character setup (loadout, viewmodel) has
			-- a chance to run first; tinting just adds a Part so timing isn't
			-- strict, but waiting lets us be sure the Torso exists.
			task.wait(0.1)
			if character.Parent then
				tintCharacter(character, team)
			end
		else
			-- No team yet — only force-open the selector when match is active
			-- (LOBBY/VOTING players are still at the menu screen and don't need it).
			task.wait(0.3) -- let MainMenuService finish its own setup
			local state = MatchStateService.GetCurrentState()
			local mode = MatchStateService.GetGamemode()
			if mode == "deathmatch" and (state == MatchState.States.MATCH
				or state == MatchState.States.STARTING) then
				if player.Parent then
					Remotes.OpenTeamSelect:FireClient(player)
				end
			end
		end
	end)
end

for _, p in Players:GetPlayers() do
	hookPlayer(p)
end
Players.PlayerAdded:Connect(hookPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	if teamOf[player.UserId] then
		teamOf[player.UserId] = nil
		cooldownUntil[player.UserId] = nil
		DeathmatchTeamService.BroadcastState()
	else
		cooldownUntil[player.UserId] = nil
	end
end)

-- =====================================================================
-- MATCH STATE: clear teams + stats at LOBBY/ENDING for a fresh round
-- =====================================================================
MatchStateService.StateChanged:Connect(function(newState: MatchState.State)
	if newState == MatchState.States.LOBBY or newState == MatchState.States.ENDING then
		-- Drop ALL assignments (players + bots) and reset team aggregates.
		-- Bots get rebuilt on the next MATCH transition by DeathmatchBotService,
		-- and players will get re-prompted with OpenTeamSelect on MATCH transition.
		teamOf = {}
		cooldownUntil = {}
		teamStats = {
			A = { kills = 0, deaths = 0 },
			B = { kills = 0, deaths = 0 },
		}
		DeathmatchTeamService.BroadcastState()
	elseif newState == MatchState.States.MATCH
		and MatchStateService.GetGamemode() == "deathmatch" then
		-- Force-open the team selector on every alive player without a team
		-- so the round starts with everyone assigned. AUTO-balance kicks in if
		-- they don't pick within the modal's grace period (UI-side decision).
		task.wait(0.5)
		for _, p in Players:GetPlayers() do
			if not teamOf[p.UserId] and p.Character then
				Remotes.OpenTeamSelect:FireClient(p)
			end
		end
	end
end)

return DeathmatchTeamService
