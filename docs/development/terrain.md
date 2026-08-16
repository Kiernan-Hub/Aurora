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

## Oversized hills

Every hill and valley rolls an independent `BIG_HILL_CHANCE_PERCENT` (10%) chance of being
oversized, at a scale drawn from `BIG_HILL_SCALES` (×1.5 or ×2.0). Measured over 8 seeds ×
900 segments: 10.2% of hills, split 231/208 between the two scales.

**The scale multiplies `length` and `magnitude` together, and that is the whole safety
argument.** Peak slope of the `sin²(πp)` profile is `atan(π·magnitude/length)` — a function of
the *ratio* only. `SMALL_HILL_AMPLITUDE`/`SMALL_SEGMENT_LENGTH` (56/480) and
`MEDIUM_HILL_AMPLITUDE`/`MEDIUM_SEGMENT_LENGTH` (74/640) already sit at this project's 20.13°
ceiling, so raising amplitude alone raises slope — and slope at or above `floor_max_angle` is
the wall-wedge failure that cost `large_valley` and `mega_drop`. Scaling both leaves
`max_slope` bit-identical; `terrain_invariant_check` reports it as 20.13° before and after.

Two consequences worth knowing:

- Curvature is `magnitude/length²`, so it **drops by 1/scale**. A big hill is geometrically
  *smoother* than a normal one and cannot worsen the residual hill camera jerk.
- Scaling **up** keeps `SMALL_SEGMENT_LENGTH` true as "the shortest segment there is", which
  is the hard bound `CHASM_MIN_SEGMENT_INDEX` and the checker convert segment indices to
  world_x through. Nothing in that derivation needed to change. A future *shrinking* scale
  would break it.

Big hills roll independently, so two in a row are possible and deliberately left possible —
same shape, same slope, so a run of them is a longer rolling stretch rather than a hazard, and
suppressing it would need the neighbour lookback this generator has none of. Their debug label
gains a `_big` suffix; normal hills keep their exact existing labels, which archived probes
match as string literals.

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
holds four entries — the three *hazards* narrow 160, standard 220, wide 280, plus the
`chasm_drop` described below — each with its own `min_segment_index`, drawn by a weighted hash
restricted to the variants legal at that segment. Placement and width use separate hashes so
the two are uncorrelated.

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
| `CHASM_VARIANT_NOT_CLEARABLE_AT_MIN_UPGRADE` | a variant wider than a level-0 player's *entire* reach — a wall rather than a hazard |
| `CHASM_LEAD_IN_TOO_SHORT` | a run-up shorter than the maximum jump reach |
| `CHASM_SEGMENT_TOO_SHORT` | run-up + void + flatness margin overflowing the segment |
| `CHASM_VARIANT_BELOW_GLOBAL_MIN` | a silently unreachable (dead) variant |
| `CHASM_TRIVIALLY_CLEARABLE` | *(per chasm)* a drop crossable by running off the edge. **Inert at `exit_drop` 0**, i.e. today |
| `UPGRADE_CEILING_EXCEEDS_CHASM_LEAD_IN` | a jump upgrade curve whose maximum outruns the run-up |
| `OBSTACLE_APEX_TOO_LOW` / `OBSTACLE_WINDOW_TOO_TIGHT` | a jump upgrade curve whose *minimum* cannot clear a 32×32 obstacle at the first cluster |

**Jump strength is a range now, so clearability is asserted in two bands** (2026-08-04,
meta-progression). This file used to evaluate reach at a hardcoded multiplier of 1.0 and
call it "the weakest jump" — true only while 1.0 was the only jump. It is now the
*strongest*: the upgrade curve runs ×0.60 → ×1.00 and the player starts nerfed. So
`CHASM_MAX_REACH_FRACTION` (0.55) is checked against **max upgrade** — is this well-tuned
for someone who has finished the curve — and `CHASM_MIN_UPGRADE_REACH_FRACTION` (0.90)
against **min upgrade** — is it physically possible at all for someone who has bought
nothing. Neither band alone is sufficient, and there is deliberately no unqualified
`get_jump_reach()` left, so no call site can silently mean the wrong one.

`CHASM_LEAD_IN_LENGTH` is **900**, not v1's 640. The old value was derived from an unboosted
reach of 600px and missed `JUMP_BOOST_VELOCITY_MULTIPLIER` (√2), whose reach at `MAX_SPEED` is
848px — a jump-boosted player who jumped at the first pixel of the run-up landed 208px past
the near lip, inside the void. What the lead-in buys is precisely this: **no jump taken before
the chasm's own segment can reach the void.** It does *not* eliminate the window inside the
run-up from which an over-early jump lands short — for any lead-in `L` and reach `R` that
window is `(L−R, L+width−R)`, which is never empty. Jumping much too early is a mistake the
player can see; that is gameplay, not geometry.

## Drop chasms (phase 3, shipped `b3d05fd`)

`chasm_drop` is the fourth variant and the only one with a non-zero `exit_drop`: a 320px void
whose far lip sits **800px lower**, giving ~1.0s of airtime
(`sqrt(2·800/GRAVITY)`). It is deliberately **not a hazard** — `must_be_jumped` is `false`,
and it is crossed by simply running off the near lip (545px of travel at the slowest speed it
can appear at, against a 320px void). The checker asserts the *opposite* property for it:
`CHASM_TRIVIALLY_CLEARABLE` is the requirement here, not the violation.

**The drop is a step at the far lip, not a ramp across the void.** `get_exit_drop_offset()`
returns 0 for the whole void and `exit_drop` from the far lip onward, so the field inside the
void still reads flat at **near**-lip height and every existing query is bit-identical to
phase 2 — no void guards anywhere. A ramp would have been continuous, but 800px over 320px is
a 68° chord, and `get_collision_chord_slope_angle()` would then aim a boosting player straight
down it instead of returning the 0 that carries the skim (`physics.md`, load-bearing).

That step is the generator's only height-field discontinuity. It is safe because **nothing
spans it**: the far lip is already a forced collision vertex (`add_lip_sample_world_x`) and a
fill-run boundary (`split_surface_into_ground_runs`), so no chord and no polygon edge crosses
it. `terrain_invariant_check` permits a step *only* at a far lip and asserts it equals that
variant's `exit_drop` — strictly stronger than the blanket no-step check it replaced.

Two consumers outside the generator close the loop:

- `Player.is_boost_gliding_over_drop()` (`player.gd:494`) hands a boosting player to gravity
  the moment ground reappears below them. Without it the gravity-free grounded model skims at
  near-lip height and hovers in mid-air until the boost timer expires, with only
  `FLOOR_SNAP_LENGTH` (18px) of snap to catch the lower lip.
- `get_pending_exit_drop_at_world_x()` is added to the surface `Player.update_fall_death()`
  measures against (`player.gd:562`). Without it the crossing itself reads as a fall: at
  545 px/s a 320px void takes 0.587s ⇒ a 276px drop against `FALL_DEATH_DEPTH` of 200.

**Frequency is periodic, not weighted** (2026-08-06). `chasm_drop` carries weight **0** and is
placed by `CHASM_DROP_WINDOW_PERIOD` instead: exactly one chasm exists per window, so the
window index *is* the chasm ordinal, and every 2nd one is a drop. This was a weighted 3-of-13
draw, which measured **one drop per 3–5 minutes** — four seeds × 120,000 world_x produced a
single drop chasm, so most runs contained none of the game's best beat.

The period turns a 23% chance into a hard bound. Consecutive drops are exactly
`CHASM_DROP_WINDOW_PERIOD` windows apart, so the gap is 112 segments ± the spread of the two
offset draws (`[14, 41]`) ⇒ **85–139 segments**. That is *tighter* than doubling the 29–83
single-chasm spacing, because those extremes require adjacent windows to draw opposite
offsets and two windows apart cannot compound them. Measured over 8 seeds × 900 segments:
gaps of 91–134 segments / 68,480–100,000 world_x ⇒ ≈**1.5–2.8 minutes**.

Window 0 is a drop, so the **first void of every run is the survivable one** — the player
learns what a void looks like before one can kill them. The cost is that the first *hazard*
chasm now arrives one chasm later than it used to.

## The frozen lake — the one runtime input to the height field

A **7500px dead-flat segment** injected at runtime for the frozen lake set piece. Every other
segment in the file is a pure hash of `(session_seed, index)`; this one is not, and it is the
only exception the project allows.

`FrozenLakeDirector` owns *when* (see `architecture.md`); everything below is the generator's
half.

### The purity relaxation, stated exactly

`get_terrain_height` stays pure in `(session_seed, world_x)` **plus one runtime input**,
`lake_segment_index`, under a **write-once, write-ahead** rule:

> `arm_lake()` is its only writer, and may set it only to an index **strictly greater than
> `highest_cached_segment_index`** — a segment whose spec, length, start_x and baseline have
> never been computed.

Segment caches only ever grow forward and are never trimmed, so such an index is provably
virgin. **Arming can therefore only EXTEND the height field, never REWRITE it.** Never assign
`lake_segment_index` directly.

**What enforces it is not the constant you would guess.** `arm_lake()` starts its candidate at
`highest_cached_segment_index + LAKE_ARM_LEAD_SEGMENTS`, but the guarantee comes from the skip
loop's `segment_spec_cache.has(candidate)` test, which walks forward past every cached index
onto the first virgin one. `LAKE_ARM_LEAD_SEGMENTS` is only a head start — mutation-tested in
step 8, where starting the candidate 10 segments *behind* the watermark still armed legally.
The same loop also steps past any index whose segment, or either neighbour, is a chasm.

### Why breaking it is the worst kind of bug

Arming at or below the watermark rewrites height that chunks, collision, player tilt and the
debug HUD have already sampled independently. Nothing throws. Chunks already built keep the old
geometry and only chunks built *later* see the lake, so the terrain silently disagrees with
itself behind the player — the freeze class that cost this project weeks.

**The disagreement is between two generators, never inside one.** `get_terrain_height` reads a
*cached* spec, so the generator that armed is exactly the one that cannot see the damage.
Re-sampling it either side of `arm_lake()` reads zero drift while maximally broken. Any future
test of this must compare against a **freshly built** generator; `check_lake_arming()` does.

### The shape, and why flat is the safety argument

Flatness is not an aesthetic choice. **Zero slope cannot reach `floor_max_angle`**, so no
wall-wedge is reachable on a lake no matter what it lands next to — which is what makes
injecting terrain at runtime defensible at all. Magnitude is exactly `0.0`, so both seams are C0
by construction (the baseline delta derives to `0.0`) and flatness is exact in binary rather
than approximately equal.

`is_lake_world_x(world_x)` is the query every spawner asks, deliberately the same shape as
`has_ground_at_world_x()` so suppression reads as one more reason a slot is unusable rather than
as a new concept. With no lake armed it is a single int compare and never touches the segment
cache — which matters, because six spawners call it per candidate item.

`get_lake_start_x()` / `get_lake_end_x()` both call `ensure_segment_cache_through()` first:
`start_x` for a segment past the watermark does not exist until the cache is walked out to it.
That is the `find_segment_index_at_x` ordering trap above, in its other form.

### Gate coverage

`terrain_invariant_check` has two independent lake passes, and the split matters:

| Pass | Covers |
|---|---|
| `check_frozen_lake()` | **The shape.** Span, flatness, no void inside, C0 seams, no chasm adjacent. Pins the lake with `debug_force_lake_segment_index`, so it says nothing about arming |
| `check_lake_arming()` | **The arming path.** Six assertions, including the write-ahead comparison and a fresh-generator agreement check |

Baseline: `flatness=0.000000` span exactly 7500.0; `watermark=164 armed_index=166 drift=0
fresh_disagreements=0`.

**Spawner suppression is gated separately** by `lake_suppression_probe.gd` — it needs live
spawners, which this geometry-only file cannot host. See `debugging.md`.

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
