# Chimera Bond

Mobile-first, turn-based monster evolution RPG (Godot 4.3).  
You bond with **one** companion for the entire run. Defeat enemies and choose to **ABSORB** their DNA to mutate forever — or die trying.

## MVP Features

- 5 starters (2 unlocked by default; more via Evolution Tokens) + Toxie Bane (evolves at Lv 8); Blazen Mouse evolves into Blazen Ninja at Lv 8
- Pokémon-style grid overworld with **5 dungeon floors per region**
- Random grass encounters, Alpha variants, turn-based combat
- Absorb / Leave with independent rolls (stats, abilities, elements, mutations)
- Ability evolution chains, max 6 abilities / 3 elements
- Forest boss (Elder Treant) + Hive finale boss (Hive Heart)
- Regions: Forest, Desert, Frozen Mountains, Alien Lab, Meteor Hive
- Companion XP levels + encounter levels that progress by floor
- Permadeath runs + account Evolution Token shop
- Portrait mobile UI with virtual joystick

## Requirements

- Godot **4.3** stable
- For Android APK: Android SDK 24+, Godot Android export templates, JDK 17
- For regenerating art: Python 3.10+ and Pillow (`pip install -r tools/requirements.txt`)

## Graphics

Game sprites/tiles are generated offline with Pillow scripts under [`tools/`](tools/). See [`tools/README.md`](tools/README.md) for setup, which scripts to run, and why **not** to replace the pipeline with LLM/AI image generation for the full asset set (mutation overlays and seamless tiles need consistent modular art).

```bash
pip install -r tools/requirements.txt
python3 tools/gen_realistic_creatures.py
python3 tools/gen_terrain_ultra.py
python3 tools/gen_realistic_flora_water.py
```

Reimport in Godot after regenerating PNGs.

## Run (editor / desktop)

```bash
godot --path . 
```

## Headless tests

```bash
godot --headless --path . res://tests/TestRunner.tscn
```

## Android export (cloud / CI)

1. Install Godot 4.3 + Android export templates  
2. Set Android SDK path in Godot Editor Settings (or `editor_settings` on CI)  
3. Export:

```bash
mkdir -p builds
godot --headless --path . --export-debug "Android" builds/ChimeraBond.apk
```

Web playtest export (optional for cloud iteration):

```bash
godot --headless --path . --export-debug "Web" builds/web/index.html
```

## Architecture

- `data/` — JSON content (creatures, abilities, elements, regions, progression)
- `scripts/domain/` — pure gameplay systems (combat, absorb, mutations…)
- `scripts/autoload/` — DataRegistry, SaveService, GameState, EventBus
- `scenes/` — Boot → Menu → Starter → Overworld ↔ Battle → Absorb → RunEnd

Adding a creature: append an entry in `data/creatures.json` with stats, families, abilities, and an `absorption` loot table. No code changes required.

## Controls

| Input | Action |
|-------|--------|
| Virtual joystick / WASD / arrows | Smooth move |
| A / Z / Enter | Interact |
| B / X / Esc | Status |
| Regions button | Travel between unlocked regions |

## Design notes

- Each region has **5 dungeon floors**. Floors 1–4 use stairs to descend; Floor 5 holds the region boss.
- Encounter levels and wild pressure rise with region index, floor depth, and bosses defeated.
- Toxie Bane evolves into Dread Basilisk at companion level 8.
- Blazen Mouse evolves into Blazen Ninja at companion level 8.
- Offline single-player; save seams kept simple for future multiplayer.
