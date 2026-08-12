# Handoff — terrain & sky visual pass

Updated 2026-08-12. Delete this file once Phase 4 is done and it has stopped being true.

Plan file: `/Users/kjh/.claude/plans/this-is-how-i-peppy-lark.md` (has the full context,
the approved scope, and the working agreement).

---

## Read these first

| File | Why |
|---|---|
| `CLAUDE.md` | The map. Traps that cost real time. |
| `docs/development/biomes.md` | Everything that changes colour over a run. Longest and most important. |
| `docs/development/visuals.md` | Layer stack, overdraw budget, the sky composition constraint |
| `docs/development/ice_panels.md` | Making a new ice tile (this is Phase 2c's spec) |
| `scripts/tools/build_ice_texture.py` | Its docstring is the tile pipeline's reasoning, including two fixes that looked right and were not |
| `docs/research/ice_shader_color_semantics.md` | Why the shader "darkened" the ice — closed |

---

## State

`HEAD` is `60fd381`, **pushed** to `origin/terrain/disable-mega-drop-camera-shake`. Everything
described below is committed. Only the two TEMP-knob files are dirty, and neither is a loose
end in the code:

```
 M scripts/systems/biome_director.gd        <-- TEMP KNOB, DO NOT COMMIT
 M scripts/systems/obstacle_spawner.gd      <-- TEMP KNOB, DO NOT COMMIT
```

**The three TEMP knobs** are live so the cycle can be eyeballed quickly. `BIOME_DISTANCE`
7500 (real 75000), `TRANSITION_DISTANCE` 2000 (real 12000), obstacles disabled.
`shipping_values_check.gd --allow-temp` lists them. **Revert before shipping; never commit.**

> **The knobs are why the biome cycle "changes length" between playtests.** With them the
> full eight-biome cycle is **1.73 min**; with the real values it is **13.74 min**. Verifying a
> commit means stashing them, so *anything launched during a gate run gets 13.7 min*. This was
> raised as a bug on 2026-08-11 and is not one. The user was offered 9000 (a clean 2.0 min) as
> a shipped value and **chose to leave it at 75000** — so if it comes up again, it is a
> decision, not a regression. Warn before stashing if they are mid-playtest.

**Gates run against this state:** `biome_schedule_check` PASS (`ice_variants=6`),
`sky_layer_check` PASS (42 layers, all 8 biomes), `terrain_invariant_check` PASS on 8 seeds,
`shipping_values_check --allow-temp` WARN on exactly the three knobs above and nothing else.
The physics gates were not re-run and did not need to be — no commit in this pass touches
geometry, collision or the velocity model.

## What has shipped

**`2ca5938`..`358a0b6` — Phase 1 (sky) and Phase 2a/2b (ice).** A directional glow, a
sun/moon disc, a starfield, a five-stop gradient with a horizontal wash; then a warm/cool hue
drift pure in `world_x` and a snow cap whose depth varies with `world_x`.

> **The parallax layers had to be lowered before any of the sky was visible.** `FarPeaks`
> peaked *above* the top of the screen, so the sky was **2.4% of the frame** and both the glow
> and the disc were rendering perfectly behind opaque mountains. If you change ridge geometry,
> re-measure the sky. This is in `visuals.md`.

**`0e9ee5e`, `586c5a4` — Phase 3, the one approved shader** (`shaders/ice.gdshader`). A
noise-mask dissolve between two tiles, which deleted one `Polygon2D` per ground run; `contrast`
independent of hue; a `gloss` uniform parked at 0 for the lake biome. Every uniform's default
is an exact identity, so headless frames are unchanged.

**`375ccb8`, `163a05f` — the vertical line in the ice, found and fixed.** Reported as
long-standing, and it was: it predates both the shader and the hue drift. Two distinct causes,
both in the tile pipeline, both now fixed in `build_ice_texture.py`:

1. **Broad horizontal banding inside each tile**, repeating every 1200 world px.
   `flatten_horizontal_banding()` divides out a 2D low-frequency field. Worst tile 33.3 →
   7.6/255.
2. **The seam the roll leaves at the tile centre.** The feather never hid it — +4.14/255 at
   11.5x the median column, at tile x=511, **in all three tiles independently**, which is what
   identified it. `remove_seam_gradient()` zeroes the one bad column gradient and adds a linear
   ramp back so the tile still wraps. Residual now ±0.018/255.

**`bb0aed6`..`60fd381` — the shader's `contrast` wired up, and Phase 2c's tiles (2026-08-11).**
`BiomePalette.ice_contrast` blends on `CHANNEL_ICE` and drives the shader uniform that had been
sitting at its identity since Phase 3 — contrast is the whole reason the shader exists. Peak
contribution is ≈ `78 × |1 − contrast|`, so `sky_layer_check`'s `IceContrast` floor (10/255, its
own — the sky overlays' 24 is unreachable here) is really a floor on the authoring; it caught
two biomes at 5 and 9/255 on the first pass. Then four new tile families from user-generated
panels: `rime` (`arctic_dawn`), `shattered` (`violet_dusk`), `granular` (`twilight_blue`),
`sastrugi` (`sunset_rose`). `ice_seam_probe.gd` was kept and documented as a maintained
diagnostic — **`CLAUDE.md` now says eleven maintained files, not ten**.

> **One tile was shipped and pulled the same day** — see the shear finding under "Things that
> will bite you". That is the single most important thing to read before touching a tile.

**`8672b0e`, `a01f798` — the ice reading green.** The drift's warm half removed *only* blue,
and subtracting blue from pale blue ice lands on yellow-green, not amber. `WARM_GREEN_FALLOFF
= 0.5` in `terrain_generator.gd` now takes a little green with it. Peak green excess on the
four affected palettes went +14 → +1.7..+2.8/255. Confirmed good by playtest.

---

## Next up

**1. Playtest `sunset_rose`, and pull `ice_sastrugi_depth` if it reads as flow lines.** This is
the only thing in the tree shipped deliberately unresolved. See "the shear finding" below: its
horizontal coherence is 18px, against 35px for a tile that was reported and pulled and 3–5px
for the six that are fine. It went in to bound where "visible" starts. Either outcome is
useful — if it looks wrong, pull it the same way and the threshold is between 5 and 18px.

**2. Fold the coherence check into `build_ice_texture.py --check`.** ~15 lines, and it closes
the hole that let the pulled tile through: `--check` and every tile metric measure TILING
artifacts and are blind to direction. Recommended but not started. The measurement is written
out in `ice_panels.md` and is a dozen lines of numpy.

**3. Phase 2c is essentially done — seven families, target was ~6.** Only `pale_morning` and
`starlit_night` still use the default tile, and no two adjacent biomes share it. The one family
still missing is the **near-mirror gloss**, and the user has said that is **its own large
phase**, not a panel drop — do not fold it into 2c. `six.png` is kept in the repo root, unbuilt,
reserved for the flat lake where its long streaks cannot shear.

**4. Phase 4 — the rare flat "glass lake" biome.** Design only; see the plan file. The
coupling is clean: the biome schedule and the terrain are both pure functions of `world_x`, so
they can agree on a lake window with no messaging. Risks: must not overlap a chasm window, and
it runs the full physics gate set.

**5. Random biome order — designed, approved in principle, not built.** The user wants: always
open on a bland bright starter biome, then a *random* order after it, re-rolled every run, with
green/faceted biomes weighted down. Keep it a pure function of `(session_seed, index)`, the way
`get_terrain_height` is pure — no state, no messaging, and Phase 4's lake still works. **The two
real complications are both in the sun/moon**, because ordering stops being authored: the
`celestial_is_moon` snap needs the picker to reject two disc biomes landing adjacent, and the
"disc-less biome copies its neighbour's `celestial_position`" rule has to be replaced by holding
the disc-having end's position in `blend_into()`. `biome_schedule_check` would then have to
validate the generator across many seeds instead of one fixed array. **Verify first whether
restart re-seeds** — if it reuses the session seed, the order repeats until relaunch.

### Smaller, genuinely optional

- **`CLAUDE.md` still says all on-screen art is placeholder `ColorRect`/`Polygon2D`.** A real
  character sprite is in the game as of 2026-08-11 (seen in a playtest screenshot). The user was
  asked whether to update that line and did not answer — ask before editing, the character may
  still be in flux.
- **Spawn embedding, cosmetic.** `FREEZE_REPRO` on seed 1277895522 at frame 1 is **not a
  freeze** and is not logged in `freeze_bug.md` on purpose. The player spawns at the hardcoded
  `(64,136)`, which assumes flat ground; on a seed whose first segment is a hill the capsule
  starts ~17px inside the terrain, frame 2 depenetrates it, and that one frame's horizontal
  motion is eaten (`dx=0.0027` vs `1.67`). Recovers completely by frame 3. Fixing it means
  seeding spawn y from `get_terrain_height`, which touches player spawn and runs the physics
  gates. Traced in full; do not re-derive.

### Known and deliberately left

- **`ice_cracked_depth` has a soft facet boundary at tile x=782** — about −6/255 over ~8px,
  8.7x that tile's median column. It is genuine content from `five.png`, not a pipeline defect,
  and it only affects `mauve_haze`. If it reads as a line in play, the fix is regenerating the
  panel, not more pipeline work.
- **`glacier_teal` has the least hue-drift headroom of the eight.** Its `ice_surface` is only
  0.88 blue, so the warm half has little to remove; `sky_layer_check` failed it at
  `ice_hue_variance` 0.08 (16/255) and 0.12 (23/255). It sits at **0.13**, the first value
  clearing the 24 floor. If it still reads too green, the lever is its `ice_surface` green
  (0.93, a +0.215 base excess), **not** variance.

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
python3 scripts/tools/build_ice_texture.py three.png                                       # ice_depth_gradient
python3 scripts/tools/build_ice_texture.py four.png assets/textures/terrain/ice_faceted_depth.png
python3 scripts/tools/build_ice_texture.py five.png assets/textures/terrain/ice_cracked_depth.png
```

The pipeline reproduces: the variants come back bit-identical, the default within 2/255 (a
Pillow resize difference). If a rebuild moves more than that, something else changed.

**Grep whole logs for `SCRIPT ERROR|Parse Error|Failed to load`. Never `tail` them.** A parse
error in a palette consumer does *not* fail these probes — the scene instantiates with the
script unattached and the probe prints a normal-looking result. This shipped a broken commit
once.

**`sky_layer_check.gd` measures whether each optional layer actually puts pixels on screen**,
per biome, against a floor of 24/255. It exists because `biome_schedule_check` proved the glow
data was well-formed while the glow was contributing 11/255 — i.e. invisible. *Numbers being
valid and pixels being different are two separate claims.* It is also the gate that caught an
`ice_hue_variance` cut going invisible, so run it after any palette edit.

### Measurement traps — every one of these produced a confidently wrong answer here

1. **`Engine.time_scale = 0` is not a safe freeze.** It zeroes the physics delta, trips the
   stall watchdog, fires a world rebase, and leaves the world off screen. Use `SceneTree.paused`.
2. **Never compare pixel numbers across two RUNS.** The terrain seed is per-session and the
   player is moving — measured camera drift ~25 world px by the first capture, so two runs are
   two different landscapes. A/B **inside one frozen frame** (`ice_seam_probe.gd` swaps tile
   bytes while paused). An earlier "the fix worked, 2.61 → 0.89" was entirely this error.
3. **Apply, wait a frame, *then* capture.** `root.get_texture()` returns the frame already
   rendered.
4. **A strided sampler misses small features**, and so does a smoothing filter. A 7–9px median
   to "suppress the tile's cracks" erases a 1px line completely — which is how the line was
   declared absent on the first pass.
5. **Hide the sprites before measuring.** Trees, the player and coins produced *four* false
   positives — a 28/255 "step" that was a trunk crossing the sample row, a 7.4/255 "line at
   9.9x median" that was the same trunk's edge, and the sky/ice surface boundary twice. A
   vertical sprite edge is exactly what a vertical-seam detector is built to find.
6. **Use the SIGNED column step, not `abs`.** A crack is a ridge and cancels; a seam is a step
   and survives. With `abs` the two are indistinguishable.
7. **Sample at constant DEPTH BELOW THE SURFACE, not constant y.** The tile's V axis is depth,
   so a fixed row compares different depths and swamps the thing you are looking for.
8. **Judge an edge by coherence, not amplitude.** ~2/255 running straight down 250 rows is
   plainly visible; 5/255 scattered is not. Ratio-to-median is the useful statistic.
9. **When testing a repeating grid, test the PHASE, not just the period.** The seam repeats
   every 1200 world px but sits at **world_x ≡ 599 (mod 1200)** — tile x 511 of 1024. Three
   separate grid tests looked at ≡ 0 and found nothing.
10. **A one-pixel step is broadband.** Removing its low-frequency part leaves the sharp edge
    untouched — measured, that *worsened* the seam 4.14 → 7.06/255. Fix a step in the gradient
    domain.

**Phase 2/4 touch terrain and run the physics gates.** `floor_flicker_probe` is slow (20 000
frames × several seeds) — it is the one gate not run against 2a/2b. Geometry is provably
untouched (`terrain_invariant_check` passes on 8 seeds) but that check is outstanding.

---

## Things that will bite you

- **`COLOR` is in-out in a `canvas_item` shader.** On entry to `fragment()` it already holds
  `vertex_color * texture(TEXTURE, UV)`. `COLOR = texture(TEXTURE, UV) * COLOR;` — the
  3D/`ALBEDO` convention — squares the texture. Write-up in
  `docs/research/ice_shader_color_semantics.md`.
- **The ice tile is a MULTIPLIER, and it repeats every 1200 world px.** Anything with
  structure at that period becomes a straight vertical line on screen, forever. Both fixed
  causes were this. Check `h banding` and the seam residual after any tile rebuild.
- **THE SHEAR FINDING (2026-08-11), and the most expensive lesson of this pass.**
  `build_ice_band()` pins the tile's `V=0` row to the terrain surface, so the texture shears to
  follow the slope. A pattern with no dominant direction shears invisibly; one made of long
  horizontal streaks fans downward on a hill and reads as flowing hair. `ice_windswept_depth`
  did exactly that — **and it measured as the CLEANEST tile in the project** (vertical edge
  2.17/255 at 1.88x the median column) while being wrong. Every tile metric measures TILING
  artifacts and says nothing about direction. The statistic that separates them is **horizontal
  coherence length** — how far a feature stays correlated (>0.5) along each axis with the depth
  ramp removed. Pulled tile: 35px x vs 6px y. Everything that looks right: 3–5px. Table and
  method in `ice_panels.md`. **Do not "fix" this by mapping V to world space** — it would
  detach the snow band from the ride line, break the band-to-fill seam, and demand a vertically
  tileable tile, which a depth RAMP cannot be.
- **The prompt boilerplate used to cause this.** Detail must VARY along x (`match_depth_ramp()`
  normalises away anything constant across a row) but must not RUN along x. Those sound
  identical and are opposites; the old wording asked for detail that "spreads left-to-right".
- **The hue drift only ever darkens**, never brightens — the renderer is LDR and several
  palettes sit at 1.0 on a channel. That is load-bearing; do not "fix" it by scaling up.
- **No two adjacent biomes may both have a sun/moon disc.** `celestial_is_moon` is a bool, so
  it snaps mid-transition. Gate-enforced. This is why `arctic_dawn` has no sun.
- **A disc-less biome must copy its disc-having neighbour's `celestial_position`**, or the
  disc slides across the sky while fading. Gate-enforced.
- **Put an evening glow ON the ridgeline, not in open sky.** The mountains clipping its lower
  half is what reads as light from behind them.
- **The snow cap and the hue drift compete for the same pixels.** Retune one, re-measure the
  other.
- **The Godot editor rewrites `project.godot`** and strips pinned physics settings.
  `git diff project.godot` before every commit.

---

## Working agreement

**One numbered sub-step at a time. Commit it alone. Then stop and wait for an explicit "go".**
The user play-tests between every step; silence is not consent. Do not batch.

**Verify with rendered frames and pixel measurements, not reasoning.** Five separate changes in
this pass looked correct and were invisible or wrong underneath — the glow at 11/255, the disc
hidden behind mountains, the shader squaring its texture, a seam "fix" that doubled the seam,
and a whole first pass that concluded there was no line at all.

**When a measurement contradicts the user's eyes, the measurement is the suspect.** Every
"I cannot reproduce it" in this pass was a detector flaw, not a false report. The user was
right about the green, right about the line, and right that the line predated the shader.

**If the user flags something you already reported on, re-derive it rather than defending the
earlier answer.** Say plainly what was wrong with the old method — the corrections here were
methodological (smoothing away the signal, `abs` vs signed, cross-run comparison), and naming
that is what stopped the same mistake recurring.
