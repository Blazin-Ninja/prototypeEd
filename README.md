# Chimera Bond

Mobile-first, turn-based monster evolution RPG (Godot 4.3).  
You bond with **one** companion for the entire run. Defeat enemies and choose to **ABSORB** their DNA to mutate forever — or die trying.

## MVP Features

- 5 starters (2 unlocked by default; more via Evolution Tokens)
- Pokémon-style grid overworld (Mutant Forest playable)
- Random grass encounters, Alpha variants, turn-based combat
- Absorb / Leave with independent rolls (stats, abilities, elements, mutations)
- Ability evolution chains, max 6 abilities / 3 elements
- Forest boss (Elder Treant) + Hive finale boss (Hive Heart)
- Region stubs: Desert, Frozen Mountains, Alien Lab
- Permadeath runs + account Evolution Token shop
- Portrait mobile UI with virtual D-pad

## Requirements

- Godot **4.3** stable
- For Android APK: Android SDK 24+, Godot Android export templates, JDK 17

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
| D-pad / WASD / arrows | Move |
| A / Z / Enter | Interact |
| B / X / Esc | Status |
| Regions button | Travel between unlocked regions |

## Design notes

- Mid-regions are content stubs; clearing Forest unlocks Desert (stub) and **Meteor Hive** (MVP finale shortcut).
- Placeholder shapes only — no polished art yet.
- Offline single-player; save seams kept simple for future multiplayer.
