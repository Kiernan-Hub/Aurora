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
to `/root/Main/Player` if `player_path` unset. **Sibling order is
load-bearing:** `Player` must stay above `TerrainGenerator` so `Player._ready()`
sets `floor_snap_length = 18.0` before `TerrainGenerator._ready()` caches it
as `session_floor_snap_length` — reorder them and the generator reads Godot's
default `1.0`, changing valley geometry.

## Terrain pipeline (`scripts/terrain/terrain_generator.gd`)

Two independent grids: **chunks** (fixed 512px — spawn/despawn + render unit)
and **segments** (variable length — the shape unit), deliberately unaligned.
Read `get_terrain_height`/`get_segment_selection`/`build_chunk_surface` for
the actual algorithm — these are the gotchas that aren't obvious from a read:

- Whole run is reproducible from one integer (`session_seed`); every segment
  is a pure hash function of `(seed, index)`, no RNG state.
- `is_mega_drop_start_segment` recurses back up to 3 segments — the hottest,
  trickiest predicate in the file.
- Baselines are cumulative and **drift downward without bound** (`+Y` down);
  there's no rebound.
- **Always call `ensure_segment_cache_for_world_x(x)` before
  `find_segment_index_at_x(x)`** — otherwise the cache's binary search
  silently clamps and returns the wrong segment.
- Fill polygon closes at `max(surface_y) + 4096`, recomputed per chunk —
  never hardcode this depth, baselines drift thousands of px down over a run.

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
- Segment length, baseline delta, and the height curve must agree, or chunk
  seams get vertical steps. Player spawn `(64,136)` = `ground_y(192) +
  surface_y_offset(-32) − capsule half-height(24)` — changing either without
  updating `Player` position in `main.tscn` drops or embeds the player at t=0.
- Player/terrain/obstacles share collision layer/mask **1**; `obstacle.gd`
  filters via `body.is_in_group("player")` — keep that guard.
- `Player.FLOOR_SNAP_LENGTH`, `GRAVITY`, `SpeedManager.INITIAL_SPEED`, and the
  tick rate feed `get_large_valley_drop_length()`, clamping the valley ramp so
  floor snap keeps contact. Currently `min(48,70.5)`→48, i.e. clamp inactive —
  lowering speed or raising snap length makes it bind. `player.gd` holds
  `speed_manager` as a bare `RefCounted` instead of typed `SpeedManager`. The
  real circular reference is Player↔TerrainGenerator (each types/references the
  other) — `speed_manager.gd` itself references neither. Untested whether typing
  `speed_manager` directly would actually break; treat as unconfirmed.

## Player physics (`scripts/player/player.gd`)

Grounded and airborne are two different velocity models — source of most feel
bugs. Grounded (`is_on_floor() and velocity.y >= 0`): `velocity =
get_slope_tangent() * current_speed` — constant speed **along the surface**,
so progress slows on steep terrain. Airborne: `velocity.x = current_speed`,
`velocity.y += GRAVITY * delta`. Coyote time / jump buffer both 0.12s; jump =
built-in `ui_accept`.

- Visual tilt lives on the child `ColorRect`, never the body: exp weight
  `1 - exp(-k*delta)`, clamped to the terrain angle's side of upright so a
  fast reversal can't overshoot; freezes mid-air. Don't swap in a plain lerp.
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
- `build_chunk_surface` does ~64 `get_terrain_height` calls per spawn, each
  walking `is_mega_drop_segment` (4 recursive lookups) — the frame-time spike
  in the project. Don't raise `height_sample_count` or lower
  `MAX_COLLISION_SEGMENT_LENGTH` casually. `add_unique_sample_world_x` is
  O(n²), fine at n≈35 only. Segment caches grow all session, never trimmed —
  fine for a few-minute run.

## Dead / disabled code — check before "fixing"

- Obstacle spawning is **off**: `spawn_chunk_obstacle(...)` commented out at
  `terrain_generator.gd:149`. Has a latent bug —
  `maxi(half_chunk_width - OBSTACLE_EDGE_PADDING, 0.0)` passes floats to an
  int function. Fix when re-enabling. (The hand-placed `Obstacle` node that used to
  sit at `(68,56)` in `main.tscn` has been deleted — jumping at t=0 landed the
  capsule inside it at t≈0.10s, killing the run and making every manual playtest
  and the harness's `tree_paused` result ambiguous.)
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
