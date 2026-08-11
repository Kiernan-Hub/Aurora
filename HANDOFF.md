# Handoff — terrain & sky visual pass

Updated 2026-08-11. Delete this file once Phase 2c/4 are done and it has stopped being true.

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

`HEAD` is `163a05f`. **Everything from the shader work and the seam/colour work is
committed.** Only two things are dirty, and neither is a loose end in the code:

```
 M scripts/systems/biome_director.gd        <-- TEMP KNOB, DO NOT COMMIT
 M scripts/systems/obstacle_spawner.gd      <-- TEMP KNOB, DO NOT COMMIT
?? scripts/debug/ice_seam_probe.gd (+ .uid) <-- undecided, see "Next up"
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

**All gates pass**, run with the knobs stashed — so `shipping_values_check` passed *without*
`--allow-temp`, which is the only way to prove no knob rode along into a commit.

---

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

**`8672b0e`, `a01f798` — the ice reading green.** The drift's warm half removed *only* blue,
and subtracting blue from pale blue ice lands on yellow-green, not amber. `WARM_GREEN_FALLOFF
= 0.5` in `terrain_generator.gd` now takes a little green with it. Peak green excess on the
four affected palettes went +14 → +1.7..+2.8/255. Confirmed good by playtest.

---

## Next up

**1. Wire the shader's `contrast` to a palette field — the immediate next step.**
`biome_palette.gd` is still untouched, so `contrast`/`gloss_strength` sit at identity defaults
and no biome uses them. Contrast is the whole reason the shader exists — the one thing vertex
colours cannot do. Add `ice_contrast` to `BiomePalette`, blend it on `CHANNEL_ICE`, push it in
`apply_ice_palette`, author per biome, measure.

> Do this **after** the tile fixes, which is now the case. `contrast` pushes the tile's own
> light/dark structure away from a 0.62 pivot, so it multiplies any residual banding directly.
> Turning it on before the tiles were flattened would have made the line worse.

**2. Decide what happens to `scripts/debug/ice_seam_probe.gd`** (254 lines, untracked). It
earned its keep — it A/Bs tile bytes inside one frozen frame, hides sprites, and can scroll the
world to tell content from rendering artifacts. Options: keep as a maintained probe (then it
belongs in `CLAUDE.md`'s list and the count goes 10 → 11), fold the useful parts into
`--check`, or delete. **Not a gate** — it prints, it does not fail.

**3. Phase 2c — more ice tile families. Blocked on art only.**
`build_ice_texture.py --check panel.png` validates a source panel; `ice_panels.md` has the
requirements plus five ready-to-paste prompts. The user generates panels; you build and gate.

**4. Phase 4 — the rare flat "glass lake" biome.** Design only; see the plan file. The
coupling is clean: the biome schedule and the terrain are both pure functions of `world_x`, so
they can agree on a lake window with no messaging. Risks: must not overlap a chasm window, and
it runs the full physics gate set.

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
