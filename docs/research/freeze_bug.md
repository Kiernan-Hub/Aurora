# Terrain freeze / stall bugs — research archive

Detailed investigation log for the terrain freeze and stall bugs referenced from
`CLAUDE.md`. This is an archive, not routine reading — open it when working on
freeze/stall/world-rebasing code, or when `CLAUDE.md` points here.

Two distinct stall bugs were found and fixed. Both have independent watchdog
backstops still active in `player.gd` (`recover_from_stall`, `update_stuck_detection`)
in case either — or a new, unrelated one — recurs.

## Bug 1: float32 precision freeze (fixed by world rebasing)

**Mechanism**: terrain baselines drift downward without bound (no rebound), so after a
few minutes of play the collision surface sits tens of thousands of pixels below y=0.
Godot's 2D physics works in 32-bit floats, so the representable step at the contact
point grows with `|y|`:

```
y =    192  ->  ulp = 0.000015 px
y = 37,404  ->  ulp = 0.0039 px   (1/256)
y = 150,192 ->  ulp = 0.0156 px   (1/64)
```

Contact separation vectors are of order `safe_margin` (1.0 px), so at depth they are
only a few hundred ulps long and their *direction* quantises to coarse integer ratios.
`get_floor_normal()` then returns an off-vertical normal on provably flat ground —
observed values are exact fractions such as 23/64 and 11/32. `player.gd` aims velocity
along that normal, into the ground, `move_and_slide()` exhausts `max_slides`, and
`motion.x` collapses to 0: the freeze.

**Fix**: shift the whole play area back toward y=0 periodically (`Main.world_rebase_enabled`,
`scripts/systems/world_rebaser.gd`). Only Y is rebased — X stays untouched so
`TerrainGenerator.get_terrain_height(world_x)` stays a pure function of
`(session_seed, world_x)` and every recorded repro seed stays valid. Measured: 3
reproducing stalls across 60 trials → 0, and the slide count stopped reaching the
engine's `max_slides` cap of 4. See "Things that break silently" in `CLAUDE.md` for
why this must never be re-exported.

**Known-bad seeds** (all this same bug — the reported normal is an exact small-integer
ratio, which is the signature; real terrain slopes are irrational):

| seed | world_x | reported floor normal | ratio |
|---|---|---|---|
| 941462462 | 175,552 | (0.169391, -0.985549) | 11/64 |
| 2160065702 | 226,800 / 237,919 | (0.338199, -0.941075) | 23/64 |
| 3188032853 | 264,063 / 294,719 | (0.242536, -0.970143) | — |

Log any new seed that triggers `FREEZE_REPRO` here, with a one-line description,
before fixing it.

**Harness rationale**: `freeze_replay_runner.gd` alone is not sufficient — it replays
from spawn with no input, and a 60,000-frame no-input replay of seed 941462462 passes
even with the fix disabled. The real reproduction needed a warp plus a jump schedule.
The harness that actually finds stalls is `freeze_search.gd`, which sweeps sub-pixel
start phases × input schedules at a target world_x. Both of those harnesses need a
physics reproduction to find a *geometry* bug; `terrain_invariant_check.gd` is a much
faster, physics-free gate for pure terrain-shape bugs (a face steeper than
`floor_max_angle`, a discontinuous seam) — this is what should have caught the 80.4°
`large_valley` face (below) on day one instead of day seven.

## Bug 2: `large_valley` wall-stall (real terrain geometry, not float precision)

A **second, distinct** stall class was found and fixed separately (`fd59c53`):
`large_valley`'s drop face used to be steep enough (80.4°) to exceed `floor_max_angle`,
so the physics engine treated it as a wall and the player wedged at the lip instead of
riding or launching off it. Confirmed by 1px-resolution height sampling — real terrain
geometry, not a precision artifact.

`Player.update_stuck_detection()` was added as a second, independent watchdog
(alongside `recover_from_stall`'s per-frame one) for exactly this shape of bug:
jittering-in-place defeats a per-frame consecutive-stall predicate since no single
frame reads exactly 0, so it tracks **net** progress over a rolling window instead.
Measured at seed 222894852 / world_x 1,166,358: 600 frames, net progress 1.6px,
recoveries 0 from the per-frame watchdog alone — the net-progress watchdog is what
caught it.

## Terrain feature history

- **`large_valley` was removed entirely** (not re-tuned again after the 80.4° bug
  above). It was ~75 lines for a 180px valley with a flat floor — a marginal variant
  of `medium_valley`, which already exists and costs ~2 lines — and it was the
  **only** place in the file reading `Player.GRAVITY`, `SpeedManager.INITIAL_SPEED`,
  or `Engine.physics_ticks_per_second`. Removing it collapsed terrain's physics
  coupling to a single constant (`floor_max_angle`, used only by `mega_drop`) and
  deleted all four of its interacting minimum-length rules along with the
  `maxf`/`minf` trap that shipped the 80.4° face. `SEGMENT_TIER_LARGE` is gone with
  it; tier is now just SMALL/MEDIUM.
- Removing `large_valley` also removed a scene-graph hazard: it was the only feature
  that additionally cached `player.floor_snap_length` at `TerrainGenerator._ready()`,
  which made sibling order between `Player` and `TerrainGenerator` in `main.tscn`
  load-bearing (reordering fed it Godot's default instead of
  `Player.FLOOR_SNAP_LENGTH`). With `large_valley` gone, that specific path no longer
  exists, but a new feature reading `player.*` at `_ready()` should still be checked
  for the same hazard.
- **`mega_drop` was collapsed from 4 linear segments to 1 eased segment.** The old
  version was joined by `is_mega_drop_segment`/`is_mega_drop_start_segment` mutual
  recursion (4× a lookup that itself recursed 3 segments back — a measured frame-time
  spike) and was *linear*, butted directly against neighbouring curves that end at
  slope 0: an instantaneous ~40° kink at both entry and exit, the only slope
  discontinuity in the world, and the likely source of a perceived "jumpy" feel
  distinct from the freeze bugs above. It's now one segment using the same
  ease-in/out profile (`get_transition_profile`) every other feature uses, at length
  `(TOTAL_VERTICAL_DROP * PI) / (2 * tan(peak_angle))` — same 1080px total drop, same
  ~40.5° peak angle, but eased in and out to slope 0 like everything else.
  `get_mega_drop_length()`/`get_mega_drop_angle()` are the only surviving
  mega_drop-specific functions.
- Dead obstacle-spawning code was deleted outright (see "Dead / disabled code" in
  `CLAUDE.md`) rather than left commented out.

## Verification (`is_on_floor()` flicker fix, cross-checked against this bug)

`terrain_invariant_check` PASS on 8 seeds; `freeze_search` 0 stalls on all 3
known-bad seeds; 60,000-frame replay `status=no_freeze`, 0 stall recoveries — run as
part of verifying the unrelated `is_on_floor()` flicker fix (see
`docs/research/floor_flicker.md`), included here since it's the standing regression
bar for any player-physics change.
