--!strict
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local ClientSignals = require(Shared.Modules.ClientSignals)

local SettingsController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SettingsHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false  -- modal: let Roblox auto-shift below the topbar (Unibar) so title isnt covered
screenGui.DisplayOrder = 150
screenGui.Parent = playerGui

-- Settings button (left side, above loadout)
local button = Instance.new("TextButton")
button.Size = UDim2.new(0, 140, 0, 36)
button.AnchorPoint = Vector2.new(0, 1)
button.Position = UDim2.new(0, 24, 1, -268)
button.BackgroundColor3 = Color3.fromRGB(70, 90, 110)
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.Font = Enum.Font.GothamBold
button.TextSize = 13
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Text = "Settings"
button.Visible = false -- access via MainMenu/PauseMenu
button.Parent = screenGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = button

-- Overlay (TextButton so clicking outside the panel closes the modal). Modal=true
-- prevents input leaking through to lower-DisplayOrder HUDs.
local overlay = Instance.new("TextButton")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.Visible = false
overlay.BorderSizePixel = 0
overlay.AutoButtonColor = false
overlay.Text = ""
overlay.Modal = true
overlay.Parent = screenGui

-- Auto-scale modal to fit small screens (mobile gets ~0.65, desktop = 1.0).
-- IMPORTANT: parent the UIScale to PANEL (not overlay) — otherwise the entire
-- full-screen overlay scales from its top-left corner, dragging the modal off
-- of center. Panel has AnchorPoint=(0.5,0.5) so scaling it keeps it centered.
local overlayScale = Instance.new("UIScale")
-- Parent is set later, AFTER `panel` is created, so the panel variable exists.
local function refreshOverlayScale()
	local vw = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X or 1920
	-- Ultra-mobile (vw < 600 — iPhone 4S 480x320 landscape) shrinks panel to
	-- ~211 wide × 90% of 320 vh = ~159 tall × 0.44 = 70 pixels rendered. That's
	-- too small for the long scroll list. Keep 0.55 floor (480×0.55 = 264 wide,
	-- fits 95% of 480 viewport easily). The panel's 0.9-vh height also auto-
	-- accommodates ultra-mobile so no separate clamp is needed here.
	if vw < 900 then overlayScale.Scale = 0.55
	elseif vw < 1300 then overlayScale.Scale = 0.8
	else overlayScale.Scale = 1.0 end
end
refreshOverlayScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshOverlayScale)
end

local panel = Instance.new("ScrollingFrame")
panel.Size = UDim2.new(0, 480, 0.9, 0)
panel.CanvasSize = UDim2.new(0, 0, 0, 1240)
panel.ScrollBarThickness = 8
panel.ScrollBarImageColor3 = Color3.fromRGB(120, 130, 150)
panel.ScrollingDirection = Enum.ScrollingDirection.Y
panel.AutomaticCanvasSize = Enum.AutomaticSize.None
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
panel.BorderSizePixel = 0
panel.Active = true -- absorb clicks so they don't bubble to overlay
panel.Parent = overlay

-- Now that panel exists, parent the UIScale to it (see comment near
-- overlayScale declaration). Scaling panel from its center keeps the modal
-- centered on mobile instead of being dragged toward the screen's top-left.
overlayScale.Parent = panel

-- Tap outside panel = close
overlay.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 32)
title.Position = UDim2.new(0, 20, 0, 16)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(120, 180, 220)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Settings"
title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 80, 0, 30)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -20, 0, 18)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "Close"
closeBtn.Parent = panel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeBtn

button.MouseButton1Click:Connect(function()
	overlay.Visible = true
end)
closeBtn.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)
-- ESC to close on desktop
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if overlay.Visible and input.KeyCode == Enum.KeyCode.Escape then
		overlay.Visible = false
	end
end)

local function makeSlider(parent: Frame, yOffset: number, label: string, min: number, max: number, settingKey: string, format: (number) -> string): (Frame, (number) -> ())
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -40, 0, 60)
	row.Position = UDim2.new(0, 20, 0, yOffset)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local labelText = Instance.new("TextLabel")
	labelText.Size = UDim2.new(1, 0, 0, 22)
	labelText.BackgroundTransparency = 1
	labelText.Font = Enum.Font.GothamBold
	labelText.TextSize = 14
	labelText.TextColor3 = Color3.fromRGB(255, 255, 255)
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.Text = label
	labelText.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0, 80, 0, 22)
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, 0, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.GothamMedium
	valueLabel.TextSize = 13
	valueLabel.TextColor3 = Color3.fromRGB(180, 185, 210)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = format(min)
	valueLabel.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 8)
	track.Position = UDim2.new(0, 0, 0, 36)
	track.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	track.BorderSizePixel = 0
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(120, 180, 220)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local thumb = Instance.new("TextButton")
	thumb.Size = UDim2.new(0, 18, 0, 18)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.new(0, 9, 0.5, 0)
	thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	thumb.BorderSizePixel = 0
	thumb.Text = ""
	thumb.Parent = track

	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(1, 0)
	thumbCorner.Parent = thumb

	local function setValue(value: number, fireRemote: boolean)
		value = math.clamp(value, min, max)
		local ratio = (value - min) / (max - min)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		thumb.Position = UDim2.new(ratio, 0, 0.5, 0)
		valueLabel.Text = format(value)
		if fireRemote then
			Remotes.UpdateSetting:FireServer(settingKey, value)
		end
	end

	local dragging = false
	thumb.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local trackAbs = track.AbsolutePosition.X
		local trackWidth = track.AbsoluteSize.X
		local x = input.Position.X - trackAbs
		local ratio = math.clamp(x / trackWidth, 0, 1)
		local value = min + ratio * (max - min)
		setValue(math.floor(value), true)
	end)

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local x = input.Position.X - track.AbsolutePosition.X
			local ratio = math.clamp(x / track.AbsoluteSize.X, 0, 1)
			local value = min + ratio * (max - min)
			setValue(math.floor(value), true)
			dragging = true
		end
	end)

	return row, setValue
end

local _, setVolume = makeSlider(panel, 70, "Master Volume", 0, 100, "masterVolume", function(v) return string.format("%d%%", v) end)
local _, setFov = makeSlider(panel, 150, "Base FOV", 50, 100, "baseFov", function(v) return tostring(v) end)
local _, setSensitivity = makeSlider(panel, 230, "Mouse Sensitivity", 10, 300, "sensitivity", function(v) return string.format("%.2fx", v / 100) end)

-- ============================================================
-- CROSSHAIR EDITOR (CS2-style) — preview window above sliders so changes
-- show live without having to close the settings panel.
-- ============================================================
local crosshairHeader = Instance.new("TextLabel")
crosshairHeader.Size = UDim2.new(1, -40, 0, 24)
crosshairHeader.Position = UDim2.new(0, 20, 0, 310)
crosshairHeader.BackgroundTransparency = 1
crosshairHeader.Font = Enum.Font.GothamBlack
crosshairHeader.TextSize = 14
crosshairHeader.TextColor3 = Color3.fromRGB(120, 180, 220)
crosshairHeader.TextXAlignment = Enum.TextXAlignment.Left
crosshairHeader.Text = "✛ CROSSHAIR"
crosshairHeader.Parent = panel

-- ----- Preview viewport (mimics in-game scene so the crosshair sits on top of
-- something representative, like the editor in CS / Valorant) -----
local previewBox = Instance.new("Frame")
previewBox.Size = UDim2.new(1, -40, 0, 140)
previewBox.Position = UDim2.new(0, 20, 0, 340)
previewBox.BackgroundColor3 = Color3.fromRGB(45, 55, 70)
previewBox.BorderSizePixel = 0
previewBox.ClipsDescendants = true
previewBox.Parent = panel

local previewCorner = Instance.new("UICorner")
previewCorner.CornerRadius = UDim.new(0, 8)
previewCorner.Parent = previewBox

-- Subtle gradient + a low-contrast "horizon line" so the preview looks like a
-- game view instead of a flat box.
local previewGradient = Instance.new("UIGradient")
previewGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 95, 130)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(50, 60, 75)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 35, 45)),
})
previewGradient.Rotation = 90
previewGradient.Parent = previewBox

local horizon = Instance.new("Frame")
horizon.Size = UDim2.new(1, 0, 0, 1)
horizon.AnchorPoint = Vector2.new(0, 0.5)
horizon.Position = UDim2.new(0, 0, 0.55, 0)
horizon.BackgroundColor3 = Color3.fromRGB(120, 130, 145)
horizon.BackgroundTransparency = 0.7
horizon.BorderSizePixel = 0
horizon.Parent = previewBox

local previewLabel = Instance.new("TextLabel")
previewLabel.Size = UDim2.new(0, 90, 0, 18)
previewLabel.AnchorPoint = Vector2.new(0, 0)
previewLabel.Position = UDim2.new(0, 8, 0, 6)
previewLabel.BackgroundTransparency = 1
previewLabel.Font = Enum.Font.GothamBold
previewLabel.TextSize = 10
previewLabel.TextColor3 = Color3.fromRGB(180, 200, 220)
previewLabel.TextTransparency = 0.3
previewLabel.TextXAlignment = Enum.TextXAlignment.Left
previewLabel.Text = "PREVIEW"
previewLabel.Parent = previewBox

-- Crosshair root: anchored to viewport center; line parts are children with
-- relative positions so a single redraw updates everything.
local previewXhair = Instance.new("Frame")
previewXhair.Size = UDim2.new(0, 1, 0, 1)
previewXhair.AnchorPoint = Vector2.new(0.5, 0.5)
previewXhair.Position = UDim2.new(0.5, 0, 0.5, 0)
previewXhair.BackgroundTransparency = 1
previewXhair.Parent = previewBox

local function makeLine(name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	f.Parent = previewXhair
	return f
end

local lineTop    = makeLine("Top")
local lineBottom = makeLine("Bottom")
local lineLeft   = makeLine("Left")
local lineRight  = makeLine("Right")
local centerDot  = makeLine("Dot")

-- Outline strokes (one per line) — black border around the white crosshair.
-- ApplyStrokeMode.Contextual is required for Frames (Border is text-only); plus
-- thickness 1.5 so the outline is clearly visible against the dark preview bg.
local function strokeFor(line: Frame): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(0, 0, 0)
	s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.Enabled = false
	s.Parent = line
	return s
end
local strokes = {
	strokeFor(lineTop),
	strokeFor(lineBottom),
	strokeFor(lineLeft),
	strokeFor(lineRight),
	strokeFor(centerDot),
}

-- Live preview state — kept in sync with the sliders/toggles below. Defaults
-- match GameConfig defaults so the preview looks right before any data loads.
local previewState = {
	length = 6,
	thickness = 2,
	offset = 7,
	dot = true,
	outline = false,
	color = Color3.fromRGB(255, 255, 255),
}

local function redrawPreview()
	local len = math.max(0, previewState.length)
	local thick = math.max(1, previewState.thickness)
	local gap = math.max(0, previewState.offset)
	local color = previewState.color

	-- Top line sits above center by (gap + len/2); bottom mirrors. Left/Right same on X axis.
	lineTop.Size       = UDim2.new(0, thick, 0, len)
	lineTop.Position   = UDim2.new(0, 0, 0, -(gap + len / 2))
	lineBottom.Size    = UDim2.new(0, thick, 0, len)
	lineBottom.Position= UDim2.new(0, 0, 0,  (gap + len / 2))
	lineLeft.Size      = UDim2.new(0, len, 0, thick)
	lineLeft.Position  = UDim2.new(0, -(gap + len / 2), 0, 0)
	lineRight.Size     = UDim2.new(0, len, 0, thick)
	lineRight.Position = UDim2.new(0,  (gap + len / 2), 0, 0)

	for _, l in { lineTop, lineBottom, lineLeft, lineRight } do
		l.BackgroundColor3 = color
	end

	-- Center dot — same thickness in both axes, sits exactly at center
	centerDot.Visible = previewState.dot
	centerDot.Size = UDim2.new(0, thick, 0, thick)
	centerDot.Position = UDim2.new(0, 0, 0, 0)
	centerDot.BackgroundColor3 = color

	-- Outline: toggle all strokes together
	for _, s in strokes do
		s.Enabled = previewState.outline
	end
end
redrawPreview()

-- ----- Sliders (shifted down by 150 so the preview fits above) -----
local _, setCrossLen_raw   = makeSlider(panel, 500, "Length",    1, 20, "crosshair_length",    function(v) return tostring(v) end)
local _, setCrossThick_raw = makeSlider(panel, 560, "Thickness", 1, 6,  "crosshair_thickness", function(v) return tostring(v) end)
local _, setCrossOff_raw   = makeSlider(panel, 620, "Gap",       0, 20, "crosshair_offset",    function(v) return tostring(v) end)

-- Wrap each setter so dragging the slider updates the preview immediately
-- (without waiting on the server round-trip via PlayerDataChanged).
local function setCrossLen(v: number, fire: boolean)
	setCrossLen_raw(v, fire)
	previewState.length = v
	redrawPreview()
end
local function setCrossThick(v: number, fire: boolean)
	setCrossThick_raw(v, fire)
	previewState.thickness = v
	redrawPreview()
end
local function setCrossOff(v: number, fire: boolean)
	setCrossOff_raw(v, fire)
	previewState.offset = v
	redrawPreview()
end

-- Toggle row (Dot + Outline inline)
local toggleRowCH = Instance.new("Frame")
toggleRowCH.Size = UDim2.new(1, -40, 0, 36)
toggleRowCH.Position = UDim2.new(0, 20, 0, 688)
toggleRowCH.BackgroundTransparency = 1
toggleRowCH.Parent = panel

local function makeMiniToggle(parent: Instance, label: string, position: UDim2, settingKey: string)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 200, 1, 0)
	frame.Position = position
	frame.BackgroundTransparency = 1
	frame.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 100, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 13
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = label
	lbl.Parent = frame

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 60, 0, 26)
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, 0, 0.5, 0)
	btn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(220, 220, 235)
	btn.Text = "OFF"
	btn.AutoButtonColor = false
	btn.Parent = frame

	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 4)
	bc.Parent = btn

	local state = false
	local function setState(value: boolean, fireRemote: boolean)
		state = value
		if value then
			btn.Text = "ON"
			btn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
			btn.TextColor3 = Color3.fromRGB(20, 30, 20)
		else
			btn.Text = "OFF"
			btn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
			btn.TextColor3 = Color3.fromRGB(220, 220, 235)
		end
		if fireRemote then
			Remotes.UpdateSetting:FireServer(settingKey, value and 1 or 0)
		end
	end
	btn.MouseButton1Click:Connect(function()
		setState(not state, true)
	end)
	return setState
end

local setCrossDot_raw = makeMiniToggle(toggleRowCH, "Center Dot",  UDim2.new(0, 0, 0, 0), "crosshair_dot")
local setCrossOutline_raw = makeMiniToggle(toggleRowCH, "Outline",  UDim2.new(0, 210, 0, 0), "crosshair_outline")

local function setCrossDot(v: boolean, fire: boolean)
	setCrossDot_raw(v, fire)
	previewState.dot = v
	redrawPreview()
end
local function setCrossOutline(v: boolean, fire: boolean)
	setCrossOutline_raw(v, fire)
	previewState.outline = v
	redrawPreview()
end

local _, setCrossR_raw = makeSlider(panel, 740, "Red",   0, 255, "crosshair_r", function(v) return tostring(v) end)
local _, setCrossG_raw = makeSlider(panel, 800, "Green", 0, 255, "crosshair_g", function(v) return tostring(v) end)
local _, setCrossB_raw = makeSlider(panel, 860, "Blue",  0, 255, "crosshair_b", function(v) return tostring(v) end)

local function refreshPreviewColor()
	previewState.color = Color3.fromRGB(
		math.clamp(previewState._r or 255, 0, 255),
		math.clamp(previewState._g or 255, 0, 255),
		math.clamp(previewState._b or 255, 0, 255)
	)
	redrawPreview()
end
local function setCrossR(v: number, fire: boolean)
	setCrossR_raw(v, fire); previewState._r = v; refreshPreviewColor()
end
local function setCrossG(v: number, fire: boolean)
	setCrossG_raw(v, fire); previewState._g = v; refreshPreviewColor()
end
local function setCrossB(v: number, fire: boolean)
	setCrossB_raw(v, fire); previewState._b = v; refreshPreviewColor()
end

-- Killstreak announcement toggle (bottom)
local toggleRow = Instance.new("Frame")
toggleRow.Size = UDim2.new(1, -40, 0, 36)
toggleRow.Position = UDim2.new(0, 20, 0, 930)
toggleRow.BackgroundTransparency = 1
toggleRow.Parent = panel

local toggleLabel = Instance.new("TextLabel")
toggleLabel.Size = UDim2.new(1, -80, 1, 0)
toggleLabel.BackgroundTransparency = 1
toggleLabel.Font = Enum.Font.GothamBold
toggleLabel.TextSize = 14
toggleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
toggleLabel.Text = "Killstreak Announcements"
toggleLabel.Parent = toggleRow

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 70, 0, 32)
toggleBtn.AnchorPoint = Vector2.new(1, 0.5)
toggleBtn.Position = UDim2.new(1, 0, 0.5, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
toggleBtn.BorderSizePixel = 0
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.TextColor3 = Color3.fromRGB(20, 30, 20)
toggleBtn.Text = "ON"
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = toggleRow

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleBtn

local killstreakOn = true
local function setToggle(value: boolean, fireRemote: boolean)
	killstreakOn = value
	if value then
		toggleBtn.Text = "ON"
		toggleBtn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
		toggleBtn.TextColor3 = Color3.fromRGB(20, 30, 20)
	else
		toggleBtn.Text = "OFF"
		toggleBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
		toggleBtn.TextColor3 = Color3.fromRGB(220, 220, 235)
	end
	if fireRemote then
		Remotes.UpdateSetting:FireServer("killstreakAnnouncements", value)
	end
end

toggleBtn.MouseButton1Click:Connect(function()
	setToggle(not killstreakOn, true)
end)

-- Left-handed toggle (mirrors viewmodel to left side of screen)
local lhRow = Instance.new("Frame")
lhRow.Size = UDim2.new(1, -40, 0, 36)
lhRow.Position = UDim2.new(0, 20, 0, 975)
lhRow.BackgroundTransparency = 1
lhRow.Parent = panel

local lhLabel = Instance.new("TextLabel")
lhLabel.Size = UDim2.new(1, -80, 1, 0)
lhLabel.BackgroundTransparency = 1
lhLabel.Font = Enum.Font.GothamBold
lhLabel.TextSize = 14
lhLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
lhLabel.TextXAlignment = Enum.TextXAlignment.Left
lhLabel.Text = "Left-Handed (senjata di kiri)"
lhLabel.Parent = lhRow

local lhBtn = Instance.new("TextButton")
lhBtn.Size = UDim2.new(0, 70, 0, 32)
lhBtn.AnchorPoint = Vector2.new(1, 0.5)
lhBtn.Position = UDim2.new(1, 0, 0.5, 0)
lhBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
lhBtn.BorderSizePixel = 0
lhBtn.Font = Enum.Font.GothamBold
lhBtn.TextSize = 13
lhBtn.TextColor3 = Color3.fromRGB(220, 220, 235)
lhBtn.Text = "OFF"
lhBtn.AutoButtonColor = false
lhBtn.Parent = lhRow

local lhCorner = Instance.new("UICorner")
lhCorner.CornerRadius = UDim.new(0, 8)
lhCorner.Parent = lhBtn

local lhOn = false
local lhSignal = ClientSignals.Get("LeftHandedChanged")
local function setLeftHanded(value: boolean, fireRemote: boolean)
	lhOn = value
	if value then
		lhBtn.Text = "ON"
		lhBtn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
		lhBtn.TextColor3 = Color3.fromRGB(20, 30, 20)
	else
		lhBtn.Text = "OFF"
		lhBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
		lhBtn.TextColor3 = Color3.fromRGB(220, 220, 235)
	end
	lhSignal:Fire(value)
	if fireRemote then
		Remotes.UpdateSetting:FireServer("leftHanded", value and 1 or 0)
	end
end

lhBtn.MouseButton1Click:Connect(function()
	setLeftHanded(not lhOn, true)
end)

-- HUD Edit toggle (mobile only — drag mobile buttons to reposition).
local hudEditRow = Instance.new("Frame")
hudEditRow.Size = UDim2.new(1, -40, 0, 36)
hudEditRow.Position = UDim2.new(0, 20, 0, 1190)
hudEditRow.BackgroundTransparency = 1
hudEditRow.Visible = UserInputService.TouchEnabled -- only show on touch devices
hudEditRow.Parent = panel

local hudEditLbl = Instance.new("TextLabel")
hudEditLbl.Size = UDim2.new(1, -80, 1, 0)
hudEditLbl.BackgroundTransparency = 1
hudEditLbl.Font = Enum.Font.GothamBold
hudEditLbl.TextSize = 14
hudEditLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
hudEditLbl.TextXAlignment = Enum.TextXAlignment.Left
hudEditLbl.Text = "Edit HUD (drag mobile buttons)"
hudEditLbl.Parent = hudEditRow

local hudEditBtn = Instance.new("TextButton")
hudEditBtn.Size = UDim2.new(0, 70, 0, 32)
hudEditBtn.AnchorPoint = Vector2.new(1, 0.5)
hudEditBtn.Position = UDim2.new(1, 0, 0.5, 0)
hudEditBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
hudEditBtn.BorderSizePixel = 0
hudEditBtn.Font = Enum.Font.GothamBold
hudEditBtn.TextSize = 13
hudEditBtn.TextColor3 = Color3.fromRGB(220, 220, 235)
hudEditBtn.Text = "OFF"
hudEditBtn.AutoButtonColor = false
hudEditBtn.Parent = hudEditRow
local hudEditCorner = Instance.new("UICorner"); hudEditCorner.CornerRadius = UDim.new(0, 8); hudEditCorner.Parent = hudEditBtn

local hudEditOn = false
local hudEditSignal = ClientSignals.Get("ToggleHudEdit")
hudEditBtn.MouseButton1Click:Connect(function()
	hudEditOn = not hudEditOn
	if hudEditOn then
		hudEditBtn.Text = "ON"
		hudEditBtn.BackgroundColor3 = Color3.fromRGB(255, 220, 80)
		hudEditBtn.TextColor3 = Color3.fromRGB(40, 30, 10)
		overlay.Visible = false -- close settings so user can drag
	else
		hudEditBtn.Text = "OFF"
		hudEditBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
		hudEditBtn.TextColor3 = Color3.fromRGB(220, 220, 235)
	end
	hudEditSignal:Fire(hudEditOn)
end)

-- ============================================================
-- ADS MODE PICKER (HOLD / TOGGLE) — how right-click enters scope
-- ============================================================
local adsRow = Instance.new("Frame")
adsRow.Size = UDim2.new(1, -40, 0, 36)
adsRow.Position = UDim2.new(0, 20, 0, 1020)
adsRow.BackgroundTransparency = 1
adsRow.Parent = panel

local adsLabel = Instance.new("TextLabel")
adsLabel.Size = UDim2.new(0, 200, 1, 0)
adsLabel.BackgroundTransparency = 1
adsLabel.Font = Enum.Font.GothamBold
adsLabel.TextSize = 14
adsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
adsLabel.TextXAlignment = Enum.TextXAlignment.Left
adsLabel.Text = "Scope (right-click) mode"
adsLabel.Parent = adsRow

local adsSignal = ClientSignals.Get("AdsModeChanged")
local adsModeState = "hold"
local holdBtn = Instance.new("TextButton")
local toggleBtnAds = Instance.new("TextButton")

local function styleAdsBtn(btn: TextButton, active: boolean)
	if active then
		btn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
		btn.TextColor3 = Color3.fromRGB(20, 30, 20)
	else
		btn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
		btn.TextColor3 = Color3.fromRGB(220, 220, 235)
	end
end

local function setAdsMode(mode: string, fireRemote: boolean)
	if mode ~= "hold" and mode ~= "toggle" then return end
	adsModeState = mode
	styleAdsBtn(holdBtn, mode == "hold")
	styleAdsBtn(toggleBtnAds, mode == "toggle")
	adsSignal:Fire(mode)
	if fireRemote then
		Remotes.UpdateSetting:FireServer("adsMode", mode)
	end
end

holdBtn.Size = UDim2.new(0, 70, 0, 32)
holdBtn.AnchorPoint = Vector2.new(1, 0.5)
holdBtn.Position = UDim2.new(1, -80, 0.5, 0)
holdBtn.BorderSizePixel = 0
holdBtn.Font = Enum.Font.GothamBold
holdBtn.TextSize = 12
holdBtn.Text = "HOLD"
holdBtn.AutoButtonColor = false
holdBtn.Parent = adsRow
local holdCorner = Instance.new("UICorner"); holdCorner.CornerRadius = UDim.new(0, 6); holdCorner.Parent = holdBtn
holdBtn.MouseButton1Click:Connect(function() setAdsMode("hold", true) end)

toggleBtnAds.Size = UDim2.new(0, 70, 0, 32)
toggleBtnAds.AnchorPoint = Vector2.new(1, 0.5)
toggleBtnAds.Position = UDim2.new(1, 0, 0.5, 0)
toggleBtnAds.BorderSizePixel = 0
toggleBtnAds.Font = Enum.Font.GothamBold
toggleBtnAds.TextSize = 12
toggleBtnAds.Text = "TOGGLE"
toggleBtnAds.AutoButtonColor = false
toggleBtnAds.Parent = adsRow
local toggleAdsCorner = Instance.new("UICorner"); toggleAdsCorner.CornerRadius = UDim.new(0, 6); toggleAdsCorner.Parent = toggleBtnAds
toggleBtnAds.MouseButton1Click:Connect(function() setAdsMode("toggle", true) end)

-- Initial style (default hold)
setAdsMode("hold", false)

-- ============================================================
-- REDEEM CODE SECTION
-- ============================================================
local redeemHeader = Instance.new("TextLabel")
redeemHeader.Size = UDim2.new(1, -40, 0, 24)
redeemHeader.Position = UDim2.new(0, 20, 0, 1080)
redeemHeader.BackgroundTransparency = 1
redeemHeader.Font = Enum.Font.GothamBlack
redeemHeader.TextSize = 14
redeemHeader.TextColor3 = Color3.fromRGB(255, 200, 100)
redeemHeader.TextXAlignment = Enum.TextXAlignment.Left
redeemHeader.Text = "🎁 REDEEM CODE"
redeemHeader.Parent = panel

local redeemInput = Instance.new("TextBox")
redeemInput.Size = UDim2.new(1, -180, 0, 36)
redeemInput.Position = UDim2.new(0, 20, 0, 1110)
redeemInput.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
redeemInput.BorderSizePixel = 0
redeemInput.Font = Enum.Font.GothamBold
redeemInput.TextSize = 14
redeemInput.TextColor3 = Color3.fromRGB(255, 255, 255)
redeemInput.PlaceholderText = "Enter code..."
redeemInput.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
redeemInput.ClearTextOnFocus = false
redeemInput.Text = ""
redeemInput.Parent = panel
local redeemInputCorner = Instance.new("UICorner")
redeemInputCorner.CornerRadius = UDim.new(0, 6)
redeemInputCorner.Parent = redeemInput

local redeemBtn = Instance.new("TextButton")
redeemBtn.Size = UDim2.new(0, 140, 0, 36)
redeemBtn.AnchorPoint = Vector2.new(1, 0)
redeemBtn.Position = UDim2.new(1, -20, 0, 1110)
redeemBtn.BackgroundColor3 = Color3.fromRGB(80, 160, 80)
redeemBtn.BorderSizePixel = 0
redeemBtn.AutoButtonColor = false
redeemBtn.Font = Enum.Font.GothamBold
redeemBtn.TextSize = 14
redeemBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
redeemBtn.Text = "REDEEM"
redeemBtn.Parent = panel
local redeemBtnCorner = Instance.new("UICorner")
redeemBtnCorner.CornerRadius = UDim.new(0, 6)
redeemBtnCorner.Parent = redeemBtn

local redeemMessage = Instance.new("TextLabel")
redeemMessage.Size = UDim2.new(1, -40, 0, 24)
redeemMessage.Position = UDim2.new(0, 20, 0, 1152)
redeemMessage.BackgroundTransparency = 1
redeemMessage.Font = Enum.Font.Gotham
redeemMessage.TextSize = 12
redeemMessage.TextColor3 = Color3.fromRGB(180, 200, 220)
redeemMessage.TextXAlignment = Enum.TextXAlignment.Left
redeemMessage.Text = ""
redeemMessage.Parent = panel

local function submitCode()
	local code = redeemInput.Text
	if code == "" then return end
	Remotes.RedeemCode:FireServer(code)
end

redeemBtn.MouseButton1Click:Connect(submitCode)
redeemInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then submitCode() end
end)

Remotes.RedeemResult.OnClientEvent:Connect(function(result: any)
	if not result then return end
	if result.success then
		redeemMessage.TextColor3 = Color3.fromRGB(120, 230, 130)
		redeemInput.Text = ""
	else
		redeemMessage.TextColor3 = Color3.fromRGB(230, 130, 130)
	end
	redeemMessage.Text = tostring(result.message or "")
end)

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	local inLobby = payload.state == "LOBBY" or payload.state == "VOTING"
	-- Settings HUD button hidden permanently — access via MainMenu/PauseMenu
	if not inLobby then
		overlay.Visible = false
	end
end)

ClientSignals.Get("OpenSettings").Event:Connect(function()
	overlay.Visible = true
end)

-- Custom sensitivity via mouse delta amplification using GetMouseDelta() in RenderStepped.
-- Roblox blocks UserGameSettings.MouseSensitivity from scripts.
-- Approach: each frame, add extra camera rotation = mouseDelta * (multiplier - 1).
local RunService = game:GetService("RunService")
local sensitivityMultiplier = 1.0

RunService:BindToRenderStep("CustomSensitivity", Enum.RenderPriority.Camera.Value + 1, function()
	local extra = sensitivityMultiplier - 1.0
	if math.abs(extra) < 0.01 then
		return
	end
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		return
	end
	local delta = UserInputService:GetMouseDelta() -- Vector2 since last frame
	if delta.Magnitude < 0.1 then
		return
	end
	local ANGLE_SCALE = 0.0044 * 1.5 -- tune factor to feel right
	local pitchAdd = -delta.Y * ANGLE_SCALE * extra
	local yawAdd = -delta.X * ANGLE_SCALE * extra
	camera.CFrame = camera.CFrame * CFrame.Angles(pitchAdd, yawAdd, 0)
end)

local crosshairSignal = ClientSignals.Get("CrosshairConfigChanged")

local lastApplied = { masterVolume = -1, baseFov = -1, killstreakAnnouncements = nil, sensitivity = -1, leftHanded = nil, adsMode = nil }
local function applyCrosshairFromSettings(s: any)
	crosshairSignal:Fire({
		length = s.crosshair_length,
		thickness = s.crosshair_thickness,
		offset = s.crosshair_offset,
		dot = (s.crosshair_dot or 1) > 0,
		outline = (s.crosshair_outline or 0) > 0,
		color = Color3.fromRGB(s.crosshair_r or 255, s.crosshair_g or 255, s.crosshair_b or 255),
	})
end

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	local settings = data.settings
	if not settings then return end

	if settings.masterVolume ~= lastApplied.masterVolume then
		setVolume(settings.masterVolume, false)
		lastApplied.masterVolume = settings.masterVolume
	end
	if settings.baseFov ~= lastApplied.baseFov then
		setFov(settings.baseFov, false)
		camera.FieldOfView = settings.baseFov
		lastApplied.baseFov = settings.baseFov
	end
	if settings.killstreakAnnouncements ~= lastApplied.killstreakAnnouncements then
		setToggle(settings.killstreakAnnouncements, false)
		lastApplied.killstreakAnnouncements = settings.killstreakAnnouncements
	end
	if settings.sensitivity ~= lastApplied.sensitivity and settings.sensitivity then
		setSensitivity(settings.sensitivity, false)
		sensitivityMultiplier = settings.sensitivity / 100
		lastApplied.sensitivity = settings.sensitivity
	end
	if settings.leftHanded ~= nil and settings.leftHanded ~= lastApplied.leftHanded then
		local val = (settings.leftHanded == true) or (tonumber(settings.leftHanded) or 0) > 0
		setLeftHanded(val, false)
		lastApplied.leftHanded = settings.leftHanded
	end
	if settings.adsMode ~= nil and settings.adsMode ~= lastApplied.adsMode then
		setAdsMode(settings.adsMode, false)
		lastApplied.adsMode = settings.adsMode
	end

	-- Crosshair: sync slider/toggle UI + push config to WeaponController
	if settings.crosshair_length  then setCrossLen(settings.crosshair_length, false) end
	if settings.crosshair_thickness then setCrossThick(settings.crosshair_thickness, false) end
	if settings.crosshair_offset  then setCrossOff(settings.crosshair_offset, false) end
	if settings.crosshair_r       then setCrossR(settings.crosshair_r, false) end
	if settings.crosshair_g       then setCrossG(settings.crosshair_g, false) end
	if settings.crosshair_b       then setCrossB(settings.crosshair_b, false) end
	if settings.crosshair_dot     ~= nil then setCrossDot((settings.crosshair_dot or 0) > 0, false) end
	if settings.crosshair_outline ~= nil then setCrossOutline((settings.crosshair_outline or 0) > 0, false) end
	applyCrosshairFromSettings(settings)
end)

return SettingsController
