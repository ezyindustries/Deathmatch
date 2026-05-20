--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local MatchState = require(Shared.Modules.MatchState)

local CurrencyController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CurrencyHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 110 -- above MainMenu so visible from main menu too
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Size = UDim2.new(0, 200, 0, 44)
container.AnchorPoint = Vector2.new(1, 1) -- bottom-right anchor
container.Position = UDim2.new(1, -20, 1, -20)
container.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
container.BackgroundTransparency = 0.2
container.BorderSizePixel = 0
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = container

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(70, 75, 95)
stroke.Thickness = 1
stroke.Parent = container

local function makeRow(yOffset: number, accent: Color3, prefix: string): TextLabel
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -16, 0, 30)
	row.Position = UDim2.new(0, 8, 0, yOffset)
	row.BackgroundTransparency = 1
	row.Parent = container

	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 16, 0, 16)
	dot.Position = UDim2.new(0, 4, 0.5, -8)
	dot.BackgroundColor3 = accent
	dot.BorderSizePixel = 0
	dot.Parent = row

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -32, 1, 0)
	label.Position = UDim2.new(0, 28, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = prefix .. " 0"
	label.Parent = row

	return label
end

local coinsLabel = makeRow(8, Color3.fromRGB(255, 200, 80), "Coins")

local function pulse(label: TextLabel)
	local startSize = label.TextSize
	TweenService:Create(label, TweenInfo.new(0.12), { TextSize = startSize + 4 }):Play()
	task.delay(0.12, function()
		TweenService:Create(label, TweenInfo.new(0.18), { TextSize = startSize }):Play()
	end)
end

local lastCoins = 0

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	if data.coins ~= lastCoins then
		pulse(coinsLabel)
		lastCoins = data.coins
	end
	coinsLabel.Text = string.format("Coins  %d", data.coins)
end)

-- Visibility rules:
--   * Training mode → ALWAYS hidden (solo practice, no shop)
--   * Mobile + DM MATCH → hidden (cluttering gameplay HUD on small screen)
--   * Otherwise (lobby, cosmetic shop, PC always) → visible so player sees
--     balance for gacha decisions.
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local isTrainingMode = false
local inMatch = false

local function refreshCurrencyVisibility()
	if isTrainingMode then
		container.Visible = false
		return
	end
	if isMobile and inMatch then
		container.Visible = false
		return
	end
	container.Visible = true
end

Remotes.EnterTrainingMode.OnClientEvent:Connect(function(active: boolean)
	isTrainingMode = active == true
	refreshCurrencyVisibility()
end)

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	if not payload then return end
	inMatch = payload.state == MatchState.States.MATCH
	refreshCurrencyVisibility()
end)

refreshCurrencyVisibility()

return CurrencyController
