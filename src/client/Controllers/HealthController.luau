--!strict
-- HealthController — HP HUD + damage feedback.
--
-- Design goals (per PLAN.md Phase 1.2):
--   • NO full-screen red overlay. It obscured vision in the exact moments
--     the player needed clarity. Replaced with edge-only vignette (4 thin
--     strips at viewport edges) that never covers the center 80% of screen.
--   • Damage feedback now lives ON the HP HUD itself: container scale pulse
--     + red flash on every health drop. This is the primary "you got shot"
--     signal — far less intrusive than a screen-wide tint.
--   • Bar fill color lerps SMOOTHLY between success → warning → danger
--     (extracted as pure healthToColor() for Lune unit testing).
--   • Sub-30% HP triggers a slow stroke pulse on the container (subtle
--     urgency cue, doesn't block sight).
--   • All visual values come from UITheme. Zero hardcoded RGB.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.Modules.UITheme)

local HealthController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- Pure color lerp (Lune-testable; operates on plain {r,g,b} tables)
-- ============================================================================
-- Anchored at three semantic colors; smooth piecewise lerp between them.
-- Returns a plain table so the function works outside the Roblox runtime —
-- this is the contract the unit tests rely on.
local SUCCESS = {
	r = UITheme.Color.success.R,
	g = UITheme.Color.success.G,
	b = UITheme.Color.success.B,
}
local WARNING = {
	r = UITheme.Color.warning.R,
	g = UITheme.Color.warning.G,
	b = UITheme.Color.warning.B,
}
local DANGER = {
	r = UITheme.Color.danger.R,
	g = UITheme.Color.danger.G,
	b = UITheme.Color.danger.B,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function healthToColor(fraction: number): { r: number, g: number, b: number }
	local f = math.clamp(fraction, 0, 1)
	if f >= 0.5 then
		-- 0.5 → warning, 1.0 → success
		local t = (f - 0.5) / 0.5
		return {
			r = lerp(WARNING.r, SUCCESS.r, t),
			g = lerp(WARNING.g, SUCCESS.g, t),
			b = lerp(WARNING.b, SUCCESS.b, t),
		}
	else
		-- 0.0 → danger, 0.5 → warning
		local t = f / 0.5
		return {
			r = lerp(DANGER.r, WARNING.r, t),
			g = lerp(DANGER.g, WARNING.g, t),
			b = lerp(DANGER.b, WARNING.b, t),
		}
	end
end

local function healthToColor3(fraction: number): Color3
	local c = healthToColor(fraction)
	return Color3.new(c.r, c.g, c.b)
end

HealthController.healthToColor = healthToColor

-- ============================================================================
-- ScreenGui + container
-- ============================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HealthHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40
screenGui.Parent = playerGui

local CONTAINER_BG = UITheme.Color.bgBase

-- Container lives in the TOP-LEFT group with the rank chip below it. We anchor
-- at (0, 0) and offset by GuiService topbar inset + a UITheme.Space.l gap so
-- the HUD never overlaps the Roblox chat/audio icons on mobile.
local container = Instance.new("Frame")
container.Size = UDim2.new(0, 180, 0, 40)
container.AnchorPoint = Vector2.new(0, 0)
container.Position = UDim2.new(0, 12, 0, UITheme.Space.l)
container.BackgroundColor3 = CONTAINER_BG
container.BackgroundTransparency = 0.25
container.BorderSizePixel = 0
container.Parent = screenGui

UITheme.corner(container, "md")
local containerStroke = UITheme.stroke(container, "borderSubtle", 1.5, 0.4)

-- Responsive sizing: mobile 150x28, tablet 220x48, desktop 260x56. We also
-- recompute the Y offset whenever the topbar inset changes (mobile rotation,
-- Studio play-mode toolbar appearing, etc.).
-- Sits BELOW MatchStateController's MatchHUD card (top-left column). The Y
-- offset reserves vertical room for MatchHUD (22 mobile / 32 desktop) plus
-- two Space.xs (4px each) gaps — keep in sync with MatchStateController.
-- Round 7 (mobile shrink): mobile shrunk 180x40 -> 150x28 per user request
-- "perkecil semua card info, health bar". MatchHUD height tracked accordingly.
local function refreshContainerLayout()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	local w, h, matchHudH
	if vw < 700 then
		w, h, matchHudH = 150, 28, 22
	elseif vw < 1100 then
		w, h, matchHudH = 220, 48, 32
	else
		w, h, matchHudH = 260, 56, 32
	end
	container.Size = UDim2.new(0, w, 0, h)
	local topInset = GuiService:GetGuiInset().Y
	-- topInset + xs(4) (MatchHUD's top gap) + matchHudH + xs(4) (gap between cards)
	container.Position = UDim2.new(0, 12, 0, topInset + UITheme.Space.xs + matchHudH + UITheme.Space.xs)
end
refreshContainerLayout()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refreshContainerLayout)
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshContainerLayout)
end

-- UIScale gives us a single mutable handle for the damage pulse animation.
local containerScale = Instance.new("UIScale")
containerScale.Scale = 1.0
containerScale.Parent = container

-- ============================================================================
-- Inline layout: [ ♥ 100   ████████ ] — heart, HP value, then bar filling
-- the rest of the row. Compact single-row design for the top-left HUD group.
-- Round 7: mobile shrink — heart 14, HP label 24, bar height 6, font caption,
-- so heart + number + bar all stay readable inside the 150x28 mobile chip.
-- ============================================================================
local INNER_PAD = UITheme.Space.s -- 8px left/right padding inside container

local heartIcon = Instance.new("TextLabel")
heartIcon.Size = UDim2.new(0, 18, 1, 0)
heartIcon.Position = UDim2.new(0, INNER_PAD, 0, 0)
heartIcon.BackgroundTransparency = 1
heartIcon.Font = UITheme.Font.display
heartIcon.TextSize = UITheme.FontSize.body
heartIcon.TextColor3 = UITheme.Color.success
heartIcon.TextXAlignment = Enum.TextXAlignment.Left
heartIcon.TextYAlignment = Enum.TextYAlignment.Center
-- TODO: replace with image asset when uploaded (see ASSETS.md)
heartIcon.Text = "♥"
heartIcon.Parent = container

local hpLabel = Instance.new("TextLabel")
hpLabel.Size = UDim2.new(0, 32, 1, 0)
hpLabel.Position = UDim2.new(0, INNER_PAD + 20, 0, 0)
hpLabel.BackgroundTransparency = 1
hpLabel.Font = UITheme.Font.mono
hpLabel.TextSize = UITheme.FontSize.body
hpLabel.TextColor3 = UITheme.Color.textPrimary
hpLabel.TextXAlignment = Enum.TextXAlignment.Left
hpLabel.TextYAlignment = Enum.TextYAlignment.Center
hpLabel.Text = "100"
hpLabel.Parent = container

-- ============================================================================
-- Bar (track + fill). Fills the right portion of the container row.
-- BAR_LEFT now driven by the labels' widths; refreshContainerLayout() rewires
-- the inner widths/sizes on viewport changes so the bar shrinks cleanly on
-- mobile without leaving an oversized empty gap to the right of the value.
-- ============================================================================
local BAR_HEIGHT_DESKTOP = UITheme.Space.s + 2 -- 10px
local BAR_HEIGHT_MOBILE = UITheme.Space.xs + 2 -- 6px

local barBg = Instance.new("Frame")
barBg.AnchorPoint = Vector2.new(0, 0.5)
barBg.Position = UDim2.new(0, INNER_PAD + 20 + 32 + UITheme.Space.s, 0.5, 0)
barBg.Size = UDim2.new(1, -(INNER_PAD + 20 + 32 + UITheme.Space.s + INNER_PAD), 0, BAR_HEIGHT_DESKTOP)
barBg.BackgroundColor3 = UITheme.Color.bgPressed
barBg.BorderSizePixel = 0
barBg.Parent = container

UITheme.corner(barBg, "full")

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = UITheme.Color.success
barFill.BorderSizePixel = 0
barFill.Parent = barBg

UITheme.corner(barFill, "full")

-- Recompute the heart/value/bar inner geometry whenever the container resizes.
-- We re-hook this into refreshContainerLayout below so both fire together.
local function applyInnerSizing(mobile: boolean)
	local heartW = mobile and 14 or 18
	local hpW = mobile and 24 or 32
	local fontSize = mobile and UITheme.FontSize.caption or UITheme.FontSize.body
	local barH = mobile and BAR_HEIGHT_MOBILE or BAR_HEIGHT_DESKTOP
	-- INNER_PAD on mobile uses xs (4) to give the bar more horizontal runway.
	local pad = mobile and UITheme.Space.xs or INNER_PAD
	local gap = mobile and UITheme.Space.xs or UITheme.Space.s
	heartIcon.Size = UDim2.new(0, heartW, 1, 0)
	heartIcon.Position = UDim2.new(0, pad, 0, 0)
	heartIcon.TextSize = fontSize
	hpLabel.Size = UDim2.new(0, hpW, 1, 0)
	hpLabel.Position = UDim2.new(0, pad + heartW + gap, 0, 0)
	hpLabel.TextSize = fontSize
	local barLeft = pad + heartW + gap + hpW + gap
	barBg.Position = UDim2.new(0, barLeft, 0.5, 0)
	barBg.Size = UDim2.new(1, -(barLeft + pad), 0, barH)
end

-- Wire inner sizing to viewport changes. We mirror the same breakpoint used
-- by refreshContainerLayout above so heart/HP/bar stay in lockstep with the
-- container width.
local function refreshInner()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	applyInnerSizing(vw < 700)
end
refreshInner()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshInner)
end

-- ============================================================================
-- Edge-only vignette: 4 thin strips at viewport edges. Each strip uses a
-- UIGradient that fades the danger color from edge → transparent inward,
-- so the center 80%+ of screen is NEVER tinted. Replaces the old full-screen
-- red overlay that obscured vision.
-- ============================================================================
local EDGE_THICKNESS = 80 -- px depth of each strip; gradient fades inward over this range

local function makeEdgeStrip(edge: string): Frame
	local strip = Instance.new("Frame")
	strip.BackgroundColor3 = UITheme.Color.danger
	strip.BackgroundTransparency = 1 -- start invisible; alpha animated by health
	strip.BorderSizePixel = 0
	strip.ZIndex = 0
	strip.Parent = screenGui

	local grad = Instance.new("UIGradient")
	-- Stronger at the outer edge, fades toward center
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = strip

	if edge == "top" then
		strip.AnchorPoint = Vector2.new(0, 0)
		strip.Position = UDim2.new(0, 0, 0, 0)
		strip.Size = UDim2.new(1, 0, 0, EDGE_THICKNESS)
		grad.Rotation = 90 -- top edge fully opaque → bottom transparent
	elseif edge == "bottom" then
		strip.AnchorPoint = Vector2.new(0, 1)
		strip.Position = UDim2.new(0, 0, 1, 0)
		strip.Size = UDim2.new(1, 0, 0, EDGE_THICKNESS)
		grad.Rotation = 270 -- bottom edge fully opaque → top transparent
	elseif edge == "left" then
		strip.AnchorPoint = Vector2.new(0, 0)
		strip.Position = UDim2.new(0, 0, 0, 0)
		strip.Size = UDim2.new(0, EDGE_THICKNESS, 1, 0)
		grad.Rotation = 0 -- left edge fully opaque → right transparent
	elseif edge == "right" then
		strip.AnchorPoint = Vector2.new(1, 0)
		strip.Position = UDim2.new(1, 0, 0, 0)
		strip.Size = UDim2.new(0, EDGE_THICKNESS, 1, 0)
		grad.Rotation = 180 -- right edge fully opaque → left transparent
	end

	return strip
end

local edgeStrips = {
	makeEdgeStrip("top"),
	makeEdgeStrip("bottom"),
	makeEdgeStrip("left"),
	makeEdgeStrip("right"),
}

-- Map a fraction in [0, 1] to vignette transparency.
-- ≥30% HP → fully transparent (no vignette).
-- 30% HP → 0.5 (subtle hint).
-- 5% HP → 0.2 (strong but never opaque).
-- <5% HP → clamped at 0.2.
local function vignetteTransparencyFor(fraction: number): number
	if fraction >= 0.3 then
		return 1.0
	end
	-- Linear interpolation between (0.3 → 0.5) and (0.05 → 0.2)
	local clamped = math.clamp(fraction, 0.05, 0.3)
	local t = (0.3 - clamped) / (0.3 - 0.05)
	return lerp(0.5, 0.2, t)
end

local function applyVignette(fraction: number)
	local transparency = vignetteTransparencyFor(fraction)
	for _, strip in edgeStrips do
		TweenService:Create(strip, UITheme.Easing.standard, {
			BackgroundTransparency = transparency,
		}):Play()
	end
end

-- ============================================================================
-- Damage pulse: container scale (1.0 → 1.08 → 1.0) + bg color flash to danger
-- and back. Fires whenever health drops. This replaces the obscuring overlay
-- as the primary "you got shot" feedback.
-- ============================================================================
local PULSE_INFO = TweenInfo.new(
	UITheme.Duration.quick,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out,
	0,    -- no repeat
	true, -- reverse (mirrors back)
	0
)

local activePulse: Tween? = nil
local activeBgFlash: Tween? = nil

local function pulseOnDamage()
	if activePulse then activePulse:Cancel() end
	if activeBgFlash then activeBgFlash:Cancel() end

	containerScale.Scale = 1.0
	activePulse = TweenService:Create(containerScale, PULSE_INFO, { Scale = 1.08 })
	activePulse:Play()

	container.BackgroundColor3 = CONTAINER_BG
	activeBgFlash = TweenService:Create(container, PULSE_INFO, {
		BackgroundColor3 = UITheme.Color.danger,
	})
	activeBgFlash:Play()
end

-- ============================================================================
-- Sub-30% HP urgency: oscillating UIStroke transparency. Slow & non-intrusive.
-- ============================================================================
local lowHpPulseActive = false
local lowHpPulseToken = 0

local function startLowHpPulse()
	if lowHpPulseActive then return end
	lowHpPulseActive = true
	lowHpPulseToken += 1
	local myToken = lowHpPulseToken
	-- Drive stroke color to danger so the pulse reads as "warning"
	containerStroke.Color = UITheme.Color.danger
	task.spawn(function()
		while lowHpPulseActive and lowHpPulseToken == myToken do
			local up = TweenService:Create(containerStroke, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {
				Transparency = 0.3,
			})
			up:Play()
			task.wait(0.3)
			if not lowHpPulseActive or lowHpPulseToken ~= myToken then break end
			local down = TweenService:Create(containerStroke, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {
				Transparency = 0.7,
			})
			down:Play()
			task.wait(0.3)
		end
	end)
end

local function stopLowHpPulse()
	if not lowHpPulseActive then return end
	lowHpPulseActive = false
	lowHpPulseToken += 1
	-- Restore neutral stroke
	TweenService:Create(containerStroke, UITheme.Easing.standard, {
		Transparency = 0.4,
	}):Play()
	containerStroke.Color = UITheme.Color.borderSubtle
end

-- ============================================================================
-- Humanoid binding
-- ============================================================================
local function bindHumanoid(humanoid: Humanoid)
	local lastHealth = humanoid.Health

	local function update()
		local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		local color = healthToColor3(ratio)

		barFill:TweenSize(
			UDim2.new(ratio, 0, 1, 0),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Quad,
			UITheme.Duration.quick,
			true
		)
		barFill.BackgroundColor3 = color
		heartIcon.TextColor3 = color
		hpLabel.Text = string.format("%d", math.ceil(humanoid.Health))

		applyVignette(ratio)

		-- Damage-only feedback: only pulse on health drops (not on regen/respawn)
		if humanoid.Health < lastHealth then
			pulseOnDamage()
		end
		lastHealth = humanoid.Health

		if ratio < 0.3 and humanoid.Health > 0 then
			startLowHpPulse()
		else
			stopLowHpPulse()
		end
	end

	humanoid.HealthChanged:Connect(update)
	humanoid.Died:Connect(function()
		stopLowHpPulse()
	end)
	update()
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	bindHumanoid(humanoid)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

return HealthController
