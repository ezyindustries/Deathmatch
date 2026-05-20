--!strict
-- verify_bot_spawn.luau — diagnostic script for the bot spawn fix.
--
-- Run via Studio MCP execute_luau in the *server* context after the match
-- has entered MATCH state with deathmatch gamemode. It will:
--   1. Print preconditions (ActiveArena, spawn folder + count)
--   2. Reach into DeathmatchBotService via _G or by re-running spawnBotsToFill
--   3. Iterate Workspace children, log every Model with IsBot attribute
--   4. Report each bot's HRP position vs nearest spawn point
--
-- This does NOT require any code changes — it reads runtime state. If the
-- printout shows bots with HRP.Position near (0,0,0) instead of the arena
-- spawn coords (around X=2000), the place-bot fix is not yet applied or
-- there is a deeper bug.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

print("=== BOT SPAWN VERIFICATION ===")
print(string.format("Players in game: %d", #Players:GetPlayers()))

local activeArena = Workspace:FindFirstChild("ActiveArena")
print(string.format("ActiveArena exists: %s", tostring(activeArena ~= nil)))
if activeArena then
    print(string.format("ActiveArena mapId: %s", tostring(activeArena:GetAttribute("mapId"))))
    local spawns = activeArena:FindFirstChild("Spawns")
    if spawns then
        local list = {}
        for _, c in spawns:GetChildren() do
            if c:IsA("BasePart") then
                table.insert(list, c)
            end
        end
        print(string.format("Spawn parts in ActiveArena.Spawns: %d", #list))
        if #list > 0 then
            print(string.format("First spawn position: %s", tostring(list[1].Position)))
        end
    else
        print("WARN: ActiveArena has no Spawns folder!")
    end
end

-- Find all bots in the workspace (Models with IsBot attribute)
local found = 0
for _, inst in Workspace:GetChildren() do
    if inst:IsA("Model") and inst:GetAttribute("IsBot") then
        found += 1
        local hrp = inst:FindFirstChild("HumanoidRootPart") :: BasePart?
        local hum = inst:FindFirstChildOfClass("Humanoid")
        print(string.format(
            "BOT %s: HRP pos=%s, parented=%s, health=%s/%s",
            inst.Name,
            tostring(hrp and hrp.Position or "NO-HRP"),
            tostring(inst.Parent ~= nil),
            tostring(hum and hum.Health or "?"),
            tostring(hum and hum.MaxHealth or "?")
        ))
    end
end
print(string.format("=== TOTAL BOTS IN WORKSPACE: %d ===", found))

if found == 0 then
    print("DIAGNOSIS: No bots physically present in Workspace. Possible causes:")
    print("  - spawnBotsToFill() never ran (check console for [DeathmatchBot] logs)")
    print("  - Bots spawned at (0,0,0), fell below FallenPartsDestroyHeight (default -500), were destroyed")
    print("  - clearBots() was called and never re-spawned")
end
