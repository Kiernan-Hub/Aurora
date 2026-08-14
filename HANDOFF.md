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

The last code change is **"Make air lines 3x rarer and hang them lower"** on
`terrain/disable-mega-drop-camera-shake` (the tip may carry docs-only fixups above it), and the
working tree is **clean**. No temp knobs are set, so a playtest right now shows shipping timings (a biome lasts
~2.3 min through the early ramp).

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

> ## ▶ RESUME HERE — the next step is **MORE UPGRADE TRACKS** (step 3 below).
>
> ### Coin combo — SHIPPED, unplayed
>
> `architecture.md` → "The coin combo" is the writeup. **+0.5× per 25 consecutive coins,
> capping at 3× on the 100th**, stepped rather than continuous. Broken **only** by a missed
> ground coin (`CoinSpawner.coin_missed`, once per coin at 72px behind the player) — not by the
> rare coin, not by a glide coin, not by an obstacle hit.
>
> **It multiplies the coin, so it inflates the wallet**, which the project owner chose knowing
> the air-line step had just held density at 0.40 for `JUMP_UPGRADE_COSTS`. A flawless two-minute
> run pays roughly **2.3×** its raw coins; measured, a **no-input** run over 100s collects 46
> and misses 20, peaking at streak 17 — so the ramp costs real play, which was the ask.
>
> A coin **above the player's current grab ceiling never breaks the streak** — without that the
> line would make the combo unplayable early, since a starting player passes unreachable coins
> constantly. The ceiling comes off the durable upgrade multiplier, not the jump powerup.
>
> **Open, for play to judge:** a mandatory chasm jump flies over any ground coins near the near
> lip, and those break the streak. Suppressing coin slots near a lip is possible and was NOT
> built — the player picks when to take off, so it may not read as unfair at all.
>
> **Also fixed here:** the startup fill was hanging coins in the `chunk_count_behind` chunks
> *behind* the player (measured x=-981 to -42 against a camera that sees back to -626) —
> visible over the shoulder, uncollectable, and reported as misses on frame one.
> `CoinSpawner.run_start_world_x` now suppresses them.
>
> **2026-08-13, end of the coin session.** Branch `terrain/disable-mega-drop-camera-shake`,
> Last code change: **"Pay a combo multiplier for coins collected without missing one"**; working
> tree **clean**. Nothing is half-finished: every item below is either done-and-committed or not
> started. **Nothing from the last three sessions has been seen
> in play** and no gate can judge most of it — the biome coin/obstacle colours, the rare coin, the
> coin sprites, the spin, the collect pop and now the air lines are all unplayed.
>
> ### Coin air lines — SHIPPED, unplayed
>
> Full derivation in `physics.md` → "Coin air lines". An included slot rolls `COIN_LINE_CHANCE`
> **0.1** into a three-coin **near-flat line** in the air instead of one 34px ground coin:
> middle **132px**, ends **10px lower**, plus 0–8px of deterministic downward-only jitter.
>
> **132 sits away from every jump level's grab ceiling on purpose.** The ask was "about 20%
> lower" than the original 174, which is 139.2 — and that lands **0.7px** under level 2's
> 139.9px ceiling, a coin that level can take only on a perfect frame. The gate now fails if the
> clearance comes within 6px of ANY level's ceiling.
>
> **Coin density fell 0.40 → ~0.34 per slot and that is intended** — the owner asked for coins
> to be less frequent. `JUMP_UPGRADE_COSTS` is still costed against 0.40, so upgrades take ~16%
> longer in raw coins; the combo (up to ×3) more than covers that on a clean run. If upgrades
> feel slow in play, the lever is the costs, not the density.
>
> **The 10px droop is not decoration.** A jump apexing on the middle coin has already fallen
> 5.1px by 60px away at 750 px/s and **11.5px at 500**, so a ruler-flat line at that height
> drops its end coins outside the 10px pickup radius at the slow end of the ramp. The jitter is
> downward-only and smaller than the droop for the same reason — an end coin hung above the
> middle sits above the curve a jump traces and can never be caught (gate-asserted).
>
> **The arc shape was built and CUT** (`a9fe841`, reverted here): ends 44px below the middle,
> matching the full capsule sweep. The user did not like how arc-y it read. Do not restore it
> without asking — the near-flat line is a deliberate look, not an approximation of the arc.
>
> Two things came out different from the spec above, both deliberate:
>
> - A line measures each coin against the ground under *that* coin, so it tilts with the slope.
>   Over `COIN_LINE_MAX_GROUND_DROP` (24px across the 120px span) the slot **falls back to a
>   single coin** rather than hanging a coin out of reach.
> - That fires on ~40% of line rolls, so `0.25 × 1.6 = 0.40` is *not* true on real terrain.
>   `COIN_SLOT_INCLUDE_CHANCE` went to **0.30**, and the gate **measures** density per seed
>   (0.3708–0.4220 over the 8-seed sweep, mean 0.400) instead of asserting a closed form.
>
> `terrain_invariant_check` PASS 8/8 with `TERRAIN_INVARIANT_COIN_LINE` and a per-seed
> `TERRAIN_INVARIANT_COIN_DENSITY` line; `shipping_values_check` PASS; `freeze_replay_runner`
> 6000 frames clean, which is only there to prove the live spawner throws no error — coins are
> Area2D layer 2 and never touch terrain collision, so no physics gate is actually involved.
>
> ### Grab ceilings — measured, use these, do not re-derive
>
> | State | Clearance a coin must be at or under |
> |---|---|
> | **Standing, no jump** | **58px** ← why every coin was free before arcs |
> | Jump level 0 (×0.60) | 104px |
> | Level 1 (×0.70) | 121px |
> | Level 2 (×0.80) | 140px |
> | Level 3 (×0.90) | 162px |
> | Level 4 (×1.00) | 186px |
>
> ### Then, in this order
>
> | Step | What | State |
> |---|---|---|
> | 1 | Coin air lines (above) | **done, unplayed** |
> | 2 | In-run coin combo (above) | **done, unplayed** |
> | **3. NEXT** | More upgrade tracks (magnet radius, powerup duration, coin value) | not started, **free on the save side** |
> | 4 | Diamonds as a second currency | **deliberately held** — see below |
> | 5 | Glide vertical drift on the parallax layers | not started, design in `look-thorugh-my-files-wobbly-church.md` |
>
> **Why the currency is worth fixing at all.** Measured payouts: **~31 coins for a 30s run, ~72
> at 60s, ~168 at 120s** (+25 per diamond), against a total upgrade curve of **1130**. So the
> entire meta-progression empties in **8–15 runs**, after which every coin on screen is worth
> nothing forever. More sinks (step 3) is the cheap fix and needs **no save migration**:
> `save_store.gd` keys `upgrade_levels` as an open dictionary precisely so "adding an upgrade
> TYPE needs no version bump."
>
> **Why step 4 is held.** A second currency IS a new top-level concept, so it needs SaveStore
> **v3** — the migration that was built and reverted once already (`5f1900e` / `6c757c2`). The
> real blocker is that **there are no cosmetics or biome unlocks to sell yet**, so it would ship
> a currency nobody can spend, which is the same dead-end being fixed. Revive is the one item
> that could ship alone. The user has approved the *direction* (coins → upgrades, diamonds →
> cosmetics / biome unlocks / revive); they have not approved building it now.
>
> **Settled, do not reopen: coins stay GOLD.** Every thematic alternative (crystals, shards,
> aurora motes, ice runes) is blue, and blue-on-ice is exactly the legibility failure that
> `check_gameplay_contrast()`'s RGB-distance floor exists to prevent. The coin is the only warm
> thing on a cold screen and that is load-bearing, not decorative. If it needs to feel less
> generic, **change the silhouette, never the hue**.
>
> **Settled, do not reopen: do not zoom the camera out.** Raised as a way to buy reaction time
> for the diamond. `zoom` 0.8333 in an 1152×648 base is 0.833 **screen px per world px** — zoom
> to 0.70 and you buy **+0.18s** for a **16% shrink of everything on screen**, undoing the sprite
> legibility work. Spawn lookahead is already 800px against a 691px half-view, so the diamond is
> visible for its whole on-screen life; 0.92s is simply what 750 px/s buys. If it proves too
> tight the fix is a **telegraph** (a ground marker at the coin's x), which costs no field of
> view. The user has said they will judge the 0.92s in play.
>
> **What step 2 actually shipped** (`biomes.md` → "Gameplay contrast" is the full writeup): all
> nine palettes now author `coin_color`/`obstacle_color`; `BiomeDirector.push_palette()` pushes
> them to `CoinSpawner`, `GlideCoinSpawner` and `ObstacleSpawner`, which stamp on spawn and
> repaint live children. **Absolute colours, never a `modulate` tint** — a multiply can only
> darken and the dark biomes need the coin brighter, and these are the two objects a player must
> *read* at 750 px/s. `check_gameplay_contrast()` in `biome_schedule_check.gd` holds an RGB
> distance floor of 0.5 against `ice_surface`/`ice_depth`/`sky_horizon` (**not** a luminance
> floor — the shipped gold is luma 0.79 against `pale_morning` ice at 0.85, so luminance fails a
> colour that has always been readable).
>
> **What the rare coin shipped** (`physics.md` → "Jump reach, and the rare coin"): a new
> `RareCoinSpawner` under `TerrainGenerator`, one 25-value pickup every 50–70s (first at ~45–65s)
> hung at **174px**, inside the 24px gap between jump level 3's grab ceiling (161.7) and level
> 4's (186.0). Only over ≤6° ground with ground across the full ±700px jump arc; a rejected slot
> retries in 3s. Not magnet-pulled, deliberately. `terrain_invariant_check.check_rare_coin_
> height()` asserts the whole derivation and reads the collision radius out of `rare_coin.tscn`.
>
> **Two open questions the user has not answered**, both raised at the end of the session:
>
> 1. **`check_upgrade_curve()` and `check_obstacle_clearance()` do not exist.** `CLAUDE.md` and
>    `upgrade_store.gd:57` both name them as gates that fail the build if `JUMP_MULTIPLIERS`
>    exceeds ×1.0224 or drops below 0.60. Neither function is anywhere in `scripts/debug/`. The
>    real check, `CHASM_LEAD_IN_TOO_SHORT` (`terrain_invariant_check.gd:292`), passes the
>    *powerup* multiplier (√2) with the upgrade multiplier left implicitly at 1.0 — so raising
>    the curve today fails nothing. **Offered fix, awaiting a go:** fold
>    `UpgradeStore.get_max_jump_multiplier()` into that one call. One line, zero effect at
>    today's values, makes the documented claim true. Do NOT quietly widen the scope past that.
> 2. Whether to do anything about the diamond's contrast (item 0).
>
> **Do not re-derive these — they are settled:** the viewport is base-size × zoom as ONE
> decision (only the ratio is field of view); art is authored at **≈2× world size**; adding
> sprites late is not hard, only the viewport was order-dependent. Four couplings make an art
> swap silently *wrong*: `OBSTACLE_HALF_HEIGHT` duplicating `obstacle.tscn`'s shape,
> `AIR_COIN_SCALE` scaling the collision shape with the visual, the hand-derived surface
> clearances, and the `get_node_or_null("ColorRect")` name lookup — **that last one is now fixed**,
> it lives in `Coin.set_visual_color()` / `Obstacle.set_visual_color()` and no spawner reaches
> for the rect by name any more.
>
> **Also found this session, not scheduled** (line numbers in the plan file): `SfxPlayer` has no
> `process_mode`, so death/menu SFX play into an already-paused tree; `save_store.gd` writes
> non-atomically and a kill mid-write silently wipes the wallet; `ensure_segment_cache_for_world_x`
> loops forever on ±INF; six silent `push_error(); return` paths in `GameManager._ready()` can
> leave a live game under an undismissable `StartScreen`.
>
> **Gate state at that commit** — all green: `terrain_invariant_check` 8/8 seeds (rare-coin
> clearance 174.0), `shipping_values_check` 13 knobs clean, `biome_schedule_check`,
> `floor_flicker` 6 seeds / 120 000 frames with worst uphill flip rate 0.0000, 0 recoveries,
> 0 stuck, worst forced snap **1.8633px** (baseline at `eca9711` was 1.76px — same ballpark, and
> coins never touch terrain collision so there is no mechanism for a sprite to move it).
> `project.godot` clean.
>
> **`floor_flicker_probe` takes ~10 minutes when the Godot editor is open**, because the editor
> and any running game instance compete for CPU with the headless run. It also prints one
> `FLICKER_RESULT` per seed *before* the `FLICKER_SUMMARY` — wait on `FLICKER_SUMMARY`, not on
> the first `RESULT`, or you will read a one-seed run as a finished one.
>
> **One process note.** Adding `class_name RareCoinSpawner` required
> `Godot --headless --editor --quit --path .` before any gate would compile — and that stripped
> 40 lines from `project.godot`, exactly as `CLAUDE.md` warns. It was restored with
> `git checkout project.godot` and re-verified. **Any new `class_name` needs this dance;
> `git diff project.godot` afterwards is not optional.**

**0. Coin sprites — DONE 2026-08-13, awaiting a play confirmation.** The user re-exported both
with transparency (~79% fully clear, soft antialiased edges, no matte left). Sources are now
`coin_source.png` / `rare_coin_source.png` in the repo root, alongside the ice panels; the
colon in the old `Rare coin:diamond.png` filename was dropped because it is not portable.

Built into `assets/sprites/coin.png` (40×40) and `rare_coin.png` (45×62) by trimming to the
opaque bbox and Lanczos-downscaling **in premultiplied alpha** — do it any other way and
transparent black bleeds into the edge as a dark fringe. Both scenes carry a `Sprite2D` named
`Visual` at `scale 0.5`, so world size is **20×20** and **22.5×31**. Collision radius left at 10.

**The first build of both was near-invisible in play, and brightness was not the problem.**
The coin art is a hairline ring around an empty field: 30px of ring in a 629px source is
**1.5 texels**, under one device pixel at world size, and the star in the middle was only 29%
of the frame — total ink coverage **29%**, most of it at low alpha. The rebuild (script kept in
the commit message for `<coin-shine>`) splits ring from star **on radius, never on colour** —
they share one gold, but sit at disjoint radii — then grows the star ×1.60, dilates the ring by
21 source px, fills the disc with a translucent gold body so the middle stops reading as
background, and lays a soft outer halo for the shine. Coverage **29% → 79%**. The diamond got
the same halo plus a ×1.45 saturation lift; per `biomes.md`'s standing rule that was chosen
**over** a brightness lift, because it hangs over pale ice that is already bright.

`COIN_SURFACE_CLEARANCE` (34) is centre-to-surface, so the coin's larger visual half-height
(8 → 10) leaves 24px of air under it instead of 26. Nothing else reads the visual size.

`Coin.set_visual_color()` now writes `modulate`, so **per-biome colour is a MULTIPLY over the
sprite's own gold, not the absolute fill the rect took**. That is safe as authored — all nine
`coin_color`s are warm gold at or below the sprite's own brightness, so the multiply only
deepens — but it can never *brighten*, so a future dark biome cannot lift the coin the way the
rect allowed. The palettes remain the source of truth for `check_gameplay_contrast()`.

**The rare coin is not tinted at all**: `RareCoinSpawner` never calls `set_visual_color`, so the
diamond stays at `modulate` WHITE. If it washes out against bright ice (`pale_morning`,
`first_light`), the lever is the sprite, not a palette field.

Open, minor: the sprite is authored at 2× for a **ground** coin. `GlideCoinSpawner` scales air
coins by `AIR_COIN_SCALE` 1.9, which lands them at ~1.05× authored — under-sampled on a high-DPI
screen. A 64px source would fix air coins and alias the far commoner ground coin (no mipmaps),
so it was left alone deliberately.

**Spin and collect pop shipped with them.** Both are exported on `Coin` so the two scenes differ
sharply on purpose: the ordinary coin is calm (`spin_speed` **3.575** rad/s, `spin_min_scale`
**0.55**) because ~168 cross the screen in a two-minute run and a fast one strobes the ground;
the diamond runs **8.9375 / 0.22** because it is rare and has under a second on screen to be
noticed. Both were tuned up from the first values (2.2 / 5.5) on the user's ear, ×1.25 and then
×1.3 again — the ratio between the two scenes has been held at 2.5× throughout.

Three things there are deliberate and will look like bugs if "fixed":

- **Neither flips through zero width** the way a Mario coin does. That costs a frame of total
  invisibility, which is the exact opposite of what the sprite rebuild was for.
- **Spin phase is seeded from `position`**, not `randf()`. Without it a row of coins squashes in
  lockstep and reads as one pulsing object rather than several spinning ones.
- **`set_visual_color()` refuses to paint a collected coin.** `apply_biome_color()` runs on every
  frame of a crossfade and would otherwise reset `modulate.a` to 1 partway through the collect
  fade and undo it — visible only *during a biome transition*, so it would have read as an
  intermittent glitch.

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
