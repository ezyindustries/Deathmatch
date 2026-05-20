--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local MatchState = require(Shared.Modules.MatchState)

local TrainingService = require(script.Parent.TrainingService)
local CasualQueueService = require(script.Parent.CasualQueueService)
local MatchStateService = require(script.Parent.MatchStateService)

local MainMenuService = {}

-- Disable auto-spawn so player sits at the main menu until they click PLAY.
Players.CharacterAutoLoads = false

local hasSpawned: { [number]: boolean } = {}

Players.PlayerAdded:Connect(function(player: Player)
	hasSpawned[player.UserId] = false
end)

Players.PlayerRemoving:Connect(function(player: Player)
	hasSpawned[player.UserId] = nil
end)

-- Shared spawn paths (used by RequestSpawn handler AND the death-respawn loop).
-- Extracted so death-respawn literally re-runs the same code path a fresh joiner
-- takes — no divergence, no race conditions from custom respawn logic.

local function exitToMenu(player: Player)
	TrainingService.ExitTraining(player)
	CasualQueueService.Leave(player)
	if player.Character then
		player.Character:Destroy()
		player.Character = nil  -- detach immediately so stale-char checks return nil
	end
	hasSpawned[player.UserId] = false
end

local function spawnInto(player: Player, mode: string?)
	if hasSpawned[player.UserId] then return end
	hasSpawned[player.UserId] = true
	if mode == "training" then
		CasualQueueService.Leave(player)
		TrainingService.StartTraining(player)
	else
		CasualQueueService.Leave(player)
		player:LoadCharacter()
	end
end

Remotes.RequestSpawn.OnServerEvent:Connect(function(player: Player, mode: any)
	local modeStr = typeof(mode) == "string" and mode or nil
	spawnInto(player, modeStr)
end)

Remotes.ExitToMainMenu.OnServerEvent:Connect(function(player: Player)
	exitToMenu(player)
end)

-- DEATHMATCH AUTO-RESPAWN: literally simulates ExitToMainMenu + RequestSpawn(deathmatch).
-- This is the EXACT same code path a player who alt-tabbed back to main menu and
-- clicked PLAY would take. No custom respawn logic = no per-respawn divergence bugs.
local RESPAWN_DELAY_DM = 0.5

local function respawnIntoDeathmatch(player: Player)
	-- Step 1: full exit (destroy character, clear queue, reset hasSpawned flag).
	exitToMenu(player)

	task.wait(RESPAWN_DELAY_DM)

	-- Step 2: re-verify state still valid post-wait (player may have left, match ended)
	if not player.Parent then return end
	if MatchStateService.GetGamemode() ~= "deathmatch" then return end
	if MatchStateService.GetCurrentState() ~= MatchState.States.MATCH then return end

	-- Step 3: fresh rejoin into deathmatch.
	spawnInto(player, "deathmatch")
end

local function hookDeathRespawn(player: Player)
	player.CharacterAdded:Connect(function(char: Model)
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		if not hum then return end
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.NameDisplayDistance = 0
		hum.HealthDisplayDistance = 0
		hum.Died:Connect(function()
			if not hasSpawned[player.UserId] then return end
			if MatchStateService.GetGamemode() ~= "deathmatch" then return end
			if MatchStateService.GetCurrentState() ~= MatchState.States.MATCH then return end
			respawnIntoDeathmatch(player)
		end)
	end)
end

Players.PlayerAdded:Connect(hookDeathRespawn)
for _, p in Players:GetPlayers() do hookDeathRespawn(p) end

return MainMenuService
