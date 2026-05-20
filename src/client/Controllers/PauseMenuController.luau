--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local ClientSignals = require(Shared.Modules.ClientSignals)
local MatchState = require(Shared.Modules.MatchState)
local UITheme = require(Shared.Modules.UITheme)

local PauseMenuController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PauseMenuHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false  -- modal: let Roblox auto-shift below the topbar (Unibar) so title isnt covered
-- DisplayOrder must sit above all in-match HUD layers so the modal overlay
-- covers FIRE / RELOAD / SWAP / RUN buttons. KillFeed sits at 80 and
-- MatchHUD/WeaponHUD around 0-50, so 200 keeps headroom for other HUDs.
screenGui.DisplayOrder = 200
screenGui.Parent = playerGui

-- Theme: dark steel-gray with single amber accent (matches armory theme of main menu)
local BG_BASE     = Color3.fromRGB(18, 20, 26)
local BG_PANEL    = Color3.fromRGB(28, 30, 38)
local BG_CARD     = Color3.fromRGB(34, 36, 44)
local BG_CARD_HOV = Color3.fromRGB(42, 44, 54)
local BG_CARD_OFF = Color3.fromRGB(24, 26, 32)
local AMBER       = Color3.fromRGB(220, 165, 80)
local AMBER_DIM   = Color3.fromRGB(140, 100, 50)
local TEXT_HI     = Color3.fromRGB(240, 240, 248)
local TEXT_MID    = Color3.fromRGB(170, 175, 190)
local TEXT_DIM    = Color3.fromRGB(95, 100, 115)
local STROKE_BASE = Color3.fromRGB(58, 62, 76)

-- ============================================================
-- TOGGLE BUTTON (top-right corner — compact, monochrome, amber-on-hover)
-- ============================================================
local menuButton = Instance.new("TextButton")
menuButton.Size = UDim2.new(0, 44, 0, 44)
menuButton.AnchorPoint = Vector2.new(1, 0)
menuButton.Position = UDim2.new(1, -16, 0, 16)
menuButton.BackgroundColor3 = BG_PANEL
menuButton.BorderSizePixel = 0
menuButton.AutoButtonColor = false
menuButton.Font = Enum.Font.GothamBlack
menuButton.TextSize = 22
menuButton.TextColor3 = TEXT_HI
menuButton.Text = "☰"
menuButton.Parent = screenGui

local menuBtnCorner = Instance.new("UICorner")
menuBtnCorner.CornerRadius = UDim.new(0, 6)
menuBtnCorner.Parent = menuButton

local menuBtnStroke = Instance.new("UIStroke")
menuBtnStroke.Color = STROKE_BASE
menuBtnStroke.Thickness = 1
menuBtnStroke.Parent = menuButton

-- Tiny ESC hint chip below the button — desktop only (mobile has no keyboard).
local escHint = Instance.new("TextLabel")
escHint.Size = UDim2.new(0, 44, 0, 14)
escHint.AnchorPoint = Vector2.new(1, 0)
escHint.Position = UDim2.new(1, -16, 0, 62)
escHint.BackgroundTransparency = 1
escHint.Font = Enum.Font.GothamBold
escHint.TextSize = 9
escHint.TextColor3 = TEXT_DIM
escHint.Text = "ESC"
-- Hide ESC hint on narrow mobile viewports (no keyboard) — viewport check is
-- robust for Studio Device Emulator which leaves MouseEnabled=true.
do
	local cam = workspace.CurrentCamera
	escHint.Visible = not (UserInputService.TouchEnabled and cam and cam.ViewportSize.X < 900)
end
escHint.Parent = screenGui

menuButton.MouseEnter:Connect(function()
	menuBtnStroke.Color = AMBER
	menuBtnStroke.Thickness = 2
	menuButton.BackgroundColor3 = BG_CARD_HOV
end)
menuButton.MouseLeave:Connect(function()
	menuBtnStroke.Color = STROKE_BASE
	menuBtnStroke.Thickness = 1
	menuButton.BackgroundColor3 = BG_PANEL
end)

-- ============================================================
-- OVERLAY + PANEL
-- ============================================================
-- Overlay is a TextButton (not a Frame) with Modal=true so that taps/clicks
-- on the dimmed area do NOT pass through to the in-match HUD buttons (FIRE,
-- RELOAD, SWAP, RUN) below. Modal=true tells the Roblox input router to
-- swallow input directed at lower-DisplayOrder GUIs while this is visible.
-- Color uses UITheme.bgDeepest + a darker transparency (0.2 vs prior 0.4) so
-- the HUD doesn't bleed through visually either.
local overlay = Instance.new("TextButton")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = UITheme.Color.bgDeepest
overlay.BackgroundTransparency = 0.2
overlay.Visible = false
overlay.BorderSizePixel = 0
overlay.AutoButtonColor = false
overlay.Text = ""
overlay.Modal = true
overlay.Parent = screenGui

-- Panel is wider to fit a 3x2 grid of cards instead of a 7-tall list.
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 580, 0, 480)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = BG_BASE
panel.BorderSizePixel = 0
panel.Parent = overlay

-- Mobile viewport clamping: keep entire panel within visible area (≤95% vw,
-- ≤92% vh) on small/portrait screens. Also use UIScale to shrink content
-- when the natural 580x480 layout would still overflow.
local panelScale = Instance.new("UIScale")
panelScale.Scale = 1
panelScale.Parent = panel
local function refreshPanelSize()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local maxW = v.X * 0.95
	local maxH = v.Y * 0.92
	-- Scale to fit if natural panel exceeds bounds
	local scaleW = math.min(1, maxW / 580)
	local scaleH = math.min(1, maxH / 480)
	panelScale.Scale = math.min(scaleW, scaleH)
end
refreshPanelSize()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshPanelSize)
end

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = STROKE_BASE
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- Top accent bar (3px amber stripe — the single saturated element)
local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.new(1, 0, 0, 3)
accentBar.Position = UDim2.new(0, 0, 0, 0)
accentBar.BackgroundColor3 = AMBER
accentBar.BorderSizePixel = 0
accentBar.Parent = panel
local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(0, 10)
accentCorner.Parent = accentBar

-- Header row: title left, close X + ESC chip right
local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(0, 200, 0, 32)
titleLbl.Position = UDim2.new(0, 24, 0, 20)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 22
titleLbl.TextColor3 = TEXT_HI
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Text = "PAUSE MENU"
titleLbl.Parent = panel

local taglineLbl = Instance.new("TextLabel")
taglineLbl.Size = UDim2.new(0, 200, 0, 14)
taglineLbl.Position = UDim2.new(0, 24, 0, 50)
taglineLbl.BackgroundTransparency = 1
taglineLbl.Font = Enum.Font.GothamBold
taglineLbl.TextSize = 10
taglineLbl.TextColor3 = AMBER_DIM
taglineLbl.TextXAlignment = Enum.TextXAlignment.Left
taglineLbl.Text = "PRESS ESC TO TOGGLE"
taglineLbl.Parent = panel

-- Close X button (top-right of panel)
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -20, 0, 20)
closeBtn.BackgroundColor3 = BG_CARD
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 18
closeBtn.TextColor3 = TEXT_MID
closeBtn.Text = "✕"
closeBtn.Parent = panel
local closeCorner = Instance.new("UICorner"); closeCorner.CornerRadius = UDim.new(0, 4); closeCorner.Parent = closeBtn
local closeStroke = Instance.new("UIStroke"); closeStroke.Color = STROKE_BASE; closeStroke.Thickness = 1; closeStroke.Parent = closeBtn

closeBtn.MouseEnter:Connect(function()
	closeBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 50)
	closeBtn.TextColor3 = TEXT_HI
	closeStroke.Color = Color3.fromRGB(220, 80, 80)
end)
closeBtn.MouseLeave:Connect(function()
	closeBtn.BackgroundColor3 = BG_CARD
	closeBtn.TextColor3 = TEXT_MID
	closeStroke.Color = STROKE_BASE
end)

-- Thin separator under header
local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, -48, 0, 1)
sep.Position = UDim2.new(0, 24, 0, 76)
sep.BackgroundColor3 = STROKE_BASE
sep.BorderSizePixel = 0
sep.Parent = panel

-- ============================================================
-- STATE
-- ============================================================
local currentState: string? = nil
local isTrainingMode = false

Remotes.EnterTrainingMode.OnClientEvent:Connect(function(active: boolean)
	isTrainingMode = active == true
end)

local function isLobbyState(): boolean
	if isTrainingMode then return true end
	return currentState == MatchState.States.LOBBY or currentState == MatchState.States.VOTING
end

type MenuItem = {
	id: string,
	label: string,
	icon: string,
	desc: string,           -- 1-line description shown under label
	signal: string?,
	action: (() -> ())?,
	lobbyOnly: boolean?,
}

-- 6 panel items (RESUME / EXIT are special bottom-bar actions, not cards).
-- All openable any time — changes apply on next spawn / next match.
local items: { MenuItem } = {
	{ id = "loadout",   label = "LOADOUT",     icon = "🔫", desc = "Pick primary + secondary",   signal = "OpenLoadout" },
	{ id = "cosmetics", label = "COSMETICS",   icon = "✦",  desc = "Skins + knives",             signal = "OpenCosmetics" },
	{ id = "shop",      label = "SHOP",        icon = "🛒", desc = "Buy with coins or Robux",    signal = "OpenShop" },
	{ id = "bp",        label = "BATTLE PASS", icon = "⭐", desc = "Season tiers + rewards",     signal = "OpenBP" },
	{ id = "missions",  label = "MISSIONS",    icon = "📋", desc = "Daily + weekly challenges",  signal = "OpenMissions" },
	{ id = "settings",  label = "SETTINGS",    icon = "⚙",  desc = "Audio, sensitivity, crosshair", signal = "OpenSettings" },
}

-- ============================================================
-- GRID OF CARDS (3 cols × 2 rows)
-- ============================================================
local gridContainer = Instance.new("Frame")
gridContainer.Size = UDim2.new(1, -48, 0, 280)
gridContainer.Position = UDim2.new(0, 24, 0, 92)
gridContainer.BackgroundTransparency = 1
gridContainer.Parent = panel

local CARD_W = 168
local CARD_H = 132
local CARD_GAP = 14

local itemCards: { TextButton } = {}
local itemStrokes: { UIStroke } = {}
local itemLockBadges: { TextLabel } = {}

for index, item in items do
	local col = (index - 1) % 3
	local row = math.floor((index - 1) / 3)

	local card = Instance.new("TextButton")
	card.Size = UDim2.new(0, CARD_W, 0, CARD_H)
	card.Position = UDim2.new(0, col * (CARD_W + CARD_GAP), 0, row * (CARD_H + CARD_GAP))
	card.BackgroundColor3 = BG_CARD
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = gridContainer

	local cardCorner = Instance.new("UICorner"); cardCorner.CornerRadius = UDim.new(0, 8); cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke"); cardStroke.Color = STROKE_BASE; cardStroke.Thickness = 1; cardStroke.Parent = card

	-- Icon (top-left, large)
	local iconLbl = Instance.new("TextLabel")
	iconLbl.Size = UDim2.new(0, 40, 0, 40)
	iconLbl.Position = UDim2.new(0, 12, 0, 14)
	iconLbl.BackgroundTransparency = 1
	iconLbl.Font = Enum.Font.GothamBlack
	iconLbl.TextSize = 24
	iconLbl.TextColor3 = AMBER
	iconLbl.TextXAlignment = Enum.TextXAlignment.Left
	iconLbl.Text = item.icon
	iconLbl.Parent = card

	-- Label (below icon, bold)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -24, 0, 22)
	lbl.Position = UDim2.new(0, 12, 0, 62)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 14
	lbl.TextColor3 = TEXT_HI
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = item.label
	lbl.Parent = card

	-- Desc (small, muted)
	local descLbl = Instance.new("TextLabel")
	descLbl.Size = UDim2.new(1, -24, 0, 32)
	descLbl.Position = UDim2.new(0, 12, 0, 86)
	descLbl.BackgroundTransparency = 1
	descLbl.Font = Enum.Font.Gotham
	descLbl.TextSize = 11
	descLbl.TextColor3 = TEXT_MID
	descLbl.TextXAlignment = Enum.TextXAlignment.Left
	descLbl.TextYAlignment = Enum.TextYAlignment.Top
	descLbl.TextWrapped = true
	descLbl.Text = item.desc
	descLbl.Parent = card

	-- LOCKED chip overlay (shown for lobby-only items when not in lobby)
	local lockBadge = Instance.new("TextLabel")
	lockBadge.Size = UDim2.new(0, 60, 0, 18)
	lockBadge.AnchorPoint = Vector2.new(1, 0)
	lockBadge.Position = UDim2.new(1, -10, 0, 10)
	lockBadge.BackgroundColor3 = Color3.fromRGB(80, 60, 30)
	lockBadge.BorderSizePixel = 0
	lockBadge.Font = Enum.Font.GothamBlack
	lockBadge.TextSize = 9
	lockBadge.TextColor3 = AMBER
	lockBadge.Text = "LOBBY"
	lockBadge.Visible = false
	lockBadge.Parent = card
	local lbCorner = Instance.new("UICorner"); lbCorner.CornerRadius = UDim.new(0, 3); lbCorner.Parent = lockBadge

	card.MouseEnter:Connect(function()
		if item.lobbyOnly and not isLobbyState() then return end
		cardStroke.Color = AMBER
		cardStroke.Thickness = 2
		card.BackgroundColor3 = BG_CARD_HOV
	end)
	card.MouseLeave:Connect(function()
		cardStroke.Color = STROKE_BASE
		cardStroke.Thickness = 1
		local available = (not item.lobbyOnly) or isLobbyState()
		card.BackgroundColor3 = if available then BG_CARD else BG_CARD_OFF
	end)
	card.MouseButton1Click:Connect(function()
		if item.lobbyOnly and not isLobbyState() then return end
		overlay.Visible = false
		if item.action then item.action() end
		if item.signal then ClientSignals.Get(item.signal):Fire() end
	end)

	itemCards[index] = card
	itemStrokes[index] = cardStroke
	itemLockBadges[index] = lockBadge
end

-- ============================================================
-- BOTTOM ACTION BAR — RESUME (primary) + EXIT TO MAIN MENU (ghost)
-- ============================================================
local resumeBtn = Instance.new("TextButton")
resumeBtn.Size = UDim2.new(0, 320, 0, 44)
resumeBtn.AnchorPoint = Vector2.new(0, 1)
resumeBtn.Position = UDim2.new(0, 24, 1, -24)
resumeBtn.BackgroundColor3 = AMBER
resumeBtn.BorderSizePixel = 0
resumeBtn.AutoButtonColor = false
resumeBtn.Font = Enum.Font.GothamBlack
resumeBtn.TextSize = 16
resumeBtn.TextColor3 = Color3.fromRGB(28, 22, 14)
resumeBtn.Text = "▶  RESUME"
resumeBtn.Parent = panel
local rbCorner = Instance.new("UICorner"); rbCorner.CornerRadius = UDim.new(0, 6); rbCorner.Parent = resumeBtn

local resumeGradient = Instance.new("UIGradient")
resumeGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 190, 100)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 140, 60)),
})
resumeGradient.Rotation = 90
resumeGradient.Parent = resumeBtn

local resumeStroke = Instance.new("UIStroke"); resumeStroke.Color = Color3.fromRGB(255, 220, 130); resumeStroke.Thickness = 1; resumeStroke.Parent = resumeBtn

resumeBtn.MouseEnter:Connect(function() resumeStroke.Thickness = 2 end)
resumeBtn.MouseLeave:Connect(function() resumeStroke.Thickness = 1 end)

local exitBtn = Instance.new("TextButton")
exitBtn.Size = UDim2.new(0, 200, 0, 44)
exitBtn.AnchorPoint = Vector2.new(1, 1)
exitBtn.Position = UDim2.new(1, -24, 1, -24)
exitBtn.BackgroundColor3 = BG_CARD
exitBtn.BorderSizePixel = 0
exitBtn.AutoButtonColor = false
exitBtn.Font = Enum.Font.GothamBold
exitBtn.TextSize = 13
exitBtn.TextColor3 = TEXT_MID
exitBtn.Text = "EXIT TO MAIN MENU  •  M"
exitBtn.Parent = panel
local ebCorner = Instance.new("UICorner"); ebCorner.CornerRadius = UDim.new(0, 6); ebCorner.Parent = exitBtn
local exitStroke = Instance.new("UIStroke"); exitStroke.Color = STROKE_BASE; exitStroke.Thickness = 1; exitStroke.Parent = exitBtn

exitBtn.MouseEnter:Connect(function()
	exitStroke.Color = Color3.fromRGB(180, 90, 90)
	exitBtn.TextColor3 = Color3.fromRGB(220, 130, 130)
end)
exitBtn.MouseLeave:Connect(function()
	exitStroke.Color = STROKE_BASE
	exitBtn.TextColor3 = TEXT_MID
end)

-- ============================================================
-- BEHAVIOR
-- ============================================================
local function refreshLobbyOnly()
	for index, item in items do
		local card = itemCards[index]
		local lock = itemLockBadges[index]
		if not card or not lock then continue end
		local locked = item.lobbyOnly and not isLobbyState()
		card.BackgroundColor3 = if locked then BG_CARD_OFF else BG_CARD
		lock.Visible = locked or false
	end
end

local function setOpen(value: boolean)
	overlay.Visible = value
	if value then
		refreshLobbyOnly()
		TweenService:Create(overlay, TweenInfo.new(0.15), { BackgroundTransparency = 0.2 }):Play()
	end
	ClientSignals.Get("PauseMenuToggle"):Fire(value)
end

menuButton.MouseButton1Click:Connect(function()
	setOpen(not overlay.Visible)
end)
closeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)
resumeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)
exitBtn.MouseButton1Click:Connect(function()
	-- Fire the same path as the M-key handler (MainMenuController owns it)
	setOpen(false)
	Remotes.ExitToMainMenu:FireServer()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		setOpen(not overlay.Visible)
	end
end)

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	currentState = payload.state
	refreshLobbyOnly()
end)

return PauseMenuController
