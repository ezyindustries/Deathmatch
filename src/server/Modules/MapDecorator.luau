--!strict
-- MapDecorator — procedural set-dressing helpers called by MapBuilders to
-- make each arena look "lived in" instead of bare boxes. All helpers are
-- deterministic-by-seed (caller passes a Random instance) so the same map
-- layout produces the same prop placement across servers — important for
-- consistent gameplay (players learn cover positions, etc.).
--
-- Conventions:
--   • All props parented to the map folder so ArenaService teardown wipes them
--     atomically with the rest of the map.
--   • CanCollide = true for cover-shaped props (barrels, crates, drums) so
--     players can hide behind them. CanCollide = false for purely decorative
--     bits (cables, neon strips, pipes overhead).
--   • Materials picked for visual contrast with concrete/brick floor surfaces.
--   • Massless = true on welded-style decorations to avoid affecting physics.
--
-- Themes:
--   "industrial" → rusty metal palette (warehouse, harbor, metro)
--   "desert"     → dusty sand-blasted palette (dust2, desert)
--   "urban"      → cleaner grey concrete + AC units (rooftop)

local MapDecorator = {}

export type Theme = "industrial" | "desert" | "urban"

type Palette = {
	barrelBody: Color3,
	barrelCap: Color3,
	barrelAccent: Color3,
	crateWood: Color3,
	crateBand: Color3,
	pipeBody: Color3,
	pipeJoint: Color3,
	neonAccent: Color3,
	signMetal: Color3,
}

local PALETTES: { [Theme]: Palette } = {
	industrial = {
		barrelBody = Color3.fromRGB(80, 60, 40),    -- rust
		barrelCap = Color3.fromRGB(50, 35, 20),
		barrelAccent = Color3.fromRGB(180, 50, 40), -- red ring/label
		crateWood = Color3.fromRGB(115, 80, 45),
		crateBand = Color3.fromRGB(60, 45, 25),
		pipeBody = Color3.fromRGB(95, 100, 110),    -- gunmetal
		pipeJoint = Color3.fromRGB(55, 60, 70),
		neonAccent = Color3.fromRGB(255, 180, 60),  -- amber warning
		signMetal = Color3.fromRGB(70, 75, 85),
	},
	desert = {
		barrelBody = Color3.fromRGB(160, 120, 70),  -- weathered sand
		barrelCap = Color3.fromRGB(100, 75, 45),
		barrelAccent = Color3.fromRGB(200, 120, 40),
		crateWood = Color3.fromRGB(190, 155, 100),
		crateBand = Color3.fromRGB(120, 90, 50),
		pipeBody = Color3.fromRGB(140, 120, 90),
		pipeJoint = Color3.fromRGB(80, 65, 45),
		neonAccent = Color3.fromRGB(255, 220, 80),
		signMetal = Color3.fromRGB(110, 95, 65),
	},
	urban = {
		barrelBody = Color3.fromRGB(70, 75, 80),
		barrelCap = Color3.fromRGB(40, 45, 50),
		barrelAccent = Color3.fromRGB(60, 160, 200), -- electric blue
		crateWood = Color3.fromRGB(90, 70, 50),
		crateBand = Color3.fromRGB(50, 40, 30),
		pipeBody = Color3.fromRGB(140, 145, 150),
		pipeJoint = Color3.fromRGB(80, 85, 90),
		neonAccent = Color3.fromRGB(80, 200, 255),  -- cyan
		signMetal = Color3.fromRGB(60, 65, 75),
	},
}

local function mkPart(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- =============================================================
-- OIL DRUM — tall thin cylinder, cover-shaped (CanCollide on)
-- =============================================================
function MapDecorator.MakeDrum(parent: Instance, position: Vector3, theme: Theme)
	local pal = PALETTES[theme] or PALETTES.industrial
	-- Body
	mkPart(parent, {
		Name = "Drum",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.5, 2.2, 2.2), -- length×Yd×Zd, rotated below
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = pal.barrelBody,
		Material = Enum.Material.Metal,
	})
	-- Top cap (slightly larger disc)
	mkPart(parent, {
		Name = "DrumCap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 2.3, 2.3),
		CFrame = CFrame.new(position.X, position.Y + 1.75, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = pal.barrelCap,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	-- Hazard ring (top accent stripe)
	mkPart(parent, {
		Name = "DrumRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 2.25, 2.25),
		CFrame = CFrame.new(position.X, position.Y + 1.2, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = pal.barrelAccent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
end

-- =============================================================
-- WOODEN CRATE — stackable cover box
-- =============================================================
function MapDecorator.MakeCrate(parent: Instance, position: Vector3, size: number?, theme: Theme)
	local s = size or 4
	local pal = PALETTES[theme] or PALETTES.industrial
	mkPart(parent, {
		Name = "Crate",
		Size = Vector3.new(s, s, s),
		CFrame = CFrame.new(position),
		Color = pal.crateWood,
		Material = Enum.Material.WoodPlanks,
	})
	-- Reinforcement bands (4 thin strips around middle)
	local bandY = position.Y
	mkPart(parent, {
		Name = "CrateBandH",
		Size = Vector3.new(s + 0.05, 0.18, s + 0.05),
		CFrame = CFrame.new(position.X, bandY, position.Z),
		Color = pal.crateBand,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	mkPart(parent, {
		Name = "CrateBandV",
		Size = Vector3.new(0.18, s + 0.05, s + 0.05),
		CFrame = CFrame.new(position.X, bandY, position.Z),
		Color = pal.crateBand,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
end

-- =============================================================
-- CEILING LIGHT FIXTURE — neon panel + downward PointLight
-- For interior maps (warehouse, metro). Position = light's top mount point;
-- panel hangs `height` below.
-- =============================================================
function MapDecorator.MakeCeilingLight(parent: Instance, mountPos: Vector3, theme: Theme, height: number?)
	local pal = PALETTES[theme] or PALETTES.industrial
	local panel = mkPart(parent, {
		Name = "LightPanel",
		Size = Vector3.new(4, 0.3, 1.5),
		CFrame = CFrame.new(mountPos.X, mountPos.Y - (height or 0.2), mountPos.Z),
		Color = Color3.fromRGB(255, 240, 200),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 210)
	light.Brightness = 2.4
	light.Range = 24
	light.Shadows = false
	light.Parent = panel
	-- Frame (darker rim so it reads as a fixture not a glowing block)
	mkPart(parent, {
		Name = "LightFrame",
		Size = Vector3.new(4.2, 0.45, 1.7),
		CFrame = CFrame.new(mountPos.X, mountPos.Y - (height or 0.2), mountPos.Z),
		Color = pal.pipeJoint,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Transparency = 0.05,
	})
end

-- =============================================================
-- WALL PIPE — horizontal pipe segment + 2 joint flanges
-- startPos & endPos at WALL surface; the pipe is offset perpendicular slightly.
-- =============================================================
function MapDecorator.MakeWallPipe(parent: Instance, startPos: Vector3, endPos: Vector3, theme: Theme)
	local pal = PALETTES[theme] or PALETTES.industrial
	local delta = endPos - startPos
	local length = delta.Magnitude
	local mid = (startPos + endPos) * 0.5
	mkPart(parent, {
		Name = "Pipe",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, 0.6, 0.6),
		CFrame = CFrame.lookAt(mid, endPos) * CFrame.Angles(0, math.rad(90), math.rad(90)),
		Color = pal.pipeBody,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	-- Joint flanges at both ends
	for _, p in { startPos, endPos } do
		mkPart(parent, {
			Name = "PipeJoint",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 0.85, 0.85),
			CFrame = CFrame.lookAt(p, endPos) * CFrame.Angles(0, math.rad(90), math.rad(90)),
			Color = pal.pipeJoint,
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end
end

-- =============================================================
-- NEON ACCENT STRIP — thin glowing line along a wall edge.
-- Visual punch with zero gameplay impact (Massless + non-collidable).
-- =============================================================
function MapDecorator.MakeNeonStrip(parent: Instance, startPos: Vector3, endPos: Vector3, theme: Theme, colorOverride: Color3?)
	local pal = PALETTES[theme] or PALETTES.industrial
	local delta = endPos - startPos
	local length = delta.Magnitude
	local mid = (startPos + endPos) * 0.5
	local strip = mkPart(parent, {
		Name = "NeonStrip",
		Size = Vector3.new(length, 0.25, 0.25),
		CFrame = CFrame.lookAt(mid, endPos) * CFrame.Angles(0, math.rad(90), 0),
		Color = colorOverride or pal.neonAccent,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	-- Subtle PointLight at midpoint for ambient color bleed onto nearby surfaces
	local light = Instance.new("PointLight")
	light.Color = colorOverride or pal.neonAccent
	light.Brightness = 1.0
	light.Range = 8
	light.Shadows = false
	light.Parent = strip
end

-- =============================================================
-- ARENA EDGE NEON — adds 4 strips along the perimeter top edge.
-- Gives the arena a futuristic "stage" border. Pass map's perimeter size.
-- =============================================================
function MapDecorator.MakeArenaEdgeNeon(parent: Instance, origin: Vector3, width: number, depth: number, topY: number, theme: Theme, colorOverride: Color3?)
	local hw, hd = width / 2, depth / 2
	local y = origin.Y + topY
	-- North/South strips along X
	MapDecorator.MakeNeonStrip(parent, origin + Vector3.new(-hw, topY, -hd), origin + Vector3.new(hw, topY, -hd), theme, colorOverride)
	MapDecorator.MakeNeonStrip(parent, origin + Vector3.new(-hw, topY, hd), origin + Vector3.new(hw, topY, hd), theme, colorOverride)
	-- East/West strips along Z (rotated 90°)
	for _, x in { -hw, hw } do
		local startP = origin + Vector3.new(x, topY, -hd)
		local endP = origin + Vector3.new(x, topY, hd)
		local delta = endP - startP
		local length = delta.Magnitude
		local mid = (startP + endP) * 0.5
		local strip = mkPart(parent, {
			Name = "NeonStrip",
			Size = Vector3.new(length, 0.25, 0.25),
			CFrame = CFrame.new(mid) * CFrame.Angles(0, math.rad(90), 0),
			Color = colorOverride or PALETTES[theme].neonAccent,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		local lt = Instance.new("PointLight")
		lt.Color = colorOverride or PALETTES[theme].neonAccent
		lt.Brightness = 0.8
		lt.Range = 10
		lt.Shadows = false
		lt.Parent = strip
	end
	-- Suppress "unused" warning for y
	local _ = y
end

-- =============================================================
-- SCATTER — random placement of mixed props within a rectangular area.
-- Avoids spawn points by minDistance check against passed `avoidPoints`.
-- =============================================================
function MapDecorator.ScatterProps(
	parent: Instance,
	origin: Vector3,
	areaWidth: number,
	areaDepth: number,
	count: number,
	theme: Theme,
	avoidPoints: { Vector3 }?,
	seed: number?
)
	local rng = Random.new(seed or 12345)
	local hw, hd = areaWidth / 2, areaDepth / 2
	local placedPositions: { Vector3 } = {}
	local minSpacing = 5
	local minToAvoid = 12
	local attempts = 0
	local maxAttempts = count * 8

	while #placedPositions < count and attempts < maxAttempts do
		attempts += 1
		local x = origin.X + rng:NextNumber(-hw, hw)
		local z = origin.Z + rng:NextNumber(-hd, hd)
		local pos = Vector3.new(x, origin.Y, z)
		-- Reject too-close-to-spawn or too-close-to-other-prop
		local tooClose = false
		if avoidPoints then
			for _, avoid in avoidPoints do
				if (Vector3.new(pos.X, avoid.Y, pos.Z) - avoid).Magnitude < minToAvoid then
					tooClose = true; break
				end
			end
		end
		if not tooClose then
			for _, prior in placedPositions do
				if (pos - prior).Magnitude < minSpacing then
					tooClose = true; break
				end
			end
		end
		if tooClose then continue end
		table.insert(placedPositions, pos)
		-- Pick prop type: 40% drum, 35% crate, 25% larger crate
		local roll = rng:NextNumber()
		if roll < 0.4 then
			MapDecorator.MakeDrum(parent, pos + Vector3.new(0, 1.1, 0), theme)
		elseif roll < 0.75 then
			MapDecorator.MakeCrate(parent, pos + Vector3.new(0, 2, 0), 4, theme)
		else
			MapDecorator.MakeCrate(parent, pos + Vector3.new(0, 2.5, 0), 5, theme)
		end
	end
end

-- =============================================================
-- GET SPAWN POSITIONS — convenience for callers building the avoid list.
-- =============================================================
function MapDecorator.GetSpawnPositions(spawnsFolder: Instance?): { Vector3 }
	local positions: { Vector3 } = {}
	if not spawnsFolder then return positions end
	for _, c in spawnsFolder:GetChildren() do
		if c:IsA("BasePart") then
			table.insert(positions, c.Position)
		end
	end
	return positions
end

return MapDecorator
