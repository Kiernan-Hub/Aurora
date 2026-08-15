# Handoff — the Glossy Frozen Lake set piece

Updated 2026-08-15. Delete this file once step 9 is done and it has stopped being true.

Plan file: `/Users/kjh/.claude/plans/replicated-twirling-twilight.md` — the approved 9-step plan.
**Read it before doing anything**; this file is the running state, that one is the design.

Older plan files, background only: `this-is-how-i-peppy-lark.md` (the 4-phase visual pass),
`wahts-the-nezt-step-melodic-shore.md` (biome persistence).

---

> # ⚠ THE WORKING TREE IS NOT CLEAN, ON PURPOSE — FIVE TEMP KNOBS
>
> | Knob | Playtest value | Shipping value |
> |---|---|---|
> | `BiomeDirector.BIOME_DISTANCE` | 7500 | **75000** |
> | `BiomeDirector.TRANSITION_DISTANCE` | 2000 | **24000** |
> | `ObstacleSpawner.debug_spawning_disabled` | true | **false** |
> | `FrozenLakeDirector.debug_lake_interval_override` | 20.0 | **0.0** |
> | `FrozenLakeDirector.debug_lake_min_run_time_override` | 18.0 | **0.0** |
>
> The two biome knobs are the owner's, from an earlier session, and are deliberately long-lived.
> The other three make a lake reachable ~20s into a run instead of 20 minutes.
>
> **The two lake knobs together cost the set piece's real pacing**: below ~120s the speed ramp has
> not finished, so the 7500px crossing runs long (39.4s measured, versus 10.0s at cap). Fine for
> judging colour, **wrong for judging pacing** — do one full-length run before signing anything off.
>
> **`shipping_values_check` fails on all five; `-- --allow-temp` downgrades it to a warning.**
> Revert the lake ones with:
> `git checkout scripts/systems/frozen_lake_director.gd scripts/systems/obstacle_spawner.gd`

---

## What this feature is

Every **20 minutes of cumulative playtime**, the player reaches a **7500px sheet of dead-flat
ice** and crosses it in **exactly 10 seconds**. Nothing spawns on it — no coins, no air lines, no
powerups, no obstacles, no trees. **Jumping is disabled.** The surface is glossy and reflects the
mountains, the pines and the player. The first one earns the project's first achievement,
**"Still Water"** (id `still_water`). An aurora set piece is planned as the second, so the shapes
built here should generalise.

### Reference images, both in `art_source/`, both untracked on purpose

**They moved out of the repo root on 2026-08-15** — the root is imported into the export,
`art_source/` is `.gdignore`d. Paths below are relative to it.

| File | What it is |
|---|---|
| `Glossy Frozen Lake.png` | 2109×746. **The look target for the lake surface.** Re-shot at higher resolution on 2026-08-15; the old 698×214 version is gone. Every constant in the lake shader is measured off this. |
| `glossy biome trail.png` | 1435×1096. **The look target for the skate trail** (steps 6b/6c). Night scene: particle spray behind the skates, an etched glowing track, low mist. Earlier drafts of this file called it `glassy biome ice effect.png`; same image, renamed. |

### Decisions settled with the owner — do not reopen

| Question | Decision |
|---|---|
| Recurrence | Every 20 min of cumulative playtime, forever. First grants the achievement. |
| Achievement backend | **In-game only.** No Google Play Games. |
| Interval alignment | Plain 20 minutes, never aligned to the biome cycle. |
| Run-length gate | **KEEP IT.** Re-confirmed 2026-08-14 after play — see "The timing question". |
| Achievement name | **"Still Water"** |
| Reflection technique | Screen-space mirror shader. Not duplicated parallax layers, not a SubViewport. |
| Lake ice tile | **NONE.** The lake discards the biome tile entirely and paints its own surface. |
| Lake colour | **Structure fixed, hue follows the biome at 45%.** See `LAKE_BIOME_HUE_WEIGHT`. |

---

## State: steps 1–5 COMMITTED, step 6 BUILT AND PLAYED BUT NOT COMMITTED

Branch `terrain/disable-mega-drop-camera-shake`.

| # | Commit | What |
|---|---|---|
| 1a | `e42f39d` | Atomic save write (temp file + rename) |
| 1 | `0a3c333` | SaveStore v3: `total_playtime_seconds`, `frozen_lake_count`, `achievements` |
| 2 | `e6e6e97` | The 7500px forced flat segment, `arm_lake()`, the terrain gate's lake pass |
| 3 | `98a9a05` | `Player.is_jump_suppressed` |
| 4 | `5a4d9a4` | Six spawner suppression guards |
| 5 | `0c5f9a9` | `FrozenLakeDirector` — the lake now actually happens |
| 6 | **UNCOMMITTED** | The whole visual pass below. Owner's last verdict: **"not bad at all"** |

### Uncommitted files, and which are mine

```
 M scenes/main.tscn                        LakeReflection node
 M scripts/main.gd                         lake camera framing
 M scripts/systems/frozen_lake_director.gd    get_lake_blend, min-run-time knob, temp knobs
 M scripts/player/player.gd                glide exemption from the input lock
 M scripts/terrain/terrain_generator.gd    lake ice colours, flatten, hue tint, blend
 M scripts/systems/obstacle_spawner.gd     TEMP KNOB ONLY
 M scripts/systems/biome_director.gd       TEMP KNOBS ONLY (owner's, pre-existing)
 M scripts/debug/shipping_values_check.gd  the new min-run-time knob
 M shaders/ice.gdshader                    `flatten` uniform + a pow() NaN fix
?? scripts/systems/lake_reflection.gd      NEW
?? shaders/frozen_lake_reflection.gdshader NEW
```

**NOT MINE, and untouched by this session — do not assume they are part of step 6:**
`scripts/systems/glide_coin_spawner.gd`, `powerup_manager.gd`, `powerup_spawner.gd`.
They appeared modified partway through 2026-08-14. Ask before committing them.

### Steps remaining

| # | What | State |
|---|---|---|
| 6b | **The skate spray** — `SkateSpray` | **BUILT, NOT COMMITTED.** Owner approved rev 2: *"that looks way better"* |
| 6c | **The etched glow track** — `SkateTrack` | **BUILT, NOT COMMITTED, awaiting playtest** |
| **7. NEXT** | "Still Water" achievement + on-screen notification | not started |
| 8 | Fold a lake case into `terrain_invariant_check` beyond step 2's | probably nothing to do |
| 9 | Docs — `CLAUDE.md`, `terrain.md`, `visuals.md`, `input.md` | partly done |

---

## How step 6 is built

### The pieces

| File | Owns |
|---|---|
| `FrozenLakeDirector` | WHEN. `Phase` (IDLE/ARMED/ACTIVE/DONE) and **`get_lake_blend()`** |
| `TerrainGenerator` | The geometry, and the ice colour under the quad |
| `LakeReflection` (`scripts/systems/lake_reflection.gd`) | One full-screen quad. Nothing but the look |
| `shaders/frozen_lake_reflection.gdshader` | The lake's entire surface |
| `main.gd` | The lake's camera framing |

**`get_lake_blend()` IS THE SPINE OF THE WHOLE VISUAL.** 0 off the lake, ramping to 1 over
`LAKE_LOOK_FADE_DISTANCE` (1500px, a bit over one screen), back to 0 at the far shore. The mirror's
opacity, the ice tint, the tile flatten, the deep-fill floor and the camera framing all ride that
one number, so none of them can arrive without the others.

**Why the ramp is not decoration**: the quad is full-screen and the ice tint is global, so at the
instant the player crosses the near seam the screen still holds a screen's worth of ordinary sloped
ground. At full strength that hillside would be painted lake-blue and reflected as if it were lying
flat. By the time the blend reaches 1 there is nothing but lake on screen.

### Draw order — a Node2D, NOT a CanvasLayer

`LakeReflection` is a sibling placed **after** `TerrainGenerator` in `main.tscn`. A `CanvasLayer` at
layer 0 draws above the root viewport canvas *regardless of tree position* (that is why the UI layer
works), so "between the world and the UI" would rest on a same-layer tie-break this project has
never relied on. A later sibling `CanvasItem` gets it from tree order alone.

**`visible = (phase == ACTIVE)` is the single most important line in that file.** A hidden
`CanvasItem` is never rendered, so the backbuffer copy `hint_screen_texture` forces never happens.
Zero cost for 19m50s of every 20 minutes.

### The shader, and where its numbers come from

Every constant is measured off `Glossy Frozen Lake.png`, not chosen:

| Feature | Measurement |
|---|---|
| Shore on screen | y=419 of 746 → `LAKE_HORIZON_FRACTION = 0.56` in `main.gd` |
| Ice at the shore | RGB(154,197,238) → `LAKE_ICE_SURFACE (0.60,0.77,0.93)` |
| Ice at the bottom | RGB(86,123,173) → `LAKE_ICE_DEPTH (0.34,0.48,0.68)` |
| Shore shelf | a BAND 3.6% of frame height, peak (178,213,244), luma along it 190→254→150 |
| Horizontal banding | **±1 to 2.6 luma of 255** → `band_strength 0.012` |
| Reflection reach | legible to ~25% below the line → `reflection_fade_depth 0.22` |

**The ice at the shore is brighter than the sky at the horizon (116,149,193).** The lake GLOWS. An
earlier pass had it darker than its own sky and it read as a hole in the world.

**Anything varying along x is keyed on WORLD x**, never `SCREEN_UV.x` — `world_left_x` and
`world_width` are pushed per frame. A screen-keyed pattern sits still while the world slides past at
750 px/s, which reads as dirt on the lens.

---

## Four wrong turns already paid for. Do not repeat them.

1. **The compression direction is inverted from intuition.** Screen distance below the line is
   MULTIPLIED before being mirrored back up, so **>1 compresses** toward the shore and **<1
   spreads**. Shipped at 0.55 once and the pines landed at the very bottom of the frame. It is now
   1.0 (a true 1:1 flip) and 1:1 IS THE INTENT — the reference's reflections are tree-shaped and
   roughly full size.
2. **The "vertical smear" was a misread of my own measurement.** Column sampling shows strong
   vertical coherence below the shore; that coherence *is* the 1:1 mirror of tall pines. Built as a
   smear it turned the player into a stripe running the full height of the lake.
3. **`reflection_blur` is a fraction of SCREEN HEIGHT.** 0.006 is ~8px per tap on a 1300px window,
   doubled by the tap spread — the owner's word was "blurry". Now 0.0022, scaled by depth so the
   reflection is nearly sharp where it meets the shore, and the taps are weighted 1-2-1 (a flat
   third-each average is a box blur, which turns edges into visible steps).
4. **Never `pow(x, 2.0)` where the base can go negative** — undefined in GLSL, a NaN on some
   drivers, and alpha-blending propagates it across the whole quad. Was present in the new glare
   and in `ice.gdshader`'s gloss; both now square by multiplication.

**A fifth, cheaper one:** `terrain_invariant_check`'s coin-density band is calibrated for the full
1758-slot sample. Running it with a shortened `--to=` produces a confident FAIL that means nothing.
Always `--seeds=8 --to=300000`.

---

## Things that will bite you

- **THE DIRECTOR HARD-SKIPS HEADLESS, SO NO HEADLESS PROBE CAN TEST THE LAKE.** The trigger reads
  cumulative playtime out of `save.dat`, so an ungated director would inject terrain into every gate
  depending on how much the developer had played — the `apply_upgrades()` failure (48/48 → 8) with a
  different field. `LakeReflection` and the camera framing are inert for the same reason.
- **HEADLESS GODOT LOADS SHADERS BUT DOES NOT COMPILE THEM.** A shader syntax error will not appear
  in any gate — it appears when the owner runs the game. Read new shader code twice.
- **A WINDOWED PROBE HOLDS NO FOCUS**, so `NOTIFICATION_APPLICATION_FOCUS_OUT` pauses the game on
  frame one. Re-assert `set_state(PLAYING)` each frame.
- **SETTING `speed_manager.elapsed_time` DOES NOT SET THE SPEED.** Pin `current_speed` as well.
- **GREP WHOLE LOGS FOR `SCRIPT ERROR|Parse Error|Failed to load`.** A narrow grep once discarded a
  probe's entire output and reported nothing at all.
- **`get_tree()` DOES NOT EXIST IN A `SceneTree` SCRIPT.** `self` is the tree; use `paused`.
- **A NEW `class_name` NEEDS `Godot --headless --editor --quit --path .`** before any gate compiles,
  and that can strip 40 lines from `project.godot`. `git diff project.godot` afterwards is not
  optional.
- **`lake_segment_index` MUST NOT BE CLEARED MID-RUN.** The segment is behind the player and must
  stay in the height field, or every cached chunk behind them disagrees with a fresh sample.
- **DO NOT REUSE `is_boosting` FOR THE INPUT LOCK.** It forces the grounded gravity-free velocity
  model (LOAD-BEARING FOR CHASMS).
- **DO NOT FORCE-END BOOST OR GLIDE AT LAKE ENTRY.** Both expire normally through
  `can_end_effect()`; force-ending adds a call site to the `active_effects`/`Player` desync class.
- **The deep fill's depth floor must track `LAKE_ICE_FLATTEN * lake_ice_blend`**, not the blend
  alone. The band's bottom row renders as the flattened tile times the depth tint; anything else
  reopens a step across the whole world exactly where the band ends.

### The purity relaxation, stated correctly

`get_terrain_height` stays pure in `(session_seed, world_x)` **plus one runtime input**,
`TerrainGenerator.lake_segment_index`, under a **write-once, write-ahead** rule: `arm_lake()` may
only set it to an index **strictly greater than `highest_cached_segment_index`** — a segment whose
spec, length, start_x and baseline have never been computed. Segment caches only grow forward and
are never trimmed, so that index is provably virgin. Arming can only **EXTEND** the height field,
never **REWRITE** it. `arm_lake()` is the only writer. **Never assign `lake_segment_index` directly.**

---

## The skate trail (`glossy biome trail.png` — renamed; the handoff called it
## `glassy biome ice effect.png`)

**Owner's decisions, 2026-08-15 — do not reopen:**

| Question | Decision |
|---|---|
| Glowing trail on normal ground too? | **NO. Lake only.** A plainer trail on ordinary terrain is wanted, but as a separate, later piece. |
| The etched glowing track | **Build it**, alongside the spray. Step 6c. |

**Why the ground trail is a different effect, not the same one dimmed.** Measured, not assumed:
the ride surface is ICE WITH A TRANSLUCENT SNOW SKIN — `build_snow_cap()` lays a separate
`Polygon2D` 3–13px deep (`SNOW_CAP_DEPTH_MIN/MAX`, waved by world_x) at 0.30–0.50 alpha, and all
nine palettes author one. A blade cutting into that goes THROUGH it, so the ground trail is the
snow cap scraped off to reveal `effective_ice_surface` underneath — a colour the game already
owns, and one that recolours per biome for free. The lake has NO cap (it discards the tile and
paints its own surface), so there is nothing there to remove and the mark has to be added light
instead. **The two effects are opposites, not one effect at two brightnesses.**

Also measured, and it is why a bright spray is wrong on ordinary ground: in a daylight reference
the spray reads 236 luma against 225 snow — an 11-luma difference, invisible. Every legible
speck in that image is where the spray crosses the DARK ridge band behind. On the night lake the
same spray is +150 luma against dark ice. **No further reference art is needed for either
effect**; two attempts at generating a daylight groove reference both produced a spray and no
groove at all, and the snow-cap finding made them unnecessary.

**The old `scripts/effects/flight_trail.gd` is the "geometric and bad" attempt the owner
remembers** — 14px straight `Line2D` sticks spawned unconnected with a random y jitter. Still
live, fired on boost from `player.gd:879`. It is not evidence against a trail; it is evidence
against that construction. Nothing in 6b/6c reuses it.

Measured off that image (1435×1096):

- **The skate line sits at y=760 → 69% of frame height.** (Note this is lower than the lake
  reference's 56%; it is a different shot, not a contradiction. Do not move
  `LAKE_HORIZON_FRACTION` on the strength of it without asking.)
- **The spray runs from y=670 to y=775, median 759** — so it is centred ON the skate line, throws
  up to ~90px (8% of frame height) ABOVE it, and drifts a little below.
- **It trails ~800px behind her**, about 55% of the frame width, thinning and dimming with distance.
- **Bright discrete particles**, luma > 150 against ice at ~(92,127,175) — points of light, not a
  cloud. 3325 such pixels in that band.
- There is also **an etched glowing track** on the ice directly behind the skates, and **low mist**
  along the far shore.

**The obvious build**, and the precedent is already in the tree: `SnowDrift` is a `GPUParticles2D`
under a `CanvasLayer` with `snow_drift.gd`, and `BirdFlock` is the precedent for "visible only
during a state". A `GPUParticles2D` emitting at the player's skates, `visible` gated on
`lake_director.phase == ACTIVE` exactly as `LakeReflection` is, and its own `apply_palette` if it
needs one. **No plugin, addon or import is required** — this is stock Godot.

**The one trap already known**: particles must be emitted in WORLD space
(`local_coords = false`), or they will ride along with the player and read as a costume rather than
as spray left behind.

### 6b as built — `scripts/systems/skate_spray.gd` + a `SkateSpray` node in `main.tscn`

A `GPUParticles2D` sibling placed **after `LakeReflection`**, and that ordering is load-bearing:
at `lake_amount` 1.0 the mirror quad is opaque and IS the lake surface, so spray drawn before it
is spray drawn under the ice. Not under a `CanvasLayer`, unlike `SnowDrift` — that one is weather
in screen space, this has to be in the world to get left behind.

`emitting = (phase == ACTIVE) and player.is_on_floor()` — the floor term matters because
`try_arm()` documents that entering a lake mid-glide cannot be prevented, and spray thrown from a
floating player announces that nobody checked. Alpha rides `get_lake_blend()` like everything else
cosmetic. Chips are killed and restarted if `Main.total_world_rebase_shift` moves: with
`local_coords` off nothing can move a live particle, so a 1024px shift under them can only be
answered by dropping them. Near-impossible on a flat lake, cheap to be right about.

**REVISION 1, after the owner played it: "it looks like snow being shot out."** The first pass
built its sprite by copying `snow_drift.gd`'s `build_flake_texture()` outright — a soft round
white puff, alpha blended. That IS a snowflake. Four changes, and **none of them is "more
glow"** (the owner also said "not too glowy"); the full argument is in the file's header:

1. **Shape.** Round soft blob → a four-point star with a hard white core and tapering flares,
   composed pixel by pixel in `build_glint_texture()`. Snow scatters light evenly; ice is a
   fracture face and throws a specular glint. **The single biggest one.**
2. **Blending.** Alpha → **additive** (`CanvasItemMaterial`, `BLEND_MODE_ADD`). Snow covers the
   surface; a glint is light arriving. This is where "glisten" actually comes from. No third
   `.gdshader` — a stock blend mode is not a reason to add one.
3. **Colour.** Neutral white → white core, **cyan flares**, coloured inside the sprite because a
   flat modulate cannot express "core is the light, flares are the material".
4. **Twinkle.** The lifetime ramp now carries a ripple on top of the reference's measured decay
   envelope, so chips wink rather than fading evenly.

Also flattened the arc (fountain → skitter): velocity max 250→190, gravity 620→520 for a ~35px
peak, wider/lower fan, plus damping so chips hang instead of tracing clean ballistic curves.
**That 35px is UNDER the reference's measured 64px and is an aesthetic call, recorded as one** —
the measurement describes a still frame of someone braking, not a skater at 750 px/s. Count
180→120: a dense field of pale dots is snow, ice is fewer separable glints.

**`CHIP_ADD_STRENGTH` (0.82) is the one knob to turn** if it lands too hot or too shy. Reaching
for the colours to fix a brightness problem is how this goes back to looking like dust.

**A trap caught before it shipped, worth keeping:** the flare taper must be SQUARED. Rendered
out, a linear taper made the horizontal flare a uniform full-width BAR — at 120 particles, 120
little dashes, which is exactly the geometric speed-line look that made `flight_trail.gd`
unusable. Verify a procedural sprite by rendering it, not by reading the formula.

**REVISION 2, after the owner played revision 1.** Verdict: glinting is *"a little better"*, but
*"too much coming off"*, *"less stuff floating away"*, and — the substantive one — **the chips
must not fall**: *"make it float up a little bit and stay at her level and drift behind her, not
fall down."*

**THE CHIPS NO LONGER ARC, AND THAT IS DIRECTION, NOT SIMULATION.** Both earlier passes threw a
ballistic curve, and both read as snow being *shot out*, because a parabola is the signature of a
thrown object — the eye reads the arc and infers mass. Hanging motes read as ice dust caught in a
light instead, and they also stay on screen long enough to be seen twinkling. So: a small upward
kick (velocity max 190→78), killed by drag that is now the dominant force (damping 34–95 →
62–130), against gravity near zero and very slightly **negative** (520 → **−6**, a faint lift, so
the field creeps ~2px up over a lifetime rather than hanging with the unnatural stillness of
exactly 0). Most chips end up within a few px of the skate line, the fastest reach ~29px, and
nothing comes back down inside its lifetime. The trail is produced entirely by the player leaving
them behind at 750 px/s.

Also: count 120→**70**, lifetime 1.05→**0.90** (trail ~770px → ~675px).

**The reference's measured 64px throw has now been rejected twice and is formally overridden.**
That measurement is a still frame of a skater braking hard; this is one crossing a lake at cap.
Recorded in the file as an aesthetic override, not relabelled as a measurement.

**The trail length is not a constant.** Chips are emitted with almost no horizontal velocity, so
the player runs out from under them and the trail length falls out of lifetime × speed. Nothing
reads the current speed; a slower player leaves a shorter trail, which is correct.

### 6c as built — `scripts/systems/skate_track.gd` + a `SkateTrack` node in `main.tscn`

A `Line2D` sibling placed **between `LakeReflection` and `SkateSpray`**: above the mirror because
that quad is the lake surface, below the spray because the etch is IN the ice and the chips are
above it. One point appended per physics frame at the blade contact, expired by AGE from the tail.

**A `Line2D` here and particles for the spray is a deliberate split, not an inconsistency.** The
spray is hundreds of independent motes with their own physics — what a particle system is for.
The etch is one continuous mark whose whole character is that it is CONNECTED and lies exactly
where the blades went, which particles cannot express without each one knowing about its
neighbours. **And it is not `flight_trail.gd`'s mistake**: that file spawned *unconnected* 14px
sticks with a random y jitter, so it read as tally marks rather than a path. One polyline sampled
every physics frame is 12.5px between points at cap — a curve, and on a dead-flat lake a straight
line with nothing to facet.

Measurements it is built from, unusually clean: fixed y, **6–9px FWHM** (~5 world px), and excess
luma decaying **near-linearly** — +145 / +95 / +57 / +15 / +3 at 0 / 800 / 500 / 200 / 860 px
behind. Hence a near-straight gradient ramp, not the ease-out that is the instinct: **a groove
healing over is not a light switching off.** 860px at cap → `TRACK_LIFETIME` 1.15s.

`TRACK_ADD_STRENGTH` (0.55) is the knob, and it is **deliberately below the spray's 0.82** — the
chips are small and sparse so they can afford brightness, while this is a continuous line across
most of the screen and equal strength would make it the loudest thing in the set piece.

**The rebase response is the OPPOSITE of the spray's, and that is the interesting bit.** Live
particles are owned by the GPU and nothing can move them, so `SkateSpray` can only drop its
chips; these points are an array this file owns, so the shift is applied to them and the mark
survives intact. Shifts are whole multiples of a power of two, so adding one is exact in binary.

`TRACK_RESUME_GAP` (40px) clears the line instead of bridging when contact is regained far away
— without it, touching down after a mid-lake glide draws one straight chord across the gap, a
perfectly geometric line through empty ice.

**REVISION 1, after the owner played it: "it's just a single white line."** They sent a
screenshot, and it found a failure no amount of reasoning would have.

**THE ADDITIVE ARGUMENT WAS RIGHT FOR THE REFERENCE AND WRONG FOR THIS LAKE.** Measured off that
screenshot: the night reference's ice is (92,127,175), luma 122, with room to receive light. This
build's lake is **(182,208,238), luma 205** — headroom R +73, G +47, **B +17**. At 0.55 strength
the core clipped to exactly (255,255,255) past the first ~400px. **A clipped signal carries no
information**: the gradient, the taper and the cyan were all being computed correctly and none
could be seen. The tail at low alpha still measured (221,241,254), correctly cyan — the shape was
right, only the level was wrong.

**And the level could not just be lowered.** With 17 luma of blue headroom, additive light on
pale blue ice saturates BLUE FIRST and can only drift toward white — the opposite of the cyan it
was for. *Additive cannot make a cyan glow on a bright blue surface at any strength.* So the
track now blends normally, and its glow is made of **saturation plus a modest luma lift**. This
is the project's standing "it looks grey means saturation, not brightness" finding on a second
axis — here it looked WHITE and the answer was the same one.

**The spray stays additive deliberately.** Its chips are tiny, sparse and short-lived, so
clipping a few dozen pixels reads as a hot specular spark — which is what a glint is. A
continuous line across the screen clipping the same way is just a bar.

Also added a **soft halo**: two `Line2D`s, and *this node is the halo with the core as its CHILD*,
because a child draws above its parent and the sharp line must sit on top. The child holds no
state — it is handed `points` once a frame. A single hard-edged stroke was much of why the first
pass read flat even before the clipping.

Verified numerically, nothing clips (max 254): tail (160,212,245) — **red −22**, same luma, more
saturated cyan; mid (181,233,252); head (241,253,254), +46 luma. **The tail works by REMOVING
red**, which additive structurally cannot do, and that is what reads as ice.

Gates after 6c: `terrain_invariant_check` 8/8 PASS, lake `flatness=0.000000`;
`shipping_values_check` the same five knobs, no sixth; editor pass left `project.godot`
unchanged. No physics or camera gate rerun — 6c touches neither.

Gates after 6b, all at baseline: `shipping_values_check` WARN on the same five knobs and no sixth;
`terrain_invariant_check` 8/8 PASS, `max_slope=20.13°`, coin density 0.3259–0.3464, lake
`flatness=0.000000` span 7500. No physics or camera gate was rerun — 6b touches neither. The
`--headless --editor --quit` pass for the new `class_name` left `project.godot` unchanged.

### What the owner offered to provide

They asked what plugins/skills/addons/pictures would help. Answer given: **nothing is needed for the
trail.** The one place art genuinely helps is the *background* — the reference has 4–5 hazy
overlapping mountain layers with varied pine clusters, ours are flat two-tone silhouettes from
`background_generator.gd`. Ridge/pine PNGs with alpha, **authored at ~2× world size**, would let the
procedural layers be swapped. **That is a separate piece of work from the lake and it improves the
whole game, not just this set piece.**

---

## The timing question — asked, answered, closed

Arithmetic: the lake is due once banked playtime crosses `(frozen_lake_count + 1) × interval`, but
`LAKE_MIN_RUN_TIME` (130s) blocks it until the run is past the speed ramp.

**Why the gate exists**: the lake is a fixed 7500px, so its duration is set by speed. `SpeedManager`
caps at MAX_SPEED (750) at t=120s, so past that the crossing is exactly 10.0s. Firing 23s into a run
means ~250 px/s and a **39.4s** crossing (measured).

**The accepted cost**: the lake lands on the first run that survives ~2 minutes after the clock is
up, not the instant it crosses. Alternatives (scale the lake length from live speed; lower the gate
to ~60s) were **declined** on 2026-08-14.

---

## How to verify

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot

# Before every commit. Reports the five temp knobs with --allow-temp.
$GODOT --headless --path . --script res://scripts/debug/shipping_values_check.gd -- --allow-temp

# Terrain, including check_frozen_lake()'s five assertions. NEVER shorten --to (see wrong turns).
$GODOT --headless --path . --script res://scripts/debug/terrain_invariant_check.gd -- --seeds=8 --to=300000

# Physics set. Required for anything touching get_terrain_height, the player or collision.
$GODOT --headless --path . --script res://scripts/debug/freeze_replay_runner.gd -- --seed=941462462 --frames=60000 --runs=1
$GODOT --headless --path . --script res://scripts/debug/floor_flicker_probe.gd -- --frames=20000
$GODOT --headless --path . --script res://scripts/debug/chasm_probe.gd -- --seed=683407368 --chasms=3 --phases=4
$GODOT --headless --path . --script res://scripts/debug/camera_shake_probe.gd -- --seed=941462462 --frames=7000 --warmup=120
```

**`camera_shake_probe` is now REQUIRED for lake work**, because step 6 touches the camera follow in
`main.gd`. It has stayed at flat mean jerk 0.0036–0.0052 across every change in this session.

**Runtimes, measured, so nobody kills one thinking it hung**: `floor_flicker_probe` is **6 seeds ×
20000 frames, ~9 minutes per seed, ~50 minutes total** — it is not the "fast" gate its docs imply.
`freeze_replay_runner` at 60k frames is ~3 minutes.

### Baselines

| Gate | Value | Status at last run |
|---|---|---|
| `terrain_invariant_check` | 8 seeds PASS, `max_slope=20.13°` | PASS |
| lake pass | `flatness=0.000000`, span exactly 7500.0 | PASS |
| coin density | 0.3259–0.3464 per slot (band 0.3163–0.3521) | PASS |
| `freeze_replay_runner` | 60k frames `no_freeze`, 0 recoveries | PASS |
| `chasm_probe` | 48/48 | PASS |
| `floor_flicker_probe` | flip 0.0000, **largest forced snap 1.8633px**, 0 recoveries | **seed 1 of 6 only** — killed at the owner's request to play, 2026-08-14. Seed 1 matched baseline exactly. |
| `camera_shake_probe` | flat mean jerk ~0.005; **no `frozen_lake` row** | PASS |
| lake crossing | exactly 10.00s over 7500.0px, measured windowed | measured at `0c5f9a9` |

**1.8633px is the pre-existing baseline** and the sharpest no-regression signal available here.
**The absence of a `frozen_lake` row in camera-shake's segment table proves the lake is inert when
nothing arms it.**

---

## Damage report — the developer's save file

**A step-1 verification probe deleted `user://save.dat` — the real one.** Whatever best score, wallet
and upgrades were in it before 2026-08-14 are gone. The owner has been told.

**Rule going forward: a probe must never touch `SaveStore.SAVE_PATH`.** Back it up and restore it,
or point the test at a temp path. The gates *already* write to it on player death — pre-existing.

---

## Reference — still true, from the earlier visual pass

- **"IT LOOKS GREY" USUALLY MEANS SATURATION, NOT BRIGHTNESS.** Compute saturation first.
- **DEEP ICE IS HARD-CAPPED AT `ice_depth × 0.38`** (`ICE_TILE_DEPTH_FLOOR`, matched to the tile
  builder's `OUTPUT_FLOOR`) — **except on the lake**, where `LAKE_ICE_FLATTEN` lifts it to 1.0.
- **`ice_contrast` DOES NOT AFFECT DEEP ICE** — faded out by `UV.y = 0.95`. Surface knob only. It
  is also meaningless on the lake, where the tile is gone; that is why `LAKE_ICE_CONTRAST` is 1.0.
- **THE HUE DRIFT ONLY EVER DARKENS**, and is forced to 0 across the lake.
- **THE SHEAR FINDING.** `build_ice_band()` pins the tile's `V=0` row to the surface, so long
  horizontal streaks fan downward on a hill and read as flowing hair. **On a flat lake nothing
  shears.**
- **The ice tile is a MULTIPLIER and repeats every 1200 world px.**
- **`COLOR` is in-out in a `canvas_item` shader** — on entry to `fragment()` it already holds
  `vertex_color * texture(TEXTURE, UV)`. `docs/research/ice_shader_color_semantics.md`.
- **No two adjacent biomes may both have a sun/moon disc.** Gate-enforced.
- **THE OPENING BIOME IS ALMOST IMPOSSIBLE TO PLAYTEST WITHOUT `debug_pin_intro_biome`.**

### Measurement traps — every one produced a confidently wrong answer

1. **Windowed probes read all-zero if the display is asleep or occluded**, and pause without focus.
2. **`mauve_haze`'s IceHue sits EXACTLY on the 24/255 floor**, so it fails intermittently.
3. **Never compare pixel numbers across two RUNS.** A/B inside one frozen frame (`ice_seam_probe`).
4. **`Engine.time_scale = 0` is not a safe freeze.** Use `SceneTree.paused`.
5. **Apply, wait a frame, *then* capture.**
6. **Hide the sprites before measuring.**
7. **Sample at constant DEPTH BELOW THE SURFACE, not constant y.**
8. **Any long-running harness needs obstacles AND chasms disabled.**
9. **Count items, never containers.**

---

## Deferred, deliberately — do not act on these unprompted

- **`BiomePalette.reflection_strength` now has NO consumer.** It is authored 0.2–0.7 across all nine
  palettes and was going to drive the mirror until the owner chose one fixed look. It is a deletion
  candidate, not a knob to reach for.
- **A dedicated lake ice tile (`six.png`)** — superseded. The lake discards the tile entirely now.
- **More upgrade tracks.** The combo multiplies every banked coin, so the 1130-coin curve empties in
  ~4 runs, not 8–15. **Cut `coin value` from the list** — it is a sink that raises income.
- **Two documented gates do not exist.** `check_upgrade_curve()` and `check_obstacle_clearance()` are
  named in `CLAUDE.md:142`, `upgrade_store.gd:57` and `obstacle_spawner.gd:56`. Neither is anywhere
  in `scripts/debug/`. The offered one-line fix is still awaiting a go.
- **Diamonds as a second currency** — SaveStore v3 is done, but nothing to spend it on.
- **Glide vertical drift on the parallax layers.** `look-thorugh-my-files-wobbly-church.md`.
- **Also found and unscheduled**: `SfxPlayer` has no `process_mode`, so death/menu SFX play into an
  already-paused tree; `ensure_segment_cache_for_world_x` loops forever on ±INF; six silent
  `push_error(); return` paths in `GameManager._ready()` can leave a live game under an
  undismissable `StartScreen`.

---

## Working agreement

**One numbered sub-step at a time. Commit it alone. Then stop and wait for an explicit "go".**
The owner play-tests between steps; silence is not consent. Do not batch.

**Verify with measurements, not reasoning.** When a probe fails, suspect the probe first.

**Flag the expensive option before building it.** The owner's standing instruction: if something has
a lot of potential to cause bugs, or is excessively hard when another option exists, say so and let
them choose.

**Do not self-verify visuals with screenshot captures.** The owner checks in-game faster. **But DO
measure the reference images with Python/PIL** — every good constant in this feature came from
sampling a PNG, and every bad one came from eyeballing it.
