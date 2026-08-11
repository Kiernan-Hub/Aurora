# Ice panels — how to make a new ice tile

Open this when you want a new ice *look* for a biome. You generate a greyscale panel, the
builder turns it into a tile, and two checks say whether it worked.

```
python3 scripts/tools/build_ice_texture.py --check mypanel.png          # will this work?
python3 scripts/tools/build_ice_texture.py mypanel.png assets/textures/terrain/ice_NAME_depth.png
godot --headless --path . --script res://scripts/debug/biome_schedule_check.gd
```

Then point one palette at it: `ice_texture = ExtResource(...)` in `resources/biomes/NAME.tres`.

---

## The one idea that makes all of this make sense

**The vertical axis of the panel is DEPTH BELOW THE ICE SURFACE THE PLAYER RIDES ON.**

It is not a picture of ice. It is not a side view. Row 0 is the ride line itself; the bottom
row is ~340px underneath it. That is why one image can carry gloss, cracks, snow and the whole
light-to-dark falloff at once and still land correctly on every hill, with no shader and no
per-slope maths.

Get this backwards and everything still *builds* — you just get ice that looks lit from below.
`--check` rejects it for you.

## Hard requirements

| Requirement | Why |
|---|---|
| **Greyscale** | The tile is a *multiplier* under `ice_surface`/`ice_depth`. Colour in the panel fights the biome's colour. |
| **Bright at the top, darker at the bottom** | That is the depth ramp. `--check` needs top−bottom ≥ 0.12. |
| **Contrast must live ACROSS a row** | `match_depth_ramp()` rescales every row onto the default tile's brightness, so *between-row* contrast is normalised away by design. Facets and cracks survive; a smooth vertical wash does not. |
| **≥ 1024×1024** | Anything smaller is upscaled and soft. A warning, not a rejection. |
| **No horizontal tiling needed** | The builder rolls by half-width and feathers the one remaining seam. |
| **Never mirror it** | Mirroring guarantees a seamless join but stamps in a symmetry axis, and long diagonal cracks become a chevron every repeat. |

## What the builder does to it, so you can stop worrying about these

Lifts the darks onto `[0.38, 1.0]` (a raw panel bottoms out near 0.09, and since the tile
multiplies, unlifted darks take every biome tint to black) · applies a 1.4 midtone gamma ·
rescales each row onto the default tile's depth ramp so all tiles agree about brightness ·
makes the horizontal wrap seamless.

That last one matters more than it sounds: during a biome change **two tiles are on screen at
once**, cross-dissolving. If they disagree about how bright ice is at a given depth, the whole
view wobbles. `biome_schedule_check.gd` gates it at `MAX_ICE_RAMP_DEVIATION = 0.02`; matched
variants measure 0.002–0.004.

## Families worth having

Six exist as of 2026-08-11 (smooth `ice_depth_gradient`, `ice_faceted_depth`,
`ice_cracked_depth`, `ice_granular_depth`, `ice_rime_depth`, `ice_shattered_depth`) against
eight biomes, which meets the plan's target -- so frozen froth, the crack web and
slushy/granular are struck from the list below. What is still missing is the **near-mirror
gloss** the Phase 4 lake would want.

**Wind-scoured streaks is struck for a different reason: it was built, shipped and pulled.**
`six.png` is still in the repo root and still builds, but the tile is not in
`assets/textures/terrain/` because a long-streak pattern is the one thing that cannot ride a
sloped band -- see below. **It is reserved for the Phase 4 flat lake**, where there is no slope
to shear it and long horizontal streaks are exactly what the reference wants. Rebuild it with
`build_ice_texture.py six.png <output>` when that biome exists.

**The failure mode to watch for when generating.** Four of the seven panels generated for this
pass were rejected by `--check` for the same reason: no vertical light-to-dark ramp (top-bottom
range 0.028-0.085, against ~0.25 for a good one). The tile's V axis IS depth below the ride
surface, so a uniformly-lit panel has nothing for V to mean. Generate at 1024x1024 or larger --
undersized panels are upscaled and come out soft.

### Detail must VARY along x, but must not RUN along x (2026-08-11)

These sound like the same instruction and are opposites, and getting them confused shipped a
tile that had to be regenerated.

**Vary along x — required.** `match_depth_ramp()` rescales each row's brightness onto the
reference ramp, so anything constant across a row is normalised away completely. Only
within-row contrast survives, which is the number `--check` prints.

**Run along x — avoid.** `build_ice_band()` pins the tile's `V=0` row to the terrain surface
(`terrain_generator.gd:726`), so the texture shears to follow the slope. A pattern with no
dominant direction — facets, crack webs, crinkle, plates — shears invisibly. A pattern made of
**long continuous lines spanning the panel** does not: on a downhill the lines fan downward and
read as flowing hair or water rather than ice. That is what `ice_windswept_depth` did, and no
tile metric caught it, because the vertical-edge and banding checks measure TILING artifacts and
are blind to how directional a pattern reads on a slope.

**The statistic that does catch it is horizontal coherence LENGTH** -- how far a feature stays
correlated (>0.5) along each axis, with the depth ramp removed first. Measured across all seven
tiles built for this pass:

| Tile | x-coherence | y-coherence | ratio |
|---|---|---|---|
| `ice_windswept_depth` (pulled) | **35px** | 6px | **5.83x** |
| `ice_depth_gradient` | 10px | 4px | 2.50x |
| `ice_faceted_depth` | 8px | 4px | 2.00x |
| `ice_shattered_depth` | 7px | 5px | 1.40x |
| `ice_cracked_depth` | 5px | 4px | 1.25x |
| `ice_rime_depth` | 4px | 3px | 1.33x |
| `ice_granular_depth` | 3px | 2px | 1.50x |

The pulled tile is an outlier on ABSOLUTE x-coherence -- 35px against 3-10px for everything
else -- not merely on the ratio. Note the ratio alone is not sufficient: the default smooth tile
sits at 2.50x and has never looked wrong, because it has almost no contrast to draw a line
with. Judge a candidate on both, or just check that nothing stays coherent for tens of pixels
along x.

So: **short, broken, irregular features that differ from their neighbours along x** — not
continuous strata. Judge a candidate panel by squinting at it rotated 20°; if it suddenly looks
like flow lines, it will do that on every hill in the game.

Prompts below; all of them should end with:

> Greyscale only. Top of the image is bright packed snow, growing gradually darker toward the
> bottom. Detail is broken up and irregular, varying left-to-right, with no single feature
> running unbroken across the width of the image. No text, no border, no vignette, no colour.
> Seamless tiling not required. 1024×1024.

1. **Air bubbles / frozen froth** — "Clusters of small pale circular bubbles suspended at
   varying depths in clear ice, denser and smaller near the top, sparser and larger lower
   down."
2. **Wind-scoured streaks** — "Short, broken, overlapping wind-carved scours in packed snow
   and ice, like sastrugi ridges seen from above — each one only a fraction of the image wide,
   at staggered offsets and slightly different angles, never forming a continuous line across
   the picture. Strongest in the upper third, fading with depth." *(Rewritten 2026-08-11: the
   original asked for "long horizontal grooves" and produced exactly the flow-line failure
   above.)*
3. **Slush / granular** — "Coarse granular refrozen slush, a fine irregular pebbled texture
   near the surface softening into smoother ice below."
4. **Shatter / impact web** — "A radiating web of fine fracture lines spreading outward from
   two or three points, hairline-thin, over otherwise clear deep ice."
5. **Near-mirror gloss** — "Almost featureless polished black ice with a few very faint,
   short, broken reflection glints near the surface." *(This is the one the flat-lake biome in
   Phase 4 will want. Kept short/broken for the same reason as 2 — though a flat lake is the
   one place a long streak would be safe, since there is no slope to shear it.)*

## Where the files go

- **Source panels** → `art_source/` (carries a `.gdignore`, so Godot never imports them).
  The old `one.png`…`five.png` are still at the repo root for historical reasons.
- **Built tiles** → `assets/textures/terrain/ice_NAME_depth.png`.

## Two ways this goes wrong quietly

- **A panel that builds but is upside down** renders as ice lit from below. Use `--check`.
- **A `.tres` whose `ExtResource` path went stale** resolves `ice_texture` to `null`, which is
  a *legal* value meaning "use the default smooth tile" — so the biome silently loses its
  pattern and nothing errors. `biome_schedule_check` prints `ice_variants=N` in its PASS line;
  watch that number go up when you add one.
