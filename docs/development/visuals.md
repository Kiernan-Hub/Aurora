# Visuals — background, scenery and palette

Everything on screen except the player sprite is an untextured `Polygon2D` / `ColorRect` /
`TextureRect`. There are no shaders, no `WorldEnvironment`, no MSAA and no `z_index`
anywhere in the project — draw order is scene-tree order plus `CanvasLayer.layer`, and
that is deliberate.

Art direction: layered minimalist winter, in the Alto's-Adventure tradition — large open
landscape, smooth silhouettes, soft gradients, heavy negative space. The palette is a
*daylight reading* of `ChatGPT Image Aug 6, 2026, 07_13_24 PM.png` (that reference is a
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
| `ParallaxBackground/PineLine` | `ParallaxLayer` | `(0.30, 0)` | `background_generator.gd` |
| `ParallaxBackground/MidRidge` | `ParallaxLayer` | `(0.14, 0)` | `background_generator.gd` |
| `ParallaxBackground/FarRidge` | `ParallaxLayer` | `(0.06, 0)` | `background_generator.gd` |
| `ParallaxBackground/FarPeaks` | `ParallaxLayer` | `(0.03, 0)` | `background_generator.gd` |
| `SkyBackdrop/SkyGradient` | `TextureRect` | `-200` | `sky_backdrop.gd` |

`ParallaxBackground` sits at the engine default `-100`, so everything it contains is
behind the world and in front of the sky.

Note the pre-existing quirk that terrain draws **over** the player: `TerrainGenerator`
comes after `Player` in `main.tscn`. Not introduced by the visual pass and not changed by
it.

## How depth is produced

Three independent cues, no shaders involved:

1. **Colour.** Distant things sit closer to the sky colour. Under a *pale* sky that means
   far = lighter, so `FarRidge` is the lightest scenery and `PineLine` the darkest.

   **The old corollary — "terrain is lighter than all of them" — is dead as of 2026-08-08.**
   `one.png`, the target art, is *dark saturated ice under a pale sky*, and that inversion
   is most of why it reads well. Since the biome pass the sky is not reliably pale either.
   What replaced it is a contrast contract that survives any palette, and that
   `biome_schedule_check.gd` enforces rather than merely documents: **the surface rim stays
   bright** (that `Line2D` core, not the fill, is what the player tracks the ride surface
   by), and **far and near scenery stay separated in luminance** so the recession below
   still has something to work with. Ordering of *scenery* layers still holds; ordering of
   terrain against scenery does not, and was never what made the surface readable.
2. **Parallax rate.** `PineLine` keeps the `0.30` that was already shipped and proven; the
   two ridge layers are *slower*. The pass therefore only ever moves background pixels
   less per frame than before, never more.
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

`apply_fill_texture()` (called from `build_chunk_fill`, right after `close_fill_run`)
assigns each fill polygon `assets/textures/terrain/ice_depth_gradient.png`, with
`texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED`.

**The tile is not a picture of ice — its vertical axis is depth below the ride surface.**
Snow band at the top, glossy pale sheen under it, deepening body, thin cracks at plausible
depths. `apply_fill_texture` maps V to exactly that: 0 at every surface vertex, maximal at
the gradient-stop corners. So gloss, cracks, snow clumps and the fill's whole vertical
colour structure are *painted in* and land correctly on every hill in every biome — four
features from one image, no shader, no per-slope maths. Full rationale in `biomes.md`.

Because the tile carries the light-to-dark ramp itself (1.0 → ~0.52),
`FILL_GRADIENT_TOP_TINT`/`BOTTOM_TINT` and the palettes' `ice_surface`/`ice_depth` must vary
**hue, not brightness**. Two darkening ramps multiplied together take deep ice to black;
`biome_schedule_check.gd` enforces the bound.

All four appended corners take the *same* maximal V, so the band below the gradient stop
samples the tile's bottom row flat rather than wrapping. That V is a texel short of the true
bottom (`ICE_TILE_V_INSET`) because **`texture_repeat` applies to both axes in Godot** — a V
landing exactly on the texture height wraps to row 0, the bright snow band, painting a white
line straight across the fill at the gradient stop.

`ICE_TILE_WORLD_WIDTH` (1200) stretches the square tile sideways deliberately: it turns the
source's steep cracks into the long lazy ones the reference art has, and slows the horizontal
repeat to ~1.6 s at `MAX_SPEED` instead of ~0.5 s.

**Texture provenance**: built by `scripts/tools/build_ice_texture.py` from a generated
greyscale panel (`three.png` in the project root). **Run that script rather than dropping a
raw image in** — it does two things the raw panel needs. It lifts the darks: a raw panel
bottoms out near 0.09, and since `Polygon2D` multiplies, that takes every biome tint to
black. And it cross-fades the horizontal wrap. It deliberately does **not** mirror, which is
what the tile it replaced (`ice_terrain_one.png`, a 2×2 mirror of a featureless crop) did —
mirroring guarantees a seamless join but stamps in a symmetry axis, visible as a faint
diamond, and long diagonal cracks would turn that into a chevron every repeat.

**UV.x is world_x, not local_x.** `build_chunk_surface`'s geometry is chunk-local by
design (`local_x = world_x - chunk_start_x - chunk_width * 0.5`), but UV'ing the texture in
that same local space would restart the texture's phase at every chunk boundary — the
exact seam-per-segment look this exists to avoid. `apply_fill_texture` takes the polygon's
local-space `uv` from `close_fill_run` and adds `chunk_start_x + chunk_width * 0.5` back
onto every `x` before assigning it, so the texture phase is continuous across chunk
boundaries. `world_x` grows unbounded over a long session (`main.gd`: "X is never
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
* **The viewport size is unset** (`project.godot` pins no `window/size/viewport_*`, and
  `stretch/aspect="expand"`), so window dimensions are genuinely unknown at author time.
  The sky uses full-rect *anchors*; the ridge layers and the snow emitter read
  `get_viewport_rect().size` in `_ready()` and re-read it on `size_changed`. Nothing here
  hardcodes a pixel height. That unset base size remains a real open decision
  (`docs/review/2026-08-03-architecture-audit.md` §B4) — this system survives either
  answer.

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
(`biomes.md`, "Why there is no shader"). The project still has zero `.gdshader` files.

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

> **Partly superseded 2026-08-08.** The run no longer stays in daylight — it cycles through
> eight moods including two genuinely dark ones (`biomes.md`). The *reasoning* below is
> still exactly right, and is now the open task it implies: the coin and obstacle colours
> were tuned against a bright backdrop and have **not** yet been re-judged. That is Phase 2,
> and `coin_color`/`obstacle_color` already exist in every palette, read by nothing.

The reference image is a night scene (sky ≈ `#40526F` → `#303F63`, sampled). Daylight was
chosen over matching it literally, for a gameplay reason as much as an aesthetic one: the
obstacle is `Color(1, 0.1, 0.1)` and the coin `Color(0.98, 0.82, 0.15)`, both tuned
against a bright backdrop. Going near-black would have put every gameplay-object contrast
ratio up for re-judgement. Under the pale sky they keep exactly the separation they
already had, and the near-white terrain gains contrast rather than losing it.
