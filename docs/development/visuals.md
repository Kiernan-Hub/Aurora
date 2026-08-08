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
   far = lighter, so `FarRidge` is the lightest scenery and `PineLine` the darkest. Terrain
   is lighter than all of them, which is what keeps the play surface unambiguous.
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

### Ice texture (2026-08-07)

The fill is no longer a flat/gradient `Color` — `apply_fill_texture()` (called from
`build_chunk_fill`, right after `close_fill_run`) assigns each fill polygon
`assets/textures/terrain/ice_terrain_one.png` as its `texture`, with
`texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED`. `Polygon2D` renders
`texture_sample * vertex_color` per pixel — **not** `color * vertex_color`; `color` is
only ever a fallback used when `vertex_colors` is empty, which it never is here (confirmed
by testing: setting `LIGHT_CHUNK_COLOR`/`DARK_CHUNK_COLOR` to a saturated blue produced no
visible change before the texture existed). So `FILL_GRADIENT_TOP_TINT`/`BOTTOM_TINT` are
now back to being multipliers — white at the surface (texture shows through untouched),
neutral grey at depth (dims without fighting the texture's own hue) — and
`LIGHT_CHUNK_COLOR`/`DARK_CHUNK_COLOR` stay at neutral white, inert unless some future
fill path ends up with no texture and no vertex_colors.

**Texture provenance**: `ice_terrain_one.png` is a 1200×520 seamless tile, built (see
scripts run during that session, not checked in) by cropping a 600×260 highlight/crack-free
patch of ice body out of a reference ice-skating illustration the project owner generated,
then mirroring it into a 2×2 grid (`ImageOps.mirror`/`flip`) so opposite edges match
exactly — cheap, robust seamless tiling for a mostly-diffuse source image, at the cost of a
faint mirror-symmetry "diamond" pattern if you look for it. The crack lines and bright
gloss hotspot visible in the original reference were deliberately cropped out: the request
that produced this was explicit that terrain should read as **one continuous surface**,
with no per-segment/per-tile seam lines. A second reference (`two.png` in the project
root, an 8-panel sheet of colour/mood variants) exists but has **not** been wired up to
anything yet.

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

| Element | Value | Where |
|---|---|---|
| Sky top / mid / horizon | `0.60,0.72,0.86` → `0.74,0.83,0.91` → `0.88,0.92,0.96` | `sky_backdrop.gd` |
| Far ridge | `0.68, 0.77, 0.86` | `main.tscn` export |
| Mid ridge | `0.57, 0.68, 0.80` | `main.tscn` export |
| Pine line | `0.45, 0.56, 0.69` | `main.tscn` export |
| Haze bands | pale sky tint, alpha 0.44–0.52 | `main.tscn` export |
| Snow | white, alpha 0.42 | `snow_drift.gd` |
| Terrain fill | `assets/textures/terrain/ice_terrain_one.png`, tiled | `terrain_generator.gd` |
| Terrain fill tint (surface → `FILL_GRADIENT_DEPTH` down) | `1.0,1.0,1.0` → `0.55,0.58,0.66` | `terrain_generator.gd` |
| Rim core | `0.97, 0.99, 1.0`, width 5 | `terrain_generator.gd` |
| Rim glow | `0.85, 0.95, 1.0`, alpha 0.35, width 22 | `terrain_generator.gd` |

**`LIGHT_CHUNK_COLOR`/`DARK_CHUNK_COLOR` do not currently affect the fill's rendered
colour at all** (2026-08-07 finding, still true after adding the texture): `Polygon2D`
renders `texture_sample * vertex_color` and ignores its `color` property outright whenever
`vertex_colors.size()` matches the polygon's vertex count, which it always does here
(`build_fill_vertex_colors()`) — confirmed by testing, back when the fill had no texture
and these two constants were set to a saturated blue that produced *zero* visible change.
Terrain colour is controlled by `assets/textures/terrain/ice_terrain_one.png` (see "Ice
texture" below) tinted by `FILL_GRADIENT_TOP_TINT`/`FILL_GRADIENT_BOTTOM_TINT` — not by the
chunk-parity constants. `LIGHT_CHUNK_COLOR`/`DARK_CHUNK_COLOR` are left at neutral white
and kept as two separate constants only so `apply_chunk_color()`'s parity branch is still
there to reach for if `color` ever becomes load-bearing again (e.g. a code path with an
empty `vertex_colors`) — give them different values and any such path lights up instantly.
Do not "fix" the terrain colour by editing these; it won't do anything.

### Ice surface rim (2026-08-07)

Terrain went from pale snow to a saturated ice blue, with a bright rim traced along the
surface to read as a glossy edge, in the style of a reference "ice slide" screenshot. Two
`Line2D`s per ground run (`add_surface_rim`, called from `build_chunk_fill`) — a wide,
low-alpha glow line under a thin, near-opaque core line — fake a bloom highlight without a
shader (this project has none, see above). Both are traced from the exact same
`surface_points`/`run_points` the fill polygon and the collision chords already use, so
the rim can never drift off the visible edge or misalign at a chunk boundary; it's built
once per chunk spawn, not per frame.

There is deliberately no per-segment or per-chunk seam in the rim or the fill — one
continuous line/gradient, not a marker at every new segment. If chunk parity colours are
ever pulled apart again for debugging (see above), the rim will still read as continuous
since it doesn't key on `chunk_color` at all.

### Why daylight

The reference image is a night scene (sky ≈ `#40526F` → `#303F63`, sampled). Daylight was
chosen over matching it literally, for a gameplay reason as much as an aesthetic one: the
obstacle is `Color(1, 0.1, 0.1)` and the coin `Color(0.98, 0.82, 0.15)`, both tuned
against a bright backdrop. Going near-black would have put every gameplay-object contrast
ratio up for re-judgement. Under the pale sky they keep exactly the separation they
already had, and the near-white terrain gains contrast rather than losing it.
