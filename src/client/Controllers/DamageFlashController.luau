--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

local DamageFlashController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DamageFlashHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 35
screenGui.Parent = playerGui

local vignette = Instance.new("ImageLabel")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.Image = "rbxasset://textures/ui/Vignette.png"
vignette.ImageColor3 = Color3.fromRGB(220, 30, 30)
vignette.ImageTransparency = 1
vignette.ScaleType = Enum.ScaleType.Stretch
vignette.Parent = screenGui

local edgeTop = Instance.new("Frame")
edgeTop.Size = UDim2.new(1, 0, 0.18, 0)
edgeTop.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
edgeTop.BackgroundTransparency = 1
edgeTop.BorderSizePixel = 0
edgeTop.Parent = screenGui

local topGradient = Instance.new("UIGradient")
topGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 1),
})
topGradient.Rotation = 90
topGradient.Parent = edgeTop

local edgeBottom = Instance.new("Frame")
edgeBottom.Size = UDim2.new(1, 0, 0.18, 0)
edgeBottom.Position = UDim2.new(0, 0, 1, 0)
edgeBottom.AnchorPoint = Vector2.new(0, 1)
edgeBottom.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
edgeBottom.BackgroundTransparency = 1
edgeBottom.BorderSizePixel = 0
edgeBottom.Parent = screenGui

local bottomGradient = Instance.new("UIGradient")
bottomGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 0),
})
bottomGradient.Rotation = 90
bottomGradient.Parent = edgeBottom

local flashIntensity = 0

local function pulse(damage: number)
	-- Damage 10 = 0.3 intensity, damage 50 = 1.0 intensity (capped)
	local addedIntensity = math.clamp(damage / 50, 0.15, 1)
	flashIntensity = math.min(1, flashIntensity + addedIntensity)
end

Remotes.DamageTaken.OnClientEvent:Connect(function(info: any)
	if not info or typeof(info.damage) ~= "number" then
		return
	end
	pulse(info.damage)
end)

-- Decay flash over time
RunService.RenderStepped:Connect(function(dt: number)
	if flashIntensity > 0 then
		flashIntensity = math.max(0, flashIntensity - dt * 1.4)
	end

	-- Map intensity → visuals (high health: barely visible; low health adds baseline already from HealthController)
	local vignetteAlpha = 1 - flashIntensity * 0.55
	local edgeAlpha = 1 - flashIntensity * 0.65

	vignette.ImageTransparency = vignetteAlpha
	edgeTop.BackgroundTransparency = edgeAlpha
	edgeBottom.BackgroundTransparency = edgeAlpha
end)

return DamageFlashController
