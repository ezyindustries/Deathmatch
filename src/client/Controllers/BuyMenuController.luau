--!strict
-- BUY MENU — press B during deathmatch to swap weapons mid-life.
--
-- Shows all weapons grouped by slot (Primary / Secondary / Melee). Click a
-- weapon → fires SetLoadout to server, server instantly re-equips so the new
-- weapon is in hand immediately (no need to die first).
--
-- NOTE: this menu shows WEAPONS not SKINS. Karambit etc. are knife skins
-- (accessed via the Cosmetics panel), not separate weapons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local WeaponConfig = require(Shared.Modules.WeaponConfig)
local MatchState = require(Shared.Modules.MatchState)

local BuyMenuController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Theme — match the pause menu's tactical/amber armory look
local BG_BASE   = Color3.fromRGB(18, 20, 26)
local BG_CARD   = Color3.fromRGB(34, 36, 44)
local BG_CARD_H = Color3.fromRGB(46, 50, 60)
local BG_CARD_S = Color3.fromRGB(60, 50, 25)  -- "selected/equipped" tint
local AMBER     = Color3.fromRGB(220, 165, 80)
local TEXT_HI   = Color3.fromRGB(240, 240, 248)
local TEXT_MID  = Color3.fromRGB(170, 175, 190)
local TEXT_DIM  = Color3.fromRGB(95, 100, 115)
local STROKE    = Color3.fromRGB(58, 62, 76)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BuyMenuHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false  -- modal: let Roblox auto-shift below the topbar (Unibar) so title isnt covered
screenGui.DisplayOrder = 140
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Backdrop is a TextButton + Modal=true so input doesn't pass through to the
-- in-match HUD (FIRE/RELOAD/etc) while the menu is open. Tap outside the panel
-- to dismiss (in addition to the X / B key).
local backdrop = Instance.new("TextButton")
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 0.5
backdrop.BorderSizePixel = 0
backdrop.AutoButtonColor = false
backdrop.Text = ""
backdrop.Modal = true
backdrop.Parent = screenGui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 700, 0, 480)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = BG_BASE
panel.BorderSizePixel = 0
panel.Active = true -- absorb taps inside panel so outside-tap-to-close works
panel.Parent = backdrop

-- Mobile viewport clamping via UIScale (shrink whole panel to fit ≤95% vw / ≤92% vh)
local panelScale = Instance.new("UIScale")
panelScale.Scale = 1
panelScale.Parent = panel
local function refreshPanelScale()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local sx = math.min(1, (v.X * 0.95) / 700)
	local sy = math.min(1, (v.Y * 0.92) / 480)
	panelScale.Scale = math.min(sx, sy)
end
refreshPanelScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshPanelScale)
end

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = STROKE
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- Top amber accent bar
local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.new(1, 0, 0, 3)
accentBar.BackgroundColor3 = AMBER
accentBar.BorderSizePixel = 0
accentBar.Parent = panel
local abCorner = Instance.new("UICorner")
abCorner.CornerRadius = UDim.new(0, 10)
abCorner.Parent = accentBar

-- Header
local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 240, 0, 32)
title.Position = UDim2.new(0, 24, 0, 18)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 22
title.TextColor3 = TEXT_HI
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "BUY MENU"
title.Parent = panel

local tagline = Instance.new("TextLabel")
tagline.Size = UDim2.new(0, 280, 0, 14)
tagline.Position = UDim2.new(0, 24, 0, 50)
tagline.BackgroundTransparency = 1
tagline.Font = Enum.Font.GothamBold
tagline.TextSize = 10
tagline.TextColor3 = Color3.fromRGB(140, 100, 50)
tagline.TextXAlignment = Enum.TextXAlignment.Left
tagline.Text = "PRESS B TO TOGGLE  •  WEAPON SWAP IS INSTANT"
tagline.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -20, 0, 20)
closeBtn.BackgroundColor3 = BG_CARD
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 18
closeBtn.TextColor3 = TEXT_MID
closeBtn.Text = "✕"
closeBtn.Parent = panel
local cbCorner = Instance.new("UICorner"); cbCorner.CornerRadius = UDim.new(0, 4); cbCorner.Parent = closeBtn
local cbStroke = Instance.new("UIStroke"); cbStroke.Color = STROKE; cbStroke.Thickness = 1; cbStroke.Parent = closeBtn
closeBtn.MouseEnter:Connect(function()
	closeBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 50)
	closeBtn.TextColor3 = TEXT_HI
end)
closeBtn.MouseLeave:Connect(function()
	closeBtn.BackgroundColor3 = BG_CARD
	closeBtn.TextColor3 = TEXT_MID
end)

local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, -48, 0, 1)
sep.Position = UDim2.new(0, 24, 0, 80)
sep.BackgroundColor3 = STROKE
sep.BorderSizePixel = 0
sep.Parent = panel

-- =====================================================================
-- WEAPON GROUPS — collected from WeaponConfig by slot
-- =====================================================================
type WInfo = { id: string, name: string, tier: string }

local function groupBySlot(slot: string): { WInfo }
	local list: { WInfo } = {}
	for id, def in WeaponConfig do
		if type(def) == "table" and def.slot == slot then
			table.insert(list, { id = id, name = def.displayName or id, tier = def.tier or "Common" })
		end
	end
	-- Stable sort by name for consistent layout
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

local groups = {
	{ slot = "primary",   label = "PRIMARY",   weapons = groupBySlot("primary") },
	{ slot = "secondary", label = "SECONDARY", weapons = groupBySlot("secondary") },
	{ slot = "melee",     label = "MELEE",     weapons = groupBySlot("melee") },
}

-- Track currently selected weapon per slot to update card highlight
local currentLoadout = { primary = "rifle", secondary = "pistol", melee = "knife" }

type CardRef = { card: TextButton, stroke: UIStroke, equippedLabel: TextLabel }
local cardsByWeaponId: { [string]: CardRef } = {}

local function refreshHighlights()
	for id, ref in cardsByWeaponId do
		local equipped = currentLoadout.primary == id
			or currentLoadout.secondary == id
			or currentLoadout.melee == id
		if equipped then
			ref.card.BackgroundColor3 = BG_CARD_S
			ref.stroke.Color = AMBER
			ref.stroke.Thickness = 2
			ref.equippedLabel.Visible = true
		else
			ref.card.BackgroundColor3 = BG_CARD
			ref.stroke.Color = STROKE
			ref.stroke.Thickness = 1
			ref.equippedLabel.Visible = false
		end
	end
end

-- =====================================================================
-- LAYOUT — three columns, one per slot. Each column lists weapon cards.
-- =====================================================================
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -48, 1, -120)
content.Position = UDim2.new(0, 24, 0, 96)
content.BackgroundTransparency = 1
content.Parent = panel

local COL_W = 200
local COL_GAP = 16
local CARD_H = 64
local CARD_GAP = 8

for gi, g in groups do
	local colX = (gi - 1) * (COL_W + COL_GAP)
	local col = Instance.new("Frame")
	col.Size = UDim2.new(0, COL_W, 1, 0)
	col.Position = UDim2.new(0, colX, 0, 0)
	col.BackgroundTransparency = 1
	col.Parent = content

	-- Column header
	local hdr = Instance.new("TextLabel")
	hdr.Size = UDim2.new(1, 0, 0, 22)
	hdr.BackgroundTransparency = 1
	hdr.Font = Enum.Font.GothamBlack
	hdr.TextSize = 12
	hdr.TextColor3 = AMBER
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.Text = g.label
	hdr.Parent = col

	for wi, w in g.weapons do
		local cardY = 28 + (wi - 1) * (CARD_H + CARD_GAP)
		local card = Instance.new("TextButton")
		card.Size = UDim2.new(1, 0, 0, CARD_H)
		card.Position = UDim2.new(0, 0, 0, cardY)
		card.BackgroundColor3 = BG_CARD
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.Text = ""
		card.Parent = col

		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 6); cc.Parent = card
		local cs = Instance.new("UIStroke"); cs.Color = STROKE; cs.Thickness = 1; cs.Parent = card

		-- Weapon name (large)
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -16, 0, 22)
		nameLbl.Position = UDim2.new(0, 12, 0, 8)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBlack
		nameLbl.TextSize = 14
		nameLbl.TextColor3 = TEXT_HI
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = w.name
		nameLbl.Parent = card

		-- Slot id (small, muted) — e.g., "rifle / primary"
		local subLbl = Instance.new("TextLabel")
		subLbl.Size = UDim2.new(1, -16, 0, 14)
		subLbl.Position = UDim2.new(0, 12, 0, 32)
		subLbl.BackgroundTransparency = 1
		subLbl.Font = Enum.Font.Gotham
		subLbl.TextSize = 11
		subLbl.TextColor3 = TEXT_MID
		subLbl.TextXAlignment = Enum.TextXAlignment.Left
		subLbl.Text = string.upper(w.id)
		subLbl.Parent = card

		-- "EQUIPPED" badge in bottom-right when this is the active weapon
		local eqLbl = Instance.new("TextLabel")
		eqLbl.Size = UDim2.new(0, 70, 0, 14)
		eqLbl.AnchorPoint = Vector2.new(1, 1)
		eqLbl.Position = UDim2.new(1, -10, 1, -8)
		eqLbl.BackgroundTransparency = 1
		eqLbl.Font = Enum.Font.GothamBold
		eqLbl.TextSize = 10
		eqLbl.TextColor3 = AMBER
		eqLbl.TextXAlignment = Enum.TextXAlignment.Right
		eqLbl.Text = "● EQUIPPED"
		eqLbl.Visible = false
		eqLbl.Parent = card

		cardsByWeaponId[w.id] = { card = card, stroke = cs, equippedLabel = eqLbl }

		card.MouseEnter:Connect(function()
			cs.Color = AMBER
			cs.Thickness = 2
			card.BackgroundColor3 = BG_CARD_H
		end)
		card.MouseLeave:Connect(function()
			refreshHighlights()
		end)
		card.MouseButton1Click:Connect(function()
			-- Map slot id to SetLoadout args (primary, secondary, melee)
			local p, s, m = nil, nil, nil
			if g.slot == "primary"   then p = w.id end
			if g.slot == "secondary" then s = w.id end
			if g.slot == "melee"     then m = w.id end
			Remotes.SetLoadout:FireServer(p, s, m)
			-- Optimistically update local highlight; server will broadcast
			-- PlayerDataChanged which re-syncs
			if p then currentLoadout.primary = p end
			if s then currentLoadout.secondary = s end
			if m then currentLoadout.melee = m end
			refreshHighlights()
		end)
	end
end

-- =====================================================================
-- VISIBILITY + INPUT (B key, deathmatch only)
-- =====================================================================
local currentState: string? = nil
local currentGamemode: string? = nil

local function setOpen(value: boolean)
	screenGui.Enabled = value
	if value then refreshHighlights() end
end

closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
backdrop.MouseButton1Click:Connect(function() setOpen(false) end)

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	if not payload then return end
	currentState = payload.state
	currentGamemode = payload.gamemode
	-- Auto-close if state leaves MATCH or mode isn't deathmatch
	if not (currentState == MatchState.States.MATCH and currentGamemode == "deathmatch") then
		setOpen(false)
	end
end)

-- Sync loadout from server profile data
Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	if data and data.loadout then
		if data.loadout.primary then currentLoadout.primary = data.loadout.primary end
		if data.loadout.secondary then currentLoadout.secondary = data.loadout.secondary end
		if data.loadout.melee then currentLoadout.melee = data.loadout.melee end
		refreshHighlights()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	-- ESC closes if open (works alongside the X button + tap-outside)
	if screenGui.Enabled and input.KeyCode == Enum.KeyCode.Escape then
		setOpen(false)
		return
	end
	if input.KeyCode ~= Enum.KeyCode.B then return end
	-- Only allow in deathmatch MATCH state (casual has fixed loadouts per round; lobby has the main-menu panel)
	if currentState ~= MatchState.States.MATCH then return end
	if currentGamemode ~= "deathmatch" then return end
	setOpen(not screenGui.Enabled)
end)

return BuyMenuController
