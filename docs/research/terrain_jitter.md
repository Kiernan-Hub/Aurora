# Residual sub-pixel bounce on curved terrain — research archive

Detailed investigation log for the residual jitter that survived the `is_on_floor()`
flicker fix (`docs/research/floor_flicker.md`). This is an archive — open it before
touching `player.gd`'s grounded movement/collision or any visual-smoothing code again,
or when `CLAUDE.md` points here. Multiple sessions across 2026-07-29 through 2026-07-31;
kept in narrative order so it survives context resets.

## 2026-07-29 — early experiment, movement-direction damping (reverted)

**Do not damp the movement direction over time.** Tried and measured: applying the
same `1 - exp(-k*delta)` + `lerp_angle` smoothing that the sprite uses to
`get_slope_tangent()`'s angle makes contact *worse*, because on a piecewise-linear
floor the correct heading **is** the current chord's heading — lagging it aims the
body into the floor on concave stretches and off it on convex ones. A/B over 9000
frames of seed 941462462: mean surface-gap wobble 0.210px → 0.270px,
vertical-velocity reversals 4.09% → 7.43% of grounded frames, ~20% more time airborne.
Reverted; the reasoning is restated at the `get_slope_tangent()` call site so it isn't
re-attempted.

**Known cosmetic quirk, not a jitter source**: visual tilt lives on the child
`ColorRect`, using exp weight `1 - exp(-k*delta)` clamped to the terrain angle's side
of upright (so a fast reversal can't overshoot; freezes mid-air). That clamp silently
defeats the smoothing whenever the terrain angle is *decreasing* on a descent —
measured pinned to the raw angle 96.9% of frames through the back half of a
`mega_drop` vs 0% through the front half. Measured rotation step size is the same
either way (mean ~0.25°/frame both halves), so it is not a jitter source; it just
means the sprite tracks the raw analytic angle there instead of a smoothed one.

## 2026-07-30 — long investigation, root cause identified

Goal was to find and fix the residual bounce noted in `floor_flicker.md`. Root cause
is now identified with high confidence and is **not fixable at the input/movement
level**.

**TL;DR**: jitter occurs near curvature transitions (hill peaks/valleys), not on flat
or constant-slope ground; it's caused by `CharacterBody2D`'s own per-frame solver
correction resolving contact against curved terrain, not by anything about how the
player is moved. Ruled out as fixes: tangent direction (start-sampled vs chord vs
floor-normal-aimed), collision shape (capsule vs rectangle), explicit floor snapping,
`safe_margin` as a *complete* fix (0.1 helps ~3-4x but costs reliability at one
known-bad seed), general visual smoothing (trades jitter for a new lag artifact on
flat ground), and velocity-manipulation approaches (clamping into-terrain velocity,
pre-emptive separation). Status at the time: **accepted/deferred**, not blocking —
revisit only if it becomes a real gameplay complaint.

### Confirmed mechanism

The vertical bounce comes from `CharacterBody2D.move_and_slide()`'s own per-frame
contact resolution on curved terrain, and it is **inherent to the solver**, not a
symptom of how the player is moved. Evidence, ranked by how directly it was tested:

- `vertical_diff` (actual step motion minus requested motion, measured with zero
  smoothing) is ~0 on flat ground, rises on any curved segment, and correlates with
  **curvature**, not steepness — `mega_drop` (28.6° peak, low curvature per chord) is
  quieter than the ~13° hills (high curvature). Collision-polyline resolution
  (16/8/4px chords) does not change it. Vertex-crossing specifically does not explain
  it either (`offset_curve_probe.gd`: residual on geometrically "stable" frames, no
  bracket change, is statistically equal to residual at transitions).
- Four different fixes to *how the player is moved* were tried and measured, and
  **none reduced it, several made it worse**:
  - Aiming along the step's endpoint chord instead of a start-sampled tangent: no
    clear improvement.
  - Aiming along the *actual* last-reported `get_floor_normal()` instead of the
    analytic chord: made residual **worse** on every segment (+21% to +48%), because
    the floor normal is one frame stale on continuously-curving ground — same lag
    failure mode as the 2026-07-29 temporal-tangent-smoothing experiment above.
  - Swapping the capsule for a flat-bottomed `RectangleShape2D`: no improvement, and
    reintroduced corner-snag behavior (more `NO_CONTACT` frames, our own explicit
    snap started firing again) — this is *why* the capsule was chosen in the first
    place (`f2f075b`), don't revisit.
  - Clamping requested vertical velocity to never point into the terrain (Test B),
    and giving the body a tiny pre-emptive upward separation before each step
    (Test C): both left the curvature-specific correction **unchanged or worse**.
    Test D (pure horizontal movement, zero terrain-following at all) confirmed this
    conclusively: Godot's own unassisted contact resolution tracks the curved
    surface about as smoothly frame-to-frame as active tangent-following does
    (`gap_wobble` on hills was *slightly better*, 0.23-0.28 vs ~0.35-0.44) even
    though the raw positional error is 6-8x larger and it introduces real airborne
    hops (up to 52px apex) that tangent-following never produces. **Conclusion: the
    solver cannot maintain stable, correction-free contact on curved terrain
    regardless of movement strategy.**
- `safe_margin` sweep (0.01 / 0.1 / 0.5 / 1.0 / 2.0): residual scales monotonically
  with margin. **0.1 gives a real ~3.2-3.9x reduction** at full 4-seed/9000-frame
  scale, with `is_on_floor()` flicker still exactly 0. But **0.01 is disqualified
  outright** — it reproduces near-stall behavior at the documented freeze location
  (33/40 near-stalling trials, 8 real `STUCK_DETECTED` events, though it never
  crossed the strictest single-trial STALL threshold — only the broader net-progress
  watchdog caught it). Even 0.1 is not fully clean: it introduced 8/40 near-stalling
  trials at one of the three known-bad seed/locations (`3188032853` @ 264063) where
  baseline is perfectly clean — the other two known-bad locations were unaffected.
  **`safe_margin=0.1` is a real, partial, non-free mitigation, not a validated fix**
  — would need much broader multi-seed freeze-search + a full 60k-frame no-input
  replay before ever adopting.
- Visual-only mitigation attempts (both reverted, no trace left in `player.gd`):
  - General smoothing (exponential lerp toward the body's true position, `k`=2..15
    swept): the strength needed to meaningfully reduce hill jitter (~33-42% at
    `k`≈2) introduces a *new*, more constant lag artifact on previously-perfect flat
    ground (0.0008px→0.30px) — not a clean win.
  - Targeted "compensation" (subtract only the solver's per-step correction from the
    rendered position, not general smoothing): a **non-accumulating** version
    (recompute fresh from the real position each frame) is mathematically provably
    unable to reduce frame-to-frame jitter (confirmed empirically: visual_jitter ==
    raw_jitter) — the single-frame delta only depends on the *difference* between
    consecutive corrections, not their magnitude, so nothing cancels. An
    **accumulating** version does work mathematically (visual delta reduces to
    exactly the requested/idealized motion) but drifts the rendered position away
    from the real physics body — clamped, it just saturates and stops helping;
    unclamped, drift reached ~70px in a short test. There is a real tension between
    "cancel oscillating noise" and "zero lag / no accumulation" that this experiment
    could not resolve within those constraints.

**Bottom line**: every angle tried — movement direction, tangent/chord sampling,
floor-normal aiming, collision shape, `safe_margin`, pure horizontal movement, and
two different visual-only strategies — either didn't help or made something else
worse. The two least-bad partial mitigations found at this point were
`safe_margin≈0.1` (real reduction, real but smaller safety cost, needs much more
validation) and possibly a bounded/leaky-accumulator visual compensation (not yet
tried — the unclamped version proved the *cancellation math works*, the open problem
was bounding the drift without reintroducing the lag the last experiment was built to
avoid).

Read-only debug probes built during this investigation, useful for any follow-up:
`chord_aim_probe.gd`, `offset_curve_probe.gd`, `slide_vs_snap_probe.gd`,
`contact_instability_probe.gd`, `solver_correction_probe.gd`,
`visual_compensation_probe.gd`. **None of them runs as-is** — they predate the start
screen and measure a paused game; see "Archived probes" in
`docs/development/debugging.md` before trusting one. (`visual_smoothing_probe.gd` was
deleted 2026-08-03: it consumed a `Player` experiment that no longer exists.)
`player.gd` carries read-only instrumentation fields
added for these (`debug_position_after_slide/snap`, `debug_velocity_before/after_slide`)
— harmless, zero behavior impact, safe to keep or strip.

## 2026-07-31 — washout-filter mitigation attempt (measured working, reverted as imperceptible)

A follow-up phase explicitly changed goal from "eliminate the solver correction" to
"hide it without touching physics, while staying safe for future steep
terrain/cliffs/chasms/jumps." Built a frequency-domain probe
(`scripts/debug/jitter_frequency_probe.gd`, kept, read-only, useful for any
follow-up) that splits vertical motion into a reversal-rate signature (HF, the
bounce) vs net progress over a rolling window (LF, real motion), instead of the
mean-|delta_y| metric used in the 2026-07-30 phase above, which can't tell a
hill-crest bob apart from a legitimate cliff fall.

That probe's no-input baseline confirmed the mechanism precisely: reversal rate
5.6-6.2% on `small_hill`/`medium_hill`/`medium_valley` vs a 0.3-1.4% floor on
`flat`/`gentle_uphill`/`mega_drop`/scripted-jump `AIRBORNE` frames — 15-40x higher
exactly on curvature-heavy segments, and low precisely where large one-directional
motion happens, which is what made a magnitude+reversal-gated filter seem safe for
future cliffs/drops (large same-signed deltas never look like the bounce).

**Implementation** (briefly present in `player.gd`/`main.gd`, since reverted): a
filter applied only to `color_rect.position.y` (never `global_position`/velocity),
continuously while genuinely rolling (`is_on_floor() and is_using_grounded_model and
not is_jump_ascending`, two consecutive such frames) and below a small magnitude
gate, `offset[n] = clamp(-0.5 * motion_y[n], ±2px)`. Applying it *every* rolling
frame (not just on frames that individually look like a reversal — a first version
gated that way and measured almost no improvement, since halving one frame's delta
without also having offset the frame before it doesn't reproduce cancellation, just
shrinks the symptom) makes consecutive offsets compose into a true causal 2-tap
moving average: `presentation_delta[n] = 0.5*(motion_y[n] + motion_y[n-1])`, which
nulls an alternating +d,-d sequence and leaves a steady one-directional sequence at a
small bounded constant offset rather than a growing lag. Camera was pointed at the
same filtered signal (`Player.get_presentation_y()`) instead of raw
`global_position.y`, so the sprite and the screen wouldn't jitter independently of
each other.

**Measured** (4 seeds × 9000 frames, no-input): reversal rate roughly halved on
exactly the affected segments (`medium_hill` 5.59%→2.95%, `medium_valley`
4.49%→1.88%, `small_hill` 6.19%→3.27%), while mean delta magnitude was essentially
untouched (`medium_hill` 1.771→1.758px, ~0.7% change) and the
`flat`/`gentle_uphill`/`mega_drop` controls showed no new lag. Camera-side numbers
barely moved either way, confirming (separately measured, before implementing
anything) that the existing `max(baseline, y-72)` clamp + `k=6` lerp already
attenuates camera-side reversal to about a third of the raw body's on every hill
segment — the camera was never the amplifier it looked like it might be from napkin
math; decoupling it turned out to be low-value on its own.

**Reverted despite the clean measurement**: playtest-confirmed (2026-07-31) the
change was imperceptible in actual play — "looks the same, nothing's changed... no
improvement on hills." The underlying artifact is sub-pixel to begin with (mean
offset well under 1px in the typical case, clamp of 2px only reached rarely), so a
real ~50% cut in an already-sub-pixel oscillating quantity does not cross into
visible territory during normal-speed gameplay. Per this investigation's own rule
("do not keep changes unless they clearly improve the result"), a metric-only win
was reverted rather than kept. Scene files were checked and do NOT override the
export that gated this (the same class of bug that silently disabled
`world_rebase_enabled` once, see "Things that break silently" in `CLAUDE.md`) — so
the null result is real, not a wiring bug.

## Implication for any future attempt

The residual bounce documented throughout this file is real and measurable at the
physics/rendering level, but is likely near or below the threshold of human visual
perception at this game's normal camera zoom and speed, independent of which
visual-only technique is used to reduce it. Before investing further here, get
independent confirmation the bounce is actually visible during normal play (not just
under close/frame-stepped inspection) — otherwise further filter-tuning is likely to
repeat this result. `jitter_frequency_probe.gd`'s reversal-rate/second-difference
split is the right tool to reach for if this is revisited; it's a materially better
signal than the mean-|delta_y| metric used in the 2026-07-30 phase above.
