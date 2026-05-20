--!strict
-- Lightweight cross-controller event bus on the client. Used by PauseMenu to
-- trigger modal opens in other controllers without tight coupling.

local signals: { [string]: BindableEvent } = {}

local ClientSignals = {}

function ClientSignals.Get(name: string): BindableEvent
	local existing = signals[name]
	if existing then
		return existing
	end
	local be = Instance.new("BindableEvent")
	signals[name] = be
	return be
end

return ClientSignals
