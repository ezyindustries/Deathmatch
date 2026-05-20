--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local AudioConfig = require(Shared.Modules.AudioConfig)

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

-- Map streak label → AudioConfig key (each tier has its own announcer sound)
local STREAK_SOUND_KEY: { [string]: string } = {
	["FIRST KILL"]  = "streak_first",
	["DOUBLE KILL"] = "streak_double",
	["TRIPLE KILL"] = "streak_triple",
	["QUADRA KILL"] = "streak_quadra",
	["PENTA KILL"]  = "streak_penta",
	["DOMINATOR"]   = "streak_dominator",
}

local function playStreakSound(label: string)
	local key = STREAK_SOUND_KEY[label]
	if not key then return end
	local entry = AudioConfig[key]
	if not entry then return end
	local s = Instance.new("Sound")
	s.SoundId = entry.id
	s.Volume = entry.volume or 0.7
	if entry.pitch then s.PlaybackSpeed = entry.pitch end
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 4)
end

local AnnouncementController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AnnouncementHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

local banner = Instance.new("Frame")
banner.Size = UDim2.new(0, 580, 0, 80)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.18, 0)
banner.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
banner.BackgroundTransparency = 0.15
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = screenGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 14)
bannerCorner.Parent = banner

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 200, 80)
stroke.Thickness = 2
stroke.Parent = banner

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 38)
titleLabel.Position = UDim2.new(0, 0, 0, 8)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 28
titleLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
titleLabel.Text = ""
titleLabel.Parent = banner

local subLabel = Instance.new("TextLabel")
subLabel.Size = UDim2.new(1, 0, 0, 24)
subLabel.Position = UDim2.new(0, 0, 0, 46)
subLabel.BackgroundTransparency = 1
subLabel.Font = Enum.Font.GothamMedium
subLabel.TextSize = 14
subLabel.TextColor3 = Color3.fromRGB(220, 220, 235)
subLabel.Text = ""
subLabel.Parent = banner

local TIER_COLORS = {
	{ minStreak = 2, color = Color3.fromRGB(255, 220, 80) },
	{ minStreak = 5, color = Color3.fromRGB(255, 150, 80) },
	{ minStreak = 7, color = Color3.fromRGB(255, 80, 100) },
	{ minStreak = 10, color = Color3.fromRGB(200, 80, 255) },
	{ minStreak = 15, color = Color3.fromRGB(120, 220, 255) },
}

local function colorForStreak(streak: number): Color3
	local result = TIER_COLORS[1].color
	for _, tier in TIER_COLORS do
		if streak >= tier.minStreak then
			result = tier.color
		end
	end
	return result
end

local activeToken = 0
local enabled = true

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	if data.settings then
		enabled = data.settings.killstreakAnnouncements ~= false
	end
end)

Remotes.KillstreakAnnouncement.OnClientEvent:Connect(function(info: any)
	if not enabled then
		return
	end
	activeToken += 1
	local myToken = activeToken

	local color = colorForStreak(info.streak)
	titleLabel.Text = info.label
	titleLabel.TextColor3 = color
	stroke.Color = color

	local isLocal = info.player == player.Name
	if isLocal then
		subLabel.Text = string.format("%d killstreak", info.streak)
		-- Play announcer voice ONLY for the local player's own streak
		playStreakSound(info.label)
	else
		subLabel.Text = string.format("%s — %d kills", info.player, info.streak)
	end

	banner.Visible = true
	banner.Size = UDim2.new(0, 580, 0, 0)
	TweenService:Create(banner, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 580, 0, 80),
	}):Play()

	task.delay(2.5, function()
		if activeToken == myToken then
			TweenService:Create(banner, TweenInfo.new(0.3), {
				BackgroundTransparency = 1,
			}):Play()
			task.delay(0.3, function()
				if activeToken == myToken then
					banner.Visible = false
					banner.BackgroundTransparency = 0.15
				end
			end)
		end
	end)
end)

return AnnouncementController
