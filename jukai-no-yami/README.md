# 樹海の闇 — Jukai No Yami
### Sea of Trees Darkness

A first-person Japanese folklore horror game set in Aokigahara (Aokigahara Jukai — the Sea of Trees) at night. Built in **Godot 4.3** with GDScript.

---

## Gameplay

Walk through pitch-black forest with only your flashlight. Manage limited battery, collect 4 suicide notes left by the dead, and survive encounters with Yurei and Onryo — vengeful spirits of Japanese folklore.

**Target playtime:** 10–15 minutes  
**Three endings:** Bad / Good / True (based on notes collected + final sanity)

---

## Core Mechanics

| Mechanic | Description |
|----------|-------------|
| **Flashlight** | Primary tool. Battery drains faster in open clearings. Flickers as sanity drops. Creates volumetric light rays in fog. |
| **Sanity** | Drains passively; faster in darkness. At 35%: Onryo spawns. At 0%: death. Restored only at Shinto shrines. |
| **5 Jump Scares** | All timed and scripted. Each uses the flashlight beam as the delivery mechanism. |
| **Crying Audio** | 4-tier system. Distant sobbing at sanity 70 → clear "tasukete" cries at 30 → overlapping voices at 15. |
| **Notes** | 4 collectibles. Each triggers a linked ghost. Collecting all 4 + high sanity = True Ending. |

---

## Ghost Types

### Yurei (幽霊)
Pale woman in white kimono, long wet black hair. Crawls toward you. **Banished by holding your gaze on her for 0.6 seconds.** Revealed in the flashlight beam triggers a jump scare.

### Onryo (怨霊)
Vengeful spirit. **Does NOT flee when looked at.** Instead freezes — classic "only moves when you look away" mechanic. Spawns only when sanity drops below 35%.

### Hanging Spirit (吊り幽霊)
Suspended from tree branches, head downward. Descends slowly if you linger nearby. `force_fast_drop()` used for a scripted drop scare above the fourth note.

### Peripheral Stalker
Only moves when not in your direct view. Teleports behind you when you look at it. Psychological — designed to make you feel followed.

---

## 5 Scripted Jump Scares

| # | Level | Trigger | Description |
|---|-------|---------|-------------|
| 1 | Forest Entrance | ~88 seconds | Yurei placed 18° off flashlight center — sweeping the beam reveals her |
| 2 | Forest Entrance | Pick up Note 0 | Yurei spawns 1m behind player; hair-drag audio cues a turn |
| 3 | Dense Tree Sea | ~62 seconds | Forced flashlight stutter → 400ms darkness → Onryo teleports 4m close |
| 4 | Dense Tree Sea | Pick up Note 2 | Hanging Spirit drops at 10× normal speed from directly above |
| 5 | Ribbon Path | Pick up Note 3 | Flashlight dies 550ms → Yurei appears at camera → MAX intensity reveal |

---

## Three Endings

| Ending | Condition |
|--------|-----------|
| **Bad** | Notes collected < 2, or any sanity |
| **Good** | Notes ≥ 2, sanity > 20% |
| **True** | All 4 notes, sanity > 50% |

---

## Areas

```
Forest Entrance → Dense Tree Sea → Ribbon Path → Cave Exit
      ↓                 ↓                ↓
  [Note 0]          [Note 1,2]        [Note 3]
  [Shrine 1]        [Shrine 2]        [EXIT]
  [Scares 1,2]      [Scares 3,4]      [Scare 5]
```

---

## Project Structure

```
jukai-no-yami/
├── project.godot                    ← Godot 4.3 project file
├── README.md
├── scenes/
│   ├── main/
│   │   ├── MainMenu.tscn
│   │   └── EndingScreen.tscn
│   ├── levels/
│   │   ├── ForestEntrance.tscn      ← Area 1
│   │   ├── DenseTreeSea.tscn        ← Area 2
│   │   └── RibbonPathCave.tscn      ← Area 3 + exit
│   ├── entities/
│   │   ├── Player.tscn              ← CharacterBody3D FPS controller
│   │   ├── YureiEntity.tscn
│   │   ├── OnryoEntity.tscn
│   │   ├── HangingSpirit.tscn
│   │   └── FlashlightBeam.tscn      ← Volumetric cone mesh
│   ├── interactables/
│   │   ├── CollectibleNote.tscn
│   │   └── Shrine.tscn
│   └── ui/
│       └── HUD.tscn
├── scripts/
│   ├── autoload/
│   │   ├── GameManager.gd           ← Global state, endings, level loading
│   │   ├── AudioManager.gd          ← All audio: SFX, ambient, crying system
│   │   └── JumpscareSystem.gd       ← Flash + static + camera shake (autoload)
│   ├── player/
│   │   ├── Player.gd                ← WASD + mouse look + head bob
│   │   ├── SanitySystem.gd          ← Drain/regen + shader params + crying tiers
│   │   └── Flashlight.gd            ← Battery + flicker + beam detection
│   ├── entities/
│   │   ├── YureiEntity.gd
│   │   ├── OnryoEntity.gd
│   │   ├── HangingSpirit.gd
│   │   ├── StalkerAI.gd
│   │   └── FlashlightBeamController.gd
│   ├── interactables/
│   │   ├── CollectibleNote.gd
│   │   └── ShrineInteraction.gd
│   ├── ui/
│   │   ├── UIManager.gd
│   │   ├── MainMenu.gd
│   │   ├── PauseMenu.gd
│   │   └── EndingScreen.gd
│   └── world/
│       ├── LevelManager.gd          ← Per-level setup, exit triggers
│       ├── TreeSpawner.gd           ← MultiMesh: all trees = 1 draw call
│       ├── RibbonSpawner.gd         ← MultiMesh: hanging white ribbons
│       ├── GhostSpawnDirector.gd    ← 5 timed/triggered jump scares
│       └── ClearingArea.gd          ← Open area → faster battery drain
├── shaders/
│   ├── sanity_vignette.gdshader     ← Vignette + desaturation + aberration
│   ├── ghost_material.gdshader      ← Translucent ghost with edge glow
│   ├── flashlight_volumetric.gdshader ← Fake volumetric beam cone
│   ├── static_overlay.gdshader      ← TV static for jump scare flash
│   └── rain_overlay.gdshader        ← Lens rain streaks (screen shader)
└── audio/
    └── README.md                    ← Placeholder paths + free asset sources
```

---

## Setup (macOS / Windows)

**Requirements:** Godot 4.3 (Standard, not .NET) — download from [godotengine.org](https://godotengine.org/download)

1. Clone this repo
2. Open Godot → Import → select `project.godot`
3. Press **F5** to run (audio buses, HUD shaders, and VHS post-process are wired automatically)
4. Optional: drop OGG files into `audio/` (see `audio/README.md`) for higher-quality sound
5. Optional: **Settings** in main menu → Graphics **High** for best visuals

**Steam release:** see [STEAM.md](STEAM.md) for export presets and store checklist.

### Performance Mode (Intel i3)

Enable in-game via Escape → Settings → Performance Mode. This disables volumetric fog and reduces fog density. Target: 30–60 FPS.

MultiMesh tree spawner means all 200–280 trees per level render in a **single draw call**.

---

## Controls

| Key | Action |
|-----|--------|
| WASD | Move |
| Mouse | Look |
| Shift | Sprint (drains sanity) |
| F | Toggle flashlight |
| E | Interact / collect |
| Esc | Pause |

---

## Credits & Free Assets

| Asset Type | Source |
|------------|--------|
| Low-poly trees/rocks | kenney.nl (CC0) |
| Ghost model base | quaternius.com (CC0) |
| Horror SFX | freesound.org (CC0), sonniss.com/gameaudiogdc |
| Japanese ambience | dova-s.jp |
| Whisper audio | ElevenLabs JP voice + Audacity pitch processing |

---

## Export (Steam)

Pre-configured presets in `export_presets.cfg`:

1. **Project → Export…**
2. Choose **Windows Desktop (Steam)** or **macOS Universal (Steam)**
3. Download export templates if prompted, then **Export Project**

See [STEAM.md](STEAM.md) for Steamworks, pricing, and marketing steps.

---

*"那人は、この森に戻ってきた。懐中電灯の光だけが、彼女たちを引き離している。"*  
*"That person returned to this forest. Only the flashlight's beam keeps them apart."*
