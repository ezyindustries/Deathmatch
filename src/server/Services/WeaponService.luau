--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local WeaponConfig = require(Shared.Modules.WeaponConfig)
local MatchState = require(Shared.Modules.MatchState)
local GameConfig = require(Shared.Constants.GameConfig)

local MatchStateService = require(script.Parent.MatchStateService)
local TrainingService = require(script.Parent.TrainingService)

print("[Weapon] Service loading...")

local WeaponService = {}

local PlayerDataService = require(script.Parent.PlayerDataService)

type Loadout = { primary: string, secondary: string, melee: string }

local DEFAULT_LOADOUT: Loadout = { primary = "rifle", secondary = "pistol", melee = "knife" }

local PRIMARY_SLOTS = { "rifle", "smg", "sniper" }
local SECONDARY_SLOTS = { "pistol" }

local function isValidLoadoutPick(weaponId: string, slot: WeaponConfig.Slot): boolean
	local weapon = WeaponConfig[weaponId]
	if not weapon then
		return false
	end
	if weapon.slot ~= slot then
		return false
	end
	return true
end

local loadouts: { [number]: Loadout } = {}
local equippedSlot: { [number]: WeaponConfig.Slot } = {}
local lastFireAt: { [number]: number } = {}
local lastDrawAt: { [number]: number } = {}

type AmmoBySlot = { primary: number, secondary: number, melee: number? }
local ammo: { [number]: AmmoBySlot } = {}
local reloading: { [number]: boolean } = {}

local playerKilledEvent = Instance.new("BindableEvent")
WeaponService.PlayerKilled = playerKilledEvent.Event

local botKilledEvent = Instance.new("BindableEvent")
WeaponService.BotKilled = botKilledEvent.Event

local function isMatchActive(): boolean
	return MatchStateService.GetState().state == MatchState.States.MATCH
end

-- Lazy-required to avoid init-time circular dep with CasualService.
local function casual()
	return require(script.Parent.CasualService)
end

-- Lazy-required: DeathmatchTeamService also requires this file in the future,
-- and load order is non-deterministic. Lazy-resolve so the cycle (if any)
-- only materializes at first call, by which point both modules are cached.
local function teamSvc()
	return require(script.Parent.DeathmatchTeamService)
end

-- Training players are always allowed to fire (bypass match state).
-- In casual mode, fire is only allowed during the LIVE round phase (not BUY/POST).
local function canFireFor(player: Player): boolean
	if TrainingService.IsTraining(player.UserId) then
		return true
	end
	if not isMatchActive() then return false end
	if MatchStateService.GetGamemode() == "casual" then
		return casual().IsLivePhase() and casual().IsAlive(player.UserId)
	end
	return true
end

local function currentWeapon(userId: number): WeaponConfig.WeaponInfo?
	local loadout = loadouts[userId]
	local slot = equippedSlot[userId]
	if not loadout or not slot then
		return nil
	end
	local id = loadout[slot]
	return id and WeaponConfig[id] or nil
end

local function fireAmmoUpdate(player: Player)
	local slot = equippedSlot[player.UserId]
	local weapon = currentWeapon(player.UserId)
	local playerAmmo = ammo[player.UserId]
	if not slot or not weapon or not playerAmmo then
		Remotes.AmmoUpdate:FireClient(player, { current = 0, magSize = 0, reloading = false })
		return
	end
	Remotes.AmmoUpdate:FireClient(player, {
		current = playerAmmo[slot],
		magSize = weapon.magSize,
		reloading = reloading[player.UserId] or false,
	})
end

local function equipSlot(player: Player, slot: WeaponConfig.Slot)
	local loadout = loadouts[player.UserId]
	if not loadout then
		return
	end
	local weaponId = loadout[slot]
	if not weaponId or not WeaponConfig[weaponId] then
		return
	end
	equippedSlot[player.UserId] = slot
	lastDrawAt[player.UserId] = os.clock()
	reloading[player.UserId] = false
	Remotes.WeaponEquipped:FireClient(player, weaponId, slot)
	fireAmmoUpdate(player)
end

local function unequip(player: Player)
	loadouts[player.UserId] = nil
	equippedSlot[player.UserId] = nil
	lastFireAt[player.UserId] = nil
	lastDrawAt[player.UserId] = nil
	ammo[player.UserId] = nil
	reloading[player.UserId] = nil
	Remotes.WeaponEquipped:FireClient(player, "", "")
end

local function giveLoadout(player: Player)
	local profile = PlayerDataService.Get(player)
	local primary = (profile and profile.loadout.primary) or DEFAULT_LOADOUT.primary
	local secondary = (profile and profile.loadout.secondary) or DEFAULT_LOADOUT.secondary
	local melee = (profile and profile.loadout.melee) or DEFAULT_LOADOUT.melee
	if not WeaponConfig[primary] or WeaponConfig[primary].slot ~= "primary" then
		primary = DEFAULT_LOADOUT.primary
	end
	if not WeaponConfig[secondary] or WeaponConfig[secondary].slot ~= "secondary" then
		secondary = DEFAULT_LOADOUT.secondary
	end
	if not WeaponConfig[melee] or WeaponConfig[melee].slot ~= "melee" then
		melee = DEFAULT_LOADOUT.melee
	end
	loadouts[player.UserId] = { primary = primary, secondary = secondary, melee = melee }
	ammo[player.UserId] = {
		primary = WeaponConfig[primary].magSize,
		secondary = WeaponConfig[secondary].magSize,
		melee = 1, -- placeholder, melee has no ammo
	}
	reloading[player.UserId] = false
	equipSlot(player, "primary")
end

Remotes.SetLoadout.OnServerEvent:Connect(function(player: Player, primaryRaw: any, secondaryRaw: any, meleeRaw: any)
	if primaryRaw ~= nil and typeof(primaryRaw) ~= "string" then return end
	if secondaryRaw ~= nil and typeof(secondaryRaw) ~= "string" then return end
	if meleeRaw ~= nil and typeof(meleeRaw) ~= "string" then return end
	if primaryRaw and not isValidLoadoutPick(primaryRaw, "primary") then return end
	if secondaryRaw and not isValidLoadoutPick(secondaryRaw, "secondary") then return end
	if meleeRaw and not isValidLoadoutPick(meleeRaw, "melee") then return end

	PlayerDataService.SetLoadout(player, primaryRaw, secondaryRaw, meleeRaw)

	-- Training + deathmatch get an instant re-equip (buy menu in deathmatch
	-- should swap the weapon mid-life, not wait for respawn). Casual is
	-- round-locked so we leave it to apply next round.
	local mode = MatchStateService.GetGamemode()
	local immediate = TrainingService.IsTraining(player.UserId)
		or (mode == "deathmatch" and player.Character ~= nil)
	if immediate and player.Character then
		giveLoadout(player)
	end
end)

Remotes.RequestReload.OnServerEvent:Connect(function(player: Player)
	if not canFireFor(player) then
		return
	end
	local weapon = currentWeapon(player.UserId)
	local slot = equippedSlot[player.UserId]
	local playerAmmo = ammo[player.UserId]
	if not weapon or not slot or not playerAmmo then
		return
	end
	if reloading[player.UserId] then
		return
	end
	if playerAmmo[slot] >= weapon.magSize then
		return
	end

	local now = os.clock()
	if now - (lastDrawAt[player.UserId] or 0) < weapon.drawTime then
		return
	end

	local reloadId = slot
	reloading[player.UserId] = true
	fireAmmoUpdate(player)

	task.delay(weapon.reloadTime, function()
		if not Players:GetPlayerByUserId(player.UserId) then
			return
		end
		if equippedSlot[player.UserId] ~= reloadId then
			reloading[player.UserId] = false
			return
		end
		if not ammo[player.UserId] then
			return
		end
		ammo[player.UserId][slot] = weapon.magSize
		reloading[player.UserId] = false
		fireAmmoUpdate(player)
	end)
end)

local function computeDamage(weapon: WeaponConfig.WeaponInfo, distance: number, isHeadshot: boolean): number
	-- Headshots ignore range falloff entirely (CS-style — full headshot damage at any range)
	if isHeadshot then
		return weapon.damage * weapon.headshotMultiplier
	end
	local falloffRange = weapon.falloffEnd - weapon.falloffStart
	local mul
	if distance <= weapon.falloffStart then
		mul = 1
	elseif distance >= weapon.falloffEnd then
		mul = weapon.minDamageMul
	else
		local t = (distance - weapon.falloffStart) / falloffRange
		mul = 1 - t * (1 - weapon.minDamageMul)
	end
	return weapon.damage * mul
end

Remotes.SwitchWeapon.OnServerEvent:Connect(function(player: Player, slotRaw: any)
	if typeof(slotRaw) ~= "string" then
		return
	end
	if slotRaw ~= "primary" and slotRaw ~= "secondary" and slotRaw ~= "melee" then
		return
	end
	if not canFireFor(player) then
		return
	end
	if equippedSlot[player.UserId] == slotRaw then
		return
	end
	equipSlot(player, slotRaw)
end)

Remotes.FireRequest.OnServerEvent:Connect(function(player: Player, originRaw: any, directionRaw: any, isStabRaw: any)
	if typeof(originRaw) ~= "Vector3" or typeof(directionRaw) ~= "Vector3" then
		return
	end
	local isStab = isStabRaw == true
	if not canFireFor(player) then
		return
	end

	local weapon = currentWeapon(player.UserId)
	if not weapon then
		return
	end

	local now = os.clock()

	-- Block firing during draw animation
	local lastDraw = lastDrawAt[player.UserId] or 0
	if now - lastDraw < weapon.drawTime then
		return
	end

	-- Block firing during reload
	if reloading[player.UserId] then
		return
	end

	-- Check ammo (melee weapons skip ammo decrement)
	local slot = equippedSlot[player.UserId]
	local playerAmmo = ammo[player.UserId]
	if not slot or not playerAmmo then
		return
	end
	local isMelee = weapon.slot == "melee"
	if not isMelee and playerAmmo[slot] <= 0 then
		return
	end

	local lastFire = lastFireAt[player.UserId] or 0
	local minInterval = 1 / weapon.fireRate
	if now - lastFire < minInterval * 0.9 then
		return
	end
	lastFireAt[player.UserId] = now
	if not isMelee then
		playerAmmo[slot] -= 1
		fireAmmoUpdate(player)
	end

	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	if (originRaw - rootPart.Position).Magnitude > 10 then
		return
	end

	-- Bullets travel in a perfectly straight line from the crosshair — no
	-- per-shot spread, no drop. The client direction (which matches the camera
	-- look vector) is used verbatim.
	local direction = directionRaw.Unit * weapon.range
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(originRaw, direction, params)

	-- Broadcast shot visual to ALL clients (tracer + muzzle flash + impact)
	local endPos = result and result.Position or (originRaw + direction)
	local hitNormal = result and result.Normal or Vector3.new(0, 1, 0)
	local hitMaterial = (result and result.Material) and result.Material.Name or "Air"
	local hitIsPlayer = false
	if result then
		local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
		if hitModel and Players:GetPlayerFromCharacter(hitModel) then
			hitIsPlayer = true
		end
	end
	Remotes.ShotFired:FireAllClients({
		shooterUserId = player.UserId,
		weaponId = weapon.id,
		weaponSlot = weapon.slot,
		origin = originRaw,
		hitPosition = endPos,
		hitNormal = hitNormal,
		hitMaterial = hitMaterial,
		hitIsPlayer = hitIsPlayer,
		didHit = result ~= nil,
	})

	if not result then
		return
	end

	local hitChar = result.Instance:FindFirstAncestorOfClass("Model")
	if not hitChar then
		return
	end
	local hitHumanoid = hitChar:FindFirstChildOfClass("Humanoid")
	if not hitHumanoid or hitHumanoid.Health <= 0 then
		return
	end
	local hitPlayer = Players:GetPlayerFromCharacter(hitChar)

	local distance = (result.Position - originRaw).Magnitude
	local isHeadshot = result.Instance.Name == "Head"

	local damage: number
	if weapon.slot == "melee" then
		-- Knife: 60 dmg (slash/left-click), 90 dmg (stab/right-click). No backstab/headshot bonus.
		damage = isStab and 90 or weapon.damage
		isHeadshot = false
	else
		damage = computeDamage(weapon, distance, isHeadshot)
	end

	-- Casual: friendly fire is disabled. Skip damage if attacker and victim are
	-- on the same team (whether victim is a player or a bot).
	if MatchStateService.GetGamemode() == "casual" then
		local attackerTeam = casual().GetTeamFor(player.UserId)
		local victimKey: any = hitPlayer and hitPlayer.UserId or hitChar.Name
		local victimTeam = casual().GetTeamFor(victimKey)
		if attackerTeam and victimTeam and attackerTeam == victimTeam then
			return
		end
	end

	-- Deathmatch (10v10 TDM): friendly fire OFF — same-team shots are eaten.
	-- We only suppress when BOTH sides have an explicit team tag AND match;
	-- if either side is untagged (e.g. training dummies, mode transition
	-- window) damage falls through.
	if MatchStateService.GetGamemode() == "deathmatch" then
		local svc = teamSvc()
		local attackerTeam = svc.GetTeam(player)
		local victimTeam = if hitPlayer then svc.GetTeam(hitPlayer) else svc.GetTeam(hitChar)
		if attackerTeam and victimTeam and attackerTeam == victimTeam then
			return
		end
	end

	hitHumanoid:TakeDamage(damage)
	local killed = hitHumanoid.Health <= 0

	-- Fire damage-direction indicator only to actual players
	if hitPlayer then
		Remotes.DamageTaken:FireClient(hitPlayer, {
			attackerPosition = originRaw,
			damage = damage,
		})
	end

	-- Always show hit confirmation to shooter (works for NPC dummies too)
	Remotes.HitConfirm:FireClient(player, {
		victim = hitPlayer and hitPlayer.Name or hitChar.Name,
		damage = damage,
		isHeadshot = isHeadshot,
		killed = killed,
		distance = distance,
		weaponSlot = weapon.slot,
	})

	-- Bot kill tracking: if victim is a bot and killed, fire event for ScoringService
	if not hitPlayer and killed and hitChar:GetAttribute("IsBot") == true then
		botKilledEvent:Fire(player, hitChar.Name)
	end

	-- VALORANT-style: killer refilled to full HP on confirmed kill.
	-- Gated on DM only (casual is round-based — no mid-round heal).
	if killed and MatchStateService.GetGamemode() ~= "casual" then
		local killerChar = player.Character
		if killerChar then
			local killerHum = killerChar:FindFirstChildOfClass("Humanoid")
			if killerHum and killerHum.Health > 0 then
				killerHum.Health = killerHum.MaxHealth
			end
		end
	end

	-- Kill feed: fire for ANY kill (player or bot victim) so the top-right
	-- notification works in all modes. Player-vs-player additionally fires
	-- DeathInfo to the victim.
	if killed then
		local killerProfile = PlayerDataService.Get(player)
		local titleId = killerProfile and killerProfile.equipped.title
		local kfxId = killerProfile and killerProfile.equipped.kill_effect
		local victimName = hitPlayer and hitPlayer.Name or hitChar.Name
		-- Resolve team tags for client-side coloring (KillFeedController uses them
		-- to color killer/victim names by Tim Kawan vs Tim Lawan). Lazy-required
		-- to avoid load-order coupling; pcall so casual / training stays safe.
		local killerTeam: string? = nil
		local victimTeam: string? = nil
		pcall(function()
			local team = require(script.Parent.DeathmatchTeamService)
			killerTeam = team.GetTeam(player.Character) :: any
			victimTeam = team.GetTeam(hitChar) :: any
		end)
		Remotes.KillFeedEntry:FireAllClients({
			killer = player.Name,
			victim = victimName,
			weapon = weapon.displayName,
			weaponId = weapon.id,
			weaponSlot = weapon.slot,
			isHeadshot = isHeadshot,
			titleId = titleId,
			killEffectId = kfxId,
			victimPosition = result.Position,
			killerTeam = killerTeam,
			victimTeam = victimTeam,
		})
		if hitPlayer then
			Remotes.DeathInfo:FireClient(hitPlayer, {
				killer = player.Name,
				weapon = weapon.displayName,
				isHeadshot = isHeadshot,
				distance = distance,
			})
			playerKilledEvent:Fire(player, hitPlayer, weapon, isHeadshot)
		end
	end
end)

MatchStateService.StateChanged:Connect(function(newState: MatchState.State)
	print("[Weapon] State changed to:", newState)
	if newState == MatchState.States.MATCH then
		print("[Weapon] MATCH! Giving loadouts to", #Players:GetPlayers(), "players")
		for _, p in Players:GetPlayers() do
			if not TrainingService.IsTraining(p.UserId) then
				giveLoadout(p)
			end
		end
	elseif newState == MatchState.States.ENDING or newState == MatchState.States.LOBBY then
		for _, p in Players:GetPlayers() do
			if not TrainingService.IsTraining(p.UserId) then
				unequip(p) -- keep training player's weapons
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player: Player)
	if isMatchActive() or TrainingService.IsTraining(player.UserId) then
		giveLoadout(player)
	end
	player.CharacterAdded:Connect(function()
		task.wait(0.1)
		if isMatchActive() or TrainingService.IsTraining(player.UserId) then
			giveLoadout(player)
		end
	end)
end)

-- Public: let TrainingService request a loadout for a player at any time
function WeaponService.GiveLoadout(player: Player)
	giveLoadout(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	unequip(player)
end)

Players.RespawnTime = GameConfig.RespawnDelay

return WeaponService
