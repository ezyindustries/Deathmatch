# Roblox Studio MCP — Panduan Lengkap

> **Untuk siapa:** Pemula yang lagi develop Roblox game dan mau pakai Claude (AI) untuk bantuin lewat Studio MCP — bisa execute Luau, inspect game tree, capture screen, dll.
> **Last updated:** 2026-05-20
> **Diuji di:** Roblox Studio 0.721.0.7211107 (macOS), Claude Code

---

## 📋 Daftar Isi

1. [Apa itu Roblox Studio MCP?](#1-apa-itu-roblox-studio-mcp)
2. [Setup 1 Kali (First-Time)](#2-setup-1-kali-first-time)
3. [Aktifkan Plugin tiap Studio Buka](#3-aktifkan-plugin-tiap-studio-buka)
4. [Tools yang Tersedia (Cheat Sheet)](#4-tools-yang-tersedia-cheat-sheet)
5. [Pola Penggunaan Umum](#5-pola-penggunaan-umum)
6. [Audit & Debug Workflow](#6-audit--debug-workflow)
7. [Limitations & Gotchas](#7-limitations--gotchas)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Apa itu Roblox Studio MCP?

**Roblox Studio MCP** = bridge antara Claude (AI assistant) dengan Roblox Studio kamu.

Komponen:
- **StudioMCP binary** (`/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP` di Mac) — daemon yang listen di `localhost:13469`, jalanin saat Studio start
- **Studio Assistant** (built-in feature di Roblox Studio) — UI yang ngomong ke StudioMCP daemon
- **Claude (via MCP)** — pakai tool `mcp__roblox-studio__*` untuk komunikasi via daemon

Flow:
```
Claude → mcp__roblox-studio__execute_luau → StudioMCP daemon → Studio Assistant → Studio runtime → result balik
```

### Yang bisa dilakukan Claude lewat MCP:
- ✅ Execute Luau code di Studio (edit mode atau play mode)
- ✅ Read script content
- ✅ Edit script content (multi_edit)
- ✅ Search/inspect game tree (Workspace, ReplicatedStorage, dll)
- ✅ Screen capture untuk lihat HUD/scene
- ✅ Start/stop Play mode
- ✅ Insert assets dari Creator Store
- ✅ Generate mesh AI (procedural)
- ✅ Mouse/keyboard input simulation (terbatas)
- ✅ Console output (print/warn/error)

---

## 2. Setup 1 Kali (First-Time)

### Prerequisites
- macOS atau Windows
- Roblox Studio installed
- Claude Code atau Claude Desktop dengan MCP config

### Step 1: Pastikan StudioMCP daemon ter-include
StudioMCP daemon biasanya sudah ter-bundle di Roblox Studio modern. Cek dengan:

**Mac:**
```bash
ls /Applications/RobloxStudio.app/Contents/MacOS/StudioMCP
# Harus ada
```

**Windows:**
```
C:\Users\YOURNAME\AppData\Local\Roblox\Versions\version-XXXX\StudioMCP.exe
```

Kalau gak ada, update Studio ke versi terbaru.

### Step 2: Konfigurasi Claude untuk pakai MCP
Di `~/.claude/mcp_settings.json` atau equivalen, tambahkan:
```json
{
  "mcpServers": {
    "roblox-studio": {
      "url": "http://localhost:13469"
    }
  }
}
```

(Atau pakai Claude Desktop GUI: Settings → MCP Servers → Add)

### Step 3: Buka Studio
- Buka file `.rbxlx` apapun
- Studio start otomatis spawn StudioMCP daemon di background (proses bernama `StudioMCP`)

### Step 4: Aktifkan Studio Assistant
- Pojok kanan atas Studio: cari icon **Assistant** (kotak chat-bubble, kadang sparkle ✨)
- Atau via View > Assistant
- Kalau gak ketemu, mungkin perlu enable via:
  - **File > Beta Features** → cari "Studio Assistant" / "Studio AI" → enable → restart Studio

### Step 5: Aktifkan MCP Server di Assistant
- Di panel Assistant, klik **gear ⚙️** (settings)
- Atau **3-dot menu (…)** → Settings
- Toggle **"MCP Server"** = **ON**
- ⚠️ **Step ini WAJIB** — tanpa ini, Claude gak bisa connect

### Step 6: Verify dari Claude side
Tanya Claude: "Cek apakah MCP Roblox Studio aktif". Claude akan call `list_roblox_studios` dan return:
```json
{"studios":[{"active":true,"id":"abc-xyz","name":"YourPlace.rbxlx"}]}
```

Kalau `studios: []` = belum connect. Cek ulang Step 5.

---

## 3. Aktifkan Plugin tiap Studio Buka

**Setiap kali tutup-buka Studio**, MCP perlu di-trigger ulang:
1. Buka Studio + place file
2. Klik icon Assistant
3. Kalau **MCP Server** ke-reset ke OFF, toggle ON lagi
4. Klik Connect dari Rojo plugin (kalau ada dialog)

**Tip**: Studio Assistant kadang auto-toggle MCP OFF. Selalu cek dulu sebelum minta Claude do audit.

---

## 4. Tools yang Tersedia (Cheat Sheet)

### Studio control
| Tool | Fungsi | Contoh |
|---|---|---|
| `list_roblox_studios` | List Studio instances | Verify MCP connected |
| `set_active_studio` | Pilih studio aktif (kalau >1 nyala) | Buat focus |
| `start_stop_play` | Play / Stop game | `{is_start: true}` |

### Code & game tree
| Tool | Fungsi | Tip |
|---|---|---|
| `execute_luau` | Run Luau code, return value | **PENTING**: pas play mode, jalan di CLIENT context (`IsServer=false`). ServerScriptService gak visible dari sini. |
| `script_read` | Baca script source | Path: `game.ServerScriptService.Services.MyService` |
| `multi_edit` | Edit script (multiple changes atomic) | Bisa create new script juga |
| `script_search` | Cari script by name keyword | Fuzzy match |
| `script_grep` | Cari pattern dalam script content | Max 50 hits |
| `inspect_instance` | Detail Instance (properties, attributes, children) | Lebih dalam dari game tree |
| `search_game_tree` | Explore hierarchy | Filter by path/type/keyword |

### Visual
| Tool | Fungsi |
|---|---|
| `screen_capture` | Take screenshot dari Studio viewport |
| `generate_mesh` | AI-generate textured mesh dari prompt |
| `generate_material` | AI-generate MaterialVariant |
| `generate_procedural_model` | Generate model dari primitives (block, sphere, dll) |

### Input simulation (terbatas)
| Tool | Fungsi |
|---|---|
| `user_keyboard_input` | Press/hold key |
| `user_mouse_input` | Click/drag/scroll |
| `character_navigation` | Walk character ke posisi |

### Console
| Tool | Fungsi |
|---|---|
| `get_console_output` | Read recent Studio output (print/warn/error) |

### Misc
| Tool | Fungsi |
|---|---|
| `search_creator_store` | Cari asset di marketplace |
| `insert_from_creator_store` | Insert asset hasil search |
| `subagent` (explore) | Spawn fast read-only subagent untuk investigate |
| `from_history` | Recall data dari compacted conversation |

---

## 5. Pola Penggunaan Umum

### Pola 1: Audit struktur game tree
```luau
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SP = game:GetService("StarterPlayer")
local result = {
  ConfigCount = #RS.Shared.Configs:GetChildren(),
  ServiceCount = #SSS.Services:GetChildren(),
  ControllerCount = #SP.StarterPlayerScripts.Controllers:GetChildren(),
}
return result
```

### Pola 2: Cek runtime state (play mode)
```luau
task.wait(10) -- biarkan bootstrap selesai
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local gui = lp:WaitForChild("PlayerGui", 5)
local names = {}
for _, g in ipairs(gui:GetChildren()) do
  if g:IsA("ScreenGui") then table.insert(names, g.Name) end
end
return { ScreenGuiCount = #names, Names = names }
```

### Pola 3: Inject probe untuk debugging
```luau
-- Saat develop service baru, tambah print marker di Bootstrap:
print("[PROBE-A] Bootstrap line 1")
local Service = require(...)
print("[PROBE-B] After require")
Service.Start()
print("[PROBE-C] After Start")
-- Habis itu cek output via get_console_output
```

### Pola 4: Tes require chain (cari script yang error)
```luau
local result = {}
for _, name in ipairs({"ServiceA", "ServiceB", "ServiceC"}) do
  local mod = workspace:FindFirstChild(name) -- adjust path
  local ok, err = pcall(require, mod)
  result[name] = ok and "OK" or "ERR: " .. tostring(err):sub(1, 200)
end
return result
```

### Pola 5: Read script + manual fix
```
# Claude flow:
1. mcp__roblox-studio__script_grep("pattern")  -- find issue
2. mcp__roblox-studio__script_read(path, line_start, line_end)
3. mcp__roblox-studio__multi_edit(path, [{old_string, new_string}])
4. mcp__roblox-studio__execute_luau("verify fix")
```

### Pola 6: Restart play untuk fresh runtime
```
1. start_stop_play(is_start=false)  -- stop
2. (filesystem edits via Edit/Write tool, atau script edits via multi_edit)
3. start_stop_play(is_start=true)   -- restart
4. execute_luau("verify")
```

---

## 6. Audit & Debug Workflow

### Pola audit lengkap pas mau verify integrasi besar:

```
1. STOP play (kalau lagi running)
2. Verify Studio data model lengkap:
   - script_search "ServiceName"  → ada/ngga
   - execute_luau hitung #ServerScriptService.Services:GetChildren()
3. START play
4. task.wait(15) lalu execute_luau cek:
   - RemoteEvents count (server bootstrap completed?)
   - PlayerGui ScreenGui count (client controllers ran?)
   - Workspace.Areas/NPCs/etc (builder scripts ran?)
5. get_console_output  → cari error / stack trace
6. screen_capture  → visual confirm HUD render
7. Identify bug:
   - Server bootstrap hang → recursion / require error?
   - Client bootstrap hang → require chain WaitForChild forever?
8. Fix via Edit/multi_edit
9. STOP + RESTART play
10. Repeat dari step 4
```

### Common debug patterns

**Server bootstrap hung di require:**
- Cek console untuk error stack
- Cek setiap service top-level untuk `WaitForChild` without timeout
- Cek for ambiguous syntax `(x :: T).Y = z` at line-start

**Client controllers gak run:**
- Cek PlayerGui count — kalau cuma BubbleChat/Chat/Freecam = ClientBootstrap chain broke
- Tes individu: `pcall(require, ctrls.ControllerName)` untuk cari yang error
- Common cause: top-level `require()` yang nge-error pas modul load

**DataService.Update infinite recursion:**
- Tipikal di OnChange listener yang call Update lagi
- Stack trace: `notifyChange → Update → ensureState → Update → ...`
- Fix: jangan call Update dari dalam OnChange listener — guard pakai flag atau pindahkan ke PlayerAdded

---

## 7. Limitations & Gotchas

### 1. Execute Luau context
Saat play mode, `execute_luau` jalan sebagai **LocalScript di Studio command bar**:
- `IsServer = false`
- `IsClient = true`
- ServerScriptService **kosong** dari sini (server-only, gak replicated)
- Solusi: query ReplicatedStorage atau PlayerGui untuk verify state

Saat edit mode, jalan di **dual context** (both IsServer and IsClient true).

### 2. Console buffer terbatas
- `get_console_output` cuma return ~50-100 baris paling baru
- Kalau ada banyak DataStore 403 error (unpublished place), itu spam buffer dan ngumpetin error penting
- Solusi: stop play, save place (Cmd+S), restart, immediately check console

### 3. Studio Play restart unreliable
- `start_stop_play(false)` kadang gak benar-benar kill server runtime (ghost session)
- Indikator: timestamp konsisten error dengan duplikasi entries
- Solusi: kalau aneh, klik **Stop button manual** di Studio toolbar

### 4. Sync timing
- Filesystem edit via Edit/Write tool → Rojo serve push ke Studio (perlu rojo serve running)
- multi_edit via MCP → langsung ke Studio in-memory (filesystem gak terupdate)
- Pilih cara yang konsisten — jangan campur (bisa drift)

### 5. Ambiguous syntax in Luau strict
Pattern berbahaya yang sering bikin script error tanpa pesan jelas:
```lua
-- ❌ BAHAYA:
local foo = bar:GetSomething()
(foo :: SomeType).Bar = 5  -- Luau parses as: bar:GetSomething()(foo :: SomeType).Bar = 5

-- ✅ FIX:
local foo = bar:GetSomething()
local typed = foo :: SomeType
typed.Bar = 5

-- Atau pakai `;`:
local foo = bar:GetSomething();
(foo :: SomeType).Bar = 5
```

Cari pattern ini:
```bash
grep -rn "^\s*(.*::.*)\." src/
```

### 6. WaitForChild default timeout
- `WaitForChild("X")` tanpa timeout = **infinite wait** (cuma warn after 5s)
- Kalau X gak pernah ada, script hang forever
- ALWAYS pakai timeout: `WaitForChild("X", 5)` lalu cek nil

### 7. DataStore di Studio
- Unpublished place: 403 "Cannot write to DataStore from studio if API access is not enabled"
- Fix: `Home > Game Settings > Security > Enable Studio Access to API Services = ON`
- Atau accept failure (game tetap jalan, save/load skip via pcall)

### 8. MCP "Studio disconnected" errors
Cara reset:
1. Tutup Studio
2. Re-open file
3. Aktifkan Assistant
4. Toggle MCP Server: OFF → ON
5. `list_roblox_studios` from Claude — harus muncul lagi

---

## 8. Troubleshooting

### Q: `list_roblox_studios` return `{studios: []}`
**Cause:** Studio Assistant > MCP Server OFF, atau Assistant belum aktif.
**Fix:**
1. Klik Assistant icon di Studio
2. Settings → toggle MCP Server ON
3. Tunggu ~5 detik
4. Coba lagi

### Q: `execute_luau` return error "Studio disconnected"
**Cause:** Studio MCP plugin lost connection.
**Fix:**
1. Cek `curl -s http://localhost:13469/health` — harus return "Studios: N"
2. Kalau N=0, restart Assistant via toggle OFF/ON
3. Atau full restart Studio

### Q: Bootstrap script gak run, no console error
**Possible causes:**
- Top-level `require()` hangs di WaitForChild
- Top-level `require()` error (cached, no stack trace)
- Ambiguous syntax issue

**Debug:**
```lua
-- Inject di awal Bootstrap:
print("[BOOT-A]")
local DataService = require(...)
print("[BOOT-B]")
-- ... etc
```

### Q: Client UIs gak muncul (PlayerGui kosong)
**Causes:**
- ClientBootstrap require chain broke (1 controller has runtime error)
- HUDController.Start() fails

**Debug:**
```lua
-- Test require tiap controller
local ctrls = lp.PlayerScripts.Controllers
for _, name in ipairs({"HUDController", "FishingController", ...}) do
  local ok, err = pcall(require, ctrls[name])
  print(name, ok, err)
end
```

### Q: Console penuh dengan DataStore 403 errors
**Cause:** Unpublished place, DataService save loop running.
**Fix (tidak masalah, cuma noise):**
- `Home > Game Settings > Security > Enable Studio Access to API Services = ON`
- Atau biarkan — code sudah pcall-wrapped, gak crash

### Q: Studio play gak benar-benar stop
**Cause:** Bug MCP `start_stop_play` reliability.
**Fix:** Klik Stop button manual di Studio toolbar (kotak merah).

### Q: Rojo dialog "Confirm sync" muncul terus
**Cause:** Filesystem ada perubahan yang belum di Studio.
**Fix:** Klik **Accept** untuk apply. Kalau gak yakin, klik **Abort** lalu cek `git diff`.

### Q: Lupa save FishIsland.rbxlx sebelum close Studio
**Cause:** Studio in-memory state hilang saat close.
**Mitigasi:** Source code di `src/` aman (gitignored? cek `.gitignore`). Rojo serve rebuild Studio state dari filesystem.

---

## 🧰 Quick Commands Cheat Sheet

```bash
# Cek StudioMCP daemon
curl -s http://localhost:13469/health
# Expected: "OK\nStudios: 1\nProxies: 1\nTools cached: 22"

# Cek StudioMCP process
pgrep -fl StudioMCP

# Cek Rojo serve
pgrep -fl "rojo serve"
# Kalau gak ada, run: rojo serve

# Build place file via rojo
rojo build -o /tmp/check.rbxlx

# Open file di Studio via terminal (Mac)
open "/path/to/YourPlace.rbxlx"
```

---

## 📚 Referensi

- StudioMCP daemon source (Anthropic Roblox docs)
- Rojo docs: https://rojo.space/
- Lune docs: https://lune-org.github.io/docs (untuk CLI testing)
- Roblox Luau reference: https://luau-lang.org/

---

**Catatan:** File ini standalone — gak perlu konteks lain. Kalau di sesi baru, kasih file ini ke Claude:
> "Baca ROBLOX_MCP_GUIDE.md dulu untuk paham setup MCP. Lalu bantu aku dengan [tugas X]."
