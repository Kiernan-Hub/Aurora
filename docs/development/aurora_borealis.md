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
| Dark-biome transitions | **Allowed between dark palettes**, forbidden into a bright one. Forced by arithmetic — see below |

### Revised 2026-09-05 after external review

The first version of this plan was reviewed against the code and **three of its numbers were
wrong**. They are corrected in place below; they are called out here because each one was load
bearing, and because a reader who saw the first version should know what moved.

| Was | Is | Where it bit |
|---|---|---|
| Safe distance sized at `MAX_SPEED` 750 px/s | `SPEED_BOOST_SPEED` is **1000** (`powerup_manager.gd:26`), and powerups keep spawning | The calm could end while the aurora was still on screen |
| "45,000 px is 20–30 segments, at most one chasm" | Segment lengths are **480 / 640 / 960** (`terrain_generator.gd:295–299`), so it is ~63–75 segments and **1–2 chasms** | The reassurance was arithmetic on the wrong constant — `CHASM_SEGMENT_LENGTH` (1600) is not a typical segment |
| "A framing lift shows more sky" | Every `motion_scale` in `main.tscn` is `(x, 0)`, so **the ridges are vertically screen-locked and a camera lift does not lower them** | The stated reason for the camera move was simply not true. The move itself still works — the lake ships it — but for a different reason, and only zoom changes the ridge composition |

Two more findings from the same review are folded in below: the lake exclusion was written in one
direction only, and adding `aurora_count` to a save that already holds a large playtime creates a
backlog of overdue events on the first launch. Both are real; both now have rules.

### Why it only fires in the dark biomes

The eight palettes rotate by a random amount each launch (`BiomeDirector.session_cycle_rotation`),
so a playtime-gated event lands on an arbitrary sky. A green curtain over `pale_morning`'s
near-white sky moves almost no pixels — which is not a guess, it is exactly the failure
`sky_layer_check.gd` was built after (a glow shipped contributing 11/255 and reading as nothing).

So the aurora waits. It becomes *due* on the clock and then arms on the first frame that the
active biome is one of the three dark ones. That is the same shape as the lake being due and then
retrying `try_arm()` until it gets a clean frame, and it costs nothing but patience.

**Eligible: `violet_dusk`, `twilight_blue`, `starlit_night`.** They are `BIOME_CYCLE` indices 5, 6
and 7 — already adjacent, because the eight are authored as a day passing and only the entry point
rotates. `sky_top` runs 0.46 → 0.26 → 0.20 across them against `pale_morning`'s 0.72, and
`star_density` 0.30 → 0.85 → 1.00, so they are the dark end of the arc by the data and not by
taste.

**A transition between two of those three is allowed. A transition toward a bright one is the
deadline.** This is not a preference, it is forced:

```
biome span            75,000 px
transition            24,000 px
stable per biome      51,000 px  =  68.0 s at MAX_SPEED
worst-case event      60,000 px  (60 s at SPEED_BOOST_SPEED — see "How long the calm must be")
```

A worst-case event **does not fit inside one biome**, and a nominal one fits with eight seconds
left for the approach. Confining the aurora to a single stable biome window therefore either fails
outright or waits forever for an interval that cannot exist. Across the three adjacent dark
palettes the stable span is 201,000 px — 268 s — which is ample.

The two dark→dark crossfades are visible under the aurora and that is fine: the curtains carry a
fixed palette of their own (see "Colour identity"), and the sky moving from dusk to night beneath
them is the day arc doing exactly what it was authored to do.

Eligibility must be computed from the **candidate event's start and worst-case end**, in real
cycle coordinates including `biome_phase_offset` — not from `applied_progress`, which
`BiomeDirector` updates in `_process` while arming runs in `_physics_process`.

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
due  ⟺  saved_playtime + unbanked_this_run  ≥  next_aurora_due_seconds
```

**A stored next-due timestamp, NOT `(aurora_count + 1) × INTERVAL`.** The lake's multiple works
because `total_playtime_seconds` and `frozen_lake_count` were both born at 0 in the same save
version, so a lake was never retroactively owed. `aurora_count` is being added to saves that
**already hold hours of playtime**, and `(0 + 1) × 1800` against a ten-hour save is twenty overdue
auroras that would fire back to back until the backlog cleared. That is the rarity destroyed on
the first launch after the update, for the game's headline feature.

So the aurora stores its own deadline and pushes it forward on completion:

```
on v3 → v4 migration:   next_aurora_due = total_playtime_seconds + AURORA_INTERVAL_SECONDS
on completion:          next_aurora_due = total_playtime_seconds + AURORA_INTERVAL_SECONDS
on reset_progress():    next_aurora_due = AURORA_INTERVAL_SECONDS
```

This makes "every 30 minutes" mean **30 minutes between sightings**, which is what was actually
decided, rather than 30 minutes of lifetime credit that can be spent in a burst. An existing
player's clock starts now — the same honest reading `save_store.gd` already applies to the v2 → v3
playtime field. `aurora_count` is still stored, but only as a statistic and for the achievement;
it is not the schedule.

**One aurora per run maximum**, so the terrain reservation stays write-once for the life of a
scene. The phase machine ends in a terminal DONE, exactly as the lake's does. A second aurora in
one sitting arrives after a death, which is also when the reservation is disposed of with the
scene.

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
- **A dark window wide enough for the worst case.** Not "blend progress ~0", which was hand-waving
  in the first version of this plan and is not an algorithm. The real test: project the reserved
  band's end at worst-case speed, convert it to a cycle coordinate, and require every biome the
  event touches to be one of the three eligible palettes. See "Why it only fires in the dark
  biomes" for why one biome is not enough room.
- **Mutual exclusion with the lake, in BOTH directions.** The first version of this plan only made
  the aurora look at the lake. That is half a rule: a lake becoming due *after* the aurora has
  armed will happily reserve its own terrain inside the aurora's, and the two are much more likely
  to collide than the nominal 20/30-minute coincidence suggests, because an overdue aurora can sit
  waiting for darkness for minutes.

  **Whoever holds a reservation keeps it; the other one waits.** If both are due and neither has
  reserved, the lake goes first — it is the shorter event and the older feature. `arm_lake()` gains
  a check against the aurora's reserved range exactly as `try_arm()` gains one against
  `FrozenLakeDirector.phase`. Two explicit checks, no event framework.
- **Past a minimum run time**, so a restart taken just before a due aurora doesn't drop one four
  seconds into the next run. The lake's `LAKE_MIN_RUN_TIME` exists for this and for a second
  reason that does *not* apply here (its 10 s crossing is only deterministic past the speed cap),
  so the aurora's minimum can be lower — 60 s is a starting value, not a derived one.

A rejected frame simply retries on the next one. The deadline stays crossed.

### Reservation and presentation are two different boundaries

**Arming ahead does not make the approach safe, and entering a safe x interval does not prove the
player is safe** — a fall begun at a chasm before the band carries into it, and `update_fall_death`
does not care which segment the body is over.

So the two are separated:

1. **Reserve** the terrain band, ahead of the cache watermark, as early as the schedule allows.
2. **Start the visual timer** only on a frame where the player is **inside** the band, **grounded**
   (`is_on_floor()`), and **not jump-ascending** — the same three conditions `FrozenLakeDirector.try_arm()`
   already uses, for the same reason.
3. The band must cover the whole timed event **plus a recovery margin** past the fade, so the first
   hazard after the aurora is not sitting immediately behind a player who is still looking up.

On death or cancellation: reset the presentation, **keep the terrain reservation**. Clearing it
would make every cached chunk and collision sample behind the player disagree with a fresh sample
of the same x — which is precisely why `finish_lake()` deliberately leaves `lake_segment_index`
set. The reservation dies with the scene, not with the event.

## The calm

This is the only part of the aurora that touches anything outside presentation, so it gets its own
commit and its own gate run.

### How long the calm must be

**Not 45,000 px. That number came from `MAX_SPEED` (750) and the first version of this plan was
wrong to use it** — powerups keep spawning during an aurora, and `SPEED_BOOST_SPEED` is **1000
px/s** (`powerup_manager.gd:26`). A player who picks up a boost late in the hold outruns a band
sized at 750 and can reach the first live chasm while the curtains are still on screen.

The band is therefore sized from the **fastest speed the player can be moving**, not the fastest
they usually are:

```
event duration        60 s
worst-case speed      1000 px/s   (SPEED_BOOST_SPEED, not MAX_SPEED)
event footprint       60,000 px
recovery margin       + one screen and change, so the first hazard is not on the fade
```

**This bound is deliberately loose, not derived.** A boost lasts 3 s, so sixty seconds of
continuous boost is impossible and the real footprint is nearer 47,000 px. Reserving the full
60,000 over-reserves by about a third — and the cost of over-reserving is *more calm*, which is
harmless, where the cost of under-reserving is a death during the game's centrepiece. Take the
loose bound. Tightening it means formally accounting for powerup scheduling, which is a lot of
reasoning to buy back twenty seconds of hills.

### What that actually costs in terrain

**Corrected.** The first version of this plan claimed 45,000 px was "20–30 segments, at most one
chasm". That was arithmetic on the wrong constant — `CHASM_SEGMENT_LENGTH` (1600) is the length of
a *chasm*, not of a typical segment. The real lengths are `SMALL_SEGMENT_LENGTH` 480,
`MEDIUM_SEGMENT_LENGTH` 640 and `SUSTAINED_DOWNHILL_LENGTH`/`GENTLE_UPHILL_LENGTH` 960
(`terrain_generator.gd:295–299`).

So a 45,000 px band is **~63–75 segments**, and at one chasm per `CHASM_WINDOW_SEGMENT_COUNT` (56)
that is **one to two chasms**, measured at two in five sampled stretches. A 60,000 px band is
proportionally more — call it **two to three**.

That is still fine, and it does not change the design: removing two or three chasms from a run is
exactly the intended effect. What it changes is that **the size of the band must be derived, never
estimated.** The old number was reassurance rather than measurement, and reassurance is how this
kind of feature ships a death.

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
- **Every index in the range must also be absent from `segment_spec_cache`**, not just past the
  watermark. `arm_lake()` already checks `segment_spec_cache.has(candidate)` and its own comment
  calls that check "defensive… the watermark rule already guarantees this is false" — but
  `get_segment_spec()` can populate the cache beyond the watermark without advancing it, so for a
  *range* the check is load-bearing rather than defensive. Check all of it.
- Once committed the range never moves, so `get_terrain_height(x)` is still the same value for the
  same x forever, for every one of the four systems that sample it independently.

**Do not implement this as "no chasms while the aurora is active."** A time-conditioned height
field is a different value depending on when you asked, and chunk visuals, collision, player tilt
and the debug HUD all sample it separately — they would disagree with each other inside one frame.
This is the cardinal terrain rule in `CLAUDE.md` and it is the single easiest way to break this
game.

**Choosing the range must not cache the terrain it is about to change.** Walking the ordinary
segment getters forward to find where 60,000 px ends would populate the spec cache for exactly the
indices the arm then wants to alter, and the arm would correctly refuse — a self-inflicted
deadlock. Suppressing a chasm does not merely disable a void, it changes that segment's *spec*,
including its length, so the band's end index is not knowable from pre-existing terrain anyway.

Use a **conservative bound from the minimum legal segment length** (480 px) instead:
`ceil(60,000 / 480)` = 125 segments, validated and committed atomically. That deliberately
over-reserves — the mean segment is longer than the minimum — and over-reserving costs nothing but
extra calm. Validate the whole range, then commit; a rejected arm must leave every cache exactly
as it found it and simply retry next frame.

`mega_drop` is already at selection weight 0, so chasms are the only hazard type to suppress — the
terrain under an aurora is hills, valleys and flats, which is what it mostly is anyway. It keeps
rolling, and it should: a second dead-flat set piece would just read as a long pale lake.

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

The aurora wants both a framing lift and a modest zoom-out, in the same shape — one function,
blended by `get_aurora_blend()`. But the reason given for the lift in the first version of this
plan was **wrong**, and the correction matters because it decides which of the two actually does
the work.

**A framing lift does not lower the mountains.** Every `motion_scale` in `main.tscn` is `(x, 0)` —
vertical parallax was tried and reverted, and `motion_scale.y = 0` is precisely what makes the
whole backdrop immune to `main.gd`'s world rebase (`visuals.md`, Traps). So the ridges are
**vertically screen-locked**: moving the camera's target y slides the *terrain* down the screen and
leaves the ridgeline exactly where it was. It does not reveal more sky.

That does not make the lift useless — the lake ships one, and `main.gd` calls it the single
biggest visual difference of that set piece. It changes the relationship between the terrain and
the ridgeline, which is a composition effect worth having. It just is not the "more sky" lever.

**Zoom is the lever that moves the sky.** `ParallaxBackground.ignore_camera_zoom` defaults to
false, so zoom scales the ridges and the panorama along with everything else. Normally that makes
zoom the riskier of the two — base size and zoom are one decision and only their ratio is field of
view, which on an auto-runner is reaction time. **During an aurora that objection does not apply**,
because there is nothing left to react to. And it is cheaper than expected: the three live readers
of `camera.zoom` (`main.gd:340`, `lake_reflection.gd:149`, `glide_coin_spawner.gd:218`) all re-read
it per frame rather than caching it at `_ready()`, so an animated zoom needs no invalidation
anywhere.

Three things this section must not forget:

- **Glide already owns the camera.** `main.gd`'s `is_glide_vertical_follow_active` deliberately
  follows a gliding player upward until they land. An aurora framing override anchored to the
  terrain will fight it and can pull a gliding player off screen. **Glide takes precedence**;
  define that explicitly rather than discovering it.
- **Capture and restore the authored zoom explicitly.** The ramp returns to 0, but read the
  authored value once rather than assuming the literal in `main.tscn` — that is how a knob left
  half-applied ships.
- **The camera follow has smoothing lag.** Blend 0 means the *target* is back, not that the camera
  has arrived. The protected band must outlast the settle, not just the fade.

`camera_shake_probe` is owed on this commit — it is the gate that exists for changes to the camera
follow in `main.gd`. Note it measures camera *position*, so it does not by itself see screen motion
caused by a zoom change; that half is an owner look.

Keep the zoom-out modest. It is the difference between "the world opened up" and "the player got
small", and only the owner can judge which side a given number lands on.

**Prototype the camera with the curtains, not after them.** Approving a static sky and then
discovering the final composition is how this gets rebuilt twice — and since zoom rescales the
ridges, the sky the curtains sit in is not the sky they were judged against.

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

`visuals.md`: *size a rect to its content, not to the screen.* Anchoring `Curtain` to the sky band
rather than `PRESET_FULL_RECT` is close to half the fragments for free, and fill rate is this
feature's one real performance question.

**But the boundary is the LOWEST exposed sky, not the highest peak, and the first version of this
plan got that backwards.** Peaks topping out at y≈0.21 says where sky *starts*; sky remains visible
much further down, in every valley between peaks and wherever the ridgelines dip. Clipping at the
highest peak would cut a hard horizontal line straight across the sky visible through those
valleys. The bottom of the quad has to sit below the lowest point of the whole silhouette across
all four layers, at every supported zoom — and zoom rescales the ridges, so the aurora's own
zoom-out moves this boundary. Derive it with margin, or measure it and leave room; do not read it
off the peak table.

### The wash

The wash at −45 is full-rect, since it is washing the mountains — but "below gameplay" only
protects the *objects'* colours, and three things still need deciding rather than defaulting:

- **`mouse_filter = MOUSE_FILTER_IGNORE`.** `ColorRect` is a `Control` and defaults to
  `MOUSE_FILTER_STOP`. A full-screen one left at the default is an input eater sitting under the
  pause button — a standing trap in `visuals.md` that every other full-screen Control in this
  project already obeys.
- **Blend mode, vertical profile and an opacity cap.** A flat full-screen veil at uniform alpha
  will wash the ridge separation flat and desaturate the curtains it is drawn over. Prefer a
  restrained spill that varies vertically — strongest near the horizon where light would pool,
  fading upward — with a hard cap, so mountain-to-mountain separation and the curtain's own colour
  structure both survive.
- **Contrast is no longer proven by the palette gates.** `biome_schedule_check` reasons about
  palette data, and the wash changes the *background* behind a coin and behind an airborne player
  without touching either object's colour. So the readability claim has to be re-checked on final
  pixels with every layer present, including a player at glide height. This is not a gate failure
  waiting to happen — it is a gate that will keep passing while saying nothing about the case.

### Overdraw budget

`visuals.md` sets it at **four full-screen alpha layers at once**. Today: `SkyGlow` and `SnowDrift`.
The aurora adds the curtain (partial-screen) and the wash (full-screen), landing at four in the
worst case. That is at the limit, not over it — and **only while an aurora is running**. Both nodes
follow the project's standing rule and are `visible = false` otherwise: a fully transparent
full-screen `TextureRect` still rasterises every pixel it covers, which is why
`sky_backdrop.apply_glow()` and `terrain_generator.paint_snow_cap()` both hide rather than fade to 0.

## Save and achievement

`SaveStore` gains two fields: **`next_aurora_due_seconds`**, the schedule (see "The trigger" for
why it is a stored deadline and not `count × interval`), and **`aurora_count`**, kept as a
statistic only.

**Bump `CURRENT_VERSION` to 4**, and unlike every previous bump in this file **the migration is not
"read the fields that exist".** That idiom worked for v0→v1, v1→v2 and v2→v3 because each new field
was born alongside the clock that drives it — when v3 landed, `total_playtime_seconds` also started
at 0, so no lake was ever retroactively owed. A v3 save already holds hours of playtime, so a
defaulted deadline of 0 is *immediately overdue*, by as many intervals as the player has hours.

```
v3 → v4:   next_aurora_due_seconds = total_playtime_seconds + AURORA_INTERVAL_SECONDS
           aurora_count            = 0
```

The existing player's first aurora is therefore 30 minutes of play away, which is the same honest
reading v2→v3 applied to playtime itself: *the clock starts now rather than being back-dated.*
`reset_progress()` clears the count and sets the deadline to one interval, not to 0.

Fixtures worth testing once, on a **copy** of the real save: a v3 file with a large playtime (the
case above), a v3 file with almost none, a v4 round-trip, and a reset.

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

**Read that as regression isolation and nothing more.** It means the aurora cannot break the
existing gates. It is emphatically *not* evidence that the aurora works: a green `freeze-search`
run with no band armed has not exercised one line of this feature. The lake draws exactly this
distinction — `lake_suppression_probe` pins a lake with `debug_force_lake_segment_index` because
the director would never arm one in a probe, and `check_lake_arming` covers the other half
separately. The aurora owes the same, and it is the next section.

## Proving it, without adding six gates

The claims this feature makes that nothing else can check:

1. Arming does not change terrain that was already sampled.
2. No obstacle **body** exists inside the band — not merely that a predicate returns true.
3. No chasm segment exists inside the band, at either boundary.
4. A player crossing the whole band, at boosted speed and with no input, **survives**.
5. A knob left on does not ship.

**One new probe covers 1–4:** `aurora_calm_probe.gd`, headless, modelled directly on
`lake_suppression_probe.gd` — which exists for the identical reason and pins its set piece the
same way. It arms a forced band, snapshots heights and specs before and after, walks the spawners,
and drives a no-input traversal at `SPEED_BOOST_SPEED` from before the near boundary to past the
far one. **Removing the calm guard must make it fail**; a probe that passes with the feature
deleted is measuring nothing, which is the standing lesson from the eighteen archived probes.

Claim 5 is `shipping_values_check`, and the row lands **in the same commit as the knob** — phase 2,
not later. A plain `var` is invisible to every other gate, so between introducing a force-on knob
and registering it there is a window where a forced-on aurora ships silently.

**This is deliberately one probe and not the full matrix.** An exhaustive reading would want
separate coverage of every session rotation, restart phase, biome boundary, glide combination,
pause/resume timing, save migration, death cleanup and camera transform — realistically five to
eight new files. `CLAUDE.md` says *"Twelve maintained checks, and only twelve"* and archives
everything else on purpose, and eighteen archived probes are already there as evidence of what
happens to gates nobody maintains. The scheduling and save cases are better as **assertions inside
gates that already exist** (`biome_schedule_check` for dark-window eligibility across every legal
rotation; `shipping_values_check` for the interval constants) plus one manual pass over a **copy**
of a real save. If the calm probe ever catches something the matrix would have caught earlier, that
is the moment to add the second file — not before.

## Phases

One numbered step at a time, each its own commit, stop for a "go" between them — the standing
working agreement. The order is deliberate: the look is where the iteration is, and it is the part
with no consequences, so it goes first and alone.

**Reordered after review.** The hazards now come out *before* production scheduling is switched on,
and the camera and wash are prototyped alongside the curtains rather than approved after them. The
old order introduced a live spectacle in phase 3 and removed the hazards in phase 4 — a window in
which a scheduled aurora could fire over ordinary terrain.

| # | Commit | Gates owed |
|---|---|---|
| 0 | This document | — |
| 1 | `GameManager.get_total_playtime_seconds()` extracted; `FrozenLakeDirector` calls it | `check.sh` |
| 2 | `aurora.gdshader` + `AuroraSky` + wash + camera override, all behind one `debug_force_aurora` knob **registered in `shipping_values_check` in this commit**. No scheduling, no terrain. Owner judges the whole composition in motion; early Android cost measured | `check.sh`, `sky_layer_check`, **owner look**, **device frame times** |
| 3 | The calm: `arm_calm()` + `is_calm_world_x()` + one line in `ObstacleSpawner` + `aurora_calm_probe.gd` **in the same commit** | **`check.sh`, `aurora_calm_probe`, freeze-search, freeze-replay, floor-flicker, chasm, `lake_suppression_probe`** |
| 4 | `AuroraDirector`: clock, phases, the ramp, entry/exit contract, dark-window eligibility, two-way lake exclusion, headless skip. **Production scheduling switches on here, with the hazards already gone** | `check.sh`, `camera_shake_probe` |
| 5 | `SaveStore` v4 + next-due migration + the achievement. Integration tested against a **copy** of a real save | `check.sh` |
| 6 | Full-event validation: no-input boosted survival end to end, restart/pause/death lifecycle, final contrast with every layer present, device frame times over repeated events | everything, plus the three windowed gates |
| 7 | `CLAUDE.md` row 12, `visuals.md`, this file | all fast gates |

Phase 3 is the only one that touches anything a physics gate can see, which is why it is alone in
its commit, carries the whole physics tier, and ships its probe with the code rather than after it.

Phase 6 is not a formality. Phases 2–5 each prove one piece; only phase 6 asks the question the
feature actually promises — *can the player look away for a minute and live* — with the shader, the
wash, the camera, the calm, the powerups and the real device all present at once.

## Open, and deliberately not decided yet

- **Fill rate on a real phone.** This is the one thing that could genuinely hurt the game rather
  than merely look wrong, and it cannot be answered from a desktop. Budget: no screen-texture read,
  ≤3 noise octaves, no loop above 8 iterations, curtain rect confined to the sky band. **Measure
  on the owner's Android device during phase 2** — before the feature has anything else built on
  top of it, and **again in phase 6 with the complete event**: curtains, wash, snow, pickups and a
  moving camera together, over repeated events, at real device resolution. The four-layer overdraw
  convention is a useful rule of thumb and **not a frame-time measurement**; treat it as a budget
  to check against, not as evidence. If it misses, the fallbacks in order are fewer curtains, then
  coarser detail, then a lower-resolution effect buffer.
- **Whether the curtains want a shader at all.** The case for one is in "Why a third shader" and it
  is the right first choice — but it is a prototype decision, not a proof. If phase 2 measures
  badly on device, authored ribbon layers are a real alternative and the reasoning against them
  (`flight_trail.gd`'s discrete elements reading as tally marks) is evidence about *trails*, not a
  law about sprites. Revisit rather than defend.
- **Judging the look needs motion, not a screenshot.** Ray shimmer, fold coherence and any temporal
  discontinuity are invisible in a still frame, and "moves pixels" is a floor, not a verdict. Watch
  a complete minute: soft-but-distinct lower edges, folds that read as one surface, smooth rays,
  multiple hues with no white clipping, and an entry and exit that feel intended.
- **Ambient audio.** There is no lake sound either, and the SFX pool is five one-shots on a 6-voice
  pool with no music bed. An aurora is the strongest argument the project has for ambience, and it
  needs an asset that does not exist. Out of scope; worth raising after the visual lands.
- **Whether "waits for a dark biome" is too rare in play.** Only playtesting answers it. The
  fallback is already designed above (a sky-channel override handed through
  `BiomeDirector.push_palette`), so this is a known road, not a redesign.
- **Whether the calm should also suppress the powerup spawner.** Currently no. A speed boost during
  an aurora is either a great moment or a thing that rushes you through it; the owner should watch
  one before deciding.
