--!strict
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local AudioConfig = require(Shared.Modules.AudioConfig)
local WeaponConfig = require(Shared.Modules.WeaponConfig)

local AudioController = {}

-- Preload all audio assets at client init.
-- Without this, the FIRST time each sound plays, Roblox has to download the asset
-- from CDN — causing the 1-3 sec delay user reported when firing.
-- After preload, subsequent plays use the cached asset and are instant.
local preloadFolder = Instance.new("Folder")
preloadFolder.Name = "AudioPreload"
preloadFolder.Parent = ReplicatedStorage

task.spawn(function()
	local toPreload: { Sound } = {}
	for _, entry in AudioConfig do
		if entry.id then
			local s = Instance.new("Sound")
			s.SoundId = entry.id
			s.Parent = preloadFolder
			table.insert(toPreload, s)
		end
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(toPreload)
	end)
	if ok then
		print(string.format("[Audio] Preloaded %d sounds", #toPreload))
	else
		warn("[Audio] Preload failed: " .. tostring(err))
	end
end)

local function playLocal(soundKey: string, pitchVariance: number?)
	local entry = AudioConfig[soundKey]
	if not entry then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = entry.id
	sound.Volume = entry.volume
	if entry.pitch then
		sound.PlaybackSpeed = entry.pitch
	end
	if pitchVariance then
		sound.PlaybackSpeed = (sound.PlaybackSpeed or 1) * (1 + (math.random() * 2 - 1) * pitchVariance)
	end
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function playAtWorld(soundKey: string, position: Vector3)
	local entry = AudioConfig[soundKey]
	if not entry then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = position
	part.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = entry.id
	sound.Volume = entry.volume
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = 150
	if entry.pitch then
		sound.PlaybackSpeed = entry.pitch
	end
	sound.Parent = part
	sound:Play()
	-- Clean up faster (2s instead of 4s) — gunshot sounds finish quickly
	Debris:AddItem(part, 2)
end

-- Per-weapon sound overrides — currently EMPTY so all guns use AK-47 sounds
-- (generic fire_rifle / fire_pistol / cocking / reload_start / reload_end keys).
-- To re-enable per-weapon distinct sounds, restore the entries below.
local PER_WEAPON_SOUNDS: { [string]: { fire: string?, cocking: string?, reloadStart: string?, reloadEnd: string? } } = {
	-- smg    = { fire = "fire_smg",    cocking = "cocking_smg",    reloadStart = "reload_smg",    reloadEnd = "reload_smg" },
	-- sniper = { fire = "fire_sniper", cocking = "cocking_sniper", reloadStart = "reload_sniper", reloadEnd = "reload_sniper" },
	-- pistol = { fire = "fire_glock",  cocking = "cocking_glock",  reloadStart = "reload_glock",  reloadEnd = "reload_glock" },
}

-- Fire / hit / kill SFX hooks. Only plays when server confirms a fire.
-- Sound key picked by weapon slot: primary=rifle, secondary=pistol, melee=knife.
Remotes.ShotFired.OnClientEvent:Connect(function(info: any)
	if not info or not info.origin then
		return
	end
	-- Per-weapon fire sound override (defined below in WeaponEquipped block).
	-- info.weaponId is sent by WeaponService since we added per-weapon kill feed.
	local soundKey
	local override = info.weaponId and PER_WEAPON_SOUNDS[info.weaponId]
	if override and override.fire then
		soundKey = override.fire
	elseif info.weaponSlot == "primary" then
		soundKey = "fire_rifle"
	elseif info.weaponSlot == "melee" then
		soundKey = "knife_swing"
	else
		soundKey = "fire_pistol"
	end
	playAtWorld(soundKey, info.origin)
end)

Remotes.HitConfirm.OnClientEvent:Connect(function(info: any)
	-- Knife silent on hit (no ting). Kill sound still plays for elimination feedback.
	local isMelee = info.weaponSlot == "melee"
	if info.killed then
		playLocal("kill")
	elseif not isMelee then
		if info.isHeadshot then
			playLocal("hit_headshot")
		else
			playLocal("hit")
		end
	end
end)

-- Weapon equip → cocking sound (knife uses different sound — no rack/slide).
-- Track equip generation so stale delayed sounds from previous weapon don't play.
local lastEquippedId: string? = nil
local equipGeneration = 0

Remotes.WeaponEquipped.OnClientEvent:Connect(function(weaponId: string, _slot: string)
	if weaponId == "" then
		lastEquippedId = nil
		equipGeneration += 1
		return
	end
	if weaponId ~= lastEquippedId then
		lastEquippedId = weaponId
		equipGeneration += 1
		local myGen = equipGeneration
		local weapon = WeaponConfig[weaponId]
		local drawTime = weapon and weapon.drawTime or 0.85
		if weapon and weapon.slot == "melee" then
			task.delay(0.05, function()
				if myGen == equipGeneration then playLocal("knife_equip") end
			end)
		else
			-- Per-weapon cocking sound override
			local override = PER_WEAPON_SOUNDS[weaponId]
			local cockingKey = (override and override.cocking) or "cocking"
			task.delay(drawTime * 0.25, function()
				if myGen == equipGeneration then playLocal(cockingKey) end
			end)
		end
	end
end)

-- Ammo update → detect reload start. Track active reload sound so we can stop it on weapon switch.
local wasReloading = false
local reloadGeneration = 0
local activeReloadSound: Sound? = nil

local function playReloadSound(soundKey: string): Sound?
	local entry = AudioConfig[soundKey]
	if not entry then return nil end
	local sound = Instance.new("Sound")
	sound.SoundId = entry.id
	sound.Volume = entry.volume
	if entry.pitch then sound.PlaybackSpeed = entry.pitch end
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
	return sound
end

local function stopActiveReload()
	if activeReloadSound then
		activeReloadSound:Stop()
		activeReloadSound:Destroy()
		activeReloadSound = nil
	end
	reloadGeneration += 1 -- cancel pending reload_end callback
	wasReloading = false
end

Remotes.AmmoUpdate.OnClientEvent:Connect(function(info: any)
	local nowReloading = info.reloading == true
	if nowReloading and not wasReloading then
		stopActiveReload() -- safety: cancel any previous
		reloadGeneration += 1
		local myGen = reloadGeneration
		-- Per-weapon reload sound override
		local override = lastEquippedId and PER_WEAPON_SOUNDS[lastEquippedId]
		local startKey = (override and override.reloadStart) or "reload_start"
		local endKey   = (override and override.reloadEnd)   or "reload_end"
		activeReloadSound = playReloadSound(startKey)
		if lastEquippedId then
			local weapon = WeaponConfig[lastEquippedId]
			if weapon then
				task.delay(weapon.reloadTime * 0.85, function()
					if myGen == reloadGeneration and wasReloading then
						activeReloadSound = playReloadSound(endKey)
					end
				end)
			end
		end
	elseif not nowReloading and wasReloading then
		-- reload finished naturally — let end sound play to completion
		activeReloadSound = nil
	end
	wasReloading = nowReloading
end)

-- Cancel reload sound when weapon switches mid-reload
Remotes.WeaponEquipped.OnClientEvent:Connect(function()
	stopActiveReload()
end)

-- Crate / engagement audio
Remotes.CrateOpened.OnClientEvent:Connect(function(result: any)
	if not result.error then
		playLocal("crate_open")
	end
end)
Remotes.DailyResult.OnClientEvent:Connect(function(result: any)
	if not result.error then
		playLocal("level_up")
	end
end)
Remotes.MissionResult.OnClientEvent:Connect(function(result: any)
	if not result.error then
		playLocal("level_up")
	end
end)
Remotes.BPRewardResult.OnClientEvent:Connect(function(result: any)
	if not result.error then
		playLocal("level_up")
	end
end)

return AudioController
