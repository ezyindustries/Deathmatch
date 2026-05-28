--!strict
-- Deathmatch scoreboard — hidden by default during gameplay, shown only while
-- the player HOLDS TAB. Disappears as soon as TAB is released. Casual mode has
-- its own always-visible score HUD, so we additionally gate visibility on the
-- active gamemode being "deathmatch".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local MatchState = require(Shared.Modules.MatchState)

local DeathmatchLeaderboardController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MAX_ENTRIES = 7 -- 7-player matches (bots fill empty slots)

-- Suppress Roblox's default PlayerList (which also opens on TAB) so it doesn't
-- show alongside ours. Wrapped in pcall because SetCore can fail early in init.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeathmatchLeaderboardHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Centered modal-style panel — larger now that it's a hold-to-show modal
-- (not a passive HUD), so all rows are easily readable at a glance.
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 480, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(80, 90, 110)
panelStroke.Thickness = 1
panelStroke.Transparency = 0.4
panelStroke.Parent = panel

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 0)
layout.Parent = panel

-- Header row
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
header.BorderSizePixel = 0
header.LayoutOrder = 0
header.Parent = panel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 10)
headerCorner.Parent = header

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(1, 0, 1, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Font = Enum.Font.GothamBlack
headerTitle.TextSize = 16
headerTitle.TextColor3 = Color3.fromRGB(255, 200, 100)
headerTitle.Text = "BATTLE SCOREBOARD"
headerTitle.Parent = header

-- Tab hint at top-right of header
local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(0, 80, 0, 16)
hint.AnchorPoint = Vector2.new(1, 0.5)
hint.Position = UDim2.new(1, -12, 0.5, 0)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamBold
hint.TextSize = 10
hint.TextColor3 = Color3.fromRGB(150, 160, 180)
hint.Text = "HOLD TAB"
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.Parent = header

-- Row builder
local rowFrames: { Frame } = {}
local rowLabels: {
	{ rank: TextLabel, name: TextLabel, kills: TextLabel }
} = {}

for i = 1, MAX_ENTRIES do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(22, 25, 35) or Color3.fromRGB(18, 20, 28)
	row.BorderSizePixel = 0
	row.LayoutOrder = i
	row.Visible = false
	row.Parent = panel

	local rank = Instance.new("TextLabel")
	rank.Size = UDim2.new(0, 40, 1, 0)
	rank.Position = UDim2.new(0, 12, 0, 0)
	rank.BackgroundTransparency = 1
	rank.Font = Enum.Font.GothamBlack
	rank.TextSize = 14
	rank.TextColor3 = Color3.fromRGB(255, 200, 100)
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Text = ""
	rank.Parent = row

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -130, 1, 0)
	name.Position = UDim2.new(0, 56, 0, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.Gotham
	name.TextSize = 15
	name.TextColor3 = Color3.fromRGB(230, 230, 240)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = ""
	name.Parent = row

	local kills = Instance.new("TextLabel")
	kills.Size = UDim2.new(0, 70, 1, 0)
	kills.AnchorPoint = Vector2.new(1, 0)
	kills.Position = UDim2.new(1, -12, 0, 0)
	kills.BackgroundTransparency = 1
	kills.Font = Enum.Font.GothamBlack
	kills.TextSize = 16
	kills.TextColor3 = Color3.fromRGB(255, 255, 255)
	kills.TextXAlignment = Enum.TextXAlignment.Right
	kills.Text = ""
	kills.Parent = row

	table.insert(rowFrames, row)
	table.insert(rowLabels, { rank = rank, name = name, kills = kills })
end

local function updateRows(scoreboard: { any })
	for i = 1, MAX_ENTRIES do
		local entry = scoreboard[i]
		local row = rowFrames[i]
		local labels = rowLabels[i]
		if entry then
			labels.rank.Text = "#" .. i
			labels.kills.Text = tostring(entry.kills or 0)
			local rankTag = entry.rank and ("[" .. entry.rank .. "] ") or ""
			if entry.isBot then
				labels.name.Text = "[BOT] " .. (entry.name or "?")
				labels.name.TextColor3 = Color3.fromRGB(170, 180, 210)
				row.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(22, 25, 35) or Color3.fromRGB(18, 20, 28)
			elseif entry.userId == player.UserId then
				labels.name.Text = rankTag .. (entry.name or "?")
				row.BackgroundColor3 = Color3.fromRGB(80, 50, 30)
				labels.name.TextColor3 = Color3.fromRGB(255, 220, 130)
			else
				labels.name.Text = rankTag .. (entry.name or "?")
				row.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(22, 25, 35) or Color3.fromRGB(18, 20, 28)
				labels.name.TextColor3 = Color3.fromRGB(230, 230, 240)
			end
			row.Visible = true
		else
			row.Visible = false
		end
	end
end

-- ============================================================
-- MINI SCOREBOARD — top-right corner, always visible during DM match.
-- Compact: top 4 entries, name + kills only. Player's own row highlighted.
-- ============================================================
local MINI_ENTRIES = 4
local miniGui = Instance.new("ScreenGui")
miniGui.Name = "DMMiniScoreboard"
miniGui.ResetOnSpawn = false
miniGui.IgnoreGuiInset = true
miniGui.DisplayOrder = 49
miniGui.Enabled = false
miniGui.Parent = playerGui

local miniPanel = Instance.new("Frame")
miniPanel.Size = UDim2.new(0, 200, 0, 4 + MINI_ENTRIES * 20 + 4)
-- Anchored to top-center, offset right of MatchHUD (which is centered at top,
-- width 420, position UDim2.new(0.5, -210, 0, 16)). Place mini board flush
-- against match HUD's right edge with a 10px gap.
miniPanel.AnchorPoint = Vector2.new(0, 0)
miniPanel.Position = UDim2.new(0.5, 220, 0, 16)
miniPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
miniPanel.BackgroundTransparency = 0.25
miniPanel.BorderSizePixel = 0
miniPanel.Parent = miniGui
local miniCorner = Instance.new("UICorner"); miniCorner.CornerRadius = UDim.new(0, 6); miniCorner.Parent = miniPanel
local miniStroke = Instance.new("UIStroke"); miniStroke.Color = Color3.fromRGB(70, 80, 100); miniStroke.Thickness = 1; miniStroke.Transparency = 0.5; miniStroke.Parent = miniPanel

local miniLayout = Instance.new("UIListLayout")
miniLayout.FillDirection = Enum.FillDirection.Vertical
miniLayout.SortOrder = Enum.SortOrder.LayoutOrder
miniLayout.Padding = UDim.new(0, 0)
miniLayout.Parent = miniPanel
local miniPad = Instance.new("UIPadding")
miniPad.PaddingTop = UDim.new(0, 4); miniPad.PaddingBottom = UDim.new(0, 4)
miniPad.Parent = miniPanel

type MiniRow = { row: Frame, rank: TextLabel, name: TextLabel, kills: TextLabel }
local miniRows: { MiniRow } = {}
for i = 1, MINI_ENTRIES do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 20)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = i
	row.Visible = false
	row.Parent = miniPanel

	local rank = Instance.new("TextLabel")
	rank.Size = UDim2.new(0, 24, 1, 0)
	rank.Position = UDim2.new(0, 8, 0, 0)
	rank.BackgroundTransparency = 1
	rank.Font = Enum.Font.GothamBold
	rank.TextSize = 11
	rank.TextColor3 = Color3.fromRGB(255, 200, 100)
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Text = ""
	rank.Parent = row

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -80, 1, 0)
	name.Position = UDim2.new(0, 34, 0, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.Gotham
	name.TextSize = 12
	name.TextColor3 = Color3.fromRGB(230, 230, 240)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = ""
	name.Parent = row

	local kills = Instance.new("TextLabel")
	kills.Size = UDim2.new(0, 36, 1, 0)
	kills.AnchorPoint = Vector2.new(1, 0)
	kills.Position = UDim2.new(1, -8, 0, 0)
	kills.BackgroundTransparency = 1
	kills.Font = Enum.Font.GothamBold
	kills.TextSize = 12
	kills.TextColor3 = Color3.fromRGB(255, 255, 255)
	kills.TextXAlignment = Enum.TextXAlignment.Right
	kills.Text = ""
	kills.Parent = row

	table.insert(miniRows, { row = row, rank = rank, name = name, kills = kills })
end

local function updateMiniRows(scoreboard: { any })
	for i = 1, MINI_ENTRIES do
		local entry = scoreboard[i]
		local r = miniRows[i]
		if entry then
			r.rank.Text = "#" .. i
			r.kills.Text = tostring(entry.kills or 0)
			-- Build name prefix: bot tag OR DM rank short tag (e.g., "B1", "G3")
			local prefix: string
			if entry.isBot then
				prefix = "[B] "
			elseif entry.rank then
				prefix = "[" .. entry.rank .. "] "
			else
				prefix = ""
			end
			r.name.Text = prefix .. (entry.name or "?")
			if entry.userId == player.UserId then
				r.row.BackgroundColor3 = Color3.fromRGB(80, 50, 30)
				r.row.BackgroundTransparency = 0.2
				r.name.TextColor3 = Color3.fromRGB(255, 220, 130)
			else
				r.row.BackgroundTransparency = 1
				r.name.TextColor3 = entry.isBot and Color3.fromRGB(170, 180, 210) or Color3.fromRGB(230, 230, 240)
			end
			r.row.Visible = true
		else
			r.row.Visible = false
		end
	end
end

-- ============================================================
-- Visibility — held-TAB only, deathmatch + MATCH state only
-- ============================================================
local currentState: string? = nil
local currentGamemode: string? = nil
local tabHeld = false

local function refreshVisible()
	local canShow = currentState == MatchState.States.MATCH and currentGamemode == "deathmatch"
	-- TAB modal: only while held + DM match active
	screenGui.Enabled = canShow and tabHeld
	-- Mini scoreboard intentionally DISABLED: ScoreboardController owns the
	-- top-right card now. Keeping miniGui forever-disabled here avoids the
	-- "two cards #1-4 side by side" duplicate the user spotted in the
	-- published build.
	miniGui.Enabled = false
end

Remotes.ScoreChanged.OnClientEvent:Connect(function(scoreboard: { any })
	if scoreboard then
		updateRows(scoreboard)
		updateMiniRows(scoreboard)
	end
end)

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	if not payload then return end
	currentState = payload.state
	currentGamemode = payload.gamemode
	refreshVisible()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		tabHeld = true
		refreshVisible()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Tab then
		tabHeld = false
		refreshVisible()
	end
end)

return DeathmatchLeaderboardController
