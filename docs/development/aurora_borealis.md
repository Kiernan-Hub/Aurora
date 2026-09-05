# Aurora borealis — the plan

**This is the feature the game is named after.** Planned 2026-09-05 against the decisions in
"Decisions taken" below; nothing is built yet. Read this whole file before writing a line of it.

The frozen lake is the model in every structural sense (`terrain.md` §10, `FrozenLakeDirector`),
and this file only explains where the aurora *differs* from it. Where it doesn't say otherwise,
copy the lake.

## What it is

A rare spectacle on the cumulative-playtime clock — **every 30 minutes**, against the lake's 20 —
that turns roughly a minute of ordinary play into something to look up at. Three things happen at
once and all of them ride one ramp:

1. **The sky fills with aurora.** Animated curtains across the whole sky band, on a new shader.
2. **The world catches the light.** Mountains and snowfall are washed in aurora colour. Ice,
   coins, obstacles and the player are deliberately *not* — see "The wash" below.
3. **The run goes calm.** No chasms and no obstacles for the duration, and the camera pulls back.
   So the player can look up for a minute without dying, which is the entire point.

It is still `GameManager.State.PLAYING` throughout, exactly as a lake is. Nothing here goes near
`get_tree().paused` or a screen's visibility; `set_state()` remains the only thing allowed to.

### Why it can't just be colours in the sky

The parallax ridges are **opaque** and their tops sit at y 0.21–0.45 (`visuals.md`, "There has to
BE a sky"). A strictly sky-only aurora is therefore confined to the top ~40% of the frame with a
hard mountain edge under it, and the other 60% of the screen carries on exactly as before. That
reads as a nice sky, not as an event. The wash and the calm are what make it reach the whole
frame; they are not decoration bolted onto the sky pass, they are the feature.

## Decisions taken (2026-09-05, owner)

These close the open questions the previous version of this file left hanging. Do not re-litigate
them without the owner.

| Question | Decision |
|---|---|
| Interval | **30 min** of cumulative playtime, not the 60 originally sketched |
| Duration | **~60 s**: 10 s in, 40 s hold, 10 s out |
| Reach | **Sky + background wash.** Not ice, not gameplay objects |
| Which sky | **Only fires in the dark biomes.** Does not force the sky dark itself |
| Gameplay | **Not purely cosmetic.** No chasms, no obstacles, camera pulls back |
| Forced flat segment | **No.** Terrain keeps rolling; only the hazards are removed |
| Ribbon rendering | **Procedural shader.** The project's third, and it is justified below |
| Colour identity | **Fixed aurora palette**, not recoloured per biome — same call as the lake |

### Why it only fires in the dark biomes

The eight palettes rotate by a random amount each launch (`BiomeDirector.session_cycle_rotation`),
so a playtime-gated event lands on an arbitrary sky. A green curtain over `pale_morning`'s
near-white sky moves almost no pixels — which is not a guess, it is exactly the failure
`sky_layer_check.gd` was built after (a glow shipped contributing 11/255 and reading as nothing).

So the aurora waits. It becomes *due* on the clock and then arms on the first frame that the
active biome is one of the three dark ones. That is the same shape as the lake being due and then
retrying `try_arm()` until it gets a clean frame, and it costs nothing but patience.

**The alternative was considered and rejected for now:** having the aurora pull the sky toward a
fixed night on its own ramp, so it could fire anywhere. That works, and the clean way to do it is
to hand `BiomeDirector.push_palette()` an override palette plus a weight so there is still exactly
one writer of every sky property — never a second node writing `sky_stars.modulate` behind
`apply_stars()`'s back, which is a two-writer bug waiting for a transition to expose it. It is a
real option if "waits for a dark biome" turns out to feel too rare in play. It is not v1.

## Structure

Five new things, and one of them is a shader. Everything else is an edit measured in lines.

```
Main
├── SkyBackdrop         CanvasLayer -200   [UNTOUCHED]
├── AuroraSky           CanvasLayer -190   [NEW]  ← above the whole sky stack, below the ridges
│   └── Curtain         ColorRect + ShaderMaterial, anchored to the sky band
├── ParallaxBackground              -100
├── BirdFlock                        -60
├── SnowDrift                        -50
├── AuroraWash          CanvasLayer  -45   [NEW]  ← over ridges and snow, UNDER everything at 0
│   └── Wash            ColorRect
├── Player / TerrainGenerator / pickups / obstacles   (layer 0)
├── AuroraDirector      Node               [NEW]  ← sibling of FrozenLakeDirector
└── ...
```

**The two layer numbers are the whole safety argument for the wash.** At −45 it sits in front of
the mountains and the snowfall and behind every canvas item at layer 0 — so the ice, the coins,
the obstacles and the player are structurally incapable of being tinted by it. That keeps
`biome_schedule_check`'s contrast floors and the coin/obstacle readability contract meaningful
without this feature having to argue with either. Do not raise it above 0. If the ice should ever
catch the light too, the lever is a lake-style single-entry ice blend on `TerrainGenerator`
(`set_lake_ice_blend` is the working precedent), **not** a palette field and not this layer.

New files:

| File | Roughly | Job |
|---|---|---|
| `scripts/systems/aurora_director.gd` | 180 lines | WHEN. The clock, the phase machine, the one ramp |
| `scripts/systems/aurora_sky.gd` | 110 lines | The look. Owns both `Curtain` and `Wash`, pushes uniforms |
| `shaders/aurora.gdshader` | 160 lines | The curtains |

Edits: `main.tscn` (three nodes), `terrain_generator.gd` (the calm band, ~30 lines),
`obstacle_spawner.gd` (**one line**), `main.gd` (camera, ~25 lines), `save_store.gd` (one field,
v3→v4), `achievement_manager.gd` (one row, one `.connect`), `game_manager.gd` (extract the
playtime helper), `shipping_values_check.gd` (the new knobs), `CLAUDE.md` row 12, `visuals.md`.

### Division of labour, and it matches the lake exactly

`AuroraDirector` owns **when**. `TerrainGenerator` owns the geometry. `ObstacleSpawner` owns its
own suppression. `main.gd` owns the camera. `aurora_sky.gd` owns nothing but the look and
**reads** the director's phase rather than being pushed at — the reason is in `lake_reflection.gd`'s
header and it still holds: a push needs a call site at begin, at finish and in the death handler,
which is three places that can disagree about whether the effect is up, where `visible = (phase ==
ACTIVE)` is true by construction from the one variable that already means it.

Nothing reaches into another system to do that system's job.

## The one ramp

`AuroraDirector.get_aurora_blend() -> float`, 0 outside the event, 1 across the hold, smoothstepped
at both ends. **Every cosmetic piece rides it and nothing computes its own fade** — the curtain's
intensity, the wash's alpha, the camera's framing and zoom. This is the lake's
`get_lake_blend()` discipline verbatim, and the reason is the same: two consumers deriving the
same fade off the same timestamps is two chances to derive it differently, and the symptom is one
element arriving a beat after the others.

**Time-based, not distance-based**, which is the one place the aurora deliberately departs from
both the lake (distance across a fixed 7500 px) and `BiomeDirector` (a pure function of world x).
The aurora is about a minute of sky, not about a place, and a distance ramp would make it shorter
for a fast player — backwards for a thing you are meant to watch. Nothing headless or replayable
depends on it, so no determinism is lost.

The clock must be `Main.elapsed_time`-derived and must therefore freeze on every menu for free:
default `process_mode` (INHERIT), same as `FrozenLakeDirector`.

## The trigger

```
due  ⟺  saved_playtime + unbanked_this_run  ≥  (aurora_count + 1) × AURORA_INTERVAL_SECONDS
```

**`get_unbanked_seconds()`, never `Main.elapsed_time`.** `GameManager.bank_playtime()` fires on
every `PLAYING → not-PLAYING` transition, which on Android includes every notification and app
switch, so adding the whole run on top of the banked total credits phantom playtime that compounds
once per pause. The lake shipped exactly that bug — three pauses at 3/6/9 minutes credited +18
phantom minutes, on their own enough to hand out a set piece nobody earned. `game_manager.gd`'s
`get_unbanked_seconds()` carries the full reasoning.

`FrozenLakeDirector.get_total_playtime_seconds()` already computes precisely this. **Move it to
`GameManager` and have both directors call it** rather than copying six lines into the second
consumer — one owner of "cumulative playtime including the part of this run not yet banked". That
refactor is a phase of its own below, done before the aurora needs it, so it lands as a two-line
diff in the lake rather than as noise inside a new feature.

Arming additionally requires, all on the same frame:

- **A dark biome.** `twilight_blue`, `violet_dusk` or `starlit_night`, asked via
  `BiomeDirector.get_cycle_base_palette()` — never `get_cycle_palette()`, which can hand back a
  rare-variant *duplicate* that fails an identity comparison against `BIOME_CYCLE`. That
  distinction is why `get_cycle_base_palette` exists at all; `biome_schedule_check` learned it
  the hard way.
- **Not mid-transition.** Arming at 0.5 through a crossfade means the sky is halfway to a bright
  biome by the hold. Require the biome's blend progress to be ~0 and to have enough distance left.
- **No lake armed or active.** At 20 and 30 minutes the two set pieces collide every hour of
  cumulative playtime, and a lake inside an aurora is two "holy crap" moments cancelling each
  other out — plus the lake locks jumping while the aurora deliberately does not. **The aurora
  yields**; it stays due and arms after. One check against `FrozenLakeDirector.phase`.
- **Past a minimum run time**, so a restart taken just before a due aurora doesn't drop one four
  seconds into the next run. The lake's `LAKE_MIN_RUN_TIME` exists for this and for a second
  reason that does *not* apply here (its 10 s crossing is only deterministic past the speed cap),
  so the aurora's minimum can be lower — 60 s is a starting value, not a derived one.

A rejected frame simply retries on the next one. The threshold stays crossed.

## The calm

This is the only part of the aurora that touches anything outside presentation, so it gets its own
commit and its own gate run.

### No obstacles

`ObstacleSpawner` already asks `terrain_generator.is_lake_world_x(world_x)` and skips a slot when
it says yes (`obstacle_spawner.gd:187`). The aurora adds `or is_calm_world_x(world_x)` **on that
same line**. That is the entire change.

**Coins and powerups keep spawning.** Only the thing that can kill you is removed. A minute of
free collection while the sky does something is a reward, and suppressing all six spawners the way
the lake does would make the aurora a dead zone six times longer than the lake's.

### No chasms

`is_chasm_segment_index()` is **already a pure function of `segment_index`** — hash-placed, one
chasm per 56-segment window, and already gated by the `debug_chasm_disabled` bool. So the change is
one more early-out in that function against a committed calm range.

**The rule that makes this safe is the rule the lake already lives by.** `get_terrain_height` must
stay pure in `(session_seed, world_x)`; the lake buys its one exception with
`lake_segment_index` being **write-once and write-ahead** — `arm_lake()` is its only writer and may
only set it *above* `highest_cached_segment_index`, so arming can only ever *extend* the height
field and never contradict a sample already taken. The calm band takes the identical deal:

- `arm_calm(start_index, end_index)` is the **only** writer of the range.
- It may only commit indices **strictly greater than `highest_cached_segment_index`**, and it
  refuses otherwise, exactly as `arm_lake()` does.
- Once committed the range never moves, so `get_terrain_height(x)` is still the same value for the
  same x forever, for every one of the four systems that sample it independently.

**Do not implement this as "no chasms while the aurora is active."** A time-conditioned height
field is a different value depending on when you asked, and chunk visuals, collision, player tilt
and the debug HUD all sample it separately — they would disagree with each other inside one frame.
This is the cardinal terrain rule in `CLAUDE.md` and it is the single easiest way to break this
game.

Scale check, so nobody imagines this is a large intervention: 60 s at `MAX_SPEED` is 45,000 px,
roughly 20–30 segments against a 56-segment chasm window. **A calm band suppresses at most one
chasm and often zero.** `mega_drop` is already at selection weight 0, so there is nothing else to
suppress — the terrain under an aurora is hills, valleys and flats, which is what it mostly is
anyway. It keeps rolling, and it should: a second dead-flat set piece would just read as a long
pale lake.

### Death is never disabled, the hazards are removed

`player.gd:147` states the constraint and it is not negotiable: `has_shield` is obstacle-only, and
`update_fall_death()` and both watchdogs must stay untouched by it, because *a shield that
swallowed fall-death would leave the player falling forever behind the terrain — a worse outcome
than the death it prevented.* A blanket "can't die" flag for the aurora is the same bug wearing a
different name.

With no chasms there is nothing to fall into, so `update_fall_death()` never fires. With no
obstacles there is nothing to hit. The player genuinely cannot die, and not one line of the death
path changed. Same reasoning as the lake locking the jump *input* rather than making jumping
harmless.

The stall watchdogs stay live throughout. They catch bugs, not gameplay.

## The camera

**The frozen lake does not zoom.** `main.gd:331 apply_lake_framing()` lerps the camera's *target y*
toward a framing where the shore sits at `LAKE_HORIZON_FRACTION` (0.56), by however much lake the
player is currently on. `Camera2D.zoom` is untouched anywhere in the project.

The aurora wants both, in the same shape — one function, blended by `get_aurora_blend()`:

- **A framing lift**, so the horizon drops and more sky is on screen. Cheap, proven, and the exact
  mechanism already in the file.
- **A modest zoom-out**, so the world opens up. Normally this would be the risky one — base size
  and zoom are one decision and only their ratio is field of view, which on an auto-runner is
  reaction time. **During an aurora that objection does not apply**, because there is nothing left
  to react to. Verified: the three live readers of `camera.zoom` (`main.gd:340`,
  `lake_reflection.gd:149`, `glide_coin_spawner.gd:218`) all re-read it per frame rather than
  caching it at `_ready()`, so an animated zoom needs no invalidation anywhere.

Both must return to exactly their authored values, which the ramp gives for free at blend 0.
`camera_shake_probe` is owed on this commit — it is the gate that exists for changes to the camera
follow in `main.gd`.

Keep the zoom-out modest. It is the difference between "the world opened up" and "the player got
small", and only the owner can judge which side a given number lands on.

## The look

### Why a third shader

The project has exactly two `.gdshader`s, both owned by ice, and `visuals.md` requires a third to
clear the same bar. It does. What the curtains need is a soft-edged field varying continuously in
**x, y and time at once**, with a colour ramp along its own vertical axis. `vertex_colors` can
express a colour per vertex on a static mesh and nothing else; the alternatives are worse in ways
the project has already paid for:

- **Authored ribbon sprites cross-faded** — needs art nobody has, reads as sliding decals, and
  cannot avoid a visible repeat.
- **`Line2D`/`Polygon2D` curtains rebuilt per frame** — per-frame node work on the main thread,
  hard edges, and this is precisely how `flight_trail.gd` ended up reading as tally marks rather
  than a path. "Choppy" is the exact failure mode being avoided.

The shader is also the *cheap* option: one hidden `ColorRect` costs nothing for the 29 minutes
between events, and unlike `frozen_lake_reflection.gdshader` it needs **no `hint_screen_texture`**,
so there is no backbuffer copy at all.

### What actually makes it read as an aurora

Five properties, and dropping any one of them is what produces "one colour" or "choppy":

1. **A folding arc, from two or three low-frequency sines** of x and time. Sines, not noise, for
   the base shape — smooth, cheap, and controllable. Noise belongs in the detail, not the skeleton.
2. **An asymmetric vertical falloff.** Sharp lower edge, long soft tail upward. This single
   property is most of what separates an aurora from a band of fog.
3. **Vertical rays.** A high-frequency function of x, strongest at the base of the curtain and
   fading upward, drifting slowly sideways. This is the striation, and it is what makes the thing
   look alive rather than pulsing.
4. **Colour along the curtain, not across the screen.** Teal-green at the sharp base → green
   through the body → magenta/violet at the crown, fading out. This is the answer to "it looks
   like one colour": the ramp runs along the curtain's own axis, so a fold shows every hue at once.
5. **Two or three curtains** at different amplitudes, phases and hue offsets, summed.

### Composition and clipping

**LDR, and it clips.** The Mobile renderer clamps at 1.0, and this project has now learned twice
that additive light saturates its brightest channel first and can only drift toward white —
`BiomePalette.glow_color`'s note, and the skate track's, where a clipped core "carried no
information". So: keep the peak well under clipping and let the aurora's presence come from
**saturation, not brightness**. If it looks grey or white, widen the hue separation before
reaching for the intensity — that is a standing finding in this project on three separate features
now.

### Motion, and the two traps

- **The clock is a script-owned uniform, never `TIME`.** `TIME` keeps running while the tree is
  paused, so a `TIME`-driven curtain animates behind the pause overlay. `aurora_sky.gd` advances
  its own `aurora_time` in `_process` and is pause-frozen by its `process_mode`, exactly as
  `lake_reflection.gd` is. This is already written down and has already been got wrong once.
- **Keying on `SCREEN_UV.x` alone is right here, and it is right for the opposite reason it was
  wrong on the lake.** The lake shader's header is emphatic that anything x-varying must key on
  *world* x, because a pattern fixed to the screen while the world slides past reads as dirt on
  the lens. An aurora is 100 km up and genuinely should not track the player. But a shape *totally*
  frozen to the screen for 60 seconds will read as a decal, so give it a very slow world-x drift —
  the parallax layers' own language, around `FarPeaks`' 0.015. **Small, and worth measuring rather
  than guessing.**

### The rect is not full-screen

`visuals.md`: *size a rect to its content, not to the screen.* The ridges are opaque and their tops
never go above y≈0.21, so anchor `Curtain` to the sky band rather than `PRESET_FULL_RECT`. That is
close to half the fragments for free, and fill rate is this feature's one real performance
question. The wash at −45 does need to be full-rect, since it is washing the mountains.

### Overdraw budget

`visuals.md` sets it at **four full-screen alpha layers at once**. Today: `SkyGlow` and `SnowDrift`.
The aurora adds the curtain (partial-screen) and the wash (full-screen), landing at four in the
worst case. That is at the limit, not over it — and **only while an aurora is running**. Both nodes
follow the project's standing rule and are `visible = false` otherwise: a fully transparent
full-screen `TextureRect` still rasterises every pixel it covers, which is why
`sky_backdrop.apply_glow()` and `terrain_generator.paint_snow_cap()` both hide rather than fade to 0.

## Save and achievement

`SaveStore` gains **`aurora_count`**, which doubles as the index of the next 30-minute threshold —
same device as `frozen_lake_count`, and for the same reason: a plain multiple cannot drift or be
lost the way a running deadline can.

**Bump `CURRENT_VERSION` to 4.** Functionally the field could be read out of a v3 file with a
default of 0 and nothing would break — but that would make "version 3" mean two different payload
shapes, which is the ambiguity the version field exists to remove. The migration is the same
idiom v0→v1, v1→v2 and v2→v3 all used: *reading the fields that exist is the migration.* A v3 file
has never seen an aurora, so 0 is the correct state for it. Keep `reset_progress()` clearing it,
alongside `frozen_lake_count`.

The achievement is a row in `ACHIEVEMENTS` and one `.connect()` on the `aurora_finished` signal —
the two-edit shape `achievement_manager.gd`'s header promises, and that file already names this
feature as the expected second one. Gate it on the **flag**, never on `aurora_count == 1`, for the
reason spelled out at `_on_lake_finished`.

> **The trap that file ends on applies here and must be checked.** `AchievementManager` has no
> headless guard, and that is only safe because its one trigger cannot fire headless.
> `AuroraDirector` hard-skips headless, so the property survives — **but it survives by
> construction only as long as that skip is the first thing in `_ready()`.** If it ever isn't,
> every probe starts writing achievements into the developer's real `save.dat`.

Achievement id is save data: renaming one un-earns it for everyone. Pick the name once. Owner's
call — the game is called AURA and this is its namesake, so it is worth a minute.

## The headless contract

Every gate instantiates `main.tscn`, so all three new files run on every gate frame. The rules are
not new and all three obey them:

- `is_headless` computed **locally** from `DisplayServer.get_name()`, never `Services.is_headless`,
  which is assigned in `GameServices._ready()` and can still read false depending on node order.
  `snow_drift.gd` and `sfx_player.gd` both shipped this bug.
- `set_process(false)` / `set_physics_process(false)` **before** the headless return, not after.
- Every dependency `get_node_or_null` + null-guarded, and a missing one is a `push_warning` and a
  disabled feature, never fatal. A missing aurora is a missing spectacle, not a broken game.
- **A parse error in any of these hangs the gates rather than failing them.** Run `check.sh`.

Because the director hard-skips headless, the calm band is never armed in a gate and no terrain
gate can move. That is the same guarantee the lake has, and it is why the terrain change is
survivable at all.

## Phases

One numbered step at a time, each its own commit, stop for a "go" between them — the standing
working agreement. The order is deliberate: the look is where the iteration is, and it is the part
with no consequences, so it goes first and alone.

| # | Commit | Gates owed |
|---|---|---|
| 0 | This document | — |
| 1 | `GameManager.get_total_playtime_seconds()` extracted; `FrozenLakeDirector` calls it | `check.sh` |
| 2 | `aurora.gdshader` + `AuroraSky` + a `debug_force_aurora` knob. **No scheduling, no gameplay.** Look at it, iterate, land it when the owner likes it | `check.sh`, then `sky_layer_check` |
| 3 | `AuroraDirector`: clock, phases, the ramp, dark-biome gate, lake exclusion, headless skip, `shipping_values_check` rows for every new knob | `check.sh` |
| 4 | The calm: `arm_calm()` + `is_calm_world_x()` + the one line in `ObstacleSpawner` | **`check.sh`, freeze-search, freeze-replay, floor-flicker, chasm, `lake_suppression_probe`** |
| 5 | Camera: framing lift + zoom-out | `check.sh`, **`camera_shake_probe`** |
| 6 | The wash layer | `check.sh`, `sky_layer_check` |
| 7 | `SaveStore` v4 + the achievement | `check.sh` |
| 8 | Gate coverage for the aurora, `CLAUDE.md` row 12, `visuals.md`, this file | all fast gates |

Phase 4 is the only one that touches anything a physics gate can see, which is exactly why it is
alone in its commit and carries the whole physics tier.

### What phase 8 has to add

`shipping_values_check` covers the knobs from phase 3 onward — every debug knob in this project is
a plain `var` precisely so the editor cannot serialise it, which also means **nothing else in the
project can see one left flipped**. A forced-on aurora that ships is a permanent aurora.

The visual side needs a claim nothing currently makes: **that the curtain and the wash actually
move pixels.** `sky_layer_check` proves exactly this for every other optional sky layer and exists
because the glow once shipped passing every data check while contributing 11/255. The aurora
cannot slot into its per-palette `LAYERS` table — it is not a `BiomePalette` field — so this is
either a small extra pass in that file with the aurora forced on, or a sibling windowed check.
Either way it must run **without `--headless`**; it diffs rendered frames.

## Open, and deliberately not decided yet

- **Fill rate on a real phone.** This is the one thing that could genuinely hurt the game rather
  than merely look wrong, and it cannot be answered from a desktop. Budget: no screen-texture read,
  ≤3 noise octaves, no loop above 8 iterations, curtain rect confined to the sky band. **Measure
  on the owner's Android device during phase 2** — before the feature has anything else built on
  top of it.
- **Ambient audio.** There is no lake sound either, and the SFX pool is five one-shots on a 6-voice
  pool with no music bed. An aurora is the strongest argument the project has for ambience, and it
  needs an asset that does not exist. Out of scope; worth raising after the visual lands.
- **Whether "waits for a dark biome" is too rare in play.** Only playtesting answers it. The
  fallback is already designed above (a sky-channel override handed through
  `BiomeDirector.push_palette`), so this is a known road, not a redesign.
- **Whether the calm should also suppress the powerup spawner.** Currently no. A speed boost during
  an aurora is either a great moment or a thing that rushes you through it; the owner should watch
  one before deciding.
