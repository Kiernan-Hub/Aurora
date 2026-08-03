# Player physics & camera

Implementation reference for `scripts/player/player.gd` and the camera follow in
`scripts/main.gd`. The residual-jitter investigation this file keeps referring to lives
in `docs/research/terrain_jitter.md`; the camera one in `docs/research/camera_shake.md`.

## Two velocity models

Grounded and airborne are genuinely different models, and mixing them up is the source
of most feel bugs.

**Grounded** (`is_boosting or (is_on_floor() and not is_jump_ascending)`):
`velocity = get_slope_tangent() * current_speed` — constant speed **along the surface**,
so forward progress slows on steep terrain.

**Airborne**: `velocity.x = current_speed`, `velocity.y += GRAVITY * delta`.

Coyote time and jump buffer are both 0.12s. Jump is the built-in `ui_accept` action plus
the separate touch path (see `input.md`).

The gate is `is_on_floor() and not is_jump_ascending`, **not** the former
`velocity.y >= 0.0`. That old test was trying to let a jump escape the grounded model,
but it also caught every *rising* frame, because the grounded model's own velocity is
the surface tangent and an uphill tangent points up. Measured before the change: on
`gentle_uphill`, **76%** of frames where the body was genuinely on the floor ran the
airborne gravity model instead of following the surface.

## get_slope_tangent() — and three things that don't work

It samples `TerrainGenerator.get_collision_chord_slope_angle` — the actual ~16px
collision chord — not the continuous height field's analytic tangent. The two can
disagree by a couple of degrees on curved terrain, and aiming the body along an angle
that doesn't match the surface it is physically sliding on injects spurious vertical
velocity every chord. Visual rotation still uses the smoother analytic
`get_slope_angle_at_x`, which is fine because it's cosmetic only.

**Do not damp this angle over time** (tried 2026-07-29, reverted). On a piecewise-linear
floor the correct heading *is* the current chord's heading; lagging it aims the body into
the floor on concave stretches and off it on convex ones. A/B over 9000 frames of seed
941462462: mean surface-gap wobble 0.210px → 0.270px, vertical-velocity reversals 4.09%
→ 7.43% of grounded frames, ~20% more time airborne. Smoothing is right for the cosmetic
sprite angle and wrong for the vector that determines contact.

**Do not aim along the step's endpoint chord** (tried 2026-07-30, reverted). No clear
improvement: `medium_hill`/`medium_valley` residual dropped ~4-10%, `small_hill` rose
~9%, and the no-contact-frame fraction it targeted was unchanged (0.361 vs 0.366).

**Do not aim along `get_floor_normal()`** (tried 2026-07-30, reverted). Worse on every
segment, including the near-constant-slope `sustained_downhill` control (0.147px →
0.218px, +48%). `get_floor_normal()` reflects the *previous* frame's resolved contact —
one frame stale on continuously-curving terrain, the same lag mechanism as the smoothing
experiment above.

Together these confirm the residual bounce is not caused by, and not fixed by chasing,
any particular tangent choice.

## apply_grounded_floor_snap()

Closes the sub-pixel gap Godot declines to close itself. `CharacterBody2D`'s own floor
snapping early-returns whenever velocity faces `up_direction` (`_snap_on_floor` →
`vel_dir_facing_up`), and on this terrain that is **every rising frame**, since the
grounded model aims velocity along the surface. The step is then tangential,
`move_and_slide()` reports no contact at all, and nothing re-seats the body:
`is_on_floor()` goes false while the capsule sits ~0.4px off the terrain, and the next
frame runs the gravity model to fall that 0.4px back down.

That two-frame cycle was the measured `is_on_floor()` flicker — ~60% of `gentle_uphill`
frames, ~36% of all rising frames, against <1% on falling ground. The body never actually
left the surface; only the engine's bookkeeping did. `apply_floor_snap()` has no velocity
gate, so calling it directly fixes it.

Deliberately scoped to exactly the suppressed case: when velocity faces down, Godot's
stock snapping already runs and this must not second-guess it. While boosting the
velocity gate is dropped entirely, because a boost is meant to be ground-locked with zero
airtime including the brief upward hop a bump imparts.

## Other invariants

- Visual tilt lives on the child `ColorRect`, **never** the body: exponential weight
  `1 - exp(-k*delta)`, clamped to the terrain angle's side of upright so a fast reversal
  can't overshoot, and frozen mid-air. Don't swap in a plain lerp.
- Collider is `CapsuleShape2D` (r16, h48) with `safe_margin = 1.0`. Both were the fix for
  a snag/freeze bug on segment seams (`f2f075b`). Don't revert to a rectangle or drop the
  margin.
- `player.gd` holds `speed_manager` as a bare `RefCounted`, not typed `SpeedManager`.
  Untested whether typing it directly would break anything — the real circular reference
  is Player↔TerrainGenerator, not this.
- `SpeedManager.update()` is **incremental** (`current_speed + accel*delta`), not
  recomputed from `elapsed_time` each call, because several probes pin `current_speed`
  directly to `MAX_SPEED` right after spawn. A formula keyed on `elapsed_time` would
  silently overwrite that pin on the next frame.

## Stall watchdogs

Two of them, both recovering through `recover_from_stall()`, which re-seats the body on
the terrain height field (the polyline is a discretisation the solver can produce a
nonsense normal for; the field it was sampled from is exact).

`is_stalled_this_frame()` is the shared predicate: grounded, `|velocity.x| >= 1.0`, and
`|last_physics_displacement.x| <= 0.01`. Sharing it means the recovery watchdog and the
freeze logger can never disagree about what a stall is.

- **Per-frame** (`update_stall_recovery`): 4 consecutive stalled frames (~67ms). Long
  enough that the known one-frame landing-depenetration false positive can't trigger it.
- **Net-progress** (`update_stuck_detection`): under 20px of net motion over a 60-frame
  (~1s) rolling window. This exists because a *jittering* stall — small back-and-forth
  motion — never strings together 4 consecutive near-zero frames, so the per-frame
  watchdog never fires while the player is nonetheless going nowhere. Measured at seed
  222894852 / world_x 1,166,358: 600 frames, net progress 1.6px, recoveries 0.

Both print (`STALL_RECOVERY` / `STUCK_DETECTED`). A passing regression run must show
**zero** `debug_stall_recovery_count` — non-zero means a stall happened and was papered
over.

## Camera follow (`scripts/main.gd`)

Vertical: follows **downward only**, `max(camera_baseline_y, player.y - 72)`, with
exponential smoothing.

Horizontal: **also exponentially smoothed** (`HORIZONTAL_FOLLOW_SMOOTHNESS`, 8.0) and
then *led* by a smoothed scroll-rate estimate that cancels the filter's steady-state lag.
**Do not "simplify" this back to `camera.x = player.x`.**

The terrain is static in world space, so the on-screen motion of the entire view *is* the
camera's per-frame displacement — a rigid follow therefore pipes every bit of
`move_and_slide()`'s per-frame x resolution noise straight to the screen as whole-view
judder. Measured (seed 941462462): mean per-frame camera jerk 0.0008 px/frame² on flat
but 0.478 on `mega_drop`, with the scroll rate **reversing direction on 52% of
`mega_drop` frames** — a ~30Hz stutter of the whole world. That matches the playtest
report exactly, and explains why the sprite still looked perfectly glued to the terrain:
sprite-vs-terrain is a pure world-space relationship that never involves the camera, so
only the shared view shook.

A/B at that seed: rigid 0.382 → 0.062, an 84% reduction, peak jerk 2.13 → 0.34.

Two constants that must stay in their current relationship:

- `SCROLL_RATE_SMOOTHNESS` (6.0) must stay **slower** than
  `HORIZONTAL_FOLLOW_SMOOTHNESS` (8.0). The lead multiplies the rate estimate by
  `(1-w)/w` (~7× at 8.0), so any frame-to-frame noise left in it is amplified straight
  back into the position the filter exists to smooth. Softer follow settings measure
  marginally better but weren't taken: at 6.0 the two are equal, and the follow
  distance's peak excursion grew (10.6px → 11.4px) as the lead began chasing noise.
- The lead is built from the **smoothed** scroll rate, never the raw per-frame delta.

The lead exists because an exponential follow settles ~38px behind its target at cap
speed, and on an auto-runner that's forward reaction distance the player can't afford to
lose. Cancelling it costs judder rejection only, not visibility.

X is never world-rebased (`world_rebaser.gd` rebases Y only), so the scroll-rate estimate
needs no rebase correction — unlike `camera_y` / `camera_baseline_y`, which do.

## Debug instrumentation that ships on

`DEBUG_SHOW_PLAYER_STATE`, `DEBUG_LOG_FREEZE_REPRO` and
`DEBUG_ALLOW_MANUAL_SPEED_CONTROL` all default to `true`. The Android build therefore
draws a 10-line state overlay across the top-left (overlapping the pause button, though
`Label`'s default `MOUSE_FILTER_IGNORE` means it doesn't block the tap) and formats a
per-frame history string at 60 Hz. Fine for development; turn them off before any build
meant to be played by someone else.

`player.gd` also carries read-only fields added for the jitter investigation
(`debug_position_after_slide/snap`, `debug_velocity_before/after_slide`) — zero behavior
impact, safe to keep or strip.
