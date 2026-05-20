--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local CosmeticRegistry = require(Shared.Modules.CosmeticRegistry)
local WeaponConfig = require(Shared.Modules.WeaponConfig)
local UITheme = require(Shared.Modules.UITheme)

local KillFeedController = {}

local MAX_ENTRIES_DESKTOP = 5
local MAX_ENTRIES_MOBILE = 2 -- short-vertical viewports can't fit more
local ENTRY_LIFETIME = 4
local ENTRY_HEIGHT_DESKTOP = 36
local ENTRY_HEIGHT_MOBILE = 28 -- shrunk so the top-right cluster stays compact
local ENTRY_MAX_W_DESKTOP = 420
local ENTRY_MAX_W_MOBILE = 220 -- shrunk from 320 to stay clear of right-edge ammo/buttons
-- Entries now sit BELOW the mini scoreboard. The background is intentionally
-- more transparent (0.35 vs old 0.08) so the cluster reads as "secondary chrome"
-- next to the prominent scoreboard cards. Tier accent stripe stays full-opacity
-- so legendary/contraband kills still pop.
local ENTRY_BG_TRANSPARENCY = 0.35
-- WeaponController places the mobile FIRE button anchored bottom-right at
-- (-88, -130) with size 72x72. KillFeed entries are anchored top-right and we
-- shift them LEFT past the FIRE button + a margin so they never extend into
-- the FIRE tap target on narrow viewports.
local FIRE_BUTTON_WIDTH = 72
-- Also clear the right-edge ADS/RELOAD/SWAP column (44 wide, +12 right padding).
local RIGHT_COL_RESERVE = 56
-- Gap between the bottom of the mini scoreboard and the first KillFeed entry.
local SCOREBOARD_GAP = UITheme.Space.m -- 12

-- Fallback scoreboard heights if the ScoreboardController helper is unavailable
-- (e.g. test environments). These match ScoreboardController.luau's constants.
local FALLBACK_MINI_HEIGHT_DESKTOP = 4 * 36 + 3 * UITheme.Space.xs -- 156
local FALLBACK_MINI_HEIGHT_MOBILE = 4 * 26 + 3 * 2                  -- 110

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KillFeed"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 80
screenGui.Parent = playerGui

-- Mobile detection: use viewport WIDTH not Touch/Mouse combo. Studio's
-- Device Emulator leaves MouseEnabled=true while TouchEnabled is also true,
-- which broke the "touch + !mouse" check. Viewport-width detection is robust
-- for Studio emulator AND real mobile (which all have narrow viewports).
local function isMobileDevice(): boolean
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	return vw < 700
end

local GuiService = game:GetService("GuiService")

local container = Instance.new("Frame")
container.Size = UDim2.new(0, ENTRY_MAX_W_DESKTOP + 8, 0, 180)
container.AnchorPoint = Vector2.new(1, 0)
container.Position = UDim2.new(1, -UITheme.Space.xl, 0, UITheme.Space.x5l + UITheme.Space.x3l)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- Mini-scoreboard height. ScoreboardController is a sibling client controller
-- (not exposed via ReplicatedStorage), so we mirror its constants here and the
-- unit test `topright_cluster_test.luau` asserts they stay in lock-step.
local function getScoreboardHeight(mobileViewport: boolean): number
	return mobileViewport and FALLBACK_MINI_HEIGHT_MOBILE or FALLBACK_MINI_HEIGHT_DESKTOP
end

local function getEntryHeight(): number
	return isMobileDevice() and ENTRY_HEIGHT_MOBILE or ENTRY_HEIGHT_DESKTOP
end

-- Responsive container position + width.
-- Width: narrower on mobile to stay clear of right-edge HUD (FIRE + ADS column).
-- Y position: ALWAYS sits BELOW the mini scoreboard (topInset + scoreboardH + gap)
-- so the top-right cluster reads as a single column (scoreboard cards on top,
-- KillFeed entries underneath) instead of two floating elements that overlap.
-- X position: shift LEFT past FIRE button + right-edge column on mobile.
local function refreshContainerSize()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	local mobileViewport = vw < 700
	local w = mobileViewport and (ENTRY_MAX_W_MOBILE + 8) or (ENTRY_MAX_W_DESKTOP + 8)
	local maxEntries = mobileViewport and MAX_ENTRIES_MOBILE or MAX_ENTRIES_DESKTOP
	local entryH = mobileViewport and ENTRY_HEIGHT_MOBILE or ENTRY_HEIGHT_DESKTOP
	local h = maxEntries * entryH + (maxEntries - 1) * UITheme.Space.s
	container.Size = UDim2.new(0, w, 0, h)

	local rightOffset = UITheme.Space.xl
	if mobileViewport then
		rightOffset = FIRE_BUTTON_WIDTH + RIGHT_COL_RESERVE + UITheme.Space.s -- ≈ 136
	end

	-- Sit directly below the mini scoreboard. The scoreboard itself anchors at
	-- topInset + UITheme.Space.l, so:
	--   topOffset = (topInset + Space.l) + scoreboardHeight + gap
	local topInset = GuiService:GetGuiInset().Y
	local sbH = getScoreboardHeight(mobileViewport)
	local topOffset = topInset + UITheme.Space.l + sbH + SCOREBOARD_GAP

	container.Position = UDim2.new(1, -rightOffset, 0, topOffset)
end
refreshContainerSize()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshContainerSize)
end

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.Padding = UDim.new(0, UITheme.Space.s)
layout.Parent = container

local entries: { Frame } = {}

-- Tier color resolver — based on weapon's rarity. Defaults to text-primary if unknown.
local function tierColorFor(weaponId: string?): Color3
	if not weaponId then return UITheme.Color.textPrimary end
	local w = WeaponConfig[weaponId]
	if not w then return UITheme.Color.textPrimary end
	local map = {
		Common = UITheme.Color.tierCommon,
		Rare = UITheme.Color.tierRare,
		Epic = UITheme.Color.tierEpic,
		Legendary = UITheme.Color.tierLegendary,
		Contraband = UITheme.Color.tierContraband,
	}
	return map[w.tier] or UITheme.Color.textPrimary
end

local function buildEntry(info: any)
	local isLocalKill = info.killer == player.Name
	local tierColor = tierColorFor(info.weaponId)
	local mobile = isMobileDevice()
	local entryH = getEntryHeight()
	-- On mobile, drop one text-size step (body 15 → caption 13). Weapon "verb"
	-- in the middle drops to micro 11 so it stays subordinate.
	local nameFontSize = mobile and UITheme.FontSize.caption or UITheme.FontSize.body
	local weaponFontSize = mobile and UITheme.FontSize.micro or UITheme.FontSize.caption

	-- Outer wrapper used for slide-in animation (translate via Position)
	local entry = Instance.new("Frame")
	entry.Size = UDim2.new(0, 0, 0, entryH)
	entry.AutomaticSize = Enum.AutomaticSize.X
	entry.BackgroundColor3 = UITheme.Color.bgElevated
	entry.BackgroundTransparency = ENTRY_BG_TRANSPARENCY
	entry.BorderSizePixel = 0
	entry.LayoutOrder = -tick()
	entry.ClipsDescendants = false
	-- Start offset to the right for slide-in
	entry.Position = UDim2.new(0, 60, 0, 0)
	entry.Parent = container

	UITheme.corner(entry, "md")

	-- Tier accent strip — 4px wide on left edge of entry, color = weapon tier
	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.Position = UDim2.new(0, 0, 0, 0)
	accent.BackgroundColor3 = tierColor
	accent.BorderSizePixel = 0
	accent.Parent = entry
	UITheme.corner(accent, "sm")

	-- If local player is the killer, add a subtle accent-primary glow stroke
	if isLocalKill then
		UITheme.stroke(entry, "accentPrimary", 1.5, 0.3)
	end

	-- Inner padding (extra-left to clear the accent stripe)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, UITheme.Space.m + 4)
	pad.PaddingRight = UDim.new(0, UITheme.Space.m)
	pad.Parent = entry

	-- Horizontal flow
	local hList = Instance.new("UIListLayout")
	hList.FillDirection = Enum.FillDirection.Horizontal
	hList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	hList.VerticalAlignment = Enum.VerticalAlignment.Center
	hList.SortOrder = Enum.SortOrder.LayoutOrder
	hList.Padding = UDim.new(0, UITheme.Space.s)
	hList.Parent = entry

	-- Killer name — green if local, lighter green otherwise
	local killerLbl = Instance.new("TextLabel")
	killerLbl.Size = UDim2.new(0, 0, 1, 0)
	killerLbl.AutomaticSize = Enum.AutomaticSize.X
	killerLbl.BackgroundTransparency = 1
	killerLbl.Font = UITheme.Font.heading
	killerLbl.TextSize = nameFontSize
	killerLbl.TextColor3 = isLocalKill and UITheme.Color.accentPrimary or UITheme.Color.success
	killerLbl.Text = info.killer or "?"
	killerLbl.LayoutOrder = 1
	killerLbl.Parent = entry

	-- Weapon name — small dimmed caption between killer and victim. Acts as
	-- a visual "verb" linking the two names (e.g. "Yusuf  ▸ AK-47 ▸  Player2").
	local weaponLbl = Instance.new("TextLabel")
	weaponLbl.Size = UDim2.new(0, 0, 1, 0)
	weaponLbl.AutomaticSize = Enum.AutomaticSize.X
	weaponLbl.BackgroundTransparency = 1
	weaponLbl.Font = UITheme.Font.heading
	weaponLbl.TextSize = weaponFontSize
	weaponLbl.TextColor3 = tierColor
	weaponLbl.Text = string.format("%s %s %s", "▸", info.weapon or "Kill", "▸")
	weaponLbl.LayoutOrder = 2
	weaponLbl.Parent = entry

	-- Headshot badge — circular red pill with skull emoji. Sits BEFORE victim name.
	if info.isHeadshot then
		local hsBadge = Instance.new("Frame")
		hsBadge.Size = UDim2.new(0, 28, 0, 22)
		hsBadge.BackgroundColor3 = UITheme.Color.danger
		hsBadge.BorderSizePixel = 0
		hsBadge.LayoutOrder = 3
		hsBadge.Parent = entry
		UITheme.corner(hsBadge, "sm")

		local hsLbl = Instance.new("TextLabel")
		hsLbl.Size = UDim2.new(1, 0, 1, 0)
		hsLbl.BackgroundTransparency = 1
		hsLbl.Font = UITheme.Font.display
		hsLbl.TextSize = 13
		hsLbl.TextColor3 = UITheme.Color.textPrimary
		hsLbl.TextScaled = false
		hsLbl.Text = "HS" -- TODO: swap to skull icon image when asset uploaded
		hsLbl.Parent = hsBadge
	end

	-- Victim name — red. Bold if local player is the victim (so player notices).
	local isLocalDeath = info.victim == player.Name
	local victimLbl = Instance.new("TextLabel")
	victimLbl.Size = UDim2.new(0, 0, 1, 0)
	victimLbl.AutomaticSize = Enum.AutomaticSize.X
	victimLbl.BackgroundTransparency = 1
	victimLbl.Font = UITheme.Font.heading
	victimLbl.TextSize = nameFontSize
	victimLbl.TextColor3 = isLocalDeath and UITheme.Color.accentSecondary or UITheme.Color.danger
	victimLbl.Text = info.victim or "?"
	victimLbl.LayoutOrder = 4
	victimLbl.Parent = entry

	-- Slide-in animation: position from offset(60, 0) → offset(0, 0) over base duration
	TweenService:Create(entry, UITheme.Easing.emphasized, {
		Position = UDim2.new(0, 0, 0, 0),
	}):Play()

	-- Local kill = subtle pop scale-up via UIScale (extra celebration for "your" kill)
	if isLocalKill then
		local pop = Instance.new("UIScale")
		pop.Scale = 0.85
		pop.Parent = entry
		TweenService:Create(pop, UITheme.Easing.celebrate, { Scale = 1.0 }):Play()
	end

	table.insert(entries, 1, entry)

	local maxEntries = isMobileDevice() and MAX_ENTRIES_MOBILE or MAX_ENTRIES_DESKTOP
	while #entries > maxEntries do
		local old = table.remove(entries)
		if old then
			old:Destroy()
		end
	end

	-- Expiry: fade-out + slight rightward translate (mirrors slide-in but exit)
	task.delay(ENTRY_LIFETIME, function()
		local idx = table.find(entries, entry)
		if idx then
			table.remove(entries, idx)
		end
		if entry.Parent then
			local fadeOut = TweenService:Create(entry, UITheme.Easing.exit, {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 40, 0, 0),
			}):Play()
			-- Also fade child text labels
			for _, child in entry:GetDescendants() do
				if child:IsA("TextLabel") then
					TweenService:Create(child, UITheme.Easing.exit, { TextTransparency = 1 }):Play()
				elseif child:IsA("Frame") and child ~= entry then
					TweenService:Create(child, UITheme.Easing.exit, { BackgroundTransparency = 1 }):Play()
				end
			end
			task.delay(UITheme.Duration.base + 0.05, function()
				if entry.Parent then entry:Destroy() end
			end)
		end
	end)
end

-- World-space kill effect (particle + flash at victim location) — unchanged
local function spawnKillEffect(position: Vector3, primaryColor: Color3, accentColor: Color3?)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = position + Vector3.new(0, 2, 0)
	part.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Lifetime = NumberRange.new(0.6, 1.0)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -25, 0)
	emitter.Color = ColorSequence.new(primaryColor, accentColor or primaryColor)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0.7
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Parent = part

	emitter:Emit(48)

	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = primaryColor
	flash.Transparency = 0.2
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.Position = position + Vector3.new(0, 2, 0)
	flash.Parent = Workspace

	local expand = TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(5, 5, 5),
		Transparency = 1,
	})
	expand:Play()

	Debris:AddItem(part, 1.5)
	Debris:AddItem(flash, 0.5)
end

Remotes.KillFeedEntry.OnClientEvent:Connect(function(info: any)
	buildEntry(info)
	if info.killEffectId and info.victimPosition then
		local cosmetic = CosmeticRegistry.ById[info.killEffectId]
		if cosmetic then
			spawnKillEffect(info.victimPosition, cosmetic.color, cosmetic.accentColor)
		end
	end
end)

return KillFeedController
