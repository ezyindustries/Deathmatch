--!strict
-- Client entry point. Dijalankan otomatis saat player join.

print("[Client] RoblokFPS booting...")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local controllers = script.Controllers

for _, child in ipairs(controllers:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, err = pcall(require, child)
		if not ok then
			warn(string.format("[Client] Failed to load controller %s: %s", child.Name, err))
		end
	end
end

print(string.format("[Client] All controllers loaded for %s.", player.Name))
