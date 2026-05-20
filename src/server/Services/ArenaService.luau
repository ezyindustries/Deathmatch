--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Modules.MatchState)

local MatchStateService = require(script.Parent.MatchStateService)
local VotingService = require(script.Parent.VotingService)
local TrainingService = require(script.Parent.TrainingService)

local MapBuilders = require(script.Parent.Parent.Modules.MapBuilders)

local ArenaService = {}

local ARENA_ORIGIN = Vector3.new(2000, 100, 0)
local KILL_Y = -200
local SPAWN_PROTECTION_SECONDS = 2
local arenaFolder: Folder? = nil

-- Sweep at service load: kill any pre-existing "ActiveArena" folders saved
-- into the place file (deathmatch.rbxl). These ghost folders are empty but
-- their presence makes Workspace:FindFirstChild("ActiveArena") return them
-- instead of our runtime arena — breaking bot spawn fallback.
for _, c in Workspace:GetChildren() do
	if c.Name == "ActiveArena" and c:IsA("Folder") then
		c:Destroy()
	end
end

type LightingPreset = {
	Ambient: Color3,
	OutdoorAmbient: Color3,
	Brightness: number,
	ClockTime: number,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
	ColorShift_Top: Color3?,
}

local LIGHTING_PRESETS: { [string]: LightingPreset } = {
	warehouse = {
		Ambient = Color3.fromRGB(70, 55, 40),
		OutdoorAmbient = Color3.fromRGB(120, 90, 60),
		Brightness = 1.6,
		ClockTime = 17.5,
		FogColor = Color3.fromRGB(180, 130, 90),
		FogStart = 60,
		FogEnd = 220,
		ColorShift_Top = Color3.fromRGB(60, 30, 0),
	},
	rooftop = {
		Ambient = Color3.fromRGB(90, 110, 140),
		OutdoorAmbient = Color3.fromRGB(140, 170, 200),
		Brightness = 2.6,
		ClockTime = 11,
		FogColor = Color3.fromRGB(170, 200, 230),
		FogStart = 200,
		FogEnd = 700,
		ColorShift_Top = Color3.fromRGB(0, 0, 0),
	},
	desert = {
		Ambient = Color3.fromRGB(140, 110, 70),
		OutdoorAmbient = Color3.fromRGB(190, 160, 110),
		Brightness = 2.8,
		ClockTime = 13.5,
		FogColor = Color3.fromRGB(220, 195, 145),
		FogStart = 80,
		FogEnd = 350,
		ColorShift_Top = Color3.fromRGB(80, 40, 0),
	},
	metro = {
		Ambient = Color3.fromRGB(95, 100, 115),       -- brighter ambient (was 25,35,50)
		OutdoorAmbient = Color3.fromRGB(120, 130, 150),
		Brightness = 1.7,                              -- was 0.9 (still dim-ish, not noon)
		ClockTime = 13,                                -- daytime indoor feel (was 22 = night)
		FogColor = Color3.fromRGB(90, 100, 120),
		FogStart = 80,                                 -- push fog back (was 30)
		FogEnd = 260,                                  -- was 120
		ColorShift_Top = Color3.fromRGB(20, 40, 60),
	},
	harbor = {
		Ambient = Color3.fromRGB(75, 90, 105),
		OutdoorAmbient = Color3.fromRGB(120, 135, 155),
		Brightness = 1.9,
		ClockTime = 9,
		FogColor = Color3.fromRGB(150, 170, 195),
		FogStart = 120,
		FogEnd = 400,
		ColorShift_Top = Color3.fromRGB(0, 0, 0),
	},
	dust2 = {
		Ambient = Color3.fromRGB(155, 130, 90),
		OutdoorAmbient = Color3.fromRGB(210, 180, 130),
		Brightness = 3.0,
		ClockTime = 14,
		FogColor = Color3.fromRGB(235, 210, 160),
		FogStart = 100,
		FogEnd = 400,
		ColorShift_Top = Color3.fromRGB(100, 60, 0),
	},
}

local DEFAULT_LIGHTING: LightingPreset? = nil

local function captureDefaultLighting()
	if DEFAULT_LIGHTING then
		return
	end
	DEFAULT_LIGHTING = {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		FogColor = Lighting.FogColor,
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		ColorShift_Top = Lighting.ColorShift_Top,
	}
end

local function applyLighting(preset: LightingPreset)
	Lighting.Ambient = preset.Ambient
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.Brightness = preset.Brightness
	Lighting.ClockTime = preset.ClockTime
	Lighting.FogColor = preset.FogColor
	Lighting.FogStart = preset.FogStart
	Lighting.FogEnd = preset.FogEnd
	if preset.ColorShift_Top then
		Lighting.ColorShift_Top = preset.ColorShift_Top
	end
end

local function teardownArena()
	if arenaFolder then
		arenaFolder:Destroy()
		arenaFolder = nil
	end
	-- Also purge any STRAY "ActiveArena" folders left in Workspace by previous
	-- sessions or by the persisted deathmatch.rbxl place file. Without this,
	-- FindFirstChild("ActiveArena") elsewhere can hit the empty stub instead
	-- of our live arena — which made getArenaSpawnPoints return zero spawns
	-- mid-match, so bots that fell into the void couldn't respawn.
	for _, c in Workspace:GetChildren() do
		if c.Name == "ActiveArena" and c:IsA("Folder") then
			c:Destroy()
		end
	end
	if DEFAULT_LIGHTING then
		applyLighting(DEFAULT_LIGHTING)
	end
end

local function grantSpawnProtection(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local existing = character:FindFirstChildOfClass("ForceField")
	if existing then
		existing:Destroy()
	end
	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Parent = character
	task.delay(SPAWN_PROTECTION_SECONDS, function()
		if ff and ff.Parent then
			ff:Destroy()
		end
	end)
end

local function buildArena(mapId: string): boolean
	teardownArena()
	local builder = (MapBuilders :: any)[mapId]
	if not builder then
		warn(string.format("[Arena] No builder for map: %s", mapId))
		return false
	end
	captureDefaultLighting()
	local folder = Instance.new("Folder")
	folder.Name = "ActiveArena"
	folder:SetAttribute("mapId", mapId)
	folder.Parent = Workspace
	arenaFolder = folder
	builder(folder, ARENA_ORIGIN)

	local preset = LIGHTING_PRESETS[mapId]
	if preset then
		applyLighting(preset)
	end

	print(string.format("[Arena] Built map: %s", mapId))
	return true
end

local function spawnsIn(folder: Instance?): { SpawnLocation }
	local list: { SpawnLocation } = {}
	if not folder then
		return list
	end
	for _, c in folder:GetChildren() do
		if c:IsA("SpawnLocation") then
			table.insert(list, c)
		end
	end
	return list
end

local function getArenaSpawns(): { SpawnLocation }
	if not arenaFolder then
		return {}
	end
	return spawnsIn(arenaFolder:FindFirstChild("Spawns"))
end

-- Casual-only: filter spawns by Team attribute ("T" or "CT") for team-aware
-- spawn assignment. Falls back to all spawns if none are tagged.
function ArenaService.GetTeamSpawns(team: string): { SpawnLocation }
	local all = getArenaSpawns()
	local filtered: { SpawnLocation } = {}
	for _, sp in all do
		if sp:GetAttribute("Team") == team then
			table.insert(filtered, sp)
		end
	end
	if #filtered == 0 then
		-- Map didn't tag spawns by team — return all (graceful fallback)
		return all
	end
	return filtered
end

-- Casual-only: return parts in arena's BombSites folder (each part has
-- BombSite attribute "A" or "B"). These are volumes T must stand inside to plant.
function ArenaService.GetBombSites(): { BasePart }
	local result: { BasePart } = {}
	if not arenaFolder then return result end
	local folder = arenaFolder:FindFirstChild("BombSites")
	if not folder then return result end
	for _, c in folder:GetChildren() do
		if c:IsA("BasePart") then
			table.insert(result, c)
		end
	end
	return result
end

function ArenaService.GetArenaFolder(): Folder?
	return arenaFolder
end

local function getLobbySpawns(): { SpawnLocation }
	return spawnsIn(Workspace:FindFirstChild("LobbySpawns"))
end

local function setLobbySpawnsEnabled(enabled: boolean)
	for _, sp in getLobbySpawns() do
		sp.Enabled = enabled
	end
end

local function teleportPlayerTo(player: Player, cf: CFrame)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	root.CFrame = cf
end

ArenaService.TeleportPlayerTo = teleportPlayerTo
ArenaService.GrantSpawnProtection = grantSpawnProtection

-- Respawn guards: callbacks consulted by the CharacterAdded auto-teleport.
-- If ANY guard returns false for the player, the auto-teleport is skipped.
-- CasualService registers a guard that returns false for players who died
-- during a round (preventing them from being teleported back into combat).
local respawnGuards: { (Player) -> boolean } = {}
function ArenaService.RegisterRespawnGuard(guard: (Player) -> boolean): () -> ()
	table.insert(respawnGuards, guard)
	return function()
		for i, g in respawnGuards do
			if g == guard then
				table.remove(respawnGuards, i)
				return
			end
		end
	end
end

local function passesRespawnGuards(player: Player): boolean
	for _, g in respawnGuards do
		if not g(player) then return false end
	end
	return true
end

local function teleportAliveTo(spawns: { SpawnLocation })
	if #spawns == 0 then
		return
	end
	for _, p in Players:GetPlayers() do
		if TrainingService.IsTraining(p.UserId) then
			continue -- training players stay in training room
		end
		local okDM, DMRoomService = pcall(require, script.Parent.DMRoomService)
		if okDM and DMRoomService.IsInDM and DMRoomService.IsInDM(p.UserId) then
			continue -- DM room players stay in DM room
		end
		local character = p.Character
		if not character then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end
		local sp = spawns[math.random(#spawns)]
		teleportPlayerTo(p, sp.CFrame + Vector3.new(0, 5, 0))
		grantSpawnProtection(p)
	end
end

-- Out-of-bounds void death: catch falls into the gap between arenas/lobby
local oobAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	oobAccumulator += dt
	if oobAccumulator < 0.4 then
		return
	end
	oobAccumulator = 0
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if not character then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		if root.Position.Y < KILL_Y then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end
	end
end)

-- Brief invulnerability on natural respawn during a match (skip for training).
-- Also: teleport mid-match joiners to a random arena spawn point.
Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		-- Capture state BEFORE wait to avoid race with state transition
		local stateBefore = MatchStateService.GetState().state
		task.wait(0.1)
		if not player.Parent then return end -- player left during wait
		if TrainingService.IsTraining(player.UserId) then
			return
		end
		-- Skip arena teleport for DM-room players (they spawn in their isolated room).
		-- Lazy-require to dodge module-load circular deps.
		local okDM, DMRoomService = pcall(require, script.Parent.DMRoomService)
		if okDM and DMRoomService.IsInDM and DMRoomService.IsInDM(player.UserId) then
			return
		end
		-- Only teleport if state was MATCH/STARTING when char spawned (not changed during wait)
		if stateBefore == MatchState.States.MATCH or stateBefore == MatchState.States.STARTING then
			local stateNow = MatchStateService.GetState().state
			if stateNow == MatchState.States.MATCH or stateNow == MatchState.States.STARTING then
				-- Casual respawn guards: if a guard rejects (e.g., dead-in-round),
				-- skip auto-teleport; CasualService manages spectator placement.
				if not passesRespawnGuards(player) then
					return
				end
				local spawns = getArenaSpawns()
				if #spawns > 0 then
					local sp = spawns[math.random(#spawns)]
					teleportPlayerTo(player, sp.CFrame + Vector3.new(0, 5, 0))
				end
				grantSpawnProtection(player)
			end
		end
	end)
end)

MatchStateService.StateChanged:Connect(function(newState: MatchState.State)
	print("[Arena] State changed to:", newState)
	if newState == MatchState.States.STARTING then
		-- Force-close voting synchronously to avoid race with VotingService's own listener
		local winner = VotingService.EndVoting()
		print("[Arena] STARTING — winner =", winner)
		if not winner then
			warn("[Arena] No winner from voting — skipping arena build.")
			return
		end
		if not buildArena(winner) then
			warn("[Arena] buildArena returned false")
			return
		end
		setLobbySpawnsEnabled(false)
		task.wait(0.15)
		local spawns = getArenaSpawns()
		print("[Arena] Teleporting", #Players:GetPlayers(), "players to", #spawns, "spawn points")
		teleportAliveTo(spawns)
	elseif newState == MatchState.States.ENDING then
		task.wait(2)
		teleportAliveTo(getLobbySpawns())
		teardownArena()
		setLobbySpawnsEnabled(true)
	end
end)

return ArenaService
