# OPUS5 — Aura review: the X-precision cliff (before & after) + every other finding

**Written for review by another AI.** Self-contained: every claim below names the command or
file:line that produced it, so you can re-run rather than trust me. Where something is
inferred or hypothesised rather than measured, it says so explicitly. Please challenge the
items in "Where I could be wrong" (§7).

**Two parts:**
- **§1–§10** — the X-precision cliff: the one thing I investigated end-to-end and fixed.
- **§11** — **everything else I found and did NOT fix.** This is the actionable list. One real
  bug, three design regressions, and a pile of hygiene. Start there if you're deciding what to
  change.

- **Date:** 2026-08-24
- **Repo:** Aura (Godot 4.7, GDScript, Mobile renderer), branch `main`
- **Scope of the change:** `scripts/systems/world_rebaser.gd`, **comments only — zero logic
  lines changed** (proof in §5)
- **Related docs I also wrote this session:** `docs/research/x_precision_cliff.md` (full
  measurement log), `docs/review/2026-08-24-code-and-repo-review.md` (broader repo review;
  this cliff was its finding #6)

---

## 1. What the code does, for context

`world_rebaser.gd` fixes a real, historical bug. Terrain baselines drift downward without
bound, so after a few minutes the collision surface sat tens of thousands of pixels below
y=0. Godot 2D physics uses **float32** for world transforms, so the representable step at the
contact point grows with |y|; contact separation vectors (of order `safe_margin` = 1.0 px)
lost directional resolution, `get_floor_normal()` returned off-vertical normals on provably
flat ground, the player's velocity was aimed into the ground, `move_and_slide()` exhausted
`max_slides`, and motion.x collapsed to 0 — a hard freeze.

The fix shifts the whole play area back toward y=0 periodically. **It rebases Y only.**

## 2. BEFORE — the claim under review

Verbatim from `git show HEAD:scripts/systems/world_rebaser.gd`, lines 27–31:

```
# ONLY Y IS REBASED. X is deliberately untouched so that
# TerrainGenerator.get_terrain_height(world_x) stays a pure function of
# (session_seed, world_x) and every recorded repro seed stays valid. X precision
# does eventually degrade too, but only around x ~ 1e6 (~33 minutes of play)
# versus y trouble by x ~ 226,000, so it is a separate, later concern.
```

So the codebase asserted an unmeasured, unguarded failure cliff at ~33 minutes of play, in an
**endless** runner whose own set pieces (frozen lake at 20 min cumulative playtime, a planned
aurora at 60 min) reward long sessions. I flagged this as the repo's most plausible
"disastrous later" item. The rest of this document is me trying to prove myself right, and
mostly failing.

## 3. What I measured

### 3a. The arithmetic in the comment is wrong, twice

Integrating the shipped `SpeedManager` ramp (`INITIAL_SPEED` 100 → `PHASE1_TARGET_SPEED` 500
over 10 s, → `MAX_SPEED` 750 over the next 110 s, then flat) at the pinned 60 Hz tick:

| threshold | float32 ulp | reached at | physics frame |
|---|---|---|---|
| 2^19 = 524,288 | 0.0625 px | 12.1 min | 43,408 |
| **2^20 = 1,048,576** | **0.125 px** | **23.7 min** | 85,351 |
| 2^21 = 2,097,152 | 0.25 px | 47.0 min | 169,238 |
| 2^22 = 4,194,304 | 0.5 px | 93.6 min | 337,010 |

Two errors:

1. **"~33 minutes" is wrong.** The first real degradation is at **23.7 min**. 33 minutes
   corresponds to x ≈ 1.5e6, which is mid-band.
2. **"x ~ 1e6" is the wrong *shape* of number.** float32 resolution is a step function that
   halves at powers of two. Nothing happens at 1e6; it's an unremarkable point inside the
   2^19→2^20 band. Only powers of two are thresholds.

These are upper bounds on x (they ignore slope, which shortens x-advance), so they are
**lower** bounds on when each threshold arrives — the conservative direction. Validated
against reality: at frame 130,000 the runs reached x ≈ 1,570,700 vs a no-slope prediction of
1,606,686, i.e. slope costs ~2%.

### 3b. Is the mechanism live in principle? Yes, probabilistically

The freeze was a bad contact **separation** direction. Separations are of order `safe_margin`
(1.0 px) and below, so angular error = `atan(ulp / separation)`:

| \|x\| | ulp | sep 1.0 px | sep 0.5 px | sep 0.25 px |
|---|---|---|---|---|
| 226,000 (the Y-era freeze) | 0.0156 | 0.9° | 1.8° | 3.6° |
| 2^20 | 0.125 | 3.6° | 7.1° | **14.0°** |
| 2^21 | 0.25 | 7.1° | **14.0°** | **26.6°** |
| 2^22 | 0.5 | 14.0° | 26.6° | **45.0°** |

For scale: the recorded freeze normals were 11/64 and 23/64 = **9.9°** and **21.1°** off
vertical; `floor_max_angle` is 45°. So the error is large enough to matter from 2^20 onward,
**but only if terrain actually presents sub-pixel separations there.** Analysis alone can't
settle it. Hence the soaks.

### 3c. The one piece of historical "evidence" is a red herring

`player.gd:666` and `freeze_bug.md:73` both record a net-progress stall at **seed 222894852 /
world_x 1,166,358** — past 2^20, which is what made it look like precision. It isn't.
`freeze_bug.md` attributes it to **Bug 2, the `large_valley` 80.4° wall-stall**, confirmed by
1 px height sampling and since removed from the generator entirely.

Re-tested with `freeze_search` (the project's own note says replay alone is insufficient;
this is the harness that actually finds stalls), against a low-x control, everything else
identical:

```bash
Godot --headless --path . --script res://scripts/debug/freeze_search.gd -- \
  --seed=222894852 --warp=1165000 --to=1168000 --phases=8 --phasestep=0.25 \
  --scan=1 --trialframes=500 --rebase=1
# control: --warp=165000 --to=168000
```

| | x = 1.17 M | x = 165 k (control) |
|---|---|---|
| trials | 40 | 40 |
| trials with a STALL | **0** | **0** |
| near-stalling | 0 | 0 |
| max slide count (engine cap 4) | 2 | 2 |
| worst-trial min motion | 6.13 px | 8.55 px |

Both clean; the `large_valley` attribution stands. **The min-motion difference is confounded**
— different x means different terrain, since terrain is a pure function of x — so I am
explicitly *not* reading it as a precision signal.

### 3d. The soaks — the actual test

```bash
Godot --headless --path . --script res://scripts/debug/freeze_replay_runner.gd -- \
  --seed=<s> --frames=<n> --runs=1
```

This harness disables obstacles, powerups and chasms (otherwise a death pauses the tree and
every number becomes meaningless), steps physics from spawn with no input, and reports
`no_freeze` / `stall_recovered` / `freeze_detected` / `tree_paused`.

| soak | play time | reached x | seeds | result |
|---|---|---|---|---|
| 130,000 frames | 36 min | 1.571 M (past 2^20) | 941462462, 683407368, 2160065702 | **3/3 `no_freeze`, `stall_recoveries=0`** |
| 200,000 frames | 55 min | 2.428 M (past 2^21) | same three | **3/3 `no_freeze`, `stall_recoveries=0`** |

`stall_recoveries=0` is the load-bearing part: a nonzero count would mean a stall *did* happen
and the watchdog papered over it. There were none.

2^21 is the band that mattered — per §3b it's where a 0.25 px separation quantises to exactly
`floor_max_angle`. Clean. The next band (2^22) requires **94 minutes of unbroken play in a
single run**, uninterrupted by any death, chasm or app-switch.

### 3e. Consequences are milder than assumed anyway

Both watchdogs — `Player.update_stall_recovery()` and `Player.update_stuck_detection()` — are
called **unconditionally** in `_physics_process`, with no `OS.is_debug_build()` gate. I
checked this specifically because many other debug facilities in this file *are* gated. So the
backstop genuinely ships in a release export, and the worst case is a recoverable ~1 s hitch,
not a dead game.

### 3f. `get_terrain_height` was never at risk

It's pure in `(session_seed, world_x)` and computed in GDScript `float`, which is **64-bit**.
The codebase confirms this itself at `terrain_generator.gd:1328` ("Dictionary of GDScript
floats (doubles), never a Vector2: Vector2 is float32…"). Only the physics solver's float32
world transforms were ever exposed. **A reviewer should push back on anyone proposing to
"fix" the generator.**

## 4. AFTER — what changed

`scripts/systems/world_rebaser.gd` grew from 52 to 96 lines. The 5-line claim in §2 was
replaced with a block that:

1. States the real thresholds as powers of two, with times and frame numbers (§3a table).
2. Explains why "x ~ 1e6" is the wrong shape of number.
3. Records the measured result: clean through 2^21, three seeds, `stall_recoveries=0`.
4. Says **do not rebase X**, and why, with the cost (§6).
5. Warns that no gate reaches any of this — the 60,000-frame gate stops at x ≈ 732,000,
   inside the 2^19 band, one band short of even 2^20 — so a passing gate is never evidence
   about long-run behaviour.
6. Notes `get_terrain_height` is float64 and must not be "fixed".

## 5. Proof that no logic changed

```bash
$ git diff -U0 scripts/systems/world_rebaser.gd \
    | grep '^[+-]' | grep -v '^[+-][+-]' \
    | grep -v '^[+-][[:space:]]*#' | grep -v '^[+-][[:space:]]*$'
(no output)
```

Every added/removed line is a comment or blank. `shipping_values_check.gd` re-run after the
edit: **PASS** (16 knobs at shipping values, scene clean).

Other gates run this session, all **PASS**: `biome_schedule_check.gd`,
`terrain_invariant_check.gd --seeds=8 --to=300000` (0 violations, max slope 20.13°, 8/8 seeds).

## 6. What I deliberately did NOT build, and the costing

A full X rebase is the exact mirror of the Y one, and the architecture already supports the
shape (`get_terrain_height()` is generator-local; `get_surface_world_y()` is the one
conversion). I costed it and recommend **against** it:

- **Spawn placement needs zero changes.** Every spawner already sets `.position` (local) equal
  to the logical `world_x`, and all six live under `TerrainGenerator`, so they'd ride the
  rebase for free. `coin_spawner.gd:320`'s magnet is global-to-global and also fine.
- **~44 reads of `player.global_position.x` across 17 files** would have to become a logical
  `player.world_x`. Each is a *silent* wrong answer if missed — a plausible height, not an
  error.
- **~8 cached x's** would need shifting: `coin_spawner.run_start_world_x`,
  `FrozenLakeDirector.lake_start_x/lake_end_x`, `BiomeDirector.session_biome_phase` (a static
  surviving scene reload), `SkateTrack.points`, spawner schedules.
- **Two known frame-mixing traps.** `player.gd:654` (`recover_from_stall`) builds a global x,
  passes it to a logical query, and writes the result back to global — all in three lines.
  `glide_coin_spawner.gd:277` compares `player.global_position.x` against `coin.position.x`
  and is *already* frame-mixing today, working only because the two frames coincide.
- **31 debug harnesses** warp to absolute world_x and would need auditing.

Asymmetry that drives the cost: Y is only ever an **output** (one conversion point); X is the
**input** to every terrain query.

**Cheaper lever if a fix is ever needed:** error is `atan(ulp/separation)`, so raising
`Player.safe_margin` (currently `1.0` in `main.tscn`) attacks the same ratio from the other
side — doubling it halves the angular error, buying a full power-of-two band ≈ 23 min. One
number, but a real physics change needing floor-flicker (3.5 h), freeze-search, chasm and
camera-shake re-runs. **Untested — a hypothesis with a rationale, not a measured fix.**

## 7. Where I could be wrong — please check these

1. **Three seeds is a small sample.** All three are seeds already known to the project. A
   reviewer could reasonably argue for random seeds, or more of them.
2. **The soaks apply no input** (`freeze_replay_runner` replays from spawn with no jumps). The
   project's own `freeze_bug.md` says the original freeze *needed* a jump schedule to
   reproduce and that replay alone was insufficient. I partly compensated with `freeze_search`
   (which does sweep input patterns) at 1.17 M — but **not** at 2^21. **This is the biggest
   gap in my evidence.** A `freeze_search --warp` run in the 2^21 band would close it.
3. **Chasms/obstacles/powerups are disabled** in the soak, as the harness requires. So the
   soaks test terrain/collision only, not the full game.
4. **The `safe_margin` lever is unverified.** I reason that a larger margin means larger
   separations, hence smaller `atan(ulp/sep)`. I have not confirmed Godot's solver actually
   uses `safe_margin` that way. Treat as hypothesis.
5. **I assume float32 for Godot 2D world transforms** (standard builds; `Vector2` is float32).
   Correct as far as I know and consistent with the codebase's own comments, but I did not
   read engine source.
6. **Non-determinism (below) means a single clean soak isn't a proof of universal safety** —
   it's evidence, not a guarantee.

## 8. Side finding — the replay is not bit-deterministic

The 200,000-frame runs pass through frame 130,000, so they can be compared against the
130,000-frame runs at the identical frame: same seed, same code (only comments changed
between them), no input.

| seed | 130k run | 200k run @ frame 130,000 | Δ |
|---|---|---|---|
| 683407368 | 1,570,298.9 | 1,570,298.9 | 0 |
| 2160065702 | 1,570,891.0 | 1,570,895.1 | +4.1 px |
| 941462462 | 1,570,699.2 | 1,570,714.6 | +15.4 px |

Two of three drifted. Magnitude is trivial (~1e-5 relative) and changes nothing above, but it
is **methodologically relevant**: `freeze_search` exists to sweep *sub-pixel* start phases, on
the premise that sub-pixel position decides whether a stall occurs. If the sim drifts
run-to-run, a stall found at a given phase may not reproduce at that phase.

`delta` is fixed at `1/physics_ticks_per_second` in Godot, so it is not a variable-timestep
effect. Likely candidate is contact or broadphase ordering in the solver. Two runs is not
enough to characterise it; cause not chased. **Recorded as an observation, not a finding.**

## 9. Process errors I made, for calibration

- I initially piped the soaks through `| tail -40`, which buffered all progress output and
  left me blind to how far they'd got. Fixed on the second run (no pipe + `caffeinate -i`).
- I misdiagnosed a 3h30m-elapsed / 3m43s-CPU reading as evidence that the project's documented
  "probe-runtime mystery" (`debugging.md`) generalised beyond `floor_flicker_probe`. **It was
  the user's Mac sleeping.** I retracted it; that mystery is untouched by my work. A reviewer
  should ignore any table I produced on that topic.
- I killed the first soak set believing they were mid-run; they had in fact already completed.
  No data was lost, but my progress estimate at the time was unfounded.

## 10. Verdict

The cliff was **real in principle and not reachable in practice.** The code needed no change;
the documentation did. Recommend: keep the comment fix, keep
`docs/research/x_precision_cliff.md` as the closed investigation, do **not** build the X
rebase, and close finding #6 of the review.

Highest-value follow-up if anyone wants more confidence: a `freeze_search` sweep in the 2^21
band (gap #2 in §7). Highest-value follow-up overall is unrelated to this file — finding #1 of
`docs/review/2026-08-24-code-and-repo-review.md`, a genuine playtime double-count bug that
makes the frozen lake fire early.

---

# §11 — Everything else I found (NOT fixed — this is the change list)

Same rules: file:line for everything, and I say when something is measured vs inferred.
Nothing in this section has been touched. Full versions in
`docs/review/2026-08-24-code-and-repo-review.md`.

## P0-1 — REAL BUG: pausing inflates cumulative playtime, so the frozen lake fires early

**The only outright logic bug I found.** `frozen_lake_director.gd:174`:

```gdscript
return services.save_store.total_playtime_seconds + main_node.elapsed_time
```

`GameManager.bank_playtime()` (`game_manager.gd:401-418`) already folds the current run into
`save_store.total_playtime_seconds` on **every** `PLAYING → not-PLAYING` transition, and
advances `banked_run_seconds` to match. It is correct in isolation. The lake director doesn't
know about it and adds the whole of `main.elapsed_time` a second time.

Walk it through: pause at t=120s → `total_playtime_seconds += 120`, `banked_run_seconds = 120`.
Resume, reach t=200s → director computes `base + 120 + 200` instead of `base + 200`.
**Every pause adds phantom playtime equal to elapsed-at-pause, compounding within one run.**

Worse on the shipping platform: `game_manager.gd:454` pauses on
`NOTIFICATION_APPLICATION_FOCUS_OUT`, so on Android *every notification or app-switch* pays it.
Pauses at 3/6/9 min credit +18 phantom minutes — enough alone to cross
`LAKE_INTERVAL_SECONDS = 1200` (20 min). A set piece meant to be rare can fire in one run.

**Fix:** subtract the already-banked part —
`total_playtime_seconds + (main.elapsed_time - game_manager.banked_run_seconds)`.
The director has no `GameManager` reference; prefer adding a `get_unbanked_seconds()` accessor
on `GameManager` over reaching in, so the arithmetic stays in the file that owns
`banked_run_seconds`. The planned aurora (build-order #12) gates on the same cumulative clock
and will inherit whichever call exists.

## P0-2 — `HANDOFF.md` actively misdirects the next session

It's the first file a new session reads. Its two load-bearing claims are false:

- `HANDOFF.md:209` — *"the background code … is still identical to `7ffd9f7` — nothing from
  this session has touched it."* Eight commits since the revert rewrote it. Verify:
  `git log 95d9ca4..HEAD -- scenes/main.tscn scripts/systems/background_*` → `56f704a`…`66ef080`.
- `HANDOFF.md:226` — *"None of this ships."* `assets/textures/experiments/` is **3.8 MB under
  `assets/`** with `.import` files generated, and `export_presets.cfg:11` is
  `export_filter="all_resources"`. It ships.

The whole document is written around `PineLine`, a node that no longer exists in `main.tscn`.

## P0-3 — Parallax depth was flattened; it's the thing the owner said was working

`scenes/main.tscn` vs `7ffd9f7`:

| Layer | was | now |
|---|---|---|
| FarPeaks | 0.030 | 0.015 |
| FarRidge | 0.060 | 0.025 |
| MidRidge | 0.140 | 0.035 |
| PineLine → IceStrip | 0.300 | 0.050 |

Near-to-far ratio **10:1 → 3.3:1**; fastest layer **6× slower**. `HANDOFF.md:17-18` records the
owner's words on what worked: *"the front layer moves faster than the ones behind it, so it
really does come together."* That separation is largely gone. **I can't tell whether this was
a deliberate re-tune for the panorama or drift across eight commits** — needs an explicit
decision. It's four numbers in `main.tscn`, not a code change.

## P0-4 — The panorama repeats every ~55 s, on the frontmost layer

`assets/textures/background/ice_pano.png` is 3548×887. At the scene's
`skyline_y_fraction 0.33` / `horizon_y_fraction 0.55` and a 648 px viewport,
`display_scale` = 0.577 → `motion_mirroring.x` = 2048 layer-px. At `motion_scale 0.05` that's
**40,956 world px ≈ 55 s at MAX_SPEED** (82 s at 500 px/s). Viewport is 1152 px wide, so
**56% of the panorama is on screen at once** — the repeat is not subtle, on the largest,
sharpest, most silhouetted background element. Biome cycle is 75,000 px, so it loops ~1.8×
per biome. The three procedural layers never repeat (hash-driven), so moving the panorama
frontmost traded non-repeating for repeating on the most visible layer.

Options cheapest-first: raise `motion_scale` (also helps P0-3, but shortens the loop in
*time*); bake a wider strip; or accept and document. **Do not** add a second offset sprite —
`ParallaxLayer.motion_mirroring` is one span by construction and a second copy reintroduces
the tear that `centered = false` exists to prevent (`background_strip.gd`).

## P1-5 — `biome_schedule_check` no longer measures what the scene renders

`BiomePalette.get_scenery_color(depth_t)` lerps `scenery_far → scenery_near`. Scene `depth_t`
was `0.0 / 0.22 / 0.58 / 1.0`; it is now `0.0 / 0.15 / 0.30 / 0.45`. **`scenery_near` — the
darkest authored colour in all nine palettes — is never rendered.** Only the far 45% of each
ramp reaches the screen.

The gate (`biome_schedule_check.gd:225`) asserts
`|lum(scenery_far) − lum(scenery_near)| ≥ MIN_SCENERY_SEPARATION (0.08)`, *"or the parallax
layers collapse into one flat mass."* It measures the **authored endpoints**, so it cannot see
this. Measured shipped separation:

| palette | authored | shipped (0→0.45) |
|---|---|---|
| pale_morning | 0.223 | **0.100** |
| starlit_night | 0.257 | 0.116 |
| first_light | 0.262 | 0.118 |
| glacier_teal | 0.303 | 0.137 |
| sunset_rose | 0.367 | 0.165 |

Everything still clears the 0.08 floor, so **nothing is broken today** — but `pale_morning`
has 25% of its headroom left and the gate would keep passing all the way to collapse. Same
blind spot in `check_gameplay_contrast` (`:355`), which compares coin/obstacle colours against
a `scenery_near` that never appears.

**Fix:** have the gate read the real `depth_t` values out of `main.tscn` and evaluate
`get_scenery_color` at the extremes the scene actually uses.

## P1-6 — Segment caches grow all run and are never pruned

`segment_start_x_cache`, `segment_length_cache`, `segment_baseline_cache`, `segment_spec_cache`
(`terrain_generator.gd:110-113`) only gain entries. `chunk_collision_sample_xs` *is* pruned
(`prune_chunk_collision_samples`, radius 10) — these four aren't. ~1.3 segments/s → ~4,700
entries/hour plus a 6-key `Dictionary` each.

**Weak evidence it's not urgent:** six soaks of 36–55 min each completed at a steady 75
frames/s to the end, no slowdown, no failure. I did **not** measure memory. Do that before
acting. **Do not add pruning casually** — `arm_lake()`'s write-ahead rule and deterministic
replay of recorded seeds both depend on cached history remaining available.

## P1-7 — `main.gd` depends on tree order with nothing enforcing it

`main.gd:221` — *"Runs before Player/TerrainGenerator (tree order)"* — is a correctness
requirement for `apply_world_rebase()`, with no `process_priority` behind it. A scene reorder
that looks cosmetic silently changes rebase and camera timing. Same class as the
`@export`-serialised `world_rebase_enabled` regression the file warns about twice. Encoding it
is cheap, but it's a behaviour change: re-run camera/freeze/floor/chasm gates.

## P2 — hygiene and dead weight

**Git state.** Local `main` is **16 commits ahead** of `origin/main` (`7ffd9f7`); GitHub has
none of the background work. Tree also holds 15 tracked art deletions whose byte-identical
copies are untracked in `art_source/terrain/` and `art_source/background/` — **a bare
`git add -u` would record the deletions and lose the new locations.** `origin` still carries a
dead branch `terrain/disable-mega-drop-camera-shake` at the same commit as `main`.

**Debug + experiments ship.** `export_filter="all_resources"` packages every imported resource:
`assets/textures/experiments/` (3.8 MB) and `scripts/debug/` (636 KB, 31 files incl. all 18
archived probes). Needs separate dev/release presets or an exclude filter, plus a check that
fails a release build containing `scripts/debug`, `scripts/experiments`, or
`assets/textures/experiments`.

**Android export is not release-shaped.** `package/unique_name = "com.example.$genname"`,
`version/code = 1` with empty `version/name`, no launcher icons, `export_format = 0` (APK, not
AAB), empty `min_sdk`/`target_sdk`. Root `aura.apk` is from 2026-08-03 — before all 16 unpushed
commits — and is not a current deliverable.

**`scripts/tools/build_iceberg_sprites.py` is dead.** 31 KB, committed `deb8677`, writes to
`assets/textures/background/iceberg_*.png` — none exist. Its documented example input
`art_source/berg_shelf_01.png` doesn't exist either. Approach abandoned two commits later for
the panorama strip. It reads authoritative and will mislead someone.

**Stale doc/comment locations, all verified:**

| location | what's stale |
|---|---|
| `docs/development/architecture.md:12` | lists `FarPeaks/FarRidge/MidRidge/PineLine`, no `IceStrip` |
| `docs/development/visuals.md:24-32` | draw-order table has old `0.30/0.14/0.06/0.03` + `PineLine`; `:165`,`:176` reason from them |
| `docs/development/visuals.md:285` | pre-split `art_source/three.png` |
| `docs/development/dead_code.md:36` | "four layers, `motion_scale.x` 0.03 to 0.3" |
| `scripts/systems/background_strip.gd:7` | calls the panorama "the far layer"; it's frontmost at `depth_t 0.45` |
| `scripts/systems/background_strip.gd:51` | reasons from `motion_scale 0.03`; scene uses `0.05` |
| `scripts/tools/build_pano_strip.py` | calibration prose assumes the strip sits at `depth_t 0.0` |
| `scripts/tools/build_ice_texture.py:5` | example uses `art_source/three.png` |
| `art_source/README.md` | describes the pre-split flat layout |
| `.claude/settings.local.json` | allowlists `mega_drop_visual_probe.gd` (now in `archive/`) and a root `thirteen.png` that doesn't exist |

**Small cruft.** Orphaned `art_source/peep.png.import` and
`art_source/transition4peep.png.import` (source PNGs gone; `art_source/.gdignore` means Godot
shouldn't generate them there anyway).
`art_source/ChatGPT Image Aug 6, 2026, 07_13_24 PM.png` needs a real name. `project.godot`
carries `3d/physics_engine="Jolt Physics"` and `rendering_device/driver.windows="d3d12"` in a
2D mobile game — harmless, but noise in an otherwise curated file.

**The pause screen's Music slider does nothing audible.** The `Music` bus exists
(`audio/default_bus_layout.tres`) and `GameServices` creates a `music_player`, but **no stream
is assigned anywhere in the project** — `sfx_player.gd:91` is the only `.stream` write. A
player will drag it, hear nothing, and read it as broken. Hide or label it until music ships.

**Comment ratio.** 10,767 shipping GDScript lines, 4,541 comments (**42%**). The comments are
unusually good and mostly record measurements — but P0-2/P0-3/P0-4 and
`background_strip.gd`'s header are the failure mode: narrative duplicated next to code drifts
faster than it's maintained.

## Verified healthy — checked, no action needed

- All `res://` references resolve; no orphaned `.uid`; all 9 ice tiles referenced by a palette.
- Every spawner correctly defers seed-derived init to the first `_physics_process` — the
  documented `_ready()` seed trap is not present anywhere.
- The six spawner hash functions use genuinely distinct multiplier pairs; no cross-system
  correlation. `background_generator` keys off `rng_salt`, not `session_seed`, so its shared
  multipliers with `terrain_generator` are harmless. (I suspected a collision here and was
  wrong — verified, it's fine.)
- `SkateTrack` and `SkateSpray` both handle world rebasing explicitly despite sitting outside
  the `TerrainGenerator` subtree.
- Celestial discs sit at y-fraction 0.08–0.09; ice strip skyline is 0.33, tallest ridge ~0.20.
  The "There has to BE a sky" occlusion bug has **not** regressed.
- `project.godot` clean in `git status` — no stray editor rewrite.

## Suggested order

1. **P0-1** (playtime double-count) — smallest diff, real gameplay impact, aurora inherits it.
2. **P0-3 / P0-4** — owner decision first; both are `main.tscn` numbers, not code.
3. **P0-2** — rewrite or retire `HANDOFF.md`, then one sweep over the stale table above.
4. Commit the art relocation deliberately (not `git add -u`), then push the 16 commits.
5. Release preset + export-content check.
6. **P1-5** (gate reads real `depth_t`), then **P1-7** (process priorities).
7. **P1-6** — measure memory before touching; read the warning first.
