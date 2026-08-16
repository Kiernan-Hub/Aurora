# Art source panels and reference images

Inputs to `scripts/tools/build_ice_texture.py`, look-target references, and superseded build
outputs kept for comparison. **Nothing in here is loaded by the game.**

The `.gdignore` next to this file is what keeps Godot from importing the directory — without
it every panel here would be imported to VRAM and shipped in the export for nothing.

## Contents

- `glacier_teal_faceted_depth_panel.png` — a **stale build output**, not a source panel,
  despite the name. Built 2026-08-08, before `build_ice_texture.py` gained `match_depth_ramp()`
  and the `OUTPUT_FLOOR = 0.38` lift: it bottoms out at 0.227 and its depth ramp sits ~0.10 off
  the default tile's, which is exactly the whole-view brightness wobble that
  `MAX_ICE_RAMP_DEVIATION` now gates against. Superseded by
  `assets/textures/terrain/ice_faceted_depth.png`. Kept only as a before/after reference for
  what an unmatched ramp looks like.

- `one.png` … `fifteen.png` — the ice panel generations, live inputs to
  `build_ice_texture.py`. The numbering is chronological, not meaningful; which panel built
  which shipped tile is the table in `docs/development/biomes.md`, "Per-biome ice textures".
- `coin_source.png`, `rare_coin_source.png` — the raw coin exports, before the transparent
  re-crops in `assets/sprites/`.
- `ChatGPT Image Aug 6, 2026, 07_13_24 PM.png` — the original art-direction reference the
  whole palette is a daylight reading of (`docs/development/visuals.md`).
- `Glossy Frozen Lake.png`, `glossy biome trail.png` — the frozen lake's look targets
  (`HANDOFF.md`). Untracked, deliberately: they are big and they are the owner's inputs.

## Why they are all in here

**Everything above sat at the repository root until 2026-08-15.** Godot imports any image it
can see, and `export_presets.cfg` is `export_filter="all_resources"` — so 31MB of reference
art that no scene, script or resource has ever loaded was being imported to VRAM and shipped
inside the APK. The `.gdignore` in this directory is what stops that, and it only works for
things that live here. **Put new reference art in this folder, not at the root.**
