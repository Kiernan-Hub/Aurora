# Aurora borealis

The feature the game is named after, build-order #12. A rare, calm, 61-second set piece: the
hazards stand down, the sky fills with light, the world and the ice catch it, and the skater lifts
once at the crest. **This file is the current state.** Every plan, slice record and superseded
design that led here is in `docs/research/aurora_borealis.md` — history, not required reading.

## Status — 2026-09-20

| | |
|---|---|
| Lifecycle, reservation, flight, camera, save, achievement | **Built, gated green.** `aurora_calm_probe` PASS, 182,974 assertions — now including the schedule and the night window |
| Look | Six owner review rounds (09-11 → 09-13). Blade glow **finished**; curtains keep their character |
| Left before ship | Restore the three TEMP knobs → `check.sh` 5/5 → the three windowed gates → a shipping-pace playtest → Android review → merge |
| Needs an owner decision | Wings reference image (rework blocked on it); bloom yes/no; brighter ice + softer smear reflection, or accept as-is |

**`art_source/aurora_reference/` (four owner-generated images) is the design authority for the
look.** Open it before answering a look question — it settled three separate wrong turns, each
argued for plausibly first.

## Owner decisions — do not re-litigate

| Question | Decision |
|---|---|
| Interval | **30 min** of cumulative playtime, as a **stored deadline** |
| Sky | **Night for the whole event** — blended `star_density` ≥ 0.8 |
| Run time | Only past **130 s** into a run (`MIN_RUN_TIME_SECONDS`, the lake's number) |
| Hazards | **Removed** for the duration — no obstacles, no chasms. Death is never disabled |
| Speed | No slowdown. Boost and glide cannot start inside the passage |
| Reach of the light | Sky → background → wash → ice. **Never coins, obstacles or the player** |
| Scenery response | **Darkens** into silhouette. Never green, never brighter |
| Wisps | Built, rejected ("terrible"), **removed** 2026-09-16. The concept was wrong, not the tuning |

## How it works

### The director — `aurora_director.gd`

One clock, one ramp. `Phase { IDLE, PENDING_ENTRY, ACTIVE, RECOVERY, DONE }`; `DONE` is terminal,
so at most one aurora per run (death also goes to `DONE`, and restart reloads the scene).
`get_aurora_blend()` is 8 s fade in, 45 s hold, 8 s fade out. **`push_blend()` is the only seam the
look arrives through**: every consumer exposes `apply_aurora(blend, elapsed)` and derives
everything from those two numbers — no private timers, so pause freezes all of it for free and
there is nothing to clean up on death.

It still is `GameManager.State.PLAYING` throughout; nothing here touches `get_tree().paused`.

### The schedule

```
due  <=>  run_time >= 130 s  and  saved_playtime + unbanked_this_run >= next_aurora_due_seconds
```

- **A stored deadline, never `(aurora_count + 1) × INTERVAL`.** The aurora arrived into saves
  already holding hours; a multiple would pay out a backlog, one aurora per run, until the count
  caught up. `aurora_count` is a statistic — anything reading it as a threshold re-creates that.
- **`-1.0` means unscheduled** and is not due. `0.0` would read as "due now". No version bump.
- Scheduled at load (or first IDLE after a shop reset) from the banked total; pushed on completion
  from `GameManager.get_total_playtime_seconds()` **after** banking. Using the bare banked field on
  completion writes a deadline already in the past after a long unpaused run.
- **The run-time gate is about the speed ramp**, not pacing: the flat is cut at `MAX_SPEED` but the
  event ends on a clock, so entering at t = 20 s leaves ~28,000 px of dead flat.
- **Preview knobs never touch progression.** Preview status latches at entry; a preview neither
  schedules, credits nor emits `aurora_finished`. The interval override is a read-side bypass in
  `is_aurora_due()` and deliberately sits above the run-time gate.

### The night gate, and what it does to rarity

`is_sky_ready()`: night now ≥ 0.8 **and** `BiomeDirector.get_minimum_night_ahead(61, SPEED_BOOST_SPEED)`
≥ 0.8 (endpoints plus every biome boundary; each transition is monotonic). Rechecked at entry.

**Measured, and now re-measured by `aurora_calm_probe` on every run** (`check_night_gate`, which
prints `AURORA_NIGHT_GATE`): with the eight-biome cycle at `MAX_SPEED` the gate is open for
**108.3 s of every 800 s** (~13.5%), identically in all eight rotations — a rotation moves the
entry point, not the arc. The one contiguous night band is **142,125 px** against a 61,000 px
lookahead. Combined with the 130 s run gate, a real sighting is likely well over 30 min apart for
a player with short runs. **Still not playtested.** If playtesting says too rare, the cheapest
lever is the lookahead speed — at `MAX_SPEED` instead of boost speed the window is ~129 s (boost
cannot be active *during* the event, but can be before entry, so check that first).

**That opening is one palette edit from closing, and nothing else would say so.** The check now
holds it inside a deliberately wide 30–300 s band: taking `twilight_blue` from 0.85 to 0.75 —
still a night band wide enough to fit the event — drops it to 20 s per cycle, and every other
gate stays green through that.

### The protected flat

`TerrainGenerator.arm_aurora_flat(length)` commits **one long flat segment** under the same
write-once, write-ahead deal as `arm_lake()`: beyond the watermark **and every sparsely cached
spec**, with a non-chasm neighbour on both sides, and it persists after the event. Choosing the
index never calls `get_segment_spec()`.

```
length = MAX_SPEED × 61 s + ENTRY_WAIT_DISTANCE (10,000) + 2 × recovery_distance
recovery_distance = max(2048, visible world width + 512)
```

- **Reserve** (IDLE, due + night, no armed/active lake): past every existing obstacle/powerup
  collision edge and the current view. Existing bodies are **never removed**.
- **PENDING_ENTRY**: wait until the player is `recovery_distance` into the flat, grounded, not
  jump-ascending, not boosting or gliding, with room for the whole event and no conflicting body
  ahead. Any failure → RECOVERY with no event (the reservation is spent; terrain cannot be un-armed).
- **ACTIVE**: fails closed to RECOVERY if the player leaves the flat or starts boost/glide.
- **Exclusion inside the flat**: `ObstacleSpawner` and `PowerupSpawner` skip placement within
  `AuroraDirector.BODY_CLEARANCE` of it (boost/glide pickups only); `PowerupManager.start_effect()`
  refuses boost/glide there, which also covers trick-earned boosts. Coins and other powerups run.
- **Lake arbitration**: an armed/active lake blocks reservation; `blocks_lake_arming()` (pending,
  active, recovery, or about to reserve) blocks the lake. Both deadlines stay due while deferred.

**Accepted costs — documented, not bugs.** A flat is always longer than its event: ~59,846 px
against ~45,750 px of presentation, so ~12 s of empty flat follows the fade. **`ENTRY_WAIT_DISTANCE`
is not slack**: the GLIDE sets its floor (7 s × 750 = 5,250 px, plus ~750 px because entry needs a
floor contact and a glide can expire at altitude), not the 3 s boost. Sizing it against the boost
argues for halving it, and that mistake has been made once. Undershooting skips the aurora *and*
still spends the reservation.

### Flight and camera

- **Crest flight** (Player state, not glide or a powerup): rise 27–32 s toward 96 px, release
  40–45 s, 260 px/s vertical cap, horizontal speed untouched, no collision bypass. Jumps and tricks
  are rejected during flight and the landing handoff (`is_aurora_flight_landing`); normal input
  resumes on the one real landing.
- **Camera** (`main.gd`, still the only camera writer): 1.055× zoom and terrain line lifted to 0.59
  of screen height, both on the blend. Glide has priority. Authored zoom captured in `_ready()`.

### The look, sky downward

| Layer | What it does | Owner |
|---|---|---|
| Curtains | Three additive bands, reveal right → left over 12 s, folds from `aurora_curtain.gdshader` | `sky_backdrop.gd` |
| Streaks | One ribbon every 7 s from t = 6 s, 1.15 s each, direction **alternates** | `aurora_streaks.gd` |
| Parallax layers | Darken toward cool silhouette, far/near split, slow breath | `background_generator.gd` statics, shared by `background_strip.gd` |
| Haze | Slightly greener, **alpha rises** 0.38 → 0.59 (cap 0.78) — this is what dissolves the ridge edge | `background_generator.gd` |
| Wash | Vertical gradient at `CanvasLayer -45`, ceiling 0.34, drifts and breathes | `aurora_wash.gd` |
| Snow | Density crests at 1.45× mid-event, inside the existing 126-flake pool | `snow_drift.gd` (sole owner) |
| Ice | Tint/gloss composed with biome and lake in `refresh_ice_appearance()` | `terrain_generator.gd` |
| Reflection | The sky mirrored into the ice, reusing the lake's shader | `aurora_reflection.gd` |
| Blade glow | Halo + core at the real contact point, grounded only. **Finished** | `aurora_blade_glow.gd` |
| Wings | Six feather lines, 20–51 s. Visible while grounded, in flight **or in the landing gap**. **Rework blocked** on the owner's reference | `aurora_wings.gd` |
| Ambience | 12 s generated loop on the Music bus, gain cap 0.55, pauses with the game | `aurora_audio.gd` |
| Achievement | `under_the_aurora`, granted by `AchievementManager` on `aurora_finished` | `achievement_manager.gd` |

Every visual consumer toggles `visible` rather than fading to alpha 0 — a hidden full-screen item
costs nothing, which is what keeps the reflection's backbuffer copy free for the other 29 minutes.
**A consumer that hides on `not is_on_floor()` must accept `is_aurora_flight_landing` too**: the
crest releases at t = 45 s and the wings run to t = 51 s, so without it they blink out for the
frames the body spends falling the last pixels back to the ice, in the middle of their own fade.
That was the wings' documented flicker, fixed 2026-09-20.

## The traps, all earned

1. **Reflection compression is derived per frame, never a constant.** The shader samples
   `waterline − depth × compression`, so the mirror runs out of frame at `waterline / compression`.
   A constant 3.0 left the lower quarter empty. Take the least squashed value that still fills:
   1.0 (a true mirror) whenever it fits. The ice line moves (camera ramp, `expand` per device).
2. **Curtain bands grow UP.** The hem sits at `AURORA_HEM_BASE` (0.84) of the rect from its top;
   growing a band downward hid all three hems behind the background layers. Keep hems at
   0.176 / 0.117 / 0.077, or re-measure *with the background present*.
3. **Scenery darkens.** Palettes tune `scenery_far` ≈ `sky_horizon`, so green or brighter ridges
   against a green sky meet as equal-brightness, different-hue masses — a seam. Dark against
   bright reads as intentional; every reference agrees.
4. **Check a hash over the range you consume.** Streak direction was 111/200 over many indices but
   7:1 over the only eight an encounter plays. It alternates now.
5. **Tree order is draw order.** `AuroraStreaks` must stay before `AuroraReflection` (so streaks are
   mirrored), and `AuroraReflection` before `AuroraBladeGlow` (the quad would eat the glow's lower
   half). Wash stays below layer 0 or it tints gameplay.
6. **Additive over a bright sky blows out** — which is why `debug_aurora_ignore_night` shows a
   composition the game never ships. Night bypass is for state flow, never for colour approval.
7. **Under additive blending no layer can remove sky blue**, so a fully saturated green is
   unreachable over these palettes. A greener aurora is a palette change, not a sky one.

## The headless contract

Every gate instantiates `main.tscn`, so all of this runs there.

- `AuroraDirector` **hard-skips headless as the first statement in `_ready()`** — its trigger reads
  the developer's own `save.dat`. Every consumer computes headless locally from
  `DisplayServer.get_name()`, never `Services.is_headless`.
- Dependencies are `get_node_or_null` + null-guarded; a missing one disables a layer, never the game.
- **No gate reaches any of it through the director's own `_ready()`.** `aurora_calm_probe` gets
  there by construction instead: it drives the lifecycle from an injected in-memory save and sets
  the lake's fields by hand (which is why `FrozenLakeDirector` looks the Aurora up in `try_arm()`,
  not `_ready()`), `check_schedule()` calls the deadline arithmetic directly, and
  `check_night_gate()` runs the real cycle maths on a **bare `BiomeDirector`** that is never added
  to the tree, so the headless early-return never happens. Visuals remain covered only by
  `sky_layer_check`, which needs a window.
- **A bare director still carries the TEMP knobs**, because they are plain vars read from source.
  `check_night_gate()` pins `debug_biome_seconds` to 0.0 for that reason: left at the committed
  review default of 10.0, `get_cycle_world_x()` stops reading the player at all and the lookahead
  reaches 457,000 px, which never clears — the check then reports a night opening of zero for
  every rotation. `make_case()` pins the same field on `ControlledNight`.

## Things that break silently

- **Debug knobs are plain `var`, never `@export`**, each with a `shipping_values_check` row in the
  same commit. The three TEMP defaults live in **source**, not `main.tscn`.
- **Never let a debug override reach the code that writes the persisted deadline.**
- **Achievement ids are save data** — renaming un-earns it for everyone.
- **`git status` after ANY engine run** — a settings save strips `project.godot` pins and scene
  properties; scene files have no gate.

## Open

- **Rarity at shipping pace** — measured above, never playtested. Wait for a natural aurora.
- **Android**: fill rate with the full event (curtains, wash, reflection backbuffer, snow) and
  speaker/headphone balance. Cannot be answered on desktop.
- **`sky_layer_check` is owed** on the curtain geometry and the streaks; its wisps assertions were
  removed with the wisps, and it has not been run since.
- **Music slider**: now visible, but the only thing on the Music bus is this bed — a player moving
  it outside an aurora hears nothing.
- **Bloom**: there is no `WorldEnvironment` in the project. It is the largest remaining glow lever,
  whole-screen and the Mobile renderer's most expensive feature — owner call, recommended no unless
  the look falls short without it.
