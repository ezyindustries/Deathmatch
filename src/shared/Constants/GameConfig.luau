--!strict
-- Tweak gameplay constants di sini. Server & client baca dari file yang sama
-- supaya gak ada drift antara prediction client dan ground-truth server.

local GameConfig = {
	-- Match flow — TEST MODE: durasi singkat biar cepat masuk match.
	-- Production values commented next to each.
	LobbyDuration = 2,         -- prod: 30
	VotingDuration = 7,        -- 7s window — auto-picks random map if nobody votes in time
	MatchDuration = 360,       -- prod: 360 (casual overrides via HoldAutoAdvance anyway)
	IntermissionDuration = 3,  -- prod: 10

	-- Player count
	MinPlayersToStart = 2,
	MaxPlayersPerMatch = 16,

	-- Combat
	RespawnDelay = 0,  -- deathmatch: instant auto-respawn
	BaseHealth = 100,

	-- Movement speeds (studs/sec). Source of truth — read by both
	-- MovementController (apply to humanoid) and WeaponController (sprint state).
	WalkSpeed = 16,        -- base
	SprintSpeed = 24,      -- shift held
	ADSWalkSpeed = 8,      -- right-click held (slow while scoping)

	-- Accuracy multipliers (multiply weapon.baseSpread cone in radians).
	BloomMulADS = 0.3,     -- tight cluster
	BloomMulWalk = 1.0,    -- baseline
	BloomMulSprint = 2.2,  -- wide spray

	-- Camera bob (sine-wave Y/X offset applied to camera each frame during movement).
	BobAmpWalk = 0.08,     -- subtle
	BobAmpSprint = 0.20,
	BobFreqWalk = 7,       -- rad/s
	BobFreqSprint = 11,

	-- Voting
	MapsPerVote = 3,           -- random 3 map dari pool tiap voting

	-- Reward
	CoinPerKill = 5,
	CoinPerWin = 100,
	CoinPerMVP = 50,
	StartingCoins = 300,

	-- Crate
	CratePrice = 100,
	PityThreshold = 75,
	DropRates = {
		Common = 0.855,
		Legendary = 0.10,
		Contraband = 0.045, -- non-karambit contrabands; karambits roll separately at 0.5%
	},
	DuplicateRefund = {
		Common = 5,
		Legendary = 200,
		Contraband = 500,
	},
}

return GameConfig
