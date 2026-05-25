# Audio Assets — Jukai No Yami v2

All audio slots are placeholders. Drop OGG or WAV files into the correct folders.

## Required folder structure

```
audio/
├── sfx/
│   ├── footstep_wet_1.ogg
│   ├── footstep_wet_2.ogg
│   ├── footstep_wet_3.ogg
│   ├── note_pickup.ogg
│   ├── shrine_charge.ogg
│   ├── flashlight_click.ogg
│   ├── flashlight_off.ogg
│   ├── battery_low_beep.ogg     ← brief electronic beep when battery empty
│   └── jumpscare_sting.ogg      ← sharp orchestral hit / brass stab
├── ambient/
│   ├── forest_night.ogg         ← looping: crickets, distant wind, rain
│   ├── deep_forest_drip.ogg     ← looping: denser, water drips, low hum
│   ├── cave_wind.ogg            ← looping: cave air movement, eerie resonance
│   └── rain_light.ogg           ← looping: soft rainfall
└── ghost/
    ├── whisper_jp_1.ogg         ← "…tasukete…" barely audible (fade to nothing)
    ├── whisper_jp_2.ogg         ← "…naze kita no…" (why did you come)
    ├── whisper_jp_3.ogg         ← "…kaere…" (go away) — harshest
    ├── hair_dragging.ogg        ← wet hair dragging on wooden floor
    ├── yurei_shriek.ogg         ← classic J-horror shriek (see The Ring, Grudge)
    ├── onryo_growl.ogg          ← low guttural possessed growl
    ├── koto_horror_sting.ogg    ← single plucked koto + reverb tail
    ├── cry_distant.ogg          ← looping: very faint distant female sobbing
    ├── cry_closer.ogg           ← looping: closer, becoming recognizable
    ├── cry_clear.ogg            ← looping: "助けて" (tasukete) distinct in the cry
    └── cry_intense.ogg          ← looping: multiple overlapping voices, distorted
```

## Graduated Crying System

The game has a 4-tier crying system driven by sanity level:

| Sanity | Tier | Audio key    | Description                        |
|--------|------|--------------|------------------------------------|
| <70    | 0    | cry_distant  | Barely audible, barely a sound     |
| <50    | 1    | cry_closer   | Getting closer, name audible       |
| <30    | 2    | cry_clear    | "Tasukete" clearly heard           |
| <15    | 3    | cry_intense  | Multiple voices, very close, loud  |

**Creating the crying audio:**
- Record a woman sobbing softly at 4 different intensity levels
- Or: use ElevenLabs Japanese voice → process through Audacity:
  - Tier 0: -24 dB, high-pass filter (200 Hz), lots of reverb
  - Tier 1: -16 dB, slight low-pass, moderate reverb
  - Tier 2: -5 dB, minimal processing
  - Tier 3: +2 dB, chorus effect, slight pitch-shift down 10%, light distortion

## Jumpscare Sting

This is the most important audio file. Characteristics:
- Sudden loud brass/string hit (think Psycho strings but modern)
- Duration: 0.4–0.8 seconds
- Peak amplitude at ~0.05s then sharp decay
- Optional: add koto pluck underneath

Free sources: pixabay.com → search "horror sting", freesound.org CC0

## Audio Bus Setup (create in Godot Audio panel)

```
Master
├── Music    (-12 dB)
├── Ambient  (-6 dB)  ← looping forest ambience
├── SFX      (0 dB)   ← footsteps, flashlight, UI
└── Ghost    (-3 dB)  ← all ghost audio including crying
    └── Effect: Reverb (Large Hall, Spread 1.0, Wet 0.35)
```

Add **LowPassFilter** to Ghost bus cutoff 1800 Hz — makes cries sound muffled/distant even at max volume.
Add **Reverb** to Ghost bus — Large Hall preset makes whispers feel like they come from everywhere.

## Free Sources

| Asset              | Source                          | Notes                         |
|--------------------|---------------------------------|-------------------------------|
| Wet footsteps      | freesound.org CC0               | Search "wet footstep wood"    |
| Forest ambience    | freesound.org CC0               | Search "night forest rain"    |
| Horror sting       | pixabay.com/sound-effects       | Search "horror sting"         |
| Full SFX pack      | sonniss.com/gameaudiogdc        | Annual free GDC bundle        |
| Koto music         | dova-s.jp                       | Japanese free music library   |
| Voice/whispers     | ElevenLabs + Audacity           | JP female voice + processing  |
| Low-poly trees     | kenney.nl/assets/nature-kit     | CC0                           |
| Ghost models       | quaternius.com                  | CC0 character base            |
