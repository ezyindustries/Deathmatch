--!strict
-- Deathmatch Room: isolated FFA arena at a far offset (parallel to casual + practice).
-- Self-contained — owns its room geometry, bots, and player spawn/respawn loop.
-- Doesn't touch the match state machine or any other mode's services.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BotModel = require(Shared.Modules.BotModel)
local Remotes = require(Shared.Modules.Remotes)

local ScoringService = require(script.Parent.ScoringService)
local BotAnimator = require(script.Parent.Parent.Modules.BotAnimator)

local DMRoomService = {}

-- Location: far from training (-2000) and main arena (0) so nothing overlaps.
local DM_ORIGIN = Vector3.new(2000, 100, 0)
local DM_RESPAWN_DELAY = 0.5
local BOT_COUNT = 5
local BOT_HEALTH = 100
local BOT_DAMAGE = 8
local BOT_RANGE = 90
local REACTION_TIME = 0.4
local BURST_SIZE = 3
local BURST_INTER = 0.18
local BURST_COOLDOWN_MIN = 0.8
local BURST_COOLDOWN_MAX = 1.5
local AIM_SPREAD_PER_STUD = 0.008
local AIM_SPREAD_MAX = 1.5
local NORMAL_WALKSPEED = 12
local COMBAT_WALKSPEED = 17
local OPTIMAL_RANGE = 24
local TOO_CLOSE_RANGE = 10
local STRAFE_INTERVAL_MIN = 0.5
local STRAFE_INTERVAL_MAX = 1.1
local BEHAVIOR_INTERVAL = 0.35

local dmPlayers: { [number]: boolean } = {}
local roomFolder: Folder? = nil
local spawnPads: { BasePart } = {}
local bots: { Model } = {}
local botMuzzle: { [Model]: Attachment } = {}
local nameIndex = 0
local botNames = { "Recruit", "Phantom", "Razor", "Vortex", "Echo", "Specter", "Wraith", "Hunter" }

type AIState = {
	nextFireAt: number,
	burstRemaining: number,
	targetSeenAt: number?,
	targetKey: any?,
	strafeDir: number,
	strafeUntilAt: number,
}
local botState: { [Model]: AIState } = {}
local lastBehaviorAt: { [Model]: number } = {}

local function newAIState(): AIState
	return {
		nextFireAt = 0,
		burstRemaining = 0,
		targetSeenAt = nil,
		targetKey = nil,
		strafeDir = if math.random() < 0.5 then -1 else 1,
		strafeUntilAt = 0,
	}
end

local function clearTargetLock(state: AIState)
	state.targetKey = nil
	state.targetSeenAt = nil
	state.burstRemaining = 0
end

-- ============================================================
-- ROOM BUILD (one-time)
-- ============================================================
local function makePart(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

local function buildRoom()
	if roomFolder then return end
	roomFolder = Instance.new("Folder")
	roomFolder.Name = "DMRoom"
	roomFolder.Parent = Workspace

	local floorCol = Color3.fromRGB(70, 75, 90)
	local wallCol  = Color3.fromRGB(180, 160, 130)
	local accentCol= Color3.fromRGB(220, 100, 80)

	-- 120×80 floor
	makePart(roomFolder, {
		Name = "Floor", Size = Vector3.new(120, 2, 80),
		Position = DM_ORIGIN + Vector3.new(0, -1, 0),
		Color = floorCol, Material = Enum.Material.Concrete,
	})
	-- Walls
	makePart(roomFolder, { Name="N", Size=Vector3.new(120,28,2), Position=DM_ORIGIN+Vector3.new(0,14,-40), Color=wallCol, Material=Enum.Material.Brick })
	makePart(roomFolder, { Name="S", Size=Vector3.new(120,28,2), Position=DM_ORIGIN+Vector3.new(0,14, 40), Color=wallCol, Material=Enum.Material.Brick })
	makePart(roomFolder, { Name="W", Size=Vector3.new(2,28,80),  Position=DM_ORIGIN+Vector3.new(-60,14,0), Color=wallCol, Material=Enum.Material.Brick })
	makePart(roomFolder, { Name="E", Size=Vector3.new(2,28,80),  Position=DM_ORIGIN+Vector3.new( 60,14,0), Color=wallCol, Material=Enum.Material.Brick })
	makePart(roomFolder, { Name="Ceiling", Size=Vector3.new(120,1,80), Position=DM_ORIGIN+Vector3.new(0,28,0), Color=Color3.fromRGB(40,45,55), Material=Enum.Material.Slate })

	-- Cover boxes scattered around
	local coverPositions = {
		Vector3.new(-30, 2, -10), Vector3.new( 30, 2,  10),
		Vector3.new(-10, 2,  20), Vector3.new( 10, 2, -20),
		Vector3.new(-45, 2,  25), Vector3.new( 45, 2, -25),
		Vector3.new(  0, 2,   0), Vector3.new(-25, 2,  -5),
		Vector3.new( 25, 2,   5),
	}
	for _, p in coverPositions do
		makePart(roomFolder, {
			Name = "Crate", Size = Vector3.new(5, 4, 5),
			Position = DM_ORIGIN + p,
			Color = Color3.fromRGB(140, 95, 50), Material = Enum.Material.WoodPlanks,
		})
	end

	-- Accent strip (top of N wall)
	makePart(roomFolder, {
		Name = "Accent", Size = Vector3.new(120, 1, 0.5),
		Position = DM_ORIGIN + Vector3.new(0, 27, -39),
		Color = accentCol, Material = Enum.Material.Neon,
	})

	-- Spawn pads (8 around perimeter, invisible)
	local spawnLocations = {
		Vector3.new(-50, 3, -30), Vector3.new( 50, 3, -30),
		Vector3.new(-50, 3,  30), Vector3.new( 50, 3,  30),
		Vector3.new(-50, 3,   0), Vector3.new( 50, 3,   0),
		Vector3.new(  0, 3, -30), Vector3.new(  0, 3,  30),
	}
	for _, sp in spawnLocations do
		local pad = makePart(roomFolder, {
			Name = "DMSpawn",
			Size = Vector3.new(3, 0.2, 3),
			Position = DM_ORIGIN + sp,
			Color = Color3.fromRGB(220, 100, 80),
			Material = Enum.Material.Neon,
			Transparency = 0.7,
		})
		table.insert(spawnPads, pad)
	end
end

-- ============================================================
-- BOT AI (free-for-all — bots shoot anything not themselves)
-- ============================================================
local function findNearestTarget(self: Model, botPos: Vector3): (Model?, BasePart?, Humanoid?, string?, any)
	local nearestChar: Model? = nil
	local nearestHRP: BasePart? = nil
	local nearestHum: Humanoid? = nil
	local nearestType: string? = nil
	local nearestId: any = nil
	local nearestDist = math.huge
	-- Players in DM only
	for _, p in Players:GetPlayers() do
		if not dmPlayers[p.UserId] then continue end
		local char = p.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		local d = (hrp.Position - botPos).Magnitude
		if d < nearestDist and d < BOT_RANGE then
			nearestDist = d; nearestChar = char; nearestHRP = hrp; nearestHum = hum
			nearestType = "player"; nearestId = p
		end
	end
	-- Other bots
	for _, other in bots do
		if other == self then continue end
		local hum = other:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = other:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		local d = (hrp.Position - botPos).Magnitude
		if d < nearestDist and d < BOT_RANGE then
			nearestDist = d; nearestChar = other; nearestHRP = hrp; nearestHum = hum
			nearestType = "bot"; nearestId = other.Name
		end
	end
	return nearestChar, nearestHRP, nearestHum, nearestType, nearestId
end

local function tryFireAt(bot: Model, state: AIState, targetChar: Model, targetHRP: BasePart,
	targetHum: Humanoid, targetType: string, targetId: any)
	local now = os.clock()
	if now < state.nextFireAt then return end
	local key = if targetType == "player" then (targetId :: Player).UserId else targetId
	if state.targetKey ~= key then
		state.targetKey = key; state.targetSeenAt = now; state.burstRemaining = 0
		return
	end
	if state.targetSeenAt and now < state.targetSeenAt + REACTION_TIME then return end
	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local lookTarget = Vector3.new(targetHRP.Position.X, hrp.Position.Y, targetHRP.Position.Z)
	hrp.CFrame = CFrame.lookAt(hrp.Position, lookTarget)
	local muzzle = botMuzzle[bot]
	local origin = if muzzle then muzzle.WorldPosition else hrp.Position + Vector3.new(0, 1, 0)
	local toTarget = targetHRP.Position - origin
	local dist = toTarget.Magnitude
	local spread = math.min(dist * AIM_SPREAD_PER_STUD, AIM_SPREAD_MAX)
	local jitter = Vector3.new(
		(math.random() - 0.5) * 2 * spread,
		(math.random() - 0.5) * 2 * spread * 0.5,
		(math.random() - 0.5) * 2 * spread
	)
	local direction = (toTarget + jitter).Unit * BOT_RANGE
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot }
	local result = Workspace:Raycast(origin, direction, params)
	local endPos = if result then result.Position else origin + direction
	local hitNormal = if result then result.Normal else Vector3.new(0, 1, 0)
	local hitMaterial = if result and result.Instance then tostring(result.Instance.Material.Name) else "Plastic"
	local hitIsPlayer = false
	if result then
		local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
		if hitModel and Players:GetPlayerFromCharacter(hitModel) then
			hitIsPlayer = true
		end
	end
	Remotes.ShotFired:FireAllClients({
		shooterUserId = nil, shooterBotName = bot.Name,
		weaponId = "rifle", weaponSlot = "primary",
		origin = origin, hitPosition = endPos,
		hitNormal = hitNormal, hitMaterial = hitMaterial,
		hitIsPlayer = hitIsPlayer, didHit = result ~= nil,
	})
	if result and result.Instance:IsDescendantOf(targetChar) then
		local prevHealth = targetHum.Health
		targetHum:TakeDamage(BOT_DAMAGE)
		if prevHealth > 0 and targetHum.Health <= 0 then
			local victimName: string
			if targetType == "player" then
				victimName = (targetId :: Player).Name
				ScoringService.BotKilledPlayer(bot.Name, targetId :: Player)
			else
				victimName = tostring(targetId)
				ScoringService.BotKilledBot(bot.Name, targetId :: string)
			end
			Remotes.KillFeedEntry:FireAllClients({
				killer = bot.Name, victim = victimName,
				weapon = "Rifle", weaponId = "rifle", weaponSlot = "primary",
				isHeadshot = false, victimPosition = result.Position,
			})
		end
	end
	if state.burstRemaining <= 0 then
		state.burstRemaining = BURST_SIZE - 1
		state.nextFireAt = now + BURST_INTER
	elseif state.burstRemaining == 1 then
		state.burstRemaining = 0
		state.nextFireAt = now + BURST_COOLDOWN_MIN + math.random() * (BURST_COOLDOWN_MAX - BURST_COOLDOWN_MIN)
	else
		state.burstRemaining -= 1
		state.nextFireAt = now + BURST_INTER
	end
end

local function botBehavior(bot: Model, state: AIState)
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local now = os.clock()
	local targetChar, targetHRP = findNearestTarget(bot, hrp.Position)
	if targetChar and targetHRP then
		hum.WalkSpeed = COMBAT_WALKSPEED
		local toTarget = targetHRP.Position - hrp.Position
		local dist = toTarget.Magnitude
		if now > state.strafeUntilAt then
			state.strafeDir = if math.random() < 0.5 then -1 else 1
			state.strafeUntilAt = now + STRAFE_INTERVAL_MIN + math.random() * (STRAFE_INTERVAL_MAX - STRAFE_INTERVAL_MIN)
		end
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flat.Magnitude < 0.01 then flat = Vector3.new(1, 0, 0) end
		local fwd = flat.Unit
		local right = Vector3.new(-fwd.Z, 0, fwd.X) * state.strafeDir
		local dest: Vector3
		if dist < TOO_CLOSE_RANGE then
			dest = hrp.Position + (-fwd * 6) + (right * 4)
		elseif dist > OPTIMAL_RANGE + 6 then
			dest = hrp.Position + (fwd * math.min(dist - OPTIMAL_RANGE, 12)) + (right * 3)
		else
			dest = hrp.Position + (right * 6)
		end
		hum:MoveTo(dest)
		return
	end
	clearTargetLock(state)
	hum.WalkSpeed = NORMAL_WALKSPEED
	if #spawnPads > 0 then
		local sp = spawnPads[math.random(#spawnPads)]
		hum:MoveTo(sp.Position)
	end
end

-- ============================================================
-- BOT LIFECYCLE
-- ============================================================
local respawnBot: (oldBot: Model) -> ()

respawnBot = function(oldBot: Model)
	local name = oldBot.Name
	local idx: number? = nil
	for i, b in bots do
		if b == oldBot then idx = i; break end
	end
	if not idx then return end
	BotAnimator.Unregister(oldBot)
	botState[oldBot] = nil
	botMuzzle[oldBot] = nil
	lastBehaviorAt[oldBot] = nil
	oldBot:Destroy()
	if #spawnPads == 0 then return end
	local sp = spawnPads[math.random(#spawnPads)]
	local fresh = BotModel.Build(name, BOT_HEALTH)
	fresh.Parent = Workspace
	fresh:PivotTo(sp.CFrame + Vector3.new(0, 5, 0))
	bots[idx] = fresh
	botState[fresh] = newAIState()
	local muzzle = BotModel.EquipRifle(fresh)
	if muzzle then botMuzzle[fresh] = muzzle end
	BotAnimator.Register(fresh)
	local hum = fresh:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			task.delay(DM_RESPAWN_DELAY, function()
				if fresh.Parent then respawnBot(fresh) end
			end)
		end)
	end
end

local function spawnBots()
	if #bots >= BOT_COUNT then return end
	for i = #bots + 1, BOT_COUNT do
		if #spawnPads == 0 then break end
		nameIndex += 1
		local name = botNames[((nameIndex - 1) % #botNames) + 1] .. "_DM" .. tostring(nameIndex)
		local sp = spawnPads[math.random(#spawnPads)]
		local bot = BotModel.Build(name, BOT_HEALTH)
		bot.Parent = Workspace
		bot:PivotTo(sp.CFrame + Vector3.new(0, 5, 0))
		table.insert(bots, bot)
		botState[bot] = newAIState()
		local muzzle = BotModel.EquipRifle(bot)
		if muzzle then botMuzzle[bot] = muzzle end
		BotAnimator.Register(bot)
		ScoringService.RegisterBot(name)
		local hum = bot:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function()
				task.delay(DM_RESPAWN_DELAY, function()
					if bot.Parent then respawnBot(bot) end
				end)
			end)
		end
	end
end

local function clearBots()
	for _, bot in bots do
		BotAnimator.Unregister(bot)
		ScoringService.UnregisterBot(bot.Name)
		bot:Destroy()
	end
	table.clear(bots)
	table.clear(botState)
	table.clear(botMuzzle)
	table.clear(lastBehaviorAt)
end

-- Global AI tick (fire + behavior)
task.spawn(function()
	while true do
		task.wait(0.1)
		if #bots == 0 then continue end
		local now = os.clock()
		for _, bot in bots do
			if not bot.Parent then continue end
			local hum = bot:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then continue end
			local state = botState[bot]
			if not state then
				state = newAIState()
				botState[bot] = state
			end
			if now - (lastBehaviorAt[bot] or 0) >= BEHAVIOR_INTERVAL then
				botBehavior(bot, state)
				lastBehaviorAt[bot] = now
			end
			local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local targetChar, targetHRP, targetHum, targetType, targetId = findNearestTarget(bot, hrp.Position)
				if targetChar and targetHRP and targetHum and targetType then
					tryFireAt(bot, state, targetChar, targetHRP, targetHum, targetType, targetId)
				else
					clearTargetLock(state)
				end
			end
		end
	end
end)

-- ============================================================
-- PLAYER API
-- ============================================================
local function teleportPlayerToDMSpawn(player: Player)
	if #spawnPads == 0 then return end
	local sp = spawnPads[math.random(#spawnPads)]
	local char = player.Character
	if not char then return end
	char:PivotTo(sp.CFrame + Vector3.new(0, 5, 0))
end

local function hookPlayerDeath(player: Player)
	-- Per-character death hook (re-registered every spawn)
	local function attach(char: Model)
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		if not hum then return end
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.NameDisplayDistance = 0
		hum.HealthDisplayDistance = 0
		hum.Died:Connect(function()
			if not dmPlayers[player.UserId] then return end
			if player.Character then player.Character:Destroy() end
			task.wait(DM_RESPAWN_DELAY)
			if not dmPlayers[player.UserId] then return end
			if not player.Parent then return end
			player:LoadCharacter()
			local fresh = player.Character or player.CharacterAdded:Wait()
			fresh:WaitForChild("HumanoidRootPart", 3)
			teleportPlayerToDMSpawn(player)
		end)
	end
	if player.Character then attach(player.Character) end
	player.CharacterAdded:Connect(attach)
end

function DMRoomService.IsInDM(userId: number): boolean
	return dmPlayers[userId] == true
end

function DMRoomService.JoinDM(player: Player)
	buildRoom()
	spawnBots()
	dmPlayers[player.UserId] = true
	player:LoadCharacter()
	task.wait(0.2)
	teleportPlayerToDMSpawn(player)
	hookPlayerDeath(player)
	print(string.format("[DMRoom] %s joined DM", player.Name))
end

function DMRoomService.LeaveDM(player: Player)
	if not dmPlayers[player.UserId] then return end
	dmPlayers[player.UserId] = nil
	-- If no DM players left, clear bots to save resources
	local any = false
	for _ in dmPlayers do any = true; break end
	if not any then
		clearBots()
	end
	print(string.format("[DMRoom] %s left DM", player.Name))
end

Players.PlayerRemoving:Connect(function(player: Player)
	DMRoomService.LeaveDM(player)
end)

return DMRoomService
