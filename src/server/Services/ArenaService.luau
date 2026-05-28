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

-- Mood / atmosphere settings layered on top of basic Lighting properties.
-- Each map's preset can override any field; nil = skip that effect.
type AtmosphereCfg = {
	Density: number,    -- 0..1, fog density (volumetric scatter look)
	Color: Color3,      -- near-fog color tint
	Decay: Color3,      -- far-distance color tint
	Glare: number,      -- 0..2, sun bloom around sun direction
	Haze: number,       -- 0..3, extra atmospheric haze layer
}
type BloomCfg = { Intensity: number, Size: number, Threshold: number }
type ColorCorrectionCfg = { Brightness: number, Contrast: number, Saturation: number, TintColor: Color3 }
type SkyCfg = {
	SkyboxBk: string?, SkyboxDn: string?, SkyboxFt: string?,
	SkyboxLf: string?, SkyboxRt: string?, SkyboxUp: string?,
	StarCount: number?,
	SunAngularSize: number?,
	MoonAngularSize: number?,
}

type LightingPreset = {
	Ambient: Color3,
	OutdoorAmbient: Color3,
	Brightness: number,
	ClockTime: number,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
	ColorShift_Top: Color3?,
	Atmosphere: AtmosphereCfg?,
	Bloom: BloomCfg?,
	ColorCorrection: ColorCorrectionCfg?,
	Sky: SkyCfg?,
}

local LIGHTING_PRESETS: { [string]: LightingPreset } = {
	-- WAREHOUSE — sunset golden hour, dust haze, warm tint
	warehouse = {
		Ambient = Color3.fromRGB(70, 55, 40),
		OutdoorAmbient = Color3.fromRGB(120, 90, 60),
		Brightness = 1.6,
		ClockTime = 17.5,
		FogColor = Color3.fromRGB(180, 130, 90),
		FogStart = 60,
		FogEnd = 220,
		ColorShift_Top = Color3.fromRGB(60, 30, 0),
		Atmosphere = { Density = 0.32, Color = Color3.fromRGB(220, 170, 110),
			Decay = Color3.fromRGB(140, 80, 50), Glare = 1.0, Haze = 1.4 },
		Bloom = { Intensity = 0.55, Size = 22, Threshold = 1.4 },
		ColorCorrection = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.15,
			TintColor = Color3.fromRGB(255, 230, 210) },
	},
	-- ROOFTOP — bright midday city, soft haze, slightly hazy distance
	rooftop = {
		Ambient = Color3.fromRGB(90, 110, 140),
		OutdoorAmbient = Color3.fromRGB(140, 170, 200),
		Brightness = 2.6,
		ClockTime = 11,
		FogColor = Color3.fromRGB(170, 200, 230),
		FogStart = 200,
		FogEnd = 700,
		ColorShift_Top = Color3.fromRGB(0, 0, 0),
		Atmosphere = { Density = 0.18, Color = Color3.fromRGB(190, 215, 245),
			Decay = Color3.fromRGB(110, 140, 180), Glare = 0.6, Haze = 0.7 },
		Bloom = { Intensity = 0.4, Size = 18, Threshold = 1.6 },
		ColorCorrection = { Brightness = 0.0, Contrast = 0.08, Saturation = 0.1,
			TintColor = Color3.fromRGB(240, 245, 255) },
	},
	-- DESERT — harsh sun, sand haze, high saturation
	desert = {
		Ambient = Color3.fromRGB(140, 110, 70),
		OutdoorAmbient = Color3.fromRGB(190, 160, 110),
		Brightness = 2.8,
		ClockTime = 13.5,
		FogColor = Color3.fromRGB(220, 195, 145),
		FogStart = 80,
		FogEnd = 350,
		ColorShift_Top = Color3.fromRGB(80, 40, 0),
		Atmosphere = { Density = 0.38, Color = Color3.fromRGB(235, 200, 145),
			Decay = Color3.fromRGB(180, 130, 80), Glare = 1.6, Haze = 2.0 },
		Bloom = { Intensity = 0.65, Size = 24, Threshold = 1.3 },
		ColorCorrection = { Brightness = 0.04, Contrast = 0.15, Saturation = 0.22,
			TintColor = Color3.fromRGB(255, 235, 200) },
	},
	-- METRO — industrial fluorescent indoor, cyan-cool, moody
	metro = {
		Ambient = Color3.fromRGB(95, 100, 115),
		OutdoorAmbient = Color3.fromRGB(120, 130, 150),
		Brightness = 1.7,
		ClockTime = 13,
		FogColor = Color3.fromRGB(90, 100, 120),
		FogStart = 80,
		FogEnd = 260,
		ColorShift_Top = Color3.fromRGB(20, 40, 60),
		Atmosphere = { Density = 0.45, Color = Color3.fromRGB(120, 140, 160),
			Decay = Color3.fromRGB(40, 55, 75), Glare = 0.3, Haze = 1.8 },
		Bloom = { Intensity = 0.7, Size = 28, Threshold = 1.0 },
		ColorCorrection = { Brightness = -0.02, Contrast = 0.18, Saturation = -0.1,
			TintColor = Color3.fromRGB(200, 220, 255) },
	},
	-- HARBOR — early morning misty seaside, cool blue
	harbor = {
		Ambient = Color3.fromRGB(75, 90, 105),
		OutdoorAmbient = Color3.fromRGB(120, 135, 155),
		Brightness = 1.9,
		ClockTime = 9,
		FogColor = Color3.fromRGB(150, 170, 195),
		FogStart = 120,
		FogEnd = 400,
		ColorShift_Top = Color3.fromRGB(0, 0, 0),
		Atmosphere = { Density = 0.40, Color = Color3.fromRGB(180, 200, 220),
			Decay = Color3.fromRGB(90, 120, 150), Glare = 0.7, Haze = 1.6 },
		Bloom = { Intensity = 0.5, Size = 20, Threshold = 1.5 },
		ColorCorrection = { Brightness = 0.01, Contrast = 0.10, Saturation = 0.05,
			TintColor = Color3.fromRGB(220, 235, 255) },
	},
	-- DUST2 — CS-style midday sandy, vibrant warm
	dust2 = {
		Ambient = Color3.fromRGB(155, 130, 90),
		OutdoorAmbient = Color3.fromRGB(210, 180, 130),
		Brightness = 3.0,
		ClockTime = 14,
		FogColor = Color3.fromRGB(235, 210, 160),
		FogStart = 100,
		FogEnd = 400,
		ColorShift_Top = Color3.fromRGB(100, 60, 0),
		Atmosphere = { Density = 0.30, Color = Color3.fromRGB(235, 210, 160),
			Decay = Color3.fromRGB(180, 140, 80), Glare = 1.3, Haze = 1.5 },
		Bloom = { Intensity = 0.6, Size = 22, Threshold = 1.4 },
		ColorCorrection = { Brightness = 0.03, Contrast = 0.13, Saturation = 0.18,
			TintColor = Color3.fromRGB(255, 240, 210) },
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

-- Tag for runtime-added effects so we can clean them up between maps. Plus
-- the effect classes we OWN — when entering arena lighting we wipe ALL
-- instances of these classes from Lighting (not just our prefixed ones),
-- because Roblox stacks duplicate post-process effects: pre-existing
-- Studio-saved Atmosphere/Bloom/ColorCorrection in the place file would
-- double up with ours and make everything look over-saturated / over-fogged
-- (the user-reported "aneh" symptom after publish).
local ARENA_FX_PREFIX = "_ArenaFX_"
local OWNED_EFFECT_CLASSES = {
	["Atmosphere"] = true,
	["BloomEffect"] = true,
	["ColorCorrectionEffect"] = true,
	["Sky"] = true,
}

local function clearArenaEffects()
	for _, c in Lighting:GetChildren() do
		-- Remove prefixed arena effects from previous map
		if c.Name:sub(1, #ARENA_FX_PREFIX) == ARENA_FX_PREFIX then
			c:Destroy()
		-- Also remove any non-prefixed instance of effect classes we own —
		-- prevents stacking with user-authored Studio defaults.
		elseif OWNED_EFFECT_CLASSES[c.ClassName] then
			c:Destroy()
		end
	end
end

local function addOrReplace(className: string, name: string, props: { [string]: any }): Instance
	local fullName = ARENA_FX_PREFIX .. name
	local existing = Lighting:FindFirstChild(fullName)
	if existing then existing:Destroy() end
	local inst = Instance.new(className)
	inst.Name = fullName
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = Lighting
	return inst
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

	-- Wipe any leftover effects from previous map, then re-add this map's set.
	clearArenaEffects()

	if preset.Atmosphere then
		addOrReplace("Atmosphere", "Atmosphere", {
			Density = preset.Atmosphere.Density,
			Color = preset.Atmosphere.Color,
			Decay = preset.Atmosphere.Decay,
			Glare = preset.Atmosphere.Glare,
			Haze = preset.Atmosphere.Haze,
		})
	end
	if preset.Bloom then
		addOrReplace("BloomEffect", "Bloom", {
			Enabled = true,
			Intensity = preset.Bloom.Intensity,
			Size = preset.Bloom.Size,
			Threshold = preset.Bloom.Threshold,
		})
	end
	if preset.ColorCorrection then
		addOrReplace("ColorCorrectionEffect", "ColorCorrection", {
			Enabled = true,
			Brightness = preset.ColorCorrection.Brightness,
			Contrast = preset.ColorCorrection.Contrast,
			Saturation = preset.ColorCorrection.Saturation,
			TintColor = preset.ColorCorrection.TintColor,
		})
	end
	if preset.Sky then
		local sky = addOrReplace("Sky", "Sky", {})
		local s = sky :: Sky
		if preset.Sky.SkyboxBk then s.SkyboxBk = preset.Sky.SkyboxBk end
		if preset.Sky.SkyboxDn then s.SkyboxDn = preset.Sky.SkyboxDn end
		if preset.Sky.SkyboxFt then s.SkyboxFt = preset.Sky.SkyboxFt end
		if preset.Sky.SkyboxLf then s.SkyboxLf = preset.Sky.SkyboxLf end
		if preset.Sky.SkyboxRt then s.SkyboxRt = preset.Sky.SkyboxRt end
		if preset.Sky.SkyboxUp then s.SkyboxUp = preset.Sky.SkyboxUp end
		if preset.Sky.StarCount then s.StarCount = preset.Sky.StarCount end
		if preset.Sky.SunAngularSize then s.SunAngularSize = preset.Sky.SunAngularSize end
		if preset.Sky.MoonAngularSize then s.MoonAngularSize = preset.Sky.MoonAngularSize end
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
	-- Belt-and-suspenders: always wipe arena-added effects on teardown even
	-- if applyLighting(DEFAULT_LIGHTING) didn't run (e.g. default never
	-- captured). Otherwise stale Atmosphere/Bloom from previous map persists
	-- into the next one and double-stacks when the new preset applies.
	clearArenaEffects()
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
