--!strict
-- CasualBotService — team-aware bots for casual 5v5 plant/defuse.
--
-- Differences from DeathmatchBotService:
--   * Bots are assigned to T or CT team and only shoot opponents
--   * No mid-round respawn (bots stay dead until CasualService respawns them at round start)
--   * T bots holding the bomb walk toward a bomb site and trigger plant
--   * CT bots near a planted bomb trigger defuse
--   * Spawned at team-specific spawn points (ArenaService.GetTeamSpawns)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BotModel = require(Shared.Modules.BotModel)
local Teams = require(Shared.Modules.Teams)
local Remotes = require(Shared.Modules.Remotes)
local _CasualConfig = require(Shared.Constants.CasualConfig)  -- retained for future use

local ArenaService = require(script.Parent.ArenaService)
local ScoringService = require(script.Parent.ScoringService)
local BotAnimator = require(script.Parent.Parent.Modules.BotAnimator)
-- Late-bound to avoid circular dep (CasualService requires us)
local CasualService: any = nil
local function casual()
	if not CasualService then
		CasualService = require(script.Parent.CasualService)
	end
	return CasualService
end

local CasualBotService = {}

local BOT_HEALTH = 100
local BOT_DAMAGE = 8
local BOT_RANGE = 90

-- Smart-AI tunables. Together these make bots feel reactive instead of
-- robotic: short reaction window before firing, burst patterns instead of
-- metronome shots, aim cone that widens with distance, and lateral strafing
-- during combat so they're not standing still.
local REACTION_TIME = 0.35           -- seconds before firing on a fresh target
local BURST_SIZE = 3                 -- shots per burst
local BURST_INTER = 0.18             -- seconds between shots in a burst
local BURST_COOLDOWN_MIN = 0.75      -- post-burst pause (lower bound)
local BURST_COOLDOWN_MAX = 1.4
local AIM_SPREAD_PER_STUD = 0.008    -- tighter (was 0.014) — CS-style small bullet spread
local AIM_SPREAD_MAX = 1.5           -- cap (was 4) — keeps clusters tight even at long range
local STRAFE_INTERVAL_MIN = 0.5
local STRAFE_INTERVAL_MAX = 1.1
local NORMAL_WALKSPEED = 12
local COMBAT_WALKSPEED = 17
local OPTIMAL_RANGE = 24             -- preferred engagement distance
local TOO_CLOSE_RANGE = 10
local FLEE_HP = 25                   -- HP below this → retreat to own spawn

local bots: { Model } = {}
local botTeam: { [string]: Teams.TeamId } = {}  -- bot.Name -> team
local botMuzzle: { [Model]: Attachment } = {}    -- bot -> muzzle attachment (for tracer origin)

type BotState = {
	nextFireAt: number,        -- earliest os.clock the bot can fire again
	burstRemaining: number,    -- shots left in the current burst (0 = need new burst)
	targetSeenAt: number?,     -- os.clock when current target was first seen (for reaction delay)
	targetKey: any?,           -- identity of locked target (Player or bot Name)
	strafeDir: number,         -- -1 or 1
	strafeUntilAt: number,     -- when to re-roll strafe direction
}
local botState: { [Model]: BotState } = {}

local function newState(): BotState
	return {
		nextFireAt = 0,
		burstRemaining = 0,
		targetSeenAt = nil,
		targetKey = nil,
		strafeDir = if math.random() < 0.5 then -1 else 1,
		strafeUntilAt = 0,
	}
end

local botNamesT  = { "Phoenix", "Leet", "Elite", "Anarch", "Brigade" }
local botNamesCT = { "SEAL", "GIGN", "SAS", "GSG9", "FBI" }

local function teamColors(team: Teams.TeamId): BotModel.BotColors
	if team == "T" then
		return {
			torso    = Color3.fromRGB(110, 95, 70),
			head     = Color3.fromRGB(30, 32, 38),     -- balaclava
			leftArm  = Color3.fromRGB(110, 95, 70),
			rightArm = Color3.fromRGB(110, 95, 70),
			leftLeg  = Color3.fromRGB(85, 70, 50),
			rightLeg = Color3.fromRGB(85, 70, 50),
		}
	else
		return {
			torso    = Color3.fromRGB(25, 35, 55),     -- navy
			head     = Color3.fromRGB(220, 195, 165),  -- skin
			leftArm  = Color3.fromRGB(220, 195, 165),
			rightArm = Color3.fromRGB(220, 195, 165),
			leftLeg  = Color3.fromRGB(35, 45, 65),
			rightLeg = Color3.fromRGB(35, 45, 65),
		}
	end
end

-- ================================================================
-- TARGETING
-- ================================================================
local function findNearestOpponent(self: Model, botPos: Vector3, selfTeam: Teams.TeamId): (Model?, BasePart?, Humanoid?, any, string?)
	local nearestChar: Model? = nil
	local nearestHRP: BasePart? = nil
	local nearestHum: Humanoid? = nil
	local nearestId: any = nil
	local nearestType: string? = nil
	local nearestDist = math.huge

	-- Players: only opponents
	for _, p in Players:GetPlayers() do
		if casual().GetTeamFor(p.UserId) == selfTeam then continue end
		local char = p.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		local d = (hrp.Position - botPos).Magnitude
		if d < nearestDist and d < BOT_RANGE then
			nearestDist = d; nearestChar = char; nearestHRP = hrp; nearestHum = hum
			nearestId = p; nearestType = "player"
		end
	end

	-- Bots: only opposite team
	for _, other in bots do
		if other == self then continue end
		if botTeam[other.Name] == selfTeam then continue end
		local hum = other:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = other:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		local d = (hrp.Position - botPos).Magnitude
		if d < nearestDist and d < BOT_RANGE then
			nearestDist = d; nearestChar = other; nearestHRP = hrp; nearestHum = hum
			nearestId = other.Name; nearestType = "bot"
		end
	end

	return nearestChar, nearestHRP, nearestHum, nearestId, nearestType
end

-- Try to fire on a target. Respects reaction delay, burst pattern, aim cone.
-- Returns true if it actually pulled the trigger (used by behavior to know
-- whether to keep position vs. push).
local function tryFireAt(
	bot: Model,
	state: BotState,
	targetChar: Model,
	targetHRP: BasePart,
	targetHum: Humanoid,
	targetId: any,
	targetType: string
): boolean
	local now = os.clock()
	if now < state.nextFireAt then return false end

	-- Reset target acquisition / reaction window if target changed
	local key = if targetType == "player" then (targetId :: Player).UserId else targetId
	if state.targetKey ~= key then
		state.targetKey = key
		state.targetSeenAt = now
		state.burstRemaining = 0
		return false  -- defer first shot to reaction window
	end
	if state.targetSeenAt and now < state.targetSeenAt + REACTION_TIME then
		return false
	end

	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return false end

	-- Turn the bot to face the target so the weapon visually points correctly.
	-- Keep pitch level (don't tilt forward/back) — only yaw.
	local lookTarget = Vector3.new(targetHRP.Position.X, hrp.Position.Y, targetHRP.Position.Z)
	hrp.CFrame = CFrame.lookAt(hrp.Position, lookTarget)

	-- Origin: prefer the actual weapon muzzle (so tracers come from the barrel
	-- tip, like a real shot). Fall back to chest if no weapon equipped.
	local muzzle = botMuzzle[bot]
	local origin = if muzzle then muzzle.WorldPosition else hrp.Position + Vector3.new(0, 1, 0)
	local toTarget = (targetHRP.Position - origin)
	local dist = toTarget.Magnitude
	-- Cone-spread aim: per-stud spread up to the cap. Far targets miss more.
	local spread = math.min(dist * AIM_SPREAD_PER_STUD, AIM_SPREAD_MAX)
	local jitter = Vector3.new(
		(math.random() - 0.5) * 2 * spread,
		(math.random() - 0.5) * 2 * spread * 0.5,  -- less vertical jitter (chest-high aim)
		(math.random() - 0.5) * 2 * spread
	)
	local direction = (toTarget + jitter).Unit * BOT_RANGE
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot }
	local result = Workspace:Raycast(origin, direction, params)

	-- Where the tracer ends — either the hit point or max range
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

	-- Broadcast the shot to all clients so they render tracer + muzzle flash +
	-- impact. shooterUserId is nil for bots; client falls back to info.origin.
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
				casual().NotifyDeath(targetId)
			end
			-- Top-right kill notification: bot killed someone with a rifle
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

	-- Burst rhythm: 3 shots quickly, then long-ish cooldown.
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
	return true
end

local function clearTargetLock(state: BotState)
	state.targetKey = nil
	state.targetSeenAt = nil
	state.burstRemaining = 0
end

-- ================================================================
-- MOVEMENT + OBJECTIVE
-- ================================================================
local function moveTo(bot: Model, pos: Vector3)
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if hum then hum:MoveTo(pos) end
end

-- Decide the next move target for this bot. Combines combat strafing,
-- objective pushing (plant/defuse), retreat at low HP, and lane wandering.
local function botBehavior(bot: Model, state: BotState)
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local team = botTeam[bot.Name]
	if not team then return end
	local cs = casual()
	local now = os.clock()

	-- LOW-HP RETREAT: run to own team spawn (proxy for "cover"). Higher speed
	-- so they actually escape instead of dying to chip damage.
	if hum.Health <= FLEE_HP then
		hum.WalkSpeed = COMBAT_WALKSPEED
		clearTargetLock(state)
		local mine = ArenaService.GetTeamSpawns(team)
		if #mine > 0 then
			moveTo(bot, mine[math.random(#mine)].Position)
		end
		return
	end

	-- Bomb-related behaviors removed in simplified casual mode — bots focus
	-- purely on combat (find + engage enemy). No plant, no defuse.

	-- COMBAT MODE: pick optimal range + strafe sideways so they're not a stationary target
	local targetChar, targetHRP = findNearestOpponent(bot, hrp.Position, team)
	if targetChar and targetHRP then
		hum.WalkSpeed = COMBAT_WALKSPEED
		local toTarget = targetHRP.Position - hrp.Position
		local dist = toTarget.Magnitude
		-- Refresh strafe direction periodically (random left/right)
		if now > state.strafeUntilAt then
			state.strafeDir = if math.random() < 0.5 then -1 else 1
			state.strafeUntilAt = now + STRAFE_INTERVAL_MIN + math.random() * (STRAFE_INTERVAL_MAX - STRAFE_INTERVAL_MIN)
		end
		local flatToward = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flatToward.Magnitude < 0.01 then flatToward = Vector3.new(1, 0, 0) end
		local fwd = flatToward.Unit
		local right = Vector3.new(-fwd.Z, 0, fwd.X) * state.strafeDir
		local destination: Vector3
		if dist < TOO_CLOSE_RANGE then
			-- Back off + strafe so they don't get knife-rushed
			destination = hrp.Position + (-fwd * 6) + (right * 4)
		elseif dist > OPTIMAL_RANGE + 6 then
			-- Push forward + slight strafe
			destination = hrp.Position + (fwd * math.min(dist - OPTIMAL_RANGE, 12)) + (right * 3)
		else
			-- Hold range, pure strafe (the natural-looking sidestep)
			destination = hrp.Position + (right * 6)
		end
		moveTo(bot, destination)
		return
	end

	-- NO TARGET: walk toward enemy spawn at normal speed. Lock target reset
	-- so reaction delay re-triggers on next contact.
	clearTargetLock(state)
	hum.WalkSpeed = NORMAL_WALKSPEED
	local opposing = ArenaService.GetTeamSpawns(Teams.Other(team))
	if #opposing > 0 then
		local sp = opposing[math.random(#opposing)]
		moveTo(bot, sp.Position)
	end
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
local function clearBots()
	for _, bot in bots do
		BotAnimator.Unregister(bot)
		ScoringService.UnregisterBot(bot.Name)
		bot:Destroy()
	end
	table.clear(bots)
	table.clear(botTeam)
	table.clear(botState)
	table.clear(botMuzzle)
end

CasualBotService.ClearBots = clearBots

-- Fill bots so each team reaches TeamSize. tNeeded/ctNeeded are remaining slots
-- after real players have been assigned. onAssign(name, team) is called for each
-- bot created so CasualService can register it in its `teams` table.
function CasualBotService.FillBots(tNeeded: number, ctNeeded: number, onAssign: (string, Teams.TeamId) -> ())
	for i = 1, tNeeded do
		local name = (botNamesT[((i - 1) % #botNamesT) + 1]) .. "_T" .. tostring(i)
		local model = BotModel.Build(name, BOT_HEALTH, teamColors("T"))
		model.Parent = Workspace
		table.insert(bots, model)
		botTeam[name] = "T"
		botState[model] = newState()
		-- Equip rifle (cache muzzle for tracer origin)
		local muzzle = BotModel.EquipRifle(model)
		if muzzle then botMuzzle[model] = muzzle end
		BotAnimator.Register(model)
		ScoringService.RegisterBot(name)
		-- Hook death so we notify casual + leave the body in place (no mid-round respawn)
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function()
				if casual().IsActive() then
					casual().NotifyDeath(name)
				end
			end)
		end
		onAssign(name, "T")
	end
	for i = 1, ctNeeded do
		local name = (botNamesCT[((i - 1) % #botNamesCT) + 1]) .. "_CT" .. tostring(i)
		local model = BotModel.Build(name, BOT_HEALTH, teamColors("CT"))
		model.Parent = Workspace
		table.insert(bots, model)
		botTeam[name] = "CT"
		botState[model] = newState()
		local muzzle = BotModel.EquipRifle(model)
		if muzzle then botMuzzle[model] = muzzle end
		BotAnimator.Register(model)
		ScoringService.RegisterBot(name)
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function()
				if casual().IsActive() then
					casual().NotifyDeath(name)
				end
			end)
		end
		onAssign(name, "CT")
	end
end

-- Remove a single bot (player join replaces a bot). Returns the team the
-- removed bot was on (or nil if not found). Caller is responsible for adding
-- the replacement player to CasualService.teams.
function CasualBotService.RemoveBot(botName: string): Teams.TeamId?
	local team = botTeam[botName]
	if not team then return nil end
	for i, b in bots do
		if b.Name == botName then
			BotAnimator.Unregister(b)
			ScoringService.UnregisterBot(b.Name)
			b:Destroy()
			table.remove(bots, i)
			break
		end
	end
	botTeam[botName] = nil
	-- botState / botMuzzle keyed by model — those die with the destroyed model
	return team
end

-- Pick a bot on a specific team to swap out. Prefers dead bots first (so we
-- don't kill an actively engaged bot), then random.
function CasualBotService.PickBotToReplace(team: Teams.TeamId): string?
	local candidates: { string } = {}
	local deadCandidates: { string } = {}
	for _, b in bots do
		if botTeam[b.Name] == team then
			local hum = b:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health <= 0 then
				table.insert(deadCandidates, b.Name)
			else
				table.insert(candidates, b.Name)
			end
		end
	end
	if #deadCandidates > 0 then
		return deadCandidates[math.random(#deadCandidates)]
	end
	if #candidates > 0 then
		return candidates[math.random(#candidates)]
	end
	return nil
end

-- Reset a bot for a new round. Reviving a dead Humanoid by just setting
-- Health back to full is unreliable (broken joints, ragdoll state lingers), so
-- we destroy the old model and rebuild a fresh one with the same name + team.
function CasualBotService.RespawnBot(botName: string, team: Teams.TeamId)
	-- Locate and remove the old model
	local oldIdx: number? = nil
	for i, b in bots do
		if b.Name == botName then
			BotAnimator.Unregister(b)
			b:Destroy()
			oldIdx = i
			break
		end
	end
	if not oldIdx then return end

	local model = BotModel.Build(botName, BOT_HEALTH, teamColors(team))
	bots[oldIdx] = model
	botTeam[botName] = team
	botState[model] = newState()
	-- Re-equip rifle on the fresh model
	local muzzle = BotModel.EquipRifle(model)
	if muzzle then botMuzzle[model] = muzzle end
	BotAnimator.Register(model)

	-- Re-hook death so this fresh bot also notifies casual on next death
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			if casual().IsActive() then
				casual().NotifyDeath(botName)
			end
		end)
	end

	-- Position at a team spawn (or arena origin as fallback)
	model.Parent = Workspace
	local spawns = ArenaService.GetTeamSpawns(team)
	if #spawns > 0 then
		local sp = spawns[math.random(#spawns)]
		model:PivotTo(sp.CFrame + Vector3.new(0, 5, 0))
	end
end

-- ================================================================
-- AI TICK
-- ================================================================
-- Two ticks at different cadences:
--   * Fire tick (~10/s): fine-grained for responsive shooting + bursts
--   * Behavior tick (~3/s): movement decisions, strafe re-rolls, retreats
-- Splitting them avoids re-running pathing every fire frame (CPU) while still
-- letting the gun feel reactive when a target peeks out.
local BEHAVIOR_INTERVAL = 0.35

task.spawn(function()
	local lastBehaviorAt: { [Model]: number } = {}
	while true do
		task.wait(0.1)
		if not casual().IsLivePhase() then continue end
		local now = os.clock()
		for _, bot in bots do
			if not bot.Parent then continue end
			local hum = bot:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then continue end
			local state = botState[bot]
			if not state then
				state = newState()
				botState[bot] = state
			end
			local team = botTeam[bot.Name]
			if not team then continue end

			-- Behavior tick (movement / strafe / objective)
			if now - (lastBehaviorAt[bot] or 0) >= BEHAVIOR_INTERVAL then
				botBehavior(bot, state)
				lastBehaviorAt[bot] = now
			end

			-- Fire tick: only if we can see a target (raycast LOS handled inside tryFireAt).
			-- Run every loop pass so bursts feel snappy, but tryFireAt respects nextFireAt.
			local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local targetChar, targetHRP, targetHum, targetId, targetType = findNearestOpponent(bot, hrp.Position, team)
				if targetChar and targetHRP and targetHum and targetType then
					tryFireAt(bot, state, targetChar, targetHRP, targetHum, targetId, targetType)
				else
					-- No visible target — clear lock so the next acquisition triggers reaction delay
					clearTargetLock(state)
				end
			end
		end
	end
end)

return CasualBotService
