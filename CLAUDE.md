# Aura — endless 2D skater (Godot 4.7, GDScript, Mobile renderer)

Alto's-Adventure-style endless downhill skater: player auto-runs right at a
speed that ramps over time, riding an infinite, seeded, procedurally generated
terrain. All on-screen art is placeholder `ColorRect`/`Polygon2D`.

**Priority order:** terrain stability > physics/collision correctness > game
feel. Missions, upgrades, and visual polish are deprioritized until the core
loop is stable (see Build order at the bottom).

## How to use this documentation

- **Read this file first, every session.** It's the fast-read handbook:
  architecture, invariants, conventions, current state, and known issues.
- **`docs/research/` is an archive, not required reading.** Each file is a
  detailed investigation log — root cause analysis, measurements, ruled-out
  approaches, full timelines. Open one only when the current task is directly
  related to that investigation, or when a section below explicitly points to
  it. Do not read them by default.
- **When you complete a new investigation**, add only a brief summary and
  conclusion here (what's true now, what to avoid, one pointer) and put the
  detailed history, measurements, and experiment log in the appropriate
  `docs/research/*.md` file — create a new one if none fits.

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

Four headless gates exist: a fast physics-free terrain-shape check, a
freeze-replay runner, a freeze-search sweep (the one that actually finds
stalls — replay alone isn't sufficient), and a floor-flicker regression
probe. Run the terrain-shape check after any segment/shape change; run the
physics ones after any change to player physics, collision, or segment
code. **Exact commands, flags, and watchdog mechanics**:
`docs/development/debugging.md`. Rationale/history for why each exists:
`docs/research/freeze_bug.md`. Log any new seed that triggers
`FREEZE_REPRO` in `docs/research/freeze_bug.md` before fixing it.

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
to `/root/Main/Player` if `player_path` unset. `TerrainGenerator._ready()`
reads `player.floor_max_angle` into `session_floor_max_angle`; `Player` never
sets it explicitly, so this read isn't order-sensitive today — but sibling
order **has** been load-bearing before (see `docs/research/freeze_bug.md`),
so check this before assuming a new `_ready()`-time `player.*` read is safe.

## Terrain pipeline (`scripts/terrain/terrain_generator.gd`)

Two independent grids: **chunks** (fixed 512px — spawn/despawn + render unit)
and **segments** (variable length — the shape unit), deliberately unaligned.
Read `get_terrain_height`/`get_segment_selection`/`build_chunk_surface` for
the actual algorithm — these are the gotchas that aren't obvious from a read:

- Whole run is reproducible from one integer (`session_seed`); every segment
  is a pure hash function of `(seed, index)`, no RNG state. A segment's
  shape/length/magnitude/tier/label are all derived from one cached spec
  (`build_segment_spec`) — implementation details in `docs/development/terrain.md`.
- Baselines are cumulative and **drift downward without bound** (`+Y` down);
  there's no rebound.
- **Always call `ensure_segment_cache_for_world_x(x)` before
  `find_segment_index_at_x(x)`** — otherwise the cache's binary search
  silently clamps and returns the wrong segment.
- `large_valley` (a segment type) was removed entirely and `mega_drop` was
  collapsed from 4 segments to 1 — permanent decisions; rationale and the
  bugs that drove them in `docs/research/freeze_bug.md`.
- Fill-polygon depth math, the `debug_weight_*` bisection dial, and
  performance notes: `docs/development/terrain.md`.

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
  *not* `@export`ed: while it was, `main.tscn` serialised it to `false` and
  silently reintroduced the freeze for weeks after it had been fixed and
  verified. Don't re-export it, don't set it from a scene. Mechanism and
  measured details: `docs/research/freeze_bug.md`.
- `get_terrain_height` must stay **pure** in `(session_seed, world_x)` — chunk
  visuals, collision, player tilt, and the debug HUD all sample it separately.
- Segment length/baseline/height-curve agreement is structural (see "Terrain
  pipeline"), but player spawn `(64,136)` = `ground_y(192) +
  surface_y_offset(-32) − capsule half-height(24)` is still a manual
  invariant — changing either without updating `Player` position in
  `main.tscn` drops or embeds the player at t=0.
- Player/terrain/obstacles share collision layer/mask **1**; `obstacle.gd`
  filters via `body.is_in_group("player")` — keep that guard even though
  obstacle *spawning* no longer exists (see "Dead / disabled code").
- `player.gd` holds `speed_manager` as a bare `RefCounted`, not typed
  `SpeedManager` — untested whether typing it directly would break anything
  (the real circular reference is Player↔TerrainGenerator, not this).

## Player physics (`scripts/player/player.gd`)

Grounded and airborne are two different velocity models — source of most feel
bugs. Grounded (`is_on_floor() and not is_jump_ascending`): `velocity =
get_slope_tangent() * current_speed` — constant speed **along the surface**,
so progress slows on steep terrain. Airborne: `velocity.x = current_speed`,
`velocity.y += GRAVITY * delta`. Coyote time / jump buffer both 0.12s; jump =
built-in `ui_accept`.

- `get_slope_tangent()` (grounded velocity) samples
  `TerrainGenerator.get_collision_chord_slope_angle` — the actual ~16px
  collision chord, not the continuous height field's analytic tangent, which
  can disagree by a couple of degrees on curved terrain and inject spurious
  vertical velocity if used instead. Visual rotation still uses the smoother
  analytic `get_slope_angle_at_x`, which is fine since it's cosmetic only.
- **Do not damp the movement direction over time** — i.e. don't smooth
  `get_slope_tangent()`'s angle the way the sprite's tilt is smoothed. Tried
  and measured: makes contact worse. Details: `docs/research/terrain_jitter.md`.
- Visual tilt lives on the child `ColorRect`, never the body: exp weight
  `1 - exp(-k*delta)`, clamped to the terrain angle's side of upright so a
  fast reversal can't overshoot; freezes mid-air. Don't swap in a plain lerp.
- Collider is `CapsuleShape2D` (r16,h48), `safe_margin = 1.0` — both were the
  fix for a snag/freeze bug on segment seams (`f2f075b`). Don't revert to a
  rectangle or drop the margin.
- Camera (`scripts/main.gd`) tracks x exactly, y **downward only**
  (`max(camera_baseline_y, player.y - 72)`), same exp smoothing.

## Known issues

- **`is_on_floor()` flicker on rising terrain — FIXED** (2026-07-29). Root
  cause, fix, and verification: `docs/research/floor_flicker.md`.
- **Residual sub-pixel bounce on curved terrain — open, deferred.** Inherent
  to `CharacterBody2D`'s per-frame solver correction on curved terrain, not
  fixable at the input/movement level. Several mitigations tried and
  rejected, most recently a 2026-07-31 visual filter that measurably reduced
  it but was reverted as imperceptible in actual play. Revisit only for a
  real gameplay complaint, and get independent confirmation it's actually
  visible first — read `docs/research/terrain_jitter.md` before touching
  this again (`jitter_frequency_probe.gd` is the tool to reach for).
- **`mega_drop` shakiness — separate, still open.** Not addressed by the
  flicker fix (mechanism measured near-absent there). Not otherwise
  investigated yet.
- **"View snaps forward/backward for half a second" — unreproduced.**
  Reported once; not explained by any fix so far (stall/stuck watchdog
  counts stayed 0 in every measurement run to date). May need different
  repro conditions.

## Conventions & performance-sensitive areas

- Static typing on everything, incl. loop vars and typed dicts/arrays. Never
  `:=`. Explicit return type always. Tunables are `const`, not `@export`,
  unless a human needs to sweep them in the Inspector. `push_error(...)` +
  `set_physics_process(false)` is the house pattern for a missing node.
  Systems stay one-file-per-concern under `scripts/systems/`.
- `build_chunk_surface` does ~64 `get_terrain_height` calls per spawn — don't
  raise `height_sample_count` or lower `MAX_COLLISION_SEGMENT_LENGTH`
  casually. Full performance notes and cache-growth details:
  `docs/development/terrain.md`.

## Dead / disabled code — check before "fixing"

Obstacle spawning (terrain-driven) and vertical background parallax were both
tried and removed entirely, not left disabled — don't resurrect either from
old code, and don't touch `project.godot`/`.godot/`/`*.uid`/`icon.svg` unless
asked. Full removal history and why: `docs/development/dead_code.md`.

## Build order / status

1. Core loop (terrain + movement) — **working**, still being tuned
2. Speed scaling — **working** (300→500 px/s, `ACCELERATION = 3.2`, ~62s to cap)
3. Visual polish — placeholder rects only
4. Missions/upgrades — not started (`mission_manager.gd`/`upgrade_manager.gd` don't exist)
