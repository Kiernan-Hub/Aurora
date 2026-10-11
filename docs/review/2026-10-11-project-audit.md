# Project audit — 2026-10-11

Baseline `91df485` (branch `ccr-66a5a39f-awpfxh`, identical to `main` at the 2026-10-05 merge plus
the A-item cleanup). Working tree clean before and after. **Only this file and one HANDOFF line
were changed.** No code fixes, so every item below is a proposal for the owner.

**Method.** I read all runtime scripts, the main scene and the export/project config. I ran every
headless gate twice on Linux with the same engine build as the Mac (`4.7.stable.official.5b4e0cb0f`),
then ran throwaway probes from outside the repo to confirm or rule out each suspicion. Facts are
marked as measured or read; inferences are labelled as such.

## Verdict

The core loop is in good health. Terrain, physics, fairness and persistence gates all pass. Every
architecture rule CLAUDE.md states still holds, and the 2026-10-04 audit's fixes are in place. One
real defect turned up, in **developer tooling**, not the game: running a visual gate as documented
**wipes the developer's own save**. The rest are small items and documentation drift.

| # | Pri | Finding | Fix size |
|---|---|---|---|
| V1 | **P2** | Visual gates overwrite `user://save.dat` with a blank save | ~4 lines, one file |
| V2 | P2 | Phone performance numbers (A3, the late frames) come from debug builds | one measurement, no code |
| V3 | P3 | Android Back closes the shop but leaves the Reset dialog up and live | ~3 lines |
| V4 | P3 | A release build would show the debug "stuck @" label | 1 line |
| V5 | P3 | The Reset dialog doesn't say it also erases achievements and set-piece progress | copy only |
| V6 | P3 | The orientation pin uses a Godot 3-style string that only works by coincidence | owner question |
| V7 | P3 | `sky_layer_check`'s IceHue row has zero margin | leave, note only |
| V8 | P3 | Documentation and comment drift (A5 leftovers) | docs-only commit |

---

### V1 — P2: the visual gates wipe the developer's save

**Measured.** I planted a non-default `save.dat` (best 4321, wallet 777, jump level 2, 5000 s of
playtime, `still_water` earned). Then I ran `sky_layer_check.gd` without `--headless`, as CLAUDE.md
requires. Afterwards the file held defaults: best 0, wallet 0, no upgrades, no achievements,
playtime 0, volumes reset, and `next_aurora_due_seconds` = 1800. A minimal probe that only does
`root.add_child(main)` in `_init()` under a real display reproduces it exactly.

**Mechanism.** Read in code, and consistent with the probe: it printed no `/root/Services` during
`_init()` and a default store afterwards, and the 1800 deadline names the writer.
1. All three visual gates (`sky_layer_check`, `ice_look_capture`, `biome_contact_sheet`) add
   `main.tscn` inside `_init()`.
2. In a `--script` run, that scene's `_ready()`s fire before the `Services` autoload's own `_ready()`
   has loaded the save. At that moment `/root/Services` exists, but its `SaveStore` still holds
   defaults.
3. `AuroraDirector._ready()` sees `next_aurora_due_seconds = -1` and calls `schedule_if_unscheduled()`.
   That writes the whole default store to disk, giving 0 + 1800.
4. `Services._ready()` then loads the file it just overwrote.

Headless gates are safe, and I measured it. The sentinel save stayed **byte-identical** through a
full `check.sh --full` run (an earlier run with no save present created none), because both directors return early under `--headless` and
GameManager's writes check `DisplayServer`. The shipped game is safe too, because autoloads are
ready before the main scene loads.

**Impact.** This is only the save used for desktop/editor playtests. The phone save lives on the
device and is untouched. If any visual gate has run on the Mac since the Aurora schedule landed
(the code is at least as old as 2026-09-23), that Mac save has already been reset. Check
`~/Library/Application Support/Godot/app_userdata/Aura/save.dat`.

**Smallest fix (recommended):** one guard at the root of the class, in `SaveStore`. Set a
`has_loaded` flag at the end of `load_from_disk()`, including when no file exists. Make
`save_to_disk()` refuse (with `push_error`, returning false) until that flag is set. That protects
every current and future harness from "write before load", in about four lines, with no change to
the shipped path. `regression_probe`'s `MemorySaveStore` overrides `save_to_disk()`, so it is
unaffected.
- *Alternative:* change each visual gate to `call_deferred` its setup and swap in a memory store.
  That's three files, and the next new harness can forget. Not recommended alone.
- *Gate for the fix:* add a `regression_probe` case that calls `save_to_disk()` on an unloaded store
  and expects `false`.

### V2 — P2: the phone performance numbers come from debug builds

**Read.** Every phone build is `--export-debug` (`debugging.md`, "Android device testing"). Debug
builds also run the following, none of which a release build does:
- Player's per-frame probe rig, `update_debug_state_label()` + `record_freeze_repro_frame()`. That is
  two `get_floor_collision_data()` passes and segment lookups per tick, and by `player.gd`'s own
  estimate ~3,600 string allocations a second.
- The debug GDScript VM.
- `OBSTACLE_SEARCH_SLOWEST` logging.
- **A first powerup at 5 s** (`debug_first_powerup_time_override`) instead of 15–39 s. That shifts
  the whole powerup schedule earlier in every phone playtest.

**Inference, not measured.** The A3 figure (4.10 ms worst) and the "~0.5 late frames/s, cause
unmeasured" item were both measured with all of this switched on. Release cost is probably lower,
but by how much is unknown.

**Recommendation.** Before optimising the obstacle search (A3), take one phone run with the
instrumentation off. The simplest way is to locally set the three `DEBUG_*` vars and the
powerup-time override to their release values, export, measure, and revert before committing
(`check.sh` catches nothing here). If the late frames vanish, A3 closes with no code change. It also
means early-game "feel" judgements on the phone were made against a non-shipping powerup schedule.

### V3 — P3: Back over the Reset dialog

**Measured (headless probe, in-memory save).** Open the shop, tap Reset Progress, then send
`NOTIFICATION_WM_GO_BACK_REQUEST`. I sent it both directly and propagated from the root, the way the
engine delivers it. The shop closes to START, but the **ConfirmationDialog stays visible**, now
floating over the start (or death) screen. Its "Reset Everything" still wipes the save.
**Not verified on a device**: Android could route Back differently while a popup has focus.

**Fix.** In `GameManager._notification`'s `State.SHOP` branch, hide `reset_confirm_dialog` first if
it is visible (Back means "cancel the dialog"), and close the shop otherwise.

### V4 — P3: a release build can show debug text

`Main._on_player_stuck_detected()` (`main.gd:296`) unhides `StuckTimeLabel` with
"stuck @ m:ss (x=N)" whenever the stuck watchdog fires, and that watchdog runs in every build. Gates
show 0 stuck events, so a player should almost never see it. If they do, it reads as a bug report.
Fix: return early unless `OS.is_debug_build()`.

### V5 — P3: the Reset dialog under-describes what it erases

`main.tscn`'s dialog says "best score, coin wallet, and every upgrade level". `SaveStore.reset_progress()`
also clears achievements, cumulative playtime and the lake/aurora schedule, which is deliberate.
Add "achievements" at minimum. The start screen's "dodge the red boxes" is also out of date
(floes, shards, thin ice), but the art pass will rewrite it anyway.

### V6 — P3: the orientation pin's type

**Measured.** In 4.7, `display/window/handheld/orientation` is an **int** enum (Landscape = 0 …
Sensor Landscape = 4). `project.godot` stores the Godot 3-style string `"landscape"`, which converts
to 0, the right value, only by coincidence. `shipping_values_check` asserts the string. It works,
so leave it unless the owner wants the following.

**Owner question:** most landscape phone games use **Sensor Landscape (4)**, so the game flips when
the phone is held the other way round. Today it is fixed Landscape. If you want that, set `4` (the
editor writes an int) and update the expected value in `shipping_values_check.gd:221`.

### V7 — P3: a knife-edge visual gate (note only)

`biomes.md:110` records IceHue contributions of 24–36/255 against a floor of 24, so at least one
biome already sits exactly on the floor on the Mac. Under Linux's software OpenGL fallback (no
Vulkan here), `mauve_haze` measured 23 and the gate failed. That's a different renderer, so this is
**not** evidence of a regression. It does mean an innocent palette or driver change can flip this
row. Don't lower the floor casually. If it starts flickering on the Mac, widen that biome's
`ice_hue_variance` instead.

### V8 — P3: documentation and comment drift

Each item was checked against the code. Together they make one docs-only commit.
- `coin_spawner.gd:108–118` and `biome_director.gd:607–611` still say the coin colour is
  absolute, not a modulate. `coin.gd` and CLAUDE.md correctly say it *multiplies* the gold sprite
  (A5 missed these two).
- CLAUDE.md row 3, "max-upgrade-only (or any level holding the ×√2 powerup)": level 0 with the
  powerup reaches 150 px, under the 174 px coin (`rare_coin_spawner.gd`'s own table). It should
  read "level 1+ with the powerup" (or a level-1 double jump).
- CLAUDE.md: "A 15th file, `ice_seam_probe.gd`". It is the 16th; README's wording, fifteen checks
  plus one diagnostic, is right.
- README: "Shipped and working" omits obstacles, the air moves and the Aurora, and
  "`check.sh`'s fifth gate" (the export check) is now the sixth.
- Harness lists naming archived probes as live: `game_manager.gd:40–42`, `obstacle_spawner.gd:19–21`,
  `powerup_spawner.gd:29–31`, `speed_manager.gd:23–24`. `player.gd:659` points at
  `scripts/debug/chord_aim_probe.gd`, which now lives in `archive/`.
- `docs/review/2026-09-20-project-audit.md`'s resolution note says no regression gate exists.
  `regression_probe` now covers all four findings.
- HANDOFF "Next actions" numbering skips 5.
- Still open from A5: the root `audit.md` belongs in `docs/review/` (as
  `2026-10-04-cleanup-audit.md`). Nine code comments cite it by bare name, so move it and update
  those citations in the same commit.

---

## Flagged, per the owner's rule (bug-prone or much harder than the alternative)

| Idea / pending work | Why flag it | Cheaper option |
|---|---|---|
| Optimising the obstacle search (A3) | Any real speedup changes which placements are accepted, so it must re-pass `check_placed_pattern_fairness()` | Do V2's release-instrumentation measurement first. It may make A3 unnecessary |
| 120 Hz via physics interpolation | Every teleport needs `reset_physics_interpolation()`, and every probe and the camera were measured with it off | Keep parked (as HANDOFF says) |
| Fixing V1 inside each visual gate | Three copies, and the next harness forgets | One guard in `SaveStore` |
| Play Store release | Needs AAB, a release keystore and explicit SDK levels (all still default/empty in `export_presets.cfg`) | No code risk. Do it as one checklist when shipping is close |

## Checked and healthy

- **Gates:** 14/14 PASS twice (256 s and 250 s). `--import` was clean, and `git status` stayed clean
  after every engine run, so no `project.godot` rewrite.
- **Save isolation for headless gates:** a sentinel save was byte-identical (same hash and mtime)
  through a full `--full` run, and the earlier run created no save at all. A non-default save (jump level 2) also didn't change any physics
  result, so `apply_upgrades()`'s headless skip holds.
- **Rules:** no `z_index` anywhere; no `Services.` in runtime code; `get_tree().paused` is written
  only at `game_manager.gd:381` and the sanctioned reload at `:650`; every file under `assets/`,
  `resources/`, `shaders/` and `audio/` has a runtime reference.
- **The 2026-10-04 fixes are present in code:** purchase rollback (A1), death-stats refresh (A2),
  the landing-window rule (A14), the dead-body pickup guard in `coin.gd`/`powerup.gd` (A15), and
  finite/range save validation (A17).
- **Size:** 13,473 runtime lines, of which 41% are comments and 6,213 code. That's fine as is (A13's
  advice still applies: extract only when a real change needs it).

## Looked at and left alone (not worth the code)

- `GlideCoinSpawner` uses the unseeded global RNG, the only score-affecting spawner not keyed to
  `session_seed`, so a replayed seed doesn't reproduce glide coin fields. Leave it unless a glide
  repro is ever needed.
- The obstacle tutorial pause can be skipped once if a tier boundary falls between "room taken"
  and placement (`is_first_appearance_room_taken` stays set). Cosmetic, about 1.5 s.
- `SaveStore` keeps a failed-rename temp file "as the only complete copy", but nothing ever reads it
  back. Harmless.

## Not covered

Vulkan/Metal visual gates (no GPU here), the camera-shake metrics, any device, audio, a release
export, and visual or art review. Remote branches were not refreshed.

## Suggested order

1. **V1** (save guard + a regression case), and check the Mac save. Until then, back up `save.dat`
   before running a visual gate.
2. **V2's** measurement on the phone (no commit). Then decide whether A3 needs anything.
3. **V3, V4, V5** as one small UI commit; run `check.sh`.
4. **V8** as one docs-only commit.
5. **V6** only if the owner wants Sensor Landscape.
