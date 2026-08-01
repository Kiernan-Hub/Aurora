# Camera shake on steep terrain (mega_drop / hill crests) — 2026-08-01

> **Outcome: mega_drop was cut from the generator** (`MEGA_DROP_SELECTION_WEIGHT = 0`)
> after every identified fix measured well and felt like nothing in play. The
> camera-follow fix below is real, measured and kept; it was simply not what the
> eye was reacting to. Read "Fixes that measured well and changed nothing" before
> re-opening this. Worst-case camera jerk went 0.382 -> 0.033 px/frame^2 (-91%)
> and the game's steepest slope 40.5deg -> 20.13deg.

Long-running "mega_drop is jittery / unplayable" investigation. Root cause was
**not** in player physics or collision at all: it was the camera's rigid
horizontal follow transmitting `move_and_slide()`'s per-frame x-resolution
noise directly to the screen. Fixed in `scripts/main.gd` by filtering the
horizontal follow and cancelling the resulting lag with a lead term.

## Symptom (playtest description that cracked it)

The decisive report, after three rounds of numeric probing had found nothing:

> on the smooth flat parts the contact orange dot isn't moving, it's constant
> and smooth. when it goes up a hill near the top part, it starts flickering
> around, similar to how it flickers on the mega drop at the bottom. for the
> mega drop, the sprite is perfectly touching the terrain. the sprite is 45
> degrees, and perfectly touching the terrain. **it shakes as in it looks like
> the camera is shaky.** at the top of the gentle hills, it looks like it's
> vertically shaking up and down a tiny tiny bit... but for the mega drop, the
> camera shakes a lot more, but **the sprite NEVER loses contact with the
> terrain.** in terms of contact, it looks impeccable, it's just shaking.

Two things in that are load-bearing and were the key to the diagnosis:

1. **Contact looks perfect while the view shakes.** Sprite-versus-terrain
   agreement is a pure world-space relationship — `sprite_screen - terrain_screen
   = player.x - terrain_x`, the camera cancels out entirely. So contact can look
   flawless no matter how badly the camera misbehaves. Any hypothesis about
   contact quality was therefore incapable of explaining the symptom.
2. **Severity ranks flat < gentle crest < mega_drop.** That ranking is the
   fingerprint of a slope-dependent quantity, and it matched the eventual
   measurement almost exactly.

## Root cause

`main.gd` set the camera rigidly: `camera_2d.global_position = Vector2(player.global_position.x, camera_y)`.

The terrain is static in world space, so **the on-screen motion of the entire
view is exactly the camera's per-frame displacement.** A rigid follow makes that
displacement equal to the player's raw per-frame x advance — including every bit
of noise `move_and_slide()` injects while resolving the capsule against the 16px
collision-chord polyline (`MAX_COLLISION_SEGMENT_LENGTH`).

That noise is the same "residual sub-pixel bounce on curved terrain" already
documented in `terrain_jitter.md` and repeatedly dismissed as imperceptible —
**but that assessment only ever examined its vertical component.** Its
horizontal component is not sub-pixel: it swings the scroll rate by ±1–2px per
frame and reverses direction on over half of all mega_drop frames. Vertically
invisible, horizontally a ~30Hz stutter of the whole world.

## Measurements (`scripts/debug/camera_shake_probe.gd`, seed 941462462)

The metric is the **second difference of camera position** — the frame-to-frame
change in scroll rate ("jerk"). Perfectly smooth scrolling is 0; the only
legitimate contribution is the speed ramp (`ACCELERATION` 3.2 px/s² ⇒
0.0009 px/frame²), so anything above ~0.001 is judder.

Baseline (rigid follow), 7000 frames, warmup 120:

| segment | mean jerk_x | max jerk_x | scroll-rate reversals |
|---|---|---|---|
| flat | 0.00052 | 0.037 | 0.0% |
| gentle_uphill | 0.00152 | 0.049 | 4.0% |
| sustained_downhill | 0.08382 | 0.516 | 40.1% |
| small_hill | 0.11697 | 0.723 | 47.9% |
| medium_hill | 0.11794 | 0.783 | 46.1% |
| medium_valley | 0.14102 | 0.781 | 46.9% |
| **mega_drop** | **0.38240** | **2.127** | **53.7%** |

mega_drop is ~735× flat, and its scroll rate reverses direction on 53.7% of
frames. **This ranking reproduces the playtest ranking exactly** — which is what
established the metric as the right one after `contact_anomaly_len` had failed
to (see "Ruled out" below).

Also confirmed directly: `camera_x[n] == player_x[n-1]` on **100.0%** of frames
(max error 0.000000 px). `Main` is the scene root, so `Main._physics_process`
runs before the `Player` child's — the camera always reads a pre-move position.
This is a real one-frame lag but is *not* the shake (a constant delay of a
smooth signal is still smooth); it only matters as ~7px of baseline framing that
the fix had to preserve.

## The fix

Two parts, both in `scripts/main.gd`, both presentation-only:

1. **Filter the horizontal follow** (`HORIZONTAL_FOLLOW_SMOOTHNESS = 8.0`),
   exponential, same `1 - exp(-k*delta)` form the vertical follow already used.
2. **Lead the target to cancel the filter's lag.** An exponential follow settles
   at `per_frame_dx * (1-w)/w` behind its target — 38.7px measured at the
   smoothing needed, which on an auto-runner is forward reaction distance the
   player cannot afford to lose. Leading by exactly that amount restores framing
   for free. The lead is built from a **smoothed** scroll-rate estimate
   (`SCROLL_RATE_SMOOTHNESS = 6.0`), never the raw per-frame delta, or it would
   feed the very noise being filtered straight back in.

Result at shipped settings (same seed/frames/warmup):

| config | follow distance | mega_drop mean jerk | mega_drop max jerk |
|---|---|---|---|
| rigid (before) | 7.01 px | 0.382 | 2.127 |
| filtered, no lead | 38.67 px | 0.055 (−86%) | 0.301 |
| **filtered + lead (shipped)** | **7.04 px** | **0.062 (−84%)** | **0.340 (−84%)** |

Framing is preserved to within 0.03px of the original while judder drops ~84%
across every affected segment (medium_hill −73%, medium_valley −73%,
small_hill −69%, sustained_downhill −76%). `flat`/`gentle_uphill` move from
0.0005→0.002, i.e. noise floor to noise floor — invisible.

`alt_frac` (fraction of frames where the scroll rate reverses) *rises* slightly
after the fix, ~54%→62%. That is expected and not a regression: what remains is
tiny-amplitude dither that still alternates. Amplitude is the visible quantity,
and it fell ~84%.

### Why not fix it in the physics instead

Considered and rejected. The camera is read by **nothing** outside `main.gd`
(verified by grep across `scripts/`), so this change provably cannot affect
terrain, collision, or the freeze/stall behaviour — it is the lowest-risk place
in the codebase to fix this, which matters given how many physics-level attempts
on this bug have been reverted (see `terrain_jitter.md`). The underlying
solver noise is still there; it is simply no longer wired straight to the screen.

## Ruled out along the way

All of these were measured and eliminated, in order. Do not re-litigate without
new evidence:

- **`apply_grounded_floor_snap()` / landing snap.** Instrumented `snap_delta`
  (`position_after_snap - position_after_slide`) per frame: exactly `(0,0)` on
  every logged mega_drop frame across three runs. The function early-returns
  whenever `is_on_floor()` is already true after `move_and_slide()`
  (`player.gd`), which is every normal landing — it only ever fires for the
  separate rising-terrain flicker case it was written for.
- **Frame-timing hitch (GC/compile stall).** Added wall-clock `wall_gap_ms`
  between physics frames. Zero correlation: the one real ~1s stall in a 90s run
  produced a 0.019px anomaly, while the largest anomalies all occurred at
  ordinary 13.8–20.7ms frame timing.
- **Segment-entry transition.** Three probing rounds had only ever run
  `mega_drop`-only terrain (all other `debug_weight_*` zeroed), so the entry from
  a different segment type had never been tested. Restored the natural mix and
  logged the boundary: all four captured entries (`gentle_uphill`, `flat`,
  `medium_hill` ×2) showed `contact_anomaly_len = 0.0000` for every frame of the
  transition. Anomalies only ever appeared 1800+px deep into the segment.
- **Grounded/airborne velocity-model flicker.** Plausible on paper — the two
  models differ in x-speed by a factor of `cos(θ)` (`player.gd`), which would
  scale with slope exactly as observed. Measured and **false**: floor-state flips
  occur on 0.0–0.1% of frames and 0.0% of high-jerk frames. The `cb8998b`
  flicker fix holds.
- **Multi-contact selection tie** (`get_slide_collision_count() >= 2` with the
  winner's rank changing) — never observed across a confirmed-shake run.

### The metric that wasted three rounds

`contact_anomaly_len` / `local_delta_len` in `mega_drop_visual_probe.gd`: how far
the reported `KinematicCollision2D` contact *point* moves relative to the body.
It is reconstructed from which chord Godot's solver happened to pick and **is
never rendered anywhere in the game**. Every hypothesis built on it died, and in
the worst-anomaly clusters the body's own `slide_delta` and rotation were smooth
— i.e. the thing actually on screen was fine exactly where the metric screamed.

This is the second time a metric on this bug decoupled from feel: an earlier
presentation-layer position-smoothing attempt cut a jitter metric 42% with zero
perceptual improvement and was reverted. **Lesson: for a visual complaint,
measure the quantity that reaches the screen.** Here that was camera jerk, and
once measured it ranked the segments in the player's exact order on the first
try.

---

## Fixes that measured well and changed nothing (2026-08-01)

Everything below was implemented, measured on rendered output, and reported by
playtest as no perceptible change. Recorded so none of it gets retried.

| attempted fix | measured effect | felt |
|---|---|---|
| Camera horizontal follow filter + lag-cancelling lead | camera jerk 0.382 -> 0.062 px/frame^2 (-84%), framing preserved to 0.03px | "maybe slightly better? or placebo" |
| MSAA 2D (2x/4x/8x, live toggle) | rendered terrain-edge jerk 0.768 -> 0.385 (-50%) | no change |
| `Polygon2D.antialiased` on terrain fill | rendered terrain-edge jerk 0.768 -> 0.317 (-59%) | no change |

The pattern across the whole investigation: **six mechanisms were measured,
four were eliminated outright, and every one of the three that produced a real
measured improvement produced no perceptual improvement.** At that point the
segment itself was cut rather than continue.

### Render-layer facts established (all still true, all worth not re-deriving)

- **Frame pacing is flawless.** 1500 consecutive rendered frames: 100% had
  exactly one physics step, mean render delta 16.667ms, zero dropped, zero
  doubled. Display is 60Hz, physics 60Hz, vsync on, `physics_interpolation`
  off. `render_pacing_probe.gd`.
- **The canvas transform is NOT snapped.** `snap_2d_transforms_to_pixel` and
  `snap_2d_vertices_to_pixel` are both false, window is exactly 1152x648 at
  `content_scale_factor` 1.0, and a fixed world point's screen position moves
  in smooth fractional steps (642.113 -> 634.998 -> 627.910, deltas -7.134,
  -7.115, -7.088) exactly mirroring the camera. `canvas_transform_probe.gd`.
- **The rendered terrain edge still moves in whole-pixel lurches** — tracks the
  camera, then jumps +1px and snaps back -1px. Terrain-edge jerk 0.768 vs
  camera jerk 0.011 (70x). Since the transform is provably smooth, this is
  rasterisation of a hard un-antialiased edge, and it is the one mechanism
  never fully eliminated — only halved, by AA that nobody could see.
- **Nothing in the game runs on `_process`.** All motion is `_physics_process`,
  so a render/physics desync in game code is impossible.

### Measurement traps hit along the way

Both cost a full cycle and will recur if the probes are reused:

1. **The debug HUD anchors image correlation.** It is static high-contrast text
   over the top-left of every frame; left in, it pins any cross-correlation to
   zero shift and produces phantom "the image barely moved" readings. Crop the
   top ~215 rows.
2. **Projection correlation is ill-posed for this scene, and parallax breaks
   naive 2D correlation too.** For a straight diagonal edge a horizontal shift
   and a vertical shift give identical row/column projections; and a frame
   containing terrain at 1x plus background at 0.3x makes a whole-frame
   correlator flip between locking onto either layer (mean measured shift lands
   between the two). Measure a single layer in an isolated band.
3. **Capturing frames perturbs pacing.** `get_viewport().get_texture().get_image()`
   per frame introduces occasional duplicate/skipped physics steps that do NOT
   occur in normal play. Filter pairs to those where exactly one physics step
   occurred before drawing conclusions.

### Why cutting the segment was the call

The quantisation mechanism is angle-dependent, so severity scales with slope —
which is exactly the reported ranking (flat clean, gentle crests barely there,
mega_drop unplayable) and exactly what the numbers show. mega_drop at 40.5deg
was the only segment above 20deg; removing it takes the game's steepest slope
to 20.13deg and the worst-case camera jerk to 0.033.

It does **not** eliminate the class. Hills/valleys still measure ~0.028-0.033
against flat's ~0.002. If the shake is ever reported on hills, the open lead is
the rendered-edge quantisation above — not the camera, not pacing, not physics,
all of which are measured clean.
