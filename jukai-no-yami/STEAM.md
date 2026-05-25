# Steam Release Guide — Jukai No Yami (樹海の闇)

This document is your checklist to ship on Steam and start earning. The game is built in **Godot 4.3** and is playable **without any audio files** (procedural fallbacks are included), but replacing them with professional assets will significantly improve reviews.

---

## What Was Improved (v1.2)

| Area | Change |
|------|--------|
| **Graphics** | Full-screen VHS/cinematic post-process (was coded but never enabled) |
| **Quality tiers** | Low / Medium / High + Performance Mode in menu and pause |
| **Resolution** | Default 1920×1080, MSAA on Medium/High |
| **Audio** | Procedural footsteps, wind, whispers, jumpscares when OGG files are missing |
| **Audio buses** | Music, Ambient, SFX, Ghost pre-configured |
| **HUD** | Styled sanity/battery bars |
| **Export** | `export_presets.cfg` for Windows + macOS |

---

## Before You Export

1. Install **Godot 4.3** (Standard, not .NET): https://godotengine.org/download
2. Open this folder → Import `project.godot`
3. Press **F5** and play through all 3 areas once
4. **Project → Export** → add export templates if prompted (download once)

### Recommended: Add Real Audio (Higher Steam Rating)

Drop files into `audio/` as listed in `audio/README.md`. Free sources:

- [Sonniss GDC bundles](https://sonniss.com/gameaudiogdc) — horror SFX
- [freesound.org](https://freesound.org) — CC0 footsteps, wind
- [dova-s.jp](https://dova-s.jp) — Japanese ambient music

Until you add files, the game uses synthesized audio automatically.

---

## Export for Steam

1. **Project → Export…**
2. Select **Windows Desktop (Steam)** or **macOS Universal (Steam)**
3. Set export path (defaults to `build/windows/` or `build/macos/`)
4. **Export Project**

Upload the built folder (or `.zip`) to Steamworks as your depot build.

### Steamworks Setup (Summary)

1. Create app at [Steamworks](https://partner.steamgames.com/)
2. Store page: use title **Jukai No Yami — Sea of Trees Darkness**
3. Tags: Horror, Walking Simulator, Psychological Horror, Short, Atmospheric
4. Price: $4.99–$9.99 is typical for 10–15 min horror (or bundle later)
5. Install **GodotSteam** plugin when ready for achievements/cloud: https://github.com/GodotSteam/GodotSteam

---

## Store Page Copy (Starter)

**Short description:**  
A first-person Japanese folklore horror walk through Aokigahara at night. Your flashlight is the only barrier between you and the Yurei.

**Key features:**

- Flashlight + battery + sanity systems
- 4 collectible notes, 3 endings
- 5 scripted jump scares
- Yurei, Onryo, hanging spirits, stalker AI
- Bilingual UI (Japanese / English)

**Content warning:** Suicide themes, forest setting references Aokigahara. Required for Steam.

---

## Graphics Settings (In-Game)

| Setting | Effect |
|---------|--------|
| **Low** | No volumetric fog SSAO; lighter VHS |
| **Medium** | MSAA 2×, fog, SSAO, full VHS |
| **High** | MSAA 4×, SSIL, tree shadows, strongest grade |
| **Performance Mode** | Forces Low; for Intel i3 / old laptops |

---

## Legal / Assets

- Tree/level geometry: procedural (no Kenney import required in repo)
- Replace placeholder audio before launch for best results
- Icon: `icon.svg` — export 512×512 PNG for Steam capsule art

---

## Next Steps for Revenue

1. Record a **30–60 second trailer** (in-engine capture + subtle music)
2. Create **capsule art** 616×353 and **header** 460×215 on Steam
3. Add **5+ screenshots** at 1920×1080 with VHS on High quality
4. Wishlist campaign: Reddit r/horror, r/indiegaming, Japanese horror communities
5. Consider **demo** on Steam (first area only) to boost wishlists

Good luck — *その光だけが、彼女たちを引き離している。*
