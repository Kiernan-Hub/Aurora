# `is_on_floor()` flicker on shallow slopes — research archive

Fixed 2026-07-29, `player.gd`. This is an archive — open it when working on the
grounded/airborne model switch or floor snapping, or when `CLAUDE.md` points here.

## Measurement that found it

Measured (headless, 6 seeds × 20,000 frames, no player input) via a per-segment-label
`is_on_floor()` flip-rate probe (`scripts/debug/floor_flicker_probe.gd`, kept as the
permanent regression gate):

| segment | floor-flip rate before fix |
|---|---|
| `gentle_uphill` | **~60-65%** of frames |
| `medium_hill` / `medium_valley` / `small_hill` | ~10-12% |
| `flat` / `sustained_downhill` / `mega_drop` | <0.5% |

## Root cause

Not steepness, but slope *sign*. Uphill frames flipped at ~35%, downhill ~1%, flat
~2%, across every tested seed — `gentle_uphill` (100% uphill) tops the table only
because it's the purest case. On a rising slope the grounded velocity model
(`velocity = slope_tangent * speed`, `player.gd`) aims the body's velocity **up**
(`velocity.y < 0`). Two things follow from that one sign:

1. The move is tangential to the surface, so `move_and_slide()` finds no contact at
   all that tick (`slide_collision_count == 0`), and `is_on_floor()` goes false.
2. Godot's own floor snapping — the mechanism that exists to catch exactly this — is
   suppressed whenever velocity faces `up_direction` (`CharacterBody2D`'s internal
   `_snap_on_floor` early-returns on `vel_dir_facing_up`). So nothing re-seats the
   body.

The next tick ran the airborne gravity model, fell the sub-pixel gap back onto the
surface, collided, and the cycle repeated at ~2-frame period. The body's actual
position barely moved (surface gap held around -0.1 to -0.6px) — this was never a
real bounce, it was Godot's internal floor bookkeeping flapping while the capsule sat
still.

## Fix (both parts required together)

- **`is_jump_ascending` flag** replaces the old grounded-model gate
  `is_on_floor() and velocity.y >= 0.0`. That expression was trying to let a jump
  escape the grounded model, but `velocity.y < 0` is *also* true for an uphill
  surface tangent, so every rising frame was misread as "jumping" and silently ran
  the gravity model instead of following the slope. `is_jump_ascending` is set true
  only on the actual jump impulse and cleared at the apex (`velocity.y >= 0`), so the
  grounded model now correctly stays active while climbing a hill. Measured before
  this changed: 76-78% of genuinely-grounded `gentle_uphill` frames were running the
  gravity model, not the slope-tangent model.
- **Forced `apply_floor_snap()`** in `apply_grounded_floor_snap()`, called after
  `move_and_slide()`, conditioned on `is_using_grounded_model and not is_on_floor()
  and velocity.y < 0.0` — i.e. exactly the case Godot's own snap suppresses.
  `apply_floor_snap()` has no `vel_dir_facing_up` gate, so it closes the sub-pixel gap
  `_snap_on_floor` declined to. Scoped narrowly on purpose: when velocity faces down,
  Godot's stock snapping already runs (over the same `FLOOR_SNAP_LENGTH`), so this
  cannot cancel airtime the engine would otherwise grant off a crest or `mega_drop`.

## Verification

Uphill flip rate 0.34-0.36 → **0.0000** on all 6 regression seeds (no-input) and
confirmed non-regressed under scripted jump input (`--jump=N` on the probe);
`terrain_invariant_check` PASS on 8 seeds; `freeze_search` 0 stalls on all 3
known-bad seeds; 60,000-frame replay `status=no_freeze`, 0 stall recoveries. Largest
forced snap displacement measured was 1.5px (against an 18px `FLOOR_SNAP_LENGTH`),
consistent with closing a sub-pixel gap rather than yanking the body onto the ground.
Landing after a real jump still shows one legitimate multi-pixel snap frame (closing
real fall distance) — that's expected and distinct from the flicker's sub-pixel case.

## What this fix does and doesn't cover

**Not fully fixed — residual sub-pixel bounce, playtest-confirmed 2026-07-29**:
`is_on_floor()` is now always `true` on the ground (the flip-rate metric above is
genuinely 0), but watching closely in-game the capsule still visibly bobs — it
doesn't stay flush with the surface every frame, occasionally lifting a hair before
the next snap pulls it back down. This matches what the probe's `gap_wobble` /
`mean_gap` fields already showed increasing on `medium_hill`/`medium_valley`/
`small_hill` post-fix (e.g. `small_hill` gap_wobble 0.29px→0.38-0.42px) — the fix
traded away the false floor-loss for a smaller, real, sub-pixel one, and that residual
is visible on screen even though every regression gate here (which checks
`is_on_floor()` correctness and stall/freeze safety, not sub-pixel visual smoothness)
passes clean. **Do not treat this file's PASS results as "no jitter remains"** — they
only certify the flicker/stall mechanism documented above, not the smoothness of the
ride. Full follow-up investigation: `docs/research/terrain_jitter.md`.

**Deferred by agreement, not forgotten**: the shakiness/jitter on the long ~40.5°
`mega_drop` slope is a **separate, still-open** issue — this fix barely touches it
(mechanism measured near-absent there: flip rate 0.002-0.004,
`gravity_while_grounded` <0.002, because `mega_drop` velocity always points down,
never up). Do not assume this fix addresses it without separately re-measuring.

**Explicitly NOT explained by this fix** (do not assume they're the same bug without
re-measuring): a separately-reported "the view snaps forward/backward for half a
second" during play. `debug_stall_recovery_count`/`debug_stuck_event_count` stayed at
**0 across every seed tested here**, so the stall/stuck watchdog's teleport-recovery
(which *would* look like a half-second snap) never fired — that bug may need
different input/conditions to reproduce, or is unrelated to floor detection entirely.
