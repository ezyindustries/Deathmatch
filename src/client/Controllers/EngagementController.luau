--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local MissionConfig = require(Shared.Modules.MissionConfig)
local ClientSignals = require(Shared.Modules.ClientSignals)

local EngagementController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EngagementHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false  -- modal: let Roblox auto-shift below the topbar (Unibar) so title isnt covered
screenGui.DisplayOrder = 150
screenGui.Parent = playerGui

-- ============ DAILY REWARD BADGE (bottom-left) — hidden, claim via signal/auto ============
local dailyBadge = Instance.new("TextButton")
dailyBadge.Size = UDim2.new(0, 220, 0, 34)
dailyBadge.AnchorPoint = Vector2.new(0, 1)
dailyBadge.Position = UDim2.new(0, 24, 1, -150)
dailyBadge.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
dailyBadge.BorderSizePixel = 0
dailyBadge.AutoButtonColor = false
dailyBadge.Visible = false
dailyBadge.Font = Enum.Font.GothamBold
dailyBadge.TextSize = 13
dailyBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
dailyBadge.Text = "Daily Reward"
dailyBadge.Parent = screenGui

local dailyBadgeCorner = Instance.new("UICorner")
dailyBadgeCorner.CornerRadius = UDim.new(0, 8)
dailyBadgeCorner.Parent = dailyBadge

local dailyPulse = Instance.new("Frame")
dailyPulse.Size = UDim2.new(0, 8, 0, 8)
dailyPulse.Position = UDim2.new(0, 8, 0.5, -4)
dailyPulse.BackgroundColor3 = Color3.fromRGB(255, 220, 80)
dailyPulse.BorderSizePixel = 0
dailyPulse.Visible = false
dailyPulse.Parent = dailyBadge

local pulseCorner = Instance.new("UICorner")
pulseCorner.CornerRadius = UDim.new(1, 0)
pulseCorner.Parent = dailyPulse

-- Daily modal (TextButton + Modal=true so input doesn't leak through; tap
-- outside the card to dismiss).
local dailyModal = Instance.new("TextButton")
dailyModal.Size = UDim2.new(1, 0, 1, 0)
dailyModal.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dailyModal.BackgroundTransparency = 0.45
dailyModal.Visible = false
dailyModal.BorderSizePixel = 0
dailyModal.AutoButtonColor = false
dailyModal.Text = ""
dailyModal.Modal = true
dailyModal.Parent = screenGui

local dailyCard = Instance.new("Frame")
dailyCard.Size = UDim2.new(0, 420, 0, 260)
dailyCard.AnchorPoint = Vector2.new(0.5, 0.5)
dailyCard.Position = UDim2.new(0.5, 0, 0.5, 0)
dailyCard.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
dailyCard.BorderSizePixel = 0
dailyCard.Active = true -- absorb taps so outside-tap-to-close only fires outside card
dailyCard.Parent = dailyModal

-- Mobile clamp for daily card
local dailyCardScale = Instance.new("UIScale")
dailyCardScale.Scale = 1
dailyCardScale.Parent = dailyCard
local function refreshDailyCardScale()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local sx = math.min(1, (v.X * 0.95) / 420)
	local sy = math.min(1, (v.Y * 0.92) / 260)
	dailyCardScale.Scale = math.min(sx, sy)
end
refreshDailyCardScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshDailyCardScale)
end

local dailyCardCorner = Instance.new("UICorner")
dailyCardCorner.CornerRadius = UDim.new(0, 14)
dailyCardCorner.Parent = dailyCard

local dailyTitle = Instance.new("TextLabel")
dailyTitle.Size = UDim2.new(1, -40, 0, 30)
dailyTitle.Position = UDim2.new(0, 20, 0, 16)
dailyTitle.BackgroundTransparency = 1
dailyTitle.Font = Enum.Font.GothamBold
dailyTitle.TextSize = 22
dailyTitle.TextColor3 = Color3.fromRGB(255, 220, 80)
dailyTitle.TextXAlignment = Enum.TextXAlignment.Left
dailyTitle.Text = "Daily Reward"
dailyTitle.Parent = dailyCard

local dailyStreakLabel = Instance.new("TextLabel")
dailyStreakLabel.Size = UDim2.new(1, -40, 0, 26)
dailyStreakLabel.Position = UDim2.new(0, 20, 0, 56)
dailyStreakLabel.BackgroundTransparency = 1
dailyStreakLabel.Font = Enum.Font.GothamMedium
dailyStreakLabel.TextSize = 16
dailyStreakLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
dailyStreakLabel.TextXAlignment = Enum.TextXAlignment.Left
dailyStreakLabel.Text = "Streak: 0 days"
dailyStreakLabel.Parent = dailyCard

local dailyRewardText = Instance.new("TextLabel")
dailyRewardText.Size = UDim2.new(1, -40, 0, 50)
dailyRewardText.Position = UDim2.new(0, 20, 0, 90)
dailyRewardText.BackgroundTransparency = 1
dailyRewardText.Font = Enum.Font.GothamBold
dailyRewardText.TextSize = 18
dailyRewardText.TextColor3 = Color3.fromRGB(255, 255, 255)
dailyRewardText.TextXAlignment = Enum.TextXAlignment.Left
dailyRewardText.TextWrapped = true
dailyRewardText.Text = "Today's reward: 50 coins"
dailyRewardText.Parent = dailyCard

local dailyClaimBtn = Instance.new("TextButton")
dailyClaimBtn.Size = UDim2.new(0, 140, 0, 40)
dailyClaimBtn.AnchorPoint = Vector2.new(0, 1)
dailyClaimBtn.Position = UDim2.new(0, 20, 1, -20)
dailyClaimBtn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
dailyClaimBtn.BorderSizePixel = 0
dailyClaimBtn.Font = Enum.Font.GothamBold
dailyClaimBtn.TextSize = 15
dailyClaimBtn.TextColor3 = Color3.fromRGB(20, 30, 20)
dailyClaimBtn.Text = "Claim"
dailyClaimBtn.AutoButtonColor = false
dailyClaimBtn.Parent = dailyCard

local dailyClaimCorner = Instance.new("UICorner")
dailyClaimCorner.CornerRadius = UDim.new(0, 8)
dailyClaimCorner.Parent = dailyClaimBtn

local dailyCloseBtn = Instance.new("TextButton")
dailyCloseBtn.Size = UDim2.new(0, 90, 0, 40)
dailyCloseBtn.AnchorPoint = Vector2.new(1, 1)
dailyCloseBtn.Position = UDim2.new(1, -20, 1, -20)
dailyCloseBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 75)
dailyCloseBtn.BorderSizePixel = 0
dailyCloseBtn.Font = Enum.Font.GothamBold
dailyCloseBtn.TextSize = 13
dailyCloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dailyCloseBtn.Text = "Close"
dailyCloseBtn.Parent = dailyCard

local dailyCloseCorner = Instance.new("UICorner")
dailyCloseCorner.CornerRadius = UDim.new(0, 8)
dailyCloseCorner.Parent = dailyCloseBtn

local SECONDS_PER_DAY = 86400

local function updateDailyView(profile: any)
	local now = os.time()
	local elapsed = now - (profile.lastDailyClaim or 0)
	local canClaim = elapsed >= SECONDS_PER_DAY

	local nextStreak
	if profile.lastDailyClaim == 0 or elapsed > 2 * SECONDS_PER_DAY then
		nextStreak = 1
	else
		nextStreak = (profile.dailyStreak or 0) + 1
	end

	local coinSteps = { 50, 75, 100, 125, 150, 175, 250 }
	local index = ((nextStreak - 1) % 7) + 1
	local coinReward = coinSteps[index]
	local gemReward = if nextStreak % 7 == 0 then 15 else 0

	dailyStreakLabel.Text = string.format("Current streak: %d days", profile.dailyStreak or 0)
	if canClaim then
		local rewardStr = string.format("Next claim: +%d coins (day %d)", coinReward, nextStreak)
		if gemReward > 0 then
			rewardStr = rewardStr .. string.format(" + %d gems!", gemReward)
		end
		dailyRewardText.Text = rewardStr
		dailyClaimBtn.Text = "Claim"
		dailyClaimBtn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
		dailyBadge.Text = "✨ Daily Reward Ready"
		dailyBadge.BackgroundColor3 = Color3.fromRGB(255, 180, 70)
		dailyBadge.TextColor3 = Color3.fromRGB(30, 30, 30)
		dailyPulse.Visible = true
	else
		local remaining = SECONDS_PER_DAY - elapsed
		local hrs = math.floor(remaining / 3600)
		local mins = math.floor((remaining % 3600) / 60)
		dailyRewardText.Text = string.format("Next reward available in %dh %dm", hrs, mins)
		dailyClaimBtn.Text = "Wait"
		dailyClaimBtn.BackgroundColor3 = Color3.fromRGB(80, 85, 100)
		dailyBadge.Text = string.format("Daily Reward (%dh)", hrs)
		dailyBadge.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
		dailyBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		dailyPulse.Visible = false
	end
end

dailyBadge.MouseButton1Click:Connect(function()
	dailyModal.Visible = true
end)
dailyCloseBtn.MouseButton1Click:Connect(function()
	dailyModal.Visible = false
end)
-- Tap outside card to dismiss
dailyModal.MouseButton1Click:Connect(function()
	dailyModal.Visible = false
end)
dailyClaimBtn.MouseButton1Click:Connect(function()
	if dailyClaimBtn.Text == "Wait" then
		return
	end
	Remotes.ClaimDaily:FireServer()
end)

-- ============ MISSIONS ============
local missionButton = Instance.new("TextButton")
missionButton.Size = UDim2.new(0, 140, 0, 44)
missionButton.AnchorPoint = Vector2.new(1, 1)
missionButton.Position = UDim2.new(1, -190, 1, -84)
missionButton.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
missionButton.BorderSizePixel = 0
missionButton.AutoButtonColor = false
missionButton.Font = Enum.Font.GothamBold
missionButton.TextSize = 14
missionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
missionButton.Text = "Missions"
missionButton.Visible = false -- access via MainMenu/PauseMenu instead
missionButton.Parent = screenGui

local missionBtnCorner = Instance.new("UICorner")
missionBtnCorner.CornerRadius = UDim.new(0, 10)
missionBtnCorner.Parent = missionButton

local missionPulse = Instance.new("Frame")
missionPulse.Size = UDim2.new(0, 10, 0, 10)
missionPulse.Position = UDim2.new(1, -14, 0, 4)
missionPulse.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
missionPulse.BorderSizePixel = 0
missionPulse.Visible = false
missionPulse.Parent = missionButton
local missionPulseCorner = Instance.new("UICorner")
missionPulseCorner.CornerRadius = UDim.new(1, 0)
missionPulseCorner.Parent = missionPulse

-- Missions panel overlay (TextButton + Modal=true, tap outside to dismiss)
local missionsOverlay = Instance.new("TextButton")
missionsOverlay.Size = UDim2.new(1, 0, 1, 0)
missionsOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
missionsOverlay.BackgroundTransparency = 0.45
missionsOverlay.Visible = false
missionsOverlay.BorderSizePixel = 0
missionsOverlay.AutoButtonColor = false
missionsOverlay.Text = ""
missionsOverlay.Modal = true
missionsOverlay.Parent = screenGui

local missionsPanel = Instance.new("Frame")
missionsPanel.Size = UDim2.new(0, 540, 0, 360)
missionsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
missionsPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
missionsPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
missionsPanel.BorderSizePixel = 0
missionsPanel.Active = true -- absorb taps inside panel
missionsPanel.Parent = missionsOverlay

-- Mobile clamp via UIScale for missions panel
local missionsScale = Instance.new("UIScale")
missionsScale.Scale = 1
missionsScale.Parent = missionsPanel
local function refreshMissionsScale()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local sx = math.min(1, (v.X * 0.95) / 540)
	local sy = math.min(1, (v.Y * 0.92) / 360)
	missionsScale.Scale = math.min(sx, sy)
end
refreshMissionsScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshMissionsScale)
end

local missionsCorner = Instance.new("UICorner")
missionsCorner.CornerRadius = UDim.new(0, 14)
missionsCorner.Parent = missionsPanel

local missionsTitle = Instance.new("TextLabel")
missionsTitle.Size = UDim2.new(1, -40, 0, 32)
missionsTitle.Position = UDim2.new(0, 20, 0, 16)
missionsTitle.BackgroundTransparency = 1
missionsTitle.Font = Enum.Font.GothamBold
missionsTitle.TextSize = 22
missionsTitle.TextColor3 = Color3.fromRGB(255, 220, 80)
missionsTitle.TextXAlignment = Enum.TextXAlignment.Left
missionsTitle.Text = "Daily Missions"
missionsTitle.Parent = missionsPanel

local resetLabel = Instance.new("TextLabel")
resetLabel.Size = UDim2.new(1, -40, 0, 18)
resetLabel.Position = UDim2.new(0, 20, 0, 48)
resetLabel.BackgroundTransparency = 1
resetLabel.Font = Enum.Font.Gotham
resetLabel.TextSize = 12
resetLabel.TextColor3 = Color3.fromRGB(170, 175, 195)
resetLabel.TextXAlignment = Enum.TextXAlignment.Left
resetLabel.Text = "Resets in 23h 59m"
resetLabel.Parent = missionsPanel

local missionsClose = Instance.new("TextButton")
missionsClose.Size = UDim2.new(0, 80, 0, 30)
missionsClose.AnchorPoint = Vector2.new(1, 0)
missionsClose.Position = UDim2.new(1, -20, 0, 18)
missionsClose.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
missionsClose.BorderSizePixel = 0
missionsClose.Font = Enum.Font.GothamBold
missionsClose.TextSize = 13
missionsClose.TextColor3 = Color3.fromRGB(255, 255, 255)
missionsClose.Text = "Close"
missionsClose.Parent = missionsPanel

local missionsCloseCorner = Instance.new("UICorner")
missionsCloseCorner.CornerRadius = UDim.new(0, 8)
missionsCloseCorner.Parent = missionsClose

missionButton.MouseButton1Click:Connect(function()
	missionsOverlay.Visible = true
end)
missionsClose.MouseButton1Click:Connect(function()
	missionsOverlay.Visible = false
end)
-- Tap outside missions panel to dismiss
missionsOverlay.MouseButton1Click:Connect(function()
	missionsOverlay.Visible = false
end)

-- ESC closes either modal on desktop
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.Escape then return end
	if dailyModal.Visible then dailyModal.Visible = false end
	if missionsOverlay.Visible then missionsOverlay.Visible = false end
end)

type MissionRowRefs = {
	frame: Frame,
	progressFill: Frame,
	progressText: TextLabel,
	claimBtn: TextButton,
}
local missionRows: { [string]: MissionRowRefs } = {}

local function buildMissionRow(mission: MissionConfig.MissionInfo, index: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -40, 0, 70)
	row.Position = UDim2.new(0, 20, 0, 78 + (index - 1) * 78)
	row.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
	row.BorderSizePixel = 0
	row.Parent = missionsPanel

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -160, 0, 22)
	title.Position = UDim2.new(0, 14, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = mission.displayName
	title.Parent = row

	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -160, 0, 18)
	desc.Position = UDim2.new(0, 14, 0, 28)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 12
	desc.TextColor3 = Color3.fromRGB(170, 175, 195)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Text = string.format("%s  -  reward: %d coins%s",
		mission.description,
		mission.rewardCoins,
		mission.rewardGems > 0 and string.format(" + %d gems", mission.rewardGems) or "")
	desc.Parent = row

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -160, 0, 8)
	barBg.Position = UDim2.new(0, 14, 1, -16)
	barBg.BackgroundColor3 = Color3.fromRGB(50, 52, 65)
	barBg.BorderSizePixel = 0
	barBg.Parent = row
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(255, 220, 80)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = barFill

	local progressText = Instance.new("TextLabel")
	progressText.Size = UDim2.new(0, 80, 0, 18)
	progressText.AnchorPoint = Vector2.new(1, 0.5)
	progressText.Position = UDim2.new(1, -140, 0.5, 12)
	progressText.BackgroundTransparency = 1
	progressText.Font = Enum.Font.GothamMedium
	progressText.TextSize = 12
	progressText.TextColor3 = Color3.fromRGB(220, 220, 235)
	progressText.TextXAlignment = Enum.TextXAlignment.Right
	progressText.Text = string.format("0 / %d", mission.target)
	progressText.Parent = row

	local claimBtn = Instance.new("TextButton")
	claimBtn.Size = UDim2.new(0, 110, 0, 34)
	claimBtn.AnchorPoint = Vector2.new(1, 0.5)
	claimBtn.Position = UDim2.new(1, -16, 0.5, 0)
	claimBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
	claimBtn.BorderSizePixel = 0
	claimBtn.AutoButtonColor = false
	claimBtn.Font = Enum.Font.GothamBold
	claimBtn.TextSize = 13
	claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	claimBtn.Text = "Locked"
	claimBtn.Parent = row

	local claimCorner = Instance.new("UICorner")
	claimCorner.CornerRadius = UDim.new(0, 8)
	claimCorner.Parent = claimBtn

	claimBtn.MouseButton1Click:Connect(function()
		Remotes.ClaimMission:FireServer(mission.id)
	end)

	missionRows[mission.id] = {
		frame = row,
		progressFill = barFill,
		progressText = progressText,
		claimBtn = claimBtn,
	}
end

for i, m in ipairs(MissionConfig.All) do
	buildMissionRow(m, i)
end

local function updateMissionsView(profile: any)
	local progress = profile.missionProgress or {}
	local claimed = profile.missionClaimed or {}

	local anyClaimable = false
	for _, mission in MissionConfig.All do
		local row = missionRows[mission.id]
		if not row then
			continue
		end
		local current = progress[mission.id] or 0
		local clamped = math.min(current, mission.target)
		local ratio = clamped / mission.target
		row.progressFill:TweenSize(UDim2.new(ratio, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
		row.progressText.Text = string.format("%d / %d", clamped, mission.target)

		local isClaimed = claimed[mission.id] == true
		local isComplete = current >= mission.target

		if isClaimed then
			row.claimBtn.Text = "Claimed"
			row.claimBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
		elseif isComplete then
			row.claimBtn.Text = "Claim"
			row.claimBtn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
			anyClaimable = true
		else
			row.claimBtn.Text = "Locked"
			row.claimBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
		end
	end

	missionPulse.Visible = anyClaimable

	-- Reset timer
	local resetAt = profile.missionsResetAt or 0
	local secondsUntil = math.max(0, (resetAt + MissionConfig.ResetIntervalSeconds) - os.time())
	local hrs = math.floor(secondsUntil / 3600)
	local mins = math.floor((secondsUntil % 3600) / 60)
	resetLabel.Text = string.format("Resets in %dh %dm", hrs, mins)
end

-- ============ DATA SYNC ============
Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	updateDailyView(data)
	updateMissionsView(data)
end)

Remotes.DailyResult.OnClientEvent:Connect(function(result: any)
	if result.error then
		dailyRewardText.Text = "Error: " .. result.error
		return
	end
	dailyRewardText.Text = string.format("Got +%d coins!%s",
		result.coinReward,
		result.gemReward > 0 and string.format(" +%d gems!", result.gemReward) or "")
	task.delay(2.5, function()
		dailyModal.Visible = false
	end)
end)

Remotes.MissionResult.OnClientEvent:Connect(function(result: any)
	if result.error then
		print("[Mission] Claim failed:", result.error)
	end
end)

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	local inLobby = payload.state == "LOBBY" or payload.state == "VOTING"
	-- HUD buttons hidden permanently — access via MainMenu/PauseMenu
	if not inLobby then
		dailyModal.Visible = false
		missionsOverlay.Visible = false
	end
end)

ClientSignals.Get("OpenMissions").Event:Connect(function()
	missionsOverlay.Visible = true
end)

return EngagementController
