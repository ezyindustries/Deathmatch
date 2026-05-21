--!strict
-- JoinByCodeController
-- Modal for joining a private session via a 6-character code (2FA-style UX).
-- Six independent TextBoxes for the code: auto-focus the next box on typing,
-- backspace moves focus back, paste of a full 6-char string distributes
-- across all boxes. Allowed chars: A-Z + 1-9, matching the backend generator
-- (no 0/O/I/L to avoid visual ambiguity).
--
-- Submit hits Remotes.JoinSessionByCode:InvokeServer(code); on ok=true the
-- server teleports the player and this controller doesn't need to do anything
-- else. On ok=false, show the error text in red and clear the boxes.
--
-- Mobile (viewport.X < 900): boxes are 32x44 (vs 40x56 desktop) with 4px gap
-- (vs 8px), panel scaled via UIScale on the PANEL.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local ClientSignals = require(Shared.Modules.ClientSignals)
local UITheme = require(Shared.Modules.UITheme)

local JoinByCodeController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Allowed character set: uppercase A-Z + digits 1-9 (mirrors backend's
-- ambiguity-free generator that excludes 0/O/I/L).
local function isAllowedChar(c: string): boolean
	if #c ~= 1 then return false end
	local b = string.byte(c)
	-- '1'..'9'
	if b >= 49 and b <= 57 then return true end
	-- 'A'..'Z' excluding I (73), L (76), O (79)
	if b >= 65 and b <= 90 and b ~= 73 and b ~= 76 and b ~= 79 then return true end
	return false
end

local function sanitize(raw: string): string
	local out = ""
	for i = 1, #raw do
		local c = string.upper(string.sub(raw, i, i))
		if isAllowedChar(c) then
			out = out .. c
		end
	end
	return out
end

-- ============================================================
-- ScreenGui
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "JoinByCodeHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false -- modal: Roblox auto-shifts below the topbar
screenGui.DisplayOrder = 180
screenGui.Parent = playerGui

-- ============================================================
-- Overlay backdrop (Modal=true)
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
-- Panel
-- ============================================================
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 480, 0, 300)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = UITheme.Color.bgBase
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = overlay
UITheme.corner(panel, "lg")
UITheme.stroke(panel, "borderSubtle", 1)

-- UIScale on PANEL (mobile shrink — keeps modal centered)
local panelScale = Instance.new("UIScale")
panelScale.Scale = 1
panelScale.Parent = panel

local function isMobile(): boolean
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	return vw < 900
end

-- Box sizing constants (re-applied on viewport change). Ultra-mobile shrinks
-- further to 26x36 (the 6-box row needs 6*26 + 5*3 = 171px which fits at
-- iPhone 4S 480px viewport with margins).
local DESKTOP_BOX_W, DESKTOP_BOX_H, DESKTOP_GAP = 40, 56, 8
local MOBILE_BOX_W, MOBILE_BOX_H, MOBILE_GAP = 32, 44, 4
local ULTRA_BOX_W, ULTRA_BOX_H, ULTRA_GAP = 26, 36, 3

-- Resize panel + scale on viewport change. Mobile uses a 380x260 panel
-- (per spec) plus a UIScale fallback for ultra-narrow viewports.
-- Ultra-mobile (vw < 600) shrinks to a 300x220 panel — fits iPhone 4S 480x320
-- with breathing room above the panel for the close X tap target.
local function refreshLayout()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	if vw < 600 then
		panel.Size = UDim2.fromOffset(300, 220)
		panelScale.Scale = 1
	elseif vw < 900 then
		panel.Size = UDim2.fromOffset(380, 260)
		panelScale.Scale = 1
	else
		panel.Size = UDim2.fromOffset(480, 300)
		panelScale.Scale = 1
	end
end
refreshLayout()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		refreshLayout()
	end)
end

-- Top accent stripe
local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.new(1, 0, 0, 3)
accentBar.BackgroundColor3 = UITheme.Color.accentPrimary
accentBar.BorderSizePixel = 0
accentBar.Parent = panel
UITheme.corner(accentBar, "lg")

-- ============================================================
-- Header (title + close X)
-- ============================================================
local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 0, 32)
titleLbl.Position = UDim2.new(0, UITheme.Space.xxl, 0, UITheme.Space.xl)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = UITheme.Font.display
titleLbl.TextSize = UITheme.FontSize.h3
titleLbl.TextColor3 = UITheme.Color.textPrimary
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Text = "JOIN dengan Code"
titleLbl.Parent = panel

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
-- Code box row (6 separate TextBoxes)
-- ============================================================
local boxesRow = Instance.new("Frame")
boxesRow.Size = UDim2.new(1, -2 * UITheme.Space.xxl, 0, 60)
boxesRow.Position = UDim2.new(0, UITheme.Space.xxl, 0, 76)
boxesRow.BackgroundTransparency = 1
boxesRow.Parent = panel

local boxesLayout = Instance.new("UIListLayout")
boxesLayout.FillDirection = Enum.FillDirection.Horizontal
boxesLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
boxesLayout.VerticalAlignment = Enum.VerticalAlignment.Center
boxesLayout.SortOrder = Enum.SortOrder.LayoutOrder
boxesLayout.Padding = UDim.new(0, DESKTOP_GAP)
boxesLayout.Parent = boxesRow

local CODE_LEN = 6

-- Forward declarations so callbacks above their definition still work.
local refreshSubmitEnabled: () -> ()
local getCode: () -> string

-- The 6 visible "boxes" are now display-only TextLabels. All input is
-- captured by a SINGLE invisible TextBox overlaying the entire row.
-- This avoids the per-box-focus race on mobile keyboards that produced
-- duplicate characters + made backspace unreliable (mobile keyboards
-- don't deliver KeyCode.Backspace through individual TextBox InputBegan).
local boxLabels: { TextLabel } = {}
local boxFrames: { Frame } = {}
local boxStrokes: { UIStroke } = {}

for i = 1, CODE_LEN do
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(DESKTOP_BOX_W, DESKTOP_BOX_H)
	frame.BackgroundColor3 = UITheme.Color.bgElevated
	frame.BorderSizePixel = 0
	frame.LayoutOrder = i
	frame.Parent = boxesRow
	UITheme.corner(frame, "sm")
	local stroke = UITheme.stroke(frame, "borderSubtle", 1)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = UITheme.Font.mono
	lbl.TextSize = UITheme.FontSize.h2
	lbl.TextColor3 = UITheme.Color.accentPrimary
	lbl.Text = ""
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Parent = frame

	-- Placeholder dot when empty (subtle, theme tertiary)
	local placeholder = Instance.new("TextLabel")
	placeholder.Size = UDim2.fromScale(1, 1)
	placeholder.BackgroundTransparency = 1
	placeholder.Font = UITheme.Font.body
	placeholder.TextSize = UITheme.FontSize.body
	placeholder.TextColor3 = UITheme.Color.textTertiary
	placeholder.Text = "·"
	placeholder.TextXAlignment = Enum.TextXAlignment.Center
	placeholder.TextYAlignment = Enum.TextYAlignment.Center
	placeholder.Name = "Placeholder"
	placeholder.Parent = frame

	boxFrames[i] = frame
	boxLabels[i] = lbl
	boxStrokes[i] = stroke
end

-- ============================================================
-- Hidden single input — captures all keystrokes, displays via labels
-- ============================================================
local hiddenInput = Instance.new("TextBox")
hiddenInput.Size = UDim2.fromScale(1, 1)
hiddenInput.Position = UDim2.fromScale(0, 0)
hiddenInput.BackgroundTransparency = 1
hiddenInput.TextTransparency = 1 -- text never rendered; only labels show it
hiddenInput.PlaceholderText = ""
hiddenInput.Text = ""
hiddenInput.ClearTextOnFocus = false
hiddenInput.MultiLine = false
hiddenInput.TextEditable = true
hiddenInput.ZIndex = 10 -- above the visual frames so taps reach it
-- Cap input length at CODE_LEN — Roblox itself enforces this on mobile
-- keyboard which prevents the "double character" issue from per-box races.
hiddenInput.Parent = boxesRow

-- Activate / deactivate cursor visually on focus
hiddenInput.Focused:Connect(function()
	-- Highlight first empty box
	for i, f in boxFrames do
		if boxLabels[i].Text == "" then
			boxStrokes[i].Color = UITheme.Color.accentPrimary
			boxStrokes[i].Thickness = 2
			break
		end
	end
end)
hiddenInput.FocusLost:Connect(function()
	for _, s in boxStrokes do
		s.Color = UITheme.Color.borderSubtle
		s.Thickness = 1
	end
end)

-- Tap any box → re-focus the hidden input
for _, frame in boxFrames do
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			hiddenInput:CaptureFocus()
		end
	end)
end

-- Mirror the hidden input's Text to the 6 visible labels. Sanitize +
-- uppercase + clamp to 6 chars. This naturally handles backspace (Roblox
-- TextBox removes the last char → handler updates labels → last label
-- empties + highlight moves back).
local function syncBoxesFromInput()
	local raw = hiddenInput.Text
	local cleaned = sanitize(raw)
	if #cleaned > CODE_LEN then
		cleaned = string.sub(cleaned, 1, CODE_LEN)
	end
	-- If sanitize changed the text (lowercase, invalid chars), feed it back
	-- so future backspaces work against the cleaned version.
	if cleaned ~= raw then
		hiddenInput.Text = cleaned
		return -- the assignment fires this handler again with the cleaned value
	end
	-- Update each label
	for i = 1, CODE_LEN do
		local char = string.sub(cleaned, i, i)
		boxLabels[i].Text = char
		local placeholder = boxFrames[i]:FindFirstChild("Placeholder")
		if placeholder and placeholder:IsA("TextLabel") then
			placeholder.Visible = char == ""
		end
	end
	-- Highlight the box at the current input position (first empty)
	for i, s in boxStrokes do
		if i == #cleaned + 1 and hiddenInput:IsFocused() then
			s.Color = UITheme.Color.accentPrimary
			s.Thickness = 2
		elseif boxLabels[i].Text ~= "" then
			s.Color = UITheme.Color.borderSubtle
			s.Thickness = 1
		else
			s.Color = UITheme.Color.borderSubtle
			s.Thickness = 1
		end
	end
	refreshSubmitEnabled()
end

hiddenInput:GetPropertyChangedSignal("Text"):Connect(syncBoxesFromInput)

-- Replace boxes[] references with boxLabels[] so the rest of the file works.
local boxes = boxLabels

local function focusBox(_index: number)
	hiddenInput:CaptureFocus()
end

-- Resize boxes + gap on viewport change. Ultra-mobile (vw < 600) uses 26x36
-- so 6 boxes + 5 gaps fit comfortably inside the 300x220 ultra-mobile panel.
local function refreshBoxes()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	local ultra = vw < 600
	local mobile = vw < 900
	local w, h, gap, fontSize
	if ultra then
		w, h, gap, fontSize = ULTRA_BOX_W, ULTRA_BOX_H, ULTRA_GAP, UITheme.FontSize.bodyLg
	elseif mobile then
		w, h, gap, fontSize = MOBILE_BOX_W, MOBILE_BOX_H, MOBILE_GAP, UITheme.FontSize.h3
	else
		w, h, gap, fontSize = DESKTOP_BOX_W, DESKTOP_BOX_H, DESKTOP_GAP, UITheme.FontSize.h2
	end
	for i, f in boxFrames do
		f.Size = UDim2.fromOffset(w, h)
		boxLabels[i].TextSize = fontSize
		local ph = f:FindFirstChild("Placeholder")
		if ph and ph:IsA("TextLabel") then
			ph.TextSize = math.floor(fontSize * 0.8)
		end
	end
	boxesLayout.Padding = UDim.new(0, gap)
end
refreshBoxes()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshBoxes)
end

-- ============================================================
-- Error text + buttons
-- ============================================================
local errorLbl = Instance.new("TextLabel")
errorLbl.Size = UDim2.new(1, -2 * UITheme.Space.xxl, 0, 20)
errorLbl.Position = UDim2.new(0, UITheme.Space.xxl, 0, 152)
errorLbl.BackgroundTransparency = 1
errorLbl.Font = UITheme.Font.body
errorLbl.TextSize = UITheme.FontSize.caption
errorLbl.TextColor3 = UITheme.Color.danger
errorLbl.TextXAlignment = Enum.TextXAlignment.Center
errorLbl.Text = ""
errorLbl.Parent = panel

local joinBtn = Instance.new("TextButton")
joinBtn.Size = UDim2.new(0.5, -UITheme.Space.xxl - UITheme.Space.xs, 0, UITheme.TouchTarget.comfortable)
joinBtn.AnchorPoint = Vector2.new(0, 1)
joinBtn.Position = UDim2.new(0, UITheme.Space.xxl, 1, -UITheme.Space.xxl)
joinBtn.BackgroundColor3 = UITheme.Color.bgDisabled
joinBtn.BorderSizePixel = 0
joinBtn.AutoButtonColor = false
joinBtn.Font = UITheme.Font.display
joinBtn.TextSize = UITheme.FontSize.body
joinBtn.TextColor3 = UITheme.Color.textTertiary
joinBtn.Text = "JOIN"
joinBtn.Parent = panel
UITheme.corner(joinBtn, "md")
local joinStroke = UITheme.stroke(joinBtn, "borderSubtle", 1)

local cancelBtn = Instance.new("TextButton")
cancelBtn.Size = UDim2.new(0.5, -UITheme.Space.xxl - UITheme.Space.xs, 0, UITheme.TouchTarget.comfortable)
cancelBtn.AnchorPoint = Vector2.new(1, 1)
cancelBtn.Position = UDim2.new(1, -UITheme.Space.xxl, 1, -UITheme.Space.xxl)
cancelBtn.BackgroundColor3 = UITheme.Color.bgElevated
cancelBtn.BorderSizePixel = 0
cancelBtn.AutoButtonColor = false
cancelBtn.Font = UITheme.Font.heading
cancelBtn.TextSize = UITheme.FontSize.body
cancelBtn.TextColor3 = UITheme.Color.textSecondary
cancelBtn.Text = "BATAL"
cancelBtn.Parent = panel
UITheme.corner(cancelBtn, "md")
UITheme.stroke(cancelBtn, "borderSubtle", 1)

-- ============================================================
-- Submit gating + helpers
-- ============================================================
getCode = function(): string
	-- Single source of truth: read directly from the hidden input (already
	-- sanitized + clamped to CODE_LEN by syncBoxesFromInput).
	return hiddenInput.Text
end

refreshSubmitEnabled = function()
	local code = getCode()
	local enabled = #code == CODE_LEN
	joinBtn.Active = enabled
	if enabled then
		joinBtn.BackgroundColor3 = UITheme.Color.accentPrimary
		joinBtn.TextColor3 = UITheme.Color.textInverse
		joinStroke.Color = UITheme.Color.accentPrimary
	else
		joinBtn.BackgroundColor3 = UITheme.Color.bgDisabled
		joinBtn.TextColor3 = UITheme.Color.textTertiary
		joinStroke.Color = UITheme.Color.borderSubtle
	end
end

local function clearBoxes()
	hiddenInput.Text = "" -- triggers syncBoxesFromInput → clears all labels
	refreshSubmitEnabled()
	hiddenInput:CaptureFocus()
end

local function setOpen(value: boolean)
	overlay.Visible = value
	if value then
		errorLbl.Text = ""
		clearBoxes()
		-- Slight delay so the input system has the modal mounted before focus.
		task.defer(function()
			if overlay.Visible then focusBox(1) end
		end)
	end
end

refreshSubmitEnabled()

-- ============================================================
-- Wiring
-- ============================================================
local isJoining = false

joinBtn.MouseButton1Click:Connect(function()
	if not joinBtn.Active or isJoining then return end
	local code = getCode()
	if #code ~= CODE_LEN then return end
	isJoining = true
	joinBtn.Text = "JOINING…"
	errorLbl.Text = ""

	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.JoinSessionByCode:InvokeServer(code)
		end)
		isJoining = false
		joinBtn.Text = "JOIN"
		if not ok then
			errorLbl.Text = "Gagal: " .. tostring(result)
			clearBoxes()
			return
		end
		if not result or not result.ok then
			local err = (result and result.error) or "Code tidak ditemukan"
			errorLbl.Text = tostring(err)
			clearBoxes()
			return
		end
		-- Success: server teleports — modal just stays until teleport happens.
		setOpen(false)
	end)
end)

cancelBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)

closeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)

overlay.MouseButton1Click:Connect(function()
	-- Outside-tap close (panel.Active=true above absorbs taps inside it).
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if overlay.Visible and input.KeyCode == Enum.KeyCode.Escape then
		setOpen(false)
	end
end)

-- Signal-driven open from MainMenuController (Agent D wires this).
ClientSignals.Get("OpenJoinByCode").Event:Connect(function()
	setOpen(true)
end)

return JoinByCodeController
