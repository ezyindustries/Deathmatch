--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local RankSystem = require(Shared.Modules.RankSystem)
local BattlePassConfig = require(Shared.Modules.BattlePassConfig)
local CosmeticRegistry = require(Shared.Modules.CosmeticRegistry)
local ClientSignals = require(Shared.Modules.ClientSignals)

local ProgressionController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ProgressionHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 150
screenGui.Parent = playerGui

-- Rank badge (below mini scoreboard)
local rankBadge = Instance.new("Frame")
rankBadge.Size = UDim2.new(0, 260, 0, 36)
rankBadge.Position = UDim2.new(0, 20, 0, 64)
rankBadge.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
rankBadge.BackgroundTransparency = 0.2
rankBadge.BorderSizePixel = 0
rankBadge.Parent = screenGui

local rankCorner = Instance.new("UICorner")
rankCorner.CornerRadius = UDim.new(0, 10)
rankCorner.Parent = rankBadge

local rankStripe = Instance.new("Frame")
rankStripe.Size = UDim2.new(0, 6, 1, -10)
rankStripe.Position = UDim2.new(0, 6, 0, 5)
rankStripe.BackgroundColor3 = Color3.fromRGB(180, 110, 70)
rankStripe.BorderSizePixel = 0
rankStripe.Parent = rankBadge

local stripeCorner = Instance.new("UICorner")
stripeCorner.CornerRadius = UDim.new(1, 0)
stripeCorner.Parent = rankStripe

local rankLabel = Instance.new("TextLabel")
rankLabel.Size = UDim2.new(1, -28, 1, 0)
rankLabel.Position = UDim2.new(0, 22, 0, 0)
rankLabel.BackgroundTransparency = 1
rankLabel.Font = Enum.Font.GothamBold
rankLabel.TextSize = 14
rankLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
rankLabel.TextXAlignment = Enum.TextXAlignment.Left
rankLabel.Text = "BRONZE   0 wins"
rankLabel.Parent = rankBadge

-- Battle Pass button (bottom-right)
local bpButton = Instance.new("TextButton")
bpButton.Size = UDim2.new(0, 160, 0, 44)
bpButton.AnchorPoint = Vector2.new(1, 1)
bpButton.Position = UDim2.new(1, -20, 1, -84)
bpButton.BackgroundColor3 = Color3.fromRGB(60, 60, 85)
bpButton.AutoButtonColor = false
bpButton.BorderSizePixel = 0
bpButton.Font = Enum.Font.GothamBold
bpButton.TextSize = 15
bpButton.TextColor3 = Color3.fromRGB(255, 255, 255)
bpButton.Text = "Battle Pass"
bpButton.Visible = false -- access via MainMenu/PauseMenu instead
bpButton.Parent = screenGui

local bpButtonCorner = Instance.new("UICorner")
bpButtonCorner.CornerRadius = UDim.new(0, 10)
bpButtonCorner.Parent = bpButton

-- Battle Pass panel (overlay)
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.4
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.Parent = screenGui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 720, 0, 480)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
panel.BorderSizePixel = 0
panel.Parent = overlay

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 16)
panelCorner.Parent = panel

local panelTitle = Instance.new("TextLabel")
panelTitle.Size = UDim2.new(1, -40, 0, 36)
panelTitle.Position = UDim2.new(0, 20, 0, 16)
panelTitle.BackgroundTransparency = 1
panelTitle.Font = Enum.Font.GothamBold
panelTitle.TextSize = 22
panelTitle.TextColor3 = Color3.fromRGB(255, 220, 80)
panelTitle.TextXAlignment = Enum.TextXAlignment.Left
panelTitle.Text = BattlePassConfig.SeasonName
panelTitle.Parent = panel

local panelClose = Instance.new("TextButton")
panelClose.Size = UDim2.new(0, 80, 0, 32)
panelClose.AnchorPoint = Vector2.new(1, 0)
panelClose.Position = UDim2.new(1, -16, 0, 16)
panelClose.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
panelClose.BorderSizePixel = 0
panelClose.Font = Enum.Font.GothamBold
panelClose.TextSize = 13
panelClose.TextColor3 = Color3.fromRGB(255, 255, 255)
panelClose.Text = "Close"
panelClose.Parent = panel

local panelCloseCorner = Instance.new("UICorner")
panelCloseCorner.CornerRadius = UDim.new(0, 8)
panelCloseCorner.Parent = panelClose

panelClose.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)
bpButton.MouseButton1Click:Connect(function()
	overlay.Visible = true
end)

-- Progress bar
local progressContainer = Instance.new("Frame")
progressContainer.Size = UDim2.new(1, -40, 0, 50)
progressContainer.Position = UDim2.new(0, 20, 0, 60)
progressContainer.BackgroundTransparency = 1
progressContainer.Parent = panel

local progressInfo = Instance.new("TextLabel")
progressInfo.Size = UDim2.new(1, 0, 0, 20)
progressInfo.BackgroundTransparency = 1
progressInfo.Font = Enum.Font.Gotham
progressInfo.TextSize = 13
progressInfo.TextColor3 = Color3.fromRGB(220, 220, 235)
progressInfo.TextXAlignment = Enum.TextXAlignment.Left
progressInfo.Text = "Tier 0  -  0 / 500 XP"
progressInfo.Parent = progressContainer

local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(1, 0, 0, 14)
barBg.Position = UDim2.new(0, 0, 0, 28)
barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
barBg.BorderSizePixel = 0
barBg.Parent = progressContainer

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

-- Tier list (scrolling)
local tierScroll = Instance.new("ScrollingFrame")
tierScroll.Size = UDim2.new(1, -40, 1, -180)
tierScroll.Position = UDim2.new(0, 20, 0, 130)
tierScroll.BackgroundTransparency = 1
tierScroll.BorderSizePixel = 0
tierScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
tierScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
tierScroll.ScrollBarThickness = 6
tierScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 105, 130)
tierScroll.Parent = panel

local tierLayout = Instance.new("UIListLayout")
tierLayout.FillDirection = Enum.FillDirection.Vertical
tierLayout.Padding = UDim.new(0, 6)
tierLayout.Parent = tierScroll

type RowRefs = {
	frame: Frame,
	freeBtn: TextButton?,
	premBtn: TextButton?,
}
local tierRows: { [number]: RowRefs } = {}

local function describeReward(reward: BattlePassConfig.Reward?): string
	if not reward then
		return "—"
	end
	if reward.kind == "coins" then
		return string.format("%d coins", reward.value)
	elseif reward.kind == "gems" then
		return string.format("%d gems", reward.value)
	elseif reward.kind == "cosmetic" then
		local info = CosmeticRegistry.ById[reward.value :: string]
		return info and info.displayName or tostring(reward.value)
	end
	return "—"
end

local function rewardColor(reward: BattlePassConfig.Reward?): Color3
	if not reward then
		return Color3.fromRGB(70, 70, 85)
	end
	if reward.kind == "coins" then
		return Color3.fromRGB(255, 200, 80)
	elseif reward.kind == "gems" then
		return Color3.fromRGB(120, 200, 255)
	elseif reward.kind == "cosmetic" then
		local info = CosmeticRegistry.ById[reward.value :: string]
		return info and CosmeticRegistry.TierColors[info.tier] or Color3.fromRGB(180, 180, 180)
	end
	return Color3.fromRGB(150, 150, 150)
end

local function buildTierRow(tierData: BattlePassConfig.Tier)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 64)
	row.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
	row.BorderSizePixel = 0
	row.LayoutOrder = tierData.tier
	row.Parent = tierScroll

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	local tierBadge = Instance.new("TextLabel")
	tierBadge.Size = UDim2.new(0, 70, 1, 0)
	tierBadge.BackgroundTransparency = 1
	tierBadge.Font = Enum.Font.GothamBold
	tierBadge.TextSize = 20
	tierBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	tierBadge.Text = "T" .. tierData.tier
	tierBadge.Parent = row

	local function buildSlot(reward: BattlePassConfig.Reward?, label: string, x: number, track: string): TextButton?
		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(0, 280, 0, 48)
		slot.Position = UDim2.new(0, x, 0.5, -24)
		slot.BackgroundColor3 = Color3.fromRGB(36, 36, 50)
		slot.BorderSizePixel = 0
		slot.Parent = row

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 8)
		slotCorner.Parent = slot

		local accent = Instance.new("Frame")
		accent.Size = UDim2.new(0, 4, 1, -8)
		accent.Position = UDim2.new(0, 4, 0, 4)
		accent.BackgroundColor3 = rewardColor(reward)
		accent.BorderSizePixel = 0
		accent.Parent = slot

		local accentCorner = Instance.new("UICorner")
		accentCorner.CornerRadius = UDim.new(1, 0)
		accentCorner.Parent = accent

		local labelText = Instance.new("TextLabel")
		labelText.Size = UDim2.new(1, -100, 0, 18)
		labelText.Position = UDim2.new(0, 14, 0, 4)
		labelText.BackgroundTransparency = 1
		labelText.Font = Enum.Font.GothamMedium
		labelText.TextSize = 11
		labelText.TextColor3 = Color3.fromRGB(150, 155, 175)
		labelText.TextXAlignment = Enum.TextXAlignment.Left
		labelText.Text = label
		labelText.Parent = slot

		local rewardText = Instance.new("TextLabel")
		rewardText.Size = UDim2.new(1, -100, 0, 26)
		rewardText.Position = UDim2.new(0, 14, 0, 18)
		rewardText.BackgroundTransparency = 1
		rewardText.Font = Enum.Font.GothamBold
		rewardText.TextSize = 14
		rewardText.TextColor3 = Color3.fromRGB(255, 255, 255)
		rewardText.TextXAlignment = Enum.TextXAlignment.Left
		rewardText.Text = describeReward(reward)
		rewardText.Parent = slot

		if not reward then
			return nil
		end

		local claimBtn = Instance.new("TextButton")
		claimBtn.Size = UDim2.new(0, 76, 0, 30)
		claimBtn.AnchorPoint = Vector2.new(1, 0.5)
		claimBtn.Position = UDim2.new(1, -8, 0.5, 0)
		claimBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
		claimBtn.BorderSizePixel = 0
		claimBtn.AutoButtonColor = false
		claimBtn.Font = Enum.Font.GothamBold
		claimBtn.TextSize = 12
		claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		claimBtn.Text = "Locked"
		claimBtn.Parent = slot

		local claimCorner = Instance.new("UICorner")
		claimCorner.CornerRadius = UDim.new(0, 6)
		claimCorner.Parent = claimBtn

		claimBtn.MouseButton1Click:Connect(function()
			Remotes.ClaimBPReward:FireServer(tierData.tier, track)
		end)

		return claimBtn
	end

	local freeBtn = buildSlot(tierData.free, "FREE", 92, "free")
	local premBtn = buildSlot(tierData.premium, "PREMIUM", 384, "premium")

	tierRows[tierData.tier] = { frame = row, freeBtn = freeBtn, premBtn = premBtn }
end

for _, tier in BattlePassConfig.Tiers do
	buildTierRow(tier)
end

local function updateClaimButton(btn: TextButton?, state: "claimable" | "claimed" | "locked" | "unavailable")
	if not btn then
		return
	end
	if state == "claimable" then
		btn.Text = "Claim"
		btn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
	elseif state == "claimed" then
		btn.Text = "Claimed"
		btn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
	elseif state == "locked" then
		btn.Text = "Locked"
		btn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
	elseif state == "unavailable" then
		btn.Text = "Premium"
		btn.BackgroundColor3 = Color3.fromRGB(80, 60, 100)
	end
end

local function refreshPanel(data: any)
	local seasonXp = data.seasonXp or 0
	local currentTier = 0
	local nextXpThreshold = BattlePassConfig.Tiers[1].xpRequired
	for _, t in BattlePassConfig.Tiers do
		if seasonXp >= t.xpRequired then
			currentTier = t.tier
		else
			nextXpThreshold = t.xpRequired
			break
		end
	end

	local progressIntoTier
	local rangeForTier
	if currentTier == 0 then
		progressIntoTier = seasonXp
		rangeForTier = BattlePassConfig.Tiers[1].xpRequired
	elseif currentTier >= BattlePassConfig.MaxTier then
		progressIntoTier = 1
		rangeForTier = 1
	else
		local prevThreshold = BattlePassConfig.Tiers[currentTier].xpRequired
		progressIntoTier = seasonXp - prevThreshold
		rangeForTier = nextXpThreshold - prevThreshold
	end
	local ratio = math.clamp(progressIntoTier / math.max(1, rangeForTier), 0, 1)
	progressInfo.Text = string.format(
		"Tier %d  -  %d / %d XP" .. (data.hasPremiumPass and "    [PREMIUM PASS ACTIVE]" or ""),
		currentTier,
		math.floor(progressIntoTier),
		math.floor(rangeForTier)
	)
	barFill:TweenSize(UDim2.new(ratio, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)

	for _, tier in BattlePassConfig.Tiers do
		local row = tierRows[tier.tier]
		if not row then
			continue
		end
		local key = tostring(tier.tier)
		local freeClaimed = data.claimedFreeTiers and data.claimedFreeTiers[key]
		local premClaimed = data.claimedPremiumTiers and data.claimedPremiumTiers[key]
		local achieved = seasonXp >= tier.xpRequired

		if tier.free then
			updateClaimButton(row.freeBtn, if freeClaimed then "claimed" elseif achieved then "claimable" else "locked")
		end
		if tier.premium then
			if not data.hasPremiumPass then
				updateClaimButton(row.premBtn, "unavailable")
			else
				updateClaimButton(row.premBtn, if premClaimed then "claimed" elseif achieved then "claimable" else "locked")
			end
		end
	end
end

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	-- DM rank badge — derived from `xp` (per-kill 20 XP, 1000 XP per level, 21 levels).
	local xp = data.xp or 0
	local rank = RankSystem.RankFromXp(xp)
	local prog = RankSystem.LevelProgress(xp)
	rankStripe.BackgroundColor3 = rank.color
	rankLabel.Text = string.format("%s   %d / %d XP", string.upper(rank.displayName), prog.xpInLevel, prog.xpNeeded)
	refreshPanel(data)
end)

Remotes.BPRewardResult.OnClientEvent:Connect(function(result: any)
	if result.error then
		print("[BP] Claim failed:", result.error)
		return
	end
	print(string.format("[BP] Claimed tier %d %s reward", result.tier, result.track))
end)

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	local inLobby = payload.state == "LOBBY" or payload.state == "VOTING"
	-- BP HUD button hidden permanently — access via MainMenu/PauseMenu
	if not inLobby then
		overlay.Visible = false
	end
end)

ClientSignals.Get("OpenBP").Event:Connect(function()
	overlay.Visible = true
end)

return ProgressionController
