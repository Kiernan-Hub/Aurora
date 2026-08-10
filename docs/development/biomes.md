# Biomes — the scenery cycle

Open this when touching anything that changes colour over the course of a run: the palette
resources, `biome_director.gd`, or any of the `apply_palette()` methods it calls.

Landed 2026-08-08 (Phase 1). Reference art: `one.png` (the target look) and `two.png` (the
eight moods) in the project root.

---

## What it is

The scenery cycles through eight `BiomePalette` resources as the run goes on, crossfading
between them. Before this, every colour in the game was a `const` in one of ~13 files and
nothing changed for the whole run.

**It is scenery only.** Nothing in this system touches collision, terrain geometry, the
velocity model, or any game state. `get_terrain_height` is untouched. If a physics gate
result ever moves because of a change in here, something is wrong that no amount of colour
tuning will fix.

## The three moving parts

| Thing | File | Role |
|---|---|---|
| `BiomePalette` | `scripts/systems/biome_palette.gd` | Pure data + one pure blend function. No scene tree, no state. |
| The eight palettes | `resources/biomes/*.tres` | One per mood. Adding a ninth is a new `.tres` plus one line in `BIOME_CYCLE`. |
| `BiomeDirector` | `scripts/systems/biome_director.gd` | The only live node, and the only thing that reads a palette. |

Consumers expose `apply_palette()` and never look anything up themselves: `sky_backdrop.gd`,
`background_generator.gd` (×4), `snow_drift.gd`, and `terrain_generator.apply_ice_palette()`.
Trees and birds need no code at all — the director writes their `modulate` directly, because
a biome's effect on a foreground object genuinely *is* a multiplicative tint.

## Why there is no shader

There was going to be one. There doesn't need to be.

`Polygon2D` renders `texture_sample × vertex_color`, and ignores `.color` outright once
`vertex_colors` is populated (this is `visuals.md` trap 9, and the reason the old
`LIGHT_CHUNK_COLOR`/`DARK_CHUNK_COLOR` did nothing for a week). That multiply is exactly the
operation an ice-tinting shader would perform. So the ice tint rides `vertex_colors`:
`ice_surface` on every surface vertex, `ice_depth` on the four that `close_fill_run()`
appends, and the per-pixel gradient between them falls out of Godot's interpolation for free.

Consequence: **this project still has zero shaders**, and the whole biome pass introduced no
new rendering technology. Do not add one here without a reason vertex colours cannot cover.
The one thing they cannot do is vary *contrast* against the texture independently of hue
(a `crack_strength` uniform); if that is ever wanted, it is an isolated addition.

## The base ice tile, and why V is depth (2026-08-08)

`assets/textures/terrain/ice_depth_gradient.png` is **not a picture of ice**. Its vertical
axis is *distance below the surface the player rides on*: snow band at the top, glossy pale
sheen under it, deepening body, cracks at plausible depths. `apply_fill_texture()` maps V to
exactly that — 0 at every surface vertex, maximal at the gradient-stop corners.

This is the single highest-leverage thing in the visual pass, because it collapses four
separate features into one image. Gloss, crack lines, snow clumps and the fill's whole
vertical colour structure are all *painted in*, and they land correctly on every hill, in
every biome, with no shader and no per-slope maths.

Two consequences worth holding onto:

- **`ice_surface`/`ice_depth` now carry hue, not brightness.** The tile owns the light-to-dark
  ramp (1.0 → ~0.52). If the palette darkens with depth too, the two ramps multiply and deep
  ice goes black. The gate enforces this.
- **The surface rim `Line2D`s are gone.** The tile's top rows are the snow band now, which is
  softer and physically sensible where a 5px stroke read as a drawn outline. Don't reintroduce
  a stroke — strengthen the tile's top rows instead, where it stays correct on every slope.

**Never drop a raw generated panel in here.** Run `scripts/tools/build_ice_texture.py`, which
lifts the darks (a raw panel bottoms out near 0.09, and since the tile is a *multiplier* that
takes every biome tint to black) and cross-fades the horizontal wrap. It deliberately does
**not** mirror: mirroring guarantees a seamless join but stamps in a symmetry axis, which is
the faint diamond artifact visible in the tile this replaced, and which long diagonal cracks
would turn into a chevron every repeat.

`ICE_TILE_WORLD_WIDTH` (1200) stretches the square tile sideways on purpose — it turns the
source's steep cracks into the long lazy ones the reference has, and slows the repeat to
~1.6 s at `MAX_SPEED` instead of ~0.5 s.

## How a transition works

A biome change is **five overlapping crossfades, not one**. `CHANNEL_CURVES` in
`biome_director.gd` gives each channel its own start/end within the transition window:

```
sky        0.00 ──────────────► 0.70      leads
scenery         0.08 ─────────────► 0.82
atmosphere   0.05 ──────────► 0.75        weather rolls in early
ice                   0.28 ──────────────► 1.00   trails
gameplay                0.35 ────────────► 1.00   (Phase 2, inert)
```

Sky first, air behind it, ice last — because ground colour is mostly reflected skylight.
Fading everything on one curve reads as somebody turning a dimmer; this reads as weather.
Each channel is a `smoothstep`, so it eases in *and* out: a linear ramp has a visible corner
at both ends of the window, and both corners are readable as events.

## The sky gradient: five stops, and two axes

**The sky is no longer a `GradientTexture2D`.** That class is a 1-D gradient projected across
an image and cannot express two independent axes, so the sky is baked by hand into a small
`Image` instead — the vertical ramp sampled per row, times a horizontal tint lerp per column.

| Field | Meaning |
|---|---|
| `sky_top` / `sky_mid` / `sky_horizon` | the three original stops |
| `sky_upper` / `sky_lower` | two extra stops, at the **midpoint of each segment** |
| `sky_mid_offset` | where `sky_mid` sits |
| `sky_tint_left` / `sky_tint_right` | left-to-right **multipliers** over the whole ramp |

**Why five stops.** Three can only produce a ramp that is straight between them, so a sky that
holds its deep blue over most of the frame and then turns hard near the horizon is not
expressible. The two extra let it *bend*. Their **offsets are derived**, not authored — what
the stops are for is bending the ramp's colour, and letting their positions move too would be
four interacting numbers per biome for nothing the colours cannot already do. Set to the exact
midpoint of their neighbours the result is identical to the old 3-stop ramp, which is what the
four non-evening palettes do; only the evening ones bend.

**The tints are multipliers, not colours**, for the same reason the ice tints are: they can
only ever darken, so they cannot push a channel past 1.0 on an LDR renderer. White means "no
horizontal variation" and is both the default and a real authoring choice —
`pale_morning` (uniform overcast), `glacier_teal` (clear midday, sun high and central) and
`starlit_night` (only the moon's own bloom is directional) all use it, and
`sky_layer_check.gd` then reports their `SkyTint` as `--` rather than failing them.

**This is a wash, not a light source** — the bloom is `SkyGlow`'s job. Each biome's tints are
authored to agree with its glow: warm on the side the glow sits, cool on the far side.

**Cost is 8×256 baked per frame of a transition, and zero extra draw calls.** Eight columns is
not a resolution compromise: the horizontal term is a straight lerp and the canvas filter
interpolates linearly between texels, so two columns would already be exact. Getting the same
effect by stacking another full-screen alpha rect would have cost real fill rate (`visuals.md`,
"Overdraw is the sky's real budget"); baking it into a texture that was already being drawn
costs none.

## The directional glow

The sky gradient is **vertical**, so on its own every biome is lit uniformly from above and
reads flat however the stops are tuned. `SkyGlow` is a soft radial bloom placed at a point on
screen — the thing that makes the reference art's dawn and sunset frames read as *lit* rather
than as a colour ramp. Four palette fields, all on `CHANNEL_SKY`:

| Field | Meaning |
|---|---|
| `glow_color` | bloom colour; its alpha scales with `glow_strength` |
| `glow_position` | centre, in **screen fractions** — `(0,0)` top-left, `(1,1)` bottom-right |
| `glow_radius` | half-extent as a fraction of viewport width (x) and height (y) |
| `glow_strength` | `0` hides the layer outright and skips the draw |

**Placed by anchor, not by pixels.** Anchors are fractions of the parent rect, which is
exactly what these fields already are — so the layout is right on any viewport with no resize
signal, no `get_viewport_rect()` read and no `_process`. That matters more here than usual
because `project.godot` pins no viewport size (see `visuals.md`). Two axes rather than one
radius so the bloom's *shape* is authored rather than inherited from the device's aspect.

**Straight alpha, not additive.** A warm bloom over a blue sky should pull the sky toward the
warm hue, which is what alpha does; additive pushes toward white and loses the hue the biome
is named for. The Mobile renderer is LDR anyway — a bright glow comes from darkening what
surrounds it, exactly as the reference does it.

**Position and radius interpolate too**, so during a transition the light *travels* rather
than one bloom fading out while another fades in elsewhere. The eight palettes are authored
as one arc: the source rises low-left through `arctic_dawn`, tracks up and over through
midday, sets low-right at `sunset_rose` (the strongest glow, 1.0), fades through
`violet_dusk` and `twilight_blue`, and `starlit_night` is a small cool halo high-left — the
moon's, with the disc sitting inside it.

**Strengths are calibrated by measurement, not by eye** — see
`sky_layer_check.gd`, which fails the build if any biome's glow peaks under 24/255.
The first authoring pass looked reasonable as data and was invisible in game (11–52/255,
most of it under 20). Two causes, and the second is the one that is easy to miss:

- the strengths were simply too low, and
- **the glow colours were too close to the sky colours they blend over.** A near-white glow on
  a near-white sky moves nothing however high the strength goes. `glacier_teal`'s glow was
  (240,252,255) over a sky of (184,199,219): 24% of a 53-unit gap is 12 units.

A third effect showed up in the numbers: peak-per-unit-strength was **142** for
`starlit_night` (`glow_position.y` 0.24) against **61** for `sunset_rose` (0.68). Glows placed
low were spending their bright centre behind the ridges and the terrain. Every
`glow_position.y` now sits in the 0.26–0.46 band.

Current measured peaks run 40–93/255. The spread is deliberate and not a defect: the three
pale daylight biomes (`pale_morning`, `glacier_teal`, `mauve_haze`) land at 40–43 because a
bright overcast sky genuinely has less directional contrast to give, while the dawn/dusk/night
biomes reach 82–93. Diffuse light *should* read as diffuse.

## The sun / moon disc

The light *source*, where the glow is the light it casts. `celestial_color`,
`celestial_position`, `celestial_size`, `celestial_strength`, all on `CHANNEL_SKY`, authored at
the same position as the glow so the two agree about where the light comes from.

**Only three of the eight biomes have a disc, deliberately.** A disc in all eight reads as a
decal rather than as weather. The three are where you would actually see one: a risen sun
(`arctic_dawn`), a clear midday (`glacier_teal`), and the moon (`starlit_night`). The other
five have a reason not to — cloud in the two overcast/hazy biomes, and the sun already at or
below the horizon in the three evening ones. `celestial_strength = 0` skips the draw, and
`sky_layer_check.gd` reports those as `--` rather than failing them.

**`sunset_rose` has the strongest glow in the cycle and no disc at all**, which is the single
most reference-accurate frame in the game. In the source art you cannot see the sun and you
know exactly what it is doing. The three evening biomes are authored as one sequence: setting
behind the peaks (`sunset_rose`, glow 1.0), just gone (`violet_dusk`), last afterglow
(`twilight_blue`).

### Put an evening glow ON the ridgeline, not in the sky

The ridge tops sit at y 0.21–0.45, so the visual horizon is ~y 0.21–0.25. **A glow centred
there has its lower half clipped by the mountains, and that clipping is what reads as light
coming from behind them.** A glow centred high in open sky reads as midday whatever colour it
is — which is exactly what the first pass after the composition change looked like, because
everything had been pushed up to y 0.08–0.18 when the top 21% was the only sky that existed.

So the arc runs low → high → low through the cycle: `arctic_dawn` 0.21 (just risen),
`glacier_teal` 0.10 (midday), `sunset_rose` 0.24, `violet_dusk` 0.26, `twilight_blue` 0.28
(progressively lower and more clipped), and `starlit_night` 0.10 for the moon.

One thing this does **not** do: the mountains are flat palette silhouettes, so they never pick
up warm light from the glow the way the reference's do. The compensation is in the palette —
an evening biome's `scenery_far`/`scenery_near` carry the warmth themselves.

**The disc is laid out in PIXELS, unlike everything else in `sky_backdrop.gd`** — because it
has to be round. Anchors are per-axis fractions, so anchoring it the way the glow is anchored
makes the radius a fraction of width horizontally and of height vertically, squashing the sun
by 1.78:1 on a 16:9 screen. Instead all four anchors collapse to the centre point and the
offsets carry a square pixel extent out from there: the anchor keeps the centre correct on any
viewport, the offsets keep the shape circular. Radius derives from viewport **height** on both
axes, so the disc keeps a constant apparent size rather than growing on a wider phone.

That is also the one thing here that needs `size_changed` connected. Everything else is
anchored and follows the viewport for free.

**A disc must be brighter than its own glow**, and getting this backwards is the easy mistake.
The disc sits *inside* the bloom, so it is composited over an already-brightened sky. First
authoring made each disc *warmer* than its glow, which measured 28–32/255 — barely visible —
because a warm disc over a warm glow has almost no gap to cover. The sun's disc is the
brightest thing in the sky and its glow is the dimmer, more saturated spill; authored that way
the same discs measure 56–97.

## Stars

`star_density` was authored in all eight palettes when the biome pass landed and read by
nothing until 2026-08-10. It rides `CHANNEL_ATMOSPHERE`, with the snow — **stars are weather,
not light** — and drives one `SkyStars` `TextureRect`.

**Built in code, not shipped as a PNG**, the same way `snow_drift.gd` builds its flake dot.
300 dots scattered once at a fixed seed into a 1024×576 `LA8` image (white, so only luminance
and alpha are ever needed; the colour comes from `modulate`).

- **`STAR_RNG_SEED` is a constant and must never come from `session_seed`.** Background code
  may not read it at all (`visuals.md`), and a starfield that reshuffles every run is a bug,
  not variety.
- **16:9, and `STRETCH_KEEP_ASPECT_COVERED`, so stars stay round.** A square texture scaled to
  fit a 16:9 viewport squashes every dot to 0.63 of its height, and a 1px dot squashed like
  that flickers as it lands on and off the pixel grid. Covering crops instead of distorting.
- **Drawn above the gradient but below the glow**, so a dawn or dusk bloom washes stars out
  near the light rather than stars sitting on top of the sun.
- Scattered uniformly, so only the third or so that land above the ridgeline are ever seen.
  That is correct — stars do not show through mountains — and `STAR_COUNT` is chosen for what
  survives, not for what is drawn.

**Density scales alpha, and the field is baked with a wide per-star brightness spread so that
reads as *count*.** As alpha comes down the faint majority drop below perception first and
only the brightest remain. Fading a uniform field would read as "dimmer stars"; fading a
varied one reads as "fewer stars", which is what is wanted.

The schedule is physical: no stars in the three daylight biomes, **none at `sunset_rose`
either** — the sun has only just reached the horizon and that is the brightest sky in the
cycle. First stars at `violet_dusk` (0.3), more at `twilight_blue` (0.6), full field at
`starlit_night` (1.0), and a few of the brightest lingering into `arctic_dawn` (0.28).

**Starting value is `glow_strength = 0`.** All six headless gates instantiate `main.tscn` and
`BiomeDirector` never applies a palette under `--headless`, so that constant is the sky they
see: hidden, and byte-identical to the glow not existing.

### A gate trap this pass hit

`MIN_MEANINGFUL_GLOW_STRENGTH` ("nonzero but invisible") is an **authoring** rule and must
only ever run against a `.tres`, never against a blended palette — which is why
`biome_schedule_check.gd` splits `check_glow_authoring()` from `check_glow_layout()`. A
crossfade out of a `glow_strength = 0` biome legitimately passes through every tiny value on
its way up, so running the authoring check on blends fails the gate for *correct* data. It
does not fire today only because no palette currently uses 0. Found by negative-testing the
new gate, not by it passing — worth doing for any check added here.

## Why distance, not a clock

The schedule is a pure function of `player.global_position.x` — which `main.gd` never
world-rebases ("X is never world-rebased"), and which `terrain_generator.gd` already uses as
the ice texture's UV axis. So the biome at any point is deterministic and replayable, the
same contract `get_terrain_height` holds, and `biome_schedule_check.gd` can assert the entire
schedule without simulating a single frame of game.

It also means a faster player sees *more of the world*, not the same amount of it faster.

`BIOME_DISTANCE` is 75 000 px: ~100 s at `MAX_SPEED`, ~2.3 min through the early ramp.
`TRANSITION_DISTANCE` is 12 000 px (~16 s at cap) and must stay well under it or biomes never
settle.

## Repainting live chunks

New chunks read the live tints at build time, so they are born in the current biome. But a
transition is slower than a chunk's lifetime, so the chunks *already on screen* must be
repainted too — otherwise the ice visibly changes colour at every chunk boundary mid-fade.

`terrain_generator.repaint_chunk()` does that. It is the old dead `apply_chunk_color()`
traversal, repointed at the values that are actually rendered. It rewrites `vertex_colors`
without reading any geometry: the array is always one entry per surface point followed by
exactly the 4 that `close_fill_run()` appends, so the split is `size - 4` whatever shape the
run is.

Parallax layers need no walk at all — the silhouette rides `ridges_root.modulate` (which
propagates to every segment and pine under it, including ones not spawned yet), and every
haze band in a layer shares **one** `GradientTexture2D`, so recolouring that single gradient
recolours all of them.

## Per-biome ice textures (2026-08-08)

`two.png` contains **three** pattern families, not eight, so there are three tiles:

| Tile | Source panel | Used by |
|---|---|---|
| `ice_depth_gradient.png` | `three.png` | the default — six of the eight biomes |
| `ice_faceted_depth.png` | `four.png` | `glacier_teal` |
| `ice_cracked_depth.png` | `five.png` | `mauve_haze` |

A palette selects one through `BiomePalette.ice_texture`. **`null` means the default tile**,
which is why six palettes leave the field unset rather than restating it.

**Every variant must go through `build_ice_texture.py`**, which now takes an optional output
path. That script's level work is what stops a raw panel (which bottoms out near 0.09)
multiplying its biome tint to black — the tile is a multiplier, not a colour.

### A variant carries pattern, never its own brightness ramp (2026-08-09)

Passing an output path also means "this is a variant", and the script **rescales it per row
onto the default tile's light-to-dark depth ramp**. What survives is the variant's
high-frequency detail — its facets and cracks, the only reason it exists. What goes is any
disagreement about how bright ice is at a given depth.

That disagreement was the real reason the tile boundary read as a hard cutoff. The swap
happens one chunk at a time (below), so there is a live vertical seam in game with the old
tile one side and the new one the other; both are *multipliers*, so a ramp mismatch renders
there as a flat brightness step, which is far more readable than any pattern change. The
faceted tile was 0.86 at the ride line and 0.66 at half depth against the default's 0.98 and
0.49 — a ~12% step across a vertical line at eye level.

Two knobs, both in the script: `RAMP_MATCH_STRENGTH` (1.0 = full match; ease toward ~0.7 if a
full match over-flattens a tile whose source has no structure where the reference is bright)
and `RAMP_SMOOTH_SIGMA` (the correction is one scalar per row, so it is smoothed vertically
or row-to-row noise stamps in horizontal banding).

The biome gate enforces it — see `MAX_ICE_RAMP_DEVIATION`. It has to, because a tile rebuilt
by any other route looks completely correct as a resource.

### How the pattern crossfades: two stacked bands (2026-08-09)

`Polygon2D` samples exactly one texture, so two tiles cannot be mixed the way two colours can.
Three approaches were costed on 2026-08-08; **B shipped first and was replaced by A on
2026-08-09** after it was judged in game.

| | Approach | Outcome |
|---|---|---|
| **A** | **Two ice bands per run, the second's alpha driven by the ice channel** | **Current.** Exact crossfade. +1 `Polygon2D` per ground run, hidden outside a transition |
| B | New chunks build with the new tile; existing chunks keep theirs | Shipped 2026-08-08, removed 2026-08-09 — the hard vertical seam at the boundary chunk was too visible |
| C | Shader with two samplers and a mix uniform | Still rejected: it would be the project's first `.gdshader`, and A already gets the result |

**Why B failed is worth keeping**, because the diagnosis was not the obvious one. The seam had
*two* causes, and only one of them was the pattern. The larger was a brightness step — the
variants did not share the default tile's depth ramp, and the tile is a multiplier, so the
boundary was a flat ~12% jump across a vertical line. That is fixed in the tiles themselves
(above) and was worth fixing on its own: during a dissolve **both tiles are on screen at
once**, so a ramp mismatch would now read as a brightness wobble across the whole view. The
remainder — the genuine pattern discontinuity — is what A removes.

Mechanically A is three things:

1. `blend_into()` **does not carry `ice_texture` at all** (it writes `null`). A single blended
   palette structurally cannot express a crossfade between two textures — that needs both
   endpoints *and* the weight. So `BiomeDirector.push_palette()` passes the pair and the ice
   channel weight straight through to `terrain_generator.apply_ice_palette()`.
2. `build_ice_band()` builds **two** `Polygon2D`s per ground run off one set of points and
   UVs: `IceBand*` carries the outgoing tile at full opacity, and `IceOverlay*` — added second,
   so it draws on top — carries the incoming tile at `alpha = ice weight`. Identical geometry
   means the composite is exactly `tint * (tile_a*(1-w) + tile_b*w)`: a true dissolve of the
   two patterns, with the colour crossfade riding on top untouched.
3. `repaint_chunk()` writes base tile, overlay tile and alpha **unconditionally on every
   call** — including `polygon.texture`, which the B-era code was explicitly forbidden to
   touch.

**That reversal is the subtle part.** The old rule existed because there was only one texture
slot and therefore no way to be halfway between two tiles, so writing it meant popping every
on-screen chunk in a single frame. With a second band there *is* a halfway, and the safe thing
is now the opposite. Both files carry a comment saying so.

The invariant that makes it pop-free at both ends of the window: every chunk — freshly built
or repainted — derives its appearance from the same three values, so they cannot disagree; and
at weight 1 the overlay fully covers the base, which renders the same pixels as the next
frame's weight 0 with the base already swapped to that tile.

The overlay is built even when the weight is 0 (`visible = false`), so the node set is the
same in every chunk however it was born and `repaint_chunk()` never creates or frees anything
mid-transition. Under `--headless` the weight is always 0, so every gate draws exactly the
bands it always did.

## Testing

`biome_schedule_check.gd` is the gate. It is physics-free and takes about a second:

```
godot --headless --path . --script res://scripts/debug/biome_schedule_check.gd
```

**It exists because the other six gates are blind to all of this by construction.** They all
instantiate `main.tscn` under `--headless`, and `BiomeDirector` deliberately returns early
under `--headless` having applied nothing — which is what makes it impossible for this pass
to move a gate result, and equally what makes those gates unable to see any of it. Same gap
`debugging.md` records for powerups.

It checks: every palette loads and is in `[0,1]`; the rim stays bright enough to read the
ride surface in every biome; far/near scenery stay separated so the depth cue survives; the
schedule is pure in `world_x` (swept forwards *and* backwards, so hidden per-call state
shows up); channel weights are monotonic and land exactly on 0 and 1; and `blend_into` never
allocates. Verified to actually fail by darkening `starlit_night.rim_core` and flattening its
scenery separation — both were caught.

It also covers the ice textures, which nothing else can see. `ice_texture` is legally `null`,
so a `.tres` whose `ExtResource` path went stale resolves to `null` and looks **identical** to
a palette that never wanted a variant — the biome would just quietly keep the smooth tile. So
the gate counts resolved variants (reported as `ice_variants=` on the PASS line, and failing
at zero) and checks each is 1024×1024. On top of that it holds the two rules the crossfade
depends on:

- **Every variant shares the default tile's depth ramp** (`MAX_ICE_RAMP_DEVIATION`, compared
  per row against `ICE_TERRAIN_TEXTURE`). Measured: the two matched variants sit at 0.002 and
  0.004; the unmatched faceted tile that shipped on 2026-08-08 was ~0.10. Verified to fail by
  tightening the tolerance to 0.001, which flagged both palettes.
- **`blend_into` never carries `ice_texture`, at any weight** — swept across the ice channel
  rather than probed at the ends, because a reintroduced snap fires in the middle. If one came
  back, the generator's "outgoing" tile would silently be a value that had already jumped: the
  dissolve would run between a tile and itself for half the window, then between two different
  tiles for the other half, and the hard seam would return while every colour check still
  passed.

**What no gate can see is the band code itself** — `BiomeDirector` is inert under `--headless`,
so `apply_ice_palette()` and therefore `repaint_chunk()` never run in any of the seven. The
dual-band contract was verified once with a throwaway probe that built a real `Main` and drove
`apply_ice_palette()` by hand across the weight: bands built in pairs, overlay hidden at
weight 0, correct tile and alpha on each band mid-dissolve, a chunk born mid-dissolve matching
the ones already on screen, and the weight-1 → next-frame-weight-0 handoff showing the same
tile. It was checked against a deliberately broken `repaint_ice_band()` before being trusted.
Not kept: it would join the 18 archived one-offs `CLAUDE.md` warns about. Rebuild it if the
band construction changes again.

## Traps

- **A parse error in `biome_director.gd` hangs the six gates rather than failing them**
  (`visuals.md` trap 3). Run one gate as soon as the file first parses, not at the end.
- **A parse error in a *palette consumer* does the opposite, and it is worse: the gate runs
  to completion and prints a normal-looking PASS.** Measured 2026-08-10 with a broken
  `sky_backdrop.gd`: `camera_shake_probe` emitted three `SCRIPT ERROR` lines at the *top* of
  its output, then loaded `main.tscn` without that script attached, produced ordinary jerk
  numbers and printed `CAMERA_SHAKE_PROBE_END`. The scene does not fail to instantiate — it
  instantiates with a node that has no behaviour. So **`tail` on a probe's output is not
  verification.** Grep the whole log:

  ```
  godot --headless --path . --script res://scripts/debug/camera_shake_probe.gd > /tmp/g.log 2>&1
  grep -n "SCRIPT ERROR\|Parse Error\|Failed to load" /tmp/g.log || echo NONE
  ```

  Cheaper still, for a single file: `godot --headless --path . --check-only --script res://<path>`.
- **`const X: PackedFloat32Array = PackedFloat32Array([...])` is a parse error.** The explicit
  constructor is a *call*, and a call is not a constant expression. Use a bare array literal —
  `const X: PackedFloat32Array = [0.0, 1.0]` — and let the type annotation convert it. Inside a
  function body the constructor form is fine, which is why the same line reads as legal.
- **`is_headless` must come from `DisplayServer.get_name()`**, never `Services.is_headless` —
  `freeze_replay_runner.gd` builds Main inside `_init()`, before the autoload has flushed.
  `snow_drift.gd` shipped exactly this bug.
- **`set_process(false)` goes *before* the headless return**, not after.
- **The director writes only `modulate.r/g/b` on the bird flock.** `bird_flock.gd` writes
  `modulate.a` every frame for its glide fade; taking the whole Color would fight it and the
  birds would never fade out.
- **Never `@export` a live colour.** An exported value can be serialised into `main.tscn` and
  silently persist (CLAUDE.md, "Things that break silently") — for a colour that means
  shipping whatever biome happened to be on screen when the scene was last saved. The tints
  in `terrain_generator.gd` are plain vars for this reason, same as `debug_chasm_disabled`.
- **Palette colour components must stay in `[0,1]`.** The Mobile renderer is LDR, so a value
  above 1.0 is silently clamped and the palette will not look like its numbers.
- **The old "terrain must be lighter than all background layers" rule is dead.** `one.png` is
  dark saturated ice under a pale sky and that inversion is most of why it reads well. What
  replaced it is the contrast contract the gate enforces: a bright rim, and real separation
  between far and near scenery. See `visuals.md`.

## Not built yet

`mist_strength`, `reflection_strength` and `star_density` are **authored in all eight
palettes and read by nothing**. That is deliberate: the palettes are complete data from day
one, and each renderer arrives in its own phase so it can be judged and reverted alone.

- **Phase 2** — gameplay contrast. `coin_color`/`obstacle_color` exist and are unused. The
  coin and obstacle colours were tuned against a bright sky (`visuals.md`, "Why daylight"),
  so the dark biomes need their own values before they are truly shippable.
- **Phase 3** — mist/fog layer.
- **Phase 4** — reflection. The only one with real risk: it is the one layer that is not
  automatically rebase-safe, and must parent under a rebased node or use `motion_scale = 0`.
- **Phase 5** — stars, and silhouette *shape* variants.

**Hill silhouette shape cannot crossfade** and is not planned. A ridge is a single
`Polygon2D`; changing its shape means rebuilding it, which pops. Doing it properly means two
ridge sets per layer cross-dissolving — double the polygons on four parallax layers, on every
gate frame. Shape variety today comes from `rng_salt`, per layer.

**Flat-looking ice is a lighting choice, not a geometry one.** The bottom row of `two.png`
reads flat because of reflection, low surface contrast and a soft horizon — not because the
ground is level. The ice surface line in this game *is* `get_terrain_height`, so it always
curves, and faking a level plane would draw a surface the player visibly does not ride on.
Every mood in the grid composites fine over the real curve. The one cue that does not
transfer is the dead-level mirror horizon in the bottom-left panel.
