# The X-precision cliff — measured, 2026-08-24

`world_rebaser.gd` rebases Y only, and its header has always carried a note that X precision
"does eventually degrade too". Nothing had ever measured it, and the numbers in that note were
wrong. This is the measurement.

**Conclusion up front: clean through 2^21. Three seeds, 55 minutes of continuous play each,
reaching x ≈ 2.43 M, zero stall recoveries and zero freezes. No X rebase is justified, and
this should not be treated as an open risk below ~90 minutes of unbroken play.**

## What the old comment said, and why it was wrong

> "X precision does eventually degrade too, but only around x ~ 1e6 (~33 minutes of play)"

Two errors.

**1. "x ~ 1e6" is the wrong shape of number.** float32 resolution is a step function that
halves at each power of two. Nothing happens at 1e6; it is an unremarkable point inside the
band that runs from 2^19 to 2^20. The only thresholds that exist are the powers of two:

| threshold | ulp | reached at | physics frame |
|---|---|---|---|
| 2^19 = 524,288 | 0.0625 px | 12.1 min | 43,408 |
| **2^20 = 1,048,576** | **0.125 px** | **23.7 min** | 85,351 |
| 2^21 = 2,097,152 | 0.25 px | 47.0 min | 169,238 |
| 2^22 = 4,194,304 | 0.5 px | 93.6 min | 337,010 |

**2. "~33 minutes" was wrong outright.** Integrating the shipped `SpeedManager` ramp
(100→500 over 10 s, 500→750 over the next 110 s, then flat) puts the first real step down at
**23.7 min**, not 33. 33 minutes is x ≈ 1.5e6 — mid-band, not a boundary. The old line paired
a time from one band with a distance from another.

Times ignore slope, so they are upper bounds on x and therefore *lower* bounds on when each
threshold arrives. Measured against the real thing: at frame 130,000 the runs below reached
x ≈ 1,570,700 versus a no-slope prediction of 1,606,686 — slope costs ~2%.

## Why the mechanism is live in principle

The original freeze (see `freeze_bug.md`) was a bad contact **separation direction**, not a bad
chord. Separations are of order `safe_margin` (1.0 px) and below, so the angular error is
`atan(ulp / separation)`:

| \|x\| | ulp | sep 1.0 px | sep 0.5 px | sep 0.25 px |
|---|---|---|---|---|
| 226,000 (Y-era freeze) | 0.0156 | 0.9° | 1.8° | 3.6° |
| 2^20 = 1,048,576 | 0.125 | 3.6° | 7.1° | **14.0°** |
| 2^21 = 2,097,152 | 0.25 | 7.1° | **14.0°** | **26.6°** |
| 2^22 = 4,194,304 | 0.5 | 14.0° | 26.6° | **45.0°** |

For scale, the recorded freeze normals were 11/64 and 23/64 — **9.9°** and **21.1°** off
vertical. `floor_max_angle` is 45°.

So this is a **probabilistic cliff, not a hard one**: the error is large enough to matter from
2^20 onward, but only if the terrain actually presents sub-pixel separations there. That is
why analysis alone could not settle it and why the soak below was needed.

## What was measured

### The one historical data point was a red herring

`player.gd` and `freeze_bug.md` both record a net-progress stall at **seed 222894852 /
world_x 1,166,358** — past 2^20, which is what made it look like evidence for this cliff. It
is not. `freeze_bug.md` attributes it to **Bug 2, the `large_valley` 80.4° wall-stall**, which
was independently confirmed by 1 px height sampling and then removed from the generator
entirely.

Re-tested with `freeze_search` (the harness that actually finds stalls), shipping config,
against a low-x control with everything else identical:

```
freeze_search.gd -- --seed=222894852 --warp=1165000 --to=1168000 --phases=8 \
                    --phasestep=0.25 --scan=1 --trialframes=500 --rebase=1
```

| | x = 1.17 M | x = 165 k (control) |
|---|---|---|
| trials | 40 | 40 |
| trials with a STALL | **0** | **0** |
| near-stalling | 0 | 0 |
| max slide count (engine cap 4) | 2 | 2 |
| worst-trial min motion | 6.13 px | 8.55 px |

Both clean. The attribution to `large_valley` stands. **Do not cite world_x 1,166,358 as
evidence of an X-precision problem.**

(The min-motion difference is confounded — different x means different terrain, since terrain
is a pure function of x. It is not a precision signal. Ignore it.)

### The soak: 2^20 is clean

```
freeze_replay_runner.gd -- --seed=<s> --frames=130000 --runs=1
```

130,000 frames ≈ 36 min of continuous play, reaching x ≈ 1.571 M — 50% past 2^20, the whole
way through the 0.125 px band.

| seed | status | frames | stall_recoveries | final world_x |
|---|---|---|---|---|
| 941462462 | `no_freeze` | 130,000 | **0** | 1,570,699 |
| 683407368 | `no_freeze` | 130,000 | **0** | 1,570,299 |
| 2160065702 | `no_freeze` | 130,000 | **0** | 1,570,891 |

Note `stall_recoveries=0` is the strong part. A recovery would mean the watchdog had to
unwedge the player — a stall that happened and was papered over. There were none.

### The soak: 2^21 is clean too

`--frames=200000` ≈ 55.5 min of play, reaching x ≈ 2.428 M — 16% past 2^21, into the 0.25 px
band. This is the band that mattered most: it is where a 0.25 px separation quantises to
exactly 45°, i.e. `floor_max_angle`, so if the mechanism were going to bite anywhere reachable
it would be here.

| seed | status | frames | stall_recoveries | final world_x |
|---|---|---|---|---|
| 941462462 | `no_freeze` | 200,000 | **0** | 2,427,824 |
| 683407368 | `no_freeze` | 200,000 | **0** | 2,427,382 |
| 2160065702 | `no_freeze` | 200,000 | **0** | 2,428,061 |

Clean. **The cliff is not reachable in any realistic session.** 2^22 (0.5 px) needs 94 minutes
of unbroken play in a single run, which no death, chasm or app-switch may interrupt.

### Side observation: the replay is not bit-deterministic

The 200,000-frame runs pass through frame 130,000, so they can be compared against the
130,000-frame runs at the identical frame — same seed, same code (only comments changed
between them), no input:

| seed | 130k run | 200k run @ frame 130,000 | Δ |
|---|---|---|---|
| 683407368 | 1,570,298.9 | 1,570,298.9 | 0 |
| 2160065702 | 1,570,891.0 | 1,570,895.1 | +4.1 px |
| 941462462 | 1,570,699.2 | 1,570,714.6 | +15.4 px |

Two of three drifted. The magnitude is trivial (1e-5 relative) and changes nothing about the
results above, but it is **methodologically relevant to the freeze work**: `freeze_search`
exists to sweep *sub-pixel* start phases, on the premise that sub-pixel position decides
whether a stall occurs. If the sim drifts run-to-run, a stall found at a given phase may not
reproduce at that phase.

`delta` is fixed at `1/physics_ticks_per_second` in Godot, so it is not a variable-timestep
effect; the likely candidate is contact or broadphase ordering in the solver. Two runs is not
enough to characterise it and the cause was not chased. Recorded as an observation, not a
finding.

### No gate reaches any of this

`freeze_replay_runner` at its 60,000-frame gate size stops at x ≈ 732,000 — inside the 2^19
band, one band short of 2^20. `floor_flicker_probe` at 20,000 frames covers 333 s. **A passing
gate has never been evidence about this cliff, and still isn't.** The soak is a manual
procedure, not a gate: at ~50 frames/s wall-clock it costs over an hour, which is the wrong
shape for something run per-commit.

## Consequences if it ever does bite

Better than the old comment implied. Both watchdogs — `Player.update_stall_recovery()` and
`Player.update_stuck_detection()` — are called **unconditionally** in `_physics_process`, with
no `OS.is_debug_build()` gate, so the backstop genuinely ships in a release export. The worst
case is a recoverable stall (net-progress watchdog fires after 60 frames, `recover_from_stall`
re-seats the body on the exact height field), not a hard freeze.

That is a ~1 s hitch in the world's scroll, not a dead game. Worth knowing before spending
anything large here.

## If a fix is ever needed, in cost order

**1. Raise `Player.safe_margin` (currently `1.0` in `main.tscn`).** The error is
`atan(ulp/separation)`, so this attacks the same ratio from the other side: doubling the
margin halves the angular error, buying a full power-of-two band ≈ 23 more minutes. One
number. But it is a real physics change and would need floor-flicker (3.5 h), freeze-search,
chasm and camera-shake re-runs, plus a check against the sub-pixel bounce known-issue.
**Untested — this is a hypothesis with a rationale, not a measured fix.**

**2. Full X rebase — costed, NOT recommended on current evidence.** It is the exact mirror of
the Y rebase and the architecture already supports the shape: `get_terrain_height()` is
generator-local, `get_surface_world_y()` is the one conversion. The catch is the asymmetry —
Y is only ever an *output*, so it needed one conversion point; X is the *input* to every
terrain query.

- **Spawn placement needs zero changes.** Every spawner already sets `.position` (local) equal
  to the logical `world_x`, and all six live under `TerrainGenerator`, so they ride the rebase
  for free and their arithmetic stays correct untouched. `coin_spawner.gd:320`'s magnet is
  global-to-global and also fine.
- **~44 reads of `player.global_position.x` across 17 files** must become a logical
  `player.world_x`. Each is a silent wrong answer if missed — a plausible height, not an
  error. Mechanical, and completeness is grep-provable, which is the one thing that makes it
  tractable: after the change no shipping file outside the camera path may contain
  `global_position.x`, and a small structural gate could hold that.
- **~8 cached x's** need shifting or re-expressing: `coin_spawner.run_start_world_x`,
  `FrozenLakeDirector.lake_start_x/lake_end_x`, `BiomeDirector.session_biome_phase` (a static
  that survives scene reload), `SkateTrack.points`, and the spawner schedules.
- **Two known traps.** `player.gd:654` (`recover_from_stall`) mixes both frames in three
  lines — it builds a global x, passes it to a logical query, and writes the result back to
  global. `glide_coin_spawner.gd:277` compares `player.global_position.x` against
  `coin.position.x`, which is already frame-mixing today and works only because the two frames
  currently coincide.
- **31 debug harnesses** warp to absolute world_x and would all need auditing. Recorded repro
  seeds stay valid — logical world_x is preserved exactly — which is the one saving grace.

## Status: closed

Measured through 2^21 and clean. **Do not reopen this without a reproduction.** If someone
reports a long-run stall, the things to check first, in order:

1. Is it actually past 2^21 (x > 2,097,152, i.e. >47 min in ONE run with no death)? Almost
   certainly not — check before assuming precision.
2. Did `stall_recoveries` / `STUCK_DETECTED` fire? If the watchdogs are silent it is not this.
3. Only then re-run the soak at `--frames=340000` (2^22, ~94 min play).

Not measured and not worth measuring speculatively: 2^22 and beyond.

## Also worth knowing

- **`get_terrain_height` was never at risk.** It is pure in `(session_seed, world_x)` and
  computed in GDScript `float`, which is **64-bit** — the terrain height field has no float32
  problem at any x. This cliff was only ever about the physics solver's float32 world
  transforms. Do not "fix" the generator.
- The 60,000-frame gate stops at x ≈ 732,000 and always will. That is fine now that this is
  closed, but it is the reason nobody should ever cite a passing gate as evidence about
  long-run behaviour.
