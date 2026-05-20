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
local WIDTH_MOBILE = 170
local WIDTH_DESKTOP = 210
local HEIGHT_MOBILE = 28
local HEIGHT_DESKTOP = 32
local MOBILE_BREAKPOINT = 700

local DOT_SIZE = 8
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

-- Container: top-center anchored, width swaps with viewport.
-- NOTE: ScreenGui.IgnoreGuiInset = true means Roblox does NOT auto-shift our
-- HUD below the topbar (chat/headphones icons on mobile). We keep IgnoreGuiInset
-- on so other ScreenGui elements (e.g. bottom-anchored mobile FIRE button) stay
-- pinned to the true viewport edge, and instead manually compensate by adding
-- GuiService:GetGuiInset().Y to this top-anchored container's Y offset below.
local container = Instance.new("Frame")
container.AnchorPoint = Vector2.new(0.5, 0)
container.Position = UDim2.new(0.5, 0, 0, UITheme.Space.l)
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
padding.PaddingLeft = UDim.new(0, UITheme.Space.m)
padding.PaddingRight = UDim.new(0, UITheme.Space.m)
padding.Parent = container

local hList = Instance.new("UIListLayout")
hList.FillDirection = Enum.FillDirection.Horizontal
hList.HorizontalAlignment = Enum.HorizontalAlignment.Center
hList.VerticalAlignment = Enum.VerticalAlignment.Center
hList.SortOrder = Enum.SortOrder.LayoutOrder
hList.Padding = UDim.new(0, UITheme.Space.s)
hList.Parent = container

-- State-color dot (8x8 Frame, full corner radius = circle)
local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
dot.BackgroundColor3 = UITheme.Color.info
dot.BorderSizePixel = 0
dot.LayoutOrder = 1
dot.Parent = container
UITheme.corner(dot, "full")

-- State label — heading font, uppercase
local stateLabel = Instance.new("TextLabel")
stateLabel.AutomaticSize = Enum.AutomaticSize.X
stateLabel.Size = UDim2.new(0, 0, 1, 0)
stateLabel.BackgroundTransparency = 1
stateLabel.Font = UITheme.Font.heading
stateLabel.TextSize = UITheme.FontSize.body
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
arrowLabel.TextSize = UITheme.FontSize.body
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
timerLabel.TextSize = UITheme.FontSize.body
timerLabel.TextColor3 = UITheme.Color.textPrimary
timerLabel.Text = "0:00"
timerLabel.LayoutOrder = 4
timerLabel.Parent = container

-- ---------------------------------------------------------------------------
-- Topbar inset compensation (Bug fix: HUD covered by Roblox topbar on mobile)
-- ---------------------------------------------------------------------------
-- IgnoreGuiInset=true means we sit underneath chat/headphones icons unless we
-- manually shift down by the topbar reservation height. TopbarInset signal
-- fires when chat opens/closes or the player rotates the device.
local function refreshTopOffset()
	local topInset = GuiService:GetGuiInset().Y
	-- Tight to topbar — user wants the match chip "mepet atas" (snug against top).
	container.Position = UDim2.new(0.5, 0, 0, topInset + UITheme.Space.xs)
end
refreshTopOffset()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refreshTopOffset)

-- ---------------------------------------------------------------------------
-- Responsive container size
-- ---------------------------------------------------------------------------
local function refreshSize()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	if vw < MOBILE_BREAKPOINT then
		container.Size = UDim2.fromOffset(WIDTH_MOBILE, HEIGHT_MOBILE)
	else
		container.Size = UDim2.fromOffset(WIDTH_DESKTOP, HEIGHT_DESKTOP)
	end
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

return MatchStateController
