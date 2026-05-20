# Testing Guide

3-tier strategi karena Roblox UI butuh Roblox runtime — gak bisa Lune sepenuhnya.

## Tier 1 — Pure Luau unit tests (Lune)

**Pakai untuk:** modul yang gak refer Color3/UDim/Instance/game.* — hanya math, string ops, data transforms.

**Lokasi:** `tests/unit/<name>_test.luau`

**Jalanin:**
```bash
lune run tests/runner.luau
```

**Pattern:**
```luau
--!strict
local assert_ = require("../assert")
local tests = {}

function tests.my_pure_function()
    assert_.equals(myModule.compute(2, 3), 5)
end

return tests
```

## Tier 2 — Studio integration tests (MCP execute_luau)

**Pakai untuk:** verify UI structure, ScreenGui properties, touch targets, AbsoluteSize/Position di runtime.

**Lokasi:** `tests/integration/<controller>_test.luau` — file ini berupa Luau code string yang dijalanin via `mcp__roblox-studio__execute_luau`. Return "PASS" atau "FAIL: <reason>".

**Pattern:**
```luau
--!strict
-- AnnouncementController integration test
return [[
local Players = game:GetService("Players")
task.wait(2) -- wait for controllers to load
local gui = Players.LocalPlayer.PlayerGui
local hud = gui:FindFirstChild("AnnouncementHUD")
if not hud then return "FAIL: AnnouncementHUD missing" end
if hud.DisplayOrder ~= 50 then return string.format("FAIL: DisplayOrder %d, expected 50", hud.DisplayOrder) end

-- Test signal-driven banner appearance
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ClientSignals = require(Shared.Modules.ClientSignals)
ClientSignals.Get("KillstreakAnnouncement"):Fire({ player = "TestPlayer", streak = 3, label = "TRIPLE KILL" })
task.wait(0.5)

local banner = hud:FindFirstChild("Banner") or hud:FindFirstChildOfClass("Frame")
if not banner then return "FAIL: banner not created after signal" end
if banner.AbsoluteSize.Y < 60 then return "FAIL: banner too small (no entry tween)" end

return "PASS"
]]
```

**Jalanin (manual via Claude):**
1. Start play mode (Studio MCP `start_stop_play(true)`)
2. Read test file content
3. Send to `execute_luau`
4. Check return value

**Atau via helper:** `tests/integration_helper.luau` punya generator function untuk pattern umum.

## Tier 3 — Visual regression (screen_capture)

**Pakai untuk:** verify UI looks right at multiple viewport sizes (mobile, tablet, desktop).

**Pattern:**
1. Start play mode + emulate target device
2. Trigger UI state to test (e.g. open modal)
3. `mcp__roblox-studio__screen_capture` → image
4. Manual review (or compare with baseline screenshots in `screenshots/`)

**Baseline storage:** `screenshots/<controller>/<state>_<viewport>.png` — committed to git.

## TDD workflow per controller redesign

1. **RED:** Write Tier 1 + Tier 2 tests untuk behavior baru. Run — they should FAIL (controller belum di-refactor).
2. **GREEN:** Refactor controller. Run tests. Make them PASS.
3. **REFACTOR:** Clean up. Tests still PASS.
4. **VISUAL:** Tier 3 screen_capture. Compare with design intent.
5. **COMMIT:** On agent's worktree branch.

## Agents working in worktrees

Each Phase 1 agent gets its own worktree:
- `/tmp/agent-<feature>-<id>/` (managed by Agent tool with `isolation: "worktree"`)
- Branch: `feature/<feature-name>`

Agent steps:
1. Read CLAUDE.md, DESIGN_SYSTEM.md, PLAN.md, TESTING.md (this file), UITheme.luau
2. Read target controller current state
3. Write Tier 1 + Tier 2 tests (RED)
4. Refactor controller using UITheme tokens
5. Run Tier 1 via `lune run tests/runner.luau`
6. Verify Tier 2 will work in Studio (review test script for completeness — actual Studio run is by orchestrator)
7. `git commit -m "feat(ui): redesign <Controller> per design system"` on worktree branch
8. Return worktree path + branch to orchestrator

Orchestrator (me) then:
- Merges branch into staging
- Runs Tier 2 in Studio via MCP
- Tier 3 visual capture
- Asks user for approval to promote staging → main
