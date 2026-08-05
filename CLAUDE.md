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
| `docs/review/*.md` | Point-in-time external audits. Read the newest before a cleanup pass — it's the running list of known-but-unfixed debt |
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

**Six headless gates:** terrain-shape check (fast, physics-free), freeze-replay,
freeze-search (the one that actually finds stalls — replay alone isn't sufficient),
floor-flicker, camera-shake, chasm. Run the terrain check after any segment/shape change,
the physics ones after any player/collision/segment change, camera-shake after any change
to the camera follow in `main.gd`, and chasm after anything touching voids, fall death or
the boost velocity model. Commands, flags and watchdog mechanics:
`docs/development/debugging.md`. Log any new seed that trips `FREEZE_REPRO` in
`docs/research/freeze_bug.md` before fixing it.

**Only those six are maintained.** The other 18 files in `scripts/debug/` are archived
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
├── SfxPlayer         6-voice AudioStreamPlayer pool on the SFX bus
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
- **Any long-running harness needs `debug_chasm_disabled = true`**, next to the two
  `debug_spawning_disabled` flags — otherwise the run hits a chasm, dies, and reports a
  confident wrong number. `freeze_search` takes `--chasms=1` to opt back in for that reason.
  `camera_shake_probe` also accepts `--chasms=1`, but it drives no input, so it just dies at
  the first void too — only meaningful there with `--frames` short enough to stop first.
- **A chasm is flat, and must stay flat** — zero added slope, steepest terrain still 20.13°.
  That is why a void was safe to build when a steep drop face was not: anything ≥
  `floor_max_angle` is a wall and wedges the player (`large_valley`, three weeks).
  `terrain_invariant_check` asserts the flatness *and*, via `CHASM_NOT_CLEARABLE`, that any
  future width/`exit_drop` is jumpable.
- **Every `Area2D` has terrain chunks entering it.** Player, chunks and obstacles are on
  layer 1; coins and powerups on layer 2; everything masks layer 1. `obstacle.gd`,
  `coin.gd` and `powerup.gd` each filter with `body.is_in_group("player")` — drop that
  guard and the first chunk to overlap a coin collects it, or kills you.
- **The jump upgrade curve may not exceed ×1.0224.** `CHASM_LEAD_IN_LENGTH` (900) bounds
  max-upgrade × the √2 powerup; above that a boosted jump taken at the first pixel of a
  chasm run-up lands *inside* the void. The curve ends at ×1.00 so every existing
  jump-reach constant stays valid. `check_upgrade_curve()` fails the build if it's raised.
- **The autoload *node* exists under `--headless --script`** even though the global
  `Services` identifier doesn't, so `resolve()` succeeds in every probe.
  `GameManager.apply_upgrades()` must therefore skip headless, or the gates measure
  whatever jump level is in *your* `save.dat` (measured: chasm_probe 48/48 → 8 failures).
  It checks `DisplayServer` directly, **not** `services.is_headless` — that isn't assigned
  yet when `GameManager._ready()` runs, the same ordering trap the audio path has.

## Known issues

- **A speed boost taken into an obstacle cluster was unavoidable death — FIXED**
  (2026-08-04). `ObstacleSpawner`'s cluster trigger (`obstacle_spawner.gd`) now withholds
  a cluster spawn while `player.is_boosting`, without touching the boost's grounded-model
  behavior (load-bearing for chasms). The wait ends the instant the boost does, and
  `spawn_cluster` always places obstacles a fixed lookahead ahead of the player's current
  position, so a cluster spawned right as a boost ends still gets full reaction time.
- **Residual sub-pixel bounce on curved terrain — open, deferred.** Inherent to
  `CharacterBody2D`'s solver correction, not fixable at the input/movement level; several
  mitigations measured and rejected. Its *horizontal* component was the entire `mega_drop`
  shake once a rigid camera piped it to screen — still there, just no longer wired to the
  view. Revisit only for a real complaint, and confirm it's visible first.
  `docs/research/terrain_jitter.md`; `jitter_frequency_probe.gd` is the tool.
- **`mega_drop` shakiness — SEGMENT CUT, not fixed** (2026-08-01).
  `MEGA_DROP_SELECTION_WEIGHT = 0`. Six mechanisms measured; the three that improved the
  numbers produced **zero** perceptual improvement. Cutting it took worst-case camera jerk
  0.382 → 0.033 px/frame². Hills/valleys still measure above flat. **Read
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

1. Core loop (terrain + movement) — **working**. Includes **chasms**: a rare 160/220/280px
   void every ~35–85s, jumped or fatal. Width is a table gated on the speed ramp — the wide
   variant is illegal early because 0.55×reach forbids it there, not for taste. `exit_drop`
   is still 0; a non-zero one is phase 3 and needs the boost-glide fix first (`terrain.md`)
2. Speed scaling — **working**. Two-phase ramp: 100→500 px/s over 10s, then 500→750 over
   the next 110s, capping at `MAX_SPEED` (750) at t=120s
3. Coins + score — **working**. `SaveStore` (v2) persists a versioned best score, plus a
   **coin wallet** every run banks into on death and per-upgrade levels
4. Obstacles + death — **working**. Singles from t=20s, then every 12–30s
5. Powerups — **working**. Speed boost (1000 px/s, 3s, 2× coins) and jump boost (×√2,
   3s). **One** ~30s-average schedule decides *when*; `PowerupSpawner.POWERUP_TABLE`
   (effect/scene/weight) decides *which*, so a new kind is one table row and does not
   change pickup density. `PowerupManager` holds effects in one `active_effects` dict
   with duration/label/coin-multiplier tables beside it
6. Screens — **working**. START/PLAYING/PAUSED/DEAD/SHOP
7. **Audio — working (SFX only).** `M111/stopaster → Music, SFX`; `SfxPlayer` plays
   jump/coin/powerup/death from a 6-voice pool (placeholder WAVs, `assets/audio/sfx/`).
   Sliders drive their bus, persisting on **drag end**. **No music track yet.** Audio must
   stay behind a locally-computed `is_headless` — `Services` isn't ready in harness `_init()`
8. Visual polish — placeholder rects only
9. **Upgrades — vertical slice working** (2026-08-04). One track: jump, five levels
   ×0.60→×1.00, bought from a SHOP screen off either the death screen or the START
   screen's Upgrades button, with banked coins. `GameManager.shop_return_state` tracks
   which one opened it so closing the shop returns there instead of always DEAD.
   The player now starts **deliberately weak** and buys their way back to baseline.
   Missions, zones and milestone unlocks are still not started; `UpgradeStore` and
   `State.SHOP` are the seams they attach to (`upgrade_store.gd` header)

The player's debug instrumentation now derives from `OS.is_debug_build()`, so it runs
under the editor and every probe and is off in a release export — it can't be shipped by
forgetting a flag. Details in `physics.md`.

**Still unset: the base viewport size.** `project.godot` declares no
`window/size/viewport_width`/`height`, so the base resolution is the engine default
(1152×648) and `stretch/aspect="expand"` lets the visible world width vary with device
aspect ratio. On an auto-runner, forward visibility *is* reaction time, so that's a
difficulty difference between phones, not a cosmetic one. Needs a deliberate decision —
see `docs/review/2026-08-03-architecture-audit.md` §B4.

---

**Keep this file under ~175 lines.** Only the most important things belong here: the
general direction of the project, and the traps that cost real time when someone doesn't
know them. Add something only if it's genuinely necessary at this level — otherwise it
goes in `docs/development/` (how something works) or `docs/research/` (what an
investigation found).

one thing i want to say (im the user, so this is important) if something has a lot of potenital to make more bugs or is gonna be exceeslsivey hard when theres another option, then jhsut flag it and let me know. i am prioritixzing this to be clean code. if a big drop is too much terrain changing, then we just add a chasm instead, for exmaple