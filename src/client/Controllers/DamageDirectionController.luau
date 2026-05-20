--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

local DamageDirectionController = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DamageDirectionHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40
screenGui.Parent = playerGui

type IndicatorEntry = {
	arrow: TextLabel,
	angle: number,
	expireAt: number,
}

local activeIndicators: { IndicatorEntry } = {}
local INDICATOR_LIFETIME = 1.2

local function makeArrow(): TextLabel
	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(0, 60, 0, 60)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextSize = 40
	arrow.TextColor3 = Color3.fromRGB(255, 70, 70)
	arrow.TextStrokeColor3 = Color3.fromRGB(120, 0, 0)
	arrow.TextStrokeTransparency = 0.2
	arrow.Text = "▲"
	arrow.Parent = screenGui
	return arrow
end

local function computeRelativeAngle(attackerPos: Vector3): number?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end

	local toAttacker = attackerPos - root.Position
	local toAttackerFlat = Vector3.new(toAttacker.X, 0, toAttacker.Z)
	if toAttackerFlat.Magnitude < 0.1 then
		return nil
	end
	toAttackerFlat = toAttackerFlat.Unit

	local camLook = camera.CFrame.LookVector
	local camLookFlat = Vector3.new(camLook.X, 0, camLook.Z)
	if camLookFlat.Magnitude < 0.1 then
		return nil
	end
	camLookFlat = camLookFlat.Unit

	local dot = camLookFlat:Dot(toAttackerFlat)
	local cross = camLookFlat.X * toAttackerFlat.Z - camLookFlat.Z * toAttackerFlat.X
	return math.atan2(cross, dot)
end

Remotes.DamageTaken.OnClientEvent:Connect(function(info: any)
	if not info or not info.attackerPosition then
		return
	end
	local angle = computeRelativeAngle(info.attackerPosition)
	if not angle then
		return
	end
	local arrow = makeArrow()
	table.insert(activeIndicators, {
		arrow = arrow,
		angle = angle,
		expireAt = os.clock() + INDICATOR_LIFETIME,
	})
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for i = #activeIndicators, 1, -1 do
		local entry = activeIndicators[i]
		if now >= entry.expireAt then
			entry.arrow:Destroy()
			table.remove(activeIndicators, i)
		else
			local lifeLeft = (entry.expireAt - now) / INDICATOR_LIFETIME
			local screenX = 0.5 + math.sin(entry.angle) * 0.36
			local screenY = 0.5 - math.cos(entry.angle) * 0.28
			entry.arrow.Position = UDim2.fromScale(screenX, screenY)
			entry.arrow.Rotation = math.deg(entry.angle)
			entry.arrow.TextTransparency = 1 - lifeLeft
			entry.arrow.TextStrokeTransparency = math.clamp(0.2 + (1 - lifeLeft) * 0.6, 0, 1)
		end
	end
end)

return DamageDirectionController
