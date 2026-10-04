# Spike approach fairness (audit finding 1) — 2026-09-28

**Status: FIXED.** `ObstacleSpawner.is_footprint_legal()` has an APPROACH clause, and
`terrain_invariant_check` re-runs the fairness proof on the real ground of accepted placements
(`check_placed_pattern_fairness()`). Closed; read only if you are changing the guard, the fairness
model, the weakest jump or the spike's size.

## The hole

`check_pattern_fairness()` proves every `PATTERNS` row on **flat** ground. The footprint guard only
slope-checked each piece's own 32px, never the ground a jump leaves from. A spike on a short
level stretch at the top of a climb passed the guard, and the take-off ground sat below the
spike's base, making it effectively taller. The weakest jump (×0.60: apex 46px over a 32px
spike) has 14px to spare, and at 750 px/s a take-off happens 80–290px before the spike.

The audit's case: seed 683407368, spike at x=21060, a ~50px near-level blip between a
`medium_valley`'s climb out (−74px at 20725) and a `medium_hill_big`'s climb. Level-0 take-offs
leave from 8–70px below the spike's base.

## How common it was (terrain-aware model, before the fix)

Accepted placements through the game's own `find_legal_offset()`, 3 seeds, nominal x every
1000px to 150k. "Unbeatable" = no line survives at some level; "tight" = best window 1–6 frames.

| Pattern | Speed | Accepted | Unbeatable | Tight | Levels hit |
|---|---|---|---|---|---|
| spike | 750 | 0.90–0.95 | 19–26% | 11–14% | 0, 1, 2 |
| spike | 523 | 0.90–0.95 | 19–26% | 12–17% | 0, 1 |
| spike_floe, spike_shard, spike_spike | 750 | 0.28–0.41 | 4–22% | 20–49% | 0, 1, 2 |
| floe_spike, shard_spike, ice_spike, floe_spike_shard | 750 | 0.12–0.41 | 0 | 34–72% | — |
| floe, shard, ice_short, ice_long | 750 | 0.90–0.98 | 0 | 0 | — |

Roughly **one spike in five was unbeatable at jump level 0 or 1**, in the base game (`main` had the
same one-x slope rule). Stay-down pieces and thin ice were never affected.

## The model, checked against the live game

`get_pattern_takeoff_window()` given the height field: every piece sits at its own surface
height, stance and landing follow the ground. The live side is audit.md's harness (real Player,
collision, spawned spike, 48 tap frames × 4 sub-frame phases, 750 px/s), parameterised by seed/x.

| Position | Guard now | Model, level 0 | Live survivors per phase |
|---|---|---|---|
| 683407368 x=21060 (the audit's) | rejects | 0 | 0 (audit: 0/192; level 4: model 25, live 26/48) |
| 1811587497 x=7200 | rejects | 0 | 0 (level 4: model 25, live ≥25) |
| 2033395789 x=9200 | rejects | 0 | 0 |
| 1811587497 x=9950, 683407368 x=72000 (flats) | accepts | 9 | 12 |
| 1811587497 x=10800 (descent) | accepts | 19 | 22 |
| 1811587497 x=4850, x=26900 (foot of descents) | accepts | 25, 27 | ≥25 (tap range truncates) |

Never optimistic: every predicted 0 died live, and live windows are ≥ the model's. The model
uses the capsule's bounding rect and grows hazards 1px; the capsule's rounded corners are worth
~3 frames on a lone spike. Grounded speed on a slope is `v·cosθ`, slower than the model's `v`,
which only adds frames to a take-off zone.

## Candidate guards (spike, 3 seeds)

| Rule | Accepted | Unbeatable | Tight |
|---|---|---|---|
| none (old guard) | 0.90–0.95 | 26–36 per seed | 14–20 |
| **approach**: no sample over the weakest jump's reach before a spike more than *tol* below its base; tol 4, 750 | 0.66–0.72 | 0 | 0 |
| approach, tol 8, 750 | 0.70–0.75 | 0 | 0–3 |
| approach, tol 4, **523** | 0.68–0.74 | 0 | 0–1 |
| approach, **tol 2**, 523 | 0.66–0.72 | 0 | 0 |
| approach, tol 0, 523 | 0.58–0.64 | 0 | 0 |
| band: every sample over [span − 360, span] within ±6px of the base | 0.22–0.24 | 0 | 0–1 |

Chosen: approach, tol **2px**, reach = the weakest jump's flat airtime × speed (360px at 750).
The band rule starves placement, since a steady descent into a spike is fine but fails a
symmetric band. Why the reach needs only the weakest jump: a stronger jump from the same take-off
point is higher at every instant, so it clears whatever the weakest one cleared.

**Ruled out without building**, per the audit: lowering the 7-frame bar (hides the mismatch),
strengthening the starting jump (moves every chasm/coin reach bound), a runtime physics solver in
the game (heavy on phones), and flattening terrain under patterns (option B, a terrain change).

## The one pattern that still went tight

`floe_spike_shard` sat at **exactly 7** on flat at 1.0s (level 2 + powerup: the jump over the spike
is carried into the shard and must clear it). A shard 1.6px above level cost that frame. Flat
windows by shard time: 0.85→5, 0.90→6, 0.95→9, **1.0→7**, 1.05→8, **1.1→9**, 1.15→8, 1.2→9. Moved to
1.1s: 9 like every other combo, with 8 either side, where 0.95 sits between a 6 and a 7.

## Final numbers (8 seeds, 300k px, the gate's own sweep at 750 px/s)

| Pattern | Before | After |
|---|---|---|
| spike | ~0.90 | 0.64–0.71 |
| floe, shard | ~0.90 | 0.90–0.94 |
| ice_short, ice_long | ~0.96 | 0.95–0.98 |
| spike_floe, spike_shard | 0.24–0.35 | 0.19–0.25 |
| floe_spike, shard_spike | 0.24–0.35 | 0.17–0.22 |
| spike_spike | 0.24–0.35 | 0.087–0.134 |
| ice_spike | 0.24–0.35 | 0.13–0.19 |
| triples | 0.13–0.20 | 0.023–0.067 |

A combo that fails falls back to its first piece, so density holds and combo *variety* drops.
Floors moved to half the worst seed: 0.32 / 0.04 / 0.01. `--placed-step=10000` deep run over the
same 8 seeds: **2,383 accepted placements, every one ≥ 7 frames** at every level ± powerup, at the
pattern's slowest speed and 750.

## Cost

- **Gate:** `terrain_invariant` 36s → 56s. ~10s is the clause itself inside the acceptance sweep
  (31k forward searches); ~10s is `check_placed_pattern_fairness()` at step 40000 (~630
  placements × up to 20 cases; ~2.4ms a case, the arc stepping, not the height sampling).
- **Game:** `find_legal_offset()` per scheduling attempt, this Mac, ~290 attempts on one seed:

| Pattern | Before (mean / worst) | After |
|---|---|---|
| spike | 112µs / 0.56ms | 245µs / 0.75ms |
| spike_spike | 0.60ms / 5.0ms | 1.17ms / 5.8ms |
| spike_floe_spike | 0.92ms / 6.8ms | 1.48ms / 7.6ms |

The clause runs last in the guard and samples every 32px (terrain curvature hides at most ~0.5px
between samples; a medium valley's peak curvature is ~0.0035/px). A first version at 16px, run
second, cost 313µs / 2.3ms on the spike. **The combo search was already several ms at worst
before this**, since every rejected offset re-walks the whole span every 16px. That's a candidate
for the phone's unexplained late frames, unmeasured.

## Mutation tests of the gate (2 seeds)

- Clause disabled: `PLACED_PATTERN_UNFAIR spike … level 0 … 0 frames … no surviving input exists`.
- Model blind to terrain (`get_ground_height` returns 0): `PLACED_KNOWN_CASE … x=21060 … the model
  gives level 0 9 frames, expected an unfair one`.
- Tolerance 2 → 12px: `PLACED_PATTERN_UNFAIR spike … 4 frames`, `spike_spike … 4 frames`.
