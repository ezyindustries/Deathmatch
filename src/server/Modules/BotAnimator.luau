--!strict
-- BotAnimator — per-frame leg/arm swing for R6 bots so they walk like real
-- players instead of sliding on rails.
--
-- Drives Motor6D rotations on Left/Right Hip + Left Shoulder based on the
-- BOT'S ACTUAL HRP VELOCITY (XZ plane). Right arm is intentionally untouched
-- because it holds the rifle in a fixed gripping pose set by EquipRifle.
--
-- Why velocity, not Humanoid.MoveDirection?
--   MoveDirection drops to zero the instant Humanoid:MoveTo reaches its
--   target — but the bot AI calls MoveTo with short hop targets every ~0.35s,
--   so MoveDirection toggles on/off rapidly. Driving the swing off that
--   produces a stop-start jitter (legs freeze between hops). Velocity is
--   continuous: as long as physics is still carrying the bot forward, the
--   legs keep cycling.
--
-- A single-Heartbeat loop ticks all registered bots — no per-bot connections,
-- so adding/removing is cheap.
--
-- Usage:
--   BotAnimator.Register(botModel)
--   BotAnimator.Unregister(botModel)

local RunService = game:GetService("RunService")

local BotAnimator = {}

type Joints = {
	hrp: BasePart,
	leftHip: Motor6D,
	rightHip: Motor6D,
	leftShoulder: Motor6D?,
	leftHipC0: CFrame,
	rightHipC0: CFrame,
	leftShoulderC0: CFrame?,
	humanoid: Humanoid,
	phase: number,
	-- Smoothed walking weight (0 = idle pose, 1 = full swing). Per-bot so the
	-- transition lerps continuously instead of snapping when velocity crosses
	-- the threshold.
	walkBlend: number,
}

local registered: { [Model]: Joints } = {}

function BotAnimator.Register(bot: Model)
	local torso = bot:FindFirstChild("Torso") :: BasePart?
	if not torso then return end
	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local lh = torso:FindFirstChild("Left Hip") :: Motor6D?
	local rh = torso:FindFirstChild("Right Hip") :: Motor6D?
	local ls = torso:FindFirstChild("Left Shoulder") :: Motor6D?
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not lh or not rh or not hum then return end
	registered[bot] = {
		hrp = hrp,
		leftHip = lh,
		rightHip = rh,
		leftShoulder = ls,
		leftHipC0 = lh.C0,
		rightHipC0 = rh.C0,
		leftShoulderC0 = ls and ls.C0 or nil,
		humanoid = hum,
		phase = math.random() * math.pi * 2,
		walkBlend = 0,
	}
end

function BotAnimator.Unregister(bot: Model)
	registered[bot] = nil
end

-- Tunables: leaning toward more visible motion than the previous 28°/7Hz
-- because user observed bots barely animating during real gameplay.
local SWING_AMPLITUDE = math.rad(38)  -- max forward/back leg angle at full walk
local ARM_AMPLITUDE   = math.rad(22)  -- left-arm counter-swing
local STEP_FREQ       = 9             -- radians/sec — slightly faster cadence
local WALK_VEL_FULL   = 12            -- stud/sec considered "full walking speed"
local WALK_VEL_MIN    = 1.5           -- below this we're idle
-- Blend rates (per second). Faster ramp UP than DOWN feels punchy on start
-- and graceful on stop — matches how real animation systems crossfade.
local BLEND_UP_RATE   = 12
local BLEND_DOWN_RATE = 7

RunService.Heartbeat:Connect(function(dt: number)
	if dt <= 0 then return end
	local now = os.clock()
	for bot, j in registered do
		if not bot.Parent then
			registered[bot] = nil
			continue
		end
		local hum = j.humanoid
		if hum.Health <= 0 then
			-- Reset to neutral on death so the ragdoll doesn't have rotated joints.
			j.leftHip.C0 = j.leftHipC0
			j.rightHip.C0 = j.rightHipC0
			if j.leftShoulder and j.leftShoulderC0 then
				j.leftShoulder.C0 = j.leftShoulderC0
			end
			j.walkBlend = 0
			continue
		end

		-- ACTUAL physical velocity in the XZ plane. Robust to MoveTo target
		-- arrival (MoveDirection drops to 0 but velocity stays > 0 while the
		-- bot is still gliding forward).
		local v = j.hrp.AssemblyLinearVelocity
		local horizSpeed = math.sqrt(v.X * v.X + v.Z * v.Z)
		local targetWeight: number
		if horizSpeed < WALK_VEL_MIN then
			targetWeight = 0
		else
			-- Linearly interpolate between min walk and full walk speed so a
			-- slow-strafing bot still swings legs (just less than at sprint).
			targetWeight = math.min(1, (horizSpeed - WALK_VEL_MIN) / (WALK_VEL_FULL - WALK_VEL_MIN))
		end

		-- Asymmetric crossfade — ramp up faster than down so the start of a
		-- step looks decisive and the stop feels smooth.
		local rate = if targetWeight > j.walkBlend then BLEND_UP_RATE else BLEND_DOWN_RATE
		local alpha = math.min(1, dt * rate)
		j.walkBlend = j.walkBlend + (targetWeight - j.walkBlend) * alpha

		if j.walkBlend < 0.01 then
			-- Effectively idle — snap to neutral (avoid tiny floating-point
			-- residual that prevents the rig from settling cleanly).
			j.leftHip.C0 = j.leftHipC0
			j.rightHip.C0 = j.rightHipC0
			if j.leftShoulder and j.leftShoulderC0 then
				j.leftShoulder.C0 = j.leftShoulderC0
			end
			continue
		end

		local t = now * STEP_FREQ + j.phase
		local swing = math.sin(t) * SWING_AMPLITUDE * j.walkBlend
		j.leftHip.C0 = j.leftHipC0 * CFrame.Angles(swing, 0, 0)
		j.rightHip.C0 = j.rightHipC0 * CFrame.Angles(-swing, 0, 0)
		if j.leftShoulder and j.leftShoulderC0 then
			local armSwing = math.sin(t + math.pi) * ARM_AMPLITUDE * j.walkBlend
			j.leftShoulder.C0 = j.leftShoulderC0 * CFrame.Angles(armSwing, 0, 0)
		end
	end
end)

return BotAnimator
