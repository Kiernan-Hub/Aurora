# Terrain pipeline implementation notes

Implementation-detail reference for `scripts/terrain/terrain_generator.gd`, split out
from `CLAUDE.md` — the load-bearing invariants (segment-cache ordering, purity, drift)
stay there; this file has the mechanics someone actively working in this file will
want. Read `get_terrain_height`/`get_segment_selection`/`build_chunk_surface` for the
actual algorithm.

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

## Feature history

`large_valley` was removed entirely and `mega_drop` was collapsed from 4 segments to
1 — full rationale and the bugs that drove both decisions: `docs/research/freeze_bug.md`.
