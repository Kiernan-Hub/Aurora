# Aurora borealis — the plan and the state

**This is the feature the game is named after.** Build-order #12.

**RECONCILED 2026-09-09 from two branches that had each planned and part-built it.** They agreed
on more than they disagreed, but they disagreed on things that matter, and the merge resolved
every one by owner decision rather than by picking a side. Where this file states a decision, it
is settled; where it says a route is open, it genuinely is.

| | State |
|---|---|
| The director, its clock and its phase machine | **BUILT** |
| The ribbons — three code-built curtains in `SkyBackdrop` | **BUILT**, not yet seen in the engine |
| The schedule — stored deadline, 30 min, night gate | **BUILT**, reconciled 2026-09-09 |
| The calm — no obstacles, no chasms | **IN SCOPE, NOT BUILT.** The live work |
| The wash, and the ground catching the light | **IN SCOPE, NOT BUILT** |
| The camera pull-back | Planned, not built |
| The achievement | Two edits, not written |

## What it is

A rare spectacle on the cumulative-playtime clock — **every 30 minutes**, against the lake's 20 —
that turns about a minute of ordinary play into something to look up at. Everything rides one
ramp, `AuroraDirector.get_aurora_blend()`.

It is still `GameManager.State.PLAYING` throughout, exactly as a lake is. Nothing here goes near
`get_tree().paused` or a screen's visibility; `set_state()` remains the only thing allowed to.

### Why it can't just be colours in the sky

The parallax ridges are **opaque** and their tops sit at y 0.21–0.45 (`visuals.md`, "There has to
BE a sky"). A strictly sky-only aurora is therefore confined to the top ~40% of the frame with a
hard mountain edge under it, and the other 60% of the screen carries on exactly as before. That
reads as a nice sky, not as an event.

**This is the argument for the calm and the wash**, and it is why the sky-only version built today
is a first phase rather than the finished feature. The owner's framing on 2026-09-09 was *"I want
everything to turn bright and beautiful"* — the light reaching the whole frame, and the hazards
standing down so there is time to look at it.

## Decisions

Consolidated from both branches. Do not re-litigate these without the owner.

| Question | Decision | When |
|---|---|---|
| Interval | **30 min** of cumulative playtime | 2026-09-09 |
| Schedule shape | **A stored deadline**, never `count × interval` | 2026-09-09 |
| Which sky | **Night only**, blended `star_density` >= 0.8 | 2026-09-07 |
| Duration | 45 s hold + two 8 s fades = **61 s** | 2026-09-07, proposed not measured |
| Forced flat segment | **No.** Terrain keeps rolling | 2026-09-07 |
| Ribbon rendering | **Code-built textures, additive `CanvasItemMaterial`.** Not a third shader | 2026-09-07 |
| Colour identity | **Fixed** green/violet, never per-biome | 2026-09-07 |
| Hazards | **Removed for the duration** — no obstacles, no chasms | 2026-09-09 |
| Reach of the light | **Sky + background + the ground.** Never coins, obstacles or the player | 2026-09-09 |

### What the reconciliation changed, and why

Both branches were wrong about something. Recorded because each was load-bearing.

| Was | Is | Why it mattered |
|---|---|---|
| `(aurora_count + 1) × INTERVAL`, the device `frozen_lake_count` uses | A **stored deadline**, `next_aurora_due_seconds` | The lake's device is only safe because its count and the playtime clock were born together at v3. The aurora lands in saves already holding hours, so a multiple is retroactively owed many times over and pays out **back to back** until the count catches up — the rarity of the headline feature destroyed on the first launch after the update |
| 60 minutes | **30 minutes** | Owner decision. It is not "three times the lake"; rarity comes from the night gate as much as the clock |
| Eligibility by palette identity (cycle slots 5–7) | **Blended `star_density` >= 0.8** | Simpler, already authored on all eight palettes, already blended every frame, and it excludes the crossfade shoulders for free with no second list to drift. The palette-identity design and the long argument about which slots qualify are **superseded** — ignore any older copy of this file that reasons about cycle slots |
| A third `.gdshader` for the curtains | An additive `CanvasItemMaterial` | A built-in, so the two-shader budget is untouched. Measured to work; see the ribbons below |
| "The aurora must never arm terrain" | **The calm is in scope**, and the constraint is narrower than that | The two halves of the calm are not equally risky, and one of them touches no terrain at all |

## The architectural rule this feature must not break

`CLAUDE.md`: **`get_terrain_height` must stay pure in `(session_seed, world_x)`.** It has exactly
one permitted runtime input today, `lake_segment_index`, and **`arm_lake()` is its only writer** —
write-once and write-ahead, above `highest_cached_segment_index`, so arming can only ever *extend*
the height field, never contradict a sample already taken. Chunk visuals, collision, player tilt
and the debug HUD all sample it independently, so a range that moved after a sample would make
them disagree inside a single frame.

One branch read that as **"the aurora must never arm terrain"** and built the feature sky-only
around it. That instinct is right and the rule is real. But the rule is not "never touch terrain"
— it is *"any runtime input to the height field takes the write-once, write-ahead deal."* The lake
proves the deal is takeable. What follows is that the two halves of the calm have **completely
different risk**, and they must not be built in one step.

## What is built

### The director — `scripts/systems/aurora_director.gd`

Owns **when**: the clock, the phase machine (`IDLE -> ACTIVE -> DONE`, terminal), and the one ramp.
`SkyBackdrop` owns the look and *reads* the ramp; `BiomeDirector` owns what time of day it is;
`SaveStore` owns the counters; `AchievementManager` will listen. Nothing reaches into another
system to do that system's job.

- **One aurora per run, maximum.** `DONE` is terminal, as the lake's is. Nothing is lost by it:
  the deadline only moves in `finish_aurora()`, so a deadline crossed in a run that ended early is
  still crossed and the next run is immediately due. This is also what will keep a calm band's
  terrain reservation write-once for the life of a scene.
- **Hard-skips headless as the first statement in `_ready()`.** Not an optimisation — the trigger
  reads cumulative playtime out of the developer's own `save.dat`. It is also what keeps
  `AchievementManager` safe, since that file has no headless guard of its own and says so.
- **Default `process_mode` (INHERIT)**, so an aurora freezes on every menu for free.
- `push_blend()` is **the one seam the look arrives through**. A later phase that replaces the
  curtains replaces what is behind that call and nothing else.

### The ribbons

Three curtains as `TextureRect`s in `SkyBackdrop`, between `SkyStars` and `SkyGlow`, driven only
by `apply_aurora(blend, elapsed)`. Both arguments come from the director and **neither may be
recomputed on the far side** — that is what lets `sky_backdrop.gd` keep its promise of having no
`_process` at all, which is what makes it free inside every headless gate.

**The shape was validated before it was written**, by porting the bake to Python and rendering it
against the two night palettes' real gradients. Not a substitute for the engine — it cannot see
draw order, the additive material, or `expand` on a device — but it caught two defects that would
each have cost a play session:

1. **The rays were invisible.** The first draft averaged three sines from one 9–34 range. An
   average of similar frequencies converges on a constant: the term sat near 0.81 across the whole
   width, so there was no striation at all — a smooth ribbon, which reads as fog. A *product* of
   them fails the other way and goes muddy. What works is **four octaves with amplitude falling as
   frequency rises**.
2. **It blew out to white.** Against the palettes as authored — `twilight_blue`'s `sky_top` is
   `(0.26, 0.28, 0.50)`, far brighter than assumed — **4.6% of the screen clipped to flat white**.
   The shipped weights measure peak 1.03 / 0.02% clipped, and that remainder is the hem's own core,
   where a white-hot centre is correct.

**A third finding, and it is a ceiling rather than a bug.** Under additive blending no layer can
*reduce* the sky's blue. Over these palettes (upper-sky blue 0.42–0.54) a fully saturated green is
unreachable by construction. Pulling blue out of the green's own colour moved the hem from G/B 1.26
to 1.53, which is as far as it goes; more brightness does not help, it clips. **If a greener aurora
is ever wanted the lever is the palette's blue, which is a biome change, not a sky one.**

**Why additive.** An aurora emits. Alpha-blended it can only darken toward its own colour, so a
green curtain comes out as flat paint. `BLEND_MODE_ADD` on a `CanvasItemMaterial` is a built-in,
not a `.gdshader`. The trap it introduces is exactly why the night gate exists: additive over a
bright sky blows out, so `debug_aurora_ignore_night` shows a composition the game never ships.

- **`visible = blend > 0.0`, never alpha 0.** A transparent full-screen `TextureRect` still
  rasterises every pixel it covers. At blend 0 this feature is byte-identical to not existing,
  which is what makes it incapable of moving a gate result.
- `mouse_filter = MOUSE_FILTER_IGNORE` on every rect, or they are full-screen input eaters under
  the pause button.
- The texture is baked **once** in `_ready()`, as a `PackedByteArray` handed to
  `create_from_data()` rather than per-pixel `set_pixel()` — that one was a real scene-load hitch.
  The bake is **skipped entirely under `--headless`**.

## The schedule

```
due  <=>  saved_playtime + unbanked_this_run  >=  next_aurora_due_seconds
```

**A stored deadline, not `(aurora_count + 1) × INTERVAL`.** `SaveStore.next_aurora_due_seconds`
carries the full reasoning in the place a reader will hit it.

```
unscheduled (a v3 save, or a reset):  -1.0, and -1.0 is NOT due
scheduled at _ready():                 total_playtime_seconds       + AURORA_INTERVAL_SECONDS
pushed on completion:                  get_total_playtime_seconds() + AURORA_INTERVAL_SECONDS
```

**The two clocks in those last lines differ on purpose, and getting it wrong re-creates the backlog
inside a single run.** `total_playtime_seconds` is the *banked* total, and `bank_playtime()` only
fires on a `PLAYING -> not-PLAYING` transition — so during a long uninterrupted run it is stale by
the entire run so far. Scheduling at `_ready()` from the bare field is correct precisely because it
runs at scene load with nothing unbanked yet. Scheduling on **completion** from that same bare
field, after a 40-minute unbroken session, writes a deadline already ten minutes in the past and
the next aurora fires as soon as the sky is dark again. **Test the completion path on a run with no
pause in it**, the only case that exposes it.

**`-1.0` rather than `0.0` is load-bearing.** Zero reads as "due immediately" to any `>=`
comparison, so an unscheduled save would fire on the first frame — the same bug in a new hat.
Absence therefore needs no migration and **no version bump**: a v3 file yields `-1.0` and is
scheduled at load, the same honest reading v2->v3 gave playtime itself. The clock starts now rather
than being back-dated.

**Cumulative playtime comes from `GameManager.get_total_playtime_seconds()`**, which both directors
call. It was computed independently in each of them until the reconciliation — two copies of a sum
whose wrong version (the saved total alone) silently reschedules a set piece. That helper has **no
headless guard of its own, deliberately**; the guard belongs in the callers, and its comment says
why.

### The night gate

`biome_director.get_night_amount() >= NIGHT_THRESHOLD` (0.8). The trigger is cumulative playtime;
the sky's colour is a pure function of world distance. **The two are independent**, so without this
gate the first aurora a player ever sees can arrive over `pale_morning` — which does not read as a
rare spectacle, it reads as a rendering bug.

`star_density` is already authored on all eight palettes, already blended every frame, and already
means "how much night is this": `starlit_night` 1.00, `twilight_blue` 0.85, `violet_dusk` 0.30,
`arctic_dawn` 0.28, the rest 0.00. So 0.8 is precisely the two night biomes — 2/8 of the arc,
matching the shipped night-length decision — with no second list to drift.

The cost is real and is the shape `LAKE_MIN_RUN_TIME` buys: the cadence is *"the first night biome
after 30 minutes"*, not strictly every 30. The arc is ~13.7 minutes, so night comes round within
one cycle of the deadline being crossed.

## The calm — in scope, not built

**Owner decision 2026-09-09: the hazards stand down for the duration.** This is what makes the
aurora more than a nice sky, and it is the only part that touches anything outside presentation.

### The two halves are not equally risky, and must not ship together

| | Touches `get_terrain_height`? | Cost |
|---|---|---|
| **No obstacles** | **No.** Obstacles are spawned *nodes* | One term on one line |
| **No chasms** | **Yes.** A chasm is geometry | A real decision — two routes below |

**No obstacles is nearly free.** `ObstacleSpawner` already asks
`terrain_generator.is_lake_world_x(world_x)` and skips a slot when it says yes
(`obstacle_spawner.gd:187`). The calm adds one more term to that same line. It touches the height
field not at all, and it is the larger half of what the player actually feels, since an obstacle is
the thing that kills you while you are looking up.

**Coins and powerups keep spawning.** Only the thing that can kill you is removed. A minute of free
collection while the sky does something is a reward, and suppressing all six spawners the way the
lake does would make the aurora a dead zone six times longer than the lake's.

### No chasms — two routes, and the choice is open

**Route A — a second write-once range.** `arm_calm(start_index, end_index)`, taking the identical
deal `arm_lake()` takes: the only writer of the range, indices strictly greater than
`highest_cached_segment_index`, **and every index in the range also absent from
`segment_spec_cache`** — `arm_lake()` treats that second check as defensive because the watermark
guarantees it for a single index, but `get_segment_spec()` can populate the cache beyond the
watermark without advancing it, so for a *range* it is load-bearing. Then one more early-out in
`is_chasm_segment_index()`, which is already a pure function of `segment_index` and already gated by
`debug_chasm_disabled`.

Two traps if this route is taken. **Choosing the range must not cache the terrain it is about to
change** — walking the ordinary segment getters forward would populate the spec cache for exactly
the indices the arm then wants to alter, and the arm would correctly refuse. Use a conservative
bound from the minimum legal segment length instead, `ceil(footprint / SMALL_SEGMENT_LENGTH)`, with
the recovery margin **inside** the division. And **never implement it as "no chasms while the
aurora is active"** — a time-conditioned height field is a different value depending on when you
asked, and the four independent samplers would disagree inside one frame.

**Route B — only start over a stretch that is already clear.** `is_chasm_segment_index()` is a
*pure function of `segment_index`*, so it can be **queried ahead without writing anything**. The
director looks forward across the worst-case footprint and only begins an aurora if that stretch
already contains no chasm. **Zero writers, zero purity risk, no new terrain API, and no probe needed
for the terrain half** — it cannot break `get_terrain_height` because it never touches it.

The cost is patience, and whether that cost is acceptable **is a measurement nobody has taken.**
One chasm per `CHASM_WINDOW_SEGMENT_COUNT` (56) segments, at lengths 480/640/960, is roughly one
per ~36,000 px; a 61,000 px event spans about 1.7 windows, so a naturally clear stretch needs two
adjacent windows to place their chasms near opposite ends. That happens — **how often is the whole
question**, and it decides the route. Measure it before choosing: over many seeds, the fraction of
start positions with a clear 61,000 px ahead. If clear windows are common, Route B is strictly
better and the feature never goes near the height field. If they are rare, Route A is the price.

**Do not pick by argument.** This is exactly the kind of number this project has been burned by
estimating.

### How long the calm must be

Sized from the **fastest the player can possibly be moving**, not the fastest they usually are:

```
event duration      61 s        (45 hold + two 8 s fades, as built)
worst-case speed    1000 px/s   (SPEED_BOOST_SPEED, NOT MAX_SPEED's 750)
event footprint     61,000 px
recovery margin     + one screen and change, so the first hazard is not on the fade
```

**Powerups keep spawning during an aurora**, and `SPEED_BOOST_SPEED` is 1000
(`powerup_manager.gd:26`). A band sized at `MAX_SPEED` can be outrun by a player who picks up a
boost late in the hold, who then reaches live terrain while the curtains are still up.

This is a **derived upper bound, not a prediction** — the supremum of distance over the interval.
It is not tight: a boost lasts 3 s, so 61 seconds of continuous boost is impossible and the typical
footprint is nearer 47,000 px. That slack is the point. Over-reserving costs *more calm*, which is
harmless; under-reserving costs a death during the centrepiece.

### Death is never disabled, the hazards are removed

`player.gd:147` states the constraint and it is not negotiable: `has_shield` is obstacle-only, and
`update_fall_death()` and both watchdogs stay untouched, because *a shield that swallowed
fall-death would leave the player falling forever behind the terrain* — worse than the death it
prevented. **A blanket "can't die" flag for the aurora is the same bug wearing a different name.**

With no chasms there is nothing to fall into; with no obstacles there is nothing to hit. The player
genuinely cannot die and not one line of the death path changed — the same reasoning as the lake
locking the jump *input* rather than making jumping harmless. The stall watchdogs stay live
throughout: they catch bugs, not gameplay.

## Making the light reach the whole frame

The owner's ask on 2026-09-09. Three layers, in increasing cost, and **none of them recolours a
gameplay object.**

1. **The sky** — built.
2. **The mountains and the snow: a wash.** A `ColorRect` on a `CanvasLayer` at **-45**, in front of
   the ridges (`ParallaxBackground` is -100) and `SnowDrift` (-50), and **behind every canvas item
   at layer 0**. That number is the entire safety argument: at -45 the ice, coins, obstacles and
   player are *structurally incapable* of being tinted by it, so the readability contract and
   `biome_schedule_check`'s contrast floors stay meaningful without this feature having to argue
   with either. **Do not raise it above 0.** Wanted: `MOUSE_FILTER_IGNORE`, a vertical profile
   rather than a flat veil (strongest near the horizon where light would pool), and a hard opacity
   cap so ridge-to-ridge separation survives.
3. **The ground itself: the ice blend.** `TerrainGenerator.set_lake_ice_blend()` is the working
   precedent — a single-entry blend that already lerps ice surface, depth and hue variance
   together, driven by the lake today. The aurora drives the same shape off its own ramp. The ice
   shader already carries a `gloss_strength` uniform sitting at 0, commented *"left at 0 for a
   later flat-lake biome."* **This is the lever for "the ground catches it too" — not a palette
   field, and not raising the wash layer.**

**What stays uncoloured, and this is a rule not a default:** coins, obstacles and the player.
`CLAUDE.md` — a biome may shift the two objects the player must *read*, never recolour them. The
calm removes obstacles anyway, so the live question is only coins and the player, and both stay.

**Contrast is no longer proven by the palette gates.** `biome_schedule_check` reasons about palette
*data*; the wash changes the background behind a coin without touching the coin's colour. That
readability claim has to be re-checked on final pixels with every layer present, including a player
at glide height. This is not a gate failure waiting to happen — it is a gate that will keep passing
while saying nothing about the case.

### Overdraw budget

`visuals.md` sets it at **four full-screen alpha layers at once**. Today: `SkyGlow` and `SnowDrift`.
The aurora adds the curtains and the wash, landing at four in the worst case — at the limit, not
over it, and **only while an aurora is running**, since every one of them is `visible = false`
otherwise. The lake's full-screen reflection quad would make five, which is one reason the two set
pieces should not overlap.

## The camera

Planned, not built. **The frozen lake does not zoom** — `main.gd:331 apply_lake_framing()` lerps the
camera's *target y* so the shore sits at `LAKE_HORIZON_FRACTION` (0.56). `Camera2D.zoom` is
untouched anywhere in the project. The aurora wants both, in the same shape, blended by
`get_aurora_blend()`.

**A framing lift does not lower the mountains.** Every `motion_scale` in `main.tscn` is `(x, 0)` —
vertical parallax was tried and reverted — so the ridges are **vertically screen-locked** and moving
the camera's target y slides the *terrain* down the screen while the ridgeline stays put. The lift
is still worth having as a composition effect; it just is not the "more sky" lever. **Zoom is.**
`ParallaxBackground.ignore_camera_zoom` defaults to false, so zoom scales the ridges and the
panorama too. Normally that makes zoom the riskier of the two, since base size and zoom are one
decision and only their ratio is field of view — which on an auto-runner is reaction time. **During
an aurora that objection does not apply, because there is nothing left to react to.**

Cheaper than expected: the three live readers of `camera.zoom` (`main.gd:340`,
`lake_reflection.gd:149`, `glide_coin_spawner.gd:218`) all re-read per frame, so an animated zoom
needs no invalidation anywhere.

Three things not to forget. **Glide already owns the camera** — `is_glide_vertical_follow_active`
follows a gliding player upward, and an aurora override anchored to the terrain will fight it and
can pull them off screen; **glide takes precedence**, define that rather than discovering it.
**Capture and restore the authored zoom explicitly** rather than assuming the literal in
`main.tscn`. And **the follow has smoothing lag** — blend 0 means the *target* is back, not that the
camera has arrived, so the protected band must outlast the settle, not just the fade.

`camera_shake_probe` is owed on that commit. Note it measures camera *position*, so it does not by
itself see screen motion caused by a zoom change; that half is an owner look.

## The headless contract

Every gate instantiates `main.tscn`, so all of this runs on every gate frame.

- `is_headless` computed **locally** from `DisplayServer.get_name()`, never `Services.is_headless`,
  which is assigned in `GameServices._ready()` and can still read false depending on node order.
  `snow_drift.gd` and `sfx_player.gd` both shipped that bug.
- `set_process(false)` / `set_physics_process(false)` **before** the headless return, not after.
- Every dependency `get_node_or_null` + null-guarded; a missing one is a `push_warning` and a
  disabled feature, never fatal. A missing aurora is a missing spectacle, not a broken game.
- **A parse error in any of these hangs the gates rather than failing them.** Run `check.sh`.

**Because the director hard-skips headless, no gate can arm a calm band and no terrain gate can
move.** Read that as regression isolation and nothing more. It is emphatically *not* evidence that
the aurora works — a green `freeze-search` with no band armed has not exercised one line of the
feature. It also means **no headless gate reaches the schedule at all**:
`get_total_playtime_seconds()`, the deadline and the night gate are all invisible to the fast five.
Know which claims a green run is not making.

## Proving the calm

Only if Route A is taken. Route B needs no terrain probe, because it writes no terrain — that is
most of its appeal.

**One new probe, `aurora_calm_probe.gd`,** headless, modelled on `lake_suppression_probe.gd` —
which exists for the identical reason and pins its set piece the same way. It arms a forced band,
snapshots heights and specs before and after, walks the spawners, and drives no-input traversals.

> **A BOOSTED TRAVERSAL PROVES NOTHING ON ITS OWN.** A boosting player is already immune to both
> hazards the calm removes: `obstacle.gd:37` returns early on `player.is_boosting`, and
> `player.gd:355`/`540` keep the grounded gravity-free model on over a void, so they skim straight
> across a chasm. **That test passes on a band with every chasm and obstacle still in it** — the
> "passes with the feature deleted" failure the eighteen archived probes are a monument to.
>
> So the traversal runs **twice**: **ordinary, unshielded, no boost, no input**, which is the case
> that actually asserts the terrain is safe; and **boosted**, which asserts the band is long enough
> — **assert duration coverage, not arrival.** At `t = EVENT_DURATION` the player must still be
> inside the band with the recovery margin in front of them. A probe that only checks "got to the
> end alive" passes on a band half the length it should be.
>
> The direct assertions stay regardless: no chasm segment in the range, and no obstacle **body**
> actually spawned in it. Assert on the spawned node, never on the predicate.

**This is deliberately one probe, not a matrix.** `CLAUDE.md` holds at *"twelve maintained checks,
and only twelve"*, and eighteen archived probes are evidence of what happens to gates nobody
maintains. The scheduling and save cases are better as one manual pass over a **copy** of a real
save.

## What is left

One numbered step at a time, each its own commit, stop for a "go" between them.

| # | Commit | Gates owed |
|---|---|---|
| — | Reconcile the branches | `check.sh` + project import — **DONE 2026-09-09** |
| A | **Owner sees the ribbons.** Nothing to write | **`sky_layer_check` WITHOUT `--headless`**, owner look, device frame times |
| B | **Measure the chasm-gap question**, then pick Route A or B | a throwaway measurement, not a gate |
| C | **No obstacles** — one term on `obstacle_spawner.gd:187` | `check.sh` |
| D | **No chasms**, by the chosen route (+ `aurora_calm_probe.gd` same commit if Route A) | **`check.sh`, freeze-search, freeze-replay, floor-flicker, chasm, `lake_suppression_probe`**, and the probe |
| E | **The wash** at `CanvasLayer -45` | `check.sh`, `sky_layer_check`, owner look |
| F | **The ice blend** off the aurora ramp | `check.sh`, `ice_look_capture`, owner look |
| G | **The camera** | `check.sh`, `camera_shake_probe`, owner look |
| H | **The achievement** — one `ACHIEVEMENTS` row, one `.connect()` on `aurora_finished` | `check.sh` |
| I | Full-event validation, then `CLAUDE.md` / `visuals.md` / this file | everything, plus the three windowed gates |

**A comes first and costs nothing to run.** The ribbons are written and measured but nobody has seen
them in the engine; every later step is composed against them, and judging a sky from a Python
render is not judging it.

**D is the only step a physics gate can see**, which is why it is alone in its commit and carries
the whole physics tier.

## Things that break silently

- **Never `Services.x`** — `GameServices.resolve(self)`, null-guarded. The global identifier does
  not exist under `--headless --script` even though the autoload node does.
- **Debug knobs are plain `var`, never `@export`.** An exported bool serialises into `main.tscn` and
  ships silently — the `world_rebase_enabled` regression exactly. Every new knob gets its
  `shipping_values_check` row **in the same commit**, because a plain `var` is invisible to every
  other gate.
- **The interval override must never reach disk.** It is a read-side bypass in `is_aurora_due()` for
  exactly that reason, and the two writers of the deadline ignore it. Rewriting the stored deadline
  instead would both persist a playtest cadence into a real save *and* fail to work, since a save
  scheduled hours ago is still waiting on that number.
- **`git status` after ANY engine run.** A settings save rewrites `project.godot` *and* scene files,
  dropping the pins and every comment. `shipping_values_check` text-scans `project.godot`; **scene
  files still have no such cover**, and this feature adds nodes to one. (A plain `--editor --quit`
  import measured **byte-identical** on 2026-09-09, consistent with the 2026-08-26 finding.)
- **`aurora_count` is a statistic, not the schedule.** Anything that reads it as a threshold index
  re-creates the backlog.
- **Achievement ids are save data.** Renaming one un-earns it for everyone. Pick the name once.

## Open, and deliberately not decided yet

- **The chasm-gap frequency.** Step B. It decides Route A vs B, and nothing on that half should be
  built until it is measured.
- **Fill rate on a real phone.** The one thing that could genuinely hurt the game rather than merely
  look wrong, and it cannot be answered from a desktop. Measure with the complete event — curtains,
  wash, snow, pickups, moving camera — over repeated events at device resolution.
- **The duration numbers** (45 s + 8 s) are proposed, not measured. Judge in play.
- **Whether the calm should also suppress powerups.** Currently no. A speed boost during an aurora
  is either a great moment or a thing that rushes you through it; watch one before deciding.
- **Whether "waits for night" is too rare in play.** Only playtesting answers it. The fallback is a
  sky-channel override handed through `BiomeDirector.push_palette` so the aurora could pull the sky
  toward night itself — a known road, not a redesign.
- **Ambient audio.** There is no lake sound either, and the SFX pool is five one-shots with no music
  bed. The strongest argument the project has for ambience, and it needs an asset that does not
  exist. Out of scope; worth raising after the visual lands.
