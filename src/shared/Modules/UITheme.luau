--!strict
-- Design tokens. Single source of truth untuk warna, font size, spacing,
-- radius, motion. Controllers import dari sini biar konsisten + gampang
-- di-rebrand.
--
-- Style: "Tactical Energetic FPS" — dark base, neon cyan/red accent, strong
-- contrast, motion penuh (semua entry/exit di-tween, gak ada instant pop).

local UITheme = {}

-- ============================================================================
-- COLORS
-- ============================================================================
-- Base palette (dark surfaces, deep navy-black)
UITheme.Color = {
	-- Backgrounds (deepest → most elevated)
	bgDeepest = Color3.fromRGB(8, 9, 14),     -- behind everything
	bgBase = Color3.fromRGB(16, 18, 26),      -- panel base
	bgElevated = Color3.fromRGB(24, 26, 36),  -- cards, list items
	bgHover = Color3.fromRGB(32, 36, 48),     -- hover/active
	bgPressed = Color3.fromRGB(20, 22, 30),   -- pressed
	bgDisabled = Color3.fromRGB(28, 30, 38),

	-- Accent (brand + combat feedback)
	accentPrimary = Color3.fromRGB(0, 220, 255),     -- cyan neon — brand
	accentSecondary = Color3.fromRGB(255, 64, 96),   -- hot red — enemy/combat
	accentWarm = Color3.fromRGB(255, 180, 60),       -- gold — MVP/reward
	accentElectric = Color3.fromRGB(140, 100, 255),  -- purple — legendary/special

	-- Semantic (use for status, not theme)
	success = Color3.fromRGB(80, 220, 130),
	danger = Color3.fromRGB(255, 60, 80),
	warning = Color3.fromRGB(255, 200, 60),
	info = Color3.fromRGB(80, 180, 255),

	-- Tier (gacha + cosmetic rarity)
	tierCommon = Color3.fromRGB(180, 185, 200),
	tierRare = Color3.fromRGB(100, 180, 255),
	tierEpic = Color3.fromRGB(200, 120, 255),
	tierLegendary = Color3.fromRGB(255, 200, 80),
	tierContraband = Color3.fromRGB(255, 80, 130),

	-- Text
	textPrimary = Color3.fromRGB(245, 247, 255),
	textSecondary = Color3.fromRGB(180, 185, 200),
	textTertiary = Color3.fromRGB(120, 125, 140),
	textInverse = Color3.fromRGB(8, 9, 14),

	-- Team (casual mode)
	teamT = Color3.fromRGB(255, 180, 60),       -- gold T's
	teamCT = Color3.fromRGB(100, 180, 255),     -- blue CT's

	-- Borders
	borderSubtle = Color3.fromRGB(40, 44, 56),
	borderNeon = Color3.fromRGB(0, 220, 255),   -- accent glow border
}

-- ============================================================================
-- SPACING (px)
-- ============================================================================
-- 4px grid. Use these for padding, gaps, margins — no random values.
UITheme.Space = {
	xs = 4,
	s = 8,
	m = 12,
	l = 16,
	xl = 20,
	xxl = 24,
	x3l = 32,
	x4l = 48,
	x5l = 64,
}

-- ============================================================================
-- CORNER RADIUS
-- ============================================================================
UITheme.Radius = {
	sm = 4,       -- inputs, tiny badges
	md = 8,       -- standard buttons, cards
	lg = 14,      -- panels, modals
	xl = 22,      -- prominent cards
	full = 9999,  -- pill / circle (44x44 close btn)
}

-- ============================================================================
-- TYPOGRAPHY
-- ============================================================================
-- Font sizes follow a perfect-fourth-ish scale (each step ~1.25x).
UITheme.FontSize = {
	micro = 11,    -- tiny tags, footnotes
	caption = 13,  -- small labels
	body = 15,     -- default
	bodyLg = 18,   -- emphasized body
	h3 = 22,       -- card titles, modal titles
	h2 = 28,       -- section heads
	h1 = 36,       -- big numbers (timer, kill count)
	display = 48,  -- match results, kill streaks
}

UITheme.Font = {
	display = Enum.Font.GothamBlack,  -- biggest, boldest
	heading = Enum.Font.GothamBold,
	body = Enum.Font.Gotham,
	mono = Enum.Font.RobotoMono,      -- timer, stats
}

-- ============================================================================
-- TOUCH TARGETS
-- ============================================================================
-- Minimums for mobile. NEVER go below these for interactive elements.
UITheme.TouchTarget = {
	min = 44,       -- absolute min (Apple HIG / Material)
	comfortable = 48,
	prominent = 56, -- primary CTAs
}

-- ============================================================================
-- MOTION (durations in seconds + easing)
-- ============================================================================
UITheme.Duration = {
	instant = 0.08,    -- hover state change
	quick = 0.16,      -- press feedback, small state
	base = 0.24,       -- standard transitions
	smooth = 0.35,     -- modal entry/exit
	celebrate = 0.6,   -- kill streak, match results
	linger = 4.0,      -- toast/notification display
}

UITheme.Easing = {
	emphasized = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	standard = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	enter = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	exit = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	bounce = TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
	celebrate = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

-- ============================================================================
-- HELPERS: shortcut constructors yang sering dipakai
-- ============================================================================

-- UICorner shortcut. Pass radius name from UITheme.Radius.
function UITheme.corner(parent: Instance, radiusKey: string?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, (UITheme.Radius :: any)[radiusKey or "md"])
	if parent then c.Parent = parent end
	return c
end

-- UIStroke shortcut. Pass color name from UITheme.Color (or Color3 directly).
function UITheme.stroke(parent: Instance, color: any?, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	local resolved: Color3
	if typeof(color) == "Color3" then
		resolved = color
	elseif typeof(color) == "string" then
		resolved = (UITheme.Color :: any)[color] or UITheme.Color.borderSubtle
	else
		resolved = UITheme.Color.borderSubtle
	end
	s.Color = resolved
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	if parent then s.Parent = parent end
	return s
end

-- UIPadding shortcut: pass space key from UITheme.Space, applied to all sides.
function UITheme.padding(parent: Instance, spaceKey: string?, override: { top: number?, bottom: number?, left: number?, right: number? }?): UIPadding
	local s = (UITheme.Space :: any)[spaceKey or "m"]
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, override and override.top or s)
	p.PaddingBottom = UDim.new(0, override and override.bottom or s)
	p.PaddingLeft = UDim.new(0, override and override.left or s)
	p.PaddingRight = UDim.new(0, override and override.right or s)
	if parent then p.Parent = parent end
	return p
end

-- Neon glow border using UIStroke with gradient — for hero cards / featured CTAs.
function UITheme.neonStroke(parent: Instance, color: Color3, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1.5
	s.Transparency = 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	-- Soft pulse via gradient (transparency varies along edge)
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	grad.Parent = s
	if parent then s.Parent = parent end
	return s
end

-- Mobile-aware UIScale: shrinks based on viewport width. Parent to PANEL, not
-- overlay (parenting to overlay shrinks the click-outside-to-close area too).
function UITheme.bindResponsiveScale(panel: GuiObject, breakpoints: { [string]: number }?): UIScale
	local Workspace = game:GetService("Workspace")
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local bp = breakpoints or { mobile = 0.65, tablet = 0.8, desktop = 1.0 }
	local function refresh()
		local cam = Workspace.CurrentCamera
		local vw = cam and cam.ViewportSize.X or 1920
		if vw < 700 then scale.Scale = bp.mobile or 0.65
		elseif vw < 1100 then scale.Scale = bp.tablet or 0.8
		else scale.Scale = bp.desktop or 1.0 end
	end
	refresh()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	return scale
end

return UITheme
