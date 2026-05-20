--!strict
-- Tier 2 integration test for HealthController.
-- Verifies in Studio play mode:
--   1. ScreenGui "HealthHUD" exists with expected structure
--   2. Container anchored at bottom-left (AnchorPoint y=1, Position 24,-80)
--   3. NO full-screen Frame with danger color (regression guard against
--      the vision-obscuring overlay that was removed)
--   4. Edge vignette frames are present (at least 1 frame styled as edge strip)
--
-- Returns a table with `code` field — the Luau code string. Orchestrator
-- reads `require(...).code` and pipes to `mcp__roblox-studio__execute_luau`
-- while in play mode. Expected return from Studio: "PASS" or "FAIL: <reason>".
--
-- Shape (table) keeps the Lune test runner from crashing on discovery (it
-- iterates table values looking for functions; finds none here, skips file).

local M = {}

M.code = [[
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Wait for controllers to load + character spawn
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then return "FAIL: PlayerGui missing" end

-- Allow extra time for HealthController require + character to spawn
task.wait(2)

local hud = playerGui:FindFirstChild("HealthHUD")
if not hud then return "FAIL: HealthHUD ScreenGui missing" end
if not hud:IsA("ScreenGui") then return "FAIL: HealthHUD not a ScreenGui" end

-- Find the HP container (the main visible Frame, bottom-left)
local container
for _, child in hud:GetChildren() do
	if child:IsA("Frame") then
		local sz = child.Size
		-- Container: bounded offset width/height, NOT a full-screen frame
		if sz.X.Scale < 0.5 and sz.Y.Scale < 0.5 then
			container = child
			break
		end
	end
end
if not container then return "FAIL: HP container Frame not found" end

-- Verify bottom-left anchoring
if container.AnchorPoint.Y < 0.99 then
	return string.format("FAIL: container AnchorPoint.Y=%.2f, expected ~1.0 (bottom-anchored)", container.AnchorPoint.Y)
end
if container.AnchorPoint.X > 0.01 then
	return string.format("FAIL: container AnchorPoint.X=%.2f, expected ~0.0 (left-anchored)", container.AnchorPoint.X)
end
if math.abs(container.Position.X.Offset - 24) > 1 then
	return string.format("FAIL: container Position.X.Offset=%d, expected 24", container.Position.X.Offset)
end

-- REGRESSION GUARD: no full-screen Frame with danger color anywhere in HealthHUD.
-- Old controller had a Frame(1,0,1,0) with red BackgroundColor3 — must be GONE.
local function isCloseToDanger(c)
	-- UITheme.Color.danger = RGB(255, 60, 80) → ~(1, 0.235, 0.314)
	local dr = math.abs(c.R - 1.0)
	local dg = math.abs(c.G - 60/255)
	local db = math.abs(c.B - 80/255)
	return dr < 0.15 and dg < 0.2 and db < 0.2
end

for _, desc in hud:GetDescendants() do
	if desc:IsA("Frame") then
		local sz = desc.Size
		-- Full-screen = Scale (1,0,1,0) and no offset
		if sz.X.Scale >= 0.99 and sz.Y.Scale >= 0.99 and sz.X.Offset == 0 and sz.Y.Offset == 0 then
			if isCloseToDanger(desc.BackgroundColor3) then
				return string.format("FAIL: full-screen danger-colored Frame still present (%s)", desc:GetFullName())
			end
		end
	end
end

-- Verify edge vignette exists: at least one Frame anchored at viewport edge
-- with danger color and bounded thickness.
local edgeVignetteFound = false
for _, desc in hud:GetDescendants() do
	if desc:IsA("Frame") then
		local sz = desc.Size
		local fullW = sz.X.Scale >= 0.99
		local fullH = sz.Y.Scale >= 0.99
		local narrow = (sz.Y.Scale < 0.5 and sz.Y.Offset > 0 and sz.Y.Offset < 200)
			or (sz.X.Scale < 0.5 and sz.X.Offset > 0 and sz.X.Offset < 200)
		if (fullW or fullH) and narrow and isCloseToDanger(desc.BackgroundColor3) then
			edgeVignetteFound = true
			break
		end
	end
end
if not edgeVignetteFound then
	return "FAIL: no edge vignette strip Frame found (expected 4 edge strips with danger color)"
end

return "PASS"
]]

return M
