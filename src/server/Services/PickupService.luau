--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Modules.MatchState)

local MatchStateService = require(script.Parent.MatchStateService)

local PickupService = {}

local PICKUP_COUNT = 6
local RESPAWN_SECONDS = 25
local HEAL_AMOUNT = 30

type PickupKind = "health" | "ammo"

type Pickup = {
	kind: PickupKind,
	model: Model,
	hitbox: BasePart,
	visual: BasePart,
	position: Vector3,
	available: boolean,
	respawnAt: number,
}

local activePickups: { Pickup } = {}
local pickupsFolder: Folder? = nil

local function makePickup(kind: PickupKind, position: Vector3): Pickup
	local color: Color3
	local labelText: string
	if kind == "health" then
		color = Color3.fromRGB(80, 220, 100)
		labelText = "+"
	else
		color = Color3.fromRGB(255, 200, 60)
		labelText = "A"
	end

	local model = Instance.new("Model")
	model.Name = string.format("Pickup_%s", kind)
	model.Parent = pickupsFolder

	local visual = Instance.new("Part")
	visual.Name = "Visual"
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanQuery = false
	visual.CastShadow = false
	visual.Size = Vector3.new(2, 2, 2)
	visual.Shape = Enum.PartType.Block
	visual.Material = Enum.Material.Neon
	visual.Color = color
	visual.Transparency = 0.15
	visual.Position = position
	visual.Parent = model

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 1.6
	light.Parent = visual

	local sgui = Instance.new("BillboardGui")
	sgui.Size = UDim2.new(0, 60, 0, 60)
	sgui.AlwaysOnTop = false
	sgui.LightInfluence = 0
	sgui.Parent = visual

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 40
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = labelText
	label.Parent = sgui

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.Transparency = 1
	hitbox.Size = Vector3.new(5, 5, 5)
	hitbox.Position = position
	hitbox.Parent = model

	return {
		kind = kind,
		model = model,
		hitbox = hitbox,
		visual = visual,
		position = position,
		available = true,
		respawnAt = 0,
	}
end

local function applyPickup(pickup: Pickup, player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if pickup.kind == "health" then
		if humanoid.Health >= humanoid.MaxHealth then
			return
		end
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + HEAL_AMOUNT)
	end
	-- ammo refill could fire a remote to WeaponService — placeholder for now

	pickup.available = false
	pickup.respawnAt = os.clock() + RESPAWN_SECONDS
	pickup.visual.Transparency = 1
	pickup.visual:FindFirstChildOfClass("PointLight").Enabled = false
	local sgui = pickup.visual:FindFirstChildOfClass("BillboardGui")
	if sgui then
		sgui.Enabled = false
	end
end

local function checkTouches()
	for _, pickup in activePickups do
		if not pickup.available then
			if os.clock() >= pickup.respawnAt then
				pickup.available = true
				pickup.visual.Transparency = 0.15
				pickup.visual:FindFirstChildOfClass("PointLight").Enabled = true
				local sgui = pickup.visual:FindFirstChildOfClass("BillboardGui")
				if sgui then
					sgui.Enabled = true
				end
			end
			continue
		end
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character then
				continue
			end
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				continue
			end
			if (root.Position - pickup.position).Magnitude < 4 then
				applyPickup(pickup, player)
				break
			end
		end
	end
end

local function spawnPickupsForArena()
	local activeArena = Workspace:FindFirstChild("ActiveArena") :: Folder?
	if not activeArena then
		return
	end
	local spawns = activeArena:FindFirstChild("Spawns")
	if not spawns then
		return
	end

	pickupsFolder = Instance.new("Folder")
	pickupsFolder.Name = "Pickups"
	pickupsFolder.Parent = Workspace

	-- Sample positions: midpoint between random pairs of arena spawns
	local spawnList: { SpawnLocation } = {}
	for _, c in spawns:GetChildren() do
		if c:IsA("SpawnLocation") then
			table.insert(spawnList, c)
		end
	end
	if #spawnList < 2 then
		return
	end

	for i = 1, PICKUP_COUNT do
		local a = spawnList[math.random(#spawnList)]
		local b = spawnList[math.random(#spawnList)]
		local mid = (a.Position + b.Position) / 2
		-- Random nudge so pickups aren't all on same spot
		mid += Vector3.new((math.random() - 0.5) * 18, 2, (math.random() - 0.5) * 18)
		local kind: PickupKind = (i % 2 == 0) and "health" or "health"
		local pickup = makePickup(kind, mid)
		table.insert(activePickups, pickup)
	end
end

local function clearPickups()
	if pickupsFolder then
		pickupsFolder:Destroy()
		pickupsFolder = nil
	end
	activePickups = {}
end

-- Rotation tween + bobbing
local startTime = os.clock()
RunService.Heartbeat:Connect(function()
	checkTouches()
	local t = os.clock() - startTime
	for _, pickup in activePickups do
		if pickup.available then
			local bob = math.sin(t * 2) * 0.5
			pickup.visual.CFrame = CFrame.new(pickup.position.X, pickup.position.Y + bob, pickup.position.Z)
				* CFrame.Angles(0, t * 2, 0)
		end
	end
end)

-- Health pickups disabled per user request. spawnPickupsForArena left in place
-- in case they're re-enabled later (and so clearPickups still has a no-op cleanup
-- path). Just don't wire the spawn-on-STARTING listener anymore.
MatchStateService.StateChanged:Connect(function(newState: MatchState.State)
	if newState == MatchState.States.ENDING or newState == MatchState.States.LOBBY then
		clearPickups()
	end
end)

return PickupService
