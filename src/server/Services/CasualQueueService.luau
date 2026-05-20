--!strict
-- Simple Set<UserId> of players who clicked PLAY → CASUAL mode. Consulted by
-- CasualService when it auto-balances teams at MATCH start. Players are
-- enrolled by MainMenuService when they request a casual spawn, and removed
-- when they leave or pick a different mode.

local Players = game:GetService("Players")

local CasualQueueService = {}

local queued: { [number]: boolean } = {}

function CasualQueueService.Enroll(player: Player)
	queued[player.UserId] = true
end

function CasualQueueService.Leave(player: Player)
	queued[player.UserId] = nil
end

function CasualQueueService.IsEnrolled(player: Player): boolean
	return queued[player.UserId] == true
end

function CasualQueueService.GetAll(): { number }
	local list: { number } = {}
	for uid in queued do
		table.insert(list, uid)
	end
	return list
end

function CasualQueueService.Count(): number
	local n = 0
	for _ in queued do n += 1 end
	return n
end

Players.PlayerRemoving:Connect(function(player: Player)
	queued[player.UserId] = nil
end)

return CasualQueueService
