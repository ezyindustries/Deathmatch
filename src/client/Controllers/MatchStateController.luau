--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Modules.MatchState)
local Remotes = require(Shared.Modules.Remotes)

local MatchStateController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 420, 0, 72)
frame.Position = UDim2.new(0.5, -210, 0, 16)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BackgroundTransparency = 0.2
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(70, 70, 90)
stroke.Thickness = 1
stroke.Parent = frame

local stateLabel = Instance.new("TextLabel")
stateLabel.Size = UDim2.new(1, -20, 0.55, 0)
stateLabel.Position = UDim2.new(0, 10, 0, 4)
stateLabel.BackgroundTransparency = 1
stateLabel.Font = Enum.Font.GothamBold
stateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
stateLabel.TextSize = 22
stateLabel.TextXAlignment = Enum.TextXAlignment.Center
stateLabel.Text = "Connecting..."
stateLabel.Parent = frame

local timerLabel = Instance.new("TextLabel")
timerLabel.Size = UDim2.new(1, -20, 0.45, 0)
timerLabel.Position = UDim2.new(0, 10, 0.5, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.Gotham
timerLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
timerLabel.TextSize = 18
timerLabel.TextXAlignment = Enum.TextXAlignment.Center
timerLabel.Text = ""
timerLabel.Parent = frame

local currentPayload: MatchState.StatePayload? = nil

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: MatchState.StatePayload)
	currentPayload = payload
	stateLabel.Text = MatchState.DisplayName[payload.state] or payload.state
end)

RunService.RenderStepped:Connect(function()
	if not currentPayload then
		return
	end
	local elapsed = Workspace:GetServerTimeNow() - currentPayload.startedAt
	local remaining = math.max(0, currentPayload.duration - elapsed)
	timerLabel.Text = string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
end)

return MatchStateController
