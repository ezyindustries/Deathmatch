--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local MatchState = require(Shared.Modules.MatchState)
local GameConfig = require(Shared.Constants.GameConfig)
local RankSystem = require(Shared.Modules.RankSystem)

local MatchStateService = require(script.Parent.MatchStateService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local WeaponService = require(script.Parent.WeaponService)

local ScoringService = {}

export type MatchScore = {
	kills: number,
	deaths: number,
	assists: number,
}

local matchScores: { [number]: MatchScore } = {}
local botScores: { [string]: MatchScore } = {} -- keyed by bot name
local killStreaks: { [number]: number } = {}

-- Streak tier labels — per-player consecutive-kill count (resets on death).
-- Function (not lookup table) so streak >= 6 always returns DOMINATOR.
local function streakLabel(streak: number): string?
	if streak == 1 then return "FIRST KILL"
	elseif streak == 2 then return "DOUBLE KILL"
	elseif streak == 3 then return "TRIPLE KILL"
	elseif streak == 4 then return "QUADRA KILL"
	elseif streak == 5 then return "PENTA KILL"
	elseif streak >= 6 then return "DOMINATOR"
	end
	return nil
end

local function getScore(userId: number): MatchScore
	if not matchScores[userId] then
		matchScores[userId] = { kills = 0, deaths = 0, assists = 0 }
	end
	return matchScores[userId]
end

local function getBotScore(name: string): MatchScore
	if not botScores[name] then
		botScores[name] = { kills = 0, deaths = 0, assists = 0 }
	end
	return botScores[name]
end

local function resetScores()
	matchScores = {}
	botScores = {}
	killStreaks = {}
end

local function buildScoreboard(): { any }
	local list = {}
	for _, p in Players:GetPlayers() do
		local s = getScore(p.UserId)
		local profile = PlayerDataService.Get(p)
		local rankShort: string? = nil
		if profile then
			rankShort = RankSystem.RankFromXp(profile.xp or 0).short
		end
		table.insert(list, {
			userId = p.UserId,
			name = p.Name,
			kills = s.kills,
			deaths = s.deaths,
			isBot = false,
			rank = rankShort,
		})
	end
	for name, s in botScores do
		table.insert(list, {
			userId = -1, -- bots have no userId
			name = name,
			kills = s.kills,
			deaths = s.deaths,
			isBot = true,
		})
	end
	table.sort(list, function(a, b)
		if a.kills == b.kills then
			return a.deaths < b.deaths
		end
		return a.kills > b.kills
	end)
	return list
end

local function broadcastScoreboard()
	Remotes.ScoreChanged:FireAllClients(buildScoreboard())
end

local XP_PER_KILL = RankSystem.XP_PER_KILL  -- 20 — drives DM rank progression
local XP_PER_WIN = 250
local XP_PER_MATCH = 100

local function awardXp(player: Player, amount: number)
	local profile = PlayerDataService.Get(player)
	local mul = (profile and profile.xpMultiplier) or 1
	local final = math.floor(amount * mul)
	-- DM rank XP (drives rank progression — Bronze 1 → ... → Immortal 3)
	PlayerDataService.IncrementStat(player, "xp", final)
	-- Battle pass season XP (separate progression)
	PlayerDataService.IncrementStat(player, "seasonXp", final)
end

WeaponService.BotKilled:Connect(function(killer: Player, botName: string)
	ScoringService.PlayerKilledBot(killer, botName)
end)

WeaponService.PlayerKilled:Connect(function(killer: Player, victim: Player, weapon: any, _isHeadshot: boolean)
	local killerScore = getScore(killer.UserId)
	local victimScore = getScore(victim.UserId)
	killerScore.kills += 1
	victimScore.deaths += 1

	PlayerDataService.IncrementStat(killer, "totalKills", 1)
	PlayerDataService.IncrementStat(victim, "totalDeaths", 1)
	awardXp(killer, XP_PER_KILL)
	PlayerDataService.AddCurrency(killer, "coins", GameConfig.CoinPerKill)

	-- Death penalty: -10 rank XP from victim. Floored at 0 (no negative XP — can
	-- derank a sub-level but not below Bronze 1).
	local victimProfile = PlayerDataService.Get(victim)
	if victimProfile then
		local current = victimProfile.xp or 0
		local delta = math.max(-10, -current) -- never drop below 0
		if delta ~= 0 then
			PlayerDataService.IncrementStat(victim, "xp", delta)
		end
	end

	killStreaks[killer.UserId] = (killStreaks[killer.UserId] or 0) + 1
	killStreaks[victim.UserId] = 0
	local streak = killStreaks[killer.UserId]
	local label = streakLabel(streak)
	if label then
		Remotes.KillstreakAnnouncement:FireAllClients({
			player = killer.Name,
			streak = streak,
			label = label,
		})
		-- Bonus coins per streak milestone
		PlayerDataService.AddCurrency(killer, "coins", streak * 5)
	end

	broadcastScoreboard()
end)

-- Track per-player Died connection so we don't leak it on each respawn
local streakConnections: { [number]: RBXScriptConnection } = {}

local function resetStreakOnDeath(player: Player)
	-- Disconnect previous connection (prevents memory leak across respawns)
	if streakConnections[player.UserId] then
		streakConnections[player.UserId]:Disconnect()
		streakConnections[player.UserId] = nil
	end
	if not player.Character then
		return
	end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		streakConnections[player.UserId] = humanoid.Died:Connect(function()
			killStreaks[player.UserId] = 0
		end)
	end
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function()
		resetStreakOnDeath(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	if streakConnections[player.UserId] then
		streakConnections[player.UserId]:Disconnect()
		streakConnections[player.UserId] = nil
	end
	killStreaks[player.UserId] = nil
	matchScores[player.UserId] = nil
end)

local function awardMatchEndRewards()
	local scoreboard = buildScoreboard()
	local mvp = scoreboard[1]

	local MissionService = require(script.Parent.MissionService)

	for _, entry in scoreboard do
		local player = Players:GetPlayerByUserId(entry.userId)
		if player then
			PlayerDataService.IncrementStat(player, "matchesPlayed", 1)
			awardXp(player, XP_PER_MATCH)
			MissionService.OnMatchPlayed(player)
		end
	end

	if mvp and mvp.kills > 0 then
		local winner = Players:GetPlayerByUserId(mvp.userId)
		if winner then
			PlayerDataService.IncrementStat(winner, "totalWins", 1)
			awardXp(winner, XP_PER_WIN)
			PlayerDataService.AddCurrency(winner, "coins", GameConfig.CoinPerWin + GameConfig.CoinPerMVP)
			MissionService.OnMatchWon(winner)
		end
	end

	Remotes.MatchResults:FireAllClients({
		scoreboard = scoreboard,
		mvp = mvp,
	})
end

MatchStateService.StateChanged:Connect(function(newState: MatchState.State)
	if newState == MatchState.States.MATCH then
		resetScores()
		broadcastScoreboard()
	elseif newState == MatchState.States.ENDING then
		-- Deathmatch-style MVP/win rewards. Casual mode has its own match-end
		-- rewards (broadcast via CasualMatchResult); don't double-award here.
		if MatchStateService.GetGamemode() == "deathmatch" then
			awardMatchEndRewards()
		end
	end
end)

Players.PlayerAdded:Connect(function(player: Player)
	task.wait(0.5)
	Remotes.ScoreChanged:FireClient(player, buildScoreboard())
end)

-- ==========================================================================
-- BOT INTEGRATION API
-- ==========================================================================
function ScoringService.RegisterBot(name: string)
	getBotScore(name) -- initialize
	broadcastScoreboard()
end

function ScoringService.UnregisterBot(name: string)
	botScores[name] = nil
	broadcastScoreboard()
end

function ScoringService.PlayerKilledBot(killer: Player, botName: string)
	getScore(killer.UserId).kills += 1
	getBotScore(botName).deaths += 1
	PlayerDataService.IncrementStat(killer, "totalKills", 1)
	awardXp(killer, XP_PER_KILL)
	PlayerDataService.AddCurrency(killer, "coins", GameConfig.CoinPerKill)
	killStreaks[killer.UserId] = (killStreaks[killer.UserId] or 0) + 1
	local streak = killStreaks[killer.UserId]
	local label = streakLabel(streak)
	if label then
		Remotes.KillstreakAnnouncement:FireAllClients({
			player = killer.Name,
			streak = streak,
			label = label,
		})
		PlayerDataService.AddCurrency(killer, "coins", streak * 5)
	end
	broadcastScoreboard()
end

function ScoringService.BotKilledPlayer(botName: string, victim: Player)
	getBotScore(botName).kills += 1
	getScore(victim.UserId).deaths += 1
	PlayerDataService.IncrementStat(victim, "totalDeaths", 1)
	killStreaks[victim.UserId] = 0
	-- Death penalty also applies when a bot kills the player.
	local victimProfile = PlayerDataService.Get(victim)
	if victimProfile then
		local current = victimProfile.xp or 0
		local delta = math.max(-10, -current)
		if delta ~= 0 then
			PlayerDataService.IncrementStat(victim, "xp", delta)
		end
	end
	broadcastScoreboard()
end

function ScoringService.BotKilledBot(killerName: string, victimName: string)
	getBotScore(killerName).kills += 1
	getBotScore(victimName).deaths += 1
	broadcastScoreboard()
end

return ScoringService
