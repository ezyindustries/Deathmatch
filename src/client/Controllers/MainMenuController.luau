--!strict
-- CS2-style full-screen main menu shown on join.
-- Layout A: PLAY+mode top-center, Loadout/Cosmetics/Stats left, Shop/BP/Missions right.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local ClientSignals = require(Shared.Modules.ClientSignals)
local UITheme = require(Shared.Modules.UITheme)

local MainMenuController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

-- ============================================================
-- RESPONSIVE BREAKPOINTS (viewport-X based, Studio Device Emulator-friendly).
-- TouchEnabled is unreliable in the emulator, so we use viewport width.
-- Recomputed inside layout helpers and bound to ViewportSize changes.
-- ============================================================
local function getViewportW(): number
	local cam = Workspace.CurrentCamera
	return (cam and cam.ViewportSize.X) or 1920
end
local function isMobileVP(): boolean return getViewportW() < 700 end
local function isTabletVP(): boolean return getViewportW() < 1100 end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainMenu"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

-- Armory backdrop — warm steel-gray gradient (weapon collection theme)
local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.fromRGB(38, 32, 26)
backdrop.BorderSizePixel = 0
backdrop.Parent = screenGui

local backdropGradient = Instance.new("UIGradient")
backdropGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 50, 42)),  -- warm top
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(32, 28, 24)), -- mid dark
	ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 18, 16)),   -- darker bottom
})
backdropGradient.Rotation = 90
backdropGradient.Parent = backdrop

-- ============================================================
-- HERO RADIAL LIGHT — soft warm glow behind the title to give the backdrop
-- depth instead of flat black. Two stacked frames simulate a radial falloff.
-- ============================================================
local heroGlow = Instance.new("Frame")
heroGlow.AnchorPoint = Vector2.new(0.5, 0)
heroGlow.Position = UDim2.new(0.5, 0, 0, 0)
heroGlow.Size = UDim2.new(0, 900, 0, 380)
heroGlow.BackgroundColor3 = Color3.fromRGB(220, 165, 90)
heroGlow.BackgroundTransparency = 0.75
heroGlow.BorderSizePixel = 0
heroGlow.Parent = backdrop
local heroGrad = Instance.new("UIGradient")
heroGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 120)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 50, 30)),
})
heroGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.45),
	NumberSequenceKeypoint.new(1, 1),
})
heroGrad.Rotation = 90
heroGrad.Parent = heroGlow

-- ============================================================
-- DIAGONAL ACCENT STRIPES — subtle tactical band across the corners.
-- Two thin amber strips at top-left and bottom-right give the page motion.
-- ============================================================
local function makeAccentStripe(yScale: number, rot: number, color: Color3)
	local s = Instance.new("Frame")
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.new(0.5, 0, yScale, 0)
	s.Size = UDim2.new(2.2, 0, 0, 2)
	s.BackgroundColor3 = color
	s.BackgroundTransparency = 0.75
	s.BorderSizePixel = 0
	s.Rotation = rot
	s.Parent = backdrop
end
makeAccentStripe(0.16, -6, Color3.fromRGB(220, 165, 90))
makeAccentStripe(0.84,  6, Color3.fromRGB(220, 165, 90))
makeAccentStripe(0.18,  4, Color3.fromRGB(160, 105, 50))
makeAccentStripe(0.82, -4, Color3.fromRGB(160, 105, 50))

-- ============================================================
-- WEAPON SILHOUETTES — detailed procedural gun shapes. Multi-part composition
-- makes them read as real weapons even at low opacity. All parts share an
-- amber/sepia palette tied to the armory theme.
-- ============================================================
local function silPart(parent: Instance, x: number, y: number, w: number, h: number, tint: Color3, transparency: number?): Frame
	local p = Instance.new("Frame")
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.new(0.5, x, 0.5, y)
	p.Size = UDim2.fromOffset(w, h)
	p.BackgroundColor3 = tint
	p.BackgroundTransparency = transparency or 0.82
	p.BorderSizePixel = 0
	p.Parent = parent
	return p
end

-- AK-style rifle silhouette: stock + receiver + magazine + handguard + barrel + muzzle + scope rail
local function makeRifleSilhouette(parent: Instance, x: number, y: number, scale: number, rot: number)
	local s = scale
	local container = Instance.new("Frame")
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(x, y)
	container.Size = UDim2.fromOffset(280 * s, 70 * s)
	container.BackgroundTransparency = 1
	container.Rotation = rot
	container.Parent = parent
	local body = Color3.fromRGB(115, 95, 70)
	local wood = Color3.fromRGB(140, 95, 55)
	local mag  = Color3.fromRGB(95, 75, 55)
	-- Receiver (main body)
	silPart(container, 0, 0, 90 * s, 18 * s, body, 0.82)
	-- Wooden handguard under barrel
	silPart(container, 50 * s, 4 * s, 50 * s, 14 * s, wood, 0.84)
	-- Barrel
	silPart(container, 90 * s, 0, 60 * s, 7 * s, body, 0.82)
	-- Front sight post
	silPart(container, 105 * s, -10 * s, 5 * s, 12 * s, body, 0.84)
	-- Muzzle brake (slotted)
	silPart(container, 125 * s, 0, 14 * s, 10 * s, body, 0.82)
	-- Scope rail
	silPart(container, -10 * s, -14 * s, 60 * s, 6 * s, body, 0.86)
	-- Scope body (cylinder approximation)
	silPart(container, -10 * s, -22 * s, 50 * s, 10 * s, body, 0.84)
	-- Curved magazine (banana mag suggestion via tilted rect)
	local magPart = silPart(container, -25 * s, 22 * s, 32 * s, 38 * s, mag, 0.82)
	magPart.Rotation = -10
	-- Pistol grip
	silPart(container, -25 * s, 24 * s, 16 * s, 28 * s, wood, 0.82)
	-- Wooden buttstock
	silPart(container, -75 * s, 4 * s, 70 * s, 22 * s, wood, 0.82)
	-- Stock cheek riser
	silPart(container, -90 * s, -6 * s, 30 * s, 4 * s, wood, 0.84)
end

-- Pistol silhouette: slide + frame + grip + trigger guard + sights
local function makePistolSilhouette(parent: Instance, x: number, y: number, scale: number, rot: number)
	local s = scale
	local container = Instance.new("Frame")
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(x, y)
	container.Size = UDim2.fromOffset(110 * s, 90 * s)
	container.BackgroundTransparency = 1
	container.Rotation = rot
	container.Parent = parent
	local steel = Color3.fromRGB(125, 100, 80)
	local polymer = Color3.fromRGB(100, 80, 65)
	-- Slide (top)
	silPart(container, 0, -22 * s, 80 * s, 18 * s, steel, 0.82)
	-- Rear sight bump
	silPart(container, 30 * s, -34 * s, 8 * s, 6 * s, steel, 0.84)
	-- Front sight
	silPart(container, -30 * s, -34 * s, 4 * s, 6 * s, steel, 0.84)
	-- Frame (below slide)
	silPart(container, 0, -8 * s, 70 * s, 8 * s, polymer, 0.82)
	-- Accessory rail (under frame)
	silPart(container, -20 * s, -2 * s, 24 * s, 4 * s, steel, 0.86)
	-- Trigger guard (oval suggested by 2 rects)
	silPart(container, 8 * s, 4 * s, 18 * s, 16 * s, polymer, 0.86)
	-- Grip (angled)
	local grip = silPart(container, 22 * s, 22 * s, 24 * s, 38 * s, polymer, 0.82)
	grip.Rotation = -8
	-- Mag baseplate
	silPart(container, 26 * s, 40 * s, 22 * s, 4 * s, steel, 0.84)
end

-- Knife silhouette: clip-point blade + crossguard + handle + pommel
local function makeKnifeSilhouette(parent: Instance, x: number, y: number, scale: number, rot: number)
	local s = scale
	local container = Instance.new("Frame")
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(x, y)
	container.Size = UDim2.fromOffset(170 * s, 30 * s)
	container.BackgroundTransparency = 1
	container.Rotation = rot
	container.Parent = parent
	local steel = Color3.fromRGB(160, 140, 115)
	local handleColor = Color3.fromRGB(80, 60, 45)
	-- Blade body
	silPart(container, -20 * s, 0, 100 * s, 9 * s, steel, 0.82)
	-- Blade edge highlight
	silPart(container, -20 * s, 5 * s, 100 * s, 2 * s, Color3.fromRGB(220, 195, 165), 0.84)
	-- Fuller (blood groove)
	silPart(container, -20 * s, -1 * s, 80 * s, 2 * s, Color3.fromRGB(110, 95, 75), 0.86)
	-- Clip-point tip
	local tip = silPart(container, 35 * s, -1 * s, 20 * s, 7 * s, steel, 0.82)
	tip.Rotation = -8
	-- Crossguard
	silPart(container, -45 * s, 0, 6 * s, 18 * s, Color3.fromRGB(95, 80, 65), 0.82)
	-- Handle (wood)
	silPart(container, -65 * s, 0, 40 * s, 12 * s, handleColor, 0.82)
	-- Handle wraps (3 small rings for texture)
	for i = -1, 1 do
		silPart(container, -65 * s + i * 12 * s, 0, 2 * s, 13 * s, Color3.fromRGB(50, 35, 25), 0.85)
	end
	-- Pommel cap
	silPart(container, -88 * s, 0, 6 * s, 14 * s, Color3.fromRGB(95, 80, 65), 0.82)
end

-- ============================================================
-- BULLET SHELL CASINGS — small brass cylinders scattered as "ejected" decor.
-- ============================================================
local function makeShell(parent: Instance, x: number, y: number, scale: number, rot: number)
	local s = scale
	local shell = Instance.new("Frame")
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(x, y)
	shell.Size = UDim2.fromOffset(28 * s, 9 * s)
	shell.BackgroundColor3 = Color3.fromRGB(195, 145, 60) -- brass
	shell.BackgroundTransparency = 0.78
	shell.BorderSizePixel = 0
	shell.Rotation = rot
	shell.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = shell
	-- Primer rim (small darker bump at one end)
	local rim = Instance.new("Frame")
	rim.AnchorPoint = Vector2.new(1, 0.5)
	rim.Position = UDim2.new(1, 0, 0.5, 0)
	rim.Size = UDim2.fromOffset(3 * s, 11 * s)
	rim.BackgroundColor3 = Color3.fromRGB(135, 90, 35)
	rim.BackgroundTransparency = 0.78
	rim.BorderSizePixel = 0
	rim.Parent = shell
end

-- ============================================================
-- SCATTER DECORATIONS across the backdrop
-- ============================================================
makeRifleSilhouette(backdrop, 0.16, 0.28, 1.05, -10)
makeRifleSilhouette(backdrop, 0.84, 0.24, 0.95, 14)
makeRifleSilhouette(backdrop, 0.12, 0.78, 0.85, -22)
makeRifleSilhouette(backdrop, 0.86, 0.74, 1.0, 20)
makePistolSilhouette(backdrop, 0.28, 0.52, 0.85, -18)
makePistolSilhouette(backdrop, 0.72, 0.56, 0.95, 22)
makeKnifeSilhouette(backdrop, 0.22, 0.42, 0.85, 35)
makeKnifeSilhouette(backdrop, 0.78, 0.38, 0.9, -38)
makeKnifeSilhouette(backdrop, 0.5, 0.88, 0.75, 4)
-- Shell casings scattered around for "ejected brass" vibe
makeShell(backdrop, 0.08, 0.40, 1.0, 18)
makeShell(backdrop, 0.93, 0.62, 0.95, -28)
makeShell(backdrop, 0.35, 0.78, 0.8, 70)
makeShell(backdrop, 0.65, 0.82, 0.85, -50)
makeShell(backdrop, 0.45, 0.18, 0.75, 95)
makeShell(backdrop, 0.55, 0.20, 0.7, -110)
makeShell(backdrop, 0.18, 0.90, 0.9, 12)
makeShell(backdrop, 0.82, 0.92, 0.85, -22)

-- ============================================================
-- CORNER HEX-DOT GRID — tiny dots in each corner suggesting a tech overlay.
-- Adds visual texture without competing with the main UI.
-- ============================================================
local function makeDotGrid(originX: number, originY: number, cols: number, rows: number, color: Color3)
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local d = Instance.new("Frame")
			d.AnchorPoint = Vector2.new(0.5, 0.5)
			d.Position = UDim2.fromOffset(originX + c * 14, originY + r * 14)
			d.Size = UDim2.fromOffset(2, 2)
			d.BackgroundColor3 = color
			d.BackgroundTransparency = 0.82
			d.BorderSizePixel = 0
			d.Parent = backdrop
			local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(1, 0); cc.Parent = d
		end
	end
end
makeDotGrid(20,  20,  9, 9, Color3.fromRGB(220, 175, 100))
makeDotGrid(20,  -150, 9, 9, Color3.fromRGB(220, 175, 100))  -- placeholder; positioned via offset-from-bottom not directly possible without UDim conversions

-- ============================================================
-- VIGNETTE — darken edges, keep center brighter for visual focus
-- ============================================================
local vignette = Instance.new("Frame")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
vignette.BackgroundTransparency = 0.45
vignette.BorderSizePixel = 0
vignette.Parent = backdrop
local vignetteGradient = Instance.new("UIGradient")
vignetteGradient.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
vignetteGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.35),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(1, 0.35),
})
vignetteGradient.Rotation = 0
vignetteGradient.Parent = vignette

-- Secondary vertical vignette for top/bottom edge darkening
local vignette2 = Instance.new("Frame")
vignette2.Size = UDim2.fromScale(1, 1)
vignette2.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
vignette2.BackgroundTransparency = 0.6
vignette2.BorderSizePixel = 0
vignette2.Parent = backdrop
local vig2Grad = Instance.new("UIGradient")
vig2Grad.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
vig2Grad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.55),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(1, 0.55),
})
vig2Grad.Rotation = 90
vig2Grad.Parent = vignette2

-- Title (top center) — responsive size. Mobile fits within ~666px viewport
-- without overlapping the rank chip top-left (~140px wide). Title text size
-- maps display(48) → h1(36) → h2(28) at desktop/tablet/mobile.
local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 600, 0, 80)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 40)
title.BackgroundTransparency = 1
title.Font = UITheme.Font.display
title.TextSize = UITheme.FontSize.display -- desktop default, refreshed below
title.TextColor3 = Color3.fromRGB(255, 240, 200)
title.TextStrokeColor3 = Color3.fromRGB(180, 130, 50) -- amber/gold stroke (armory)
title.TextStrokeTransparency = 0.3
title.Text = "SHOOTING GAME"
title.Parent = screenGui

-- Subtitle
local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(0, 400, 0, 20)
subtitle.AnchorPoint = Vector2.new(0.5, 0)
subtitle.Position = UDim2.new(0.5, 0, 0, 115)
subtitle.BackgroundTransparency = 1
subtitle.Font = UITheme.Font.body
subtitle.TextSize = UITheme.FontSize.caption
subtitle.TextColor3 = Color3.fromRGB(220, 180, 130)
subtitle.Text = "TACTICAL DEATHMATCH"
subtitle.Parent = screenGui

-- ===== Center column: Mode cards (visible at once) + PLAY button =====
local centerCol = Instance.new("Frame")
centerCol.Size = UDim2.new(0, 560, 0, 320) -- refreshed in applyResponsiveLayout()
centerCol.AnchorPoint = Vector2.new(0.5, 0.5)
centerCol.Position = UDim2.new(0.5, 0, 0.5, -10)
centerCol.BackgroundTransparency = 1
centerCol.Parent = screenGui

-- Section label above the mode cards
local sectionLbl = Instance.new("TextLabel")
sectionLbl.Size = UDim2.new(1, 0, 0, 18)
sectionLbl.Position = UDim2.new(0, 0, 0, 0)
sectionLbl.BackgroundTransparency = 1
sectionLbl.Font = UITheme.Font.heading
sectionLbl.TextSize = UITheme.FontSize.micro
sectionLbl.TextColor3 = Color3.fromRGB(180, 150, 100)
sectionLbl.TextXAlignment = Enum.TextXAlignment.Center
sectionLbl.Text = "— SELECT GAME MODE —"
sectionLbl.Parent = centerCol

-- Mode cards: visible side-by-side instead of cycle dropdown, so the player
-- can compare options at a glance (and adding a 3rd mode later won't change
-- the interaction model).
type ModeInfo = { id: string, name: string, tagline: string, info: string, accent: Color3 }
local MODES: { ModeInfo } = {
	{
		id = "deathmatch",
		name = "DEATHMATCH",
		tagline = "FREE-FOR-ALL",
		info = "Respawn terus, kill sebanyak-banyaknya dalam 6 menit. Semua senjata bebas.",
		accent = Color3.fromRGB(220, 100, 80),
	},
	{
		id = "training",
		name = "PRACTICE",
		tagline = "SOLO RANGE",
		info = "Range room with dummy targets. Test loadouts and aim freely.",
		accent = Color3.fromRGB(100, 170, 220),
	},
}
local currentModeIndex = 1

local modeCards: { TextButton } = {}
local modeStrokes: { UIStroke } = {}

-- Mode card geometry is responsive (recomputed in applyResponsiveLayout).
-- Mobile (vw<700): 140x80 — fits two cards side-by-side on iPhone 7 landscape
-- (666x374) with generous breathing room above (title) + below (PLAY).
-- Shrunk from 180x100 after mobile audit: cards no longer dominate ~70% of the
-- vertical real estate, leaving room for PLAY without overlapping the side
-- button columns. Tablet (vw<1100): 200x110. Desktop: 260x160.
local function getCardDims(): (number, number, number)
	local w, h, gap
	if isMobileVP() then
		w, h, gap = 140, 80, UITheme.Space.s -- 8
	elseif isTabletVP() then
		w, h, gap = 200, 110, UITheme.Space.m -- 12
	else
		w, h, gap = 260, 160, UITheme.Space.xl -- 20
	end
	return w, h, gap
end

-- Initial card dims used to size sub-labels at card creation. Layout helper
-- below repositions everything when viewport changes.
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP = getCardDims()
local CARDS_TOTAL = #MODES * CARD_WIDTH + (#MODES - 1) * CARD_GAP

local function selectMode(index: number)
	currentModeIndex = index
	for i, card in modeCards do
		local stroke = modeStrokes[i]
		if i == index then
			stroke.Color = MODES[i].accent
			stroke.Thickness = 3
			stroke.Transparency = 0
			card.BackgroundColor3 = UITheme.Color.bgHover
		else
			stroke.Color = UITheme.Color.borderSubtle
			stroke.Thickness = 1
			stroke.Transparency = 0.3
			card.BackgroundColor3 = UITheme.Color.bgElevated
		end
	end
end

-- Per-card label refs so responsive layout can adjust font sizes + positions
type ModeCardRefs = {
	tag: TextLabel,
	name: TextLabel,
	desc: TextLabel,
	check: TextLabel,
}
local modeCardRefs: { ModeCardRefs } = {}

for i, mode in MODES do
	local card = Instance.new("TextButton")
	card.Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
	card.AnchorPoint = Vector2.new(0, 0)
	card.Position = UDim2.new(0.5, -CARDS_TOTAL / 2 + (i - 1) * (CARD_WIDTH + CARD_GAP), 0, 32)
	card.BackgroundColor3 = UITheme.Color.bgElevated
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = centerCol

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UITheme.Radius.md)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Color.borderSubtle
	stroke.Thickness = 1
	stroke.Parent = card

	-- Top accent bar (3px) — the only saturated color, so cards feel restrained
	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(1, 0, 0, 3)
	accentBar.BackgroundColor3 = mode.accent
	accentBar.BorderSizePixel = 0
	accentBar.Parent = card
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, UITheme.Radius.md)
	barCorner.Parent = accentBar

	-- Tagline (small, muted)
	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(1, -UITheme.Space.xxl, 0, 14)
	tag.Position = UDim2.new(0, UITheme.Space.m, 0, UITheme.Space.m)
	tag.BackgroundTransparency = 1
	tag.Font = UITheme.Font.heading
	tag.TextSize = 10
	tag.TextColor3 = mode.accent
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.Text = mode.tagline
	tag.Parent = card

	-- Name (large, prominent) — text scales with viewport via applyResponsiveLayout
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -UITheme.Space.xxl, 0, 28)
	name.Position = UDim2.new(0, UITheme.Space.m, 0, 28)
	name.BackgroundTransparency = 1
	name.Font = UITheme.Font.display
	name.TextSize = UITheme.FontSize.h3 -- 22; bumped to 24 on desktop in layout helper
	name.TextColor3 = UITheme.Color.textPrimary
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextScaled = false
	name.TextWrapped = false
	name.Text = mode.name
	name.Parent = card

	-- Description (multi-line, wrapped) — hidden on mobile to save vertical space.
	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -UITheme.Space.xxl, 0, 44)
	desc.Position = UDim2.new(0, UITheme.Space.m, 0, 62)
	desc.BackgroundTransparency = 1
	desc.Font = UITheme.Font.body
	desc.TextSize = UITheme.FontSize.micro
	desc.TextColor3 = UITheme.Color.textSecondary
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Text = mode.info
	desc.Parent = card

	-- Selected check indicator (bottom-right). Hidden when unselected.
	local checkLbl = Instance.new("TextLabel")
	checkLbl.Name = "Check"
	checkLbl.Size = UDim2.new(0, 70, 0, 14)
	checkLbl.AnchorPoint = Vector2.new(1, 1)
	checkLbl.Position = UDim2.new(1, -UITheme.Space.s, 1, -UITheme.Space.s)
	checkLbl.BackgroundTransparency = 1
	checkLbl.Font = UITheme.Font.heading
	checkLbl.TextSize = 10
	checkLbl.TextColor3 = mode.accent
	checkLbl.TextXAlignment = Enum.TextXAlignment.Right
	checkLbl.Text = "● SELECTED"
	checkLbl.Visible = false
	checkLbl.Parent = card

	card.MouseEnter:Connect(function()
		if currentModeIndex ~= i then
			stroke.Color = mode.accent
			stroke.Transparency = 0.5
		end
	end)
	card.MouseLeave:Connect(function()
		if currentModeIndex ~= i then
			stroke.Color = UITheme.Color.borderSubtle
			stroke.Transparency = 0.3
		end
	end)
	card.MouseButton1Click:Connect(function()
		selectMode(i)
		for j, c in modeCards do
			local check = c:FindFirstChild("Check") :: TextLabel?
			if check then check.Visible = (j == i) end
		end
	end)

	modeCards[i] = card
	modeStrokes[i] = stroke
	modeCardRefs[i] = { tag = tag, name = name, desc = desc, check = checkLbl }
end

selectMode(1)
local firstCheck = modeCards[1]:FindFirstChild("Check") :: TextLabel?
if firstCheck then firstCheck.Visible = true end

-- PLAY button — sized + positioned in applyResponsiveLayout() so it scales with
-- the mode card row. Mobile: 360x56, tablet: 440x64, desktop: matches card row
-- width × 72. Amber gradient ties into the armory/title theme.
local playBtn = Instance.new("TextButton")
playBtn.Size = UDim2.new(0, CARDS_TOTAL, 0, 72) -- refreshed below
playBtn.AnchorPoint = Vector2.new(0.5, 0)
playBtn.Position = UDim2.new(0.5, 0, 0, 220)
playBtn.BackgroundColor3 = Color3.fromRGB(210, 160, 70)
playBtn.BorderSizePixel = 0
playBtn.AutoButtonColor = false
playBtn.Font = UITheme.Font.display
playBtn.TextSize = UITheme.FontSize.h2 -- 28; bumped to 30 on desktop
playBtn.TextColor3 = Color3.fromRGB(28, 22, 14)
playBtn.Text = "▶  PLAY"
playBtn.Parent = centerCol

local playCorner = Instance.new("UICorner")
playCorner.CornerRadius = UDim.new(0, UITheme.Radius.md)
playCorner.Parent = playBtn

local playGradient = Instance.new("UIGradient")
playGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 110)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(195, 140, 50)),
})
playGradient.Rotation = 90
playGradient.Parent = playBtn

local playStroke = Instance.new("UIStroke")
playStroke.Color = Color3.fromRGB(255, 220, 140)
playStroke.Thickness = 2
playStroke.Parent = playBtn

playBtn.MouseEnter:Connect(function()
	playStroke.Thickness = 4
end)
playBtn.MouseLeave:Connect(function()
	playStroke.Thickness = 2
end)

-- ===== Side columns: secondary action buttons =====
-- Uniform slim dark cards. The previous design used rainbow saturated fills
-- (purple/orange/blue all at full chroma) which made the menu feel like an
-- arcade lobby; the redesign keeps a single muted dark base and lets each
-- button's accent show only on the left edge + hover stroke + icon tint.
type SideButton = { label: string, icon: string, accent: Color3, signal: string }

-- Side-button sizing is viewport-based (Studio Device Emulator-friendly).
-- Detection switched from TouchEnabled to ViewportSize.X because the emulator
-- doesn't always toggle TouchEnabled when simulating mobile viewports.
--   mobile (vw<700): 50x50 icon-only — shrunk from 70x56 after mobile audit;
--     iPhone 7 landscape (666x374) needs side buttons to occupy <55% of the
--     vertical column so PLAY button + mode cards fit without overlap. Glyph
--     size dropped to 22 (from 28) to feel proportional to the smaller chip.
--   tablet/desktop (vw>=700): 200x56 with label visible.
-- Note: getSideHeight() is dynamic too — mobile uses 50, prominent (56) elsewhere.
local SIDE_GAP_MOBILE = UITheme.Space.s -- 8
local SIDE_GAP_DESKTOP = UITheme.Space.m -- 12
local function getSideMetrics(): (number, number, number, number, number)
	-- Returns (width, height, edgeInset, iconSize, gap).
	if isMobileVP() then
		return 50, 50, UITheme.Space.s, 22, SIDE_GAP_MOBILE
	else
		return 200, UITheme.TouchTarget.prominent, UITheme.Space.x4l, 18, SIDE_GAP_DESKTOP
	end
end

type SideButtonRefs = {
	btn: TextButton,
	icon: TextLabel,
	label: TextLabel,
	anchor: Vector2,
	indexInCol: number,
	colSize: number,
}
local sideButtonRefs: { SideButtonRefs } = {}

local function makeSideButton(parent: Instance, def: SideButton, anchor: Vector2, indexInCol: number, colSize: number): TextButton
	local sideW, sideH, edgeInset, iconSize, _ = getSideMetrics()

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, sideW, 0, sideH)
	btn.AnchorPoint = anchor
	-- Y position computed by layout helper based on indexInCol/colSize
	btn.Position = UDim2.new(anchor.X, anchor.X == 0 and edgeInset or -edgeInset, 0.5, 0)
	btn.BackgroundColor3 = UITheme.Color.bgElevated
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UITheme.Radius.md)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Color.borderSubtle
	stroke.Thickness = 1
	stroke.Transparency = 0.2
	stroke.Parent = btn

	-- Left accent strip — the only colored element at rest
	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(0, 3, 1, -16)
	accentBar.Position = UDim2.new(0, 0, 0, 8)
	accentBar.BackgroundColor3 = def.accent
	accentBar.BorderSizePixel = 0
	accentBar.Parent = btn
	local ac = Instance.new("UICorner")
	ac.CornerRadius = UDim.new(0, 2)
	ac.Parent = accentBar

	-- Icon — sized + positioned in applyResponsiveLayout based on viewport.
	local iconLbl = Instance.new("TextLabel")
	iconLbl.BackgroundTransparency = 1
	iconLbl.Font = UITheme.Font.heading
	iconLbl.TextSize = iconSize
	iconLbl.TextColor3 = def.accent
	iconLbl.Text = def.icon
	iconLbl.Parent = btn

	-- Label (right side, white). Hidden on mobile.
	local labelLbl = Instance.new("TextLabel")
	labelLbl.BackgroundTransparency = 1
	labelLbl.Font = UITheme.Font.heading
	labelLbl.TextSize = UITheme.FontSize.caption + 1 -- 14
	labelLbl.TextColor3 = UITheme.Color.textPrimary
	labelLbl.TextXAlignment = Enum.TextXAlignment.Left
	labelLbl.Text = def.label
	labelLbl.Parent = btn

	-- Hover/press feedback: subtle accent stroke + bg shift. The accent stroke
	-- on hover gives glyph-only mobile buttons a clear "selected" cue.
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = UITheme.Color.bgHover
		stroke.Color = def.accent
		stroke.Transparency = 0
		stroke.Thickness = 2
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = UITheme.Color.bgElevated
		stroke.Color = UITheme.Color.borderSubtle
		stroke.Transparency = 0.2
		stroke.Thickness = 1
	end)

	btn.MouseButton1Click:Connect(function()
		ClientSignals.Get(def.signal):Fire()
	end)

	table.insert(sideButtonRefs, {
		btn = btn,
		icon = iconLbl,
		label = labelLbl,
		anchor = anchor,
		indexInCol = indexInCol,
		colSize = colSize,
	})

	return btn
end

-- Left column buttons (icons use simple typographic glyphs instead of emoji
-- so they render consistently across platforms)
local leftButtons: { SideButton } = {
	{ label = "LOADOUT",   icon = "▤", accent = Color3.fromRGB(110, 170, 230), signal = "OpenLoadout" },
	{ label = "COSMETICS", icon = "✦", accent = Color3.fromRGB(190, 130, 230), signal = "OpenCosmetics" },
	{ label = "MISSIONS",  icon = "✓", accent = Color3.fromRGB(230, 170, 90),  signal = "OpenMissions" },
}

for i, def in leftButtons do
	makeSideButton(screenGui, def, Vector2.new(0, 0.5), i, #leftButtons)
end

-- Right column buttons
local rightButtons: { SideButton } = {
	{ label = "SHOP",        icon = "$", accent = Color3.fromRGB(170, 130, 230), signal = "OpenShop" },
	{ label = "BATTLE PASS", icon = "★", accent = Color3.fromRGB(240, 190, 90),  signal = "OpenBP" },
	{ label = "SETTINGS",    icon = "⚙", accent = Color3.fromRGB(140, 155, 180), signal = "OpenSettings" },
}

for i, def in rightButtons do
	makeSideButton(screenGui, def, Vector2.new(1, 0.5), i, #rightButtons)
end

-- ============================================================
-- RESPONSIVE LAYOUT — recomputed at startup and whenever viewport changes.
-- All sizing decisions live here so designers can tweak breakpoints in one
-- place. Uses viewport.X (Studio Device Emulator-friendly), NOT TouchEnabled.
-- ============================================================
local function applyResponsiveLayout()
	local mobile = isMobileVP()
	local tablet = isTabletVP()

	-- Title size: 28 mobile / 40 tablet / 60 desktop. Mobile shrunk from h1=36
	-- to h2=28 after audit — at 666x374 the h1 dominated ~22% of vertical space.
	-- Subtitle dropped to micro+hidden-leading-padding for similar reason.
	if mobile then
		title.TextSize = UITheme.FontSize.h2 -- 28
		title.Size = UDim2.new(0, math.min(560, getViewportW() - 80), 0, 36)
		title.Position = UDim2.new(0.5, 0, 0, UITheme.Space.s) -- 8px from top
		subtitle.Position = UDim2.new(0.5, 0, 0, UITheme.Space.s + 32)
		subtitle.TextSize = UITheme.FontSize.micro
	elseif tablet then
		title.TextSize = 40
		title.Size = UDim2.new(0, 600, 0, 52)
		title.Position = UDim2.new(0.5, 0, 0, UITheme.Space.xl)
		subtitle.Position = UDim2.new(0.5, 0, 0, UITheme.Space.xl + 48)
		subtitle.TextSize = UITheme.FontSize.caption
	else
		title.TextSize = 60
		title.Size = UDim2.new(0, 600, 0, 80)
		title.Position = UDim2.new(0.5, 0, 0, 40)
		subtitle.Position = UDim2.new(0.5, 0, 0, 115)
		subtitle.TextSize = UITheme.FontSize.caption + 1
	end

	-- Recompute card dimensions
	local cw, ch, gap = getCardDims()
	CARD_WIDTH, CARD_HEIGHT, CARD_GAP = cw, ch, gap
	CARDS_TOTAL = #MODES * CARD_WIDTH + (#MODES - 1) * CARD_GAP

	-- Center column size + offset — narrower on mobile so it sits above PLAY
	-- without colliding with edge-pinned side buttons. Mobile: card_h(80) +
	-- gap(32) + PLAY_h(48) = 160; tablet/desktop unchanged from prior layout.
	local colHeight = ch + (mobile and 80 or 100) -- card height + space for PLAY
	centerCol.Size = UDim2.new(0, CARDS_TOTAL + 24, 0, colHeight + (mobile and 32 or 60))
	-- Shift center column down on mobile so it clears the title block above
	-- (title bottom ~46) and the rank chip (~y=84 top-left). Centered-y with a
	-- small bias keeps PLAY visible above the player/version labels at bottom.
	centerCol.Position = UDim2.new(0.5, 0, 0.5, mobile and 20 or -10)

	-- Re-lay each mode card + its labels. Cards start closer to section label on
	-- mobile (y=22) than desktop (y=32) — the section label is smaller and the
	-- vertical budget is tight at 374px viewport height.
	local cardTopY = mobile and 22 or 32
	for i, card in modeCards do
		card.Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
		card.Position = UDim2.new(0.5, -CARDS_TOTAL / 2 + (i - 1) * (CARD_WIDTH + CARD_GAP), 0, cardTopY)

		local refs = modeCardRefs[i]
		if refs then
			-- Tag (small caption)
			refs.tag.Size = UDim2.new(1, -UITheme.Space.xxl, 0, 14)
			refs.tag.Position = UDim2.new(0, UITheme.Space.m, 0, mobile and UITheme.Space.s or UITheme.Space.m)
			refs.tag.TextSize = mobile and 9 or 10

			-- Name — keep readable: 16 mobile / 20 tablet / 24 desktop
			local nameSize = mobile and 16 or (tablet and 20 or 24)
			refs.name.Size = UDim2.new(1, -UITheme.Space.xxl, 0, mobile and 22 or 28)
			refs.name.Position = UDim2.new(0, UITheme.Space.m, 0, mobile and 22 or 28)
			refs.name.TextSize = nameSize

			-- Description: hidden on mobile (no room), small wrap on tablet+
			if mobile then
				refs.desc.Visible = false
			else
				refs.desc.Visible = true
				refs.desc.Size = UDim2.new(1, -UITheme.Space.xxl, 0, CARD_HEIGHT - 70)
				refs.desc.Position = UDim2.new(0, UITheme.Space.m, 0, 56)
				refs.desc.TextSize = tablet and 11 or 12
			end

			refs.check.TextSize = mobile and 9 or 10
		end
	end

	-- PLAY button — mobile 280x48, tablet 380x60, desktop matches card row x 72.
	-- Mobile shrunk from 360x56 → 280x48 after audit: at 666x374, the previous
	-- size pushed PLAY into the side-button vertical column. 280 still gives a
	-- generous tap target while leaving comfortable padding from the cards above.
	local playW, playH, playTextSize
	if mobile then
		playW, playH, playTextSize = math.min(280, CARDS_TOTAL), 48, UITheme.FontSize.body
	elseif tablet then
		playW, playH, playTextSize = math.min(380, CARDS_TOTAL), 60, UITheme.FontSize.bodyLg
	else
		playW, playH, playTextSize = CARDS_TOTAL, 72, 30
	end
	playBtn.Size = UDim2.new(0, playW, 0, playH)
	playBtn.Position = UDim2.new(0.5, 0, 0, CARD_HEIGHT + (mobile and UITheme.Space.x3l or 60))
	playBtn.TextSize = playTextSize

	-- Side buttons — width, height, icon size, label visibility, position.
	-- Height is dynamic (50 mobile / 56 desktop) so the 3-button column on
	-- mobile shrinks from 192px tall → 166px, freeing vertical space for the
	-- center column without clipping the player/version labels at the bottom.
	local sideW, sideH, edgeInset, iconSize, sideGap = getSideMetrics()
	for _, ref in sideButtonRefs do
		ref.btn.Size = UDim2.new(0, sideW, 0, sideH)
		local yOffset = -((ref.colSize - 1) * (sideH + sideGap)) / 2 + (ref.indexInCol - 1) * (sideH + sideGap)
		if ref.anchor.X == 0 then
			ref.btn.Position = UDim2.new(0, edgeInset, 0.5, yOffset)
		else
			ref.btn.Position = UDim2.new(1, -edgeInset, 0.5, yOffset)
		end

		ref.icon.TextSize = iconSize
		if mobile then
			-- Icon-only, centered to fill the narrow button
			ref.icon.Size = UDim2.new(1, 0, 1, 0)
			ref.icon.Position = UDim2.new(0, 0, 0, 0)
			ref.icon.TextXAlignment = Enum.TextXAlignment.Center
			ref.label.Visible = false
		else
			-- Icon left, label right
			ref.icon.Size = UDim2.new(0, 32, 1, 0)
			ref.icon.Position = UDim2.new(0, UITheme.Space.m, 0, 0)
			ref.icon.TextXAlignment = Enum.TextXAlignment.Center
			ref.label.Size = UDim2.new(1, -58, 1, 0)
			ref.label.Position = UDim2.new(0, 50, 0, 0)
			ref.label.Visible = true
		end
	end
end

applyResponsiveLayout()

-- Re-run on viewport changes so toggling Studio Device Emulator (and real
-- device rotation) updates the layout live.
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
end

-- Player name at bottom-left — hidden on mobile to keep the menu uncluttered
-- (the side button column already occupies the left edge below center)
local playerLabel = Instance.new("TextLabel")
playerLabel.Size = UDim2.new(0, 300, 0, 24)
playerLabel.AnchorPoint = Vector2.new(0, 1)
playerLabel.Position = UDim2.new(0, 30, 1, -30)
playerLabel.BackgroundTransparency = 1
playerLabel.Font = Enum.Font.Gotham
playerLabel.TextSize = 14
playerLabel.TextColor3 = Color3.fromRGB(150, 160, 180)
playerLabel.TextXAlignment = Enum.TextXAlignment.Left
playerLabel.Text = "▸ " .. player.Name
playerLabel.Parent = screenGui

-- Version label bottom-right
local versionLabel = Instance.new("TextLabel")
versionLabel.Size = UDim2.new(0, 200, 0, 20)
versionLabel.AnchorPoint = Vector2.new(1, 1)
versionLabel.Position = UDim2.new(1, -30, 1, -30)
versionLabel.BackgroundTransparency = 1
versionLabel.Font = Enum.Font.Gotham
versionLabel.TextSize = 12
versionLabel.TextColor3 = Color3.fromRGB(90, 100, 120)
versionLabel.TextXAlignment = Enum.TextXAlignment.Right
versionLabel.Text = "v0.1 — early dev"
versionLabel.Parent = screenGui

-- Hide chrome labels on mobile — at 666x374 the side button column edges sit
-- close to the corner labels and they end up visually overlapping. Player name
-- + version are non-essential context that the player can see in the settings
-- menu anyway.
local function refreshChromeVisibility()
	local mobile = isMobileVP()
	playerLabel.Visible = not mobile
	versionLabel.Visible = not mobile
end
refreshChromeVisibility()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshChromeVisibility)
end

-- ===== Scriptable cinematic camera =====
local function setupMenuCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	-- Position high above lobby looking down at angle
	local startTime = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not screenGui.Enabled then
			conn:Disconnect()
			return
		end
		local t = os.clock() - startTime
		local angle = t * 0.1 -- slow rotation
		local radius = 80
		local height = 40
		local cx = math.cos(angle) * radius
		local cz = math.sin(angle) * radius
		camera.CFrame = CFrame.lookAt(
			Vector3.new(cx, height, cz),
			Vector3.new(0, 5, 0)
		)
	end)
end

setupMenuCamera()

-- Free cursor (so user can click UI)
UserInputService.MouseBehavior = Enum.MouseBehavior.Default
UserInputService.MouseIconEnabled = true

-- ===== Show / Hide menu =====
local function hideMenu()
	local tween = TweenService:Create(backdrop, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
	tween:Play()
	TweenService:Create(title, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	for _, child in screenGui:GetChildren() do
		if child:IsA("GuiObject") and child ~= backdrop then
			TweenService:Create(child, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			if child:IsA("TextButton") or child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			end
		end
	end
	task.wait(0.4)
	screenGui.Enabled = false
	camera.CameraType = Enum.CameraType.Custom
end

-- Restore menu state (called when player exits training back to menu)
local function showMenu()
	-- Reset PLAY button
	playBtn.Text = "▶  PLAY"
	playBtn.AutoButtonColor = false

	-- Restore backdrop + title transparencies
	backdrop.BackgroundTransparency = 0
	title.TextTransparency = 0
	title.TextStrokeTransparency = 0.4
	subtitle.TextTransparency = 0

	-- Restore all child transparencies
	for _, child in screenGui:GetChildren() do
		if child:IsA("GuiObject") and child ~= backdrop then
			child.BackgroundTransparency = (child:IsA("Frame") and child ~= backdrop) and 0 or child.BackgroundTransparency
			if child:IsA("TextButton") or child:IsA("TextLabel") then
				child.TextTransparency = 0
			end
		end
	end

	screenGui.Enabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	setupMenuCamera()
end

playBtn.MouseButton1Click:Connect(function()
	playBtn.Text = "LOADING..."
	playBtn.AutoButtonColor = false
	Remotes.RequestSpawn:FireServer(MODES[currentModeIndex].id)
	hideMenu()
end)

-- (mode selection now happens via the card click handlers above; no dropdown
-- cycle button needed since all modes are visible at once.)

-- ===== Training-mode exit (M key) =====
local isTrainingMode = false

Remotes.EnterTrainingMode.OnClientEvent:Connect(function(active: boolean)
	isTrainingMode = active == true
	if not active then
		-- Server exited training (probably via ExitToMainMenu request) — show menu
		task.wait(0.1)
		showMenu()
	end
end)

-- ============================================================
-- WAITING / SPECTATOR OVERLAY
-- Shown when player picked a mode but match isn't running their mode yet (or
-- they're between rounds in casual). Camera scriptable-orbits a random alive
-- character so they're spectating the live action, not staring at a static UI.
-- ============================================================
local waitingGui = Instance.new("ScreenGui")
waitingGui.Name = "ModeWaitingOverlay"
waitingGui.ResetOnSpawn = false
waitingGui.IgnoreGuiInset = true
waitingGui.DisplayOrder = 200
waitingGui.Enabled = false
waitingGui.Parent = playerGui

-- Thin top + bottom bars (CS-style "spectating" letterbox) so camera is the main view
local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 60)
topBar.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
topBar.BackgroundTransparency = 0.15
topBar.BorderSizePixel = 0
topBar.Parent = waitingGui

local bottomBar = Instance.new("Frame")
bottomBar.Size = UDim2.new(1, 0, 0, 110)
bottomBar.AnchorPoint = Vector2.new(0, 1)
bottomBar.Position = UDim2.new(0, 0, 1, 0)
bottomBar.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
bottomBar.BackgroundTransparency = 0.15
bottomBar.BorderSizePixel = 0
bottomBar.Parent = waitingGui

local waitTag = Instance.new("TextLabel")
waitTag.Size = UDim2.new(1, -40, 0, 16)
waitTag.Position = UDim2.new(0, 20, 0, 10)
waitTag.BackgroundTransparency = 1
waitTag.Font = Enum.Font.GothamBold
waitTag.TextSize = 12
waitTag.TextColor3 = Color3.fromRGB(210, 160, 80)
waitTag.TextXAlignment = Enum.TextXAlignment.Center
waitTag.Text = "SPECTATING — WAITING TO JOIN"
waitTag.Parent = topBar

local waitTitle = Instance.new("TextLabel")
waitTitle.Size = UDim2.new(1, -40, 0, 30)
waitTitle.Position = UDim2.new(0, 20, 0, 26)
waitTitle.BackgroundTransparency = 1
waitTitle.Font = Enum.Font.GothamBlack
waitTitle.TextSize = 22
waitTitle.TextColor3 = Color3.fromRGB(245, 245, 250)
waitTitle.TextXAlignment = Enum.TextXAlignment.Center
waitTitle.Text = "Joining next round..."
waitTitle.Parent = topBar

local waitDesc = Instance.new("TextLabel")
waitDesc.Size = UDim2.new(1, -40, 0, 36)
waitDesc.Position = UDim2.new(0, 20, 0, 14)
waitDesc.BackgroundTransparency = 1
waitDesc.Font = Enum.Font.Gotham
waitDesc.TextSize = 13
waitDesc.TextColor3 = Color3.fromRGB(170, 180, 200)
waitDesc.TextXAlignment = Enum.TextXAlignment.Center
waitDesc.TextYAlignment = Enum.TextYAlignment.Top
waitDesc.TextWrapped = true
waitDesc.Text = "Lo lagi nonton match yang jalan. Pas ronde berikutnya mulai lo auto spawn."
waitDesc.Parent = bottomBar

local waitCancelBtn = Instance.new("TextButton")
waitCancelBtn.Size = UDim2.new(0, 200, 0, 36)
waitCancelBtn.AnchorPoint = Vector2.new(0.5, 1)
waitCancelBtn.Position = UDim2.new(0.5, 0, 1, -20)
waitCancelBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
waitCancelBtn.BorderSizePixel = 0
waitCancelBtn.AutoButtonColor = false
waitCancelBtn.Font = Enum.Font.GothamBold
waitCancelBtn.TextSize = 14
waitCancelBtn.TextColor3 = Color3.fromRGB(245, 245, 250)
waitCancelBtn.Text = "Cancel (M) — back to menu"
waitCancelBtn.Parent = bottomBar
local waitCancelCorner = Instance.new("UICorner"); waitCancelCorner.CornerRadius = UDim.new(0, 8); waitCancelCorner.Parent = waitCancelBtn

-- ============================================================
-- SPECTATOR CAMERA
-- Picks a random alive character (player or bot model in workspace) every 5s
-- and orbits it. Falls back to a static aerial view of dust2 origin if nothing
-- alive. Active only while waitingGui.Enabled.
-- ============================================================
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local spectateTarget: BasePart? = nil
local spectateOrbitAngle = 0
local nextTargetSwapAt = 0

local function pickSpectatorTarget(): BasePart?
	local candidates: { BasePart } = {}
	-- Player characters
	for _, p in Players:GetPlayers() do
		if p == player then continue end
		local char = p.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and hum.Health > 0 and hrp then
			table.insert(candidates, hrp)
		end
	end
	-- Bots (models with IsBot attribute OR named with _T/_CT suffix from CasualBotService)
	for _, m in Workspace:GetChildren() do
		if not m:IsA("Model") then continue end
		if m == player.Character then continue end
		local hum = m:FindFirstChildOfClass("Humanoid")
		local hrp = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and hum.Health > 0 and hrp then
			-- Heuristic: it's a bot if it has IsBot attr OR name contains _T/_CT
			if m:GetAttribute("IsBot") or string.find(m.Name, "_T%d") or string.find(m.Name, "_CT%d") then
				table.insert(candidates, hrp)
			end
		end
	end
	if #candidates == 0 then return nil end
	return candidates[math.random(#candidates)]
end

local spectatorActive = false
RunService:BindToRenderStep("SpectatorCam", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if not spectatorActive then return end
	local now = os.clock()
	-- Swap target every 5s OR if current target dies / disappears
	local needSwap = now >= nextTargetSwapAt
	if spectateTarget then
		local parent = spectateTarget.Parent
		if not parent or not parent.Parent then needSwap = true end
		if parent then
			local hum = parent:FindFirstChildOfClass("Humanoid") :: Humanoid?
			if not hum or hum.Health <= 0 then needSwap = true end
		end
	else
		needSwap = true
	end
	if needSwap then
		spectateTarget = pickSpectatorTarget()
		nextTargetSwapAt = now + 5
	end
	if spectateTarget then
		spectateOrbitAngle += dt * 0.25 -- slow orbit
		local radius = 14
		local height = 6
		local pivot = spectateTarget.Position
		local camPos = pivot + Vector3.new(math.cos(spectateOrbitAngle) * radius, height, math.sin(spectateOrbitAngle) * radius)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(camPos, pivot + Vector3.new(0, 2, 0))
	else
		-- No targets — slow aerial pan over arena origin
		spectateOrbitAngle += dt * 0.15
		local origin = Vector3.new(0, 130, 0) -- arena built ~Y=100, look down from above
		local camPos = origin + Vector3.new(math.cos(spectateOrbitAngle) * 80, 50, math.sin(spectateOrbitAngle) * 80)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(camPos, origin)
	end
end)

local function stopSpectator()
	spectatorActive = false
	spectateTarget = nil
	if camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
end

waitCancelBtn.MouseButton1Click:Connect(function()
	Remotes.ExitToMainMenu:FireServer()
	waitingGui.Enabled = false
	stopSpectator()
	task.wait(0.15)
	showMenu()
end)

Remotes.CasualWaitingForMatch.OnClientEvent:Connect(function(payload: any)
	-- Payload back-compat: server may send boolean OR { waiting, mode, activeMatch }
	local waiting: boolean
	local pMode: string? = nil
	local pActive: boolean = false
	if typeof(payload) == "boolean" then
		waiting = payload
	elseif typeof(payload) == "table" then
		waiting = payload.waiting == true
		pMode = payload.mode
		pActive = payload.activeMatch == true
	else
		waiting = false
	end

	waitingGui.Enabled = waiting
	if waiting then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		spectatorActive = true
		nextTargetSwapAt = 0 -- force immediate target pick
		-- Customize text per mode
		if pMode == "deathmatch" then
			waitTag.Text = "SPECTATING — WAITING FOR DEATHMATCH"
			waitTag.TextColor3 = Color3.fromRGB(220, 100, 80)
			waitTitle.Text = if pActive then "Joining active deathmatch..." else "Waiting for next DM match..."
			waitDesc.Text = "Lo lagi nonton match. Pas DM match berikutnya mulai lo auto spawn."
		else
			waitTag.Text = "SPECTATING — JOINING NEXT ROUND"
			waitTag.TextColor3 = Color3.fromRGB(210, 160, 80)
			waitTitle.Text = if pActive then "Joining next round..." else "Waiting for next casual match..."
			waitDesc.Text = "Lo lagi nonton match. Pas ronde berikutnya mulai lo nggantiin satu bot dan spawn di team spawn."
		end
	else
		stopSpectator()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	-- M = exit current session (training OR deathmatch OR casual wait) and return to main menu
	if input.KeyCode == Enum.KeyCode.M then
		Remotes.ExitToMainMenu:FireServer()
		waitingGui.Enabled = false
		stopSpectator()
		task.wait(0.15)
		showMenu()
	end
end)

return MainMenuController
