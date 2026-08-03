# Terrain pipeline implementation notes

Implementation reference for `scripts/terrain/terrain_generator.gd`. `CLAUDE.md` keeps
only the invariants that break silently; everything else is here. Read
`get_terrain_height` / `get_segment_selection` / `build_chunk_surface` for the actual
algorithm.

## Two independent grids

**Chunks** (fixed 512px) are the spawn/despawn and render unit. **Segments** (variable
length) are the shape unit. They are deliberately **unaligned** — don't "fix" that.

The whole run is reproducible from one integer (`session_seed`): every segment is a pure
hash function of `(seed, index)`, with no RNG state anywhere. Baselines are cumulative
and **drift downward without bound** (`+Y` is down); there is no rebound, which is why
world rebasing exists.

## Chunk lifecycle

- Chunk `i` spans `[i*512, (i+1)*512)` and its node sits at `((i+0.5)*512, ground_y)`.
  Surface Y is a local offset from the shared origin `ground_y` (192) — **chunk nodes
  never move vertically.**
- `_physics_process` spawns up to `player_chunk + chunk_count_ahead` and frees below
  `player_chunk - chunk_count_behind`.
- `next_chunk_index` only ever increases, so chunks **cannot re-spawn behind the
  player**. That's safe because chunk identity comes from the pure height field, not
  from the `active_chunks` dict.
- `remove_chunk` uses `queue_free()`. It used to call `free()` synchronously, justified
  by the chunk being ≥1024px behind the player — but that is a distance margin, not a
  guarantee, and destroying a `StaticBody2D` mid-`_physics_process` is the documented
  unsafe case. Changed 2026-08-03; the extra frame the node survives is invisible
  because it is erased from `active_chunks` first and `next_chunk_index` only increases.
- No pooling; chunks rebuild from scratch on every spawn. `BackgroundGenerator` mirrors
  this scheme for 1024px stripes, indexed in *parallax-layer* space
  (`player.x * motion_scale.x`).

## Segment cache ordering

**Always call `ensure_segment_cache_for_world_x(x)` before `find_segment_index_at_x(x)`.**
Otherwise the binary search silently clamps to the cached range and returns the wrong
segment — no error, just wrong terrain.

## Segment spec caching

A segment's shape, length, magnitude, tier, and debug label all come from one place:
`build_segment_spec`, cached per-index in `segment_spec_cache` via `get_segment_spec`.
This replaced five independent dispatch chains (`get_segment_type`/`get_segment_length`/
`get_segment_baseline_delta`/`get_segment_tier`/`get_segment_selection_label`) that
each re-derived the same thing and could silently disagree. Adding a new segment type
means adding one branch to `build_segment_spec` — don't reintroduce a parallel
if-chain elsewhere.

`get_segment_baseline_delta` is **derived**, not hand-written: it evaluates
`evaluate_segment_offset(spec, 1.0)` — the segment's own shape function at its
endpoint. C0 continuity between segments is guaranteed by construction; there is no
separately-maintained delta that can drift out of sync with the shape.

`is_mega_drop_segment` is an O(1) selection check, not a recursive predicate —
`mega_drop` is a single segment (see `docs/research/freeze_bug.md`), so there is no
neighbour lookback anywhere in the file anymore.

## Fill polygon depth

Fill polygon closes at `max(surface_y) + 4096` (`TERRAIN_FILL_DEPTH_MARGIN`),
recomputed per chunk — never hardcode this depth, baselines drift thousands of px
down over a run.

## Complexity dial for bisecting terrain bugs

`TerrainGenerator.debug_weight_*` (`debug_weight_flat`, `debug_weight_small_hill`,
`debug_weight_medium_hill_valley_mix`, `debug_weight_big_downhill`,
`debug_weight_gentle_uphill`, `debug_weight_mega_drop`) — set any weight to 0 to
remove that shape from the world entirely (uses the existing weight<=0 skip in the
selection code, zero new dispatch logic). Defaults reproduce the shipping mix. Useful
for isolating which segment type a bug reproduces on without editing code.

## Performance

`build_chunk_surface` does ~64 `get_terrain_height` calls per spawn.
`is_mega_drop_segment` used to be the frame-time spike here (4 recursive lookups,
each itself recursing 3 segments back) — it's now an O(1) selection check since
`mega_drop` collapsed to a single segment (see `docs/research/freeze_bug.md`). Don't
raise `height_sample_count` or lower `MAX_COLLISION_SEGMENT_LENGTH` casually
regardless. `add_unique_sample_world_x` is O(n²), fine at n≈35 only. Segment caches
(`segment_start_x_cache`, `segment_length_cache`, `segment_baseline_cache`,
`segment_spec_cache`) grow all session, never trimmed — fine for a few-minute run.

**The hottest path is `get_collision_chord_slope_angle`, not chunk spawning.**
`Player.get_slope_tangent()` calls it on every grounded physics frame, and it rebuilds
the chunk's entire collision sample list from scratch each time — the O(n²)
`add_unique_sample_world_x` loop at n≈35, a sort, two `ensure_segment_cache_for_world_x`
calls and two `find_segment_index_at_x` binary searches, then two `get_terrain_height`
evaluations. That's ~60×/s on top of the per-spawn cost above. The sample list is a pure
function of `chunk_index`, so it is cacheable per chunk — worth doing if mobile frame
time ever becomes a problem, but measure before assuming this is the bottleneck.

## Feature history

`large_valley` was removed entirely and `mega_drop` was collapsed from 4 segments to
1 — full rationale and the bugs that drove both decisions: `docs/research/freeze_bug.md`.
Both are permanent decisions.

`mega_drop` is additionally **disabled** as of 2026-08-01
(`MEGA_DROP_SELECTION_WEIGHT = 0`) over a visual shake nothing could fix; the generator
code is deliberately left intact, so restoring it is a one-constant change back to 10.
See "Known issues" in `CLAUDE.md` and `docs/research/camera_shake.md`.

**Consequence worth knowing:** with `mega_drop` gone the steepest slope the generator
can produce is **20.13°**, down from 40.5°. Anything written assuming a
near-`floor_max_angle` face still exists in the world is now wrong.
