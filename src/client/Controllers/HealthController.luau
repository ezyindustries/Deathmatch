--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HealthController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HealthHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Size = UDim2.new(0, 260, 0, 56)
container.Position = UDim2.new(0, 24, 1, -80)
container.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
container.BackgroundTransparency = 0.25
container.BorderSizePixel = 0
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = container

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(70, 75, 95)
stroke.Thickness = 1
stroke.Parent = container

local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(1, -20, 0, 14)
barBg.Position = UDim2.new(0, 10, 1, -22)
barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
barBg.BorderSizePixel = 0
barBg.Parent = container

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBg

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(110, 220, 130)
barFill.BorderSizePixel = 0
barFill.Parent = barBg

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = barFill

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -20, 0, 22)
label.Position = UDim2.new(0, 10, 0, 6)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 18
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextXAlignment = Enum.TextXAlignment.Left
label.Text = "HP 100"
label.Parent = container

local lowHealthOverlay = Instance.new("Frame")
lowHealthOverlay.Size = UDim2.new(1, 0, 1, 0)
lowHealthOverlay.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
lowHealthOverlay.BackgroundTransparency = 1
lowHealthOverlay.BorderSizePixel = 0
lowHealthOverlay.ZIndex = -1
lowHealthOverlay.Parent = screenGui

local function colorForHealth(ratio: number): Color3
	if ratio > 0.6 then
		return Color3.fromRGB(110, 220, 130)
	elseif ratio > 0.3 then
		return Color3.fromRGB(240, 200, 80)
	else
		return Color3.fromRGB(230, 80, 80)
	end
end

local function bindHumanoid(humanoid: Humanoid)
	local function update()
		local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		barFill:TweenSize(UDim2.new(ratio, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.18, true)
		barFill.BackgroundColor3 = colorForHealth(ratio)
		label.Text = string.format("HP %d", math.ceil(humanoid.Health))
		lowHealthOverlay.BackgroundTransparency = math.max(0.85, 1 - (0.4 - math.min(0.4, ratio)) * 0.7)
	end

	humanoid.HealthChanged:Connect(update)
	update()
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	bindHumanoid(humanoid)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

return HealthController
