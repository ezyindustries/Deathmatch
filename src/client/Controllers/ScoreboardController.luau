--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local UITheme = require(Shared.Modules.UITheme)
local DMTeams = require(Shared.Modules.DMTeams)
local ClientSignals = require(Shared.Modules.ClientSignals)

local ScoreboardController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ScoreboardHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ---------------------------------------------------------------------------
-- MINI SCOREBOARD (top-right cluster) — 2 team-score rows.
-- Was: top-N player rank rows. Now: TIM KAWAN [kills] / TIM LAWAN [kills],
-- color-coded with subtle team-tinted background. Total height tightly bounded
-- (~50px desktop, ~44px mobile) so the KillFeed sits comfortably below.
-- ---------------------------------------------------------------------------
local MINI_ROW_W_DESKTOP = 210
local MINI_ROW_H_DESKTOP = 28
local MINI_ROW_W_MOBILE = 150
local MINI_ROW_H_MOBILE = 24
local MINI_ROW_GAP_DESKTOP = 3
local MINI_ROW_GAP_MOBILE = 2
local MINI_ROWS = 2 -- always exactly 2 rows (team A + team B)

local function isMobileViewport(): boolean
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	return vw < 900
end

-- Total mini-scoreboard height. Exposed for KillFeed positioning math.
function ScoreboardController.getMiniHeight(): number
	local mobile = isMobileViewport()
	local rowH = mobile and MINI_ROW_H_MOBILE or MINI_ROW_H_DESKTOP
	local gap = mobile and MINI_ROW_GAP_MOBILE or MINI_ROW_GAP_DESKTOP
	return MINI_ROWS * rowH + (MINI_ROWS - 1) * gap
end

function ScoreboardController.getMiniWidth(): number
	return isMobileViewport() and MINI_ROW_W_MOBILE or MINI_ROW_W_DESKTOP
end

-- Anchored top-right container.
local mini = Instance.new("Frame")
mini.Name = "MiniScoreboard"
mini.AnchorPoint = Vector2.new(1, 0)
mini.BackgroundTransparency = 1
mini.BorderSizePixel = 0
mini.Parent = screenGui

local miniLayout = Instance.new("UIListLayout")
miniLayout.FillDirection = Enum.FillDirection.Vertical
miniLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
miniLayout.VerticalAlignment = Enum.VerticalAlignment.Top
miniLayout.SortOrder = Enum.SortOrder.LayoutOrder
miniLayout.Parent = mini

-- Build the two persistent team rows once. We update text/colors via refs
-- rather than rebuild instances on every TeamStateChanged tick.
type MiniRowRefs = {
	row: Frame,
	nameLbl: TextLabel,
	killsLbl: TextLabel,
	tintGrad: UIGradient,
}

local function buildMiniRow(teamId: string, layoutOrder: number): MiniRowRefs
	local mobile = isMobileViewport()
	local rowH = mobile and MINI_ROW_H_MOBILE or MINI_ROW_H_DESKTOP
	local rowW = mobile and MINI_ROW_W_MOBILE or MINI_ROW_W_DESKTOP
	local color = DMTeams.Colors[teamId]
	local displayName = DMTeams.Display[teamId]

	local row = Instance.new("Frame")
	row.Name = "Team_" .. teamId
	row.Size = UDim2.fromOffset(rowW, rowH)
	row.BackgroundColor3 = UITheme.Color.bgElevated
	row.BackgroundTransparency = 0.15
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = mini
	UITheme.corner(row, "md")

	-- Subtle team-tint gradient (left = brighter team color, right = panel bg)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(
			math.min(1, color.R * 0.5 + 0.05),
			math.min(1, color.G * 0.5 + 0.05),
			math.min(1, color.B * 0.5 + 0.05)
		)),
		ColorSequenceKeypoint.new(1, UITheme.Color.bgElevated),
	})
	grad.Rotation = 0
	grad.Parent = row

	-- Color stripe on the very left (3px)
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 3, 1, 0)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Parent = row
	UITheme.corner(stripe, "sm")

	-- Team name (left-aligned, bold, team color)
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -56, 1, 0)
	nameLbl.Position = UDim2.new(0, mobile and 8 or 10, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = UITheme.Font.heading
	nameLbl.TextSize = mobile and UITheme.FontSize.micro or UITheme.FontSize.caption
	nameLbl.TextColor3 = color
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = string.upper(displayName)
	nameLbl.Parent = row

	-- Kills (right-aligned, mono, team color, bold)
	local killsLbl = Instance.new("TextLabel")
	killsLbl.Size = UDim2.new(0, 48, 1, 0)
	killsLbl.Position = UDim2.new(1, -(48 + (mobile and 8 or 10)), 0, 0)
	killsLbl.BackgroundTransparency = 1
	killsLbl.Font = UITheme.Font.mono
	killsLbl.TextSize = mobile and UITheme.FontSize.micro or UITheme.FontSize.caption
	killsLbl.TextColor3 = color
	killsLbl.TextXAlignment = Enum.TextXAlignment.Right
	killsLbl.Text = "0"
	killsLbl.Parent = row

	return { row = row, nameLbl = nameLbl, killsLbl = killsLbl, tintGrad = grad }
end

local miniRowA = buildMiniRow("A", 1)
local miniRowB = buildMiniRow("B", 2)

local function refreshMiniLayout()
	local mobile = isMobileViewport()
	local w = mobile and MINI_ROW_W_MOBILE or MINI_ROW_W_DESKTOP
	local rowH = mobile and MINI_ROW_H_MOBILE or MINI_ROW_H_DESKTOP
	local h = ScoreboardController.getMiniHeight()
	mini.Size = UDim2.new(0, w, 0, h)
	local rightOffset = UITheme.Space.l
	if mobile then rightOffset = UITheme.Space.m end
	local topInset = GuiService:GetGuiInset().Y
	mini.Position = UDim2.new(1, -rightOffset, 0, topInset + UITheme.Space.l)
	miniLayout.Padding = UDim.new(0, mobile and MINI_ROW_GAP_MOBILE or MINI_ROW_GAP_DESKTOP)

	-- Resize the persistent rows too
	for _, ref in { miniRowA, miniRowB } do
		ref.row.Size = UDim2.fromOffset(w, rowH)
		ref.nameLbl.TextSize = mobile and UITheme.FontSize.micro or UITheme.FontSize.caption
		ref.killsLbl.TextSize = mobile and UITheme.FontSize.micro or UITheme.FontSize.caption
		ref.nameLbl.Position = UDim2.new(0, mobile and 8 or 10, 0, 0)
		ref.killsLbl.Position = UDim2.new(1, -(48 + (mobile and 8 or 10)), 0, 0)
	end
end
refreshMiniLayout()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshMiniLayout)
end

-- ---------------------------------------------------------------------------
-- FULL SCOREBOARD (hold Tab) — 2 columns side-by-side, sorted within team.
-- Responsive: base 640x420, clamped to ≤95% vw / ≤92% vh on small viewports
-- (iPhone 4S 480x320 → ~456x294). A UIScale on the panel shrinks content
-- proportionally on mobile + ultra-mobile so player rows stay readable.
-- ---------------------------------------------------------------------------
local fullScoreboard = Instance.new("Frame")
fullScoreboard.Size = UDim2.fromOffset(640, 420)
fullScoreboard.AnchorPoint = Vector2.new(0.5, 0.5)
fullScoreboard.Position = UDim2.fromScale(0.5, 0.5)
fullScoreboard.BackgroundColor3 = UITheme.Color.bgBase
fullScoreboard.BackgroundTransparency = 0.05
fullScoreboard.BorderSizePixel = 0
fullScoreboard.Visible = false
fullScoreboard.Parent = screenGui
UITheme.corner(fullScoreboard, "lg")
UITheme.stroke(fullScoreboard, "borderSubtle", 1)

-- Multi-viewport responsive sizing for the full scoreboard. Without this the
-- 640x420 panel overflows iPhone 4S (480x320) — JOIN buttons + headers go
-- off-screen and the close-via-Tab-release still works but the modal looks
-- broken. We clamp the panel to viewport bounds and apply UIScale to keep
-- inner text proportional.
local fullScoreboardScale = Instance.new("UIScale")
fullScoreboardScale.Scale = 1
fullScoreboardScale.Parent = fullScoreboard

local function refreshFullScoreboardSize()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(640, 420)
	local maxW = v.X * 0.95
	local maxH = v.Y * 0.92
	-- Scale so the natural 640x420 layout fits within the viewport bounds.
	local sx = math.min(1, maxW / 640)
	local sy = math.min(1, maxH / 420)
	fullScoreboardScale.Scale = math.min(sx, sy)
end
refreshFullScoreboardSize()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshFullScoreboardSize)
end

local fullTitle = Instance.new("TextLabel")
fullTitle.Size = UDim2.new(1, 0, 0, 40)
fullTitle.BackgroundTransparency = 1
fullTitle.Font = UITheme.Font.heading
fullTitle.TextSize = UITheme.FontSize.h3
fullTitle.TextColor3 = UITheme.Color.textPrimary
fullTitle.Text = "SCOREBOARD"
fullTitle.Parent = fullScoreboard

-- Container for the two team columns
local columnsContainer = Instance.new("Frame")
columnsContainer.Size = UDim2.new(1, -UITheme.Space.l * 2, 1, -56)
columnsContainer.Position = UDim2.new(0, UITheme.Space.l, 0, 48)
columnsContainer.BackgroundTransparency = 1
columnsContainer.Parent = fullScoreboard

local columnsLayout = Instance.new("UIListLayout")
columnsLayout.FillDirection = Enum.FillDirection.Horizontal
columnsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
columnsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
columnsLayout.Padding = UDim.new(0, UITheme.Space.s)
columnsLayout.SortOrder = Enum.SortOrder.LayoutOrder
columnsLayout.Parent = columnsContainer

type ColumnRefs = {
	frame: Frame,
	header: TextLabel,
	rowsHolder: Frame,
}

local function buildColumn(teamId: string, layoutOrder: number): ColumnRefs
	local color = DMTeams.Colors[teamId]
	local displayName = DMTeams.Display[teamId]

	local col = Instance.new("Frame")
	col.Name = "Col_" .. teamId
	col.Size = UDim2.new(0.5, -UITheme.Space.xs, 1, 0)
	col.BackgroundColor3 = UITheme.Color.bgElevated
	col.BackgroundTransparency = 0.1
	col.BorderSizePixel = 0
	col.LayoutOrder = layoutOrder
	col.Parent = columnsContainer
	UITheme.corner(col, "md")

	-- Header bar: team name + team-aggregate kills
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -UITheme.Space.m * 2, 0, 28)
	header.Position = UDim2.new(0, UITheme.Space.m, 0, UITheme.Space.s)
	header.BackgroundTransparency = 1
	header.Font = UITheme.Font.heading
	header.TextSize = UITheme.FontSize.body
	header.TextColor3 = color
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = string.upper(displayName) .. "  0"
	header.Parent = col

	-- Colored separator bar
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -UITheme.Space.m * 2, 0, 2)
	sep.Position = UDim2.new(0, UITheme.Space.m, 0, 42)
	sep.BackgroundColor3 = color
	sep.BackgroundTransparency = 0.4
	sep.BorderSizePixel = 0
	sep.Parent = col
	UITheme.corner(sep, "sm")

	-- Player rows holder
	local rowsHolder = Instance.new("Frame")
	rowsHolder.Size = UDim2.new(1, -UITheme.Space.m * 2, 1, -52)
	rowsHolder.Position = UDim2.new(0, UITheme.Space.m, 0, 50)
	rowsHolder.BackgroundTransparency = 1
	rowsHolder.Parent = col

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.Padding = UDim.new(0, UITheme.Space.xs)
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = rowsHolder

	return { frame = col, header = header, rowsHolder = rowsHolder }
end

local colA = buildColumn("A", 1)
local colB = buildColumn("B", 2)

local function clearColumn(col: ColumnRefs)
	for _, c in col.rowsHolder:GetChildren() do
		if c:IsA("Frame") then c:Destroy() end
	end
end

local function buildPlayerRow(entry: any, rank: number, teamId: string, parent: Frame)
	local color = DMTeams.Colors[teamId]
	local isLocal = entry.userId == player.UserId

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 26)
	row.LayoutOrder = rank
	row.BackgroundColor3 = isLocal and UITheme.Color.bgHover or UITheme.Color.bgBase
	row.BackgroundTransparency = isLocal and 0.1 or 0.3
	row.BorderSizePixel = 0
	row.Parent = parent
	UITheme.corner(row, "sm")

	-- Team-tinted left stripe (3px)
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 3, 1, 0)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Parent = row

	-- Rank tag "#1"
	local rankLbl = Instance.new("TextLabel")
	rankLbl.Size = UDim2.new(0, 22, 1, 0)
	rankLbl.Position = UDim2.new(0, 8, 0, 0)
	rankLbl.BackgroundTransparency = 1
	rankLbl.Font = UITheme.Font.heading
	rankLbl.TextSize = UITheme.FontSize.caption
	rankLbl.TextColor3 = UITheme.Color.textTertiary
	rankLbl.TextXAlignment = Enum.TextXAlignment.Left
	rankLbl.Text = "#" .. tostring(rank)
	rankLbl.Parent = row

	-- Player name (truncates)
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -100, 1, 0)
	nameLbl.Position = UDim2.new(0, 34, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = UITheme.Font.body
	nameLbl.TextSize = UITheme.FontSize.caption
	nameLbl.TextColor3 = isLocal and UITheme.Color.accentPrimary or UITheme.Color.textPrimary
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = tostring(entry.name or "?")
	nameLbl.Parent = row

	-- K/D (mono, right-aligned)
	local kdLbl = Instance.new("TextLabel")
	kdLbl.Size = UDim2.new(0, 60, 1, 0)
	kdLbl.Position = UDim2.new(1, -68, 0, 0)
	kdLbl.BackgroundTransparency = 1
	kdLbl.Font = UITheme.Font.mono
	kdLbl.TextSize = UITheme.FontSize.caption
	kdLbl.TextColor3 = UITheme.Color.textSecondary
	kdLbl.TextXAlignment = Enum.TextXAlignment.Right
	kdLbl.Text = string.format("%d/%d", entry.kills or 0, entry.deaths or 0)
	kdLbl.Parent = row
end

-- ---------------------------------------------------------------------------
-- Score update (handles legacy flat-list payload AND new team payload).
-- ---------------------------------------------------------------------------
-- Legacy ScoreChanged payload: flat array { entry, ... }
-- New (post-Agent-A) payload:  { players = {entry,...}, teamA = {...}, teamB = {...} }
-- Defensive parse handles both.
local function parsePayload(payload: any): ({ any }, { kills: number, deaths: number }?, { kills: number, deaths: number }?)
	if typeof(payload) ~= "table" then
		return {}, nil, nil
	end
	-- New shape: has .players
	if payload.players and typeof(payload.players) == "table" then
		return payload.players, payload.teamA, payload.teamB
	end
	-- Old shape: payload is the list itself
	return payload, nil, nil
end

-- Split a player list into teamA / teamB columns. Entries without entry.team
-- (legacy payload pre-Agent-A) fall back to A on alternating index so the
-- scoreboard still shows SOMETHING during the transition.
local function splitByTeam(players: { any }): ({ any }, { any })
	local aList, bList = {}, {}
	for i, entry in ipairs(players) do
		local team = entry.team
		if team == "A" then
			table.insert(aList, entry)
		elseif team == "B" then
			table.insert(bList, entry)
		else
			-- Legacy fallback: distribute by index parity
			if (i % 2) == 1 then table.insert(aList, entry)
			else table.insert(bList, entry) end
		end
	end
	-- Sort within each column by kills desc (deaths asc as tiebreaker)
	local function cmp(a: any, b: any): boolean
		if a.kills == b.kills then return (a.deaths or 0) < (b.deaths or 0) end
		return (a.kills or 0) > (b.kills or 0)
	end
	table.sort(aList, cmp)
	table.sort(bList, cmp)
	return aList, bList
end

local function aggregateKills(list: { any }): number
	local sum = 0
	for _, e in list do sum += (e.kills or 0) end
	return sum
end

-- Track latest team-aggregate kills (preferred source = TeamStateChanged when
-- available; fallback to scoreboard aggregation).
local latestTeamKills: { A: number, B: number } = { A = 0, B = 0 }

local function renderScoreboard(payload: any)
	local players, teamA, teamB = parsePayload(payload)
	local aList, bList = splitByTeam(players)

	-- Determine kill totals: prefer payload-provided aggregates, else compute
	local aKills = (teamA and teamA.kills) or aggregateKills(aList)
	local bKills = (teamB and teamB.kills) or aggregateKills(bList)
	latestTeamKills.A = aKills
	latestTeamKills.B = bKills

	-- Update mini scoreboard rows
	miniRowA.killsLbl.Text = tostring(aKills)
	miniRowB.killsLbl.Text = tostring(bKills)

	-- Update full scoreboard column headers + rows
	colA.header.Text = string.format("%s  %d", string.upper(DMTeams.Display.A), aKills)
	colB.header.Text = string.format("%s  %d", string.upper(DMTeams.Display.B), bKills)

	clearColumn(colA)
	clearColumn(colB)
	for i, entry in ipairs(aList) do buildPlayerRow(entry, i, "A", colA.rowsHolder) end
	for i, entry in ipairs(bList) do buildPlayerRow(entry, i, "B", colB.rowsHolder) end
end

Remotes.ScoreChanged.OnClientEvent:Connect(renderScoreboard)

-- TeamStateChanged carries team aggregates directly (kills/deaths/players).
-- We update the mini-scoreboard team kills immediately so the chip stays live
-- even between ScoreChanged broadcasts.
Remotes.TeamStateChanged.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then return end
	if payload.teamA and typeof(payload.teamA.kills) == "number" then
		latestTeamKills.A = payload.teamA.kills
		miniRowA.killsLbl.Text = tostring(payload.teamA.kills)
		colA.header.Text = string.format("%s  %d", string.upper(DMTeams.Display.A), payload.teamA.kills)
	end
	if payload.teamB and typeof(payload.teamB.kills) == "number" then
		latestTeamKills.B = payload.teamB.kills
		miniRowB.killsLbl.Text = tostring(payload.teamB.kills)
		colB.header.Text = string.format("%s  %d", string.upper(DMTeams.Display.B), payload.teamB.kills)
	end
end)

-- ---------------------------------------------------------------------------
-- "Change Team" button (visible inside the full scoreboard).
-- Fires the ClientSignal — TeamSelectController handles open.
-- ---------------------------------------------------------------------------
local changeTeamBtn = Instance.new("TextButton")
changeTeamBtn.Name = "ChangeTeam"
changeTeamBtn.AnchorPoint = Vector2.new(1, 0)
changeTeamBtn.Position = UDim2.new(1, -UITheme.Space.m, 0, UITheme.Space.s)
changeTeamBtn.Size = UDim2.fromOffset(120, 28)
changeTeamBtn.BackgroundColor3 = UITheme.Color.bgHover
changeTeamBtn.AutoButtonColor = false
changeTeamBtn.Font = UITheme.Font.heading
changeTeamBtn.TextSize = UITheme.FontSize.caption
changeTeamBtn.TextColor3 = UITheme.Color.textPrimary
changeTeamBtn.Text = "GANTI TIM"
changeTeamBtn.BorderSizePixel = 0
changeTeamBtn.Parent = fullScoreboard
UITheme.corner(changeTeamBtn, "md")
UITheme.stroke(changeTeamBtn, "accentPrimary", 1, 0.6)

changeTeamBtn.MouseEnter:Connect(function()
	changeTeamBtn.BackgroundColor3 = UITheme.Color.bgPressed
end)
changeTeamBtn.MouseLeave:Connect(function()
	changeTeamBtn.BackgroundColor3 = UITheme.Color.bgHover
end)
changeTeamBtn.MouseButton1Click:Connect(function()
	ClientSignals.Get("OpenTeamSelect"):Fire()
end)

-- ---------------------------------------------------------------------------
-- Tab toggle for full scoreboard
-- ---------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		fullScoreboard.Visible = true
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Tab then
		fullScoreboard.Visible = false
	end
end)

-- ---------------------------------------------------------------------------
-- Match results banner (unchanged behavior)
-- ---------------------------------------------------------------------------
local resultsBanner = Instance.new("Frame")
resultsBanner.Size = UDim2.fromOffset(540, 130)
resultsBanner.AnchorPoint = Vector2.new(0.5, 0.5)
resultsBanner.Position = UDim2.new(0.5, 0, 0.4, 0)
resultsBanner.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
resultsBanner.BackgroundTransparency = 0.1
resultsBanner.BorderSizePixel = 0
resultsBanner.Visible = false
resultsBanner.Parent = screenGui

-- Results banner clamp — 540 wide overflows iPhone 4S 480px viewport.
-- UIScale on the banner shrinks proportionally to fit ≤90% vw.
local resultsBannerScale = Instance.new("UIScale")
resultsBannerScale.Scale = 1
resultsBannerScale.Parent = resultsBanner
local function refreshResultsBannerScale()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(540, 130)
	resultsBannerScale.Scale = math.min(1, (v.X * 0.9) / 540)
end
refreshResultsBannerScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshResultsBannerScale)
end

local resultsCorner = Instance.new("UICorner")
resultsCorner.CornerRadius = UDim.new(0, 14)
resultsCorner.Parent = resultsBanner

local resultsTitle = Instance.new("TextLabel")
resultsTitle.Size = UDim2.new(1, 0, 0, 40)
resultsTitle.Position = UDim2.new(0, 0, 0, 12)
resultsTitle.BackgroundTransparency = 1
resultsTitle.Font = Enum.Font.GothamBold
resultsTitle.TextSize = 22
resultsTitle.TextColor3 = Color3.fromRGB(255, 220, 80)
resultsTitle.Text = "MATCH RESULTS"
resultsTitle.Parent = resultsBanner

local resultsMvp = Instance.new("TextLabel")
resultsMvp.Size = UDim2.new(1, -40, 0, 28)
resultsMvp.Position = UDim2.new(0, 20, 0, 56)
resultsMvp.BackgroundTransparency = 1
resultsMvp.Font = Enum.Font.GothamBold
resultsMvp.TextSize = 18
resultsMvp.TextColor3 = Color3.fromRGB(255, 255, 255)
resultsMvp.Text = ""
resultsMvp.Parent = resultsBanner

local resultsSummary = Instance.new("TextLabel")
resultsSummary.Size = UDim2.new(1, -40, 0, 24)
resultsSummary.Position = UDim2.new(0, 20, 0, 90)
resultsSummary.BackgroundTransparency = 1
resultsSummary.Font = Enum.Font.Gotham
resultsSummary.TextSize = 14
resultsSummary.TextColor3 = Color3.fromRGB(200, 200, 220)
resultsSummary.Text = ""
resultsSummary.Parent = resultsBanner

Remotes.MatchResults.OnClientEvent:Connect(function(results: any)
	-- TDM: show winning team big + team scores. Fallback to FFA-style MVP
	-- only message when winningTeam absent (e.g. casual mode or legacy).
	if results.winningTeam then
		local teamName = if results.winningTeam == "A" then "TIM KAWAN" else "TIM LAWAN"
		local teamColor = if results.winningTeam == "A"
			then Color3.fromRGB(96, 165, 250)
			else Color3.fromRGB(248, 113, 113)
		resultsTitle.Text = teamName .. " MENANG!"
		resultsTitle.TextColor3 = teamColor
		local wins = results.teamWins or { A = 0, B = 0 }
		local mvpStr = ""
		if results.mvp and results.mvp.kills > 0 then
			mvpStr = string.format("  •  🏆 MVP: %s (%d)", results.mvp.name, results.mvp.kills)
		end
		resultsMvp.Text = string.format("Tim Kawan %d  —  %d Tim Lawan%s",
			wins.A or 0, wins.B or 0, mvpStr)
	elseif results.teamWins then
		resultsTitle.Text = "DRAW"
		resultsTitle.TextColor3 = Color3.fromRGB(255, 220, 80)
		local wins = results.teamWins
		resultsMvp.Text = string.format("Tim Kawan %d  —  %d Tim Lawan (seri)",
			wins.A or 0, wins.B or 0)
	else
		-- Legacy FFA fallback
		resultsTitle.Text = "MATCH RESULTS"
		resultsTitle.TextColor3 = Color3.fromRGB(255, 220, 80)
		if results.mvp and results.mvp.kills > 0 then
			resultsMvp.Text = string.format("🏆 MVP: %s  (%d KOs)", results.mvp.name, results.mvp.kills)
		else
			resultsMvp.Text = "No MVP — no KOs this match"
		end
	end
	resultsSummary.Text = string.format("%d players competed", #results.scoreboard)
	resultsBanner.Visible = true
	task.delay(6, function()
		resultsBanner.Visible = false
	end)
end)

-- ---------------------------------------------------------------------------
-- Pure helpers (exported for unit tests)
-- ---------------------------------------------------------------------------
ScoreboardController.splitByTeam = splitByTeam
ScoreboardController.parsePayload = parsePayload
ScoreboardController.aggregateKills = aggregateKills

return ScoreboardController
