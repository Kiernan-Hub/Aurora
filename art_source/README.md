# Art source panels and reference images

Inputs to `scripts/tools/build_ice_texture.py`, look-target references, and superseded build
outputs kept for comparison. **Nothing in here is loaded by the game.**

## What is kept, and why (2026-10-04, ~96 MiB tracked)

| Folder | Size | Kind | Rule |
|---|---|---|---|
| `background/` | 38 MiB | **build input** (`pano.png`/`.xcf`) plus its provenance | keep; the GIMP files are the only editable source |
| `terrain/` | 29 MiB | **build input** for the ice tiles, plus the lake's two look targets | keep while any shipped tile traces to a panel |
| `aurora_reference/` | 6 MiB | **design authority** for the aurora's look (CLAUDE.md row 12) | keep |
| `audits/` | 20 MiB | **historical captures** from closed aurora investigations, cited by `docs/research/aurora_borealis.md` and the 2026-09-09 reviews | add nothing new; delete only in an explicit cleanup, keeping whatever a doc cites |
| top level | — | app-icon source, coin sources, the art-direction reference | keep |

**New investigation screenshots and logs go to a scratch directory, not here**, unless a doc
cites them. Deleting a tracked file does not shrink the git history, so a cleanup buys a smaller
checkout, not a smaller repo; no history rewrite or LFS move is planned (`audit.md` A12).
`scripts/check.sh` fails if this folder's `.gdignore` disappears or any of it reaches a pack.

The `.gdignore` next to this file is what keeps Godot from importing the directory — without
it every panel here would be imported to VRAM and shipped in the export for nothing.

## Contents

Split into two subfolders on 2026-08-24; before that everything sat loose at this folder's top
level, and older docs and tool examples may still show the flat paths.

### `terrain/` — inputs to `build_ice_texture.py`

- `one.png` … `sixteen.png` — the ice panel generations, live inputs to
  `build_ice_texture.py`. The numbering is chronological, not meaningful (`nine`, `ten` and
  `thirteen` were not kept); which panel built which shipped tile is the table in
  `docs/development/biomes.md`, "Per-biome ice textures". `sixteen.png` is the source of the
  shipped `ice_bubbled_depth.png`.
- `Glossy Frozen Lake.png`, `glossy biome trail.png` — the frozen lake's look targets.

### `background/` — inputs to `build_pano_strip.py`

- `pano.png` — **the current source of the shipped `assets/textures/background/ice_pano.png`**,
  as of 2026-08-25. It supersedes `arch_spike_massif.png` as the direct build input: it's
  `arch_spike_massif.png`'s art with a fourth panel (`sharp.png`) stitched onto it, widening the
  panorama from 3548px to 5220px — a step toward the repeat-cadence item in `HANDOFF.md`. The
  new cycle time HAS since been measured against `MAX_SPEED`: **106.1s**
  (`docs/review/2026-08-24-code-and-repo-review.md`, #4). `pano.xcf` is the GIMP working
  file (layered, not flattened — reopen it, don't restart from the PNG, if the seam needs more
  work). Rebuild with `python3 scripts/tools/build_pano_strip.py art_source/background/pano.png
  assets/textures/background/ice_pano.png`, and update `main.tscn`'s `IceStrip.source_skyline_y`
  to whatever the build prints — it moves if the art above the skyline changes at all.
- `arch_spike_massif.png` — the previous shipped source, now superseded by `pano.png` but kept
  for provenance (its art is still embedded in the new stitch). `arch_spike_massif.xcf` and
  `spike_massif.xcf` are its GIMP working files.
- `sharp.png`, `pano2.png` — the panel stitched onto `arch_spike_massif.png` to build `pano.png`.
  `pano2.png` is an earlier, too-short (725px) generation of the same panel; `sharp.png` (842px)
  is what actually got used, then scaled to 887px inside `pano.xcf` to match.
- `example.png` — the load-bearing target-look reference, cited throughout
  `docs/research/background_differentiation.md`.
- `archtower.png`, `spikefield.png`, `massif.png` — the three hand-picked panels that were
  stitched into `arch_spike_massif.png`. `full_strip.png` is an intermediate stitch of those
  three, one generation further back than `pano.xcf`. `spike_massif.png` is the PNG of
  `spike_massif.xcf`.
- `moons.png` — eight moon panels; panel 6 is the source of the shipped moon disc
  (`scripts/systems/sky_backdrop.gd`).

### `aurora_reference/` — the aurora's look

- `aurora_ref_1.png` … `aurora_ref_4.png` — the design authority for the aurora borealis
  (CLAUDE.md row 12: open it before guessing; it settled three wrong turns).

### `audits/` — historical captures

One folder per aurora slice or audit (`aurora-2026-09-09`, `aurora-*-slice`,
`aurora-flat-foundation`): screenshots behind conclusions recorded in
`docs/research/aurora_borealis.md` and `docs/review/2026-09-09-*.md`. Evidence for closed work,
not inputs to anything.

### Loose at the top level

- `aura.png` — **the app-icon source, and a 3×3 contact sheet of nine candidates, not an icon.**
  Input to `scripts/tools/build_app_icons.py`, which measures the sheet's gutters and cuts one
  tile. Shipping tile is row 1, column 2 (the aurora over dark peaks); `--row`/`--col` re-cuts a
  different one. What the three outputs in `assets/icons/` are for, and the four ways an app
  icon fails silently, are in `docs/development/visuals.md`, "The app icon".
- `coin_source.png`, `rare_coin_source.png` — the raw coin exports, before the transparent
  re-crops in `assets/sprites/`.
- `art_direction_reference_night.png` — the original art-direction reference the whole palette
  is a daylight reading of (`docs/development/visuals.md`). It is a *night* scene; the name says
  so because the palette deliberately is not. Renamed 2026-09-02 from a ChatGPT export filename.

`glacier_teal_faceted_depth_panel.png` was a stale 2026-08-08 build output kept as a
before/after reference for an unmatched depth ramp; it was deleted on 2026-08-24.
`background/mountains.png`, a spare not used by anything, was deleted on 2026-08-25.

## Why they are all in here

**Everything above sat at the repository root until 2026-08-15.** Godot imports any image it
can see, and `export_presets.cfg` is `export_filter="all_resources"` — so 31MB of reference
art that no scene, script or resource has ever loaded was being imported to VRAM and shipped
inside the APK. The `.gdignore` in this directory is what stops that, and it only works for
things that live here. **Put new reference art in this folder, not at the root.**
