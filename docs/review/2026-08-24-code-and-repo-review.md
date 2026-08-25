# Aura review — 2026-08-24 (code + repo)

Read-only pass over the whole tree. Nothing was changed. Everything below was verified
against the files as they stand, not inferred from docs or commit messages; where a number
is quoted, the measurement command is named so it can be re-run.

**This is the single 2026-08-24 review.** A second audit, `2026-08-24-project-audit.md`, was
written earlier the same day and covered repo hygiene and release readiness; its findings were
re-verified and folded into this file (Android export in P2, engine patch as #9, the validation
runner as #10, and the watch list below), and that file was deleted. Do not re-create it — one
file per review date, or the two drift apart the way the background docs did.

## Gates run during this review

| Gate | Result |
|---|---|
| `shipping_values_check.gd` | **PASS** — 16 knobs at shipping values, scene clean |
| `biome_schedule_check.gd` | **PASS** — 8 palettes, 8 ice variants |
| `terrain_invariant_check.gd --seeds=8 --to=300000` | **PASS** — 0 violations, max slope 20.13°, 8/8 seeds |

Not run: freeze-replay/search, floor-flicker, chasm, lake-suppression, the three windowed
visual gates. Core terrain and collision geometry are healthy; **no finding below is a
current crash or a broken run.**

---

## P0 — real defects

### 1. Pausing inflates cumulative playtime, so the frozen lake fires early

`frozen_lake_director.gd:174`

```gdscript
return services.save_store.total_playtime_seconds + main_node.elapsed_time
```

`GameManager.bank_playtime()` (`game_manager.gd:401-418`) already folds the current run into
`save_store.total_playtime_seconds` on **every** `PLAYING → not-PLAYING` transition, and
advances `banked_run_seconds` to match. It is correct on its own. The lake director is not
aware of it and adds the whole of `main.elapsed_time` again.

Concretely: pause at t=120s → `total_playtime_seconds += 120`. Resume, reach t=200s → the
director computes `base + 120 + 200` instead of `base + 200`. **Every pause adds phantom
playtime equal to elapsed-at-pause**, and it compounds within one run.

This is worse on the shipping platform than it looks: `game_manager.gd:454` pauses on
`NOTIFICATION_APPLICATION_FOCUS_OUT`, so on Android *every notification or app switch* pays
the penalty. Three pauses at 3/6/9 minutes credit +18 phantom minutes — enough on its own to
cross `LAKE_INTERVAL_SECONDS = 1200`. The set piece meant to appear every 20 minutes of real
play can arrive in a single run.

Fix is one expression: subtract the already-banked part —
`total_playtime_seconds + (main.elapsed_time - game_manager.banked_run_seconds)`. The
director has no `GameManager` reference today, so it needs one (null-guarded, same style as
`main_node`), or `GameManager` needs a `get_unbanked_seconds()` accessor. **Prefer the
accessor** — it keeps the arithmetic in the file that owns `banked_run_seconds` and gives the
planned aurora (build-order #12, same cumulative-playtime gating) one correct call to reuse.

### 2. `HANDOFF.md` actively misdirects the next session

It is the first file a new session reads, and its two load-bearing statements are now false:

- `HANDOFF.md:209` — *"the background code … is still identical to `7ffd9f7` — nothing from
  this session has touched it."* Eight commits since the revert (`56f704a` … `66ef080`,
  confirmed with `git log 95d9ca4..HEAD -- scenes/main.tscn scripts/systems/background_*`)
  rewrote it: `IceStrip` was added to `main.tscn`, `background_strip.gd` was written,
  `ice_pano.png` was baked, and every layer's `motion_scale` and `depth_t` changed.
- `HANDOFF.md:226` — *"None of this ships."* `assets/textures/experiments/` is **3.8 MB under
  `assets/`** with `.import` files already generated, and `export_presets.cfg:11` is
  `export_filter="all_resources"`. It ships.

The whole document is also written around `PineLine`, a node that no longer exists.

### 3. Parallax depth was flattened, and it is the thing the owner said worked

`main.tscn` vs `7ffd9f7`:

| Layer | was | now |
|---|---|---|
| FarPeaks | 0.030 | 0.015 |
| FarRidge | 0.060 | 0.025 |
| MidRidge | 0.140 | 0.035 |
| PineLine → IceStrip | 0.300 | 0.050 |

The near-to-far ratio went from **10:1 to 3.3:1**, and the fastest layer is now **6× slower**.
`HANDOFF.md:17-18` records the owner's own words on what was working: *"the front layer moves
faster than the ones behind it, so it really does come together."* That separation is largely
gone. I cannot tell from the commits whether this was a deliberate re-tune for the panorama
or drift across eight commits — worth an explicit decision either way, and it is a
four-number change in `main.tscn`, not a code change.

### 4. The panorama repeats every ~55 seconds, on the frontmost layer

> **CLOSED 2026-08-25 — re-measured at 106.1 s / 79,590 world px, 29% on screen.** The strip
> was re-baked from a wider source (3548 → 5220 px) and `source_skyline_y` moved 242 → 302,
> which together took `motion_mirroring.x` from 2048 to 3979 layer px. The loop is now 1.06
> biome cycles rather than 0.55, so a repeat cannot land inside the same biome. The two inputs
> are **not** independent — `display_scale` divides by `source_horizon_y − source_skyline_y`,
> so the skyline row is also a loop-period knob. Full working in `HANDOFF.md`, open decision 2.
> The arithmetic below is the pre-widen state and is kept because it is the method.

`ice_pano.png` is 3548×887. At the scene's `skyline_y_fraction 0.33` / `horizon_y_fraction
0.55` and a 648px viewport, `display_scale` = 0.577, so `motion_mirroring.x` = 2048 layer-px.
At `motion_scale 0.05` the loop covers **40,956 world px ≈ 55 s at MAX_SPEED** (82 s at 500
px/s). The viewport is 1152px wide, so **56% of the panorama is on screen at once** — the
repeat is not subtle, and this is now the largest, sharpest, most silhouetted background
element. For comparison the biome cycle is 75,000 px, so it loops ~1.8× per biome.

The three procedural layers never repeat (hash-driven). Moving the panorama to the front
traded non-repeating for repeating on the most visible layer.

Options, cheapest first: raise `motion_scale` (also helps #3, but shortens the loop in
*time*); bake a wider strip; or accept it and note it. **Do not** add a second offset copy —
`ParallaxLayer.motion_mirroring` is one span by construction and a second sprite reintroduces
the tear the `centered = false` comment exists to prevent.

---

## P1 — silent-drift risks

### 5. `biome_schedule_check` no longer measures what the scene renders

`get_scenery_color(depth_t)` lerps `scenery_far → scenery_near`. The scene's `depth_t` values
were `0.0 / 0.22 / 0.58 / 1.0`; they are now `0.0 / 0.15 / 0.30 / 0.45`. **`scenery_near` — the
darkest authored colour in all nine palettes — is never rendered.** Only the far 45% of every
ramp reaches the screen.

The gate (`biome_schedule_check.gd:225`) asserts `|lum(scenery_far) − lum(scenery_near)| ≥
MIN_SCENERY_SEPARATION (0.08)` *"or the parallax layers collapse into one flat mass."* It
measures the authored endpoints, so it cannot see this at all. Measured actual shipped
separation:

| palette | authored | shipped (0→0.45) |
|---|---|---|
| pale_morning | 0.223 | **0.100** |
| starlit_night | 0.257 | 0.116 |
| first_light | 0.262 | 0.118 |
| … | … | … |
| sunset_rose | 0.367 | 0.165 |

Everything still clears the 0.08 floor, so **nothing is broken today** — but `pale_morning`
has 25% of its headroom left, and the gate would keep passing all the way to collapse. Same
blind spot applies to `check_gameplay_contrast` (`:355`), which compares coin/obstacle colours
against `scenery_near`.

Fix: have the gate read the actual `depth_t` values out of `main.tscn` and evaluate
`get_scenery_color` at the extremes the scene really uses. That is the difference between a
gate that guards a property and one that guards a data file.

### 6. Run-length cliff — MEASURED 2026-08-24, CLOSED

**Status: closed, not a risk.** This was the review's top "disastrous later" item. It has now
been measured clean through 2^21 and should be struck from the risk list. Full write-up in
`docs/research/x_precision_cliff.md`; summary here.

The old `world_rebaser.gd` comment — *"X precision does eventually degrade too, but only
around x ~ 1e6 (~33 minutes of play)"* — was wrong twice, and both are now fixed in the file:

- **"x ~ 1e6" is the wrong shape of number.** float32 resolution halves at powers of two, so
  the only thresholds are 2^19 (12.1 min), **2^20 = 1,048,576 (23.7 min)** and 2^21 (47.0 min).
  Nothing happens at 1e6.
- **"~33 minutes" was wrong outright.** The first real step down is 23.7 min. 33 min is
  x ≈ 1.5e6, mid-band.

**The soaks: clean, both bands.** `freeze_replay_runner` on three seeds each:

| soak | play time | reached x | result |
|---|---|---|---|
| `--frames=130000` | 36 min | 1.571 M (past 2^20) | 3/3 `no_freeze`, `stall_recoveries=0` |
| `--frames=200000` | 55 min | 2.428 M (past 2^21) | 3/3 `no_freeze`, `stall_recoveries=0` |

2^21 was the band that mattered — it's where a 0.25 px separation quantises to exactly
`floor_max_angle`. The next band, 2^22, needs 94 minutes of unbroken play in a single run.

**The one historical data point was a red herring.** The net-progress stall recorded at seed
222894852 / world_x 1,166,358 sits past 2^20, which made it look like evidence. `freeze_search`
re-tested that region against a low-x control: 0 stalls, 0 near-stalls, both. It was the
`large_valley` 80.4° wall-stall (`freeze_bug.md` Bug 2), since removed. Don't cite it here.

**Consequences are milder than assumed anyway.** Both watchdogs are called unconditionally in
`_physics_process` — no `is_debug_build()` gate — so the backstop ships. Worst case is a
recoverable ~1 s hitch, not a hard freeze.

**Still true and worth keeping:** no *gate* reaches any of this — the 60,000-frame gate stops
at x ≈ 732,000, one band short — so a passing gate is never evidence about long-run behaviour,
and the soak is far too slow (~55 min) to become one. That asymmetry is permanent; it is the
reason the measurement lives in `docs/research/` as a procedure rather than in the gate list.

**Do not build the X rebase.** It is costed in the research doc (~44 silent-failure call sites,
8 cached x's, 2 frame-mixing traps, 31 debug harnesses) and is not justified by this evidence.
If a fix is ever needed, raising `Player.safe_margin` is a one-number lever that buys a full
band — untested, and it needs the full physics gate suite.

### 7. Segment caches grow for the whole run and are never pruned

`segment_start_x_cache`, `segment_length_cache`, `segment_baseline_cache` and
`segment_spec_cache` (`terrain_generator.gd:110-113`) only ever gain entries.
`chunk_collision_sample_xs` *is* pruned (`prune_chunk_collision_samples`, radius 10) — these
four are not. At ~1.3 segments/s that is ~4,700 dictionary entries per hour plus a
6-key `Dictionary` each.

Probably fine for normal sessions; measure it in the same soak as #6 rather than guessing.
**Do not add pruning casually** — `arm_lake()`'s write-ahead rule and the deterministic
replay of recorded seeds both depend on cached history staying available.

### 8. `main.gd` depends on tree order with nothing enforcing it

`main.gd:221` — *"Runs before Player/TerrainGenerator (tree order)"* — is a correctness
requirement for `apply_world_rebase()`, with no `process_priority` behind it. A scene reorder
that looks cosmetic changes rebase and camera timing. This is the same class of failure as
the `@export`-serialised `world_rebase_enabled` regression the file's own comments warn about
twice. Encoding it is cheap; treat it as a behaviour change and re-run the camera/freeze/
floor/chasm gates.

### 9. Engine patch release is behind

The project and the installed editor are `4.7.stable`; current stable is
[Godot 4.7.2](https://godotengine.org/article/maintenance-release-godot-4-7-2/), released
2026-08-18. Godot describes maintenance releases as intended to be safe upgrades while still
recommending version control and backups.

Upgrade the editor and the matching Android export templates in an isolated commit, then re-run
the fast gates, the chasm and lake gates, the three visual checks, and one device build. **Do
not move to the 4.8 development line.** Watch `project.godot` afterwards — an `--editor` run
strips the pinned physics settings, so `git diff` it before committing.

### 10. There is no single fast validation command

The custom gates are strong, but there is no runner and no CI, so their protection depends on a
person remembering several commands. Add one script (or CI job) covering project import plus
`shipping_values_check`, `biome_schedule_check`, `terrain_invariant_check` and
`lake_suppression_probe` — all fast. Keep the multi-minute physics soaks and the three windowed
visual gates in separate manual/nightly tiers, since they cannot run headless or cannot run
quickly.

Add to the same runner an export-content check that fails if release output contains
`scripts/debug`, `scripts/experiments`, or `assets/textures/experiments`.

---

## P2 — hygiene, dead weight, and stale docs

**Unpushed / uncommitted.** Local `main` is 16 commits ahead of `origin/main` (`7ffd9f7`);
GitHub has none of the background work. The tree also holds 15 tracked art deletions whose
byte-identical copies are untracked in `art_source/terrain/` and `art_source/background/` —
a `git add -u` alone would record the deletions and lose the new locations. `origin` also
still carries `terrain/disable-mega-drop-camera-shake`, pointing at the same commit as
`main`; it is dead and can go.

**`assets/textures/experiments/` (3.8 MB) and `scripts/debug/` (636 KB, 31 files) ship.**
`export_filter="all_resources"` packages every imported resource, including all 18 archived
probes. Separate dev/release presets, or an exclude filter, plus a check that fails a release
build containing `scripts/debug`, `scripts/experiments`, or `assets/textures/experiments`.

**`build_iceberg_sprites.py` is dead.** 31 KB, committed in `deb8677`, writes to
`assets/textures/background/iceberg_*.png` — none of which exist. Its documented example
input `art_source/berg_shelf_01.png` does not exist either. The approach was abandoned two
commits later for the panorama strip. It reads authoritative and will mislead someone. Delete
it or move it under a clearly-superseded heading.

**Stale doc/comment locations** (all verified):

- `docs/development/architecture.md:12` — still lists `FarPeaks/FarRidge/MidRidge/PineLine`,
  no `IceStrip`.
- `docs/development/visuals.md:24-32` — the draw-order table still carries the old
  `0.30/0.14/0.06/0.03` motion scales and `PineLine`; `:165` and `:176` reason from them.
  `:285` uses the pre-split `art_source/three.png`.
- `docs/development/dead_code.md:36` — "four layers, `motion_scale.x` 0.03 to 0.3".
- `background_strip.gd:7` calls the panorama "the far layer"; it is frontmost at
  `depth_t 0.45`. `:51` reasons from `motion_scale 0.03`; the scene uses `0.05`.
- `scripts/tools/build_pano_strip.py` — calibration prose assumes the strip sits at
  `depth_t 0.0`.
- `scripts/tools/build_ice_texture.py:5` — example uses `art_source/three.png`.
- `art_source/README.md` — describes the pre-split flat layout.
- `.claude/settings.local.json` — allowlists `scripts/debug/mega_drop_visual_probe.gd` (now
  in `archive/`) and a `thirteen.png` at the repo root that does not exist.

**Small cruft.** Orphaned `art_source/peep.png.import` and
`art_source/transition4peep.png.import` (their PNGs are gone, and `art_source/.gdignore`
means Godot should not be generating them there).
`art_source/ChatGPT Image Aug 6, 2026, 07_13_24 PM.png` needs a real name.
`project.godot` carries `3d/physics_engine="Jolt Physics"` and
`rendering_device/driver.windows="d3d12"` in a 2D mobile game — harmless, but noise in a file
that is otherwise deliberately curated.

**The pause screen's Music slider does nothing audible.** The `Music` bus exists
(`audio/default_bus_layout.tres`) and `GameServices` creates a `music_player`, but no stream
is ever assigned anywhere in the project — `SfxPlayer` is the only thing that sets `.stream`.
A player will drag it, hear no change, and read it as a bug. Either hide it until music
ships, or label it.

**Android export is not release-shaped.**
`package/unique_name = "com.example.$genname"`, `version/code = 1` with an empty
`version/name`, no launcher/adaptive icons, `export_format = 0` (APK, not AAB), empty
`min_sdk` / `target_sdk`, and `export_filter = "all_resources"` with no exclusions. The
`aura.apk`/`.idsig` at the repo root are from 2026-08-03 — before all 16 unpushed commits and
much of the present project — and are not current deliverables. Inspecting that APK confirmed
`all_resources` packages the debug probes; the untracked `assets/textures/experiments/`,
`scenes/experiments/` and `scripts/experiments/` will be packaged too while they sit under
shipping paths.

Fix: separate development and release presets (or explicit include/exclude filters), exclude
debug/archive/experiment material from release, set the real application ID and versioning,
configure final icons and signing outside Git, and only then produce a fresh artifact.

**`README.md` is one line.** Add a short real one — setup, run, gate commands, release steps —
and keep `CLAUDE.md` a map rather than a second implementation manual.

**Comment ratio.** 10,767 shipping GDScript lines, 4,541 of them comments (**42%**). The
comments are unusually high quality and mostly record measurements — but items #3, #4 and the
`background_strip.gd` header above are the failure mode: narrative duplicated next to code
drifts faster than it gets maintained. Keep contracts and measurements adjacent to the code;
move investigation history to `docs/research/`.

---

## Watch list — measure before changing

- **Segment caches are never pruned** — see #7. Measure in a soak; do not prune casually.
- **`SkyBackdrop` rebuilds its generated textures on every scene reload** — a 256×256 moon and
  a 1024×576 star texture (`sky_backdrop.gd:415`, `:467`). Profile restart time on the target
  phone; cache across reloads only if the measurement says to.
- **Two run clocks.** `Main.elapsed_time` (`main.gd:90`) and
  `Player.speed_manager.elapsed_time` (`speed_manager.gd:17`) are duplicates read by different
  systems. They advance together today, but one authoritative clock would remove a future
  pause/restart drift class — the same class as #1.
- **Debug editor runs force the first powerup to 5 s**
  (`powerup_spawner.gd:47`, `debug_first_powerup_time_override`), so ordinary editor
  playtesting never exercises the release first-spawn cadence. Keep the convenience only while
  it stays clearly a debug mode.
- **`BiomePalette.mist_strength` has no renderer.** It is authored per palette and blended in
  `biome_palette.gd:330`, but nothing reads it. Implement it when mist is scheduled or remove
  it; speculative data that no gate covers is how a palette field goes quietly wrong.

## Confirmed healthy (checked, no action)

- All `res://` references resolve; no orphaned `.uid`; all 9 ice tiles referenced by a palette.
- Every spawner correctly defers seed-derived init to the first `_physics_process` — the
  documented `_ready()` trap is not present anywhere.
- The six spawner hash functions use genuinely distinct multiplier pairs; no cross-system
  correlation. `background_generator` keys off `rng_salt`, not `session_seed`, so its shared
  multipliers with `terrain_generator` are harmless.
- `SkateTrack` and `SkateSpray` both handle world rebasing explicitly despite sitting outside
  the `TerrainGenerator` subtree.
- Celestial discs sit at y-fraction 0.08–0.09; the ice strip's skyline is 0.33 and the tallest
  ridge ~0.20. The "There has to BE a sky" occlusion bug has **not** regressed.
- `project.godot` is clean in `git status` — no stray editor rewrite.

## Suggested order

1. Fix #1 (playtime double-count) — smallest diff, real gameplay impact, and the aurora will
   inherit the same call.
2. Decide #3, #4 and #5 with the owner before touching them; all three are background/parallax
   numbers that belong to the visual pass in flight, not to a cleanup.
3. Rewrite or retire `HANDOFF.md` (#2), then one sweep over the stale locations in P2.
4. Commit the art relocation deliberately, then push the 16 commits.
5. ~~Run the soak for #6~~ — **done, #6 is closed.** #7 still unmeasured directly, but six
   soaks of 36–55 min each completed with no slowdown (steady 75 frames/s to the end) and no
   failure, which is weak evidence against it being urgent. Measure memory properly before
   touching it, and re-read the warning there first.
6. Release preset + export-content check and the #10 validation runner, which share the same
   exclude list — do them together.
7. #9 (Godot 4.7.2) in an isolated commit, then #8 (process priority) as a behaviour change
   with the full physics gate suite behind it.
