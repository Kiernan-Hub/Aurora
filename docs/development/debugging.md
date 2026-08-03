# Debugging & regression harnesses

Reference doc for the exact commands and flags used to reproduce/regress physics and
terrain bugs. `CLAUDE.md` says *when* to run these; this file has the *how*. Rationale
and measured history for why each harness exists: `docs/research/freeze_bug.md`.

No test suite, no build script. Godot: `/Applications/Godot.app/Contents/MacOS/Godot`
(play with `--path .`, opens a window and blocks — only when asked).

**No gate covers input.** Every harness below drives `ui_accept` synthetically via
`Input.action_press`, so they exercise the *consumer* of input, never its delivery.
A platform input path can be completely dead with all gates green — that is exactly
how the 2026-08-02 Android bug shipped. Input changes need a real desktop run
(check keyboard *and* mouse-click separately) plus an on-device Android check:
re-export to `./aura.apk`, `adb install -r aura.apk`, tap Start, then tap during
play. If a tap does nothing on device, `adb logcat -s godot` while tapping is the
next step.

## The four headless gates

**Terrain shape** (fast, physics-free) — no Y discontinuity, no slope exceeding
`floor_max_angle`, across N random seeds. Expect `status=PASS`:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/terrain_invariant_check.gd -- --seeds=8 --to=300000
```

**Freeze replay** — steps physics frames from spawn, no input. Prints
`status=no_freeze|freeze_detected|tree_paused|stall_recovered`. **`--frames` must be
large** — every recorded freeze is past frame ~25,000; short runs report `no_freeze`
unconditionally. `--rebase=0` disables world rebasing for A/B work:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/freeze_replay_runner.gd -- --seed=941462462 --frames=60000 --runs=1
```

**Freeze search** — the harness that actually finds stalls (replay alone is not
sufficient); sweeps sub-pixel start phases × input schedules at a target world_x.
Expect `trials with a STALL : 0`:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/freeze_search.gd -- --seed=941462462 --warp=175000 --to=178000 --phases=8 --phasestep=0.25 --scan=1 --trialframes=500 --rebase=1
```

**Floor flicker probe** (`scripts/debug/floor_flicker_probe.gd`) — the permanent
regression gate for the `is_on_floor()` flicker fix; per-segment-label flip-rate,
kept from `docs/research/floor_flicker.md`'s investigation.

## Watchdog mechanics

`Player.recover_from_stall()` re-seats the body on the terrain height field after
`STALL_RECOVERY_FRAME_THRESHOLD` (4 frames, ~67ms) consecutive stalled frames, with
`STALL_RECOVERY_CLEARANCE` (1.0px) of clearance above the surface so it isn't reborn
inside the collision polyline. A passing regression run must show **zero**
`debug_stall_recovery_count` — non-zero means a stall happened and was papered over.

`update_stuck_detection()` is a second, independent watchdog for the same failure
mode: it tracks **net** progress over a `STUCK_WINDOW_FRAME_COUNT` (60 frame, ~1s)
rolling window instead of a single frame, since a jittering stall (small
back-and-forth motion) never strings together enough consecutive near-zero frames to
trip the per-frame one. Both watchdogs recover through the same
`recover_from_stall()` path and print (`STALL_RECOVERY` / `STUCK_DETECTED`) so a
console log always shows the full history even if a screen wasn't watched live.

`is_stalled_this_frame()` (the shared predicate both watchdogs are built on):
grounded, `|velocity.x| >= 1.0`, and `|last_physics_displacement.x| <= 0.01` — shared
so the recovery watchdog and the freeze logger can never disagree about what a stall
is.

## Debug flags & logging toggles

- `Player.DEBUG_SHOW_PLAYER_STATE` — runtime `Label` with live physics/terrain state
  incl. **session seed**; read it to reproduce a bug via `--seed=`.
- `Player.DEBUG_LOG_FREEZE_REPRO` — prints `FREEZE_REPRO` when grounded with
  `|velocity.x| >= 1` but `|motion.x| <= 0.01`, emitting
  `debug_freeze_detected(session_seed)` — what the replay runner watches. Log any
  seed that triggers this in `docs/research/freeze_bug.md` before fixing it.
- `TerrainGenerator.debug_log_segment_selection` / `DEBUG_TERRAIN_LOGGING` /
  `Player.DEBUG_SLOPE_LOGGING` — `const` toggles for per-frame spam.
- `TerrainGenerator.debug_weight_*` — see `docs/development/terrain.md`.
- `GameManager.require_start_screen` (default `true`, not `@export` — same reasoning
  as `Main.world_rebase_enabled`) — real play pauses on a start screen until tapped;
  any harness that instantiates `main.tscn` and steps many physics frames expecting
  the player to actually move must set
  `(main.get_node("GameManager") as GameManager).require_start_screen = false`
  before `add_child(main)`, or the run sits paused and the gate trivially "passes"
  by doing nothing. `freeze_replay_runner.gd`, `freeze_search.gd`,
  `floor_flicker_probe.gd`, and `camera_shake_probe.gd` already do this.
  `terrain_invariant_check.gd` doesn't need it: it awaits exactly one
  `physics_frame` (frame signals fire regardless of pause) and samples the height
  field directly, never depending on player movement.
- `ObstacleSpawner` schedules clusters off live `Player.speed_manager.elapsed_time`
  (not world_x), so any harness that steps many no-input frames will eventually
  reach one. A collision pauses the tree via `GameManager`, which stops
  `Player`/`Main` `_physics_process` mid-run and gets silently misread as whatever
  that harness measures (a stall, a floor-contact anomaly, a camera freeze
  reported as one huge jerk spike followed by a run of near-zero frames). Found
  once already this way in `camera_shake_probe.gd` -- an 8.5 px/frame^2 spike with
  `scroll_rate_x=0.0000` that vanished when the run was truncated to end before
  the first cluster's ~20s trigger.
  **`set_physics_process(false)` does NOT reliably suppress this** -- tried first,
  and confirmed by direct instrumentation to be a no-op: `_physics_process` kept
  firing every frame even while `is_physics_processing()` reported `false` on the
  same node. Every harness "fixed" this way was actually still spawning obstacles;
  the entire investigation above (camera jerk spike, `floor_flicker_probe.gd`
  showing a frozen-looking `distance=11356`, a cross-seed pause cascade freezing
  every seed after the first death in the same process) traced back to this one
  ineffective fix, not a real physics/stall bug -- confirmed by
  `freeze_replay_runner.gd` reaching `world_x=108978.9` at frame 10000 with
  `status=no_freeze` once the real fix was in. Use
  `ObstacleSpawner.debug_spawning_disabled = true` instead (a plain script var
  checked inside `_physics_process()`, the same pattern as
  `Main.world_rebase_enabled` / `Player.DEBUG_LOG_FREEZE_REPRO` /
  `GameManager.require_start_screen`, all of which DO work reliably):
  `(main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner).debug_spawning_disabled = true`
  before `add_child(main)`. `freeze_search.gd`, `freeze_ab_runner.gd`,
  `stall_recovery_probe.gd`, `camera_shake_probe.gd`, `floor_flicker_probe.gd`, and
  `freeze_replay_runner.gd` all do this now.
- `floor_flicker_probe.gd` runs multiple seeds sequentially in one process via
  `run_seed()`. `get_tree().paused` is tree-wide, not scoped to one seed's `main`
  instance -- without an explicit `paused = false` after `main.queue_free()`, a
  seed that ends paused (e.g. from an obstacle death, before the fix above
  existed) leaves every LATER seed in the sequence frozen at spawn for its entire
  run. Fixed by resetting `paused = false` at the end of each `run_seed()` call.
  `freeze_replay_runner.gd` doesn't need it: an obstacle death there reports as
  its own distinct `status=tree_paused`, not misread as a stall.

## Camera shake probe (`scripts/debug/camera_shake_probe.gd`)

Regression gate for the 2026-08-01 camera-judder fix (`main.gd` horizontal
follow). Measures **camera jerk** — the frame-to-frame change in scroll rate —
per segment label. The terrain is static in world space, so the camera's
per-frame displacement *is* the on-screen motion of the whole view; uneven
displacement is perceived shake. Smooth scrolling reads 0; the speed ramp only
accounts for ~0.0009 px/frame², so anything above ~0.001 is judder.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/camera_shake_probe.gd -- --seed=941462462 --frames=7000 --warmup=120
```

- `--smoothness=0` restores the old rigid `camera.x = player.x` follow and
  `--lead=0` disables the lag-cancelling lead term, so before/after A/Bs come
  from one binary and one seed rather than a checkout swap.
- **`--warmup` matters.** A smoothed follow legitimately spends its opening
  frames settling into its steady-state lag; without a warmup that one-time
  transient lands in the stats as a bogus `gentle_uphill` max-jerk spike
  (0.049 → 1.19) that looks exactly like a regression. 120 is plenty.
- Expected on current `main`: `mega_drop` mean jerk ~0.06 (was 0.38 rigid),
  `flat`/`gentle_uphill` at the ~0.002 noise floor, and follow distance ~7px.
  A `mega_drop` mean above ~0.15 means the follow filter or its lead term
  regressed.

Full investigation — root cause, the four hypotheses ruled out first, and why
the contact-point metric it replaced was a dead end: `docs/research/camera_shake.md`.
