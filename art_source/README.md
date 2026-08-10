# Art source panels

Inputs to `scripts/tools/build_ice_texture.py`, and superseded build outputs kept for
reference. **Nothing in here is loaded by the game.**

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

The live source panels (`one.png` … `five.png`) are still at the repository root — the
locations `build_ice_texture.py`'s usage examples name. Moving them here would be a tidier
convention, but it means editing those examples, so it is left as its own change.
