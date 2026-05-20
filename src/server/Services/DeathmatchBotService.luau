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
local MatchStateService = require(script.Parent.MatchStateService)
local ScoringService = require(script.Parent.ScoringService)
local BotAnimator = require(script.Parent.Parent.Modules.BotAnimator)

local DeathmatchBotService = {}

local TARGET_PLAYER_COUNT = 7
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

local function clearTargetLock(state: BotAIState)
	state.targetKey = nil
	state.targetSeenAt = nil
	state.burstRemaining = 0
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

-- Find nearest target (player OR another bot) within engagement range.
local function findNearestTarget(self: Model, botPos: Vector3): (Model?, BasePart?, Humanoid?, string?, any)
	local nearestChar: Model? = nil
	local nearestHRP: BasePart? = nil
	local nearestHum: Humanoid? = nil
	local nearestType: string? = nil
	local nearestId: any = nil
	local nearestDist = math.huge
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
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

-- Full destroy + rebuild rather than just topping up Health. Reviving a dead
-- Humanoid leaves broken joints + the equipped rifle frozen in the wrong pose;
-- rebuilding gives us a fresh rig with the rifle, vest, animator, and Died
-- listener all re-attached cleanly.
rebuildBot = function(oldBot: Model)
	local name = oldBot.Name
	local oldIdx: number? = nil
	for i, b in bots do
		if b == oldBot then
			oldIdx = i
			break
		end
	end
	if not oldIdx then return end
	BotAnimator.Unregister(oldBot)
	botState[oldBot] = nil
	botMuzzle[oldBot] = nil
	lastBehaviorAt[oldBot] = nil
	oldBot:Destroy()

	local spawns = getArenaSpawnPoints()
	if #spawns == 0 then return end
	local sp = spawns[math.random(#spawns)]

	local okBuild, botOrErr = pcall(BotModel.Build, name, BOT_HEALTH)
	if not okBuild then
		warn(string.format("[DeathmatchBot] rebuildBot: Build failed for %s: %s", name, tostring(botOrErr)))
		return
	end
	local bot: Model = botOrErr :: Model
	-- Use the proven Parent → CFrame → PivotTo pattern (see placeBotAt
	-- comment above for why PivotTo-before-Parent was unreliable).
	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetCF = sp.CFrame + Vector3.new(0, 5, 0)
	if hrp then
		hrp.CFrame = targetCF
	end
	bot.Parent = Workspace
	pcall(function()
		bot:PivotTo(targetCF)
	end)
	bots[oldIdx] = bot
	botState[bot] = newAIState()
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
		bot:Destroy()
	end
	table.clear(bots)
	table.clear(botState)
	table.clear(lastBehaviorAt)
	table.clear(botMuzzle)
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

local function spawnBotsToFill()
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
	local botsNeeded = math.max(0, TARGET_PLAYER_COUNT - playerCount)
	print(string.format("[DeathmatchBot] Spawning %d bots (players: %d, target: %d)", botsNeeded, playerCount, TARGET_PLAYER_COUNT))
	for i = 1, botsNeeded do
		nameIndex = (nameIndex % #botNames) + 1
		local name = botNames[nameIndex] .. "_" .. tostring(i)
		local okBuild, botOrErr = pcall(BotModel.Build, name, BOT_HEALTH)
		if not okBuild then
			warn(string.format("[DeathmatchBot] BotModel.Build failed for %s: %s", name, tostring(botOrErr)))
			continue
		end
		local bot: Model = botOrErr :: Model
		-- Random spawn + jitter to avoid overlap when bots > spawns
		local sp = spawns[math.random(#spawns)]
		local jitterX = (math.random() - 0.5) * 6
		local jitterZ = (math.random() - 0.5) * 6
		local targetCF = sp.CFrame + Vector3.new(jitterX, 5, jitterZ)
		placeBotAt(bot, targetCF)
		table.insert(bots, bot)
		botState[bot] = newAIState()
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

return DeathmatchBotService
