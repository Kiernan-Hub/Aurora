# Art source panels and reference images

Inputs to `scripts/tools/build_ice_texture.py`, look-target references, and superseded build
outputs kept for comparison. **Nothing in here is loaded by the game.**

The `.gdignore` next to this file is what keeps Godot from importing the directory — without
it every panel here would be imported to VRAM and shipped in the export for nothing.

## Contents

Split into two subfolders on 2026-08-24; before that everything sat loose at this folder's top
level, and older docs and tool examples may still show the flat paths.

### `terrain/` — inputs to `build_ice_texture.py`

- `one.png` … `fifteen.png` — the ice panel generations, live inputs to
  `build_ice_texture.py`. The numbering is chronological, not meaningful; which panel built
  which shipped tile is the table in `docs/development/biomes.md`, "Per-biome ice textures".
- `raster_wall_1.png`, `raster_wall_2.png` — unused by any scene; safe to delete.
- `Glossy Frozen Lake.png`, `glossy biome trail.png` — the frozen lake's look targets.

### `background/` — inputs to `build_pano_strip.py`

- `arch_spike_massif.png` — **the source of the shipped
  `assets/textures/background/ice_pano.png`.** The rebuild is deterministic; verified
  byte-identical on 2026-08-24. Do not lose this file. `arch_spike_massif.xcf` and
  `spike_massif.xcf` are its GIMP working files.
- `example.png` — the load-bearing target-look reference, cited throughout
  `docs/research/background_differentiation.md`.
- `archtower.png`, `spikefield.png`, `massif.png` — the three hand-picked panels that were
  stitched into the panorama. `full_strip.png` is an intermediate stitch.
- `mountains.png` — a spare, not used by anything.

### Loose at the top level

- `coin_source.png`, `rare_coin_source.png` — the raw coin exports, before the transparent
  re-crops in `assets/sprites/`.
- `ChatGPT Image Aug 6, 2026, 07_13_24 PM.png` — the original art-direction reference the
  whole palette is a daylight reading of (`docs/development/visuals.md`). Deserves a real name.

`glacier_teal_faceted_depth_panel.png` was a stale 2026-08-08 build output kept as a
before/after reference for an unmatched depth ramp; it was deleted on 2026-08-24.

## Why they are all in here

**Everything above sat at the repository root until 2026-08-15.** Godot imports any image it
can see, and `export_presets.cfg` is `export_filter="all_resources"` — so 31MB of reference
art that no scene, script or resource has ever loaded was being imported to VRAM and shipped
inside the APK. The `.gdignore` in this directory is what stops that, and it only works for
things that live here. **Put new reference art in this folder, not at the root.**
