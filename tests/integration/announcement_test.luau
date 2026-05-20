--!strict
-- Tier 2 Studio integration test for AnnouncementController.
--
-- This file returns a table (so the Lune runner doesn't treat it as a
-- malformed unit test) but its primary payload is `.code` — a Luau source
-- string meant to be fed into `mcp__roblox-studio__execute_luau` inside an
-- active play session. The script verifies, when executed in Studio:
--   1. AnnouncementHUD ScreenGui exists with DisplayOrder=50.
--   2. Banner can be created at runtime by invoking the controller's
--      `_OpenForTest(payload)` hook (exposed on the returned module table
--      precisely for Tier 2 testing — same shape as the server payload).
--   3. The banner is mobile-responsive (AbsoluteSize.X < viewport.X * 0.95).
--
-- Usage from orchestrator:
--   local code = require("tests/integration/announcement_test").code
--   mcp__roblox-studio__execute_luau(code)  -- expect "PASS" or "FAIL: ..."

local STUDIO_CODE = [[
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
task.wait(2) -- let client controllers boot

local gui = Players.LocalPlayer:WaitForChild("PlayerGui", 5)
if not gui then return "FAIL: PlayerGui missing" end

local hud = gui:FindFirstChild("AnnouncementHUD")
if not hud then return "FAIL: AnnouncementHUD ScreenGui missing" end
if hud.DisplayOrder ~= 50 then
	return string.format("FAIL: DisplayOrder=%d, expected 50", hud.DisplayOrder)
end

-- Resolve the controller via its module path so we can invoke the test hook.
-- Controllers in this project live under StarterPlayerScripts.Client; at
-- runtime they're under Players.LocalPlayer.PlayerScripts.Client.
local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 5)
local Client = PlayerScripts:FindFirstChild("Client")
if not Client then return "FAIL: PlayerScripts.Client folder missing" end
local controllers = Client:FindFirstChild("Controllers")
if not controllers then return "FAIL: Client.Controllers folder missing" end
local module = controllers:FindFirstChild("AnnouncementController")
if not module then return "FAIL: AnnouncementController module missing" end

local ok, ctrl = pcall(require, module)
if not ok then return "FAIL: require AnnouncementController errored: " .. tostring(ctrl) end
if typeof(ctrl) ~= "table" then return "FAIL: AnnouncementController did not return a table" end
if typeof(ctrl._OpenForTest) ~= "function" then
	return "FAIL: AnnouncementController._OpenForTest hook missing (expected for Tier 2 testing)"
end

-- Fire the test hook with a DOMINATOR-tier streak (>=6) so the particle
-- burst path is also exercised (visual verification via Tier 3 capture).
ctrl._OpenForTest({ player = Players.LocalPlayer.Name, streak = 7, label = "DOMINATOR" })
task.wait(0.5)

local banner = hud:FindFirstChild("Banner")
if not banner then
	-- Fallback: any reasonably-sized Frame child
	for _, c in hud:GetChildren() do
		if c:IsA("Frame") and c.AbsoluteSize.Y >= 40 then
			banner = c
			break
		end
	end
end
if not banner then return "FAIL: banner Frame not found after _OpenForTest" end

local cam = Workspace.CurrentCamera
local vw = cam and cam.ViewportSize.X or 1920
if banner.AbsoluteSize.X >= vw * 0.95 then
	return string.format("FAIL: banner width %d not responsive (viewport %d)", banner.AbsoluteSize.X, vw)
end
if banner.AbsoluteSize.Y < 40 then
	return string.format("FAIL: banner too small post-entry (%dy)", banner.AbsoluteSize.Y)
end

return "PASS"
]]

-- Returned shape: table with `.code` field. The Lune runner sees a table
-- with no functions and skips it cleanly (no PASS, no FAIL). The
-- orchestrator imports this and pipes `.code` to execute_luau.
return {
	code = STUDIO_CODE,
}
