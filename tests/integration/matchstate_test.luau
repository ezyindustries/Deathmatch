--!strict
-- Studio integration test for MatchStateController. Returns a Luau source
-- string to be executed via `mcp__roblox-studio__execute_luau` while a play
-- session is active.
--
-- Verifies:
--   * MatchHUD ScreenGui exists
--   * Container width matches viewport breakpoint (280 if <700, else 360)
--   * Timer label uses RobotoMono (no width-shift digits)
--   * UIStroke present on container (so state-color stroke can re-tint)
--   * State-color dot exists (Frame sized 0,8,0,8) — visual state indicator
--
-- Returns "PASS" or "FAIL: <reason>".

return [[
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Wait for client init.client.luau to require all controllers
task.wait(2)

local gui = Players.LocalPlayer:WaitForChild("PlayerGui", 5)
if not gui then return "FAIL: PlayerGui missing" end

local hud = gui:FindFirstChild("MatchHUD")
if not hud then return "FAIL: MatchHUD ScreenGui missing" end

-- The container is the only Frame direct-child of the ScreenGui
local container = hud:FindFirstChildOfClass("Frame")
if not container then return "FAIL: container Frame missing under MatchHUD" end

-- Viewport-aware width: 280 if vw<700, else 360
local cam = Workspace.CurrentCamera
local vw = cam and cam.ViewportSize.X or 1920
local expectedW = (vw < 700) and 280 or 360
-- container.Size.X.Offset is what controller sets; AbsoluteSize may include
-- scale effects so we check the explicit Offset value.
if container.Size.X.Offset ~= expectedW then
    return string.format("FAIL: container width %d, expected %d (vw=%d)",
        container.Size.X.Offset, expectedW, vw)
end

-- UIStroke present (for state-color re-tint)
local stroke = container:FindFirstChildOfClass("UIStroke")
if not stroke then return "FAIL: container UIStroke missing" end

-- Find timer label by font (RobotoMono); skip the state label which uses heading font
local timerLabel: TextLabel? = nil
for _, child in container:GetDescendants() do
    if child:IsA("TextLabel") and child.Font == Enum.Font.RobotoMono then
        timerLabel = child
        break
    end
end
if not timerLabel then return "FAIL: timer label with Font=RobotoMono not found" end

-- State-color dot — Frame with explicit size offset 8x8 (0,8,0,8)
local foundDot = false
for _, child in container:GetDescendants() do
    if child:IsA("Frame")
        and child.Size.X.Scale == 0 and child.Size.X.Offset == 8
        and child.Size.Y.Scale == 0 and child.Size.Y.Offset == 8 then
        foundDot = true
        break
    end
end
if not foundDot then return "FAIL: state-color dot Frame (Size 0,8,0,8) not found" end

return "PASS"
]]
