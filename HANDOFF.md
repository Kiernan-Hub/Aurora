# Handoff — terrain & sky visual pass

Updated 2026-08-13. Delete this file once Phase 4 is done and it has stopped being true.

Plan files: `/Users/kjh/.claude/plans/this-is-how-i-peppy-lark.md` (the original 4-phase pass)
and `/Users/kjh/.claude/plans/wahts-the-nezt-step-melodic-shore.md` (the 2026-08-12 session:
biome persistence, the opening biome).

---

## Read these first

| File | Why |
|---|---|
| `CLAUDE.md` | The map. Traps that cost real time. |
| `docs/development/biomes.md` | Everything that changes colour over a run. Longest and most important. |
| `docs/development/visuals.md` | Layer stack, overdraw budget, the sky composition constraint |
| `docs/development/ice_panels.md` | Making a new ice tile. **Three** distinct failure modes now, not two |
| `scripts/tools/build_ice_texture.py` | Its docstring is the tile pipeline's reasoning |
| `docs/research/ice_shader_color_semantics.md` | Why the shader "darkened" the ice — closed |

---

## State

`HEAD` is on `terrain/disable-mega-drop-camera-shake`. Everything below is committed, and as of
2026-08-13 the working tree is **completely clean** — no temp knobs are currently set, so a
playtest right now shows shipping timings (a biome lasts ~2.3 min through the early ramp).

**Four TEMP knobs**, all uncommitted when set, and all in `biome_director.gd` except one:

```
 M scripts/systems/biome_director.gd   <-- BIOME_DISTANCE, TRANSITION_DISTANCE, debug_pin_intro_biome
 M scripts/systems/obstacle_spawner.gd <-- debug_spawning_disabled, if obstacles are off
```

| Knob | Playtest value | Shipping value |
|---|---|---|
| `BiomeDirector.BIOME_DISTANCE` | 7500 | **75000** |
| `BiomeDirector.TRANSITION_DISTANCE` | 2000 | **24000** |
| `BiomeDirector.debug_pin_intro_biome` | true | **false** |
| `ObstacleSpawner.debug_spawning_disabled` | true | **false** |

`shipping_values_check.gd -- --allow-temp` lists them. **Revert before committing; never commit.**

> **The knobs are why the biome cycle "changes length" between playtests.** With them a full
> cycle is **1.73 min**; with the real values it is **13.74 min**. The user was offered 9000 (a
> clean 2.0 min) as a shipped value and **chose to leave it at 75000** — a decision, not a
> regression.
>
> **At 7500 a ~105-second run is one COMPLETE lap** (measured against the real speed ramp:
> 60 756 px vs a 60 000 px cycle). So dying near that mark lands the resumed phase back near
> where it started and looks exactly like a reset. It is not one. This was raised as a bug and
> is arithmetic.

**Gates against this state** (all at shipping values): `biome_schedule_check` PASS
(`ice_variants=8`, `transition=24000`), `shipping_values_check` PASS (13 knobs) against a clean
tree. `sky_layer_check` PASS (**biomes=9**, 45 layers) and `terrain_invariant_check` PASS on 8
seeds were last run 2026-08-12 and are unaffected by the variant work, which touches no sky field
and no geometry. `project.godot` clean. The physics
gates were not re-run and did not need to be — nothing in this pass touches geometry, collision
or the velocity model.

---

## What shipped before 2026-08-12

Phase 1 (sky), Phase 2a/2b (ice hue drift, snow cap), Phase 3 (`shaders/ice.gdshader` with a
noise dissolve and per-biome `contrast`), and Phase 2c's tile families. The vertical-line bug in
the ice was found and fixed in the tile pipeline (broad horizontal banding, plus the seam the
half-width roll leaves at tile centre). See git log `2ca5938..60fd381`.

## What shipped 2026-08-12

**`5f1900e`, `6c757c2` — the biome phase carries across runs, scoped to the session.**
`GameManager` banks it on death; `BiomeDirector` adds it to `world_x` before the cycle maths.
A full cycle is ~13.7 min and nobody plays that in one run, so most palettes were unreachable
in practice; chaining short sessions walks the arc in order.

> **Random biome order was designed, approved in principle, and DROPPED. Do not revive it.**
> Measured across the eight palettes, ice brightness tracks sky brightness — `ice_surface` falls
> 0.863 → 0.625 and `ice_depth` 0.688 → 0.322 alongside `sky_top` 0.773 → 0.244. A shuffle, or
> splitting the sky schedule from the ground schedule, puts a moon over daylight-bright ice.
> Persistence solves the same problem (nobody sees all eight biomes) without touching the order.

The phase is a **`static var`**, not saved to disk: it survives the `reload_current_scene()` a
restart does, exactly like `GameManager.pending_quick_restart`, and dies with the process. `5f1900e`
persisted it to `save.dat` (SaveStore v3) and `6c757c2` reverted that — a returning player would
eventually open the game straight into the night biome, and index 0 was chosen deliberately as
the first impression. The revert also deleted a save-format migration and its NaN guard.

**`5dbab3a` — `ice_crazed_depth` (from `fourteen.png`) on `arctic_dawn`; `ice_rime_depth` moved
to `pale_morning`.**

**`11b098c` — `first_light`, a NINTH palette held outside `BIOME_CYCLE`.** Substituted for
**absolute** cycle index 0, checked before the `posmod`, so it opens a session once and never
returns until relaunch; index 8, 16, … resolve to `BIOME_CYCLE[0]` as always. Pale, claims no
optional sky layer at all, and its tile `ice_veined_depth` (`fifteen.png`) is the faintest in the
project on purpose.

**`283cf77` — `first_light` tuned to a light blue, and `debug_pin_intro_biome`.**

## What shipped 2026-08-13

**`b9dc8f7` — `ice_sastrugi_depth` pulled off `sunset_rose`.** Its 18px x-coherence, flagged as
"on probation" when it shipped, was confirmed in a rendered frame: the surface reads as combed
strata following the hill silhouette. **The sastrugi prompt is now struck entirely** — the pulled
tile was already the *rewrite* of the prompt that produced the first flow-line failure, so the
family is directional by definition. Replaced by `ice_bubbled_depth` (`art_source/sixteen.png`,
the air-bubble prompt): within-row 0.0282 against the default's 0.0154, 3px x-coherence, a 1.00x
ratio — the least directional tile in the project.

> **Blending two finished tiles to get "a bit of each" was measured and does not work.** At
> sastrugi weights 0.15/0.25/0.40 the x-coherence never rose above 4px while within-row contrast
> fell 0.0282 → 0.0223: the higher-contrast field dominates the correlation, so the statistic goes
> quiet while the streaks are still there on a slope. Mixing characters means ONE panel with both
> drawn in. Written up in `ice_panels.md`.

**`9bfffc3` — rare per-visit variants on three biomes.** `sunset_rose` rolls 50/50 between the
bubbled and sastrugi tiles; `glacier_teal` and `violet_dusk` became **paler as their common case**
with the previously-authored saturated colours kept as a 20% rare version. User-requested, and the
returning sastrugi is deliberate — they were told it brings the flow lines back half the time.

Built as **overrides on the base palette, not duplicate `.tres` files** (`variant_chance` plus four
`variant_ice_*` fields; alpha 0 / negative means "not overridden"). A duplicate would share ~35
fields that must stay identical forever. **Ice-only on purpose**: a variant that moved the sky
would make `sky_layer_check`'s expected values depend on a roll it cannot see.

> **The roll is keyed on `cycle_index` and must stay that way.** `get_cycle_palette` is contracted
> pure in `cycle_index`, and the transition asks for index and index + 1 every frame — a live coin
> flip hands one index two palettes and the ice pops mid-crossfade. Verified pure over 40 indices;
> observed rates 0.495 / 0.190 / 0.189 over 8000.
>
> **Identity comparisons must use `get_cycle_base_palette`, not `get_cycle_palette`.** A variant is
> a `duplicate()`, so it can never `==` anything in `BIOME_CYCLE`. This broke the arc-order and
> one-shot-intro claims in `biome_schedule_check` the moment variants landed, and the failure
> message printed an empty biome name.

**`d8b938a` — `TRANSITION_DISTANCE` 12000 → 24000**, the user's preference from play. The constant
went in with `9bfffc3` and the gate + doc halves followed here.

**Shield desync fixed (the second ordering).** `gain_shield()` now clears
`is_shield_from_glide_landing`. The 2026-08-10 fix guarded *glide lands while holding a powerup
shield*; the mirror — *collect a shield powerup inside the 1s glide-landing window* — was still
live, and the 1s timer then expired the powerup shield with no `shield_consumed`, leaving
`PowerupManager` holding `EFFECT_SHIELD` at INF while the player had none. Found by audit, not by
play. **No gate covers this** — every gate disables powerup spawning — so it is verified by hand
only (glide, land, grab a shield within 1s, wait 2s, hit an obstacle, survive).

---

## Things that will bite you

- **THE OPENING BIOME IS ALMOST IMPOSSIBLE TO PLAYTEST WITHOUT `debug_pin_intro_biome`.** It
  renders at absolute index 0 only, and the phase advances on every death and survives a
  restart. At the shipping `BIOME_DISTANCE` that is the first ~3 minutes of a **cold launch**;
  at the 7500 playtest value it is **18.8 seconds**, after which one death puts it out of reach
  for the whole session. Three rounds of colour edits were made and eyeballed against a
  different biome entirely before anyone noticed. Set the knob before touching `first_light.tres`.

- **"IT LOOKS GREY" USUALLY MEANS SATURATION, NOT BRIGHTNESS.** The most expensive detour of
  this session. Deep ice at `RGB(72, 82, 97)` has a blue/red ratio of 1.35 — which sounds blue —
  but only **26% saturation**, and at that brightness it reads grey. Three separate fixes were
  built and discarded chasing brightness (a per-biome `ice_depth_floor` field with a shader
  remap, a lower `ice_contrast`, a proposed `ICE_BAND_DEPTH` raise). The actual fix was **two
  numbers in one `.tres`**: pull red down, saturation 26% → 50%, same brightness cap.
  **Compute saturation before proposing a mechanism.**

- **THE DEEP ICE IS HARD-CAPPED AT `ice_depth × 0.38`.** `ICE_TILE_DEPTH_FLOOR` is the tile's own
  darkest value, matched to `OUTPUT_FLOOR` in `build_ice_texture.py`, and the flat fill below the
  band folds it in by hand (`get_deep_fill_color`). A colour channel maxes at 1.0, so **even a
  pure white `ice_depth` renders as a 0.38 grey** — no palette value escapes it. More than half
  the screen is that flat fill. If someone genuinely needs lighter deep ice, the lever is the
  floor, and raising it compresses the tile's range and flattens the detail (measured: 0.62 was
  visibly too flat). Prefer saturation.

- **`ice_contrast` DOES NOT AFFECT THE DEEP ICE.** The shader fades it out with depth
  (`surface_weight` reaches 0 by `UV.y = 0.95`) precisely so the band's bottom row keeps meeting
  the flat fill without a seam. It is a surface knob only. It also must stay outside roughly
  0.87–1.13 or its contribution drops under `sky_layer_check`'s 10/255 floor.

- **THE HUE DRIFT ONLY EVER DARKENS**, and its warm half removes blue plus half as much green.
  So a base colour whose red is close to its blue lands on **neutral grey** at the warm end —
  that is a real reported complaint, twice. Keep `b − r` wide enough that `b × (1 − variance)`
  is still comfortably above `r`. Do not "fix" this by scaling up: the renderer is LDR and
  several palettes sit at 1.0 on a channel.

- **A PALETTE OUTSIDE `BIOME_CYCLE` IS INVISIBLE TO EVERY CHECK THAT WALKS THE CYCLE**, which was
  every check in both biome gates. `biome_schedule_check.get_all_palettes()`,
  `sky_layer_check.get_measured_palettes()` and `find_pair_differing_on` all fold `first_light`
  in now, plus explicit `first_light → BIOME_CYCLE[1]` cases for the two disc invariants. It
  caught `first_light`'s `SkyTint` at 11/255 on the first authoring pass.

- **THE SHEAR FINDING (2026-08-11).** `build_ice_band()` pins the tile's `V=0` row to the terrain
  surface, so the texture shears with the slope. A pattern of long horizontal streaks fans
  downward on a hill and reads as flowing hair. `ice_windswept_depth` did that **and measured as
  the cleanest tile in the project**. The statistic that catches it is **horizontal coherence
  length**; table and method in `ice_panels.md`. Do not "fix" it by mapping V to world space.

- **`--check` PASSING DOES NOT PREDICT HOW MUCH CONTRAST SURVIVES THE BUILD.** `thirteen.png`
  passed every raw metric and arrived at within-row 0.0106, half the default tile's, because
  `flatten_horizontal_banding()` divides out exactly the low-frequency content it was made of
  (banding 17.63 → 4.10). Measure the **built** tile. Third failure mode in `ice_panels.md`.

- **`COLOR` is in-out in a `canvas_item` shader.** On entry to `fragment()` it already holds
  `vertex_color * texture(TEXTURE, UV)`. Write-up in `docs/research/ice_shader_color_semantics.md`.

- **The ice tile is a MULTIPLIER and repeats every 1200 world px.** Anything with structure at
  that period becomes a permanent vertical line.

- **No two adjacent biomes may both have a sun/moon disc**, and a disc-less biome must copy its
  disc-having neighbour's `celestial_position`. Both gate-enforced, both include `first_light`.

- **The Godot editor rewrites `project.godot`** and strips pinned physics settings.
  `git diff project.godot` before every commit.

---

## How to verify — and the traps in doing so

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path . --script res://scripts/debug/biome_schedule_check.gd     # palette data
$GODOT --headless --path . --script res://scripts/debug/terrain_invariant_check.gd  # geometry
$GODOT --path . --script res://scripts/debug/sky_layer_check.gd                     # NO --headless
$GODOT --path . --script res://scripts/debug/biome_contact_sheet.gd -- --out=/tmp/b # NO --headless
$GODOT --headless --path . --script res://scripts/debug/shipping_values_check.gd -- --allow-temp
```

Rebuilding tiles — **default FIRST**, because the variants match their depth ramp against it:

```bash
python3 scripts/tools/build_ice_texture.py three.png                                        # ice_depth_gradient
python3 scripts/tools/build_ice_texture.py four.png     assets/textures/terrain/ice_faceted_depth.png
python3 scripts/tools/build_ice_texture.py five.png     assets/textures/terrain/ice_cracked_depth.png
python3 scripts/tools/build_ice_texture.py fourteen.png assets/textures/terrain/ice_crazed_depth.png
python3 scripts/tools/build_ice_texture.py fifteen.png  assets/textures/terrain/ice_veined_depth.png
```

**Grep whole logs for `SCRIPT ERROR|Parse Error|Failed to load`. Never `tail` them.** A parse
error in a palette consumer does *not* fail these probes.

### Measurement traps — every one produced a confidently wrong answer here

1. **The windowed probes read all-zero if the display is asleep or occluded.** `sky_layer_check`
   diffs rendered frames, so it reports every layer at 0/255 and fails 45 assertions with no
   error line. **Confirm by stashing and running on clean `HEAD`** before believing a regression;
   that is how this was identified in a few minutes rather than an hour.
2. **`mauve_haze`'s IceHue sits EXACTLY on the 24/255 floor** and the probe does not pin a
   terrain seed, so it reads 23 and fails intermittently. Observed once, then 24 on three
   consecutive re-runs. The fix if someone wants one is raising its `ice_hue_variance`.
3. **Never compare pixel numbers across two RUNS.** The terrain seed is per-session and the
   player is moving. A/B **inside one frozen frame** (`ice_seam_probe.gd`).
4. **`Engine.time_scale = 0` is not a safe freeze.** Use `SceneTree.paused`.
5. **Apply, wait a frame, *then* capture.** `root.get_texture()` returns the frame already rendered.
6. **A strided sampler misses small features**, and so does a smoothing filter.
7. **Hide the sprites before measuring.** Trees, the player and coins produced four false positives.
8. **Use the SIGNED column step, not `abs`.** A crack is a ridge and cancels; a seam is a step.
9. **Sample at constant DEPTH BELOW THE SURFACE, not constant y.** The tile's V axis is depth.
10. **Judge an edge by coherence, not amplitude.** Ratio-to-median is the useful statistic.
11. **When testing a repeating grid, test the PHASE, not just the period** (the seam sits at
    `world_x ≡ 599 (mod 1200)`).
12. **A one-pixel step is broadband.** Fix a step in the gradient domain.

---

## Next up

> **RESUME HERE (2026-08-13, end of session).** A full audit ran this session; the plan is
> `/Users/kjh/.claude/plans/look-thorugh-my-files-wobbly-church.md`. Step 0 (shield desync) is
> **done and committed**. The agreed order from here is:
>
> | Step | What | Decided |
> |---|---|---|
> | 1 | Pin the base viewport: `window/size/viewport_width=1152` / `_height=648` in `project.godot`, `aspect` stays `"expand"`, `Camera2D.zoom` stays `0.8333` | Option A, user-chosen — **DONE, `ec1ef8b`** |
> | 2 | Gameplay-object coherence — wire `coin_color`/`obstacle_color` | **DONE 2026-08-13.** All nine palettes author both; `push_palette()` feeds `CoinSpawner`/`GlideCoinSpawner`/`ObstacleSpawner`; `check_gameplay_contrast()` added to the biome gate. Not yet played — see biomes.md, "Gameplay contrast" |
> | **3. NEXT** | Glide vertical drift on the parallax layers (user-requested) | design settled, see plan |
> | 4 | Art / sprites | gated on step 1 |
>
> **Step 1 is two lines and changes nothing observable.** Visible world = base ÷ zoom =
> 1382×778 world px, which is exactly what the engine's undeclared 1152×648 default already
> produces. No world constant moves, no gate needs re-running. Its whole point is unlocking the
> sprite rule: **author source art at ≈2× its intended world size** (1 world px = 1.39 device px
> on a 1080p phone, 1.85 on 1440p). The existing player sprite already matches — 150×180 source
> for a 51×61 world footprint. Full numbers, the `expand` semantics, and the rejected options are
> in the plan file. `git diff project.godot` after, as always.
>
> **The sprite advice from the other session was half right.** Adding sprites later is *not*
> hard — the player sprite proved that on 08-11. The one genuinely order-dependent thing was the
> viewport, which step 1 closes. Four couplings will make an art swap silently *wrong* rather
> than hard, and are listed in the plan: `OBSTACLE_HALF_HEIGHT` duplicating `obstacle.tscn`'s
> shape, `glide_coin_spawner.gd:198`'s `get_node_or_null("ColorRect")`, `AIR_COIN_SCALE` scaling
> the collision shape with the visual, and the hand-derived surface clearances.
>
> **Also found, not scheduled** (details + line numbers in the plan): `SfxPlayer` has no
> `process_mode` so death/menu SFX play into an already-paused tree; `save_store.gd` writes
> non-atomically and a kill mid-write silently wipes the wallet; `ensure_segment_cache_for_world_x`
> loops forever on ±INF; six silent `push_error(); return` paths in `GameManager._ready()` can
> leave a live game under an undismissable `StartScreen`.

**0. Two coin sprites are pending a transparent re-export.** `Coin.png` and
`Rare coin:diamond.png` sit untracked in the repo root and are **fully opaque** — product shots
with baked backgrounds (the coin's is a tinted blue field that no saturation key can remove;
72% of the image survives the matte). The designs are good and the coin is the stronger of the
two; the diamond is pale blue-white and is the one to watch for washing out against bright ice.
When transparent versions land at `assets/sprites/coin.png` / `rare_coin.png`, the swap is
`ColorRect` → `Sprite2D` inside `coin.tscn` / `rare_coin.tscn` plus the one line in
`Coin.set_visual_color()` — **and per-biome colour becomes a `modulate` tint over the sprite's
own gold rather than the absolute colour the palettes now author**, which the nine values in
`resources/biomes/*.tres` would need re-judging against. Leave the collision radius at 10:
`check_rare_coin_height()` fails the build if the pickup grows.

**1. Playtest the three new rare variants.** The only thing in the tree shipped without a play
confirmation. Two of the three are colour judgments nobody but the project owner can make: is the
paler `glacier_teal` still recognisably green, and is the paler `violet_dusk` still purple rather
than blue-grey? The rare (20%) side of each is the previously-shipped colour, so it needs no
review. `sunset_rose`'s 50/50 is a tile roll, not a colour.

> `first_light`'s colours were confirmed fine on 2026-08-13 — that item is closed.

**2. Fold the coherence check into `build_ice_texture.py --check`.** ~15 lines of numpy, written
out in `ice_panels.md`. Closes the hole that let the pulled tile through. **Also fold in the
built-tile within-row contrast check** — the third failure mode has no automation either.

**3. Phase 4 — the rare flat "glass lake" biome.** Design only. The coupling is clean: the biome
schedule and the terrain are both pure in `world_x`, so they can agree on a lake window with no
messaging. Risks: must not overlap a chasm window, and it runs the full physics gate set.
`six.png` is kept in the repo root, unbuilt, reserved for it — long streaks cannot shear on flat
ice. `ice.gdshader`'s `gloss_strength` is parked at 0 for the same biome.

**4. Rarity — `glacier_teal` only.** The user wants the green biome rarer AND `four.png`'s tile
rarer. **These are the same request**: `glacier_teal` is both. Two options costed in the plan
file — a per-biome distance share (cleanest, but rewrites the schedule's core arithmetic) or a
longer `BIOME_CYCLE` with duplicates (nearly free). **Decide only after playing chained sessions**,
since persistence may have already fixed the over-stay.

> **Half of this may already be solved.** `9bfffc3` made the deep saturated green a 20% variant,
> so the colour the request was actually about is now four times rarer without touching the
> schedule. What is left is whether the *biome* still comes round too often — which is the part
> that needs chained sessions to judge. Re-read the request before building the expensive option.

### Smaller, genuinely optional

- **`CLAUDE.md` still says all on-screen art is placeholder `ColorRect`/`Polygon2D`.** A real
  character sprite has been in the game since 2026-08-11. Ask before editing — the character may
  still be in flux.
- **Spawn embedding, cosmetic.** `FREEZE_REPRO` at frame 1 on a seed whose first segment is a hill
  is **not a freeze** and is deliberately not logged in `freeze_bug.md`. The player spawns at a
  hardcoded `(64,136)` assuming flat ground, frame 2 depenetrates, recovered by frame 3. Fixing it
  means seeding spawn y from `get_terrain_height`, which runs the physics gates. Do not re-derive.

### Known and deliberately left

- **`ice_cracked_depth` has a soft facet boundary at tile x=782**, genuine content from `five.png`,
  affects only `mauve_haze`. If it reads as a line, regenerate the panel.
- **`glacier_teal` has the least hue-drift headroom of the nine.** Its `ice_surface` is only 0.88
  blue. It sits at `ice_hue_variance` 0.13, the first value clearing the 24/255 floor. If it still
  reads green, the lever is its `ice_surface` green (0.93), **not** variance.

---

## Working agreement

**One numbered sub-step at a time. Commit it alone. Then stop and wait for an explicit "go".**
The user play-tests between every step; silence is not consent. Do not batch.

**Verify with rendered frames and pixel measurements, not reasoning.** Many changes in this pass
looked correct and were invisible or wrong underneath.

**When a measurement contradicts the user's eyes, the measurement is the suspect** — but also
check you are measuring the right *quantity*. The grey-ice detour was three correct brightness
measurements answering a question that was actually about saturation.

**If the user flags something you already reported on, re-derive it rather than defending the
earlier answer.** Say plainly what was wrong with the old method.

**Flag the expensive option before building it.** The user's standing instruction: if something
has a lot of potential to cause bugs or is excessively hard when another option exists, say so
and let them choose.
