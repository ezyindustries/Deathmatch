--!strict
-- Integration test helper. Generates Luau code strings to be executed inside
-- Roblox Studio via the MCP `execute_luau` tool. Use this from agent prompts
-- or test runners to verify UI structure post-build.
--
-- Pattern:
--   local code = IntegrationHelper.assertScreenGui("LoadoutHUD", {
--       displayOrder = 150,
--       enabled = true,
--   })
--   -- Send `code` to `mcp__roblox-studio__execute_luau`
--   -- Returns "PASS" or a descriptive error message.

local IntegrationHelper = {}

function IntegrationHelper.assertScreenGui(name: string, expected: { displayOrder: number?, enabled: boolean? }): string
	local checks = {}
	if expected.displayOrder ~= nil then
		table.insert(checks, string.format("if g.DisplayOrder ~= %d then return 'FAIL: DisplayOrder %d, expected %d' end",
			expected.displayOrder, 0, expected.displayOrder))
	end
	if expected.enabled ~= nil then
		table.insert(checks, string.format("if g.Enabled ~= %s then return 'FAIL: Enabled mismatch' end",
			tostring(expected.enabled)))
	end
	return string.format([[
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui", 5)
local g = gui:FindFirstChild("%s")
if not g then return "FAIL: ScreenGui '%s' missing" end
%s
return "PASS"
]], name, name, table.concat(checks, "\n"))
end

-- Assert a Frame/Button exists at a given path AND meets touch target minimum.
function IntegrationHelper.assertTouchTarget(path: string, minSize: number?): string
	local minSz = minSize or 44
	return string.format([[
local target = %s
if not target then return "FAIL: instance at path not found" end
local size = target.AbsoluteSize
if size.X < %d or size.Y < %d then
    return string.format("FAIL: touch target %%.0fx%%.0f below min %d", size.X, size.Y)
end
return "PASS"
]], path, minSz, minSz, minSz)
end

-- Assert UIScale parent is the modal panel, NOT the overlay (mobile bug pattern).
function IntegrationHelper.assertResponsiveScaleOnPanel(overlayPath: string): string
	return string.format([[
local overlay = %s
if not overlay then return "FAIL: overlay not found" end
local overlayScale = overlay:FindFirstChildOfClass("UIScale")
if overlayScale and overlayScale.Scale < 0.99 then
    return "FAIL: UIScale on overlay (will shrink tap area on mobile)"
end
local panel = overlay:FindFirstChildOfClass("TextButton") or overlay:FindFirstChildOfClass("Frame")
if not panel then return "FAIL: panel not found" end
local panelScale = panel:FindFirstChildOfClass("UIScale")
if not panelScale then return "WARN: no UIScale on panel" end
return "PASS"
]], overlayPath)
end

return IntegrationHelper
