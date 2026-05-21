--!strict
-- MatchStateController — compact 1-line match HUD: [●] STATE ▸ M:SS
--
-- Visual design (per DESIGN_SYSTEM.md + PLAN.md Phase 1.3):
--   * Single line: state-color dot (8px) + state label (heading) + arrow + timer (mono).
--   * Responsive width: 280 mobile (<700 vw), 360 desktop.
--   * State-color stroke + dot match the current state (LOBBY=info blue, MATCH=danger red, ...).
--   * Urgency at low timer (MATCH only): timer text pulses danger<->textPrimary at <30s;
--     also UIStroke thickness pulses 1<->2 at <10s.
--   * State transition: brief UIScale 1.0 -> 1.05 -> 1.0 celebration via Back-Out easing.
--
-- All tokens come from UITheme; no hardcoded RGB/Font. Exposes pure helpers
-- (`formatTimer`, `stateColorKey`) on the returned module table for testing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Modules.MatchState)
local Remotes = require(Shared.Modules.Remotes)
local UITheme = require(Shared.Modules.UITheme)
local DMTeams = require(Shared.Modules.DMTeams)

local MatchStateController = {}

-- ---------------------------------------------------------------------------
-- Pure helpers (exported for unit tests)
-- ---------------------------------------------------------------------------

-- Mapping: state -> UITheme.Color KEY (string, not Color3). Kept as a string
-- key so tests stay pure-Luau (no Color3 dependency under Lune).
local STATE_COLOR_KEY: { [string]: string } = {
	LOBBY = "info",         -- waiting
	VOTING = "warning",     -- action needed
	STARTING = "success",   -- ready
	MATCH = "danger",       -- combat live
	ENDING = "textTertiary",-- cooldown
}

-- Convert remaining seconds to "M:SS". Negative / NaN clamp to "0:00" so the
-- timer never flashes garbage values at the exact state-transition boundary.
local function formatTimer(seconds: number): string
	if seconds <= 0 or seconds ~= seconds then
		return "0:00"
	end
	local total = math.floor(seconds)
	local minutes = math.floor(total / 60)
	local secs = total % 60
	return string.format("%d:%02d", minutes, secs)
end

local function stateColorKey(state: string): string
	return STATE_COLOR_KEY[state] or "textTertiary"
end

MatchStateController.formatTimer = formatTimer
MatchStateController.stateColorKey = stateColorKey

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------
-- Slimmer compact MatchHUD: "● MATCH 5:26" — single-word state + timer.
-- Sized down ~40% from earlier so it sits as a discreet header chip near
-- the top edge instead of a wide banner.
-- Round 7 (mobile shrink pass): mobile 170x28 -> 140x22, font micro,
-- so the chip reads as a discreet header at iPhone 7 (666x374). Desktop
-- retains 210x32 since it has plenty of room.
-- Round 8 (multi-viewport audit): added ultra-mobile (vw < 600) branch so
-- iPhone 4S (480x320) gets 120x20 chip. Breakpoint aligned to 900 (was 700)
-- to match HealthController.refreshContainerLayout — both controllers now
-- treat mobile identically, so the HP bar's matchHudH math never desyncs.
local WIDTH_ULTRA = 120
local WIDTH_MOBILE = 140
local WIDTH_DESKTOP = 210
local HEIGHT_ULTRA = 20
local HEIGHT_MOBILE = 22
local HEIGHT_DESKTOP = 32
local ULTRA_BREAKPOINT = 600
local MOBILE_BREAKPOINT = 900

local DOT_SIZE_ULTRA = 5
local DOT_SIZE_MOBILE = 6
local DOT_SIZE_DESKTOP = 8
local URGENT_THRESHOLD = 30  -- timer pulse begins
local CRITICAL_THRESHOLD = 10 -- stroke pulse begins
local PULSE_PERIOD = 0.5     -- one half-cycle (color/thickness flip)

-- ---------------------------------------------------------------------------
-- Build UI tree
-- ---------------------------------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Container: TOP-LEFT anchored (user request: card waktu di ATAS darah).
-- Sits in the top-left group, just above the HealthHUD. Width matches the
-- HP bar widths exactly so the two cards form a clean stacked column.
-- IgnoreGuiInset=true → we manually add GuiService:GetGuiInset().Y so we
-- never sit underneath the Roblox chat/audio icons on mobile.
local container = Instance.new("Frame")
container.AnchorPoint = Vector2.new(0, 0)
container.Position = UDim2.new(0, 12, 0, UITheme.Space.xs)
container.Size = UDim2.fromOffset(WIDTH_DESKTOP, HEIGHT_DESKTOP)
container.BackgroundColor3 = UITheme.Color.bgBase
container.BackgroundTransparency = 0.15
container.BorderSizePixel = 0
container.Parent = screenGui

UITheme.corner(container, "md")
local containerStroke = UITheme.stroke(container, "borderSubtle", 1)

-- UIScale used for state-change celebration. Lives separate so we can tween
-- without disturbing the container's Size (which is the responsive token).
local containerScale = Instance.new("UIScale")
containerScale.Scale = 1
containerScale.Parent = container

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, UITheme.Space.s)
padding.PaddingRight = UDim.new(0, UITheme.Space.s)
padding.Parent = container

local hList = Instance.new("UIListLayout")
hList.FillDirection = Enum.FillDirection.Horizontal
hList.HorizontalAlignment = Enum.HorizontalAlignment.Center
hList.VerticalAlignment = Enum.VerticalAlignment.Center
hList.SortOrder = Enum.SortOrder.LayoutOrder
hList.Padding = UDim.new(0, UITheme.Space.xs)
hList.Parent = container

-- State-color dot (8x8 Frame, full corner radius = circle).
-- Size driven by refreshSize() — mobile uses 6, desktop 8.
local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(DOT_SIZE_DESKTOP, DOT_SIZE_DESKTOP)
dot.BackgroundColor3 = UITheme.Color.info
dot.BorderSizePixel = 0
dot.LayoutOrder = 1
dot.Parent = container
UITheme.corner(dot, "full")

-- State label — heading font, uppercase. Mobile drops to micro (11) so
-- "MATCH 5:23" fits inside the 140px chip without elision.
local stateLabel = Instance.new("TextLabel")
stateLabel.AutomaticSize = Enum.AutomaticSize.X
stateLabel.Size = UDim2.new(0, 0, 1, 0)
stateLabel.BackgroundTransparency = 1
stateLabel.Font = UITheme.Font.heading
stateLabel.TextSize = UITheme.FontSize.caption
stateLabel.TextColor3 = UITheme.Color.textPrimary
stateLabel.TextXAlignment = Enum.TextXAlignment.Center
stateLabel.TextYAlignment = Enum.TextYAlignment.Center
stateLabel.Text = "..."
stateLabel.LayoutOrder = 2
stateLabel.Parent = container

-- Separator arrow (between state label and timer)
local arrowLabel = Instance.new("TextLabel")
arrowLabel.AutomaticSize = Enum.AutomaticSize.X
arrowLabel.Size = UDim2.new(0, 0, 1, 0)
arrowLabel.BackgroundTransparency = 1
arrowLabel.Font = UITheme.Font.body
arrowLabel.TextSize = UITheme.FontSize.caption
arrowLabel.TextColor3 = UITheme.Color.textTertiary
arrowLabel.Text = "\u{25B8}"  -- right-pointing small triangle ▸
arrowLabel.LayoutOrder = 3
arrowLabel.Parent = container

-- Timer label — mono font so digits don't jitter the layout each tick
local timerLabel = Instance.new("TextLabel")
timerLabel.AutomaticSize = Enum.AutomaticSize.X
timerLabel.Size = UDim2.new(0, 0, 1, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = UITheme.Font.mono
timerLabel.TextSize = UITheme.FontSize.caption
timerLabel.TextColor3 = UITheme.Color.textPrimary
timerLabel.Text = "0:00"
timerLabel.LayoutOrder = 4
timerLabel.Parent = container

-- Score-arrow separator (between timer and team score)
local scoreSep = Instance.new("TextLabel")
scoreSep.AutomaticSize = Enum.AutomaticSize.X
scoreSep.Size = UDim2.new(0, 0, 1, 0)
scoreSep.BackgroundTransparency = 1
scoreSep.Font = UITheme.Font.body
scoreSep.TextSize = UITheme.FontSize.caption
scoreSep.TextColor3 = UITheme.Color.textTertiary
scoreSep.Text = "\u{25B8}"  -- ▸
scoreSep.LayoutOrder = 5
scoreSep.Visible = false
scoreSep.Parent = container

-- Team-score label — "47-32" with team A kills colored blue and team B red.
-- Uses RichText so a single TextLabel can hold both colors.
local scoreLabel = Instance.new("TextLabel")
scoreLabel.AutomaticSize = Enum.AutomaticSize.X
scoreLabel.Size = UDim2.new(0, 0, 1, 0)
scoreLabel.BackgroundTransparency = 1
scoreLabel.Font = UITheme.Font.mono
scoreLabel.TextSize = UITheme.FontSize.caption
scoreLabel.TextColor3 = UITheme.Color.textPrimary
scoreLabel.RichText = true
scoreLabel.Text = ""
scoreLabel.LayoutOrder = 6
scoreLabel.Visible = false
scoreLabel.Parent = container

-- Convert Color3 (0..1 floats) to "RRGGBB" hex string for RichText.
local function colorToHex(c: Color3): string
	return string.format("%02X%02X%02X",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5))
end

local TEAM_A_HEX = colorToHex(DMTeams.Colors.A)
local TEAM_B_HEX = colorToHex(DMTeams.Colors.B)

local function setTeamScore(aKills: number, bKills: number)
	scoreLabel.Text = string.format(
		"<font color=\"#%s\">%d</font>-<font color=\"#%s\">%d</font>",
		TEAM_A_HEX, aKills, TEAM_B_HEX, bKills
	)
	scoreLabel.Visible = true
	scoreSep.Visible = true
end

MatchStateController.setTeamScore = setTeamScore

-- ---------------------------------------------------------------------------
-- Topbar inset compensation (Bug fix: HUD covered by Roblox topbar on mobile)
-- ---------------------------------------------------------------------------
-- IgnoreGuiInset=true means we sit underneath chat/headphones icons unless we
-- manually shift down by the topbar reservation height. TopbarInset signal
-- fires when chat opens/closes or the player rotates the device.
local function refreshTopOffset()
	local topInset = GuiService:GetGuiInset().Y
	-- Top-left, snug against the topbar. HealthHUD shifts below us via its own
	-- refresh — see HealthController.refreshContainerLayout.
	container.Position = UDim2.new(0, 12, 0, topInset + UITheme.Space.xs)
end
refreshTopOffset()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refreshTopOffset)

-- ---------------------------------------------------------------------------
-- Responsive container size
-- ---------------------------------------------------------------------------
local function refreshSize()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	local ultra = vw < ULTRA_BREAKPOINT
	local mobile = vw < MOBILE_BREAKPOINT
	local w, h, dotSize
	if ultra then
		w, h, dotSize = WIDTH_ULTRA, HEIGHT_ULTRA, DOT_SIZE_ULTRA
	elseif mobile then
		w, h, dotSize = WIDTH_MOBILE, HEIGHT_MOBILE, DOT_SIZE_MOBILE
	else
		w, h, dotSize = WIDTH_DESKTOP, HEIGHT_DESKTOP, DOT_SIZE_DESKTOP
	end
	container.Size = UDim2.fromOffset(w, h)
	dot.Size = UDim2.fromOffset(dotSize, dotSize)
	-- Mobile + ultra both drop to micro font; desktop uses caption for clarity.
	local fontSize = mobile and UITheme.FontSize.micro or UITheme.FontSize.caption
	stateLabel.TextSize = fontSize
	arrowLabel.TextSize = fontSize
	timerLabel.TextSize = fontSize
	scoreSep.TextSize = fontSize
	scoreLabel.TextSize = fontSize
end
refreshSize()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshSize)
end
-- Re-bind when the camera is swapped out (e.g. ReplicatedFirst custom cam)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	refreshSize()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshSize)
	end
end)

-- ---------------------------------------------------------------------------
-- State-driven visual updates
-- ---------------------------------------------------------------------------
local currentPayload: MatchState.StatePayload? = nil
local currentState: string? = nil
-- Token (incremented per state change) used to invalidate stale pulse loops.
local pulseToken = 0

local function applyStateColor(state: string)
	local key = stateColorKey(state)
	local color = (UITheme.Color :: any)[key] or UITheme.Color.textTertiary

	-- Dot snaps to color (small element, no tween cost)
	dot.BackgroundColor3 = color

	-- Stroke tween over smooth duration — matches DESIGN_SYSTEM motion rule
	TweenService:Create(containerStroke, UITheme.Easing.emphasized, {
		Color = color,
	}):Play()
end

local function celebrateStateChange()
	-- Scale 1.0 -> 1.05 -> 1.0 via two chained tweens. Back-Out gives a subtle
	-- spring overshoot that reads as "something just happened".
	containerScale.Scale = 1.0
	local up = TweenService:Create(
		containerScale,
		TweenInfo.new(UITheme.Duration.smooth * 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.05 }
	)
	up:Play()
	up.Completed:Connect(function()
		TweenService:Create(
			containerScale,
			TweenInfo.new(UITheme.Duration.smooth * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1.0 }
		):Play()
	end)
end

-- Pulse loop: runs while currentState == MATCH and time is short. Uses a
-- monotonic token so any state change cancels in-flight loops cleanly.
local function startUrgencyPulse(myToken: number)
	task.spawn(function()
		local flip = false
		while myToken == pulseToken and currentState == "MATCH" do
			if not currentPayload then break end
			local elapsed = Workspace:GetServerTimeNow() - currentPayload.startedAt
			local remaining = currentPayload.duration - elapsed

			if remaining < URGENT_THRESHOLD and remaining > 0 then
				flip = not flip
				-- Timer color pulse — danger <-> textPrimary
				timerLabel.TextColor3 = flip and UITheme.Color.danger or UITheme.Color.textPrimary
				-- Stroke thickness pulse — only at <10s
				if remaining < CRITICAL_THRESHOLD then
					containerStroke.Thickness = flip and 2 or 1
				else
					containerStroke.Thickness = 1
				end
			else
				timerLabel.TextColor3 = UITheme.Color.textPrimary
				containerStroke.Thickness = 1
			end
			task.wait(PULSE_PERIOD)
		end
	end)
end

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: MatchState.StatePayload)
	currentPayload = payload
	currentState = payload.state

	-- Short one-word label (user feedback): "MATCH IN PROGRESS" → "MATCH",
	-- "Waiting for players" → "LOBBY", etc. The full DisplayName lives in
	-- MatchState.luau for any other consumer; here we just upper-case the
	-- enum key itself for the most compact chip text.
	stateLabel.Text = string.upper(payload.state)
	applyStateColor(payload.state)
	celebrateStateChange()

	-- Reset urgency visuals between states so a non-MATCH state never stays red
	timerLabel.TextColor3 = UITheme.Color.textPrimary
	containerStroke.Thickness = 1

	-- Bump the token to kill any in-flight pulse loop, then start a fresh one
	-- if we just entered MATCH. Other states don't need urgency feedback.
	pulseToken += 1
	if payload.state == "MATCH" then
		startUrgencyPulse(pulseToken)
	end
end)

RunService.RenderStepped:Connect(function()
	if not currentPayload then
		return
	end
	local elapsed = Workspace:GetServerTimeNow() - currentPayload.startedAt
	local remaining = math.max(0, currentPayload.duration - elapsed)
	timerLabel.Text = formatTimer(remaining)
end)

-- Team-score sublabel. Subscribes to TeamStateChanged to keep the "47-32"
-- chip live. The chip stays hidden until the first event arrives — keeps the
-- MatchHUD clean during non-DM modes (casual / training) where TeamStateChanged
-- never fires.
Remotes.TeamStateChanged.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then return end
	local a = payload.teamA
	local b = payload.teamB
	local aK = (a and typeof(a.kills) == "number") and a.kills or 0
	local bK = (b and typeof(b.kills) == "number") and b.kills or 0
	setTeamScore(aK, bK)
end)

return MatchStateController
