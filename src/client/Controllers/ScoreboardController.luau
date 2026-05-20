--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

local ScoreboardController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ScoreboardHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Compact mini-scoreboard (top-left, always visible)
local mini = Instance.new("Frame")
mini.Size = UDim2.new(0, 260, 0, 36)
mini.Position = UDim2.new(0, 20, 0, 20)
mini.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
mini.BackgroundTransparency = 0.2
mini.BorderSizePixel = 0
mini.Parent = screenGui

local miniCorner = Instance.new("UICorner")
miniCorner.CornerRadius = UDim.new(0, 10)
miniCorner.Parent = mini

local miniLabel = Instance.new("TextLabel")
miniLabel.Size = UDim2.new(1, -16, 1, 0)
miniLabel.Position = UDim2.new(0, 8, 0, 0)
miniLabel.BackgroundTransparency = 1
miniLabel.Font = Enum.Font.GothamBold
miniLabel.TextSize = 16
miniLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
miniLabel.TextXAlignment = Enum.TextXAlignment.Left
miniLabel.Text = "K 0  /  D 0"
miniLabel.Parent = mini

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
	clearRows()
	for i, entry in ipairs(list) do
		buildRow(entry, i)
		if entry.userId == player.UserId then
			miniLabel.Text = string.format("K %d  /  D %d", entry.kills, entry.deaths)
		end
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
