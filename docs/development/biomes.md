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

## Traps

- **A parse error in `biome_director.gd` hangs the six gates rather than failing them**
  (`visuals.md` trap 3). Run one gate as soon as the file first parses, not at the end.
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
