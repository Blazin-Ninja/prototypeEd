# Graphics generation

Chimera Bond art is generated **offline** with Python + Pillow scripts in this folder, then committed under `assets/`. Runtime GDScript (`scripts/util/CreatureSprites.gd`, `TileArt.gd`, etc.) **loads** those PNGs — it does not paint base sprites.

## Should you use an LLM for graphics?

**No — not as the main art pipeline.**

| Tool | Use for | Avoid for |
|------|---------|-----------|
| Text LLM (ChatGPT, Claude, Cursor) | Improving these scripts, art notes, prompt drafts | Actual sprite pixels |
| Image model (Flux, SDXL, Midjourney) | Optional launcher icon / 1–2 hero showcase shots | Full creature set, mutation overlays, seamless tiles |
| These Pillow scripts | Whole-game regen from `data/creatures.json` | Photoreal / painterly look |

Why AI image models fight this project:

- Creatures need transparent PNGs named by id (`assets/creatures/{id}.png`)
- Mutations stack as overlays by slot (`assets/mutations/{slot}/{key}.png`) on a shared pose
- Overworld tiles need seamless / variant sets
- One Pillow run keeps style consistent across ~35 creatures + bosses

**Recommended:** improve Pillow (resolution, shading, species accents). Optionally use an image model only for a few hero icons, hand-fit to transparent BG + game pose. Do not regenerate all of `assets/` with AI unless you also redesign the mutation compositor.

Prefer game sprites around 416–512px (creatures) / 256px (tiles). Large AI PNGs bloat the APK (~50MB already).

## Setup

```bash
pip install -r tools/requirements.txt
```

Requires Python 3.10+.

## Scripts

| Script | Regenerates |
|--------|-------------|
| `gen_realistic_creatures.py` | Creature + boss PNGs (current quality) |
| `gen_terrain_ultra.py` | 256px terrain tiles |
| `gen_realistic_flora_water.py` | Trees + water refinements |
| `gen_graphics_overhaul.py` | Older full pass (creatures, mutations, arenas, FX, tiles, player) |
| `gen_phase_ab_art.py` | Early Phase A/B tiles + UI chrome |

Paths resolve relative to the repo root (parent of `tools/`).

## Run (from repo root)

```bash
python3 tools/gen_realistic_creatures.py
python3 tools/gen_terrain_ultra.py
python3 tools/gen_realistic_flora_water.py
```

Then open the project in Godot 4.3 so it reimports the new PNGs.

Current intended regenerators: creatures → `gen_realistic_creatures.py`; tiles → `gen_terrain_ultra.py`, then optionally `gen_realistic_flora_water.py`.
