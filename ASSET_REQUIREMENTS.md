# Asset Requirements — RoblokFPS

> **Untuk AI image gen agent (Midjourney / DALL-E / SD).**  
> Project: 10v10 Team Deathmatch FPS di Roblox.  
> Style guide: **Tactical Energetic** — flat silhouette, minimal detail, futuristik militer, neon accent (cyan + amber). White-on-transparent untuk icon (color-tint via code).
>
> File `.png` dengan **alpha transparency**. Upload ke Roblox Creator Hub → catat AssetId → daftarin di `src/shared/Modules/AssetIds.luau`.

---

## 📐 Aturan Resolusi

| Tipe | Resolusi | Format | Catatan |
|---|---|---|---|
| Icon kecil (HUD, sidebar) | **64×64** | PNG transparan | Render @ 24-48px in UI, jadi 2-3× supersample untuk crisp |
| Icon medium (mode card, badge) | **128×128** | PNG transparan | Render @ 64-96px |
| Icon besar (banner, hero) | **256×256** | PNG transparan | Render @ 128-200px |
| Map thumbnail | **512×288** (16:9) | PNG/JPG | Compress < 100KB |
| 9-slice frame | **256×256** | PNG transparan | 14px corner radius, edges tileable |
| Background hero | **1920×1080** | PNG/JPG | Dark vignette, < 500KB |
| Particle sprite | **64×64** atau **128×128** | PNG transparan | Single frame atau sprite sheet |

---

## 🎯 P0 — Asset BARU untuk TDM + Multiplayer (priority tertinggi)

Ini asset yang BELUM ada dan SANGAT terlihat di gameplay.

### 1. Team Badges (Tim Kawan / Tim Lawan)

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `team-kawan-badge.png` | **128×128** | Shield silhouette + blue cyan glow, faint emblem (chevron crossed) | TeamSelectController card, MatchHUD, Scoreboard |
| `team-lawan-badge.png` | **128×128** | Shield silhouette + red glow, faint emblem (skull crossed knives) | TeamSelectController card, MatchHUD, Scoreboard |
| `team-kawan-banner.png` | **256×128** | Wide horizontal banner blue → dark gradient | Full scoreboard 2-column header |
| `team-lawan-banner.png` | **256×128** | Wide red → dark gradient | Full scoreboard 2-column header |
| `auto-assign-icon.png` | **64×64** | Two arrows swapping (auto-balance symbol) | TeamSelectController AUTO-ASSIGN button |

**AI prompt sample:**
> "tactical FPS team shield badge, cyan blue glow, white silhouette chevron, military style, flat icon, transparent background, centered, 128x128"

---

### 2. Action Grid Icons (Main Menu 2×2)

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `action-quickplay.png` | **64×64** | Lightning bolt + crosshair (fast match feel) | QUICK PLAY button |
| `action-server-browser.png` | **64×64** | List icon with magnifying glass | SERVER BROWSER button |
| `action-create-party.png` | **64×64** | Two people silhouette + plus | CREATE PARTY button |
| `action-join-code.png` | **64×64** | Six boxes (code input style) | JOIN BY CODE button |

**Style:** Konsisten, line weight 4-6px, white silhouette pada background transparan.

---

### 3. Map Thumbnails (untuk Voting + Server Browser)

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `map-warehouse.png` | **512×288** | Top-down view warehouse industrial, crate stacks, forklift, neon accents | VotingController card, ServerBrowser row |
| `map-rooftop.png` | **512×288** | Mirage-style two buildings + plaza, sunset orange | Same |
| `map-desert.png` | **512×288** | Dust2-style desert ruins + central pillars | Same |
| `map-metro.png` | **512×288** | Underground subway station + train wreck | Same |
| `map-harbor.png` | **512×288** | Shipping yard containers + crane + catwalks | Same |
| `map-dust2.png` | **512×288** | Classic CS:GO Dust2 inspired (T spawn → mid → bombsite) | Same |

**AI prompt sample:**
> "Roblox FPS map thumbnail, isometric top-down warehouse industrial scene, crates stacks forklift, dark teal + amber lighting, low-poly stylized, 16:9, no text, 512x288"

---

### 4. Multiplayer Modal Icons

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `private-lock.png` | **64×64** | Padlock + cyan accent | PrivateLobbyController title |
| `private-code-bg.png` | **256×80** | Wide dark plate with neon edge (tempat display 6-char code) | PrivateLobby Stage B code area |
| `copy-icon.png` | **48×48** | Two overlapping rectangles | COPY button next to code |
| `invite-icon.png` | **48×48** | Person + arrow outward | (future: invite friends list) |
| `ready-check.png` | **48×48** | Green checkmark in circle | PrivateLobby member READY indicator |
| `ready-cross.png` | **48×48** | Red X in circle | PrivateLobby member NOT READY |

---

### 5. Bot Radar Assets

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `radar-bg.png` | **128×128** | Dark circular radar with concentric rings + faint grid | BotRadarController mapFrame background |
| `radar-player-dot.png` | **16×16** | Cyan filled circle with glow halo | BotRadar player center |
| `radar-enemy-dot.png` | **16×16** | Red filled triangle (direction-aware) | BotRadar enemy dots |
| `radar-ally-dot.png` | **16×16** | Cyan filled square (untuk future: ally pings) | BotRadar (TDM enhancement) |

---

## 🔥 P1 — Asset untuk Kill Feed & Combat (sudah ada di ASSETS.md, di-restate)

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `weapon-rifle.png` | **128×64** | AK-47 silhouette horizontal | KillFeed, Loadout, BuyMenu |
| `weapon-pistol.png` | **128×64** | Glock/Deagle silhouette | Same |
| `weapon-smg.png` | **128×64** | UMP/MP5 silhouette | Same |
| `weapon-sniper.png` | **128×64** | AWP silhouette | Same |
| `weapon-knife.png` | **128×64** | Karambit knife silhouette | Same |
| `headshot-skull.png` | **64×64** | White skull on red badge, glow halo | KillFeed HS indicator (replace "HS" text) |
| `kill-chevron.png` | **32×32** | Right-pointing chevron `▸` | KillFeed killer→victim separator |
| `damage-arrow.png` | **96×96** | Red glowing arrow with soft halo, edges feathered | DamageDirectionController |
| `crown-domination.png` | **96×96** | Golden crown for DOMINATOR streak | Announcement banner |
| `crosshair-dot.png` | **32×32** | Single white dot | Crosshair variant |
| `crosshair-classic.png` | **32×32** | + cross style | Crosshair variant |
| `crosshair-dynamic.png` | **32×32** | Expandable bracket style | Crosshair variant |
| `crosshair-x.png` | **32×32** | X mark style | Crosshair variant |

---

## 🧭 P2 — Navigation & Mode Icons

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `mode-deathmatch.png` | **96×96** | Crossed pistols silhouette | MainMenu mode card |
| `mode-practice.png` | **96×96** | Bullseye target with arrows | MainMenu mode card |
| `mode-casual.png` | **96×96** | C4 bomb silhouette (when casual visible) | MainMenu mode card |
| `nav-loadout.png` | **48×48** | Clipboard + weapon rack | MainMenu sidebar left |
| `nav-cosmetics.png` | **48×48** | Paint brush stroke | MainMenu sidebar |
| `nav-missions.png` | **48×48** | Checklist scroll | MainMenu sidebar |
| `nav-shop.png` | **48×48** | Coin stack with $ | MainMenu sidebar right |
| `nav-battlepass.png` | **48×48** | Star with ribbon | MainMenu sidebar |
| `nav-settings.png` | **48×48** | Gear cog | MainMenu sidebar |
| `nav-gacha.png` | **48×48** | Slot machine handle / 3 reels | Bottom GACHA button |

---

## 💰 P3 — Economy Icons

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `coin-icon.png` | **32×32** | Gold circle with stylized $ | Currency display, Shop, Kill rewards |
| `crate-icon.png` | **128×128** | Weapon case 3/4 angle, neon edge | CrateController, Shop |
| `xp-burst.png` | **128×128** | Radial glow with star center | Level-up celebration |
| `streak-fire.png` | **32×32** | Flame silhouette | Daily streak indicator |
| `daily-calendar.png` | **48×48** | Calendar with check | EngagementController |
| `mission-checkmark.png` | **64×64** | Glowing checkmark | Mission complete |

---

## 🏅 P4 — Rank Badges (Bronze → Radiant)

24 total: `bronze/silver/gold/platinum/diamond/master/immortal` × 3 sub-rank + `radiant` standalone.

**Filename convention:** `rank-bronze-1.png`, `rank-bronze-2.png`, ..., `rank-immortal-3.png`, `rank-radiant.png`.

**Spec:** 96×96 each, shield/chevron shape, metallic finish per tier (bronze=copper, silver=chrome, gold=warm gold, platinum=silver-blue, diamond=cyan crystal, master=deep purple, immortal=red, radiant=rainbow holographic).

Sub-rank: 1 star = 1 small star, 2 = 2 stars, 3 = 3 stars positioned at top of shield.

**Reference:** Valorant rank icons style.

---

## 🩹 P5 — HUD Small Icons

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `hp-heart.png` | **24×24** | White heart silhouette | HealthController |
| `hp-shield.png` | **24×24** | Shield outline (future: armor) | HealthController variant |
| `ammo-bullet.png` | **24×24** | Side-view bullet | WeaponController ammo |
| `ammo-mag.png` | **24×24** | Full magazine | WeaponController ammo |
| `timer-clock.png` | **24×24** | Clock face | MatchStateController |
| `player-count.png` | **24×24** | Person silhouette | (future: player count display) |

---

## 🖼️ P6 — Modal Frames (9-Slice)

Tiap frame **256×256 PNG** dengan 14px corner radius + 2px edge stroke.

Properties: Center 32px transparan-fill, edges 32px painted dengan gradient.

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `frame-modal-default.png` | **256×256** | Dark center + cyan edge stroke | Pause/Settings/Shop modals |
| `frame-modal-legendary.png` | **256×256** | Dark center + gold edge stroke | Crate legendary reveal |
| `frame-modal-epic.png` | **256×256** | Dark center + purple edge stroke | Crate epic reveal |
| `frame-toast.png` | **128×128** | Notification box, dark + tier-color left edge | KillFeed entries |
| `frame-banner.png` | **256×128** | Wide hero banner, dark with cyan ambient | Announcement banner |
| `frame-team-card-blue.png` | **256×256** | Tim Kawan card frame, blue glow edge | TeamSelectController card |
| `frame-team-card-red.png` | **256×256** | Tim Lawan card frame, red glow edge | TeamSelectController card |

**Roblox 9-slice docs:** https://create.roblox.com/docs/ui/9-slice

---

## 🎬 P7 — Background & Decoration

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `bg-mainmenu.png` | **1920×1080** | Dark warehouse / shooting range, neon strips, vignette edges | MainMenuController hero bg |
| `bg-mainmenu-mobile.png` | **1080×1920** (portrait fallback) | Same scene rotated | (optional, currently uses landscape) |
| `bg-loadout.png` | **1920×1080** | Armory wall, weapons on rack | (future: LoadoutController bg) |
| `bg-shop.png` | **1920×1080** | Tactical store interior | (future: ShopController bg) |
| `bg-pattern-tech-grid.png` | **256×256** seamless | Diagonal tech grid lines, low opacity | HUD background overlay |
| `bg-pattern-carbon.png` | **128×128** seamless | Carbon fiber texture | Modal bg overlay |
| `bg-pattern-stripes.png` | **64×64** seamless | Diagonal hazard stripes | Loading bar / warning |

---

## ✨ P8 — Particles & FX

| Filename | Size | Detail | Pakai di |
|---|---|---|---|
| `particle-spark.png` | **64×64** | Bright spark, 8-direction radial | Kill effect, hit impact |
| `particle-smoke.png` | **128×128** | Soft smoke puff | Bomb plant (casual), grenades (future) |
| `particle-ember.png` | **64×64** | Glowing ember dot | Legendary crate open |
| `particle-confetti.png` | **256×256** sprite sheet 4x4 frames | Colored confetti burst | Match win celebration |
| `muzzle-flash.png` | **128×128** | Yellow-white flash 3-frame | WeaponController fire |
| `tracer.png` | **256×16** thin horizontal | Yellow tracer line | Bullet tracer |
| `blood-splash.png` | **128×128** | Red splash (kalau allowed by Roblox ToS — utk minor-friendly bisa diganti yellow paint splash) | Hit feedback |

> ⚠️ Untuk all-ages rating: skip darah merah. Pakai paint splash (yellow/orange) atau just sparks.

---

## 🎨 Cosmetic Skins (P9 — optional, bisa ditambah bertahap)

Untuk setiap weapon × tier (Common/Rare/Epic/Legendary/Contraband), bisa siapin skin image. Minimum **128×64** weapon silhouette dengan color/pattern variant.

Contoh:
- `skin-ak47-fire-serpent.png` (Legendary) — flame pattern
- `skin-glock-fade.png` (Epic) — purple-pink gradient
- `skin-awp-dragon-lore.png` (Contraband) — dragon engraving gold

Daftar weapon di `src/shared/Modules/WeaponConfig.luau`, daftar skin di `src/shared/Modules/CosmeticRegistry.luau`.

---

## 📋 Summary Total

| Priority | Jumlah Asset | Estimasi |
|---|---|---|
| P0 (TDM + Multiplayer baru) | **24 asset** | Wajib ada sebelum publish |
| P1 (Kill feed combat) | 13 asset | Tinggi visibility per match |
| P2 (Navigation) | 10 asset | Tampil di main menu |
| P3 (Economy) | 6 asset | Shop / currency |
| P4 (Rank badges) | 24 asset | Scoreboard / progression |
| P5 (HUD small) | 6 asset | HP / ammo / timer |
| P6 (Modal frames) | 7 asset | Semua modal |
| P7 (Background) | 7 asset | Decoration |
| P8 (Particles) | 7 asset | Combat FX |
| **TOTAL CORE** | **104 asset** | Untuk full polish |

**Quick-start MVP (kalau mau jalan cepat):** Cuma P0 + P1 weapon icons + P3 coin = **~30 asset**. Sisanya pakai placeholder.

---

## 🤖 AI Prompt Template

Untuk konsistensi style, pakai prompt skeleton ini:

```
[ASSET NAME] for Roblox FPS game, [DESCRIPTION], 
flat silhouette design, white on transparent background,
military tactical style, line weight 4-6px,
no skeumorphism, no gradient inside,
neon accent edge optional cyan or amber,
crisp edges, no shadows,
[SIZE]x[SIZE] PNG with alpha,
icon centered with 10% padding
```

Contoh full:
```
Tactical FPS team badge for Tim Kawan, blue shield silhouette with 
chevron emblem inside, white on transparent background, military 
tactical style, line weight 4px, neon cyan glow edge, no skeumorphism, 
crisp edges no shadows, 128x128 PNG with alpha, centered with 10% padding
```

---

## 📦 Upload Workflow

1. Generate semua PNG via AI agent
2. Buka **Roblox Creator Hub** → My Creations → Images → **Upload Image**
3. Upload satu-satu (atau batch dengan tool kayak Roblox Asset Manager)
4. Catat AssetId tiap upload (format: `rbxassetid://1234567890`)
5. Update `src/shared/Modules/AssetIds.luau` dengan map filename → AssetId:
   ```luau
   return {
       Team = {
           kawanBadge = "rbxassetid://1234567890",
           lawanBadge = "rbxassetid://1234567891",
           ...
       },
       Action = { quickPlay = "...", serverBrowser = "...", ... },
       Map = { warehouse = "...", rooftop = "...", ... },
       Weapon = { rifle = "...", pistol = "...", ... },
       ...
   }
   ```
6. Controller pakai `ImageLabel.Image = AssetIds.Team.kawanBadge`

---

## 🚨 Constraint Roblox

- Image upload **gratis** (no Robux cost)
- Image max **1024×1024** per dimension (Roblox auto-resize lebih besar)
- File size **max 2MB**
- Approval delay biasanya **5-15 menit** untuk moderation
- **No copyrighted material** (logo brand asli, character dari game lain) — bakal ditolak / ban
- **All-ages compliance**: no real-blood, gore, alcohol, drug references

---

## 🔄 Sebelum kasih ke AI image gen

1. **Spesifikasikan size** explicit di prompt (Roblox down-scale tapi up-scale buruk)
2. **Transparent background** — paling penting, AI sering lupa
3. **Single asset per image** — JANGAN batch multi-icon dalam 1 PNG
4. **Consistent palette** — bilang ke AI: "use only white silhouette, optional cyan or amber accent"
5. **No text dalam asset** — text di-render via Roblox font system

Selamat generating! 🎨
