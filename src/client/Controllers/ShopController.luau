--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local ProductsConfig = require(Shared.Modules.ProductsConfig)
local ClientSignals = require(Shared.Modules.ClientSignals)

local ShopController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 150
screenGui.Parent = playerGui

-- Shop button (bottom area, left of crate)
local shopButton = Instance.new("TextButton")
shopButton.Size = UDim2.new(0, 100, 0, 44)
shopButton.AnchorPoint = Vector2.new(1, 1)
shopButton.Position = UDim2.new(0.5, -150, 1, -20)
shopButton.BackgroundColor3 = Color3.fromRGB(120, 80, 200)
shopButton.BorderSizePixel = 0
shopButton.AutoButtonColor = false
shopButton.Font = Enum.Font.GothamBold
shopButton.TextSize = 14
shopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
shopButton.Text = "SHOP"
shopButton.Visible = false -- access via MainMenu/PauseMenu
shopButton.Parent = screenGui

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 10)
shopCorner.Parent = shopButton

-- Shop overlay
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.Visible = false
overlay.BorderSizePixel = 0
overlay.Parent = screenGui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 720, 0, 520)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
panel.BorderSizePixel = 0
panel.Parent = overlay

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 36)
title.Position = UDim2.new(0, 20, 0, 16)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(200, 130, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Shop"
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -40, 0, 18)
subtitle.Position = UDim2.new(0, 20, 0, 48)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 12
subtitle.TextColor3 = Color3.fromRGB(170, 175, 195)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = "Gamepasses (permanent) and Coin/Gem packs"
subtitle.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 80, 0, 30)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -20, 0, 20)
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

shopButton.MouseButton1Click:Connect(function()
	overlay.Visible = true
end)
closeBtn.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)

-- Scroll container
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -40, 1, -100)
scroll.Position = UDim2.new(0, 20, 0, 80)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 105, 130)
scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.Parent = scroll

type RowRefs = { frame: Frame, buyButton: TextButton, kind: string, key: string }
local rows: { RowRefs } = {}

local function sectionLabel(text: string)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 24)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 14
	lbl.TextColor3 = Color3.fromRGB(170, 130, 255)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text
	lbl.LayoutOrder = #rows
	lbl.Parent = scroll
end

local function makeRow(kind: string, key: string, name: string, desc: string, price: number, accent: Color3): RowRefs
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 76)
	row.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
	row.BorderSizePixel = 0
	row.LayoutOrder = #rows + 1
	row.Parent = scroll

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(0, 4, 1, -16)
	accentBar.Position = UDim2.new(0, 6, 0, 8)
	accentBar.BackgroundColor3 = accent
	accentBar.BorderSizePixel = 0
	accentBar.Parent = row
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = accentBar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -190, 0, 22)
	nameLabel.Position = UDim2.new(0, 20, 0, 12)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = name
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -190, 0, 36)
	descLabel.Position = UDim2.new(0, 20, 0, 36)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextColor3 = Color3.fromRGB(170, 175, 195)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true
	descLabel.Text = desc
	descLabel.Parent = row

	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(0, 130, 0, 40)
	buyBtn.AnchorPoint = Vector2.new(1, 0.5)
	buyBtn.Position = UDim2.new(1, -16, 0.5, 0)
	buyBtn.BackgroundColor3 = accent
	buyBtn.BorderSizePixel = 0
	buyBtn.AutoButtonColor = false
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.TextSize = 14
	buyBtn.TextColor3 = Color3.fromRGB(20, 20, 30)
	buyBtn.Text = string.format("R$ %d", price)
	buyBtn.Parent = row

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 8)
	buyCorner.Parent = buyBtn

	buyBtn.MouseButton1Click:Connect(function()
		Remotes.PromptPurchase:FireServer(kind, key)
	end)

	return { frame = row, buyButton = buyBtn, kind = kind, key = key }
end

local function countDict(t: { [string]: any }): number
	local n = 0
	for _ in t do n += 1 end
	return n
end

local hasGamepasses = countDict(ProductsConfig.Gamepasses) > 0
local hasProducts = countDict(ProductsConfig.Products) > 0

if hasGamepasses then
	sectionLabel("Gamepasses")
	for key, info in ProductsConfig.Gamepasses do
		table.insert(rows, makeRow("gamepass", key, info.displayName, info.description, info.priceRobux, Color3.fromRGB(180, 130, 255)))
	end
end

if hasProducts then
	sectionLabel("Coin & Gem Packs")
	for key, info in ProductsConfig.Products do
		local accent = if info.reward.kind == "gems"
			then Color3.fromRGB(120, 200, 255)
			else Color3.fromRGB(255, 200, 80)
		table.insert(rows, makeRow("product", key, info.displayName, info.description, info.priceRobux, accent))
	end
end

-- Coming-soon placeholder when nothing is configured yet (so the panel doesn't
-- look broken / empty). Hidden the moment a gamepass or product is registered.
if not hasGamepasses and not hasProducts then
	subtitle.Text = "New items coming soon"
	local placeholder = Instance.new("Frame")
	placeholder.Size = UDim2.new(1, 0, 0, 180)
	placeholder.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
	placeholder.BorderSizePixel = 0
	placeholder.LayoutOrder = 1
	placeholder.Parent = scroll
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 10)
	pc.Parent = placeholder

	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.new(1, 0, 0, 56)
	emoji.Position = UDim2.new(0, 0, 0, 30)
	emoji.BackgroundTransparency = 1
	emoji.Font = Enum.Font.GothamBold
	emoji.TextSize = 42
	emoji.TextColor3 = Color3.fromRGB(170, 130, 255)
	emoji.Text = "🛒"
	emoji.Parent = placeholder

	local msg = Instance.new("TextLabel")
	msg.Size = UDim2.new(1, -40, 0, 28)
	msg.Position = UDim2.new(0, 20, 0, 92)
	msg.BackgroundTransparency = 1
	msg.Font = Enum.Font.GothamBold
	msg.TextSize = 16
	msg.TextColor3 = Color3.fromRGB(230, 230, 245)
	msg.Text = "Shop is empty"
	msg.Parent = placeholder

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -40, 0, 20)
	sub.Position = UDim2.new(0, 20, 0, 122)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 12
	sub.TextColor3 = Color3.fromRGB(160, 165, 185)
	sub.TextWrapped = true
	sub.Text = "Gamepasses and coin packs will appear here once available."
	sub.Parent = placeholder
end

Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data: any)
	local owned = data.ownedGamepasses or {}
	for _, row in rows do
		if row.kind == "gamepass" and owned[row.key] then
			row.buyButton.Text = "Owned"
			row.buyButton.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
			row.buyButton.TextColor3 = Color3.fromRGB(170, 175, 195)
		end
	end
end)

Remotes.MatchStateChanged.OnClientEvent:Connect(function(payload: any)
	local inLobby = payload.state == "LOBBY" or payload.state == "VOTING"
	-- Shop HUD button hidden permanently — access via MainMenu/PauseMenu
	if not inLobby then
		overlay.Visible = false
	end
end)

ClientSignals.Get("OpenShop").Event:Connect(function()
	overlay.Visible = true
end)

return ShopController
