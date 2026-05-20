--!strict
-- DamageDirectionController — peripheral arrow indicators showing where damage
-- came from. Each incoming hit spawns a glowing arrow at the screen edge
-- pointing toward the attacker. Arrows fade out over ~1.2s.
--
-- Design intent (PLAN.md Phase 1.4):
--   * Larger arrow (96px) with soft red halo (140px) — visible on mobile
--   * Radial stacking when multiple sources hit at once (no full overlap)
--   * Damage-type hooks: bullet (▲), melee (◢), explosion (⚠)
--   * Peripheral position (42% off center) to keep crosshair clear
--   * All colors from UITheme tokens (no hardcoded RGB)
--
-- TESTABILITY: pure helper functions (`arrowSymbolFor`, `stackOffsetFor`,
-- `computeAngleDeg`) are exposed on the returned module table under `.Pure`.
-- They take plain Luau tables / strings and have no Roblox dependency, so
-- they can be unit-tested under Lune (see tests/unit/damagedir_test.luau).
--
-- When loaded in test sandbox (sentinel `__DAMAGEDIR_TEST_MODE` set), the
-- controller skips all Roblox-side setup and only returns the Pure table.

-- ============================================================================
-- PURE HELPERS — no Roblox APIs, safe to unit-test under Lune.
-- ============================================================================
local Pure = {}

-- Map damage type → arrow symbol. Future variant hook; today the server may
-- not yet populate `damageType`, so we default to ▲ (bullet) for nil/unknown.
function Pure.arrowSymbolFor(damageType: string?): string
    if damageType == "melee" then return "◢" end
    if damageType == "explosion" then return "⚠" end
    return "▲" -- "bullet", nil, or any unknown type
end

-- Given the count of arrows already active, return an angular offset (degrees)
-- to apply to the new arrow so it doesn't fully overlap existing ones.
-- Alternates ±15°, stepping by 15° magnitude every 2 entries:
--   0 → 0    (first arrow, no offset)
--   1 → +15  (second arrow, slight right)
--   2 → -15  (third, slight left)
--   3 → +30
--   4 → -30
--   5 → +45
--   ...
-- This pattern keeps total angular spread tight (peripheral readability)
-- while preventing perfect overlap.
function Pure.stackOffsetFor(activeArrows: number): number
    if activeArrows <= 0 then return 0 end
    -- Step magnitude: ceil(n/2) * 15°. Sign alternates: odd n → +, even n → -.
    local magnitude = math.ceil(activeArrows / 2) * 15
    if activeArrows % 2 == 1 then return magnitude end
    return -magnitude
end

-- Compute relative bearing in degrees [0, 360) from camera forward to the
-- direction toward the attacker. Both inputs are plain {x, z} tables
-- (horizontal plane — Y is irrelevant for an on-screen compass arrow).
--
-- Convention (right-handed, +Y up, viewed from above):
--   0°   = attacker directly in front of camera
--   90°  = attacker to the right
--   180° = attacker directly behind
--   270° = attacker to the left
-- Output increases CLOCKWISE when looking down at the player.
--
-- Degenerate inputs (zero-magnitude vectors) → 0°. This matches the legacy
-- behavior that simply returned nil and skipped the arrow; here we return a
-- sentinel that callers can detect via a separate magnitude check.
function Pure.computeAngleDeg(camForward: { x: number, z: number }, attackerRelative: { x: number, z: number }): number
    local camMag = math.sqrt(camForward.x * camForward.x + camForward.z * camForward.z)
    local atkMag = math.sqrt(attackerRelative.x * attackerRelative.x + attackerRelative.z * attackerRelative.z)
    if camMag < 1e-4 or atkMag < 1e-4 then return 0 end

    local cx, cz = camForward.x / camMag, camForward.z / camMag
    local ax, az = attackerRelative.x / atkMag, attackerRelative.z / atkMag

    -- atan2(cross, dot). Cross sign chosen so +X attacker (right of -Z cam)
    -- yields +90°, matching screen-space convention.
    local dot = cx * ax + cz * az
    local cross = cx * az - cz * ax
    local rad = math.atan2(cross, dot)
    local deg = math.deg(rad)
    if deg < 0 then deg = deg + 360 end
    if deg >= 360 then deg = deg - 360 end
    return deg
end

-- ============================================================================
-- TEST-SANDBOX EARLY-RETURN — when loaded under Lune unit tests with no `game`
-- ============================================================================
-- The unit-test runner stubs out Roblox globals so it can extract `Pure`
-- without paying the cost of (or failing on) the Roblox-side setup below.
if rawget(_G, "__DAMAGEDIR_TEST_MODE") then
    return { Pure = Pure }
end

-- ============================================================================
-- ROBLOX-SIDE CONTROLLER (real runtime path)
-- ============================================================================
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local UITheme = require(Shared.Modules.UITheme)

local DamageDirectionController = { Pure = Pure }

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DamageDirectionHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40
screenGui.Parent = playerGui

-- ----------------------------------------------------------------------------
-- Visual constants. Sizes tuned for 96px arrow + 140px halo per DESIGN_SYSTEM.
-- ----------------------------------------------------------------------------
local ARROW_SIZE = 96
local HALO_SIZE = 140
local ARROW_TEXT_SIZE = 56
local EDGE_OFFSET = 0.42       -- of min(viewport width, height); peripheral
local LIFETIME = 1.2           -- seconds before the arrow auto-destroys
local ENTER_DUR = 0.16
local EXIT_DUR = 0.4
local HALO_ZINDEX = 1          -- behind arrow
local ARROW_ZINDEX = 2

type IndicatorEntry = {
    arrow: TextLabel,
    halo: Frame,
    scaler: UIScale,
    haloStroke: UIStroke,
    angleRad: number,
    stackOffsetDeg: number,
    spawnedAt: number,
    expireAt: number,
    exiting: boolean,
}

local activeIndicators: { IndicatorEntry } = {}

-- ----------------------------------------------------------------------------
-- Builders
-- ----------------------------------------------------------------------------
local function makeArrow(damageType: string?): (TextLabel, Frame, UIScale)
    -- Halo (rendered FIRST so it sits visually behind via ZIndex anyway)
    local halo = Instance.new("Frame")
    halo.Name = "DamageHalo"
    halo.Size = UDim2.fromOffset(HALO_SIZE, HALO_SIZE)
    halo.AnchorPoint = Vector2.new(0.5, 0.5)
    halo.BackgroundColor3 = UITheme.Color.danger
    halo.BackgroundTransparency = 0.5
    halo.BorderSizePixel = 0
    halo.ZIndex = HALO_ZINDEX
    halo.Parent = screenGui

    -- Full-radius (pill -> circle since w == h)
    local haloCorner = Instance.new("UICorner")
    haloCorner.CornerRadius = UDim.new(1, 0)
    haloCorner.Parent = halo

    -- Subtle soft gradient on halo for depth — center brighter, edge fades
    local grad = Instance.new("UIGradient")
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.6, 0.5),
        NumberSequenceKeypoint.new(1, 0.85),
    })
    grad.Parent = halo

    -- Arrow text label sits on top of halo
    local arrow = Instance.new("TextLabel")
    arrow.Name = "DamageArrow"
    arrow.Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE)
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.BackgroundTransparency = 1
    arrow.Font = UITheme.Font.display          -- GothamBlack
    arrow.TextSize = ARROW_TEXT_SIZE
    arrow.TextColor3 = UITheme.Color.danger
    arrow.TextStrokeColor3 = UITheme.Color.bgDeepest
    arrow.TextStrokeTransparency = 0
    arrow.Text = Pure.arrowSymbolFor(damageType)
    arrow.ZIndex = ARROW_ZINDEX
    arrow.Parent = screenGui

    -- UIScale on arrow for entry pop (0.7 → 1.0). Halo uses its own scaler via
    -- shared reference: simpler to give each Instance its own scaler since they
    -- aren't parented together (both sit directly under screenGui to keep the
    -- ZIndex relationship explicit).
    local arrowScale = Instance.new("UIScale")
    arrowScale.Scale = 0.7
    arrowScale.Parent = arrow

    local haloScale = Instance.new("UIScale")
    haloScale.Scale = 0.7
    haloScale.Parent = halo

    -- Tween in — share easing across both via separate Tweens (TweenService
    -- doesn't accept multi-target). Use UITheme.Easing.quick (0.16s back-out)
    -- approximation: build a custom TweenInfo at ENTER_DUR with Back easing.
    local enterInfo = TweenInfo.new(ENTER_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    TweenService:Create(arrowScale, enterInfo, { Scale = 1.0 }):Play()
    TweenService:Create(haloScale, enterInfo, { Scale = 1.0 }):Play()

    return arrow, halo, arrowScale
end

-- Compute the (x, y) screen-space position for an arrow at a given final angle
-- (radians, where 0 = forward, increases clockwise looking down). Uses an
-- elliptical edge offset so widescreen displays don't push the arrow into the
-- corners. EDGE_OFFSET is applied to the smaller viewport dimension.
local function positionForAngle(angleRad: number): (number, number)
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local minDim = math.min(vp.X, vp.Y)
    local offsetX = (EDGE_OFFSET * minDim) / vp.X
    local offsetY = (EDGE_OFFSET * minDim) / vp.Y
    local sx = 0.5 + math.sin(angleRad) * offsetX
    local sy = 0.5 - math.cos(angleRad) * offsetY
    return sx, sy
end

-- ----------------------------------------------------------------------------
-- Damage event handler
-- ----------------------------------------------------------------------------
Remotes.DamageTaken.OnClientEvent:Connect(function(info: any)
    if not info or not info.attackerPosition then return end

    local character = player.Character
    if not character then return end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    -- Pure-math angle calc using {x,z} plain tables
    local rel = (info.attackerPosition :: Vector3) - root.Position
    local camLook = camera.CFrame.LookVector
    local angleDeg = Pure.computeAngleDeg(
        { x = camLook.X, z = camLook.Z },
        { x = rel.X, z = rel.Z }
    )

    -- Skip if both vectors degenerate (computeAngleDeg returns 0 for that case;
    -- guard with a magnitude check on the attacker offset).
    if rel.Magnitude < 0.1 then return end

    local stackOffset = Pure.stackOffsetFor(#activeIndicators)
    local finalAngleDeg = (angleDeg + stackOffset) % 360
    local finalAngleRad = math.rad(finalAngleDeg)

    local arrow, halo, scaler = makeArrow(info.damageType)
    -- Place halo + arrow at same screen position; arrow rotation follows angle
    local sx, sy = positionForAngle(finalAngleRad)
    arrow.Position = UDim2.fromScale(sx, sy)
    arrow.Rotation = finalAngleDeg
    halo.Position = UDim2.fromScale(sx, sy)
    -- Halo doesn't rotate — it's a symmetric glow

    -- Track haloStroke as nil placeholder — keeping struct shape simple
    local haloStroke = nil :: any

    local now = os.clock()
    table.insert(activeIndicators, {
        arrow = arrow,
        halo = halo,
        scaler = scaler,
        haloStroke = haloStroke,
        angleRad = finalAngleRad,
        stackOffsetDeg = stackOffset,
        spawnedAt = now,
        expireAt = now + LIFETIME,
        exiting = false,
    })
end)

-- ----------------------------------------------------------------------------
-- Per-frame update: fade arrows that have lived past their lifetime, and
-- trigger exit animation in the last EXIT_DUR seconds.
-- ----------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
    local now = os.clock()
    for i = #activeIndicators, 1, -1 do
        local entry = activeIndicators[i]
        local lifeLeft = entry.expireAt - now
        if lifeLeft <= 0 then
            entry.arrow:Destroy()
            entry.halo:Destroy()
            table.remove(activeIndicators, i)
        elseif not entry.exiting and lifeLeft <= EXIT_DUR then
            -- Start exit tween: scale 1.0 → 0.7 + fade out
            entry.exiting = true
            local exitInfo = TweenInfo.new(EXIT_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            local arrowScaler = entry.arrow:FindFirstChildOfClass("UIScale")
            local haloScaler = entry.halo:FindFirstChildOfClass("UIScale")
            if arrowScaler then
                TweenService:Create(arrowScaler, exitInfo, { Scale = 0.7 }):Play()
            end
            if haloScaler then
                TweenService:Create(haloScaler, exitInfo, { Scale = 0.7 }):Play()
            end
            TweenService:Create(entry.arrow, exitInfo, {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
            }):Play()
            TweenService:Create(entry.halo, exitInfo, {
                BackgroundTransparency = 1,
            }):Play()
        end
    end
end)

return DamageDirectionController
