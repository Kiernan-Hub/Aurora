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

Four exist (smooth `ice_depth_gradient`, `ice_faceted_depth`, `ice_cracked_depth`,
`ice_windswept_depth`) against eight biomes -- so wind-scoured streaks is struck from the list
below. Prompts below; all of them should end with:

> Greyscale only. Top of the image is bright packed snow, growing gradually darker toward the
> bottom. Detail is horizontal — features spread left-to-right across the image, not top-to-
> bottom. No text, no border, no vignette, no colour. Seamless tiling not required. 1024×1024.

1. **Air bubbles / frozen froth** — "Clusters of small pale circular bubbles suspended at
   varying depths in clear ice, denser and smaller near the top, sparser and larger lower
   down."
2. **Wind-scoured streaks** — "Long shallow horizontal wind-carved grooves in packed snow and
   ice, like sastrugi, strongest in the upper third and fading with depth."
3. **Slush / granular** — "Coarse granular refrozen slush, a fine irregular pebbled texture
   near the surface softening into smoother ice below."
4. **Shatter / impact web** — "A radiating web of fine fracture lines spreading outward from
   two or three points, hairline-thin, over otherwise clear deep ice."
5. **Near-mirror gloss** — "Almost featureless polished black ice with a few very faint long
   horizontal reflection streaks near the surface." *(This is the one the flat-lake biome in
   Phase 4 will want.)*

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
