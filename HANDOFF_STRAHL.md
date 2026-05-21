# Handoff buat Strahl — RoblokFPS (Deathmatch)

> Dokumen ini ringkas semua yang dikerjakan dari awal sampai sekarang. Tujuannya supaya kamu bisa langsung kontribusi tanpa harus baca semua commit history. Project state per **2026-05-21**.

---

## 🎮 Apa yang Kita Bangun

**RoblokFPS** — Roblox FPS multiplayer dengan 2 gamemode:
- **Deathmatch (DM)** — sekarang **10v10 Team Deathmatch** (Tim Kawan biru vs Tim Lawan merah)
- **Casual** — CS-style 5v5 T vs CT bomb defuse (hidden dari player tapi kode lengkap, lihat `src/server/Services/CasualService.luau`)

Build aktif: **DM only**. Casual ke-hide dari main menu.

### Game flow sekarang

```
Main Menu (4 tombol)
├── QUICK PLAY      → Roblox auto-matchmaking, masuk server existing/baru
├── SERVER BROWSER  → list public sessions, pilih sendiri
├── CREATE PARTY    → reserved server, generate 6-char code, optional bots
└── JOIN BY CODE    → masukin 6-char code dari temen

In-match (DM):
TeamSelect modal force-open → pilih TIM KAWAN / TIM LAWAN / AUTO-ASSIGN
↓
20 combatants di arena (10v10). Solo player = 1 + 19 bots.
↓
Bot AI: search → shoot → dodge. Filter by enemy team only.
Friendly fire OFF.
↓
Scoreboard 2-column. KillFeed nama biru (teman) / merah (lawan).
MatchHUD chip "● MATCH 5:23 ▸ 47-32".
```

---

## 🗺️ Workflow Development (penting)

### Dari Mac via terminal

Project di `/Users/macstudio/roblox game/gamenya al deathmatch`. Pakai Claude Code via terminal — bisa edit source code + jalanin perintah Studio via MCP.

**2 jalur sync ke Studio:**

1. **Rojo** (file disk ↔ Studio tree)
   ```bash
   rojo serve  # listen di localhost:34872
   ```
   Lalu di Studio: Plugins → Rojo → Connect. Source code auto-sync 2-arah.
   
   ⚠️ **Gotcha**: Rojo kadang disconnect saat play mode. Pattern aman:
   - Edit disk
   - Studio: Disconnect → Connect Rojo lagi
   - Stop play → Play (snapshot rebuilt)

2. **Studio MCP** (Claude Code ↔ Studio runtime)
   - Daemon: `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP` di port 13469
   - 24 tools tersedia: `execute_luau`, `screen_capture`, `start_stop_play`, dll
   - Health check: `curl http://localhost:13469/health`
   - Toggle MCP server di Studio Assistant (3-dot menu → Manage MCP Servers → "Enable Studio as MCP server" ON)
   - Detail lengkap: lihat `ROBLOX_MCP_GUIDE.md`

### Testing

```bash
# Unit tests (Lune)
lune run tests/runner.luau

# 62 tests, all should pass
```

### Build + Publish

```bash
# Build .rbxl dari src/
rojo build -o Deathmatch.rbxl

# Atau di Studio: File → Publish to Roblox
```

### Re-extract dari .rbxl (kalau abis kerja di Mac lain)

```bash
lune run scripts/extract.luau deathmatch.rbxl
```

---

## 🏗️ Arsitektur

### Boot sequence

- **Server**: `src/server/init.server.luau` iterate `Services/:GetChildren()` dan `require()` semua (pcall-wrapped). Order **tidak deterministic** — lazy-require pattern dipakai buat circular deps.
- **Client**: `src/client/init.client.luau` iterate `Controllers/:GetChildren()` dan `require()` semua.

### Match state machine

```
LOBBY → VOTING → STARTING → MATCH → ENDING → LOBBY ...
```

- **LOBBY** 2s (test) / 30s (prod)
- **VOTING** 7s (3 random map per round)
- **STARTING** ArenaService build map + teleport players
- **MATCH** 360s gameplay
- **ENDING** scoreboard + reward, lalu teleport balik ke lobby

`CasualService.HoldAutoAdvance(true)` dipake selama casual MATCH biar round loop manual.

### Top services (`src/server/Services/`)

| Service | Job |
|---|---|
| `MatchStateService` | State machine + StateChanged signal |
| `VotingService` | 3 random map vote, set gamemode dari winning map |
| `ArenaService` | Build/destroy map via MapBuilders, lighting presets, OOB death (Y < -200) |
| `DeathmatchBotService` | Bot fill, AI tick, evasion, scan, team split |
| **`DeathmatchTeamService`** (baru) | Player+bot team assignment, 30s switch cooldown, broadcast team state |
| `WeaponService` | Loadout, fire validation, raycast hit, **friendly fire OFF in DM** |
| `ScoringService` | Per-player K/D, kill streaks, MVP, **team kill aggregation** |
| `MainMenuService` | RequestSpawn/ExitToMainMenu, **late-join arena teleport** |
| `LobbyBuilderService` | Build lobby geometry on require |
| **`SessionAdvertiser`** (baru) | Publish server state ke MemoryStore SortedMap per 8s |
| **`SessionDirectory`** (baru) | ListPublicSessions RemoteFunction, baca + cache 3s |
| **`PrivateLobbyService`** (baru) | CreatePrivateLobby + JoinSessionByCode via ReserveServer + 6-char code di HashMap |
| **`JoinByCodeService`** (baru) | JoinSessionByJobId via TeleportToPlaceInstance |
| `PlayerDataService` | DataStore `RoblokFPS_PlayerData_v1`, auto-save 60s + BindToClose |
| `CrateService` | Gacha (pity 75 = Legendary, 0.5% karambit) |
| `BattlePassService`, `MissionService`, `MonetizationService`, dll. |

### Top controllers (`src/client/Controllers/`)

**HUD in-match:**
- `MatchStateController` (chip + timer + team score)
- `HealthController` (HP bar top-left)
- `ScoreboardController` (mini 2-row + full Tab 2-column)
- `KillFeedController` (team-colored names, hidden di mobile <900)
- `WeaponController` (FIRE button, ADS column, ammo, hotbar)
- `DamageDirectionController`, `DamageFlashController`, `AnnouncementController`
- `BotRadarController` (radar bulat tunjukin live bot positions)
- `TopbarController` (disable CoreGui Chat/Backpack/PlayerList/Health/EmotesMenu)

**Menu/modal:**
- `MainMenuController` (2×2 grid: QUICK PLAY / SERVER BROWSER / CREATE PARTY / JOIN BY CODE)
- **`TeamSelectController`** (baru — modal pilih kawan/lawan, sticky kalau unassigned, 30s cooldown indicator)
- **`ServerBrowserController`** (baru — list public sessions, refresh + auto-poll 8s)
- **`PrivateLobbyController`** (baru — Stage A create dengan bots toggle + max players stepper, Stage B lobby view dengan code + COPY + members + READY/START/LEAVE)
- **`JoinByCodeController`** (baru — 6-box code input, auto-advance)
- `PauseMenuController`, `SettingsController`, `ShopController`, `CosmeticsController`, `CrateController`, `LoadoutController`, `BuyMenuController`, `VotingController`, `SpectatorController`, `EngagementController`

### Shared modules (`src/shared/Modules/`)

| Module | Role |
|---|---|
| `Remotes` | RemoteEvents + **RemoteFunctions** registry, auto-create di ReplicatedStorage.Remotes |
| `MatchState` | State enums + config |
| `WeaponConfig` | Weapon registry (damage, fireRate, range, falloff, dll) |
| `MapRegistry` | Map metadata + supportedModes |
| `GameConfig` | Match durations, movement, bloom, coin/XP rates, crate drop |
| `CasualConfig` | Round timer, plant/defuse, buy time |
| `CosmeticRegistry` | Skin pool buat gacha |
| `RankSystem` | XP → rank (Bronze 1 → Immortal 3) |
| `BattlePassConfig`, `ProductsConfig`, `MissionConfig`, `AudioConfig` |
| `Teams` | T vs CT constants (casual mode) |
| **`DMTeams`** (baru) | A/B team constants, "Tim Kawan"/"Tim Lawan", TARGET=20, TEAM_SIZE=10, SWITCH_COOLDOWN_SEC=30, `isEnemy()`, `pickSmaller()` |
| `ClientSignals` | BindableEvents antar controllers |
| `BotModel` | R6 rig builder — **with Animator child + R6-standard Motor6D** |
| `UITheme` | Design tokens — **JANGAN DIMODIFIKASI** |

---

## 🚨 Gotchas — Wajib Tahu

### 1. Bot rendering pernah rusak — fix ada di BotModel.luau

Bot AI tetap kerja (kill registered) tapi VISUAL gak muncul di real device. Root causes:
- **Humanoid wajib punya `Animator` child** — tanpa ini, Motor6D writes gak replicate ke client
- **Motor6D wajib pakai R6 standard rotation** — `CFrame.Angles(-π/2, 0, π)` untuk root/neck, `±π/2 Y` untuk limbs
- **`model.ModelStreamingMode = Persistent`** wajib supaya parts gak culled oleh streaming
- **JANGAN set `StreamingPriority`** — itu BUKAN property valid di Model, bakal error pcall-silent

### 2. Mobile breakpoint = `viewport.X < 900`

JANGAN pakai `UserInputService.TouchEnabled` — Studio Device Emulator pasang `TouchEnabled=true AND MouseEnabled=true`, jadi check legacy break.

Breakpoints:
- mobile < 900 (iPhone 7+, X, 11, 14 Pro Max, Galaxy)
- tablet < 1300 (iPad)
- desktop ≥ 1300

### 3. Stray ActiveArena dari `deathmatch.rbxl`

Place file punya baked-in empty `ActiveArena` folder dari testing dulu. `Workspace:FindFirstChild("ActiveArena")` bisa kena yang kosong duluan.

**Fix sudah dipasang**: `ArenaService` punya init-time sweep + teardown sweep yang destroy semua stray `ActiveArena` Folder.

Kalau bug muncul lagi: di Studio edit mode, jalanin `for _,c in Workspace:GetChildren() do if c.Name=="ActiveArena" then c:Destroy() end end` lalu File → Save.

### 4. Bot spawn near player — SPAWN_NEAR_PLAYER mode

Currently `DeathmatchBotService.SPAWN_NEAR_PLAYER = true` (diagnostic). Bots spawn dalam 15-stud ring di sekitar player supaya langsung kelihatan.

Set ke `false` sebelum public release supaya bots tersebar lewat arena spawns kayak game normal.

### 5. Late-join teleport

Player yang klik PLAY mid-MATCH gak otomatis ke arena via Roblox flow. `MainMenuService.spawnInto` punya custom teleport: kalau MATCH state aktif → setelah LoadCharacter, teleport ke arena spawn point.

### 6. Topbar (Roblox Unibar) cuma sebagian bisa di-hide

Bisa: Chat, Backpack, PlayerList, Health, EmotesMenu (via `StarterGui:SetCoreGuiEnabled`)  
Gak bisa: Roblox brand logo, hamburger menu icon (policy Roblox, gak ada API)

Modal screen GUIs harus pakai `IgnoreGuiInset = false` supaya title gak ketutup topbar.

### 7. Rojo sync flakiness

Studio kadang gak pickup file disk changes meski Rojo serve jalan. Pattern aman:
- Edit disk → Rojo Disconnect → Connect → Stop play → Play
- Atau: directly modify Studio source via `execute_luau` (cara aku selama development)

### 8. MemoryStore unavailable di Studio test

`SessionDirectory`, `PrivateLobbyService` pakai MemoryStoreService yang **gak aktif di Studio Test mode**. Code wrap di pcall + return stub data buat UI testing. Real list muncul cuma di **published place**.

---

## 📦 Major Features Built (chronological)

### Round 1-5 (May 20): UI polish + bot visibility
- Mobile UI shrink across 22 controllers (vw < 900 breakpoint)
- Bot rendering fix (Animator + R6 Motor6D + StreamingPriority diagnosis)
- Modal topbar fix (IgnoreGuiInset = false)
- MatchHUD above HP bar (top-left column)
- KillFeed hidden on mobile (vw < 900)
- BotRadar HUD (live count + dots)

Commits: `27b4d3f`, `8af41bb`, `e61679e`

### Round 6 (May 20): Bot fixes
- 20 bots target (was 7)
- Ring-spawn around player (skip spawn points)
- Void watchdog (Y < -100 force-rebuild)
- ArenaService stray-folder purge
- Late-join arena teleport

Commits: `bf7f03a`, `f1144ae`, `db4b33f`, `a58c6a0`

### Multiplayer feature (May 21):
- 4 RemoteFunctions: ListPublicSessions, CreatePrivateLobby, JoinSessionByCode, JoinSessionByJobId, LeavePrivateLobby
- Server: SessionAdvertiser, SessionDirectory, PrivateLobbyService, JoinByCodeService
- Client: ServerBrowserController (544 lines), PrivateLobbyController (633 lines), JoinByCodeController (480 lines)
- MainMenu 2×2 grid

Commit: `7d82abc`

### TDM 10v10 (May 21):
- DMTeams shared module + DeathmatchTeamService (342 lines)
- TARGET 21 → 20, bot split 10v10, AI filter enemy team
- Friendly fire OFF in DM
- TeamSelectController modal (657 lines)
- Scoreboard 2-column + team score chip in MatchHUD
- KillFeed team colors (own=blue, enemy=red)
- Private server config (with bots Y/N, max players 2-20)

Commit: `25a26b6`

---

## 🐙 GitHub

Remote: `https://github.com/ezyindustries/Deathmatch`  
Branch utama: `staging`

```bash
git pull origin staging
git add src/
git commit -m "..."
git push origin staging
```

Latest commits:
- `25a26b6` feat(tdm): 10v10 Team Deathmatch + team select + private config
- `7d82abc` feat(multiplayer): server browser + private party + join-by-code
- `c4b85c0` chore: gitignore .claude/
- `a58c6a0` fix(arena+bot): purge stray ActiveArena + ring-spawn
- `db4b33f` fix(spawn): late-join teleport
- `bf7f03a` fix(bot): 21-bot target + lobby-aware ref
- `f1144ae` fix(bot): remove invalid StreamingPriority
- `e61679e` fix(ui): wider mobile breakpoint + bot radar

---

## 📋 Open TODOs / Known Issues

1. **`SPAWN_NEAR_PLAYER` masih true** — set false sebelum release production
2. **GameSetting "All Ages"** — admin task: Studio File → Game Settings → Permissions → Experience Maturity → "Minimal"
3. **Multi-server testing** — perlu publish + multi-device buat verify cross-server flow (Server Browser, Private Party)
4. **`deathmatch.rbxl` perlu di-save ulang** — supaya stray ActiveArena baked-in hilang permanent
5. **Casual mode hidden** — game saat ini DM-only; Casual mode reactivate butuh main menu update lagi

---

## 🛠️ Commands Cepat

```bash
# Dev sync
rojo serve

# Build .rbxl
rojo build -o Deathmatch.rbxl

# Re-extract dari .rbxl
lune run scripts/extract.luau deathmatch.rbxl

# Tests
lune run tests/runner.luau

# MCP health
curl -s http://localhost:13469/health
# OK / Studios: 1 / Tools cached: 24

# Re-register MCP kalau ke-drop
claude mcp add roblox-studio -- /Applications/RobloxStudio.app/Contents/MacOS/StudioMCP --stdio
```

---

## 💬 Kontak

Owner: ezy.industries@gmail.com (Mac Studio)  
Repo: github.com/ezyindustries/Deathmatch

Kalau ada yang gak jelas, baca `CLAUDE.md` buat detail arsitektur lengkap dan `ROBLOX_MCP_GUIDE.md` buat workflow MCP setup.

Selamat kerja, Strahl! 🎮
