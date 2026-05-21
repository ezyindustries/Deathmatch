--!strict
-- ServerBrowserController
--
-- Modal UI yang nge-list public sessions yang lagi running, biar player bisa
-- pilih + join salah satunya alih-alih cuma di-matchmake otomatis. Open lewat
-- ClientSignals.Get("OpenServerBrowser") yang di-fire dari MainMenuController.
--
-- Pattern ngikutin CosmeticsController / ShopController:
-- * ScreenGui dengan IgnoreGuiInset=false biar auto-shift di bawah topbar.
-- * Overlay = TextButton (Modal=true) → absorb input + outside-tap-to-close.
-- * Panel = Frame di tengah overlay, viewport-clamped via UIScale pada PANEL
--   (bukan overlay — kalau scale overlay-nya, area click-outside ikut shrink).
--
-- Backend (sudah ada di Remotes):
--   Remotes.ListPublicSessions:InvokeServer()
--     → { { jobId, mapId, state, players, max, kind }, ... }
--   Remotes.JoinSessionByJobId:InvokeServer(jobId)
--     → { ok = true } atau { ok = false, error = "string" }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local ClientSignals = require(Shared.Modules.ClientSignals)
local UITheme = require(Shared.Modules.UITheme)

local ServerBrowserController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- Types
-- ============================================================================
type Session = {
	jobId: string,
	mapId: string,
	state: string,
	players: number,
	max: number,
	kind: string,
}

-- ============================================================================
-- Layout breakpoints (use ViewportSize.X — Studio Device Emulator quirk)
-- ============================================================================
local function getViewportWidth(): number
	local cam = Workspace.CurrentCamera
	return cam and cam.ViewportSize.X or 1920
end

local function isMobile(): boolean
	return getViewportWidth() < 900
end

-- ============================================================================
-- ScreenGui + overlay (modal)
-- ============================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ServerBrowserHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 160
screenGui.Parent = playerGui

local overlay = Instance.new("TextButton")
overlay.Name = "Overlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.BorderSizePixel = 0
overlay.AutoButtonColor = false
overlay.Text = ""
overlay.Modal = true
overlay.Visible = false
overlay.Parent = screenGui

-- ============================================================================
-- Panel (center)
-- ============================================================================
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(720, 500)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = UITheme.Color.bgBase
panel.BorderSizePixel = 0
panel.Active = true -- absorb tap so outside-click only fires outside the panel
panel.Parent = overlay

UITheme.corner(panel, "lg")
UITheme.stroke(panel, "borderSubtle", 1, 0)

-- UIScale untuk responsive (on panel, NOT overlay — gotcha)
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local function refreshPanelSize()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(720, 500)
	-- Cap base panel size against viewport (don't exceed 95% vw / 92% vh).
	local w = math.min(720, v.X * 0.95)
	local h = math.min(500, v.Y * 0.92)
	panel.Size = UDim2.fromOffset(w, h)
	-- Mobile: scale panel down a bit for breathing room.
	panelScale.Scale = isMobile() and 0.7 or 1.0
end
refreshPanelSize()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshPanelSize)
end

UITheme.padding(panel, "l")

-- ============================================================================
-- Title row (heading + REFRESH + CLOSE)
-- ============================================================================
local titleRow = Instance.new("Frame")
titleRow.Name = "TitleRow"
titleRow.Size = UDim2.new(1, 0, 0, 40)
titleRow.BackgroundTransparency = 1
titleRow.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -220, 1, 0)
title.Position = UDim2.new(0, 0, 0, 0)
title.BackgroundTransparency = 1
title.Font = UITheme.Font.heading
title.TextSize = UITheme.FontSize.h3
title.TextColor3 = UITheme.Color.textPrimary
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextYAlignment = Enum.TextYAlignment.Center
title.Text = "SERVER BROWSER"
title.Parent = titleRow

local refreshBtn = Instance.new("TextButton")
refreshBtn.Name = "RefreshBtn"
refreshBtn.Size = UDim2.new(0, 100, 0, 36)
refreshBtn.AnchorPoint = Vector2.new(1, 0.5)
refreshBtn.Position = UDim2.new(1, -100, 0.5, 0)
refreshBtn.BackgroundColor3 = UITheme.Color.bgElevated
refreshBtn.BorderSizePixel = 0
refreshBtn.AutoButtonColor = false
refreshBtn.Font = UITheme.Font.heading
refreshBtn.TextSize = UITheme.FontSize.caption
refreshBtn.TextColor3 = UITheme.Color.textPrimary
refreshBtn.Text = "REFRESH"
refreshBtn.Parent = titleRow
UITheme.corner(refreshBtn, "md")
UITheme.stroke(refreshBtn, "borderSubtle", 1, 0)

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 90, 0, 36)
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
closeBtn.BackgroundColor3 = UITheme.Color.bgElevated
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Font = UITheme.Font.heading
closeBtn.TextSize = UITheme.FontSize.caption
closeBtn.TextColor3 = UITheme.Color.textPrimary
closeBtn.Text = "X CLOSE"
closeBtn.Parent = titleRow
UITheme.corner(closeBtn, "md")
UITheme.stroke(closeBtn, "borderSubtle", 1, 0)

-- ============================================================================
-- Subtitle
-- ============================================================================
local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(1, 0, 0, 22)
subtitle.Position = UDim2.new(0, 0, 0, 48)
subtitle.BackgroundTransparency = 1
subtitle.Font = UITheme.Font.body
subtitle.TextSize = UITheme.FontSize.caption
subtitle.TextColor3 = UITheme.Color.textSecondary
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = "Pilih session untuk join"
subtitle.Parent = panel

-- ============================================================================
-- List body (ScrollingFrame)
-- ============================================================================
local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "ListBody"
listFrame.Position = UDim2.new(0, 0, 0, 80)
listFrame.Size = UDim2.new(1, 0, 1, -120) -- leave room for title+subtitle+footer
listFrame.BackgroundColor3 = UITheme.Color.bgDeepest
listFrame.BackgroundTransparency = 0.2
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 6
listFrame.ScrollBarImageColor3 = UITheme.Color.borderSubtle
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
listFrame.Parent = panel
UITheme.corner(listFrame, "md")
UITheme.padding(listFrame, "s")

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.Padding = UDim.new(0, UITheme.Space.s)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
listLayout.Parent = listFrame

-- ============================================================================
-- Footer status text
-- ============================================================================
local footer = Instance.new("TextLabel")
footer.Name = "Footer"
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 0, 1, 0)
footer.Size = UDim2.new(1, 0, 0, 24)
footer.BackgroundTransparency = 1
footer.Font = UITheme.Font.body
footer.TextSize = UITheme.FontSize.caption
footer.TextColor3 = UITheme.Color.textTertiary
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = ""
footer.Parent = panel

-- ============================================================================
-- State
-- ============================================================================
local sessions: { Session } = {}
local refreshing: boolean = false
local autoRefreshToken: number = 0

-- ============================================================================
-- Helpers
-- ============================================================================
local function capitalize(s: string): string
	if not s or #s == 0 then
		return s or ""
	end
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

local function stateChipColor(state: string): Color3
	if state == "LOBBY" then
		return UITheme.Color.info
	elseif state == "VOTING" then
		return UITheme.Color.warning
	elseif state == "STARTING" then
		return UITheme.Color.success
	elseif state == "MATCH" then
		return UITheme.Color.danger
	elseif state == "ENDING" then
		return UITheme.Color.textTertiary
	end
	return UITheme.Color.textTertiary
end

local function countColor(playersCount: number, maxCount: number): Color3
	if maxCount > 0 and playersCount >= maxCount then
		return UITheme.Color.danger
	elseif maxCount > 0 and playersCount >= maxCount - 2 then
		return UITheme.Color.warning
	end
	return UITheme.Color.textPrimary
end

local function clearList()
	for _, child in listFrame:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

-- ============================================================================
-- Build session row
-- ============================================================================
local function buildRow(session: Session, index: number)
	local mobile = isMobile()
	local rowHeight = mobile and 64 or 76

	local row = Instance.new("Frame")
	row.Name = "Row_" .. tostring(index)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -8, 0, rowHeight)
	row.BackgroundColor3 = UITheme.Color.bgElevated
	row.BorderSizePixel = 0
	row.Parent = listFrame
	UITheme.corner(row, "md")
	UITheme.padding(row, "s")

	-- Thumbnail placeholder (colored frame, no asset)
	local thumbSize = mobile and 50 or 60
	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.Size = UDim2.fromOffset(thumbSize, thumbSize)
	thumb.AnchorPoint = Vector2.new(0, 0.5)
	thumb.Position = UDim2.new(0, 0, 0.5, 0)
	-- derive a stable color per mapId so different maps look distinct
	local h = 0
	for i = 1, #session.mapId do
		h = (h * 31 + string.byte(session.mapId, i)) % 360
	end
	thumb.BackgroundColor3 = Color3.fromHSV(h / 360, 0.5, 0.55)
	thumb.BorderSizePixel = 0
	thumb.Parent = row
	UITheme.corner(thumb, "sm")
	UITheme.stroke(thumb, "borderSubtle", 1, 0)

	-- Right-side JOIN button
	local joinW = mobile and 80 or 100
	local joinH = mobile and 32 or 40
	local isFull = session.max > 0 and session.players >= session.max

	local joinBtn = Instance.new("TextButton")
	joinBtn.Name = "JoinBtn"
	joinBtn.Size = UDim2.fromOffset(joinW, joinH)
	joinBtn.AnchorPoint = Vector2.new(1, 0.5)
	joinBtn.Position = UDim2.new(1, 0, 0.5, 0)
	joinBtn.BackgroundColor3 = isFull and UITheme.Color.bgDisabled or UITheme.Color.accentPrimary
	joinBtn.BorderSizePixel = 0
	joinBtn.AutoButtonColor = false
	joinBtn.Font = UITheme.Font.heading
	joinBtn.TextSize = UITheme.FontSize.caption
	joinBtn.TextColor3 = isFull and UITheme.Color.textTertiary or UITheme.Color.textInverse
	joinBtn.Text = isFull and "FULL" or "JOIN"
	joinBtn.AutoLocalize = false
	joinBtn.Parent = row
	UITheme.corner(joinBtn, "md")

	-- Middle column: name + state chip + count
	local midLeft = thumbSize + UITheme.Space.m
	local midRight = joinW + UITheme.Space.m
	local mid = Instance.new("Frame")
	mid.Name = "Mid"
	mid.Position = UDim2.new(0, midLeft, 0, 0)
	mid.Size = UDim2.new(1, -(midLeft + midRight), 1, 0)
	mid.BackgroundTransparency = 1
	mid.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0, mobile and 18 or 22)
	nameLabel.Position = UDim2.new(0, 0, 0, mobile and 4 or 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = UITheme.Font.heading
	nameLabel.TextSize = mobile and UITheme.FontSize.caption or UITheme.FontSize.body
	nameLabel.TextColor3 = UITheme.Color.textPrimary
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.Text = capitalize(session.mapId)
	nameLabel.Parent = mid

	-- State + count row (chip on the left, count on the right of mid column)
	local infoRow = Instance.new("Frame")
	infoRow.Name = "InfoRow"
	infoRow.Size = UDim2.new(1, 0, 0, mobile and 18 or 22)
	infoRow.Position = UDim2.new(0, 0, 1, -(mobile and 22 or 28))
	infoRow.BackgroundTransparency = 1
	infoRow.Parent = mid

	-- State chip = small label colored by state
	local chip = Instance.new("TextLabel")
	chip.Name = "StateChip"
	chip.Size = UDim2.fromOffset(78, mobile and 16 or 20)
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, 0, 0.5, 0)
	chip.BackgroundColor3 = stateChipColor(session.state)
	chip.BackgroundTransparency = 0.15
	chip.BorderSizePixel = 0
	chip.Font = UITheme.Font.heading
	chip.TextSize = UITheme.FontSize.micro
	chip.TextColor3 = UITheme.Color.textInverse
	chip.Text = session.state
	chip.Parent = infoRow
	UITheme.corner(chip, "sm")

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.AnchorPoint = Vector2.new(0, 0.5)
	countLabel.Position = UDim2.new(0, 88, 0.5, 0)
	countLabel.Size = UDim2.new(1, -88, 1, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Font = UITheme.Font.heading
	countLabel.TextSize = mobile and UITheme.FontSize.micro or UITheme.FontSize.caption
	countLabel.TextColor3 = countColor(session.players, session.max)
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.TextYAlignment = Enum.TextYAlignment.Center
	countLabel.Text = string.format("%d / %d", session.players, session.max)
	countLabel.Parent = infoRow

	-- JOIN handler
	if isFull then
		-- Disabled: no connect
	else
		joinBtn.MouseButton1Click:Connect(function()
			joinBtn.Text = "Joining..."
			joinBtn.AutoButtonColor = false
			footer.TextColor3 = UITheme.Color.textTertiary
			footer.Text = "Joining " .. capitalize(session.mapId) .. "..."
			local ok, result = pcall(function()
				return Remotes.JoinSessionByJobId:InvokeServer(session.jobId)
			end)
			if ok and typeof(result) == "table" and result.ok then
				overlay.Visible = false
			else
				local errMsg: string
				if ok and typeof(result) == "table" and result.error then
					errMsg = tostring(result.error)
				elseif not ok then
					errMsg = tostring(result)
				else
					errMsg = "Unknown error"
				end
				footer.TextColor3 = UITheme.Color.danger
				footer.Text = "Failed to join: " .. errMsg
				joinBtn.Text = "JOIN"
			end
		end)
	end
end

-- ============================================================================
-- Render whole list
-- ============================================================================
local function renderList()
	clearList()
	for i, session in sessions do
		buildRow(session, i)
	end

	if #sessions == 0 then
		footer.TextColor3 = UITheme.Color.textTertiary
		footer.Text = "No servers — start a private lobby"
	else
		footer.TextColor3 = UITheme.Color.textSecondary
		footer.Text = string.format("%d servers available", #sessions)
	end

	-- Hide subtitle on mobile for vertical room
	subtitle.Visible = not isMobile()
end

-- ============================================================================
-- Refresh
-- ============================================================================
local function doRefresh()
	if refreshing then
		return
	end
	refreshing = true
	refreshBtn.Text = "..."
	refreshBtn.AutoButtonColor = false
	footer.TextColor3 = UITheme.Color.textTertiary
	footer.Text = "Loading..."

	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.ListPublicSessions:InvokeServer()
		end)
		refreshing = false
		refreshBtn.Text = "REFRESH"
		if not overlay.Visible then
			return -- closed while in flight
		end
		if ok and typeof(result) == "table" then
			sessions = result :: { Session }
			renderList()
		else
			sessions = {}
			renderList()
			footer.TextColor3 = UITheme.Color.danger
			footer.Text = "Failed to load servers"
		end
	end)
end

-- ============================================================================
-- Auto-refresh loop (8s) while overlay open
-- ============================================================================
local function startAutoRefreshLoop()
	autoRefreshToken += 1
	local token = autoRefreshToken
	task.spawn(function()
		while overlay.Visible and token == autoRefreshToken do
			task.wait(8)
			if not overlay.Visible or token ~= autoRefreshToken then
				break
			end
			doRefresh()
		end
	end)
end

-- ============================================================================
-- Open / Close
-- ============================================================================
local function openModal()
	if overlay.Visible then
		return
	end
	overlay.Visible = true
	refreshPanelSize()
	-- Clear stale list; re-render placeholder before fetch lands
	sessions = {}
	renderList()
	footer.TextColor3 = UITheme.Color.textTertiary
	footer.Text = "Loading..."
	doRefresh()
	startAutoRefreshLoop()
end

local function closeModal()
	overlay.Visible = false
	autoRefreshToken += 1 -- invalidate any pending loop
end

-- ============================================================================
-- Wire up inputs
-- ============================================================================
closeBtn.MouseButton1Click:Connect(closeModal)
overlay.MouseButton1Click:Connect(closeModal)
refreshBtn.MouseButton1Click:Connect(function()
	doRefresh()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if overlay.Visible and input.KeyCode == Enum.KeyCode.Escape then
		closeModal()
	end
end)

-- ClientSignals: returns a BindableEvent; use .Event:Connect (CosmeticsController pattern)
ClientSignals.Get("OpenServerBrowser").Event:Connect(function()
	openModal()
end)

return ServerBrowserController
