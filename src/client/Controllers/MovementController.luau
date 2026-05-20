--!strict
-- Movement: walk (default), sprint (Shift), scope-walk (slow while ADS).
-- WASD only. Locks first-person camera. Respects MovementLock signal (used by
-- voting overlay to freeze player). Sprint + ADS state owned by WeaponController
-- and broadcast via ClientSignals — this controller only enforces target speed.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local ClientSignals = require(Shared.Modules.ClientSignals)
local GameConfig = require(Shared.Constants.GameConfig)

local MovementController = {}

local JUMP_POWER = 52
local NORMAL_FOV = 70

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

camera.FieldOfView = NORMAL_FOV

local currentHumanoid: Humanoid? = nil
local isMovementLocked = false
local isSprinting = false
local isAds = false

ClientSignals.Get("MovementLock").Event:Connect(function(locked: boolean)
	isMovementLocked = locked == true
end)

ClientSignals.Get("SprintChanged").Event:Connect(function(value: boolean)
	isSprinting = value == true
end)

ClientSignals.Get("AdsChanged").Event:Connect(function(value: boolean)
	isAds = value == true
end)

local function targetSpeed(): number
	if isMovementLocked then return 0 end
	if isAds then return GameConfig.ADSWalkSpeed end
	if isSprinting then return GameConfig.SprintSpeed end
	return GameConfig.WalkSpeed
end

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	if data.settings and data.settings.baseFov then
		NORMAL_FOV = data.settings.baseFov
		camera.FieldOfView = NORMAL_FOV
	end
end)

local function lockFirstPerson()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	-- DevEnableMouseLock requires elevated permissions; just leave Roblox default
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end
	currentHumanoid = humanoid
	humanoid.UseJumpPower = true
	humanoid.JumpPower = JUMP_POWER
	humanoid.WalkSpeed = GameConfig.WalkSpeed
	humanoid.CameraOffset = Vector3.new(0, 0, 0)
	camera.FieldOfView = NORMAL_FOV
	lockFirstPerson()
end

lockFirstPerson()

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

-- Enforce WalkSpeed every frame so MovementLock takes effect immediately
-- and to undo any Roblox default-control overrides.
RunService.Heartbeat:Connect(function()
	if currentHumanoid and currentHumanoid.Parent then
		local target = targetSpeed()
		if currentHumanoid.WalkSpeed ~= target then
			currentHumanoid.WalkSpeed = target
		end
		local targetJump = isMovementLocked and 0 or JUMP_POWER
		if currentHumanoid.JumpPower ~= targetJump then
			currentHumanoid.JumpPower = targetJump
		end
	end
end)

return MovementController
