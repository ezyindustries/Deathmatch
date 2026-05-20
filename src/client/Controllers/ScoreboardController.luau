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

local ScoreboardController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ScoreboardHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ---------------------------------------------------------------------------
-- MINI SCOREBOARD (top-right cluster) — top-N rank list, always visible.
-- Shows up to 4 cards (#1..#4) with rank, name, K/D. Mobile shrinks rows
-- (260x36 → 180x26) and font (caption 13 → micro 11) so the cluster doesn't
-- crowd the FIRE button + right-edge column on narrow viewports.
-- ---------------------------------------------------------------------------
local MINI_MAX_ENTRIES = 4

-- Layout constants (desktop vs mobile). Exposed via ScoreboardController so
-- KillFeedController (and tests) can compute container offsets that sit
-- directly below the mini scoreboard without overlapping.
local MINI_ROW_W_DESKTOP = 260
local MINI_ROW_H_DESKTOP = 36
local MINI_ROW_W_MOBILE = 180
local MINI_ROW_H_MOBILE = 26
local MINI_ROW_GAP_DESKTOP = UITheme.Space.xs -- 4px
local MINI_ROW_GAP_MOBILE = 2

local function isMobileViewport(): boolean
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	return vw < 700
end

-- Compute total mini-scoreboard height (rows + gaps). Used by KillFeed to
-- position its container directly underneath.
function ScoreboardController.getMiniHeight(): number
	local mobile = isMobileViewport()
	local rowH = mobile and MINI_ROW_H_MOBILE or MINI_ROW_H_DESKTOP
	local gap = mobile and MINI_ROW_GAP_MOBILE or MINI_ROW_GAP_DESKTOP
	return MINI_MAX_ENTRIES * rowH + (MINI_MAX_ENTRIES - 1) * gap
end

function ScoreboardController.getMiniWidth(): number
	return isMobileViewport() and MINI_ROW_W_MOBILE or MINI_ROW_W_DESKTOP
end

-- Anchored top-right. Width/height get refreshed responsively below.
local mini = Instance.new("Frame")
mini.Name = "MiniScoreboard"
mini.AnchorPoint = Vector2.new(1, 0)
mini.BackgroundTransparency = 1 -- container is invisible; rows have their own bg
mini.BorderSizePixel = 0
mini.Parent = screenGui

local miniLayout = Instance.new("UIListLayout")
miniLayout.FillDirection = Enum.FillDirection.Vertical
miniLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
miniLayout.VerticalAlignment = Enum.VerticalAlignment.Top
miniLayout.SortOrder = Enum.SortOrder.LayoutOrder
miniLayout.Parent = mini

local function refreshMiniLayout()
	local mobile = isMobileViewport()
	local w = mobile and MINI_ROW_W_MOBILE or MINI_ROW_W_DESKTOP
	local h = ScoreboardController.getMiniHeight()
	mini.Size = UDim2.new(0, w, 0, h)
	-- Right-edge inset. Match KillFeedController's xl margin so they share the
	-- same right edge on desktop. On mobile, additionally clear the FIRE
	-- button + right-edge column — handled by KillFeed, but keep scoreboard
	-- with a generous mobile inset so it still has breathing room.
	local rightOffset = UITheme.Space.l -- 16
	if mobile then
		rightOffset = UITheme.Space.m -- 12 — tighter on phone to maximize space
	end
	local topInset = GuiService:GetGuiInset().Y
	mini.Position = UDim2.new(1, -rightOffset, 0, topInset + UITheme.Space.l)
	miniLayout.Padding = UDim.new(0, mobile and MINI_ROW_GAP_MOBILE or MINI_ROW_GAP_DESKTOP)
end
refreshMiniLayout()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshMiniLayout)
end

-- Per-row builder. Local player gets a cyan accent so they can spot themselves.
local function buildMiniRow(rank: number, entry: any, layoutOrder: number): Frame
	local mobile = isMobileViewport()
	local rowH = mobile and MINI_ROW_H_MOBILE or MINI_ROW_H_DESKTOP
	local rowW = mobile and MINI_ROW_W_MOBILE or MINI_ROW_W_DESKTOP
	local fontSize = mobile and UITheme.FontSize.micro or UITheme.FontSize.caption
	local isLocal = entry.userId == player.UserId

	local row = Instance.new("Frame")
	row.Name = "Rank" .. tostring(rank)
	row.Size = UDim2.new(0, rowW, 0, rowH)
	row.BackgroundColor3 = isLocal and UITheme.Color.bgHover or UITheme.Color.bgElevated
	row.BackgroundTransparency = 0.15
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = mini

	UITheme.corner(row, "md")

	-- Subtle accent stripe for local player (matches KillFeed tier stripe vibe)
	if isLocal then
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 3, 1, 0)
		stripe.BackgroundColor3 = UITheme.Color.accentPrimary
		stripe.BorderSizePixel = 0
		stripe.Parent = row
		UITheme.corner(stripe, "sm")
	end

	-- Rank "#1" tag on the left
	local rankLbl = Instance.new("TextLabel")
	rankLbl.Size = UDim2.new(0, mobile and 22 or 30, 1, 0)
	rankLbl.Position = UDim2.new(0, mobile and 8 or 10, 0, 0)
	rankLbl.BackgroundTransparency = 1
	rankLbl.Font = UITheme.Font.heading
	rankLbl.TextSize = fontSize
	rankLbl.TextColor3 = UITheme.Color.textTertiary
	rankLbl.TextXAlignment = Enum.TextXAlignment.Left
	rankLbl.Text = "#" .. tostring(rank)
	rankLbl.Parent = row

	-- Name (truncates if too long)
	local nameLbl = Instance.new("TextLabel")
	local namePadL = mobile and 32 or 44
	local kdW = mobile and 56 or 80
	nameLbl.Size = UDim2.new(1, -(namePadL + kdW + (mobile and 8 or 12)), 1, 0)
	nameLbl.Position = UDim2.new(0, namePadL, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = UITheme.Font.heading
	nameLbl.TextSize = fontSize
	nameLbl.TextColor3 = isLocal and UITheme.Color.accentPrimary or UITheme.Color.textPrimary
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = tostring(entry.name or "?")
	nameLbl.Parent = row

	-- K/D on the right
	local kdLbl = Instance.new("TextLabel")
	kdLbl.Size = UDim2.new(0, kdW, 1, 0)
	kdLbl.Position = UDim2.new(1, -(kdW + (mobile and 8 or 12)), 0, 0)
	kdLbl.BackgroundTransparency = 1
	kdLbl.Font = UITheme.Font.mono
	kdLbl.TextSize = fontSize
	kdLbl.TextColor3 = UITheme.Color.textSecondary
	kdLbl.TextXAlignment = Enum.TextXAlignment.Right
	kdLbl.Text = string.format("%d / %d", entry.kills or 0, entry.deaths or 0)
	kdLbl.Parent = row

	return row
end

local function clearMiniRows()
	for _, c in mini:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
end

-- Full scoreboard (hold Tab to show)
local fullScoreboard = Instance.new("Frame")
fullScoreboard.Size = UDim2.new(0, 480, 0, 380)
fullScoreboard.AnchorPoint = Vector2.new(0.5, 0.5)
fullScoreboard.Position = UDim2.new(0.5, 0, 0.5, 0)
fullScoreboard.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
fullScoreboard.BackgroundTransparency = 0.1
fullScoreboard.BorderSizePixel = 0
fullScoreboard.Visible = false
fullScoreboard.Parent = screenGui

local fullCorner = Instance.new("UICorner")
fullCorner.CornerRadius = UDim.new(0, 14)
fullCorner.Parent = fullScoreboard

local fullTitle = Instance.new("TextLabel")
fullTitle.Size = UDim2.new(1, 0, 0, 40)
fullTitle.BackgroundTransparency = 1
fullTitle.Font = Enum.Font.GothamBold
fullTitle.TextSize = 20
fullTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
fullTitle.Text = "Scoreboard"
fullTitle.Parent = fullScoreboard

local fullHeader = Instance.new("Frame")
fullHeader.Size = UDim2.new(1, -24, 0, 24)
fullHeader.Position = UDim2.new(0, 12, 0, 44)
fullHeader.BackgroundTransparency = 1
fullHeader.Parent = fullScoreboard

local function makeHeaderCol(text: string, x: number, w: number, align: Enum.TextXAlignment)
	local col = Instance.new("TextLabel")
	col.Size = UDim2.new(0, w, 1, 0)
	col.Position = UDim2.new(0, x, 0, 0)
	col.BackgroundTransparency = 1
	col.Font = Enum.Font.GothamMedium
	col.TextSize = 13
	col.TextColor3 = Color3.fromRGB(140, 145, 165)
	col.TextXAlignment = align
	col.Text = text
	col.Parent = fullHeader
end

makeHeaderCol("PLAYER", 8, 260, Enum.TextXAlignment.Left)
makeHeaderCol("KILLS", 280, 70, Enum.TextXAlignment.Center)
makeHeaderCol("DEATHS", 360, 70, Enum.TextXAlignment.Center)

local rowsContainer = Instance.new("Frame")
rowsContainer.Size = UDim2.new(1, -24, 1, -84)
rowsContainer.Position = UDim2.new(0, 12, 0, 72)
rowsContainer.BackgroundTransparency = 1
rowsContainer.Parent = fullScoreboard

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.FillDirection = Enum.FillDirection.Vertical
rowsLayout.Padding = UDim.new(0, 4)
rowsLayout.Parent = rowsContainer

local function clearRows()
	for _, c in rowsContainer:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
end

local function buildRow(entry: any, index: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 28)
	row.LayoutOrder = index
	local isLocal = entry.userId == player.UserId
	row.BackgroundColor3 = isLocal and Color3.fromRGB(45, 60, 80) or Color3.fromRGB(28, 28, 38)
	row.BorderSizePixel = 0
	row.Parent = rowsContainer

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local function makeCol(text: string, x: number, w: number, align: Enum.TextXAlignment, bold: boolean)
		local col = Instance.new("TextLabel")
		col.Size = UDim2.new(0, w, 1, 0)
		col.Position = UDim2.new(0, x, 0, 0)
		col.BackgroundTransparency = 1
		col.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		col.TextSize = 14
		col.TextColor3 = isLocal and Color3.fromRGB(130, 200, 255) or Color3.fromRGB(240, 240, 240)
		col.TextXAlignment = align
		col.Text = text
		col.Parent = row
	end

	makeCol(entry.name, 12, 256, Enum.TextXAlignment.Left, true)
	makeCol(tostring(entry.kills), 280, 70, Enum.TextXAlignment.Center, false)
	makeCol(tostring(entry.deaths), 360, 70, Enum.TextXAlignment.Center, false)
end

local function updateScoreboard(list: { any })
	-- Full scoreboard rows (visible while holding Tab)
	clearRows()
	for i, entry in ipairs(list) do
		buildRow(entry, i)
	end

	-- Mini scoreboard: top-N by kills (list arrives sorted from server). If the
	-- local player isn't already in the top-N, swap them into the last slot so
	-- the player can always see their own K/D.
	clearMiniRows()
	local topN: { any } = {}
	local localInTop = false
	local localEntry: any = nil
	for i, entry in ipairs(list) do
		if i <= MINI_MAX_ENTRIES then
			table.insert(topN, entry)
			if entry.userId == player.UserId then localInTop = true end
		elseif entry.userId == player.UserId then
			localEntry = entry
		end
	end
	if not localInTop and localEntry and #topN >= MINI_MAX_ENTRIES then
		topN[#topN] = localEntry
	end
	for i, entry in ipairs(topN) do
		buildMiniRow(i, entry, i)
	end
end

Remotes.ScoreChanged.OnClientEvent:Connect(updateScoreboard)

-- Toggle full scoreboard on Tab
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Tab then
		fullScoreboard.Visible = true
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Tab then
		fullScoreboard.Visible = false
	end
end)

-- Match results banner
local resultsBanner = Instance.new("Frame")
resultsBanner.Size = UDim2.new(0, 540, 0, 130)
resultsBanner.AnchorPoint = Vector2.new(0.5, 0.5)
resultsBanner.Position = UDim2.new(0.5, 0, 0.4, 0)
resultsBanner.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
resultsBanner.BackgroundTransparency = 0.1
resultsBanner.BorderSizePixel = 0
resultsBanner.Visible = false
resultsBanner.Parent = screenGui

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
	if results.mvp and results.mvp.kills > 0 then
		resultsMvp.Text = string.format("🏆 MVP: %s  (%d kills)", results.mvp.name, results.mvp.kills)
	else
		resultsMvp.Text = "No MVP — no kills this match"
	end
	resultsSummary.Text = string.format("%d players competed", #results.scoreboard)
	resultsBanner.Visible = true
	task.delay(6, function()
		resultsBanner.Visible = false
	end)
end)

return ScoreboardController
