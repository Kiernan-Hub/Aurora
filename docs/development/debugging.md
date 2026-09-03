# Debugging & regression harnesses

Reference doc for the exact commands and flags used to reproduce/regress physics and
terrain bugs. `CLAUDE.md` says *when* to run these; this file has the *how*. Rationale
and measured history for why each harness exists: `docs/research/freeze_bug.md`.

No test suite, no build script. Godot: `/Applications/Godot.app/Contents/MacOS/Godot`
(play with `--path .`, opens a window and blocks — only when asked).

## The fast five: `./scripts/check.sh`

One command, ~25s, the tier to run before every commit:

```bash
./scripts/check.sh          # quiet on PASS, full gate output on FAIL, exits non-zero
./scripts/check.sh -v       # print every gate's output either way
GODOT=/path/to/Godot ./scripts/check.sh
```

It runs `shipping_values_check`, `biome_schedule_check`, `terrain_invariant_check`
(`--seeds=8 --to=300000`, not tunable — a shortened run FAILs meaninglessly),
`lake_suppression_probe`, and the export-content check below. It runs **all five even
after one fails**, so a red run still gives you the whole picture. Mutation-tested
2026-08-25 by flipping `debug_chasm_disabled`: `shipping_values` and `terrain_invariant`
both caught it and the runner exited 1.

### `export_content` — what actually reaches a device

The fifth entry is not a Godot gate. It exports a pack headless
(`--export-pack Android`, ~2s) into a temp dir and fails if any of four paths survived
`export_presets.cfg`'s `exclude_filter`: `scripts/debug`, `scripts/experiments`,
`scenes/experiments`, `assets/textures/experiments`. Without the filter that is 636 KB of
probes and 3.8 MB of experiment textures on a player's phone. It reports the pack's
resource count on PASS (136 today) and deletes the pack either way.

Three things about it worth knowing before editing it:

- **The forbidden list is hardcoded, not read from `exclude_filter`.** Deriving it from
  the preset would make the check agree with the preset by construction — including when
  someone deletes a line from it, which is the regression worth catching. Mutation-tested
  2026-08-25 by blanking `exclude_filter`: 3 of the 4 paths appeared and the run went red
  (`scenes/experiments` doesn't exist in the repo, so it can't appear; it stays listed
  because it costs nothing).
- **The search is an unanchored byte search over the pack**, not a parse of its path
  table, so a merged `strings` line or a path embedded inside a resource still trips it.
  It errs toward failing on purpose. No shipping script embeds those literals today; if
  one ever legitimately needs to, that is the moment to write a real path-table parse.
- **`--export-pack` does not rewrite `project.godot`** — verified, and it is the only
  export form that doesn't. That is the only reason this can live in a runner at all.
  See "Engine commands that rewrite `project.godot`" below before running any other.

**The other two tiers stay manual, and cannot join this one.** The physics gates
(freeze-search, freeze-replay, floor-flicker, chasm, camera-shake) take minutes each; the
three visual gates (`sky_layer_check`, `ice_look_capture`, `biome_contact_sheet`) **must**
run without `--headless`, so no headless runner can ever include them.

**Project import is deliberately NOT in the runner.** The original reason — that `--editor`
strips the pinned physics settings — turned out to be wrong (measured 2026-08-26, see the
corrected table below). The decision stands on its remaining merits: import is slow, it is
needed only after adding a `class_name`, and keeping the ~25s runner free of any command that
*can* write to the project is worth more than the convenience. Import stays the manual step
below.

## Engine commands that rewrite `project.godot`

**This is wider than "the editor does it", which is how it was documented until
2026-08-25 and how it then bit a session.** These commands delete the pinned
`viewport_width`/`viewport_height`, `physics_ticks_per_second` and
`physics_interpolation`, along with **every explanatory comment in the file** — the only
record of why each setting exists.

**Corrected 2026-08-26 — the trigger is a project-setting *save*, not the command.** The table
below said `--editor` and the APK exports always rewrite the file. Measured on `4.7.stable`,
against this repo, on a throwaway copy — they do not:

| Command | Rewrites `project.godot`? |
|---|---|
| `--headless --editor --quit`, `.godot/` deleted first (full cold import) | **no** — byte-identical, measured 2026-08-26 |
| `--export-debug` (full signed APK) | **no** — byte-identical, measured 2026-08-26 |
| `--export-pack` (what `check.sh` uses) | no, verified |
| `--script` (every gate and probe) | no |
| **Anything that changes a project setting**, then saves | **YES — this is the real trigger** |

Neither run touched *any* tracked file, `main.tscn` and the experiment scenes included. So the
2026-08-25 and 2026-08-26 incidents were not caused by the commands themselves: both happened
during sessions that were *editing settings* (the icon and bundle id). Editing a setting through
the editor — or any `ProjectSettings.save()` — is what rewrites the file.

**The mechanism, confirmed:** Godot never persists a setting whose value equals the engine
default ([godot#83494](https://github.com/godotengine/godot/issues/83494)), and comments are
never preserved. All four pinned keys are pinned *at* their defaults, so all four vanish;
`quit_on_go_back`, `stretch/aspect` and `orientation` differ from theirs and survive. Reproduced
exactly by setting one unrelated key and calling `ProjectSettings.save()`:

```
- window/size/viewport_width=1152      - common/physics_ticks_per_second=60
- window/size/viewport_height=648      - common/physics_interpolation=false
  ...plus every explanatory comment in the file
```

**This does not make the pins safe — it makes the danger precise.** The four keys are invisible
in the file, so a stripped pin reads back identically and the day an engine default moves, level
geometry changes silently.

**Closed 2026-08-27: `shipping_values_check` now scans `project.godot` as text**
(`check_project_godot_declares_pins()`) and fails if any of the eight pinned keys is missing —
so the gate now covers both sides, the effective value *and* the declaration. Mutation-tested by
deleting the four default-equal pins: the runtime half still passed on all four (which is exactly
the hole), the text scan caught all four, exit 1; `--allow-temp` still downgrades to a warning.
`git status` after any engine run remains correct advice, but it is now cheap insurance rather
than the only line of defence.

**It is not only `project.godot` — these runs re-serialise SCENE files too, and drop authored
property values doing it.** Observed 2026-08-26: `scenes/experiments/background_pano_test.tscn`
came back rewritten with `uid=` fields added and **two authored values silently gone**
(`cycle_seconds = 20.0`, `current = true`). It was only an experiment scene, so nothing broke
— and that scene has since been deleted (2026-09-03, with the rest of the abandoned procedural
background line), so this is the record of the observation, not a file to go and look at.
**`main.tscn` was untouched that time, and it is the one that matters** — it carries the manual
player-spawn invariant, the four layers' `depth_t`, and every `base_y_fraction`. So the check
is `git status`, not `git diff project.godot` alone: **look at every dirty file after an editor
or export run**, and revert anything you did not deliberately change. This is the same failure
class as the `@export`-serialised `world_rebase_enabled` regression that cost weeks.

**`shipping_values_check` does not catch this. Measured: it PASSES on the stripped file.**
It reads `ProjectSettings` at runtime, and the stripped keys fall back to engine defaults
that *currently equal* the pinned values — so a stripped file looks identical to a pinned
one until an engine default moves. That is exactly what a version upgrade can do, which
makes this most dangerous during the one task where you run the editor most.

So: **`git diff project.godot` after any editor or export run**, and
`git checkout -- project.godot` if it moved. A green `check.sh` is no evidence here.

The cheap fix, written up but deliberately not built: have `shipping_values_check` scan
`project.godot` as *text* for the pinned keys, exactly the way it already text-scans
`main.tscn` rather than reading properties, and for the same reason it gives there — a
text scan catches what a property read structurally cannot.

**No gate covers input, and input has two independent paths.** A change verified on
one can be completely broken on the other. Desktop mouse and keyboard go through the
`ui_accept` action, polled in `player.gd._physics_process`; touch bypasses the action
entirely and calls `Player.buffer_jump()` from `Main._input`. The pause-button jump
leak (2026-08-03) was fixed for touch first and still reproduced on every desktop
click, because the desktop path was never involved. Test **both** deliberately.

Every harness below drives `ui_accept` synthetically via
`Input.action_press`, so they exercise the *consumer* of input, never its delivery.
A platform input path can be completely dead with all gates green — that is exactly
how the 2026-08-02 Android bug shipped. Input changes need a real desktop run
(check keyboard *and* mouse-click separately) plus an on-device Android check:
re-export to `./aura.apk`, `adb install -r aura.apk`, tap Start, then tap during
play. If a tap does nothing on device, `adb logcat -s godot` while tapping is the
next step.

## Two ways a harness hangs instead of failing

Both of these were hit on 2026-08-03 adding the `Services` autoload. Neither prints a
useful failure — the gate just never terminates — so check them first when a probe
that used to finish suddenly doesn't.

**1. `--script` runs do not register autoloads.** Referencing the global identifier
`Services` from gameplay code is a *compile* error in a headless script run, not a
runtime null. The referencing script fails to load entirely, its class resolves to
`Nil`, and every probe line configuring it (`require_start_screen = false`,
`debug_spawning_disabled = true`) fails against `Nil`. The start screen then stays up,
the tree stays paused, and the frame loop spins forever. **Never write `Services.x` in
gameplay code — use `GameServices.resolve(self)` and null-guard it.**

**2. A new `class_name` added outside the editor isn't in the global class cache.**
`.godot/global_script_class_cache.cfg` is written by the editor, and `--script` runs
read it. A script file created by hand parses fine in isolation but any *other* script
naming its type fails with `Could not find type "X"` — same cascade as above. Fix:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .
```

Run that after adding any new `class_name`, before running any gate — then **`git diff
project.godot` immediately**, because that command strips it (see the table above).

## Harness opt-outs — set these before `add_child(main)`

Five things in the running game will quietly invalidate a measurement or make a gate
"pass" by doing nothing. Any **new** harness that steps many physics frames needs all
five.

**Do not read this table as a guarantee about the existing gates.** It used to say they
"already have them", which was not true and is the same shape of assumption that let the
original `world_rebase_enabled` regression hide: only `freeze_search`,
`freeze_replay_runner` and `stall_recovery_probe` reference `world_rebase_enabled` at
all. That's behaviourally fine — the default is `true`, which is what a gate wants — but
check the file, don't trust the sentence.

| Flag | Why |
|---|---|
| `Main.world_rebase_enabled` | The freeze fix. `=false` only for deliberate A/B work. |
| `GameManager.require_start_screen = false` | Otherwise the run sits paused on the start screen and the gate trivially passes. |
| `ObstacleSpawner.debug_spawning_disabled = true` | Clusters schedule off `elapsed_time`; a collision ends the run mid-measurement. |
| `PowerupSpawner.debug_spawning_disabled = true` | Same scheduling, worse effect — see below. |
| `TerrainGenerator.debug_chasm_disabled = true` | A no-input run reaches a chasm, runs off the lip and dies. Same failure shape as the two spawner flags. `freeze_search` takes `--chasms=1` to opt back in; `chasm_probe` leaves them on by design. `camera_shake_probe` has the flag too, but it drives no input and so cannot jump a chasm — only meaningful with `--frames` short enough to stop before the seed's first void. |

The `Services` autoload (`scripts/autoload/services.gd`) is instantiated in
`--headless --script` runs too, so it executes inside every probe. It carries an
`is_headless` guard for exactly this reason; anything added there that touches audio,
rendering or input must sit behind that guard.

**The powerup flag was added after it broke a gate (2026-08-03).** Powerup spawning
moved from fixed world-X positions to an `elapsed_time` schedule starting at t=15s, and
a probe player collects every pickup it runs into. A speed boost snaps `current_speed`
to a flat 1000 px/s for 3s — above `MAX_SPEED`'s 750 — so each one injects two
instantaneous speed step-changes into the run. `camera_shake_probe` then reported flat
mean jerk **0.0066** against the documented 0.002 baseline, with `scroll_rate_x` topping
out at 17.2 px/frame (1032 px/s, impossible under the ramp alone). That last number is
the tell: if a camera measurement looks inflated, check `scroll_rate_x` against the
750 px/s cap (12.5 px/frame) before believing it's a camera regression.

## Archived probes are NOT gates — and most of them no longer run

**They live in `scripts/debug/archive/` as of 2026-08-15.** `scripts/debug/` now holds exactly
the **twelve maintained** files and nothing else — the six headless gates, the four visual
checks, `shipping_values_check.gd` and `ice_seam_probe.gd` — so "is this thing a gate?" is
answered by which directory it is in rather than by checking a list.

**Comments across the codebase name these probes by bare filename** (`freeze_ab_runner.gd`,
`stall_recovery_probe.gd`, …) in `player.gd`, `game_manager.gd`, `speed_manager.gd`,
`obstacle_spawner.gd`, `powerup_spawner.gd` and several research docs. Those were left as
written — none of them is a path, they are prose naming a measurement's source, and rewriting
28 comment lines across gameplay files to add a directory earns nothing. **A bare probe
filename in a comment means `scripts/debug/archive/<name>`** unless it is one of the twelve.

Everything in `archive/` is a one-off from a closed investigation, kept for its measurements and
its comments. **Audited 2026-08-03, and most of them silently lie now:**

| Probe | State |
|---|---|
| `chord_aim_probe`, `contact_instability_probe`, `mega_drop_probe`, `offset_curve_probe`, `slide_vs_snap_probe`, `solver_correction_probe`, `visual_compensation_probe` | Run, but **measure a frozen game** — see below |
| `aa_toggle_probe`, `canvas_transform_probe`, `frame_capture_probe`, `mega_drop_visual_probe`, `render_pacing_probe` | Same, and additionally need a real window (they measure rendering), so they hang under `--headless` |
| `model_validation_dump`, `rebase_probe`, `ghost_collision_probe` | Fine — they don't depend on the player moving |
| `visual_smoothing_probe` | **Deleted 2026-08-03.** It consumed a temporary `Player` visual-smoothing experiment that was reverted; it had been erroring on the removed `debug_visual_process_frame_count` ever since |
| `jitter_frequency_probe` | **Repaired 2026-08-03.** Was erroring on the removed washout API and printing an empty table; the presentation/washout columns are gone and the opt-outs are in |

Why "frozen": all of these predate `GameManager`, so none of them sets
`require_start_screen = false`. `GameManager` holds `get_tree().paused` on the start
screen, `Player` uses the default `process_mode`, and so `Player._physics_process`
**never runs for the entire measurement**. Nothing errors and nothing hangs — the probe
prints a full, well-formatted, completely meaningless table.

Measured: `chord_aim_probe --frames=600` (10s of game time) reports `distance=64`,
which is the player's spawn x. It moved zero pixels.

**Before trusting any archived probe, add the opt-outs from the table above and check
its `distance=` output is not 64.** Reviving one is a few lines, but it is never free.

Each archived probe's own usage line was rewritten to its new path when it moved, so copying
the command out of a file's header still works:

```bash
Godot --headless --path . --script res://scripts/debug/archive/<probe>.gd -- ...
```

## The six headless gates

> **Plus one non-physics gate: `biome_schedule_check.gd`** (2026-08-08). It is listed
> separately below because it is the odd one out — physics-free, ~1 second, and it exists
> precisely because the six below **cannot see the biome system at all**. They all
> instantiate `main.tscn` under `--headless`, and `BiomeDirector` deliberately returns early
> under `--headless` having applied nothing. That is what makes it impossible for a colour
> change to move a physics gate result, and equally what makes those gates blind to every
> line of biome code — the same structural gap this file already records for powerups.

**These run at real-time 60Hz, so budget by frame count, not by patience.** A headless
`SceneTree` script awaiting `physics_frame` still steps at the physics rate: freeze-replay
(60,000) ~17 min, camera-shake (7,000) ~2 min.

**Floor-flicker at the full gate size is far slower than its frame count predicts, and nobody
has explained why.** Measured 2026-08-09, all on one machine:

| Run | Frames | Predicted at 60Hz | Actual |
|---|---|---|---|
| `--frames=2000` (6 seeds) | 12,000 | 3.3 min | **3.3 min** ✔ |
| `--frames=20000` (6 seeds, the gate) | 120,000 | 33 min | **3h 20m** ✘ |
| camera-shake `--frames=7000` | 7,000 | 2 min | **2 min** ✔ |

So the tick rate is genuinely 60Hz — the short run and camera-shake both hit it exactly — and
the full gate is ~6x off that anyway, at ~1% CPU the whole time (sleep-bound, not compute-
bound). **Budget 3.5 hours for the bare gate form, not 33 minutes.** If you only need a smoke
test, `--frames=2000` exercises every code path in 3 minutes and just covers less terrain.

Worth someone's time eventually; it is a probe-runtime mystery, not a game bug.

A gate that has been "hanging" for twenty minutes is almost certainly just running — check
elapsed CPU time before killing it.

**Terrain shape** (fast, physics-free) — no Y discontinuity, no slope exceeding
`floor_max_angle`, across N random seeds. Expect `status=PASS`:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/terrain_invariant_check.gd -- --seeds=8 --to=300000
```

**Never shorten `--to`.** The coin-density band is calibrated for the full 1758-slot sample, so
a shortened run produces a confident FAIL that means nothing. Always `--seeds=8 --to=300000`.

It also carries several **constant-only checks** that need no scene and no seed — chasm variant
table, rare-coin height, coin-line height, and the two below. They are cheap, so they run on
every invocation.

### `check_upgrade_curve()` and `check_obstacle_clearance()` (2026-08-15)

**These two were documented in three places for weeks before they existed** — `CLAUDE.md`,
`upgrade_store.gd:57` and `obstacle_spawner.gd:56` all named them as the thing that stops a bad
constant shipping, and neither was anywhere in `scripts/debug/`. That is worse than having no
gate: CLAUDE.md said "raising the ceiling fails the build rather than shipping the bug", so the
person most likely to raise `JUMP_MULTIPLIERS` was the one being told a net would catch them.

They bound the jump upgrade curve from both ends:

| Check | Bounds | Baseline |
|---|---|---|
| `check_upgrade_curve()` | **The ceiling.** A boosted max-upgrade jump taken at the first pixel of a chasm run-up must still land before the void | `max_multiplier=1.0000 boosted_reach=848.5 budget=868.0` |
| `check_obstacle_clearance()` | **The floor.** The weakest jump the curve sells must clear a 32×32 obstacle, vertically *and* horizontally | `min_multiplier=0.60 apex=46.1 obstacle=32.0 window=0.265s/138.7px` |

**The powerup is included in the ceiling and excluded from clearability, and that is not an
inconsistency** — they are opposite bounds. `get_chasm_jump_reach()` asks about the *weakest*
jump, so ignoring the ×√2 powerup keeps it conservative; this asks about the *strongest*, so it
must include it.

Mutation-tested, each independently:

```
max 1.00 -> 1.10  =>  UPGRADE_CURVE_OVERSHOOTS_LEAD_IN, reach 933.4 > budget 868.0
min 0.60 -> 0.50  =>  OBSTACLE_APEX_TOO_LOW, apex 32.0 = obstacle 32.0, window 0.0s
```

The second reproduces `upgrade_store.gd`'s documented failure exactly — at 0.50 the apex equals
the obstacle height and the first cluster becomes a literal wall.

**One number is printed but deliberately NOT asserted.** `upgrade_store.gd` quotes "~8.6 frames"
of window at 0.60 and "~3.7" at 0.55; the plain projectile derivation of *time spent above 32px*
gives **15.9 and 11.0**. Those figures came from a derivation nobody has reproduced, so the gate
asserts the apex — which *does* reproduce exactly — and prints its own window for comparison.
**Do not reconcile the two by editing whichever is easier to change.**

It also carries **two independent frozen-lake passes**, and the split is the point:

| Pass | Covers | Baseline |
|---|---|---|
| `check_frozen_lake()` | The lake's **shape** — span, flatness, no void, C0 seams, no chasm adjacent. Pins the index with `debug_force_lake_segment_index`, so it proves nothing about arming | `flatness=0.000000`, span 7500.0 |
| `check_lake_arming()` | The **arming path** — `arm_lake()` is the sole writer of the one runtime input allowed into `get_terrain_height` | `watermark=164 armed_index=166 drift=0 fresh_disagreements=0` |

**The lesson from mutation-testing `check_lake_arming` (step 8), because the intuitive test does
not work:** re-sampling the SAME generator either side of `arm_lake()` reads `drift=0` even when
arming is maximally broken. `get_terrain_height` reads a *cached* spec, so the generator that
armed is the one that cannot see the damage. That is the bug's signature, not a gap — the
disagreement is between two generators, never inside one. Assertion 6 builds a fresh generator
and caught it at **292 disagreeing samples, worst 713.97px**. Both lake passes run once against
the first seed; what they assert is seed-independent.

**That gap is now closed** by `lake_suppression_probe.gd` below — it needs live spawner
instances driven over a pinned lake, which is why it is a separate file rather than a case here.

**Freeze replay** — steps physics frames from spawn, no input. Prints
`status=no_freeze|freeze_detected|tree_paused|stall_recovered`. **`--frames` must be
large** — every recorded freeze is past frame ~25,000; short runs report `no_freeze`
unconditionally. `--rebase=0` disables world rebasing for A/B work:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/freeze_replay_runner.gd -- --seed=941462462 --frames=60000 --runs=1
```

**Freeze search** — the harness that actually finds stalls (replay alone is not
sufficient); sweeps sub-pixel start phases × input schedules at a target world_x.
Expect `trials with a STALL : 0`:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/freeze_search.gd -- --seed=941462462 --warp=175000 --to=178000 --phases=8 --phasestep=0.25 --scan=1 --trialframes=500 --rebase=1
```

**Floor flicker probe** (`scripts/debug/floor_flicker_probe.gd`) — the permanent
regression gate for the `is_on_floor()` flicker fix; per-segment-label flip-rate,
kept from `docs/research/floor_flicker.md`'s investigation. Defaults to the same six
seeds and 20,000 frames the original measurement used, so the bare form is the gate:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/floor_flicker_probe.gd -- --frames=20000
```
Other flags: `--seeds`, `--trace`, `--tracelines`, `--jump`.

**Chasm probe** (`scripts/debug/chasm_probe.gd`) — the behavioural gate for chasms.
`terrain_invariant_check` proves the *geometry* (lips level, void cut out of the collision
shape, width clearable on paper) and runs no physics, so it cannot prove a chasm actually
behaves. Four trials per chasm from the same warp onto the lead-in flat. Expect
`status=PASS`:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/chasm_probe.gd -- --seed=683407368 --chasms=3 --phases=4
```
`--phases` sweeps sub-pixel start offsets (0.25px apart) so trials do not all land on the far
lip at the same offset — the same idea as `freeze_search`, applied where `freeze_search` cannot
reach. `--speed=750` re-runs every trial at cap speed; the default pins each trial to the
slowest speed the player could actually have reached *that* chasm at, which is the case that
has to work.

**Pinning the speed is not optional, and neither is defining "cleared" as *landed*.** Trials
run from a warp, so `elapsed_time` bears no relation to `world_x`: unpinned, the first trial
runs at the start-of-run ~100 px/s and reports a jump that cannot clear a gap sized for
595 px/s. And at 750 px/s the player crosses a 220px void in 0.29s having fallen only ~69px, so
a body still descending toward its death sails past a pure horizontal-distance threshold and
reports as a clean crossing. Both of those shipped as probe bugs first and read exactly like
feature failures — the `camera_shake.md` lesson again: measure the quantity that matters.
- `no_jump` — the player must **fall in and die**. If this "passes" by surviving, the void
  is not actually cut out of the collision shape and every other result is meaningless.
- `jump` / `late` — must clear and land on the far lip, `recoveries=0`. The far lip is an
  exposed open chord end in a `ConcavePolygonShape2D` segment soup, i.e. the highest-risk
  geometry in the feature; a non-zero recovery count there is a stop-ship. `late` fires the
  jump *past* the lip, so it exercises coyote time — the real takeoff window, not the paper
  one.
- `boost` — a speed boost must carry the player across. Jumping is suppressed for the
  boost's full 3s, so if the glide ever stops working a boosted chasm becomes unavoidable
  death. The glide is *emergent* (it falls out of `is_boosting` forcing the gravity-free
  grounded model, plus `get_collision_chord_slope_angle` returning 0 over the void), so it
  is exactly what a future refactor breaks silently. **This is the only gate that catches
  it.**

## Biome check (`scripts/debug/biome_schedule_check.gd`)

Physics-free, ~1 second, no seeds. Run it after touching `resources/biomes/*.tres`,
`biome_palette.gd`, `biome_director.gd` or any ice tile under `assets/textures/terrain/`.
Expect `BIOME_CHECK PASS`:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/biome_schedule_check.gd
```

It asserts that every palette loads and stays inside `[0,1]` (the Mobile renderer is LDR, so
a value above 1.0 is silently clamped and the palette will not look like its numbers); that
the **surface rim stays bright** and **far/near scenery stay separated** in every biome —
the contrast contract that replaced `visuals.md`'s old "terrain lighter than background"
rule; that the schedule is pure in `world_x`, swept forwards *and backwards* so any hidden
per-call state shows up rather than passing on a monotonic sweep; that every channel curve
is monotonic and lands exactly on 0 and 1; and that `BiomePalette.blend_into` never
allocates, since it runs every frame of a transition.

**The scenery separation is measured at the `depth_t` values `main.tscn` really uses, not at
the palettes' authored endpoints** (2026-08-25, review item #5). Those are different numbers:
the four parallax layers sit at 0.0 / 0.15 / 0.30 / 0.45, so a palette only ever shows the far
45% of its `scenery_far → scenery_near` ramp, and the gate used to pass `pale_morning` at 0.223
while the frame showed 0.100. It reads the range out of the saved scene through `SceneState` —
no instantiation, so the gate stays physics- and render-free — and reports it on the PASS line
as `scenery_depth=0.00..0.45` so the range is visible when nothing is wrong. **A layer with no
`depth_t` line in `main.tscn` is not skipped**: Godot omits a property still equal to its
script's default (the same stripping documented in `shipping_values_check.gd`), so the default
is recovered from the script. Finding *no* layers at all is a failure, not an empty pass.

It also guards the **per-biome ice textures**, which are invisible everywhere else: `ice_texture`
is legally `null` (= use the default smooth tile), so a stale `ExtResource` path resolves to
`null` and is indistinguishable from a palette that never wanted a variant. The PASS line
therefore reports `ice_variants=N`, and the gate fails at zero, on a wrong tile size, if a
variant's depth ramp drifts off the default tile's (`MAX_ICE_RAMP_DEVIATION`), or if
`blend_into` starts carrying `ice_texture` again — the pattern rides a two-band dissolve in
`terrain_generator.gd` and must not also be snapped onto the blended palette.

**It has been verified to fail**, by darkening `starlit_night.rim_core` and flattening its
scenery separation, and (for the texture checks) by tightening `MAX_ICE_RAMP_DEVIATION` to
0.001 — all were caught, and the file passed again on revert. Worth repeating
if you extend it: this file's whole reason to exist is that nothing else can see this code.

The depth-range read was negative-tested the same way, and the first of the two is the one
that proves the change rather than the code: raising `MIN_SCENERY_SEPARATION` to 0.15 failed
**7 palettes at a rendered 0.100–0.137 while every one of them authors 0.223–0.304** — under
the old endpoint-based check all seven would have passed. Deleting a layer's `depth_t` line
from `main.tscn` was caught too, via the script-default fallback (`FarPeaks` came back as
`BackgroundGenerator`'s own 0.5, which is exactly why its authored 0.0 is serialised at all).

**What even this gate cannot see is the two-band build/repaint code**, because `BiomeDirector`
is inert under `--headless` and never calls `apply_ice_palette()`. That was verified once with
a throwaway probe — see `biomes.md`, "Testing" — not kept as a gate.

Full design notes: `docs/development/biomes.md`.

## Shipping values check (`scripts/debug/shipping_values_check.gd`)

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/shipping_values_check.gd
```

~0.2s, no scene stepped, no seeds. **Run it before every commit.** Fails if any "turn this off
before you commit" knob is left flipped.

Added 2026-08-10 to close a real hole. Every debug knob here is a plain `var` rather than an
`@export` *on purpose*, so the editor cannot serialise it into `main.tscn` — that is the
`world_rebase_enabled` regression's mechanism. The unpaid cost of that choice: a plain var is
invisible to every other gate, so **nothing caught one left on.** `ObstacleSpawner.
debug_spawning_disabled` was documented here as "check by hand", and `biome_distance` was
described as having a "tripwire" that was only ever a *printed number* — `biome_schedule_check`
returns `PASS` at any value, verified against a live TEMP of `7500.0`.

It checks two things, and the second is the stronger one:

1. **The source-level default of each knob**, by `.new()`-ing the script and reading the
   property (`_ready()` only runs on tree entry, so nothing resolves a NodePath or spawns).
   Covers `debug_chasm_disabled`, `debug_drop_chasm_rehearsal`, `debug_log_segment_selection`,
   `debug_replay_session_seed`, `debug_weight_mega_drop`, both `debug_spawning_disabled`,
   `debug_forced_effect`, `world_rebase_enabled`, `require_start_screen`, `BIOME_DISTANCE`,
   `TRANSITION_DISTANCE`.
2. **That `main.tscn` serialises no override**, by scanning the scene as **text** for any line
   starting `debug_`, `world_rebase_enabled` or `require_start_screen`. Deliberately a text
   scan rather than a property read on an instantiated scene: the text catches a property this
   file has never heard of, which is the entire failure mode. Verified by injecting
   `world_rebase_enabled = false` into `main.tscn` — caught at the exact line. Note the script
   *default* still read `true` throughout that test, which is exactly why reading defaults
   alone is not enough.

`--allow-temp` downgrades every failure to a `WARN` and exits 0, for deliberately eyeballing a
run with knobs flipped (same opt-out idiom as `freeze_search --chasms=1`). The point is that
silencing it has to be something you typed.

**Two things it deliberately does not fail on:** `debug_first_powerup_time_override` and
`debug_first_powerup_effect_override` both derive from `OS.is_debug_build()`, and a gate runs on
the editor binary — which *is* a debug build — so their non-shipping value is correct in every
context this can run in. They are printed for information.

## Sky layer check (`scripts/debug/sky_layer_check.gd`)

```
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://scripts/debug/sky_layer_check.gd
```

**A gate, but not a headless one — it has to render.** It measures what each optional sky
layer (`SkyGlow`, `SkyCelestial`, `SkyStars`, `SkyTint`) actually puts on screen, in pixels,
per biome, and exits non-zero if any layer a biome *claims* falls under
`MIN_PEAK_CONTRIBUTION` (24/255). A layer a biome does not claim reports as `--` and is skipped — `celestial_strength = 0`
(five of eight), `star_density = 0` (five of eight), or white sky tints (three of eight), all
of which are deliberate authoring choices rather than omissions.

`SkyTint` is measured differently from the other three: the horizontal sky wash is baked into
the gradient texture and has no node to toggle, so its baseline is the same palette
`duplicate()`d with the tints forced to white. Same two-capture shape, different way of
producing the "off" frame.

It exists because `biome_schedule_check` cannot see this. That gate proves the glow *data* is
well-formed — colours in range, anchors on screen, `blend_into` carrying every field — and the
glow shipped in 92c7867 passed all of it while contributing **11/255** at its peak, which is
invisible. *Numbers being valid* and *pixels being different* are two separate claims.

Method: for each palette, two captures of the same frame differing only in `SkyGlow.visible`.
Three things make the difference mean only the glow, and each was learned by getting it wrong:

- **`Engine.time_scale = 0`.** Without it the world scrolls between captures and the diff
  measures terrain motion. A first attempt reported 22% of pixels changed by a glow that was
  contributing nothing.
- **The palette goes straight to `SkyBackdrop.apply_palette()`**, not through a `world_x`, so
  terrain and snow never move between biomes either.
- **Apply, wait, then capture** — `root.get_texture()` returns the frame already rendered.
  Same trap `biome_contact_sheet.gd` documents at its head.

A failure is almost always one of three things: the glow sits where scenery covers it, its
colour is too close to the sky colour it blends over, or the strength is too low. **The second
is the least obvious and was the real cause the first time**: a near-white glow on a near-white
sky moves nothing however high the strength goes.

## Visual capture (`scripts/debug/ice_look_capture.gd`)

**Not a gate — it asserts nothing.** It runs `main.tscn` *with* a renderer (no `--headless`)
and saves viewport PNGs at a few frame counts, so a terrain/texture change can be looked at
without a human having to play the game and screenshot it.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://scripts/debug/ice_look_capture.gd -- --out=/tmp/ice
```

It exists because the ice pass shipped a visibly broken frame twice in one session — a
funnel-warped texture and a washed-out palette — both of which were obvious in one
screenshot and invisible to every headless check. **Run it before handing a visual
change over.** It re-asserts `State.PLAYING` every frame (the capture window loses focus
immediately, and `GameManager` pauses on `NOTIFICATION_APPLICATION_FOCUS_OUT`) and hides the
UI `CanvasLayer`.

The project owner still judges the final look in-game; this is for catching the gross
breakage first.

## Ice seam probe (`scripts/debug/ice_seam_probe.gd`)

**Not a gate — it prints, it never fails.** Kept maintained (2026-08-11) because it is the only
instrument that measures the ice as *rendered*. `build_ice_texture.py --check` reads a tile's
source bytes and catches both known defect classes offline in ~1s; use that first. This is for
the question it cannot answer: *does this read as a line on screen, and is that the tile's
content or the renderer?*

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://scripts/debug/ice_seam_probe.gd -- --out=/tmp/seam --old=/tmp/old-tiles
```

No `--headless`: `BiomeDirector` returns early there, so `ice_hue_variance` stays 0 and the
drift under investigation never runs. `--old=DIR` points at previous-version tiles with the
**same basenames**; omit it to capture and report without an A/B.

Three things it does that a naive version of the same script got wrong, each having produced a
confidently false answer during the 2026-08-11 seam hunt:

- **It A/Bs inside ONE frozen frame.** The seed is per-session and the player is moving, so two
  *runs* are two different landscapes — measured camera drift ~25 world px by the first capture.
  It settles, pauses the tree, captures, swaps the tile textures in place, captures again.
- **It hides Player, snow, birds and all four spawners.** A vertical sprite edge is precisely
  what a vertical-seam detector is built to find. Four false positives came from this — a
  28/255 "step" that was a tree trunk crossing the sample row, and a 7.4/255 "line at 9.9×
  median" that was the same trunk's edge.
- **It scrolls the world between captures** (`DRIFT_CAPTURES`). A feature of the *ice* travels
  with the camera; a feature of the *rendering* stays put on screen. Nothing else here splits
  those two apart, and every earlier detector could find either without knowing which it had.

`SceneTree.paused` for the freeze, never `Engine.time_scale = 0` — that zeroes the physics
delta, trips the stall watchdog and fires a world rebase, leaving the world off screen. Full
list of the measurement traps in `docs/research/` and at the head of the file itself.

## Measurement traps

**Every one of these produced a confidently wrong answer at least once.** They are about
measuring the game, so they apply to any new probe, not just the visual ones.

1. **A windowed probe reads all-zero if the display is asleep or the window is occluded**, and
   it holds no focus, so `NOTIFICATION_APPLICATION_FOCUS_OUT` pauses the game on frame one.
   Re-assert `set_state(PLAYING)` every frame.
2. **`Engine.time_scale = 0` is not a safe freeze.** It zeroes the physics delta, trips the
   stall watchdog and fires a world rebase, leaving the world off screen. Use `SceneTree.paused`
   — rendering still runs while paused, which is what makes a swap visible.
3. **Never compare pixel numbers across two RUNS.** A/B inside one frozen frame
   (`ice_seam_probe`).
4. **Apply, wait a frame, *then* capture.** `root.get_texture()` returns the frame already
   rendered.
5. **Hide the sprites before measuring**, and **sample at constant DEPTH BELOW THE SURFACE, not
   constant y** — on sloped terrain a fixed y walks through different parts of the band.
6. **Count items, never containers.**
7. **Any long-running harness needs obstacles AND chasms disabled** (`debug_chasm_disabled`
   alongside the two `debug_spawning_disabled` flags), or a chasm death reports a confident wrong
   number. `freeze_search` and `camera_shake_probe` take `--chasms=1` to opt back in.
8. **Grep whole logs for `SCRIPT ERROR|Parse Error|Failed to load`.** A narrow grep once
   discarded a probe's entire output and reported nothing at all.
9. **`get_tree()` does not exist in a `SceneTree` script** — `self` is the tree; use `paused`.
10. **A new `class_name` needs `Godot --headless --editor --quit --path .`** before any gate
    compiles, and that pass can strip 40 lines from `project.godot`. `git diff project.godot`
    afterwards is not optional.
11. **A probe must never touch `SaveStore.SAVE_PATH`.** A step-1 verification probe deleted the
    developer's real `user://save.dat` (2026-08-14). Back it up and restore it, or point the test
    at a temp path. The gates already write to it on player death — pre-existing, and worth
    fixing the same way.
12. **Headless Godot loads shaders but does NOT compile them.** A shader syntax error appears in
    no gate; it appears when someone runs the game. Read new shader code twice.
13. **When a probe fails, suspect the probe first.** And a green check that cannot go red is
    worthless — mutation-test a new assertion by breaking the thing it guards, as
    `check_lake_arming` was.

## Lake suppression probe (`scripts/debug/lake_suppression_probe.gd`)

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/lake_suppression_probe.gd
```

**Asserts that nothing spawns on a frozen lake.** ~10s. Run it after any spawner change, and
without fail when adding a seventh spawner.

Suppression is not a property of the height field, so `terrain_invariant_check` structurally
cannot cover it — that file is geometry-only by contract. Six spawners each ask
`is_lake_world_x()` and skip the slot; the only way to know all six *do* is to run them and look.

**Why it matters more than it sounds:** jumping is disabled across a lake, so a coin placed on
one is unreachable by construction and an **obstacle** placed on one is unavoidable by
construction — a guaranteed death in a stretch where the jump button does nothing. All of it
fails silently, with the terrain still perfectly flat and every geometry gate still green.

It pins a lake with `debug_force_lake_segment_index` (no probe can reach a naturally armed one —
`FrozenLakeDirector` hard-skips headless), warps onto it at `MAX_SPEED`, crosses, and collects
every item any of the six spawners places with an x strictly inside the span. Deduplicated by
instance id, so the count is distinct offending nodes.

Baseline: `frames=600 spawners=6 status=PASS`.

Mutation-tested by deleting both `is_lake_world_x` guards from `CoinSpawner`:
`SPAWNED_ON_LAKE spawner=CoinSpawner count=21 first=Coin` — with the other five still clean.

**THE TRAP IT WALKED INTO FIRST, because it is this file's own trap 6.** `CoinSpawner` and
`GroundTreeSpawner` wrap each chunk's items in an unnamed `Node2D` group positioned at the
chunk. The first version recursed blindly, saw those groups inside the lake, and reported
thousands of violations. **An empty group inside the lake is the CORRECT result** — the chunk
still exists, it just holds no coins, so the group is evidence of suppression *working*. Count
items, never containers.

## Watchdog mechanics

`Player.recover_from_stall()` re-seats the body on the terrain height field after
`STALL_RECOVERY_FRAME_THRESHOLD` (4 frames, ~67ms) consecutive stalled frames, with
`STALL_RECOVERY_CLEARANCE` (1.0px) of clearance above the surface so it isn't reborn
inside the collision polyline. A passing regression run must show **zero**
`debug_stall_recovery_count` — non-zero means a stall happened and was papered over.

`update_stuck_detection()` is a second, independent watchdog for the same failure
mode: it tracks **net** progress over a `STUCK_WINDOW_FRAME_COUNT` (60 frame, ~1s)
rolling window instead of a single frame, since a jittering stall (small
back-and-forth motion) never strings together enough consecutive near-zero frames to
trip the per-frame one. Both watchdogs recover through the same
`recover_from_stall()` path and print (`STALL_RECOVERY` / `STUCK_DETECTED`) so a
console log always shows the full history even if a screen wasn't watched live.

`is_stalled_this_frame()` (the shared predicate both watchdogs are built on):
grounded, `|velocity.x| >= 1.0`, and `|last_physics_displacement.x| <= 0.01` — shared
so the recovery watchdog and the freeze logger can never disagree about what a stall
is.

## Debug flags & logging toggles

- `Player.DEBUG_SHOW_PLAYER_STATE` — runtime `Label` with live physics/terrain state
  incl. **session seed**; read it to reproduce a bug via `--seed=`.
- `Player.DEBUG_LOG_FREEZE_REPRO` — prints `FREEZE_REPRO` when grounded with
  `|velocity.x| >= 1` but `|motion.x| <= 0.01`, emitting
  `debug_freeze_detected(session_seed)` — what the replay runner watches. Log any
  seed that triggers this in `docs/research/freeze_bug.md` before fixing it.
- `TerrainGenerator.debug_log_segment_selection` / `DEBUG_TERRAIN_LOGGING` /
  `Player.DEBUG_SLOPE_LOGGING` — `const` toggles for per-frame spam.
- `TerrainGenerator.debug_weight_*` — see `docs/development/terrain.md`.
- `GameManager.require_start_screen` (default `true`, not `@export` — same reasoning
  as `Main.world_rebase_enabled`) — real play pauses on a start screen until tapped;
  any harness that instantiates `main.tscn` and steps many physics frames expecting
  the player to actually move must set
  `(main.get_node("GameManager") as GameManager).require_start_screen = false`
  before `add_child(main)`, or the run sits paused and the gate trivially "passes"
  by doing nothing. `freeze_replay_runner.gd`, `freeze_search.gd`,
  `floor_flicker_probe.gd`, and `camera_shake_probe.gd` already do this.
  `terrain_invariant_check.gd` doesn't need it: it awaits exactly one
  `physics_frame` (frame signals fire regardless of pause) and samples the height
  field directly, never depending on player movement.
- `ObstacleSpawner` schedules clusters off live `Player.speed_manager.elapsed_time`
  (not world_x), so any harness that steps many no-input frames will eventually
  reach one. A collision pauses the tree via `GameManager`, which stops
  `Player`/`Main` `_physics_process` mid-run and gets silently misread as whatever
  that harness measures (a stall, a floor-contact anomaly, a camera freeze
  reported as one huge jerk spike followed by a run of near-zero frames). Found
  once already this way in `camera_shake_probe.gd` -- an 8.5 px/frame^2 spike with
  `scroll_rate_x=0.0000` that vanished when the run was truncated to end before
  the first cluster's ~20s trigger.
  **`set_physics_process(false)` does NOT reliably suppress this** -- tried first,
  and confirmed by direct instrumentation to be a no-op: `_physics_process` kept
  firing every frame even while `is_physics_processing()` reported `false` on the
  same node. Every harness "fixed" this way was actually still spawning obstacles;
  the entire investigation above (camera jerk spike, `floor_flicker_probe.gd`
  showing a frozen-looking `distance=11356`, a cross-seed pause cascade freezing
  every seed after the first death in the same process) traced back to this one
  ineffective fix, not a real physics/stall bug -- confirmed by
  `freeze_replay_runner.gd` reaching `world_x=108978.9` at frame 10000 with
  `status=no_freeze` once the real fix was in. Use
  `ObstacleSpawner.debug_spawning_disabled = true` instead (a plain script var
  checked inside `_physics_process()`, the same pattern as
  `Main.world_rebase_enabled` / `Player.DEBUG_LOG_FREEZE_REPRO` /
  `GameManager.require_start_screen`, all of which DO work reliably):
  `(main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner).debug_spawning_disabled = true`
  before `add_child(main)`. `freeze_search.gd`, `freeze_ab_runner.gd`,
  `stall_recovery_probe.gd`, `camera_shake_probe.gd`, `floor_flicker_probe.gd`, and
  `freeze_replay_runner.gd` all do this now.
- `floor_flicker_probe.gd` runs multiple seeds sequentially in one process via
  `run_seed()`. `get_tree().paused` is tree-wide, not scoped to one seed's `main`
  instance -- without an explicit `paused = false` after `main.queue_free()`, a
  seed that ends paused (e.g. from an obstacle death, before the fix above
  existed) leaves every LATER seed in the sequence frozen at spawn for its entire
  run. Fixed by resetting `paused = false` at the end of each `run_seed()` call.
  `freeze_replay_runner.gd` doesn't need it: an obstacle death there reports as
  its own distinct `status=tree_paused`, not misread as a stall.

## Camera shake probe (`scripts/debug/camera_shake_probe.gd`)

Regression gate for the 2026-08-01 camera-judder fix (`main.gd` horizontal
follow). Measures **camera jerk** — the frame-to-frame change in scroll rate —
per segment label. The terrain is static in world space, so the camera's
per-frame displacement *is* the on-screen motion of the whole view; uneven
displacement is perceived shake. Smooth scrolling reads 0; the speed ramp only
accounts for ~0.0009 px/frame², so anything above ~0.001 is judder.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/camera_shake_probe.gd -- --seed=941462462 --frames=7000 --warmup=120
```

- `--smoothness=0` restores the old rigid `camera.x = player.x` follow and
  `--lead=0` disables the lag-cancelling lead term, so before/after A/Bs come
  from one binary and one seed rather than a checkout swap.
- **`--warmup` matters.** A smoothed follow legitimately spends its opening
  frames settling into its steady-state lag; without a warmup that one-time
  transient lands in the stats as a bogus `gentle_uphill` max-jerk spike
  (0.049 → 1.19) that looks exactly like a regression. 120 is plenty.
- Expected on current `main`: `mega_drop` mean jerk ~0.06 (was 0.38 rigid),
  `flat`/`gentle_uphill` at the ~0.002 noise floor, and follow distance ~7px.
  A `mega_drop` mean above ~0.15 means the follow filter or its lead term
  regressed.

Full investigation — root cause, the four hypotheses ruled out first, and why
the contact-point metric it replaced was a dead end: `docs/research/camera_shake.md`.
