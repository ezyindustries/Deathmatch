--!strict
export type Tier = "Common" | "Rare" | "Epic" | "Legendary" | "Contraband"
export type Slot = "primary" | "secondary" | "melee"
export type PartRole = "body" | "slide" | "mag" | "barrel" | "stock" | "grip" | "sight"

export type ViewmodelPart = {
	role: PartRole,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
}

export type ViewmodelConfig = {
	grip: CFrame,
	parts: { ViewmodelPart },
}

export type WeaponInfo = {
	id: string,
	displayName: string,
	tier: Tier,
	slot: Slot,
	damage: number,
	fireRate: number,
	range: number,
	magSize: number,
	reloadTime: number,
	drawTime: number,
	headshotMultiplier: number,
	falloffStart: number,
	falloffEnd: number,
	minDamageMul: number,
	recoilVertical: number,
	recoilHorizontal: number,
	recoilRecoverSpeed: number,
	isAuto: boolean,
	viewmodel: ViewmodelConfig,
}

local function rad(deg: number): number
	return math.rad(deg)
end

local WeaponConfig: { [string]: WeaponInfo } = {
	pistol = {
		id = "pistol",
		displayName = "Glock-18",
		tier = "Common",
		slot = "secondary",
		damage = 22,
		fireRate = 4,
		range = 250,
		magSize = 17,
		reloadTime = 1.4,
		drawTime = 0.7,
		headshotMultiplier = 1.7,
		falloffStart = 40,
		falloffEnd = 120,
		minDamageMul = 0.55,
		recoilVertical = 0.7,
		recoilHorizontal = 0.2,
		recoilRecoverSpeed = 6,
		isAuto = false,
		viewmodel = {
			grip = CFrame.new(0.6, -0.55, -1.4) * CFrame.Angles(0, rad(-4), 0),
			parts = (function(): { ViewmodelPart }
				local parts: { ViewmodelPart } = {}
				local function add(p: any) table.insert(parts, p) end

				-- ============================================================
				-- POLYMER FRAME (Gen 4 Glock style — stippling + finger grooves)
				-- ============================================================
				-- Main frame body
				add({ role = "body", size = Vector3.new(0.22, 0.16, 0.78), offset = CFrame.new(0, 0.06, 0), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Dust cover (front part of frame, under barrel)
				add({ role = "body", size = Vector3.new(0.22, 0.12, 0.32), offset = CFrame.new(0, 0.08, -0.3), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Accessory rail (under dust cover, picatinny rail for lights/lasers)
				add({ role = "body", size = Vector3.new(0.12, 0.04, 0.22), offset = CFrame.new(0, 0.0, -0.32), color = Color3.fromRGB(22, 24, 30), material = Enum.Material.Plastic })
				-- Rail slot cuts (3 transverse grooves)
				for i = 0, 2 do
					add({ role = "body", size = Vector3.new(0.14, 0.025, 0.018), offset = CFrame.new(0, -0.005, -0.25 - i * 0.07), color = Color3.fromRGB(10, 12, 16), material = Enum.Material.Plastic })
				end

				-- ============================================================
				-- SLIDE (cycles on shot — slide role)
				-- ============================================================
				-- Main slide body
				add({ role = "slide", size = Vector3.new(0.22, 0.2, 0.86), offset = CFrame.new(0, 0.24, -0.02), color = Color3.fromRGB(45, 48, 55), material = Enum.Material.Metal })
				-- Slide top flat
				add({ role = "slide", size = Vector3.new(0.18, 0.04, 0.84), offset = CFrame.new(0, 0.36, -0.02), color = Color3.fromRGB(38, 40, 48), material = Enum.Material.Metal })
				-- REAR slide serrations (8 thin grooves on slide rear)
				for i = 0, 7 do
					add({ role = "slide", size = Vector3.new(0.24, 0.18, 0.012), offset = CFrame.new(0, 0.24, 0.16 + i * 0.025), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal })
				end
				-- FRONT slide serrations (6 grooves on slide front)
				for i = 0, 5 do
					add({ role = "slide", size = Vector3.new(0.24, 0.18, 0.012), offset = CFrame.new(0, 0.24, -0.30 - i * 0.025), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal })
				end
				-- Ejection port cutout (square hole on right side of slide)
				add({ role = "slide", size = Vector3.new(0.05, 0.12, 0.22), offset = CFrame.new(0.1, 0.24, -0.05), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				-- Slide stop lever (left side, you press to release slide)
				add({ role = "slide", size = Vector3.new(0.03, 0.04, 0.16), offset = CFrame.new(-0.13, 0.16, 0.08), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal })

				-- ============================================================
				-- BARREL
				-- ============================================================
				-- Inner barrel (visible through ejection port + at muzzle)
				add({ role = "barrel", size = Vector3.new(0.08, 0.08, 0.5), offset = CFrame.new(0, 0.24, -0.18), color = Color3.fromRGB(60, 65, 75), material = Enum.Material.Metal })
				-- Barrel poking out front of slide (Glock 18 has longer barrel than standard Glock 17)
				add({ role = "barrel", size = Vector3.new(0.1, 0.1, 0.18), offset = CFrame.new(0, 0.24, -0.52), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Metal })
				-- Muzzle crown (slight chamfer)
				add({ role = "barrel", size = Vector3.new(0.11, 0.11, 0.03), offset = CFrame.new(0, 0.24, -0.62), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal })
				-- Muzzle hole (dark center)
				add({ role = "barrel", size = Vector3.new(0.05, 0.05, 0.02), offset = CFrame.new(0, 0.24, -0.64), color = Color3.fromRGB(5, 7, 10), material = Enum.Material.Metal })
				-- Recoil spring guide rod (visible at very front, below barrel)
				add({ role = "barrel", size = Vector3.new(0.04, 0.04, 0.16), offset = CFrame.new(0, 0.16, -0.52), color = Color3.fromRGB(70, 75, 85), material = Enum.Material.Metal })

				-- ============================================================
				-- MAGAZINE (17-round 9mm staggered, drops on reload)
				-- ============================================================
				add({ role = "mag", size = Vector3.new(0.2, 0.46, 0.22), offset = CFrame.new(0, -0.36, 0.12), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Plastic })
				-- Mag witness holes (3 visible numbered holes on side)
				for i = 0, 2 do
					add({ role = "mag", size = Vector3.new(0.21, 0.03, 0.04), offset = CFrame.new(0, -0.2 - i * 0.1, 0.18), color = Color3.fromRGB(80, 85, 95), material = Enum.Material.Plastic })
				end
				-- Mag baseplate (the bottom extension you grab)
				add({ role = "mag", size = Vector3.new(0.22, 0.05, 0.26), offset = CFrame.new(0, -0.61, 0.13), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Plastic })
				-- Mag follower visible at top (orange = Glock signature)
				add({ role = "mag", size = Vector3.new(0.16, 0.03, 0.18), offset = CFrame.new(0, -0.12, 0.12), color = Color3.fromRGB(220, 130, 30), material = Enum.Material.Plastic })

				-- ============================================================
				-- PISTOL GRIP (polymer with finger grooves + stippling)
				-- ============================================================
				-- Main grip body
				add({ role = "grip", size = Vector3.new(0.2, 0.42, 0.24), offset = CFrame.new(0, -0.18, 0.2) * CFrame.Angles(rad(-5), 0, 0), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Backstrap (the back of the grip you hold against your palm)
				add({ role = "grip", size = Vector3.new(0.18, 0.42, 0.04), offset = CFrame.new(0, -0.18, 0.32) * CFrame.Angles(rad(-5), 0, 0), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Plastic })
				-- Finger grooves (3 raised ridges on front of grip)
				for i = 0, 2 do
					add({ role = "grip", size = Vector3.new(0.21, 0.025, 0.04), offset = CFrame.new(0, -0.08 - i * 0.12, 0.08) * CFrame.Angles(rad(-5), 0, 0), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Plastic })
				end
				-- Stippling texture (small bumps on grip sides — 6 dots each side)
				for i = 0, 5 do
					add({ role = "grip", size = Vector3.new(0.22, 0.018, 0.018), offset = CFrame.new(0, -0.1 - i * 0.05, 0.22) * CFrame.Angles(rad(-5), 0, 0), color = Color3.fromRGB(50, 52, 60), material = Enum.Material.Plastic })
				end
				-- Magazine release button (right side, behind trigger guard)
				add({ role = "grip", size = Vector3.new(0.04, 0.06, 0.08), offset = CFrame.new(0.12, -0.04, 0.18), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Plastic })
				-- Mag well flare (slight extension at bottom for fast reloads)
				add({ role = "grip", size = Vector3.new(0.21, 0.04, 0.22), offset = CFrame.new(0, -0.38, 0.15), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Plastic })

				-- ============================================================
				-- TRIGGER ASSEMBLY
				-- ============================================================
				-- Trigger guard top
				add({ role = "body", size = Vector3.new(0.05, 0.04, 0.18), offset = CFrame.new(0, -0.02, 0.08), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Trigger guard bottom
				add({ role = "body", size = Vector3.new(0.05, 0.04, 0.18), offset = CFrame.new(0, -0.12, 0.08), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Trigger guard front (rounded curve approximated)
				add({ role = "body", size = Vector3.new(0.05, 0.12, 0.04), offset = CFrame.new(0, -0.07, 0.0), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Trigger guard rear (vertical strut)
				add({ role = "body", size = Vector3.new(0.05, 0.12, 0.04), offset = CFrame.new(0, -0.07, 0.16), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Trigger blade
				add({ role = "body", size = Vector3.new(0.03, 0.1, 0.04), offset = CFrame.new(0, -0.06, 0.1), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Plastic })
				-- Trigger safety blade (Glock's signature center safety on trigger)
				add({ role = "body", size = Vector3.new(0.012, 0.08, 0.02), offset = CFrame.new(0, -0.06, 0.11), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Plastic })

				-- ============================================================
				-- SIGHTS (white-dot iron sights)
				-- ============================================================
				-- Rear sight base
				add({ role = "sight", size = Vector3.new(0.16, 0.06, 0.06), offset = CFrame.new(0, 0.4, 0.38), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal })
				-- Rear sight notch divider
				add({ role = "sight", size = Vector3.new(0.04, 0.08, 0.04), offset = CFrame.new(0, 0.42, 0.4), color = Color3.fromRGB(10, 12, 16), material = Enum.Material.Metal })
				-- Rear sight white dots (2 small dots either side of notch)
				add({ role = "sight", size = Vector3.new(0.02, 0.025, 0.02), offset = CFrame.new(-0.05, 0.41, 0.4), color = Color3.fromRGB(240, 240, 240), material = Enum.Material.SmoothPlastic })
				add({ role = "sight", size = Vector3.new(0.02, 0.025, 0.02), offset = CFrame.new(0.05, 0.41, 0.4), color = Color3.fromRGB(240, 240, 240), material = Enum.Material.SmoothPlastic })
				-- Front sight post
				add({ role = "sight", size = Vector3.new(0.04, 0.08, 0.04), offset = CFrame.new(0, 0.4, -0.32), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal })
				-- Front sight white dot
				add({ role = "sight", size = Vector3.new(0.025, 0.025, 0.02), offset = CFrame.new(0, 0.4, -0.34), color = Color3.fromRGB(240, 240, 240), material = Enum.Material.SmoothPlastic })

				-- COCKING ARM — fake left hand reaching for slide. Fades out by
				-- end of draw via isCockingArm flag (handled in WeaponController).
				add({ role = "hand", size = Vector3.new(0.5, 0.20, 0.20),
					offset = CFrame.new(0.0, 0.30, 0.05) * CFrame.Angles(0, math.rad(-100), 0),
					color = Color3.fromRGB(225, 190, 155), material = Enum.Material.SmoothPlastic,
					isCockingArm = true })

				return parts
			end)(),
		},
	},

	rifle = {
		id = "rifle",
		displayName = "AK-47",
		tier = "Epic",
		slot = "primary",
		damage = 32,
		fireRate = 9,
		range = 350,
		magSize = 30,
		reloadTime = 2.4,
		drawTime = 1.0,
		headshotMultiplier = 4.0, -- 32 × 4.0 = 128 dmg → instant headshot kill (>100 HP)
		falloffStart = 70,
		falloffEnd = 220,
		minDamageMul = 0.55,
		recoilVertical = 0.5,
		recoilHorizontal = 0.3,
		recoilRecoverSpeed = 4.5,
		isAuto = true,
		viewmodel = {
			grip = CFrame.new(0.55, -0.42, -1.8) * CFrame.Angles(0, rad(-3), 0),
			parts = {
				-- ================================================================
				-- RECEIVER (main metal body) — recolor on skin
				-- ================================================================
				-- Main receiver lower (the boxy lower part)
				{ role = "body", size = Vector3.new(0.22, 0.28, 1.0), offset = CFrame.new(0, -0.02, 0), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal },
				-- Rear receiver cap (angled cut where stock meets, simulated with thin part)
				{ role = "body", size = Vector3.new(0.22, 0.22, 0.06), offset = CFrame.new(0, -0.05, 0.5), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				-- Dust cover (top of receiver, removable in real life)
				{ role = "body", size = Vector3.new(0.2, 0.08, 0.92), offset = CFrame.new(0, 0.17, -0.04), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal },
				-- Dust cover center ridge
				{ role = "body", size = Vector3.new(0.05, 0.04, 0.86), offset = CFrame.new(0, 0.22, -0.04), color = Color3.fromRGB(20, 22, 30), material = Enum.Material.Metal },
				-- Receiver rivets (3 LEFT side, classic Romanian/Russian style)
				{ role = "body", size = Vector3.new(0.025, 0.06, 0.06), offset = CFrame.new(-0.12, 0.04, -0.22), color = Color3.fromRGB(20, 22, 30), material = Enum.Material.Metal },
				{ role = "body", size = Vector3.new(0.025, 0.06, 0.06), offset = CFrame.new(-0.12, 0.04, 0.02), color = Color3.fromRGB(20, 22, 30), material = Enum.Material.Metal },
				{ role = "body", size = Vector3.new(0.025, 0.06, 0.06), offset = CFrame.new(-0.12, 0.04, 0.22), color = Color3.fromRGB(20, 22, 30), material = Enum.Material.Metal },
				-- Receiver rivets (3 RIGHT side, mirror)
				{ role = "body", size = Vector3.new(0.025, 0.06, 0.06), offset = CFrame.new(0.12, 0.04, -0.22), color = Color3.fromRGB(20, 22, 30), material = Enum.Material.Metal },
				{ role = "body", size = Vector3.new(0.025, 0.06, 0.06), offset = CFrame.new(0.12, 0.04, 0.02), color = Color3.fromRGB(20, 22, 30), material = Enum.Material.Metal },
				{ role = "body", size = Vector3.new(0.025, 0.06, 0.06), offset = CFrame.new(0.12, 0.04, 0.22), color = Color3.fromRGB(20, 22, 30), material = Enum.Material.Metal },
				-- Magazine well lip (the "shelf" extending below receiver, holds mag)
				{ role = "body", size = Vector3.new(0.24, 0.05, 0.32), offset = CFrame.new(0, -0.19, 0.04), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				-- Selector lever (big right-side AK lever — iconic)
				{ role = "body", size = Vector3.new(0.08, 0.22, 0.32), offset = CFrame.new(0.13, 0.0, 0.08), color = Color3.fromRGB(45, 48, 56), material = Enum.Material.Metal },
				-- Selector lever pivot dot
				{ role = "body", size = Vector3.new(0.03, 0.05, 0.05), offset = CFrame.new(0.15, 0.06, 0.0), color = Color3.fromRGB(60, 65, 75), material = Enum.Material.Metal },
				-- Selector position markers (S/A/1 stamps — 3 small ridges on receiver)
				{ role = "body", size = Vector3.new(0.012, 0.025, 0.012), offset = CFrame.new(0.115, 0.11, 0.0), color = Color3.fromRGB(220, 220, 220), material = Enum.Material.Metal },
				{ role = "body", size = Vector3.new(0.012, 0.025, 0.012), offset = CFrame.new(0.115, 0.05, 0.0), color = Color3.fromRGB(220, 220, 220), material = Enum.Material.Metal },
				{ role = "body", size = Vector3.new(0.012, 0.025, 0.012), offset = CFrame.new(0.115, -0.01, 0.0), color = Color3.fromRGB(220, 220, 220), material = Enum.Material.Metal },
				-- Charging handle knurling (3 small grip lines on slide knob)
				{ role = "slide", size = Vector3.new(0.07, 0.025, 0.01), offset = CFrame.new(0.25, 0.18, -0.1), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				{ role = "slide", size = Vector3.new(0.07, 0.025, 0.01), offset = CFrame.new(0.25, 0.16, -0.1), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				{ role = "slide", size = Vector3.new(0.07, 0.025, 0.01), offset = CFrame.new(0.25, 0.14, -0.1), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				-- Dust cover release button (small recessed circle at rear of dust cover)
				{ role = "body", size = Vector3.new(0.04, 0.04, 0.04), offset = CFrame.new(0, 0.2, 0.4), color = Color3.fromRGB(55, 60, 70), material = Enum.Material.Metal, shape = "ball" },
				-- Mag release paddle (front of trigger guard, ahead of mag)
				{ role = "body", size = Vector3.new(0.04, 0.14, 0.06), offset = CFrame.new(0, -0.23, -0.02), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },

				-- ================================================================
				-- CHARGING HANDLE (slide role — moves during cocking & reload)
				-- ================================================================
				-- Handle stub sticking right (welded to bolt carrier)
				{ role = "slide", size = Vector3.new(0.38, 0.08, 0.16), offset = CFrame.new(0.07, 0.16, -0.1), color = Color3.fromRGB(55, 60, 70), material = Enum.Material.Metal },
				-- Handle knob (round grippy end you grab)
				{ role = "slide", size = Vector3.new(0.06, 0.12, 0.1), offset = CFrame.new(0.25, 0.16, -0.1), color = Color3.fromRGB(70, 75, 85), material = Enum.Material.Metal },
				-- Handle base attachment
				{ role = "slide", size = Vector3.new(0.06, 0.08, 0.16), offset = CFrame.new(0.08, 0.16, -0.1), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal },

				-- ================================================================
				-- LOWER HANDGUARD (wood, tapered toward muzzle — 5 segments)
				-- ================================================================
				-- Segment 1 (closest to receiver, widest)
				{ role = "barrel", size = Vector3.new(0.22, 0.16, 0.14), offset = CFrame.new(0, -0.04, -0.47), color = Color3.fromRGB(130, 80, 40), material = Enum.Material.Wood },
				-- Segment 2
				{ role = "barrel", size = Vector3.new(0.21, 0.16, 0.14), offset = CFrame.new(0, -0.04, -0.6), color = Color3.fromRGB(135, 82, 42), material = Enum.Material.Wood },
				-- Segment 3 (middle, narrow groove for fingers)
				{ role = "barrel", size = Vector3.new(0.2, 0.14, 0.14), offset = CFrame.new(0, -0.05, -0.73), color = Color3.fromRGB(125, 76, 38), material = Enum.Material.Wood },
				-- Segment 4
				{ role = "barrel", size = Vector3.new(0.19, 0.14, 0.14), offset = CFrame.new(0, -0.05, -0.86), color = Color3.fromRGB(132, 80, 40), material = Enum.Material.Wood },
				-- Segment 5 (narrowest, near front cap)
				{ role = "barrel", size = Vector3.new(0.18, 0.13, 0.1), offset = CFrame.new(0, -0.06, -0.97), color = Color3.fromRGB(120, 72, 36), material = Enum.Material.Wood },
				-- Finger grooves (3 thin darker strips)
				{ role = "barrel", size = Vector3.new(0.23, 0.025, 0.04), offset = CFrame.new(0, -0.08, -0.6), color = Color3.fromRGB(80, 50, 25), material = Enum.Material.Wood },
				{ role = "barrel", size = Vector3.new(0.22, 0.025, 0.04), offset = CFrame.new(0, -0.08, -0.75), color = Color3.fromRGB(80, 50, 25), material = Enum.Material.Wood },
				{ role = "barrel", size = Vector3.new(0.21, 0.025, 0.04), offset = CFrame.new(0, -0.08, -0.9), color = Color3.fromRGB(80, 50, 25), material = Enum.Material.Wood },
				-- Handguard front metal cap
				{ role = "barrel", size = Vector3.new(0.22, 0.18, 0.06), offset = CFrame.new(0, 0.04, -1.03), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal },
				-- Handguard rear metal cap
				{ role = "barrel", size = Vector3.new(0.22, 0.18, 0.06), offset = CFrame.new(0, 0.04, -0.42), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal },

				-- ================================================================
				-- UPPER HANDGUARD (wood over gas tube — 4 segments tapered)
				-- ================================================================
				{ role = "barrel", size = Vector3.new(0.2, 0.1, 0.14), offset = CFrame.new(0, 0.16, -0.5), color = Color3.fromRGB(140, 88, 45), material = Enum.Material.Wood },
				{ role = "barrel", size = Vector3.new(0.19, 0.1, 0.14), offset = CFrame.new(0, 0.16, -0.64), color = Color3.fromRGB(138, 86, 44), material = Enum.Material.Wood },
				{ role = "barrel", size = Vector3.new(0.18, 0.1, 0.14), offset = CFrame.new(0, 0.16, -0.78), color = Color3.fromRGB(142, 90, 46), material = Enum.Material.Wood },
				{ role = "barrel", size = Vector3.new(0.17, 0.1, 0.12), offset = CFrame.new(0, 0.16, -0.91), color = Color3.fromRGB(136, 84, 42), material = Enum.Material.Wood },

				-- ================================================================
				-- GAS SYSTEM
				-- ================================================================
				-- Gas block (large block where barrel meets gas tube, slightly angled)
				{ role = "barrel", size = Vector3.new(0.14, 0.2, 0.14), offset = CFrame.new(0, 0.1, -1.1), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal },
				-- Gas tube (slim cylinder above barrel)
				{ role = "barrel", size = Vector3.new(0.08, 0.08, 0.52), offset = CFrame.new(0, 0.24, -0.72), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				-- Gas tube end cap (rear)
				{ role = "barrel", size = Vector3.new(0.1, 0.1, 0.04), offset = CFrame.new(0, 0.24, -0.45), color = Color3.fromRGB(38, 40, 48), material = Enum.Material.Metal },
				-- Gas tube vents (3 small slot details on side)
				{ role = "barrel", size = Vector3.new(0.09, 0.03, 0.03), offset = CFrame.new(0, 0.27, -0.6), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal },
				{ role = "barrel", size = Vector3.new(0.09, 0.03, 0.03), offset = CFrame.new(0, 0.27, -0.72), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal },
				{ role = "barrel", size = Vector3.new(0.09, 0.03, 0.03), offset = CFrame.new(0, 0.27, -0.84), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal },

				-- ================================================================
				-- BARREL (segmented for taper + sights)
				-- ================================================================
				-- Main barrel (between handguard front and front sight)
				{ role = "barrel", size = Vector3.new(0.1, 0.1, 0.4), offset = CFrame.new(0, -0.02, -1.3), color = Color3.fromRGB(25, 28, 35), material = Enum.Material.Metal },
				-- Barrel forward of front sight (thinner)
				{ role = "barrel", size = Vector3.new(0.09, 0.09, 0.18), offset = CFrame.new(0, -0.02, -1.6), color = Color3.fromRGB(22, 25, 32), material = Enum.Material.Metal },
				-- Front sight block (the big square base before sight post)
				{ role = "barrel", size = Vector3.new(0.13, 0.24, 0.12), offset = CFrame.new(0, 0.08, -1.5), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal },
				-- Bayonet lug (small block under barrel)
				{ role = "barrel", size = Vector3.new(0.08, 0.04, 0.1), offset = CFrame.new(0, -0.08, -1.5), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal },
				-- Slant compensator (AK-74 style — angled muzzle brake)
				{ role = "barrel", size = Vector3.new(0.14, 0.16, 0.16), offset = CFrame.new(0, 0.0, -1.76) * CFrame.Angles(0, rad(-8), 0), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				-- Compensator top expansion chamber (the big cut on top)
				{ role = "barrel", size = Vector3.new(0.12, 0.06, 0.1), offset = CFrame.new(0, 0.08, -1.78), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal },
				-- Compensator side ports (2 left + 2 right)
				{ role = "barrel", size = Vector3.new(0.04, 0.06, 0.025), offset = CFrame.new(-0.07, 0.0, -1.74), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal },
				{ role = "barrel", size = Vector3.new(0.04, 0.06, 0.025), offset = CFrame.new(-0.07, 0.0, -1.78), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal },
				{ role = "barrel", size = Vector3.new(0.04, 0.06, 0.025), offset = CFrame.new(0.07, 0.0, -1.74), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal },
				{ role = "barrel", size = Vector3.new(0.04, 0.06, 0.025), offset = CFrame.new(0.07, 0.0, -1.78), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal },
				-- Muzzle crown
				{ role = "barrel", size = Vector3.new(0.13, 0.13, 0.02), offset = CFrame.new(0, -0.02, -1.84), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Metal },
				-- Muzzle hole
				{ role = "barrel", size = Vector3.new(0.05, 0.05, 0.02), offset = CFrame.new(0, -0.02, -1.85), color = Color3.fromRGB(5, 7, 10), material = Enum.Material.Metal },

				-- ================================================================
				-- BANANA MAGAZINE — 7 segments forming smooth curve
				-- Each segment tilts more forward, drops down, shifts forward.
				-- ================================================================
				-- Mag well top section (vertical at top, attaches to receiver)
				{ role = "mag", size = Vector3.new(0.18, 0.07, 0.22), offset = CFrame.new(0, -0.2, 0.05), color = Color3.fromRGB(55, 42, 30), material = Enum.Material.Wood },
				-- Seg 1 (slight tilt 5°)
				{ role = "mag", size = Vector3.new(0.18, 0.07, 0.22), offset = CFrame.new(0, -0.27, 0.045) * CFrame.Angles(rad(-5), 0, 0), color = Color3.fromRGB(52, 40, 28), material = Enum.Material.Wood },
				-- Seg 2 (10°)
				{ role = "mag", size = Vector3.new(0.18, 0.07, 0.22), offset = CFrame.new(0, -0.34, 0.035) * CFrame.Angles(rad(-10), 0, 0), color = Color3.fromRGB(50, 38, 27), material = Enum.Material.Wood },
				-- Seg 3 (15°)
				{ role = "mag", size = Vector3.new(0.18, 0.07, 0.22), offset = CFrame.new(0, -0.41, 0.018) * CFrame.Angles(rad(-15), 0, 0), color = Color3.fromRGB(48, 36, 26), material = Enum.Material.Wood },
				-- Seg 4 (20°)
				{ role = "mag", size = Vector3.new(0.18, 0.07, 0.22), offset = CFrame.new(0, -0.48, -0.005) * CFrame.Angles(rad(-20), 0, 0), color = Color3.fromRGB(46, 35, 25), material = Enum.Material.Wood },
				-- Seg 5 (25°)
				{ role = "mag", size = Vector3.new(0.17, 0.07, 0.22), offset = CFrame.new(0, -0.54, -0.035) * CFrame.Angles(rad(-25), 0, 0), color = Color3.fromRGB(44, 34, 24), material = Enum.Material.Wood },
				-- Seg 6 (30°, bottom of mag with floor plate)
				{ role = "mag", size = Vector3.new(0.17, 0.06, 0.22), offset = CFrame.new(0, -0.6, -0.07) * CFrame.Angles(rad(-30), 0, 0), color = Color3.fromRGB(42, 32, 22), material = Enum.Material.Wood },
				-- Mag floor plate (the bottom metal cap)
				{ role = "mag", size = Vector3.new(0.18, 0.025, 0.23), offset = CFrame.new(0, -0.64, -0.09) * CFrame.Angles(rad(-30), 0, 0), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal },
				-- Mag follower visible inside well (tiny piece on top)
				{ role = "mag", size = Vector3.new(0.14, 0.03, 0.18), offset = CFrame.new(0, -0.16, 0.05), color = Color3.fromRGB(80, 50, 30), material = Enum.Material.Metal },

				-- ================================================================
				-- PISTOL GRIP — 5 segments forming bird's beak curve
				-- ================================================================
				-- Top of grip (joins receiver)
				{ role = "grip", size = Vector3.new(0.2, 0.08, 0.24), offset = CFrame.new(0, -0.16, 0.35), color = Color3.fromRGB(130, 82, 42), material = Enum.Material.Wood },
				-- Upper segment (5° forward)
				{ role = "grip", size = Vector3.new(0.2, 0.1, 0.24), offset = CFrame.new(0, -0.25, 0.38) * CFrame.Angles(rad(-6), 0, 0), color = Color3.fromRGB(128, 80, 40), material = Enum.Material.Wood },
				-- Middle (12° forward, slight bulge)
				{ role = "grip", size = Vector3.new(0.21, 0.1, 0.25), offset = CFrame.new(0, -0.34, 0.42) * CFrame.Angles(rad(-12), 0, 0), color = Color3.fromRGB(125, 78, 38), material = Enum.Material.Wood },
				-- Lower (18°)
				{ role = "grip", size = Vector3.new(0.2, 0.09, 0.24), offset = CFrame.new(0, -0.43, 0.47) * CFrame.Angles(rad(-18), 0, 0), color = Color3.fromRGB(122, 76, 36), material = Enum.Material.Wood },
				-- Bottom curl (24°, the "beak")
				{ role = "grip", size = Vector3.new(0.19, 0.08, 0.22), offset = CFrame.new(0, -0.51, 0.53) * CFrame.Angles(rad(-24), 0, 0), color = Color3.fromRGB(118, 72, 35), material = Enum.Material.Wood },
				-- Grip cap (metal bottom)
				{ role = "grip", size = Vector3.new(0.18, 0.03, 0.2), offset = CFrame.new(0, -0.56, 0.56) * CFrame.Angles(rad(-24), 0, 0), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal },
				-- Grip checkering stripes (3 horizontal grooves for grip texture)
				{ role = "grip", size = Vector3.new(0.22, 0.02, 0.02), offset = CFrame.new(0, -0.3, 0.34) * CFrame.Angles(rad(-9), 0, 0), color = Color3.fromRGB(85, 55, 25), material = Enum.Material.Wood },
				{ role = "grip", size = Vector3.new(0.22, 0.02, 0.02), offset = CFrame.new(0, -0.38, 0.36) * CFrame.Angles(rad(-13), 0, 0), color = Color3.fromRGB(85, 55, 25), material = Enum.Material.Wood },
				{ role = "grip", size = Vector3.new(0.21, 0.02, 0.02), offset = CFrame.new(0, -0.46, 0.4) * CFrame.Angles(rad(-18), 0, 0), color = Color3.fromRGB(85, 55, 25), material = Enum.Material.Wood },

				-- ================================================================
				-- TRIGGER ASSEMBLY
				-- ================================================================
				-- Trigger guard top
				{ role = "body", size = Vector3.new(0.06, 0.04, 0.2), offset = CFrame.new(0, -0.16, 0.17), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				-- Trigger guard bottom
				{ role = "body", size = Vector3.new(0.06, 0.04, 0.2), offset = CFrame.new(0, -0.28, 0.17), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				-- Trigger guard rear
				{ role = "body", size = Vector3.new(0.06, 0.16, 0.04), offset = CFrame.new(0, -0.22, 0.25), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				-- Trigger guard front
				{ role = "body", size = Vector3.new(0.06, 0.16, 0.04), offset = CFrame.new(0, -0.22, 0.09), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal },
				-- Trigger blade (curved-ish via thin angled box)
				{ role = "body", size = Vector3.new(0.05, 0.12, 0.04), offset = CFrame.new(0, -0.2, 0.17) * CFrame.Angles(rad(8), 0, 0), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal },

				-- ================================================================
				-- BUTTSTOCK (wood) — angled comb cut for realistic AK profile
				-- ================================================================
				-- Stock attachment plate (where stock meets receiver, metal)
				{ role = "stock", size = Vector3.new(0.22, 0.3, 0.06), offset = CFrame.new(0, -0.05, 0.54), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal },
				-- Main stock body (lower part, full length)
				{ role = "stock", size = Vector3.new(0.18, 0.18, 0.85), offset = CFrame.new(0, -0.13, 0.98), color = Color3.fromRGB(130, 82, 40), material = Enum.Material.Wood },
				-- Stock upper segments forming slanted "comb" (3 stepped pieces going down toward back)
				{ role = "stock", size = Vector3.new(0.16, 0.08, 0.3), offset = CFrame.new(0, 0.08, 0.7), color = Color3.fromRGB(125, 78, 38), material = Enum.Material.Wood },
				{ role = "stock", size = Vector3.new(0.16, 0.07, 0.3), offset = CFrame.new(0, 0.05, 0.95), color = Color3.fromRGB(128, 80, 39), material = Enum.Material.Wood },
				{ role = "stock", size = Vector3.new(0.16, 0.05, 0.3), offset = CFrame.new(0, 0.02, 1.2), color = Color3.fromRGB(122, 76, 37), material = Enum.Material.Wood },
				-- Stock middle filler (visual blend between top + bottom)
				{ role = "stock", size = Vector3.new(0.18, 0.1, 0.7), offset = CFrame.new(0, 0.0, 0.95), color = Color3.fromRGB(128, 80, 39), material = Enum.Material.Wood },
				-- Recoil pad (rubber-look black plate at very end)
				{ role = "stock", size = Vector3.new(0.2, 0.32, 0.04), offset = CFrame.new(0, -0.04, 1.42), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Plastic },
				-- Sling swivel (small loop on left side of stock)
				{ role = "stock", size = Vector3.new(0.04, 0.06, 0.08), offset = CFrame.new(-0.1, -0.18, 0.85), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal },
				-- Sling swivel front (under handguard rear cap)
				{ role = "stock", size = Vector3.new(0.04, 0.06, 0.08), offset = CFrame.new(0, -0.13, -0.45), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal },

				-- ================================================================
				-- SIGHTS
				-- ================================================================
				-- Front sight post (the upright pin you aim with)
				{ role = "sight", size = Vector3.new(0.025, 0.16, 0.025), offset = CFrame.new(0, 0.24, -1.5), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Metal },
				-- Front sight protector wings (curved guard around post)
				{ role = "sight", size = Vector3.new(0.02, 0.14, 0.06), offset = CFrame.new(-0.05, 0.25, -1.5), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Metal },
				{ role = "sight", size = Vector3.new(0.02, 0.14, 0.06), offset = CFrame.new(0.05, 0.25, -1.5), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Metal },
				-- Front sight wing TOP connector (curved over post)
				{ role = "sight", size = Vector3.new(0.12, 0.02, 0.06), offset = CFrame.new(0, 0.32, -1.5), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Metal },
				-- Rear sight base
				{ role = "sight", size = Vector3.new(0.18, 0.06, 0.18), offset = CFrame.new(0, 0.26, 0.16), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal },
				-- Rear sight leaf (the notched blade)
				{ role = "sight", size = Vector3.new(0.14, 0.1, 0.05), offset = CFrame.new(0, 0.33, 0.22), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Metal },
				-- Rear sight slider (the marked piece you adjust)
				{ role = "sight", size = Vector3.new(0.08, 0.04, 0.12), offset = CFrame.new(0, 0.31, 0.13), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal },

				-- ================================================================
				-- CLEANING ROD (slim long rod under barrel — classic AK detail)
				-- ================================================================
				{ role = "barrel", size = Vector3.new(0.035, 0.035, 1.0), offset = CFrame.new(0, -0.13, -1.05), color = Color3.fromRGB(60, 65, 75), material = Enum.Material.Metal },
				-- Cleaning rod head (tiny tip)
				{ role = "barrel", size = Vector3.new(0.05, 0.05, 0.04), offset = CFrame.new(0, -0.13, -1.57), color = Color3.fromRGB(70, 75, 85), material = Enum.Material.Metal },

				-- ================================================================
				-- LEFT FORE-ARM (always visible — extends from PLAYER BODY (back) to magazine area (front))
				-- Long axis along Z (camera depth) so arm looks like it's coming from player's body.
				-- ================================================================
				-- Chunky forearm: extends back-left from front-of-magazine area. Hand (tip) lands in front of mag.
				{ role = "hand", size = Vector3.new(1.4, 0.26, 0.26),
					offset = CFrame.new(-0.5, -0.3, 0.1) * CFrame.Angles(0, math.rad(-135), 0),
					color = Color3.fromRGB(225, 190, 155), material = Enum.Material.SmoothPlastic },

				-- (Cocking arm removed — during cocking the existing LEFT fore-arm reaches charging handle
				-- when AK rotates left, no separate ghost arm needed.)
			},
		},
	},

	smg = {
		id = "smg",
		displayName = "UMP-45",
		tier = "Rare",
		slot = "primary",
		damage = 18,
		fireRate = 10,
		range = 200,
		magSize = 25,
		reloadTime = 2.0,
		drawTime = 0.7,
		headshotMultiplier = 1.6,
		falloffStart = 30,
		falloffEnd = 100,
		minDamageMul = 0.5,
		recoilVertical = 0.35,
		recoilHorizontal = 0.35,
		recoilRecoverSpeed = 7,
		isAuto = true,
		viewmodel = {
			grip = CFrame.new(0.55, -0.42, -1.4) * CFrame.Angles(0, rad(-3), 0),
			parts = (function(): { ViewmodelPart }
				local parts: { ViewmodelPart } = {}
				local function add(p: any) table.insert(parts, p) end

				-- ============================================================
				-- LOWER RECEIVER (polymer, dark gray)
				-- ============================================================
				-- Main lower receiver body
				add({ role = "body", size = Vector3.new(0.2, 0.24, 0.85), offset = CFrame.new(0, -0.02, 0), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Mag well housing (wider flare around mag)
				add({ role = "body", size = Vector3.new(0.24, 0.2, 0.34), offset = CFrame.new(0, -0.13, 0.12), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Lower receiver front fin (UMP signature shape under barrel)
				add({ role = "body", size = Vector3.new(0.2, 0.08, 0.5), offset = CFrame.new(0, -0.12, -0.25), color = Color3.fromRGB(28, 30, 36), material = Enum.Material.Plastic })
				-- Forend grip area (where support hand goes)
				add({ role = "body", size = Vector3.new(0.18, 0.1, 0.3), offset = CFrame.new(0, -0.06, -0.32), color = Color3.fromRGB(22, 24, 30), material = Enum.Material.Plastic })
				-- Hand-stop ledge at front (prevents support hand from sliding forward)
				add({ role = "body", size = Vector3.new(0.2, 0.06, 0.04), offset = CFrame.new(0, -0.08, -0.42), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Plastic })
				-- Trigger pin (pin head visible left side)
				add({ role = "body", size = Vector3.new(0.04, 0.04, 0.04), offset = CFrame.new(-0.11, -0.05, 0.18), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })
				-- Trigger pin (pin head visible right side)
				add({ role = "body", size = Vector3.new(0.04, 0.04, 0.04), offset = CFrame.new(0.11, -0.05, 0.18), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })

				-- ============================================================
				-- UPPER RECEIVER + BOLT (slide role — cycles on shot)
				-- ============================================================
				-- Main upper receiver (the box on top)
				add({ role = "slide", size = Vector3.new(0.22, 0.18, 0.7), offset = CFrame.new(0, 0.16, -0.05), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal })
				-- Top flat
				add({ role = "slide", size = Vector3.new(0.18, 0.04, 0.66), offset = CFrame.new(0, 0.27, -0.05), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal })
				-- Charging handle slot (the channel where handle moves)
				add({ role = "slide", size = Vector3.new(0.02, 0.06, 0.4), offset = CFrame.new(-0.11, 0.16, 0.1), color = Color3.fromRGB(10, 12, 16), material = Enum.Material.Metal })
				-- Charging handle nub (left side)
				add({ role = "slide", size = Vector3.new(0.08, 0.06, 0.06), offset = CFrame.new(-0.14, 0.16, 0.18), color = Color3.fromRGB(60, 65, 75), material = Enum.Material.Metal })
				-- Charging handle knob (round end you grab)
				add({ role = "slide", size = Vector3.new(0.06, 0.1, 0.08), offset = CFrame.new(-0.18, 0.16, 0.18), color = Color3.fromRGB(75, 80, 90), material = Enum.Material.Metal, shape = "ball" })
				-- Ejection port (rectangular cutout right side)
				add({ role = "slide", size = Vector3.new(0.04, 0.1, 0.22), offset = CFrame.new(0.11, 0.16, 0.0), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				-- Brass deflector (small angled piece at rear of ejection port)
				add({ role = "slide", size = Vector3.new(0.04, 0.08, 0.04), offset = CFrame.new(0.11, 0.18, 0.13), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })

				-- ============================================================
				-- TOP PICATINNY RAIL (for sights/optics)
				-- ============================================================
				add({ role = "body", size = Vector3.new(0.09, 0.04, 0.66), offset = CFrame.new(0, 0.31, -0.05), color = Color3.fromRGB(25, 27, 35), material = Enum.Material.Metal })
				-- Rail slot cuts (6 transverse grooves making it look picatinny)
				for i = 0, 5 do
					add({ role = "body", size = Vector3.new(0.1, 0.025, 0.018), offset = CFrame.new(0, 0.305, -0.3 + i * 0.1), color = Color3.fromRGB(10, 12, 16), material = Enum.Material.Metal })
				end

				-- ============================================================
				-- BARREL
				-- ============================================================
				-- Inner barrel (between front of receiver and muzzle)
				add({ role = "barrel", size = Vector3.new(0.1, 0.1, 0.45), offset = CFrame.new(0, 0.08, -0.65), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal })
				-- Barrel shroud collar (mid-barrel reinforcement)
				add({ role = "barrel", size = Vector3.new(0.13, 0.13, 0.05), offset = CFrame.new(0, 0.08, -0.55), color = Color3.fromRGB(38, 40, 48), material = Enum.Material.Metal })
				-- Compensator (muzzle device)
				add({ role = "barrel", size = Vector3.new(0.14, 0.14, 0.12), offset = CFrame.new(0, 0.08, -0.93), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal })
				-- Compensator side vents (left + right)
				add({ role = "barrel", size = Vector3.new(0.16, 0.06, 0.025), offset = CFrame.new(0, 0.12, -0.91), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				add({ role = "barrel", size = Vector3.new(0.16, 0.06, 0.025), offset = CFrame.new(0, 0.12, -0.95), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				-- Muzzle crown
				add({ role = "barrel", size = Vector3.new(0.13, 0.13, 0.02), offset = CFrame.new(0, 0.08, -0.99), color = Color3.fromRGB(25, 27, 35), material = Enum.Material.Metal })
				-- Muzzle hole
				add({ role = "barrel", size = Vector3.new(0.05, 0.05, 0.02), offset = CFrame.new(0, 0.08, -1.005), color = Color3.fromRGB(5, 7, 10), material = Enum.Material.Metal })

				-- ============================================================
				-- MAGAZINE (curved 25-round .45 ACP, drops on reload)
				-- ============================================================
				-- Mag segments (4 stacked for slight curve)
				for i = 0, 3 do
					local tilt = -8 - i * 2 -- progressive curve
					local yOff = -0.2 - i * 0.1
					local zOff = 0.1 + i * 0.005
					add({ role = "mag", size = Vector3.new(0.2, 0.1, 0.24), offset = CFrame.new(0, yOff, zOff) * CFrame.Angles(rad(tilt), 0, 0), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Plastic })
				end
				-- Mag floor plate (bottom)
				add({ role = "mag", size = Vector3.new(0.22, 0.04, 0.26), offset = CFrame.new(0, -0.62, 0.18) * CFrame.Angles(rad(-14), 0, 0), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Plastic })
				-- Mag witness holes (3 small notches showing ammo count)
				for i = 0, 2 do
					add({ role = "mag", size = Vector3.new(0.21, 0.025, 0.04), offset = CFrame.new(0, -0.26 - i * 0.1, 0.18) * CFrame.Angles(rad(-10), 0, 0), color = Color3.fromRGB(60, 65, 75), material = Enum.Material.Plastic })
				end

				-- ============================================================
				-- PISTOL GRIP (polymer, angled — H&K UMP style)
				-- ============================================================
				add({ role = "grip", size = Vector3.new(0.18, 0.38, 0.22), offset = CFrame.new(0, -0.22, 0.35) * CFrame.Angles(rad(-10), 0, 0), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Plastic })
				-- Backstrap
				add({ role = "grip", size = Vector3.new(0.16, 0.38, 0.04), offset = CFrame.new(0, -0.22, 0.45) * CFrame.Angles(rad(-10), 0, 0), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Plastic })
				-- Grip stippling (5 horizontal ridges for texture)
				for i = 0, 4 do
					add({ role = "grip", size = Vector3.new(0.19, 0.02, 0.02), offset = CFrame.new(0, -0.12 - i * 0.06, 0.3) * CFrame.Angles(rad(-10), 0, 0), color = Color3.fromRGB(55, 58, 65), material = Enum.Material.Plastic })
				end
				-- Grip bottom flare (palm rest)
				add({ role = "grip", size = Vector3.new(0.19, 0.04, 0.22), offset = CFrame.new(0, -0.42, 0.4) * CFrame.Angles(rad(-10), 0, 0), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Plastic })

				-- ============================================================
				-- TRIGGER ASSEMBLY
				-- ============================================================
				-- Trigger blade
				add({ role = "body", size = Vector3.new(0.04, 0.1, 0.04), offset = CFrame.new(0, -0.12, 0.16) * CFrame.Angles(rad(5), 0, 0), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal })
				-- Trigger guard top
				add({ role = "body", size = Vector3.new(0.06, 0.04, 0.18), offset = CFrame.new(0, -0.06, 0.16), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Plastic })
				-- Trigger guard bottom
				add({ role = "body", size = Vector3.new(0.06, 0.04, 0.18), offset = CFrame.new(0, -0.2, 0.16), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Plastic })
				-- Trigger guard front strut
				add({ role = "body", size = Vector3.new(0.06, 0.14, 0.04), offset = CFrame.new(0, -0.13, 0.08), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Plastic })
				-- Trigger guard rear strut
				add({ role = "body", size = Vector3.new(0.06, 0.14, 0.04), offset = CFrame.new(0, -0.13, 0.24), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Plastic })
				-- Safety selector lever (left side, 3-position)
				add({ role = "body", size = Vector3.new(0.04, 0.06, 0.08), offset = CFrame.new(-0.11, -0.02, 0.24), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal })
				-- Mag release paddle (just behind mag, ambidextrous lever)
				add({ role = "body", size = Vector3.new(0.04, 0.08, 0.04), offset = CFrame.new(0, -0.16, 0.28), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal })

				-- ============================================================
				-- FOLDING STOCK (UMP signature side-folding skeleton — extended)
				-- ============================================================
				-- Top stock arm (skeleton rail)
				add({ role = "stock", size = Vector3.new(0.06, 0.04, 0.55), offset = CFrame.new(0, 0.1, 0.6), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal })
				-- Bottom stock arm (skeleton rail)
				add({ role = "stock", size = Vector3.new(0.06, 0.04, 0.55), offset = CFrame.new(0, -0.05, 0.6), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal })
				-- Stock cross-brace (vertical connector between top + bottom rails)
				add({ role = "stock", size = Vector3.new(0.06, 0.18, 0.04), offset = CFrame.new(0, 0.025, 0.7), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal })
				-- Stock joint hinge (where it folds at receiver)
				add({ role = "stock", size = Vector3.new(0.12, 0.16, 0.06), offset = CFrame.new(0, 0.025, 0.4), color = Color3.fromRGB(45, 48, 56), material = Enum.Material.Metal })
				-- Hinge pin (visible bolt)
				add({ role = "stock", size = Vector3.new(0.04, 0.04, 0.08), offset = CFrame.new(0.07, 0.025, 0.4), color = Color3.fromRGB(60, 65, 75), material = Enum.Material.Metal })
				-- Stock buttplate (rubber pad at end)
				add({ role = "stock", size = Vector3.new(0.18, 0.24, 0.04), offset = CFrame.new(0, 0.025, 0.92), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Plastic })
				-- Buttplate horizontal ridges (3 grip ridges)
				for i = 0, 2 do
					add({ role = "stock", size = Vector3.new(0.18, 0.012, 0.02), offset = CFrame.new(0, 0.06 - i * 0.04, 0.94), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Plastic })
				end
				-- Sling swivel
				add({ role = "stock", size = Vector3.new(0.04, 0.05, 0.05), offset = CFrame.new(0.08, 0.025, 0.45), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })

				-- ============================================================
				-- SIGHTS (folding iron sights)
				-- ============================================================
				-- Rear sight base
				add({ role = "sight", size = Vector3.new(0.11, 0.05, 0.06), offset = CFrame.new(0, 0.34, 0.2), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Metal })
				-- Rear sight aperture (the hole you look through)
				add({ role = "sight", size = Vector3.new(0.07, 0.08, 0.03), offset = CFrame.new(0, 0.38, 0.22), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal })
				-- Rear sight aperture hole (dark center)
				add({ role = "sight", size = Vector3.new(0.025, 0.025, 0.04), offset = CFrame.new(0, 0.38, 0.22), color = Color3.fromRGB(5, 7, 10), material = Enum.Material.Metal })
				-- Front sight ring base (protective hood)
				add({ role = "sight", size = Vector3.new(0.1, 0.08, 0.04), offset = CFrame.new(0, 0.36, -0.55), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Metal })
				-- Front sight post (tall pin)
				add({ role = "sight", size = Vector3.new(0.025, 0.12, 0.025), offset = CFrame.new(0, 0.38, -0.55), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal })
				-- Front sight wings (left + right protectors)
				add({ role = "sight", size = Vector3.new(0.02, 0.1, 0.04), offset = CFrame.new(-0.05, 0.39, -0.55), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Metal })
				add({ role = "sight", size = Vector3.new(0.02, 0.1, 0.04), offset = CFrame.new(0.05, 0.39, -0.55), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Metal })

				-- COCKING ARM — fake left hand reaching for charging handle.
				-- Visible 0-70% of draw, fades to invisible by draw end via the
				-- cockingFade formula in WeaponController (isCockingArm flag).
				add({ role = "hand", size = Vector3.new(0.6, 0.22, 0.22),
					offset = CFrame.new(-0.18, 0.18, 0.05) * CFrame.Angles(0, math.rad(-100), 0),
					color = Color3.fromRGB(225, 190, 155), material = Enum.Material.SmoothPlastic,
					isCockingArm = true })

				return parts
			end)(),
		},
	},

	sniper = {
		id = "sniper",
		displayName = "AWP",
		tier = "Legendary",
		slot = "primary",
		damage = 115, -- CS AWP one-shot upper body
		fireRate = 1 / 0.5, -- 0.5s bolt cycle between shots (locks fire + scope)
		range = 800,
		magSize = 5,  -- CS2 AWP: 5 rounds per mag
		reloadTime = 3.5,
		drawTime = 1.0,
		headshotMultiplier = 2.5,
		falloffStart = 250,
		falloffEnd = 800,
		minDamageMul = 0.9,
		recoilVertical = 2.5,
		recoilHorizontal = 0.15,
		recoilRecoverSpeed = 2.5,
		isAuto = false,
		viewmodel = {
			grip = CFrame.new(0.55, -0.4, -2.1) * CFrame.Angles(0, rad(-2), 0),
			parts = (function(): { ViewmodelPart }
				local parts: { ViewmodelPart } = {}
				local function add(p: any) table.insert(parts, p) end

				-- ============================================================
				-- MAIN RECEIVER (matte black bolt-action body — Accuracy International AWM)
				-- ============================================================
				add({ role = "body", size = Vector3.new(0.2, 0.22, 0.72), offset = CFrame.new(0, 0, 0.1), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal })
				-- Receiver top rail (mount surface for scope)
				add({ role = "body", size = Vector3.new(0.18, 0.04, 0.72), offset = CFrame.new(0, 0.13, 0.1), color = Color3.fromRGB(20, 22, 30), material = Enum.Material.Metal })
				-- Picatinny rail slot cuts (8 transverse grooves)
				for i = 0, 7 do
					add({ role = "body", size = Vector3.new(0.19, 0.025, 0.018), offset = CFrame.new(0, 0.125, -0.18 + i * 0.07), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				end
				-- Receiver bottom (mag well housing extension)
				add({ role = "body", size = Vector3.new(0.22, 0.08, 0.4), offset = CFrame.new(0, -0.13, 0.05), color = Color3.fromRGB(25, 27, 35), material = Enum.Material.Metal })
				-- Receiver side panels (left + right plates with bolts visible)
				add({ role = "body", size = Vector3.new(0.04, 0.18, 0.7), offset = CFrame.new(-0.1, 0.0, 0.1), color = Color3.fromRGB(22, 24, 32), material = Enum.Material.Metal })
				add({ role = "body", size = Vector3.new(0.04, 0.18, 0.7), offset = CFrame.new(0.1, 0.0, 0.1), color = Color3.fromRGB(22, 24, 32), material = Enum.Material.Metal })
				-- Receiver bolts (4 visible socket-head bolts on left side)
				for i = 0, 3 do
					add({ role = "body", size = Vector3.new(0.025, 0.04, 0.04), offset = CFrame.new(-0.115, -0.05, -0.1 + i * 0.13), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })
				end
				-- Ejection port (large cutout)
				add({ role = "body", size = Vector3.new(0.04, 0.16, 0.32), offset = CFrame.new(0.115, 0.04, 0.0), color = Color3.fromRGB(5, 7, 10), material = Enum.Material.Metal })

				-- ============================================================
				-- BOLT (slide role — cycles on cocking)
				-- ============================================================
				-- Bolt body cylinder
				add({ role = "slide", size = Vector3.new(0.11, 0.11, 0.42), offset = CFrame.new(0.07, 0.16, 0), color = Color3.fromRGB(55, 60, 70), material = Enum.Material.Metal, shape = "cylinder" })
				-- Bolt handle stub (sticks right, perpendicular)
				add({ role = "slide", size = Vector3.new(0.18, 0.05, 0.1), offset = CFrame.new(0.13, 0.16, 0.12), color = Color3.fromRGB(70, 75, 85), material = Enum.Material.Metal })
				-- Bolt handle ball (round knob at end)
				add({ role = "slide", size = Vector3.new(0.08, 0.08, 0.08), offset = CFrame.new(0.2, 0.16, 0.12), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal, shape = "ball" })
				-- Bolt face / extractor (visible at end of bolt body)
				add({ role = "slide", size = Vector3.new(0.04, 0.08, 0.03), offset = CFrame.new(0.07, 0.13, -0.21), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal })
				-- Bolt body grooves (3 longitudinal grip flutes)
				for i = 0, 2 do
					add({ role = "slide", size = Vector3.new(0.02, 0.02, 0.4), offset = CFrame.new(0.07 + (i-1)*0.05, 0.22, 0), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal })
				end

				-- ============================================================
				-- BARREL (long heavy AI-style sniper barrel)
				-- ============================================================
				-- Main barrel
				add({ role = "barrel", size = Vector3.new(0.12, 0.12, 1.3), offset = CFrame.new(0, 0.04, -0.95), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Metal, shape = "cylinder" })
				-- Barrel collar at chamber (thicker reinforcement near receiver)
				add({ role = "barrel", size = Vector3.new(0.16, 0.16, 0.12), offset = CFrame.new(0, 0.04, -0.36), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal })
				-- Barrel barrel mid-cooling fins (3 thin ridges along barrel — heat dissipation look)
				for i = 0, 2 do
					add({ role = "barrel", size = Vector3.new(0.14, 0.14, 0.02), offset = CFrame.new(0, 0.04, -0.6 - i * 0.22), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal })
				end
				-- Barrel taper toward muzzle
				add({ role = "barrel", size = Vector3.new(0.1, 0.1, 0.35), offset = CFrame.new(0, 0.04, -1.78), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Metal, shape = "cylinder" })
				-- Muzzle brake body
				add({ role = "barrel", size = Vector3.new(0.17, 0.17, 0.18), offset = CFrame.new(0, 0.04, -2.05), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal })
				-- Muzzle brake top slot
				add({ role = "barrel", size = Vector3.new(0.18, 0.04, 0.04), offset = CFrame.new(0, 0.13, -2.02), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				add({ role = "barrel", size = Vector3.new(0.18, 0.04, 0.04), offset = CFrame.new(0, 0.13, -2.08), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				-- Muzzle brake side slots (left)
				add({ role = "barrel", size = Vector3.new(0.04, 0.18, 0.04), offset = CFrame.new(-0.09, 0.04, -2.02), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				add({ role = "barrel", size = Vector3.new(0.04, 0.18, 0.04), offset = CFrame.new(-0.09, 0.04, -2.08), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				-- Muzzle brake side slots (right)
				add({ role = "barrel", size = Vector3.new(0.04, 0.18, 0.04), offset = CFrame.new(0.09, 0.04, -2.02), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				add({ role = "barrel", size = Vector3.new(0.04, 0.18, 0.04), offset = CFrame.new(0.09, 0.04, -2.08), color = Color3.fromRGB(8, 10, 14), material = Enum.Material.Metal })
				-- Muzzle crown
				add({ role = "barrel", size = Vector3.new(0.13, 0.13, 0.02), offset = CFrame.new(0, 0.04, -2.15), color = Color3.fromRGB(25, 27, 35), material = Enum.Material.Metal })
				-- Muzzle hole (dark)
				add({ role = "barrel", size = Vector3.new(0.06, 0.06, 0.02), offset = CFrame.new(0, 0.04, -2.16), color = Color3.fromRGB(5, 7, 10), material = Enum.Material.Metal })

				-- ============================================================
				-- SCOPE — Schmidt & Bender style high-power tactical scope
				-- ============================================================
				-- Scope main tube (segments for thickness variation along length)
				add({ role = "sight", size = Vector3.new(0.18, 0.22, 0.7), offset = CFrame.new(0, 0.32, -0.1), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Metal, shape = "cylinder" })
				-- Scope front objective bell (larger lens housing)
				add({ role = "sight", size = Vector3.new(0.28, 0.32, 0.18), offset = CFrame.new(0, 0.32, -0.52), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal })
				-- Front bell stepped collars (2 rings approximating curved transition)
				add({ role = "sight", size = Vector3.new(0.25, 0.29, 0.04), offset = CFrame.new(0, 0.32, -0.43), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Metal })
				add({ role = "sight", size = Vector3.new(0.22, 0.26, 0.04), offset = CFrame.new(0, 0.32, -0.4), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Metal })
				-- Front lens (glass with blue tint)
				add({ role = "sight", size = Vector3.new(0.24, 0.28, 0.02), offset = CFrame.new(0, 0.32, -0.62), color = Color3.fromRGB(80, 130, 180), material = Enum.Material.Glass })
				-- Front lens outer rim
				add({ role = "sight", size = Vector3.new(0.28, 0.32, 0.02), offset = CFrame.new(0, 0.32, -0.61), color = Color3.fromRGB(10, 12, 16), material = Enum.Material.Metal })
				-- Front sunshade (extends forward of front bell)
				add({ role = "sight", size = Vector3.new(0.22, 0.26, 0.18), offset = CFrame.new(0, 0.32, -0.7), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Metal })
				-- Scope rear bell (eyepiece housing)
				add({ role = "sight", size = Vector3.new(0.2, 0.24, 0.14), offset = CFrame.new(0, 0.32, 0.22), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal })
				-- Rear lens (smaller, darker tint)
				add({ role = "sight", size = Vector3.new(0.16, 0.18, 0.02), offset = CFrame.new(0, 0.32, 0.3), color = Color3.fromRGB(30, 50, 80), material = Enum.Material.Glass })
				-- Eyepiece rubber cup
				add({ role = "sight", size = Vector3.new(0.18, 0.22, 0.05), offset = CFrame.new(0, 0.32, 0.32), color = Color3.fromRGB(20, 22, 28), material = Enum.Material.Plastic })
				-- Elevation turret (top knob)
				add({ role = "sight", size = Vector3.new(0.09, 0.12, 0.11), offset = CFrame.new(0, 0.5, -0.05), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal })
				-- Elevation turret cap
				add({ role = "sight", size = Vector3.new(0.075, 0.04, 0.09), offset = CFrame.new(0, 0.58, -0.05), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal })
				-- Elevation turret tick marks (4 small notches)
				for i = 0, 3 do
					add({ role = "sight", size = Vector3.new(0.1, 0.015, 0.012), offset = CFrame.new(0, 0.47 + i * 0.02, -0.05), color = Color3.fromRGB(220, 220, 220), material = Enum.Material.Metal })
				end
				-- Windage turret (right side)
				add({ role = "sight", size = Vector3.new(0.11, 0.09, 0.11), offset = CFrame.new(0.14, 0.32, -0.05), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal })
				-- Windage turret cap
				add({ role = "sight", size = Vector3.new(0.04, 0.075, 0.09), offset = CFrame.new(0.21, 0.32, -0.05), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal })
				-- Parallax adjustment (left side knob)
				add({ role = "sight", size = Vector3.new(0.04, 0.09, 0.11), offset = CFrame.new(-0.13, 0.32, -0.05), color = Color3.fromRGB(35, 38, 46), material = Enum.Material.Metal })
				-- Zoom ring (between rear bell and main tube)
				add({ role = "sight", size = Vector3.new(0.2, 0.24, 0.08), offset = CFrame.new(0, 0.32, 0.12), color = Color3.fromRGB(25, 27, 35), material = Enum.Material.Metal })
				-- Zoom ring grip pattern (4 small ribs)
				for i = 0, 3 do
					add({ role = "sight", size = Vector3.new(0.22, 0.012, 0.012), offset = CFrame.new(0, 0.42, 0.1 + i * 0.012), color = Color3.fromRGB(15, 17, 22), material = Enum.Material.Metal })
				end
				-- Scope mount rings (front + rear)
				add({ role = "sight", size = Vector3.new(0.16, 0.06, 0.08), offset = CFrame.new(0, 0.18, -0.3), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal })
				add({ role = "sight", size = Vector3.new(0.16, 0.06, 0.08), offset = CFrame.new(0, 0.18, 0.1), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal })
				-- Scope mount ring bolts (2 visible per ring)
				add({ role = "sight", size = Vector3.new(0.04, 0.025, 0.04), offset = CFrame.new(-0.06, 0.16, -0.3), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })
				add({ role = "sight", size = Vector3.new(0.04, 0.025, 0.04), offset = CFrame.new(0.06, 0.16, -0.3), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })
				add({ role = "sight", size = Vector3.new(0.04, 0.025, 0.04), offset = CFrame.new(-0.06, 0.16, 0.1), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })
				add({ role = "sight", size = Vector3.new(0.04, 0.025, 0.04), offset = CFrame.new(0.06, 0.16, 0.1), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })

				-- ============================================================
				-- MAGAZINE (10-round .338 box mag)
				-- ============================================================
				add({ role = "mag", size = Vector3.new(0.18, 0.2, 0.16), offset = CFrame.new(0, -0.26, 0.1), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal })
				-- Mag floor plate
				add({ role = "mag", size = Vector3.new(0.2, 0.035, 0.18), offset = CFrame.new(0, -0.37, 0.1), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal })
				-- Mag witness holes (4 sequential)
				for i = 0, 3 do
					add({ role = "mag", size = Vector3.new(0.19, 0.02, 0.04), offset = CFrame.new(0, -0.2 - i * 0.04, 0.13), color = Color3.fromRGB(80, 85, 95), material = Enum.Material.Metal })
				end

				-- ============================================================
				-- STOCK (Accuracy International AI green polymer thumbhole)
				-- ============================================================
				-- Main stock body
				add({ role = "stock", size = Vector3.new(0.22, 0.18, 1.0), offset = CFrame.new(0, -0.05, 0.95), color = Color3.fromRGB(55, 65, 50), material = Enum.Material.Plastic })
				-- Stock comb (raised top for cheek weld)
				add({ role = "stock", size = Vector3.new(0.2, 0.1, 0.7), offset = CFrame.new(0, 0.08, 0.85), color = Color3.fromRGB(50, 60, 45), material = Enum.Material.Plastic })
				-- Cheek riser (taller, adjustable look)
				add({ role = "stock", size = Vector3.new(0.22, 0.06, 0.45), offset = CFrame.new(0, 0.16, 0.75), color = Color3.fromRGB(45, 55, 40), material = Enum.Material.Plastic })
				-- Cheek riser height adjustment knob
				add({ role = "stock", size = Vector3.new(0.05, 0.06, 0.06), offset = CFrame.new(0, 0.2, 0.55), color = Color3.fromRGB(35, 45, 30), material = Enum.Material.Metal })
				-- Stock thumbhole cutout (decorative dark slot)
				add({ role = "stock", size = Vector3.new(0.18, 0.16, 0.12), offset = CFrame.new(0, -0.05, 0.45), color = Color3.fromRGB(20, 24, 18), material = Enum.Material.Plastic })
				-- Recoil pad (rubber at very end)
				add({ role = "stock", size = Vector3.new(0.24, 0.34, 0.06), offset = CFrame.new(0, -0.03, 1.48), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Plastic })
				-- Recoil pad ridges (4 horizontal grip lines)
				for i = 0, 3 do
					add({ role = "stock", size = Vector3.new(0.24, 0.015, 0.02), offset = CFrame.new(0, 0.1 - i * 0.06, 1.5), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Plastic })
				end
				-- Sling swivel rear
				add({ role = "stock", size = Vector3.new(0.04, 0.05, 0.06), offset = CFrame.new(0.11, -0.16, 0.95), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })
				-- Sling swivel front (under forend)
				add({ role = "stock", size = Vector3.new(0.04, 0.05, 0.06), offset = CFrame.new(0, -0.1, -0.4), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })
				-- Stock bottom rail (Anschutz-style)
				add({ role = "stock", size = Vector3.new(0.04, 0.05, 0.32), offset = CFrame.new(0, -0.16, 1.1), color = Color3.fromRGB(35, 45, 30), material = Enum.Material.Metal })

				-- ============================================================
				-- PISTOL GRIP (integrated into thumbhole stock)
				-- ============================================================
				add({ role = "grip", size = Vector3.new(0.18, 0.34, 0.22), offset = CFrame.new(0, -0.2, 0.42) * CFrame.Angles(rad(-12), 0, 0), color = Color3.fromRGB(50, 60, 45), material = Enum.Material.Plastic })
				-- Grip stippling pattern (6 horizontal ridges)
				for i = 0, 5 do
					add({ role = "grip", size = Vector3.new(0.19, 0.02, 0.02), offset = CFrame.new(0, -0.1 - i * 0.06, 0.36) * CFrame.Angles(rad(-12), 0, 0), color = Color3.fromRGB(35, 45, 30), material = Enum.Material.Plastic })
				end
				-- Grip cap (palm rest)
				add({ role = "grip", size = Vector3.new(0.17, 0.03, 0.2), offset = CFrame.new(0, -0.37, 0.5) * CFrame.Angles(rad(-12), 0, 0), color = Color3.fromRGB(35, 45, 30), material = Enum.Material.Plastic })

				-- ============================================================
				-- TRIGGER ASSEMBLY
				-- ============================================================
				-- Trigger blade
				add({ role = "body", size = Vector3.new(0.04, 0.1, 0.04), offset = CFrame.new(0, -0.14, 0.2), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal })
				-- Trigger guard top
				add({ role = "body", size = Vector3.new(0.06, 0.04, 0.2), offset = CFrame.new(0, -0.08, 0.2), color = Color3.fromRGB(25, 27, 35), material = Enum.Material.Metal })
				-- Trigger guard bottom
				add({ role = "body", size = Vector3.new(0.06, 0.04, 0.2), offset = CFrame.new(0, -0.22, 0.2), color = Color3.fromRGB(25, 27, 35), material = Enum.Material.Metal })
				-- Trigger guard front strut
				add({ role = "body", size = Vector3.new(0.06, 0.14, 0.04), offset = CFrame.new(0, -0.15, 0.12), color = Color3.fromRGB(25, 27, 35), material = Enum.Material.Metal })
				-- Trigger guard rear strut
				add({ role = "body", size = Vector3.new(0.06, 0.14, 0.04), offset = CFrame.new(0, -0.15, 0.28), color = Color3.fromRGB(25, 27, 35), material = Enum.Material.Metal })
				-- Safety lever (rear of receiver, behind bolt)
				add({ role = "body", size = Vector3.new(0.04, 0.05, 0.06), offset = CFrame.new(0.12, 0.0, 0.4), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })

				-- ============================================================
				-- BIPOD (folded forward under barrel)
				-- ============================================================
				-- Bipod mount
				add({ role = "barrel", size = Vector3.new(0.1, 0.06, 0.08), offset = CFrame.new(0, -0.04, -1.4), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Metal })
				-- Bipod left leg (angled out + down)
				add({ role = "barrel", size = Vector3.new(0.025, 0.04, 0.45), offset = CFrame.new(-0.06, -0.08, -1.35) * CFrame.Angles(0, 0, rad(20)), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal })
				-- Bipod right leg
				add({ role = "barrel", size = Vector3.new(0.025, 0.04, 0.45), offset = CFrame.new(0.06, -0.08, -1.35) * CFrame.Angles(0, 0, rad(-20)), color = Color3.fromRGB(30, 32, 40), material = Enum.Material.Metal })
				-- Bipod feet (small pads at end of each leg)
				add({ role = "barrel", size = Vector3.new(0.04, 0.03, 0.04), offset = CFrame.new(-0.13, -0.28, -1.35), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Plastic })
				add({ role = "barrel", size = Vector3.new(0.04, 0.03, 0.04), offset = CFrame.new(0.13, -0.28, -1.35), color = Color3.fromRGB(18, 20, 26), material = Enum.Material.Plastic })
				-- Bipod pivot bolt (visible hex bolt at center mount)
				add({ role = "barrel", size = Vector3.new(0.04, 0.04, 0.04), offset = CFrame.new(0, -0.08, -1.4), color = Color3.fromRGB(50, 55, 65), material = Enum.Material.Metal })

				-- COCKING ARM — fake left hand reaching for bolt handle (right side
				-- of receiver). Fades out by end of draw via isCockingArm flag.
				add({ role = "hand", size = Vector3.new(0.55, 0.22, 0.22),
					offset = CFrame.new(0.05, 0.18, 0.12) * CFrame.Angles(0, math.rad(-90), math.rad(-20)),
					color = Color3.fromRGB(225, 190, 155), material = Enum.Material.SmoothPlastic,
					isCockingArm = true })

				return parts
			end)(),
		},
	},

	knife = {
		id = "knife",
		displayName = "Combat Knife",
		tier = "Common",
		slot = "melee",
		damage = 60,         -- body/head front = 60 (2-hit kill); backstab = 120 (1-hit) handled in WeaponService
		fireRate = 1 / 0.3,  -- left-click slash cooldown 0.3s (right-click stab has separate 0.6s)
		range = 7,           -- melee reach in studs
		magSize = 0,         -- no ammo
		reloadTime = 0,
		drawTime = 0.7,      -- 0.7s pullout/draw animation — can't attack until fully drawn
		headshotMultiplier = 1, -- knife head = body (no headshot bonus; backstab is the 1-hit mechanic)
		falloffStart = 0,
		falloffEnd = 7,
		minDamageMul = 1,    -- no falloff for melee
		recoilVertical = 0,
		recoilHorizontal = 0,
		recoilRecoverSpeed = 5,
		isAuto = false,
		viewmodel = {
			-- POSITION sama (Y -0.5), arah DIATASIN lagi (pitch +25°) + DIKANANIN (yaw -45°)
			grip = CFrame.new(0.55, -0.5, -1.6) * CFrame.Angles(rad(25), rad(-45), 0),
			-- REGULAR KNIFE (straight blade) — default shape when player doesn't own karambit skin.
			parts = {
				-- === RIGHT ARM (holds the knife) ===
				{ role = "stock",
					size = Vector3.new(0.95, 0.35, 0.35),
					offset = CFrame.new(0.4, -0.3, -0.05),
					color = Color3.fromRGB(225, 190, 155),
					material = Enum.Material.SmoothPlastic },

				-- === LEFT ARM (relaxed off-hand from body) ===
				{ role = "stock",
					size = Vector3.new(0.55, 0.35, 0.35),
					offset = (CFrame.new(0.55, -0.5, -1.6) * CFrame.Angles(rad(25), rad(-45), 0)):Inverse()
						* (CFrame.new(-0.5, -0.85, -1.0) * CFrame.Angles(rad(-30), rad(-20), rad(10)))
						* CFrame.new(0.25, 0, 0),
					color = Color3.fromRGB(225, 190, 155),
					material = Enum.Material.SmoothPlastic },

				-- === HANDLE (cylinder smooth grip) ===
				{ role = "body",
					size = Vector3.new(0.45, 0.18, 0.18),
					offset = CFrame.new(-0.25, -0.25, -0.05),
					color = Color3.fromRGB(35, 35, 40),
					material = Enum.Material.SmoothPlastic,
					shape = "cylinder" },
				-- Pommel cap (small rounded end)
				{ role = "body",
					size = Vector3.new(0.08, 0.22, 0.22),
					offset = CFrame.new(-0.02, -0.25, -0.05),
					color = Color3.fromRGB(50, 50, 60),
					material = Enum.Material.Metal,
					shape = "ball" },

				-- === CROSS-GUARD ===
				{ role = "body",
					size = Vector3.new(0.06, 0.28, 0.1),
					offset = CFrame.new(-0.5, -0.25, -0.05),
					color = Color3.fromRGB(60, 65, 75),
					material = Enum.Material.Metal },

				-- === BLADE (straight) ===
				{ role = "barrel",
					size = Vector3.new(0.65, 0.18, 0.05),
					offset = CFrame.new(-0.85, -0.25, -0.05),
					color = Color3.fromRGB(200, 210, 220),
					material = Enum.Material.SmoothPlastic },
				-- Blade edge highlight
				{ role = "barrel",
					size = Vector3.new(0.65, 0.04, 0.05),
					offset = CFrame.new(-0.85, -0.33, -0.05),
					color = Color3.fromRGB(245, 248, 252),
					material = Enum.Material.SmoothPlastic },
				-- Blade groove
				{ role = "barrel",
					size = Vector3.new(0.55, 0.04, 0.06),
					offset = CFrame.new(-0.83, -0.23, -0.05),
					color = Color3.fromRGB(120, 130, 145),
					material = Enum.Material.SmoothPlastic },
				-- Blade TIP (wedge)
				{ role = "barrel",
					size = Vector3.new(0.18, 0.18, 0.05),
					offset = CFrame.new(-1.27, -0.25, -0.05),
					color = Color3.fromRGB(220, 230, 240),
					material = Enum.Material.SmoothPlastic,
					shape = "wedge" },
			},
		},
		-- KARAMBIT viewmodel — arm parts use `grip` (matches default knife arm positions),
		-- blade body parts use `bladeGrip` (final user-tuned orientation via HUD).
		viewmodelKarambit = {
			grip = CFrame.new(0.55, -0.5, -1.6) * CFrame.Angles(rad(25), rad(-45), 0),
			bladeGrip = CFrame.new(0.83, -0.68, -1.47) * CFrame.Angles(rad(101.08), rad(180), rad(15.23)),
			parts = (function(): { ViewmodelPart }
				local parts: { ViewmodelPart } = {}
				local function add(p: any)
					table.insert(parts, p)
				end

				-- Right arm
				add({ role = "stock",
					size = Vector3.new(0.95, 0.35, 0.35),
					offset = CFrame.new(0.4, -0.3, -0.05),
					color = Color3.fromRGB(225, 190, 155),
					material = Enum.Material.SmoothPlastic })

				-- Left arm
				add({ role = "stock",
					size = Vector3.new(0.55, 0.35, 0.35),
					offset = (CFrame.new(0.55, -0.5, -1.6) * CFrame.Angles(rad(25), rad(-45), 0)):Inverse()
						* (CFrame.new(-0.5, -0.85, -1.0) * CFrame.Angles(rad(-30), rad(-20), rad(10)))
						* CFrame.new(0.25, 0, 0),
					color = Color3.fromRGB(225, 190, 155),
					material = Enum.Material.SmoothPlastic })

				-- Handle (shorter cylinder)
				add({ role = "body",
					size = Vector3.new(0.32, 0.16, 0.16),
					offset = CFrame.new(-0.18, -0.25, -0.05),
					color = Color3.fromRGB(35, 35, 40),
					material = Enum.Material.SmoothPlastic,
					shape = "cylinder" })

				-- Grip wraps (3 traction rings, fewer because handle is shorter)
				for _, wrapX in { -0.27, -0.18, -0.09 } do
					add({ role = "body",
						size = Vector3.new(0.024, 0.18, 0.18),
						offset = CFrame.new(wrapX, -0.25, -0.05),
						color = Color3.fromRGB(18, 18, 22),
						material = Enum.Material.SmoothPlastic,
						shape = "cylinder" })
				end

				-- Cross-guard (smaller)
				add({ role = "body",
					size = Vector3.new(0.05, 0.25, 0.11),
					offset = CFrame.new(-0.35, -0.25, -0.05),
					color = Color3.fromRGB(60, 65, 75),
					material = Enum.Material.Metal })
				-- Lower finger nub (BELOW cross-guard, with blade-down arc orientation)
				add({ role = "body",
					size = Vector3.new(0.04, 0.11, 0.08),
					offset = CFrame.new(-0.35, -0.45, -0.05),
					color = Color3.fromRGB(60, 65, 75),
					material = Enum.Material.Metal })

				-- Hawkbill blade arc: center BELOW handle, blade curves DOWN-FORWARD.
				-- With grip pitch +90°, part -Y axis maps to camera -Z (forward into screen).
				-- 16 segments, 80° CCW sweep.
				local CX, CY, CZ = -0.35, -0.6, -0.05
				local R_MAIN = 0.35
				local SEG = 16
				local A_START = rad(90)   -- top of arc (at cross-guard level)
				local A_END = rad(170)    -- lower-left, where tip is
				local A_STEP = (A_END - A_START) / SEG  -- POSITIVE → CCW sweep

				-- Main blade body
				for i = 0, SEG - 1 do
					local midA = A_START + A_STEP * (i + 0.5)
					local x = CX + R_MAIN * math.cos(midA)
					local y = CY + R_MAIN * math.sin(midA)
					local chord = math.abs(2 * R_MAIN * math.sin(A_STEP / 2))
					add({ role = "barrel",
						size = Vector3.new(chord + 0.003, 0.18, 0.045),
						offset = CFrame.new(x, y, CZ) * CFrame.Angles(0, 0, midA - math.pi / 2),
						color = Color3.fromRGB(200, 210, 220),
						material = Enum.Material.SmoothPlastic })
				end

				-- Cutting edge highlight (inner concave side = closer to arc center = UP for flipped)
				local R_EDGE = R_MAIN - 0.07
				for i = 0, SEG - 1 do
					local midA = A_START + A_STEP * (i + 0.5)
					local x = CX + R_EDGE * math.cos(midA)
					local y = CY + R_EDGE * math.sin(midA)
					local chord = math.abs(2 * R_EDGE * math.sin(A_STEP / 2))
					add({ role = "barrel",
						size = Vector3.new(chord + 0.003, 0.025, 0.05),
						offset = CFrame.new(x, y, CZ) * CFrame.Angles(0, 0, midA - math.pi / 2),
						color = Color3.fromRGB(245, 248, 252),
						material = Enum.Material.SmoothPlastic })
				end

				-- Spine ridge (outer convex side = away from center = DOWN for flipped)
				local R_SPINE = R_MAIN + 0.065
				for i = 0, SEG - 1 do
					local midA = A_START + A_STEP * (i + 0.5)
					local x = CX + R_SPINE * math.cos(midA)
					local y = CY + R_SPINE * math.sin(midA)
					local chord = math.abs(2 * R_SPINE * math.sin(A_STEP / 2))
					add({ role = "barrel",
						size = Vector3.new(chord + 0.003, 0.03, 0.04),
						offset = CFrame.new(x, y, CZ) * CFrame.Angles(0, 0, midA - math.pi / 2),
						color = Color3.fromRGB(115, 125, 140),
						material = Enum.Material.SmoothPlastic })
				end

				-- Blade tip — SINGLE triangular wedge (clean triangle, not boxy stair-step).
				-- Wedge is positioned so its center is half-length past the arc end, so the
				-- triangular slant tapers FROM the blade body TO a sharp point along the tangent.
				local TIP_A = A_END
				local tangentAngle = TIP_A + math.pi / 2  -- CCW arc tangent
				local arcEndX = CX + R_MAIN * math.cos(TIP_A)
				local arcEndY = CY + R_MAIN * math.sin(TIP_A)
				local TIP_LEN = 0.22
				local extX, extY = math.cos(tangentAngle), math.sin(tangentAngle)
				-- Center the wedge so its back edge meets the arc end, tip extends forward
				local tipCenterX = arcEndX + extX * (TIP_LEN / 2)
				local tipCenterY = arcEndY + extY * (TIP_LEN / 2)
				add({ role = "barrel",
					size = Vector3.new(TIP_LEN, 0.18, 0.045), -- length, height, thickness
					offset = CFrame.new(tipCenterX, tipCenterY, CZ) * CFrame.Angles(0, 0, tangentAngle),
					color = Color3.fromRGB(220, 230, 240),
					material = Enum.Material.SmoothPlastic,
					shape = "wedge" })

				-- Finger ring (12-segment circle, smaller radius)
				local RING_CX, RING_CY, RING_CZ = 0.10, -0.25, -0.05
				local R_RING = 0.13
				local RING_SEG = 12
				local RING_STEP = (2 * math.pi) / RING_SEG

				for i = 0, RING_SEG - 1 do
					local midA = RING_STEP * (i + 0.5)
					local x = RING_CX + R_RING * math.cos(midA)
					local y = RING_CY + R_RING * math.sin(midA)
					local chord = 2 * R_RING * math.sin(RING_STEP / 2)
					add({ role = "body",
						size = Vector3.new(chord + 0.003, 0.06, 0.06),
						offset = CFrame.new(x, y, RING_CZ) * CFrame.Angles(0, 0, midA - math.pi / 2),
						color = Color3.fromRGB(35, 35, 40),
						material = Enum.Material.SmoothPlastic })
				end

				-- ============================================================
				-- DOTS (role = "stardot") — 4 small dots ATTACHED to the blade arc surface.
				-- Visible only when equipped skin has accentColor (e.g., Marble Fade = 4 yellow dots).
				-- Positions sampled along the blade arc so dots sit ON the blade, not floating.
				-- ============================================================
				local dotAngles = { rad(105), rad(125), rad(145), rad(165) }
				for _, ang in dotAngles do
					local dx = CX + R_MAIN * math.cos(ang)
					local dy = CY + R_MAIN * math.sin(ang)
					add({ role = "stardot",
						size = Vector3.new(0.04, 0.04, 0.015),
						offset = CFrame.new(dx, dy, CZ + 0.025), -- slightly in front of blade surface
						color = Color3.fromRGB(255, 255, 255),
						material = Enum.Material.Neon })
				end

				return parts
			end)(),
		},
		-- M9 BAYONET viewmodel — straight long blade with clip point + partial
		-- serration near hilt + signature wire-cutter hole near tip. Uses the
		-- same `grip` CFrame as the default combat knife since both are held
		-- the same way (straight knife, edge down). Activated when the player's
		-- equipped skin_knife cosmetic has `isM9 = true`.
		viewmodelM9 = {
			-- `grip` = arm/hand basis (kept constant; matches combat knife arm pose).
			grip = CFrame.new(0.55, -0.5, -1.6) * CFrame.Angles(rad(25), rad(-45), 0),
			-- bladeGrip stored as DECOMPOSED components so the pullout animation
			-- can lerp the X rotation independently (around camera-horizontal axis
			-- → true vertical swing). Order applied per frame:
			--   CFrame.new(pos) * CFrame.Angles(rx, 0, 0) * CFrame.Angles(0, ry, rz)
			-- Mathematically identical to CFrame.new(pos) * CFrame.Angles(rx, ry, rz)
			-- when rx is at rest value.
			bladeGripPos = Vector3.new(0.72, -0.67, -1.45),
			bladeGripRX = rad(21),    -- rest X pitch (knife held in ready pose)
			bladeGripRY = rad(-60),
			bladeGripRZ = rad(-66),
			parts = (function(): { ViewmodelPart }
				local parts: { ViewmodelPart } = {}
				local function add(p: any)
					table.insert(parts, p)
				end

				-- Color palette (M9 vanilla — raw steel + black grip)
				local SKIN_TONE   = Color3.fromRGB(225, 190, 155)
				local BLACK_GRIP  = Color3.fromRGB(25, 25, 28)
				local GRIP_DARK   = Color3.fromRGB(15, 15, 18)
				local METAL_DARK  = Color3.fromRGB(60, 65, 75)
				local METAL_MID   = Color3.fromRGB(85, 90, 100)
				local BLADE_STEEL = Color3.fromRGB(195, 200, 210)
				local BLADE_EDGE  = Color3.fromRGB(240, 245, 250)
				local GROOVE_DARK = Color3.fromRGB(110, 120, 135)
				local HOLE_BLACK  = Color3.fromRGB(5, 5, 8)

				-- Coordinate convention (matches combat knife):
				-- -X = forward (blade tip), +X = back (pommel)
				-- Y vertical, Z lateral (small offset for thickness)

				-- === RIGHT ARM (holds the knife) ===
				add({ role = "stock",
					size = Vector3.new(0.95, 0.35, 0.35),
					offset = CFrame.new(0.4, -0.3, -0.05),
					color = SKIN_TONE,
					material = Enum.Material.SmoothPlastic })

				-- === LEFT ARM (relaxed off-hand) — same expression as combat knife
				add({ role = "stock",
					size = Vector3.new(0.55, 0.35, 0.35),
					offset = (CFrame.new(0.55, -0.5, -1.6) * CFrame.Angles(rad(25), rad(-45), 0)):Inverse()
						* (CFrame.new(-0.5, -0.85, -1.0) * CFrame.Angles(rad(-30), rad(-20), rad(10)))
						* CFrame.new(0.25, 0, 0),
					color = SKIN_TONE,
					material = Enum.Material.SmoothPlastic })

				-- === HANDLE — longer than combat (0.50 vs 0.45), black polymer cylinder
				add({ role = "body",
					size = Vector3.new(0.50, 0.20, 0.20),
					offset = CFrame.new(-0.20, -0.25, -0.05),
					color = BLACK_GRIP,
					material = Enum.Material.SmoothPlastic,
					shape = "cylinder" })
				-- Grip wraps (3 tactile rings around handle for texture)
				for _, x in { -0.05, -0.20, -0.35 } do
					add({ role = "body",
						size = Vector3.new(0.024, 0.215, 0.215),
						offset = CFrame.new(x, -0.25, -0.05),
						color = GRIP_DARK,
						material = Enum.Material.SmoothPlastic,
						shape = "cylinder" })
				end
				-- Pommel cap (small ball at back end of handle)
				add({ role = "body",
					size = Vector3.new(0.10, 0.22, 0.22),
					offset = CFrame.new(0.08, -0.25, -0.05),
					color = METAL_DARK,
					material = Enum.Material.Metal,
					shape = "ball" })

				-- === CROSS-GUARD (wider than combat, with thumb ramp on top)
				add({ role = "body",
					size = Vector3.new(0.08, 0.36, 0.13),
					offset = CFrame.new(-0.49, -0.25, -0.05),
					color = METAL_DARK,
					material = Enum.Material.Metal })
				-- Thumb ramp (small bump on top of crossguard, signature M9 detail)
				add({ role = "body",
					size = Vector3.new(0.10, 0.06, 0.08),
					offset = CFrame.new(-0.54, -0.10, -0.05),
					color = METAL_MID,
					material = Enum.Material.Metal })

				-- === MAIN BLADE — long (0.85 vs combat 0.65), wider (0.22 vs 0.18)
				add({ role = "barrel",
					size = Vector3.new(0.85, 0.22, 0.05),
					offset = CFrame.new(-0.97, -0.25, -0.05),
					color = BLADE_STEEL,
					material = Enum.Material.Metal })
				-- Cutting edge highlight (along the bottom edge of the blade)
				add({ role = "barrel",
					size = Vector3.new(0.85, 0.04, 0.05),
					offset = CFrame.new(-0.97, -0.35, -0.05),
					color = BLADE_EDGE,
					material = Enum.Material.Metal })
				-- Blood groove / fuller (long darker channel down blade center)
				add({ role = "barrel",
					size = Vector3.new(0.60, 0.05, 0.06),
					offset = CFrame.new(-0.92, -0.25, -0.05),
					color = GROOVE_DARK,
					material = Enum.Material.Metal })

				-- === SERRATIONS — 6 small bumps on the SPINE (top edge), only on
				-- the half closest to the handle. Real M9 has saw teeth near hilt,
				-- smooth back half for piercing.
				for i = 0, 5 do
					local x = -0.62 - i * 0.06  -- runs from x=-0.62 (near crossguard) toward x=-0.92
					add({ role = "barrel",
						size = Vector3.new(0.04, 0.06, 0.06),
						offset = CFrame.new(x, -0.13, -0.05),
						color = BLADE_STEEL,
						material = Enum.Material.Metal })
				end

				-- === WIRE-CUTTING HOLE — signature M9 detail (small dark notch
				-- near the tip, where wire-cutter pin would sit)
				add({ role = "body",
					size = Vector3.new(0.07, 0.07, 0.07),
					offset = CFrame.new(-1.28, -0.22, -0.05),
					color = HOLE_BLACK,
					material = Enum.Material.Metal })

				-- === CLIP-POINT TIP — asymmetric wedge tapering toward the point
				add({ role = "barrel",
					size = Vector3.new(0.20, 0.20, 0.05),
					offset = CFrame.new(-1.46, -0.27, -0.05),
					color = BLADE_STEEL,
					material = Enum.Material.Metal,
					shape = "wedge" })

				return parts
			end)(),
		},
		-- STILETTO viewmodel — boxy switchblade with PULLOUT slide animation.
		-- Final held pose (baked from in-game tuner values):
		--   • HANDLE (brown): translated +0.5 stud in X, rotated -60° around Z
		--   • BLADE (silver): translated (+0.25, +0.40, 0) stud, rotated -60° around Z
		-- On draw, the blade STARTS at the handle's position (visually tucked
		-- inside the handle) and LERPS upward/forward to its rest pose over
		-- `bladePullDuration` seconds with ease-out. KLIK sound plays exactly
		-- when the blade locks into the final pose.
		-- Activated when the player's equipped skin_knife cosmetic has
		-- `isStiletto = true`.
		--
		-- Animation contract (read by WeaponController render loop):
		--   • Parts with role == "barrel" (the blade) lerp from
		--     `bladePullStartOffset` → `info.config.offset` over `bladePullDuration`.
		--   • Parts with role == "body" (the handle) are static at their offset.
		--   • Stock role = arms (untouched, same as M9/combat).
		viewmodelStiletto = {
			-- M9-style grip — knife held horizontally, edge down. Same pose
			-- as M9 Bayonet per user "berdiri kayak m9" request — no Z-axis
			-- tilt, blade extends forward from handle naturally.
			grip = CFrame.new(0.55, -0.5, -1.6) * CFrame.Angles(rad(25), rad(-45), 0),
			-- Pullout start: blade tucked inside the handle (sharing handle's
			-- offset). During the pullout window the render loop lerps the
			-- blade forward to its rest offset → visible "slides out the front
			-- of the handle" effect. KLIK plays the instant the blade locks
			-- into the forward position.
			bladePullStartOffset = CFrame.new(-0.25, -0.25, -0.05),
			bladePullDuration = 0.35,
			parts = (function(): { ViewmodelPart }
				local parts: { ViewmodelPart } = {}
				local function add(p: any)
					table.insert(parts, p)
				end

				-- Color palette
				local SKIN_TONE   = Color3.fromRGB(225, 190, 155)
				local HANDLE_BROWN = Color3.fromRGB(95, 60, 30)
				local HANDLE_DARK  = Color3.fromRGB(60, 38, 18)
				local BLADE_SILVER = Color3.fromRGB(210, 220, 230)

				-- Coordinate convention (matches combat/M9 knife):
				-- -X = forward (blade tip), +X = back (pommel)
				-- Y vertical, Z lateral. NO Z-axis rotation — knife held flat/horizontal
				-- in the M9 pose.

				-- === RIGHT ARM ===
				add({ role = "stock",
					size = Vector3.new(0.95, 0.35, 0.35),
					offset = CFrame.new(0.4, -0.3, -0.05),
					color = SKIN_TONE,
					material = Enum.Material.SmoothPlastic })

				-- === LEFT ARM (same off-hand pose as combat/M9) ===
				add({ role = "stock",
					size = Vector3.new(0.55, 0.35, 0.35),
					offset = (CFrame.new(0.55, -0.5, -1.6) * CFrame.Angles(rad(25), rad(-45), 0)):Inverse()
						* (CFrame.new(-0.5, -0.85, -1.0) * CFrame.Angles(rad(-30), rad(-20), rad(10)))
						* CFrame.new(0.25, 0, 0),
					color = SKIN_TONE,
					material = Enum.Material.SmoothPlastic })

				-- === HANDLE — brown rectangular box sitting in the hand area,
				-- spanning x=[-0.5, 0]. Same X-span as the combat/M9 handle.
				add({ role = "body",
					size = Vector3.new(0.5, 0.2, 0.2),
					offset = CFrame.new(-0.25, -0.25, -0.05),
					color = HANDLE_BROWN,
					material = Enum.Material.WoodPlanks })
				-- Darker mid-stripe panel (visual detail on the side of the handle).
				add({ role = "body",
					size = Vector3.new(0.46, 0.06, 0.21),
					offset = CFrame.new(-0.25, -0.25, -0.05),
					color = HANDLE_DARK,
					material = Enum.Material.SmoothPlastic })

				-- === BLADE — silver rectangular box extending FORWARD from
				-- the handle's front edge (x=-0.5). Blade length 0.4 → spans
				-- x=[-0.9, -0.5]. Centered vertically with handle (y=-0.25).
				-- Same Z (-0.05) for visual alignment. Rest pose looks like a
				-- M9 bayonet held horizontally, blade pointing forward.
				add({ role = "barrel",
					size = Vector3.new(0.4, 0.1, 0.06),
					offset = CFrame.new(-0.7, -0.25, -0.05),
					color = BLADE_SILVER,
					material = Enum.Material.Metal })

				return parts
			end)(),
		},
	},
}

return WeaponConfig
