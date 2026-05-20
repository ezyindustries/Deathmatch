--!strict
-- Unit tests for DamageDirectionController pure-function helpers.
--
-- Controller exports a small `Pure` table with arrow symbol resolver,
-- radial stack offset computation, and the relative-angle math. These
-- are all Roblox-free so they live under Tier 1.
--
-- ANGLE CONVENTION (computeAngleDeg):
--   0° = attacker directly in front of camera (along camForward)
--   Increases CLOCKWISE when viewed from above (+Y in Roblox).
--   90°  = attacker directly to the player's right
--   180° = attacker directly behind
--   270° = attacker directly to the player's left
--
-- Inputs are plain Luau tables `{ x = number, z = number }` (no Vector3
-- so tests stay pure). Y is ignored — direction indicator is horizontal.

local assert_ = require("../assert")

-- Load the controller module by reading + executing its source. We can't just
-- `require()` because the controller has Roblox globals at top-level. We only
-- need the `Pure` table.
--
-- Strategy: source-grep the Pure table via an injected stub environment.
local fs = require("@lune/fs")

-- Load + run the controller source in a sandboxed env that stubs out Roblox
-- globals enough to let module evaluation reach `return ... .Pure`. Anything
-- that touches Players/Workspace/etc. is wrapped in `if game then ... end`
-- inside the controller itself.
local source = fs.readFile("src/client/Controllers/DamageDirectionController.luau")

-- Build sandbox: provide no-op stand-ins for Roblox APIs the controller
-- references at load time. Any unstubbed access errors loudly so we notice.
local sandbox: { [string]: any } = {}
sandbox._G = sandbox
sandbox.math = math
sandbox.string = string
sandbox.table = table
sandbox.os = os
sandbox.typeof = typeof
sandbox.type = type
sandbox.tostring = tostring
sandbox.tonumber = tonumber
sandbox.ipairs = ipairs
sandbox.pairs = pairs
sandbox.next = next
sandbox.select = select
sandbox.error = error
sandbox.assert = assert
sandbox.pcall = pcall
sandbox.xpcall = xpcall
sandbox.rawget = rawget
sandbox.rawset = rawset
sandbox.rawequal = rawequal
sandbox.setmetatable = setmetatable
sandbox.getmetatable = getmetatable
sandbox.require = function() return {} end -- stub all requires
sandbox.task = { delay = function() end, wait = function() end, spawn = function() end }
-- Sentinel that signals "running in unit-test sandbox" — controller skips
-- side-effectful Roblox setup when this is set.
sandbox.__DAMAGEDIR_TEST_MODE = true
sandbox.game = nil :: any

local chunk, loadErr = loadstring(source, "DamageDirectionController")
if not chunk then
    error("failed to compile controller source: " .. tostring(loadErr))
end
setfenv(chunk, sandbox)
local ok, mod = pcall(chunk)
if not ok then
    error("failed to execute controller in sandbox: " .. tostring(mod))
end
if type(mod) ~= "table" or type(mod.Pure) ~= "table" then
    error("controller did not export Pure table; got " .. typeof(mod))
end

local Pure = mod.Pure

local tests = {}

-- ============================================================================
-- arrowSymbolFor
-- ============================================================================
function tests.arrow_bullet_returns_triangle()
    assert_.equals(Pure.arrowSymbolFor("bullet"), "▲")
end

function tests.arrow_melee_returns_slash()
    assert_.equals(Pure.arrowSymbolFor("melee"), "◢")
end

function tests.arrow_explosion_returns_warn()
    assert_.equals(Pure.arrowSymbolFor("explosion"), "⚠")
end

function tests.arrow_nil_defaults_to_triangle()
    assert_.equals(Pure.arrowSymbolFor(nil), "▲")
end

function tests.arrow_unknown_defaults_to_triangle()
    assert_.equals(Pure.arrowSymbolFor("plasma_beam"), "▲")
end

-- ============================================================================
-- stackOffsetFor — alternating ±15° per active arrow count, 30° step on every 2
-- ============================================================================
function tests.stack_offset_zero_active()
    assert_.equals(Pure.stackOffsetFor(0), 0)
end

function tests.stack_offset_one_active()
    assert_.equals(Pure.stackOffsetFor(1), 15)
end

function tests.stack_offset_two_active()
    assert_.equals(Pure.stackOffsetFor(2), -15)
end

function tests.stack_offset_three_active()
    assert_.equals(Pure.stackOffsetFor(3), 30)
end

function tests.stack_offset_four_active()
    assert_.equals(Pure.stackOffsetFor(4), -30)
end

function tests.stack_offset_five_active()
    assert_.equals(Pure.stackOffsetFor(5), 45)
end

function tests.stack_offset_six_active()
    assert_.equals(Pure.stackOffsetFor(6), -45)
end

-- ============================================================================
-- computeAngleDeg — relative bearing from camera forward to attacker direction
-- ============================================================================
local function approx(a: number, b: number, tol: number?)
    local t = tol or 0.001
    if math.abs(a - b) > t then
        error(string.format("expected ~%f, got %f (tol %f)", b, a, t), 2)
    end
end

function tests.angle_attacker_in_front_is_zero()
    -- cam facing -Z (Roblox forward), attacker also at -Z direction
    local angle = Pure.computeAngleDeg({ x = 0, z = -1 }, { x = 0, z = -1 })
    approx(angle, 0)
end

function tests.angle_attacker_behind_is_180()
    -- cam facing -Z, attacker direction is +Z
    local angle = Pure.computeAngleDeg({ x = 0, z = -1 }, { x = 0, z = 1 })
    approx(angle, 180)
end

function tests.angle_attacker_right_is_90()
    -- cam facing -Z, attacker at +X (to the right of camera)
    local angle = Pure.computeAngleDeg({ x = 0, z = -1 }, { x = 1, z = 0 })
    approx(angle, 90)
end

function tests.angle_attacker_left_is_270()
    -- cam facing -Z, attacker at -X (to the left)
    local angle = Pure.computeAngleDeg({ x = 0, z = -1 }, { x = -1, z = 0 })
    approx(angle, 270)
end

function tests.angle_zero_camforward_returns_zero()
    -- Degenerate input: camera forward is zero vector
    assert_.equals(Pure.computeAngleDeg({ x = 0, z = 0 }, { x = 1, z = 0 }), 0)
end

function tests.angle_zero_attacker_returns_zero()
    -- Degenerate input: attacker direction is zero vector
    assert_.equals(Pure.computeAngleDeg({ x = 0, z = -1 }, { x = 0, z = 0 }), 0)
end

function tests.angle_output_always_in_0_360()
    -- Sweep several inputs, output must be 0 ≤ deg < 360
    local cam = { x = 0, z = -1 }
    for i = 1, 16 do
        local theta = (i / 16) * math.pi * 2
        local atk = { x = math.sin(theta), z = -math.cos(theta) }
        local a = Pure.computeAngleDeg(cam, atk)
        if a < 0 or a >= 360 then
            error(string.format("angle %f out of range [0, 360)", a))
        end
    end
end

return tests
