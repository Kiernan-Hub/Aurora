# Aura — endless 2D skater (Godot 4.7, GDScript, Mobile renderer)

Alto's-Adventure-style endless downhill skater: player auto-runs right at a
speed that ramps over time, riding an infinite, seeded, procedurally generated
terrain. All on-screen art is placeholder `ColorRect`/`Polygon2D`.

**Priority order:** terrain stability > physics/collision correctness > game
feel. Missions, upgrades, and visual polish are deprioritized until the core
loop is stable (see Build order at the bottom).

## AI editing rules

- Inspect connected files and investigate root cause before modifying or
  fixing anything. Prefer targeted changes; preserve existing architecture
  unless you have a clear reason to change it — then propose and explain first.

`project.godot`: features `4.7` + `Mobile`, physics **60 Hz**, interpolation
**OFF**. Some terrain constants derive from `1.0/physics_ticks_per_second` —
changing tick rate silently changes level geometry.

## Run / debug / test

No test suite, no build script. Godot: `/Applications/Godot.app/Contents/MacOS/Godot`
(play with `--path .`, opens a window and blocks — only when asked).

Headless freeze-regression replay:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/freeze_replay_runner.gd -- --seed=941462462 --frames=60000 --runs=1
```
Instantiates `main.tscn`, forces `debug_replay_session_seed`, steps physics
frames, prints `status=no_freeze|freeze_detected|tree_paused|stall_recovered`.
Run after any change to player physics, collision, or segment code.
**`--frames` must be large.** 400 frames (the count documented here until this was
corrected) is 6.7s ≈ 2,000 world_x; every recorded freeze is beyond world_x
175,000, i.e. past frame ~25,000. Short runs report `no_freeze` unconditionally.
`--rebase=0` disables world rebasing for A/B work (see `scripts/systems/world_rebaser.gd`).

**This runner alone is not sufficient.** It replays from spawn with no input, and
a 60,000-frame no-input replay of seed 941462462 passes even with the fix disabled
— the real reproduction needed a warp plus a jump schedule. The harness that
actually finds stalls is `scripts/debug/freeze_search.gd`, which sweeps sub-pixel
start phases × input schedules at a target world_x:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/freeze_search.gd -- --seed=941462462 --warp=175000 --to=178000 --phases=8 --phasestep=0.25 --scan=1 --trialframes=500 --rebase=1
```
Expect `trials with a STALL : 0`. With `--rebase=0` the same command yields 1.

Both harnesses above need a physics reproduction to find a geometry bug. For pure
terrain-shape bugs (a face steeper than `floor_max_angle`, a discontinuous seam)
there's a much faster, physics-free gate:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/terrain_invariant_check.gd -- --seeds=8 --to=300000
```
Samples the height field at 1px and asserts no Y discontinuity and no slope
exceeding `floor_max_angle`, across N random seeds, in seconds. This is what should
have caught the 80.4° `large_valley` face (below) on day one instead of day seven —
run it after any change to segment shape, length, or baseline-delta logic, before
reaching for the physics harnesses. Expect `status=PASS` for every seed.

Debug tooling: `Player.DEBUG_SHOW_PLAYER_STATE` builds a runtime `Label` with
live physics/terrain state incl. **session seed** — read it to reproduce a bug
via `--seed=`. `Player.DEBUG_LOG_FREEZE_REPRO` prints `FREEZE_REPRO` when
grounded with `|velocity.x| >= 1` but `|motion.x| <= 0.01`, emitting
`debug_freeze_detected(session_seed)` — what the replay runner watches.
Log any seed that triggers `FREEZE_REPRO` or a visual bug here, with a one-line
description, before fixing it. Known-bad seeds (all the same float32 bug, all fixed
by world rebasing — the reported normal is an exact small-integer ratio, which is
the signature; real terrain slopes are irrational):

| seed | world_x | reported floor normal | ratio |
|---|---|---|---|
| 941462462 | 175,552 | (0.169391, -0.985549) | 11/64 |
| 2160065702 | 226,800 / 237,919 | (0.338199, -0.941075) | 23/64 |
| 3188032853 | 264,063 / 294,719 | (0.242536, -0.970143) | — |

A **second, distinct** stall class was found and fixed separately (`fd59c53`):
`large_valley`'s drop face used to be steep enough (80.4°) to exceed
`floor_max_angle`, so the physics engine treated it as a wall and the player
wedged at the lip instead of riding or launching off it. Not a float precision
issue — real terrain geometry, confirmed by 1px-resolution height sampling.
`large_valley` itself has since been **removed entirely** (see "Terrain feature
history" below) rather than re-tuned again, since it was also the sole source of
the file's coupling to `GRAVITY`/`INITIAL_SPEED`/tick-rate. `Player.update_stuck_detection()`
remains as a second, independent watchdog
(alongside `recover_from_stall`'s per-frame one) for exactly this shape of bug:
jittering-in-place defeats a per-frame consecutive-stall predicate since no single
frame reads exactly 0, so it tracks **net** progress over a rolling window instead.

`Player.recover_from_stall()` is the watchdog: after
`STALL_RECOVERY_FRAME_THRESHOLD` consecutive stalled frames it re-seats the body on
the terrain height field, prints `STALL_RECOVERY`, and bumps
`debug_stall_recovery_count`. A passing regression run must show **zero**
recoveries — a non-zero count means a stall still happened and was papered over.
`TerrainGenerator.debug_log_segment_selection` / `DEBUG_TERRAIN_LOGGING` /
`Player.DEBUG_SLOPE_LOGGING` are `const` toggles for per-frame spam.

## Scene graph (`scenes/main.tscn`)

```
Main (Node2D, scripts/main.gd)
├── ParallaxBackground/ParallaxLayer  motion_scale (0.3,0) ← background_generator.gd
├── Player            position (64,136), safe_margin 1.0  ← player.tscn
├── TerrainGenerator  player_path = ../Player
├── Camera2D          position (0,136)
├── GameManager       scripts/game/game_manager.gd
└── CanvasLayer/YouDiedLabel  (hidden until death)
```

Wiring is by sibling path — **no autoloads, no `autoloads/` dir** (ignore
older docs claiming `GameState.gd` exists). `BackgroundGenerator` falls back
to `/root/Main/Player` if `player_path` unset. `TerrainGenerator._ready()` reads
`player.floor_max_angle` into `session_floor_max_angle`, but `Player` never sets
`floor_max_angle` explicitly (it stays at CharacterBody2D's engine default), so
this read is not order-sensitive. Sibling order **was** load-bearing until the
`large_valley` cut: that feature additionally cached `player.floor_snap_length`
before use, and reordering the two nodes fed it Godot's default instead of
`Player.FLOOR_SNAP_LENGTH`. With `large_valley` removed, that path no longer
exists — don't assume a new feature reading `player.*` at `_ready()` is safe
without rechecking this.

## Terrain pipeline (`scripts/terrain/terrain_generator.gd`)

Two independent grids: **chunks** (fixed 512px — spawn/despawn + render unit)
and **segments** (variable length — the shape unit), deliberately unaligned.
Read `get_terrain_height`/`get_segment_selection`/`build_chunk_surface` for
the actual algorithm — these are the gotchas that aren't obvious from a read:

- Whole run is reproducible from one integer (`session_seed`); every segment
  is a pure hash function of `(seed, index)`, no RNG state.
- A segment's shape, length, magnitude (drop depth / rise height / hill-valley
  amplitude — one field, since `evaluate_segment_offset` uses it identically per
  type), tier, and debug label all come from one place: `build_segment_spec`,
  cached per-index in `segment_spec_cache` via `get_segment_spec`. This replaced
  five independent dispatch chains (`get_segment_type`/`get_segment_length`/
  `get_segment_baseline_delta`/`get_segment_tier`/`get_segment_selection_label`)
  that each re-derived the same thing and could silently disagree. Adding a new
  segment type means adding one branch to `build_segment_spec` — don't reintroduce
  a parallel if-chain elsewhere.
- `get_segment_baseline_delta` is **derived**, not hand-written: it evaluates
  `evaluate_segment_offset(spec, 1.0)` — the segment's own shape function at its
  endpoint. C0 continuity between segments is guaranteed by construction; there
  is no longer a separately-maintained delta that can drift out of sync with the
  shape.
- `is_mega_drop_segment` is an O(1) selection check, not a recursive predicate —
  `mega_drop` is a single segment (see "Terrain feature history" below), so there
  is no neighbour lookback anywhere in the file anymore.
- Baselines are cumulative and **drift downward without bound** (`+Y` down);
  there's no rebound.
- **Always call `ensure_segment_cache_for_world_x(x)` before
  `find_segment_index_at_x(x)`** — otherwise the cache's binary search
  silently clamps and returns the wrong segment.
- Fill polygon closes at `max(surface_y) + 4096`, recomputed per chunk —
  never hardcode this depth, baselines drift thousands of px down over a run.
- `TerrainGenerator.debug_weight_*` (`debug_weight_flat`, `debug_weight_small_hill`,
  `debug_weight_medium_hill_valley_mix`, `debug_weight_big_downhill`,
  `debug_weight_gentle_uphill`, `debug_weight_mega_drop`) is a complexity dial for
  bisecting terrain bugs: set any weight to 0 to remove that shape from the world
  entirely (uses the existing weight<=0 skip in the selection code, zero new
  dispatch logic). Defaults reproduce the shipping mix.

## Terrain feature history

- **`large_valley` was removed** (not re-tuned again after the 80.4° bug above).
  It was ~75 lines for a 180px valley with a flat floor — a marginal variant of
  `medium_valley`, which already exists and costs ~2 lines — and it was the
  **only** place in the file reading `Player.GRAVITY`, `SpeedManager.INITIAL_SPEED`,
  or `Engine.physics_ticks_per_second`. Removing it collapsed terrain's physics
  coupling to a single constant (`floor_max_angle`, used only by `mega_drop`) and
  deleted all four of its interacting minimum-length rules along with the
  `maxf`/`minf` trap that shipped the 80.4° face. `SEGMENT_TIER_LARGE` is gone
  with it; tier is now just SMALL/MEDIUM.
- **`mega_drop` was collapsed from 4 linear segments to 1 eased segment.** The old
  version was joined by `is_mega_drop_segment`/`is_mega_drop_start_segment` mutual
  recursion (4× a lookup that itself recursed 3 segments back — the frame-time
  spike noted below) and was *linear*, butted directly against neighbouring
  curves that end at slope 0: an instantaneous ~40° kink at both entry and exit,
  the only slope discontinuity in the world, and the likely source of a
  perceived "jumpy" feel distinct from the freeze bugs above. It's now one
  segment using the same ease-in/out profile (`get_transition_profile`) every
  other feature uses, at length `(TOTAL_VERTICAL_DROP * PI) / (2 * tan(peak_angle))`
  — same 1080px total drop, same ~40.5° peak angle, but eased in and out to
  slope 0 like everything else. `get_mega_drop_length()`/`get_mega_drop_angle()`
  are the only surviving mega_drop-specific functions.
- Dead obstacle-spawning code was deleted outright (see "Dead / disabled code"
  below) rather than left commented out.

## Chunk lifecycle

- Chunk `i` spans `[i*512,(i+1)*512)`; node sits at `((i+0.5)*512, ground_y)`
  — surface Y is a local offset from shared origin `ground_y` (192); chunk
  nodes never move vertically.
- `_physics_process` spawns to `player_chunk + chunk_count_ahead`, frees below
  `player_chunk - chunk_count_behind`. `next_chunk_index` only increases —
  **can't re-spawn behind the player**; identity comes from the pure height
  field, not this dict. `remove_chunk` calls `chunk.free()` immediately (not
  `queue_free()`) — safe only because a despawning chunk is ≥1024px behind.
- No pooling — chunks rebuild from scratch every spawn. `BackgroundGenerator`
  mirrors this for 1024px stripes, indexed in *parallax-layer* space
  (`player.x * motion_scale.x`).

## Things that break silently

- **World rebasing must stay on.** `Main.world_rebase_enabled` is intentionally
  *not* `@export`ed: while it was, `main.tscn` serialised it to `false` and silently
  reintroduced the freeze for weeks after it had been fixed and verified. Terrain
  baselines drift downward without bound, so contact Y reaches tens of thousands of
  px; float32 ulp there coarsens to ~1/512, contact separation vectors (order
  `safe_margin` = 1px) quantise, and `get_floor_normal()` starts returning
  off-vertical normals on provably flat ground. Don't re-export it, don't set it
  from a scene. See `scripts/systems/world_rebaser.gd` for the measured chain.
- `get_terrain_height` must stay **pure** in `(session_seed, world_x)` — chunk
  visuals, collision, player tilt, and the debug HUD all sample it separately.
- Segment length, baseline delta, and the height curve agreeing is now
  **structural**, not a manual invariant to maintain: `get_segment_baseline_delta`
  evaluates the same shape function `get_terrain_height` uses, at progress=1.0
  (see "Terrain pipeline" above). A new segment type only needs one entry in
  `build_segment_spec`; there's no second place to keep in sync. Player spawn
  `(64,136)` = `ground_y(192) + surface_y_offset(-32) − capsule half-height(24)`
  is still a manual invariant, though — changing either without updating
  `Player` position in `main.tscn` drops or embeds the player at t=0.
- Player/terrain/obstacles share collision layer/mask **1**; `obstacle.gd`
  filters via `body.is_in_group("player")` — keep that guard. Note obstacle
  *spawning* from terrain chunks no longer exists (see "Dead / disabled code");
  `obstacle.tscn`/`obstacle.gd` are unreferenced scene files kept for a future
  re-implementation, not currently reachable from any code path.
- `player.gd` holds `speed_manager` as a bare `RefCounted` instead of typed
  `SpeedManager`. The real circular reference is Player↔TerrainGenerator (each
  types/references the other) — `speed_manager.gd` itself references neither.
  Untested whether typing `speed_manager` directly would actually break; treat
  as unconfirmed.

## Player physics (`scripts/player/player.gd`)

Grounded and airborne are two different velocity models — source of most feel
bugs. Grounded (`is_on_floor() and velocity.y >= 0`): `velocity =
get_slope_tangent() * current_speed` — constant speed **along the surface**,
so progress slows on steep terrain. Airborne: `velocity.x = current_speed`,
`velocity.y += GRAVITY * delta`. Coyote time / jump buffer both 0.12s; jump =
built-in `ui_accept`.

- `get_slope_tangent()` (what drives grounded velocity) samples
  `TerrainGenerator.get_collision_chord_slope_angle`, **not**
  `get_slope_angle_at_x`. The latter is a +/-2px analytic finite difference on
  the continuous height field; the actual collision surface is a ~16px polyline
  chord, and the two can disagree by a couple of degrees on curved terrain
  (measured up to 2.19° on seed 941462462) — aiming velocity along the analytic
  angle while resting on the chord injected spurious vertical velocity every
  chord, a likely source of "jittery" feel distinct from the freeze bugs.
  `get_collision_chord_slope_angle` reuses `get_chunk_surface_sample_world_xs`
  (the same sample points `build_chunk_surface` feeds into
  `ConcavePolygonShape2D`), so the aim direction and the physical surface can't
  disagree. Visual rotation (below) still uses the smoother analytic
  `get_slope_angle_at_x` — that's cosmetic, not physics, so the extra fidelity
  is fine there.
- **Do not damp the movement direction over time.** Tried and measured
  (2026-07-29): applying the same `1 - exp(-k*delta)` + `lerp_angle` smoothing
  that the sprite uses to `get_slope_tangent()`'s angle makes contact *worse*,
  because on a piecewise-linear floor the correct heading **is** the current
  chord's heading — lagging it aims the body into the floor on concave
  stretches and off it on convex ones. A/B over 9000 frames of seed 941462462:
  mean surface-gap wobble 0.210px → 0.270px, vertical-velocity reversals
  4.09% → 7.43% of grounded frames, ~20% more time airborne. Reverted; the
  reasoning is restated at the `get_slope_tangent()` call site so it isn't
  re-attempted.
- Visual tilt lives on the child `ColorRect`, never the body: exp weight
  `1 - exp(-k*delta)`, clamped to the terrain angle's side of upright so a
  fast reversal can't overshoot; freezes mid-air. Don't swap in a plain lerp.
  **Known smell, not yet fixed:** that clamp silently defeats the smoothing
  whenever the terrain angle is *decreasing* on a descent — measured pinned to
  the raw angle 96.9% of frames through the back half of a `mega_drop` vs 0%
  through the front half. Measured rotation step size is the same either way
  (mean ~0.25°/frame both halves), so it is not a jitter source; it just means
  the sprite tracks the raw analytic angle there instead of a smoothed one.

## FIXED: `is_on_floor()` flicker on shallow slopes (2026-07-29, `player.gd`)

Was previously logged here as an open bug. Measured (headless, 6 seeds × 20,000
frames, no player input) via a per-segment-label `is_on_floor()` flip-rate probe
(`scripts/debug/floor_flicker_probe.gd`, kept as the permanent regression gate):

| segment | floor-flip rate before fix |
|---|---|
| `gentle_uphill` | **~60-65%** of frames |
| `medium_hill` / `medium_valley` / `small_hill` | ~10-12% |
| `flat` / `sustained_downhill` / `mega_drop` | <0.5% |

**Root cause**: not steepness, but slope *sign*. Uphill frames flipped at ~35%,
downhill ~1%, flat ~2%, across every tested seed — `gentle_uphill` (100% uphill)
tops the table only because it's the purest case. On a rising slope the grounded
velocity model (`velocity = slope_tangent * speed`, `player.gd`) aims the body's
velocity **up** (`velocity.y < 0`). Two things follow from that one sign:
1. The move is tangential to the surface, so `move_and_slide()` finds no contact at
   all that tick (`slide_collision_count == 0`), and `is_on_floor()` goes false.
2. Godot's own floor snapping — the mechanism that exists to catch exactly this —
   is suppressed whenever velocity faces `up_direction` (`CharacterBody2D`'s
   internal `_snap_on_floor` early-returns on `vel_dir_facing_up`). So nothing
   re-seats the body.
The next tick ran the airborne gravity model, fell the sub-pixel gap back onto the
surface, collided, and the cycle repeated at ~2-frame period. The body's actual
position barely moved (surface gap held around -0.1 to -0.6px) — this was never a
real bounce, it was Godot's internal floor bookkeeping flapping while the capsule
sat still.

**Fix, both parts required together**:
- **`is_jump_ascending` flag** replaces the old grounded-model gate
  `is_on_floor() and velocity.y >= 0.0`. That expression was trying to let a jump
  escape the grounded model, but `velocity.y < 0` is *also* true for an uphill
  surface tangent, so every rising frame was misread as "jumping" and silently
  ran the gravity model instead of following the slope. `is_jump_ascending` is set
  true only on the actual jump impulse and cleared at the apex (`velocity.y >= 0`),
  so the grounded model now correctly stays active while climbing a hill. Measured
  before this changed: 76-78% of genuinely-grounded `gentle_uphill` frames were
  running the gravity model, not the slope-tangent model.
- **Forced `apply_floor_snap()`** in `apply_grounded_floor_snap()`, called after
  `move_and_slide()`, conditioned on `is_using_grounded_model and not is_on_floor()
  and velocity.y < 0.0` — i.e. exactly the case Godot's own snap suppresses.
  `apply_floor_snap()` has no `vel_dir_facing_up` gate, so it closes the sub-pixel
  gap `_snap_on_floor` declined to. Scoped narrowly on purpose: when velocity faces
  down, Godot's stock snapping already runs (over the same `FLOOR_SNAP_LENGTH`), so
  this cannot cancel airtime the engine would otherwise grant off a crest or
  `mega_drop`.

**Verified**: uphill flip rate 0.34-0.36 → **0.0000** on all 6 regression seeds
(no-input) and confirmed non-regressed under scripted jump input (`--jump=N` on the
probe); `terrain_invariant_check` PASS on 8 seeds; `freeze_search` 0 stalls on all 3
known-bad seeds; 60,000-frame replay `status=no_freeze`, 0 stall recoveries. Largest
forced snap displacement measured was 1.5px (against an 18px `FLOOR_SNAP_LENGTH`),
consistent with closing a sub-pixel gap rather than yanking the body onto the
ground. Landing after a real jump still shows one legitimate multi-pixel snap frame
(closing real fall distance) — that's expected and distinct from the flicker's
sub-pixel case.

**Not fully fixed — residual sub-pixel bounce, playtest-confirmed 2026-07-29**:
`is_on_floor()` is now always `true` on the ground (the flip-rate metric above is
genuinely 0), but watching closely in-game the capsule still visibly bobs — it
doesn't stay flush with the surface every frame, occasionally lifting a hair before
the next snap pulls it back down. This matches what the probe's `gap_wobble` /
`mean_gap` fields already showed increasing on `medium_hill`/`medium_valley`/
`small_hill` post-fix (e.g. `small_hill` gap_wobble 0.29px→0.38-0.42px) — the fix
traded away the false floor-loss for a smaller, real, sub-pixel one, and that
residual is visible on screen even though every regression gate here (which checks
`is_on_floor()` correctness and stall/freeze safety, not sub-pixel visual smoothness)
passes clean. **Do not treat this CLAUDE.md entry's PASS results as "no jitter
remains"** — they only certify the flicker/stall mechanism this section documents,
not the smoothness of the ride. Chase this only if revisited; not blocking.

**Deferred by agreement, not forgotten**: the shakiness/jitter on the long ~40.5°
`mega_drop` slope is a **separate, still-open** issue — this fix barely touches it
(mechanism measured near-absent there: flip rate 0.002-0.004, `gravity_while_grounded`
<0.002, because `mega_drop` velocity always points down, never up). Do not assume
this fix addresses it without separately re-measuring.

**Explicitly NOT explained by this fix** (do not assume they're the same bug without
re-measuring): a separately-reported "the view snaps forward/backward for half a
second" during play. `debug_stall_recovery_count`/`debug_stuck_event_count` stayed at
**0 across every seed tested here**, so the stall/stuck watchdog's teleport-recovery
(which *would* look like a half-second snap) never fired — that bug may need
different input/conditions to reproduce, or is unrelated to floor detection entirely.

**Already tried and reverted, do not retry** (see `get_slope_tangent()`'s comment):
smoothing the movement-direction angle over time makes contact measurably worse, not
better (0.210px→0.270px mean surface-gap wobble, 4.09%→7.43% velocity-reversal rate).
That result is why this fix targeted the floor-detection/snap mechanism directly
instead of damping the symptom.
- Collider is `CapsuleShape2D` (r16,h48), `safe_margin = 1.0` — both were the
  fix for a snag/freeze bug on segment seams (`f2f075b`). Don't revert to a
  rectangle or drop the margin.
- Camera (`scripts/main.gd`) tracks x exactly, y **downward only**
  (`max(camera_baseline_y, player.y - 72)`), same exp smoothing.

## Conventions & performance-sensitive areas

- Static typing on everything, incl. loop vars and typed dicts/arrays. Never
  `:=`. Explicit return type always. Tunables are `const`, not `@export`,
  unless a human needs to sweep them in the Inspector. `push_error(...)` +
  `set_physics_process(false)` is the house pattern for a missing node.
  Systems stay one-file-per-concern under `scripts/systems/`.
- `build_chunk_surface` does ~64 `get_terrain_height` calls per spawn.
  `is_mega_drop_segment` used to be the frame-time spike here (4 recursive
  lookups, each itself recursing 3 segments back) — it's now an O(1) selection
  check since `mega_drop` collapsed to a single segment (see "Terrain feature
  history"). Don't raise `height_sample_count` or lower
  `MAX_COLLISION_SEGMENT_LENGTH` casually regardless. `add_unique_sample_world_x`
  is O(n²), fine at n≈35 only. Segment caches (`segment_start_x_cache`,
  `segment_length_cache`, `segment_baseline_cache`, `segment_spec_cache`) grow
  all session, never trimmed — fine for a few-minute run.

## Dead / disabled code — check before "fixing"

- Obstacle spawning is **gone, not just disabled**: `spawn_chunk_obstacle`,
  `is_world_x_in_mega_drop`, `is_chunk_overlapping_mega_drop`, and their
  constants (`MIN_SAFE_START_DISTANCE`, `MIN_OBSTACLE_GAP`,
  `OBSTACLE_EDGE_PADDING`, `OBSTACLE_SURFACE_Y_OFFSET`) were deleted from
  `terrain_generator.gd` rather than left commented out — they were unreachable
  dead code and included a latent bug (`maxi(float, float)` on the padding
  calc). `scenes/obstacles/obstacle.tscn` / `scripts/obstacles/obstacle.gd`
  still exist but are unreferenced by anything; a re-implementation starts from
  scratch against the current `TerrainGenerator` API, not from the deleted
  functions. (Separately: the hand-placed `Obstacle` node that used to sit at
  `(68,56)` in `main.tscn` was deleted earlier — jumping at t=0 landed the
  capsule inside it at t≈0.10s, killing the run and making every manual
  playtest and the harness's `tree_paused` result ambiguous.)
- Background parallax is **horizontal only** (`motion_scale = (0.3, 0)`). Vertical
  parallax is deliberately off: it made the layer jump ~0.3× the camera's Y move,
  so each world rebase (~every 26s) snapped the background, and the layer's
  `y ∈ [-1024,1024]` coverage vanished after a few mega drops. With `motion_scale.y
  = 0` the layer is screen-locked vertically and both symptoms are gone. Restoring
  vertical parallax means tiling `background_generator.gd` stripes on a 2D grid.
- Leave alone unless asked: `project.godot`, `.godot/`, `*.uid` files (must
  move with their script), `icon.svg`.

## Build order / status

1. Core loop (terrain + movement) — **working**, still being tuned
2. Speed scaling — **working** (300→500 px/s, `ACCELERATION = 3.2`, ~62s to cap)
3. Visual polish — placeholder rects only
4. Missions/upgrades — not started (`mission_manager.gd`/`upgrade_manager.gd` don't exist)
