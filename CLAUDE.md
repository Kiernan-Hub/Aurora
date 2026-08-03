# Aura — endless 2D skater (Godot 4.7, GDScript, Mobile renderer)

Alto's-Adventure-style endless downhill skater: the player auto-runs right at a speed
that ramps over time, riding an infinite, seeded, procedurally generated terrain. All
on-screen art is placeholder `ColorRect`/`Polygon2D`.

**Priority order:** terrain stability > physics/collision correctness > game feel.
Missions, upgrades and visual polish stay deprioritized until the core loop is stable.

## Where things are documented

This file is the map. Everything else is one level down, read on demand.

| Doc | Open it when |
|---|---|
| `docs/development/architecture.md` | Touching scene wiring, `GameManager`, `Services`, persistence, or adding a system |
| `docs/development/terrain.md` | Working inside the generator, chunk lifecycle, or segment shapes |
| `docs/development/physics.md` | Changing player movement, collision, stall watchdogs, or the camera |
| `docs/development/input.md` | Any input change — desktop *or* touch |
| `docs/development/debugging.md` | Running a gate, or reviving an archived probe |
| `docs/development/dead_code.md` | Something looks reachable but isn't |
| `docs/research/*.md` | Archive of closed investigations. **Not required reading** — open one only when a section here points you at it |

**Finishing an investigation?** Put the conclusion here (what's true now, what to
avoid, one pointer) and the full log — measurements, ruled-out approaches, timeline —
in `docs/research/`.

## AI editing rules

Inspect connected files and find the root cause before changing anything. Prefer
targeted changes; preserve existing architecture unless you have a clear reason not to,
and then propose and explain first.

`project.godot`: features `4.7` + `Mobile`, physics **60 Hz**, interpolation **OFF**.
Some terrain constants derive from `1.0/physics_ticks_per_second` — changing the tick
rate silently changes level geometry.

## Run / debug / test

No test suite, no build script. Godot lives at
`/Applications/Godot.app/Contents/MacOS/Godot` (play with `--path .`; it opens a window
and blocks, so only when asked).

**Five headless gates:** terrain-shape check (fast, physics-free), freeze-replay,
freeze-search (the one that actually finds stalls — replay alone isn't sufficient),
floor-flicker, camera-shake. Run the terrain check after any segment/shape change, the
physics ones after any player/collision/segment change, and camera-shake after any
change to the camera follow in `main.gd`. Commands, flags and watchdog mechanics:
`docs/development/debugging.md`. Log any new seed that trips `FREEZE_REPRO` in
`docs/research/freeze_bug.md` before fixing it.

**Only those five are maintained.** The other 18 files in `scripts/debug/` are archived
one-offs, and most predate the start screen — they measure a *paused* game and print
confident, meaningless numbers rather than failing. Never trust one without reviving it
first.

## Scene graph (`scenes/main.tscn`)

```
Main (Node2D, scripts/main.gd)
├── ParallaxBackground/ParallaxLayer  motion_scale (0.3,0) ← background_generator.gd
├── Player            position (64,136), safe_margin 1.0  ← player.tscn
├── TerrainGenerator  player_path = ../Player
│   ├── CoinSpawner       per-chunk coin slots
│   ├── ObstacleSpawner   timed clusters; a hit calls Player.die()
│   └── PowerupSpawner    timed speed/jump pickups
├── Camera2D          position (0,136)
├── GameManager       State { START, PLAYING, PAUSED, DEAD }
├── PowerupManager    boost timers; drives Player.start_boost etc.
└── CanvasLayer       StartScreen / PauseScreen / DeathScreen (all process_mode=ALWAYS),
					  PauseButton, Timer/Coin/Powerup labels
```

Wiring is by sibling path. There is **exactly one autoload** — `Services`
(`class_name GameServices`) — and new globals need a real justification. **Never write
`Services.x` in gameplay code**; use `GameServices.resolve(self)` and null-guard it, or
you break every headless probe. `GameManager.set_state()` is the **only** place allowed
to touch `get_tree().paused` or a screen's visibility. Reasoning for all of it:
`architecture.md`.

## Things that break silently

- **World rebasing must stay on.** `Main.world_rebase_enabled` is intentionally *not*
  `@export`ed: while it was, `main.tscn` serialised it to `false` and silently
  reintroduced the freeze for weeks after it had been fixed and verified. Don't
  re-export it, don't set it from a scene. (`docs/research/freeze_bug.md`)
- **Spawners under `TerrainGenerator` must not read `session_seed` in `_ready()`.**
  Godot readies children before parents, so the seed is still 0 there. Initialise
  seed-derived state on the first `_physics_process`. This shipped as a real bug —
  every session got an identical powerup schedule. (`architecture.md`)
- **`get_terrain_height` must stay pure** in `(session_seed, world_x)`. Chunk visuals,
  collision, player tilt and the debug HUD all sample it independently.
- **Always `ensure_segment_cache_for_world_x(x)` before `find_segment_index_at_x(x)`**,
  or the binary search silently clamps and returns the wrong segment.
- **Player spawn `(64,136)` is a manual invariant**: `ground_y(192) +
  surface_y_offset(-32) − capsule half-height(24)`. Change either without updating
  `Player` in `main.tscn` and the player starts embedded in, or dropping toward, the
  terrain.
- **Every `Area2D` has terrain chunks entering it.** Player, chunks and obstacles are on
  layer 1; coins and powerups on layer 2; everything masks layer 1. `obstacle.gd`,
  `coin.gd` and `powerup.gd` each filter with `body.is_in_group("player")` — drop that
  guard and the first chunk to overlap a coin collects it, or kills you.

## Known issues

- **A speed boost taken into an obstacle cluster is unavoidable death — open, needs a
  design decision** (found 2026-08-03 by inspection). Jumping is impossible for the full
  3s of a boost (`player.gd` gates on `not is_boosting`, and `start_boost()` clears the
  coyote/buffer timers), obstacles kill on contact with no i-frames, and the boost covers
  3000px — further than a whole 5-obstacle cluster. The two spawners schedule
  independently, so nothing keeps them apart. Options: i-frames, smash-through, allow
  jumping while boosting, or suppress obstacle placement during a boost.
- **Residual sub-pixel bounce on curved terrain — open, deferred.** Inherent to
  `CharacterBody2D`'s per-frame solver correction, not fixable at the input/movement
  level; several mitigations measured and rejected. Its *horizontal* component was the
  entire `mega_drop` shake once a rigid camera piped it to screen — the noise is still
  there, it's just no longer wired to the view. Revisit only for a real gameplay
  complaint, and confirm it's actually visible first. Read
  `docs/research/terrain_jitter.md`; `jitter_frequency_probe.gd` is the tool.
- **`mega_drop` shakiness — SEGMENT CUT, not fixed** (2026-08-01).
  `MEGA_DROP_SELECTION_WEIGHT = 0`. Six mechanisms were measured; the three that produced
  real measured improvement produced **zero** perceptual improvement in playtest. Cutting
  the segment took worst-case camera jerk 0.382 → 0.033 px/frame². Hills/valleys still
  measure above flat, so the class is reduced, not gone. **Read
  `docs/research/camera_shake.md` before spending any more time here** — it lists what's
  already eliminated and three measurement traps that each cost a cycle.
- **`is_on_floor()` flicker on rising terrain — FIXED** (2026-07-29).
  (`docs/research/floor_flicker.md`)
- **"View snaps forward/backward for half a second" — unreproduced.** Reported once, not
  explained by any fix so far; stall/stuck watchdog counts stayed 0 in every measurement
  run to date. May need different repro conditions.

## Dead / disabled code — check before "fixing"

The old **terrain-driven** obstacle placement inside `terrain_generator.gd` and vertical
background parallax were both removed entirely, not left disabled — don't resurrect
either from old code. This is **not** the same thing as the current `ObstacleSpawner`,
which is live. Don't touch `project.godot` / `.godot/` / `*.uid` / `icon.svg` unless
asked. Full history: `docs/development/dead_code.md`.

## Build order / status

1. Core loop (terrain + movement) — **working**, still being tuned
2. Speed scaling — **working**. Two-phase ramp: 100→500 px/s over 10s, then 500→750 over
   the next 110s, capping at `MAX_SPEED` (750) at t=120s
3. Coins + score — **working**. `SaveStore` persists a versioned best score
4. Obstacles + death — **working**. Clusters from t=20s, then every 50–70s, growing
5. Powerups — **working**. Speed boost (1000 px/s, 3s, 2× coins) and jump boost (×√2,
   3s), independent ~60s-average schedules
6. Screens — **working**. START/PLAYING/PAUSED/DEAD
7. **Audio — not started, and next up.** The pause sliders already persist through
   `SaveStore`, but **nothing consumes those values**: there are no audio buses and no
   `AudioStreamPlayer` anywhere, so both sliders are currently no-ops. Wiring them up is
   part of that work, not a separate bug
8. Visual polish — placeholder rects only
9. Missions/upgrades — not started

Note the player's debug instrumentation (`DEBUG_SHOW_PLAYER_STATE`,
`DEBUG_LOG_FREEZE_REPRO`, `DEBUG_ALLOW_MANUAL_SPEED_CONTROL`) **ships on** — turn it off
before any build someone else will play. Details in `physics.md`.

---

**Keep this file under ~175 lines.** Only the most important things belong here: the
general direction of the project, and the traps that cost real time when someone doesn't
know them. Add something only if it's genuinely necessary at this level — otherwise it
goes in `docs/development/` (how something works) or `docs/research/` (what an
investigation found).
