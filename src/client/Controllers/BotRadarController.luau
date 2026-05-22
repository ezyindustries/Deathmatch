--!strict
-- BotRadarController — small persistent indicator showing how many bots are
-- alive + a minimap-style dot view of their positions relative to the player.
--
-- WHY: user reported "bot tidak muncul" on real device. We can't tell from
-- the player's POV alone whether bots are missing from the server, missing
-- from client replication, or simply out of sight. This radar:
--   • Reads bot Models server-side (any descendant of Workspace with
--     attribute IsBot=true) — so even if the rig fails to render, the
--     scoreboard-style count still updates.
--   • Renders an N×N minimap with one dot per bot relative to the player.
--   • Counts "alive vs total" so the player can see deaths happening.
--
-- DESIGN: top-right corner just below the scoreboard, very compact on
-- mobile (vw < 900). Always shows the COUNT; the minimap dots only
-- render when 1+ bots are alive (no need to draw an empty circle).
--
-- DEBUG MODE: if no bots are detected for 3+ seconds during MATCH state,
-- the text turns red and shows "NO BOTS — server side?" so the player
-- knows the spawn failed (vs the more common case where bots exist but
-- haven't streamed yet).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.Modules.UITheme)

local BotRadarController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------
local MAP_RANGE_STUDS = 80   -- world distance covered by the radar radius
local UPDATE_HZ = 5          -- 5 ticks/sec — cheap, smooth enough
local NO_BOT_GRACE = 3       -- seconds without any bot before flagging error

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BotRadarHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 45
-- HIDDEN per user request: radar was a diagnostic for the "bots not
-- spawning" investigation. Bots render correctly now, so the radar adds
-- clutter without value. Keep the controller code intact in case we need
-- the debug tool back later — just disable the ScreenGui.
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Container: top-right column, BELOW the scoreboard cluster. Scoreboard mini
-- card stack height is ~94 mobile / ~129 desktop (see ScoreboardController).
-- We anchor at (1, 0) and offset down by topInset + scoreboard reservation.
local container = Instance.new("Frame")
container.AnchorPoint = Vector2.new(1, 0)
container.BackgroundColor3 = UITheme.Color.bgBase
container.BackgroundTransparency = 0.2
container.BorderSizePixel = 0
container.Parent = screenGui

UITheme.corner(container, "md")
UITheme.stroke(container, "borderSubtle", 1, 0.5)

-- Responsive size + position. Mobile: small minimap 70x70 + 24px text row.
-- Desktop: 100x100 + 28px text row. Always sits below scoreboard cluster.
local SIZE_MOBILE = 70
local SIZE_DESKTOP = 100
local TEXT_H_MOBILE = 22
local TEXT_H_DESKTOP = 26

local mapFrame = Instance.new("Frame")
mapFrame.BackgroundColor3 = UITheme.Color.bgPressed
mapFrame.BackgroundTransparency = 0.3
mapFrame.BorderSizePixel = 0
mapFrame.Parent = container
UITheme.corner(mapFrame, "full") -- circular radar

-- Concentric ring for visual reference
local ring = Instance.new("Frame")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.new(0.5, 0, 0.5, 0)
ring.BackgroundTransparency = 1
ring.BorderSizePixel = 0
ring.Parent = mapFrame
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = UITheme.Color.borderSubtle
ringStroke.Thickness = 1
ringStroke.Transparency = 0.5
ringStroke.Parent = ring
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(1, 0)
ringCorner.Parent = ring

-- Player dot (center) — always visible
local playerDot = Instance.new("Frame")
playerDot.Size = UDim2.fromOffset(6, 6)
playerDot.AnchorPoint = Vector2.new(0.5, 0.5)
playerDot.Position = UDim2.new(0.5, 0, 0.5, 0)
playerDot.BackgroundColor3 = UITheme.Color.accentPrimary
playerDot.BorderSizePixel = 0
playerDot.Parent = mapFrame
UITheme.corner(playerDot, "full")

-- Text label (count)
local countLabel = Instance.new("TextLabel")
countLabel.BackgroundTransparency = 1
countLabel.Font = UITheme.Font.mono
countLabel.TextColor3 = UITheme.Color.textPrimary
countLabel.TextXAlignment = Enum.TextXAlignment.Center
countLabel.TextYAlignment = Enum.TextYAlignment.Center
countLabel.Text = "BOTS: 0"
countLabel.Parent = container

-- Pool of bot dots — created lazily as bots appear
local dotPool: { Frame } = {}
local function getDot(i: number): Frame
	local d = dotPool[i]
	if d then return d end
	d = Instance.new("Frame")
	d.Size = UDim2.fromOffset(5, 5)
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.BackgroundColor3 = UITheme.Color.danger
	d.BorderSizePixel = 0
	d.Parent = mapFrame
	UITheme.corner(d, "full")
	dotPool[i] = d
	return d
end

-- ---------------------------------------------------------------------------
-- Responsive layout
-- ---------------------------------------------------------------------------
local function refreshLayout()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1920
	local mobile = vw < 900
	local mapSize = mobile and SIZE_MOBILE or SIZE_DESKTOP
	local textH = mobile and TEXT_H_MOBILE or TEXT_H_DESKTOP
	local fontSize = mobile and UITheme.FontSize.micro or UITheme.FontSize.caption

	container.Size = UDim2.fromOffset(mapSize, mapSize + textH)
	mapFrame.Size = UDim2.fromOffset(mapSize, mapSize)
	mapFrame.Position = UDim2.new(0, 0, 0, 0)
	ring.Size = UDim2.fromOffset(mapSize - 8, mapSize - 8)
	countLabel.Size = UDim2.new(1, 0, 0, textH)
	countLabel.Position = UDim2.new(0, 0, 0, mapSize)
	countLabel.TextSize = fontSize

	-- Position: top-right, below scoreboard.
	-- Scoreboard top edge = topInset + Space.l, height ~94 mobile / ~129 desktop.
	local topInset = GuiService:GetGuiInset().Y
	local scoreboardH = mobile and (4 * 22 + 3 * 2) or (4 * 30 + 3 * 3)
	local gap = UITheme.Space.s
	local rightInset = mobile and UITheme.Space.m or UITheme.Space.l
	container.Position = UDim2.new(1, -rightInset, 0, topInset + UITheme.Space.l + scoreboardH + gap)
end
refreshLayout()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshLayout)
end
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refreshLayout)

-- ---------------------------------------------------------------------------
-- Tick: scan workspace for bot models, update dots + count.
-- ---------------------------------------------------------------------------
local lastSeenBotAt = os.clock()

local function tick()
	-- Find player HRP (radar center)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		-- No player char (lobby / death) → still show count, hide dots
		countLabel.Text = "BOTS: ?"
		for _, d in dotPool do d.Visible = false end
		return
	end

	-- Collect bot rigs (cheap: top-level Workspace children only)
	local alive = 0
	local total = 0
	local positions: { Vector3 } = {}
	for _, inst in Workspace:GetChildren() do
		if inst:IsA("Model") and inst:GetAttribute("IsBot") then
			total += 1
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local bhrp = inst:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and bhrp and hum.Health > 0 then
				alive += 1
				table.insert(positions, bhrp.Position)
			end
		end
	end

	if alive > 0 then lastSeenBotAt = os.clock() end

	-- Update text + color
	local secsSinceBot = os.clock() - lastSeenBotAt
	if total == 0 and secsSinceBot > NO_BOT_GRACE then
		countLabel.Text = "NO BOTS"
		countLabel.TextColor3 = UITheme.Color.danger
	elseif alive == 0 and total > 0 then
		countLabel.Text = string.format("BOTS: 0/%d", total)
		countLabel.TextColor3 = UITheme.Color.warning
	else
		countLabel.Text = string.format("BOTS: %d", alive)
		countLabel.TextColor3 = UITheme.Color.textPrimary
	end

	-- Update dots: project each bot's XZ delta onto the radar
	local mapHalf = mapFrame.AbsoluteSize.X * 0.5
	if mapHalf < 1 then mapHalf = SIZE_MOBILE * 0.5 end
	local origin = hrp.Position
	local cam = Workspace.CurrentCamera
	-- Use camera look direction to ROTATE the radar so "up" = where player faces
	local lookFlat = Vector3.new(0, 0, 0)
	if cam then
		local lv = cam.CFrame.LookVector
		lookFlat = Vector3.new(lv.X, 0, lv.Z)
		if lookFlat.Magnitude > 0.01 then lookFlat = lookFlat.Unit end
	end
	local lookAngle = if lookFlat.Magnitude > 0.01 then math.atan2(lookFlat.X, lookFlat.Z) else 0

	for i, pos in positions do
		local dot = getDot(i)
		local dx = pos.X - origin.X
		local dz = pos.Z - origin.Z
		-- Rotate by -lookAngle so player's facing is "up"
		local cosA = math.cos(-lookAngle)
		local sinA = math.sin(-lookAngle)
		local rx = dx * cosA - dz * sinA
		local rz = dx * sinA + dz * cosA
		-- Scale to radar
		local rangeFrac = math.min(1, math.max(math.abs(rx), math.abs(rz)) / MAP_RANGE_STUDS)
		local scale = mapHalf / MAP_RANGE_STUDS
		-- Clamp to ring (just outside center means far; at ring means MAP_RANGE_STUDS)
		local px = rx * scale
		local py = -rz * scale -- negate Z so "forward in world" = "up on radar"
		-- Clamp to ring radius
		local mag = math.sqrt(px*px + py*py)
		local maxR = mapHalf - 4
		if mag > maxR then
			px = px / mag * maxR
			py = py / mag * maxR
		end
		dot.Position = UDim2.new(0.5, math.floor(px), 0.5, math.floor(py))
		-- Color by distance (red close, yellow medium, white far)
		if rangeFrac < 0.3 then
			dot.BackgroundColor3 = UITheme.Color.danger
		elseif rangeFrac < 0.7 then
			dot.BackgroundColor3 = UITheme.Color.warning
		else
			dot.BackgroundColor3 = UITheme.Color.textSecondary
		end
		dot.Visible = true
	end
	-- Hide unused pool slots
	for i = #positions + 1, #dotPool do
		dotPool[i].Visible = false
	end
end

local tickInterval = 1 / UPDATE_HZ
local accum = 0
RunService.RenderStepped:Connect(function(dt)
	accum += dt
	if accum >= tickInterval then
		accum = 0
		tick()
	end
end)

return BotRadarController
