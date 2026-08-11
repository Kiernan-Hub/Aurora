# Handoff — terrain & sky visual pass

Written 2026-08-10. Delete this file once Phase 2c/4 are done and it has stopped being true.

Plan file: `/Users/kjh/.claude/plans/this-is-how-i-peppy-lark.md` (has the full context,
the approved scope, and the working agreement).

---

## Read these first

| File | Why |
|---|---|
| `CLAUDE.md` | The map. Traps that cost real time. |
| `docs/development/biomes.md` | Everything that changes colour over a run. Longest and most important. |
| `docs/development/visuals.md` | Layer stack, overdraw budget, the sky composition constraint |
| `docs/development/ice_panels.md` | Making a new ice tile (this is Phase 2c's spec) |
| `docs/research/ice_shader_color_semantics.md` | Why the shader "darkened" the ice — closed |

---

## State

The ice-shader work is **committed** (`0e9ee5e`, plus the docs commit above this line's
sibling). All that should be left dirty in the tree is the debug knobs:

```
 M scripts/systems/biome_director.gd        <-- TEMP KNOB, DO NOT COMMIT
 M scripts/systems/obstacle_spawner.gd      <-- TEMP KNOB, DO NOT COMMIT
```

**The three TEMP knobs** are live so the cycle can be eyeballed quickly. `BIOME_DISTANCE`
7500 (real 75000), `TRANSITION_DISTANCE` 2000 (real 12000), obstacles disabled.
`shipping_values_check.gd --allow-temp` lists them. **Revert before shipping; never commit.**

**All gates pass**, and `shipping_values_check` was run with the knobs stashed — so it passed
*without* `--allow-temp`, which is the only way to prove no knob rode along into a commit.

---

## What has shipped (committed, `2ca5938`..`358a0b6`)

**Phase 1 — sky, complete.** A directional glow, a sun/moon disc, a starfield, and a
five-stop gradient with a horizontal wash. Plus one thing that was not in the plan:

> **The parallax layers had to be lowered before any of it was visible.** `FarPeaks` peaked
> *above* the top of the screen, so the sky was **2.4% of the frame** and both the glow and
> the disc were rendering perfectly behind opaque mountains. If you change ridge geometry,
> re-measure the sky. This is in `visuals.md`.

**Phase 2 — ice.** `2a` a warm/cool hue drift along the ride line, pure in `world_x`,
recovered from the band's UVs. `2b` a snow cap whose depth varies with `world_x` (thinned to
a 3–13px frost line after playtest — it read as a thick "snowboard" edge at 10–44px).

**Phase 3 — the one approved shader**, `shaders/ice.gdshader`. Noise-mask dissolve between
two tiles (which deleted one `Polygon2D` per ground run), contrast independent of hue, and a
gloss uniform parked at 0 for the lake biome. Every uniform's default is an exact identity.

---

## Next up

**Phase 2c — more ice tile families. Blocked on art only.** Everything else is ready:
`build_ice_texture.py --check panel.png` validates a source panel before building, and
`docs/development/ice_panels.md` has the requirements plus five ready-to-paste generation
prompts. The user generates panels; you build and gate them.

**Wire the shader's `contrast` to a palette field.** `biome_palette.gd` was deliberately not
touched, so `contrast`/`gloss_strength` sit at identity defaults and no biome uses them yet.
Contrast is the whole reason the shader exists — it is the one thing vertex colours cannot do.
This is a small, high-value step: add `ice_contrast` to `BiomePalette`, blend it on
`CHANNEL_ICE`, push it in `apply_ice_palette`, author per biome, measure.

**Phase 4 — the rare flat "glass lake" biome.** Design only; see the plan file. Roughly once
per 30 min as a milestone. The coupling is already clean: the biome schedule and the terrain
are both pure functions of `world_x`, so they can agree on a lake window with no messaging.
Risks: it must not overlap a chasm window, and it runs the full physics gate set.

---

## How to verify — and the traps in doing so

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path . --script res://scripts/debug/biome_schedule_check.gd     # palette data
$GODOT --headless --path . --script res://scripts/debug/terrain_invariant_check.gd  # geometry
$GODOT --path . --script res://scripts/debug/sky_layer_check.gd                     # NO --headless
$GODOT --path . --script res://scripts/debug/biome_contact_sheet.gd -- --out=/tmp/b # NO --headless
$GODOT --headless --path . --script res://scripts/debug/shipping_values_check.gd -- --allow-temp
```

**Grep whole logs for `SCRIPT ERROR|Parse Error|Failed to load`. Never `tail` them.** A parse
error in a palette consumer does *not* fail these probes — the scene instantiates with the
script unattached and the probe prints a normal-looking result. This shipped a broken commit
once.

**`sky_layer_check.gd` measures whether each optional layer actually puts pixels on screen**,
per biome, against a floor of 24/255. It exists because `biome_schedule_check` proved the glow
data was well-formed while the glow was contributing 11/255 — i.e. invisible. *Numbers being
valid and pixels being different are two separate claims.*

**Four measurement traps, each of which produced a confidently wrong answer here:**

1. **`Engine.time_scale = 0` is not a safe freeze.** It zeroes the physics delta, trips the
   stall watchdog, fires a world rebase, and — because the camera follow is delta-driven —
   leaves the world off screen. Every capture is then an empty sky and every layer measures as
   fully visible. Use `SceneTree.paused`.
2. **`biome_contact_sheet.gd` does not pin the terrain seed**, so two runs have different
   terrain. Never compare means across runs; compare within one frozen frame.
3. **Apply, wait a frame, *then* capture.** `root.get_texture()` returns the frame already
   rendered.
4. **A strided pixel sampler misses small features.** A 4px stride samples a 1px star with
   probability 1/16. `sky_layer_check` walks raw bytes at full density.

**Phase 2/4 touch terrain and run the physics gates.** `floor_flicker_probe` is slow (20 000
frames × several seeds) — it is the one gate not run against 2a/2b. Geometry is provably
untouched (`terrain_invariant_check` passes on 8 seeds) but that check is outstanding.

---

## Things that will bite you

- **`COLOR` is in-out in a `canvas_item` shader.** On entry to `fragment()` it already holds
  `vertex_color * texture(TEXTURE, UV)`. `COLOR = texture(TEXTURE, UV) * COLOR;` — the
  3D/`ALBEDO` convention — squares the texture. Full write-up in
  `docs/research/ice_shader_color_semantics.md`.
- **No two adjacent biomes may both have a sun/moon disc.** `celestial_is_moon` is a bool, so
  it snaps mid-transition and the texture swaps outright; that is only invisible because
  strength is 0 at one end. Gate-enforced. This is why `arctic_dawn` has no sun.
- **A disc-less biome must copy its disc-having neighbour's `celestial_position`**, or the
  disc slides across the sky while fading. Gate-enforced.
- **Put an evening glow ON the ridgeline, not in open sky.** The mountains clipping its lower
  half is what reads as light from behind them.
- **The snow cap and the hue drift compete for the same pixels.** Retune one, re-measure the
  other.
- **The Godot editor rewrites `project.godot`** and strips pinned physics settings.
  `git diff project.godot` before every commit.

---

## Working agreement

**One numbered sub-step at a time. Commit it alone. Then stop and wait for an explicit "go".**
The user play-tests between every step; silence is not consent. Do not batch.

**Verify with rendered frames and pixel measurements, not reasoning.** Three separate changes
in this pass looked correct and were invisible or wrong underneath — the glow at 11/255, the
disc hidden behind mountains, the shader squaring its texture. Each was found by measuring and
missed by inspection.
