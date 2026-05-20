--!strict
-- Sound asset registry. rbxasset:// paths use Roblox's bundled engine sounds
-- (always available). Replace with custom Audio uploads (rbxassetid://...) when
-- ready — Roblox audio is region-restricted so verify license before uploading.

export type SoundEntry = {
	id: string,
	volume: number,
	pitch: number?,
}

local Sounds: { [string]: SoundEntry } = {
	-- Pistol fire: use same AK gunshot for Glock per user preference (more impactful than built-in click)
	fire_pistol = { id = "rbxassetid://132258172", volume = 0.7 },
	-- Rifle fire: real AK-74 gunshot from public Roblox catalog
	fire_rifle = { id = "rbxassetid://132258172", volume = 0.7 },
	-- Cocking: real "gun equip" mechanical sound (0.76s — fits the 1s draw window)
	cocking = { id = "rbxassetid://7405483764", volume = 0.8 },
	-- Reload start/end: AK-47 reload sequence (full 2.6s reload)
	reload_start = { id = "rbxassetid://6808977427", volume = 0.7 },
	reload_end = { id = "rbxasset://sounds/clickfast.wav", volume = 0.6 },
	hit = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.6 },
	hit_headshot = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, pitch = 2.0 },
	kill = { id = "rbxasset://sounds/bell.mp3", volume = 0.7 },
	ui_click = { id = "rbxasset://sounds/clickfast.wav", volume = 0.4 },
	crate_open = { id = "rbxasset://sounds/bell.mp3", volume = 0.6, pitch = 0.8 },
	level_up = { id = "rbxasset://sounds/bell.mp3", volume = 0.8, pitch = 1.4 },
	hit_marker = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.8 },
	hit_marker_head = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, pitch = 2.4 },
	-- Killstreak announcer voices. Placeholder = built-in bell at varying pitch.
	-- TODO: replace each `id` with a real announcer voice asset (e.g., "Double Kill"
	-- TTS or game-rip). Volume scales up with tier so DOMINATOR feels biggest.
	streak_first     = { id = "rbxasset://sounds/bell.mp3", volume = 0.65, pitch = 1.0 },
	streak_double    = { id = "rbxasset://sounds/bell.mp3", volume = 0.70, pitch = 1.2 },
	streak_triple    = { id = "rbxasset://sounds/bell.mp3", volume = 0.75, pitch = 1.4 },
	streak_quadra    = { id = "rbxasset://sounds/bell.mp3", volume = 0.80, pitch = 1.6 },
	streak_penta     = { id = "rbxasset://sounds/bell.mp3", volume = 0.90, pitch = 1.8 },
	streak_dominator = { id = "rbxasset://sounds/bell.mp3", volume = 1.00, pitch = 0.6 },

	-- Knife: metal ting on equip, clean "swoosh through air" on swing (NOT hit/blood)
	knife_equip = { id = "rbxassetid://9116197044", volume = 0.8 },
	-- Modern tactical blade whoosh (CS-style). Played 3D-positional at the
	-- shooter via ShotFired → AudioController.
	knife_swing = { id = "rbxassetid://7382280087", volume = 0.9, pitch = 1.0 },

	-- =========================================================
	-- PER-WEAPON SOUNDS (UMP-45 / AWP / Glock-18). AK-47 unchanged → uses
	-- the generic fire_rifle / cocking / reload_start above.
	-- =========================================================
	-- UMP-45 — SMG, sharper crack
	fire_smg     = { id = "rbxassetid://9114290937", volume = 0.55, pitch = 1.15 },
	cocking_smg  = { id = "rbxassetid://9116514270", volume = 0.7 },
	reload_smg   = { id = "rbxassetid://6975309081", volume = 0.65 },

	-- AWP — sniper, heavy resonant boom + bolt-action slap
	fire_sniper    = { id = "rbxassetid://1850450287", volume = 0.85, pitch = 0.95 },
	cocking_sniper = { id = "rbxassetid://168143115",  volume = 0.75 },
	reload_sniper  = { id = "rbxassetid://9118800469", volume = 0.7 },

	-- Glock-18 — pistol, crisp snap
	fire_glock     = { id = "rbxassetid://9114290776", volume = 0.55, pitch = 1.2 },
	cocking_glock  = { id = "rbxassetid://9116514120", volume = 0.7 },
	reload_glock   = { id = "rbxassetid://9118996498", volume = 0.65 },
}

return Sounds
