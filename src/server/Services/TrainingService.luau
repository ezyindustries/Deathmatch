--!strict
-- Training Practice mode: solo room with target dummies, free loadout switching,
-- bypasses voting/match cycle entirely.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)

local TrainingService = {}

local TRAINING_ORIGIN = Vector3.new(-2000, 100, 0)
local SPAWN_POS = TRAINING_ORIGIN + Vector3.new(0, 4, 30)
local DUMMY_LINE_Z = TRAINING_ORIGIN.Z - 30 -- dummies 60 units in front of spawn
local DUMMY_RESPAWN_TIME = 3

local trainingPlayers: { [number]: boolean } = {}
local dummies: { Model } = {}
local roomBuilt = false

-- ============================================================
-- ROOM BUILDER
-- ============================================================
local function makePart(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function buildRoom()
	if roomBuilt then return end
	roomBuilt = true

	local folder = Instance.new("Folder")
	folder.Name = "TrainingRoom"
	folder.Parent = Workspace

	local floorColor = Color3.fromRGB(60, 65, 80)
	local wallColor = Color3.fromRGB(200, 180, 150) -- warm beige
	local accentColor = Color3.fromRGB(80, 200, 110) -- green accent

	-- Floor (80x100)
	makePart(folder, {
		Name = "Floor",
		Size = Vector3.new(80, 2, 100),
		Position = TRAINING_ORIGIN + Vector3.new(0, -1, 0),
		Color = floorColor,
		Material = Enum.Material.Concrete,
	})

	-- Walls (4 sides, height 24)
	makePart(folder, { Name = "WallN", Size = Vector3.new(80, 24, 2), Position = TRAINING_ORIGIN + Vector3.new(0, 12, -50), Color = wallColor, Material = Enum.Material.Brick })
	makePart(folder, { Name = "WallS", Size = Vector3.new(80, 24, 2), Position = TRAINING_ORIGIN + Vector3.new(0, 12, 50),  Color = wallColor, Material = Enum.Material.Brick })
	makePart(folder, { Name = "WallW", Size = Vector3.new(2, 24, 100), Position = TRAINING_ORIGIN + Vector3.new(-40, 12, 0), Color = wallColor, Material = Enum.Material.Brick })
	makePart(folder, { Name = "WallE", Size = Vector3.new(2, 24, 100), Position = TRAINING_ORIGIN + Vector3.new(40, 12, 0),  Color = wallColor, Material = Enum.Material.Brick })

	-- Ceiling
	makePart(folder, {
		Name = "Ceiling",
		Size = Vector3.new(80, 1, 100),
		Position = TRAINING_ORIGIN + Vector3.new(0, 24, 0),
		Color = Color3.fromRGB(40, 45, 60),
		Material = Enum.Material.Slate,
	})

	-- Ceiling light panels (4 spots, moderate brightness)
	for x = -25, 25, 25 do
		for z = -35, 35, 35 do
			local lightPart = makePart(folder, {
				Name = "LightPanel",
				Size = Vector3.new(8, 0.4, 8),
				Position = TRAINING_ORIGIN + Vector3.new(x, 23.5, z),
				Color = Color3.fromRGB(220, 220, 230),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
			})
			local pointLight = Instance.new("PointLight")
			pointLight.Color = Color3.fromRGB(255, 245, 220)
			pointLight.Brightness = 1.2 -- was 3 (too bright)
			pointLight.Range = 25
			pointLight.Shadows = false
			pointLight.Parent = lightPart
		end
	end

	-- Spawn pad (green glow at player spawn)
	makePart(folder, {
		Name = "SpawnPad",
		Size = Vector3.new(6, 0.2, 6),
		Position = TRAINING_ORIGIN + Vector3.new(0, 0.1, 30),
		Color = accentColor,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	-- Distance markers on floor (white stripes every 10 units)
	for d = 10, 50, 10 do
		makePart(folder, {
			Name = "DistMark_" .. d,
			Size = Vector3.new(8, 0.15, 0.4),
			Position = TRAINING_ORIGIN + Vector3.new(-25, 0.08, 30 - d),
			Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		-- Distance label sign
		local sign = makePart(folder, {
			Name = "DistSign_" .. d,
			Size = Vector3.new(0.4, 1.5, 1.5),
			Position = TRAINING_ORIGIN + Vector3.new(-37, 1, 30 - d),
			Color = Color3.fromRGB(30, 30, 40),
			Material = Enum.Material.Metal,
		})
		local sgui = Instance.new("SurfaceGui")
		sgui.Face = Enum.NormalId.Right
		sgui.Parent = sign
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = accentColor
		label.Text = tostring(d) .. "m"
		label.Parent = sgui
	end

	-- Wall info sign
	local infoSign = makePart(folder, {
		Name = "InfoSign",
		Size = Vector3.new(20, 8, 0.4),
		Position = TRAINING_ORIGIN + Vector3.new(0, 14, 49),
		Color = Color3.fromRGB(30, 30, 40),
		Material = Enum.Material.Metal,
	})
	local sgui = Instance.new("SurfaceGui")
	sgui.Face = Enum.NormalId.Front
	sgui.Parent = infoSign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = accentColor
	label.Text = "🎯 TRAINING ROOM\nFire on dummies — they respawn"
	label.Parent = sgui

	print("[Training] Room built at " .. tostring(TRAINING_ORIGIN))
end

-- ============================================================
-- DUMMY MODELS (target NPCs with Humanoid)
-- ============================================================
local function makeDummy(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"
	model.Parent = Workspace:FindFirstChild("TrainingRoom") or Workspace

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Position = position
	hrp.Anchored = true
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.TopSurface = Enum.SurfaceType.Smooth
	hrp.BottomSurface = Enum.SurfaceType.Smooth
	hrp.Parent = model
	model.PrimaryPart = hrp

	-- Torso
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Position = position
	torso.Anchored = true
	torso.CanCollide = false
	torso.Color = Color3.fromRGB(180, 60, 60)
	torso.Material = Enum.Material.SmoothPlastic
	torso.TopSurface = Enum.SurfaceType.Smooth
	torso.BottomSurface = Enum.SurfaceType.Smooth
	torso.Parent = model

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Position = position + Vector3.new(0, 1.6, 0)
	head.Anchored = true
	head.CanCollide = false
	head.Color = Color3.fromRGB(220, 80, 80)
	head.Material = Enum.Material.SmoothPlastic
	head.Shape = Enum.PartType.Ball
	head.Parent = model

	-- Left arm
	local lArm = Instance.new("Part")
	lArm.Name = "LeftArm"
	lArm.Size = Vector3.new(0.6, 2, 1)
	lArm.Position = position + Vector3.new(-1.3, 0, 0)
	lArm.Anchored = true
	lArm.CanCollide = false
	lArm.Color = Color3.fromRGB(160, 50, 50)
	lArm.Material = Enum.Material.SmoothPlastic
	lArm.Parent = model

	-- Right arm
	local rArm = lArm:Clone()
	rArm.Name = "RightArm"
	rArm.Position = position + Vector3.new(1.3, 0, 0)
	rArm.Parent = model

	-- Left leg
	local lLeg = Instance.new("Part")
	lLeg.Name = "LeftLeg"
	lLeg.Size = Vector3.new(0.8, 2, 1)
	lLeg.Position = position + Vector3.new(-0.4, -2, 0)
	lLeg.Anchored = true
	lLeg.CanCollide = false
	lLeg.Color = Color3.fromRGB(60, 60, 70)
	lLeg.Material = Enum.Material.SmoothPlastic
	lLeg.Parent = model

	-- Right leg
	local rLeg = lLeg:Clone()
	rLeg.Name = "RightLeg"
	rLeg.Position = position + Vector3.new(0.4, -2, 0)
	rLeg.Parent = model

	-- Humanoid (anchored characters don't fire Died normally, so we poll HealthChanged)
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.Parent = model

	-- Healthbar billboard
	local bgui = Instance.new("BillboardGui")
	bgui.Size = UDim2.new(0, 80, 0, 12)
	bgui.StudsOffset = Vector3.new(0, 2.5, 0)
	bgui.AlwaysOnTop = true
	bgui.Parent = head

	local hpBg = Instance.new("Frame")
	hpBg.Size = UDim2.new(1, 0, 1, 0)
	hpBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	hpBg.BorderSizePixel = 0
	hpBg.Parent = bgui

	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPFill"
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBg

	local originalPosition = position
	-- Respawn: check HealthChanged (Died event unreliable for anchored humanoids).
	local isDead = false
	hum.HealthChanged:Connect(function(newHealth)
		local ratio = newHealth / hum.MaxHealth
		hpFill.Size = UDim2.new(math.max(0, ratio), 0, 1, 0)
		if ratio > 0.6 then
			hpFill.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
		elseif ratio > 0.3 then
			hpFill.BackgroundColor3 = Color3.fromRGB(240, 200, 80)
		else
			hpFill.BackgroundColor3 = Color3.fromRGB(230, 80, 80)
		end

		if newHealth <= 0 and not isDead then
			isDead = true
			-- Ghost effect
			for _, p in model:GetChildren() do
				if p:IsA("BasePart") then
					p.Transparency = (p.Name == "HumanoidRootPart") and 1 or 0.7
				end
			end
			if bgui then bgui.Enabled = false end
			task.delay(DUMMY_RESPAWN_TIME, function()
				if not model.Parent then return end
				for i, d in dummies do
					if d == model then
						table.remove(dummies, i)
						break
					end
				end
				model:Destroy()
				local fresh = makeDummy(originalPosition)
				table.insert(dummies, fresh)
			end)
		end
	end)

	return model
end

local function spawnAllDummies()
	-- Clear existing
	for _, d in dummies do
		if d.Parent then d:Destroy() end
	end
	table.clear(dummies)

	-- Spawn 5 dummies in a horizontal line at various distances
	local layouts = {
		{ x = -20, distance = 15 },
		{ x = -10, distance = 25 },
		{ x = 0,   distance = 35 },
		{ x = 10,  distance = 25 },
		{ x = 20,  distance = 15 },
	}
	for _, l in layouts do
		local pos = TRAINING_ORIGIN + Vector3.new(l.x, 3, 30 - l.distance)
		local dummy = makeDummy(pos)
		table.insert(dummies, dummy)
	end
	print(string.format("[Training] Spawned %d dummies", #dummies))
end

-- ============================================================
-- PUBLIC API
-- ============================================================
function TrainingService.IsTraining(userId: number): boolean
	return trainingPlayers[userId] == true
end

function TrainingService.StartTraining(player: Player)
	buildRoom()
	if #dummies == 0 then
		spawnAllDummies()
	end

	trainingPlayers[player.UserId] = true
	player:LoadCharacter()

	-- Teleport on character load
	task.wait(0.3)
	local char = player.Character
	if char and char.PrimaryPart then
		char:PivotTo(CFrame.new(SPAWN_POS))
	elseif char then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.CFrame = CFrame.new(SPAWN_POS)
		end
	end

	-- Tell client they're in training mode (so VotingController skips overlay)
	Remotes.EnterTrainingMode:FireClient(player, true)

	print(string.format("[Training] %s entered training", player.Name))
end

function TrainingService.ExitTraining(player: Player)
	if not trainingPlayers[player.UserId] then return end
	trainingPlayers[player.UserId] = nil
	Remotes.EnterTrainingMode:FireClient(player, false)
end

Players.PlayerRemoving:Connect(function(player: Player)
	trainingPlayers[player.UserId] = nil
end)

return TrainingService
