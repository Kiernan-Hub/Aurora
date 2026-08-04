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
`Player.get_slope_tangent()` calls it on every grounded physics frame. It used to rebuild
the chunk's entire collision sample list on every call; as of `6a80b97` it indexes
`chunk_collision_sample_xs` / `chunk_collision_sample_heights`, built once per chunk by
`ensure_chunk_collision_samples` and pruned to `CHUNK_COLLISION_SAMPLE_CACHE_RADIUS`. The
bracketing scan inside it is *deliberately* still linear over ~33 entries — that preserves
the original tie-breaking (first bracketing pair wins; out-of-range falls back to the
chunk's first and last vertex), verified byte-identical over 20,000 samples.

## Chasms

A chasm is a rare **void**: a span of x with no collision and no fill, which the player
jumps or dies in. Added 2026-08-03.

**It is a `SEGMENT_TYPE_FLAT` segment carrying three extra spec keys** —
`void_start_offset`, `void_length`, `exit_drop`. Inside the void, `get_terrain_height()`
still returns the **lip height**. The height field never learns the ground is missing.

That one decision is the whole design. Because the field stays single-valued, continuous,
finite and flat, `get_fill_bottom_y`, `get_collision_chord_slope_angle`,
`get_slope_angle_at_x`, player tilt, `get_surface_world_y`, `recover_from_stall`, world
rebasing and both existing `terrain_invariant_check` assertions keep working **unmodified**.
Ground *presence* is a second, orthogonal fact behind `has_ground_at_world_x()`; only the
collision-chord emitter, the fill builder and the spawners consult it.

Rejected alternatives, for the record: `INF`/`NAN` over the void (breaks `get_fill_bottom_y`
and aims the player straight down via `atan2`), and a real canyon floor (two 90° faces —
that is the `large_valley` wall-wedge bug by construction).

**A chasm adds zero slope to the world.** The steepest terrain stays 20.13°, exactly as
without the feature — `terrain_invariant_check` asserts it. Both lips are exactly horizontal
for free, because every profile in `evaluate_segment_offset` already has zero derivative at
progress 0 and 1. This is why a void was buildable and a steep drop face was not: anything
at or above `floor_max_angle` is a **wall** to `CharacterBody2D`, and a height field cannot
represent an overhang at all.

**Cutting the geometry.** `add_segment_boundary_sample_world_xs` forces a sample vertex
exactly on each lip that falls strictly inside the chunk, so every chord and fill edge is
wholly inside or wholly outside the void and the **midpoint** decides — never a tie-break at
an endpoint. `build_chunk_surface` then skips emitting chords whose midpoint has no ground
(`ConcavePolygonShape2D.set_segments()` is a segment *soup*, so a hole is valid), and
`build_chunk_fill` emits one `Polygon2D` per contiguous ground run. On a chunk with no void
there is exactly one run spanning the chunk edges, so the output is identical to the
pre-chasm code — that equivalence is the no-regression argument, checked by running the
physics gates with `debug_chasm_disabled = true`.

**The collision sample arrays keep their void entries.** Only chord *emission* is filtered.
`get_collision_chord_slope_angle` reads those arrays and falls back to the chunk's first and
last vertex when nothing brackets, so pruning them would return an arbitrary 512px-chord
angle over a void instead of the correct **0**. That 0 is load-bearing: it is what carries a
speed-boosting player across a chasm (see `physics.md`).

**Rarity is a guaranteed minimum spacing, not a weight** — a weight permits two in a row,
and instant death is not a shape that may repeat adjacently. So the chasm bypasses the weight
table entirely: `build_segment_spec` checks `is_chasm_segment_index()` first. One per
56-segment window at a hash-chosen offset in `[14, 41]` ⇒ 29–83 segments apart, measured at
25k–58k world_x (≈35–85s). O(1), no neighbour lookback, no recursion, and **no read of
`segment_start_x_cache`** — `cache_previous_segment()` computes a length before writing its
start_x, and negative indices are real.

**Width is a table, and the table is gated on speed** (phase 2, 2026-08-03). `CHASM_VARIANTS`
holds three entries — narrow 160, standard 220, wide 280 — each with its own
`min_segment_index`, drawn by a weighted hash restricted to the variants legal at that
segment. Placement and width use separate hashes so the two are uncorrelated.

The per-variant gate is not stylistic. `CHASM_MAX_REACH_FRACTION` (0.55 of jump reach) is the
safety invariant, and the `SpeedManager` ramp has only reached ~545 px/s by the earliest
position a chasm may occupy — which allows at most a **240px** void there. So a wide chasm is
not a thing a chasm can be *anywhere*; it is only drawn once the ramp has produced the speed
that clears it. `min_segment_index` converts to world_x through `SMALL_SEGMENT_LENGTH`, the
shortest segment there is, so the bound is hard.

`terrain_invariant_check` derives those minimums rather than trusting them, in a
seed-independent `check_chasm_variant_table()` pass that runs once before the seed sweep:

| assertion | what it catches |
|---|---|
| `CHASM_VARIANT_NOT_CLEARABLE` | a variant unclearable at the earliest index it may occupy — the worst case no finite seed sweep is guaranteed to contain. Reports the `min_segment_index` that *would* work |
| `CHASM_LEAD_IN_TOO_SHORT` | a run-up shorter than the maximum jump reach |
| `CHASM_SEGMENT_TOO_SHORT` | run-up + void + flatness margin overflowing the segment |
| `CHASM_VARIANT_BELOW_GLOBAL_MIN` | a silently unreachable (dead) variant |
| `CHASM_TRIVIALLY_CLEARABLE` | *(per chasm)* a drop crossable by running off the edge. **Inert at `exit_drop` 0**, i.e. today |

`CHASM_LEAD_IN_LENGTH` is **900**, not v1's 640. The old value was derived from an unboosted
reach of 600px and missed `JUMP_BOOST_VELOCITY_MULTIPLIER` (√2), whose reach at `MAX_SPEED` is
848px — a jump-boosted player who jumped at the first pixel of the run-up landed 208px past
the near lip, inside the void. What the lead-in buys is precisely this: **no jump taken before
the chasm's own segment can reach the void.** It does *not* eliminate the window inside the
run-up from which an over-early jump lands short — for any lead-in `L` and reach `R` that
window is `(L−R, L+width−R)`, which is never empty. Jumping much too early is a mistake the
player can see; that is gameplay, not geometry.

**`exit_drop` is still 0, deliberately deferred to phase 3.** It is not a data change. The
field would need a step at the far lip — invisible to geometry, since no chord or fill edge
survives inside a void, but visible to the checker's 1px sweep, to `get_slope_angle_at_x` and
to `get_collision_chord_slope_angle`, all of which would need void guards. Decisively: a
boosting player skims the void at **near**-lip height on a gravity-free grounded model, so it
would arrive above a lower far lip with only `FLOOR_SNAP_LENGTH` (18px) of snap to catch it,
and hover in mid-air until the boost expired. `chasm_probe`'s boost trial checks survival and
reached-x, not contact, so it would not catch that as written.

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
