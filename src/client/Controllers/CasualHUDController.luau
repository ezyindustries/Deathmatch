--!strict
-- Casual-mode HUD (simplified — no bomb): round timer, team scores, team
-- badge, big WIN banner, blue overhead marker for teammates.
--
-- Listens to: CasualRoundState, CasualRoundResult, CasualMatchResult,
-- MatchStateChanged.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local Teams = require(Shared.Modules.Teams)

local CasualHUD = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CasualHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 105
screenGui.Enabled = false
screenGui.Parent = playerGui

-- =====================================================================
-- TOP-CENTER: round + scores + timer
-- Round 7 mobile shrink: panel 360x56 -> 260x40 with smaller scores/timer,
-- so the casual HUD stays discreet at iPhone 7 (666x374). Currently hidden
-- in production DM but supported for future Casual rollout.
-- =====================================================================
local function isMobileViewport(): boolean
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	return vw < 700
end

local topPanel = Instance.new("Frame")
topPanel.Size = UDim2.new(0, 360, 0, 56)
topPanel.AnchorPoint = Vector2.new(0.5, 0)
topPanel.Position = UDim2.new(0.5, 0, 0, 12)
topPanel.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
topPanel.BackgroundTransparency = 0.15
topPanel.BorderSizePixel = 0
topPanel.Parent = screenGui

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 8)
topCorner.Parent = topPanel

-- CT score (left)
local ctScore = Instance.new("TextLabel")
ctScore.Size = UDim2.new(0, 70, 0, 32)
ctScore.AnchorPoint = Vector2.new(0, 0)
ctScore.Position = UDim2.new(0, 12, 0, 4)
ctScore.BackgroundColor3 = Teams.Info.CT.color
ctScore.BorderSizePixel = 0
ctScore.Font = Enum.Font.GothamBlack
ctScore.TextSize = 22
ctScore.TextColor3 = Color3.fromRGB(255, 255, 255)
ctScore.Text = "CT 0"
ctScore.Parent = topPanel
local ctCorner = Instance.new("UICorner"); ctCorner.CornerRadius = UDim.new(0, 6); ctCorner.Parent = ctScore

-- T score (right)
local tScore = Instance.new("TextLabel")
tScore.Size = UDim2.new(0, 70, 0, 32)
tScore.AnchorPoint = Vector2.new(1, 0)
tScore.Position = UDim2.new(1, -12, 0, 4)
tScore.BackgroundColor3 = Teams.Info.T.color
tScore.BorderSizePixel = 0
tScore.Font = Enum.Font.GothamBlack
tScore.TextSize = 22
tScore.TextColor3 = Color3.fromRGB(255, 255, 255)
tScore.Text = "0 T"
tScore.Parent = topPanel
local tCorner = Instance.new("UICorner"); tCorner.CornerRadius = UDim.new(0, 6); tCorner.Parent = tScore

-- Timer (center large)
local timerLbl = Instance.new("TextLabel")
timerLbl.Size = UDim2.new(0, 140, 0, 32)
timerLbl.AnchorPoint = Vector2.new(0.5, 0)
timerLbl.Position = UDim2.new(0.5, 0, 0, 4)
timerLbl.BackgroundTransparency = 1
timerLbl.Font = Enum.Font.RobotoMono
timerLbl.TextSize = 26
timerLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLbl.Text = "1:30"
timerLbl.Parent = topPanel

-- Round + phase label (small, below)
local roundLbl = Instance.new("TextLabel")
roundLbl.Size = UDim2.new(1, 0, 0, 16)
roundLbl.Position = UDim2.new(0, 0, 0, 38)
roundLbl.BackgroundTransparency = 1
roundLbl.Font = Enum.Font.GothamBold
roundLbl.TextSize = 11
roundLbl.TextColor3 = Color3.fromRGB(180, 190, 210)
roundLbl.Text = "ROUND 1 — BUY"
roundLbl.Parent = topPanel

-- Responsive sizing: mobile shrinks panel + inner labels.
local function refreshTopLayout()
	local mobile = isMobileViewport()
	if mobile then
		topPanel.Size = UDim2.new(0, 260, 0, 40)
		ctScore.Size = UDim2.new(0, 52, 0, 22)
		ctScore.Position = UDim2.new(0, 8, 0, 3)
		ctScore.TextSize = 14
		tScore.Size = UDim2.new(0, 52, 0, 22)
		tScore.Position = UDim2.new(1, -8, 0, 3)
		tScore.TextSize = 14
		timerLbl.Size = UDim2.new(0, 110, 0, 22)
		timerLbl.Position = UDim2.new(0.5, 0, 0, 3)
		timerLbl.TextSize = 17
		roundLbl.Size = UDim2.new(1, 0, 0, 12)
		roundLbl.Position = UDim2.new(0, 0, 0, 26)
		roundLbl.TextSize = 9
	else
		topPanel.Size = UDim2.new(0, 360, 0, 56)
		ctScore.Size = UDim2.new(0, 70, 0, 32)
		ctScore.Position = UDim2.new(0, 12, 0, 4)
		ctScore.TextSize = 22
		tScore.Size = UDim2.new(0, 70, 0, 32)
		tScore.Position = UDim2.new(1, -12, 0, 4)
		tScore.TextSize = 22
		timerLbl.Size = UDim2.new(0, 140, 0, 32)
		timerLbl.Position = UDim2.new(0.5, 0, 0, 4)
		timerLbl.TextSize = 26
		roundLbl.Size = UDim2.new(1, 0, 0, 16)
		roundLbl.Position = UDim2.new(0, 0, 0, 38)
		roundLbl.TextSize = 11
	end
end
refreshTopLayout()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshTopLayout)
end

-- =====================================================================
-- TEAM BADGE (bottom-left)
-- =====================================================================
local teamBadge = Instance.new("Frame")
teamBadge.Size = UDim2.new(0, 120, 0, 30)
teamBadge.AnchorPoint = Vector2.new(0, 1)
teamBadge.Position = UDim2.new(0, 20, 1, -20)
teamBadge.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
teamBadge.BorderSizePixel = 0
teamBadge.Visible = false
teamBadge.Parent = screenGui
local badgeCorner = Instance.new("UICorner"); badgeCorner.CornerRadius = UDim.new(0, 6); badgeCorner.Parent = teamBadge

local teamBadgeLbl = Instance.new("TextLabel")
teamBadgeLbl.Size = UDim2.new(1, 0, 1, 0)
teamBadgeLbl.BackgroundTransparency = 1
teamBadgeLbl.Font = Enum.Font.GothamBlack
teamBadgeLbl.TextSize = 14
teamBadgeLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
teamBadgeLbl.Text = "—"
teamBadgeLbl.Parent = teamBadge

-- Bomb status panel + plant/defuse hold bars REMOVED — simplified casual mode
-- is pure team deathmatch, no bomb mechanic.

-- =====================================================================
-- BIG WIN BANNER — dramatic full-screen overlay when a round ends.
-- Backdrop dim + huge team-colored text + small subtitle.
-- =====================================================================
local winOverlay = Instance.new("Frame")
winOverlay.Size = UDim2.new(1, 0, 1, 0)
winOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
winOverlay.BackgroundTransparency = 0.55
winOverlay.BorderSizePixel = 0
winOverlay.Visible = false
winOverlay.Parent = screenGui

local roundBanner = Instance.new("TextLabel")
roundBanner.Size = UDim2.new(1, 0, 0, 140)
roundBanner.AnchorPoint = Vector2.new(0.5, 0.5)
roundBanner.Position = UDim2.new(0.5, 0, 0.45, 0)
roundBanner.BackgroundTransparency = 1
roundBanner.Font = Enum.Font.GothamBlack
roundBanner.TextSize = 110
roundBanner.TextColor3 = Color3.fromRGB(255, 220, 100)
roundBanner.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
roundBanner.TextStrokeTransparency = 0.3
roundBanner.Text = ""
roundBanner.Parent = winOverlay

local bannerSub = Instance.new("TextLabel")
bannerSub.Size = UDim2.new(1, 0, 0, 30)
bannerSub.AnchorPoint = Vector2.new(0.5, 0)
bannerSub.Position = UDim2.new(0.5, 0, 0.45, 80)
bannerSub.BackgroundTransparency = 1
bannerSub.Font = Enum.Font.GothamBold
bannerSub.TextSize = 18
bannerSub.TextColor3 = Color3.fromRGB(220, 225, 235)
bannerSub.Text = ""
bannerSub.Parent = winOverlay

-- =====================================================================
-- ROUND-START BANNER — Distinct visual that fires at start of every BUY phase
-- so Casual feels different from DM (DM has no round structure). Shows
-- "ROUND X" big + "ELIMINATION — NO RESPAWN" subtitle.
-- =====================================================================
local roundStartOverlay = Instance.new("Frame")
roundStartOverlay.Size = UDim2.new(1, 0, 1, 0)
roundStartOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
roundStartOverlay.BackgroundTransparency = 0.5
roundStartOverlay.BorderSizePixel = 0
roundStartOverlay.Visible = false
roundStartOverlay.Parent = screenGui

local roundStartLbl = Instance.new("TextLabel")
roundStartLbl.Size = UDim2.new(1, 0, 0, 120)
roundStartLbl.AnchorPoint = Vector2.new(0.5, 0.5)
roundStartLbl.Position = UDim2.new(0.5, 0, 0.42, 0)
roundStartLbl.BackgroundTransparency = 1
roundStartLbl.Font = Enum.Font.GothamBlack
roundStartLbl.TextSize = 96
roundStartLbl.TextColor3 = Color3.fromRGB(255, 235, 140)
roundStartLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
roundStartLbl.TextStrokeTransparency = 0.2
roundStartLbl.Text = "ROUND 1"
roundStartLbl.Parent = roundStartOverlay

local roundStartSub = Instance.new("TextLabel")
roundStartSub.Size = UDim2.new(1, 0, 0, 32)
roundStartSub.AnchorPoint = Vector2.new(0.5, 0)
roundStartSub.Position = UDim2.new(0.5, 0, 0.42, 60)
roundStartSub.BackgroundTransparency = 1
roundStartSub.Font = Enum.Font.GothamBold
roundStartSub.TextSize = 22
roundStartSub.TextColor3 = Color3.fromRGB(240, 240, 240)
roundStartSub.Text = "ELIMINATION — NO RESPAWN"
roundStartSub.Parent = roundStartOverlay

local roundStartTeam = Instance.new("TextLabel")
roundStartTeam.Size = UDim2.new(1, 0, 0, 28)
roundStartTeam.AnchorPoint = Vector2.new(0.5, 0)
roundStartTeam.Position = UDim2.new(0.5, 0, 0.42, 100)
roundStartTeam.BackgroundTransparency = 1
roundStartTeam.Font = Enum.Font.GothamBold
roundStartTeam.TextSize = 18
roundStartTeam.TextColor3 = Color3.fromRGB(180, 200, 230)
roundStartTeam.Text = ""
roundStartTeam.Parent = roundStartOverlay

-- =====================================================================
-- STATE
-- =====================================================================
local currentPhase: string = "IDLE"
local currentRound: number = 0
local phaseEndsAt: number = 0
local localTeam: string? = nil
local teamsByKey: { [string]: string } = {} -- uid/botName → "T"/"CT" (for team marker)

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

-- =====================================================================
-- LISTENERS
-- =====================================================================
Remotes.CasualRoundState.OnClientEvent:Connect(function(payload: any)
	if not payload then return end
	screenGui.Enabled = true
	ctScore.Text = string.format("CT %d", payload.scoreCT or 0)
	tScore.Text = string.format("%d T", payload.scoreT or 0)
	roundLbl.Text = string.format("ROUND %d — %s", payload.round or 0, payload.phase or "IDLE")
	local prevPhase = currentPhase
	local prevRound = currentRound
	currentPhase = payload.phase or "IDLE"
	currentRound = payload.round or 0
	phaseEndsAt = payload.phaseEndsAt or 0
	if payload.teams then
		teamsByKey = payload.teams
		local key = tostring(player.UserId)
		localTeam = teamsByKey[key]
		if localTeam then
			local info = Teams.Info[localTeam]
			if info then
				teamBadge.BackgroundColor3 = info.color
				teamBadgeLbl.Text = info.shortName .. " — " .. info.displayName
				teamBadge.Visible = true
			end
		else
			teamBadge.Visible = false
		end
	end
	-- New round (BUY phase started OR round number bumped) → show round-start banner
	-- + hide any lingering win banner. Banner displays for ~2.2s (covers BUY freeze).
	if currentPhase == "BUY" and (prevPhase ~= "BUY" or currentRound ~= prevRound) then
		winOverlay.Visible = false
		roundStartLbl.Text = string.format("ROUND %d", currentRound)
		if localTeam then
			local info = Teams.Info[localTeam]
			if info then
				roundStartLbl.TextColor3 = info.color
				roundStartTeam.Text = "YOU ARE " .. info.shortName .. " — " .. info.displayName
				roundStartTeam.TextColor3 = info.color
			end
		else
			roundStartLbl.TextColor3 = Color3.fromRGB(255, 235, 140)
			roundStartTeam.Text = ""
		end
		roundStartOverlay.Visible = true
		local roundShown = currentRound
		task.delay(2.2, function()
			-- Only hide if still showing this same round (avoid clobbering a newer banner)
			if currentRound == roundShown then
				roundStartOverlay.Visible = false
			end
		end)
	end
end)

Remotes.CasualRoundResult.OnClientEvent:Connect(function(payload: any)
	if not payload then return end
	local winner = payload.winner or "?"
	local info = Teams.Info[winner]
	local color = info and info.color or Color3.fromRGB(180, 180, 180)
	roundBanner.Text = winner .. " WIN"
	roundBanner.TextColor3 = color
	bannerSub.Text = string.upper(payload.reason or "")
	bannerSub.TextColor3 = color
	winOverlay.Visible = true
	task.delay(3, function()
		winOverlay.Visible = false
	end)
end)

Remotes.CasualMatchResult.OnClientEvent:Connect(function(payload: any)
	if not payload then return end
	local winner = tostring(payload.winner)
	local info = Teams.Info[winner]
	local color = info and info.color or Color3.fromRGB(255, 220, 100)
	roundBanner.Text = winner .. " WIN"
	roundBanner.TextColor3 = color
	bannerSub.Text = string.format("MATCH OVER — FINAL: CT %d  vs  %d T",
		payload.finalScoreCT or 0, payload.finalScoreT or 0)
	bannerSub.TextColor3 = color
	winOverlay.Visible = true
	task.delay(8, function()
		winOverlay.Visible = false
		screenGui.Enabled = false
	end)
end)

-- HUD only shown for casual gamemode during MATCH
Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	if not payload then return end
	local active = payload.gamemode == "casual" and payload.state == "MATCH"
	screenGui.Enabled = active
	if not active then
		winOverlay.Visible = false
		roundStartOverlay.Visible = false
	end
end)

-- =====================================================================
-- RENDER TICK: update phase timer
-- =====================================================================
RunService.RenderStepped:Connect(function()
	if not screenGui.Enabled then return end
	local now = workspace:GetServerTimeNow()
	timerLbl.Text = fmtTime(math.max(0, phaseEndsAt - now))
end)

-- =====================================================================
-- BLUE TEAMMATE MARKER — small blue dot above each teammate's head so the
-- player can recognize allies from enemies. Refreshed every 0.5s; attaches
-- to player characters + bot models in workspace whose actorKey matches a
-- teammate in `teamsByKey`.
-- =====================================================================
local MARKER_NAME = "_CasualAllyMarker"
local function attachMarker(character: Model)
	local head = character:FindFirstChild("Head")
	if not head then return end
	if head:FindFirstChild(MARKER_NAME) then return end -- already attached
	local bb = Instance.new("BillboardGui")
	bb.Name = MARKER_NAME
	bb.Adornee = head
	bb.Size = UDim2.new(0, 20, 0, 20)
	bb.StudsOffset = Vector3.new(0, 2.4, 0)
	bb.AlwaysOnTop = true
	bb.Parent = head
	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(1, 0, 1, 0)
	dot.BackgroundColor3 = Color3.fromRGB(80, 150, 240)
	dot.BorderSizePixel = 0
	dot.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 1.5
	stroke.Parent = dot
end

local function detachMarker(character: Model)
	local head = character:FindFirstChild("Head")
	if not head then return end
	local bb = head:FindFirstChild(MARKER_NAME)
	if bb then bb:Destroy() end
end

local function refreshTeamMarkers()
	if not screenGui.Enabled or not localTeam then return end
	-- Players
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if not char then continue end
		local team = teamsByKey[tostring(p.UserId)]
		if p ~= player and team == localTeam then
			attachMarker(char)
		else
			detachMarker(char)
		end
	end
	-- Bots (models in workspace with IsBot attribute)
	for _, m in workspace:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("IsBot") then
			local team = teamsByKey[m.Name]
			if team == localTeam then
				attachMarker(m)
			else
				detachMarker(m)
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(refreshTeamMarkers)
	end
end)

return CasualHUD
