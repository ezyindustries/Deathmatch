--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Modules.MatchState)
local Remotes = require(Shared.Modules.Remotes)

local MatchStateService = {}

local currentState: MatchState.State = MatchState.States.LOBBY
local stateStartedAt: number = 0
-- Active gamemode for the current match. Set by VotingService when a map is
-- selected (based on map metadata). Replicated to clients so HUD can branch.
local currentGamemode: MatchState.Gamemode = MatchState.Gamemodes.Deathmatch
-- When true, the global auto-advance loop skips its task.wait/transition for
-- the current state. CasualService holds this during MATCH so its round loop
-- can drive the timing, then calls AdvanceTo("ENDING") when the match ends.
local autoAdvanceHeld = false

local stateChangedEvent = Instance.new("BindableEvent")
MatchStateService.StateChanged = stateChangedEvent.Event

local function buildPayload(): MatchState.StatePayload
	local config = MatchState.StateConfig[currentState]
	return {
		state = currentState,
		duration = config.duration,
		startedAt = stateStartedAt,
		gamemode = currentGamemode,
	}
end

local function transition(newState: MatchState.State)
	currentState = newState
	stateStartedAt = Workspace:GetServerTimeNow()
	Remotes.MatchStateChanged:FireAllClients(buildPayload())
	print(string.format("[MatchState] -> %s (%ds) [%s]", currentState, MatchState.StateConfig[currentState].duration, currentGamemode))
	stateChangedEvent:Fire(currentState)
end

function MatchStateService.GetState(): MatchState.StatePayload
	return buildPayload()
end

function MatchStateService.GetCurrentState(): MatchState.State
	return currentState
end

function MatchStateService.GetGamemode(): MatchState.Gamemode
	return currentGamemode
end

-- VotingService calls this once the winning map is locked in, so the next
-- STARTING/MATCH transitions know which mode to run.
function MatchStateService.SetGamemode(mode: MatchState.Gamemode)
	if mode ~= "deathmatch" and mode ~= "casual" then
		warn(string.format("[MatchState] Ignoring invalid gamemode %s", tostring(mode)))
		return
	end
	currentGamemode = mode
	-- Re-broadcast current payload so clients see the updated gamemode without
	-- waiting for the next state transition.
	Remotes.MatchStateChanged:FireAllClients(buildPayload())
end

-- CasualService pauses auto-advance during MATCH so its round loop can take
-- variable time without the global timer forcing ENDING.
function MatchStateService.HoldAutoAdvance(hold: boolean)
	autoAdvanceHeld = hold
end

-- Manual state transition. CasualService uses AdvanceTo("ENDING") to end the
-- match when first-to-12 is reached.
function MatchStateService.AdvanceTo(newState: MatchState.State)
	transition(newState)
end

Players.PlayerAdded:Connect(function(player: Player)
	Remotes.MatchStateChanged:FireClient(player, buildPayload())
end)

transition(MatchState.States.LOBBY)

task.spawn(function()
	while true do
		local entered = currentState
		local config = MatchState.StateConfig[currentState]
		task.wait(config.duration)
		while autoAdvanceHeld do
			task.wait(0.25)
		end
		if currentState ~= entered then
			continue
		end
		-- IDLE GATE removed — cycle is perpetual. Bots (DeathmatchBotService)
		-- fill empty matches, so the server is always running a live DM. New
		-- players joining never see a "stuck waiting for players" lobby.
		transition(MatchState.StateConfig[currentState].next)
	end
end)

return MatchStateService
