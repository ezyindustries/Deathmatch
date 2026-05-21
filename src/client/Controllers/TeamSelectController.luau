--!strict
-- TeamSelectController — modal for picking team A ("Tim Kawan") or B ("Tim Lawan")
-- in 10v10 Team Deathmatch.
--
-- Opens via:
--   • Remotes.OpenTeamSelect.OnClientEvent (server force-opens, e.g. match start)
--   • ClientSignals.Get("OpenTeamSelect"):Fire() (e.g. scoreboard "Change Team" btn)
--
-- Live-updates per-team counts from Remotes.TeamStateChanged. Smaller team gets
-- a pulsing "recommended" stroke; full team (=TEAM_SIZE) shows a "FULL" overlay
-- with disabled JOIN.
--
-- AUTO-ASSIGN button always fires "AUTO" — server picks the smaller side.
--
-- Cooldown UX: TeamAssigned payload includes lockedUntil (os.time epoch). While
-- lockedUntil > now, JOIN for the OTHER team is disabled and shows "Switch tim
-- dalam Xs" countdown on both cards. Current team's JOIN stays disabled too
-- (re-joining your own team is a no-op).
--
-- Stickiness: if the local player has never been assigned a team, ESC/outside-
-- tap CANNOT close the modal — they MUST pick. Once they have a team, ESC and
-- outside-tap dismiss as usual.
--
-- Mobile (vw < 900): stack vertically (TIM KAWAN top, TIM LAWAN bottom),
-- cards 280x120, gap 8, title drops from h2 → h3.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local UITheme = require(Shared.Modules.UITheme)
local DMTeams = require(Shared.Modules.DMTeams)
local ClientSignals = require(Shared.Modules.ClientSignals)

local TeamSelectController = {}

local MOBILE_BREAKPOINT = 900

local function isMobileViewport(): boolean
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	return vw < MOBILE_BREAKPOINT
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local localTeam: string? = nil       -- "A" | "B" | nil (never assigned)
local lockedUntil: number = 0         -- os.time epoch when switch cooldown ends
local lastTeamState: {
	teamA: { players: number, kills: number, deaths: number }?,
	teamB: { players: number, kills: number, deaths: number }?,
}? = nil

-- ---------------------------------------------------------------------------
-- Build UI tree
-- ---------------------------------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeamSelectHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
-- Higher than PauseMenu (200) and any HUD layer — this modal can be forced
-- open on match start and must sit above everything else.
screenGui.DisplayOrder = 220
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Modal overlay backdrop (TextButton + Modal=true so the dimmed area absorbs
-- taps and doesn't pass through to in-match HUD buttons underneath).
local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
backdrop.BackgroundTransparency = 0.25
backdrop.BorderSizePixel = 0
backdrop.AutoButtonColor = false
backdrop.Modal = true
backdrop.Text = ""
backdrop.Parent = screenGui

-- Main panel (anchored center)
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(640, 360) -- desktop default; overridden in refreshResponsive
panel.BackgroundColor3 = UITheme.Color.bgBase
panel.BorderSizePixel = 0
panel.Parent = screenGui
UITheme.corner(panel, "lg")
UITheme.stroke(panel, "borderSubtle", 1)

-- Title ("PILIH TIM")
local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, UITheme.Space.l)
title.Size = UDim2.new(1, -UITheme.Space.xxl * 2, 0, 32)
title.BackgroundTransparency = 1
title.Font = UITheme.Font.heading
title.TextSize = UITheme.FontSize.h2
title.TextColor3 = UITheme.Color.textPrimary
title.TextXAlignment = Enum.TextXAlignment.Center
title.Text = "PILIH TIM"
title.Parent = panel

-- Cards container (horizontal on desktop, vertical on mobile)
local cardsContainer = Instance.new("Frame")
cardsContainer.Name = "Cards"
cardsContainer.AnchorPoint = Vector2.new(0.5, 0)
cardsContainer.Position = UDim2.new(0.5, 0, 0, 64)
cardsContainer.Size = UDim2.new(1, -UITheme.Space.xxl * 2, 0, 180)
cardsContainer.BackgroundTransparency = 1
cardsContainer.Parent = panel

local cardsLayout = Instance.new("UIListLayout")
cardsLayout.FillDirection = Enum.FillDirection.Horizontal
cardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsLayout.Padding = UDim.new(0, UITheme.Space.l)
cardsLayout.Parent = cardsContainer

-- ---------------------------------------------------------------------------
-- Team card builder
-- ---------------------------------------------------------------------------
type CardRefs = {
	frame: Frame,
	countLabel: TextLabel,
	colorChip: TextLabel,
	joinBtn: TextButton,
	fullOverlay: Frame,
	cooldownLabel: TextLabel,
	stroke: UIStroke,
}

local cardA: CardRefs
local cardB: CardRefs

local function buildCard(teamId: string, layoutOrder: number): CardRefs
	local color = DMTeams.Colors[teamId]
	local displayName = DMTeams.Display[teamId]

	local frame = Instance.new("Frame")
	frame.Name = "Card_" .. teamId
	frame.Size = UDim2.fromOffset(240, 180)
	frame.BackgroundColor3 = UITheme.Color.bgElevated
	frame.BorderSizePixel = 0
	frame.LayoutOrder = layoutOrder
	frame.Parent = cardsContainer
	UITheme.corner(frame, "md")
	local stroke = UITheme.stroke(frame, "borderSubtle", 1)

	-- Subtle team-tinted gradient
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(
			math.min(1, color.R * 0.4 + 0.05),
			math.min(1, color.G * 0.4 + 0.05),
			math.min(1, color.B * 0.4 + 0.05)
		)),
		ColorSequenceKeypoint.new(1, UITheme.Color.bgElevated),
	})
	grad.Rotation = 90
	grad.Parent = frame

	-- Team name label
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "Name"
	nameLbl.AnchorPoint = Vector2.new(0.5, 0)
	nameLbl.Position = UDim2.new(0.5, 0, 0, UITheme.Space.m)
	nameLbl.Size = UDim2.new(1, -UITheme.Space.m * 2, 0, 28)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = UITheme.Font.heading
	nameLbl.TextSize = UITheme.FontSize.h3
	nameLbl.TextColor3 = color
	nameLbl.TextXAlignment = Enum.TextXAlignment.Center
	nameLbl.Text = string.upper(displayName)
	nameLbl.Parent = frame

	-- Count label "X / 10"
	local countLbl = Instance.new("TextLabel")
	countLbl.Name = "Count"
	countLbl.AnchorPoint = Vector2.new(0.5, 0)
	countLbl.Position = UDim2.new(0.5, 0, 0, 48)
	countLbl.Size = UDim2.new(1, -UITheme.Space.m * 2, 0, 36)
	countLbl.BackgroundTransparency = 1
	countLbl.Font = UITheme.Font.mono
	countLbl.TextSize = UITheme.FontSize.h2
	countLbl.TextColor3 = UITheme.Color.textPrimary
	countLbl.TextXAlignment = Enum.TextXAlignment.Center
	countLbl.Text = string.format("0 / %d", DMTeams.TEAM_SIZE)
	countLbl.Parent = frame

	-- Color chip ("(BLUE)" / "(RED)")
	local chipLbl = Instance.new("TextLabel")
	chipLbl.Name = "Chip"
	chipLbl.AnchorPoint = Vector2.new(0.5, 0)
	chipLbl.Position = UDim2.new(0.5, 0, 0, 88)
	chipLbl.Size = UDim2.new(1, -UITheme.Space.m * 2, 0, 16)
	chipLbl.BackgroundTransparency = 1
	chipLbl.Font = UITheme.Font.body
	chipLbl.TextSize = UITheme.FontSize.caption
	chipLbl.TextColor3 = UITheme.Color.textTertiary
	chipLbl.TextXAlignment = Enum.TextXAlignment.Center
	chipLbl.Text = teamId == "A" and "(BLUE)" or "(RED)"
	chipLbl.Parent = frame

	-- JOIN button
	local joinBtn = Instance.new("TextButton")
	joinBtn.Name = "Join"
	joinBtn.AnchorPoint = Vector2.new(0.5, 1)
	joinBtn.Position = UDim2.new(0.5, 0, 1, -UITheme.Space.m)
	joinBtn.Size = UDim2.new(1, -UITheme.Space.l * 2, 0, UITheme.TouchTarget.min)
	joinBtn.BackgroundColor3 = color
	joinBtn.AutoButtonColor = false
	joinBtn.Font = UITheme.Font.heading
	joinBtn.TextSize = UITheme.FontSize.body
	joinBtn.TextColor3 = UITheme.Color.textInverse
	joinBtn.Text = "JOIN"
	joinBtn.BorderSizePixel = 0
	joinBtn.Parent = frame
	UITheme.corner(joinBtn, "md")

	-- Cooldown overlay label (initially hidden, set during Tick when lockedUntil > now)
	local cooldownLbl = Instance.new("TextLabel")
	cooldownLbl.Name = "Cooldown"
	cooldownLbl.AnchorPoint = Vector2.new(0.5, 1)
	cooldownLbl.Position = UDim2.new(0.5, 0, 1, -(UITheme.Space.m + UITheme.TouchTarget.min + UITheme.Space.xs))
	cooldownLbl.Size = UDim2.new(1, -UITheme.Space.l * 2, 0, 14)
	cooldownLbl.BackgroundTransparency = 1
	cooldownLbl.Font = UITheme.Font.body
	cooldownLbl.TextSize = UITheme.FontSize.micro
	cooldownLbl.TextColor3 = UITheme.Color.warning
	cooldownLbl.TextXAlignment = Enum.TextXAlignment.Center
	cooldownLbl.Text = ""
	cooldownLbl.Visible = false
	cooldownLbl.Parent = frame

	-- FULL overlay (covers card when team has TEAM_SIZE players)
	local fullOverlay = Instance.new("Frame")
	fullOverlay.Name = "FullOverlay"
	fullOverlay.Size = UDim2.fromScale(1, 1)
	fullOverlay.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	fullOverlay.BackgroundTransparency = 0.25
	fullOverlay.BorderSizePixel = 0
	fullOverlay.Visible = false
	fullOverlay.ZIndex = 5
	fullOverlay.Parent = frame
	UITheme.corner(fullOverlay, "md")

	local fullLbl = Instance.new("TextLabel")
	fullLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	fullLbl.Position = UDim2.fromScale(0.5, 0.5)
	fullLbl.Size = UDim2.new(1, 0, 0, 40)
	fullLbl.BackgroundTransparency = 1
	fullLbl.Font = UITheme.Font.display
	fullLbl.TextSize = UITheme.FontSize.h2
	fullLbl.TextColor3 = UITheme.Color.danger
	fullLbl.TextXAlignment = Enum.TextXAlignment.Center
	fullLbl.Text = "FULL"
	fullLbl.ZIndex = 6
	fullLbl.Parent = fullOverlay

	return {
		frame = frame,
		countLabel = countLbl,
		colorChip = chipLbl,
		joinBtn = joinBtn,
		fullOverlay = fullOverlay,
		cooldownLabel = cooldownLbl,
		stroke = stroke,
	}
end

cardA = buildCard("A", 1)
cardB = buildCard("B", 2)

-- ---------------------------------------------------------------------------
-- AUTO-ASSIGN button + footer
-- ---------------------------------------------------------------------------
local autoBtn = Instance.new("TextButton")
autoBtn.Name = "AutoAssign"
autoBtn.AnchorPoint = Vector2.new(0.5, 1)
autoBtn.Position = UDim2.new(0.5, 0, 1, -52)
autoBtn.Size = UDim2.fromOffset(280, 40)
autoBtn.BackgroundColor3 = UITheme.Color.bgHover
autoBtn.AutoButtonColor = false
autoBtn.Font = UITheme.Font.heading
autoBtn.TextSize = UITheme.FontSize.body
autoBtn.TextColor3 = UITheme.Color.textPrimary
autoBtn.Text = "AUTO-ASSIGN"
autoBtn.BorderSizePixel = 0
autoBtn.Parent = panel
UITheme.corner(autoBtn, "md")
UITheme.stroke(autoBtn, "accentPrimary", 1, 0.5)

local footerLabel = Instance.new("TextLabel")
footerLabel.Name = "Footer"
footerLabel.AnchorPoint = Vector2.new(0.5, 1)
footerLabel.Position = UDim2.new(0.5, 0, 1, -UITheme.Space.m)
footerLabel.Size = UDim2.new(1, -UITheme.Space.l * 2, 0, 18)
footerLabel.BackgroundTransparency = 1
footerLabel.Font = UITheme.Font.body
footerLabel.TextSize = UITheme.FontSize.micro
footerLabel.TextColor3 = UITheme.Color.textTertiary
footerLabel.TextXAlignment = Enum.TextXAlignment.Center
footerLabel.Text = string.format("Switch tim ada cooldown %ds", DMTeams.SWITCH_COOLDOWN_SEC)
footerLabel.Parent = panel

-- ---------------------------------------------------------------------------
-- Toast (post-assignment confirmation, e.g. "JOINED TIM KAWAN")
-- ---------------------------------------------------------------------------
local toast = Instance.new("Frame")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 64)
toast.Size = UDim2.fromOffset(280, 44)
toast.BackgroundColor3 = UITheme.Color.bgBase
toast.BorderSizePixel = 0
toast.Visible = false
toast.Parent = screenGui
UITheme.corner(toast, "md")
local toastStroke = UITheme.stroke(toast, "accentPrimary", 2)

local toastLabel = Instance.new("TextLabel")
toastLabel.AnchorPoint = Vector2.new(0.5, 0.5)
toastLabel.Position = UDim2.fromScale(0.5, 0.5)
toastLabel.Size = UDim2.new(1, -UITheme.Space.m, 1, 0)
toastLabel.BackgroundTransparency = 1
toastLabel.Font = UITheme.Font.heading
toastLabel.TextSize = UITheme.FontSize.body
toastLabel.TextColor3 = UITheme.Color.textPrimary
toastLabel.TextXAlignment = Enum.TextXAlignment.Center
toastLabel.Text = ""
toastLabel.Parent = toast

-- ---------------------------------------------------------------------------
-- Responsive layout
-- ---------------------------------------------------------------------------
local function refreshResponsive()
	local mobile = isMobileViewport()
	if mobile then
		-- Stack vertically: 280x120 cards, gap 8. Title shrinks h2 → h3.
		panel.Size = UDim2.fromOffset(320, 460)
		title.TextSize = UITheme.FontSize.h3
		title.Size = UDim2.new(1, -UITheme.Space.l * 2, 0, 24)

		cardsContainer.Position = UDim2.new(0.5, 0, 0, 52)
		cardsContainer.Size = UDim2.new(1, -UITheme.Space.l * 2, 0, 256) -- 2*120 + 8 gap + breathing room
		cardsLayout.FillDirection = Enum.FillDirection.Vertical
		cardsLayout.Padding = UDim.new(0, UITheme.Space.s)

		for _, ref in { cardA, cardB } do
			ref.frame.Size = UDim2.fromOffset(280, 120)
			-- Reposition inner elements for shorter card
			local name = ref.frame:FindFirstChild("Name") :: TextLabel
			local count = ref.countLabel
			local chip = ref.colorChip
			name.Position = UDim2.new(0.5, 0, 0, UITheme.Space.s)
			name.TextSize = UITheme.FontSize.body
			count.Position = UDim2.new(0.5, 0, 0, 30)
			count.TextSize = UITheme.FontSize.h3
			chip.Position = UDim2.new(0.5, 0, 0, 60)
			ref.joinBtn.Size = UDim2.new(1, -UITheme.Space.l * 2, 0, 32)
			ref.joinBtn.Position = UDim2.new(0.5, 0, 1, -UITheme.Space.s)
			ref.cooldownLabel.Position = UDim2.new(0.5, 0, 1, -(UITheme.Space.s + 32 + 2))
		end

		autoBtn.Size = UDim2.fromOffset(240, 36)
		autoBtn.Position = UDim2.new(0.5, 0, 1, -44)
		footerLabel.Position = UDim2.new(0.5, 0, 1, -UITheme.Space.s)
	else
		panel.Size = UDim2.fromOffset(640, 380)
		title.TextSize = UITheme.FontSize.h2
		title.Size = UDim2.new(1, -UITheme.Space.l * 2, 0, 32)

		cardsContainer.Position = UDim2.new(0.5, 0, 0, 64)
		cardsContainer.Size = UDim2.new(1, -UITheme.Space.xxl * 2, 0, 200)
		cardsLayout.FillDirection = Enum.FillDirection.Horizontal
		cardsLayout.Padding = UDim.new(0, UITheme.Space.l)

		for _, ref in { cardA, cardB } do
			ref.frame.Size = UDim2.fromOffset(240, 200)
			local name = ref.frame:FindFirstChild("Name") :: TextLabel
			name.Position = UDim2.new(0.5, 0, 0, UITheme.Space.m)
			name.TextSize = UITheme.FontSize.h3
			ref.countLabel.Position = UDim2.new(0.5, 0, 0, 48)
			ref.countLabel.TextSize = UITheme.FontSize.h2
			ref.colorChip.Position = UDim2.new(0.5, 0, 0, 88)
			ref.joinBtn.Size = UDim2.new(1, -UITheme.Space.l * 2, 0, UITheme.TouchTarget.min)
			ref.joinBtn.Position = UDim2.new(0.5, 0, 1, -UITheme.Space.m)
			ref.cooldownLabel.Position = UDim2.new(0.5, 0, 1, -(UITheme.Space.m + UITheme.TouchTarget.min + UITheme.Space.xs))
		end

		autoBtn.Size = UDim2.fromOffset(280, 40)
		autoBtn.Position = UDim2.new(0.5, 0, 1, -52)
		footerLabel.Position = UDim2.new(0.5, 0, 1, -UITheme.Space.m)
	end
end
refreshResponsive()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshResponsive)
end

-- ---------------------------------------------------------------------------
-- Recommended-team pulsing glow (smaller team gets accent stroke)
-- ---------------------------------------------------------------------------
-- Single shared pulse loop so we don't spawn redundant tasks. A monotonic token
-- invalidates stale loops if the recommended team flips mid-pulse.
local pulseToken = 0

local function startPulse(stroke: UIStroke, myToken: number)
	task.spawn(function()
		local t = 0
		while myToken == pulseToken and stroke.Parent do
			t += task.wait(0.06)
			-- Sine-wave thickness 1 → 3 over ~1.4s period
			local k = (math.sin(t * 4.5) + 1) * 0.5 -- 0..1
			stroke.Thickness = 1 + k * 2
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Card state refresh (count, FULL overlay, recommended highlight, JOIN enable)
-- ---------------------------------------------------------------------------
local function refreshCards()
	local aCount = (lastTeamState and lastTeamState.teamA and lastTeamState.teamA.players) or 0
	local bCount = (lastTeamState and lastTeamState.teamB and lastTeamState.teamB.players) or 0

	cardA.countLabel.Text = string.format("%d / %d", aCount, DMTeams.TEAM_SIZE)
	cardB.countLabel.Text = string.format("%d / %d", bCount, DMTeams.TEAM_SIZE)

	-- Bump pulse token so all old loops die before we start fresh ones.
	pulseToken += 1

	-- FULL overlay
	local aFull = aCount >= DMTeams.TEAM_SIZE
	local bFull = bCount >= DMTeams.TEAM_SIZE
	cardA.fullOverlay.Visible = aFull
	cardB.fullOverlay.Visible = bFull

	-- Cooldown lock: if locked, the OPPOSING team button is disabled. The
	-- player's CURRENT team button is also disabled (no point joining your
	-- own team again).
	local now = os.time()
	local locked = lockedUntil > now
	local remainingLock = math.max(0, lockedUntil - now)

	local function setJoinEnabled(ref: CardRefs, teamId: string, enabled: boolean, dimmedReason: string?)
		local btn = ref.joinBtn
		btn.AutoButtonColor = enabled
		btn.Active = enabled
		btn.Selectable = enabled
		if enabled then
			btn.BackgroundColor3 = DMTeams.Colors[teamId]
			btn.TextColor3 = UITheme.Color.textInverse
			btn.Text = "JOIN"
		else
			btn.BackgroundColor3 = UITheme.Color.bgDisabled
			btn.TextColor3 = UITheme.Color.textTertiary
			btn.Text = dimmedReason or "—"
		end
	end

	-- Reset cooldown labels
	cardA.cooldownLabel.Visible = false
	cardB.cooldownLabel.Visible = false

	setJoinEnabled(cardA, "A", not aFull, aFull and "FULL" or nil)
	setJoinEnabled(cardB, "B", not bFull, bFull and "FULL" or nil)

	if locked then
		local cooldownText = string.format("Switch tim dalam %ds", remainingLock)
		cardA.cooldownLabel.Text = cooldownText
		cardA.cooldownLabel.Visible = true
		cardB.cooldownLabel.Text = cooldownText
		cardB.cooldownLabel.Visible = true
		-- Disable the OPPOSING team JOIN (can't switch yet)
		if localTeam == "A" then
			setJoinEnabled(cardA, "A", false, "JOINED")
			setJoinEnabled(cardB, "B", false, "LOCKED")
		elseif localTeam == "B" then
			setJoinEnabled(cardA, "A", false, "LOCKED")
			setJoinEnabled(cardB, "B", false, "JOINED")
		end
	else
		-- No lock: show "JOINED" on the current team so the user knows
		if localTeam == "A" and not aFull then
			setJoinEnabled(cardA, "A", false, "JOINED")
		elseif localTeam == "B" and not bFull then
			setJoinEnabled(cardB, "B", false, "JOINED")
		end
	end

	-- Recommended glow: smaller team (only if not full + not locked OUT of it)
	local recommendedTeam: string? = nil
	if not aFull and not bFull then
		if aCount < bCount then recommendedTeam = "A"
		elseif bCount < aCount then recommendedTeam = "B" end
	elseif not aFull then recommendedTeam = "A"
	elseif not bFull then recommendedTeam = "B" end

	-- Reset strokes
	cardA.stroke.Color = UITheme.Color.borderSubtle
	cardA.stroke.Thickness = 1
	cardB.stroke.Color = UITheme.Color.borderSubtle
	cardB.stroke.Thickness = 1

	if recommendedTeam == "A" then
		cardA.stroke.Color = UITheme.Color.accentPrimary
		startPulse(cardA.stroke, pulseToken)
	elseif recommendedTeam == "B" then
		cardB.stroke.Color = UITheme.Color.accentPrimary
		startPulse(cardB.stroke, pulseToken)
	end
end

-- Cooldown tick: re-render labels every second while modal visible + locked
RunService.Heartbeat:Connect(function()
	if not screenGui.Enabled then return end
	if lockedUntil > os.time() then
		-- Cheap path: only refresh card cooldown TEXT, no full layout pass
		local remaining = lockedUntil - os.time()
		local txt = string.format("Switch tim dalam %ds", remaining)
		if cardA.cooldownLabel.Visible then cardA.cooldownLabel.Text = txt end
		if cardB.cooldownLabel.Visible then cardB.cooldownLabel.Text = txt end
	elseif cardA.cooldownLabel.Visible or cardB.cooldownLabel.Visible then
		-- Cooldown just expired → re-eval JOIN button enablement
		refreshCards()
	end
end)

-- ---------------------------------------------------------------------------
-- Open / Close
-- ---------------------------------------------------------------------------
local function openModal()
	screenGui.Enabled = true
	refreshCards()
end

local function closeModal()
	-- Sticky if player hasn't picked a team yet
	if localTeam == nil then return end
	screenGui.Enabled = false
end

-- ---------------------------------------------------------------------------
-- Toast (post-assign confirmation)
-- ---------------------------------------------------------------------------
local function showToast(teamId: string)
	local displayName = DMTeams.Display[teamId]
	local color = DMTeams.Colors[teamId]
	toastLabel.Text = string.format("JOINED %s", string.upper(displayName))
	toastLabel.TextColor3 = color
	toastStroke.Color = color
	toast.Visible = true
	-- Auto-hide after linger duration
	task.delay(UITheme.Duration.linger * 0.5, function()
		toast.Visible = false
	end)
end

-- ---------------------------------------------------------------------------
-- Input wiring
-- ---------------------------------------------------------------------------
backdrop.MouseButton1Click:Connect(function()
	closeModal()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if not screenGui.Enabled then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		closeModal()
	end
end)

cardA.joinBtn.MouseButton1Click:Connect(function()
	if not cardA.joinBtn.Active then return end
	Remotes.ChooseTeam:FireServer("A")
end)
cardB.joinBtn.MouseButton1Click:Connect(function()
	if not cardB.joinBtn.Active then return end
	Remotes.ChooseTeam:FireServer("B")
end)
autoBtn.MouseButton1Click:Connect(function()
	Remotes.ChooseTeam:FireServer("AUTO")
end)

-- Hover affordance for AUTO button
autoBtn.MouseEnter:Connect(function()
	autoBtn.BackgroundColor3 = UITheme.Color.bgPressed
end)
autoBtn.MouseLeave:Connect(function()
	autoBtn.BackgroundColor3 = UITheme.Color.bgHover
end)

-- ---------------------------------------------------------------------------
-- Remote subscriptions
-- ---------------------------------------------------------------------------
Remotes.OpenTeamSelect.OnClientEvent:Connect(function()
	openModal()
end)

ClientSignals.Get("OpenTeamSelect").Event:Connect(function()
	openModal()
end)

Remotes.TeamStateChanged.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then return end
	lastTeamState = payload
	if screenGui.Enabled then
		refreshCards()
	end
end)

Remotes.TeamAssigned.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then return end
	local team = payload.team
	if team ~= "A" and team ~= "B" then return end
	localTeam = team
	lockedUntil = tonumber(payload.lockedUntil) or 0
	showToast(team)
	screenGui.Enabled = false
end)

-- ---------------------------------------------------------------------------
-- Pure helpers exposed for tests (no Roblox instances touched)
-- ---------------------------------------------------------------------------
-- Recommended team given player counts. Tie / both equal returns nil.
function TeamSelectController.computeRecommended(aCount: number, bCount: number, teamSize: number): string?
	local aFull = aCount >= teamSize
	local bFull = bCount >= teamSize
	if aFull and bFull then return nil end
	if aFull then return "B" end
	if bFull then return "A" end
	if aCount < bCount then return "A"
	elseif bCount < aCount then return "B" end
	return nil
end

-- Whether the modal should be sticky (cannot be closed) given current team.
function TeamSelectController.isSticky(currentTeam: string?): boolean
	return currentTeam == nil
end

return TeamSelectController
