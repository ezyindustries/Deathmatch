--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local CosmeticRegistry = require(Shared.Modules.CosmeticRegistry)
local ClientSignals = require(Shared.Modules.ClientSignals)

local CosmeticsController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CosmeticsHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false  -- modal: let Roblox auto-shift below the topbar (Unibar) so title isnt covered
screenGui.DisplayOrder = 150
screenGui.Parent = playerGui

-- Open button (left side, below loadout)
local button = Instance.new("TextButton")
button.Size = UDim2.new(0, 140, 0, 36)
button.AnchorPoint = Vector2.new(0, 1)
button.Position = UDim2.new(0, 24, 1, -228)
button.BackgroundColor3 = Color3.fromRGB(180, 90, 220)
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.Font = Enum.Font.GothamBold
button.TextSize = 13
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Text = "Cosmetics"
button.Visible = false -- access via MainMenu/PauseMenu
button.Parent = screenGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = button

-- Overlay panel (TextButton + Modal=true so taps don't leak through; tap
-- outside the panel dismisses)
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

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 800, 0, 540)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
panel.BorderSizePixel = 0
panel.Active = true -- absorb taps so outside-tap-to-close only fires outside panel
panel.Parent = overlay

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

-- Viewport-clamped sizing. On small viewports (mobile portrait/landscape) the
-- old fixed 800x540 panel extended off-screen — cutting off the top + bottom
-- (so tabs and close buttons became unreachable). Clamp to a fraction of the
-- live viewport and reapply whenever the viewport changes (e.g. orientation).
local function refreshPanelSize()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(800, 540)
	local w = math.min(800, v.X * 0.95)
	local h = math.min(540, v.Y * 0.92)
	panel.Size = UDim2.fromOffset(w, h)
end
refreshPanelSize()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshPanelSize)
end

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 32)
title.Position = UDim2.new(0, 20, 0, 16)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(200, 130, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Cosmetics"
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
-- Outside-tap = close
overlay.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)
-- ESC to close on desktop
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if overlay.Visible and input.KeyCode == Enum.KeyCode.Escape then
		overlay.Visible = false
	end
end)

-- Tabs (actual weapon names — Glock/AK/UMP/AWP + Knife category)
local TABS = {
	{ key = "skin_pistol", label = "Glock", slot = "skin_pistol", typeKey = "weapon_skin_pistol" },
	{ key = "skin_rifle", label = "AK", slot = "skin_rifle", typeKey = "weapon_skin_rifle" },
	{ key = "skin_smg", label = "UMP", slot = "skin_smg", typeKey = "weapon_skin_smg" },
	{ key = "skin_sniper", label = "AWP", slot = "skin_sniper", typeKey = "weapon_skin_sniper" },
	{ key = "skin_knife", label = "Knife", slot = "skin_knife", typeKey = "weapon_skin_knife" },
	{ key = "emote", label = "Emotes", slot = "emote", typeKey = "emote" },
}

-- Horizontal scrolling tab bar so all 6 tabs remain reachable when panel is
-- clamped narrow on mobile (6 * 100 + padding = 636 > many mobile widths).
local tabBar = Instance.new("ScrollingFrame")
tabBar.Size = UDim2.new(1, -40, 0, 36)
tabBar.Position = UDim2.new(0, 20, 0, 60)
tabBar.BackgroundTransparency = 1
tabBar.BorderSizePixel = 0
tabBar.ScrollBarThickness = 0
tabBar.ScrollingDirection = Enum.ScrollingDirection.X
tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
tabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
tabBar.Parent = panel

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabBar

local tabButtons: { [string]: TextButton } = {}
local activeTab = TABS[1].key

local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -40, 1, -140)
content.Position = UDim2.new(0, 20, 0, 104)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 6
content.ScrollBarImageColor3 = Color3.fromRGB(100, 105, 130)
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, 170, 0, 130)
grid.CellPadding = UDim2.new(0, 10, 0, 10)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = content

local function renderTab(tabKey: string)
	for _, c in content:GetChildren() do
		if c:IsA("Frame") or c:IsA("TextButton") then
			c:Destroy()
		end
	end

	local tab
	for _, t in TABS do
		if t.key == tabKey then
			tab = t
			break
		end
	end
	if not tab then
		return
	end

	local pool = CosmeticRegistry.ByType[tab.typeKey] or {}
	local sorted = table.clone(pool)
	local tierOrder = { Legendary = 4, Epic = 3, Rare = 2, Common = 1 }
	table.sort(sorted, function(a, b)
		return (tierOrder[a.tier] or 0) > (tierOrder[b.tier] or 0)
	end)

	local profile = cachedProfile or { inventory = {}, equipped = {} }
	local equipped = (profile.equipped or {})[tab.slot]
	local inventory = profile.inventory or {}

	for index, cosmetic in sorted do
		local owned = inventory[cosmetic.id] == true
		local isEquipped = equipped == cosmetic.id

		local card = Instance.new("Frame")
		card.LayoutOrder = index
		card.BackgroundColor3 = owned and Color3.fromRGB(32, 32, 44) or Color3.fromRGB(22, 22, 30)
		card.BorderSizePixel = 0
		card.Parent = content

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 10)
		cardCorner.Parent = card

		local tierStrip = Instance.new("Frame")
		tierStrip.Size = UDim2.new(1, 0, 0, 4)
		tierStrip.BackgroundColor3 = CosmeticRegistry.TierColors[cosmetic.tier] or Color3.fromRGB(180, 180, 180)
		tierStrip.BorderSizePixel = 0
		tierStrip.Parent = card

		local colorPreview = Instance.new("Frame")
		colorPreview.Size = UDim2.new(1, -16, 0, 28)
		colorPreview.Position = UDim2.new(0, 8, 0, 12)
		colorPreview.BackgroundColor3 = cosmetic.color
		colorPreview.BackgroundTransparency = owned and 0 or 0.7
		colorPreview.BorderSizePixel = 0
		colorPreview.Parent = card
		local pcCorner = Instance.new("UICorner")
		pcCorner.CornerRadius = UDim.new(0, 6)
		pcCorner.Parent = colorPreview

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -16, 0, 18)
		nameLabel.Position = UDim2.new(0, 8, 0, 46)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 12
		nameLabel.TextColor3 = owned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(140, 140, 155)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = cosmetic.displayName
		nameLabel.Parent = card

		local tierLabel = Instance.new("TextLabel")
		tierLabel.Size = UDim2.new(1, -16, 0, 14)
		tierLabel.Position = UDim2.new(0, 8, 0, 66)
		tierLabel.BackgroundTransparency = 1
		tierLabel.Font = Enum.Font.GothamMedium
		tierLabel.TextSize = 10
		tierLabel.TextColor3 = CosmeticRegistry.TierColors[cosmetic.tier] or Color3.fromRGB(180, 180, 180)
		tierLabel.TextXAlignment = Enum.TextXAlignment.Left
		tierLabel.Text = string.upper(cosmetic.tier)
		tierLabel.Parent = card

		local actionBtn = Instance.new("TextButton")
		actionBtn.Size = UDim2.new(1, -16, 0, 30)
		actionBtn.AnchorPoint = Vector2.new(0, 1)
		actionBtn.Position = UDim2.new(0, 8, 1, -8)
		actionBtn.BorderSizePixel = 0
		actionBtn.AutoButtonColor = false
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.TextSize = 12
		actionBtn.Parent = card

		local actionCorner = Instance.new("UICorner")
		actionCorner.CornerRadius = UDim.new(0, 6)
		actionCorner.Parent = actionBtn

		if not owned then
			actionBtn.Text = "Locked"
			actionBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
			actionBtn.TextColor3 = Color3.fromRGB(140, 140, 155)
		elseif isEquipped then
			actionBtn.Text = "Unequip"
			actionBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 85)
			actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			actionBtn.MouseButton1Click:Connect(function()
				Remotes.EquipCosmetic:FireServer(tab.slot, nil)
			end)
		else
			actionBtn.Text = "Equip"
			actionBtn.BackgroundColor3 = Color3.fromRGB(110, 200, 110)
			actionBtn.TextColor3 = Color3.fromRGB(20, 30, 20)
			actionBtn.MouseButton1Click:Connect(function()
				Remotes.EquipCosmetic:FireServer(tab.slot, cosmetic.id)
			end)
		end
	end
end

cachedProfile = nil

local function selectTab(tabKey: string)
	activeTab = tabKey
	for key, btn in tabButtons do
		btn.BackgroundColor3 = (key == tabKey) and Color3.fromRGB(120, 80, 200) or Color3.fromRGB(40, 42, 55)
	end
	renderTab(tabKey)
end

for _, tab in TABS do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 100, 1, 0)
	btn.BackgroundColor3 = Color3.fromRGB(40, 42, 55)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = tab.label
	btn.Parent = tabBar

	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = btn

	btn.MouseButton1Click:Connect(function()
		selectTab(tab.key)
	end)

	tabButtons[tab.key] = btn
end

selectTab(TABS[1].key)

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	cachedProfile = data
	if overlay.Visible then
		renderTab(activeTab)
	end
end)

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	local inLobby = payload.state == "LOBBY" or payload.state == "VOTING"
	-- button hidden permanently — access via MainMenu/PauseMenu
	if not inLobby then
		overlay.Visible = false
	end
end)

ClientSignals.Get("OpenCosmetics").Event:Connect(function()
	overlay.Visible = true
	renderTab(activeTab)
end)

return CosmeticsController
