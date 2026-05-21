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

-- Box sizing constants (re-applied on viewport change)
local DESKTOP_BOX_W, DESKTOP_BOX_H, DESKTOP_GAP = 40, 56, 8
local MOBILE_BOX_W, MOBILE_BOX_H, MOBILE_GAP = 32, 44, 4

-- Resize panel + scale on viewport change. Mobile uses a 380x260 panel
-- (per spec) plus a UIScale fallback for ultra-narrow viewports.
local function refreshLayout()
	if isMobile() then
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

local boxes: { TextBox } = {}
local boxStrokes: { UIStroke } = {}

local CODE_LEN = 6

-- Forward declarations so callbacks above their definition still work.
local refreshSubmitEnabled: () -> ()
local getCode: () -> string

local function focusBox(index: number)
	local b = boxes[index]
	if b then
		b:CaptureFocus()
	end
end

local function distributeChars(startIndex: number, chars: string)
	-- Fill chars across boxes starting at startIndex. Each box gets one char.
	local cleaned = sanitize(chars)
	local i = startIndex
	for k = 1, #cleaned do
		if i > CODE_LEN then break end
		boxes[i].Text = string.sub(cleaned, k, k)
		i += 1
	end
	-- Focus the next empty box, or the last one if all filled.
	local nextEmpty = CODE_LEN
	for j = 1, CODE_LEN do
		if boxes[j].Text == "" then
			nextEmpty = j
			break
		end
	end
	focusBox(nextEmpty)
	refreshSubmitEnabled()
end

for i = 1, CODE_LEN do
	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(DESKTOP_BOX_W, DESKTOP_BOX_H)
	box.BackgroundColor3 = UITheme.Color.bgElevated
	box.BorderSizePixel = 0
	box.Font = UITheme.Font.mono
	box.TextSize = UITheme.FontSize.h2
	box.TextColor3 = UITheme.Color.accentPrimary
	box.PlaceholderText = "·"
	box.PlaceholderColor3 = UITheme.Color.textTertiary
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.LayoutOrder = i
	box.Parent = boxesRow
	UITheme.corner(box, "sm")
	local stroke = UITheme.stroke(box, "borderSubtle", 1)
	boxes[i] = box
	boxStrokes[i] = stroke

	box.Focused:Connect(function()
		stroke.Color = UITheme.Color.accentPrimary
		stroke.Thickness = 2
	end)
	box.FocusLost:Connect(function()
		stroke.Color = UITheme.Color.borderSubtle
		stroke.Thickness = 1
	end)

	-- Per-box text gating: enforce single allowed char; treat any longer
	-- input (e.g. paste) as a distribute-across-boxes operation.
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local raw = box.Text
		if raw == "" then
			refreshSubmitEnabled()
			return
		end
		if #raw == 1 then
			local upper = string.upper(raw)
			if isAllowedChar(upper) then
				if upper ~= raw then box.Text = upper end
				-- Auto-advance focus to next box
				if i < CODE_LEN then
					focusBox(i + 1)
				else
					box:ReleaseFocus()
				end
				refreshSubmitEnabled()
			else
				-- Strip invalid char
				box.Text = ""
				refreshSubmitEnabled()
			end
			return
		end
		-- Multi-char input (likely paste): clean, fit single char in this box,
		-- distribute remainder across subsequent boxes.
		local cleaned = sanitize(raw)
		if #cleaned == 0 then
			box.Text = ""
			refreshSubmitEnabled()
			return
		end
		box.Text = string.sub(cleaned, 1, 1)
		if #cleaned > 1 then
			distributeChars(i + 1, string.sub(cleaned, 2))
		else
			if i < CODE_LEN then
				focusBox(i + 1)
			end
			refreshSubmitEnabled()
		end
	end)

	-- Backspace on empty box → move focus left + clear prev box.
	box.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Backspace then
			if box.Text == "" and i > 1 then
				local prev = boxes[i - 1]
				prev.Text = ""
				focusBox(i - 1)
				refreshSubmitEnabled()
			end
		end
	end)
end

-- Resize boxes + gap on viewport change.
local function refreshBoxes()
	local mobile = isMobile()
	local w, h, gap = if mobile then MOBILE_BOX_W else DESKTOP_BOX_W,
		if mobile then MOBILE_BOX_H else DESKTOP_BOX_H,
		if mobile then MOBILE_GAP else DESKTOP_GAP
	for _, b in boxes do
		b.Size = UDim2.fromOffset(w, h)
		b.TextSize = if mobile then UITheme.FontSize.h3 else UITheme.FontSize.h2
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
	local s = ""
	for _, b in boxes do
		s ..= b.Text
	end
	return s
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
	for _, b in boxes do
		b.Text = ""
	end
	refreshSubmitEnabled()
	focusBox(1)
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
ClientSignals.Get("OpenJoinByCode"):Connect(function()
	setOpen(true)
end)

return JoinByCodeController
