# Background differentiation — investigation log

Closed-investigation record for the background thread: what was tried, what failed, and the
constraints that were measured along the way. Moved out of `HANDOFF.md` on 2026-08-24, where
its "current status" sections had gone stale and were actively misdirecting new sessions.

**This is history, not a plan.** For where the background actually stands, read `HANDOFF.md`;
for how the shipped layers work, `docs/development/visuals.md`. Nothing below describes the
current scene: at the time this was written the four parallax layers were
`FarPeaks/FarRidge/MidRidge/PineLine` and the panorama was an unwired experiment. `PineLine`
no longer exists and the panorama shipped as `IceStrip`.

The parts worth not re-deriving are "What is worth keeping from the failure" (four measured
rendering facts) and the two blockers under "Raster art".

---

## The problem, stated correctly

The background reads too much like Alto's Adventure. **It does not look bad — it looks
good.** The owner's own words at the start of the session: *"it looks good with the layers,
and the front layer moves faster than the ones behind it, so it really does come together.
only problem is it looks too much like Alto's Adventure."*

This is a **differentiation** problem, not a quality problem. The session that just ended
lost sight of that and spent five commits making the background objectively worse. Getting
this wrong again is the main risk here.

The target look the owner keeps pointing at is `art_source/example.png` — four mockups of
*this game* with an ice-mountain/iceberg background painted in. Panels 1–4 are four
arrangements of one visual vocabulary: tabular shelves, arches, jagged spires, faceted
ranges, some with reflections.

## What was tried this session, and reverted

Five commits (`0cbebdc`, `01ed39f`, `dde27bb`, `47fdb0e`, `0c5268a`), reverted by `95d9ca4`.
They are in history; any piece is recoverable.

The idea was to replace the pine treeline on `PineLine` with procedurally generated ice —
first a shard polygon, then faceted "ice masses" with `vertex_colors`, then angular
walls/shelves at larger scale. It ended at the owner's verdict: *"it just looks like
rocks."*

**Why it failed, at the root:**

1. **It bolted scattered objects onto the ridge layers instead of changing the ridges.**
   The layering, haze, low contrast and scale of the four `ParallaxLayer`s are what carry
   this background's look. They were never touched. The owner had **already chosen option 4
   — rework `get_ridge_height()` to be jagged instead of smooth** — and scattered objects
   are nowhere on that list. That plan was never actually tried.
2. **It matched the reference's subject and missed its atmosphere.** In `example.png` the
   ice formations are *barely visible*: low contrast, heavily fogged, half dissolved into
   the sky. Every cut built here was a row of distinct high-contrast objects on a line.

## What is worth keeping from the failure

Genuinely useful, do not re-derive:

- **`Polygon2D.vertex_colors` sits UNDER `ridges_root.modulate`.** Godot renders
  `texture * vertex_color`, and `modulate` multiplies on top. So internal facet shading on
  background geometry costs **no architecture change** and does not break the
  one-property-write-per-layer biome recolour. (`visuals.md` trap 9; the terrain already
  does this in `build_fill_vertex_colors()`.) An earlier claim in-session that two-tone
  facets would need a second child root was **wrong**.
- **`vertex_colors` can only multiply DOWN from the layer's `modulate`.** No facet value can
  make a layer lighter than its palette colour. If near-layer geometry needs to be pale, the
  lever is that layer's `depth_t` in `main.tscn`, not the facet values.
- **Mound silhouettes read as rock.** Anything that tapers to zero height at both feet is a
  hill. Ice fractures along planes: vertical side walls, flat or sharply angular tops.
- **Small elements at high density read as gravel** regardless of shape. ~25 forms per
  screen at 26–58px was the worst version.
- **Sun/moon occlusion is pure alpha.** `SkyBackdrop` is `layer -200`, `ParallaxBackground`
  is `-100`; the sun hides behind the background only because those polygons are opaque.
  Any replacement must be opaque above the horizon, and must **not** bake a sky — the
  planned aurora is sky-only and needs `SkyBackdrop` free.

## Raster art: tried three times now, failed three times

Two rounds happened last session (recorded in the previous handoff), two more this session.
Every round drifted toward a **shaded 3D-render look** no matter the prompt. Measured on the
outputs: facets landing at **~5px on screen**, and **7.5% of the form below 0.45 luminance**
against a reference that bottoms out near **0.75**.

The colour spec *did* work — the last attempt came back at saturation 0.015 with luminance
p5/median/p95 of 0.55/0.80/0.98, which tints correctly under all 8 palettes. Shape and
lighting were the failures, not colour.

**Two blockers that kill the raster route as attempted, and are worth knowing before anyone
tries a fourth time:**

- **Chat prompting cannot match an edge.** Asking for "the next tile whose left edge matches
  this right edge" does not work — the model has no access to the pixels. The real tool is
  **outpainting** (Photoshop Generative Expand, or an image-edit API that conditions on
  actual pixels). If raster is ever revisited, that is the tooling, not a chat prompt.
- **Eight biome palettes cycle every 75,000 world px.** Baked art can only be
  multiply-tinted, so it must be near-greyscale to survive — at which point the painterly
  colour that makes `example.png` good is gone. Procedural gets biome colour for free.

Tile *count* is not the blocker, contrary to expectation: at `motion_scale` 0.03 and
~600 px/s, ten 1500px tiles would cover roughly 14 minutes of play before repeating.

## Where the procedural option still stands (not attempted this session)

**Option 4 from the original brainstorm has still never been tried**, and was the owner's pick
before this session's raster detour: rework `get_ridge_height()` in
`scripts/systems/background_generator.gd` to produce jagged/faceted skylines instead of smooth
sine humps. It drives all four live `ParallaxLayer`s (`FarPeaks`, `FarRidge`, `MidRidge`,
`PineLine`) and therefore all 8 biome palettes, since `BiomeDirector` only recolours this shape.
Its advantage over the raster route: it gets biome tinting for free, no multiply-tint survival
question at all.

Leave the layer/haze/scale system **completely alone** — it works — and change only the
shape language. That is the actual complaint.

Proposed, not confirmed in code:

1. **Ridged transform.** `1 - abs(sin(...))` so peaks come out as sharp Vs.
   **TRAP, verified by reading the code:** apply it to each octave individually, *not* to
   the summed wave. The file's `wave` is built to land in `[-1, 1]` so `(wave * 0.5) + 0.5`
   maps it to `[0, 1]`. Ridge each octave and every term is already `[0, 1]`, so that line
   double-compresses everything into the upper half and the skyline comes out uniformly tall
   and flat — looking like the math failed when it is only the mapping.
   `RIDGE_PEAK_SHARPNESS` (1.5) also duplicates the sharpening ridging does; expect to drop
   it toward 1.0.
2. **A 4th octave**, high frequency, low amplitude — small jagged secondary bumps.
3. **Deliberately under-sample the short octave.** Lowering `RIDGE_SAMPLE_COUNT` (64) turns
   the straight spans between sample points into visible facets, for free. Safe: the seam
   guarantee only needs samples to divide `segment_width` evenly.
4. **Re-tune each layer's `ridge_height_min/max` and `ridge_period_scale` afterward** — a
   jagged function reads taller at the same amplitude, so values tuned for round hills will
   need adjusting.

**Open question, asked but never answered:** apply to all 4 layers at once, or start with
one (`FarPeaks` suggested, least visually busy) so the math can be judged before it touches
everything?

**Also unresolved and worth raising early:** in `example.png` the near ice is *not* darker
than the far ice — distance is carried by **contrast**, not darkness. This background is
built on the opposite rule (`visuals.md`: "far = lighter, so `FarRidge` is the lightest
scenery and `PineLine` the darkest"), and `biome_schedule_check` holds a contrast floor over
it. Matching the reference on this point means inverting atmospheric perspective across all
8 palettes — a palette-data change touching every biome plus a gate, **not** a one-liner.
Flag it to the owner before attempting; it looks right in one biome and wrong in five.

**After any change to the silhouette**, re-run `biome_schedule_check.gd` (fast, headless)
and the three windowed visual gates — `sky_layer_check.gd`, `ice_look_capture.gd`,
`biome_contact_sheet.gd`. Those three **must run without `--headless`**. And re-measure the
sky: `visuals.md` "There has to BE a sky" documents the composition constraint the ridge
heights are bound by, and it is invisible from the code.

## The alternative the owner should keep in view

The **aurora borealis** — `docs/development/aurora_borealis.md`, CLAUDE.md build-order row
#12 — is fully planned, not started, and is the feature the game is named after. It is
sky-only, purely cosmetic, rides its own single blend ramp like the frozen lake, and would
differentiate the look far more than reshaping mountains will. It was deliberately sequenced
*after* the background settles the sky/silhouette composition its ribbons sit against —
but "settled" could reasonably mean "left alone."

The owner has chosen to keep working on the background for now. This is not a blocker, just
the thing worth re-raising if the background stalls again.

