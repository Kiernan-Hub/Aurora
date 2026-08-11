# Why a ShaderMaterial "darkened" the ice, and what the ice shader ended up being

Closed 2026-08-10. Conclusion lives in `docs/development/biomes.md` ("The ice shader") and
`docs/development/visuals.md`; this is the log.

## The report

Attaching a `ShaderMaterial` to the ice band's `Polygon2D` made the ice render noticeably
darker than with no material, even though the fragment body was what looked like the exact
default operation:

```glsl
shader_type canvas_item;
void fragment() { COLOR = texture(TEXTURE, UV) * COLOR; }
```

Near the ride line the colour was about right; the error grew with depth. Suspicion fell on
vertex-colour interpolation, a `render_mode` that `Polygon2D` uses when unshaded, or a
linear-vs-gamma difference between the built-in and custom-shader paths.

## The cause: `COLOR` is in-out, and the texture is already in it

None of those. In a Godot `canvas_item` shader `COLOR` is **in-out**, and on entry to
`fragment()` it already holds `vertex_color * texture(TEXTURE, UV)` — the built-in code
samples the node's texture *before* the user's `fragment()` runs. So the identity body is

```glsl
void fragment() { COLOR = COLOR; }     // or an empty fragment(), or no fragment() at all
```

and `COLOR = texture(TEXTURE, UV) * COLOR;` — the 3D/`ALBEDO` convention, which is what makes
it look like a no-op — multiplies the tile in a **second** time. It squares the texture.

Squaring is a no-op at 1.0 and worst at the dark end. This tile's V axis is *depth below the
ride surface* with a 1.0 → ~0.38 ramp down it (`ICE_TILE_DEPTH_FLOOR`), so squaring it is
almost invisible at the surface and progressively wrong with depth — exactly the reported
symptom, and exactly the symptom that makes a colour-space bug look plausible.

## How it was pinned down

The original measurements could not settle it, for a reason worth keeping: the contact-sheet
tool does not pin the terrain seed, so the "no material" and "with material" captures were of
different terrain with different amounts of ice in frame. The one self-consistent number in
the report — shader receives `(0.208, 0.443, 0.404)` where the vertex colours interpolate to
`(0.344, 0.824, 0.769)` — was itself the clue: **G = 0.443 is below `ice_depth.g` = 0.74**, so
no interpolation of `ice_surface`→`ice_depth`, in any colour space, can produce it. The
"vertex colour" being read was already multiplied by the tile. The three channel ratios
(0.605 / 0.538 / 0.525) are just the tile's own greyscale value at that depth.

It was then settled in a controlled scene (five identical quad-strip bands drawn side by side
in one frame, so no cross-run variance at all):

| Fragment body | vs no material |
|---|---|
| *(empty)* `void fragment() { }` | **max delta 0/255 — identical** |
| `COLOR = COLOR;` | **max delta 0/255 — identical** |
| `COLOR = vec4(COLOR.rgb, 1.0);` | **max delta 0/255 — identical** ← proves the texture is already in `COLOR` |
| `COLOR = texture(TEXTURE, UV) * COLOR;` | max delta **55/255**, darker |

and confirmed arithmetically: recovering the tile value as `entry_COLOR / vertex_colour` and
predicting `tile * no_material` matched the buggy render to within 1/255 at every depth.

With a **white** texture the buggy body and the built-in path are identical, which is the
cleanest single demonstration — the divergence needs a texture that is not 1.0 to exist at all.

## Ruled out, by measurement, not by argument

- Vertex-colour interpolation. Identical with a white texture; identical for all three correct
  bodies with the real tile.
- A missing `render_mode`. `blend_mix` is already the default and there are no 2D lights in
  this project; **no `render_mode` line is needed on the ice shader**, and adding one fixes
  nothing because nothing is broken.
- Colour space. Mipmaps disabled, no sRGB import flag, no `hdr_2d`; and a gamma conversion
  cannot produce the measured numbers (checked — `srgb_to_linear(0.344) ≈ 0.098`, not 0.208).
- `Polygon2D.polygons` / the indexed-quad path. Same geometry either way.

## What shipped

`shaders/ice.gdshader`, the project's only shader, on the ice band only. Three jobs, each with
an exact-identity default:

- **(a)** cross-dissolve two ice tiles on a noise mask, replacing the second alpha-faded
  `IceOverlay` `Polygon2D` per ground run — one node fewer, and a patchy dissolve rather than a
  uniform fade
- **(b)** `contrast` against the tile, independent of hue
- **(c)** `gloss_strength`, parameterised and left at 0 for a later flat-lake biome

### Tuning the dissolve, and two rejected attempts

Both were measured and both were worse than leaving the mask alone.

The mask's first cut (`MASK_SCALE = (3.0, 1.6)`) put only ~3 noise cells across the viewport,
so the "dissolve" was one screen-sized soft wipe: 74% of pixels sat mid-blend at weight 0.5,
barely distinguishable from the uniform fade it replaced. At `(6.0, 2.2)` — roughly 200×155
world px per cell, ~6 patches across — it goes properly bimodal (7% mid-blend, per-pixel blend
std 0.41).

Two octaves of interpolated value noise are bell-shaped, not uniform, so a linearly swept
threshold dissolves 1/9/34/64/85/96% of the screen at weights 0.2…0.8 — an S rather than a
straight line. Attempts to flatten it:

| Attempt | Result |
|---|---|
| Widen the distribution about its median, clamped | Linearised the numbers, but the clamp gives every pixel in the flattened tails the **same** mask value, so ~20% of the screen moved in lockstep at the end of the window — a localised copy of the uniform fade being removed |
| Ease the threshold sweep instead (monotone, unclamped, so no lockstep) | Cut mean deviation from linear only 0.137 → 0.092, and bought it with a plateau across the middle third where the dissolve visibly stalls (0.59 → 0.64 → 0.69 over weights 0.4…0.6) |

Neither shipped. The S is also simply correct: it eases the pattern change in and out, the same
reason every channel in `biome_director.gd` is a `smoothstep` rather than a linear ramp.

## Verification, and a harness trap worth keeping

**Two separate runs cannot be diffed, even with the seed and the physics tick both pinned.**
Building the identity proof took three attempts:

1. Counting **render frames** does not pin how far the world has advanced — physics is a fixed
   60 Hz clock running independently of render speed, so the same render frame lands on a
   different physics tick run to run (measured: `player_x` 359.6 vs 365.8 at frame 120).
   Fixed by freezing the tree from `_physics_process` on an exact tick.
2. Even tick-pinned, the residual diff was **coins, obstacles and the player sprite** — all
   animate on the *render* clock. Hiding them cleared it.
3. Even with all of that, two runs of *different builds* still drift sub-pixel (`player_x`
   344.4749 vs 344.4455), and the diff fills with thin tree/surface-line edges that have
   nothing to do with shading. Something in the physics path is coupled to render-frame count.
   **Not chased** — it is a harness problem, not a game one, and the fix removes the need.

The sound test swaps the material **in place, inside one frozen frame of one run**: geometry,
camera, terrain and lighting are then identical by construction and the material is the only
variable. Result, over 9 ice bands at each of three positions:

```
tick 240: no-material vs ice.gdshader(defaults)  max=0  PIXEL-IDENTICAL
tick 620: no-material vs ice.gdshader(defaults)  max=0  PIXEL-IDENTICAL
tick 900: no-material vs ice.gdshader(defaults)  max=0  PIXEL-IDENTICAL
```

No material at all is precisely what the old build rendered at weight 0, because its second
band was hidden there — so this is a like-for-like comparison against the shipped look.

The dissolve itself was checked by driving `apply_ice_palette()` by hand across the weight with
two genuinely different tiles: weight 0 renders exactly the base tile alone and weight 1 exactly
the overlay tile alone (max delta 0 against dedicated reference frames — the pop-free handoff at
both ends of the window), with a monotone, strongly bimodal progression between them.

`contrast` and `gloss_strength` were checked in the isolated rig, where UV.y is known exactly:
each visibly changes the band (34 and 45/255) while leaving the bottom 4% **pixel-identical**,
which is what keeps the band's bottom row equal to `get_deep_fill_color()` and stops a seam
opening across the whole world at `ICE_BAND_DEPTH`.

None of the probes were kept — they would join the archived one-offs `CLAUDE.md` warns about.
Rebuild them if the band construction changes again.
