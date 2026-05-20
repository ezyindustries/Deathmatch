--!strict
-- Shared R6 bot rig builder. Used by DeathmatchBotService (per-faction colors
-- override defaults via post-build paint) and CasualBotService (team-colored
-- torso/legs). Keeping rig assembly in one place stops the two services from
-- drifting on joint setup or nameplate layout.

local BotModel = {}

export type BotColors = {
	torso: Color3,
	head: Color3,
	leftArm: Color3,
	rightArm: Color3,
	leftLeg: Color3,
	rightLeg: Color3,
}

local DEFAULT_COLORS: BotColors = {
	torso    = Color3.fromRGB(150, 50, 50),
	head     = Color3.fromRGB(200, 170, 140),
	leftArm  = Color3.fromRGB(150, 50, 50),
	rightArm = Color3.fromRGB(150, 50, 50),
	leftLeg  = Color3.fromRGB(40, 40, 50),
	rightLeg = Color3.fromRGB(40, 40, 50),
}

local function mkPart(name: string, size: Vector3, color: Color3, canCollide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = canCollide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- Build a complete R6 bot rig with name, HP bar, IsBot attribute.
-- maxHealth: required so the HP bar driver knows the scale.
-- colors: optional palette override (CasualBotService uses team colors)
function BotModel.Build(name: string, maxHealth: number, colors: BotColors?): Model
	local c = colors or DEFAULT_COLORS

	local model = Instance.new("Model")
	model.Name = name

	-- CRITICAL: build parts ANCHORED. When the model gets parented to Workspace
	-- (before being PivotTo'd to the arena), gravity would otherwise yank the
	-- unanchored parts at (0,0,0) downward; they fall below FallenPartsDestroyHeight
	-- (-500 studs by default) within ~2.5s and get auto-destroyed by Roblox,
	-- leaving a Humanoid + weapon folder ghost (the user-reported bug).
	-- Caller MUST unanchor after final positioning — see BotModel.UnanchorRig.
	local hrp = mkPart("HumanoidRootPart", Vector3.new(2, 2, 1), Color3.new(1,1,1), false)
	hrp.Transparency = 1
	hrp.CFrame = CFrame.new(0, 0, 0)
	hrp.Anchored = true
	hrp.Parent = model

	local torso    = mkPart("Torso", Vector3.new(2, 2, 1), c.torso, true);            torso.CFrame    = CFrame.new(0, 0, 0);    torso.Anchored = true; torso.Parent = model
	-- Head slightly enlarged from 1.2 → 1.6 cube to make headshots a bit easier
	-- (CS-style — head is still the highest-reward target, just less pixel-hunt).
	local head     = mkPart("Head", Vector3.new(1.6, 1.6, 1.6), c.head, true);        head.CFrame     = CFrame.new(0, 1.8, 0);  head.Anchored = true; head.Parent = model
	local leftArm  = mkPart("Left Arm",  Vector3.new(1, 2, 1), c.leftArm, true);      leftArm.CFrame  = CFrame.new(-1.5, 0, 0); leftArm.Anchored = true; leftArm.Parent = model
	local rightArm = mkPart("Right Arm", Vector3.new(1, 2, 1), c.rightArm, true);     rightArm.CFrame = CFrame.new(1.5, 0, 0);  rightArm.Anchored = true; rightArm.Parent = model
	local leftLeg  = mkPart("Left Leg",  Vector3.new(1, 2, 1), c.leftLeg, true);      leftLeg.CFrame  = CFrame.new(-0.5, -2, 0);leftLeg.Anchored = true; leftLeg.Parent = model
	local rightLeg = mkPart("Right Leg", Vector3.new(1, 2, 1), c.rightLeg, true);     rightLeg.CFrame = CFrame.new(0.5, -2, 0); rightLeg.Anchored = true; rightLeg.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = 12
	humanoid.DisplayName = name
	humanoid.Parent = model

	model.PrimaryPart = hrp
	model:SetAttribute("IsBot", true)
	-- Force the bot to fully replicate to ALL clients regardless of StreamingEnabled
	-- + camera/player position. Without this, body parts created on the server
	-- weren't being streamed to clients on the published game, so players saw
	-- bot names in the scoreboard but no characters in the arena (the user-
	-- reported bug). Persistent streaming bypasses Roblox's per-Part visibility
	-- culling for this Model's descendants.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local function motor(p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame, motorName: string)
		local m = Instance.new("Motor6D")
		m.Name = motorName
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = c0
		m.C1 = c1
		m.Parent = p0
	end
	motor(hrp, torso, CFrame.new(), CFrame.new(), "RootJoint")
	motor(torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.8, 0), "Neck")  -- C1 = -head/2 for 1.6 head
	motor(torso, leftArm, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0), "Left Shoulder")
	motor(torso, rightArm, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0), "Right Shoulder")
	motor(torso, leftLeg, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0), "Left Hip")
	motor(torso, rightLeg, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0), "Right Hip")

	-- CS-style: no overhead name, no HP bar. Damage is silent — players can't
	-- read the enemy's HP. Suppress Roblox's default Humanoid display too.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0

	return model
end

-- Unanchor all body Parts on the rig. Call AFTER the bot has been parented
-- to Workspace AND moved to its final spawn (via PivotTo). HRP stays
-- unanchored so the Humanoid can walk; if any caller anchored it post-build,
-- this also releases it. Weapon parts (in BotWeapon folder) are managed
-- separately via EquipRifle/UnequipWeapon and not touched here.
function BotModel.UnanchorRig(bot: Model)
	for _, p in bot:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
end

-- =====================================================================
-- WEAPON EQUIP — build a procedural rifle, weld it to the bot's right arm,
-- rotate the arm Motor6D so it juts forward (gripping pose), and return the
-- muzzle attachment so the bot AI can fire tracers from a believable origin.
--
-- The weapon is built from primitive blocks so it stays cheap and matches the
-- low-poly look of the procedural maps + viewmodel.
-- =====================================================================
-- nearbyAnchor: an existing positioned part whose CFrame we copy onto the
-- new weapon part so it doesn't briefly spawn at (0,0,0) inside the lobby
-- baseplate before the weld snaps it home. The bot model has already been
-- placed at its arena spawn by the time EquipRifle runs, so we want any
-- new parts to materialize near that spawn — otherwise unanchored physics
-- can push the bot when overlapping geometry resolves.
local function mkWeaponPart(parent: Instance, size: Vector3, color: Color3, material: Enum.Material?, nearbyAnchor: BasePart?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if nearbyAnchor then
		p.CFrame = nearbyAnchor.CFrame
	end
	p.Parent = parent
	return p
end

-- Weld two parts rigidly at a relative offset. Part1 is the moving piece.
-- We also pre-set Part1.CFrame to Part0 * C0 so the weld doesn't have to
-- yank the part across the world on activation (a long yank can knock
-- unanchored connected parts around momentarily).
local function weldRigid(p0: BasePart, p1: BasePart, c0: CFrame)
	p1.CFrame = p0.CFrame * c0
	local w = Instance.new("Weld")
	w.Part0 = p0
	w.Part1 = p1
	w.C0 = c0
	w.C1 = CFrame.new()
	w.Parent = p1
end

-- Returns the muzzle Attachment (world position read via attachment.WorldPosition).
function BotModel.EquipRifle(model: Model): Attachment?
	local rightArm = model:FindFirstChild("Right Arm") :: BasePart?
	if not rightArm then return nil end

	-- Rotate the right shoulder so the arm points forward (gripping pose).
	-- Default R6 arm hangs straight down; tilt ~75° forward at the shoulder.
	local torso = model:FindFirstChild("Torso") :: BasePart?
	if torso then
		local shoulder = torso:FindFirstChild("Right Shoulder") :: Motor6D?
		if shoulder then
			shoulder.C0 = shoulder.C0 * CFrame.Angles(math.rad(-75), 0, 0)
		end
		-- Also bring the LEFT arm forward a bit so it looks like a two-handed grip
		local lShoulder = torso:FindFirstChild("Left Shoulder") :: Motor6D?
		if lShoulder then
			lShoulder.C0 = lShoulder.C0 * CFrame.Angles(math.rad(-55), math.rad(-15), 0)
		end
	end

	-- Build weapon as a folder of welded parts. Anchor positions relative to the
	-- right arm's tip (which after rotation points forward).
	local weaponFolder = Instance.new("Folder")
	weaponFolder.Name = "BotWeapon"
	weaponFolder.Parent = model

	local bodyColor = Color3.fromRGB(35, 38, 45)
	local accentColor = Color3.fromRGB(60, 65, 75)
	local magColor = Color3.fromRGB(25, 28, 35)

	-- Body (receiver) — main block, sits just past the hand
	local body = mkWeaponPart(weaponFolder, Vector3.new(0.45, 0.45, 2.4), bodyColor, Enum.Material.Metal, rightArm)
	weldRigid(rightArm, body, CFrame.new(0, -1.4, 0) * CFrame.Angles(-math.pi/2, 0, 0))

	-- Barrel — thin block extending forward from body
	local barrel = mkWeaponPart(weaponFolder, Vector3.new(0.22, 0.22, 1.4), bodyColor, Enum.Material.Metal, body)
	weldRigid(body, barrel, CFrame.new(0, 0, -1.9))

	-- Magazine below body
	local mag = mkWeaponPart(weaponFolder, Vector3.new(0.4, 0.7, 0.5), magColor, Enum.Material.Plastic, body)
	weldRigid(body, mag, CFrame.new(0, -0.55, 0.3))

	-- Stock behind body
	local stock = mkWeaponPart(weaponFolder, Vector3.new(0.35, 0.45, 0.9), accentColor, Enum.Material.Wood, body)
	weldRigid(body, stock, CFrame.new(0, 0, 1.65))

	-- Sight rail on top
	local sight = mkWeaponPart(weaponFolder, Vector3.new(0.3, 0.15, 0.6), accentColor, Enum.Material.Metal, body)
	weldRigid(body, sight, CFrame.new(0, 0.3, -0.5))

	-- Muzzle attachment at the tip of the barrel — used as shot origin
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -0.75) -- front face of barrel
	muzzle.Parent = barrel

	-- Holstered pistol on back of torso for extra "tactical" look
	if torso then
		local holster = mkWeaponPart(weaponFolder, Vector3.new(0.4, 0.7, 0.25), bodyColor, Enum.Material.Metal, torso)
		weldRigid(torso, holster, CFrame.new(0.7, -0.2, 0.55))

		-- Front chest vest plate (so bots look less like plain colored cubes)
		local vest = mkWeaponPart(weaponFolder, Vector3.new(1.85, 1.5, 0.35), Color3.fromRGB(28, 30, 36), Enum.Material.Fabric, torso)
		weldRigid(torso, vest, CFrame.new(0, 0.1, -0.55))
		-- Mag pouches on the vest (three small bumps)
		for i = -1, 1 do
			local pouch = mkWeaponPart(weaponFolder, Vector3.new(0.42, 0.45, 0.18), Color3.fromRGB(20, 22, 28), Enum.Material.Fabric, torso)
			weldRigid(torso, pouch, CFrame.new(i * 0.55, -0.1, -0.78))
		end
		-- Shoulder pads
		local leftArm = model:FindFirstChild("Left Arm") :: BasePart?
		if leftArm then
			local lShoulder = mkWeaponPart(weaponFolder, Vector3.new(1.15, 0.5, 1.15), Color3.fromRGB(28, 30, 36), Enum.Material.Fabric, leftArm)
			weldRigid(leftArm, lShoulder, CFrame.new(0, 0.85, 0))
		end
		local rShoulder = mkWeaponPart(weaponFolder, Vector3.new(1.15, 0.5, 1.15), Color3.fromRGB(28, 30, 36), Enum.Material.Fabric, rightArm)
		weldRigid(rightArm, rShoulder, CFrame.new(0, 0.85, 0))
	end

	-- Helmet on head (sized for the 1.6 cube head)
	local head = model:FindFirstChild("Head") :: BasePart?
	if head then
		local helmet = mkWeaponPart(weaponFolder, Vector3.new(1.8, 0.7, 1.8), Color3.fromRGB(28, 30, 36), Enum.Material.Metal, head)
		weldRigid(head, helmet, CFrame.new(0, 0.7, 0))
		-- Visor strip across the brow
		local visor = mkWeaponPart(weaponFolder, Vector3.new(1.5, 0.22, 0.1), Color3.fromRGB(60, 80, 110), Enum.Material.Glass, head)
		weldRigid(head, visor, CFrame.new(0, 0.15, -0.85))
	end

	return muzzle
end

-- Knife variant: a curved blade weld for melee bots, no muzzle attachment.
function BotModel.EquipKnife(model: Model)
	local rightArm = model:FindFirstChild("Right Arm") :: BasePart?
	if not rightArm then return end
	local torso = model:FindFirstChild("Torso") :: BasePart?
	if torso then
		local shoulder = torso:FindFirstChild("Right Shoulder") :: Motor6D?
		if shoulder then
			shoulder.C0 = shoulder.C0 * CFrame.Angles(math.rad(-65), 0, math.rad(-10))
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "BotKnife"
	folder.Parent = model

	-- Handle
	local handle = mkWeaponPart(folder, Vector3.new(0.32, 0.32, 0.9), Color3.fromRGB(30, 25, 20), Enum.Material.Wood, rightArm)
	weldRigid(rightArm, handle, CFrame.new(0, -1.2, 0) * CFrame.Angles(-math.pi/2, 0, 0))

	-- Guard
	local guard = mkWeaponPart(folder, Vector3.new(0.7, 0.18, 0.25), Color3.fromRGB(70, 70, 80), Enum.Material.Metal, handle)
	weldRigid(handle, guard, CFrame.new(0, 0, -0.5))

	-- Blade — angled forward for a "ready to slash" pose
	local blade = mkWeaponPart(folder, Vector3.new(0.2, 0.55, 1.4), Color3.fromRGB(200, 210, 220), Enum.Material.Metal, handle)
	weldRigid(handle, blade, CFrame.new(0, 0, -1.2) * CFrame.Angles(math.rad(-10), 0, 0))
end

return BotModel
