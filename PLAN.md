# RoblokFPS — UI Excellence Plan

> Tujuan: ngubah UI dari "fungsional but flat" jadi **"setiap interaksi terasa hidup, setiap reward kerasa earned, setiap kill kerasa epic"**.
> Standar: top-tier Roblox FPS (Phantom Forces, Frontlines, Bad Business level polish) — tapi dengan **mobile-first** mindset karena mayoritas audience Roblox di mobile.

---

## 🎯 Vision Statement

```
Tactical Energetic FPS — dark navy-black base, neon cyan + hot red accent,
motion-rich, mobile-native. Reference vibe:
  • Valorant — HUD discipline & color discipline
  • Apex Legends — celebration energy & character voice
  • CS2 — readability & competitive clarity
  • Fortnite — reward & progression dopamine

Every interaction has feedback (≤200ms).
Every state change is animated.
Every milestone is celebrated.
```

**Not the goal:** photorealistic AAA, complex animations that tax mobile, copying Valorant 1:1.

---

## 📊 Current state vs target

| Aspek | Sekarang | Target |
|---|---|---|
| Design tokens | ✅ UITheme.luau exists | All 27 controllers use it (~6 use, 21 to migrate) |
| Mobile responsive | ⚠️ 2/27 controllers (Settings, Loadout) | 27/27 |
| Touch targets ≥44px | ⚠️ ~70% compliant | 100% |
| Animated entry/exit | ⚠️ ~30% have any animation | 100% (with proper easing) |
| Tier-color hierarchy | ⚠️ Loadout cards, KillFeed only | All gacha/economy UI |
| Custom art assets | ❌ 0 (all procedural Frames) | 13 minimum, 50 ideal |
| Sound design | ❌ None | UI sounds for tick/click/notify/celebration |
| Onboarding | ❌ Tutorial flag exists, no flow | 30-sec new-player walkthrough |
| Loading states | ❌ Blank screens | Skeleton/spinner where needed |
| Error states | ❌ Silent fail | Toast notification |

---

## 🚦 6-Phase Roadmap

Estimate: 1 session = ~1-2 hours focused work. Time = "Claude session-hours", not real-world calendar.

### Phase 1 — Combat HUD energetics (4 sessions)
**Goal:** Setiap shot, hit, kill, damage taken — KERASA. Player gak boleh feel "boring" di tengah firefight.

| # | Controller | Brief redesain | Effort | Frequency |
|---|---|---|---|---|
| 1.1 | `AnnouncementController` | Banner dengan particle burst di DOMINATOR/PENTA, scale spring entry (0.85→1.05→1.0), background tier-color glow. Mobile responsive width (90vw). Optional screen shake at PENTA+. | M | Every streak |
| 1.2 | `HealthController` | Hapus full-screen red overlay (vision-obscuring). Ganti: HP icon pulse + bar shake animation pas damage. Heartbeat pulse di HP <30%. Low-HP screen vignette tipis di edges, bukan center. | M | Every hit |
| 1.3 | `MatchStateController` | Compact 1-line: `[icon] DEATHMATCH ▸ 4:27`. Timer red pulse animation di <30s. Sub-state indicator (LOBBY/VOTING/MATCH/ENDING) via color. Mobile width responsive. | S | Always visible |
| 1.4 | `DamageDirectionController` | Arrow lebih besar (120px) + soft red glow halo. Stack multiple sources radially (gak overlap). Slightly different shape per damage type (sharp triangle = bullet, jagged = explosion, slash = melee). | M | Every hit taken |

**Phase 1 deliverable:** Match feels alive. Damage feels responsive. Streaks feel earned.

---

### Phase 2 — Modal & flow consistency (5 sessions)
**Goal:** Setiap modal terasa "satu keluarga". Pattern entry/exit, header X button, close-outside, all consistent.

| # | Controller | Brief redesain | Effort | Frequency |
|---|---|---|---|---|
| 2.1 | `MainMenuController` | Mode select card dengan icon (perlu asset). Mobile UIScale on panel. PLAY button celebrate hover (subtle scale 1.04 + glow). Side buttons → 48px height + icon. Letterbox bg lebih atmospheric. | L | Every session |
| 2.2 | `SettingsController` | Modal pattern (X close 44px), slider track 12px + thumb 24px + value tooltip on drag. Scrollbar 14px. Crosshair preview collapsible accordion. Group sliders by section card. | L | Frequent |
| 2.3 | `ScoreboardController` | Mini scoreboard add visual K/D bar (not just text). Full scoreboard: row hover state, MVP gold border, your row cyan border + filled accent. Mobile responsive width. | M | Frequent (Tab) |
| 2.4 | `PauseMenuController` | Apply modal pattern. Add quick-actions: Loadout, Settings, Leave Match. Animated entry. Click-outside close. | S | Per match |
| 2.5 | `BuyMenuController` | (Casual) Modal pattern. Weapon icons (perlu asset). Budget remaining counter prominent. Mobile column reflow. | M | Casual matches |

**Phase 2 deliverable:** Modal experience uniform. No "this menu is different" cognitive load.

---

### Phase 3 — Economy & reward celebrations (4 sessions)
**Goal:** Open crate kerasa epic, claim mission kerasa worth it, level up = dopamine. Setiap reward harus ada visual moment.

| # | Controller | Brief redesain | Effort | Frequency |
|---|---|---|---|---|
| 3.1 | `CrateController` | Open animation: case shake → light burst → tier-color reveal. Confetti at Legendary+. Slot-machine "spinning" reveal alternative. Better skin preview. Pity counter prominent. | L | Per crate |
| 3.2 | `CosmeticsController` | Card grid layout dengan tier color, equipped checkmark, "OWNED" badge. Filter by slot/tier. Animated equip swap. Preview area dengan rotating model (kalau ada model asset). | L | Frequent |
| 3.3 | `ShopController` | Featured deal hero card. Daily rotation indicator. Buy button celebration animation. Price → coin icon (asset). | M | Frequent |
| 3.4 | `BattlePassController` | Tier track visualization (horizontal scroll dengan progress). Free vs Premium lane. Unlock animation pas claim. Premium upsell modal saat tier locked. | L | Periodic |
| 3.5 | `MissionController` + `ProgressionController` + `EngagementController` | Daily mission card stack. Progress bar fill animation. Claim button → coin burst. XP gain → number flying to bar (lerp). Daily login streak → fire icon (asset) with day counter. Level up → screen flash + sound + banner. | M | Daily |

**Phase 3 deliverable:** Reward loop feels rewarding. Players wanna grind because moments hit.

---

### Phase 4 — Asset upload sprint (2 sessions)
**Goal:** Replace procedural Frame silhouettes dengan custom art. Visual quality leap.

**Session 4.1 — Minimum viable (13 assets)**
- 5 weapon icons (128×64): rifle, pistol, smg, sniper, knife
- Skull headshot badge (64×64, white skull on transparent — gets red tint via UI)
- Coin icon (32×32, gold $)
- Crate icon (128×128, weapon case 3/4 view)
- PLAY chevron + 6 nav icons (48×48): loadout, cosmetics, shop, BP, missions, settings

**Session 4.2 — Polish set (~30 more assets)**
- Mode icons (deathmatch, casual, training)
- Rank badges (24 tiers: bronze 1-3 → radiant)
- HP/Ammo/Magazine/Timer icons
- Modal frame 9-slice (default + tier variants)
- Toast frame 9-slice
- Banner background 9-slice
- Particle textures (sparks, smoke, ember, confetti)
- Hero background image
- Mission complete checkmark
- Battle pass badge
- Damage direction arrow asset

**Deliverable:** `AssetIds.luau` module wired. All controllers use real images, fallback to procedural.

**Decision points:**
- Source method: Creator Store (free, ~1 jam) / Figma+AI generation (custom, ~3-4 jam) / commission Fiverr (cost ~$50-150, 1-2 hari) — pilih satu atau hybrid.

---

### Phase 5 — Sound design (3 sessions, OPTIONAL but huge impact)
**Goal:** UI clicks, hovers, notifications, celebrations have sound. Doubles perceived polish without much code.

| Sound | When | Free sources |
|---|---|---|
| UI click (soft tick) | Button press | Freesound.org, Pixabay |
| UI hover (subtle) | Button mouse-enter | (Desktop only) |
| Notification (pop) | KillFeed entry, toast | Freesound |
| Headshot (sharp) | HS kill | Custom mix |
| Killstreak whoosh | Announcement banner | Freesound |
| Crate open (anticipation) | Crate animation start | Freesound |
| Tier reveal (sting) | Rare/Epic/Legendary reveal | Freesound, varies per tier |
| Level up (chord) | XP threshold | Freesound |
| Coin pickup (cha-ching) | Currency gained | Freesound |
| Match start (whistle/horn) | Match starting | Freesound |
| Match end (drum hit) | Match end | Freesound |
| Bomb plant tick (casual) | Plant in progress | Custom |
| Defuse tick (casual) | Defuse in progress | Custom |

Implementation: `AudioConfig.luau` already exists — extend with UI sound IDs. Add `SoundManager.luau` controller for centralized play. Volume tied to master volume in settings.

**Session split:**
- 5.1: Source 15 sounds (Freesound + Pixabay), upload to Roblox, register in AudioConfig
- 5.2: Wire sounds to UI events (KillFeed, Buttons, Announcements)
- 5.3: Wire sounds to Economy events (Crate, Level Up, Coin, Mission)

**Deliverable:** Audio-visual congruence. Every visual celebration has audio kick.

---

### Phase 6 — Onboarding + polish (3 sessions)
**Goal:** New player understands the game in 30 seconds. Returning player feels welcomed.

| # | Item | Brief |
|---|---|---|
| 6.1 | First-time UX flow | Detect `tutorialCompleted = false` → guided tour: PLAY button → first kill banner → first reward modal → loadout intro. Skippable. |
| 6.2 | Loading states | Blank screens → skeleton placeholders + spinner. Especially: profile load on join, crate roll, shop refresh. |
| 6.3 | Empty states | "No missions claimed yet" → illustration + CTA. "Inventory empty" → "Open a crate!" suggestion. |
| 6.4 | Error states | Network fail / DataStore error → toast notification (not console). Retry CTA. |
| 6.5 | Achievement celebrations | First kill, first headshot, level milestones (5/10/25/50/100), first legendary skin, 100 matches played — full-screen banner moment. |
| 6.6 | Settings polish | Add reset-to-default, sensitivity test pad, audio preview button. |

**Deliverable:** Game feels welcoming + retention loop tighter.

---

## 🎨 Quality Criteria — "Done" means

Setiap controller pass-fail checklist:

- [ ] All hardcoded colors → `UITheme.Color` reference
- [ ] All spacing values → `UITheme.Space` reference
- [ ] All corner radii → `UITheme.Radius` reference
- [ ] Touch targets ≥ 44×44 px for interactive elements
- [ ] Entry animation present (≥0.16s, non-linear easing)
- [ ] Exit animation present (fade + slight motion)
- [ ] Hover state (desktop) or pressed state (touch) defined
- [ ] Mobile responsive: works at 360×640 viewport
- [ ] Close affordance visible (X icon ≥44px) if modal
- [ ] Click-outside closes (if modal)
- [ ] No fixed widths that overflow on mobile narrow
- [ ] Sound effect tied to primary action (after Phase 5)
- [ ] Text contrast WCAG AA (4.5:1 for body, 3:1 for large)
- [ ] No JS console errors / Lua warnings

**Definition of "sangat bagus" untuk seluruh project:**
- 0 controller masih hardcode color
- 100% pass touch target test (Studio device emulation @ iPhone SE)
- All modals follow same enter/exit pattern
- All notifications stack consistently
- Loading + empty + error states defined
- 50+ assets uploaded
- 15+ UI sounds wired
- Tutorial flow runs end-to-end without confusion

---

## 💰 Asset Strategy

### Tier 1: FREE (Roblox Creator Store)
- **Cara:** Studio → Toolbox → search "UI icon pack" / "weapon icons" / "rank badges"
- **Pro:** Gratis, instant insert, AssetId langsung tersedia
- **Con:** Generic look, might clash with brand identity
- **Cocok untuk:** Minimum viable (P0 assets, weapon icons, basic UI)
- **Estimated cost:** $0
- **Estimated time:** 1-2 jam search + 30 min organize

### Tier 2: AI-GENERATED (Midjourney / Stable Diffusion / DALL-E 3)
- **Cara:** Generate per spec → manual upload ke Roblox
- **Prompt template:** "tactical FPS icon, [item], flat silhouette, white on transparent background, military style, no detail, vector look, 256x256"
- **Pro:** Custom look, brand-consistent, iterate fast
- **Con:** Quality varies, often need touch-up in Photoshop, licensing nuance (most commercial use OK)
- **Cocok untuk:** Frames, decorative elements, particle textures, hero backgrounds
- **Estimated cost:** $10-30 (subscription if not have)
- **Estimated time:** 3-5 jam (generate, curate, edit, upload)

### Tier 3: COMMISSION (Fiverr / Roblox Forum / Twitter)
- **Cara:** Brief artist with mood board + design system
- **Pro:** Custom brand-aligned, professional polish
- **Con:** Cost, revisions can slow
- **Cocok untuk:** Hero illustrations, rank badge set, character art
- **Estimated cost:** $50-300 depending scope
- **Estimated time:** 3-7 hari turnaround

### Tier 4: PROCEDURAL (current fallback)
- **Cara:** Lua-rendered Frames + UIStroke + UIGradient (like Loadout weapon cards)
- **Pro:** No upload, dynamic recolor, instant
- **Con:** Many Frame instances → perf cost di low-end mobile
- **Cocok untuk:** Prototype, weapon silhouettes, simple icons

### **Recommended hybrid for now:**
- 80% Tier 1 (free from store) for non-hero items
- 15% Tier 2 (AI) for frames + decorative
- 5% Tier 3 (commission) for hero bg + rank badges
- 0% Tier 4 (sunset procedural for icons, keep for non-critical decoration)

---

## 🔬 Testing Protocol — Verify "sangat bagus"

Per redesign, run this checklist in Studio:

1. **Mobile emulation: iPhone SE (375×667)** — Test menu → Device → iPhone SE
   - All buttons tappable (no overflow, no clip)
   - All text readable (≥13px)
   - Close affordances visible
2. **Mobile emulation: iPad Pro 12.9 (1024×1366)** — landscape & portrait
3. **Desktop default (1920×1080)** — sanity check no regression
4. **Stress test: 5 kill feed entries + 1 announcement + open settings simultaneously** — no z-fighting, no perf drop
5. **Cold join match-in-progress** — UI states correct
6. **Death + respawn cycle** — death cam, scoreboard, respawn HUD all transition smoothly
7. **Slow network (Studio throttling)** — loading states show
8. **Player profile load fail (simulate DataStore down)** — graceful fallback

Screenshot per state → store in `/screenshots/` folder for design review.

---

## ⚠️ Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Performance drop di low-end mobile (banyak tween) | Medium | High | Use TweenService::Cancel on rapid state change; cap simultaneous tweens; profile MicroProfiler |
| Asset upload bottleneck (1 dev) | High | Medium | Tier 1 (store) first, commission later. Or use AI gen. |
| Design drift (later sessions diverge from tokens) | Medium | High | Lint rule: grep for hardcoded `Color3.fromRGB` outside `UITheme.luau` — fail PR if present |
| Sound design adds complexity | Low | Medium | Phase 5 is OPTIONAL — ship visuals first, sound later |
| Mobile performance test gap | Medium | High | Add Studio test on actual mobile device via Companion app before each phase ship |
| Touch input edge cases (gesture conflict) | Low | Medium | Test multi-touch scenarios (ADS hold + fire + sprint) |
| Player resistance to new look | Low | Low | Soft rollout via setting toggle: "Legacy HUD" option (optional) |
| Scope creep (every controller "needs more") | Very High | Medium | Strict acceptance criteria above. Ship phase before starting next. |
| AI-generated asset license issue | Low | Low | Stick to Midjourney/SD commercial-allowed plans |

---

## ❓ Decisions Needed From You

Aku perlu jawaban ini sebelum lanjut implementasi maksimal:

### D1. Brand direction
- [ ] **A. Cyan + hot red** (sekarang di UITheme.luau) — clean, tech, modern
- [ ] B. Amber + crimson — warm, military, retro
- [ ] C. Cyan + gold — premium, luxury (good for crate reveals)
- [ ] D. Other (kasih tau referensi)

### D2. Asset budget / approach
- [ ] **A. Free-only (Tier 1)** — Creator Store hunting, 0 budget, ship cepet
- [ ] B. AI-generated (Tier 2) — $10-30 budget, 1 session of generation
- [ ] C. Commission (Tier 3) — $100-300 budget, 1 week turnaround
- [ ] D. Hybrid — start free, commission hero pieces later

### D3. Sound design — Phase 5
- [ ] A. **YES, include after Phase 4** — adds 3 sessions
- [ ] B. SKIP for now, revisit later
- [ ] C. DIY (you source sounds) vs Claude source

### D4. Mobile-first strict?
- [ ] **A. STRICT — every controller must pass 375×667 viewport test** (longer dev, better mobile UX)
- [ ] B. Mobile-aware but desktop priority — faster ship
- [ ] C. Desktop-only acceptable for some modals (Settings, BattlePass) — fastest, sacrifices mobile

### D5. Implementation pace
- [ ] **A. Methodical — 1 controller per session, full polish + screenshot test**
- [ ] B. Batch — 3-5 controllers per session, less polish per
- [ ] C. Sprint — try to finish Phase 1+2 in 2 sessions, accept some debt

### D6. Animation level
- [ ] A. Subtle — quick fades, no spring/back easing — clean
- [ ] **B. Energetic — spring overshoots, particle bursts, screen shakes** — fun
- [ ] C. Maximalist — full Apex/Fortnite celebration energy — risk of feeling kid-tier

### D7. Language consistency
- Sekarang code/docs mix EN + ID. UI text mostly Indonesian (Deathmatch desc), some English (LOADOUT, PLAY, COSMETICS).
- [ ] A. ALL Indonesian UI
- [ ] **B. EN for short labels (PLAY, LOADOUT, KILL), ID for descriptions**
- [ ] C. ALL English

---

## 🗓️ Suggested execution order

Asumsi default decisions: D1-A, D2-D (hybrid), D3-A, D4-A, D5-A, D6-B, D7-B.

| Session | Phase | Focus |
|---|---|---|
| 1 | 1.1 | Announcement banner redesain |
| 2 | 1.2 | Health bar + damage pulse |
| 3 | 1.3 | Match state HUD |
| 4 | 1.4 | Damage direction |
| 5 | 4.1 | Source + upload 13 minimum assets |
| 6 | 2.1 | MainMenu redesain |
| 7 | 2.2 | Settings redesain |
| 8 | 2.3 | Scoreboard redesain |
| 9 | 2.4-2.5 | Pause + Buy menu |
| 10 | 3.1 | Crate animation + reveal |
| 11 | 3.2 | Cosmetics gallery |
| 12 | 3.3-3.4 | Shop + Battle Pass |
| 13 | 3.5 | Mission + Progression + Engagement |
| 14 | 4.2 | Source + upload polish assets |
| 15 | 5.1-5.3 | Sound design wire-up |
| 16 | 6.1-6.2 | Onboarding + loading states |
| 17 | 6.3-6.6 | Empty/error/achievement states |
| 18 | QA | Mobile device test, performance profile, screenshot review |

**Total: 18 sessions** untuk hit "sangat bagus" criteria. Bisa lebih cepet kalau batch (D5-B/C) atau lebih lama kalau ada redesign rework.

---

## 📈 Progress tracking

Bikin "UI Polish Score" dashboard di project:

```
Phase 1 — Combat HUD       [█████░░░░░] 1/4 (KillFeed done)
Phase 2 — Modal flow       [██░░░░░░░░] 1/5 (Loadout done)
Phase 3 — Economy          [░░░░░░░░░░] 0/5
Phase 4 — Asset upload     [░░░░░░░░░░] 0/2
Phase 5 — Sound design     [░░░░░░░░░░] 0/3
Phase 6 — Onboarding       [░░░░░░░░░░] 0/6

Overall: [██░░░░░░░░░░░░░░░░░░] 2/25 (8%)
```

Update setiap session selesai. Print di task list / commit message.

---

## 🚀 Next immediate step

**Recommended: Mulai Phase 1.1 — Announcement banner redesain.**

Alasan:
1. **High visual impact**: muncul di setiap kill streak (sering)
2. **Self-contained**: gak depend asset (cuma motion + particle)
3. **Demonstrates motion system**: spring entry, particle burst, color tier transition — semua pattern yang akan reused
4. **Quick win**: 1 session, hasil dramatic

Atau kalau mau langsung "wow" effect untuk new visitor: **Phase 2.1 — MainMenu redesain** dulu (first impression matters most), tapi butuh asset (D2 decision).

Kasih tau jawaban D1-D7 di atas, lalu pilih session pertama. Aku siap eksekusi.
