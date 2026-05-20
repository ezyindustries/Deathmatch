--!strict
-- Toggle cursor-free mode (LeftAlt). Freezes camera & releases mouse so the
-- player can click HUD/menu elements. Pencet lagi buat balik ke first-person.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientSignals = require(Shared.Modules.ClientSignals)

local CursorModeController = {}

local TOGGLE_KEY = Enum.KeyCode.LeftAlt

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local cursorChanged = ClientSignals.Get("CursorModeChanged")
local pauseSignal = ClientSignals.Get("PauseMenuToggle")

local isCursorMode = false
local frozenCFrame: CFrame? = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CursorModeHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 25
screenGui.Parent = playerGui

local hint = Instance.new("Frame")
hint.Size = UDim2.new(0, 220, 0, 36)
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 0, 70)
hint.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
hint.BackgroundTransparency = 0.15
hint.BorderSizePixel = 0
hint.Visible = false
hint.Parent = screenGui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hint

local hintStroke = Instance.new("UIStroke")
hintStroke.Color = Color3.fromRGB(120, 160, 230)
hintStroke.Thickness = 1.5
hintStroke.Parent = hint

local hintLabel = Instance.new("TextLabel")
hintLabel.Size = UDim2.new(1, -10, 1, 0)
hintLabel.Position = UDim2.new(0, 5, 0, 0)
hintLabel.BackgroundTransparency = 1
hintLabel.Font = Enum.Font.GothamBold
hintLabel.TextSize = 13
hintLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
hintLabel.Text = "🖱 CURSOR MODE — Alt to lock back"

-- Persistent top-right hint: "ALT for cursor" — desktop-only (no keyboard ALT on touch).
-- Viewport-width check is robust for Studio Device Emulator (which keeps MouseEnabled=true).
local isTouchOnly = UserInputService.TouchEnabled and Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X < 700
local persistentHint = Instance.new("Frame")
persistentHint.Size = UDim2.new(0, 160, 0, 28)
persistentHint.AnchorPoint = Vector2.new(1, 0)
persistentHint.Position = UDim2.new(1, -20, 0, 76)
persistentHint.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
persistentHint.BackgroundTransparency = 0.3
persistentHint.BorderSizePixel = 0
persistentHint.Visible = not isTouchOnly
persistentHint.Parent = screenGui

local persistentCorner = Instance.new("UICorner")
persistentCorner.CornerRadius = UDim.new(0, 6)
persistentCorner.Parent = persistentHint

local persistentStroke = Instance.new("UIStroke")
persistentStroke.Color = Color3.fromRGB(80, 120, 180)
persistentStroke.Thickness = 1
persistentStroke.Transparency = 0.3
persistentStroke.Parent = persistentHint

local persistentLabel = Instance.new("TextLabel")
persistentLabel.Size = UDim2.new(1, -8, 1, 0)
persistentLabel.Position = UDim2.new(0, 4, 0, 0)
persistentLabel.BackgroundTransparency = 1
persistentLabel.Font = Enum.Font.GothamBold
persistentLabel.TextSize = 12
persistentLabel.TextColor3 = Color3.fromRGB(220, 230, 245)
persistentLabel.Text = "ALT for cursor"
persistentLabel.Parent = persistentHint
hintLabel.Parent = hint

local function enterCursorMode()
	if isCursorMode then
		return
	end
	isCursorMode = true
	frozenCFrame = camera.CFrame

	player.CameraMode = Enum.CameraMode.Classic
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = frozenCFrame :: CFrame

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	hint.Visible = true
	persistentHint.Visible = false
	cursorChanged:Fire(true)
end

local function exitCursorMode()
	if not isCursorMode then
		return
	end
	isCursorMode = false
	frozenCFrame = nil

	camera.CameraType = Enum.CameraType.Custom
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	hint.Visible = false
	persistentHint.Visible = true
	cursorChanged:Fire(false)
end

local function toggle()
	if isCursorMode then
		exitCursorMode()
	else
		enterCursorMode()
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == TOGGLE_KEY then
		toggle()
	end
end)

-- Keep camera frozen while in cursor mode (in case anything else moves it)
local RunService = game:GetService("RunService")
RunService.RenderStepped:Connect(function()
	if isCursorMode and frozenCFrame then
		camera.CFrame = frozenCFrame
	end
end)

-- If player respawns or pause menu opens, exit cursor mode so we don't get stuck
player.CharacterAdded:Connect(function()
	exitCursorMode()
end)

pauseSignal.Event:Connect(function(opened: boolean?)
	-- Pause menu needs free cursor to be clickable in first-person.
	if opened then
		enterCursorMode()
	else
		exitCursorMode()
	end
end)

-- Mobile cursor-mode button REMOVED — mobile has no mouse cursor concept,
-- and the button cluttered the gameplay HUD. Cursor mode is desktop-only
-- (toggled via LeftAlt). Mobile players don't need to lock/unlock cursor.

CursorModeController.IsCursorMode = function(): boolean
	return isCursorMode
end

return CursorModeController
