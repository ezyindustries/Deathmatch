--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local WeaponConfig = require(Shared.Modules.WeaponConfig)
local MatchState = require(Shared.Modules.MatchState)
local ClientSignals = require(Shared.Modules.ClientSignals)

local LoadoutController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadoutHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false  -- modal: let Roblox auto-shift below the topbar (Unibar) so title isnt covered
screenGui.DisplayOrder = 150
screenGui.Parent = playerGui

-- Loadout button (left side, below daily/health area)
local button = Instance.new("TextButton")
button.Size = UDim2.new(0, 140, 0, 36)
button.AnchorPoint = Vector2.new(0, 1)
button.Position = UDim2.new(0, 24, 1, -188)
button.BackgroundColor3 = Color3.fromRGB(60, 90, 160)
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.Font = Enum.Font.GothamBold
button.TextSize = 13
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Text = "Loadout"
button.Visible = false -- access via MainMenu/PauseMenu
button.Parent = screenGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = button

-- Overlay (clickable TextButton → tap outside the panel closes the modal).
local overlay = Instance.new("TextButton")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.Visible = false
overlay.BorderSizePixel = 0
overlay.AutoButtonColor = false
overlay.Text = ""
overlay.Parent = screenGui

local Workspace = game:GetService("Workspace")

-- Panel (TextButton too, so clicks on it DON'T bubble to overlay = no accidental close)
local panel = Instance.new("TextButton")
panel.Size = UDim2.new(0, 700, 0, 540)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
panel.BorderSizePixel = 0
panel.AutoButtonColor = false
panel.Text = ""
panel.Parent = overlay

-- Auto-scale based on viewport width (mobile screens get smaller modal).
-- IMPORTANT: scale must be parented to `panel`, NOT `overlay`. Putting it on
-- the overlay shrinks the overlay's tap area too, so taps in the now-uncovered
-- bottom/right of the screen on mobile didn't trigger the outside-click close.
-- Mobile scale tightened from 0.65 → 0.55 so the 700x540 panel renders as
-- 385x297 — fits comfortably within 666x374 with margin for the close button
-- + visible backdrop tap-target outside the modal.
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel
local function refreshPanelScale()
	local vw = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X or 1920
	if vw < 900 then panelScale.Scale = 0.55
	elseif vw < 1300 then panelScale.Scale = 0.8
	else panelScale.Scale = 1.0 end
end
refreshPanelScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshPanelScale)
end

-- Tap outside panel = close (overlay click fires; panel absorbs its own clicks)
overlay.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 32)
title.Position = UDim2.new(0, 20, 0, 16)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(110, 180, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Loadout"
title.Parent = panel

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -40, 0, 18)
hint.Position = UDim2.new(0, 20, 0, 48)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.TextColor3 = Color3.fromRGB(170, 175, 195)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "Pick one primary and one secondary. Changes apply next match."
hint.Parent = panel

-- Circular X close button — 44px tap target (meets mobile touch guidelines),
-- unambiguous icon vs the old "Close" text label that users missed on mobile.
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 44, 0, 44)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -14, 0, 14)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = true
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "✕"
closeBtn.Parent = panel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(1, 0) -- circular
closeCorner.Parent = closeBtn

closeBtn.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)
button.MouseButton1Click:Connect(function()
	overlay.Visible = true
end)

local TIER_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(180, 180, 180),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(200, 80, 255),
	Legendary = Color3.fromRGB(255, 180, 60),
}

-- Asset IDs for weapon preview images. Keyed by weapon.id (see WeaponConfig).
-- When an entry exists here, the image renders in the card; otherwise the
-- procedural silhouette below is drawn instead. Add entries here once weapon
-- art is uploaded to Roblox as proper Image assets (not Decals).
local WEAPON_ICONS: { [string]: string } = {
	-- smg = "rbxassetid://...", -- UMP-45 image upload didn't render (Decal issue)
}

-- =====================================================================
-- PROCEDURAL WEAPON SILHOUETTES
-- Each drawer renders a tactical-icon style silhouette of the weapon into a
-- 200×96 image area using stacked Frames + UIGradients. Style: flat dark
-- shapes + light highlights + tier-color outline accent. Barrel always points
-- LEFT so weapons read consistently across the loadout.
-- =====================================================================
local function mkRect(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, rotation: number?, cornerRadius: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, x, 0.5, y)
	f.Size = UDim2.new(0, w, 0, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rotation or 0
	f.Parent = parent
	if cornerRadius and cornerRadius > 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, cornerRadius)
		c.Parent = f
	end
	return f
end

local function drawAK(parent: Instance, accent: Color3)
	local wood = Color3.fromRGB(120, 78, 42)
	local woodDark = Color3.fromRGB(85, 55, 30)
	local metal = Color3.fromRGB(38, 40, 48)
	local metalLight = Color3.fromRGB(58, 60, 70)
	-- Wood foregrip (left under barrel)
	mkRect(parent, -32, 6, 30, 8, wood, 0, 2)
	-- Barrel
	mkRect(parent, -50, -2, 36, 4, metal, 0, 1)
	-- Front sight post
	mkRect(parent, -60, -8, 4, 8, metal, 0, 1)
	-- Muzzle brake
	mkRect(parent, -70, -2, 8, 6, metalLight, 0, 1)
	-- Gas tube (above receiver)
	mkRect(parent, -12, -8, 36, 4, metal, 0, 1)
	-- Receiver (main body)
	mkRect(parent, -2, 0, 56, 16, metalLight, 0, 2)
	-- Iconic banana magazine (curved approximation: angled rect)
	mkRect(parent, -8, 20, 14, 30, metal, -12, 2)
	mkRect(parent, -2, 28, 14, 22, metal, -18, 2)
	-- Pistol grip
	mkRect(parent, 12, 16, 8, 18, woodDark, -8, 2)
	-- Trigger guard
	mkRect(parent, 10, 12, 14, 4, metal, 0, 1)
	-- Wooden stock
	mkRect(parent, 42, 0, 36, 14, wood, 0, 3)
	-- Stock highlight
	mkRect(parent, 42, -2, 32, 2, Color3.fromRGB(160, 110, 60), 0, 1)
end

local function drawAWP(parent: Instance, accent: Color3)
	local body = Color3.fromRGB(55, 65, 55)
	local bodyDark = Color3.fromRGB(35, 42, 35)
	local metal = Color3.fromRGB(40, 42, 48)
	-- Very long barrel
	mkRect(parent, -50, -4, 70, 4, metal, 0, 1)
	-- Muzzle
	mkRect(parent, -86, -4, 6, 8, metal, 0, 1)
	-- Bipod (folded V below barrel)
	mkRect(parent, -40, 8, 3, 12, metal, -25, 0)
	mkRect(parent, -36, 8, 3, 12, metal, 25, 0)
	-- Bolt handle bump on top of receiver
	mkRect(parent, 4, -10, 8, 6, metal, 0, 1)
	-- Scope mount rail
	mkRect(parent, 0, -14, 40, 3, metal, 0, 0)
	-- Scope
	mkRect(parent, 0, -22, 40, 10, bodyDark, 0, 3)
	-- Scope lens (front)
	mkRect(parent, -22, -22, 4, 12, Color3.fromRGB(120, 180, 200), 0, 1)
	-- Scope lens (rear)
	mkRect(parent, 22, -22, 4, 10, Color3.fromRGB(120, 180, 200), 0, 1)
	-- Receiver
	mkRect(parent, 0, -2, 50, 14, body, 0, 2)
	-- Pistol grip
	mkRect(parent, 14, 14, 10, 16, bodyDark, -10, 2)
	-- Trigger guard
	mkRect(parent, 12, 10, 14, 4, metal, 0, 1)
	-- Thumbhole stock
	mkRect(parent, 44, 0, 40, 18, body, 0, 4)
	-- Stock thumbhole cutout (darker)
	mkRect(parent, 44, 0, 14, 10, bodyDark, 0, 3)
	-- Cheek riser highlight
	mkRect(parent, 44, -8, 32, 2, Color3.fromRGB(85, 100, 85), 0, 1)
end

local function drawUMP(parent: Instance, accent: Color3)
	local body = Color3.fromRGB(38, 40, 48)
	local bodyLight = Color3.fromRGB(58, 60, 70)
	local metal = Color3.fromRGB(28, 30, 36)
	-- Barrel shroud
	mkRect(parent, -36, -2, 16, 8, body, 0, 1)
	-- Muzzle / suppressor
	mkRect(parent, -52, -2, 14, 8, metal, 0, 1)
	-- Top rail
	mkRect(parent, -14, -10, 44, 4, metal, 0, 0)
	-- Iron sight bump on rail
	mkRect(parent, 8, -14, 4, 4, metal, 0, 0)
	-- Receiver
	mkRect(parent, -10, 0, 50, 18, body, 0, 2)
	-- Receiver highlight
	mkRect(parent, -10, -6, 46, 2, bodyLight, 0, 1)
	-- Vertical .45 ACP magazine
	mkRect(parent, -16, 22, 10, 28, metal, 0, 1)
	-- Pistol grip
	mkRect(parent, 12, 18, 10, 18, body, -8, 2)
	-- Trigger guard
	mkRect(parent, 10, 12, 12, 4, metal, 0, 1)
	-- Folding stock (folded right)
	mkRect(parent, 42, 0, 40, 12, body, 0, 2)
	-- Stock cutout (gives the H&K look)
	mkRect(parent, 42, 0, 28, 5, Color3.fromRGB(20, 22, 28), 0, 1)
end

local function drawGlock(parent: Instance, accent: Color3)
	local body = Color3.fromRGB(38, 40, 48)
	local bodyDark = Color3.fromRGB(22, 24, 30)
	local metal = Color3.fromRGB(28, 30, 36)
	-- Slide (top half)
	mkRect(parent, -10, -8, 60, 12, body, 0, 2)
	-- Slide serrations (right side)
	mkRect(parent, 12, -8, 14, 2, bodyDark, 0, 0)
	mkRect(parent, 12, -10, 14, 1, Color3.fromRGB(55, 58, 70), 0, 0)
	-- Barrel sticking out
	mkRect(parent, -42, -8, 8, 6, metal, 0, 1)
	-- Front sight
	mkRect(parent, -34, -16, 3, 4, metal, 0, 0)
	-- Rear sight
	mkRect(parent, 16, -16, 4, 4, metal, 0, 0)
	-- Frame (under slide)
	mkRect(parent, -10, 0, 58, 8, bodyDark, 0, 1)
	-- Trigger guard (rounded)
	mkRect(parent, -6, 6, 18, 8, body, 0, 4)
	mkRect(parent, -6, 8, 14, 4, Color3.fromRGB(22, 24, 30), 0, 2)
	-- Grip (angled down)
	mkRect(parent, 4, 18, 16, 28, body, -6, 3)
	-- Grip stippling texture (suggestion)
	mkRect(parent, 4, 18, 12, 24, Color3.fromRGB(30, 32, 38), -6, 2)
	-- Magazine baseplate (peeking out bottom)
	mkRect(parent, 4, 34, 14, 4, metal, -6, 1)
end

local function drawKnife(parent: Instance, accent: Color3)
	local steel = Color3.fromRGB(200, 205, 215)
	local steelDark = Color3.fromRGB(140, 145, 160)
	local handle = Color3.fromRGB(50, 35, 25)
	local handleHl = Color3.fromRGB(80, 55, 35)
	-- Blade (angled diagonal slash for dynamic look)
	mkRect(parent, -22, -4, 70, 10, steel, -8, 1)
	-- Blade highlight (top edge)
	mkRect(parent, -22, -8, 64, 2, Color3.fromRGB(240, 245, 250), -8, 0)
	-- Blade fuller (groove down the middle)
	mkRect(parent, -22, -3, 56, 1, steelDark, -8, 0)
	-- Tip (small triangle pointing left, via small rotated square)
	mkRect(parent, -58, -10, 8, 8, steel, 35, 0)
	-- Crossguard (perpendicular bar between blade and handle)
	mkRect(parent, 16, 0, 4, 22, Color3.fromRGB(90, 92, 100), 0, 1)
	-- Handle
	mkRect(parent, 36, 6, 32, 14, handle, -4, 3)
	-- Handle highlight
	mkRect(parent, 36, 3, 28, 2, handleHl, -4, 1)
	-- Grip ridges (3 small lines)
	mkRect(parent, 28, 6, 1, 12, Color3.fromRGB(30, 22, 16), -4, 0)
	mkRect(parent, 36, 6, 1, 12, Color3.fromRGB(30, 22, 16), -4, 0)
	mkRect(parent, 44, 6, 1, 12, Color3.fromRGB(30, 22, 16), -4, 0)
	-- Pommel
	mkRect(parent, 56, 10, 6, 14, Color3.fromRGB(90, 92, 100), -4, 2)
end

local WEAPON_DRAWERS: { [string]: (Instance, Color3) -> () } = {
	rifle  = drawAK,
	sniper = drawAWP,
	smg    = drawUMP,
	pistol = drawGlock,
	knife  = drawKnife,
}

-- =====================================================================
-- PREMIUM IMAGE-AREA BACKDROP
-- Adds tier-color glow + corner vignette + animated sheen sweep behind the
-- weapon silhouette. This is what makes the card look polished vs flat.
-- =====================================================================
local function setupImageBackdrop(imageArea: Frame, tierColor: Color3)
	-- Tier-color soft glow — wide ellipse behind the weapon, low-opacity fill
	-- that fades to nothing at edges via gradient. Gives a "spotlight on the
	-- weapon" feel matched to the weapon's rarity color.
	local glow = Instance.new("Frame")
	glow.Name = "TierGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0.5, 0)
	glow.Size = UDim2.new(1, 40, 1, 40)
	glow.BackgroundColor3 = tierColor
	glow.BackgroundTransparency = 0.75
	glow.BorderSizePixel = 0
	glow.ZIndex = 0
	glow.Parent = imageArea
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0) -- ellipse
	glowCorner.Parent = glow
	local glowGrad = Instance.new("UIGradient")
	-- Horizontal fade: full color in middle, transparent at sides
	glowGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	glowGrad.Parent = glow

	-- Corner vignette — dark gradient overlay on corners so the spotlight
	-- effect is reinforced (light center, dark edges).
	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.new(1, 0, 1, 0)
	vignette.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	vignette.BackgroundTransparency = 0.5
	vignette.BorderSizePixel = 0
	vignette.ZIndex = 1
	vignette.Parent = imageArea
	local vGrad = Instance.new("UIGradient")
	vGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0.4),
	})
	vGrad.Rotation = 0
	vGrad.Parent = vignette

	-- Animated sheen — thin diagonal highlight that sweeps across the card
	-- every few seconds. Subtle but adds life to an otherwise static UI.
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.AnchorPoint = Vector2.new(0, 0.5)
	sheen.Size = UDim2.new(0, 40, 1.4, 0)
	sheen.Position = UDim2.new(0, -50, 0.5, 0)
	sheen.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sheen.BackgroundTransparency = 0.88
	sheen.BorderSizePixel = 0
	sheen.Rotation = 18
	sheen.ZIndex = 20
	sheen.Parent = imageArea
	local sheenGrad = Instance.new("UIGradient")
	sheenGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sheenGrad.Rotation = 90
	sheenGrad.Parent = sheen

	-- Loop: sweep every 6 seconds (staggered start so all 5 cards don't sync)
	task.spawn(function()
		task.wait(math.random() * 2) -- random initial offset
		while sheen.Parent do
			sheen.Position = UDim2.new(0, -50, 0.5, 0)
			local tween = TweenService:Create(
				sheen,
				TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Position = UDim2.new(1, 50, 0.5, 0) }
			)
			tween:Play()
			tween.Completed:Wait()
			task.wait(4 + math.random() * 2) -- 4-6s pause between sweeps
		end
	end)

	-- Subtle tier-glow pulse — slow breathing so the card feels "alive"
	task.spawn(function()
		local t0 = os.clock() + math.random() * 3.14
		while glow.Parent do
			local t = os.clock() - t0
			glow.BackgroundTransparency = 0.75 + math.sin(t * 1.2) * 0.08
			task.wait(0.05)
		end
	end)
end

type SlotRow = { sectionLabel: TextLabel, cards: { [string]: TextButton } }
local slots: { primary: SlotRow, secondary: SlotRow } = { primary = { cards = {} }, secondary = { cards = {} } }

local currentSelection = { primary = "rifle", secondary = "pistol" }

local CARD_W = 200
local CARD_H = 170
local IMAGE_H = 96 -- top portion devoted to weapon preview image

local function makeWeaponCard(weapon: WeaponConfig.WeaponInfo, parent: Frame, layoutOrder: number): TextButton
	local tierColor = TIER_COLORS[weapon.tier] or Color3.fromRGB(180, 180, 180)
	local card = Instance.new("TextButton")
	card.Size = UDim2.new(0, CARD_W, 0, CARD_H)
	card.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.LayoutOrder = layoutOrder
	card.Parent = parent

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card

	-- Image area at top — lighter neutral bg so dark weapon art is visible
	local imageArea = Instance.new("Frame")
	imageArea.Size = UDim2.new(1, 0, 0, IMAGE_H)
	imageArea.BackgroundColor3 = Color3.fromRGB(55, 60, 75)
	imageArea.BorderSizePixel = 0
	imageArea.ClipsDescendants = true
	imageArea.Parent = card
	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(0, 10)
	imageCorner.Parent = imageArea
	local imageMaskBottom = Instance.new("Frame")
	imageMaskBottom.Size = UDim2.new(1, 0, 0, 12)
	imageMaskBottom.AnchorPoint = Vector2.new(0, 1)
	imageMaskBottom.Position = UDim2.new(0, 0, 1, 0)
	imageMaskBottom.BackgroundColor3 = Color3.fromRGB(55, 60, 75)
	imageMaskBottom.BorderSizePixel = 0
	imageMaskBottom.Parent = imageArea

	-- Premium backdrop: tier-color glow + vignette + animated sheen
	setupImageBackdrop(imageArea, tierColor)

	-- Container for the weapon silhouette — ZIndex above the backdrop layers
	-- so the gun reads cleanly on top of the glow
	local weaponLayer = Instance.new("Frame")
	weaponLayer.Size = UDim2.new(1, 0, 1, 0)
	weaponLayer.BackgroundTransparency = 1
	weaponLayer.ZIndex = 10
	weaponLayer.Parent = imageArea

	-- Render priority: uploaded image > procedural silhouette > text placeholder
	local iconAsset = WEAPON_ICONS[weapon.id]
	local drawer = WEAPON_DRAWERS[weapon.id]
	if iconAsset then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(1, -8, 1, -8)
		img.Position = UDim2.new(0, 4, 0, 4)
		img.BackgroundTransparency = 1
		img.Image = iconAsset
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = 10
		img.Parent = weaponLayer
	elseif drawer then
		drawer(weaponLayer, tierColor)
	else
		local placeholder = Instance.new("TextLabel")
		placeholder.Size = UDim2.new(1, 0, 1, 0)
		placeholder.BackgroundTransparency = 1
		placeholder.Font = Enum.Font.GothamBold
		placeholder.TextSize = 32
		placeholder.TextColor3 = Color3.fromRGB(60, 65, 80)
		placeholder.Text = string.upper(string.sub(weapon.displayName, 1, 3))
		placeholder.Parent = weaponLayer
	end

	-- Tier strip overlay at top of image area
	local tierStrip = Instance.new("Frame")
	tierStrip.Size = UDim2.new(1, 0, 0, 4)
	tierStrip.BackgroundColor3 = tierColor
	tierStrip.BorderSizePixel = 0
	tierStrip.ZIndex = 2
	tierStrip.Parent = imageArea

	-- Text area at bottom
	local textArea = Instance.new("Frame")
	textArea.Size = UDim2.new(1, 0, 0, CARD_H - IMAGE_H)
	textArea.Position = UDim2.new(0, 0, 0, IMAGE_H)
	textArea.BackgroundTransparency = 1
	textArea.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -16, 0, 20)
	nameLabel.Position = UDim2.new(0, 10, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromRGB(245, 245, 250)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = weapon.displayName
	nameLabel.Parent = textArea

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Size = UDim2.new(1, -16, 0, 12)
	tierLabel.Position = UDim2.new(0, 10, 0, 26)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Font = Enum.Font.GothamBold
	tierLabel.TextSize = 9
	tierLabel.TextColor3 = tierColor
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierLabel.Text = string.upper(weapon.tier)
	tierLabel.Parent = textArea

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(1, -16, 0, 14)
	statsLabel.Position = UDim2.new(0, 10, 0, 44)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.Gotham
	statsLabel.TextSize = 10
	statsLabel.TextColor3 = Color3.fromRGB(150, 160, 180)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.Text = string.format("DMG %d  •  RPS %.1f  •  MAG %d", weapon.damage, weapon.fireRate, weapon.magSize)
	statsLabel.Parent = textArea

	card.MouseButton1Click:Connect(function()
		currentSelection[weapon.slot] = weapon.id
		if weapon.slot == "primary" then
			Remotes.SetLoadout:FireServer(weapon.id, nil)
		else
			Remotes.SetLoadout:FireServer(nil, weapon.id)
		end
	end)

	return card
end

local function makeSection(slotName: string, position: UDim2): (Frame, TextLabel)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -40, 0, 200)
	row.Position = position
	row.BackgroundTransparency = 1
	row.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(170, 175, 195)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = slotName
	label.Parent = row

	local cardRow = Instance.new("Frame")
	cardRow.Size = UDim2.new(1, 0, 0, CARD_H + 4)
	cardRow.Position = UDim2.new(0, 0, 0, 24)
	cardRow.BackgroundTransparency = 1
	cardRow.Parent = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.Parent = cardRow

	return cardRow, label
end

local primaryRow, _ = makeSection("PRIMARY (1)", UDim2.new(0, 20, 0, 80))
local secondaryRow, _ = makeSection("SECONDARY (2)", UDim2.new(0, 20, 0, 300))

local order = 1
for _, weapon in WeaponConfig do
	if weapon.slot == "primary" then
		slots.primary.cards[weapon.id] = makeWeaponCard(weapon, primaryRow, order)
	else
		slots.secondary.cards[weapon.id] = makeWeaponCard(weapon, secondaryRow, order)
	end
	order += 1
end

local function refreshHighlight()
	for slot, slotData in slots do
		for id, card in slotData.cards do
			if id == currentSelection[slot] then
				card.BackgroundColor3 = Color3.fromRGB(60, 95, 140)
			else
				card.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
			end
		end
	end
end
refreshHighlight()

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	if data.loadout then
		currentSelection.primary = data.loadout.primary
		currentSelection.secondary = data.loadout.secondary
		refreshHighlight()
	end
end)

-- Loadout panel is openable any time (lobby, match, casual). Changes apply on
-- next spawn — the panel doesn't affect live combat, so there's no reason to
-- force-close it mid-match.

ClientSignals.Get("OpenLoadout").Event:Connect(function()
	overlay.Visible = true
end)

return LoadoutController
