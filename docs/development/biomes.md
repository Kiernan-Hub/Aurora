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

## Why colour is still not a shader's job

`Polygon2D` renders `texture_sample × vertex_color`, and ignores `.color` outright once
`vertex_colors` is populated (this is `visuals.md` trap 9, and the reason the old
`LIGHT_CHUNK_COLOR`/`DARK_CHUNK_COLOR` did nothing for a week). That multiply is exactly the
operation an ice-tinting shader would perform. So the ice tint rides `vertex_colors`:
`ice_surface` on every surface vertex, `ice_depth` on the four that `close_fill_run()`
appends, and the per-pixel gradient between them falls out of Godot's interpolation for free.

**That is still true and still what ships.** There is now exactly one shader in the project
(`shaders/ice.gdshader`, 2026-08-10, see "The ice shader" below), and it does **not** touch any
of the above — the tints, the hue drift and the depth ramp all still ride vertex colours. It
exists only for the three things vertex colours provably cannot do. Do not move colour work
into it, and do not add a second shader anywhere without the same standard of justification.

## The base ice tile, and why V is depth (2026-08-08)

`assets/textures/terrain/ice_depth_gradient.png` is **not a picture of ice**. Its vertical
axis is *distance below the surface the player rides on*: snow band at the top, glossy pale
sheen under it, deepening body, cracks at plausible depths. `build_ice_band()` maps V to
exactly that — 0 along the band's top row, `ICE_BAND_DEPTH` along its bottom one.

This is the single highest-leverage thing in the visual pass, because it collapses four
separate features into one image. Gloss, crack lines, snow clumps and the fill's whole
vertical colour structure are all *painted in*, and they land correctly on every hill, in
every biome, with no per-slope maths — and none of it moved into the shader when one arrived.

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

## Ice hue drift (Phase 2a)

`ice_surface` is written to every surface vertex identically, and the tile is greyscale, so
before this a whole screen of ice was exactly one colour — the tile supplied texture but no
colour variation at all. `ice_hue_variance` drifts the surface tint warm/cool as a
low-frequency function of **world_x**.

- **Pure in `world_x`**, exactly like `get_terrain_height` and the ridge silhouettes. A
  chunk's last surface sample and the next chunk's first are the same `world_x`, so they get
  the same shift and the drift crosses chunk boundaries seamlessly. Anything keyed on a chunk
  index or a local x would crawl.
- **`world_x` comes back out of the UVs.** `build_ice_band()` wrote `uv.x = world_x ×
  horizontal_scale`, so `paint_ice_band()` inverts that instead of storing or recomputing it.
  The drift therefore cannot fall out of step with the pattern, and repaint needs no idea
  which chunk it is looking at.
- **Surface row only.** The depth row keeps `ice_depth` untouched, so the band still meets the
  flat deep fill at exactly the colour the fill uses and no seam appears where the band ends.
  It is also the truer read — patches are a surface phenomenon.
- **The shift only ever darkens a channel** (warm removes blue, cool removes red). Same LDR
  discipline as every other tint: `sunset_rose`'s `ice_surface` is already `(1.0, 0.88, 0.88)`,
  and scaling up would silently clamp — flattening the drift to nothing on exactly the biomes
  with the most saturated ice.
- Two octaves at 2600 and 900 px, both much longer than the ~1150px viewport (so it reads as a
  wash, not stripes) and both deliberately **unrelated to `ICE_TILE_WORLD_WIDTH` (1200)**, so
  the colour drift and the texture repeat never lock into a visible beat.

Costs nothing: no new nodes, no new textures, no extra draw calls — just a different colour
per vertex in a loop that already existed. `starlit_night` opts out at 0 (clean uniform night
ice); the rest run 0.10–0.16, measured at 24–36/255 by `sky_layer_check`'s `IceHue` column.

## The snow cap (Phase 2b)

A third quad strip per ground run, sharing the ice band's top edge, with a lower edge
displaced per-vertex by `get_snow_cap_depth(world_x)` between **3 and 13px**. `snow_cap_color`
and `snow_cap_strength` on `CHANNEL_ICE`; 0 hides it.

**Keep it thin.** The first cut ran 10–44px and read as a thick rolled edge — "snowboard-y" —
and became the dominant thing on the slope, which is wrong: the ice's own cracks and facets
are supposed to carry that. This is a frost line catching the light on the lip, and its
*variation* is what makes it read, not its mass.

Worth knowing when retuning: **depth changes the area, `snow_cap_strength` changes the peak.**
`sky_layer_check` measures peak contribution, which comes from the fully-opaque top row — so
thinning the band alone would have kept exactly the same number while fixing the actual
complaint. The strengths came down ~40% alongside it.

**Why geometry and not the tile.** The tile already paints a snow band in its top rows — but
it repeats every `ICE_TILE_WORLD_WIDTH` (1200px), so the ride line has the *same profile
forever*. Uniformity was the actual complaint. Displacing real geometry by a function of
`world_x` is the only way to get a cap that thickens and thins and never repeats.

**This is not the reinstated `Line2D` stroke**, and the distinction is why it was allowed at
all. A `Line2D` is a constant-width outline faking a bloom; this is a variable-depth band. The
tombstone at the head of `terrain_generator.gd` says so explicitly — if someone ever wants a
constant-width edge back, that is still the thing not to build.

Untextured: vertex colours alone, opaque along the surface row and alpha 0 along the displaced
lower row, so it dissolves into the ice rather than ending on a line. Costs **one extra
`Polygon2D` per ground run** (terrain is ~3 per run: fill, band, cap — it was 4 until the
shader folded the overlay band away on 2026-08-10).

**It interacts with 2a, and the measurement caught it.** The cap covers the top of the ice
band, which is exactly where the hue drift is strongest — adding it knocked every `IceHue`
reading down ~4 points and pushed three biomes under the floor. Their `ice_hue_variance` was
raised to compensate. Worth remembering: these two features compete for the same pixels, so
retuning one means re-measuring the other.

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

### Two rules the gate now enforces, both learned from a playtest

The disc shipped in 1b with two bugs that only showed up in motion, and both are now asserted
by `biome_schedule_check.gd` rather than left to authoring care.

**1. A disc-less biome must copy its disc-having neighbour's `celestial_position`.**
Position interpolates on the same channel as strength, so if the neighbour disagrees the disc
*flies across the sky while fading in*. `twilight_blue` parked it at (0.82, 0.26) while the
moon lives at (0.30, 0.09), and the moon visibly travelled from the bottom-right to the
top-left as night fell. `check_disc_positions_are_stationary()`.

**2. No two adjacent biomes may both have a disc.** `celestial_is_moon` is a bool, so it
cannot be interpolated — `sky_backdrop` swaps the texture outright instead of dissolving
between two stacked nodes the way the ice pattern must. That is only invisible because
strength is 0 at one end of any transition that changes it. `check_no_adjacent_discs()`.
This is what cost `arctic_dawn` its sun: it sits next to `starlit_night` in the wrap, and a
sun→moon swap mid-fade with both visible would pop.

**Sun and moon must not look the same.** They differ only in tint otherwise, and in play both
read as "a pale dot" — which is exactly what happened. The moon is a **crescent**: the same
disc and halo with an offset circle subtracted, baked into an `Image` because subtracting one
circle from another is not something a radial `GradientTexture2D` can express. Same falloff
stops as the sun, so they still belong to the same sky; only the shape differs.

**Only two of the eight biomes have a disc, deliberately.** A disc in all eight reads as a
decal rather than as weather. Two, now: a clear midday sun (`glacier_teal`) and the
crescent moon (`starlit_night`). The other six have a reason not to — cloud in the two
overcast/hazy biomes, the sun at or below the horizon in the three evening ones, and
`arctic_dawn` giving up its risen sun to satisfy the no-adjacent-discs rule above. `celestial_strength = 0` skips the draw, and
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
`glacier_teal` 0.10 (midday), `sunset_rose` 0.24, `violet_dusk` 0.26, `twilight_blue` 0.30
(progressively lower and more clipped), and `starlit_night` 0.10 for the moon.

**The glow must not sweep across the screen between two biomes.** Position interpolates, so a
large gap between neighbours reads as the light source *flying* rather than drifting. The
cycle wraps, so at least one reset is unavoidable — the fix is to spread it. `twilight_blue`'s
afterglow was at x 0.82 against the moon's 0.30, a 0.52 sweep that was immediately obvious in
play; moving it to 0.58 and dropping its strength to 0.5 turns the night end into three small
steps (0.78 → 0.58 → 0.30 → 0.16) that read as the light quietly returning east. **Largest
single step in the cycle is now 0.28.**

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

`two.png` contained **three** pattern families, not eight; three more were added on
2026-08-11 from separately generated panels, hitting the plan's target of ~6:

| Tile | Source panel | Used by |
|---|---|---|
| `ice_depth_gradient.png` | `three.png` | the default — three of the eight biomes |
| `ice_faceted_depth.png` | `four.png` | `glacier_teal` |
| `ice_cracked_depth.png` | `five.png` | `mauve_haze` |
| `ice_granular_depth.png` | `eleven.png` | `twilight_blue` |
| `ice_sastrugi_depth.png` | `twelve.png` | `sunset_rose` |
| `ice_rime_depth.png` | `seven.png` | `arctic_dawn` |
| `ice_shattered_depth.png` | `eight.png` | `violet_dusk` |

> **`ice_windswept_depth` was built, shipped and pulled the same day.** It measured as the
> cleanest tile in the project on every metric that existed, and was still wrong: its long
> streaks stayed coherent for 35px along x, so on a slope they fanned downward and read as
> flowing hair. Reported from a playtest, not caught by a gate. `six.png` is kept for the
> Phase 4 flat lake, where nothing shears it. See `ice_panels.md`.
>
> **`ice_sastrugi_depth` (2026-08-11) is the regenerated version of that panel, and it is
> deliberately on probation.** It halves the streak length -- 18px x-coherence against the
> pulled tile's 35px -- but everything else in the cycle sits at 3-5px, so it is still ~3.6x
> more directional than anything else shipping. It went in to find out where "visible" actually
> starts, since 35px is the only calibration point that exists. If `sunset_rose` reads as flow
> lines on a slope, pull it the same way and the answer is between 5 and 18px.

**The three were placed to spread the pattern, not per-biome taste.** Before them,
`sunset_rose` through `arctic_dawn` was four consecutive biomes on the default tile, so the
ice pattern never changed across half the cycle. Now **no two adjacent biomes both use the
default**, and `cracked`/`shattered` — the two most similar families — are deliberately kept
one biome apart so the dissolve between them still reads as a change.

**Vertical edge is the number to watch on a new tile**, because the tile repeats every 1200
world px and a coherent vertical feature becomes a permanent line on screen; a horizontal
edge sits at one depth and never repeats. Localized, smoothed over 64px, worst against the
median column:

| Tile | Worst | Ratio to median |
|---|---|---|
| `ice_granular_depth` | 7.00/255 | 2.59x |
| `ice_sastrugi_depth` | 2.81/255 | 2.14x |
| `ice_rime_depth` | 4.80/255 | 1.99x — the cleanest in the project |
| `ice_depth_gradient` | 3.33/255 | 3.00x |
| `ice_faceted_depth` | 3.06/255 | 3.21x |
| `ice_shattered_depth` | 8.95/255 | 3.13x — see below |
| `ice_cracked_depth` | 9.97/255 | 3.34x — the known facet boundary at x=782 |

`ice_shattered_depth` lands in the same band as `ice_cracked_depth`'s already-shipped
artifact, and at a suspiciously similar column (789 vs 780). The other four peak at 437/561/
615/956, so there is no fixed pipeline column and this reads as content in two panels that are
both large-plate patterns. If either reads as a line in play, the fix is regenerating the
panel, not more pipeline work.

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
*used to* happen one chunk at a time, giving a live vertical seam with the old tile one side
and the new one the other; both are *multipliers*, so a ramp mismatch rendered there as a flat
brightness step, far more readable than any pattern change. Since a real dissolve
replaced the snap (2026-08-09) both tiles are on screen together for the whole transition, so
a mismatch is now a wobble across the entire view rather than a step at one seam — the same
requirement, with more at stake. The
faceted tile was 0.86 at the ride line and 0.66 at half depth against the default's 0.98 and
0.49 — a ~12% step across a vertical line at eye level.

Two knobs, both in the script: `RAMP_MATCH_STRENGTH` (1.0 = full match; ease toward ~0.7 if a
full match over-flattens a tile whose source has no structure where the reference is bright)
and `RAMP_SMOOTH_SIGMA` (the correction is one scalar per row, so it is smoothed vertically
or row-to-row noise stamps in horizontal banding).

The biome gate enforces it — see `MAX_ICE_RAMP_DEVIATION`. It has to, because a tile rebuilt
by any other route looks completely correct as a resource.

### How the pattern crossfades: one band, two samplers (2026-08-10)

`Polygon2D` samples exactly one texture, so two tiles cannot be mixed the way two colours can.
Three approaches were costed on 2026-08-08. **B shipped first, was replaced by A on 2026-08-09,
and C — rejected twice — shipped on 2026-08-10** once there was an independent reason to have a
shader at all.

| | Approach | Outcome |
|---|---|---|
| **C** | **One band; the incoming tile is a `uniform sampler2D` and the shader dissolves on a noise mask** | **Current.** One `Polygon2D` per ground run, and a patchy dissolve instead of a uniform fade |
| A | Two ice bands per run, the second's alpha driven by the ice channel | Shipped 2026-08-09, removed 2026-08-10. Correct, but a whole extra `Polygon2D` per run and only ever a uniform fade |
| B | New chunks build with the new tile; existing chunks keep theirs | Shipped 2026-08-08, removed 2026-08-09 — the hard vertical seam at the boundary chunk was too visible |

**Why B failed is worth keeping**, because the diagnosis was not the obvious one. The seam had
*two* causes, and only one of them was the pattern. The larger was a brightness step — the
variants did not share the default tile's depth ramp, and the tile is a multiplier, so the
boundary was a flat ~12% jump across a vertical line. That is fixed in the tiles themselves
(above) and was worth fixing on its own: during a dissolve **both tiles are on screen at
once**, so a ramp mismatch reads as a brightness wobble across the whole view rather than a
step at one seam. That requirement did not change when C replaced A.

**Why C was rejected twice and then taken.** The standing objection was that it would be the
project's first `.gdshader` for a result A already achieved. What changed is that the ice
needed contrast independent of hue and a gloss uniform — neither expressible in vertex
colours — so the shader was going to exist regardless. Once it does, the second band is pure
cost, and folding the mix into the shader is strictly better than A: one node fewer per ground
run always, and the mix can be a **noise-masked dissolve** rather than a uniform alpha fade, so
the new pattern arrives in patches instead of the whole screen ghosting through a half-and-half
state.

Mechanically C is three things:

1. `blend_into()` **does not carry `ice_texture` at all** (it writes `null`), unchanged from A.
   A single blended palette structurally cannot express a crossfade between two textures — that
   needs both endpoints *and* the weight. So `BiomeDirector.push_palette()` passes the pair and
   the ice channel weight straight through to `terrain_generator.apply_ice_palette()`.
2. `build_ice_band()` builds **one** `Polygon2D` per ground run. Its own `texture` is the
   outgoing tile — which it must keep, because `Polygon2D` normalises `uv` by its own texture's
   size and the band writes UVs in texture pixels. The incoming tile and the weight are
   uniforms on **one shared `ShaderMaterial`**, so a transition moves them with a single write
   instead of a walk, and no two bands can hold different values for them.
3. `repaint_chunk()` still walks, but only for the vertex tints — which are genuinely
   per-vertex, since the hue drift is a function of `world_x` — plus the base tile. It writes
   `polygon.texture` **unconditionally on every call**, which the B-era code was explicitly
   forbidden to do.

**That reversal is the subtle part.** The old rule existed because there was only one texture
slot and therefore no way to be halfway between two tiles, so writing it meant popping every
on-screen chunk in a single frame. The shader provides the halfway, and the safe thing is now
the opposite. Both files carry a comment saying so.

The invariant that makes it pop-free at both ends of the window: every chunk — freshly built or
repainted — derives its appearance from the same values, so they cannot disagree; and at weight
1 the shader outputs the overlay tile everywhere, which is the same pixels as the next frame's
weight 0 with the base already swapped to that tile. **Both ends were measured at max delta
0/255** against dedicated single-tile reference frames.

Under `--headless` the weight is always 0 and every uniform stays at its default, so every gate
draws exactly the pixels it always did.

## The ice shader (2026-08-10)

`shaders/ice.gdshader` is the **only** shader in the project, and it is on the ice band and
nothing else. Sky, obstacles, player and UI stay `Polygon2D`/`TextureRect`. It has three jobs,
and they are the three things vertex colours provably cannot do:

| Uniform | Default | What it is for |
|---|---|---|
| `overlay_tile` / `overlay_weight` | — / `0.0` | the two-tile dissolve above |
| `dissolve_softness` | `0.12` | width of a patch's soft edge |
| `contrast` | `1.0` | tile contrast **independent of hue** — the palette's `ice_surface`/`ice_depth` are a hue ramp by contract, so they cannot express this. Driven by `BiomePalette.ice_contrast`, below |
| `gloss_strength` / `gloss_depth` / `gloss_softness` | `0.0` / `0.16` / `0.12` | a sheen for a later flat-lake biome; parameterised now, left off |

**Every default is an exact identity**, and that is verified rather than asserted: with the
material swapped in place inside one frozen frame, `ice.gdshader` at its defaults renders
**pixel-identical** (max delta 0/255, 9 bands × 3 positions) to no material at all — which is
what the old build drew at weight 0, since its second band was hidden there.

### `ice_contrast` — the palette field that drives it (2026-08-11)

`BiomePalette.ice_contrast` blends on `CHANNEL_ICE` alongside the tints and is pushed onto the
shared material in `apply_ice_palette()`, so it crossfades with them instead of snapping at a
chunk boundary. It is the **one ice field that is not a hue**: every other one multiplies a
greyscale tile, which scales light and dark by the same factor and can never move the ratio
between them.

**Its effect is asymmetric on purpose.** The tile's surface rows sit near 1.0, so a value
above 1 clamps there — the snow band is left alone while cracks and mid-tones deepen. A value
below 1 pulls everything toward `CONTRAST_PIVOT` at once, which is the flat, veiled read the
hazy and dusk biomes want. Authored along the day arc: clear light crisp
(`glacier_teal` 1.28, `starlit_night` 1.20 — moonlight is a hard small source), haze and dusk
flat (`mauve_haze` 0.78, `twilight_blue` 0.80).

**The measured peak is ≈ `78 × |1 − ice_contrast|`**, near-constant across the eight, because
the pixels that move most are those surface rows and they sit a fixed distance from the pivot.
So `sky_layer_check`'s `IceContrast` floor (10/255, its own — the 24 calibrated for the sky
overlays is unreachable here without washing the ice out) is really a floor on the *authoring*:
below `|1 − contrast| ≈ 0.13` the field is set but is not a decision anyone sees. The first
authoring pass had two biomes under it, at 5 and 9/255, and that is what caught them.

Two rules the file depends on, both easy to break:

- **`contrast` and `gloss_strength` must fade to exactly zero effect before the band's bottom
  row.** `get_deep_fill_color()` hardcodes that row as `ICE_TILE_DEPTH_FLOOR * ice_depth_tint`
  so the flat deep fill meets it without a step; anything that moved it would open a seam
  across the whole world at `ICE_BAND_DEPTH`. Both are multiplied by a depth fade that reaches
  0 at `UV.y = 0.95`. Measured: each visibly changes the band (34 and 45/255) while leaving the
  bottom 4% pixel-identical.
- **The dissolve mask wraps on a fixed lattice period.** `UV.x` is `world_x /
  ICE_TILE_WORLD_WIDTH` and `world_x` is never rebased, so it grows without bound over a long
  session — and `fract()`-based hashing loses its fractional bits once the input gets large,
  which would degrade the mask into flat blocks late in a run. The integer cell is wrapped
  (not the sample point, which would seam) on a period of ~76 800 world px: longer than a whole
  biome, so it cannot read as a repeat.

### The trap that made this shader necessary to get right

In a `canvas_item` shader `COLOR` is **in-out**, and on entry to `fragment()` it already holds
`vertex_color * texture(TEXTURE, UV)`. So the identity body is `COLOR = COLOR;` (or an empty
`fragment()`), **not**

```glsl
COLOR = texture(TEXTURE, UV) * COLOR;   // WRONG: multiplies the tile in twice
```

which is the 3D/`ALBEDO` convention and looks like the obvious no-op. It squares the texture —
invisible at 1.0, worst at the dark end, and this tile's V axis is depth with a 1.0 → ~0.38
ramp down it, so the symptom is ice that looks right at the ride line and progressively too
dark with depth (measured: up to 55/255). It is not a colour-space bug, not a `render_mode`
bug, and nothing to do with how `Polygon2D` feeds `vertex_colors` — all three were ruled out by
measurement. **No `render_mode` line is needed**: `blend_mix` is already the default and there
are no 2D lights in this project.

Because of that same in-out semantic the shader cannot read the raw vertex tint in
`fragment()`; it captures `COLOR` in `vertex()`, where it is still untouched, and carries it
across in a varying. Full log: `docs/research/ice_shader_color_semantics.md`.

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
so `apply_ice_palette()` and therefore `repaint_chunk()` never run in any of the seven, and
every shader uniform stays at its default there. The dissolve contract was verified with
throwaway probes that built a real `Main`, froze it on an exact physics tick, and drove
`apply_ice_palette()` by hand across the weight with two genuinely different tiles: weight 0
renders exactly the base tile and weight 1 exactly the overlay tile (max delta 0/255 against
dedicated single-tile reference frames — the pop-free handoff at both ends), monotone and
strongly bimodal in between, and the shader at default uniforms pixel-identical to no material.
Not kept: they would join the archived one-offs `CLAUDE.md` warns about. Rebuild them if the
band construction changes again — `docs/research/ice_shader_color_semantics.md` records what
they measured and, more usefully, **how to build one that is actually sound**:

> Two separate runs cannot be diffed, even with the seed *and* the physics tick pinned. Render
> frames and physics ticks drift apart; coins, obstacles and the player sprite animate on the
> render clock; and two runs of different builds still diverge sub-pixel in `player_x`, which
> fills the diff with tree and surface-line edges. The sound test swaps the material **in place
> inside one frozen frame of one run**, where geometry, camera and lighting are identical by
> construction.

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
