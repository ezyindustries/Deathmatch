--!strict
-- BotAnimator — per-frame leg/torso swing for R6 bots so they look like they're
-- actually walking instead of sliding on rails.
--
-- Drives Motor6D rotations on Left Hip / Right Hip (and a subtle bob on the
-- left arm) based on whether the bot's Humanoid is moving. Right arm is
-- intentionally left untouched because it holds the rifle in a fixed pose.
--
-- Usage:
--   BotAnimator.Register(botModel)
--   BotAnimator.Unregister(botModel)
-- A single Heartbeat loop ticks all registered bots — no per-bot connections,
-- so adding/removing is cheap.

local RunService = game:GetService("RunService")

local BotAnimator = {}

type Joints = {
	leftHip: Motor6D,
	rightHip: Motor6D,
	leftShoulder: Motor6D?,
	leftHipC0: CFrame,    -- original C0 (without animation rotation)
	rightHipC0: CFrame,
	leftShoulderC0: CFrame?,
	humanoid: Humanoid,
	phase: number,        -- per-bot phase offset so a crowd doesn't move in lockstep
}

local registered: { [Model]: Joints } = {}

function BotAnimator.Register(bot: Model)
	local torso = bot:FindFirstChild("Torso") :: BasePart?
	if not torso then return end
	local lh = torso:FindFirstChild("Left Hip") :: Motor6D?
	local rh = torso:FindFirstChild("Right Hip") :: Motor6D?
	local ls = torso:FindFirstChild("Left Shoulder") :: Motor6D?
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not lh or not rh or not hum then return end
	registered[bot] = {
		leftHip = lh,
		rightHip = rh,
		leftShoulder = ls,
		leftHipC0 = lh.C0,
		rightHipC0 = rh.C0,
		leftShoulderC0 = ls and ls.C0 or nil,
		humanoid = hum,
		phase = math.random() * math.pi * 2,
	}
end

function BotAnimator.Unregister(bot: Model)
	registered[bot] = nil
end

local SWING_AMPLITUDE = math.rad(28)   -- max forward/back leg angle
local ARM_AMPLITUDE = math.rad(18)     -- subtle left-arm counter-swing
local STEP_FREQ = 7                    -- radians per second per stud (sin frequency)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for bot, j in registered do
		if not bot.Parent then
			registered[bot] = nil
			continue
		end
		local hum = j.humanoid
		if hum.Health <= 0 then
			-- Reset to neutral on death so the ragdoll doesn't have rotated joints
			j.leftHip.C0 = j.leftHipC0
			j.rightHip.C0 = j.rightHipC0
			if j.leftShoulder and j.leftShoulderC0 then
				j.leftShoulder.C0 = j.leftShoulderC0
			end
			continue
		end
		-- Move speed magnitude (0..1) — Humanoid.MoveDirection is unit-length
		-- when the bot is moving, zero otherwise. Use that as the on/off gate
		-- and scale amplitude by it.
		local moveMag = hum.MoveDirection.Magnitude
		if moveMag < 0.05 then
			-- Idle: ease back to neutral pose
			j.leftHip.C0 = j.leftHipC0
			j.rightHip.C0 = j.rightHipC0
			if j.leftShoulder and j.leftShoulderC0 then
				j.leftShoulder.C0 = j.leftShoulderC0
			end
			continue
		end
		-- Walking: oscillate hips opposite each other
		local t = now * STEP_FREQ * moveMag + j.phase
		local swing = math.sin(t) * SWING_AMPLITUDE
		j.leftHip.C0 = j.leftHipC0 * CFrame.Angles(swing, 0, 0)
		j.rightHip.C0 = j.rightHipC0 * CFrame.Angles(-swing, 0, 0)
		-- Subtle counter-swing on the left arm (arms swing opposite to legs)
		if j.leftShoulder and j.leftShoulderC0 then
			local armSwing = math.sin(t + math.pi) * ARM_AMPLITUDE
			j.leftShoulder.C0 = j.leftShoulderC0 * CFrame.Angles(armSwing, 0, 0)
		end
	end
end)

return BotAnimator
