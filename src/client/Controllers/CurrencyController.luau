--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local MatchState = require(Shared.Modules.MatchState)
local UITheme = require(Shared.Modules.UITheme)

-- Viewport-based mobile detection (Studio Device Emulator-friendly).
local function getViewportW(): number
	local cam = Workspace.CurrentCamera
	return (cam and cam.ViewportSize.X) or 1920
end
local function isMobileVP(): boolean return getViewportW() < 900 end

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
container.Size = UDim2.new(0, 200, 0, 44) -- refreshed in applyCurrencyResponsive
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

-- Track row refs so applyCurrencyResponsive can resize labels + dots on viewport change.
type RowRefs = { row: Frame, dot: Frame, label: TextLabel }
local rowRefs: { RowRefs } = {}

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

	table.insert(rowRefs, { row = row, dot = dot, label = label })
	return label
end

local coinsLabel = makeRow(8, Color3.fromRGB(255, 200, 80), "Coins")

-- Responsive sizing — mobile shrinks the coin chip from 200x44 (~30% of 666px
-- viewport width) to 110x28, freeing space at the bottom-right corner so it
-- doesn't visually crowd the right-side menu button column.
local function applyCurrencyResponsive()
	if isMobileVP() then
		container.Size = UDim2.new(0, 110, 0, 28)
		container.Position = UDim2.new(1, -UITheme.Space.m, 1, -UITheme.Space.m)
		for _, ref in rowRefs do
			ref.row.Size = UDim2.new(1, -8, 0, 20)
			ref.row.Position = UDim2.new(0, 4, 0, 4)
			ref.dot.Size = UDim2.new(0, 10, 0, 10)
			ref.dot.Position = UDim2.new(0, 2, 0.5, -5)
			ref.label.Size = UDim2.new(1, -18, 1, 0)
			ref.label.Position = UDim2.new(0, 16, 0, 0)
			ref.label.TextSize = UITheme.FontSize.micro -- 11
		end
	else
		container.Size = UDim2.new(0, 200, 0, 44)
		container.Position = UDim2.new(1, -20, 1, -20)
		for _, ref in rowRefs do
			ref.row.Size = UDim2.new(1, -16, 0, 30)
			ref.row.Position = UDim2.new(0, 8, 0, 8)
			ref.dot.Size = UDim2.new(0, 16, 0, 16)
			ref.dot.Position = UDim2.new(0, 4, 0.5, -8)
			ref.label.Size = UDim2.new(1, -32, 1, 0)
			ref.label.Position = UDim2.new(0, 28, 0, 0)
			ref.label.TextSize = 18
		end
	end
end
applyCurrencyResponsive()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyCurrencyResponsive)
end

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
	-- On mobile the chip is narrow; use a shorter prefix so the number always fits.
	local prefix = if isMobileVP() then "$" else "Coins  "
	coinsLabel.Text = string.format("%s%d", prefix, data.coins)
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
