--!strict
-- AnnouncementController — kill-streak banner.
--
-- Design system compliance (DESIGN_SYSTEM.md / PLAN.md Phase 1.1):
--   • Scale-spring entry (0.85 → 1.05 → 1.0) over UITheme.Duration.celebrate.
--   • Mobile-responsive width: min(580, viewport.X * 0.9). Re-binds on
--     Workspace.CurrentCamera.ViewportSize change.
--   • Particle burst (screen-space confetti) when streak >= DOMINATOR_THRESHOLD.
--   • Streak → tier-color mapping is a PURE function (streak: number → string
--     key) extracted with sentinel comments so it is Lune-testable without
--     touching Roblox APIs.
--   • All colors / spacing / fonts come from UITheme tokens. The only
--     hardcoded mapping lives in LOCAL_TIER_COLORS (streak count → token KEY).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local AudioConfig = require(Shared.Modules.AudioConfig)
local UITheme = require(Shared.Modules.UITheme)

-- Map streak label → AudioConfig key (each tier has its own announcer sound).
local STREAK_SOUND_KEY: { [string]: string } = {
	["FIRST KILL"]  = "streak_first",
	["DOUBLE KILL"] = "streak_double",
	["TRIPLE KILL"] = "streak_triple",
	["QUADRA KILL"] = "streak_quadra",
	["PENTA KILL"]  = "streak_penta",
	["DOMINATOR"]   = "streak_dominator",
}

-- Streak threshold at which we emit the celebratory particle burst. Anything
-- ≥ this gets the confetti screen-space FX. 6 = DOMINATOR floor (matches the
-- 5-6 → warning tier; DOMINATOR-class streaks should feel HUGE).
local DOMINATOR_THRESHOLD = 6

-- Max banner width on desktop. Mobile shrinks via min(MAX, viewport.X * 0.9)
-- so phones <644px get a banner that fits with breathing room.
local BANNER_MAX_WIDTH = 580
local BANNER_HEIGHT = 80
local BANNER_LINGER = 2.5

-- Particle burst tuning. ~30 confetti pieces gives "celebratory" density
-- without thrashing low-end mobile (each is a single Frame, GC'd after life).
local PARTICLE_COUNT = 30
local PARTICLE_LIFETIME = 0.8
local PARTICLE_SIZE_MIN = 6
local PARTICLE_SIZE_MAX = 12
local PARTICLE_RADIUS_MIN = 90
local PARTICLE_RADIUS_MAX = 260

-- TIER_KEY_FN_BEGIN
-- Pure function — streak count → UITheme.Color KEY (string). Kept inside
-- sentinel markers so the Lune test loader can extract & exec it without
-- pulling in the rest of the controller (which has Roblox-only top-level
-- side effects). DO NOT remove these markers.
local LOCAL_TIER_COLORS = {
	-- minStreak (inclusive) → UITheme.Color key
	{ min = 15, key = "accentPrimary" },   -- god-tier (cyan)
	{ min = 10, key = "accentElectric" },  -- legendary (purple)
	{ min = 7,  key = "danger" },          -- domination (red)
	{ min = 5,  key = "warning" },         -- heating up (amber)
	{ min = 2,  key = "success" },         -- solid spree (green)
	{ min = 0,  key = "success" },         -- default for single-kill announce
}

local function streakTierKey(streak: number): string
	-- Iterate top-down — first match wins (highest tier the streak qualifies
	-- for). The final `min = 0` entry guarantees a string return for any
	-- non-negative input.
	for _, tier in ipairs(LOCAL_TIER_COLORS) do
		if streak >= tier.min then
			return tier.key
		end
	end
	return "success"
end
-- TIER_KEY_FN_END

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

-- Banner Frame — anchored at horizontal center, ~18% from top of viewport.
-- Width is set dynamically by refreshBannerWidth(); height is fixed.
local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.Size = UDim2.fromOffset(BANNER_MAX_WIDTH, BANNER_HEIGHT)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.18, 0)
banner.BackgroundColor3 = UITheme.Color.bgBase
banner.BackgroundTransparency = 0.05
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = screenGui

UITheme.corner(banner, "lg")

-- Stroke is the primary tier-color affordance — colored to match streak tier
-- on each open. Use UITheme helper so thickness/transparency stay consistent.
local bannerStroke = UITheme.stroke(banner, "warning", 2)

-- Spotlight gradient — subtle vertical fade (tier-color at top → transparent
-- at bottom) gives the banner a "stage light from above" feel. Color is
-- re-tinted per open via bannerGradient.Color.
local bannerGradient = Instance.new("UIGradient")
bannerGradient.Rotation = 90 -- top → bottom
bannerGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.7),  -- top: slightly visible glow
	NumberSequenceKeypoint.new(1, 1.0),  -- bottom: fully transparent
})
bannerGradient.Parent = banner

-- UIScale powers the entry spring (0.85 → 1.05 → 1.0). It is intentionally
-- separate from the responsive width logic (which mutates Size directly) so
-- the spring overshoot doesn't clip the banner content.
local bannerScale = Instance.new("UIScale")
bannerScale.Scale = 1
bannerScale.Parent = banner

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, 38)
titleLabel.Position = UDim2.new(0, 0, 0, UITheme.Space.s)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = UITheme.Font.display
titleLabel.TextSize = UITheme.FontSize.h2
titleLabel.TextColor3 = UITheme.Color.warning
titleLabel.Text = ""
titleLabel.Parent = banner

local subLabel = Instance.new("TextLabel")
subLabel.Name = "Subtitle"
subLabel.Size = UDim2.new(1, 0, 0, 24)
subLabel.Position = UDim2.new(0, 0, 0, 46)
subLabel.BackgroundTransparency = 1
subLabel.Font = UITheme.Font.heading
subLabel.TextSize = UITheme.FontSize.body
subLabel.TextColor3 = UITheme.Color.textPrimary
subLabel.TextStrokeColor3 = UITheme.Color.bgDeepest
subLabel.TextStrokeTransparency = 0.5
subLabel.Text = ""
subLabel.Parent = banner

-- Particle layer — screen-space Frame container, parented to the ScreenGui
-- (NOT banner) so particles can spread outside banner bounds.
local particleLayer = Instance.new("Frame")
particleLayer.Name = "ParticleLayer"
particleLayer.Size = UDim2.fromScale(1, 1)
particleLayer.BackgroundTransparency = 1
particleLayer.BorderSizePixel = 0
particleLayer.ClipsDescendants = false
particleLayer.Parent = screenGui

-- Recomputes banner width vs viewport. Called on init and on ViewportSize
-- changes so phones in landscape ↔ portrait or window resizes stay correct.
local function refreshBannerWidth()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	local w = math.min(BANNER_MAX_WIDTH, vw * 0.9)
	banner.Size = UDim2.fromOffset(w, BANNER_HEIGHT)
end
refreshBannerWidth()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshBannerWidth)
end

-- Emit a confetti burst from the banner's screen center. Each particle is a
-- small colored Frame that radiates outward + falls due to a gravity bias,
-- fading out over PARTICLE_LIFETIME. Cleanup is via task.spawn + Destroy.
local function emitParticleBurst(tierColor: Color3)
	-- Banner may have just appeared; AbsolutePosition is now-valid since
	-- refreshBannerWidth applied an offset Size and parent ScreenGui sized
	-- to viewport. Fall back to center if not laid out yet.
	local bp = banner.AbsolutePosition
	local bs = banner.AbsoluteSize
	local centerX = bp.X + bs.X * 0.5
	local centerY = bp.Y + bs.Y * 0.5

	for i = 1, PARTICLE_COUNT do
		local p = Instance.new("Frame")
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		local size = math.random(PARTICLE_SIZE_MIN, PARTICLE_SIZE_MAX)
		p.Size = UDim2.fromOffset(size, size)
		p.Position = UDim2.fromOffset(centerX, centerY)
		p.BackgroundColor3 = tierColor
		p.BorderSizePixel = 0
		p.Rotation = math.random(0, 360)
		p.ZIndex = 5
		-- Slight rounded corners for confetti feel without per-particle UICorner cost
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 2)
		corner.Parent = p
		p.Parent = particleLayer

		-- Radial direction with downward gravity bias (additive Y offset on end).
		-- Clamp the radius ceiling to a fraction of the live viewport width so
		-- confetti never flies off-screen on narrow mobile devices (~390px).
		local viewportW = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X) or 1920
		local maxRadius = math.max(PARTICLE_RADIUS_MIN, math.min(PARTICLE_RADIUS_MAX, viewportW * 0.4))
		local angle = math.rad(math.random(0, 359))
		local radius = math.random(PARTICLE_RADIUS_MIN, math.floor(maxRadius))
		local endX = centerX + math.cos(angle) * radius
		local endY = centerY + math.sin(angle) * radius + 60 -- gravity drift

		-- Two tweens in parallel: position (Quart Out) + transparency (linear-ish).
		-- Using TweenService with separate goals keeps each particle cheap (~2 tweens).
		local moveTween = TweenService:Create(
			p,
			TweenInfo.new(PARTICLE_LIFETIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(endX, endY), Rotation = p.Rotation + math.random(-180, 180) }
		)
		local fadeTween = TweenService:Create(
			p,
			TweenInfo.new(PARTICLE_LIFETIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		)
		moveTween:Play()
		fadeTween:Play()

		-- Cleanup via task.spawn — avoid relying on Debris (we want it to
		-- coincide with the tween end, not an arbitrary fixed delay).
		task.spawn(function()
			task.wait(PARTICLE_LIFETIME + 0.05)
			if p.Parent then p:Destroy() end
		end)
		-- i unused beyond loop iteration count
		local _ = i
	end
end

local activeToken = 0
local enabled = true

-- Token-guarded entry/exit so rapid back-to-back streaks don't have their
-- exit tweens cancel an in-progress entry of the next banner.
local function renderBanner(info: any)
	activeToken += 1
	local myToken = activeToken

	-- Resolve tier color from streak (pure fn → UITheme key → Color3)
	local tierKey = streakTierKey(info.streak or 1)
	local tierColor = (UITheme.Color :: any)[tierKey] or UITheme.Color.success

	-- Apply tier color to all themed surfaces
	titleLabel.Text = info.label or ""
	titleLabel.TextColor3 = tierColor
	bannerStroke.Color = tierColor
	bannerGradient.Color = ColorSequence.new(tierColor)

	local isLocal = info.player == player.Name
	if isLocal then
		subLabel.Text = string.format("%d killstreak", info.streak or 0)
		-- Announcer voice only for local player's own streak (avoid spam)
		playStreakSound(info.label)
	else
		subLabel.Text = string.format("%s — %d kills", info.player or "?", info.streak or 0)
	end

	-- Ensure responsive size is current before showing (in case viewport
	-- changed while banner was hidden)
	refreshBannerWidth()
	banner.BackgroundTransparency = 0.05
	banner.Visible = true

	-- Scale-spring entry: 0.85 → 1.05 (slight overshoot) → 1.0.
	-- We use UITheme.Easing.celebrate (Back Out 0.6s) which naturally provides
	-- the overshoot+settle without needing a manual two-stage chain.
	bannerScale.Scale = 0.85
	TweenService:Create(bannerScale, UITheme.Easing.celebrate, { Scale = 1.0 }):Play()

	-- Particle burst for DOMINATOR-tier and above. task.spawn so any
	-- per-particle tween work doesn't block the banner's entry tween.
	if (info.streak or 0) >= DOMINATOR_THRESHOLD then
		task.spawn(function()
			-- Tiny delay so banner has a frame to lay out (AbsolutePosition
			-- needs the parent ScreenGui sized to viewport).
			task.wait(0.05)
			if activeToken == myToken then
				emitParticleBurst(tierColor)
			end
		end)
	end

	-- Linger then fade. Token guard prevents this exit from canceling a
	-- newer banner that came in during the linger window.
	task.delay(BANNER_LINGER, function()
		if activeToken ~= myToken then return end
		TweenService:Create(banner, UITheme.Easing.exit, {
			BackgroundTransparency = 1,
		}):Play()
		task.delay(UITheme.Duration.base, function()
			if activeToken == myToken then
				banner.Visible = false
				banner.BackgroundTransparency = 0.05
			end
		end)
	end)
end

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	if data and data.settings then
		enabled = data.settings.killstreakAnnouncements ~= false
	end
end)

-- PRESERVED INTERFACE: server payload contract is { player, streak, label }.
-- Do not change this signature — multiple server services emit this remote.
-- Public entry: gated on `enabled` (player setting). Production path.
local function openBanner(info: any)
	if not enabled then return end
	renderBanner(info)
end

Remotes.KillstreakAnnouncement.OnClientEvent:Connect(openBanner)

-- Test hook (Tier 2 integration tests). BYPASSES the `enabled` setting check
-- so tests can verify the banner regardless of the player's killstreak toggle.
-- Underscore-prefixed to signal "do not call from gameplay code".
AnnouncementController._OpenForTest = renderBanner

-- Also export the pure resolver so Tier 1 tests can sanity-check without
-- having to parse source — kept alongside the sentinel-extracted path for
-- redundancy. Both must agree.
AnnouncementController._streakTierKey = streakTierKey

return AnnouncementController
