# RoblokFPS — Asset List

Semua gambar, ikon, dan frame yang dibutuhkan untuk redesain mobile UI ke arah **"Tactical Energetic FPS"**.

> **Sumber:** Roblox Asset ID (upload `.png` via Creator Hub → Assets → Decals/Images). Aset bawaan Roblox (`rbxasset://`) gratis & legal.
> **Resolusi PNG ideal:** ikon kecil 64×64 atau 128×128. Frame 9-slice 256×256. Background hero 1024×1024.
> **Format:** PNG transparan (alpha). Avoid JPG (no alpha).

---

## 🎯 Priority Tier

| Tier | Kapan dibutuhin | Berapa aset |
|---|---|---|
| **P0** — KILL/COMBAT | KillFeed, Announcement, DamageDirection redesign | ~8 ikon |
| **P1** — NAVIGATION | MainMenu mode select, side buttons | ~10 ikon |
| **P2** — ECONOMY | Shop, Crate, BattlePass, Cosmetics, Currency | ~12 ikon |
| **P3** — HUD | Health, Ammo, Match state | ~6 ikon |
| **P4** — FRAMES | Modal/notification 9-slice backgrounds | ~5 frame |
| **P5** — DECORATION | Hero bg, particle textures | ~6 asset |

---

## P0 — Combat & Kill (paling dipanggil user)

| Asset | Spec | Pakai di | Catatan |
|---|---|---|---|
| **Skull headshot badge** | 64×64, white silhouette skull on red | KillFeed (HS variant) | Replace "HS" text label. Tier-color tint untuk legendary headshot. |
| **Weapon icons (5)** | 128×64 horizontal silhouette, white on transparent | KillFeed weapon column, Loadout cards, BuyMenu | id: `rifle`, `pistol`, `smg`, `sniper`, `knife`. Style: flat solid silhouette, no detail (small render size). |
| **Kill notification chevron** | 32×32, ">" arrow icon, white | KillFeed killer→victim separator | Replace text "X" with proper arrow. |
| **Damage direction arrow** | 96×96, soft red glow gradient | DamageDirectionController | Bigger than current 60px "▲" text. With glow halo. |
| **Bullet impact spark** | 64×64 sprite sheet 4-frame | DamageFlash, Hit effect | Optional — Roblox built-in `rbxasset://textures/particles/sparkles_main.dds` works for now. |
| **Crosshair shapes (4)** | 32×32 each: dot, classic, dynamic, X | SettingsController crosshair editor | Currently drawn via Frames (works). Image variants add polish. |
| **Domination crown** | 96×96, golden crown | Announcement banner (DOMINATOR) | For 6+ kill streak celebration. |
| **Knife slash effect** | 256×128 streak | Melee kill particle | Replaces generic sparkles for knife kills. |

---

## P1 — Navigation & Modes

| Asset | Spec | Pakai di |
|---|---|---|
| **PLAY icon** | 64×64, ▶ chevron | MainMenu main CTA |
| **Deathmatch mode icon** | 96×96, crossed pistols/swords silhouette | MainMenu mode card |
| **Casual mode icon** | 96×96, bomb / defuse C4 | MainMenu mode card (when casual visible) |
| **Training mode icon** | 96×96, target with arrows | MainMenu mode card (Practice) |
| **Loadout nav icon** | 48×48, weapon rack / clipboard | MainMenu sidebar |
| **Cosmetics nav icon** | 48×48, paint roller / brush stroke | MainMenu sidebar |
| **Shop nav icon** | 48×48, $ coin stack | MainMenu sidebar |
| **Battle Pass nav icon** | 48×48, star with ribbon | MainMenu sidebar |
| **Missions nav icon** | 48×48, checklist / scroll | MainMenu sidebar |
| **Settings nav icon** | 48×48, gear | MainMenu sidebar |

> **Style:** Konsisten dengan FPS militeristik. Line weight 4-6px, no skeumorph, flat silhouette putih (color-tint via UI code).

---

## P2 — Economy & Reward

| Asset | Spec | Pakai di |
|---|---|---|
| **Coin icon** | 32×32, gold circle with "$" or stylized C | CurrencyController, Shop, KillFeed |
| **Gem / premium currency icon** (jika ada) | 32×32, cyan crystal | Future premium |
| **Crate / loot box icon** | 128×128, weapon case 3/4 angle silhouette | CrateController, Shop |
| **Battle Pass badge** | 96×96, shield with star | BattlePassController, MainMenu |
| **Tier rank icons (8 tiers × 3 sub = 24)** | 96×96 each | RankSystem, Scoreboard | See breakdown below |
| **XP burst** | 128×128 radial glow | Level up celebration |
| **Mission complete checkmark** | 64×64, ✓ circle with glow | MissionController |
| **Daily reward calendar icon** | 48×48 | EngagementController |
| **Streak fire icon** | 32×32 flame | EngagementController daily streak |

### Tier rank icons breakdown (24 total)

`bronze 1/2/3` → `silver 1/2/3` → `gold 1/2/3` → `platinum 1/2/3` → `diamond 1/2/3` → `master 1/2/3` → `immortal 1/2/3` → `radiant`.

Style: shield/chevron shape with metallic color + sub-rank stars (1=1 star, 2=2 stars, 3=3 stars). Reference: Valorant rank icons.

**Cara cepat sourcing:** Search Creator Store "rank badge pack" — ada beberapa free pack. Atau commission lewat Roblox forum / Fiverr.

---

## P3 — HUD elements

| Asset | Spec | Pakai di |
|---|---|---|
| **Heart / HP icon** | 24×24, white heart or shield | HealthController |
| **Bullet / ammo icon** | 24×24, side-view bullet | WeaponController HUD ammo |
| **Magazine icon** | 24×24, full mag silhouette | WeaponController ammo |
| **Timer / clock icon** | 24×24 | MatchStateController |
| **Player count icon** | 24×24, person silhouette | MatchHUD if showing player count |
| **Voice indicator (mic)** | 24×24 | (Future) chat |

---

## P4 — Frames & Backgrounds

### Modal frame (9-slice)

Sliced PNG yang bisa di-tile untuk modal panel.

| Asset | Spec | Catatan |
|---|---|---|
| **Modal panel 9-slice** | 256×256, dark center + 14px corner radius, 2px neon edge stroke | Center transparent, edges painted with subtle gradient. Variants: default (cyan), legendary (gold), epic (purple). |
| **Notification toast 9-slice** | 128×128, dark with subtle tier-color edge left | KillFeed/toast container |
| **Hero banner 9-slice** | 256×128, very dark with cyan ambient glow | Announcement banner background |

> Implementasi: Pakai `ImageLabel.ScaleType = Slice` + `SliceCenter` properties. Roblox dokumentasi: https://create.roblox.com/docs/ui/9-slice

### Surface textures (subtle, optional)

| Asset | Spec | Pakai |
|---|---|---|
| **Carbon fiber tile** | 128×128 seamless | Modal background overlay 10% opacity |
| **Tech grid lines** | 256×256 seamless | HUD background pattern, very low opacity |
| **Diagonal stripe** | 64×64 seamless | Loading bar pattern |

---

## P5 — Decoration & Background

| Asset | Spec | Pakai |
|---|---|---|
| **Hero background (Main Menu)** | 1920×1080, dark warehouse / shooting range, vignette | MainMenuController hero bg |
| **Skybox accent gradient** | 256×1024 vertical gradient | MainMenu warm glow overlay (currently programmatic) |
| **Particle: sparks (kill effect)** | 64×64 sprite | Particle emitters |
| **Particle: smoke** | 128×128 sprite | Bomb plant effect (casual) |
| **Particle: ember (legendary)** | 64×64 glow sprite | Legendary crate open |
| **Confetti burst** | 256×256 sprite sheet | Match win celebration |

---

## 🎨 Cara mendapatkan asset

### Option A — Roblox Creator Store (free / cheap)

Cari di [create.roblox.com → Marketplace](https://create.roblox.com/store):

- Search "UI icon pack" — banyak yang free
- Search "weapon icons" — ada beberapa FPS-style pack
- Search "rank badges" — bronze-radiant pack
- Search "particles sparkles fire"

Cara insert: Studio → Toolbox → search → drag ke project → catat AssetId.

### Option B — Source dari luar Roblox

Generate via:
- **Figma** + free icon libs (Lucide, Heroicons, Tabler — semuanya MIT/Apache lisensi)
- **Krita / Photoshop** untuk frame 9-slice custom
- **Aseprite** untuk pixel art weapon icons
- **AI image gen** (Midjourney/SD/DALL-E) — prompt: "tactical FPS weapon icon, flat silhouette, white on transparent, military style, no detail, 128x128"

Upload ke Roblox: Creator Hub → My Creations → Images → Upload (gratis). Dapet AssetId.

### Option C — Procedural (fallback, sekarang dipakai)

LoadoutController udah punya `drawAK/drawAWP/drawGlock/drawKnife` (vector frames Lua). Cocok untuk MVP. Trade-off: pakai banyak Frame instances per card, performance OK but bisa heavy di low-end mobile.

---

## 📦 AssetIds.luau (proposed module)

Setelah upload asset, daftarkan ID centralized di module ini:

```luau
-- src/shared/Modules/AssetIds.luau
return {
    Icons = {
        Close = "rbxassetid://XXXXXXXXX",
        Skull = "rbxassetid://XXXXXXXXX",
        Coin = "rbxassetid://XXXXXXXXX",
        Weapon = {
            rifle = "rbxassetid://XXXXXXXXX",
            pistol = "rbxassetid://XXXXXXXXX",
            smg = "rbxassetid://XXXXXXXXX",
            sniper = "rbxassetid://XXXXXXXXX",
            knife = "rbxassetid://XXXXXXXXX",
        },
        Mode = { deathmatch = ..., casual = ..., training = ... },
        Nav = { loadout = ..., shop = ..., battlepass = ..., ... },
    },
    Frames = {
        ModalPanel = "rbxassetid://XXXXXXXXX",
        Toast = "rbxassetid://XXXXXXXXX",
        Banner = "rbxassetid://XXXXXXXXX",
    },
    Particles = {
        Sparks = "rbxassetid://XXXXXXXXX",
        Smoke = "rbxassetid://XXXXXXXXX",
    },
}
```

---

## ✅ Quick-start (minimal viable assets)

Kalau mau jalan cepet dengan polish kelihatan, prioritas upload:

1. **5 weapon icons** (P0) — visible di KillFeed setiap kill
2. **Skull headshot badge** (P0) — kelihatan jelas pas HS
3. **Coin icon** (P2) — di setiap currency display
4. **Crate icon** (P2) — main visual di CrateController
5. **PLAY chevron + 6 nav icons** (P1) — MainMenu look fresh

Total: ~13 asset uploads. Bisa selesai dalam 1-2 jam kalau dari pack yang udah ada di Creator Store.

Sisanya bisa pakai prosedural / placeholder dulu (ada fallback di code).

---

## 🔄 Workflow update asset

1. Cari/buat asset di Figma/Photoshop/AI
2. Upload ke Roblox Creator Hub → catat AssetId
3. Update `AssetIds.luau` module dengan ID baru
4. Controller-controller import: `local AssetIds = require(Shared.Modules.AssetIds)` lalu `imageLabel.Image = AssetIds.Icons.Skull`
5. Test di Studio play mode → screenshot → verify look

Single source of truth = AssetIds module. Mau A/B test? Tinggal swap ID di satu tempat.
