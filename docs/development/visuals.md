# Visuals — background, scenery and palette

Everything on screen except the player sprite is an untextured `Polygon2D` / `ColorRect` /
`TextureRect`. There are exactly **two** shaders, and both are ice: `shaders/ice.gdshader` on
the ice band (`biomes.md`, "The ice shader") and `shaders/frozen_lake_reflection.gdshader` on
the frozen lake's surface quad, which exists only while a lake is being crossed ("The skate
trail" below, and `terrain.md`). There is no `WorldEnvironment`, no MSAA and no `z_index` in the
project. Draw order is scene-tree order plus `CanvasLayer.layer`, and that is deliberate.

Art direction: layered minimalist winter, in the Alto's-Adventure tradition — large open
landscape, smooth silhouettes, soft gradients, heavy negative space. The palette is a
*daylight reading* of `art_source/ChatGPT Image Aug 6, 2026, 07_13_24 PM.png` (that reference is a
night scene; its composition, layering and colour family carried over, its darkness did
not — see "Why daylight" below).

## The layer stack

Front-to-back, as wired in `scenes/main.tscn`:

| Node | Kind | `layer` / `motion_scale` | Script |
|---|---|---|---|
| `CanvasLayer` | UI | `1` | — |
| `TerrainGenerator` chunks, pickups, obstacles | world | `0` | `terrain_generator.gd` |
| `TerrainGenerator/GroundTreeSpawner` | world | `0` | `ground_tree_spawner.gd` |
| `Player` | world | `0` | `player.gd` |
| `SnowDrift/SnowParticles` | `GPUParticles2D` | `-50` | `snow_drift.gd` |
| `BirdFlock/Flock` | `Node2D` | `-60` | `bird_flock.gd` |
| `ParallaxBackground/IceStrip` | `ParallaxLayer` | `(0.05, 0)` | `background_strip.gd` |
| `ParallaxBackground/MidRidge` | `ParallaxLayer` | `(0.035, 0)` | `background_generator.gd` |
| `ParallaxBackground/FarRidge` | `ParallaxLayer` | `(0.025, 0)` | `background_generator.gd` |
| `ParallaxBackground/FarPeaks` | `ParallaxLayer` | `(0.015, 0)` | `background_generator.gd` |
| `SkyBackdrop/SkyCelestial` | `TextureRect` | `-200` | `sky_backdrop.gd` |
| `SkyBackdrop/SkyStars` | `TextureRect` | `-200` | `sky_backdrop.gd` |
| `SkyBackdrop/SkyGlow` | `TextureRect` | `-200` | `sky_backdrop.gd` |
| `SkyBackdrop/SkyGradient` | `TextureRect` | `-200` | `sky_backdrop.gd` (baked 8×256 image, not a `GradientTexture2D`) |

`ParallaxBackground` sits at the engine default `-100`, so everything it contains is
behind the world and in front of the sky.

`SkyGlow` and `SkyGradient` share a `layer`, so their order is **tree order**: the glow is
added second in `_ready()` and therefore draws over the gradient. There is no `z_index`
anywhere in the project to override that with.

### There has to BE a sky (2026-08-10)

For the whole life of the background pass there was effectively none. `FarPeaks` sat at
`base_y_fraction = 0.34` with heights up to **340px**, so its peaks topped out at y = −120 —
*above the top of the screen* — and the four parallax layers covered the frame edge to edge.
Measured with an opaque full-rect `ColorRect` on the `SkyBackdrop` layer: **2.4% of the frame**,
confined to the top 7%, never more than 45% of any row. What read as "sky" was the pale
`FarPeaks` silhouette.

Nothing was wrong with the sky code; it had nowhere to draw. Both 1a's glow and 1b's disc
rendered correctly and were completely invisible in game — all four discs measured **0/255**.

The layers were lowered and compressed so the tallest peak now tops out at y ≈ 0.21:

| Layer | `base_y_fraction` | heights | ridge tops |
|---|---|---|---|
| `FarPeaks` | 0.34 → **0.42** | 140–340 → **65–135** | y 0.21–0.32 |
| `FarRidge` | 0.44 → **0.47** | 110–260 → **55–110** | y 0.30–0.39 |
| `MidRidge` | 0.52 → **0.52** | 75–190 → **45–90** | y 0.38–0.45 |
| `PineLine` | **unchanged** | unchanged | y 0.51–0.57 |

**Historical: `PineLine` no longer exists.** The table above records a 2026-08-08 pass, when the
near layer was a procedural pine treeline. It was replaced by the raster `IceStrip` (see the
draw-order table); the three ridge layers and their retuned heights are still live. The reason
`PineLine` was left alone then still applies to what sits there now: the near layer's line sits
*below* the ice surface (~y 0.46), which is what makes it read as standing behind the slope
rather than on top of it. Raising it breaks that immediately.

`haze_rise` came down with the heights (230/190/140 → 140/120/100), or the haze band starts
above the ridge it is supposed to be veiling and washes out the new sky.

**If you change the ridge geometry, re-measure the sky.** The composition is the constraint on
everything in `sky_backdrop.gd`, and it is invisible from the code.

### Overdraw is the sky's real budget

Every layer stacked over a pixel shades it again, and full-screen semi-transparent rects are
where a mobile GPU actually pays. `SkyGradient` is opaque so it costs nothing extra;
`SkyGlow` and `SnowDrift` are alpha. **Budget: at most 4 full-screen alpha layers at once.**

Two rules follow, both already applied in `sky_backdrop.gd` and worth keeping:

- **Hide a layer at zero, do not draw it transparent.** A fully transparent full-screen
  `TextureRect` still rasterises every pixel it covers. Same reasoning as
  `terrain_generator.paint_snow_cap()`'s `visible = snow_cap_strength > 0`.
- **Size a rect to its content, not to the screen.** `SkyGlow` is anchored to its own box.
  It is deliberately *not* clamped to the viewport: fragments outside are scissored before
  shading, so a bloom hanging off an edge only costs the visible part — while clamping would
  squash the texture and change the falloff's shape.

Note the pre-existing quirk that terrain draws **over** the player: `TerrainGenerator`
comes after `Player` in `main.tscn`. Not introduced by the visual pass and not changed by
it.

## Base viewport size (2026-08-13)

`project.godot` pins `window/size/viewport_width = 1152` / `_height = 648`, with
`stretch/mode = "canvas_items"` and `stretch/aspect = "expand"`. `Camera2D.zoom` is `0.8333`.

This was **unset until 2026-08-13** — the engine's own 1152×648 default applied, so the number
every art decision depended on was written down nowhere. Pinning it changed nothing observable
and needed no gate re-run.

**Base size and camera zoom are one decision; only their ratio is gameplay.** Visible world =
base ÷ zoom = **1382 × 778 world px**. Changing either alone changes the field of view, which on
an auto-runner is how much warning the player gets. Terrain constants are unaffected either way —
`GROUND_Y`, `ICE_BAND_DEPTH`, `FILL_GRADIENT_DEPTH` and `CHASM_LEAD_IN_LENGTH` are all world px.

### What `expand` actually does

`scale = min(window.x / base.x, window.y / base.y)`, then the viewport is sized to
`window ÷ scale`. The base is therefore a **minimum in both axes** — a device never sees *less*
than the base, only more in one direction:

| Device | Window | Viewport | Visible world | Forward view @ 750 px/s |
|---|---|---|---|---|
| 16:9 desktop | 1920×1080 | 1152×648 | 1382×778 | ~0.92 s |
| 19.5:9 iPhone | 2556×1179 | 1404×648 | 1685×778 | ~1.12 s |
| 20:9 Android | 2400×1080 | 1440×648 | 1728×778 | ~1.15 s |
| 4:3 iPad | 2048×1536 | 1152×864 | 1382×1037 | ~0.92 s, extra height |

So tall phones get **+25% forward visibility** and tablets get extra sky/ground rather than extra
warning distance. Bounded, and in the forgiving direction. Equalising it properly means an
**aspect-compensated `Camera2D.zoom`** — still open, deliberately not done here, and it needs
`camera_shake_probe` re-run plus a playtest because it changes what players see.

**Fixing the height is what the rest of this file rests on.** Every `base_y_fraction` in
`main.tscn` and every sky anchor is a fraction of viewport height, so the vertical composition —
the whole point of the sky pass — is now identical on every device.

### Authoring raster art

`canvas_items` scales the **canvas transform**, not a low-res framebuffer, so `Polygon2D`, text
and every generated shape render at full device resolution regardless of the base. Only raster
sprites care. One world px maps to `zoom × (window.y / 648)` device px:

| Device | Device px per world px |
|---|---|
| 1080p phone | 1.39 |
| 1440p phone | 1.85 |

> **Author source art at ≈2× its intended world size.**

The shipped player sprite already sets the reference: `skate_0.png` is 150×180 for a 51×61 world
footprint (`AnimatedSprite2D` at `scale 0.34`), i.e. ~2.9× — generous, and harmless.

| Object | World size | Author at |
|---|---|---|
| Coin (`coin.tscn` `ColorRect` 16×16) | 16×16 | 32–48 px |
| Obstacle (`obstacle.tscn` 32×32) | 32×32 | 64–96 px |
| Ground tree (`ground_tree_spawner.build_tree`) | ~40×70 | 80–140 px |

**Four couplings will make an art swap silently wrong rather than hard**, and none of them
errors — fix each alongside its sprite: `obstacle_spawner.gd`'s `OBSTACLE_HALF_HEIGHT`
duplicates `obstacle.tscn`'s shape; `glide_coin_spawner.gd` tints the bonus coin by looking up a
child *named* `"ColorRect"`; `AIR_COIN_SCALE` scales the whole `Area2D`, so visual scale **is**
pickup range; and the surface clearances in `coin_spawner.gd` (34) and `powerup_spawner.gd` (40)
were derived by hand from the placeholder rect sizes.

### The app icon (2026-08-25)

Not game art, but the same pipeline: source in `art_source/`, baked into `assets/` by a tool in
`scripts/tools/`, never hand-placed.

`art_source/aura.png` is a **3×3 contact sheet of nine candidate icons**, not an icon.
`scripts/tools/build_app_icons.py` measures the sheet's gutters, cuts one tile and writes the
three launcher images. The shipped tile is `--row 1 --col 2`, the aurora over dark peaks — the
game's namesake, and the highest-contrast of the nine. Re-cutting a different one is one flag.

Four things here fail silently, all verified by exporting an APK and unzipping it, which is the
only way to see what actually ships:

- **An empty `launcher_icons/*` path does not mean "no layer".** Godot substitutes the project
  icon, still the stock Godot robot. That is why `adaptive_foreground_432x432` points at a
  deliberately **fully transparent** PNG rather than being left blank: the art lives in the
  background layer, and a blank path would have put the Godot logo on top of it.
- **`adaptive_monochrome_432x432` is still empty, so the themed icon IS the Godot robot** on
  Android 13+ with themed icons enabled. Confirmed in the APK: 23,679 opaque pixels of Godot
  logo. Deriving a silhouette from the aurora tile was tried at several thresholds and produced
  unreadable mush — a photographic scene has no single-colour reduction. It needs a simple
  drawn mark, which is a design decision, not a build step. **Open.**
- **The two crops are different on purpose.** The tile has rounded corners baked into its
  pixels. The adaptive background takes the *full* tile, because the launcher's mask cuts well
  inside those corners; the legacy 192px icon takes an *inset* crop, because old launchers draw
  the square as-is and the baked corners read as a black frame. Backwards, it is either
  black-cornered or over-zoomed.
- **`assets/icons/*` is in `export_presets.cfg`'s `exclude_filter`, and must stay excluded but
  present.** The exporter reads launcher icons off disk at export time, not out of the pack, so
  excluding them saves ~225 KB of `.ctex` that no code ever loads (verified: the `res/mipmap-*`
  icons are identical either way). **Excluded does not mean unused — deleting these files
  breaks the icon**, and nothing will fail to tell you.

## How depth is produced

Three independent cues, no shaders involved:

1. **Colour.** Distant things sit closer to the sky colour. Under a *pale* sky that means
   far = lighter, so `FarRidge` is the lightest scenery and the near layer the darkest.

   **Note the near layer never reaches its authored end of that ramp.** `get_scenery_color`
   lerps `scenery_far → scenery_near`, but the scene's `depth_t` values top out at 0.45, so
   `scenery_near` itself is never rendered and every palette shows only the far 45% of its
   ramp. **That is not a bug and it is now guarded** — as of 2026-08-25 `biome_schedule_check`
   reads the scene's real `depth_t` range and applies its separation floor there, rather than
   to the authored endpoints it used to measure (review item #5, closed). Before that it
   passed `pale_morning` at 0.223 while the frame showed 0.100.

   The consequence for authoring: **a palette's `scenery_far`/`scenery_near` pair has to be
   roughly twice as wide as the separation you want on screen.** Widening the ramp and
   spreading the layers' `depth_t` are interchangeable fixes, and the gate's failure text names
   both.

   **The old corollary — "terrain is lighter than all of them" — is dead as of 2026-08-08.**
   `one.png`, the target art, is *dark saturated ice under a pale sky*, and that inversion
   is most of why it reads well. Since the biome pass the sky is not reliably pale either.
   What replaced it is a contrast contract that survives any palette, and that
   `biome_schedule_check.gd` enforces rather than merely documents: **the surface rim stays
   bright** (that `Line2D` core, not the fill, is what the player tracks the ride surface
   by), and **far and near scenery stay separated in luminance** so the recession below
   still has something to work with. Ordering of *scenery* layers still holds; ordering of
   terrain against scenery does not, and was never what made the surface readable.
2. **Parallax rate.** Layers further back move slower. The near-to-far spread is
   `0.05 … 0.015` (3.3:1); it was `0.30 … 0.03` (10:1) before the panorama landed. **That
   flattening was reviewed and kept, 2026-08-25** (review item #3) — not drift any more, a
   decision.

   **`IceStrip`'s `motion_scale` is not a free knob, and this is the trap.** It is the front
   layer, so it is the one anybody reaching for more depth separation would raise — but it is
   also the *raster* layer, and a raster layer loops. `ParallaxLayer.motion_mirroring` is fixed
   in layer px, so the panorama's repeat distance is `mirror ÷ motion_scale`: at the shipped
   0.05 the loop is 79,590 world px (106 s at `MAX_SPEED`, 1.06 biome cycles); at 0.15 it is
   26,530 px (35 s). Depth separation and repeat visibility are the same number pulled in
   opposite directions, and the three procedural layers behind it have no such constraint
   because they never repeat. Raise the front layer only with the loop re-measured.
3. **Haze.** Each layer builds two child containers in `_ready()`: `Ridges`, then `Haze`.
   Because `Haze` is added second it draws over every silhouette in **its own** layer and
   only that layer — so layer N's haze veils layer N, and layer N+1's silhouette then
   draws crisply on top of it. The recession falls out of tree order alone.

## Silhouette generation

`background_generator.gd` is one parameterised script attached to all three
`ParallaxLayer`s; they differ only by `@export` values. A new layer is a scene edit, not a
new script.

Skyline height is `get_ridge_height(x)` — three sine octaves, **pure in
`(rng_salt, x)`**. Purity is what makes adjacent segments join: the shared boundary x is
fed to the same function twice and yields the same y, so seams are impossible by
construction rather than by bookkeeping. Same discipline as
`TerrainGenerator.get_terrain_height` being pure in `(session_seed, world_x)`.

`RIDGE_WAVE_WAVELENGTHS` are true wavelengths in pixels and `get_ridge_height` converts
with `TAU`. The first cut fed them to `sin(x / period)` directly, which made the real
wavelengths 2π larger — ~16,000 px for the first octave — and rendered every skyline as a
straight diagonal line. If the mountains ever look flat again, check this first: an octave
much longer than the ~1150 px viewport cannot read as a mountain, only as a slope.

Pines (`shape_kind = 1`) are placed on a **global** grid, so a tree's identity is its
absolute index rather than its offset within a segment — that is what keeps a given tree
at the same x with the same height regardless of which segment contains it. Each is rooted
on the ridge line at its own x, so the tree line grows out of the hill instead of floating
in front of it.

## Ground-attached trees

`ground_tree_spawner.gd` is the one piece of scenery that is *not* decorative parallax:
it is a `TerrainGenerator/GroundTreeSpawner` child, chunk-lifecycle-identical to
`coin_spawner.gd` (same spawn/despawn window, same "don't read `session_seed` in
`_ready()`" ordering trap, own hash-multiplier pair so its sequence never lines up with
any other spawner's). Each tree's root position is `terrain_generator.get_terrain_height(world_x)`
in `TerrainGenerator`'s own local space — the same value `build_chunk_surface` feeds the
visible snow polygon — so a tree sits exactly on the rendered surface, not floating above
or buried in it, and tilts to the local `get_slope_angle_at_x`. Trees are skipped wherever
`has_ground_at_world_x` is false, so nothing plants itself over a chasm void.

An additional `FarPeaks` parallax layer (behind `FarRidge`, `motion_scale.x = 0.03`) and
taller `ridge_height_max` on the existing ridge layers exist so the skyline reads as
mountains rather than a single flat color once the camera climbs during a glide — see
"Traps" below for why this still goes flat above a certain altitude, by design.

## Terrain fill shading

`build_chunk_fill` / `close_fill_run` in `terrain_generator.gd` build the solid polygon
below the visible snow surface — it exists purely as a safety margin so a deep camera
excursion never scrolls past the bottom of a chunk's paint. `TERRAIN_FILL_DEPTH_MARGIN` is
4096px, and a high glide (`main.gd`'s `is_glide_vertical_follow_active`) can put most of
that fill on screen with the actual bumpy surface scrolled almost out of frame — at that
point the fill *is* the picture, and a single flat `Color` reads as a blank screen.

`build_fill_vertex_colors` fixes this by giving each fill polygon `Polygon2D.vertex_colors`:
`FILL_GRADIENT_TOP_TINT` at every surface-line vertex, `FILL_GRADIENT_BOTTOM_TINT` at the
two bottom corners `close_fill_run` appends. There are only two vertex rows (top and
bottom), so this is one linear ramp over the full 4096px, not a curve; it doesn't need to
be more than that; it only needs to not be flat.

### Ice texture (2026-08-07, remapped to depth 2026-08-08)

> **Corrected 2026-08-10.** This section described `apply_fill_texture()`, which put the tile
> on the *fill* polygon. That function is gone. The fill is now **flat and untextured**
> (`build_fill_vertex_colors()` writes one colour to every vertex), and the tile lives on its
> own **quad-strip bands** built by `build_ice_band()`. The reason is in
> `terrain_generator.gd`'s header: the fill has ~64 vertices along the top and exactly four at
> the bottom, so Polygon2D fans it into long skinny triangles, and "depth below a curved
> surface" is not affine — fanning it across those triangles smeared the texture into a funnel
> that restarted at every chunk boundary. The band is one quad per surface sample instead, so
> V is exact at every vertex.

`build_ice_band()` (called from `build_chunk_fill`, once per ground run) builds a two-row quad
strip hugging the surface and assigns it
`assets/textures/terrain/ice_depth_gradient.png`, with
`texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED` and the project's one shader
(`shaders/ice.gdshader`, `biomes.md`). **The band's own `texture` must stay set** even though
the shader could take both tiles as uniforms: `Polygon2D` normalises `uv` by its own texture's
size, and the band writes UVs in texture pixels, so a null texture there would feed raw pixel
values through as UVs.

**The tile is not a picture of ice — its vertical axis is depth below the ride surface.**
Snow band at the top, glossy pale sheen under it, deepening body, thin cracks at plausible
depths. The band maps V to exactly that: 0 along its top row, `ICE_BAND_DEPTH` along its
bottom one. So gloss, cracks, snow clumps and the fill's whole vertical
colour structure are *painted in* and land correctly on every hill in every biome — four
features from one image, and no per-slope maths. Full rationale in `biomes.md`. The shader on
the band does not touch any of this: it dissolves between two tiles and carries `contrast` and
`gloss_strength`, and at its default uniforms it is a measured pixel-exact no-op.

Because the tile carries the light-to-dark ramp itself (1.0 → ~0.52),
`FILL_GRADIENT_TOP_TINT`/`BOTTOM_TINT` and the palettes' `ice_surface`/`ice_depth` must vary
**hue, not brightness**. Two darkening ramps multiplied together take deep ice to black;
`biome_schedule_check.gd` enforces the bound.

The band's lower row takes the same maximal V all the way across. That V is a texel short of
the true bottom (`ICE_TILE_V_INSET`) because **`texture_repeat` applies to both axes in Godot** — a V
landing exactly on the texture height wraps to row 0, the bright snow band, painting a white
line straight across the fill at the gradient stop.

`ICE_TILE_WORLD_WIDTH` (1200) stretches the square tile sideways deliberately: it turns the
source's steep cracks into the long lazy ones the reference art has, and slows the horizontal
repeat to ~1.6 s at `MAX_SPEED` instead of ~0.5 s.

**Texture provenance**: built by `scripts/tools/build_ice_texture.py` from a generated
greyscale panel (`art_source/terrain/three.png`). **Run that script rather than dropping a
raw image in** — it does two things the raw panel needs. It lifts the darks: a raw panel
bottoms out near 0.09, and since `Polygon2D` multiplies, that takes every biome tint to
black. And it cross-fades the horizontal wrap. It deliberately does **not** mirror, which is
what the tile it replaced (`ice_terrain_one.png`, a 2×2 mirror of a featureless crop) did —
mirroring guarantees a seamless join but stamps in a symmetry axis, visible as a faint
diamond, and long diagonal cracks would turn that into a chevron every repeat.

**UV.x is world_x, not local_x.** `build_chunk_surface`'s geometry is chunk-local by
design (`local_x = world_x - chunk_start_x - chunk_width * 0.5`), but UV'ing the texture in
that same local space would restart the texture's phase at every chunk boundary — the
exact seam-per-segment look this exists to avoid. `build_ice_band` adds
`chunk_start_x + chunk_width * 0.5` back onto every sample's `x` before scaling it into a U,
so the texture phase is continuous across chunk boundaries. `paint_ice_band` then inverts that
to recover `world_x` for the hue drift, which is why the drift can never fall out of step with
the pattern. `world_x` grows unbounded over a long session (`main.gd`: "X is never
world-rebased"); this doesn't introduce a new precision failure mode, since
`chunk.position.x` already carries the same unbounded value.

## Birds (glide-only)

`bird_flock.gd` sits on `BirdFlock/Flock`, a `Node2D` child of a `CanvasLayer` at
`layer = -60` (in front of the parallax mountains, behind `SnowDrift`'s `-50`) — the
`Node2D`-under-`CanvasLayer` split exists because `CanvasLayer` extends `Node`, not
`CanvasItem`, so it has neither `modulate` nor `get_viewport_rect()` (same reason
`snow_drift.gd`'s script lives on the `GPUParticles2D` child, not the `SnowDrift`
`CanvasLayer` itself).

This is the fix for the case "Terrain fill shading" above can't reach: at extreme glide
height the entire visible screen can be *past* `FILL_GRADIENT_DEPTH`, at which point no
amount of fill tuning helps — the whole frame is flat by construction, just a darker flat.
Birds aren't tied to terrain depth at all, so they read as something happening on screen
regardless of how far below the surface actually is. `flock_alpha` fades them in/out off
`player.is_glide_active` (`FADE_SMOOTHNESS`), so they only ever appear during the glide
they exist for, never as clutter over obstacles during ordinary play.

## The skate trail (frozen lake only)

Two nodes, both visible only while a lake is being crossed, both riding
`FrozenLakeDirector.get_lake_blend()` like everything else cosmetic on the lake.

**`SkateSpray`** (`GPUParticles2D`) — the glints thrown off the blades. **`SkateTrack`**
(`Line2D`) — the etch left in the ice. **Tree order between them is load-bearing:** the mirror
quad at full blend *is* the lake surface, so the track sits above it (the etch is in the ice)
and the spray above that (chips are on top). Spray drawn before the mirror is spray drawn under
the ice.

**Why one is particles and the other is not, which is not an inconsistency.** The spray is
hundreds of independent motes with their own physics — what a particle system is for. The etch
is one continuous mark whose whole character is that it is *connected* and lies exactly where
the blades went, which particles cannot express without each one knowing about its neighbours.

**Neither is `scripts/effects/flight_trail.gd`.** That is the project's earlier trail attempt
and it is still live on boost; it spawns *unconnected* 14px sticks with random y jitter, so it
reads as tally marks rather than a path. The failure was the construction, not the class.

Four findings worth keeping:

- **A glint is not a snowflake.** The first spray copied `snow_drift.gd`'s soft round puff and
  read as *"snow being shot out."* The fix was shape (a four-point star with a hard core) and
  **additive** blending, not more glow. Snow covers a surface; a glint is light arriving.
- **Chips must not arc.** A parabola is the signature of a thrown object — the eye reads the arc
  and infers mass. Gravity is now very slightly *negative* so the field creeps up rather than
  hanging with the unnatural stillness of exactly 0, and the trail comes entirely from the player
  running out from under them at 750 px/s. **Trail length is therefore not a constant**; a slower
  player leaves a shorter one, which is correct.
- **THE TRACK IS NOT ADDITIVE, AND THAT IS THE OPPOSITE CHOICE FROM THE SPRAY.** It shipped
  additive once and read as *"just a single white line."* The lake measures (182,208,238) —
  luma 205, with only **17 luma of blue headroom** — so additive light saturates blue first and
  can only drift toward white, and the core clipped to (255,255,255) past ~400px. **A clipped
  signal carries no information.** It now blends normally and makes its glow from *saturation
  plus a modest luma lift*: the tail works by **removing red**, which additive structurally
  cannot do. This is the standing "it looks grey means saturation, not brightness" finding on a
  second axis — here it looked *white* and the answer was the same one.
- **The spray stays additive deliberately.** Its chips are tiny, sparse and short-lived, so
  clipping a few dozen pixels reads as a hot specular spark. A continuous line clipping the same
  way is just a bar.

**Verify a procedural sprite by rendering it, not by reading the formula.** The flare taper has
to be squared; rendered out, a linear taper made the horizontal flare a uniform full-width bar —
120 little dashes, exactly the geometric look that made `flight_trail.gd` unusable.

**Rebasing is answered in opposite ways, and the reason is ownership.** Live particles belong to
the GPU and nothing can move them, so `SkateSpray` can only drop its chips on a shift.
`SkateTrack`'s points are an array it owns, so the shift is applied to them and the mark
survives intact — shifts are whole powers of two, so adding one is exact in binary.

## Traps

* **`motion_scale.y` must stay 0 on every layer.** Vertical parallax was tried and
  reverted: it snapped the background on every world rebase (~26 s) and lost its vertical
  coverage after a few mega drops. `docs/development/dead_code.md`, "Vertical parallax —
  tried, reverted". Screen-locked vertically is also precisely what makes the whole
  backdrop immune to `main.gd`'s rebase, which shifts Y on
  `TerrainGenerator`/`Player`/`Camera2D` only.
* **Never read `TerrainGenerator.session_seed` in background code.**
  `ParallaxBackground` is `main.tscn`'s *first* child, so these `_ready()`s run before
  `TerrainGenerator`'s and `session_seed` is still 0 there — the ordering trap
  `architecture.md` documents, which shipped once as an identical powerup schedule every
  session. Silhouettes key on `rng_salt`, a per-layer constant, instead. No session
  variety is needed: the skyline is a function of world x and an endless runner never
  revisits an x.
* **All six headless gates instantiate `main.tscn`**, so every line of background code
  runs on every gate frame, and there is no `debug_*_disabled` opt-out for it. Keep
  `_physics_process` to the index arithmetic it already is; do no per-frame node work. A
  *parse* error here makes the gates **hang** rather than fail.
* **`snow_drift.gd` disables emission under `--headless`**, computed locally from
  `DisplayServer.get_name()` and never from `Services.is_headless` — `freeze_replay_runner`
  adds Main inside its `_init()`, before the autoload's `_ready()` has flushed. Same
  one-line check, and same already-measured bug, as `sfx_player.gd`.
* **Snow lives at `layer = -50`: behind all gameplay.** Snow drifting over an obstacle or
  a coin is the one part of this system that could genuinely cost readability, so it is
  placed where it structurally cannot. Do not raise it above `0`.
* **`snow_drift.gd`'s headless branch must call `set_process(false)` before it returns.**
  `_process` is what reads `player.is_glide_active` to thicken the snowfall during a glide
  (see "Terrain fill shading" — same high-glide moment); `Node._process` defaults to
  *enabled*, so skipping that call while `player` is still unset crashes every headless
  gate on the first frame. Shipped and caught by `freeze_replay_runner` before merge.
* **Every full-screen `Control` sets `mouse_filter = MOUSE_FILTER_IGNORE`.** `Control`
  defaults to `MOUSE_FILTER_STOP`, and the sky and haze bands cover the whole screen —
  left at the default they are input eaters sitting under the pause button.
* **Still read the viewport, never hardcode it.** The base size is pinned as of 2026-08-13
  (see "Base viewport size" above, and `docs/review/2026-08-03-architecture-audit.md` §B4,
  now closed), but `aspect="expand"` means the *actual* viewport is still wider or taller
  than that base on most devices — the base is a floor, not a size. The sky uses full-rect
  *anchors*; the ridge layers and the snow emitter read `get_viewport_rect().size` in
  `_ready()` and re-read it on `size_changed`. Nothing here hardcodes a pixel height, and
  nothing should start.

## Palette

> **Since 2026-08-08 these are only the STARTING values, not the palette.**
> `biome_director.gd` overwrites all of them on the first frame of a run and again through
> every transition — see `docs/development/biomes.md`. They still describe exactly what is
> on screen under `--headless` (the director returns early there, so all six gates see the
> pre-biome look), and they are the fallback if the director fails to resolve a consumer.
> The eight live palettes are `resources/biomes/*.tres`. **Editing a constant below changes
> the gates and the fallback, not the game.**

| Element | Value | Where |
|---|---|---|
| Sky top / mid / horizon | `0.60,0.72,0.86` → `0.74,0.83,0.91` → `0.88,0.92,0.96` | `sky_backdrop.gd` |
| Far ridge | `0.68, 0.77, 0.86` | `main.tscn` export |
| Mid ridge | `0.57, 0.68, 0.80` | `main.tscn` export |
| Pine line | `0.45, 0.56, 0.69` | `main.tscn` export |
| Haze bands | pale sky tint, alpha 0.44–0.52 | `main.tscn` export |
| Snow | white, alpha 0.42 | `snow_drift.gd` |
| Terrain fill | `assets/textures/terrain/ice_depth_gradient.png`, V = depth below surface | `terrain_generator.gd` |
| Terrain fill tint (surface → `FILL_GRADIENT_DEPTH` down) | `1.0,1.0,1.0` → `0.83,0.88,0.98` — **hue shift, not darkening**; the tile owns the light-to-dark ramp | `terrain_generator.gd` |
| Rim core / glow | **removed 2026-08-08** — the tile's top rows are the snow band now | — |

**`Polygon2D` renders `texture_sample * vertex_color` and ignores its `color` property
outright whenever `vertex_colors.size()` matches the polygon's vertex count** — which it
always does here (`build_fill_vertex_colors()`). Confirmed by testing, back when the fill
had no texture and `LIGHT_CHUNK_COLOR`/`DARK_CHUNK_COLOR` were set to a saturated blue that
produced *zero* visible change. Terrain colour is
`assets/textures/terrain/ice_depth_gradient.png` (see "Ice texture" below) multiplied by
`FILL_GRADIENT_TOP_TINT`/`FILL_GRADIENT_BOTTOM_TINT`. Do not try to "fix" terrain colour
through `Polygon2D.color`; it won't do anything.

That multiply is also **why the biome pass needed no shader** — it is exactly the operation
an ice-tinting shader would perform, so the per-biome tint simply rides `vertex_colors`
(`biomes.md`, "Why colour is still not a shader's job"). That is still true: the one
`.gdshader` the project now has does not touch tint, hue drift or the depth ramp, all of which
remain vertex colours.

`LIGHT_CHUNK_COLOR`/`DARK_CHUNK_COLOR` were **removed on 2026-08-08**. They had been kept as
a canary for any future path where `color` became load-bearing; that path never arrived, and
the `apply_chunk_color()` traversal that justified them is now `repaint_chunk()`, which
writes `vertex_colors` for real. Don't reintroduce them — per-chunk parity colouring is
precisely what the seamless-surface pass exists to prevent.

### Ice surface rim — REMOVED 2026-08-08

Two stacked `Line2D` per ground run used to trace the surface: a 22px low-alpha glow under a
5px near-opaque core, faking a bloom highlight without a shader. Removed when the depth tile
landed — its top rows are a real snow band, which is softer and physically sensible (snow
settled on the lip) where the stroke read as a drawn outline.

**Don't reintroduce a stroke.** If the ride line ever needs strengthening it belongs in the
tile's top rows, where it stays correct on every slope for free and costs no nodes. The
palette's `ice_surface` is what now controls how bright that band reads, and
`biome_schedule_check.gd` holds a floor under it.

### Why daylight

> **Partly superseded 2026-08-08, and CLOSED 2026-08-13.** The run no longer stays in
> daylight — it cycles through eight moods including two genuinely dark ones (`biomes.md`).
> The *reasoning* below is still exactly right, and it is what Phase 2 acted on: every
> palette now authors `coin_color`/`obstacle_color`, and `BiomeDirector.push_palette()`
> pushes them to `CoinSpawner`, `GlideCoinSpawner` and `ObstacleSpawner`. The constants
> quoted below are now just the *starting* values, still what `coin.tscn`/`obstacle.tscn`
> ship and what a gate sees (the director is inert under `--headless`). See
> `biomes.md`'s "Gameplay contrast".

The reference image is a night scene (sky ≈ `#40526F` → `#303F63`, sampled). Daylight was
chosen over matching it literally, for a gameplay reason as much as an aesthetic one: the
obstacle is `Color(1, 0.1, 0.1)` and the coin `Color(0.98, 0.82, 0.15)`, both tuned
against a bright backdrop. Going near-black would have put every gameplay-object contrast
ratio up for re-judgement. Under the pale sky they keep exactly the separation they
already had, and the near-white terrain gains contrast rather than losing it.
