--!strict
-- Deathmatch bots: walking R6 AI dummies that fill empty slots up to TARGET_PLAYER_COUNT.
-- Bots can move around the arena, shoot players AND each other, take damage, respawn.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Modules.MatchState)
local BotModel = require(Shared.Modules.BotModel)
local Remotes = require(Shared.Modules.Remotes)
local DMTeams = require(Shared.Modules.DMTeams)
local MatchStateService = require(script.Parent.MatchStateService)
local ScoringService = require(script.Parent.ScoringService)
local BotAnimator = require(script.Parent.Parent.Modules.BotAnimator)

local DeathmatchBotService = {}

-- Lazy-require DeathmatchTeamService so we don't depend on its init order.
-- Both services are auto-loaded, but ordering isn't deterministic.
local function teamSvc()
	return require(script.Parent.DeathmatchTeamService)
end

-- Total combatants (players + bots) target. 10v10 TDM → 20 total.
-- Solo player = 1 + 19 bots = 20 combatants split 10 vs 10.
local TARGET_PLAYER_COUNT = DMTeams.TARGET
local BOT_HEALTH = 100
local BOT_DAMAGE = 8              -- damage per shot
local BOT_RANGE = 90              -- engagement distance
local BOT_RESPAWN_DELAY = 0.5  -- near-instant respawn so the arena stays populated
local BOT_WALK_SPEED = 12         -- studs/sec (wander)

-- Smart AI tunables — same shape as CasualBotService so behavior feels consistent.
local REACTION_TIME = 0.4
local BURST_SIZE = 3
local BURST_INTER = 0.18
local BURST_COOLDOWN_MIN = 0.8
local BURST_COOLDOWN_MAX = 1.5
local AIM_SPREAD_PER_STUD = 0.008    -- tighter CS-style small spread (was 0.014)
local AIM_SPREAD_MAX = 1.5           -- (was 4)
local STRAFE_INTERVAL_MIN = 0.5
local STRAFE_INTERVAL_MAX = 1.1
local COMBAT_WALKSPEED = 17
local OPTIMAL_RANGE = 24
local TOO_CLOSE_RANGE = 10
local FLEE_HP = 25
local BEHAVIOR_INTERVAL = 0.35

local bots: { Model } = {}
local botMuzzle: { [Model]: Attachment } = {}
local botNames = { "Recruit", "Phantom", "Razor", "Vortex", "Echo", "Specter", "Wraith", "Hunter" }
local nameIndex = 0

-- Void-rescue tracking. Watchdog flags any bot whose HRP.Y < -100 and forces
-- a rebuild. If the SAME bot keeps falling into the void after multiple
-- rescues (rebuildBot can't find spawns, build fails, or the fresh model
-- still ends up below the floor), we eventually give up so we don't flood
-- the console + waste CPU forever. Counter is keyed by bot NAME (not Model)
-- because rebuildBot swaps the Model instance each pass — the name is the
-- only stable identity across rebuilds.
local VOID_RESCUE_MAX_ATTEMPTS = 2
local voidRescueAttempts: { [string]: number } = {}
-- Track void-rescued names that we've already given up on so we never try to
-- rebuild them again for the remainder of the match (cleared on clearBots).
local voidGaveUp: { [string]: boolean } = {}

type BotAIState = {
	nextFireAt: number,
	burstRemaining: number,
	targetSeenAt: number?,
	targetKey: any?,
	strafeDir: number,
	strafeUntilAt: number,
	-- Evasion (on-hit dodge) state — set by HealthChanged listener,
	-- consumed by botBehavior to force a strafe-jump perpendicular to attacker.
	lastHitAt: number?,
	lastHealth: number,
	evasionDir: number,
	evasionUntilAt: number,
	jumpedOnEvasion: boolean,
	-- Scan state (look-around when no target visible)
	nextScanAt: number,
}
local botState: { [Model]: BotAIState } = {}
local lastBehaviorAt: { [Model]: number } = {}

local function newAIState(): BotAIState
	return {
		nextFireAt = 0,
		burstRemaining = 0,
		targetSeenAt = nil,
		targetKey = nil,
		strafeDir = if math.random() < 0.5 then -1 else 1,
		strafeUntilAt = 0,
		lastHitAt = nil,
		lastHealth = BOT_HEALTH,
		evasionDir = if math.random() < 0.5 then -1 else 1,
		evasionUntilAt = 0,
		jumpedOnEvasion = false,
		nextScanAt = 0,
	}
end

-- Per-team palettes for the BotModel.Build colors override. Blue for team A
-- ("Kawan" / friendly), red for team B ("Lawan" / enemy). Legs/arms stay
-- desaturated so the team tint reads from the torso/head silhouette without
-- making every limb scream the same hue.
local TEAM_BOT_COLORS: { [string]: BotModel.BotColors } = {
	A = {
		torso    = Color3.fromRGB(60, 110, 200),
		head     = Color3.fromRGB(200, 170, 140),
		leftArm  = Color3.fromRGB(60, 110, 200),
		rightArm = Color3.fromRGB(60, 110, 200),
		leftLeg  = Color3.fromRGB(30, 35, 50),
		rightLeg = Color3.fromRGB(30, 35, 50),
	},
	B = {
		torso    = Color3.fromRGB(180, 55, 55),
		head     = Color3.fromRGB(200, 170, 140),
		leftArm  = Color3.fromRGB(180, 55, 55),
		rightArm = Color3.fromRGB(180, 55, 55),
		leftLeg  = Color3.fromRGB(40, 35, 35),
		rightLeg = Color3.fromRGB(40, 35, 35),
	},
}

-- Track each bot's team across rebuilds so it stays on the same side across
-- respawns. We key by Model — when a bot is destroyed + rebuilt we copy the
-- prior team onto the new Model via this map.
local botTeam: { [Model]: DMTeams.TeamId } = {}

-- Pick which team the next-spawning bot should join. We count current bot
-- assignments (not the overall combatant count) so bot fill stays balanced
-- regardless of how players have lined up.
local function pickBotTeam(): DMTeams.TeamId
	local a, b = 0, 0
	for _, t in botTeam do
		if t == "A" then a += 1 else b += 1 end
	end
	if a <= b then return "A" end
	return "B"
end

local function clearTargetLock(state: BotAIState)
	state.targetKey = nil
	state.targetSeenAt = nil
	state.burstRemaining = 0
end

-- DIAGNOSTIC MODE: spawn bots within ~30 studs of the first live player so the
-- player can immediately see them and confirm rendering works on their device.
-- Set to false once bots are visually confirmed in production.
local SPAWN_NEAR_PLAYER = true

-- Sort arena spawn points by distance to a given world position (ascending).
local function spawnsByDistanceTo(pos: Vector3): { BasePart }
	local arena = Workspace:FindFirstChild("ActiveArena")
	if not arena then return {} end
	local spawnsFolder = arena:FindFirstChild("Spawns")
	if not spawnsFolder then return {} end
	local result: { BasePart } = {}
	for _, child in spawnsFolder:GetChildren() do
		if child:IsA("BasePart") then table.insert(result, child) end
	end
	table.sort(result, function(a, b)
		return (a.Position - pos).Magnitude < (b.Position - pos).Magnitude
	end)
	return result
end

-- Try to find a "reference position" the bots should spawn near.
-- ONLY returns a position if the player is actually IN the arena (close to
-- one of the arena spawn points). If the player is still at the lobby, we
-- return nil so the caller falls back to plain arena spawns — otherwise
-- the "near player" spawn would dump bots in the lobby, useless.
--
-- Heuristic: take the median spawn Y, accept the player ref only if they're
-- within ±20 studs of it (so the arena-spawn vs lobby check is automatic
-- regardless of which map is active).
local function findReferencePlayerPos(): Vector3?
	if not SPAWN_NEAR_PLAYER then return nil end
	local arena = Workspace:FindFirstChild("ActiveArena")
	local spawnsFolder = arena and arena:FindFirstChild("Spawns")
	if not spawnsFolder then return nil end
	-- Compute median spawn Y (any spawn works as a sample of arena floor height)
	local sampleY: number? = nil
	for _, c in spawnsFolder:GetChildren() do
		if c:IsA("BasePart") then sampleY = c.Position.Y; break end
	end
	if not sampleY then return nil end
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local dy = math.abs(hrp.Position.Y - sampleY)
			if dy < 20 then
				return hrp.Position
			end
		end
	end
	return nil
end

local function getArenaSpawnPoints(): { BasePart }
	local arena = Workspace:FindFirstChild("ActiveArena")
	if not arena then return {} end
	local spawnsFolder = arena:FindFirstChild("Spawns")
	if not spawnsFolder then return {} end
	local result: { BasePart } = {}
	for _, child in spawnsFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(result, child)
		end
	end
	return result
end

-- DEPRECATED: kept temporarily; new code calls BotModel.Build directly.
-- Left in place so the rig setup logic (joints, BillboardGui) is documented
-- here even after extraction to BotModel.luau.
local function _buildBotModel_legacy(name: string): Model
	local model = Instance.new("Model")
	model.Name = name

	-- HumanoidRootPart (collisionless anchor for humanoid)
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.TopSurface = Enum.SurfaceType.Smooth
	hrp.BottomSurface = Enum.SurfaceType.Smooth
	hrp.Parent = model

	-- Torso — CanCollide TRUE so bot can stand
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Color = Color3.fromRGB(150, 50, 50)
	torso.Material = Enum.Material.SmoothPlastic
	torso.CanCollide = true
	torso.TopSurface = Enum.SurfaceType.Smooth
	torso.BottomSurface = Enum.SurfaceType.Smooth
	torso.Parent = model

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Color3.fromRGB(200, 170, 140)
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = true
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	head.Parent = model

	local function mkLimb(limbName: string, size: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = limbName
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local leftArm = mkLimb("Left Arm", Vector3.new(1, 2, 1), Color3.fromRGB(150, 50, 50))
	local rightArm = mkLimb("Right Arm", Vector3.new(1, 2, 1), Color3.fromRGB(150, 50, 50))
	local leftLeg = mkLimb("Left Leg", Vector3.new(1, 2, 1), Color3.fromRGB(40, 40, 50))
	local rightLeg = mkLimb("Right Leg", Vector3.new(1, 2, 1), Color3.fromRGB(40, 40, 50))

	-- Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.MaxHealth = BOT_HEALTH
	humanoid.Health = BOT_HEALTH
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = BOT_WALK_SPEED
	humanoid.DisplayName = name
	humanoid.Parent = model

	model.PrimaryPart = hrp
	model:SetAttribute("IsBot", true)

	-- R6 Motor6D joints (required for Humanoid to recognize structure)
	local function motor(parent: BasePart, partA: BasePart, c0: CFrame, c1: CFrame, motorName: string)
		local m = Instance.new("Motor6D")
		m.Name = motorName
		m.Part0 = parent
		m.Part1 = partA
		m.C0 = c0
		m.C1 = c1
		m.Parent = parent
	end
	motor(hrp, torso, CFrame.new(), CFrame.new(), "RootJoint")
	motor(torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0), "Neck")
	motor(torso, leftArm, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0), "Left Shoulder")
	motor(torso, rightArm, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0), "Right Shoulder")
	motor(torso, leftLeg, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0), "Left Hip")
	motor(torso, rightLeg, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0), "Right Hip")

	-- Floating name + health bar
	local bb = Instance.new("BillboardGui")
	bb.Adornee = head
	bb.Size = UDim2.new(0, 100, 0, 28)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = true
	bb.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 14)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Parent = bb

	local hpBar = Instance.new("Frame")
	hpBar.Size = UDim2.new(0.9, 0, 0, 6)
	hpBar.Position = UDim2.new(0.05, 0, 1, -10)
	hpBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	hpBar.BorderSizePixel = 0
	hpBar.Parent = bb

	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPFill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBar

	humanoid.HealthChanged:Connect(function(health)
		local pct = math.clamp(health / BOT_HEALTH, 0, 1)
		hpFill.Size = UDim2.fromScale(pct, 1)
		if pct > 0.6 then
			hpFill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
		elseif pct > 0.3 then
			hpFill.BackgroundColor3 = Color3.fromRGB(220, 200, 80)
		else
			hpFill.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
		end
	end)

	return model
end

-- Find nearest ENEMY target (player OR another bot) within engagement range.
-- Same-team combatants are skipped so 10v10 TDM AI only shoots enemies.
local function findNearestTarget(self: Model, botPos: Vector3): (Model?, BasePart?, Humanoid?, string?, any)
	local nearestChar: Model? = nil
	local nearestHRP: BasePart? = nil
	local nearestHum: Humanoid? = nil
	local nearestType: string? = nil
	local nearestId: any = nil
	local nearestDist = math.huge
	-- Cache our own team for the friendly-fire filter. Untagged bots (e.g.
	-- mid-rebuild) fall through to "engage anyone in range" — safer than
	-- standing motionless. Re-fetched per call so team swaps mid-life apply.
	local myTeam = teamSvc().GetTeam(self)
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		-- Skip same-team players when both sides have a team tag.
		if myTeam then
			local theirTeam = teamSvc().GetTeam(p)
			if theirTeam and theirTeam == myTeam then continue end
		end
		local dist = (hrp.Position - botPos).Magnitude
		if dist < nearestDist and dist < BOT_RANGE then
			nearestDist = dist
			nearestChar = char; nearestHRP = hrp; nearestHum = hum
			nearestType = "player"; nearestId = p
		end
	end
	for _, otherBot in bots do
		if otherBot == self then continue end
		local hum = otherBot:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = otherBot:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		-- Skip same-team bots.
		if myTeam then
			local theirTeam = teamSvc().GetTeam(otherBot)
			if theirTeam and theirTeam == myTeam then continue end
		end
		local dist = (hrp.Position - botPos).Magnitude
		if dist < nearestDist and dist < BOT_RANGE then
			nearestDist = dist
			nearestChar = otherBot; nearestHRP = hrp; nearestHum = hum
			nearestType = "bot"; nearestId = otherBot.Name
		end
	end
	return nearestChar, nearestHRP, nearestHum, nearestType, nearestId
end

-- Smart fire with reaction delay + burst pattern + cone-spread aim.
local function tryFireAt(
	bot: Model,
	state: BotAIState,
	targetChar: Model,
	targetHRP: BasePart,
	targetHum: Humanoid,
	targetType: string,
	targetId: any
)
	local now = os.clock()
	if now < state.nextFireAt then return end

	-- Reset reaction window on new target acquisition
	local key = if targetType == "player" then (targetId :: Player).UserId else targetId
	if state.targetKey ~= key then
		state.targetKey = key
		state.targetSeenAt = now
		state.burstRemaining = 0
		return
	end
	if state.targetSeenAt and now < state.targetSeenAt + REACTION_TIME then return end

	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	-- Face the target horizontally so the equipped weapon points at them.
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

	-- Broadcast shot so clients render tracer/muzzle flash/impact
	Remotes.ShotFired:FireAllClients({
		shooterUserId = nil,
		shooterBotName = bot.Name,
		weaponId = "rifle",
		weaponSlot = "primary",
		origin = origin,
		hitPosition = endPos,
		hitNormal = hitNormal,
		hitMaterial = hitMaterial,
		hitIsPlayer = hitIsPlayer,
		didHit = result ~= nil,
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
			-- Top-right kill notification — bots use rifle visual
			Remotes.KillFeedEntry:FireAllClients({
				killer = bot.Name,
				victim = victimName,
				weapon = "Rifle",
				weaponId = "rifle",
				weaponSlot = "primary",
				isHeadshot = false,
				victimPosition = result.Position,
			})
		end
	end

	-- Burst rhythm
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

-- Movement: strafe + optimal range when in combat, flee at low HP, wander otherwise.
local function botBehavior(bot: Model, state: BotAIState)
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local now = os.clock()

	-- EVASION (on-hit dodge): if we were recently hit, force a hard
	-- perpendicular strafe + one-shot jump so we visibly dodge incoming fire.
	-- This runs BEFORE the normal target-tracking branch so it overrides
	-- the regular strafe pattern for the evasion window (~0.6s).
	if now < state.evasionUntilAt then
		hum.WalkSpeed = COMBAT_WALKSPEED
		-- Try to perpendicular-strafe relative to a known threat direction:
		-- if we have a target, dodge perpendicular to the line to them.
		-- Otherwise dodge perpendicular to our current facing.
		local targetChar, targetHRP = findNearestTarget(bot, hrp.Position)
		local fwd: Vector3
		if targetChar and targetHRP then
			local toTarget = targetHRP.Position - hrp.Position
			local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
			fwd = if flat.Magnitude < 0.01 then Vector3.new(1, 0, 0) else flat.Unit
		else
			local lookFlat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
			fwd = if lookFlat.Magnitude < 0.01 then Vector3.new(1, 0, 0) else lookFlat.Unit
		end
		local perp = Vector3.new(-fwd.Z, 0, fwd.X) * state.evasionDir
		hum:MoveTo(hrp.Position + perp * 8)
		-- One-shot jump for visible vertical dodge
		if not state.jumpedOnEvasion then
			hum.Jump = true
			state.jumpedOnEvasion = true
		end
		return
	end

	-- Retreat at low HP (run to a random spawn for safety)
	if hum.Health <= FLEE_HP then
		hum.WalkSpeed = COMBAT_WALKSPEED
		clearTargetLock(state)
		local spawns = getArenaSpawnPoints()
		if #spawns > 0 then
			local sp = spawns[math.random(#spawns)]
			hum:MoveTo(sp.Position + Vector3.new(0, 3, 0))
		end
		return
	end

	local targetChar, targetHRP = findNearestTarget(bot, hrp.Position)
	if targetChar and targetHRP then
		hum.WalkSpeed = COMBAT_WALKSPEED
		local toTarget = targetHRP.Position - hrp.Position
		local dist = toTarget.Magnitude
		-- Periodic strafe direction flip
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

	-- No target — wander + SCAN (look-around). The bot picks a spawn point
	-- that's *far* from its current position so the route forces it to
	-- traverse the arena and visually sweep its view. Re-rolls on a short
	-- interval so the bot doesn't sit idle if it reaches the dest.
	clearTargetLock(state)
	hum.WalkSpeed = BOT_WALK_SPEED
	local spawns = getArenaSpawnPoints()
	if #spawns == 0 then return end
	if now >= state.nextScanAt then
		-- Pick a spawn far from current position (top-half of distance distribution).
		-- This counts as the bot's "scan" sweep — it rotates as it pathfinds.
		local farthest: BasePart? = nil
		local farthestDist = -1
		for _, sp in spawns do
			local d = (sp.Position - hrp.Position).Magnitude
			if d > farthestDist then
				farthestDist = d
				farthest = sp
			end
		end
		local pick: BasePart
		if farthest and math.random() < 0.65 then
			pick = farthest
		else
			pick = spawns[math.random(#spawns)]
		end
		hum:MoveTo(pick.Position + Vector3.new(0, 3, 0))
		state.nextScanAt = now + 1.2 + math.random() * 1.3
	end
end

-- Forward-declared so setupBot can reference it
local rebuildBot: (oldBot: Model) -> ()

-- Fallback spawn position used when ArenaService hasn't published spawns yet
-- (mid-map-rebuild) or when all arena spawns have somehow ended up in the
-- void. Picked high above the lobby so the bot has time to physics-settle
-- onto SOMETHING reachable instead of falling straight to FallenPartsDestroy.
local FALLBACK_SPAWN_POS = Vector3.new(0, 50, 0)
local VOID_Y_THRESHOLD = -50

-- Full destroy + rebuild rather than just topping up Health. Reviving a dead
-- Humanoid leaves broken joints + the equipped rifle frozen in the wrong pose;
-- rebuilding gives us a fresh rig with the rifle, vest, animator, and Died
-- listener all re-attached cleanly.
--
-- CRITICAL invariants this fn must preserve to avoid the void-watchdog loop:
--   1. oldBot is ALWAYS destroyed + scrubbed from `bots`, even if the new
--      build fails. A zombie Model lingering in `bots` with Y=-1000000 is
--      what the watchdog used to rebuild forever.
--   2. New bot is NEVER inserted back into `bots` until its HRP is verified
--      above VOID_Y_THRESHOLD. Otherwise the watchdog re-flags it next pass.
--   3. UnregisterBot from ScoringService when we permanently give up so the
--      scoreboard doesn't show a ghost slot.
rebuildBot = function(oldBot: Model)
	local name = oldBot.Name
	-- Preserve team across rebuild so a bot stays loyal to its side after
	-- death. Grab BEFORE we Destroy() the old model (which clears the
	-- attribute) and before we drop botTeam[oldBot].
	local preservedTeam: DMTeams.TeamId? = botTeam[oldBot] or teamSvc().GetTeam(oldBot)
	local oldIdx: number? = nil
	for i, b in bots do
		if b == oldBot then
			oldIdx = i
			break
		end
	end
	-- Always tear down the old model + service state FIRST, regardless of
	-- whether we can build a replacement. Previously we early-returned on
	-- `not oldIdx` BEFORE Destroy(), which left the corpse rotting in
	-- Workspace and (with its frozen position attribute) confusing the
	-- watchdog if it ever scanned children directly.
	BotAnimator.Unregister(oldBot)
	botState[oldBot] = nil
	botMuzzle[oldBot] = nil
	lastBehaviorAt[oldBot] = nil
	teamSvc().UnassignBot(oldBot)
	botTeam[oldBot] = nil
	if oldBot.Parent then
		oldBot:Destroy()
	end
	if not oldIdx then
		-- Stale rebuild call (e.g. clearBots ran while a delayed task waited)
		-- — old model is destroyed, nothing to do.
		return
	end
	-- Pull the stale reference out of `bots` immediately. We'll re-insert
	-- only after a successful + validated rebuild.
	table.remove(bots, oldIdx)

	-- If we've already given up on this name (too many void rescues), do not
	-- attempt to bring it back this match. The bot is gone for good.
	if voidGaveUp[name] then
		ScoringService.UnregisterBot(name)
		return
	end

	-- Pick a spawn. If none available (arena not built, map swap in flight,
	-- etc.) fall back to a hardcoded safe position instead of bailing out.
	-- Bailing without a replacement is what caused player slots to shrink
	-- mid-match.
	local spawns = getArenaSpawnPoints()
	local targetPos: Vector3
	if #spawns > 0 then
		local sp = spawns[math.random(#spawns)]
		targetPos = sp.Position + Vector3.new(0, 5, 0)
	else
		warn(string.format(
			"[DeathmatchBot] rebuildBot: no arena spawns for %s — using fallback %s",
			name, tostring(FALLBACK_SPAWN_POS)
		))
		targetPos = FALLBACK_SPAWN_POS
	end
	-- Reject any spawn that would itself drop the bot into the void.
	if targetPos.Y < VOID_Y_THRESHOLD then
		warn(string.format(
			"[DeathmatchBot] rebuildBot: chosen spawn pos %s is below void threshold; using fallback",
			tostring(targetPos)
		))
		targetPos = FALLBACK_SPAWN_POS
	end
	local targetCF = CFrame.new(targetPos)

	local rebuildTeam: DMTeams.TeamId = preservedTeam or pickBotTeam()
	local colors = TEAM_BOT_COLORS[rebuildTeam]
	local okBuild, botOrErr = pcall(BotModel.Build, name, BOT_HEALTH, colors)
	if not okBuild then
		warn(string.format("[DeathmatchBot] rebuildBot: Build failed for %s: %s", name, tostring(botOrErr)))
		-- Build failure is unrecoverable — escalate the void counter so the
		-- watchdog doesn't keep trying.
		voidRescueAttempts[name] = (voidRescueAttempts[name] or 0) + 1
		if (voidRescueAttempts[name] or 0) >= VOID_RESCUE_MAX_ATTEMPTS then
			voidGaveUp[name] = true
			ScoringService.UnregisterBot(name)
		end
		return
	end
	local bot: Model = botOrErr :: Model
	-- Use the proven Parent → CFrame → PivotTo pattern (see placeBotAt
	-- comment above for why PivotTo-before-Parent was unreliable).
	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = targetCF
	end
	bot.Parent = Workspace
	pcall(function()
		bot:PivotTo(targetCF)
	end)

	-- Verify the new model actually exists in Workspace at a sane Y BEFORE
	-- registering it in `bots`. If it's somehow already below the void
	-- threshold, log loudly and give up instead of feeding the watchdog loop.
	local newHrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not newHrp or not bot.Parent or newHrp.Position.Y < VOID_Y_THRESHOLD then
		warn(string.format(
			"[DeathmatchBot] rebuildBot: fresh bot %s failed Y validation (parent=%s, HRP=%s, y=%s) — discarding",
			name,
			tostring(bot.Parent ~= nil),
			tostring(newHrp ~= nil),
			tostring(newHrp and newHrp.Position.Y or "n/a")
		))
		voidRescueAttempts[name] = (voidRescueAttempts[name] or 0) + 1
		if (voidRescueAttempts[name] or 0) >= VOID_RESCUE_MAX_ATTEMPTS then
			voidGaveUp[name] = true
			ScoringService.UnregisterBot(name)
		end
		if bot.Parent then bot:Destroy() end
		return
	end

	-- Validated — safe to register the new model.
	table.insert(bots, bot)
	botState[bot] = newAIState()
	-- Re-register with the team service using the preserved team. AssignBot
	-- handles the SetAttribute + tint + broadcast.
	botTeam[bot] = rebuildTeam
	teamSvc().AssignBot(bot, rebuildTeam)
	local okEquip, muzzleOrErr = pcall(BotModel.EquipRifle, bot)
	if okEquip then
		local muzzle = muzzleOrErr :: Attachment?
		if muzzle then botMuzzle[bot] = muzzle end
	else
		warn(string.format("[DeathmatchBot] rebuildBot: EquipRifle failed for %s: %s", name, tostring(muzzleOrErr)))
	end
	BotAnimator.Register(bot)
	-- Re-hook death + HealthChanged (evasion) so this fresh bot behaves
	-- exactly like a newly spawned one on its next damage / death.
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			task.delay(BOT_RESPAWN_DELAY, function()
				if bot.Parent then rebuildBot(bot) end
			end)
		end)
		local st = botState[bot]
		if st then st.lastHealth = hum.Health end
		hum.HealthChanged:Connect(function(newHealth)
			local s = botState[bot]
			if not s then return end
			if newHealth < s.lastHealth - 0.01 then
				local now = os.clock()
				s.lastHitAt = now
				s.evasionDir = if math.random() < 0.5 then -1 else 1
				s.evasionUntilAt = now + 0.6
				s.jumpedOnEvasion = false
			end
			s.lastHealth = newHealth
		end)
	end
	print(string.format(
		"[DEBUG-BOT] Rebuilt %s — parented: %s, HRP pos: %s",
		name,
		tostring(bot.Parent ~= nil),
		tostring(bot.PrimaryPart and bot.PrimaryPart.Position or "no-PrimaryPart")
	))
end

local function setupBot(bot: Model)
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	hum.Died:Connect(function()
		task.delay(BOT_RESPAWN_DELAY, function()
			if bot.Parent then rebuildBot(bot) end
		end)
	end)
	-- Evasion trigger: any HP drop arms a ~0.6s strafe-jump window.
	-- We ignore equal-or-greater health changes (healing / regen) and
	-- the initial MaxHealth-from-spawn ramp by tracking lastHealth.
	local state = botState[bot]
	if state then state.lastHealth = hum.Health end
	hum.HealthChanged:Connect(function(newHealth)
		local st = botState[bot]
		if not st then return end
		if newHealth < st.lastHealth - 0.01 then
			local now = os.clock()
			st.lastHitAt = now
			st.evasionDir = if math.random() < 0.5 then -1 else 1
			st.evasionUntilAt = now + 0.6
			st.jumpedOnEvasion = false
		end
		st.lastHealth = newHealth
	end)
end

local function clearBots()
	for _, bot in bots do
		BotAnimator.Unregister(bot)
		ScoringService.UnregisterBot(bot.Name)
		teamSvc().UnassignBot(bot)
		bot:Destroy()
	end
	table.clear(bots)
	table.clear(botState)
	table.clear(lastBehaviorAt)
	table.clear(botMuzzle)
	table.clear(botTeam)
	table.clear(voidRescueAttempts)
	table.clear(voidGaveUp)
end

-- Drop any stale entries from `bots` that no longer reference a live Workspace
-- model with a HumanoidRootPart. The watchdog + AI tick both iterate `bots`,
-- and a zombie reference (Model destroyed but pointer still in the table)
-- previously caused the watchdog to fire forever on bots that no longer
-- existed — Roblox keeps Position semantics on destroyed BaseParts in some
-- cases (frozen at last replicated position which can be -1000000 if it
-- already fell out of the world). This runs at the top of every fill pass
-- and also right after a void-rescue rebuild attempt so we never iterate
-- garbage.
local function pruneStaleBots()
	local kept: { Model } = {}
	for _, bot in bots do
		if not bot or not bot.Parent then continue end
		local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		table.insert(kept, bot)
	end
	-- Replace contents of `bots` in-place so the watchdog/AI loop iterators
	-- that captured the table reference still see updated state.
	table.clear(bots)
	for _, b in kept do
		table.insert(bots, b)
	end
end

-- Position a freshly built bot at the given target CFrame. This is the
-- belt-and-suspenders sequence: set HRP CFrame directly, parent, then
-- PivotTo as a final safety. Previous "PivotTo-before-Parent" approach
-- (commit f5c2f0c) was unreliable because PivotTo on an unparented Model
-- doesn't always rigidly translate every BasePart when those parts are
-- not yet joined together in physics space — bots would silently spawn
-- at (0,0,0), fall through the lobby into the void, and be
-- auto-destroyed by FallenPartsDestroyHeight (-500). The scoreboard
-- entry survived (ScoringService.RegisterBot already ran) but the model
-- was gone. This sequence matches the proven pattern used in
-- DMRoomService / CasualBotService.
local function placeBotAt(bot: Model, targetCF: CFrame)
	-- BotModel.Build returns the rig with all body Parts ANCHORED so they
	-- don't fall during the brief window between Parent and PivotTo. We:
	--   1. Parent to Workspace (parts are visible but stuck — anchored)
	--   2. PivotTo target — moves the whole assembly to the arena spawn
	--   3. Unanchor — physics + Motor6D joints take over for the Humanoid
	bot.Parent = Workspace
	pcall(function()
		bot:PivotTo(targetCF)
	end)
	BotModel.UnanchorRig(bot)
end

-- Private servers (created via TeleportService:ReserveServer for parties) used
-- to unconditionally skip bot fill. Now the host can opt in/out via the
-- "With Bots" toggle in the Create-Lobby UI; the choice is forwarded as
-- TeleportData and stamped onto Workspace attributes by PrivateLobbyService.
-- Reading the attribute (not a captured boot-time flag) means a slow
-- TeleportData arrival doesn't fall through to "default off" — we re-read
-- every fill pass.
local IS_PRIVATE_SERVER = game.PrivateServerId ~= ""
if IS_PRIVATE_SERVER then
	print("[DeathmatchBot] Private server detected (PrivateServerId=" .. game.PrivateServerId .. ") — will honor Workspace WithBots/MaxPlayers attributes")
end

-- Read host-configured lobby settings stamped on Workspace by
-- PrivateLobbyService.applyTeleportDataToWorkspace. Public servers (no
-- PrivateServerId) call sites bypass this helper and use TARGET_PLAYER_COUNT.
local function resolvePrivateLobbyConfig(): (boolean, number)
	local withBotsAttr = Workspace:GetAttribute("WithBots")
	local maxPlayersAttr = Workspace:GetAttribute("MaxPlayers")
	local withBots = if typeof(withBotsAttr) == "boolean" then withBotsAttr else true
	local maxPlayers = TARGET_PLAYER_COUNT
	if typeof(maxPlayersAttr) == "number" then
		local mp = math.floor(maxPlayersAttr)
		if mp < 2 then mp = 2 end
		if mp > 20 then mp = 20 end
		maxPlayers = mp
	end
	return withBots, maxPlayers
end

local function spawnBotsToFill()
	-- Prune stale entries up front so any subsequent log/iteration sees a
	-- clean table. clearBots below will wipe everything anyway, but the
	-- prune ensures we don't crash trying to UnregisterBot on a nil model
	-- or iterate a destroyed instance. Cheap insurance.
	pruneStaleBots()
	-- In private servers: honor the host's WithBots/MaxPlayers settings.
	-- If WithBots=false → skip entirely (same legacy "private = no bots"
	-- behavior). Otherwise treat private just like a public match but with
	-- the host's chosen MaxPlayers as the fill target.
	local effectiveTarget = TARGET_PLAYER_COUNT
	if IS_PRIVATE_SERVER then
		local withBots, maxPlayers = resolvePrivateLobbyConfig()
		if not withBots then
			print("[DeathmatchBot] Private server with WithBots=false — skipping bot fill")
			return
		end
		effectiveTarget = maxPlayers
		print(string.format(
			"[DeathmatchBot] Private server with WithBots=true, MaxPlayers=%d — filling normally",
			maxPlayers
		))
	end
	-- Retry up to 10 times waiting for arena spawns (max ~5 seconds total)
	local spawns = getArenaSpawnPoints()
	local retries = 0
	while #spawns == 0 and retries < 10 do
		print(string.format("[DeathmatchBot] Arena spawns not ready (retry %d/10), waiting 0.5s...", retries + 1))
		task.wait(0.5)
		spawns = getArenaSpawnPoints()
		retries += 1
	end
	-- DEBUG: snapshot of preconditions at spawn time
	local arenaExists = Workspace:FindFirstChild("ActiveArena") ~= nil
	print(string.format(
		"[DEBUG-BOT] Match state: %s, gamemode: %s, players: %d, ActiveArena exists: %s",
		tostring(MatchStateService.GetState().state),
		tostring(MatchStateService.GetGamemode()),
		#Players:GetPlayers(),
		tostring(arenaExists)
	))
	if #spawns == 0 then
		warn("[DeathmatchBot] Arena spawns NEVER appeared! ActiveArena exists: " .. tostring(arenaExists))
		return
	end
	print(string.format("[DEBUG-BOT] Found %d arena spawn points", #spawns))
	-- Log a sample spawn position so we can sanity-check coordinates
	print(string.format("[DEBUG-BOT] First spawn position: %s", tostring(spawns[1].Position)))
	clearBots()
	local playerCount = #Players:GetPlayers()
	local botsNeeded = math.max(0, effectiveTarget - playerCount)
	print(string.format("[DeathmatchBot] Spawning %d bots (players: %d, target: %d)", botsNeeded, playerCount, effectiveTarget))
	-- Diagnostic mode: if a player is alive in arena, prefer the spawn points
	-- closest to them for the first 2 bots so they're visible immediately.
	-- Remaining bots fall back to random spawns to keep the arena populated.
	local refPos = findReferencePlayerPos()
	local sortedNearPlayer: { BasePart }? = nil
	if refPos then
		sortedNearPlayer = spawnsByDistanceTo(refPos)
		print(string.format(
			"[DEBUG-BOT] SPAWN_NEAR_PLAYER active. Player at %s; closest spawn = %s (%.1f studs)",
			tostring(refPos),
			tostring(sortedNearPlayer[1] and sortedNearPlayer[1].Name),
			sortedNearPlayer[1] and (sortedNearPlayer[1].Position - refPos).Magnitude or -1
		))
	end

	for i = 1, botsNeeded do
		nameIndex = (nameIndex % #botNames) + 1
		local name = botNames[nameIndex] .. "_" .. tostring(i)
		-- Decide team BEFORE building so we can apply the team palette to the
		-- rig. pickBotTeam consults the running botTeam map; we record the
		-- assignment IMMEDIATELY after building the model (below) so the next
		-- loop iteration sees an up-to-date count.
		local assignedTeam: DMTeams.TeamId = pickBotTeam()
		local colors = TEAM_BOT_COLORS[assignedTeam]
		local okBuild, botOrErr = pcall(BotModel.Build, name, BOT_HEALTH, colors)
		if not okBuild then
			warn(string.format("[DeathmatchBot] BotModel.Build failed for %s: %s", name, tostring(botOrErr)))
			continue
		end
		local bot: Model = botOrErr :: Model
		botTeam[bot] = assignedTeam
		-- DIAGNOSTIC SPAWN: when a player is in the arena, place the first 6
		-- bots in a ring directly around them (radius ~15 studs). This bypasses
		-- the map's spawn points entirely so it works even on maps with gaps,
		-- elevated platforms (rooftop), or floors that bots tend to fall off.
		-- Remaining bots use the regular spawn points + small jitter.
		local targetCF: CFrame
		if refPos and i <= 6 then
			local angle = (i / 6) * math.pi * 2
			local offset = Vector3.new(math.cos(angle) * 15, 3, math.sin(angle) * 15)
			targetCF = CFrame.new(refPos + offset)
		else
			local sp: BasePart
			if sortedNearPlayer and i <= 2 and sortedNearPlayer[i] then
				sp = sortedNearPlayer[i]
			else
				sp = spawns[math.random(#spawns)]
			end
			-- ±5 studs jitter — narrow enough to stay on the arena floor.
			local jitterX = (math.random() - 0.5) * 10
			local jitterZ = (math.random() - 0.5) * 10
			targetCF = sp.CFrame + Vector3.new(jitterX, 5, jitterZ)
		end
		placeBotAt(bot, targetCF)
		table.insert(bots, bot)
		botState[bot] = newAIState()
		-- Register with team service NOW (after parent — AssignBot sets a
		-- Team attribute + armband, which both need the model in Workspace
		-- to replicate visibly). The botTeam map was set right after Build()
		-- so pickBotTeam already counts this bot for the next iteration.
		teamSvc().AssignBot(bot, assignedTeam)
		-- Equip rifle + cache muzzle for tracer origin. EquipRifle creates
		-- new welded parts; wrap in pcall so a single broken weld can't
		-- abort the rest of the spawn loop.
		local okEquip, muzzleOrErr = pcall(BotModel.EquipRifle, bot)
		if okEquip then
			local muzzle = muzzleOrErr :: Attachment?
			if muzzle then botMuzzle[bot] = muzzle end
		else
			warn(string.format("[DeathmatchBot] EquipRifle failed for %s: %s", name, tostring(muzzleOrErr)))
		end
		BotAnimator.Register(bot)
		setupBot(bot)
		ScoringService.RegisterBot(name)
		-- DEBUG: confirm parenting + position landed correctly
		local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
		print(string.format(
			"[DEBUG-BOT] Spawned %s — parented: %s, PrimaryPart: %s, HRP pos: %s, target was: %s",
			name,
			tostring(bot.Parent ~= nil),
			tostring(bot.PrimaryPart and bot.PrimaryPart.Name or "nil"),
			tostring(hrp and hrp.Position or "no-HRP"),
			tostring(targetCF.Position)
		))
	end
end

-- Two-axis tick: fast fire pass (~10Hz) for responsive bursts, slower behavior
-- pass (~3Hz) for movement decisions / strafe re-rolls. Splitting keeps the
-- shooting reactive without re-pathing every loop.
--
-- Void watchdog: every 5 seconds, scan bots and force-rebuild any whose HRP
-- has dropped below y=-100. Roblox's FallenPartsDestroyHeight should kill
-- characters that fall too far, but ModelStreamingMode=Persistent overrides
-- that — so void-fallen bots stay parented at y=-1000000 with HP intact,
-- which causes findNearestTarget to still consider them (and the player to
-- "feel alone" because half the bots are off-map). The watchdog calls
-- rebuildBot directly so we don't depend on Humanoid:Died firing reliably
-- when the bot is already in the void (it sometimes doesn't fire if the
-- humanoid is already dead from FallenPartsDestroyHeight rules).
--
-- Loop-protection: per bot NAME, track void-rescue attempts. After
-- VOID_RESCUE_MAX_ATTEMPTS consecutive rescues that don't stick, give up on
-- that name entirely — unregister from ScoringService and never try to
-- rebuild it again this match. This prevents the "same bots void every 2s
-- forever" log flood when an arena map has no valid spawns above ground.
--
-- Frequency bumped from 2s → 5s so Roblox physics + replication has time to
-- settle a fresh respawn before we re-check it. A new bot whose HRP arrives
-- at y=50, then briefly dips to y=-10 mid-fall during physics simulation,
-- could otherwise trip the watchdog on the next 2s tick.
task.spawn(function()
	while true do
		task.wait(5)
		pcall(function()
			-- Snapshot the bots table first because rebuildBot mutates it
			-- (table.remove + table.insert). Iterating + mutating in-place
			-- can skip entries.
			local snapshot: { Model } = {}
			for _, b in bots do table.insert(snapshot, b) end
			for _, bot in snapshot do
				if not bot or not bot.Parent then continue end
				local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not hrp then continue end
				if hrp.Position.Y >= -100 then continue end

				local name = bot.Name
				if voidGaveUp[name] then
					-- Already given up on this name in an earlier pass —
					-- ensure the corpse is gone so we don't keep flagging it.
					BotAnimator.Unregister(bot)
					botState[bot] = nil
					botMuzzle[bot] = nil
					lastBehaviorAt[bot] = nil
					teamSvc().UnassignBot(bot)
					botTeam[bot] = nil
					ScoringService.UnregisterBot(name)
					bot:Destroy()
					pruneStaleBots()
					continue
				end

				local attempts = (voidRescueAttempts[name] or 0) + 1
				voidRescueAttempts[name] = attempts

				-- Rich diagnostic so we can tell whether the arena is
				-- actually present + populated when the rescue fires.
				local arena = Workspace:FindFirstChild("ActiveArena")
				local spawnsFolder = arena and arena:FindFirstChild("Spawns")
				local spawnCount = 0
				if spawnsFolder then
					for _, c in spawnsFolder:GetChildren() do
						if c:IsA("BasePart") then spawnCount += 1 end
					end
				end
				print(string.format(
					"[DEBUG-BOT] Void-fallen bot %s @ y=%d (attempt %d/%d) — parent=%s, Anchored=%s, ActiveArena=%s, spawns=%d",
					name,
					math.floor(hrp.Position.Y),
					attempts, VOID_RESCUE_MAX_ATTEMPTS,
					tostring(bot.Parent and bot.Parent.Name or "nil"),
					tostring(hrp.Anchored),
					tostring(arena ~= nil),
					spawnCount
				))

				if attempts > VOID_RESCUE_MAX_ATTEMPTS then
					-- Give up permanently on this name.
					warn(string.format(
						"[DeathmatchBot] Bot %s void-fell %d times — removing from match permanently",
						name, attempts
					))
					voidGaveUp[name] = true
					BotAnimator.Unregister(bot)
					botState[bot] = nil
					botMuzzle[bot] = nil
					lastBehaviorAt[bot] = nil
					teamSvc().UnassignBot(bot)
					botTeam[bot] = nil
					ScoringService.UnregisterBot(name)
					bot:Destroy()
					pruneStaleBots()
					continue
				end

				-- Rebuild directly (don't rely on Humanoid:Died firing for
				-- an already-void-fallen humanoid).
				rebuildBot(bot)
			end
		end)
	end
end)

-- Wrapped in pcall per-iteration: an unhandled error inside botBehavior or
-- tryFireAt previously would kill the entire AI thread, leaving bots in the
-- scoreboard but motionless. We now log and continue.
task.spawn(function()
	while true do
		task.wait(0.1)
		local ok, err = pcall(function()
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

				-- Behavior tick (movement / strafe / objective)
				if now - (lastBehaviorAt[bot] or 0) >= BEHAVIOR_INTERVAL then
					botBehavior(bot, state)
					lastBehaviorAt[bot] = now
				end

				-- Fire tick every loop pass; tryFireAt respects nextFireAt + reaction delay.
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
		end)
		if not ok then
			warn("[DeathmatchBot] AI tick error (continuing): " .. tostring(err))
		end
	end
end)

-- Match state listener — only spawn for deathmatch gamemode (casual mode
-- has its own bot service that manages team-aware AI).
print("[DeathmatchBot] Service loaded, registering state listener")
MatchStateService.StateChanged:Connect(function(newState: MatchState.State)
	print("[DeathmatchBot] State changed to:", newState)
	if newState == MatchState.States.MATCH then
		if MatchStateService.GetGamemode() ~= "deathmatch" then
			return
		end
		task.wait(1)
		spawnBotsToFill()
	elseif newState == MatchState.States.ENDING or newState == MatchState.States.LOBBY then
		clearBots()
	end
end)
-- Catch-up: if MATCH already active when service loads, spawn bots now (deathmatch only)
if MatchStateService.GetState().state == MatchState.States.MATCH
	and MatchStateService.GetGamemode() == "deathmatch" then
	print("[DeathmatchBot] MATCH already active at service load, spawning bots now")
	task.spawn(spawnBotsToFill)
end

-- Rebalance when players join/leave mid-match (debounced to prevent thrash)
local lastRebalanceAt = 0
local REBALANCE_DEBOUNCE = 2 -- seconds
local function rebalanceIfMatch()
	if MatchStateService.GetState().state ~= MatchState.States.MATCH then return end
	if MatchStateService.GetGamemode() ~= "deathmatch" then return end
	local now = os.clock()
	if now - lastRebalanceAt < REBALANCE_DEBOUNCE then return end
	lastRebalanceAt = now
	task.wait(1) -- let player character spawn
	spawnBotsToFill()
end
Players.PlayerAdded:Connect(rebalanceIfMatch)
Players.PlayerRemoving:Connect(rebalanceIfMatch)

-- DIAGNOSTIC: when a player spawns into the arena, teleport up to 2 nearby
-- bots to within ~25 studs of them so the player can immediately see at
-- least one bot. Only fires when SPAWN_NEAR_PLAYER is true (diagnostic mode).
local function relocateBotsNearPlayer(char: Model)
	if not SPAWN_NEAR_PLAYER then return end
	if MatchStateService.GetState().state ~= MatchState.States.MATCH then return end
	if MatchStateService.GetGamemode() ~= "deathmatch" then return end
	-- Wait a beat for both physics + ArenaService teleport. CharacterAdded
	-- fires the moment the character is parented to Workspace, BEFORE
	-- ArenaService:Teleport runs, so without the wait we'd see the
	-- character still at lobby (y ≈ 107).
	task.wait(1.5)
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or hrp.Position.Y < -100 then return end
	-- Reject lobby refs — same arena-vs-lobby check as findReferencePlayerPos.
	local arena = Workspace:FindFirstChild("ActiveArena")
	local spawnsFolder = arena and arena:FindFirstChild("Spawns")
	local sampleY: number? = nil
	if spawnsFolder then
		for _, c in spawnsFolder:GetChildren() do
			if c:IsA("BasePart") then sampleY = c.Position.Y; break end
		end
	end
	if sampleY and math.abs(hrp.Position.Y - sampleY) > 20 then
		print(string.format(
			"[DEBUG-BOT] relocateBotsNearPlayer: player still at lobby (y=%d vs arena y=%d), skipping",
			math.floor(hrp.Position.Y), math.floor(sampleY)
		))
		return
	end
	-- Find 2 alive bots farthest from the player, move them close.
	local candidates: { Model } = {}
	for _, bot in bots do
		local hum = bot:FindFirstChildOfClass("Humanoid")
		local bhrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and bhrp and hum.Health > 0 then
			table.insert(candidates, bot)
		end
	end
	if #candidates == 0 then
		print("[DEBUG-BOT] relocateBotsNearPlayer: no live bots to move")
		return
	end
	-- Sort farthest-first so we move the bot that's least likely to be in
	-- visual range already; up to 2.
	table.sort(candidates, function(a, b)
		local ah = a:FindFirstChild("HumanoidRootPart") :: BasePart
		local bh = b:FindFirstChild("HumanoidRootPart") :: BasePart
		return (ah.Position - hrp.Position).Magnitude > (bh.Position - hrp.Position).Magnitude
	end)
	-- Offsets in a small ring around the player (~20 studs out)
	local offsets = { Vector3.new(18, 3, 0), Vector3.new(-18, 3, 6) }
	for i = 1, math.min(2, #candidates) do
		local bot = candidates[i]
		local target = hrp.Position + offsets[i]
		local bhrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
		if bhrp then
			pcall(function() bot:PivotTo(CFrame.new(target)) end)
			print(string.format(
				"[DEBUG-BOT] Relocated %s to %s (was %.1f studs from player)",
				bot.Name, tostring(target),
				(bhrp.Position - hrp.Position).Magnitude
			))
		end
	end
end

Players.PlayerAdded:Connect(function(p: Player)
	p.CharacterAdded:Connect(relocateBotsNearPlayer)
end)
for _, p in Players:GetPlayers() do
	p.CharacterAdded:Connect(relocateBotsNearPlayer)
	if p.Character then task.spawn(relocateBotsNearPlayer, p.Character) end
end

return DeathmatchBotService
