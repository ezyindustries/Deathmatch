# RoblokFPS — Mobile UI Design System

Style direction: **"Tactical Energetic FPS"** — dark surfaces, neon cyan + hot red accents, strong contrast, **motion-rich**. Reference vibe: Valorant HUD discipline + Apex Legends celebration energy + CS2 readability.

---

## 🔍 Audit Findings (current state)

Disusun dari baca 8 controller utama: `MainMenu`, `KillFeed`, `Announcement`, `Scoreboard`, `MatchState`, `Health`, `DamageDirection`, `Settings`.

### Sistemik (semua controller)
1. **Gak ada design language tunggal** — MainMenu warm amber/armory theme; HUD cool gray/blue. Konflik kerasa.
2. **Mobile scaling spotty** — cuma Settings + (now) Loadout pakai UIScale. MainMenu/KillFeed/MatchState fixed width → overflow di phone narrow.
3. **Touch targets borderline** — banyak yang exact 36px (≥44px standar). Slider track 8px, scrollbar 8px — susah di-tap mobile.
4. **Animasi minim / lemah** — kebanyakan instant appear. Tween-nya ada tapi linear default (gak ada juice/spring/back-out).
5. **Visual depth flat** — single corner radius, no gradient, no glow (kecuali Loadout weapon cards). Background overlay default black-45%, boring.
6. **Icon text-heavy** — "Close" text vs ✕ ikon (fixed di Loadout), "HS" text vs visual badge headshot.
7. **No safe-area handling** — semua `IgnoreGuiInset = true` tapi gak protect notch/home indicator iOS.
8. **No design tokens** — warna/spacing/radius hardcoded everywhere. Mau ganti theme = grep-replace 50 file.

### Per-controller issue (top items)

**MainMenuController** — weapon silhouettes terlalu samar (0.82 transparency, hilang di bright skybox). No close on mode picker. PLAY button 560×72 OK tapi gak ada hover state celebration.

**KillFeedController** — entries fixed 420×220 (overflow di narrow). No weapon icon (cuma text "AK-47"). Headshot "HS" text label (11px) — gak jelas. No slide-in animation. No tier-color border buat legendary kill.

**AnnouncementController** — banner 580px fixed → overflow di phone <550px. Streak color tier ada (5 level) — bagus, tapi banner entrance instant size-tween (gak ada celebration motion). No particle burst pas DOMINATOR.

**ScoreboardController** — mini scoreboard 260×36 label-only (gak ada bar visual K/D). Full scoreboard 480×380 overflow di <400px viewport. No scroll indicator visible. Results banner force-timeout 6s tanpa user-dismiss.

**MatchStateController** — 420×72 fixed → overlap side HUD di <500px. No red flash di <30s warning timer. 2-line layout boros vertical space.

**HealthController** — low-health overlay full-screen red merah 15% bisa obscure vision di critical moment. No pulse/flash buat draw attention saat damage. Bar 14px tipis.

**DamageDirectionController** — multiple arrow overlap (gak stack). Edge-only positioning susah dilihat di widescreen. No type distinction (melee vs bullet).

**SettingsController** — scrollbar 8px susah grab di touch. Slider track 8px + thumb 18px imbalance. Crosshair preview 140px makan 30% view di phone small. No value popup di slider drag.

---

## 🎨 Design System (proposed)

### Color Palette — "Tactical Energetic"

```
BASE (deep navy-black)
  bg-deepest      RGB(8, 9, 14)        true black backdrop
  bg-base         RGB(16, 18, 26)      panel base
  bg-elevated     RGB(24, 26, 36)      cards, list items
  bg-hover        RGB(32, 36, 48)      hover/active
  bg-pressed      RGB(20, 22, 30)      pressed feedback

ACCENT (brand + combat)
  accent-primary    RGB(0, 220, 255)    cyan neon — brand, CTAs
  accent-secondary  RGB(255, 64, 96)    hot red — combat, enemy
  accent-warm       RGB(255, 180, 60)   gold — MVP, reward
  accent-electric   RGB(140, 100, 255)  purple — legendary, special

SEMANTIC
  success  RGB(80, 220, 130)   green — friendly, OK
  danger   RGB(255, 60, 80)    red — low HP, enemy
  warning  RGB(255, 200, 60)   amber — caution
  info     RGB(80, 180, 255)   blue — neutral message

TIER (gacha rarity, kill feed accent)
  common      RGB(180, 185, 200)
  rare        RGB(100, 180, 255)
  epic        RGB(200, 120, 255)
  legendary   RGB(255, 200, 80)
  contraband  RGB(255, 80, 130)
```

### Spacing — 4px grid

`xs=4, s=8, m=12, l=16, xl=20, xxl=24, x3l=32, x4l=48, x5l=64`. Gak ada nilai random — pilih dari skala ini.

### Corner radius

`sm=4, md=8, lg=14, xl=22, full=9999 (pill/circle)`. Standar button = `md`, modal panel = `lg`, prominent card = `xl`, close button bulet = `full`.

### Typography — Gotham scale

```
micro    11px  GothamBold     tiny tags
caption  13px  Gotham         small labels
body     15px  Gotham         default
bodyLg   18px  Gotham         emphasized
h3       22px  GothamBold     card titles
h2       28px  GothamBold     section heads
h1       36px  GothamBlack    big numbers (timer, kill count)
display  48px  GothamBlack    match results, kill streaks
```

### Touch targets

- **Min 44×44px** untuk SEMUA tombol interaktif (Apple HIG / Material).
- 48×48 untuk yang sering ditekan.
- 56×56 untuk primary CTA (PLAY).
- Slider track minimal 12px tall, thumb 24-28px.
- Scrollbar minimal 14px wide untuk mobile.

### Motion / Easing

```
duration-instant     0.08s   hover state
duration-quick       0.16s   press feedback
duration-base        0.24s   standard transitions
duration-smooth      0.35s   modal entry/exit
duration-celebrate   0.6s    kill streak, match results
duration-linger      4.0s    toast display before fade

easing-emphasized    Quart Out (panels)
easing-standard      Quad Out
easing-enter         Back Out (spring, modals)
easing-celebrate     Back Out 0.6s
easing-bounce        Elastic Out (kill streak)
```

**Rule:** Setiap UI entry/exit di-tween. NO instant pop. Modals scale `0.92 → 1.0` + fade in. Toast slide-in dari right. Kill streak pop scale `1.2 → 1.0` dengan particle burst.

---

## 🧩 Component patterns

### Modal (Loadout, Shop, Settings, Cosmetics, Crate, BattlePass)

```
[ Backdrop ]
  bg: bg-deepest at 40% opacity
  full screen (UIScale on PANEL not overlay)
  click outside = close

  [ Panel ]
    bg: bg-base
    border: 2px stroke accent-primary (or tier color)
    radius: lg
    padding: xxl
    max-width: 700, max-height 80vh

    [ Header ]
      title — h3 accent-primary
      close button — 44×44 circular, "✕" icon, top-right

    [ Body ]
      content + scroll if overflow

  Entry: scale 0.92→1.0 + opacity 0→1 over duration-smooth (Back Out)
  Exit:  scale 1.0→0.92 + opacity 1→0 over duration-base (Quad In)
```

### Toast / Notification (KillFeed, currency popup, mission complete)

```
[ Toast ]
  bg: bg-elevated 95% opacity
  border-left: 4px tier-color (or 2px neon stroke entire)
  radius: md
  padding-x: l, padding-y: s
  max-width: 340 mobile, 420 desktop
  min-height: 44

  layout: [icon] [text rich] [accessory icon]

  Entry: slide-in from right (translate x +60→0) + opacity 0→1 over duration-base
  Linger: 4s (configurable)
  Exit: opacity 1→0 + translate y 0→-10 over duration-base

  Stack: vertical, newest on top, FIFO with max 5 visible
```

### Banner (Match results, Streak announcement)

```
[ Banner ]
  bg: bg-base 95% opacity
  border: 2px stroke (tier-color based on streak)
  radius: lg
  width: 580px desktop, 90vw mobile
  height: auto (min 80)
  padding: xxl

  title — display 36px display-font, animated
  subtitle — body 14

  Entry: scale 0.85→1.05→1.0 (spring overshoot) + opacity 0→1 over duration-celebrate
  Linger: 2.5s
  Exit: opacity + slight scale down

  At DOMINATOR/PENTA: emit particle burst, screen shake, lower volume of game audio
```

### Button

```
Variants:
  primary    — bg accent-primary, text dark, prominent
  secondary  — bg bg-elevated + 1px stroke borderSubtle, text primary
  ghost      — transparent + 1.5px stroke accent-primary
  danger     — bg accent-secondary, text white
  warm       — bg accent-warm, text dark (rewards)

Sizes:
  sm    height 32, body caption, padding-x m   (compact)
  md    height 44, body, padding-x l           (default)
  lg    height 56, bodyLg, padding-x xxl       (CTAs)

States:
  hover    scale 1.02, brightness +5%
  pressed  scale 0.96, brightness -5%
  disabled bgDisabled, text tertiary

Corner: md
```

### HUD bar (Health, Ammo, Currency)

```
[ Container ]
  bg: bg-base 70% opacity
  radius: md
  padding: m

  [ Icon ]
    size 24
    color matches semantic (HP = success/warning/danger gradient)

  [ Value ]
    GothamBold bodyLg (18px)
    Roboto Mono buat angka biar gak shift width

  [ Bar (optional) ]
    track: bg-pressed
    fill: semantic color (animated tween on change)
    height: 6 (mini), 12 (standard)
```

---

## 📋 Implementation Roadmap

Prioritas dari high impact → polish:

### Tier 1 (impact tinggi, terlihat tiap match)
1. **KillFeed** — slide-in animation, weapon icon support, tier-color border, mobile responsive
2. **Announcement banner** — particle burst pas DOMINATOR/PENTA, mobile responsive
3. **Match state HUD** — red pulse warning <30s, compact 1-line layout
4. **Health bar** — pulse animation pas damage taken (gak full-screen overlay, cukup HUD pulse)

### Tier 2 (high impact, modal flow)
5. **MainMenu mode select** — add visible close, mobile UIScale, button hover celebration
6. **Settings** — bigger scrollbar (14px), slider track 12px + value popup, crosshair preview collapsible
7. **Scoreboard mini** — add visual HP icon + K/D ratio bar (not just text)
8. **Loadout** ✅ DONE (UIScale on panel, ✕ icon)

### Tier 3 (polish, less frequent)
9. **Shop / Crate / Cosmetics** — apply modal pattern uniformly
10. **BuyMenu** (casual) — apply modal pattern + weapon icon support
11. **PauseMenu** — apply modal pattern
12. **DamageDirection** — bigger arrow, type variants (bullet vs explosion vs melee)
13. **Spectator HUD** — POV cycle indicator polish

### Tier 4 (system-wide refactor)
14. Migrate ALL hardcoded colors → `UITheme.Color`
15. Migrate ALL hardcoded spacing → `UITheme.Space`
16. Add `AssetIds.luau` module for centralized image references
17. Asset upload pipeline (see `ASSETS.md`)

---

## 🚦 Conventions going forward

1. **Import tokens**, jangan hardcode:
   ```luau
   local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
   frame.BackgroundColor3 = UITheme.Color.bgElevated
   ```

2. **Use helpers** untuk UICorner/UIStroke/UIPadding:
   ```luau
   UITheme.corner(frame, "lg")
   UITheme.stroke(frame, "accentPrimary", 2)
   UITheme.padding(frame, "xxl")
   ```

3. **Tween everything** — gak ada instant `.Visible = true`. Pakai `UITheme.Easing.enter` minimal:
   ```luau
   panel.Size = UDim2.fromOffset(0, 0)
   panel.Visible = true
   TweenService:Create(panel, UITheme.Easing.enter, { Size = UDim2.fromOffset(700, 540) }):Play()
   ```

4. **Mobile-first responsive** pakai helper `bindResponsiveScale`:
   ```luau
   UITheme.bindResponsiveScale(panel)
   -- panel auto-scale 0.65 di <700px, 0.8 di <1100, 1.0 di desktop
   ```

5. **Touch targets minimum 44px**. Tombol kecil = pakai padding hit area, bukan size kecil.

6. **Reference `ASSETS.md`** untuk asset list & upload checklist.

Lihat `ASSETS.md` buat list gambar/icon/frame yang perlu di-source atau upload.
