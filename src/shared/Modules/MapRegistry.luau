--!strict
export type Gamemode = "deathmatch" | "casual"

export type MapInfo = {
	id: string,
	displayName: string,
	description: string,
	color: Color3,
	supportedModes: { Gamemode }, -- which gamemodes this map can host (filters voting pool)
}

local MapRegistry: { MapInfo } = {
	{
		id = "warehouse",
		displayName = "Warehouse",
		description = "Close-quarters industrial. Lots of cover, short sightlines.",
		color = Color3.fromRGB(180, 120, 60),
		supportedModes = { "deathmatch" },
	},
	{
		id = "rooftop",
		displayName = "Rooftop",
		description = "Vertical urban combat. Verticality decides fights.",
		color = Color3.fromRGB(80, 140, 200),
		supportedModes = { "deathmatch" },
	},
	{
		id = "desert",
		displayName = "Desert Outpost",
		description = "Open mid-range sightlines, scattered cover.",
		color = Color3.fromRGB(200, 170, 90),
		supportedModes = { "deathmatch" },
	},
	{
		id = "metro",
		displayName = "Metro Station",
		description = "Underground choke points and tight corners.",
		color = Color3.fromRGB(120, 110, 130),
		supportedModes = { "deathmatch" },
	},
	{
		id = "harbor",
		displayName = "Harbor",
		description = "Mixed range, container maze layout.",
		color = Color3.fromRGB(90, 140, 110),
		supportedModes = { "deathmatch" },
	},
	{
		id = "dust2",
		displayName = "Dust II",
		description = "Bomb plant/defuse. Two sites (A long, B tunnels), mid control.",
		color = Color3.fromRGB(210, 175, 110),
		supportedModes = { "casual" },
	},
}

return MapRegistry
