--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local GameConfig = require(Shared.Constants.GameConfig)

local SpectatorController = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SpectatorHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 80
screenGui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(80, 10, 10)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.Parent = screenGui

local deathTitle = Instance.new("TextLabel")
deathTitle.Size = UDim2.new(0, 600, 0, 60)
deathTitle.AnchorPoint = Vector2.new(0.5, 0)
deathTitle.Position = UDim2.new(0.5, 0, 0.22, 0)
deathTitle.BackgroundTransparency = 1
deathTitle.Font = Enum.Font.GothamBlack
deathTitle.TextSize = 44
deathTitle.TextColor3 = Color3.fromRGB(255, 90, 90)
deathTitle.TextStrokeTransparency = 0.4
deathTitle.Text = "KNOCKED OUT"
deathTitle.Parent = screenGui
deathTitle.Visible = false

local deathInfo = Instance.new("TextLabel")
deathInfo.Size = UDim2.new(0, 600, 0, 26)
deathInfo.AnchorPoint = Vector2.new(0.5, 0)
deathInfo.Position = UDim2.new(0.5, 0, 0.22, 56)
deathInfo.BackgroundTransparency = 1
deathInfo.Font = Enum.Font.GothamMedium
deathInfo.TextSize = 16
deathInfo.TextColor3 = Color3.fromRGB(255, 200, 200)
deathInfo.TextStrokeTransparency = 0.5
deathInfo.Text = ""
deathInfo.Parent = screenGui
deathInfo.Visible = false

local respawnLabel = Instance.new("TextLabel")
respawnLabel.Size = UDim2.new(0, 400, 0, 28)
respawnLabel.AnchorPoint = Vector2.new(0.5, 0)
respawnLabel.Position = UDim2.new(0.5, 0, 0.22, 96)
respawnLabel.BackgroundTransparency = 1
respawnLabel.Font = Enum.Font.GothamBold
respawnLabel.TextSize = 18
respawnLabel.TextColor3 = Color3.fromRGB(255, 230, 90)
respawnLabel.Text = "Respawning in 3s..."
respawnLabel.Parent = screenGui
respawnLabel.Visible = false

-- Spectator controls (bottom)
local controlsPanel = Instance.new("Frame")
controlsPanel.Size = UDim2.new(0, 460, 0, 56)
controlsPanel.AnchorPoint = Vector2.new(0.5, 1)
controlsPanel.Position = UDim2.new(0.5, 0, 0.85, 0)
controlsPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
controlsPanel.BackgroundTransparency = 0.25
controlsPanel.BorderSizePixel = 0
controlsPanel.Visible = false
controlsPanel.Parent = screenGui

local controlsCorner = Instance.new("UICorner")
controlsCorner.CornerRadius = UDim.new(0, 12)
controlsCorner.Parent = controlsPanel

local spectatingLabel = Instance.new("TextLabel")
spectatingLabel.Size = UDim2.new(1, -160, 1, 0)
spectatingLabel.Position = UDim2.new(0, 80, 0, 0)
spectatingLabel.BackgroundTransparency = 1
spectatingLabel.Font = Enum.Font.GothamBold
spectatingLabel.TextSize = 16
spectatingLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
spectatingLabel.Text = "Spectating: —"
spectatingLabel.Parent = controlsPanel

local prevBtn = Instance.new("TextButton")
prevBtn.Size = UDim2.new(0, 60, 0, 36)
prevBtn.AnchorPoint = Vector2.new(0, 0.5)
prevBtn.Position = UDim2.new(0, 10, 0.5, 0)
prevBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
prevBtn.BorderSizePixel = 0
prevBtn.Font = Enum.Font.GothamBold
prevBtn.TextSize = 14
prevBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
prevBtn.Text = "< Prev"
prevBtn.AutoButtonColor = false
prevBtn.Parent = controlsPanel
local pc = Instance.new("UICorner")
pc.CornerRadius = UDim.new(0, 8)
pc.Parent = prevBtn

local nextBtn = Instance.new("TextButton")
nextBtn.Size = UDim2.new(0, 60, 0, 36)
nextBtn.AnchorPoint = Vector2.new(1, 0.5)
nextBtn.Position = UDim2.new(1, -10, 0.5, 0)
nextBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
nextBtn.BorderSizePixel = 0
nextBtn.Font = Enum.Font.GothamBold
nextBtn.TextSize = 14
nextBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
nextBtn.Text = "Next >"
nextBtn.AutoButtonColor = false
nextBtn.Parent = controlsPanel
local nc = Instance.new("UICorner")
nc.CornerRadius = UDim.new(0, 8)
nc.Parent = nextBtn

local isSpectating = false
local spectatingPlayer: Player? = nil
local deathTime: number = 0
local cameraConnection: RBXScriptConnection? = nil

local function getAlivePlayers(): { Player }
	local alive = {}
	for _, p in Players:GetPlayers() do
		if p == player then
			continue
		end
		local character = p.Character
		if not character then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			table.insert(alive, p)
		end
	end
	return alive
end

local function followPlayer(target: Player?)
	spectatingPlayer = target
	if target then
		spectatingLabel.Text = string.format("Spectating: %s", target.Name)
	else
		spectatingLabel.Text = "No alive players"
	end
end

local function pickNext(direction: number)
	local alive = getAlivePlayers()
	if #alive == 0 then
		followPlayer(nil)
		return
	end
	if not spectatingPlayer then
		followPlayer(alive[1])
		return
	end
	local currentIndex = 1
	for i, p in alive do
		if p == spectatingPlayer then
			currentIndex = i
			break
		end
	end
	local newIndex = ((currentIndex - 1 + direction) % #alive) + 1
	followPlayer(alive[newIndex])
end

prevBtn.MouseButton1Click:Connect(function()
	pickNext(-1)
end)
nextBtn.MouseButton1Click:Connect(function()
	pickNext(1)
end)

local function updateCamera()
	if not spectatingPlayer or not spectatingPlayer.Character then
		local alive = getAlivePlayers()
		if #alive > 0 then
			followPlayer(alive[math.random(#alive)])
		end
		return
	end
	local char = spectatingPlayer.Character
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	camera.CFrame = CFrame.new(root.Position + Vector3.new(0, 8, -16), root.Position + Vector3.new(0, 2, 0))
end

local function enterSpectator(info: any?)
	if isSpectating then
		return
	end
	isSpectating = true
	deathTime = os.clock()

	overlay.Visible = true
	deathTitle.Visible = true
	respawnLabel.Visible = true
	controlsPanel.Visible = true
	TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.55 }):Play()

	if info then
		local hsTag = info.isHeadshot and "  [HEADSHOT]" or ""
		deathInfo.Text = string.format("KO'd by %s • %s (%dm)%s",
			info.killer or "?",
			info.weapon or "?",
			math.floor(info.distance or 0),
			hsTag)
		deathInfo.Visible = true
	else
		deathInfo.Visible = false
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local alive = getAlivePlayers()
	if #alive > 0 then
		followPlayer(alive[1])
	else
		followPlayer(nil)
	end

	if cameraConnection then
		cameraConnection:Disconnect()
	end
	cameraConnection = RunService.RenderStepped:Connect(function()
		if not isSpectating then
			return
		end
		updateCamera()
		local remaining = math.max(0, GameConfig.RespawnDelay - (os.clock() - deathTime))
		respawnLabel.Text = string.format("Respawning in %ds...", math.ceil(remaining))
	end)
end

local function exitSpectator()
	if not isSpectating then
		return
	end
	isSpectating = false
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	camera.CameraType = Enum.CameraType.Custom
	overlay.Visible = false
	overlay.BackgroundTransparency = 1
	deathTitle.Visible = false
	deathInfo.Visible = false
	respawnLabel.Visible = false
	controlsPanel.Visible = false
end

local pendingDeathInfo: any? = nil

Remotes.DeathInfo.OnClientEvent:Connect(function(info: any)
	pendingDeathInfo = info
end)

local function onCharacter(character: Model)
	exitSpectator()
	pendingDeathInfo = nil
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		enterSpectator(pendingDeathInfo)
	end)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

return SpectatorController
