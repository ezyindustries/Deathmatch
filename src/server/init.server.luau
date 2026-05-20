--!strict
-- Server entry point. Dijalankan otomatis saat server start.

-- CRITICAL: disable CharacterAutoLoads BEFORE any player can join, to avoid
-- race where player joins before MainMenuService loads + auto-spawns blockily.
local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

-- Disable shift-lock (Roblox's default mouse-lock option) per user request.
-- This is an FPS — we already lock the cursor + drive camera ourselves via
-- the weapon controller, so the built-in shift-lock toggle just gets in the way.
local StarterPlayer = game:GetService("StarterPlayer")
StarterPlayer.EnableMouseLockOption = false

print("[Server] RoblokFPS booting...")

local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

for _, child in ipairs(Services:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, err = pcall(require, child)
		if not ok then
			warn(string.format("[Server] Failed to load service %s: %s", child.Name, err))
		end
	end
end

print("[Server] All services loaded.")
