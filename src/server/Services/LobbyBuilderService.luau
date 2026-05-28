--!strict
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LobbyBuilder = {}

local MAP_SIZE = 140
local WALL_HEIGHT = 24
local FLOOR_LIFT = 3 -- naikkan seluruh lobby supaya lantai gak terlalu mepet

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = Workspace
	return p
end

local function buildBaseplate()
	makePart({
		Name = "Baseplate",
		Size = Vector3.new(MAP_SIZE, 4, MAP_SIZE),
		Position = Vector3.new(0, -2 + FLOOR_LIFT, 0),
		Color = Color3.fromRGB(45, 50, 60),
		Material = Enum.Material.SmoothPlastic,
	})
end

local function buildWalls()
	local thickness = 2
	local halfMap = MAP_SIZE / 2

	local wallY = WALL_HEIGHT / 2 + FLOOR_LIFT
	local layouts = {
		{ Vector3.new(MAP_SIZE, WALL_HEIGHT, thickness), Vector3.new(0, wallY, halfMap) },
		{ Vector3.new(MAP_SIZE, WALL_HEIGHT, thickness), Vector3.new(0, wallY, -halfMap) },
		{ Vector3.new(thickness, WALL_HEIGHT, MAP_SIZE), Vector3.new(halfMap, wallY, 0) },
		{ Vector3.new(thickness, WALL_HEIGHT, MAP_SIZE), Vector3.new(-halfMap, wallY, 0) },
	}

	for i, layout in layouts do
		makePart({
			Name = "Wall_" .. i,
			Size = layout[1],
			Position = layout[2],
			Color = Color3.fromRGB(70, 75, 90),
			Material = Enum.Material.Concrete,
		})
	end
end

local function buildCenterPlatform()
	makePart({
		Name = "CenterPlatform",
		Size = Vector3.new(34, 2, 34),
		Position = Vector3.new(0, 1 + FLOOR_LIFT, 0),
		Color = Color3.fromRGB(95, 105, 130),
		Material = Enum.Material.Metal,
	})

	makePart({
		Name = "CenterPodium",
		Size = Vector3.new(10, 4, 10),
		Position = Vector3.new(0, 4 + FLOOR_LIFT, 0),
		Color = Color3.fromRGB(120, 140, 180),
		Material = Enum.Material.Neon,
	})
end

local function buildSpawnPoints()
	local folder = Instance.new("Folder")
	folder.Name = "LobbySpawns"
	folder.Parent = Workspace

	local radius = 38
	local count = 6
	local spawnColor = Color3.fromRGB(80, 200, 120)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local px = math.cos(angle) * radius
		local pz = math.sin(angle) * radius
		local spawnY = 2.5 + FLOOR_LIFT
		local floorY = FLOOR_LIFT -- lobby floor level (top of baseplate)

		-- Invisible positional marker — visual replaced by beam + disc below.
		local sp = Instance.new("SpawnLocation")
		sp.Name = "Spawn_" .. i
		sp.Anchored = true
		sp.Size = Vector3.new(4, 1, 4)
		sp.Position = Vector3.new(px, spawnY, pz)
		sp.Transparency = 1
		sp.CanCollide = false
		sp.TopSurface = Enum.SurfaceType.Smooth
		sp.BottomSurface = Enum.SurfaceType.Smooth
		sp.Neutral = true
		sp.AllowTeamChangeOnTouch = false
		sp.Duration = 0
		sp.Parent = folder

		-- Vertical light pillar from the floor (matches makeSpawn in MapBuilders).
		local BEAM_HEIGHT = 15
		local BEAM_DIAMETER = 2.8
		local beam = Instance.new("Part")
		beam.Name = "SpawnBeam"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CastShadow = false
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(BEAM_HEIGHT, BEAM_DIAMETER, BEAM_DIAMETER)
		beam.CFrame = CFrame.new(px, floorY + BEAM_HEIGHT / 2, pz) * CFrame.Angles(0, 0, math.rad(90))
		beam.Color = spawnColor
		beam.Material = Enum.Material.Neon
		beam.Transparency = 0.5
		beam.TopSurface = Enum.SurfaceType.Smooth
		beam.BottomSurface = Enum.SurfaceType.Smooth
		beam.Parent = folder

		local light = Instance.new("PointLight")
		light.Color = spawnColor
		light.Brightness = 1.6
		light.Range = 14
		light.Shadows = false
		light.Parent = beam

		-- Floor disc — landing-pad accent at the beam's base.
		local disc = Instance.new("Part")
		disc.Name = "SpawnDisc"
		disc.Anchored = true
		disc.CanCollide = false
		disc.CastShadow = false
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.2, 6, 6)
		disc.CFrame = CFrame.new(px, floorY + 0.1, pz) * CFrame.Angles(0, 0, math.rad(90))
		disc.Color = spawnColor
		disc.Material = Enum.Material.Neon
		disc.Transparency = 0.2
		disc.Parent = folder
	end
end

local function buildSafeZoneDecals()
	for x = -50, 50, 25 do
		for z = -50, 50, 25 do
			if math.abs(x) > 18 or math.abs(z) > 18 then
				makePart({
					Name = "FloorAccent",
					Size = Vector3.new(8, 0.1, 8),
					Position = Vector3.new(x, 0.05 + FLOOR_LIFT, z),
					Color = Color3.fromRGB(60, 70, 85),
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
				})
			end
		end
	end
end

local function setupLighting()
	Lighting.Ambient = Color3.fromRGB(70, 75, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(100, 105, 125)
	Lighting.Brightness = 2.2
	Lighting.ClockTime = 14
	Lighting.FogColor = Color3.fromRGB(160, 165, 180)
	Lighting.FogStart = 120
	Lighting.FogEnd = 350
	Lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
end

function LobbyBuilder.Build()
	buildBaseplate()
	buildWalls()
	buildCenterPlatform()
	buildSpawnPoints()
	buildSafeZoneDecals()
	setupLighting()
	print("[Lobby] Scene built.")
end

LobbyBuilder.Build()

return LobbyBuilder
