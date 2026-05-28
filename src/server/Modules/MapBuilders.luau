--!strict
-- Map builders inspired by CS2 architecture (Dust2 / Mirage / Nuke / Cache).
-- Design principles:
--   * Solid ground at origin.Y. No floating platforms.
--   * Elevated structures sit on visible walls/pillars/stairs.
--   * Multiple sightlines, chokepoints, and cover variety per map.
--   * Map size ~240x200, allowing room for 6-12 players.
local MapDecorator = require(script.Parent.MapDecorator)

local MapBuilders = {}

-- ============================================================
-- HELPERS
-- ============================================================
local function makePart(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function makeBox(parent: Instance, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	return makePart(parent, {
		Size = size,
		Position = position,
		Color = color,
		Material = material,
	})
end

-- Spawn marker visual: invisible SpawnLocation (functional positional marker
-- only — ArenaService reads .Position from these) + a glowing vertical light
-- beam rising from the floor. Replaces the previous "floating Neon cube"
-- look with a "sinar dari lantai" effect per user request.
local function makeSpawn(parent: Instance, position: Vector3, color: Color3): SpawnLocation
	local sp = Instance.new("SpawnLocation")
	sp.Anchored = true
	sp.Size = Vector3.new(4, 1, 4)
	sp.Position = position
	-- Invisible + non-collidable — the position is still used by the spawn
	-- logic but nothing visual or physical lives here.
	sp.Transparency = 1
	sp.CanCollide = false
	sp.TopSurface = Enum.SurfaceType.Smooth
	sp.BottomSurface = Enum.SurfaceType.Smooth
	sp.Neutral = true
	sp.AllowTeamChangeOnTouch = false
	sp.Duration = 0
	sp.Enabled = true
	sp.Parent = parent

	-- Find the actual floor Y below this spawn so the beam starts AT the
	-- ground, not at the spawn's floating height. Falls back to spawn Y
	-- if nothing is below (shouldn't happen in a well-built map).
	local floorY = position.Y - 3 -- safe default (spawn pattern across maps = Y=3 above floor)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { sp }
	local hit = workspace:Raycast(position + Vector3.new(0, 0.5, 0), Vector3.new(0, -50, 0), rayParams)
	if hit then floorY = hit.Position.Y end

	-- Vertical light pillar — Neon cylinder rotated 90° around Z so its long
	-- axis points up. Tall and translucent so it reads as "energy beam" from
	-- a distance without blocking sight lines.
	local BEAM_HEIGHT = 15
	local BEAM_DIAMETER = 2.8
	local beam = Instance.new("Part")
	beam.Name = "SpawnBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CastShadow = false
	beam.Shape = Enum.PartType.Cylinder
	-- Cylinder convention: long axis = local +X. Size.X = beam length, Y/Z = diameter.
	beam.Size = Vector3.new(BEAM_HEIGHT, BEAM_DIAMETER, BEAM_DIAMETER)
	-- Center beam vertically: bottom rests on floorY, extends BEAM_HEIGHT upward.
	beam.CFrame = CFrame.new(position.X, floorY + BEAM_HEIGHT / 2, position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	beam.Color = color
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.5
	beam.TopSurface = Enum.SurfaceType.Smooth
	beam.BottomSurface = Enum.SurfaceType.Smooth
	beam.Parent = parent

	-- Soft base glow on the floor surrounding the beam — anchors the light
	-- visually to the ground so players see "ah, spawn here" from distance.
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.6
	light.Range = 14
	light.Shadows = false
	light.Parent = beam

	-- Floor disc — flat Neon circle at the beam's base for a "landing pad"
	-- feel. Same color as the beam, slightly brighter (full opacity) so it
	-- contrasts the translucent column above it.
	local disc = Instance.new("Part")
	disc.Name = "SpawnDisc"
	disc.Anchored = true
	disc.CanCollide = false
	disc.CastShadow = false
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.2, 6, 6) -- thin, 6-stud wide circle
	disc.CFrame = CFrame.new(position.X, floorY + 0.1, position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	disc.Color = color
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.2
	disc.Parent = parent

	return sp
end

local function spawnsFolder(parent: Folder): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Spawns"
	folder.Parent = parent
	return folder
end

-- Solid ground at origin.Y level (top surface at origin.Y).
local function makeGround(parent: Instance, origin: Vector3, width: number, depth: number, color: Color3, material: Enum.Material)
	return makeBox(
		parent,
		Vector3.new(width, 4, depth),
		origin + Vector3.new(0, -2, 0),
		color,
		material
	)
end

local function makePerimeterWalls(parent: Instance, origin: Vector3, width: number, depth: number, height: number, color: Color3, material: Enum.Material)
	local t = 2
	local halfW = width / 2
	local halfD = depth / 2
	local y = origin.Y + height / 2
	makeBox(parent, Vector3.new(width, height, t), Vector3.new(origin.X, y, origin.Z + halfD), color, material)
	makeBox(parent, Vector3.new(width, height, t), Vector3.new(origin.X, y, origin.Z - halfD), color, material)
	makeBox(parent, Vector3.new(t, height, depth), Vector3.new(origin.X + halfW, y, origin.Z), color, material)
	makeBox(parent, Vector3.new(t, height, depth), Vector3.new(origin.X - halfW, y, origin.Z), color, material)
end

-- A 4-wall building with optional door opening on one side + roof.
local function makeBuilding(parent: Instance, origin: Vector3, size: Vector3, wallColor: Color3, roofColor: Color3, material: Enum.Material, doorSide: string?)
	local halfW = size.X / 2
	local halfD = size.Z / 2
	local h = size.Y
	local t = 1
	local centerY = origin.Y + h / 2

	local function wallWithDoor(axis: string, isPositive: boolean)
		local s = (axis == "x") and size.X or size.Z
		local segLen = (s - 10) / 2
		if axis == "x" then
			local zSign = isPositive and halfD or -halfD
			makeBox(parent, Vector3.new(segLen, h, t), Vector3.new(origin.X - 5 - segLen / 2, centerY, origin.Z + zSign), wallColor, material)
			makeBox(parent, Vector3.new(segLen, h, t), Vector3.new(origin.X + 5 + segLen / 2, centerY, origin.Z + zSign), wallColor, material)
			makeBox(parent, Vector3.new(10, math.max(1, h - 8), t), Vector3.new(origin.X, centerY + 4, origin.Z + zSign), wallColor, material)
		else
			local xSign = isPositive and halfW or -halfW
			makeBox(parent, Vector3.new(t, h, segLen), Vector3.new(origin.X + xSign, centerY, origin.Z - 5 - segLen / 2), wallColor, material)
			makeBox(parent, Vector3.new(t, h, segLen), Vector3.new(origin.X + xSign, centerY, origin.Z + 5 + segLen / 2), wallColor, material)
			makeBox(parent, Vector3.new(t, math.max(1, h - 8), 10), Vector3.new(origin.X + xSign, centerY + 4, origin.Z), wallColor, material)
		end
	end

	-- North wall (z+)
	if doorSide == "north" then
		wallWithDoor("x", true)
	else
		makeBox(parent, Vector3.new(size.X, h, t), Vector3.new(origin.X, centerY, origin.Z + halfD), wallColor, material)
	end
	-- South wall (z-)
	if doorSide == "south" then
		wallWithDoor("x", false)
	else
		makeBox(parent, Vector3.new(size.X, h, t), Vector3.new(origin.X, centerY, origin.Z - halfD), wallColor, material)
	end
	-- East wall (x+)
	if doorSide == "east" then
		wallWithDoor("z", true)
	else
		makeBox(parent, Vector3.new(t, h, size.Z), Vector3.new(origin.X + halfW, centerY, origin.Z), wallColor, material)
	end
	-- West wall (x-)
	if doorSide == "west" then
		wallWithDoor("z", false)
	else
		makeBox(parent, Vector3.new(t, h, size.Z), Vector3.new(origin.X - halfW, centerY, origin.Z), wallColor, material)
	end
	-- Roof
	makeBox(parent, Vector3.new(size.X, t, size.Z), Vector3.new(origin.X, origin.Y + h, origin.Z), roofColor, material)
end

local function makeStairs(parent: Instance, basePos: Vector3, steps: number, stepHeight: number, stepDepth: number, width: number, color: Color3, material: Enum.Material)
	for i = 1, steps do
		makeBox(
			parent,
			Vector3.new(width, stepHeight, stepDepth),
			basePos + Vector3.new(0, (i - 0.5) * stepHeight, (i - 0.5) * stepDepth),
			color,
			material
		)
	end
end

local function makeContainer(parent: Instance, position: Vector3, size: Vector3, color: Color3)
	return makeBox(parent, size, position, color, Enum.Material.CorrodedMetal)
end

local function makePillar(parent: Instance, x: number, z: number, baseY: number, height: number, size: number, color: Color3, material: Enum.Material)
	return makeBox(
		parent,
		Vector3.new(size, height, size),
		Vector3.new(x, baseY + height / 2, z),
		color,
		material
	)
end

-- ============================================================
-- WAREHOUSE: industrial hangar with two warehouses + central yard.
-- Inspired by Dust2 catwalk + Cache mid.
-- ============================================================
function MapBuilders.warehouse(parent: Folder, origin: Vector3)
	local floorColor = Color3.fromRGB(95, 90, 85)
	local wallColor = Color3.fromRGB(180, 100, 75) -- warm terracotta brick
	local trimColor = Color3.fromRGB(220, 165, 90) -- warm wood/tile roof
	local crateColor = Color3.fromRGB(140, 95, 55)
	local accentColor = Color3.fromRGB(255, 165, 50)
	local containerRed = Color3.fromRGB(170, 65, 65)
	local containerBlue = Color3.fromRGB(55, 100, 150)
	local containerGreen = Color3.fromRGB(75, 130, 85)

	local width, depth = 240, 200

	makeGround(parent, origin, width, depth, floorColor, Enum.Material.Concrete)
	makePerimeterWalls(parent, origin, width, depth, 22, wallColor, Enum.Material.Brick)

	makeBuilding(parent, origin + Vector3.new(-75, 0, 0), Vector3.new(60, 20, 70), wallColor, trimColor, Enum.Material.Brick, "east")
	makeBuilding(parent, origin + Vector3.new(75, 0, 0), Vector3.new(60, 20, 70), wallColor, trimColor, Enum.Material.Brick, "west")

	makeStairs(parent, origin + Vector3.new(-105, 0, 40), 12, 1.7, 1.5, 8, trimColor, Enum.Material.Metal)
	makeStairs(parent, origin + Vector3.new(105, 0, -40), 12, 1.7, 1.5, 8, trimColor, Enum.Material.Metal)

	makeContainer(parent, origin + Vector3.new(-10, 4, -20), Vector3.new(20, 8, 8), containerRed)
	makeContainer(parent, origin + Vector3.new(10, 4, 20), Vector3.new(20, 8, 8), containerBlue)
	makeContainer(parent, origin + Vector3.new(0, 4, 0), Vector3.new(8, 8, 16), containerGreen)
	makeContainer(parent, origin + Vector3.new(-30, 4, 50), Vector3.new(16, 8, 12), containerRed)
	makeContainer(parent, origin + Vector3.new(-30, 12, 50), Vector3.new(16, 8, 12), containerBlue)
	makeContainer(parent, origin + Vector3.new(30, 4, -50), Vector3.new(16, 8, 12), containerGreen)
	makeContainer(parent, origin + Vector3.new(30, 12, -50), Vector3.new(16, 8, 12), containerRed)

	local cratePositions = {
		Vector3.new(-40, 0, -60), Vector3.new(40, 0, -60), Vector3.new(-40, 0, 60), Vector3.new(40, 0, 60),
		Vector3.new(-55, 0, -10), Vector3.new(55, 0, 10),
		Vector3.new(0, 0, -80), Vector3.new(0, 0, 80),
	}
	for _, p in cratePositions do
		makeBox(parent, Vector3.new(5, 5, 5), origin + p + Vector3.new(0, 2.5, 0), crateColor, Enum.Material.WoodPlanks)
	end

	makeBox(parent, Vector3.new(width - 20, 0.2, 2), origin + Vector3.new(0, 0.1, 0), accentColor, Enum.Material.Neon)

	-- Forklift mockup
	makeBox(parent, Vector3.new(6, 4, 10), origin + Vector3.new(-20, 2, 80), Color3.fromRGB(220, 180, 40), Enum.Material.Metal)
	makeBox(parent, Vector3.new(2, 8, 2), origin + Vector3.new(-22, 6, 85), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)

	local spawns = spawnsFolder(parent)
	local spawnPositions = {
		Vector3.new(-110, 3, -90), Vector3.new(110, 3, 90),
		Vector3.new(-110, 3, 90), Vector3.new(110, 3, -90),
		Vector3.new(0, 3, -95), Vector3.new(0, 3, 95),
	}
	for _, p in spawnPositions do
		makeSpawn(spawns, origin + p, accentColor)
	end

	-- Set dressing — industrial rust barrels/crates scattered around floor,
	-- ceiling lights for interior atmosphere, neon edge accents for the arena
	-- perimeter. Seed is map-id-stable so layout is deterministic per server.
	local avoidPts = MapDecorator.GetSpawnPositions(spawns)
	MapDecorator.ScatterProps(parent, origin, width - 60, depth - 60, 14, "industrial", avoidPts, 31415)
	MapDecorator.MakeArenaEdgeNeon(parent, origin, width, depth, 0.6, "industrial")
	-- 4 ceiling lights at hanging height (15) — gives the warehouse interior glow
	for _, lp in { Vector3.new(-60, 15, -40), Vector3.new(60, 15, 40), Vector3.new(-60, 15, 40), Vector3.new(60, 15, -40) } do
		MapDecorator.MakeCeilingLight(parent, origin + lp, "industrial")
	end
end

-- ============================================================
-- ROOFTOP (Mirage Streets style): two long buildings + central plaza.
-- Solid ground, no floating platforms.
-- ============================================================
function MapBuilders.rooftop(parent: Folder, origin: Vector3)
	local groundColor = Color3.fromRGB(170, 145, 110)
	local wallColor = Color3.fromRGB(210, 175, 130) -- warm cream brick
	local trimColor = Color3.fromRGB(160, 110, 70)
	local roofColor = Color3.fromRGB(130, 80, 55)
	local accent = Color3.fromRGB(70, 150, 220)

	local width, depth = 230, 190

	makeGround(parent, origin, width, depth, groundColor, Enum.Material.Cobblestone)
	makePerimeterWalls(parent, origin, width, depth, 22, wallColor, Enum.Material.Brick)

	makeBuilding(parent, origin + Vector3.new(0, 0, 70), Vector3.new(160, 24, 30), wallColor, roofColor, Enum.Material.Brick, "south")
	makeBuilding(parent, origin + Vector3.new(0, 0, -70), Vector3.new(160, 24, 30), wallColor, roofColor, Enum.Material.Brick, "north")

	-- Central plaza cover (low walls)
	makeBox(parent, Vector3.new(8, 4, 24), origin + Vector3.new(-30, 2, 0), trimColor, Enum.Material.Brick)
	makeBox(parent, Vector3.new(8, 4, 24), origin + Vector3.new(30, 2, 0), trimColor, Enum.Material.Brick)
	makeBox(parent, Vector3.new(20, 3, 8), origin + Vector3.new(0, 1.5, -25), trimColor, Enum.Material.Brick)
	makeBox(parent, Vector3.new(20, 3, 8), origin + Vector3.new(0, 1.5, 25), trimColor, Enum.Material.Brick)

	makePillar(parent, origin.X - 60, origin.Z, origin.Y, 16, 3, trimColor, Enum.Material.Brick)
	makePillar(parent, origin.X + 60, origin.Z, origin.Y, 16, 3, trimColor, Enum.Material.Brick)
	makePillar(parent, origin.X - 60, origin.Z + 35, origin.Y, 16, 3, trimColor, Enum.Material.Brick)
	makePillar(parent, origin.X + 60, origin.Z - 35, origin.Y, 16, 3, trimColor, Enum.Material.Brick)

	makeStairs(parent, origin + Vector3.new(-100, 0, 50), 14, 1.7, 1.4, 8, trimColor, Enum.Material.Cobblestone)
	makeStairs(parent, origin + Vector3.new(100, 0, -50), 14, 1.7, 1.4, 8, trimColor, Enum.Material.Cobblestone)

	-- Palm-like decoratives
	makePillar(parent, origin.X - 90, origin.Z + 30, origin.Y, 12, 1, Color3.fromRGB(80, 60, 40), Enum.Material.Wood)
	makePillar(parent, origin.X + 90, origin.Z - 30, origin.Y, 12, 1, Color3.fromRGB(80, 60, 40), Enum.Material.Wood)
	makeBox(parent, Vector3.new(8, 1, 8), origin + Vector3.new(-90, 12, 30), Color3.fromRGB(50, 130, 60), Enum.Material.Grass)
	makeBox(parent, Vector3.new(8, 1, 8), origin + Vector3.new(90, 12, -30), Color3.fromRGB(50, 130, 60), Enum.Material.Grass)

	makeBox(parent, Vector3.new(width - 20, 0.2, 1.5), origin + Vector3.new(0, 0.1, -10), accent, Enum.Material.Neon)
	makeBox(parent, Vector3.new(width - 20, 0.2, 1.5), origin + Vector3.new(0, 0.1, 10), accent, Enum.Material.Neon)

	local spawns = spawnsFolder(parent)
	local spawnPositions = {
		Vector3.new(-105, 3, -80), Vector3.new(105, 3, 80),
		Vector3.new(-105, 3, 80), Vector3.new(105, 3, -80),
		Vector3.new(-50, 3, -88), Vector3.new(50, 3, 88),
	}
	for _, p in spawnPositions do
		makeSpawn(spawns, origin + p, accent)
	end

	-- Urban rooftop dressing — AC units (as crates) + cyan neon edge.
	-- Fewer props than warehouse since rooftop is open/airy.
	local avoidPts = MapDecorator.GetSpawnPositions(spawns)
	MapDecorator.ScatterProps(parent, origin, width - 80, depth - 80, 10, "urban", avoidPts, 27182)
	MapDecorator.MakeArenaEdgeNeon(parent, origin, width, depth, 0.6, "urban")
end

-- ============================================================
-- DESERT: wide open ruins + central bombsite-like pillared structure.
-- Inspired by Dust2 Long A / Mid.
-- ============================================================
function MapBuilders.desert(parent: Folder, origin: Vector3)
	local sandColor = Color3.fromRGB(225, 195, 145)
	local brickColor = Color3.fromRGB(200, 130, 85) -- adobe brick (warm orange)
	local darkBrickColor = Color3.fromRGB(150, 95, 60)
	local accentColor = Color3.fromRGB(220, 140, 50)

	local width, depth = 280, 220

	makeGround(parent, origin, width, depth, sandColor, Enum.Material.Sand)
	makePerimeterWalls(parent, origin, width, depth, 22, brickColor, Enum.Material.Brick)

	makeBox(parent, Vector3.new(40, 0.3, 40), origin + Vector3.new(0, 0.15, 0), darkBrickColor, Enum.Material.Cobblestone)
	makePillar(parent, origin.X - 18, origin.Z - 18, origin.Y, 18, 4, brickColor, Enum.Material.Brick)
	makePillar(parent, origin.X + 18, origin.Z - 18, origin.Y, 18, 4, brickColor, Enum.Material.Brick)
	makePillar(parent, origin.X - 18, origin.Z + 18, origin.Y, 18, 4, brickColor, Enum.Material.Brick)
	makePillar(parent, origin.X + 18, origin.Z + 18, origin.Y, 18, 4, brickColor, Enum.Material.Brick)
	makeBox(parent, Vector3.new(40, 2, 4), origin + Vector3.new(0, 19, -18), brickColor, Enum.Material.Brick)
	makeBox(parent, Vector3.new(40, 2, 4), origin + Vector3.new(0, 19, 18), brickColor, Enum.Material.Brick)

	makeBuilding(parent, origin + Vector3.new(-90, 0, -70), Vector3.new(40, 16, 35), brickColor, darkBrickColor, Enum.Material.Brick, "east")
	makeBuilding(parent, origin + Vector3.new(90, 0, 70), Vector3.new(40, 16, 35), brickColor, darkBrickColor, Enum.Material.Brick, "west")
	makeBuilding(parent, origin + Vector3.new(-90, 0, 70), Vector3.new(40, 14, 30), brickColor, darkBrickColor, Enum.Material.Brick, "south")
	makeBuilding(parent, origin + Vector3.new(90, 0, -70), Vector3.new(40, 14, 30), brickColor, darkBrickColor, Enum.Material.Brick, "north")

	-- Sand dunes
	makeBox(parent, Vector3.new(24, 4, 14), origin + Vector3.new(-50, 2, 30), sandColor, Enum.Material.Sand)
	makeBox(parent, Vector3.new(20, 3, 12), origin + Vector3.new(-50, 5, 30), sandColor, Enum.Material.Sand)
	makeBox(parent, Vector3.new(24, 4, 14), origin + Vector3.new(50, 2, -30), sandColor, Enum.Material.Sand)
	makeBox(parent, Vector3.new(20, 3, 12), origin + Vector3.new(50, 5, -30), sandColor, Enum.Material.Sand)

	-- Brick half-cover walls
	makeBox(parent, Vector3.new(20, 5, 2), origin + Vector3.new(-40, 2.5, 0), brickColor, Enum.Material.Brick)
	makeBox(parent, Vector3.new(2, 5, 20), origin + Vector3.new(40, 2.5, 0), brickColor, Enum.Material.Brick)
	makeBox(parent, Vector3.new(20, 5, 2), origin + Vector3.new(60, 2.5, 50), brickColor, Enum.Material.Brick)
	makeBox(parent, Vector3.new(2, 5, 20), origin + Vector3.new(-60, 2.5, -50), brickColor, Enum.Material.Brick)

	-- Wooden carts
	makeBox(parent, Vector3.new(8, 3, 4), origin + Vector3.new(-115, 1.5, -10), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
	makeBox(parent, Vector3.new(8, 3, 4), origin + Vector3.new(115, 1.5, 10), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)

	makeBox(parent, Vector3.new(width - 20, 0.2, 6), origin + Vector3.new(0, 0.11, 0), accentColor, Enum.Material.Sand)

	local spawns = spawnsFolder(parent)
	local spawnPositions = {
		Vector3.new(-130, 3, -100), Vector3.new(130, 3, 100),
		Vector3.new(-130, 3, 100), Vector3.new(130, 3, -100),
		Vector3.new(0, 3, -105), Vector3.new(0, 3, 105),
	}
	for _, p in spawnPositions do
		makeSpawn(spawns, origin + p, accentColor)
	end

	-- Desert dressing — weathered barrels/crates, sand-yellow neon strips.
	local avoidPts = MapDecorator.GetSpawnPositions(spawns)
	MapDecorator.ScatterProps(parent, origin, width - 70, depth - 70, 16, "desert", avoidPts, 16180)
	MapDecorator.MakeArenaEdgeNeon(parent, origin, width, depth, 0.6, "desert")
end

-- ============================================================
-- METRO: underground subway station with platform + train wreck.
-- Inspired by Inferno banana + Train metro.
-- ============================================================
function MapBuilders.metro(parent: Folder, origin: Vector3)
	local floorColor = Color3.fromRGB(80, 80, 90)
	local wallColor = Color3.fromRGB(190, 160, 130) -- cream subway tile / brick
	local trimColor = Color3.fromRGB(120, 90, 70)
	local pillarColor = Color3.fromRGB(140, 110, 85)
	local accentColor = Color3.fromRGB(255, 200, 60)
	local neonBlue = Color3.fromRGB(80, 160, 240)
	local trainColor = Color3.fromRGB(180, 60, 60)

	local width, depth = 250, 180

	makeGround(parent, origin, width, depth, floorColor, Enum.Material.Cobblestone)
	makePerimeterWalls(parent, origin, width, depth, 22, wallColor, Enum.Material.Brick)

	-- Ceiling
	makeBox(parent, Vector3.new(width, 1, depth), origin + Vector3.new(0, 22, 0), trimColor, Enum.Material.Brick)

	-- Raised platform
	makeBox(parent, Vector3.new(width - 40, 3, 40), origin + Vector3.new(0, 1.5, 0), Color3.fromRGB(180, 170, 150), Enum.Material.Concrete)
	makeBox(parent, Vector3.new(width - 40, 0.3, 2), origin + Vector3.new(0, 3.2, 22), accentColor, Enum.Material.Neon)
	makeBox(parent, Vector3.new(width - 40, 0.3, 2), origin + Vector3.new(0, 3.2, -22), accentColor, Enum.Material.Neon)

	-- Pillars
	for i = -2, 2 do
		makePillar(parent, origin.X + i * 40, origin.Z - 60, origin.Y, 22, 3, pillarColor, Enum.Material.Brick)
		makePillar(parent, origin.X + i * 40, origin.Z + 60, origin.Y, 22, 3, pillarColor, Enum.Material.Brick)
	end

	-- Train wreck
	makeBox(parent, Vector3.new(80, 10, 12), origin + Vector3.new(-50, 5, 65), trainColor, Enum.Material.Metal)
	makeBox(parent, Vector3.new(78, 4, 8), origin + Vector3.new(-50, 12, 65), Color3.fromRGB(100, 30, 30), Enum.Material.Metal)
	for i = 0, 5 do
		makeBox(parent, Vector3.new(10, 4, 1), origin + Vector3.new(-80 + i * 12, 9, 71.5), neonBlue, Enum.Material.Neon)
	end

	-- Track rails
	makeBox(parent, Vector3.new(width - 40, 0.3, 2), origin + Vector3.new(0, 0.16, -60), Color3.fromRGB(40, 40, 50), Enum.Material.Metal)
	makeBox(parent, Vector3.new(width - 40, 0.3, 2), origin + Vector3.new(0, 0.16, 60), Color3.fromRGB(40, 40, 50), Enum.Material.Metal)

	-- Exit stairs at ends
	makeStairs(parent, origin + Vector3.new(-110, 0, 0), 8, 1.5, 1.5, 12, trimColor, Enum.Material.Concrete)
	makeStairs(parent, origin + Vector3.new(110, 0, 0), 8, 1.5, 1.5, 12, trimColor, Enum.Material.Concrete)

	-- Neon ceiling lights
	for i = -3, 3 do
		makeBox(parent, Vector3.new(20, 0.5, 2), origin + Vector3.new(i * 30, 21.5, 0), neonBlue, Enum.Material.Neon)
	end

	-- Benches
	makeBox(parent, Vector3.new(10, 1.5, 2), origin + Vector3.new(-30, 3.75, 15), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
	makeBox(parent, Vector3.new(10, 1.5, 2), origin + Vector3.new(30, 3.75, -15), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)

	makeBox(parent, Vector3.new(width - 40, 0.2, 3), origin + Vector3.new(0, 3.21, 0), accentColor, Enum.Material.Neon)

	local spawns = spawnsFolder(parent)
	local spawnPositions = {
		Vector3.new(-115, 4, -75), Vector3.new(115, 4, 75),
		Vector3.new(-115, 4, 75), Vector3.new(115, 4, -75),
		Vector3.new(-50, 4, -80), Vector3.new(50, 4, 80),
	}
	for _, p in spawnPositions do
		makeSpawn(spawns, origin + p, accentColor)
	end

	-- Subway dressing — extra ceiling lights at platform ends, industrial drums,
	-- amber neon edge underlines the platform border.
	local avoidPts = MapDecorator.GetSpawnPositions(spawns)
	MapDecorator.ScatterProps(parent, origin, width - 80, depth - 100, 10, "industrial", avoidPts, 12345)
	MapDecorator.MakeArenaEdgeNeon(parent, origin, width, depth, 0.6, "industrial")
	for _, lp in { Vector3.new(-80, 18, 0), Vector3.new(80, 18, 0), Vector3.new(0, 18, 40), Vector3.new(0, 18, -40) } do
		MapDecorator.MakeCeilingLight(parent, origin + lp, "industrial")
	end
end

-- ============================================================
-- HARBOR: shipping yard with container maze + crane + catwalks.
-- Inspired by Cache / Overpass dock area.
-- ============================================================
function MapBuilders.harbor(parent: Folder, origin: Vector3)
	local floorColor = Color3.fromRGB(95, 95, 100)
	local wallColor = Color3.fromRGB(160, 100, 80) -- weathered brick (port building)
	local catwalkColor = Color3.fromRGB(90, 100, 110)
	local accentColor = Color3.fromRGB(60, 160, 200)
	local craneColor = Color3.fromRGB(220, 150, 30)

	local containerRed = Color3.fromRGB(170, 65, 65)
	local containerBlue = Color3.fromRGB(60, 110, 160)
	local containerGreen = Color3.fromRGB(65, 130, 85)
	local containerYellow = Color3.fromRGB(220, 185, 60)
	local containerRust = Color3.fromRGB(160, 105, 70)

	local width, depth = 240, 220

	makeGround(parent, origin, width, depth, floorColor, Enum.Material.Concrete)
	makePerimeterWalls(parent, origin, width, depth, 22, wallColor, Enum.Material.Brick)

	local layouts = {
		{ pos = Vector3.new(-60, 4, -50), size = Vector3.new(24, 8, 10), color = containerRed },
		{ pos = Vector3.new(-60, 12, -50), size = Vector3.new(24, 8, 10), color = containerBlue },
		{ pos = Vector3.new(-30, 4, -50), size = Vector3.new(24, 8, 10), color = containerGreen },
		{ pos = Vector3.new(60, 4, 50), size = Vector3.new(24, 8, 10), color = containerYellow },
		{ pos = Vector3.new(60, 12, 50), size = Vector3.new(24, 8, 10), color = containerRust },
		{ pos = Vector3.new(30, 4, 50), size = Vector3.new(24, 8, 10), color = containerBlue },
		{ pos = Vector3.new(0, 4, 0), size = Vector3.new(30, 8, 12), color = containerRed },
		{ pos = Vector3.new(-80, 4, 60), size = Vector3.new(20, 8, 12), color = containerYellow },
		{ pos = Vector3.new(80, 4, -60), size = Vector3.new(20, 8, 12), color = containerGreen },
		{ pos = Vector3.new(-30, 4, 80), size = Vector3.new(24, 8, 10), color = containerRust },
		{ pos = Vector3.new(30, 4, -80), size = Vector3.new(24, 8, 10), color = containerBlue },
		{ pos = Vector3.new(0, 12, 0), size = Vector3.new(30, 8, 12), color = containerGreen },
		{ pos = Vector3.new(0, 20, 0), size = Vector3.new(30, 8, 12), color = containerYellow },
	}
	for _, c in layouts do
		makeContainer(parent, origin + c.pos, c.size, c.color)
	end

	-- Catwalk along north edge
	makeBox(parent, Vector3.new(width - 20, 1, 8), origin + Vector3.new(0, 12, 95), catwalkColor, Enum.Material.Metal)
	makeBox(parent, Vector3.new(width - 20, 4, 0.5), origin + Vector3.new(0, 14.5, 99), catwalkColor, Enum.Material.Metal)
	makeStairs(parent, origin + Vector3.new(-100, 0, 85), 10, 1.4, 1.2, 6, catwalkColor, Enum.Material.Metal)
	makeStairs(parent, origin + Vector3.new(100, 0, 85), 10, 1.4, 1.2, 6, catwalkColor, Enum.Material.Metal)

	-- Crane tower (decorative)
	makeBox(parent, Vector3.new(4, 50, 4), origin + Vector3.new(-100, 25, -50), craneColor, Enum.Material.Metal)
	makeBox(parent, Vector3.new(50, 3, 3), origin + Vector3.new(-75, 48, -50), craneColor, Enum.Material.Metal)
	makeBox(parent, Vector3.new(8, 5, 5), origin + Vector3.new(-110, 48, -50), Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
	makeBox(parent, Vector3.new(0.4, 12, 0.4), origin + Vector3.new(-60, 42, -50), Color3.fromRGB(40, 40, 50), Enum.Material.Metal)
	makeBox(parent, Vector3.new(2, 2, 2), origin + Vector3.new(-60, 36, -50), Color3.fromRGB(50, 50, 60), Enum.Material.Metal)

	-- Loading dock
	makeBox(parent, Vector3.new(40, 2, 60), origin + Vector3.new(95, 1, 0), Color3.fromRGB(130, 110, 80), Enum.Material.Wood)
	for i = -2, 2 do
		makeBox(parent, Vector3.new(2, 4, 2), origin + Vector3.new(115, 2, i * 12), Color3.fromRGB(50, 40, 30), Enum.Material.Metal)
	end

	makeBox(parent, Vector3.new(width - 20, 0.2, 2), origin + Vector3.new(0, 0.11, -30), accentColor, Enum.Material.Neon)
	makeBox(parent, Vector3.new(width - 20, 0.2, 2), origin + Vector3.new(0, 0.11, 30), accentColor, Enum.Material.Neon)

	local spawns = spawnsFolder(parent)
	local spawnPositions = {
		Vector3.new(-110, 3, -100), Vector3.new(110, 3, 100),
		Vector3.new(-110, 3, 100), Vector3.new(110, 3, -100),
		Vector3.new(0, 3, -105), Vector3.new(0, 3, 105),
	}
	for _, p in spawnPositions do
		makeSpawn(spawns, origin + p, accentColor)
	end

	-- Harbor dressing — rust barrels around container maze (industrial theme),
	-- cyan-blue neon edge matches accentColor for cohesive look.
	local avoidPts = MapDecorator.GetSpawnPositions(spawns)
	MapDecorator.ScatterProps(parent, origin, width - 60, depth - 80, 18, "industrial", avoidPts, 11235)
	MapDecorator.MakeArenaEdgeNeon(parent, origin, width, depth, 0.6, "industrial", accentColor)
end

-- ============================================================
-- DUST II (Casual mode): T (south) vs CT (north) bomb plant/defuse map.
-- Three lanes: B tunnels (west), Mid (center), Long A (east).
-- Two bomb sites: A (northeast), B (northwest). Spawns tagged with Team
-- attribute ("T" or "CT") so CasualService can filter via ArenaService.
-- BombSites folder holds two volumes with BombSite attribute ("A" / "B")
-- that T must stand inside to plant.
-- ============================================================
function MapBuilders.dust2(parent: Folder, origin: Vector3)
	-- CS Dust II — canonical layout recreation. Coordinate convention:
	--   +X = east (A side: long, A site, outside long)
	--   -X = west (B side: tunnels, B site)
	--   +Z = south (T spawn)
	--   -Z = north (CT spawn)
	-- All distances tuned for Roblox FPS pacing (~16 walkspeed, ~6s mid-to-CT).
	local sandColor   = Color3.fromRGB(225, 195, 130)
	local wallColor   = Color3.fromRGB(195, 155, 100)
	local trimColor   = Color3.fromRGB(155, 105, 65)
	local archColor   = Color3.fromRGB(170, 130, 85)
	local tileColor   = Color3.fromRGB(175, 150, 110)
	local crateColor  = Color3.fromRGB(140, 95, 50)
	local plankColor  = Color3.fromRGB(170, 125, 70)
	local carRed      = Color3.fromRGB(165, 50, 45)
	local carGlass    = Color3.fromRGB(35, 40, 55)
	local truckGreen  = Color3.fromRGB(85, 105, 70)    -- outside long truck
	local blueBarrel  = Color3.fromRGB(70, 110, 165)
	local yellowAccent= Color3.fromRGB(240, 195, 70)
	local catwalkGrey = Color3.fromRGB(100, 95, 90)
	local siteAColor  = Color3.fromRGB(245, 110, 95)
	local siteBColor  = Color3.fromRGB(95, 145, 230)
	local tSpawnTint  = Color3.fromRGB(220, 140, 50)
	local ctSpawnTint = Color3.fromRGB(80, 140, 220)
	local rebarColor  = Color3.fromRGB(110, 95, 70)    -- rebar/metal trim on walls
	local wheelColor  = Color3.fromRGB(25, 25, 30)
	local doorWood    = Color3.fromRGB(110, 70, 35)

	local width, depth = 360, 300
	makeGround(parent, origin, width, depth, sandColor, Enum.Material.Sand)
	makePerimeterWalls(parent, origin, width, depth, 32, wallColor, Enum.Material.Sandstone)

	-- ----- Local helpers (Dust2-specific composite shapes) -----

	-- Arch: two columns + keystone beam (used at every Dust2 doorway).
	local function arch(center: Vector3, w: number, h: number, d: number, color: Color3)
		local colW = 2
		makeBox(parent, Vector3.new(colW, h, d),
			center + Vector3.new(-(w/2) - colW/2, h/2, 0), color, Enum.Material.Sandstone)
		makeBox(parent, Vector3.new(colW, h, d),
			center + Vector3.new( (w/2) + colW/2, h/2, 0), color, Enum.Material.Sandstone)
		makeBox(parent, Vector3.new(w + colW*2 + 1, 3, d + 0.5),
			center + Vector3.new(0, h + 1.5, 0), archColor, Enum.Material.Sandstone)
	end

	-- Wall segment (single rect, sandstone) — shorthand
	local function wall(size: Vector3, pos: Vector3, color: Color3?)
		makeBox(parent, size, pos, color or wallColor, Enum.Material.Sandstone)
	end

	-- Crate stack — N stacked wooden boxes for cover
	local function crateStack(x: number, z: number, baseY: number, count: number, sizeXY: number)
		for i = 1, count do
			local y = baseY + (i - 0.5) * sizeXY
			local c = (i == count) and plankColor or crateColor
			makeBox(parent, Vector3.new(sizeXY, sizeXY, sizeXY),
				origin + Vector3.new(x, y, z), c, Enum.Material.WoodPlanks)
		end
	end

	-- Car: composite (body + cabin + hood + 4 wheels + windows). Used for
	-- A site red car AND B site cars (recolored).
	local function car(cx: number, cz: number, color: Color3, rotation: number?)
		-- rotation 0 = car points east-west (long axis along X)
		-- rotation 90 = car points north-south (long axis along Z) — not implemented; use rotated parts
		local r = rotation or 0
		local cosR = math.cos(math.rad(r))
		local sinR = math.sin(math.rad(r))
		local function place(sx: number, sy: number, sz: number, ox: number, oy: number, oz: number, col: Color3, mat: Enum.Material)
			-- Rotate offset around vertical axis
			local rx = ox * cosR - oz * sinR
			local rz = ox * sinR + oz * cosR
			local p = makeBox(parent, Vector3.new(
				sx * math.abs(cosR) + sz * math.abs(sinR),
				sy,
				sx * math.abs(sinR) + sz * math.abs(cosR)
			), origin + Vector3.new(cx + rx, oy, cz + rz), col, mat)
			return p
		end
		-- Main body
		place(14, 3, 6,   0,  2,  0, color, Enum.Material.Metal)
		-- Hood (lower, in front)
		place(5, 2, 6,    5,  1.5, 0, color, Enum.Material.Metal)
		-- Cabin / roof (raised, slightly back)
		place(8, 2.5, 5.6, -2,  4.7, 0, color, Enum.Material.Metal)
		-- Windows
		place(1.5, 1.8, 5.4, 2,  4.6, 0, carGlass, Enum.Material.Glass)
		place(1, 1.8, 5.4,  -6,  4.6, 0, carGlass, Enum.Material.Glass)
		place(7.8, 1.6, 0.4, -2, 4.8, 3, carGlass, Enum.Material.Glass)
		place(7.8, 1.6, 0.4, -2, 4.8, -3, carGlass, Enum.Material.Glass)
		-- Wheels (4)
		place(1, 2, 2, -5, 0.5, 3, wheelColor, Enum.Material.Plastic)
		place(1, 2, 2, -5, 0.5, -3, wheelColor, Enum.Material.Plastic)
		place(1, 2, 2, 5, 0.5, 3, wheelColor, Enum.Material.Plastic)
		place(1, 2, 2, 5, 0.5, -3, wheelColor, Enum.Material.Plastic)
	end

	-- Truck (outside long): bigger than car, signature green box truck
	local function truck(cx: number, cz: number)
		-- Cargo box (rear)
		makeBox(parent, Vector3.new(8, 7, 14), origin + Vector3.new(cx - 4, 4, cz),
			truckGreen, Enum.Material.Metal)
		-- Cab (front)
		makeBox(parent, Vector3.new(6, 5, 8), origin + Vector3.new(cx + 7, 3, cz),
			truckGreen, Enum.Material.Metal)
		-- Cab roof
		makeBox(parent, Vector3.new(6, 0.5, 8), origin + Vector3.new(cx + 7, 5.5, cz),
			truckGreen, Enum.Material.Metal)
		-- Windshield
		makeBox(parent, Vector3.new(0.5, 2.5, 7), origin + Vector3.new(cx + 10, 4, cz),
			carGlass, Enum.Material.Glass)
		-- Side windows
		makeBox(parent, Vector3.new(5.5, 2, 0.4), origin + Vector3.new(cx + 7, 4, cz + 4),
			carGlass, Enum.Material.Glass)
		makeBox(parent, Vector3.new(5.5, 2, 0.4), origin + Vector3.new(cx + 7, 4, cz - 4),
			carGlass, Enum.Material.Glass)
		-- Wheels (6)
		for _, wp in {
			Vector3.new(cx - 8, 0.7, cz + 4), Vector3.new(cx - 8, 0.7, cz - 4),
			Vector3.new(cx - 1, 0.7, cz + 4), Vector3.new(cx - 1, 0.7, cz - 4),
			Vector3.new(cx + 8, 0.7, cz + 4), Vector3.new(cx + 8, 0.7, cz - 4),
		} do
			makeBox(parent, Vector3.new(1.4, 2.5, 2.5), origin + wp, wheelColor, Enum.Material.Plastic)
		end
	end

	-- Palm tree — wooden trunk + radial green canopy (Dust2 spawn decor)
	local function palmTree(cx: number, cz: number)
		makeBox(parent, Vector3.new(1.6, 14, 1.6), origin + Vector3.new(cx, 7, cz),
			Color3.fromRGB(110, 80, 50), Enum.Material.Wood)
		local canopyColor = Color3.fromRGB(85, 130, 60)
		for i = 0, 5 do
			local theta = math.rad(i * 60)
			local f = makeBox(parent, Vector3.new(9, 0.4, 2.5),
				origin + Vector3.new(cx + math.cos(theta) * 3, 14.5, cz + math.sin(theta) * 3),
				canopyColor, Enum.Material.Grass)
			f.Orientation = Vector3.new(0, math.deg(theta), -15)
		end
	end

	-- ============================================================
	-- INTERIOR LANE WALLS — divides the map into the canonical Dust2 lanes
	-- ============================================================
	-- East wall of mid (also west wall of catwalk / short A approach).
	-- Runs from CT-side (z=-30) through entire mid up to T mid (z=+70).
	-- Gap left for catwalk drop-down to A short at z = -30..-15 (handled by
	-- breaking the wall into two segments).
	wall(Vector3.new(2, 26, 50), origin + Vector3.new(20, 13, -65)) -- A short divider (south of A site)
	wall(Vector3.new(2, 26, 100), origin + Vector3.new(20, 13, 20)) -- mid east wall (covers T side)

	-- West wall of mid (also east wall of B tunnels / CT short connector)
	wall(Vector3.new(2, 26, 100), origin + Vector3.new(-20, 13, 20)) -- mid west wall

	-- East perimeter of long A (creates "outside long" alley between this and the perimeter wall)
	wall(Vector3.new(2, 30, 180), origin + Vector3.new(120, 15, -10))

	-- West perimeter of B tunnels (separates tunnels from outer wrap)
	wall(Vector3.new(2, 30, 180), origin + Vector3.new(-120, 15, -10))

	-- North walls behind A site / B site (separates from CT spawn)
	wall(Vector3.new(110, 26, 2), origin + Vector3.new(-65, 13, -55))  -- B side north wall
	wall(Vector3.new(110, 26, 2), origin + Vector3.new(65, 13, -55))   -- A side north wall
	-- Gap in north wall at x=-20..+20 for CT short connection to mid

	-- ============================================================
	-- T SPAWN (south, z=+85..+135) — open courtyard with signature T arch
	-- ============================================================
	-- Tile floor
	makeBox(parent, Vector3.new(width - 10, 0.6, 50), origin + Vector3.new(0, 0.3, 110),
		tileColor, Enum.Material.Concrete)
	-- T arch (signature large gateway at south end of T mid)
	arch(origin + Vector3.new(0, 0, 80), 36, 22, 4, archColor)
	-- T spawn back wall
	wall(Vector3.new(width - 10, 22, 2), origin + Vector3.new(0, 11, 138), trimColor)
	-- Decorative side arches (west / east of T spawn)
	arch(origin + Vector3.new(-75, 0, 80), 16, 14, 3, archColor)
	arch(origin + Vector3.new( 75, 0, 80), 16, 14, 3, archColor)
	-- T spawn courtyard pillars
	makePillar(parent, origin.X - 140, origin.Z + 110, origin.Y, 24, 4, trimColor, Enum.Material.Sandstone)
	makePillar(parent, origin.X + 140, origin.Z + 110, origin.Y, 24, 4, trimColor, Enum.Material.Sandstone)
	-- Sandbag piles flanking T spawn exits
	makeBox(parent, Vector3.new(8, 3, 4), origin + Vector3.new(-60, 1.5, 90), crateColor, Enum.Material.Fabric)
	makeBox(parent, Vector3.new(8, 3, 4), origin + Vector3.new( 60, 1.5, 90), crateColor, Enum.Material.Fabric)
	-- T spawn signage box (decorative — like the "T side" graffiti wall)
	makeBox(parent, Vector3.new(40, 5, 0.4), origin + Vector3.new(0, 14, 137.5), tSpawnTint, Enum.Material.Neon)
	-- T SPAWN ENCLOSURE — 3-wall room (back wall at z=138 already exists) + front gate
	-- with single arch exit at z=80 (existing T arch). Forces ~3s walk before combat.
	wall(Vector3.new(2, 22, 50), origin + Vector3.new(-100, 11, 113), trimColor)  -- west side wall
	wall(Vector3.new(2, 22, 50), origin + Vector3.new( 100, 11, 113), trimColor)  -- east side wall
	-- Front gate walls flanking the T arch (gap at x=-20..+20 for arch passage)
	wall(Vector3.new(80, 16, 2), origin + Vector3.new(-60, 8, 88), trimColor)
	wall(Vector3.new(80, 16, 2), origin + Vector3.new( 60, 8, 88), trimColor)
	-- Decor: palm trees in T spawn corners
	palmTree(-90, 125)
	palmTree( 90, 125)

	-- ============================================================
	-- CT SPAWN (north, z=-95..-130) — paved area
	-- ============================================================
	makeBox(parent, Vector3.new(width - 10, 0.6, 40), origin + Vector3.new(0, 0.3, -113),
		tileColor, Enum.Material.Concrete)
	wall(Vector3.new(width - 10, 22, 2), origin + Vector3.new(0, 11, -134), trimColor)
	-- Sniper rocks (the elevated cover blocks where CT awpers hold)
	makeBox(parent, Vector3.new(10, 5, 10), origin + Vector3.new(-40, 2.5, -100), trimColor, Enum.Material.Slate)
	makeBox(parent, Vector3.new(10, 5, 10), origin + Vector3.new(  0, 2.5, -105), trimColor, Enum.Material.Slate)
	makeBox(parent, Vector3.new(10, 5, 10), origin + Vector3.new( 40, 2.5, -100), trimColor, Enum.Material.Slate)
	-- CT spawn corner pillars
	makePillar(parent, origin.X - 140, origin.Z - 105, origin.Y, 24, 4, trimColor, Enum.Material.Sandstone)
	makePillar(parent, origin.X + 140, origin.Z - 105, origin.Y, 24, 4, trimColor, Enum.Material.Sandstone)
	-- CT spawn signage
	makeBox(parent, Vector3.new(40, 5, 0.4), origin + Vector3.new(0, 14, -133.5), ctSpawnTint, Enum.Material.Neon)
	-- CT SPAWN ENCLOSURE — 3-wall room + single front arch exit
	wall(Vector3.new(2, 22, 40), origin + Vector3.new(-100, 11, -113), trimColor)
	wall(Vector3.new(2, 22, 40), origin + Vector3.new( 100, 11, -113), trimColor)
	-- Front gate walls (gap at x=-20..+20 for arch passage out to A short / mid / B doors)
	wall(Vector3.new(60, 16, 2), origin + Vector3.new(-65, 8, -95), trimColor)
	wall(Vector3.new(60, 16, 2), origin + Vector3.new( 65, 8, -95), trimColor)
	-- Front gate arch (single exit toward site area)
	arch(origin + Vector3.new(0, 0, -95), 22, 14, 3, archColor)
	-- CT spawn cars (signature) — 2 parked jeeps as cover/decor
	car(-50, -120, Color3.fromRGB(160, 140, 90))     -- tan jeep
	car( 50, -120, Color3.fromRGB(70, 95, 80), 180)  -- olive jeep
	-- Palm trees in CT spawn corners
	palmTree(-90, -125)
	palmTree( 90, -125)

	-- ============================================================
	-- MID corridor (x=-20..+20, z=-30..+80)
	-- Layout from south to north: T mid → mid doors arch → mid → X box → double doors → CT mid
	-- ============================================================
	makeBox(parent, Vector3.new(42, 0.4, 110), origin + Vector3.new(0, 0.2, 25),
		tileColor, Enum.Material.Concrete)

	-- Mid doors (T-side mid entry, arch only)
	arch(origin + Vector3.new(0, 0, 60), 22, 18, 3, archColor)

	-- X BOX — signature low wooden crate T uses to peek mid
	makeBox(parent, Vector3.new(8, 6, 8), origin + Vector3.new(0, 3, 35), crateColor, Enum.Material.WoodPlanks)
	makeBox(parent, Vector3.new(8.4, 0.4, 8.4), origin + Vector3.new(0, 6.2, 35), plankColor, Enum.Material.WoodPlanks)

	-- DOUBLE DOORS (CT side of mid) — two-leaf wooden doors flanked by walls
	wall(Vector3.new(2, 22, 18), origin + Vector3.new(13, 11, -20))
	wall(Vector3.new(2, 22, 18), origin + Vector3.new(-13, 11, -20))
	-- Door leafs
	makeBox(parent, Vector3.new(11, 14, 0.5), origin + Vector3.new(-6, 7, -20.5), doorWood, Enum.Material.WoodPlanks)
	makeBox(parent, Vector3.new(11, 14, 0.5), origin + Vector3.new( 6, 7, -20.5), doorWood, Enum.Material.WoodPlanks)
	-- Door arch keystone
	makeBox(parent, Vector3.new(28, 4, 4), origin + Vector3.new(0, 16, -20), archColor, Enum.Material.Sandstone)

	-- CT MID short wall (CT can hold this from CT spawn, peek mid)
	wall(Vector3.new(2, 14, 25), origin + Vector3.new(15, 7, -42))
	wall(Vector3.new(2, 14, 25), origin + Vector3.new(-15, 7, -42))

	-- ============================================================
	-- CATWALK (raised path from T mid east into A short) — signature
	-- Goes from z=+45 (T-mid entry) up + north to z=-30 (drops into A short)
	-- ============================================================
	-- Catwalk deck
	makeBox(parent, Vector3.new(8, 1, 75), origin + Vector3.new(32, 8, 7), catwalkGrey, Enum.Material.DiamondPlate)
	-- Railing (mid-facing side, so T can peek but not fall)
	makeBox(parent, Vector3.new(0.4, 4, 75), origin + Vector3.new(28, 10, 7), catwalkGrey, Enum.Material.Metal)
	-- Catwalk support pillars
	makeBox(parent, Vector3.new(1, 8, 1), origin + Vector3.new(30, 4, -25), catwalkGrey, Enum.Material.Metal)
	makeBox(parent, Vector3.new(1, 8, 1), origin + Vector3.new(30, 4, 0), catwalkGrey, Enum.Material.Metal)
	makeBox(parent, Vector3.new(1, 8, 1), origin + Vector3.new(30, 4, 40), catwalkGrey, Enum.Material.Metal)
	-- Stairs up from T mid (south end of catwalk)
	makeStairs(parent, origin + Vector3.new(25, 0, 45), 8, 1.0, 1.0, 6, catwalkGrey, Enum.Material.DiamondPlate)
	-- Stairs down to A short (north end of catwalk)
	makeStairs(parent, origin + Vector3.new(40, 0, -35), 8, 1.0, 1.0, 6, catwalkGrey, Enum.Material.DiamondPlate)
	-- Short A connector (between catwalk drop and A site north)
	makeBox(parent, Vector3.new(30, 0.4, 18), origin + Vector3.new(40, 0.2, -45),
		tileColor, Enum.Material.Concrete)

	-- ============================================================
	-- LONG A (east, x=+25..+120, z=-50..+75) — major rotational lane
	-- Sub-features: long doors, pit, plat (Tetris), blue box, mini, X box
	-- ============================================================
	-- Long doors entry (T side, two-arch entrance)
	arch(origin + Vector3.new(75, 0, 70), 16, 18, 4, archColor)
	-- Inner wall separating long from outside long (T can choose to push outside)
	-- (handled by the long east wall already; outside long sits in the gap between long-east-wall and perimeter)

	-- Long A floor accent (warm sand contrast)
	makeBox(parent, Vector3.new(85, 0.3, 120), origin + Vector3.new(72, 0.15, 5),
		Color3.fromRGB(215, 180, 120), Enum.Material.Sand)

	-- PIT (sunken defender hold spot on the west side of long, near long doors)
	-- Recessed floor (1.5 below surface)
	makeBox(parent, Vector3.new(16, 3, 14), origin + Vector3.new(40, -1.5, 30), trimColor, Enum.Material.Sandstone)
	-- Pit retaining walls (low enough to peek over)
	makeBox(parent, Vector3.new(16, 2.4, 0.6), origin + Vector3.new(40, 1.2, 23), trimColor, Enum.Material.Sandstone)
	makeBox(parent, Vector3.new(16, 2.4, 0.6), origin + Vector3.new(40, 1.2, 37), trimColor, Enum.Material.Sandstone)
	makeBox(parent, Vector3.new(0.6, 2.4, 14), origin + Vector3.new(32, 1.2, 30), trimColor, Enum.Material.Sandstone)
	-- Small box inside pit (the "pit box")
	makeBox(parent, Vector3.new(3, 2, 3), origin + Vector3.new(40, 0, 30), crateColor, Enum.Material.WoodPlanks)

	-- PLAT / TETRIS (the stacked wooden boxes on the east side of long, near long doors)
	crateStack(95, 50, 0, 2, 6) -- 2 stacked 6x6 boxes
	crateStack(95, 56, 0, 1, 6) -- ground-level box behind
	crateStack(100, 45, 0, 1, 5) -- extra side box

	-- BLUE BOX (mid-long: cover that splits long into two firing angles)
	makeBox(parent, Vector3.new(5, 5, 5), origin + Vector3.new(95, 2.5, 15), blueBarrel, Enum.Material.WoodPlanks)
	makeBox(parent, Vector3.new(4.5, 0.4, 4.5), origin + Vector3.new(95, 5.2, 15), Color3.fromRGB(100, 140, 195), Enum.Material.WoodPlanks)

	-- MINI / SIDE BOX (small cover halfway down long)
	makeBox(parent, Vector3.new(5, 3, 5), origin + Vector3.new(50, 1.5, 10), crateColor, Enum.Material.WoodPlanks)
	-- Long sandbag pile (T side cover near long doors)
	makeBox(parent, Vector3.new(8, 2.5, 4), origin + Vector3.new(60, 1.25, 55), crateColor, Enum.Material.Fabric)
	makeBox(parent, Vector3.new(4, 2, 8), origin + Vector3.new(95, 1, 60), crateColor, Enum.Material.Fabric)

	-- ============================================================
	-- A SITE (NE, x=+25..+115, z=-95..-50) — open plaza
	-- Features: red car, goose, ramp to A (from short), ninja corner box, default X
	-- ============================================================
	-- Site marker (subtle neon ground accent)
	local siteAGround = makeBox(parent, Vector3.new(60, 0.3, 42),
		origin + Vector3.new(70, 0.15, -75), siteAColor, Enum.Material.Neon)
	siteAGround.Transparency = 0.85
	-- Yellow danger-stripe border around bombsite
	makeBox(parent, Vector3.new(64, 0.4, 1), origin + Vector3.new(70, 0.2, -54), yellowAccent, Enum.Material.Neon)
	makeBox(parent, Vector3.new(64, 0.4, 1), origin + Vector3.new(70, 0.2, -96), yellowAccent, Enum.Material.Neon)
	makeBox(parent, Vector3.new(1, 0.4, 42), origin + Vector3.new(38, 0.2, -75), yellowAccent, Enum.Material.Neon)
	makeBox(parent, Vector3.new(1, 0.4, 42), origin + Vector3.new(102, 0.2, -75), yellowAccent, Enum.Material.Neon)
	-- "A" marker pillar
	makeBox(parent, Vector3.new(2, 16, 2), origin + Vector3.new(108, 8, -94), yellowAccent, Enum.Material.Neon)

	-- RED CAR (the iconic A site car) — sits in the middle-south of A site, providing
	-- cover for default plant
	car(70, -68, carRed)

	-- GOOSE (the wooden crate stack at the long-side of A, used for default plant peeks)
	crateStack(95, -65, 0, 2, 6)
	makeBox(parent, Vector3.new(5, 0.4, 5), origin + Vector3.new(98, 6.2, -67), plankColor, Enum.Material.WoodPlanks)

	-- DEFAULT BOX / X BOX (a single low crate near default plant position behind car)
	makeBox(parent, Vector3.new(4, 3, 4), origin + Vector3.new(75, 1.5, -80), crateColor, Enum.Material.WoodPlanks)

	-- NINJA BOX (corner box near short A side — defender hides here)
	makeBox(parent, Vector3.new(5, 5, 5), origin + Vector3.new(42, 2.5, -57), crateColor, Enum.Material.WoodPlanks)

	-- RAMP up to A site from short A side (small elevation)
	makeStairs(parent, origin + Vector3.new(45, 0, -55), 5, 0.8, 1.2, 12, trimColor, Enum.Material.Sandstone)

	-- "PIT" / lower area on A site near car (CT defenders can hold from here)
	makeBox(parent, Vector3.new(8, 0.6, 8), origin + Vector3.new(55, 0.3, -78), trimColor, Enum.Material.Sandstone)

	-- A site back wall
	wall(Vector3.new(95, 24, 2), origin + Vector3.new(67, 12, -103))

	-- ============================================================
	-- OUTSIDE LONG (east, x=+120..+148, z=-50..+90) — narrow T-side alley with truck
	-- ============================================================
	-- Floor accent (slightly different)
	makeBox(parent, Vector3.new(26, 0.3, 140), origin + Vector3.new(134, 0.15, 20),
		Color3.fromRGB(200, 170, 110), Enum.Material.Sand)
	-- TRUCK (signature outside long cover)
	truck(135, 30)
	-- Sandbags near long doors (outside long T side)
	makeBox(parent, Vector3.new(4, 2.5, 8), origin + Vector3.new(133, 1.25, 60), crateColor, Enum.Material.Fabric)
	-- Wall blocking outside long from going further north (forces engagement with long)
	wall(Vector3.new(28, 22, 2), origin + Vector3.new(134, 11, -50))

	-- ============================================================
	-- B TUNNELS — lower (T-side) + upper (CT-side)
	-- T side entry from courtyard at z=+70, exits into B site at z=-50
	-- ============================================================
	-- Tunnel entry arch (T side)
	arch(origin + Vector3.new(-70, 0, 70), 18, 16, 4, archColor)
	-- Lower tunnel roof (covers the south half of tunnels)
	makeBox(parent, Vector3.new(70, 1, 50), origin + Vector3.new(-70, 16, 40),
		trimColor, Enum.Material.Sandstone)
	-- Upper tunnel roof (covers the north half — slightly higher to suggest "upper")
	makeBox(parent, Vector3.new(70, 1, 60), origin + Vector3.new(-70, 18, -10),
		trimColor, Enum.Material.Sandstone)
	-- "Upper" walkway (raised path along the inner side — CT can hold from up here)
	makeBox(parent, Vector3.new(12, 1, 50), origin + Vector3.new(-40, 8, -15),
		catwalkGrey, Enum.Material.DiamondPlate)
	-- Walkway support pillars
	makeBox(parent, Vector3.new(1, 8, 1), origin + Vector3.new(-40, 4, -38), catwalkGrey, Enum.Material.Metal)
	makeBox(parent, Vector3.new(1, 8, 1), origin + Vector3.new(-40, 4, 8), catwalkGrey, Enum.Material.Metal)
	-- Stairs UP to upper (T side, climbing as you go north)
	makeStairs(parent, origin + Vector3.new(-47, 0, 12), 8, 1.0, 1.0, 6, catwalkGrey, Enum.Material.DiamondPlate)
	-- Stairs DOWN from upper into B site (CT side)
	makeStairs(parent, origin + Vector3.new(-47, 0, -42), 8, 1.0, 1.0, 6, catwalkGrey, Enum.Material.DiamondPlate)
	-- Cover crates inside tunnels at choke points
	crateStack(-95, 50, 0, 1, 5)
	makeBox(parent, Vector3.new(8, 2.5, 4), origin + Vector3.new(-60, 1.25, 30), crateColor, Enum.Material.Fabric)
	crateStack(-95, 20, 0, 1, 5)
	makeBox(parent, Vector3.new(5, 2.5, 8), origin + Vector3.new(-50, 1.25, -10), crateColor, Enum.Material.Fabric)
	-- Tunnel exit arch into B site
	arch(origin + Vector3.new(-70, 0, -45), 18, 14, 3, archColor)
	-- Mid wall between lower and upper sections (CT defenders peek from upper)
	wall(Vector3.new(0.5, 6, 12), origin + Vector3.new(-46, 11, -15), catwalkGrey)

	-- ============================================================
	-- B SITE (NW, x=-115..-25, z=-95..-50) — signature plat + new box
	-- ============================================================
	-- Site marker
	local siteBGround = makeBox(parent, Vector3.new(60, 0.3, 42),
		origin + Vector3.new(-70, 0.15, -75), siteBColor, Enum.Material.Neon)
	siteBGround.Transparency = 0.85
	-- Yellow border
	makeBox(parent, Vector3.new(64, 0.4, 1), origin + Vector3.new(-70, 0.2, -54), yellowAccent, Enum.Material.Neon)
	makeBox(parent, Vector3.new(64, 0.4, 1), origin + Vector3.new(-70, 0.2, -96), yellowAccent, Enum.Material.Neon)
	makeBox(parent, Vector3.new(1, 0.4, 42), origin + Vector3.new(-38, 0.2, -75), yellowAccent, Enum.Material.Neon)
	makeBox(parent, Vector3.new(1, 0.4, 42), origin + Vector3.new(-102, 0.2, -75), yellowAccent, Enum.Material.Neon)
	-- "B" marker pillar
	makeBox(parent, Vector3.new(2, 16, 2), origin + Vector3.new(-108, 8, -94), yellowAccent, Enum.Material.Neon)

	-- PLAT (signature B site default plant — raised wooden platform between tunnels exit and back wall)
	makeBox(parent, Vector3.new(16, 4, 14), origin + Vector3.new(-80, 2, -75), crateColor, Enum.Material.WoodPlanks)
	makeBox(parent, Vector3.new(16.4, 0.5, 14.4), origin + Vector3.new(-80, 4.25, -75), plankColor, Enum.Material.WoodPlanks)
	-- BACK PLAT (smaller crate stack behind main plat, near back wall)
	makeBox(parent, Vector3.new(8, 6, 6), origin + Vector3.new(-98, 3, -90), crateColor, Enum.Material.WoodPlanks)
	-- NEW BOX (cover at tunnel exit side — defender peeks from here)
	makeBox(parent, Vector3.new(5, 5, 5), origin + Vector3.new(-50, 2.5, -68), crateColor, Enum.Material.WoodPlanks)
	-- Back-of-site cover (low wall behind plat for retake angle)
	makeBox(parent, Vector3.new(20, 3, 1), origin + Vector3.new(-80, 1.5, -100), trimColor, Enum.Material.Sandstone)
	-- Blue barrels (decoration matching B site signature theme)
	makeBox(parent, Vector3.new(2, 4, 2), origin + Vector3.new(-45, 2, -90), blueBarrel, Enum.Material.Metal)
	makeBox(parent, Vector3.new(2, 4, 2), origin + Vector3.new(-42, 2, -88), blueBarrel, Enum.Material.Metal)
	makeBox(parent, Vector3.new(2, 4, 2), origin + Vector3.new(-44, 2, -85), blueBarrel, Enum.Material.Metal)

	-- B DOORS (CT-side entrance into B site from CT spawn area)
	arch(origin + Vector3.new(-40, 0, -55), 14, 14, 3, archColor)
	-- B doors decorative wood double-door (similar to mid double doors)
	makeBox(parent, Vector3.new(6, 12, 0.5), origin + Vector3.new(-43, 6, -55.5), doorWood, Enum.Material.WoodPlanks)
	makeBox(parent, Vector3.new(6, 12, 0.5), origin + Vector3.new(-37, 6, -55.5), doorWood, Enum.Material.WoodPlanks)

	-- B site back wall
	wall(Vector3.new(95, 24, 2), origin + Vector3.new(-67, 12, -103))

	-- ============================================================
	-- A SHORT / CT short connector — between CT spawn and A site
	-- ============================================================
	-- Short A floor
	makeBox(parent, Vector3.new(30, 0.4, 25), origin + Vector3.new(40, 0.2, -75),
		tileColor, Enum.Material.Concrete)
	-- Wall separating short A from mid (CT defenders peek out from short)
	wall(Vector3.new(2, 22, 30), origin + Vector3.new(25, 11, -75))

	-- ============================================================
	-- EXTRA COVER — sprinkled crates / sandbags throughout lanes
	-- ============================================================
	-- Mid lane extra cover
	crateStack(-8, 50, 0, 1, 4)
	crateStack( 8, 12, 0, 2, 4)
	-- Long A extra (pit area + long mid)
	crateStack(50, -10, 0, 1, 5)
	crateStack(85, -20, 0, 1, 4)
	makeBox(parent, Vector3.new(6, 2.5, 3), origin + Vector3.new(75, 1.25, -5), crateColor, Enum.Material.Fabric)
	-- B tunnels extra cover
	crateStack(-50, -25, 0, 1, 4)
	crateStack(-90, -5, 0, 1, 5)
	makeBox(parent, Vector3.new(5, 2.5, 6), origin + Vector3.new(-75, 1.25, -30), crateColor, Enum.Material.Fabric)
	-- A site extra (near ninja box area)
	makeBox(parent, Vector3.new(4, 3, 4), origin + Vector3.new(95, 1.5, -50), crateColor, Enum.Material.WoodPlanks)
	-- B site extra
	crateStack(-45, -80, 0, 1, 4)
	-- Long doors extra (T side, behind sandbag)
	makeBox(parent, Vector3.new(5, 3, 5), origin + Vector3.new(70, 1.5, 50), crateColor, Enum.Material.WoodPlanks)

	-- ============================================================
	-- SPAWNS — 5 T + 5 CT (Team attribute, used by CasualService)
	-- ============================================================
	local spawns = spawnsFolder(parent)

	local tSpawnPositions = {
		Vector3.new(-30, 3, 128),
		Vector3.new(-10, 3, 128),
		Vector3.new(  0, 3, 133),
		Vector3.new( 10, 3, 128),
		Vector3.new( 30, 3, 128),
	}
	for _, p in tSpawnPositions do
		local sp = makeSpawn(spawns, origin + p, tSpawnTint)
		sp:SetAttribute("Team", "T")
	end

	local ctSpawnPositions = {
		Vector3.new(-30, 3, -123),
		Vector3.new(-10, 3, -123),
		Vector3.new(  0, 3, -128),
		Vector3.new( 10, 3, -123),
		Vector3.new( 30, 3, -123),
	}
	for _, p in ctSpawnPositions do
		local sp = makeSpawn(spawns, origin + p, ctSpawnTint)
		sp:SetAttribute("Team", "CT")
	end

	-- ============================================================
	-- BOMB SITES — plant volumes (CasualService reads BombSite attribute)
	-- ============================================================
	local sitesFolder = Instance.new("Folder")
	sitesFolder.Name = "BombSites"
	sitesFolder.Parent = parent

	local siteAVolume = makePart(sitesFolder, {
		Name = "SiteA",
		Size = Vector3.new(50, 14, 38),
		Position = origin + Vector3.new(70, 7, -75),
		Color = siteAColor,
		Material = Enum.Material.Neon,
		Transparency = 0.92,
		CanCollide = false,
	})
	siteAVolume:SetAttribute("BombSite", "A")

	local siteBVolume = makePart(sitesFolder, {
		Name = "SiteB",
		Size = Vector3.new(50, 14, 38),
		Position = origin + Vector3.new(-70, 7, -75),
		Color = siteBColor,
		Material = Enum.Material.Neon,
		Transparency = 0.92,
		CanCollide = false,
	})
	siteBVolume:SetAttribute("BombSite", "B")
end

return MapBuilders
