--!strict
-- Integration test for DamageDirectionController.
--
-- Returns a table of test functions per the Lune runner contract. Each
-- function's body asserts only on the SHAPE of the integration script
-- (so Lune can sanity-check it without Roblox), and exposes the actual
-- script source via `getScript()` for the orchestrator to feed into
-- `mcp__roblox-studio__execute_luau`.
--
-- The Studio script verifies:
--   1. ScreenGui "DamageDirectionHUD" exists on LocalPlayer
--   2. DisplayOrder is 40 (peripheral HUD, below kill feed/announcement)
--   3. ResetOnSpawn false, IgnoreGuiInset true
--   4. NO full-screen background Frame (would obscure crosshair)
--   5. After firing a fake DamageTaken event, the arrow's halo has a
--      LOWER ZIndex than the arrow (halo renders BEHIND arrow).
-- Returns "PASS" or "FAIL: <reason>" when run in Studio.

local assert_ = require("../assert")

local STUDIO_SCRIPT = [[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

task.wait(2)

local player = Players.LocalPlayer
if not player then return "FAIL: no LocalPlayer" end

local gui = player:WaitForChild("PlayerGui", 5)
if not gui then return "FAIL: PlayerGui missing" end

local hud = gui:FindFirstChild("DamageDirectionHUD")
if not hud then return "FAIL: DamageDirectionHUD missing" end
if not hud:IsA("ScreenGui") then return "FAIL: DamageDirectionHUD is not a ScreenGui" end
if hud.DisplayOrder ~= 40 then
    return string.format("FAIL: DisplayOrder %d, expected 40", hud.DisplayOrder)
end
if hud.ResetOnSpawn then return "FAIL: ResetOnSpawn should be false" end
if not hud.IgnoreGuiInset then return "FAIL: IgnoreGuiInset should be true" end

-- No full-screen Frame (would obscure crosshair / cover viewport)
for _, child in hud:GetChildren() do
    if child:IsA("Frame") then
        local sz = child.Size
        if sz.X.Scale >= 0.99 and sz.Y.Scale >= 0.99 then
            return "FAIL: full-screen Frame inside DamageDirectionHUD obscures view"
        end
    end
end

-- Trigger a fake damage event from a position behind the player. Verify
-- the halo Frame appears with a LOWER ZIndex than the arrow TextLabel.
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
local damageEv = Remotes and Remotes:FindFirstChild("DamageTaken")
if damageEv and player.Character then
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    if root then
        damageEv:FireClient(player, {
            attackerPosition = root.Position + Vector3.new(0, 0, 30),
            damage = 10,
        })
        task.wait(0.25)
        local arrow, halo
        for _, c in hud:GetDescendants() do
            if c:IsA("TextLabel") and c.Text ~= "" and not arrow then arrow = c end
            if c:IsA("Frame") and c.BackgroundTransparency < 1 and not halo then halo = c end
        end
        if arrow and halo then
            if halo.ZIndex >= arrow.ZIndex then
                return string.format("FAIL: halo ZIndex %d should be < arrow ZIndex %d",
                    halo.ZIndex, arrow.ZIndex)
            end
        end
    end
end

return "PASS"
]]

local M = {}

-- Lune-side smoke check: ensure script is non-empty and references key APIs.
function M.studio_script_well_formed()
    assert_.truthy(#STUDIO_SCRIPT > 200, "studio script suspiciously short")
    assert_.truthy(string.find(STUDIO_SCRIPT, "DamageDirectionHUD", 1, true), "must reference HUD name")
    assert_.truthy(string.find(STUDIO_SCRIPT, "DisplayOrder ~= 40", 1, true), "must check DisplayOrder == 40")
end

-- Expose to orchestrator so it can feed the script into execute_luau.
function M.getScript(): string
    return STUDIO_SCRIPT
end

return M
