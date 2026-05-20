--!strict
-- Full-screen "loading-style" map voting overlay (CS2-inspired).
-- Shown during VOTING + STARTING states. Big map cards, countdown, winner banner.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local MapRegistry = require(Shared.Modules.MapRegistry)
local MatchState = require(Shared.Modules.MatchState)
local ClientSignals = require(Shared.Modules.ClientSignals)

local movementLockSignal = ClientSignals.Get("MovementLock")

local isTrainingMode = false -- set true when EnterTrainingMode remote fires (wired below)

local VotingController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VoteUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 95
screenGui.Enabled = false
screenGui.Parent = playerGui

Remotes.EnterTrainingMode.OnClientEvent:Connect(function(active: boolean)
	isTrainingMode = active == true
	if isTrainingMode then
		screenGui.Enabled = false
		movementLockSignal:Fire(false)
	end
end)

-- Full-screen dark backdrop (slight gradient)
local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
backdrop.BackgroundTransparency = 0.05
backdrop.BorderSizePixel = 0
backdrop.Parent = screenGui

local backdropGrad = Instance.new("UIGradient")
backdropGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 25, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 18)),
})
backdropGrad.Rotation = 90
backdropGrad.Parent = backdrop

-- Top header
local headerLabel = Instance.new("TextLabel")
headerLabel.Size = UDim2.new(0, 600, 0, 60)
headerLabel.AnchorPoint = Vector2.new(0.5, 0)
headerLabel.Position = UDim2.new(0.5, 0, 0, 80)
headerLabel.BackgroundTransparency = 1
headerLabel.Font = Enum.Font.GothamBlack
headerLabel.TextSize = 42
headerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
headerLabel.TextStrokeColor3 = Color3.fromRGB(80, 140, 220)
headerLabel.TextStrokeTransparency = 0.5
headerLabel.Text = "MAP VOTING"
headerLabel.Parent = screenGui

-- Sub-header (instruction)
local subLabel = Instance.new("TextLabel")
subLabel.Size = UDim2.new(0, 600, 0, 24)
subLabel.AnchorPoint = Vector2.new(0.5, 0)
subLabel.Position = UDim2.new(0.5, 0, 0, 140)
subLabel.BackgroundTransparency = 1
subLabel.Font = Enum.Font.Gotham
subLabel.TextSize = 16
subLabel.TextColor3 = Color3.fromRGB(160, 175, 200)
subLabel.Text = "Click a map to cast your vote"
subLabel.Parent = screenGui

-- Card container (horizontal row of 3 big cards)
local container = Instance.new("Frame")
container.Size = UDim2.new(0, 900, 0, 380)
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Position = UDim2.new(0.5, 0, 0.5, -20)
container.BackgroundTransparency = 1
container.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 20)
layout.Parent = container

-- Countdown timer (big at bottom)
local timerFrame = Instance.new("Frame")
timerFrame.Size = UDim2.new(0, 220, 0, 80)
timerFrame.AnchorPoint = Vector2.new(0.5, 1)
timerFrame.Position = UDim2.new(0.5, 0, 1, -80)
timerFrame.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
timerFrame.BorderSizePixel = 0
timerFrame.Parent = screenGui

local timerCorner = Instance.new("UICorner")
timerCorner.CornerRadius = UDim.new(0, 8)
timerCorner.Parent = timerFrame

local timerStroke = Instance.new("UIStroke")
timerStroke.Color = Color3.fromRGB(80, 140, 220)
timerStroke.Thickness = 2
timerStroke.Parent = timerFrame

local timerLabel = Instance.new("TextLabel")
timerLabel.Size = UDim2.new(1, 0, 0, 20)
timerLabel.Position = UDim2.new(0, 0, 0, 8)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextSize = 12
timerLabel.TextColor3 = Color3.fromRGB(160, 175, 200)
timerLabel.Text = "TIME LEFT"
timerLabel.Parent = timerFrame

local timerNumber = Instance.new("TextLabel")
timerNumber.Size = UDim2.new(1, 0, 0, 48)
timerNumber.Position = UDim2.new(0, 0, 0, 28)
timerNumber.BackgroundTransparency = 1
timerNumber.Font = Enum.Font.GothamBlack
timerNumber.TextSize = 44
timerNumber.TextColor3 = Color3.fromRGB(255, 255, 255)
timerNumber.Text = "00"
timerNumber.Parent = timerFrame

-- Status banner (used for STARTING phase to show "GET READY: <map>")
local statusBanner = Instance.new("Frame")
statusBanner.Size = UDim2.new(0, 700, 0, 100)
statusBanner.AnchorPoint = Vector2.new(0.5, 0.5)
statusBanner.Position = UDim2.new(0.5, 0, 0.5, 0)
statusBanner.BackgroundColor3 = Color3.fromRGB(20, 25, 40)
statusBanner.BorderSizePixel = 0
statusBanner.Visible = false
statusBanner.Parent = screenGui

local statusBannerCorner = Instance.new("UICorner")
statusBannerCorner.CornerRadius = UDim.new(0, 12)
statusBannerCorner.Parent = statusBanner

local statusBannerStroke = Instance.new("UIStroke")
statusBannerStroke.Color = Color3.fromRGB(80, 200, 110)
statusBannerStroke.Thickness = 3
statusBannerStroke.Parent = statusBanner

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 1, -20)
statusLabel.Position = UDim2.new(0, 10, 0, 10)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBlack
statusLabel.TextSize = 32
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Text = ""
statusLabel.Parent = statusBanner

-- ============= card building =============
local cards: { TextButton } = {}
local hasVoted = false
local selectedCard: TextButton? = nil

local function clearCards()
	for _, c in cards do
		c:Destroy()
	end
	table.clear(cards)
	hasVoted = false
	selectedCard = nil
end

local function highlightSelected(card: TextButton)
	for _, c in cards do
		local stroke = c:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = (c == card) and 5 or 0
			stroke.Color = Color3.fromRGB(255, 230, 90)
		end
	end
	selectedCard = card
end

local function buildCard(map: MapRegistry.MapInfo, index: number)
	local card = Instance.new("TextButton")
	card.Size = UDim2.new(0, 280, 0, 360)
	card.BackgroundColor3 = map.color
	card.AutoButtonColor = false
	card.Text = ""
	card.LayoutOrder = index
	card.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card

	-- Subtle gradient for depth
	local cg = Instance.new("UIGradient")
	cg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(
			math.min(1, map.color.R + 0.15),
			math.min(1, map.color.G + 0.15),
			math.min(1, map.color.B + 0.15)
		)),
		ColorSequenceKeypoint.new(1, Color3.new(
			math.max(0, map.color.R - 0.2),
			math.max(0, map.color.G - 0.2),
			math.max(0, map.color.B - 0.2)
		)),
	})
	cg.Rotation = 90
	cg.Parent = card

	-- Selection stroke (invisible until voted)
	local sel = Instance.new("UIStroke")
	sel.Color = Color3.fromRGB(255, 230, 90)
	sel.Thickness = 0
	sel.Parent = card

	-- Map name big
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 48)
	title.Position = UDim2.new(0, 12, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 32
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	title.TextStrokeTransparency = 0.6
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = string.upper(map.displayName)
	title.Parent = card

	-- Map ID tag (small)
	local idTag = Instance.new("TextLabel")
	idTag.Size = UDim2.new(1, -24, 0, 18)
	idTag.Position = UDim2.new(0, 12, 0, 68)
	idTag.BackgroundTransparency = 1
	idTag.Font = Enum.Font.GothamMedium
	idTag.TextSize = 12
	idTag.TextColor3 = Color3.fromRGB(255, 255, 255)
	idTag.TextTransparency = 0.4
	idTag.TextXAlignment = Enum.TextXAlignment.Left
	idTag.Text = "MAP_" .. string.upper(map.id)
	idTag.Parent = card

	-- Description
	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -24, 0, 140)
	desc.Position = UDim2.new(0, 12, 0, 100)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 15
	desc.TextColor3 = Color3.fromRGB(245, 245, 245)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Text = map.description
	desc.Parent = card

	-- Bottom call-to-action button area
	local cta = Instance.new("Frame")
	cta.Size = UDim2.new(1, -24, 0, 50)
	cta.Position = UDim2.new(0, 12, 1, -68)
	cta.BackgroundColor3 = Color3.new(
		math.max(0, map.color.R - 0.25),
		math.max(0, map.color.G - 0.25),
		math.max(0, map.color.B - 0.25)
	)
	cta.BorderSizePixel = 0
	cta.Parent = card
	local ctaCorner = Instance.new("UICorner")
	ctaCorner.CornerRadius = UDim.new(0, 6)
	ctaCorner.Parent = cta

	local ctaLabel = Instance.new("TextLabel")
	ctaLabel.Name = "Hint"
	ctaLabel.Size = UDim2.new(1, 0, 1, 0)
	ctaLabel.BackgroundTransparency = 1
	ctaLabel.Font = Enum.Font.GothamBold
	ctaLabel.TextSize = 18
	ctaLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	ctaLabel.Text = "▸ VOTE"
	ctaLabel.Parent = cta

	card.MouseEnter:Connect(function()
		if not hasVoted then
			sel.Thickness = 2
			sel.Color = Color3.fromRGB(255, 255, 255)
		end
	end)
	card.MouseLeave:Connect(function()
		if selectedCard ~= card then
			sel.Thickness = 0
		end
	end)

	card.MouseButton1Click:Connect(function()
		Remotes.CastVote:FireServer(map.id)
		hasVoted = true
		-- Reset ALL cards' CTA labels first (clears stale "VOTED" from previous selection)
		for _, c in cards do
			local oldCta = c:FindFirstChild("Hint", true)
			if oldCta and oldCta:IsA("TextLabel") then
				oldCta.Text = "▸ VOTE"
			end
		end
		-- Then mark this card as voted
		ctaLabel.Text = "✓ VOTED"
		highlightSelected(card)
	end)

	cards[index] = card
end

-- ============= state-driven show/hide =============
local currentState: MatchState.State = MatchState.States.LOBBY
local stateStartedAt = 0
local stateDuration = 0

local function showLobbyLoading()
	-- Overlay version for LOBBY state (post-PLAY, waiting for voting)
	container.Visible = false
	statusBanner.Visible = true
	statusBannerStroke.Color = Color3.fromRGB(80, 140, 220)
	statusLabel.Text = "⏳  WAITING FOR NEXT ROUND..."
	headerLabel.Text = "MATCH LOBBY"
	subLabel.Text = "Voting will begin shortly"
	timerStroke.Color = Color3.fromRGB(80, 140, 220)
	screenGui.Enabled = true
	movementLockSignal:Fire(true)
end

-- Show overlay whenever player has character but match hasn't started yet.
-- This covers the gap between PLAY click → spawn → first VOTING state.
local function refreshOverlayForState()
	if not player.Character then return end
	if isTrainingMode then return end -- training bypasses entire overlay
	if currentState == MatchState.States.LOBBY then
		showLobbyLoading()
	elseif currentState == MatchState.States.MATCH then
		screenGui.Enabled = false
		movementLockSignal:Fire(false) -- unlock immediately so player can walk in match
	end
	-- VOTING / STARTING handled by their respective remote handlers below
end

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	if not payload then return end
	currentState = payload.state
	stateStartedAt = payload.startedAt or Workspace:GetServerTimeNow()
	stateDuration = payload.duration or 0
	refreshOverlayForState()
end)

player.CharacterAdded:Connect(function()
	-- Slight delay so character physics settle before we cover screen
	task.wait(0.1)
	refreshOverlayForState()
end)

Remotes.MapVoteOptions.OnClientEvent:Connect(function(maps: { MapRegistry.MapInfo })
	if isTrainingMode then return end -- training player ignores voting entirely
	clearCards()
	statusBanner.Visible = false
	container.Visible = true
	headerLabel.Text = "MAP VOTING"
	subLabel.Text = "Click a map to cast your vote"
	timerStroke.Color = Color3.fromRGB(80, 140, 220)
	timerNumber.TextColor3 = Color3.fromRGB(255, 255, 255)
	for i, m in ipairs(maps) do
		buildCard(m, i)
	end
	screenGui.Enabled = true
	movementLockSignal:Fire(true)
end)

Remotes.MapVoteResult.OnClientEvent:Connect(function(result: { winner: string, tally: { [string]: number } })
	if isTrainingMode then return end -- training player ignores match results
	-- Switch to "STARTING / GET READY" mode
	container.Visible = false

	local winnerInfo: MapRegistry.MapInfo? = nil
	for _, m in MapRegistry do
		if m.id == result.winner then
			winnerInfo = m
			break
		end
	end

	local winnerName = winnerInfo and winnerInfo.displayName or result.winner
	headerLabel.Text = "GET READY"
	subLabel.Text = "Match starting..."
	statusLabel.Text = string.format("🏆  %s", string.upper(winnerName))
	statusBanner.Visible = true
	if winnerInfo then
		statusBannerStroke.Color = winnerInfo.color
	end
	timerStroke.Color = Color3.fromRGB(80, 200, 110)
end)

-- Countdown + auto-hide on MATCH
RunService.Heartbeat:Connect(function()
	if not screenGui.Enabled then return end
	if currentState == MatchState.States.LOBBY
		or currentState == MatchState.States.VOTING
		or currentState == MatchState.States.STARTING then
		local elapsed = Workspace:GetServerTimeNow() - stateStartedAt
		local remaining = math.max(0, math.ceil(stateDuration - elapsed))
		timerNumber.Text = string.format("%02d", remaining)
		-- Pulse color when low
		if remaining <= 3 and currentState ~= MatchState.States.LOBBY then
			timerStroke.Color = Color3.fromRGB(255, 90, 90)
			timerNumber.TextColor3 = Color3.fromRGB(255, 220, 220)
		end
	elseif currentState == MatchState.States.MATCH then
		-- Match started, fade out
		if screenGui.Enabled then
			TweenService:Create(backdrop, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			task.delay(0.4, function()
				if currentState == MatchState.States.MATCH then
					screenGui.Enabled = false
					backdrop.BackgroundTransparency = 0.05 -- reset for next round
					container.Visible = true
					statusBanner.Visible = false
					movementLockSignal:Fire(false)
				end
			end)
		end
	end
end)

return VotingController
