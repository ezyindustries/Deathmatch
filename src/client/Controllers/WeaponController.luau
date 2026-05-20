--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local WeaponConfig = require(Shared.Modules.WeaponConfig)
local CosmeticRegistry = require(Shared.Modules.CosmeticRegistry)
local AudioConfig = require(Shared.Modules.AudioConfig)
local ClientSignals = require(Shared.Modules.ClientSignals)
local GameConfig = require(Shared.Constants.GameConfig)

local SoundService = game:GetService("SoundService")

local function playUiSound(entry: any)
	if not entry then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = entry.id
	sound.Volume = entry.volume or 0.5
	sound.PlaybackSpeed = entry.pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(2, function()
		if sound and sound.Parent then
			sound:Destroy()
		end
	end)
end


local WeaponController = {}

local cursorModeActive = false
ClientSignals.Get("CursorModeChanged").Event:Connect(function(active: boolean)
	cursorModeActive = active == true
end)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local equippedId: string? = nil
local equippedSlotName: string? = nil
local lastFireAt: number = 0
local drawStartTime: number = 0
local crosshairBloom: number = 0
local recoilPitch: number = 0
local recoilYaw: number = 0
local recoilPitchVel: number = 0
local recoilYawVel: number = 0

-- Combat Knife swing animation (alternates left ↔ right each click, CS2-style wide slash)
local knifeSwingStart: number = -10  -- past epoch = no swing active
local knifeSwingDir: number = 1       -- 1 = right slash, -1 = left slash (flips each swing)
local KNIFE_SWING_DURATION = 0.3      -- matches left-click attack cooldown — full animation per swing

-- Knife stab animation (right-click forward thrust, works for all knife types)
local knifeStabStart: number = -10
local KNIFE_STAB_DURATION = 0.5      -- slower stab animation (cooldown 0.6s)
local lastKnifeStabAt: number = 0
local KNIFE_STAB_COOLDOWN = 0.6  -- 0.6s between right-click stabs
local pendingStab: boolean = false  -- consumed by tryFire to tell server "this is a stab" (90 dmg)
local currentSkinColor: Color3? = nil

local currentAmmo: number = 0
local currentMagSize: number = 0
local isReloading: boolean = false
local reloadStartTime: number = 0
local reloadDuration: number = 0

local cachedProfile: any = nil

local isAds: boolean = false
local adsTransition: number = 0 -- 0 = no ADS, 1 = full ADS
local NORMAL_FOV: number = 70
local ADS_FOV: number = 55

-- ADS input mode (set by SettingsController via ClientSignals; persisted in profile).
-- "hold" = scope while MB2 held; "toggle" = click MB2 to enter, click again to exit.
local adsMode: string = "hold"

-- Sprint state. LeftShift held → isSprinting = true (gated: AWP cannot sprint).
local isSprinting: boolean = false

-- Camera-bob phase accumulator (advances by dt * frequency each frame during movement).
local bobPhase: number = 0

type ViewmodelEntry = {
	part: Part,
	config: WeaponConfig.ViewmodelPart,
	baseColor: Color3,
}
local viewmodelParts: { ViewmodelEntry } = {}
local viewmodelFolder: Folder? = nil

-- ============ HUD ============

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WeaponHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ==========================================================================
-- AWP SCOPE OVERLAY (CS2-style: black mask + circular ring + crosshair lines)
-- Toggled via scopeOverlay.Visible in setAds().
-- ==========================================================================
local scopeOverlay = Instance.new("Frame")
scopeOverlay.Name = "ScopeOverlay"
scopeOverlay.Size = UDim2.fromScale(1, 1)
scopeOverlay.BackgroundTransparency = 1
scopeOverlay.Visible = false
scopeOverlay.ZIndex = 10
scopeOverlay.Parent = screenGui

-- Scope fills (almost) full screen height. Black bars on left/right (letterbox).
local function blackMask(): Frame
	local m = Instance.new("Frame")
	m.BackgroundColor3 = Color3.new(0, 0, 0)
	m.BorderSizePixel = 0
	m.ZIndex = 11
	m.Parent = scopeOverlay
	return m
end

local topMask = blackMask()
local bottomMask = blackMask()
bottomMask.AnchorPoint = Vector2.new(0, 1)
local leftMask = blackMask()
leftMask.AnchorPoint = Vector2.new(0, 0.5)
local rightMask = blackMask()
rightMask.AnchorPoint = Vector2.new(1, 0.5)

-- 4 corner bulges — circle masks CENTERED at each corner of the square hole.
-- One quarter of each circle protrudes INTO the hole's corner (CONVEX bulge),
-- carving the square corners off the hole so it looks round. The other 3
-- quarters extend outside the hole (overlap rect masks — harmless).
local function cornerMask(): Frame
	local c = Instance.new("Frame")
	c.BackgroundColor3 = Color3.new(0, 0, 0)
	c.BorderSizePixel = 0
	c.ZIndex = 11
	c.AnchorPoint = Vector2.new(0.5, 0.5) -- centered on hole corner
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0.5, 0)
	cc.Parent = c
	c.Parent = scopeOverlay
	return c
end
local cornerTL = cornerMask()
local cornerTR = cornerMask()
local cornerBL = cornerMask()
local cornerBR = cornerMask()

-- Circular ring outline (thin black ring around scope edge)
local ring = Instance.new("Frame")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.new(0.5, 0, 0.5, 0)
ring.BackgroundTransparency = 1
ring.ZIndex = 12
ring.Parent = scopeOverlay
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(0.5, 0)
ringCorner.Parent = ring
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = Color3.new(0, 0, 0)
ringStroke.Thickness = 3
ringStroke.Parent = ring

-- Horizontal + vertical crosshair lines (thin black, span scope diameter)
local hLine = Instance.new("Frame")
hLine.AnchorPoint = Vector2.new(0.5, 0.5)
hLine.Position = UDim2.new(0.5, 0, 0.5, 0)
hLine.BackgroundColor3 = Color3.new(0, 0, 0)
hLine.BorderSizePixel = 0
hLine.ZIndex = 12
hLine.Parent = scopeOverlay

local vLine = Instance.new("Frame")
vLine.AnchorPoint = Vector2.new(0.5, 0.5)
vLine.Position = UDim2.new(0.5, 0, 0.5, 0)
vLine.BackgroundColor3 = Color3.new(0, 0, 0)
vLine.BorderSizePixel = 0
vLine.ZIndex = 12
vLine.Parent = scopeOverlay

-- Mil-dot ticks: positioned by scale-of-half-radius so they stay consistent
-- across screen sizes. List of (scale from center, isVertical) pairs.
local tickFrames: { { frame: Frame, scale: number, vertical: boolean } } = {}
local function mkTick(scale: number, vertical: boolean)
	local t = Instance.new("Frame")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.BackgroundColor3 = Color3.new(0, 0, 0)
	t.BorderSizePixel = 0
	t.ZIndex = 12
	t.Parent = scopeOverlay
	table.insert(tickFrames, { frame = t, scale = scale, vertical = vertical })
end
-- 4 ticks each axis at 20/40/60/80% of half-diameter
for _, s in { 0.2, 0.4, 0.6, 0.8 } do
	mkTick(-s, false) -- left of center on h-line
	mkTick(s, false)  -- right
	mkTick(-s, true)  -- top of center on v-line
	mkTick(s, true)   -- bottom
end

-- Center dot
local centerDot = Instance.new("Frame")
centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
centerDot.Size = UDim2.fromOffset(3, 3)
centerDot.Position = UDim2.new(0.5, 0, 0.5, 0)
centerDot.BackgroundColor3 = Color3.new(0, 0, 0)
centerDot.BorderSizePixel = 0
centerDot.ZIndex = 13
centerDot.Parent = scopeOverlay
local centerDotCorner = Instance.new("UICorner")
centerDotCorner.CornerRadius = UDim.new(0.5, 0)
centerDotCorner.Parent = centerDot

-- ==========================================================================
-- DOT SIGHT OVERLAY (COD-style red-dot for non-sniper guns when ADS).
-- 4 L-shape corner brackets around a center red dot. Toggled in setAds()
-- by checking weapon.id ~= "sniper" (sniper uses the big scopeOverlay).
-- ==========================================================================
local dotSightOverlay = Instance.new("Frame")
dotSightOverlay.Name = "DotSightOverlay"
dotSightOverlay.Size = UDim2.fromScale(1, 1)
dotSightOverlay.BackgroundTransparency = 1
dotSightOverlay.Visible = false
dotSightOverlay.ZIndex = 8
dotSightOverlay.Parent = screenGui

local sightBox = Instance.new("Frame")
sightBox.AnchorPoint = Vector2.new(0.5, 0.5)
sightBox.Position = UDim2.new(0.5, 0, 0.5, 0)
sightBox.Size = UDim2.fromOffset(72, 72)
sightBox.BackgroundTransparency = 1
sightBox.BorderSizePixel = 0
sightBox.ZIndex = 8
sightBox.Parent = dotSightOverlay

-- L-bracket builder: horizontal segment + vertical segment at a corner of sightBox
local function bracket(hAlign: string, vAlign: string)
	local ax = if hAlign == "left" then 0 else 1
	local ay = if vAlign == "top" then 0 else 1
	local hSeg = Instance.new("Frame")
	hSeg.AnchorPoint = Vector2.new(ax, ay)
	hSeg.Position = UDim2.new(ax, 0, ay, 0)
	hSeg.Size = UDim2.fromOffset(16, 2)
	hSeg.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	hSeg.BorderSizePixel = 0
	hSeg.ZIndex = 9
	hSeg.Parent = sightBox
	local vSeg = Instance.new("Frame")
	vSeg.AnchorPoint = Vector2.new(ax, ay)
	vSeg.Position = UDim2.new(ax, 0, ay, 0)
	vSeg.Size = UDim2.fromOffset(2, 16)
	vSeg.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	vSeg.BorderSizePixel = 0
	vSeg.ZIndex = 9
	vSeg.Parent = sightBox
end
bracket("left", "top")
bracket("right", "top")
bracket("left", "bottom")
bracket("right", "bottom")

-- Center red dot
local redDot = Instance.new("Frame")
redDot.AnchorPoint = Vector2.new(0.5, 0.5)
redDot.Position = UDim2.new(0.5, 0, 0.5, 0)
redDot.Size = UDim2.fromOffset(5, 5)
redDot.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
redDot.BorderSizePixel = 0
redDot.ZIndex = 10
redDot.Parent = dotSightOverlay
local redDotCorner = Instance.new("UICorner")
redDotCorner.CornerRadius = UDim.new(1, 0)
redDotCorner.Parent = redDot

-- Recompute scope geometry based on current viewport so scope fills (almost)
-- full screen height. Called on init + whenever viewport size changes.
local function updateScopeLayout()
	local vp = camera.ViewportSize
	local diameter = math.min(vp.X, vp.Y) * 0.95 -- nearly full screen height
	local half = diameter / 2

	topMask.Size = UDim2.new(1, 0, 0.5, -half)
	topMask.Position = UDim2.new(0, 0, 0, 0)
	bottomMask.Size = UDim2.new(1, 0, 0.5, -half)
	bottomMask.Position = UDim2.new(0, 0, 1, 0)
	leftMask.Size = UDim2.new(0.5, -half, 0, diameter)
	leftMask.Position = UDim2.new(0, 0, 0.5, 0)
	rightMask.Size = UDim2.new(0.5, -half, 0, diameter)
	rightMask.Position = UDim2.new(1, 0, 0.5, 0)

	-- Corner bulges: circles CENTERED at each hole corner. Diameter = halfDiameter
	-- so the visible quarter (inside hole) is a quarter-disk that rounds each
	-- corner with radius = quarterDiameter. Hole becomes "rounded square" — much
	-- closer to circular than the previous square. The 3 quarters of each circle
	-- outside the hole are hidden under the rect masks.
	local bulgeSize = UDim2.fromOffset(half, half)
	cornerTL.Size = bulgeSize
	cornerTL.Position = UDim2.new(0.5, -half, 0.5, -half)
	cornerTR.Size = bulgeSize
	cornerTR.Position = UDim2.new(0.5, half, 0.5, -half)
	cornerBL.Size = bulgeSize
	cornerBL.Position = UDim2.new(0.5, -half, 0.5, half)
	cornerBR.Size = bulgeSize
	cornerBR.Position = UDim2.new(0.5, half, 0.5, half)

	ring.Size = UDim2.fromOffset(diameter - 4, diameter - 4)
	hLine.Size = UDim2.fromOffset(diameter, 1)
	vLine.Size = UDim2.fromOffset(1, diameter)

	for _, info in tickFrames do
		local offset = info.scale * half
		if info.vertical then
			info.frame.Size = UDim2.fromOffset(8, 2)
			info.frame.Position = UDim2.new(0.5, 0, 0.5, offset)
		else
			info.frame.Size = UDim2.fromOffset(2, 8)
			info.frame.Position = UDim2.new(0.5, offset, 0.5, 0)
		end
	end
end
updateScopeLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScopeLayout)

local crosshair = Instance.new("Frame")
crosshair.Name = "Crosshair"
crosshair.Size = UDim2.new(0, 40, 0, 40)
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshair.BackgroundTransparency = 1
crosshair.Visible = false
crosshair.Parent = screenGui

type LineInfo = { line: Frame, dir: Vector2 }
local crosshairLines: { LineInfo } = {}

local function makeCrosshairLine(dir: Vector2, isVertical: boolean)
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Size = if isVertical then UDim2.new(0, 2, 0, 6) else UDim2.new(0, 6, 0, 2)
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	line.BorderSizePixel = 0
	line.Parent = crosshair
	-- Outline (UIStroke) — same setup as the preview in SettingsController so
	-- the in-game crosshair matches the preview pixel-for-pixel when outline is on.
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Enabled = false
	stroke.Parent = line
	table.insert(crosshairLines, { line = line, dir = dir })
end

makeCrosshairLine(Vector2.new(0, -1), true)
makeCrosshairLine(Vector2.new(0, 1), true)
makeCrosshairLine(Vector2.new(-1, 0), false)
makeCrosshairLine(Vector2.new(1, 0), false)

-- Center dot (CS-style, toggleable)
local centerDot = Instance.new("Frame")
centerDot.Name = "CenterDot"
centerDot.Size = UDim2.new(0, 2, 0, 2)
centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
centerDot.Position = UDim2.new(0.5, 0, 0.5, 0)
centerDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
centerDot.BorderSizePixel = 0
centerDot.Parent = crosshair
local centerDotStroke = Instance.new("UIStroke")
centerDotStroke.Color = Color3.fromRGB(0, 0, 0)
centerDotStroke.Thickness = 1.5
centerDotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
centerDotStroke.LineJoinMode = Enum.LineJoinMode.Miter
centerDotStroke.Enabled = false
centerDotStroke.Parent = centerDot

-- Crosshair config (live-updated from SettingsController via ClientSignals)
local crosshairConfig = {
	length = 6,
	thickness = 2,
	offset = 7,
	dot = true,
	outline = false,
	color = Color3.fromRGB(255, 255, 255),
}

local function applyCrosshairConfig()
	local cfg = crosshairConfig
	-- Gap semantics (matches SettingsController preview): `offset` is the
	-- distance from screen center to the INNER edge of the line, so the line
	-- CENTER sits at (offset + length/2) from center.
	local centerDist = cfg.offset + cfg.length / 2
	for _, info in crosshairLines do
		local isVertical = info.dir.Y ~= 0
		if isVertical then
			info.line.Size = UDim2.new(0, cfg.thickness, 0, cfg.length)
		else
			info.line.Size = UDim2.new(0, cfg.length, 0, cfg.thickness)
		end
		info.line.Position = UDim2.new(0.5, info.dir.X * centerDist, 0.5, info.dir.Y * centerDist)
		info.line.BackgroundColor3 = cfg.color
		local stroke = info.line:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Enabled = cfg.outline end
	end
	centerDot.Visible = cfg.dot
	centerDot.Size = UDim2.new(0, cfg.thickness, 0, cfg.thickness)
	centerDot.BackgroundColor3 = cfg.color
	centerDotStroke.Enabled = cfg.outline
end

-- Public function so SettingsController can push new config
local function setCrosshairConfig(newCfg: any)
	crosshairConfig.length = newCfg.length or crosshairConfig.length
	crosshairConfig.thickness = newCfg.thickness or crosshairConfig.thickness
	crosshairConfig.offset = newCfg.offset or crosshairConfig.offset
	if newCfg.dot ~= nil then crosshairConfig.dot = newCfg.dot end
	if newCfg.outline ~= nil then crosshairConfig.outline = newCfg.outline end
	if newCfg.color then crosshairConfig.color = newCfg.color end
	applyCrosshairConfig()
end

-- Listen to settings broadcast (signal-based, fired from SettingsController)
ClientSignals.Get("CrosshairConfigChanged").Event:Connect(setCrosshairConfig)

-- Left-handed viewmodel toggle (broadcast from SettingsController). When true,
-- viewmodel + hands mirror to the left side of the screen for left-eye-dominant
-- players. Applied as the LAST transform on each part's cam-relative CFrame.
local leftHanded = false
ClientSignals.Get("LeftHandedChanged").Event:Connect(function(value: boolean)
	leftHanded = value == true
end)

-- ADS input mode (set by SettingsController; values: "hold" or "toggle").
ClientSignals.Get("AdsModeChanged").Event:Connect(function(mode: string)
	if mode == "hold" or mode == "toggle" then
		adsMode = mode
	end
end)

-- Mirror a cam-relative CFrame across the YZ plane: negate X position, negate
-- yaw (Y rotation) and roll (Z rotation), keep pitch (X). Not a true rigid
-- mirror (which would be improper), but visually correct for FPS viewmodels:
-- weapon flips to left side of screen and tilts the opposite way.
local function mirrorCamLocal(cf: CFrame): CFrame
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	return CFrame.new(-cf.X, cf.Y, cf.Z) * CFrame.fromEulerAnglesXYZ(rx, -ry, -rz)
end

local function updateCrosshairLines()
	-- Kept as no-op for backward compat (was called by old bloom code).
end

local hitmark = Instance.new("Frame")
hitmark.Name = "Hitmark"
hitmark.Size = UDim2.new(0, 30, 0, 30)
hitmark.AnchorPoint = Vector2.new(0.5, 0.5)
hitmark.Position = UDim2.new(0.5, 0, 0.5, 0)
hitmark.BackgroundTransparency = 1
hitmark.Visible = false
hitmark.Parent = screenGui

local hitmarkLines: { Frame } = {}
for _, rot in { 45, -45 } do
	local line = Instance.new("Frame")
	line.Size = UDim2.new(0, 16, 0, 2)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.new(0.5, 0, 0.5, 0)
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	line.BorderSizePixel = 0
	line.Rotation = rot
	line.Parent = hitmark
	table.insert(hitmarkLines, line)
end

local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Name = "DamageFeedback"
feedbackLabel.Size = UDim2.new(0, 240, 0, 28)
feedbackLabel.AnchorPoint = Vector2.new(0.5, 0)
feedbackLabel.Position = UDim2.new(0.5, 0, 0.5, 36)
feedbackLabel.BackgroundTransparency = 1
feedbackLabel.Font = Enum.Font.GothamBold
feedbackLabel.TextSize = 18
feedbackLabel.TextColor3 = Color3.fromRGB(255, 230, 90)
feedbackLabel.TextStrokeTransparency = 0.3
feedbackLabel.Text = ""
feedbackLabel.Parent = screenGui

-- Weapon slot HUD: shows current slot + both weapons
local slotPanel = Instance.new("Frame")
slotPanel.Size = UDim2.new(0, 280, 0, 64)
slotPanel.AnchorPoint = Vector2.new(1, 1)
slotPanel.Position = UDim2.new(1, -20, 1, -20)
slotPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
slotPanel.BackgroundTransparency = 0.25
slotPanel.BorderSizePixel = 0
slotPanel.Visible = false
slotPanel.Parent = screenGui

local slotCorner = Instance.new("UICorner")
slotCorner.CornerRadius = UDim.new(0, 10)
slotCorner.Parent = slotPanel

local function makeSlotChip(key: string, position: UDim2, accentColor: Color3): (TextButton, TextLabel, TextLabel)
	local chip = Instance.new("TextButton")
	chip.Size = UDim2.new(0, 130, 1, -16)
	chip.Position = position
	chip.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
	chip.BorderSizePixel = 0
	chip.AutoButtonColor = false
	chip.Text = ""
	chip.Parent = slotPanel

	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0, 6)
	chipCorner.Parent = chip

	local chipStroke = Instance.new("UIStroke")
	chipStroke.Color = accentColor
	chipStroke.Thickness = 1.5
	chipStroke.Transparency = 0.4
	chipStroke.Parent = chip

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Size = UDim2.new(0, 28, 0, 28)
	keyLabel.Position = UDim2.new(0, 8, 0.5, -14)
	keyLabel.BackgroundColor3 = accentColor
	keyLabel.BorderSizePixel = 0
	keyLabel.Font = Enum.Font.GothamBlack
	keyLabel.TextSize = 16
	keyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	keyLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	keyLabel.TextStrokeTransparency = 0.5
	keyLabel.Text = key
	keyLabel.Parent = chip
	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 4)
	keyCorner.Parent = keyLabel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -48, 1, 0)
	nameLabel.Position = UDim2.new(0, 42, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.fromRGB(220, 225, 240)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = "—"
	nameLabel.Parent = chip

	return chip, keyLabel, nameLabel
end

local primaryChip, _, primaryLabel = makeSlotChip("1", UDim2.new(0, 8, 0, 8), Color3.fromRGB(220, 100, 60))
local secondaryChip, _, secondaryLabel = makeSlotChip("2", UDim2.new(0, 142, 0, 8), Color3.fromRGB(60, 140, 220))

primaryChip.MouseButton1Click:Connect(function()
	Remotes.SwitchWeapon:FireServer("primary")
end)
secondaryChip.MouseButton1Click:Connect(function()
	Remotes.SwitchWeapon:FireServer("secondary")
end)

-- Ammo display (above slot panel).
-- Default position sits 20px from right, 92px from bottom. On mobile the
-- bottom-right FIRE button (100x100, anchored bottom-right at offset -100,-180)
-- collides with this ammo panel's right edge (the FIRE button covers x: -100..0
-- from right; the ammo panel covers x: -200..-20). User report: "FIRE button
-- overlaps ammo counter on narrow screens" — fix by shifting ammo LEFT past the
-- FIRE button's width on touch devices (see mobile-detection block below).
local ammoPanel = Instance.new("Frame")
ammoPanel.Size = UDim2.new(0, 130, 0, 40)
ammoPanel.AnchorPoint = Vector2.new(1, 1)
ammoPanel.Position = UDim2.new(1, -20, 1, -76)
ammoPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
ammoPanel.BackgroundTransparency = 0.25
ammoPanel.BorderSizePixel = 0
ammoPanel.Visible = false
ammoPanel.Parent = screenGui

-- Mobile: stack ammo ABOVE FIRE button (right-bottom column). FIRE is 72x72
-- anchored at (1, -88, 1, -130). Ammo sits 8px above FIRE top with same right
-- anchor so the vertical stack reads as one cluster.
do
	local _uis = UserInputService
	local isMobileDevice = _uis.TouchEnabled and not _uis.MouseEnabled
	if isMobileDevice then
		ammoPanel.Position = UDim2.new(1, -88, 1, -210)
	end
end

local ammoCorner = Instance.new("UICorner")
ammoCorner.CornerRadius = UDim.new(0, 10)
ammoCorner.Parent = ammoPanel

local ammoNumber = Instance.new("TextLabel")
ammoNumber.Size = UDim2.new(0.55, 0, 1, 0)
ammoNumber.Position = UDim2.new(0, 0, 0, 0)
ammoNumber.BackgroundTransparency = 1
ammoNumber.Font = Enum.Font.GothamBlack
ammoNumber.TextSize = 22
ammoNumber.TextColor3 = Color3.fromRGB(255, 255, 255)
ammoNumber.TextXAlignment = Enum.TextXAlignment.Right
ammoNumber.Text = "0"
ammoNumber.Parent = ammoPanel

local ammoMag = Instance.new("TextLabel")
ammoMag.Size = UDim2.new(0.4, -10, 1, 0)
ammoMag.Position = UDim2.new(0.55, 4, 0, 0)
ammoMag.BackgroundTransparency = 1
ammoMag.Font = Enum.Font.GothamMedium
ammoMag.TextSize = 13
ammoMag.TextColor3 = Color3.fromRGB(170, 175, 195)
ammoMag.TextXAlignment = Enum.TextXAlignment.Left
ammoMag.TextYAlignment = Enum.TextYAlignment.Bottom
ammoMag.Text = "/ 0"
ammoMag.Parent = ammoPanel

local reloadingLabel = Instance.new("TextLabel")
reloadingLabel.Size = UDim2.new(1, 0, 0, 16)
reloadingLabel.AnchorPoint = Vector2.new(0.5, 0)
reloadingLabel.Position = UDim2.new(0.5, 0, 0, 4)
reloadingLabel.BackgroundTransparency = 1
reloadingLabel.Font = Enum.Font.GothamBold
reloadingLabel.TextSize = 11
reloadingLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
reloadingLabel.Text = ""
reloadingLabel.Parent = ammoPanel

local function updateAmmoPanel()
	if not equippedId then
		ammoPanel.Visible = false
		return
	end
	local weapon = WeaponConfig[equippedId]
	-- Hide ammo panel for melee (knife has no ammo)
	if weapon and weapon.slot == "melee" then
		ammoPanel.Visible = false
		return
	end
	ammoPanel.Visible = true
	ammoNumber.Text = tostring(currentAmmo)
	ammoMag.Text = "/ " .. tostring(currentMagSize)
	if isReloading then
		reloadingLabel.Text = "RELOADING..."
		ammoNumber.TextColor3 = Color3.fromRGB(255, 200, 80)
	elseif currentAmmo == 0 then
		reloadingLabel.Text = "PRESS R"
		ammoNumber.TextColor3 = Color3.fromRGB(255, 90, 90)
	elseif currentAmmo / math.max(1, currentMagSize) <= 0.25 then
		reloadingLabel.Text = ""
		ammoNumber.TextColor3 = Color3.fromRGB(255, 180, 80)
	else
		reloadingLabel.Text = ""
		ammoNumber.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

local function updateSlotPanel()
	local primaryName = "—"
	local secondaryName = "—"
	if equippedSlotName == "primary" and equippedId and WeaponConfig[equippedId] then
		primaryName = WeaponConfig[equippedId].displayName
	end
	if equippedSlotName == "secondary" and equippedId and WeaponConfig[equippedId] then
		secondaryName = WeaponConfig[equippedId].displayName
	end
	-- Fallback: show defaults if no equip yet for that slot
	if primaryName == "—" and WeaponConfig.rifle then primaryName = WeaponConfig.rifle.displayName end
	if secondaryName == "—" and WeaponConfig.pistol then secondaryName = WeaponConfig.pistol.displayName end

	primaryLabel.Text = primaryName
	secondaryLabel.Text = secondaryName

	local activePrimary = equippedSlotName == "primary"
	local activeSecondary = equippedSlotName == "secondary"
	-- Brighten active slot
	primaryChip.BackgroundColor3 = activePrimary and Color3.fromRGB(75, 50, 35) or Color3.fromRGB(28, 32, 44)
	secondaryChip.BackgroundColor3 = activeSecondary and Color3.fromRGB(35, 55, 80) or Color3.fromRGB(28, 32, 44)
	local pStroke = primaryChip:FindFirstChildOfClass("UIStroke")
	if pStroke then
		pStroke.Transparency = activePrimary and 0 or 0.4
		pStroke.Thickness = activePrimary and 2.5 or 1.5
	end
	local sStroke = secondaryChip:FindFirstChildOfClass("UIStroke")
	if sStroke then
		sStroke.Transparency = activeSecondary and 0 or 0.4
		sStroke.Thickness = activeSecondary and 2.5 or 1.5
	end
	slotPanel.Visible = equippedSlotName ~= nil
end

-- ============ Viewmodel ============

local function ensureFolder(): Folder
	if viewmodelFolder and viewmodelFolder.Parent then
		return viewmodelFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "LocalViewmodel"
	folder.Parent = Workspace
	viewmodelFolder = folder
	return folder
end

local function clearViewmodel()
	for _, info in viewmodelParts do
		info.part:Destroy()
	end
	table.clear(viewmodelParts)
end

-- Apply a multi-tone skin palette. Looks up override color per part role.
-- Pass nil = reset to original config colors.
local currentSkin: any? = nil
local function applySkin(skin: any?)
	currentSkin = skin
	currentSkinColor = skin and skin.color or nil
	for _, info in viewmodelParts do
		local role = info.config.role
		local overrideColor: Color3? = nil
		if skin then
			if role == "body" then
				overrideColor = skin.color
			elseif role == "slide" and skin.slideColor then
				overrideColor = skin.slideColor
			elseif role == "grip" and skin.gripColor then
				overrideColor = skin.gripColor
			elseif role == "stock" and skin.stockColor then
				overrideColor = skin.stockColor
			elseif role == "barrel" and skin.barrelColor then
				overrideColor = skin.barrelColor
			elseif role == "sight" and skin.accentColor then
				-- accent applies to sights for highlight color
				overrideColor = skin.accentColor
			end
		end
		-- Star dots: visible only when skin has accentColor, colored via accent
		if role == "stardot" then
			if skin and skin.accentColor then
				info.part.Color = skin.accentColor
				info.part.Transparency = 0
			else
				info.part.Transparency = 1 -- hide for skins without accent
			end
		else
			info.part.Color = overrideColor or info.config.color
		end
	end
end

local function buildViewmodel(weapon: WeaponConfig.WeaponInfo, partsOverride: any?)
	clearViewmodel()
	local folder = ensureFolder()
	local parts = partsOverride or weapon.viewmodel.parts
	for _, partConfig in parts do
		local shape = (partConfig :: any).shape
		local part: BasePart
		if shape == "wedge" then
			part = Instance.new("WedgePart")
		else
			local p = Instance.new("Part")
			if shape == "cylinder" then
				p.Shape = Enum.PartType.Cylinder
			elseif shape == "ball" then
				p.Shape = Enum.PartType.Ball
			end
			part = p
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Size = partConfig.size
		part.Color = partConfig.color
		part.Material = partConfig.material
		part.Name = partConfig.role
		part.Parent = folder
		table.insert(viewmodelParts, {
			part = part,
			config = partConfig,
			baseColor = partConfig.color,
		})
	end
	applySkin(currentSkin)
end

-- CS2-style cocking animation:
-- 0.00-0.20: gun rises from below into ready pose
-- 0.20-0.35: gun TILTS LEFT (camera sees right side, exposing charging handle)
-- 0.35-0.55: charging handle PULLED BACK (positive Z = toward shooter)
-- 0.55-0.65: held back briefly (hand pause at rear)
-- 0.65-0.78: handle SLAPPED forward (snaps fast) — this is when cocking sound plays
-- 0.78-1.00: gun returns to neutral aim pose
local function getAnimOffsets(progress: number): (CFrame, CFrame)
	-- Gun rising from below (first 20%)
	local drawY = 0
	if progress < 0.2 then
		drawY = -1.4 * (1 - progress / 0.2)
	end

	-- Gun roll (tilt left so right-side charging handle is visible)
	local rollAngle = 0
	if progress >= 0.2 and progress < 0.78 then
		local t = math.min(1, (progress - 0.2) / 0.15) -- ramp up to full tilt
		local fade = math.max(0, 1 - (progress - 0.65) / 0.13) -- fade out toward end
		rollAngle = math.rad(-22) * math.min(t, fade)
	end

	-- Gun yaw (subtle inward turn so charging handle faces camera better)
	local yawAngle = 0
	if progress >= 0.2 and progress < 0.78 then
		local t = math.min(1, (progress - 0.2) / 0.15)
		local fade = math.max(0, 1 - (progress - 0.65) / 0.13)
		yawAngle = math.rad(8) * math.min(t, fade)
	end

	-- Slide / charging handle motion (POSITIVE Z = toward shooter, real cocking direction)
	local slideZ = 0
	if progress >= 0.35 and progress < 0.55 then
		local t = (progress - 0.35) / 0.20
		slideZ = t * 0.45 -- pulls back smooth
	elseif progress >= 0.55 and progress < 0.65 then
		slideZ = 0.45 -- held back at rear
	elseif progress >= 0.65 and progress < 0.78 then
		local t = (progress - 0.65) / 0.13
		-- Fast slap forward with slight overshoot
		slideZ = 0.45 * (1 - t * 1.05)
	end

	-- Tilt forward when raising (initial draw)
	local drawTilt = math.rad(-18) * math.max(0, 1 - progress / 0.25)

	-- Hand thump shake when slide slaps forward (~0.70)
	local thumpY = 0
	if progress >= 0.68 and progress < 0.76 then
		local intensity = 1 - math.abs((progress - 0.72) / 0.04)
		thumpY = -0.06 * intensity
	end

	local drawCF = CFrame.new(0, drawY + thumpY, 0) * CFrame.Angles(drawTilt, yawAngle, rollAngle)
	local slideCF = CFrame.new(0, 0, slideZ)
	return drawCF, slideCF
end

-- Detailed AK-style reload:
-- 0.00-0.10: press mag release (small jerk down)
-- 0.10-0.25: mag rocks FORWARD out of well + drops down
-- 0.25-0.45: empty well (hand offscreen retrieving new mag)
-- 0.45-0.65: new mag rocks INTO well (tip first, then rock back)
-- 0.65-0.78: short pause (mag seated)
-- 0.78-0.88: charging handle pulled BACK (visible slide motion)
-- 0.88-0.95: handle released (slide snaps forward)
-- 0.95-1.00: settle to rest
local function getReloadOffsets(progress: number): (CFrame, CFrame, CFrame, CFrame)
	-- Mag translation Y (drop then return)
	local magY = 0
	if progress < 0.10 then
		magY = -(progress / 0.10) * 0.04 -- tiny jerk on release press
	elseif progress < 0.25 then
		local t = (progress - 0.10) / 0.15
		magY = -0.04 - t * 0.5 -- drops out
	elseif progress < 0.45 then
		magY = -0.6 -- mag gone, well empty
	elseif progress < 0.65 then
		local t = (progress - 0.45) / 0.20
		magY = -0.6 + t * 0.6 -- new mag rises into place
	end

	-- Mag rocking rotation (AK-style rock forward to release/insert)
	local magRotX = 0
	if progress < 0.10 then
		magRotX = -math.rad(2) * (progress / 0.10) -- slight pre-tilt
	elseif progress < 0.25 then
		local t = (progress - 0.10) / 0.15
		magRotX = math.rad(-2 - t * 28) -- rock forward (tip out the back)
	elseif progress < 0.45 then
		magRotX = math.rad(-30) -- mag dropped, no longer attached
	elseif progress < 0.65 then
		local t = (progress - 0.45) / 0.20
		magRotX = math.rad(-30 + t * 30) -- rock back to upright as new mag seats
	end

	-- Slide / charging handle motion (bigger pull for AK feel)
	local slideZ = 0
	if progress >= 0.78 and progress < 0.88 then
		local t = (progress - 0.78) / 0.10
		slideZ = -t * 0.40 -- handle pulls back
	elseif progress >= 0.88 and progress < 0.95 then
		local t = (progress - 0.88) / 0.07
		slideZ = -0.40 * (1 - t) -- snaps forward
	end

	-- Grip motion (gun tilts during reload)
	local easeBell = math.sin(math.clamp(progress, 0, 1) * math.pi)
	local gripCF = CFrame.new(0, -0.2 * easeBell, 0) * CFrame.Angles(math.rad(14) * easeBell, math.rad(-3) * easeBell, math.rad(2) * easeBell)
	local magCF = CFrame.new(0, magY, 0) * CFrame.Angles(magRotX, 0, 0)
	local slideCF = CFrame.new(0, 0, slideZ)
	-- New: return an extra "hand thump" CFrame for charging handle slap effect (subtle shake at 0.88)
	local thumpJitter = CFrame.new()
	if progress >= 0.86 and progress < 0.92 then
		local intensity = 1 - math.abs((progress - 0.89) / 0.03)
		thumpJitter = CFrame.new(0, -0.04 * intensity, 0)
	end
	return gripCF, magCF, slideCF, thumpJitter
end

local function muzzleWorldPosition(): Vector3?
	if not equippedId then
		return nil
	end
	local weapon = WeaponConfig[equippedId]
	if not weapon then
		return nil
	end
	local barrelEntry
	for _, info in viewmodelParts do
		if info.config.role == "barrel" then
			barrelEntry = info
			break
		end
	end
	if not barrelEntry then
		return nil
	end
	return (barrelEntry.part.CFrame * CFrame.new(0, 0, -barrelEntry.part.Size.Z / 2)).Position
end

local function spawnMuzzleFlash()
	local pos = muzzleWorldPosition()
	if not pos then
		return
	end
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 220, 140)
	flash.Transparency = 0.1
	flash.Size = Vector3.new(0.35, 0.35, 0.35)
	flash.Position = pos
	flash.Parent = ensureFolder()
	Debris:AddItem(flash, 0.05)
end

local function showHitmark(isHeadshot: boolean, killed: boolean)
	local color
	if killed then
		color = Color3.fromRGB(255, 80, 80)
	elseif isHeadshot then
		color = Color3.fromRGB(255, 170, 80)
	else
		color = Color3.fromRGB(255, 255, 255)
	end
	for _, line in hitmarkLines do
		line.BackgroundColor3 = color
	end
	hitmark.Visible = true
	task.delay(killed and 0.4 or 0.18, function()
		hitmark.Visible = false
	end)
end

local feedbackToken = 0
local function showDamageFeedback(damage: number, killed: boolean, isHeadshot: boolean)
	feedbackToken += 1
	local myToken = feedbackToken
	if killed then
		feedbackLabel.Text = "ELIMINATED"
		feedbackLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	else
		local prefix = isHeadshot and "HEADSHOT  -" or "-"
		feedbackLabel.Text = string.format("%s%d", prefix, math.floor(damage))
		feedbackLabel.TextColor3 = isHeadshot and Color3.fromRGB(255, 170, 80) or Color3.fromRGB(255, 230, 90)
	end
	task.delay(0.8, function()
		if feedbackToken == myToken then
			feedbackLabel.Text = ""
		end
	end)
end

local function drawTracer(startPos: Vector3, hitPos: Vector3)
	local distance = (hitPos - startPos).Magnitude
	if distance < 0.5 then
		return
	end
	-- Main beam — bright neon line that lingers ~0.18s so the player can clearly
	-- see the trajectory and direction of fire.
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 215, 110)
	tracer.Transparency = 0.05
	tracer.Size = Vector3.new(0.18, 0.18, distance)
	tracer.CFrame = CFrame.lookAt((startPos + hitPos) / 2, hitPos)
	tracer.Parent = ensureFolder()
	-- Tween out so the line fades instead of popping
	game:GetService("TweenService"):Create(tracer, TweenInfo.new(0.18), {
		Transparency = 1,
		Size = Vector3.new(0.04, 0.04, distance),
	}):Play()
	Debris:AddItem(tracer, 0.22)

	-- Bullet head — a tiny bright ball that travels from muzzle to hit point so
	-- there's a clear "this is the bullet, this is the direction" cue.
	local bullet = Instance.new("Part")
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CanQuery = false
	bullet.CastShadow = false
	bullet.Material = Enum.Material.Neon
	bullet.Color = Color3.fromRGB(255, 240, 180)
	bullet.Shape = Enum.PartType.Ball
	bullet.Size = Vector3.new(0.35, 0.35, 0.35)
	bullet.Position = startPos
	bullet.Parent = ensureFolder()
	local travelTime = math.clamp(distance / 800, 0.02, 0.12)
	game:GetService("TweenService"):Create(bullet, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
		Position = hitPos,
	}):Play()
	Debris:AddItem(bullet, travelTime + 0.02)
end

local function spawnBroadcastMuzzleFlash(position: Vector3)
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 230, 150)
	flash.Transparency = 0.1
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.55, 0.55, 0.55)
	flash.Position = position
	flash.Parent = ensureFolder()

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 100)
	light.Range = 8
	light.Brightness = 3
	light.Parent = flash

	Debris:AddItem(flash, 0.07)
end

local function spawnBulletImpact(position: Vector3, normal: Vector3, material: string, isPlayer: boolean)
	local attachment = Instance.new("Attachment")
	attachment.WorldCFrame = CFrame.lookAt(position, position + normal)

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Position = position
	anchor.Parent = ensureFolder()
	attachment.Parent = anchor

	local color: Color3
	local lifetime = NumberRange.new(0.18, 0.4)
	local rate = 60
	if isPlayer then
		color = Color3.fromRGB(180, 30, 30)
	elseif material == "Wood" or material == "WoodPlanks" then
		color = Color3.fromRGB(150, 110, 70)
	elseif material == "Sand" or material == "Ground" then
		color = Color3.fromRGB(200, 180, 130)
	elseif material == "Brick" or material == "Concrete" or material == "Slate" then
		color = Color3.fromRGB(190, 190, 200)
	elseif material == "Metal" or material == "DiamondPlate" or material == "CorrodedMetal" then
		color = Color3.fromRGB(255, 220, 130)
		rate = 90
	else
		color = Color3.fromRGB(200, 200, 210)
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Lifetime = lifetime
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(8, 18)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Drag = 4
	emitter.Parent = attachment
	emitter:Emit(rate)

	-- Quick flash decal-ish: tiny neon ball for half-frame
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Material = Enum.Material.Neon
	flash.Shape = Enum.PartType.Ball
	flash.Color = color
	flash.Transparency = 0.2
	flash.Size = Vector3.new(0.3, 0.3, 0.3)
	flash.Position = position
	flash.Parent = ensureFolder()
	Debris:AddItem(flash, 0.05)
	Debris:AddItem(anchor, 0.5)
end

local function findRemoteShooterMuzzle(shooterUserId: number?): Vector3?
	-- Bots fire ShotFired with shooterUserId=nil; skip the player lookup
	-- entirely (Players:GetPlayerByUserId(nil) errors with "Argument 1
	-- missing or nil"). Caller falls back to info.origin on nil return.
	if typeof(shooterUserId) ~= "number" then
		return nil
	end
	local shooter = Players:GetPlayerByUserId(shooterUserId)
	if not shooter then
		return nil
	end
	local character = shooter.Character
	if not character then
		return nil
	end
	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand.Position + rightHand.CFrame.LookVector * 1.2
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position + root.CFrame.LookVector * 2
	end
	return nil
end

local function isReady(): boolean
	if not equippedId then
		return false
	end
	if isReloading then
		return false
	end
	local weapon = WeaponConfig[equippedId]
	if not weapon then
		return false
	end
	return os.clock() - drawStartTime >= weapon.drawTime
end

local function tryReload()
	if not equippedId or isReloading then
		return
	end
	if currentAmmo >= currentMagSize then
		return
	end
	Remotes.RequestReload:FireServer()
end

local function tryFire()
	if cursorModeActive then
		return
	end
	if not isReady() then
		return
	end
	local weapon = WeaponConfig[equippedId :: string]
	if not weapon then
		return
	end
	-- Melee weapons skip ammo check (knife has no ammo)
	if weapon.slot ~= "melee" and currentAmmo <= 0 then
		tryReload()
		return
	end

	local now = os.clock()
	local interval = 1 / weapon.fireRate
	if now - lastFireAt < interval then
		return
	end
	lastFireAt = now

	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	-- Use CAMERA position as origin so bullet aligns exactly with crosshair center.
	-- (HRP is at body center, slightly below eyes → would shoot low.)
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector

	-- State-based bloom multiplier (multiplied into per-weapon spread + recoil).
	-- ADS = very accurate, walk = baseline, sprint = wide spray.
	local bloomMul: number
	if isAds then
		bloomMul = GameConfig.BloomMulADS
	elseif isSprinting then
		bloomMul = GameConfig.BloomMulSprint
	else
		bloomMul = GameConfig.BloomMulWalk
	end

	-- Per-shot spread cone — ALL guns get cone deviation scaled by bloomMul.
	-- AWP hipfire still has its own large baseline spread (CS-style sniper feel).
	if weapon.slot ~= "melee" then
		local baseSpreadDeg = if weapon.id == "sniper" and not isAds then 8
			elseif weapon.id == "sniper" then 0.1
			elseif weapon.id == "pistol" then 1.0
			elseif weapon.id == "smg" then 1.2
			else 0.9 -- rifle / fallback
		local SPREAD = math.rad(baseSpreadDeg) * bloomMul
		local randPitch = (math.random() * 2 - 1) * SPREAD
		local randYaw = (math.random() * 2 - 1) * SPREAD
		direction = (camera.CFrame * CFrame.Angles(randPitch, randYaw, 0)).LookVector
	end

	Remotes.FireRequest:FireServer(origin, direction, pendingStab)
	pendingStab = false
	-- No muzzle flash + no swing sound for melee (knife is silent).
	if weapon.slot ~= "melee" then
		spawnMuzzleFlash()
	end
	crosshairBloom = math.min(crosshairBloom + weapon.recoilVertical * 6 * bloomMul, 30)

	-- Camera recoil kick: spring-based velocity (camera tilts up + sways)
	local kickPitch = math.rad(weapon.recoilVertical * 0.9 * bloomMul)
	local kickYaw = math.rad((math.random() * 2 - 1) * weapon.recoilHorizontal * 0.6 * bloomMul)
	recoilPitchVel += kickPitch * 10
	recoilYawVel += kickYaw * 10

	-- AWP: auto-close scope after shot (bolt cycle locks out fire+scope for 0.5s via fireRate)
	if weapon.id == "sniper" and isAds then
		setAds(false)
	end
end

-- Mobile fire & reload buttons (only visible if touch enabled)
local isTouch = UserInputService.TouchEnabled
local hasKeyboard = UserInputService.KeyboardEnabled
local isMobile = isTouch and not hasKeyboard

local fireButton: TextButton? = nil
local reloadButton: TextButton? = nil

-- HUD edit mode (mobile only). When true, each registered mobile button can
-- be dragged to reposition. Toggle via ClientSignals "ToggleHudEdit" fired
-- from SettingsController. Positions saved to PlayerData (hudFireX/Y, etc).
local hudEditMode = false
local hudButtons: { { btn: GuiObject, settingKey: string, originalColor: Color3 } } = {}
local hudPositions: { [string]: { x: number, y: number } } = {}

ClientSignals.Get("ToggleHudEdit").Event:Connect(function(value: boolean)
	hudEditMode = value == true
	for _, entry in hudButtons do
		if hudEditMode then
			entry.btn.BackgroundColor3 = Color3.fromRGB(255, 220, 80) -- yellow = edit mode
		else
			entry.btn.BackgroundColor3 = entry.originalColor
		end
	end
end)

-- Register a mobile HUD button for drag-to-reposition in edit mode.
-- `defaultPos` = the button's hardcoded default UDim2 (so we can re-derive
-- the saved offset = current - default after each drag).
local function registerHudButton(btn: GuiObject, settingKey: string, defaultPos: UDim2)
	table.insert(hudButtons, { btn = btn, settingKey = settingKey, originalColor = btn.BackgroundColor3 })
	-- Apply saved offset (additive on top of default position)
	local saved = hudPositions[settingKey]
	if saved and (saved.x ~= 0 or saved.y ~= 0) then
		btn.Position = UDim2.new(defaultPos.X.Scale, defaultPos.X.Offset + saved.x,
		                          defaultPos.Y.Scale, defaultPos.Y.Offset + saved.y)
	end
	local dragTouch: InputObject? = nil
	local startTouchPos: Vector2? = nil
	local startBtnAbsPos: Vector2? = nil
	btn.InputBegan:Connect(function(input: InputObject)
		if not hudEditMode then return end
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragTouch = input
			startTouchPos = Vector2.new(input.Position.X, input.Position.Y)
			startBtnAbsPos = btn.AbsolutePosition
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input ~= dragTouch then return end
		if not startTouchPos or not startBtnAbsPos then return end
		local dx = input.Position.X - startTouchPos.X
		local dy = input.Position.Y - startTouchPos.Y
		-- New absolute target position = original abs + delta
		local newAbs = (startBtnAbsPos :: Vector2) + Vector2.new(dx, dy)
		-- Convert back to offset relative to anchor. Anchor uses btn.AnchorPoint.
		-- For our buttons all use either AnchorPoint (0,0), (1,0), (0,1), (1,1) etc.
		-- Easier: compute as Scale=0 with absolute pixel offset.
		btn.AnchorPoint = Vector2.new(0, 0)
		btn.Position = UDim2.new(0, newAbs.X, 0, newAbs.Y)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input ~= dragTouch then return end
		dragTouch = nil
		startTouchPos = nil
		-- Save delta (current AbsolutePosition - original default AbsolutePosition)
		-- We approximate by storing the new offset relative to the default.
		local viewport = camera.ViewportSize
		local defaultAbsX = defaultPos.X.Scale * viewport.X + defaultPos.X.Offset
		local defaultAbsY = defaultPos.Y.Scale * viewport.Y + defaultPos.Y.Offset
		local newAbsX = btn.AbsolutePosition.X
		local newAbsY = btn.AbsolutePosition.Y
		local deltaX = math.floor(newAbsX - defaultAbsX)
		local deltaY = math.floor(newAbsY - defaultAbsY)
		hudPositions[settingKey] = { x = deltaX, y = deltaY }
		Remotes.UpdateSetting:FireServer(settingKey .. "X", deltaX)
		Remotes.UpdateSetting:FireServer(settingKey .. "Y", deltaY)
	end)
end

-- Listen for PlayerDataChanged to sync saved HUD positions
Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	if not data or not data.settings then return end
	local s = data.settings
	local keys = { "hudFire", "hudAds", "hudReload", "hudSwap", "hudSprint" }
	for _, k in keys do
		hudPositions[k] = { x = s[k .. "X"] or 0, y = s[k .. "Y"] or 0 }
	end
end)

-- Mobile HUD: visible FIRE button (PUBG-style) + compact button cluster.
-- FIRE = a transparent-bg Frame (Active=false → does NOT consume the touch).
-- Touching it starts firing; the SAME touch is also processed by Roblox's
-- default camera-rotate handler, so dragging your thumb on the FIRE button
-- rotates the camera (aim while firing). Touching anywhere ELSE on screen
-- only rotates the camera (no auto-fire) — fixing the prior bug where any
-- right-side touch fired the gun.

local function setAds(value: boolean)
	if isAds == value then
		return
	end
	if value and not equippedId then
		return
	end
	if value and cursorModeActive then
		return
	end
	-- All guns can ADS; knife can't (right-click on knife = stab).
	if value then
		local weapon = WeaponConfig[equippedId :: string]
		if not weapon or weapon.slot == "melee" then
			return
		end
		-- Block scope during AWP bolt cycle (0.5s after last shot)
		if weapon.id == "sniper" and os.clock() - lastFireAt < 0.5 then
			return
		end
	end
	isAds = value
	-- Sniper gets the big AWP scope; all other guns get the COD-style red-dot.
	local weapon = equippedId and WeaponConfig[equippedId]
	local isSniper = value and weapon ~= nil and weapon.id == "sniper"
	scopeOverlay.Visible = isSniper
	dotSightOverlay.Visible = value and weapon ~= nil and weapon.slot ~= "melee" and not isSniper
	-- Broadcast to MovementController so it can slow walk speed while scoping.
	ClientSignals.Get("AdsChanged"):Fire(value)
end

local mouseHeld = false

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and not isMobile then
		mouseHeld = true
		-- Knife slash animation trigger: only if draw complete, previous swing finished,
		-- AND stab animation NOT currently playing (prevents animation overlap).
		if equippedId == "knife" and isReady() then
			local now = os.clock()
			local stabActive = (now - knifeStabStart) < KNIFE_STAB_DURATION
			if now - knifeSwingStart >= KNIFE_SWING_DURATION and not stabActive then
				knifeSwingStart = now
				knifeSwingDir = -knifeSwingDir
				tryFire()
			end
		else
			tryFire()
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not isMobile then
		-- Knife right-click = forward stab. Gun right-click = scope (mode per setting).
		if equippedId == "knife" and isReady() then
			local now = os.clock()
			local slashActive = (now - knifeSwingStart) < KNIFE_SWING_DURATION
			if now - lastKnifeStabAt >= KNIFE_STAB_COOLDOWN and not slashActive then
				lastKnifeStabAt = now
				knifeStabStart = now
				pendingStab = true
				tryFire()
			end
		elseif equippedId ~= "knife" then
			if adsMode == "hold" then
				setAds(true)
			else
				setAds(not isAds) -- toggle mode: click = flip state
			end
		end
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		-- Sprint. AWP can't sprint (heavy sniper feel). Sprint also auto-cancels ADS.
		if equippedId == "sniper" then return end
		isSprinting = true
		if isAds then setAds(false) end
		ClientSignals.Get("SprintChanged"):Fire(true)
	elseif input.KeyCode == Enum.KeyCode.One then
		Remotes.SwitchWeapon:FireServer("primary")
	elseif input.KeyCode == Enum.KeyCode.Two then
		Remotes.SwitchWeapon:FireServer("secondary")
	elseif input.KeyCode == Enum.KeyCode.Three then
		Remotes.SwitchWeapon:FireServer("melee")
	elseif input.KeyCode == Enum.KeyCode.R then
		tryReload()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		-- Hold mode: release MB2 exits scope. Toggle mode: release does nothing.
		if adsMode == "hold" and isAds then
			setAds(false)
		end
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		if isSprinting then
			isSprinting = false
			ClientSignals.Get("SprintChanged"):Fire(false)
		end
	end
end)

-- Full-auto loop: while mouse held + equipped + weapon.isAuto, keep firing.
-- tryFire has its own rate limit (lastFireAt + interval), so polling is fine.
task.spawn(function()
	while true do
		if mouseHeld and not isMobile and equippedId then
			local weapon = WeaponConfig[equippedId]
			if weapon and weapon.isAuto then
				tryFire()
			end
		end
		task.wait(0.03)
	end
end)

-- ============================================================
-- MOBILE HUD (REDESIGNED): minimal pro look + drag-fire
-- Layout:
--   Right HALF of screen: invisible fire-zone (touch + drag = fire + aim)
--   Right-EDGE cluster (vertical column): ADS, RELOAD, SWITCH (3 small dark
--     buttons in corner, low visual noise)
--   Bottom-LEFT corner (just above joystick): SPRINT toggle
-- Defaults (joystick + jump): handled by Roblox engine on touch devices.
-- ============================================================
if isTouch then
	-- ===== VISIBLE FIRE BUTTON (PUBG-style: tap + drag = fire + aim) =====
	-- Frame (NOT TextButton) with Active=false → touch is NOT consumed, so
	-- Roblox's default camera-rotate also receives it. Result: tapping fires,
	-- dragging from the button rotates the camera (aim while firing).
	-- Touching anywhere else on screen → camera rotate only, NO auto-fire.
	-- Compact mobile HUD (per user feedback "perkecil semua"):
	--   FIRE 72×72 anchored bottom-right at (1, -88, 1, -130) — sits ABOVE
	--   the default Roblox jump button (~80px corner reservation) and to the
	--   LEFT of the right-edge ADS/RELOAD/SWAP column.
	local fireDefaultPos = UDim2.new(1, -88, 1, -130)
	local fireBtn = Instance.new("Frame")
	fireBtn.Name = "MobileFireBtn"
	fireBtn.AnchorPoint = Vector2.new(1, 1)
	fireBtn.Position = fireDefaultPos
	fireBtn.Size = UDim2.new(0, 72, 0, 72)
	fireBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	fireBtn.BackgroundTransparency = 0.35
	fireBtn.BorderSizePixel = 0
	fireBtn.Active = false -- crucial: lets the touch also drive camera rotation
	fireBtn.Parent = screenGui
	local fireBtnCorner = Instance.new("UICorner"); fireBtnCorner.CornerRadius = UDim.new(1, 0); fireBtnCorner.Parent = fireBtn
	local fireBtnStroke = Instance.new("UIStroke"); fireBtnStroke.Color = Color3.fromRGB(255, 255, 255); fireBtnStroke.Thickness = 2; fireBtnStroke.Transparency = 0.4; fireBtnStroke.Parent = fireBtn
	local fireBtnLbl = Instance.new("TextLabel")
	fireBtnLbl.Size = UDim2.new(1, 0, 1, 0)
	fireBtnLbl.BackgroundTransparency = 1
	fireBtnLbl.Font = Enum.Font.GothamBold
	fireBtnLbl.TextSize = 12
	fireBtnLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	fireBtnLbl.Text = "FIRE"
	fireBtnLbl.Parent = fireBtn

	local fireTouch: InputObject? = nil
	UserInputService.TouchStarted:Connect(function(input: InputObject, processed: boolean)
		if processed then return end
		-- Hit-test against fire button's screen rect. Using AbsolutePosition/Size
		-- so the test stays correct across viewport changes.
		local btnPos = fireBtn.AbsolutePosition
		local btnSize = fireBtn.AbsoluteSize
		local p = input.Position
		if p.X >= btnPos.X and p.X <= btnPos.X + btnSize.X
			and p.Y >= btnPos.Y and p.Y <= btnPos.Y + btnSize.Y then
			fireTouch = input
			task.spawn(function()
				while fireTouch == input do
					tryFire()
					task.wait(0.05)
				end
			end)
		end
	end)
	UserInputService.TouchEnded:Connect(function(input: InputObject)
		if input == fireTouch then fireTouch = nil end
	end)

	registerHudButton(fireBtn, "hudFire", fireDefaultPos)

	-- ===== RIGHT-EDGE BUTTON COLUMN (compact) =====
	-- 3 small dark buttons (44×44 each), 8px gaps, stacked at right edge
	-- centered vertically. To the right of FIRE; doesn't overlap FIRE
	-- because FIRE x ends at -88 and column x starts at -56.
	local btnCol = Instance.new("Frame")
	btnCol.Name = "MobileBtnCol"
	btnCol.AnchorPoint = Vector2.new(1, 0.5)
	btnCol.Position = UDim2.new(1, -12, 0.5, 0)
	btnCol.Size = UDim2.new(0, 44, 0, 148) -- 3×44 + 2×8 = 148
	btnCol.BackgroundTransparency = 1
	btnCol.Parent = screenGui

	local function styleBtn(b: TextButton)
		b.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
		b.BackgroundTransparency = 0.25
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold
		b.TextSize = 10
		b.TextColor3 = Color3.fromRGB(220, 225, 235)
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(90, 100, 120); s.Thickness = 1; s.Transparency = 0.5; s.Parent = b
	end

	-- ADS button (top of column) — hold to scope
	local adsBtn = Instance.new("TextButton")
	adsBtn.Size = UDim2.new(1, 0, 0, 44)
	adsBtn.Position = UDim2.new(0, 0, 0, 0)
	adsBtn.Text = "ADS"
	adsBtn.Parent = btnCol
	styleBtn(adsBtn)
	adsBtn.MouseButton1Down:Connect(function() setAds(true) end)
	adsBtn.MouseButton1Up:Connect(function() setAds(false) end)

	-- RELOAD button
	local reloadBtn = Instance.new("TextButton")
	reloadBtn.Size = UDim2.new(1, 0, 0, 44)
	reloadBtn.Position = UDim2.new(0, 0, 0, 52) -- 44 + 8 gap
	reloadBtn.Text = "RELOAD"
	reloadBtn.Parent = btnCol
	styleBtn(reloadBtn)
	reloadBtn.MouseButton1Click:Connect(tryReload)

	-- Weapon switch (slot cycle)
	local switchBtn = Instance.new("TextButton")
	switchBtn.Size = UDim2.new(1, 0, 0, 44)
	switchBtn.Position = UDim2.new(0, 0, 0, 104) -- 52 + 44 + 8
	switchBtn.Text = "SWAP"
	switchBtn.Parent = btnCol
	styleBtn(switchBtn)
	-- Cycle through slots: primary → secondary → melee → primary
	switchBtn.MouseButton1Click:Connect(function()
		local order = { "primary", "secondary", "melee" }
		local currentIdx = 1
		for i, s in order do if s == equippedSlotName then currentIdx = i; break end end
		local nextSlot = order[(currentIdx % #order) + 1]
		Remotes.SwitchWeapon:FireServer(nextSlot)
	end)

	-- ===== SPRINT TOGGLE (bottom-LEFT, ABOVE HP bar) =====
	-- HP bar (HealthController) occupies x:24-284 y:-136..-80 at bottom-left,
	-- so we stack RUN above it at y:-204..-160 (24px gap). Still clears the
	-- BRONZE rank chip at top because phones are tall enough.
	local sprintBtn = Instance.new("TextButton")
	sprintBtn.Name = "MobileSprintBtn"
	sprintBtn.Size = UDim2.new(0, 44, 0, 44)
	sprintBtn.AnchorPoint = Vector2.new(0, 1)
	sprintBtn.Position = UDim2.new(0, 12, 1, -160)
	sprintBtn.Text = "RUN"
	sprintBtn.Parent = screenGui
	styleBtn(sprintBtn)

	local function refreshSprintStyle()
		if isSprinting then
			sprintBtn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
			sprintBtn.BackgroundTransparency = 0.1
			sprintBtn.TextColor3 = Color3.fromRGB(15, 25, 15)
		else
			sprintBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
			sprintBtn.BackgroundTransparency = 0.25
			sprintBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
		end
	end
	sprintBtn.MouseButton1Click:Connect(function()
		if equippedId == "sniper" then return end
		isSprinting = not isSprinting
		if isSprinting and isAds then setAds(false) end
		ClientSignals.Get("SprintChanged"):Fire(isSprinting)
		refreshSprintStyle()
	end)

	-- Register mobile buttons for drag-to-reposition in HUD Edit mode.
	-- Defaults match new compact layout (44px buttons; col size 148; sprint at -100).
	registerHudButton(adsBtn,    "hudAds",    UDim2.new(1, -12, 0.5, -52)) -- top of col
	registerHudButton(reloadBtn, "hudReload", UDim2.new(1, -12, 0.5, 0))
	registerHudButton(switchBtn, "hudSwap",   UDim2.new(1, -12, 0.5, 52))
	registerHudButton(sprintBtn, "hudSprint", UDim2.new(0, 12, 1, -160))
end

Remotes.AmmoUpdate.OnClientEvent:Connect(function(info: any)
	currentAmmo = info.current or 0
	currentMagSize = info.magSize or 0
	local wasReloading = isReloading
	isReloading = info.reloading == true
	if isReloading and not wasReloading then
		reloadStartTime = os.clock()
		if equippedId then
			local weapon = WeaponConfig[equippedId]
			reloadDuration = weapon and weapon.reloadTime or 1.5
		end
	end
	updateAmmoPanel()
end)

local function applySkinForCurrentWeapon()
	if not equippedId or not cachedProfile then
		applySkin(nil)
		return
	end
	local slotKey = "skin_" .. equippedId
	local skinId = cachedProfile.equipped and cachedProfile.equipped[slotKey]
	if skinId then
		local cosmetic = CosmeticRegistry.ById[skinId]
		if cosmetic then
			applySkin(cosmetic) -- pass full palette
			return
		end
	end
	applySkin(nil)
end

-- Returns karambit parts override if knife equipped with karambit-flagged skin, else nil.
local function knifeKarambitPartsIfActive(): any?
	if not cachedProfile then return nil end
	local skinId = cachedProfile.equipped and cachedProfile.equipped["skin_knife"]
	if not skinId then return nil end
	local cosmetic = CosmeticRegistry.ById[skinId]
	if not cosmetic or not (cosmetic :: any).isKarambit then return nil end
	local weapon = WeaponConfig["knife"]
	local kViewmodel = weapon and (weapon :: any).viewmodelKarambit
	return kViewmodel and kViewmodel.parts
end

-- Returns M9 Bayonet parts override if knife equipped with M9-flagged skin, else nil.
local function knifeM9PartsIfActive(): any?
	if not cachedProfile then return nil end
	local skinId = cachedProfile.equipped and cachedProfile.equipped["skin_knife"]
	if not skinId then return nil end
	local cosmetic = CosmeticRegistry.ById[skinId]
	if not cosmetic or not (cosmetic :: any).isM9 then return nil end
	local weapon = WeaponConfig["knife"]
	local m9Viewmodel = weapon and (weapon :: any).viewmodelM9
	return m9Viewmodel and m9Viewmodel.parts
end

local currentKnifeIsKarambit = false
local currentKnifeIsM9 = false

Remotes.WeaponEquipped.OnClientEvent:Connect(function(weaponId: string, slot: string)
	-- Auto-close scope on weapon switch (toggle scope wouldn't survive switching)
	if isAds then setAds(false) end
	if weaponId == "" then
		clearViewmodel()
		equippedId = nil
		equippedSlotName = nil
		crosshair.Visible = false
		isReloading = false
		updateSlotPanel()
		updateAmmoPanel()
		return
	end
	equippedId = weaponId
	equippedSlotName = slot
	isReloading = false
	-- Switching TO sniper cancels active sprint (AWP can't sprint).
	if weaponId == "sniper" and isSprinting then
		isSprinting = false
		ClientSignals.Get("SprintChanged"):Fire(false)
	end
	local weapon = WeaponConfig[weaponId]
	if not weapon then
		return
	end
	-- Knife shape switch: if equipped skin has isM9 → M9 Bayonet viewmodel,
	-- else isKarambit → karambit viewmodel, else default straight combat knife.
	-- Flags are mutually exclusive in practice (one shape per cosmetic).
	local partsOverride: any = nil
	if weaponId == "knife" then
		local m9Parts = knifeM9PartsIfActive()
		local karambitParts = knifeKarambitPartsIfActive()
		partsOverride = m9Parts or karambitParts
		currentKnifeIsM9 = (m9Parts ~= nil)
		currentKnifeIsKarambit = (karambitParts ~= nil) and (m9Parts == nil)
	else
		currentKnifeIsM9 = false
		currentKnifeIsKarambit = false
	end
	buildViewmodel(weapon, partsOverride)
	drawStartTime = os.clock()
	crosshair.Visible = true
	updateSlotPanel()
	updateAmmoPanel()
	applySkinForCurrentWeapon()
end)

Remotes.HitConfirm.OnClientEvent:Connect(function(info: any)
	showHitmark(info.isHeadshot, info.killed)
	showDamageFeedback(info.damage, info.killed, info.isHeadshot)
	-- Knife: silent on hit (no ting marker). Kill sound still plays for elimination feedback.
	local isMelee = info.weaponSlot == "melee"
	if info.killed then
		playUiSound(AudioConfig.kill)
	elseif not isMelee then
		if info.isHeadshot then
			playUiSound(AudioConfig.hit_marker_head)
		else
			playUiSound(AudioConfig.hit_marker)
		end
	end
end)

Remotes.ShotFired.OnClientEvent:Connect(function(info: any)
	if not info or not info.origin or not info.hitPosition then
		return
	end
	local shooterUserId = info.shooterUserId
	local startPos: Vector3
	if shooterUserId == player.UserId then
		startPos = muzzleWorldPosition() or info.origin
	else
		startPos = findRemoteShooterMuzzle(shooterUserId) or info.origin
	end
	-- Skip tracer + muzzle flash for melee (knife has no bullet trail).
	local isMelee = info.weaponSlot == "melee"
	if not isMelee then
		drawTracer(startPos, info.hitPosition)
		if shooterUserId ~= player.UserId then
			spawnBroadcastMuzzleFlash(startPos)
		end
	end
	if info.didHit then
		spawnBulletImpact(
			info.hitPosition,
			info.hitNormal or Vector3.new(0, 1, 0),
			info.hitMaterial or "Plastic",
			info.hitIsPlayer == true
		)
	end
end)

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	cachedProfile = data
	-- Sync NORMAL_FOV with player's baseFov setting (so FOV slider in settings works)
	if data and data.settings and type(data.settings.baseFov) == "number" then
		NORMAL_FOV = data.settings.baseFov
	end
	-- If knife equipped + shape changed (karambit / M9 / default swap), rebuild viewmodel.
	if equippedId == "knife" then
		local m9Parts = knifeM9PartsIfActive()
		local karambitParts = knifeKarambitPartsIfActive()
		local newParts = m9Parts or karambitParts
		local newIsM9 = (m9Parts ~= nil)
		local newIsKarambit = (karambitParts ~= nil) and (m9Parts == nil)
		if newIsM9 ~= currentKnifeIsM9 or newIsKarambit ~= currentKnifeIsKarambit then
			local weapon = WeaponConfig["knife"]
			if weapon then
				buildViewmodel(weapon, newParts)
				currentKnifeIsM9 = newIsM9
				currentKnifeIsKarambit = newIsKarambit
			end
		end
	end
	applySkinForCurrentWeapon()
end)

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end
	-- DEFENSIVE: force camera to attach to the fresh humanoid + nuke any leftover
	-- viewmodel state from the previous body. Fixes "POV stuck at death location"
	-- where the old body's CameraSubject lingers after respawn — the new viewmodel
	-- then renders relative to the frozen camera (= old death location).
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
	clearViewmodel()
	equippedId = nil
	equippedSlotName = nil

	humanoid.Died:Connect(function()
		clearViewmodel()
		equippedId = nil
		equippedSlotName = nil
		crosshair.Visible = false
		slotPanel.Visible = false
	end)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

RunService.RenderStepped:Connect(function(dt: number)
	-- Classic static crosshair: no bloom recovery loop needed.

	-- Smooth ADS transition
	local adsTarget = isAds and 1 or 0
	adsTransition = adsTransition + (adsTarget - adsTransition) * math.min(1, dt * 10)

	-- CAMERA BOB — sine-wave Y/X offset during ground movement. Applied to
	-- camera.CFrame BEFORE viewmodel positioning so viewmodel (which composes
	-- via camera.CFrame * grip) inherits the bob naturally. Suppressed during
	-- ADS so aim stays steady.
	local char = player.Character
	local charHum = char and char:FindFirstChildOfClass("Humanoid")
	if charHum and charHum.Health > 0 and not isAds then
		local moveMag = charHum.MoveDirection.Magnitude
		local grounded = charHum.FloorMaterial ~= Enum.Material.Air
		if moveMag > 0.1 and grounded then
			local amp = if isSprinting then GameConfig.BobAmpSprint else GameConfig.BobAmpWalk
			local freq = if isSprinting then GameConfig.BobFreqSprint else GameConfig.BobFreqWalk
			bobPhase += dt * freq
			local bobY = math.sin(bobPhase) * amp
			local bobX = math.sin(bobPhase * 0.5) * amp * 0.4
			camera.CFrame = camera.CFrame * CFrame.new(bobX, bobY, 0)
		end
	end

	if equippedId and #viewmodelParts > 0 then
		local weapon = WeaponConfig[equippedId]
		if not weapon then
			return
		end

		local drawProgress = math.min(1, (os.clock() - drawStartTime) / weapon.drawTime)
		local drawCF, slideCF = getAnimOffsets(drawProgress)
		-- AWP bolt cycle: after each shot, animate slide back-forward (CS2-style bolt action, 0.5s lockout)
		if equippedId == "sniper" then
			local timeSinceShot = os.clock() - lastFireAt
			local BOLT_DURATION = 0.5
			if timeSinceShot >= 0 and timeSinceShot < BOLT_DURATION then
				local t = timeSinceShot / BOLT_DURATION
				local boltAmt = math.sin(t * math.pi)
				slideCF = slideCF * CFrame.new(0, 0, boltAmt * 0.35)
			end
		end
		-- Karambit pullout: blade spins around finger RING (ring is pivot, blade+handle orbit).
		-- Arm stays put — only blade body twirls. Quadratic ease-out from fast spin to settled.
		local karambitBladePivotSpinCF: CFrame? = nil
		-- M9: zero out drawCF/slideCF so the arms (which use baseGripCF) don't bob
		-- during draw. Only the M9 blade body animates via its own swing offset.
		if currentKnifeIsM9 then
			drawCF = CFrame.new()
			slideCF = CFrame.new()
		end
		if currentKnifeIsKarambit then
			drawCF = CFrame.new()
			slideCF = CFrame.new()
			-- Spin completes in first ~50% of drawTime, then settles. After spin, knife rests until drawTime up.
			local SPIN_PORTION = 0.5
			if drawProgress < SPIN_PORTION then
				local spinProgress = drawProgress / SPIN_PORTION
				local spinT = 1 - spinProgress
				local spinAngle = -spinT * spinT * math.rad(360) -- 1 full rotation
				local pivot = Vector3.new(0.10, -0.25, -0.05)
				karambitBladePivotSpinCF = CFrame.new(pivot) * CFrame.Angles(0, 0, spinAngle) * CFrame.new(-pivot.X, -pivot.Y, -pivot.Z)
			end
		end

		local reloadGripCF = CFrame.new()
		local reloadMagCF = CFrame.new()
		local reloadSlideCF = CFrame.new()
		local reloadThumpCF = CFrame.new()
		if isReloading and reloadDuration > 0 then
			local reloadProgress = math.min(1, (os.clock() - reloadStartTime) / reloadDuration)
			reloadGripCF, reloadMagCF, reloadSlideCF, reloadThumpCF = getReloadOffsets(reloadProgress)
		end

		-- ADS shift: pull grip toward screen center horizontally + DOWN so the
		-- weapon body sits below the dot sight (won't cover the reticle). For
		-- AWP this still works fine because its scope overlay masks the whole
		-- screen — the gun being lower is invisible behind the black mask.
		local adsShift = CFrame.new(-0.55 * adsTransition, -0.35 * adsTransition, -0.15 * adsTransition)

		-- Per-weapon cocking rotation — each weapon does a subtle rotate during
		-- draw to "expose" the slide/bolt/charging-handle to the camera while the
		-- fake cocking arm reaches in. Knife/M9 skipped (no cocking).
		local cockingRotation = CFrame.new()
		if equippedId == "rifle" then
			-- AK-47: yaw left +45°, ease back by 85% of draw
			local cockProg = drawProgress
			local rotAmt = 0
			if cockProg < 0.5 then
				rotAmt = math.rad(45)
			elseif cockProg < 0.85 then
				rotAmt = math.rad(45) * (1 - (cockProg - 0.5) / 0.35)
			end
			if rotAmt > 0 then
				cockingRotation = CFrame.Angles(0, rotAmt, 0)
			end
		elseif equippedId == "smg" then
			-- UMP-45: yaw left +30° (lighter than AK), ease back by 85%
			local cp = drawProgress
			local rotAmt = 0
			if cp < 0.5 then
				rotAmt = math.rad(30)
			elseif cp < 0.85 then
				rotAmt = math.rad(30) * (1 - (cp - 0.5) / 0.35)
			end
			if rotAmt > 0 then
				cockingRotation = CFrame.Angles(0, rotAmt, 0)
			end
		elseif equippedId == "sniper" then
			-- AWP: yaw RIGHT 25° (expose bolt on right side) + slight pitch up
			local cp = drawProgress
			local rotY, rotX = 0, 0
			if cp < 0.55 then
				rotY = math.rad(-25); rotX = math.rad(-5)
			elseif cp < 0.85 then
				local t = 1 - (cp - 0.55) / 0.3
				rotY = math.rad(-25) * t; rotX = math.rad(-5) * t
			end
			if rotY ~= 0 or rotX ~= 0 then
				cockingRotation = CFrame.Angles(rotX, rotY, 0)
			end
		elseif equippedId == "pistol" then
			-- Glock-18: yaw left +40° (expose slide to camera), ease back by 85%
			local cp = drawProgress
			local rotAmt = 0
			if cp < 0.5 then
				rotAmt = math.rad(40)
			elseif cp < 0.85 then
				rotAmt = math.rad(40) * (1 - (cp - 0.5) / 0.35)
			end
			if rotAmt > 0 then
				cockingRotation = CFrame.Angles(0, rotAmt, 0)
			end
		end
		-- Arm/hand basis: M9 uses viewmodelM9.grip (kept fixed), else default combat grip.
		local activeGrip = weapon.viewmodel.grip
		if currentKnifeIsM9 and (weapon :: any).viewmodelM9 and (weapon :: any).viewmodelM9.grip then
			activeGrip = (weapon :: any).viewmodelM9.grip
		end
		local baseGripCF = camera.CFrame * activeGrip * cockingRotation * drawCF * reloadGripCF * reloadThumpCF * adsShift
		-- Karambit: blade body uses tuned `bladeGrip`, arms use base `grip`.
		-- M9 Bayonet: knife body uses decomposed viewmodelM9 fields so the RX
		-- (pitch) can animate independently for the pullout swing.
		local bladeGripCF = baseGripCF
		local karambitBladeGrip = currentKnifeIsKarambit and (weapon :: any).viewmodelKarambit and (weapon :: any).viewmodelKarambit.bladeGrip
		local m9 = currentKnifeIsM9 and (weapon :: any).viewmodelM9 or nil
		local hasM9 = m9 and m9.bladeGripPos and true or false
		if karambitBladeGrip then
			bladeGripCF = camera.CFrame * karambitBladeGrip * drawCF * reloadGripCF * reloadThumpCF * adsShift
		elseif hasM9 then
			-- M9 PULLOUT (CS2-style): RX pitches from -100° (knife pointed down) UP
			-- to rest RX over 0.45s, ease-out (fast lift → slow settle).
			-- Because RX is applied BEFORE Y/Z rotations on a position-only frame,
			-- it pivots around the camera's horizontal axis = true vertical swing.
			local M9_SWING_DURATION = 0.45
			local M9_START_RX = math.rad(-150)
			local restRX = m9.bladeGripRX
			local swingT = math.min(1, (os.clock() - drawStartTime) / M9_SWING_DURATION)
			local eased = 1 - (1 - swingT) * (1 - swingT)
			local currentRX = M9_START_RX + (restRX - M9_START_RX) * eased
			local animBladeGrip = CFrame.new(m9.bladeGripPos)
				* CFrame.Angles(currentRX, 0, 0)
				* CFrame.Angles(0, m9.bladeGripRY, m9.bladeGripRZ)
			bladeGripCF = camera.CFrame * animBladeGrip * drawCF * reloadGripCF * reloadThumpCF * adsShift
		end

		-- M9 right-arm "lift then settle" — small Y rise that peaks mid-swing
		-- and returns to rest, sold-stamps the "kesan m9" deploy feel. Sine wave
		-- so it eases in + out symmetrically. Applied to right arm (i==1) and the
		-- M9 weapon body (i>=3) so they stay visually connected; left arm stays put.
		local m9ArmRiseCF = CFrame.new()
		if hasM9 then
			local M9_RISE_DURATION = 0.45
			local riseT = math.min(1, (os.clock() - drawStartTime) / M9_RISE_DURATION)
			local rise = math.sin(riseT * math.pi) * 0.18 -- peak +0.18 stud at riseT=0.5
			m9ArmRiseCF = CFrame.new(0, rise, 0)
		end

		-- Knife slash animation (left-click): wide 140° horizontal alternating L/R for ALL knives.
		local knifeSwingCF = CFrame.new()
		local slashActive = false
		if equippedId == "knife" then
			local elapsed = os.clock() - knifeSwingStart
			if elapsed >= 0 and elapsed < KNIFE_SWING_DURATION then
				slashActive = true
				local t = elapsed / KNIFE_SWING_DURATION
				local arc = math.sin(t * math.pi)
				local yawAngle = arc * math.rad(140) * knifeSwingDir
				knifeSwingCF = knifeSwingCF * CFrame.Angles(0, yawAngle, 0) * CFrame.new(0, 0, -arc * 0.7)
			end
		end

		-- Knife right-click stab/swing — per-knife specific animation.
		-- Compute separate stab grip for arm (lerp from baseGripCF) vs blade (lerp from bladeGripCF for karambit).
		-- This avoids snap at end of animation when blade switches back to bladeGripCF.
		local armStabGripCF: CFrame? = nil
		local bladeStabGripCF: CFrame? = nil
		if equippedId == "knife" then
			local stabElapsed = os.clock() - knifeStabStart
			if stabElapsed >= 0 and stabElapsed < KNIFE_STAB_DURATION then
				local t = stabElapsed / KNIFE_STAB_DURATION
				local arc
				if t < 0.4 then
					arc = (t / 0.4) ^ 0.6
				else
					arc = 1 - ((t - 0.4) / 0.6)
				end
				if currentKnifeIsKarambit then
					-- Karambit right-click: hand FORWARD + blade SWINGS UP + 180° vertical flip.
					local stabPose = CFrame.new(0.55, -0.55, -1.6 - arc * 1.5)
						* CFrame.Angles(0, math.rad(-90), 0)
						* CFrame.Angles(0, 0, math.pi)
					local upwardSwing = CFrame.Angles(arc * math.rad(45), 0, 0) -- gentler upward swing
					local fullPoseCF = camera.CFrame * upwardSwing * stabPose * drawCF * reloadGripCF * reloadThumpCF * adsShift
					armStabGripCF = baseGripCF:Lerp(fullPoseCF, arc)        -- arm from normal pose
					bladeStabGripCF = bladeGripCF:Lerp(fullPoseCF, arc)     -- blade from karambit pose
				else
					-- Combat knife: stab pose (hand forward + thrust)
					local stabPose = CFrame.new(0.55, -0.55, -1.6 - arc * 1.5) * CFrame.Angles(0, math.rad(-90), 0)
					local stabPoseCF = camera.CFrame * stabPose * drawCF * reloadGripCF * reloadThumpCF * adsShift
					armStabGripCF = baseGripCF:Lerp(stabPoseCF, arc)
					bladeStabGripCF = armStabGripCF  -- combat knife: same lerp source (no separate blade grip)
				end
			end
		end

		-- Precompute karambit blade-relative-to-arm CFrame (constant per frame, avoid CFrame:Inverse() in tight loop).
		local karambitBladeRelative: CFrame? = nil
		if slashActive and currentKnifeIsKarambit and karambitBladeGrip and not bladeStabGripCF then
			karambitBladeRelative = baseGripCF:Inverse() * bladeGripCF
		end

		-- Hide AWP viewmodel during scope (scope view should not include the rifle).
		local hideForScope = isAds and weapon.id == "sniper"
		for i, info in viewmodelParts do
			local extra = CFrame.new()
			if info.config.role == "slide" then
				extra = slideCF * reloadSlideCF
			elseif info.config.role == "mag" then
				extra = reloadMagCF
			end
			-- For karambit AND M9, first 2 parts are arms (base grip), rest are knife body (tuned grip).
			local grip = baseGripCF
			if (karambitBladeGrip or hasM9) and i > 2 then
				grip = bladeGripCF
			end
			-- M9 right-arm lift: apply rise to right arm (i==1) + weapon body
			-- (i>=3) so they move together. Left arm (i==2) stays static.
			if hasM9 and (i == 1 or i > 2) then
				grip = grip * m9ArmRiseCF
			end
			-- Stab override: arm (i=1) uses armStabGripCF, blade body (i>=3) uses bladeStabGripCF.
			if armStabGripCF and i == 1 then
				grip = armStabGripCF
			elseif bladeStabGripCF and i >= 3 then
				grip = bladeStabGripCF
			end
			-- Knife slash: apply to right arm (i=1) + knife body (i>=3), skip left arm (i=2).
			local swing = CFrame.new()
			if equippedId == "knife" and (i == 1 or i >= 3) then
				swing = knifeSwingCF
			end
			-- KARAMBIT SLASH: blade body follows arm — rotate around arm pivot (baseGripCF), not blade pivot.
			-- Uses precomputed karambitBladeRelative (no per-part :Inverse() call).
			if karambitBladeRelative and i >= 3 then
				grip = baseGripCF * swing * karambitBladeRelative
				swing = CFrame.new()
			end
			-- KARAMBIT PULLOUT SPIN: blade body twirls around finger ring (pivot).
			-- Apply only to blade body parts (i >= 3), arm stays put.
			local pivotedSpin = (karambitBladePivotSpinCF and i >= 3) and karambitBladePivotSpinCF or nil
			local finalCF: CFrame
			if pivotedSpin then
				finalCF = grip * swing * pivotedSpin * info.config.offset * extra
			else
				finalCF = grip * swing * info.config.offset * extra
			end
			-- Left-handed mirror: transform to cam-local, mirror across YZ, back to world.
			if leftHanded then
				local camCF = camera.CFrame
				finalCF = camCF * mirrorCamLocal(camCF:Inverse() * finalCF)
			end
			info.part.CFrame = finalCF
			-- Cocking arm fade: visible during draw (0-70%), fades out (70-100%), hidden after
			local cockingFade = 0
			if (info.config :: any).isCockingArm then
				cockingFade = math.clamp((drawProgress - 0.7) / 0.3, 0, 1)
			end
			info.part.LocalTransparencyModifier = hideForScope and 1 or cockingFade
		end

		-- FOV interpolation
		local targetFov = NORMAL_FOV - (NORMAL_FOV - ADS_FOV) * adsTransition
		camera.FieldOfView = camera.FieldOfView + (targetFov - camera.FieldOfView) * math.min(1, dt * 12)

		-- Crosshair fade during ADS (lines + center dot)
		for _, info in crosshairLines do
			info.line.BackgroundTransparency = adsTransition * 0.95
		end
		centerDot.BackgroundTransparency = adsTransition * 0.95
	end
end)

-- Camera recoil: spring physics. Camera kicks up on fire, no auto-recover
-- (player compensates manually like classic FPS). Crosshair stays where mouse points.
local CAMERA_RECOIL_STIFFNESS = 180
local CAMERA_RECOIL_DAMPING = 14

RunService:BindToRenderStep("WeaponRecoil", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	if dt <= 0 then return end
	recoilPitchVel += -recoilPitch * CAMERA_RECOIL_STIFFNESS * dt
	recoilPitchVel -= recoilPitchVel * CAMERA_RECOIL_DAMPING * dt
	recoilPitch += recoilPitchVel * dt

	recoilYawVel += -recoilYaw * CAMERA_RECOIL_STIFFNESS * dt
	recoilYawVel -= recoilYawVel * CAMERA_RECOIL_DAMPING * dt
	recoilYaw += recoilYawVel * dt

	if math.abs(recoilPitch) > 0.0005 or math.abs(recoilYaw) > 0.0005 then
		camera.CFrame = camera.CFrame * CFrame.Angles(recoilPitch * dt * 60, recoilYaw * dt * 60, 0)
	end
end)

return WeaponController
