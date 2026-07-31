# Debugging & regression harnesses

Reference doc for the exact commands and flags used to reproduce/regress physics and
terrain bugs. `CLAUDE.md` says *when* to run these; this file has the *how*. Rationale
and measured history for why each harness exists: `docs/research/freeze_bug.md`.

No test suite, no build script. Godot: `/Applications/Godot.app/Contents/MacOS/Godot`
(play with `--path .`, opens a window and blocks — only when asked).

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
