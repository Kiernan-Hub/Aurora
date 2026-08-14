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

**Two independent jump multipliers compose at the impulse**:
`velocity.y = JUMP_VELOCITY * upgrade_jump_multiplier * jump_boost_multiplier`.
They are separate vars on purpose. `jump_boost_multiplier` is the powerup (√2, temporary)
and `end_jump_boost()` resets it to 1.0 **absolutely**; `upgrade_jump_multiplier` is the
purchased meta-progression level (×0.60 → ×1.00, fixed for a whole run). Sharing one var
would mean every expiring powerup silently wiped the player's purchase. Only
`GameManager.apply_upgrades()` may write the upgrade one, and it skips headless runs so no
probe measures physics derived from the developer's own `save.dat` — see `CLAUDE.md`.

**Double jump — ruled out (2026-08-06).** Every chasm invariant in
`terrain_invariant_check.gd` (`CHASM_LEAD_IN_LENGTH`, `CHASM_MAX_REACH_FRACTION`,
`check_chasm_variant_table()`) is built on reach as a pure function of takeoff speed —
`get_jump_reach(speed, multiplier)`, one continuous parabola. A double jump makes reach a
function of *when* the player fires the second impulse mid-arc, which none of that math
represents; it isn't a bigger number to re-bound, it's a different shape of function.
A cooldown doesn't help — it limits how often the mechanic fires per run, not what happens
the one time it's used right at a chasm's lead-in edge, which is exactly when a player
would use it. Proving it safe would mean deriving and asserting a worst-case two-impulse
reach bound the way `check_chasm_variant_table()` does for one impulse today — real,
non-trivial verification work, not a multiplier tweak. Airborne tricks (CLAUDE.md Build
order §5) were built instead — same "more airtime = more fun" fantasy, zero reach risk.

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

## Jump reach, and the rare coin (2026-08-13)

Apex is `v² / 2g` with `v = JUMP_VELOCITY(640) × upgrade multiplier`, so it goes as the
**square** of the multiplier — `128 × m²`. The upgrade tree is a much bigger change in reach
than the multipliers suggest at a glance:

| Jump level | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| Multiplier | 0.60 | 0.70 | 0.80 | 0.90 | 1.00 |
| Apex (px) | 46.1 | 62.7 | 81.9 | 103.7 | 128.0 |
| Grab ceiling (px above surface) | 104.1 | 120.7 | 139.9 | 161.7 | 186.0 |

Grab ceiling is `48 + apex + pickup radius(10)`. The 48 is the capsule's centre-to-top
distance *doubled*: the capsule centre starts one half-height (24) above the surface, and it
is the top of the capsule that reaches a pickup.

`RareCoinSpawner.RARE_COIN_CLEARANCE = 174` is placed inside the ~24px gap between the top
two ceilings — 12.3px above level 3, 12px below level 4 — which is what makes it a
max-upgrade-only reward. **The jump powerup (×√2 velocity, so ×2 apex) is the one documented
exception**: any level holding one reaches it, which is intended.

That number is coupled to `JUMP_VELOCITY`, `GRAVITY`, the last two `JUMP_MULTIPLIERS` and
`rare_coin.tscn`'s collision radius, in four different files, and **both ways of getting it
wrong are silent in play** — so `terrain_invariant_check.check_rare_coin_height()` asserts
the whole table above, reading the radius out of the scene rather than restating it.

### Coin arcs (2026-08-13)

The same table read from the bottom. With no jump at all the ceiling is **58px** (`48 +
radius 10`), and `COIN_SURFACE_CLEARANCE` is 34 — so before arcs, **every ground coin in the
game was collected with zero input**. That is why an in-run combo counter was pointless: no
coin could be missed.

An included coin slot now rolls `COIN_ARC_CHANCE` (0.3) into a three-coin arc instead of one
ground coin: peak **92**, shoulders **84** at ±60px. 92 clears the 58 free line by a wide
margin and sits 12px under **level 0's** 104 ceiling — the weakest jump, because a coin the
starting player cannot reach reads as a bug. The shoulders are on the jump parabola through
that peak, not on an arbitrary lower line: `½·g·(60/v)²` is 11.5px of drop at 500 px/s and
5.1px at 750, so one 8px offset covers the whole speed range.

Two things about the arc are terrain-dependent, not constants:

- Clearance is measured per coin against the ground under **that** coin, so an arc tilts with
  the slope while a jump does not. Over `COIN_ARC_MAX_GROUND_DROP` (24px across the 120px
  span, ~11°) the slot **falls back to a single ground coin**.
- That fallback fires on roughly 40% of arc rolls, so the density is not the product of the
  constants. `COIN_SLOT_INCLUDE_CHANCE` was cut 0.40 → **0.30** to land the measured density
  back on the pre-arc **0.40 coins per slot** that `JUMP_UPGRADE_COSTS` is costed against.
  `terrain_invariant_check` **measures** it per seed (0.37–0.42 observed over 8) rather than
  asserting a closed form, and `check_coin_arc_height()` holds both clearance ceilings.

## Fall death (chasms)

`update_fall_death()` runs after `move_and_slide()` + snap and **before** both watchdogs, so
a dead player never enters one. It is the only death path other than `obstacle.gd`.

The predicate is **depth below the height field**, not an absolute Y and not a captured lip
height:

```gdscript
global_position.y - terrain_generator.get_surface_world_y(global_position.x) > FALL_DEATH_DEPTH  # 360
```

Two properties are load-bearing. It **needs no knowledge of chasms** — the field is
single-valued and the body is always above the surface on real ground, so positive depth can
only mean a void, and because `get_terrain_height()` returns the lip height across a void this
*is* "how far below the lip am I". And it is **stateless**, which is what makes it correct
across a world rebase: `Main.apply_world_rebase` runs earlier in tree order and shifts the
generator and the body by the same amount in the same frame, and `get_surface_world_y()` reads
the generator's live `global_position.y`, so the difference is invariant. A captured lip Y
would go stale by a full rebase quantum the moment one landed mid-fall.

360px is ~0.67s of fall. There is no terminal velocity in this project, so a deeper threshold
gets expensive fast.

## A speed boost carries the player across a chasm

`is_using_grounded_model = is_boosting or (...)` forces the grounded, **gravity-free** velocity
model whether or not there is a floor. Over a void the collision chord slope reads 0, so
velocity is `(boost_speed, 0)` and the player skims across at lip height onto the far lip.

This matters because jump input is suppressed for the boost's full 3s — without the glide,
every boosted chasm would be unavoidable death, the same class as the obstacle/boost issue in
CLAUDE.md's Known issues. Here the boost *solves* the hazard instead.

**It is emergent, not designed**, and it rests on two facts in two files: this gate in
`player.gd`, and `TerrainGenerator` keeping the void's entries in `chunk_collision_sample_xs`
so the chord slope is 0 rather than an arbitrary 512px-chord angle. Splitting the boost out of
the model gate, or pruning those samples, silently breaks it. `chasm_probe.gd`'s `boost` trial
is the only thing that would catch it.

The remaining hole is a boost *expiring* mid-void — gravity would return at lip height with no
jump available. `PowerupManager.can_end_effect()` holds the boost until the player is over
ground again; the extension is at most ~0.25s. Which effects get that treatment is the
`VOID_GUARDED_EFFECTS` list — any future effect that is the only thing holding the player up
over a void belongs on it.

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

## Debug instrumentation

`DEBUG_SHOW_PLAYER_STATE`, `DEBUG_LOG_FREEZE_REPRO` and
`DEBUG_ALLOW_MANUAL_SPEED_CONTROL` all default to **`OS.is_debug_build()`** — on under
the editor, headless probes and debug exports; **off in an exported release build.**

They shipped as plain `true` until 2026-08-03. That meant the release APK ran the full
probe rig every physics frame: `update_debug_state_label()` and
`record_freeze_repro_frame()` each do a `get_floor_collision_data()` pass and a terrain
segment lookup, and between them allocate ~25 transient Strings — roughly 3,600
refcounted heap allocations per second, which is the profile that produces intermittent
stutter on mid-range Android. It also drew a 10-line overlay over the pause button and
left the arrow keys as a live speed cheat on desktop builds.

They are deliberately **not** `@export` anymore, matching `Main.world_rebase_enabled` and
`GameManager.require_start_screen`. An `@export` is exactly what `main.tscn` silently
serialised to reintroduce the freeze bug for weeks, and these now control whether the
game does thousands of allocations per second. Probes set them directly in code, which
works identically on a plain var.

`player.gd` also carries read-only fields added for the jitter investigation
(`debug_position_after_slide/snap`, `debug_velocity_before/after_slide`) — zero behavior
impact, safe to keep or strip.
