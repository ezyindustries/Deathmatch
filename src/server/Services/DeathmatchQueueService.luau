--!strict
-- Simple Set<UserId> of players who clicked PLAY → DEATHMATCH. Consulted by
-- MatchStateService at ENDING to decide whether the next cycle runs DM, and
-- by MainMenuService to spawn queued DM players when a DM MATCH actually starts.

local Players = game:GetService("Players")

local DeathmatchQueueService = {}

local queued: { [number]: boolean } = {}

function DeathmatchQueueService.Enroll(player: Player)
	queued[player.UserId] = true
end

function DeathmatchQueueService.Leave(player: Player)
	queued[player.UserId] = nil
end

function DeathmatchQueueService.IsEnrolled(player: Player): boolean
	return queued[player.UserId] == true
end

function DeathmatchQueueService.GetAll(): { number }
	local list: { number } = {}
	for uid in queued do
		table.insert(list, uid)
	end
	return list
end

function DeathmatchQueueService.Count(): number
	local n = 0
	for _ in queued do n += 1 end
	return n
end

Players.PlayerRemoving:Connect(function(player: Player)
	queued[player.UserId] = nil
end)

return DeathmatchQueueService
