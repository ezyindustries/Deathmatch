--!strict
-- TopbarController — hide the Roblox top-left CoreGui icons (chat, audio,
-- emote, player list, backpack) so they don't overlap our MatchHUD + HP HUD
-- in the top-left column. User feedback: "untuk menu roblox bisa ngga sih
-- dihide aja(yang kiri atas)".
--
-- We keep TopbarEnabled = true (the bar still exists for the Roblox menu /
-- shift-tap menu icon — needed for player-driven actions like leaving the
-- game) but disable each CoreGuiType individually so the icons don't render.
--
-- SetCore("TopbarEnabled", ...) sometimes errors before CoreScripts have
-- finished loading; wrap it in pcall + retry so a one-time race doesn't
-- leave the bar visible.

local StarterGui = game:GetService("StarterGui")

local TopbarController = {}

local DISABLED_TYPES: { Enum.CoreGuiType } = {
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.EmotesMenu,
	-- Health bar stays disabled too — we render our own HP HUD.
	Enum.CoreGuiType.Health,
}

local function tryHide()
	for _, t in DISABLED_TYPES do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(t, false)
		end)
	end
	-- TopbarEnabled hides the entire top icon strip (chat icon + headphones
	-- icon on the Unibar). On versions where this is a no-op (modern Unibar
	-- on web), the per-CoreGuiType disables above still hide the icons.
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", false)
	end)
end

-- Try immediately + retry a few times in case CoreScripts haven't loaded yet
tryHide()
task.spawn(function()
	for _ = 1, 5 do
		task.wait(0.5)
		tryHide()
	end
end)

return TopbarController
