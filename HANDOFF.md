# Handoff — the Glossy Frozen Lake set piece

Updated 2026-08-14. Delete this file once step 9 is done and it has stopped being true.

Plan file: `/Users/kjh/.claude/plans/replicated-twirling-twilight.md` — the approved 9-step
plan for this feature. **Read it before doing anything**; this file is the running state, that
one is the design and the reasoning.

Older plan files, for background only: `this-is-how-i-peppy-lark.md` (the 4-phase visual pass),
`wahts-the-nezt-step-melodic-shore.md` (biome persistence).

---

> # ⚠ THE WORKING TREE IS NOT CLEAN, ON PURPOSE — FOUR TEMP KNOBS
>
> ```
>  M scripts/systems/biome_director.gd     BIOME_DISTANCE 7500, TRANSITION_DISTANCE 2000
>  M scripts/systems/obstacle_spawner.gd   debug_spawning_disabled = true
>  M scripts/game/frozen_lake_director.gd  debug_lake_interval_override = 135.0
> ```
>
> | Knob | Playtest value | Shipping value |
> |---|---|---|
> | `BiomeDirector.BIOME_DISTANCE` | 7500 | **75000** |
> | `BiomeDirector.TRANSITION_DISTANCE` | 2000 | **24000** |
> | `ObstacleSpawner.debug_spawning_disabled` | true | **false** |
> | `FrozenLakeDirector.debug_lake_interval_override` | 135.0 | **0.0** |
>
> The two biome knobs are the owner's, from an earlier session, and are deliberately long-lived.
> The other two were set on 2026-08-14 so the lake could be reached in ~2 minutes instead of 20.
>
> **`shipping_values_check` fails until all four are reverted; `-- --allow-temp` downgrades it to
> a warning and lists them.** Revert the lake ones with:
> `git checkout scripts/game/frozen_lake_director.gd scripts/systems/obstacle_spawner.gd`
>
> **Every other file is committed.** `Glossy Frozen Lake.png` (+ `.import`) is the owner's
> reference screenshot, untracked on purpose — nobody has asked for it to be committed.

---

## What this feature is

Every **20 minutes of cumulative playtime**, the player reaches a **7500px sheet of dead-flat
ice** and crosses it in **exactly 10 seconds**. Nothing spawns on it — no coins, no air lines,
no diamond, no powerups, no obstacles, no trees. **Jumping is disabled.** The surface is glossy
and reflects the mountains, the pines and the player. The first one earns the project's first
achievement, **"Still Water"** (id `still_water`). An aurora borealis set piece is planned as
the second, so the shapes built here should generalise.

The reference is `Glossy Frozen Lake.png` in the repo root.

### Decisions settled with the owner — do not reopen

| Question | Decision |
|---|---|
| Recurrence | Every 20 min of cumulative playtime, forever. First grants the achievement. |
| Achievement backend | **In-game only.** No Google Play Games. |
| Lake colours | **Whatever biome is current.** No new palette, no new ice tile. |
| Interval alignment | Plain 20 minutes, never aligned to the biome cycle. |
| Run-length gate | **KEEP IT.** Re-confirmed 2026-08-14 after play — see "The timing question" below. |
| Achievement name | **"Still Water"** |
| Reflection technique | Screen-space mirror shader, **not** duplicated parallax layers or a SubViewport. |

---

## State: steps 1–5 of 9 are committed and PLAYTESTED

Branch `terrain/disable-mega-drop-camera-shake`. Nothing is half-finished.

| # | Commit | What |
|---|---|---|
| 1a | `e42f39d` | Atomic save write (temp file + rename) |
| 1 | `0a3c333` | SaveStore v3: `total_playtime_seconds`, `frozen_lake_count`, `achievements`; playtime banking |
| 2 | `e6e6e97` | The 7500px forced flat segment, `arm_lake()`, the terrain gate's lake pass |
| 3 | `98a9a05` | `Player.is_jump_suppressed` |
| 4 | `5a4d9a4` | Six spawner suppression guards |
| 5 | `0c5f9a9` | `FrozenLakeDirector` — the lake now actually happens |

**The owner played it on 2026-08-14 and approved: "other than that it's good."** They rode a
real lake at 2:15 into their third run. So the terrain, the input lock, the suppression and the
schedule are all confirmed working in play, not just in probes.

### Steps remaining

| # | What | State |
|---|---|---|
| **6. NEXT** | The reflection — `shaders/frozen_lake_reflection.gdshader` + a `Node2D` in `main.tscn` | not started. **The big one.** |
| 7 | The "Still Water" achievement + its on-screen notification | not started |
| 8 | Fold a lake case into `terrain_invariant_check` beyond what step 2 added, if step 6 needs it | probably nothing to do |
| 9 | Docs — `CLAUDE.md`, `terrain.md`, `visuals.md`, `input.md` | partly done, see below |

---

## Step 6 — the reflection. Everything already worked out

**Do not redesign this.** Three techniques were researched and two rejected.

**USE: a single quad with a `hint_screen_texture` shader**, mirroring `SCREEN_UV.y` about the
waterline. It reflects the ridges, pines, snow and the player automatically, because it is a
copy of the frame that was just drawn. **Rejected:** duplicated y-flipped parallax layers (four
more procedural layers, can't reflect the player, needs its own clipping) and a mirrored
SubViewport camera (renders the scene twice).

**Node type and position — a world-space `Node2D` child of `Main`, inserted directly after the
`TerrainGenerator` block in `main.tscn`. NOT a `CanvasLayer`.** A `CanvasLayer` at layer 0 draws
above the root viewport canvas *regardless of tree position* — which is exactly why the UI layer
at `main.tscn:147` works — so slotting one "between the world and the UI" would depend on a
same-layer tie-break the project has never relied on and that silently inverts if anyone reorders
the scene. A later sibling `CanvasItem` in the root canvas draws after Sky (-200), Parallax
(-100), Birds (-60), Snow (-50), `Player` (:105) and `TerrainGenerator` (:109), and before the UI
layer, using only tree order — the rule this project already documents ("no `z_index` anywhere").

**Full-screen quad, rebuilt every physics frame**, with the top half clipped to `alpha = 0` in
the shader. Full-screen because the automatic backbuffer copy's region derives from the item's
rect and **rect-mode copies are the known-buggy path on the Mobile renderer**; a full-screen rect
is the universally-exercised case, and a transparent top half costs one blend op per pixel.
Rebuilt per frame because the waterline is a **world** y that rebasing moves — read it through
`get_surface_world_y()` and it is rebase-correct for free, and `get_viewport_rect().size /
camera.zoom` handles `aspect="expand"` correctly.

Three things to build in from the start:

- **Clamp and zero alpha outside `[0,1]`**, or a waterline near the screen top wraps the sky in
  from the bottom.
- **Use a `wobble_time` uniform the director advances, not `TIME`.** `TIME` keeps running while
  the tree is paused, so the wobble would animate behind the pause overlay. The director is
  pause-frozen, so it stops for free.
- **`visible = (phase == ACTIVE)`.** The single most important line: a hidden `CanvasItem` is
  never rendered, so the backbuffer copy never happens. Zero cost for 19m50s of every 20 minutes.

**`BiomePalette.reflection_strength` is the mix.** Authored 0.2–0.7 across all nine palettes
(`resources/biomes/*.tres`), already blended per-frame at `biome_palette.gd:325`, and **read by
nothing** — this is its first consumer.

### What the reference actually shows (measured, use these numbers)

Sampled from `Glossy Frozen Lake.png` (698×214):

- **Waterline at 62% down the frame** (y=133/214); the lower ~38% is lake.
- **A bright rim exactly at the shore** — the two rows at the waterline jump to RGB(201,212,225)
  then (224,234,243), brighter than both the land above and the ice below.
- **The reflection darkens steadily with depth**, it does not fade to a flat colour. At x=330 the
  samples run 148 → 133 → 125 → 106 at 10/25/45/70px below the line.
- **The mirror is weak, ~30–40% mixed.** At x=200, 45px above the line reads 182 but 45px below
  reads 132. A 1:1 mirror will look wrong *and* cost more.

**Two of those traits are already implemented.** `ice.gdshader`'s parked gloss uniforms
(`gloss_strength`/`gloss_depth`/`gloss_softness`, lines 65-67, never written from GDScript) are
exactly a bright band at a tunable depth below the surface — that is the shore rim. The depth
darkening is what the existing surface/depth vertex-colour ramp already does.

### The owner's own words on the look, 2026-08-14

> "make it a flat ice that's like horizontal no mountains and stuff, so the bottom of the screen
> is like 20 feet down for all the other biomes, but this time the bottom of the screen is the
> same y level as her feet right. just like the picture. and yeah glossy and reflective."

**Reading, to be confirmed in play:** the lake's surface is a dead-flat horizontal line at the
player's feet, and everything below it becomes **mirror** instead of the usual deep-ice mass that
fills the lower screen. The parallax mountains stay where they are *above* the line — they are in
the reference too, and they are what the mirror reflects. It is the *ground* that has no hills,
which step 2 already delivers. **If this reading is wrong, it most likely means the camera should
also frame the lake differently, which nothing in the plan currently does.**

### Snow will be reflected falling upward, and that is correct

`SnowDrift` is CanvasLayer -50, so it is in the backbuffer. A real mirror shows falling snow
rising, and it is the strongest cue that the surface is a mirror rather than a texture. **Ship
it.** If a playtest hates it, the fix is lerping `snow_density_scale` toward 0 across the lake,
**not** reordering `SnowDrift` (pinned behind all gameplay deliberately).

### After step 6, `CLAUDE.md` line ~205 stops being true

"**Exactly one `.gdshader` exists**" — this will be the project's second shader, and its first
screen-reading one. Fix it in step 9 along with the `visuals.md` draw-order and backbuffer notes.

---

## The timing question — asked, answered, closed

The owner played three runs (1:52, 1:00, 2:15) and expected the lake ~23s into the second.
It arrived at 2:15 in the third. **That is correct behaviour, and they re-confirmed the design
after having it explained.**

Arithmetic: 112 + 60 = 172s banked, threshold 135s, so the lake was *due* from the start of run
3 — but `LAKE_MIN_RUN_TIME` (130s) blocks it until the run is past the speed ramp. It armed at
130s and the player entered ~4s later (the ~3072px arm-ahead distance).

**Why the gate exists**: the lake is a fixed 7500px, so its duration is set by speed.
`SpeedManager` caps at MAX_SPEED (750) at t=120s, so past that the crossing is exactly 10.0s.
Firing 23s into a run means ~250 px/s and a **30+ second** crossing. Measured during
verification: with speed unpinned the crossing took **39.4s**.

**The accepted cost**: the lake lands on the first run that survives ~2 minutes after the clock
is up, not the instant it crosses. Offered alternatives (drop the gate and scale the lake length
from live speed; or lower the gate to ~60s) were **declined** on 2026-08-14.

---

## Things that will bite you

- **THE DIRECTOR HARD-SKIPS HEADLESS, SO NO HEADLESS PROBE CAN TEST IT.** Verify it with a
  windowed run (`--script` without `--headless`), like `sky_layer_check.gd`. The skip is not an
  optimisation: the trigger reads cumulative playtime out of `save.dat`, so an ungated director
  would inject terrain into every gate depending on how much the developer had played — the
  `apply_upgrades()` failure (48/48 → 8) with a different field.
- **A WINDOWED PROBE HOLDS NO FOCUS**, so `NOTIFICATION_APPLICATION_FOCUS_OUT` pauses the game on
  frame one and the player sits at x=64 forever. Re-assert `set_state(PLAYING)` each frame.
- **SETTING `speed_manager.elapsed_time` DOES NOT SET THE SPEED.** `SpeedManager.update()` is
  incremental by design so probes can pin `current_speed` (its own comment says so). Pin
  `current_speed = SpeedManager.MAX_SPEED` as well, or measurements are taken at ~100 px/s.
- **GREP WHOLE LOGS FOR `SCRIPT ERROR|Parse Error|Failed to load`.** A probe filtered through a
  narrow grep reported *nothing at all* while failing to parse, and two gate runs had to be
  repeated because the filter matched only banner lines and discarded the measurements.
- **`get_tree()` DOES NOT EXIST IN A `SceneTree` SCRIPT.** `self` is the tree; use `paused`.
- **A NEW `class_name` NEEDS `Godot --headless --editor --quit --path .`** before any gate will
  compile, and that can strip 40 lines from `project.godot`. `git diff project.godot` afterwards
  is not optional. (It happened not to strip anything on 2026-08-14 — do not rely on that.)
- **`lake_segment_index` MUST NOT BE CLEARED MID-RUN.** The segment is behind the player and must
  stay in the height field, or every cached chunk and collision sample behind them would disagree
  with a fresh sample of the same x.
- **DO NOT REUSE `is_boosting` FOR THE INPUT LOCK.** It also forces the grounded gravity-free
  velocity model (`player.gd`, LOAD-BEARING FOR CHASMS), so a player entering airborne would sail
  flat across the lake instead of landing on it.
- **DO NOT FORCE-END BOOST OR GLIDE AT LAKE ENTRY.** Deliberately not done: the lake is flat,
  void-free and obstacle-free, so both expire normally through `can_end_effect()`, and
  force-ending would add a call site to the `active_effects`/`Player` desync class.

### The purity relaxation, stated correctly

`get_terrain_height` stays pure in `(session_seed, world_x)` **plus one runtime input**,
`TerrainGenerator.lake_segment_index`, under a **write-once, write-ahead** rule: `arm_lake()` may
only set it to an index **strictly greater than `highest_cached_segment_index`** — a segment whose
spec, length, start_x and baseline have never been computed. Segment caches only grow forward and
are never trimmed, so that index is provably virgin. The consequence is the property the invariant
actually protects: **arming can only EXTEND the height field, never REWRITE it.** `arm_lake()` is
the only writer and enforces the rule itself. **Never assign `lake_segment_index` directly.**

---

## Damage report — the developer's save file

**My step-1 verification probe deleted `user://save.dat` — the real one — at the start and end of
its run.** Whatever best score, wallet and upgrade levels were in it before 2026-08-14 are gone.
The file now reads `best_score: 19, best_time: 21.5s, coin_wallet: 67, upgrades: {}`, which may be
genuine play since or may have been written by the headless gates (they call `record_run` on
player death). The owner has been told.

**Rule going forward: a probe must never touch `SaveStore.SAVE_PATH`.** Back it up and restore it,
or point the test at a temp path. Note the gates *already* write to it on player death — that is
pre-existing, not introduced here.

---

## How to verify

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot

# Before every commit. Reports the four temp knobs above with --allow-temp.
$GODOT --headless --path . --script res://scripts/debug/shipping_values_check.gd -- --allow-temp

# Terrain, including check_frozen_lake()'s five assertions (span, flatness, both seams,
# ground throughout, no chasm at the pinned index).
$GODOT --headless --path . --script res://scripts/debug/terrain_invariant_check.gd -- --seeds=8 --to=300000

# Physics set. Required for anything touching get_terrain_height, the player or collision.
$GODOT --headless --path . --script res://scripts/debug/freeze_replay_runner.gd -- --seed=941462462 --frames=60000 --runs=1
$GODOT --headless --path . --script res://scripts/debug/floor_flicker_probe.gd -- --frames=20000
$GODOT --headless --path . --script res://scripts/debug/chasm_probe.gd -- --seed=683407368 --chasms=3 --phases=4
$GODOT --headless --path . --script res://scripts/debug/camera_shake_probe.gd -- --seed=941462462 --frames=7000 --warmup=120
```

**Step 6 additionally needs the windowed visual checks** — `sky_layer_check.gd`,
`biome_contact_sheet.gd`, `ice_look_capture.gd`, all **without** `--headless`.

### Baselines, all green at `0c5f9a9`

| Gate | Value |
|---|---|
| `terrain_invariant_check` | 8 seeds PASS, `max_slope=20.13°` |
| lake pass | `flatness=0.000000`, span exactly 7500.0 |
| coin density | 0.3259–0.3464 per slot (band of record: 0.3163–0.3521) |
| `freeze_replay_runner` | 60k frames `no_freeze`, 0 stall recoveries |
| `chasm_probe` | 48/48 |
| `floor_flicker_probe` | flip rate 0.0000, **largest forced snap 1.8633px**, 0 recoveries, 0 stuck |
| `camera_shake_probe` | mean jerk 0.006 flat / 0.04–0.049 hills; **no `frozen_lake` row** (lake inert by default) |
| lake crossing | **exactly 10.00s over 7500.0px**, measured windowed |

**1.8633px is the pre-existing baseline**, unchanged across every step — it is the sharpest
no-regression signal available here. **The absence of a `frozen_lake` row in camera-shake's
segment table is the proof the lake is inert when nothing arms it.**

---

## Reference — still true, from the earlier visual pass

These are unchanged by the lake work and still cost real time if forgotten.

- **"IT LOOKS GREY" USUALLY MEANS SATURATION, NOT BRIGHTNESS.** Deep ice at RGB(72,82,97) has a
  blue/red ratio of 1.35 but only **26% saturation**. Three fixes were built and discarded chasing
  brightness; the real fix was two numbers in one `.tres`. **Compute saturation first.**
- **DEEP ICE IS HARD-CAPPED AT `ice_depth × 0.38`** (`ICE_TILE_DEPTH_FLOOR`, matched to the tile
  builder's `OUTPUT_FLOOR`), so even a pure white `ice_depth` renders as a 0.38 grey.
- **`ice_contrast` DOES NOT AFFECT DEEP ICE** — the shader fades it out by `UV.y = 0.95` so the
  band's bottom row meets the flat fill without a seam. Surface knob only.
- **THE HUE DRIFT ONLY EVER DARKENS**, and its warm half removes blue plus half as much green, so
  a colour whose red is close to its blue lands on neutral grey at the warm end.
- **THE SHEAR FINDING.** `build_ice_band()` pins the tile's `V=0` row to the terrain surface, so a
  pattern of long horizontal streaks fans downward on a hill and reads as flowing hair. The
  statistic that catches it is horizontal coherence length. **On a flat lake nothing shears** —
  which is why `six.png` was reserved for it.
- **The ice tile is a MULTIPLIER and repeats every 1200 world px.** Anything with structure at that
  period becomes a permanent vertical line.
- **`COLOR` is in-out in a `canvas_item` shader** — on entry to `fragment()` it already holds
  `vertex_color * texture(TEXTURE, UV)`. See `docs/research/ice_shader_color_semantics.md`.
- **No two adjacent biomes may both have a sun/moon disc**, and a disc-less biome must copy its
  disc-having neighbour's `celestial_position`. Both gate-enforced.
- **THE OPENING BIOME IS ALMOST IMPOSSIBLE TO PLAYTEST WITHOUT `debug_pin_intro_biome`.**

### Measurement traps — every one produced a confidently wrong answer

1. **Windowed probes read all-zero if the display is asleep or occluded**, and pause themselves if
   the window lacks focus. Confirm a suspected regression by stashing and running on clean `HEAD`.
2. **`mauve_haze`'s IceHue sits EXACTLY on the 24/255 floor**, so it fails intermittently.
3. **Never compare pixel numbers across two RUNS.** A/B inside one frozen frame (`ice_seam_probe`).
4. **`Engine.time_scale = 0` is not a safe freeze.** Use `SceneTree.paused`.
5. **Apply, wait a frame, *then* capture.** `root.get_texture()` returns the frame already rendered.
6. **Hide the sprites before measuring** — trees, player and coins produced four false positives.
7. **Sample at constant DEPTH BELOW THE SURFACE, not constant y.** The tile's V axis is depth.
8. **Any long-running harness needs obstacles AND chasms disabled**, or the player dies, the tree
   pauses, and the probe measures a stationary game for the rest of its frames.
9. **Count items, never containers.** `CoinSpawner` and `GroundTreeSpawner` each create one empty
   per-chunk `Node2D` group whether or not anything goes in it, so a naive descendant walk reports
   ~15 false intruders on any 7500px span.

---

## Deferred, deliberately — do not act on these unprompted

- **More upgrade tracks** (magnet radius, powerup duration). Analysed 2026-08-14: the combo now
  multiplies every banked coin, so a 2-minute run banks ~270 rather than ~168, and the 1130-coin
  curve empties in **~4 runs, not 8–15**. Cost numbers in the plan file are stale in that
  direction. **Cut `coin value` from the list** — it is a sink that raises income.
- **Two documented gates do not exist.** `check_upgrade_curve()` and `check_obstacle_clearance()`
  are named in `CLAUDE.md:142`, `upgrade_store.gd:57` and `obstacle_spawner.gd:56`. Neither is
  anywhere in `scripts/debug/`. The offered one-line fix (fold
  `UpgradeStore.get_max_jump_multiplier()` into `CHASM_LEAD_IN_TOO_SHORT`) is still awaiting a go.
- **Diamonds as a second currency** — needs SaveStore v3 (now done) but there is still nothing to
  spend it on.
- **Phase 4's original "glass lake biome"** is superseded by this feature. `six.png` remains
  unbuilt in the repo root.
- **Rarity — `glacier_teal` only.** Decide after playing chained sessions.
- **Glide vertical drift on the parallax layers.** Design in `look-thorugh-my-files-wobbly-church.md`.
- **Also found and unscheduled**: `SfxPlayer` has no `process_mode`, so death/menu SFX play into an
  already-paused tree; `ensure_segment_cache_for_world_x` loops forever on ±INF; six silent
  `push_error(); return` paths in `GameManager._ready()` can leave a live game under an
  undismissable `StartScreen`.

---

## Working agreement

**One numbered sub-step at a time. Commit it alone. Then stop and wait for an explicit "go".**
The owner play-tests between steps; silence is not consent. Do not batch.

**Verify with measurements, not reasoning.** Several changes in this feature looked correct and
were wrong underneath — and several *probes* were wrong while the code was right. When a probe
fails, suspect the probe first.

**Flag the expensive option before building it.** The owner's standing instruction: if something
has a lot of potential to cause bugs or is excessively hard when another option exists, say so and
let them choose.

**Do not self-verify visuals with screenshot captures.** The owner checks in-game faster.
