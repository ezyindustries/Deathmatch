--!strict
-- PrivateLobbyController
-- Two-stage modal for Private Party flow:
--   Stage A "Create": prompts host to create a reserved server. Calls
--     Remotes.CreatePrivateLobby:InvokeServer(); on success the server-side
--     handler teleports the host into the reserved server. Stage A stays as
--     fallback in case the teleport fails or this controller persists across
--     spawn (ResetOnSpawn=false).
--   Stage B "Lobby": shown once Remotes.PrivateLobbyUpdate.OnClientEvent fires
--     (host has arrived at the reserved server). Displays the join code with
--     a COPY button, member list with avatars + ready state, START MATCH
--     (host-only, gated on all-ready), and LEAVE LOBBY.
--
-- Stage transition is one-way per session: any update event upgrades the modal
-- from A → B. Closing the modal (via LEAVE or X) resets back to A so a future
-- OpenPrivateLobby signal lands on the create prompt again.
--
-- Mobile (viewport.X < 900): panel UIScale 0.7, code font 22 (vs 28 desktop),
-- member rows 36 tall (vs 44 desktop). Same scale-on-PANEL pattern as
-- PauseMenu/Shop — never scale the overlay or the modal drifts off-center.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local ClientSignals = require(Shared.Modules.ClientSignals)
local UITheme = require(Shared.Modules.UITheme)

local PrivateLobbyController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================
-- ScreenGui (modal layer)
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PrivateLobbyHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false -- modal: Roblox auto-shifts below the topbar
screenGui.DisplayOrder = 180     -- above shop (150), below pause menu (200)
screenGui.Parent = playerGui

-- ============================================================
-- Overlay (Modal=true backdrop, outside-tap dismisses)
-- ============================================================
local overlay = Instance.new("TextButton")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = UITheme.Color.bgDeepest
overlay.BackgroundTransparency = 0.35
overlay.Visible = false
overlay.BorderSizePixel = 0
overlay.AutoButtonColor = false
overlay.Text = ""
overlay.Modal = true
overlay.Parent = screenGui

-- ============================================================
-- Panel (anchored center; absorb taps with Active=true)
-- ============================================================
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 480, 0, 520)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = UITheme.Color.bgBase
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = overlay

UITheme.corner(panel, "lg")
UITheme.stroke(panel, "borderSubtle", 1)

-- UIScale on PANEL (not overlay — see git blame on ShopController). 0.7 on
-- mobile so the 480x520 layout fits a narrow viewport without overflow.
local panelScale = Instance.new("UIScale")
panelScale.Scale = 1
panelScale.Parent = panel

local function isMobile(): boolean
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	return vw < 900
end

local function refreshScale()
	panelScale.Scale = if isMobile() then 0.7 else 1
end
refreshScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
end

-- Thin neon accent stripe on top edge
local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.new(1, 0, 0, 3)
accentBar.Position = UDim2.new(0, 0, 0, 0)
accentBar.BackgroundColor3 = UITheme.Color.accentPrimary
accentBar.BorderSizePixel = 0
accentBar.Parent = panel
UITheme.corner(accentBar, "lg")

-- ============================================================
-- Header (title + close X — shared across both stages)
-- ============================================================
local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 0, 32)
titleLbl.Position = UDim2.new(0, UITheme.Space.xxl, 0, UITheme.Space.xl)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = UITheme.Font.display
titleLbl.TextSize = UITheme.FontSize.h3
titleLbl.TextColor3 = UITheme.Color.textPrimary
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Text = "Buat Private Party"
titleLbl.Parent = panel

local subtitleLbl = Instance.new("TextLabel")
subtitleLbl.Size = UDim2.new(1, -48, 0, 36)
subtitleLbl.Position = UDim2.new(0, UITheme.Space.xxl, 0, UITheme.Space.xxl + 28)
subtitleLbl.BackgroundTransparency = 1
subtitleLbl.Font = UITheme.Font.body
subtitleLbl.TextSize = UITheme.FontSize.caption
subtitleLbl.TextColor3 = UITheme.Color.textSecondary
subtitleLbl.TextXAlignment = Enum.TextXAlignment.Left
subtitleLbl.TextYAlignment = Enum.TextYAlignment.Top
subtitleLbl.TextWrapped = true
subtitleLbl.Text = "Server private cuma untuk kamu + temen. Share code dapet di stage berikut."
subtitleLbl.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -UITheme.Space.xl, 0, UITheme.Space.xl)
closeBtn.BackgroundColor3 = UITheme.Color.bgElevated
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Font = UITheme.Font.display
closeBtn.TextSize = UITheme.FontSize.bodyLg
closeBtn.TextColor3 = UITheme.Color.textSecondary
closeBtn.Text = "X"
closeBtn.Parent = panel
UITheme.corner(closeBtn, "sm")
local closeStroke = UITheme.stroke(closeBtn, "borderSubtle", 1)
closeBtn.MouseEnter:Connect(function()
	closeStroke.Color = UITheme.Color.danger
	closeBtn.TextColor3 = UITheme.Color.textPrimary
end)
closeBtn.MouseLeave:Connect(function()
	closeStroke.Color = UITheme.Color.borderSubtle
	closeBtn.TextColor3 = UITheme.Color.textSecondary
end)

-- ============================================================
-- STAGE A (Create prompt)
-- ============================================================
local stageA = Instance.new("Frame")
stageA.Size = UDim2.new(1, 0, 1, -100)
stageA.Position = UDim2.new(0, 0, 0, 100)
stageA.BackgroundTransparency = 1
stageA.Visible = true
stageA.Parent = panel

-- Hero label (centered, big icon-ish text)
local heroLbl = Instance.new("TextLabel")
heroLbl.Size = UDim2.new(1, -48, 0, 80)
heroLbl.Position = UDim2.new(0, UITheme.Space.xxl, 0, UITheme.Space.l)
heroLbl.BackgroundTransparency = 1
heroLbl.Font = UITheme.Font.display
heroLbl.TextSize = UITheme.FontSize.display
heroLbl.TextColor3 = UITheme.Color.accentPrimary
heroLbl.TextXAlignment = Enum.TextXAlignment.Center
heroLbl.Text = "PRIVATE"
heroLbl.Parent = stageA

local heroSubLbl = Instance.new("TextLabel")
heroSubLbl.Size = UDim2.new(1, -48, 0, 24)
heroSubLbl.Position = UDim2.new(0, UITheme.Space.xxl, 0, 96)
heroSubLbl.BackgroundTransparency = 1
heroSubLbl.Font = UITheme.Font.heading
heroSubLbl.TextSize = UITheme.FontSize.body
heroSubLbl.TextColor3 = UITheme.Color.textSecondary
heroSubLbl.TextXAlignment = Enum.TextXAlignment.Center
heroSubLbl.Text = "Reserved server, dipanggil pakai 6-char code"
heroSubLbl.Parent = stageA

-- Status text under the hero (loading/error message)
local createStatusLbl = Instance.new("TextLabel")
createStatusLbl.Size = UDim2.new(1, -48, 0, 22)
createStatusLbl.Position = UDim2.new(0, UITheme.Space.xxl, 0, 144)
createStatusLbl.BackgroundTransparency = 1
createStatusLbl.Font = UITheme.Font.body
createStatusLbl.TextSize = UITheme.FontSize.caption
createStatusLbl.TextColor3 = UITheme.Color.danger
createStatusLbl.TextXAlignment = Enum.TextXAlignment.Center
createStatusLbl.Text = ""
createStatusLbl.Parent = stageA

-- CREATE button (primary CTA, neon-cyan)
local createBtn = Instance.new("TextButton")
createBtn.Size = UDim2.new(1, -2 * UITheme.Space.xxl, 0, UITheme.TouchTarget.prominent)
createBtn.AnchorPoint = Vector2.new(0, 1)
createBtn.Position = UDim2.new(0, UITheme.Space.xxl, 1, -(UITheme.TouchTarget.comfortable + UITheme.Space.xxl + UITheme.Space.m))
createBtn.BackgroundColor3 = UITheme.Color.accentPrimary
createBtn.BorderSizePixel = 0
createBtn.AutoButtonColor = false
createBtn.Font = UITheme.Font.display
createBtn.TextSize = UITheme.FontSize.bodyLg
createBtn.TextColor3 = UITheme.Color.textInverse
createBtn.Text = "CREATE"
createBtn.Parent = stageA
UITheme.corner(createBtn, "md")
local createStroke = UITheme.stroke(createBtn, "accentPrimary", 1)
createBtn.MouseEnter:Connect(function() createStroke.Thickness = 2 end)
createBtn.MouseLeave:Connect(function() createStroke.Thickness = 1 end)

-- BATAL (cancel, ghost)
local cancelBtn = Instance.new("TextButton")
cancelBtn.Size = UDim2.new(1, -2 * UITheme.Space.xxl, 0, UITheme.TouchTarget.comfortable)
cancelBtn.AnchorPoint = Vector2.new(0, 1)
cancelBtn.Position = UDim2.new(0, UITheme.Space.xxl, 1, -UITheme.Space.xxl)
cancelBtn.BackgroundColor3 = UITheme.Color.bgElevated
cancelBtn.BorderSizePixel = 0
cancelBtn.AutoButtonColor = false
cancelBtn.Font = UITheme.Font.heading
cancelBtn.TextSize = UITheme.FontSize.body
cancelBtn.TextColor3 = UITheme.Color.textSecondary
cancelBtn.Text = "BATAL"
cancelBtn.Parent = stageA
UITheme.corner(cancelBtn, "md")
UITheme.stroke(cancelBtn, "borderSubtle", 1)

-- ============================================================
-- STAGE B (Lobby Open — code + member list + actions)
-- ============================================================
local stageB = Instance.new("Frame")
stageB.Size = UDim2.new(1, 0, 1, -100)
stageB.Position = UDim2.new(0, 0, 0, 100)
stageB.BackgroundTransparency = 1
stageB.Visible = false
stageB.Parent = panel

-- Code row: big mono "XYZ4K7" + COPY pill
local codeRow = Instance.new("Frame")
codeRow.Size = UDim2.new(1, -48, 0, 56)
codeRow.Position = UDim2.new(0, UITheme.Space.xxl, 0, UITheme.Space.s)
codeRow.BackgroundColor3 = UITheme.Color.bgElevated
codeRow.BorderSizePixel = 0
codeRow.Parent = stageB
UITheme.corner(codeRow, "md")
UITheme.stroke(codeRow, "borderSubtle", 1)

local codeLbl = Instance.new("TextLabel")
codeLbl.Size = UDim2.new(1, -110, 1, 0)
codeLbl.Position = UDim2.new(0, UITheme.Space.l, 0, 0)
codeLbl.BackgroundTransparency = 1
codeLbl.Font = UITheme.Font.mono
codeLbl.TextSize = 28
codeLbl.TextColor3 = UITheme.Color.accentPrimary
codeLbl.TextXAlignment = Enum.TextXAlignment.Left
codeLbl.Text = "------"
codeLbl.Parent = codeRow

local copyBtn = Instance.new("TextButton")
copyBtn.Size = UDim2.new(0, 84, 0, 36)
copyBtn.AnchorPoint = Vector2.new(1, 0.5)
copyBtn.Position = UDim2.new(1, -UITheme.Space.s, 0.5, 0)
copyBtn.BackgroundColor3 = UITheme.Color.bgHover
copyBtn.BorderSizePixel = 0
copyBtn.AutoButtonColor = false
copyBtn.Font = UITheme.Font.heading
copyBtn.TextSize = UITheme.FontSize.caption
copyBtn.TextColor3 = UITheme.Color.textPrimary
copyBtn.Text = "COPY"
copyBtn.Parent = codeRow
UITheme.corner(copyBtn, "sm")
local copyStroke = UITheme.stroke(copyBtn, "accentPrimary", 1)
copyBtn.MouseEnter:Connect(function() copyStroke.Thickness = 2 end)
copyBtn.MouseLeave:Connect(function() copyStroke.Thickness = 1 end)

-- Members list (scrolling)
local membersLbl = Instance.new("TextLabel")
membersLbl.Size = UDim2.new(1, -48, 0, 18)
membersLbl.Position = UDim2.new(0, UITheme.Space.xxl, 0, 80)
membersLbl.BackgroundTransparency = 1
membersLbl.Font = UITheme.Font.heading
membersLbl.TextSize = UITheme.FontSize.micro
membersLbl.TextColor3 = UITheme.Color.textTertiary
membersLbl.TextXAlignment = Enum.TextXAlignment.Left
membersLbl.Text = "MEMBERS"
membersLbl.Parent = stageB

local memberScroll = Instance.new("ScrollingFrame")
memberScroll.Size = UDim2.new(1, -48, 0, 200)
memberScroll.Position = UDim2.new(0, UITheme.Space.xxl, 0, 104)
memberScroll.BackgroundTransparency = 1
memberScroll.BorderSizePixel = 0
memberScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
memberScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
memberScroll.ScrollBarThickness = 4
memberScroll.ScrollBarImageColor3 = UITheme.Color.borderSubtle
memberScroll.Parent = stageB

local memberLayout = Instance.new("UIListLayout")
memberLayout.Padding = UDim.new(0, UITheme.Space.xs)
memberLayout.SortOrder = Enum.SortOrder.LayoutOrder
memberLayout.Parent = memberScroll

-- Toggle Ready (for local player) + START MATCH (host) + LEAVE LOBBY
local readyBtn = Instance.new("TextButton")
readyBtn.Size = UDim2.new(0.5, -UITheme.Space.xxl - UITheme.Space.xs, 0, UITheme.TouchTarget.comfortable)
readyBtn.AnchorPoint = Vector2.new(0, 1)
readyBtn.Position = UDim2.new(0, UITheme.Space.xxl, 1, -(UITheme.TouchTarget.comfortable + UITheme.Space.xxl + UITheme.Space.m))
readyBtn.BackgroundColor3 = UITheme.Color.bgElevated
readyBtn.BorderSizePixel = 0
readyBtn.AutoButtonColor = false
readyBtn.Font = UITheme.Font.heading
readyBtn.TextSize = UITheme.FontSize.body
readyBtn.TextColor3 = UITheme.Color.textPrimary
readyBtn.Text = "TOGGLE READY"
readyBtn.Parent = stageB
UITheme.corner(readyBtn, "md")
local readyStroke = UITheme.stroke(readyBtn, "borderSubtle", 1)

local startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.new(0.5, -UITheme.Space.xxl - UITheme.Space.xs, 0, UITheme.TouchTarget.comfortable)
startBtn.AnchorPoint = Vector2.new(1, 1)
startBtn.Position = UDim2.new(1, -UITheme.Space.xxl, 1, -(UITheme.TouchTarget.comfortable + UITheme.Space.xxl + UITheme.Space.m))
startBtn.BackgroundColor3 = UITheme.Color.success
startBtn.BorderSizePixel = 0
startBtn.AutoButtonColor = false
startBtn.Font = UITheme.Font.display
startBtn.TextSize = UITheme.FontSize.body
startBtn.TextColor3 = UITheme.Color.textInverse
startBtn.Text = "START MATCH"
startBtn.Parent = stageB
UITheme.corner(startBtn, "md")
local startStroke = UITheme.stroke(startBtn, "success", 1)
startBtn.MouseEnter:Connect(function() startStroke.Thickness = 2 end)
startBtn.MouseLeave:Connect(function() startStroke.Thickness = 1 end)

local leaveBtn = Instance.new("TextButton")
leaveBtn.Size = UDim2.new(1, -2 * UITheme.Space.xxl, 0, UITheme.TouchTarget.comfortable)
leaveBtn.AnchorPoint = Vector2.new(0, 1)
leaveBtn.Position = UDim2.new(0, UITheme.Space.xxl, 1, -UITheme.Space.xxl)
leaveBtn.BackgroundColor3 = UITheme.Color.bgElevated
leaveBtn.BorderSizePixel = 0
leaveBtn.AutoButtonColor = false
leaveBtn.Font = UITheme.Font.heading
leaveBtn.TextSize = UITheme.FontSize.body
leaveBtn.TextColor3 = UITheme.Color.danger
leaveBtn.Text = "LEAVE LOBBY"
leaveBtn.Parent = stageB
UITheme.corner(leaveBtn, "md")
UITheme.stroke(leaveBtn, "danger", 1)

-- ============================================================
-- State
-- ============================================================
local currentStage: "A" | "B" = "A"
local currentCode: string? = nil
local currentHostUserId: number? = nil
local lastMembers: { { userId: number, name: string, ready: boolean } } = {}
local localReady = false

local function setStage(stage: "A" | "B")
	currentStage = stage
	stageA.Visible = stage == "A"
	stageB.Visible = stage == "B"
	if stage == "A" then
		titleLbl.Text = "Buat Private Party"
		subtitleLbl.Text = "Server private cuma untuk kamu + temen. Share code dapet di stage berikut."
		subtitleLbl.Visible = true
	else
		titleLbl.Text = "Private Lobby"
		subtitleLbl.Text = "Share code dengan temen — mereka pake JOIN BY CODE buat masuk."
		subtitleLbl.Visible = true
	end
end

local function setOpen(value: boolean)
	overlay.Visible = value
	if value then
		-- Start fresh on every open (reset to Stage A unless an update arrives).
		createStatusLbl.Text = ""
		createBtn.Text = "CREATE"
		createBtn.Active = true
		setStage("A")
	end
end

-- ============================================================
-- Member rows
-- ============================================================
local memberRows: { Frame } = {}

local function clearMembers()
	for _, row in memberRows do
		row:Destroy()
	end
	memberRows = {}
end

local function buildMemberRow(member: { userId: number, name: string, ready: boolean }, isLocalPlayer: boolean, isHost: boolean, order: number): Frame
	local rowHeight = if isMobile() then 36 else 44
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, rowHeight)
	row.BackgroundColor3 = UITheme.Color.bgElevated
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = memberScroll
	UITheme.corner(row, "sm")

	-- Avatar (32x32 — pulled async, fallback bg if it fails)
	local avatar = Instance.new("ImageLabel")
	avatar.Size = UDim2.new(0, 32, 0, 32)
	avatar.Position = UDim2.new(0, UITheme.Space.s, 0.5, -16)
	avatar.BackgroundColor3 = UITheme.Color.bgHover
	avatar.BorderSizePixel = 0
	avatar.Image = ""
	avatar.Parent = row
	UITheme.corner(avatar, "sm")
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(member.userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and content and row.Parent then
			avatar.Image = content
		end
	end)

	-- Name + host crown
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -180, 1, 0)
	nameLbl.Position = UDim2.new(0, 32 + 2 * UITheme.Space.s, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = UITheme.Font.heading
	nameLbl.TextSize = UITheme.FontSize.caption
	nameLbl.TextColor3 = if isHost then UITheme.Color.accentWarm else UITheme.Color.textPrimary
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Text = if isHost then (member.name .. "  *HOST") else member.name
	nameLbl.Parent = row

	-- Ready/Not ready chip
	local statusChip = Instance.new("TextLabel")
	statusChip.Size = UDim2.new(0, 96, 0, 24)
	statusChip.AnchorPoint = Vector2.new(1, 0.5)
	statusChip.Position = UDim2.new(1, -UITheme.Space.s, 0.5, 0)
	statusChip.BackgroundColor3 = if member.ready then UITheme.Color.success else UITheme.Color.bgHover
	statusChip.BorderSizePixel = 0
	statusChip.Font = UITheme.Font.display
	statusChip.TextSize = UITheme.FontSize.micro
	statusChip.TextColor3 = if member.ready then UITheme.Color.textInverse else UITheme.Color.textTertiary
	statusChip.Text = if member.ready then "READY" else "NOT READY"
	statusChip.Parent = row
	UITheme.corner(statusChip, "sm")

	-- Visual highlight for local player row
	if isLocalPlayer then
		UITheme.stroke(row, "accentPrimary", 1)
	end

	return row
end

local function rebuildMembers(payload: { code: string?, hostUserId: number?, members: { { userId: number, name: string, ready: boolean } } })
	clearMembers()
	local hostId = payload.hostUserId
	for i, member in payload.members do
		local isLocal = member.userId == player.UserId
		local isHost = hostId ~= nil and member.userId == hostId
		local row = buildMemberRow(member, isLocal, isHost, i)
		table.insert(memberRows, row)
		if isLocal then
			localReady = member.ready
		end
	end
end

local function refreshButtons()
	-- Ready label reflects local state
	if localReady then
		readyBtn.Text = "READY [v]"
		readyBtn.BackgroundColor3 = UITheme.Color.success
		readyBtn.TextColor3 = UITheme.Color.textInverse
		readyStroke.Color = UITheme.Color.success
	else
		readyBtn.Text = "TOGGLE READY"
		readyBtn.BackgroundColor3 = UITheme.Color.bgElevated
		readyBtn.TextColor3 = UITheme.Color.textPrimary
		readyStroke.Color = UITheme.Color.borderSubtle
	end

	-- START MATCH: host only, all-ready gate
	local isHost = currentHostUserId ~= nil and currentHostUserId == player.UserId
	startBtn.Visible = isHost
	if isHost then
		local allReady = #lastMembers > 0
		for _, m in lastMembers do
			if not m.ready then allReady = false; break end
		end
		startBtn.Active = allReady
		startBtn.AutoButtonColor = false
		if allReady then
			startBtn.BackgroundColor3 = UITheme.Color.success
			startBtn.TextColor3 = UITheme.Color.textInverse
			startStroke.Color = UITheme.Color.success
			startBtn.Text = "START MATCH"
		else
			startBtn.BackgroundColor3 = UITheme.Color.bgDisabled
			startBtn.TextColor3 = UITheme.Color.textTertiary
			startStroke.Color = UITheme.Color.borderSubtle
			startBtn.Text = "WAITING…"
		end
	end
end

-- ============================================================
-- Wiring
-- ============================================================
local function showCreateError(msg: string)
	createStatusLbl.Text = msg
	createStatusLbl.TextColor3 = UITheme.Color.danger
end

createBtn.MouseButton1Click:Connect(function()
	if not createBtn.Active then return end
	createBtn.Active = false
	createBtn.Text = "CREATING…"
	createStatusLbl.Text = ""

	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.CreatePrivateLobby:InvokeServer()
		end)
		if not ok then
			showCreateError("Gagal: " .. tostring(result))
			createBtn.Text = "CREATE"
			createBtn.Active = true
			return
		end
		if not result or not result.ok then
			local err = (result and result.error) or "Gagal bikin lobby"
			showCreateError(tostring(err))
			createBtn.Text = "CREATE"
			createBtn.Active = true
			return
		end
		-- Success: server-side handler teleports the host into the reserved
		-- server. If teleport doesn't happen for some reason, surface the
		-- returned code so the user at least sees it.
		if result.code then
			currentCode = result.code
			codeLbl.Text = result.code
			setStage("B")
		end
		createBtn.Text = "CREATE"
		createBtn.Active = true
	end)
end)

cancelBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)

closeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)

overlay.MouseButton1Click:Connect(function()
	-- Tap on dimmed area (outside panel) = close. Panel.Active=true above
	-- absorbs clicks inside so this only fires for true outside-taps.
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if overlay.Visible and input.KeyCode == Enum.KeyCode.Escape then
		setOpen(false)
	end
end)

copyBtn.MouseButton1Click:Connect(function()
	-- Roblox runtime doesn't expose a clipboard API to LocalScripts (only
	-- Studio plugins get `setclipboard`). Best we can do is flash visual
	-- confirmation; the code is already large + selectable visually so the
	-- player can read + share it manually.
	copyBtn.Text = "SHOWN"
	task.delay(1.5, function()
		copyBtn.Text = "COPY"
	end)
end)

readyBtn.MouseButton1Click:Connect(function()
	localReady = not localReady
	Remotes.PrivateLobbyReady:FireServer(localReady)
	refreshButtons()
end)

startBtn.MouseButton1Click:Connect(function()
	if not startBtn.Active then return end
	Remotes.PrivateLobbyStart:FireServer()
end)

leaveBtn.MouseButton1Click:Connect(function()
	task.spawn(function()
		pcall(function() Remotes.LeavePrivateLobby:InvokeServer() end)
	end)
	setOpen(false)
end)

-- PrivateLobbyUpdate from server: payload {code, hostUserId, members:{...}}.
-- First update upgrades Stage A → B; subsequent updates refresh the list.
Remotes.PrivateLobbyUpdate.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then return end
	currentCode = payload.code
	currentHostUserId = payload.hostUserId
	lastMembers = payload.members or {}
	if payload.code then codeLbl.Text = payload.code end
	rebuildMembers(payload)
	refreshButtons()
	if currentStage == "A" then
		setStage("B")
	end
end)

-- Signal-driven open from MainMenuController (Agent D wires this).
ClientSignals.Get("OpenPrivateLobby"):Connect(function()
	setOpen(true)
end)

return PrivateLobbyController
