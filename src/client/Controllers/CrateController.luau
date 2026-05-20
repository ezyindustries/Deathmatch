--!strict
-- GACHA system: bottom-center button + CS2-style slot machine animation on reveal.
-- No pity for now (per user request).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local CosmeticRegistry = require(Shared.Modules.CosmeticRegistry)
local GameConfig = require(Shared.Constants.GameConfig)

local CrateController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GachaHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 110 -- above MainMenu (100) so GACHA button visible from main menu
screenGui.Parent = playerGui

-- =========================================================
-- GACHA BUTTON — original simple design (bottom-center, orange).
-- Rolling-strip case-reveal animation still triggers on click (handled below).
-- =========================================================
local gachaButton = Instance.new("TextButton")
gachaButton.Size = UDim2.new(0, 220, 0, 56)
gachaButton.AnchorPoint = Vector2.new(0.5, 1)
gachaButton.Position = UDim2.new(0.5, 0, 1, -20)
gachaButton.BackgroundColor3 = Color3.fromRGB(255, 180, 70)
gachaButton.BorderSizePixel = 0
gachaButton.AutoButtonColor = false
gachaButton.Font = Enum.Font.GothamBlack
gachaButton.TextSize = 22
gachaButton.TextColor3 = Color3.fromRGB(28, 28, 38)
gachaButton.Text = string.format("🎰 GACHA (%d)", GameConfig.CratePrice)
gachaButton.Parent = screenGui

local gachaCorner = Instance.new("UICorner")
gachaCorner.CornerRadius = UDim.new(0, 8)
gachaCorner.Parent = gachaButton

local gachaStroke = Instance.new("UIStroke")
gachaStroke.Color = Color3.fromRGB(255, 220, 130)
gachaStroke.Thickness = 2
gachaStroke.Parent = gachaButton

gachaButton.MouseEnter:Connect(function() gachaStroke.Thickness = 3 end)
gachaButton.MouseLeave:Connect(function() gachaStroke.Thickness = 2 end)

-- Alias for visibility-refresh code further down (it toggles `gachaWrap.Visible`).
local gachaWrap = gachaButton

local canAfford = false
local isOpening = false

local function setButtonEnabled(enabled: boolean)
	if isOpening then
		gachaButton.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		gachaButton.TextColor3 = Color3.fromRGB(180, 180, 190)
		gachaButton.Text = "🎰 OPENING..."
		return
	end
	gachaButton.BackgroundColor3 = enabled and Color3.fromRGB(255, 180, 70) or Color3.fromRGB(80, 80, 90)
	gachaButton.TextColor3 = enabled and Color3.fromRGB(28, 28, 38) or Color3.fromRGB(150, 150, 160)
	gachaButton.Text = string.format("🎰 GACHA (%d)", GameConfig.CratePrice)
end
setButtonEnabled(false)

-- =========================================================
-- RECENT PULLS HISTORY — small widget showing last 5 pulls as tier-colored chips.
-- Sits next to the case button in the lobby; gives quick visual recap.
-- =========================================================
local historyFrame = Instance.new("Frame")
historyFrame.Size = UDim2.new(0, 200, 0, 32)
historyFrame.AnchorPoint = Vector2.new(0.5, 1)
historyFrame.Position = UDim2.new(0.5, 0, 1, -130)
historyFrame.BackgroundTransparency = 1
historyFrame.Parent = screenGui

local historyLabel = Instance.new("TextLabel")
historyLabel.Size = UDim2.new(0, 60, 1, 0)
historyLabel.Position = UDim2.new(0, 0, 0, 0)
historyLabel.BackgroundTransparency = 1
historyLabel.Font = Enum.Font.GothamBold
historyLabel.TextSize = 10
historyLabel.TextColor3 = Color3.fromRGB(140, 150, 170)
historyLabel.TextXAlignment = Enum.TextXAlignment.Left
historyLabel.Text = "RECENT"
historyLabel.Parent = historyFrame

-- History chips disabled (original simple gacha UI). Function kept as no-op so
-- the call site below (in CrateOpened handler) doesn't need a guard.
historyFrame.Visible = false
local function pushHistory(_tier: string) end

-- =========================================================
-- SLOT MACHINE OVERLAY (CS2-style horizontal scroll)
-- =========================================================
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.Parent = screenGui

local overlayGrad = Instance.new("UIGradient")
overlayGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 25, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 18)),
})
overlayGrad.Rotation = 90
overlayGrad.Parent = overlay

local headerLabel = Instance.new("TextLabel")
headerLabel.Size = UDim2.new(0, 600, 0, 50)
headerLabel.AnchorPoint = Vector2.new(0.5, 0)
headerLabel.Position = UDim2.new(0.5, 0, 0, 80)
headerLabel.BackgroundTransparency = 1
headerLabel.Font = Enum.Font.GothamBlack
headerLabel.TextSize = 36
headerLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
headerLabel.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
headerLabel.TextStrokeTransparency = 0.4
headerLabel.Text = "🎰 OPENING CASE..."
headerLabel.Parent = overlay

-- Slot strip viewport (clipping mask) — bigger + cinematic dark theme
local VIEWPORT_W = 920
local VIEWPORT_H = 200
local viewport = Instance.new("Frame")
viewport.Size = UDim2.new(0, VIEWPORT_W, 0, VIEWPORT_H)
viewport.AnchorPoint = Vector2.new(0.5, 0.5)
viewport.Position = UDim2.new(0.5, 0, 0.5, 0)
viewport.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
viewport.BorderSizePixel = 0
viewport.ClipsDescendants = true
viewport.Parent = overlay

local viewportCorner = Instance.new("UICorner")
viewportCorner.CornerRadius = UDim.new(0, 14)
viewportCorner.Parent = viewport

local viewportStroke = Instance.new("UIStroke")
viewportStroke.Color = Color3.fromRGB(255, 220, 100)
viewportStroke.Thickness = 2
viewportStroke.Parent = viewport

-- Subtle inner gradient — adds depth so it doesn't feel like a flat box
local viewportGrad = Instance.new("UIGradient")
viewportGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 32, 48)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(14, 16, 26)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 32, 48)),
})
viewportGrad.Rotation = 90
viewportGrad.Parent = viewport

-- Vignette overlay on viewport edges (sides darker so cards in center pop).
-- Each side is a dark frame with a UIGradient that fades to fully transparent
-- toward the center of the viewport.
local function makeVignette(anchorRight: boolean)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 130, 1, 0)
	f.AnchorPoint = if anchorRight then Vector2.new(1, 0) else Vector2.new(0, 0)
	f.Position = if anchorRight then UDim2.new(1, 0, 0, 0) else UDim2.new(0, 0, 0, 0)
	f.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
	f.BorderSizePixel = 0
	f.ZIndex = 4
	f.Parent = viewport
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(6, 8, 14))
	-- 0% transparent at edge, 100% transparent at inner side
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if anchorRight then 1 else 0),
		NumberSequenceKeypoint.new(1, if anchorRight then 0 else 1),
	})
	g.Parent = f
end
makeVignette(false)
makeVignette(true)

-- Center indicator — glowing vertical column with pulse animation
local centerIndicator = Instance.new("Frame")
centerIndicator.Size = UDim2.new(0, 6, 1, 0)
centerIndicator.AnchorPoint = Vector2.new(0.5, 0.5)
centerIndicator.Position = UDim2.new(0.5, 0, 0.5, 0)
centerIndicator.BackgroundColor3 = Color3.fromRGB(255, 220, 100)
centerIndicator.BorderSizePixel = 0
centerIndicator.ZIndex = 5
centerIndicator.Parent = viewport
local centerCorner = Instance.new("UICorner")
centerCorner.CornerRadius = UDim.new(0, 3)
centerCorner.Parent = centerIndicator

-- Glow halo around the indicator (wider, more transparent)
local centerGlow = Instance.new("Frame")
centerGlow.Size = UDim2.new(0, 28, 1, 0)
centerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
centerGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
centerGlow.BackgroundColor3 = Color3.fromRGB(255, 220, 100)
centerGlow.BackgroundTransparency = 0.8
centerGlow.BorderSizePixel = 0
centerGlow.ZIndex = 4
centerGlow.Parent = viewport

-- Triangular markers top + bottom pointing at center
local function makeMarker(top: boolean)
	local m = Instance.new("TextLabel")
	m.Size = UDim2.new(0, 20, 0, 18)
	m.AnchorPoint = Vector2.new(0.5, if top then 0 else 1)
	m.Position = UDim2.new(0.5, 0, if top then 0 else 1, 0)
	m.BackgroundTransparency = 1
	m.Font = Enum.Font.GothamBlack
	m.TextSize = 18
	m.TextColor3 = Color3.fromRGB(255, 220, 100)
	m.Text = if top then "▼" else "▲"
	m.ZIndex = 6
	m.Parent = viewport
	return m
end
local markerTop = makeMarker(true)
local markerBot = makeMarker(false)

-- Pulse animation on center indicator (subtle breathing while idle, intense during roll)
local centerPulseConn: RBXScriptConnection? = nil
local function startCenterPulse(intensity: number)
	if centerPulseConn then centerPulseConn:Disconnect() end
	local t0 = os.clock()
	centerPulseConn = game:GetService("RunService").RenderStepped:Connect(function()
		local t = os.clock() - t0
		local pulse = 0.5 + 0.5 * math.sin(t * 4)
		centerGlow.BackgroundTransparency = 0.85 - pulse * 0.35 * intensity
		centerGlow.Size = UDim2.new(0, 24 + pulse * 12 * intensity, 1, 0)
	end)
end
local function stopCenterPulse()
	if centerPulseConn then centerPulseConn:Disconnect(); centerPulseConn = nil end
end

-- Strip (moves left during animation)
local strip = Instance.new("Frame")
strip.AnchorPoint = Vector2.new(0, 0.5)
strip.Position = UDim2.new(0, 0, 0.5, 0)
strip.BackgroundTransparency = 1
strip.Parent = viewport

-- Reveal panel (shows after animation finishes) — bigger, animated tier glow
local REVEAL_W = 560
local REVEAL_H = 200
local revealCard = Instance.new("Frame")
revealCard.Size = UDim2.new(0, REVEAL_W, 0, REVEAL_H)
revealCard.AnchorPoint = Vector2.new(0.5, 0)
revealCard.Position = UDim2.new(0.5, 0, 0.5, 130)
revealCard.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
revealCard.BorderSizePixel = 0
revealCard.Visible = false
revealCard.Parent = overlay

local revealCorner = Instance.new("UICorner")
revealCorner.CornerRadius = UDim.new(0, 14)
revealCorner.Parent = revealCard

local revealStroke = Instance.new("UIStroke")
revealStroke.Color = Color3.fromRGB(255, 255, 255)
revealStroke.Thickness = 4
revealStroke.Parent = revealCard

-- Glow ring behind the card (tier-colored, pulses while visible)
local revealGlow = Instance.new("Frame")
revealGlow.Size = UDim2.new(1, 40, 1, 40)
revealGlow.AnchorPoint = Vector2.new(0.5, 0.5)
revealGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
revealGlow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
revealGlow.BackgroundTransparency = 0.8
revealGlow.BorderSizePixel = 0
revealGlow.ZIndex = -1
revealGlow.Parent = revealCard
local revealGlowCorner = Instance.new("UICorner")
revealGlowCorner.CornerRadius = UDim.new(0, 20)
revealGlowCorner.Parent = revealGlow

-- Top accent bar (tier color stripe spanning full width)
local revealAccentBar = Instance.new("Frame")
revealAccentBar.Size = UDim2.new(1, 0, 0, 6)
revealAccentBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
revealAccentBar.BorderSizePixel = 0
revealAccentBar.Parent = revealCard
local revealAccentCorner = Instance.new("UICorner")
revealAccentCorner.CornerRadius = UDim.new(0, 14)
revealAccentCorner.Parent = revealAccentBar

-- Tier badge (pill, top-left)
local revealTier = Instance.new("TextLabel")
revealTier.Size = UDim2.new(0, 140, 0, 28)
revealTier.AnchorPoint = Vector2.new(0, 0)
revealTier.Position = UDim2.new(0, 20, 0, 22)
revealTier.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
revealTier.BorderSizePixel = 0
revealTier.Font = Enum.Font.GothamBlack
revealTier.TextSize = 14
revealTier.TextColor3 = Color3.fromRGB(0, 0, 0)
revealTier.Text = "TIER"
revealTier.Parent = revealCard

local revealTierCorner = Instance.new("UICorner")
revealTierCorner.CornerRadius = UDim.new(0, 6)
revealTierCorner.Parent = revealTier

-- Visual color swatch (right of badge — shows the cosmetic's color tile)
local revealSwatch = Instance.new("Frame")
revealSwatch.Size = UDim2.new(0, 90, 0, 90)
revealSwatch.AnchorPoint = Vector2.new(1, 0)
revealSwatch.Position = UDim2.new(1, -20, 0, 22)
revealSwatch.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
revealSwatch.BorderSizePixel = 0
revealSwatch.Parent = revealCard
local swatchCorner = Instance.new("UICorner")
swatchCorner.CornerRadius = UDim.new(0, 8)
swatchCorner.Parent = revealSwatch
local swatchStroke = Instance.new("UIStroke")
swatchStroke.Color = Color3.fromRGB(255, 255, 255)
swatchStroke.Transparency = 0.5
swatchStroke.Thickness = 1
swatchStroke.Parent = revealSwatch

-- Item name (larger, bold)
local revealName = Instance.new("TextLabel")
revealName.Size = UDim2.new(1, -140, 0, 36)
revealName.Position = UDim2.new(0, 20, 0, 60)
revealName.BackgroundTransparency = 1
revealName.Font = Enum.Font.GothamBlack
revealName.TextSize = 26
revealName.TextColor3 = Color3.fromRGB(245, 245, 250)
revealName.TextXAlignment = Enum.TextXAlignment.Left
revealName.Text = "—"
revealName.Parent = revealCard

local revealType = Instance.new("TextLabel")
revealType.Size = UDim2.new(1, -140, 0, 22)
revealType.Position = UDim2.new(0, 20, 0, 98)
revealType.BackgroundTransparency = 1
revealType.Font = Enum.Font.Gotham
revealType.TextSize = 14
revealType.TextColor3 = Color3.fromRGB(150, 160, 180)
revealType.TextXAlignment = Enum.TextXAlignment.Left
revealType.Text = ""
revealType.Parent = revealCard

local revealExtra = Instance.new("TextLabel")
revealExtra.Size = UDim2.new(1, -40, 0, 24)
revealExtra.Position = UDim2.new(0, 20, 1, -42)
revealExtra.BackgroundTransparency = 1
revealExtra.Font = Enum.Font.GothamBold
revealExtra.TextSize = 14
revealExtra.TextColor3 = Color3.fromRGB(255, 220, 90)
revealExtra.TextXAlignment = Enum.TextXAlignment.Left
revealExtra.Text = ""
revealExtra.Parent = revealCard

-- Glow ring pulse (only runs while reveal is visible; cleaned up on close)
local revealGlowConn: RBXScriptConnection? = nil
local function startRevealPulse(tierColor: Color3)
	if revealGlowConn then revealGlowConn:Disconnect() end
	revealGlow.BackgroundColor3 = tierColor
	local t0 = os.clock()
	revealGlowConn = game:GetService("RunService").RenderStepped:Connect(function()
		local t = os.clock() - t0
		local p = 0.5 + 0.5 * math.sin(t * 2.5)
		revealGlow.BackgroundTransparency = 0.85 - p * 0.45
		revealGlow.Size = UDim2.new(1, 30 + p * 30, 1, 30 + p * 30)
	end)
end
local function stopRevealPulse()
	if revealGlowConn then revealGlowConn:Disconnect(); revealGlowConn = nil end
end

-- Close button
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 180, 0, 44)
closeButton.AnchorPoint = Vector2.new(0.5, 1)
closeButton.Position = UDim2.new(0.5, 0, 1, -40)
closeButton.BackgroundColor3 = Color3.fromRGB(80, 200, 110)
closeButton.BorderSizePixel = 0
closeButton.AutoButtonColor = false
closeButton.Font = Enum.Font.GothamBlack
closeButton.TextSize = 18
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Text = "▸ CONTINUE"
closeButton.Visible = false
closeButton.Parent = overlay

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

-- Pending karambit mystery → actual reveal task (cancelled on close to prevent stale UI updates)
local pendingRevealTask: thread? = nil

closeButton.MouseButton1Click:Connect(function()
	if pendingRevealTask then
		task.cancel(pendingRevealTask)
		pendingRevealTask = nil
	end
	stopCenterPulse()
	stopRevealPulse()
	overlay.Visible = false
	revealCard.Visible = false
	closeButton.Visible = false
	isOpening = false
	screenGui.DisplayOrder = 110 -- reset to normal (button-only height)
	setButtonEnabled(canAfford)
end)

-- SKIP button (visible during slot animation; snaps strip to predetermined winner position)
local skipButton = Instance.new("TextButton")
skipButton.Size = UDim2.new(0, 160, 0, 36)
skipButton.AnchorPoint = Vector2.new(0.5, 0)
skipButton.Position = UDim2.new(0.5, 0, 0.5, 90) -- center-bottom, below viewport (viewport is 140 tall centered)
skipButton.BackgroundColor3 = Color3.fromRGB(110, 110, 130)
skipButton.BorderSizePixel = 0
skipButton.AutoButtonColor = false
skipButton.Font = Enum.Font.GothamBold
skipButton.TextSize = 15
skipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
skipButton.Text = "⏭ SKIP"
skipButton.Visible = false
skipButton.Parent = overlay

local skipCorner = Instance.new("UICorner")
skipCorner.CornerRadius = UDim.new(0, 8)
skipCorner.Parent = skipButton

local activeTween: Tween? = nil
local skipRequested = false
local currentTargetX: number = 0 -- shared so skip handler can snap to winner position immediately
skipButton.MouseButton1Click:Connect(function()
	if activeTween then
		skipRequested = true
		-- SNAP strip to predetermined winner position IMMEDIATELY (before canceling tween,
		-- so player can't see intermediate frames where wrong item might appear at center)
		strip.Position = UDim2.new(0, currentTargetX, 0.5, 0)
		activeTween:Cancel()
	end
	skipButton.Visible = false
end)

-- =========================================================
-- SLOT ANIMATION
-- =========================================================
local CARD_WIDTH = 140
local CARD_HEIGHT = 180
local CARD_GAP = 10
local STRIP_ITEM_COUNT = 40
local WINNER_INDEX = 32 -- 0-based; strip stops with this card centered

local function makeStripCard(cosmetic: CosmeticRegistry.CosmeticInfo, index: number): Frame
	local tierColor = CosmeticRegistry.TierColors[cosmetic.tier] or Color3.fromRGB(80, 80, 95)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
	f.Position = UDim2.new(0, index * (CARD_WIDTH + CARD_GAP), 0, -CARD_HEIGHT / 2)
	f.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
	f.BorderSizePixel = 0
	f.Parent = strip

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = f

	-- Outer tier-color stroke + small glow
	local stroke = Instance.new("UIStroke")
	stroke.Color = tierColor
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = f

	-- Top tier accent bar (color identifier)
	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(1, 0, 0, 5)
	accentBar.BackgroundColor3 = tierColor
	accentBar.BorderSizePixel = 0
	accentBar.Parent = f
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 10)
	barCorner.Parent = accentBar

	-- Color tile in upper area (representing the cosmetic visually)
	local colorTile = Instance.new("Frame")
	colorTile.Size = UDim2.new(1, -20, 0, 70)
	colorTile.Position = UDim2.new(0, 10, 0, 18)
	colorTile.BackgroundColor3 = cosmetic.color
	colorTile.BorderSizePixel = 0
	colorTile.Parent = f
	local tileCorner = Instance.new("UICorner")
	tileCorner.CornerRadius = UDim.new(0, 6)
	tileCorner.Parent = colorTile
	local tileGrad = Instance.new("UIGradient")
	tileGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(
			math.min(1, cosmetic.color.R + 0.15),
			math.min(1, cosmetic.color.G + 0.15),
			math.min(1, cosmetic.color.B + 0.15)
		)),
		ColorSequenceKeypoint.new(1, Color3.new(
			math.max(0, cosmetic.color.R - 0.15),
			math.max(0, cosmetic.color.G - 0.15),
			math.max(0, cosmetic.color.B - 0.15)
		)),
	})
	tileGrad.Rotation = 135
	tileGrad.Parent = colorTile

	-- Tier label
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Size = UDim2.new(1, -16, 0, 14)
	tierLabel.Position = UDim2.new(0, 8, 0, 96)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Font = Enum.Font.GothamBlack
	tierLabel.TextSize = 10
	tierLabel.TextColor3 = tierColor
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierLabel.Text = string.upper(cosmetic.tier)
	tierLabel.Parent = f

	-- Item name (multi-line)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -16, 0, 56)
	nameLabel.Position = UDim2.new(0, 8, 0, 114)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.fromRGB(240, 240, 250)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Top
	nameLabel.TextWrapped = true
	-- For karambits, show generic "Karambit" — don't reveal specific variant in strip
	if (cosmetic :: any).isKarambit then
		nameLabel.Text = "★ Karambit ★"
		nameLabel.TextColor3 = Color3.fromRGB(255, 230, 130)
	else
		nameLabel.Text = cosmetic.displayName
	end
	nameLabel.Parent = f

	return f
end

-- Strip visual weighting — Contraband intentionally rare so the strip stays mostly Common
-- with occasional Legendary flashes. Winner card is forced at WINNER_INDEX regardless.
local STRIP_TIER_WEIGHTS = {
	{ tier = "Common",     weight = 0.90 },
	{ tier = "Legendary",  weight = 0.08 },
	{ tier = "Contraband", weight = 0.02 },
}

local function pickStripTier(): CosmeticRegistry.Tier
	local r = math.random()
	local cum = 0
	for _, entry in STRIP_TIER_WEIGHTS do
		cum += entry.weight
		if r < cum then
			return entry.tier :: CosmeticRegistry.Tier
		end
	end
	return "Common"
end

local function pickRandomCosmetic(): CosmeticRegistry.CosmeticInfo
	local tier = pickStripTier()
	local pool = CosmeticRegistry.ByTier[tier]
	if pool and #pool > 0 then
		-- Avoid karambits in strip filler (they should only appear as winner)
		for _ = 1, 5 do
			local pick = pool[math.random(#pool)]
			if not (pick :: any).isKarambit then
				return pick
			end
		end
	end
	-- Fallback: any cosmetic
	local all = CosmeticRegistry.All
	return all[math.random(#all)]
end

local function typeDisplayName(type_: string): string
	if type_ == "weapon_skin" then return "Weapon Skin" end
	if type_ == "kill_effect" then return "Kill Effect" end
	if type_ == "emote" then return "Emote" end
	if type_ == "title" then return "Title" end
	if type_ == "banner" then return "Banner" end
	return type_
end

local function clearStrip()
	for _, c in strip:GetChildren() do
		c:Destroy()
	end
end

local function runSlotAnimation(winner: CosmeticRegistry.CosmeticInfo, onComplete: () -> ())
	clearStrip()

	for i = 0, STRIP_ITEM_COUNT - 1 do
		local item: CosmeticRegistry.CosmeticInfo
		if i == WINNER_INDEX then
			item = winner
		else
			item = pickRandomCosmetic()
		end
		makeStripCard(item, i)
	end

	local winnerCenterX = WINNER_INDEX * (CARD_WIDTH + CARD_GAP) + CARD_WIDTH / 2
	local targetX = -(winnerCenterX - VIEWPORT_W / 2)
	local jitter = (math.random() * 2 - 1) * 18
	targetX += jitter

	strip.Position = UDim2.new(0, VIEWPORT_W, 0.5, 0)

	-- Tier-aware suspense: rare drops get a slower deceleration + longer settle
	-- pause so the reveal feels earned (Quint→Cubic = less harsh stop). Karambit
	-- gets the longest tease because it's the rarest outcome.
	local winnerTier = winner.tier
	local isKarambit = (winner :: any).isKarambit == true
	local duration, easing, settleWait
	if isKarambit then
		duration = 5.5
		easing = Enum.EasingStyle.Cubic
		settleWait = 0.8
	elseif winnerTier == "Contraband" then
		duration = 5.0
		easing = Enum.EasingStyle.Cubic
		settleWait = 0.6
	elseif winnerTier == "Legendary" then
		duration = 4.3
		easing = Enum.EasingStyle.Quint
		settleWait = 0.5
	else
		duration = 3.8
		easing = Enum.EasingStyle.Quint
		settleWait = 0.4
	end

	-- Start indicator pulse (intensifies during roll)
	startCenterPulse(if isKarambit or winnerTier == "Contraband" then 1.5 else 0.7)

	-- Flash viewport stroke tier color during last portion of the roll
	local tierColor = CosmeticRegistry.TierColors[winnerTier] or Color3.fromRGB(255, 220, 100)
	viewportStroke.Color = tierColor
	if isKarambit then viewportStroke.Color = Color3.fromRGB(255, 230, 130) end

	local tween = TweenService:Create(
		strip,
		TweenInfo.new(duration, easing, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, targetX, 0.5, 0) }
	)
	activeTween = tween
	skipRequested = false
	currentTargetX = targetX
	skipButton.Visible = true
	tween:Play()

	tween.Completed:Connect(function()
		strip.Position = UDim2.new(0, targetX, 0.5, 0)
		activeTween = nil
		skipButton.Visible = false
		task.wait(skipRequested and 0.1 or settleWait)
		onComplete()
	end)
end

local function showReveal(result: any)
	local cosmetic = result.cosmetic :: CosmeticRegistry.CosmeticInfo
	local tierColor = CosmeticRegistry.TierColors[cosmetic.tier] or Color3.fromRGB(200, 200, 200)
	local isKarambit = (cosmetic :: any).isKarambit == true

	pushHistory(cosmetic.tier)
	stopCenterPulse()

	local function fillFinalReveal()
		revealTier.Text = string.upper(cosmetic.tier)
		revealTier.BackgroundColor3 = tierColor
		revealStroke.Color = tierColor
		revealAccentBar.BackgroundColor3 = tierColor
		revealSwatch.BackgroundColor3 = cosmetic.color
		revealName.Text = cosmetic.displayName
		revealType.Text = typeDisplayName(cosmetic.type)
		if result.isDuplicate then
			revealExtra.Text = string.format("◇ DUPLICATE — refunded %d coins", result.refund)
			revealExtra.TextColor3 = Color3.fromRGB(180, 190, 210)
		else
			revealExtra.Text = "★ NEW UNLOCK!"
			revealExtra.TextColor3 = Color3.fromRGB(255, 220, 90)
		end
		closeButton.Visible = true
		headerLabel.Text = "ITEM UNLOCKED"
		headerLabel.TextColor3 = tierColor
		startRevealPulse(tierColor)
	end

	if isKarambit then
		headerLabel.Text = "★  KARAMBIT  ★"
		headerLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
		revealCard.Visible = false
		closeButton.Visible = false
		pendingRevealTask = task.delay(2, function()
			pendingRevealTask = nil
			if not overlay.Visible then return end
			fillFinalReveal()
			revealCard.Visible = true
			revealCard.Size = UDim2.new(0, 120, 0, 80)
			TweenService:Create(revealCard, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, REVEAL_W, 0, REVEAL_H),
			}):Play()
		end)
		return
	end

	fillFinalReveal()
	revealCard.Visible = true
	revealCard.Size = UDim2.new(0, 120, 0, 80)
	TweenService:Create(revealCard, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, REVEAL_W, 0, REVEAL_H),
	}):Play()
end

-- =========================================================
-- WIRE UP EVENTS
-- =========================================================
gachaButton.MouseButton1Click:Connect(function()
	if isOpening or not canAfford then
		return
	end
	if pendingRevealTask then
		task.cancel(pendingRevealTask)
		pendingRevealTask = nil
	end
	isOpening = true
	setButtonEnabled(false)
	Remotes.OpenCrate:FireServer()
end)

Remotes.CrateOpened.OnClientEvent:Connect(function(result: any)
	if result.error then
		gachaButton.Text = "ERROR: " .. tostring(result.error)
		task.delay(2, function()
			isOpening = false
			setButtonEnabled(canAfford)
		end)
		return
	end
	screenGui.DisplayOrder = 200 -- raise above other menus during reveal
	overlay.Visible = true
	overlay.BackgroundTransparency = 0
	headerLabel.Text = "🎰 OPENING CASE..."
	headerLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	revealCard.Visible = false
	closeButton.Visible = false

	task.wait(0.2)
	runSlotAnimation(result.cosmetic, function()
		showReveal(result)
	end)
end)

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	canAfford = (data.coins or 0) >= GameConfig.CratePrice
	setButtonEnabled(canAfford)
end)

-- Visibility: gacha follows the LOCAL player — visible whenever THIS player
-- isn't actively in the arena (i.e., they're at the main menu, between matches,
-- or waiting in lobby). Triggered by character spawn/despawn rather than the
-- global match state — the server's state may be MATCH while this player is
-- still browsing the menu (hasn't clicked PLAY yet), and gacha should be
-- accessible in that case.
local isTrainingMode = false
local localPlayer = Players.LocalPlayer

local function refreshGachaVisibility()
	local inArena = localPlayer.Character ~= nil
	local show = (not isTrainingMode) and (not inArena)
	gachaWrap.Visible = show
	historyFrame.Visible = show
end

Remotes.EnterTrainingMode.OnClientEvent:Connect(function(active: boolean)
	isTrainingMode = active == true
	refreshGachaVisibility()
end)

localPlayer.CharacterAdded:Connect(function()
	refreshGachaVisibility()
end)
localPlayer.CharacterRemoving:Connect(function()
	-- Defer one frame so player.Character has cleared by the time we check
	task.defer(refreshGachaVisibility)
end)

refreshGachaVisibility()

return CrateController
