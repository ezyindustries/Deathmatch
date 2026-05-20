# RoblokFPS — Deathmatch

Roblox FPS game dengan dua gamemode: **Deathmatch** (free-for-all dengan bot fill) dan **Casual** (CS-style 5v5 bomb defuse, T vs CT). Project ini lagi dalam aktif development; build saat ini "DM-only" (casual mode hidden dari player tapi kode-nya lengkap).

> Place file di Studio: `Deathmatch`. Project internal name di code: `RoblokFPS`.

---

## Workflow development di Mac

Kamu (ezy.industries@gmail.com) develop game ini dari Mac via 2 mekanisme paralel:

### 1. Roblox Studio MCP (built-in, real-time)

MCP daemon bawaan Studio yang ngubungin Claude Code (terminal) ↔ Roblox Studio Assistant. **Lihat `ROBLOX_MCP_GUIDE.md`** untuk panduan lengkap setup + troubleshooting.

Komponen:
- **StudioMCP daemon**: `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP` — listen di `localhost:13469`, auto-spawn saat Studio start
- **Studio Assistant**: panel built-in di Studio (toggle "Enable Studio as MCP server" wajib ON via 3-dot menu → Manage MCP Servers)
- **Claude Code**: spawn proxy stdio ke daemon — registered via `claude mcp add roblox-studio -- /Applications/RobloxStudio.app/Contents/MacOS/StudioMCP --stdio`

Tools yang penting (~24 total, semua **free** termasuk `execute_luau`):
- `list_roblox_studios` — verify MCP connected
- `execute_luau` — run Luau di Studio (edit mode dual-context, play mode client-context)
- `script_read`, `multi_edit`, `script_search`, `script_grep` — code ops
- `inspect_instance`, `search_game_tree` — explore hierarchy
- `screen_capture` — Studio viewport screenshot
- `start_stop_play` — play/stop game
- `get_console_output` — read recent print/warn/error
- `generate_mesh`, `generate_material`, `generate_procedural_model` — AI gen
- `user_keyboard_input`, `user_mouse_input`, `character_navigation` — input sim
- `search_creator_store`, `insert_from_creator_store` — marketplace

**Health check:**
```bash
curl -s http://localhost:13469/health
# OK
# Studios: 1   (kalau 0, toggle MCP belum ON di Assistant)
# Tools cached: 24
```

**Toggle MCP server tiap Studio buka:** Studio Assistant kadang reset MCP ke OFF. Sebelum minta Claude do audit: buka Assistant panel (tab kanan bawah) → 3-dot menu (…) → Manage MCP Servers → toggle "Enable Studio as MCP server" ON.

**Catatan:** Sebelumnya project ini pakai `weppy-roblox-mcp` (3rd-party, Basic tier paywall blok `execute_luau`). Sudah di-replace dengan official MCP — `execute_luau` free, daemon stable, terintegrasi langsung dengan Studio Assistant.

### 2. Rojo (offline disk sync)

File `default.project.json` di root memetakan struktur on-disk → instance tree Studio. Workflow:

```bash
# Sync 2-way ke Studio (plugin Rojo Studio harus connect)
rojo serve

# Build .rbxl place file dari folder (one-shot publish artifact)
rojo build -o Deathmatch.rbxl

# Bikin sourcemap buat IDE (Luau LSP / VSCode)
rojo sourcemap > sourcemap.json
```

Mapping yang dipakai:

| Disk path | Studio path |
|---|---|
| `src/server/` | `ServerScriptService.Server` (Script entry-point + Services + Modules) |
| `src/shared/` | `ReplicatedStorage.Shared` (Constants + Modules + Packages) |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` (LocalScript + Controllers) |

Geometri Workspace (`ActiveArena/Parts`, `Baseplate`, `SpawnLocation`, dll) **tidak** di-track Rojo — itu live di `deathmatch.rbxl` (binary place file backup) di root folder.

### Backup convention

| Apa | Di mana | Kapan diupdate |
|---|---|---|
| Source code semua script | `src/**/*.luau` (Rojo) | Setiap kali edit (manual atau auto via Rojo sync) |
| Geometry / non-script Instances | `deathmatch.rbxl` (root) | Manual save di Studio: **File → Download a Copy** |
| Project mapping | `default.project.json` | Saat tambah service/folder baru |

**⚠️ Catatan format**: macOS Studio cuma support format `.rbxl` (binary) untuk save lokal. Menu "File → Save to File" tidak ada di Mac — pakai **File → Download a Copy** instead. Format `.rbxlx` (XML) gak available; tapi extractor di bawah handle binary, jadi fine.

**Sebelum sesi development**, save place via `File → Download a Copy` ke root folder sebagai `deathmatch.rbxl`. Setelah selesai, save lagi (overwrite). File ini = source of truth untuk geometri + setting Studio. Script source = di disk via Rojo.

Untuk extract semua script dari `.rbxl` (mis. abis kerja di PC lain → balik ke Mac, atau mau update src/ dari Studio):
```bash
lune run scripts/extract.luau deathmatch.rbxl
```

Extractor pakai `@lune/roblox` API (lune 0.10+), bisa baca binary `.rbxl` maupun XML `.rbxlx`. Output: 66 file Luau di `src/` (27 controller + 24 server + 15 shared).

---

## Arsitektur runtime

### Server boot (`src/server/init.server.luau`)

Run otomatis saat server start. Steps:
1. `Players.CharacterAutoLoads = false` — player nyangkut di main menu sampai klik PLAY
2. `StarterPlayer.EnableMouseLockOption = false` — disable shift-lock bawaan (FPS pakai kursor lock sendiri)
3. Loop `require()` semua ModuleScript di `Services/` (pcall-wrapped — error 1 service gak crash yang lain)

### Client boot (`src/client/init.client.luau`)

Run per player saat join. Loop `require()` semua ModuleScript di `Controllers/`.

### Match state machine

`MatchStateService` punya 5 state, transition otomatis:
```
LOBBY → VOTING → STARTING → MATCH → ENDING → LOBBY ...
```

- **LOBBY**: pre-match countdown (test: 2s, prod: 30s)
- **VOTING**: 7s, player vote di antara 3 random map yang support gamemode aktif
- **STARTING**: VotingService close, ArenaService build map + teleport players
- **MATCH**: actual gameplay (360s default)
- **ENDING**: scoreboard + reward, lalu teleport balik ke lobby

`MatchStateService.HoldAutoAdvance(true)` dipake `CasualService` selama MATCH biar round loop CS-style yang kelola durasi (bukan timer 360s).

### Server Services (`src/server/Services/`)

Auto-loaded. **Lazy-require pattern** dipake untuk dodge circular deps (mis. `WeaponService` lazy-require `CasualService` via local function).

| Service | Tanggung jawab |
|---|---|
| **MatchStateService** | State machine + state-change BindableEvent (`StateChanged`) |
| **VotingService** | 3 random map per round, vote tally, set gamemode dari winning map's metadata |
| **ArenaService** | Build/destroy arena via MapBuilders, lighting presets per map, spawn protection (2s ForceField), out-of-bounds death (Y < -200), spawn guards |
| **WeaponService** | Loadout (primary/secondary/melee), fire validation, hit detection (raycast), damage formula (range falloff + headshot mul), kill feed broadcast, VALORANT-style refill-on-kill (DM only) |
| **PlayerDataService** | Profile schema + DataStore CRUD (`RoblokFPS_PlayerData_v1`), auto-save 60s + BindToClose, graceful fallback ke in-memory, settings whitelist validation, legacy migration |
| **ScoringService** | Per-match K/D scoreboard (players + bots), kill streaks (DOUBLE/TRIPLE/.../DOMINATOR + bonus coins), XP awards, rank XP penalty (-10 per death, floored at 0), MVP reward |
| **LobbyBuilderService** | Procedural lobby geometry (baseplate, walls, center platform, 6 spawn points circular) — dijalankan saat require pertama |
| **MainMenuService** | RequestSpawn/ExitToMainMenu remotes, deathmatch auto-respawn (literally re-runs exit→spawn buat avoid divergence bugs) |
| **CasualService** | CS-style: T vs CT teams, BUY (15s) → LIVE (round timer) → POST → next round. Bomb plant/defuse, friendly fire OFF, first-to-12 wins |
| **DeathmatchBotService** | Bot fill saat player count rendah — server selalu running live DM |
| **CasualBotService** | Bot fill untuk casual mode (perlu 5v5 minimum) |
| **DeathmatchQueueService** | Pasangin player ke DM match |
| **CasualQueueService** | Pasangin player ke casual match (5v5 lobby) |
| **DMRoomService** | Isolated 1v1 room di luar arena utama |
| **TrainingService** | Solo practice mode — bypass match state, always allow fire |
| **CrateService** | Gacha: roll dari pity counter (75 = guaranteed Legendary/Contraband), 0.5% karambit roll separately |
| **BattlePassService** | Tier claim, free vs premium track |
| **MonetizationService** | Gamepass ownership check, prompt purchase, multiplier grants |
| **MissionService** | Daily/weekly missions, progress tracking, claim |
| **PickupService** | World pickups (ammo, weapon swap) |
| **RedeemService** | Promo code redemption |

### Shared Modules (`src/shared/Modules/`)

Server + client baca shared logic dari sini biar gak drift.

| Module | Isi |
|---|---|
| **Remotes** | Auto-create + WaitForChild ~50 RemoteEvents di `ReplicatedStorage.Remotes` (lihat list di file — kategori: match flow, combat, casual/bomb, economy, social) |
| **MatchState** | Enums (`States.LOBBY/VOTING/STARTING/MATCH/ENDING`, `Gamemodes.Deathmatch/Casual`), `StateConfig` (duration + next-state per state) |
| **WeaponConfig** | Master weapon registry — id, slot, damage, fireRate, range, falloff, magSize, reloadTime, drawTime, baseSpread, headshotMultiplier, minDamageMul |
| **MapRegistry** | Map metadata: id, displayName, supportedModes (`{"deathmatch", "casual"}`), thumbnail |
| **GameConfig** (Constants/) | Match durations (TEST values!), movement speeds, bloom multipliers, camera bob, coin/XP rates, crate drop rates + pity |
| **CasualConfig** (Constants/) | CS-style config: round timer, plant/defuse durations, buy time, win condition |
| **CosmeticRegistry** | Skin pool buat gacha + display info |
| **RankSystem** | XP → rank mapping (Bronze 1 → Immortal 3), `XP_PER_KILL = 20` |
| **BattlePassConfig** | Tier list, reward per tier (free + premium) |
| **ProductsConfig** | DevProduct + Gamepass IDs |
| **MissionConfig** | Daily/weekly mission definitions |
| **AudioConfig** | Sound IDs, volume defaults |
| **Teams** | T vs CT team constants |
| **ClientSignals** | BindableEvents shared antara controllers |
| **BotModel** | Bot character template + naming |

### Client Controllers (`src/client/Controllers/`)

Auto-loaded per player. Kategori:

**Core gameplay**
- `MovementController` — apply WalkSpeed/SprintSpeed/ADSWalkSpeed dari GameConfig ke Humanoid
- `WeaponController` — viewmodel, ADS, recoil, crosshair bloom, fire input, mobile HUD buttons
- `HealthController` — health bar UI

**HUD (in-match)**
- `KillFeedController` — top-right kill notifications (with title + kill-effect cosmetic)
- `ScoreboardController` — Tab to view K/D, rank icons
- `DamageDirectionController` — directional damage indicator (compass arrow saat di-shoot)
- `DamageFlashController` — screen tint merah saat dapet damage
- `AnnouncementController` — center-screen big text (FIRST KILL / DOMINATOR / Match Won)
- `CasualHUDController` — CS-style HUD (team score, round number, BUY/LIVE/POST phase)
- `DeathmatchLeaderboardController` — DM live top-3 sidebar

**Menus**
- `MainMenuController` — pre-match home screen (PLAY button → RequestSpawn)
- `PauseMenuController` — ESC menu
- `LoadoutController` — pick primary/secondary/melee
- `BuyMenuController` — casual BUY phase weapon purchase
- `ShopController`, `CosmeticsController`, `CrateController` — economy UIs
- `SettingsController` — preferences (sensitivity, FOV, ADS toggle/hold, crosshair editor)
- `VotingController` — 3-map vote UI
- `SpectatorController` — POV cycle saat mati di casual

**Misc**
- `MatchStateController` — sync state to client, show countdown
- `CurrencyController` — coin balance HUD
- `ProgressionController` — XP bar + level-up tutorial
- `AudioController` — apply master volume, play UI sfx
- `CursorModeController` — toggle locked / unlocked cursor
- `EngagementController` — daily login claim
- `LoadoutController` — pick weapons

---

## Data flow ringkasan (Deathmatch hit)

```
Client (WeaponController)
  ↓ mouse click → originVec3, dirVec3, isStab
Remotes.FireRequest:FireServer(...)
  ↓
WeaponService:OnServerEvent
  ↓ validate fire-rate, ammo, draw time, match state
Workspace:Raycast(origin, dir * weapon.range, params)
  ↓ filter ExcludeShooterChar
result.Instance → find Humanoid → calc damage (range falloff + headshot mul)
  ↓
Humanoid:TakeDamage(damage)
  ↓ Remotes.ShotFired:FireAllClients (tracer/muzzle FX)
  ↓ Remotes.HitConfirm:FireClient(shooter) (hit marker)
  ↓ Remotes.DamageTaken:FireClient(victim) (damage indicator)
If killed:
  ↓ Remotes.KillFeedEntry:FireAllClients (top-right notif)
  ↓ Remotes.DeathInfo:FireClient(victim) (death cam)
  ↓ playerKilledEvent → ScoringService → +1 K, +XP, +coin, kill streak
  ↓ killer Humanoid.Health = MaxHealth (VALORANT-style refill, DM only)
```

---

## Yang sering jadi gotcha

1. **Module load order** — `Server/init.server.luau` iterate `Services/:GetChildren()` (order **tidak deterministic**). Service yang butuh service lain pakai `require(script.Parent.XYZ)` di body — Roblox cache require result, jadi urutan gak penting selama gak ada circular dep.

2. **Circular deps** — `WeaponService` butuh `CasualService` untuk team check, tapi `CasualService` butuh `WeaponService` untuk damage. Solusi: lazy-require pattern (`local function casual() return require(...) end` — dipanggil baru saat butuh).

3. **TEST vs PROD config** — `GameConfig.luau` saat ini di TEST mode (LobbyDuration=2 instead of prod 30). Komentar `prod: XX` ada di sebelah tiap value. Ubah sebelum publish ke production.

4. **CharacterAutoLoads = false** — di-set di TIGA tempat (server init, MainMenuService, PlayerService boot). Kalau player ke-stuck "loading character", kemungkinan ada race antara init.server.luau dan MainMenuService.

5. **DataStore key**: `RoblokFPS_PlayerData_v1`. Bumping ke `_v2` butuh migration handler. Schema migration sekarang via `mergeDefaults()` di PlayerDataService — handle field-level missing keys.

6. **Legacy testing coin value 9_999_999_999** — di-detect & reset ke `StartingCoins`. Kalau ada user tagih coin hilang, cek apakah dia kebagi sebelumnya 9.99B.

7. **Friendly fire** — OFF di casual (cek `MatchStateService.GetGamemode() == "casual"` di WeaponService). ON di DM (free-for-all).

8. **Headshot ignore range falloff** — full damage * headshotMultiplier di jarak berapapun (CS-style).

---

## Catatan tier & data

- **Roblox Studio MCP**: official + free. Semua 24 tools tersedia (termasuk `execute_luau`). No paywall.
- **Roblox DataStore**: pakai prod DataStore di game published. Di Studio test session, DataStore.GetAsync ke-skip → fallback ke in-memory profile (saved di `[PlayerData] DataStore unavailable - using in-memory only.` log).

---

## Komandos cepat

```bash
# Rojo dev sync
rojo serve

# Force build .rbxl dari current src/
rojo build -o Deathmatch.rbxl

# Re-extract scripts dari .rbxl (kalau abis kerja di PC lain)
lune run scripts/extract.luau deathmatch.rbxl

# Verify Roblox Studio MCP daemon
curl -s http://localhost:13469/health
# OK
# Studios: 1   (kalau 0, toggle Assistant MCP belum ON)
# Tools cached: 24

# Re-register Roblox Studio MCP kalau ke-drop
claude mcp add roblox-studio -- /Applications/RobloxStudio.app/Contents/MacOS/StudioMCP --stdio
```
