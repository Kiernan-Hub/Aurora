# Aurora borealis — planned, phased, not started

**This is the feature the game is named after.** Build-order #12. It is a real major feature,
not visual polish — but it is also the *cheapest* major feature left, because it touches no
terrain, no collision and no gameplay state. That is the property to protect: every idea below
that would have made it touch terrain was rejected on an architectural reason, not on taste.

**Status as of 2026-09-07:** Phase 0 decided, **Phase 1 and Phase 2a written** — the director,
its bookkeeping, and three code-built curtains in `SkyBackdrop`. Phase 2b (a shader) and Phase 3
(the achievement) are not started.

**Phase 1 has NOT been run.** It was written in an environment with no Godot binary, so
`./scripts/check.sh` did not execute and nothing has been parsed by the engine. Two things are
owed before it can be trusted: a **project import** (`class_name AuroraDirector` is new, and
`shipping_values_check` now instantiates it — CLAUDE.md keeps import as the manual step for
exactly this), and then `./scripts/check.sh`.

> **Correction to the record, 2026-09-07.** `HANDOFF.md` and
> `docs/research/background_differentiation.md` both described this feature as "fully planned".
> It was not — the previous draft of this file ended on three unresolved questions and a
> sequencing note. Those files have been corrected. Do not re-introduce the claim until Phase 0
> below is signed off.

## What it is

A rare, spectacle-only event: **sky only**, purely cosmetic, structurally the sibling of the
frozen lake (`FrozenLakeDirector`, `terrain.md` §10) but rarer and with no gameplay lockout.
The point is "look up", not a new mechanic.

- **Trigger:** cumulative playtime, the same clock the lake uses
  (`SaveStore.total_playtime_seconds` + `GameManager.get_unbanked_seconds()`), at roughly
  **every 60 minutes** vs. the lake's 20.
- **Scope:** ribbons of colour in `SkyBackdrop`, added to the existing stack
  (`SkyGradient`, `SkyStars`, `SkyGlow`, `SkyCelestial`). No terrain, no ice tint, no
  collision, no `GameManager.State` — the same boundary `biomes.md` already holds.
- **Not a `BiomeDirector` cycle entry.** The eight palettes rotate on world-px distance and are
  authored as a day passing; this is playtime-gated and rare. It sits *beside* that system the
  way the lake sits beside `TerrainGenerator`.
- **One blend ramp.** `AuroraDirector.get_aurora_blend()` is the single value every cosmetic
  piece reads — ribbon opacity, ribbon drift, any star dimming. Exactly the discipline
  `FrozenLakeDirector.get_lake_blend()` holds, and for the same reason: two systems fading the
  same event independently is two chances to disagree.
- **First sighting is an achievement.** `AchievementManager` listens to signals systems already
  emit; this is one table row and one `.connect()` in that file, both after the director exists.

## THE ARCHITECTURAL RULE THIS FEATURE EXISTS TO NOT BREAK

**The aurora must never arm terrain.** `CLAUDE.md` states that `get_terrain_height` has exactly
one permitted runtime input, `lake_segment_index`, and that **`arm_lake()` is its only writer**
— write-once, write-ahead, above `highest_cached_segment_index`, so arming can only *extend*
the height field. A second set piece that shaped ground would put a second writer on that
invariant, and every chunk visual, collision sample, player tilt and debug HUD reads it
independently.

That single fact settles the biggest open question below, and it is why this feature is cheap:
sky-only means `terrain_generator.gd` is not in the diff at all.

## Phase 0 — four decisions, DECIDED BY THE OWNER 2026-09-07

All four answered. The reasoning is kept because it is what the code's comments point back at.

| # | Question | Decision |
|---|---|---|
| 1 | Forced flat segment? | **No** — sky only, terrain untouched |
| 2 | Ribbon rendering | **Code-built textures first**, shader expected later as Phase 2b — see the note under 2 |
| 3 | Colour identity | **Fixed** green/violet, never per-biome |
| 4 | Night only? | **Yes** — blended `star_density` >= 0.8 |

### 1. Does it force its own flat terrain segment, like the lake's 7500px? — **DECIDED: NO**

Not a taste call. Three reasons, in order of weight:

1. **The `arm_lake()` sole-writer rule above.** Decisive on its own.
2. **A distance-based set piece needs `LAKE_MIN_RUN_TIME`, a time-based one does not.** The
   lake's 7500px is 10.0s at `MAX_SPEED` and ~40s during the ramp, which is the entire reason
   `LAKE_MIN_RUN_TIME = 130.0` exists — and its documented cost is that the lake really arrives
   on "the first good run after 20 minutes", not every 20 minutes. A sky event has no distance,
   so it can be a plain seconds-long window and inherits none of that.
3. The point is a sky event during ordinary play, not a second set piece.

**What this gives up, honestly:** the player may be mid-chasm or mid-obstacle-cluster when it
starts, and will not look up. Mitigation costs nothing: `try_arm()` retries every frame the way
the lake's does, so it can decline any frame the player is airborne or a chasm is within the
lead-in — the threshold stays crossed and it arms on the first calm frame instead.

### 2. Shader, or authored sprite layers? — **DECIDED: code-built first, shader NOT ruled out**

The project's shader budget is two, both owned by ice, and `visuals.md` requires a third to
justify itself. Neither option in the original draft is the cheapest thing available.

`SkyBackdrop` already builds three of its four layers **in code** — `build_glow_texture()`,
`build_star_texture()`, `build_celestial_texture()` — as `Gradient`/`Image` bakes with the
colour carried on `modulate`. A ribbon is a soft vertical band with a falloff, which is the
same class of object as the glow.

**Recommended first attempt:** 2–3 ribbon `TextureRect`s, each an LA8 image baked once in
`_ready()` (same idiom and same memory shape as the 1024×576 starfield), coloured by `modulate`
from a fixed aurora palette, and animated by moving each rect's **anchors** at a different slow
rate — which is how `position_glow()` already moves the bloom, needs no `_process` maths beyond
one lerp, and is resolution-independent for free.

- **Cost if it works:** no new shader, no new imported asset, no `.import` file, no art
  pipeline, ~1 MB of LA8. Roughly 120 lines in `sky_backdrop.gd` plus the director.
- **Cost if it does not:** the owner looks at it and says it reads flat, and *then* shader #3
  has a real justification and a reference to beat. That is the cheap order to fail in.
- **Flagging this per the working agreement:** a `.gdshader` is the option with the most bug
  surface (a third shader to keep in sync with `ice_contrast`, per-biome uniforms, a Mobile
  renderer to verify on) and there is a materially cheaper option to try first. Do not start
  with the shader.

**THE OWNER'S ANSWER, AND IT CHANGES HOW PHASE 2 SHOULD BE BUILT (2026-09-07):** code-built
first, but **the shader is expected to be wanted later and is explicitly not being ruled out on
difficulty** — this is the part of the game the owner cares most about and is willing to spend
time and iterations on. So treat the code-built version as **Phase 2a, a deliberate first draft
whose job is to be judged**, not as the intended end state, and build it so a shader can replace
the ribbon rendering without touching anything else:

- `get_aurora_blend()` stays the only timing input. A shader version reads the same float as a
  uniform; it must never grow its own clock off `TIME`, which keeps running while the tree is
  paused — that is exactly why `frozen_lake_reflection.gdshader` takes a `wobble_time` uniform
  instead, and the same rule applies here.
- `apply_aurora(blend)` on `SkyBackdrop` stays the only seam. Phase 2b swaps what is behind it.
- Keep the ribbon *layout* (where bands sit, how many, how they drift) as data on the node, not
  baked into the texture, so the shader version can inherit the composition the owner approved
  rather than restarting the art direction.

The order is "let the cheap version establish the composition, then spend the shader on making
it move properly" — not "avoid the shader".

### 3. Fixed aurora colours, or recoloured by the active biome? — **DECIDED: FIXED**

Settled by precedent already in the codebase. `lake_reflection.gd`'s header records the owner's
2026-08-14 call for the lake: the same set piece every time, "recognisable on sight rather than
recoloured by whichever biome it happens to interrupt" — and `BiomePalette.reflection_strength`
was **deleted** rather than wired up, because a palette lookup in a set piece is the thing that
makes it stop being a set piece.

Same argument, same answer: a fixed green/violet identity. The biome still reaches it, and only
this way — through the sky gradient the ribbons are drawn *over*.

### 4. NEW, AND THE IMPORTANT ONE: does it only happen at night? — **DECIDED: YES**

The earlier draft missed this entirely, and it is the question with a wrong answer available.
The trigger is cumulative playtime; the sky colour is a function of world distance. **They are
independent**, so as written the first aurora can perfectly well fire over `pale_morning`. An
aurora in a bright morning sky does not read as a rare spectacle; it reads as a rendering bug.

**Recommend: yes, night only, gated on data that already exists.** `BiomeDirector` already
blends `star_density` every frame, and the authored values make it an exact darkness signal
with nothing new to keep in sync:

| palette | `star_density` |
|---|---|
| `starlit_night` | 1.00 |
| `twilight_blue` | 0.85 |
| `violet_dusk` | 0.30 |
| `arctic_dawn` | 0.28 |
| the other five | 0.00 |

A threshold of **≥ 0.8 on the blended value** is exactly the two night biomes — 2/8 of the arc,
matching the night-length decision already shipped — and reading the *blended* value rather
than the palette identity excludes the crossfade shoulders for free, so the aurora cannot begin
while the sky is still going dark. One accessor on `BiomeDirector`
(`get_night_amount() -> float: return blended.star_density`), one comparison in the director.

**What it costs:** the aurora is no longer strictly "every 60 minutes" — it is "the first night
biome after 60 minutes of playtime". That is the same shape of cost `LAKE_MIN_RUN_TIME` already
buys and the owner already accepted, and the arc is ~13.7 minutes, so night comes around within
one cycle of the threshold being crossed. **It also makes the event rarer and more special,
which is the stated goal**, and it means the starfield is up underneath the ribbons — which is
the composition the whole thing wants anyway.

**The one thing to check before committing to this:** `BiomeDirector` returns early under
`--headless` and applies nothing, so `blended.star_density` reads whatever `BiomePalette.new()`
defaults to in a gate. The director hard-skips headless too (Phase 1), so this can never be
reached there — but the guard has to be the director's, not this comparison's.

## Phase 1 — the director, no visuals — **WRITTEN 2026-09-07, NOT YET RUN**

**What landed**, and it matches the spec below except where noted:

| File | Change |
|---|---|
| `scripts/systems/aurora_director.gd` | New. `class_name AuroraDirector`, ~250 lines, modelled on `frozen_lake_director.gd` |
| `scripts/systems/save_store.gd` | `aurora_count`, read/written/reset. **No version bump** — reasoning is on the field |
| `scripts/systems/biome_director.gd` | `get_night_amount()` — returns `blended.star_density`, its only new public surface |
| `scenes/main.tscn` | `AuroraDirector` node under `Main`, between `FrozenLakeDirector` and `AchievementManager` |
| `scripts/debug/shipping_values_check.gd` | Both new debug knobs, same commit as the knobs themselves |

**Two deviations from the spec below, both deliberate and both simplifications:**

1. **No chasm-proximity check in the arm condition.** The spec proposed declining a frame if a
   chasm was close. On reflection that is scope the feature does not need: the lake's floor and
   jump checks exist because it commits geometry *and* locks input, so a bad entry is a real
   state problem. Nothing here locks anything — an aurora starting over a void just means the
   player looks up a second later, and the 8-second fade-in is far longer than a chasm takes to
   clear. A proximity check would mean new `TerrainGenerator` API for a problem that does not
   exist. **The airborne check went too, for the same reason.**
2. **`debug_aurora_ignore_night` replaced the proposed second knob.** The interval override
   alone cannot reach an aurora during the ~10 of every 13.7 minutes that are not night, so this
   is the one that actually shortens an iteration loop. Its own comment says what it costs (you
   are then judging the ribbons against a sky they were not authored for).

**`push_blend()` is the seam Phase 2 arrives through.** It calls `apply_aurora(blend)` on
`SkyBackdrop` if that method exists, and does nothing if it does not — so Phase 1 landed with
**no edit to `sky_backdrop.gd` at all**, and a Phase 1 regression cannot be hiding in the sky
stack. `has_method` rather than a typed call because `sky_backdrop.gd` carries no `class_name`,
the same reason `BiomeDirector` routes its two unchecked consumers through
`resolve_palette_consumer()`.

**What is owed before trusting any of it:** a project import (new `class_name`), then
`./scripts/check.sh`. The physics tier is **not** owed — nothing here touches physics, collision
or spawning. The visual tier is not owed either, because Phase 1 draws nothing.

### The spec it was built to

One new file, `scripts/systems/AuroraDirector` (`scripts/systems/aurora_director.gd`), and one
new node under `Main` in `main.tscn`, placed beside `FrozenLakeDirector`. Model it on
`frozen_lake_director.gd` closely enough that the two read as a pair.

- `enum Phase { IDLE, ACTIVE, DONE }` — no `ARMED`, because there is no geometry to commit
  ahead of the player. One aurora per run maximum, `DONE` terminal, for the lake's exact
  reason: the unspent threshold stays owed and the next run is immediately due.
- `const AURORA_INTERVAL_SECONDS: float = 3600.0`.
- `const AURORA_DURATION_SECONDS: float = 45.0` and
  `const AURORA_FADE_SECONDS: float = 8.0` — proposed, not measured. The lake is 10s and is
  something you cross; this is something you watch, so it should outlast a glance without
  outstaying the biome it needs (a night biome holds ~100s at cap, so 45 + two 8s ramps fits
  inside one comfortably). **Owner should judge this in play, not from the number.**
- `get_aurora_blend() -> float` — 0 outside `ACTIVE`, a symmetric ramp in and out over
  `AURORA_FADE_SECONDS`, identical in spirit to `get_lake_blend()`'s two clamped terms.
- `get_total_playtime_seconds()` — **must** go through `GameManager.get_unbanked_seconds()`,
  never `Main.elapsed_time`. That function exists because reading `elapsed_time` directly
  double-counted banked time and armed lakes early; the 2026-08-24 review says in as many words
  that the aurora should reuse it.
- `is_aurora_due()` — `(aurora_count + 1) * interval`, the lake's counter-as-threshold-index
  trick, which cannot drift and cannot be lost.
- `try_arm()` — declines the frame if the player is airborne, if a chasm is close, or if
  `get_night_amount() < NIGHT_THRESHOLD`. Retries next frame.
- Signals `aurora_started` and `aurora_finished(total_auroras: int)`.
- **Headless:** `is_headless = DisplayServer.get_name() == "headless"` computed locally, never
  `services.is_headless`; `set_physics_process(false)` **before** the return. This is not
  optional and not an optimisation — the trigger reads the developer's own `save.dat`, which is
  the `apply_upgrades()` failure (48/48 chasms → 8) with a different field.
- **Two debug knobs**, plain `var`, never `@export` — `debug_aurora_interval_override` and
  `debug_aurora_ignore_night`. Both must be added to `shipping_values_check.gd` in the **same
  commit**; that gate is the only thing in the project watching a knob left flipped.

`SaveStore` gains `aurora_count: int`, read under the existing `if version >= 3:` block with a
default of 0. **No version bump.** A v3 file written before this build has no key, `.get(..., 0)`
returns the correct new-player state, and the file's own idiom is "reading the fields that exist
IS the migration" — only a new top-level *concept* earns a bump, and cumulative-playtime-gated
set-piece counts is not a new concept. `reset_progress()` clears it alongside `frozen_lake_count`.

**Verify Phase 1 with `./scripts/check.sh` alone.** Nothing here touches physics, collision or
spawning, so the physics tier is not owed.

## Phase 2a — the ribbons — **WRITTEN 2026-09-07, NOT YET RUN IN THE ENGINE**

Three curtains as `TextureRect`s in `SkyBackdrop`, built between `SkyStars` and `SkyGlow`,
driven only by `apply_aurora(blend, elapsed)`.

**The shape was validated before it was written**, by porting the bake to Python and rendering
it against the two night palettes' real gradients. That is not a substitute for the engine — it
cannot see draw order, the additive material, or `expand` on a real device — but it caught two
defects that would otherwise have needed a play session each:

1. **The rays were invisible.** The first draft averaged three sines drawn from one 9–34 range.
   An average of similar frequencies converges on a constant: the term sat near 0.81 across the
   whole width, so there was no striation at all — a smooth ribbon, which reads as fog. A
   *product* of them fails the other way, collapsing the mean toward the floor and going muddy.
   What works is **four octaves with amplitude falling as frequency rises** (`AURORA_RAY_BANDS`,
   `AURORA_RAY_AMPLITUDES`): broad bright and dim regions with fine rays laid over them, mean
   unchanged.
2. **It blew out to white.** Measured against a *guessed* dark sky the band weights looked fine.
   Against the palettes as authored — `twilight_blue`'s `sky_top` is `(0.26, 0.28, 0.50)`, far
   brighter than assumed — **4.6% of the screen clipped to flat white**. The shipped weights
   `[0.70, 0.28, 0.24]` measure peak 1.03 / 0.02% clipped, and that remainder is the hem's own
   core, where a white-hot centre is correct.

**A third finding, and it is a ceiling rather than a bug:** under additive blending a band's
channel values land on the sky's directly, and **no additive layer can reduce the sky's blue**.
Over these two palettes (blue 0.42–0.54 in the upper sky) a fully saturated green is unreachable
by construction. Pulling blue almost out of the green's own colour moved the hem from G/B 1.26 to
1.53, which is as far as it goes; making it brighter does not help, it clips. If a greener aurora
is ever wanted, the lever is the *palette's* blue, not this file — and that is a biome change.

**Why additive at all, and why it is not shader #3.** An aurora emits. Alpha-blended it can only
darken toward its own colour, so a green curtain over the sky comes out as flat paint. A
`CanvasItemMaterial` with `BLEND_MODE_ADD` is a **built-in**, not a `.gdshader` — the two-shader
budget is untouched. The trap it introduces is exactly why the night gate exists: additive over
a bright sky blows out, so `debug_aurora_ignore_night` shows a composition the game never ships.

**One cost fix worth knowing about.** The bake is ~295,000 pixels across three bands, against the
starfield's 300. Two changes keep that off the gates and off scene load: the whole construction is
**skipped under `--headless`** (gate output is byte-identical either way, since the bands are built
`visible = false` and the director hard-skips headless anyway), and the image is filled as a
**`PackedByteArray` handed to `create_from_data()`** rather than through per-pixel `set_pixel()`.

**What is owed:** the project import and `check.sh` from Phase 1, and then — because this is a sky
change the owner has not seen — **`sky_layer_check.gd`, which must run WITHOUT `--headless`.**

### The spec it was built to

#### Phase 2 — the ribbons

`sky_backdrop.gd` gains a `SkyAurora` child and an `apply_aurora(blend: float)` called by the
director each frame it is active.

- **Draw order: after `SkyStars`, before `SkyGlow`.** Tree order is draw order and there is no
  `z_index` anywhere. Above the stars so the ribbons occlude them; below the glow and the disc
  so a horizon bloom and the moon still sit on top — the moon reading as *behind* a ribbon is
  the physically correct choice and the wrong-looking one, since `SkyCelestial` is the only
  hard-edged body in the stack and a soft band crossing it reads as a smear.
- **`visible = blend > 0.0`, never alpha 0.** `apply_glow()` and
  `terrain_generator.paint_snow_cap()` both do this and both say why: a transparent full-screen
  `TextureRect` still rasterises every pixel it covers, and stacked full-screen alpha is the
  fill-rate cost that actually matters on the Mobile renderer. At blend 0 this feature must be
  byte-identical to not existing — which is also what keeps it incapable of moving a gate result.
- `mouse_filter = MOUSE_FILTER_IGNORE` on every rect. `Control` defaults to `STOP` and these
  cover the whole screen; left at the default they are full-screen input eaters under the pause
  button. `sky_backdrop.gd` calls this out as mandatory rather than tidiness.
- `PRESET_FULL_RECT` anchors, moved by anchor rather than pixels, per `position_glow()`.
- The ribbon texture is baked once in `_ready()` — **not** per frame, and **not** per blend
  value. Only `modulate` and the anchors move.

**`sky_layer_check.gd` is owed after this, and it must run WITHOUT `--headless`.** It is the
gate that caught a glow contributing 11/255 and being invisible, and a new soft full-screen
alpha layer in this exact stack is precisely its failure mode. Its current status is "settled
2026-09-02 by the owner in-game" — this is the change that puts it back in play, because it is
a sky change the owner has not seen. `ice_look_capture.gd` and `biome_contact_sheet.gd` are
worth a look but assert nothing.

## Phase 3 — the achievement

Two edits, both in `achievement_manager.gd`: a row in `ACHIEVEMENTS` and one `.connect()` in
`connect_triggers()` onto `aurora_finished`, gated on the flag and never on `total == 1` — the
same reasoning `_on_lake_finished` spells out.

**Read that file's closing trap before writing this.** It has no headless guard, and that is
only safe because its one trigger comes from a director that hard-skips headless. Phase 1's
director does too, so this stays safe — but the reason it stays safe is Phase 1's guard, not
anything in this phase.

Achievement ids are save data: adding is free, renaming un-earns it for everyone.

## Phase 4 — the record

- `CLAUDE.md` row 12 moves off "PLANNED, not started".
- `HANDOFF.md`'s "what is actually next" list.
- `visuals.md` gains the sky stack's new member.
- This file keeps the phases and gains what was measured; anything ruled out on evidence goes
  to `docs/research/`.

## The sequencing prerequisite is satisfied — evidence, 2026-09-07

The previous draft held this feature behind "ice canyon walls / shard spires, extra sky
elements should land first", so the ribbons would sit against a settled composition. **That
prerequisite is stale**, and the record says so from three directions:

- The background **shipped** on 2026-08-24 as the baked raster panorama (`ice_pano.png` on
  `IceStrip`), and the iceberg-sprite line was abandoned — `build_iceberg_sprites.py` was
  deleted the same day.
- The raster route was **tried three times and failed three times**
  (`background_differentiation.md`), and the only live remaining option is procedural ridge
  reshaping — which changes the **silhouette**, not the sky.
- `background_differentiation.md` states the constraint that matters here: any background
  replacement must be opaque above the horizon and **must not bake a sky**, because "the
  planned aurora is sky-only and needs `SkyBackdrop` free." `SkyBackdrop` is layer `-200`,
  `ParallaxBackground` is `-100`. The ribbons are behind every silhouette by construction, so
  what shape those silhouettes are cannot affect them.

**Conclusion: the ridge-shape work and the aurora are independent and can be done in either
order.** Worth one line of owner confirmation, not a blocker.

## Things that will break silently if ignored

- **Never `Services.x`** — `GameServices.resolve(self)`, null-guarded. The global identifier
  does not exist under `--headless --script` even though the autoload node does.
- **`set_physics_process(false)` before the headless return**, not after (`visuals.md` trap 6).
- **A parse error in a file `main.tscn` instantiates hangs the gates rather than failing them**
  (`visuals.md` trap 3). Every headless gate builds this scene.
- **Debug knobs are plain `var`, never `@export`** — an exported bool serialises into
  `main.tscn` and ships silently. That is the `world_rebase_enabled` regression exactly.
- **`git status` after ANY engine run.** A settings save rewrites `project.godot` *and* scene
  files, dropping the pinned values and every comment. `shipping_values_check` text-scans
  `project.godot`; **scene files still have no such cover**, and this feature adds a node to one.
