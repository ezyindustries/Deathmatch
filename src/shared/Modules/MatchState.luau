--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Constants.GameConfig)

local MatchState = {}

MatchState.States = {
	LOBBY = "LOBBY",
	VOTING = "VOTING",
	STARTING = "STARTING",
	MATCH = "MATCH",
	ENDING = "ENDING",
}

export type State = "LOBBY" | "VOTING" | "STARTING" | "MATCH" | "ENDING"

export type Gamemode = "deathmatch" | "casual"

MatchState.Gamemodes = {
	Deathmatch = "deathmatch" :: Gamemode,
	Casual = "casual" :: Gamemode,
}

export type StatePayload = {
	state: State,
	duration: number,
	startedAt: number,
	gamemode: Gamemode?, -- which gamemode is active during this state (replicated for HUD gating)
}

MatchState.StateConfig = {
	[MatchState.States.LOBBY] = { duration = GameConfig.LobbyDuration, next = MatchState.States.VOTING },
	[MatchState.States.VOTING] = { duration = GameConfig.VotingDuration, next = MatchState.States.STARTING },
	[MatchState.States.STARTING] = { duration = 2, next = MatchState.States.MATCH }, -- TEST MODE (prod: 5)
	[MatchState.States.MATCH] = { duration = GameConfig.MatchDuration, next = MatchState.States.ENDING },
	[MatchState.States.ENDING] = { duration = GameConfig.IntermissionDuration, next = MatchState.States.LOBBY },
}

MatchState.DisplayName = {
	[MatchState.States.LOBBY] = "Waiting for players",
	[MatchState.States.VOTING] = "Vote next map",
	[MatchState.States.STARTING] = "Get ready!",
	[MatchState.States.MATCH] = "Match in progress",
	[MatchState.States.ENDING] = "Match ended",
}

return MatchState
