# Aura — architecture & code quality audit (2026-08-03)

Review only. No code was changed. Scope: every `.gd` and `.tscn` in the project, plus
`project.godot` and `docs/`.

Confidence is marked per finding:
**[verified]** = read directly in the source; **[likely]** = strong inference from the
code but not run/measured; **[assumption]** = my judgement call, argue with it.

---

## 0. The short version

This is a well-above-average hobby-scale Godot codebase. The physics and terrain work is
genuinely rigorous — measured, documented, with negative results recorded so nobody
re-tries them. That's rarer than it should be.

The problems are almost entirely on the *other* side of the project: the shipping build
carries a heavy per-frame debug tax, several node-lifetime calls are the unsafe variant,
Android configuration is effectively unset, and a lot of correctness rests on scene-tree
ordering and `_ready()` timing that is documented in comments but enforced nowhere.

The single most valuable thing you could do before adding audio is **cut the per-frame
debug instrumentation and the per-frame terrain re-sampling**. Those two together are
probably the bulk of your CPU budget on a mid-range phone, and neither buys you anything
during normal play.

---

## 1. Organization

### What's good

- **Folder layout is clean and consistent.** `scripts/<domain>/` mirrors
  `scenes/<domain>/`, one script per node type, no dumping ground. Nothing is misfiled.
- **Non-node logic is correctly `RefCounted`,** not autoloads and not nodes:
  `SpeedManager`, `SaveStore`, `WorldRebaser`, `InputSetup`. `WorldRebaser` being
  `static` and stateless is exactly right for something a headless probe needs to reason
  about.
- **Exactly one autoload,** and the reasoning for why the exception is safe is written
  down in the file itself. `GameServices.resolve()` instead of the global identifier is
  an unusual discipline and it's correct.
- **The pickup/obstacle scripts are appropriately tiny** (21–25 lines) and all three
  share the same "guard on group, deferred-disable monitoring, free" shape.

### God classes / files doing too much

**`scripts/main.gd` (245 lines) — the clearest violation.** [verified] `Main` is
simultaneously:

1. the scene root,
2. the camera controller (follow filter, lead term, scroll-rate EMA),
3. the world-rebase applier,
4. the touch input router,
5. the HUD clock owner (`elapsed_time`, `timer_label`),
6. the stuck-event display.

The camera is ~60% of the file and has nothing to do with the other five. It has three
tuning vars, its own EMA state, and a rebase-correction obligation. It wants to be a
`CameraController` node (or a script on `Camera2D`) that reads player position — which
would also mean the camera-shake probe could instantiate it in isolation instead of
booting the whole game.

**`scripts/terrain/terrain_generator.gd` (655 lines).** [verified] Four separable
concerns in one file: (a) the seeded segment *model* — hashing, weights, selection,
spec-building, baseline chaining; (b) the segment *cache* — a bidirectional sparse cache
with binary search; (c) chunk *lifecycle* — spawn/despawn windowing; (d) chunk *geometry*
— sampling, `ConcavePolygonShape2D` construction, fill polygon, colouring.

(a) and (b) are pure and testable without a scene tree. (c) and (d) need nodes. Splitting
along that line would let the terrain-shape gate run against a plain object instead of
instantiating `main.tscn`. Not urgent — the file is well organised internally, with one
dispatch point (`build_segment_spec`) — but it will keep growing.

**`scripts/player/player.gd` (606 lines) — roughly 55% of it is debug instrumentation.**
[verified] Count: 4 debug `@export`s, 3 debug signals, ~14 debug member vars, and 8 of
the 24 functions exist only for probes (`setup_debug_state_label`,
`update_debug_state_label`, `get_current_terrain_segment_label`,
`get_terrain_segment_label_at_x`, `get_floor_collision_text`, `get_floor_collision_data`,
`get_terrain_chunk_index_at_x`, `record_freeze_repro_frame`). The actual movement model
is about 120 lines and is clear. The instrumentation isn't wrong to exist, but it's
interleaved with gameplay rather than separated, and it *runs in the shipping build*
(see §5).

### Responsibilities in the wrong place

- **`Player` writes into the HUD.** [verified] `setup_debug_state_label()` reaches
  `../CanvasLayer` and `add_child`s a `Label`. A `CharacterBody2D` should not be
  creating UI in a sibling node's subtree. Combined with the hardcoded
  `../TerrainGenerator` lookup, `player.tscn` is not independently instantiable — it
  only works as a child of this specific `main.tscn` shape.
- **`GameManager` reaches up into `Main`** for `elapsed_time` and
  `format_elapsed_time()`. [verified] Minor, but it means the run clock lives in the
  scene root and the score lives in the manager.
- **The run clock exists twice.** [verified] `Main.elapsed_time` (HUD + death screen)
  and `SpeedManager.elapsed_time` (obstacle + powerup schedules) are two independent
  accumulations of the same physics delta, started on different frames. They will differ
  by at least one frame, and any probe that pins `current_speed` desyncs them further.
  One of them should be the source of truth.

---

## 2. Architecture

### What's holding up well

- **`GameManager.set_state()` as the sole owner of `get_tree().paused` and screen
  visibility is the right call** and is actually respected — I grepped; nothing else in
  `scripts/` (excluding `debug/`) touches `paused` except `_on_restart_pressed`, which
  has a documented reason. [verified]
- **The `debug_*` opt-out pattern as plain (non-`@export`) vars** is a good answer to a
  real bug you already got burned by.
- **Seeded, pure-function world generation** with per-system hash salts is the right
  foundation for an endless runner. `get_terrain_height` being pure in
  `(session_seed, world_x)` is what makes the whole replay-by-seed workflow possible.
- **Spawners as children of `TerrainGenerator` so rebasing carries them for free** is
  genuinely elegant.

### Where the design will bite you

**a) Correctness depends on undeclared scene-tree ordering.** [verified]
`main.gd:154` says "Runs before Player/TerrainGenerator (tree order), so this sees the
fully settled state of the previous physics frame." That is true *only because* `Main` is
the root and `Player` precedes `TerrainGenerator` in `main.tscn`. Reordering two lines in
a `.tscn` — something an editor drag does silently — changes rebase timing, camera lag by
one frame, and whether `ObstacleSpawner` reads this frame's or last frame's
`elapsed_time`. There is no assert, no `process_priority`, nothing. This is the same class
of failure as the `world_rebase_enabled` serialization bug: invisible in the diff,
expensive to find. **[assumption]** Setting explicit `process_physics_priority` on the
four nodes that care would make the dependency real instead of incidental.

**b) `_ready()` ordering is handled three different ways.** [verified]
- `CoinSpawner`: `has_initialized_coin_groups` flag, deferred to first `_physics_process`.
- `PowerupSpawner`: `has_initialized_schedule` flag, same pattern.
- `ObstacleSpawner`: **no flag at all.** It's correct only by accident — `next_cluster_time`
  starts at the constant `20.0`, and the first hash draw happens inside `spawn_cluster()`
  at t≥20s, by which point `session_seed` is set. If anyone ever moves cluster 0's
  interval draw into initialization (the obvious refactor), the seed-0 bug you already
  shipped in `PowerupSpawner` comes straight back, in a system where it's much harder to
  notice.

**c) `GameManager._ready()` is a chain of eight `push_error(); return` gates, and the
failure mode is silent, not loud.** [verified] If any of them fires, `set_state()` at
line 133 never runs. That leaves `get_tree().paused` at `false` and every screen at its
`.tscn` default — which for `StartScreen` is `visible = true`. Result: a fully running
game underneath an un-dismissable dark overlay, with an error in the log you may not be
watching. An early `set_state(State.START)` (or a hard `assert`) would fail loudly
instead.

**d) `Main._input` calls into `Player` directly.** [verified] Pragmatically justified —
the comment block documents real on-device measurement, and I'd keep the behaviour. But
the *shape* is that the scene root now knows about the player's jump buffer. When you add
a second input action (crouch, trick, whatever), this becomes a switchboard. A small
`InputRouter` node emitting `jump_requested` would keep the same measured behaviour with
a seam.

**e) Four near-identical copies of the spawn/despawn windowing algorithm.** [verified]
`TerrainGenerator._physics_process`, `CoinSpawner._physics_process`, and
`BackgroundGenerator._physics_process` are the same 12 lines with different nouns;
`ObstacleSpawner` and `PowerupSpawner` are a second near-identical pair (time-scheduled
spawn + `for i in range(size-1, -1, -1)` despawn). `initialize_chunks` and
`initialize_coin_groups` are the same function twice. Any fix to the windowing logic has
to be applied 3–5 times, and there's nothing making that obvious.

**f) The hash function is copy-pasted four times** with different salt constants.
[verified] The *design* (independent streams off one seed) is right; the duplication is
the problem. Four identical `xor/shift/mul/shift` bodies that must stay in sync.

**g) Unbounded caches.** [verified] `segment_start_x_cache`, `segment_length_cache`,
`segment_baseline_cache` and `segment_spec_cache` grow monotonically and are never
pruned. Segments are 480–960px, so a run reaching the `world_x ≈ 1,166,358` you recorded
in the freeze notes holds roughly 2,000 entries across four dictionaries, one of which
stores a `Dictionary` per segment. Not a crisis, but it's an endless runner — "runs
forever" is the product.

---

## 3. Bugs

Ordered roughly by how much I'd worry.

### B1. `free()` instead of `queue_free()` on collision objects, inside `_physics_process` — [verified], **fix this**

Five sites:

| File | Line | Object freed |
|---|---|---|
| `terrain_generator.gd` | 188 | `StaticBody2D` with a `ConcavePolygonShape2D` |
| `coin_spawner.gd` | 118 | `Node2D` containing live `Area2D` children |
| `obstacle_spawner.gd` | 121 | `Area2D` |
| `powerup_spawner.gd` | 129 | `Area2D` |
| `background_generator.gd` | 88 | `ColorRect` (harmless — no physics) |

All four physics-bearing ones run inside `_physics_process`, i.e. while the physics server
is mid-step. Godot's documented rule is to use `queue_free()` for exactly this case;
synchronously destroying a `CollisionObject2D` during a physics callback is the classic
source of "Condition ... is true" spam and intermittent crashes. **[likely]** you haven't
seen it because chunks despawn two chunks behind the player and obstacles 1500px behind,
so nothing being freed is currently in contact. That's a distance margin, not a guarantee
— and it's the kind of bug that shows up on device under load and not on desktop.

### B2. `ObstacleSpawner._physics_process` dereferences `player` with no null guard — [verified]

`obstacle_spawner.gd:109` does `player.speed_manager.elapsed_time` with no guard.
`PowerupSpawner` has an explicit guard at line 96 with a comment saying exactly why:
`set_physics_process(false)` from `_ready()` is documented in this project as *not
reliably* suppressing `_physics_process` in headless runs. `ObstacleSpawner._ready()`
relies on precisely that unreliable call. By the project's own documented rule, this one
is missing its guard. It would be a hard crash, not a degradation.

### B3. No Android lifecycle handling at all — [verified], mobile-only

There is no `_notification()` anywhere in `scripts/` (grepped). Consequences on device:

- **Back button quits the app mid-run.** Godot's `quit_on_go_back` defaults to true and
  `project.godot` doesn't override it. Score is lost, no confirm, no pause. Users will
  read this as a crash.
- **No auto-pause on focus loss.** A notification, an incoming call, or the recents
  switcher leaves the game in `PLAYING`. On resume, behaviour depends on how the OS and
  Godot handled the suspend — at best a jarring resume, at worst a large accumulated
  delta.
- **Nothing is saved on suspend.** Android can kill a backgrounded app without further
  callbacks.

Desktop testing cannot surface any of this.

### B4. `project.godot` has no viewport size and no orientation — [verified], mobile-only

> **RESOLVED.** Orientation was pinned to landscape earlier; the base viewport was pinned to
> **1152×648** on 2026-08-13, with `aspect` deliberately left `"expand"`. Reasoning, the
> per-device table and the raster-art authoring rule it unlocks are in
> `docs/development/visuals.md`, "Base viewport size". `export_presets.cfg` is **still
> gitignored** — that half of this item is open.
>
> **One claim below is wrong and worth correcting**, since this file is the running debt list.
> "A 20:9 phone sees meaningfully further ahead than a 4:3 tablet" is only half right. Under
> `expand`, `scale = min(window.x/base.x, window.y/base.y)` and the viewport is `window/scale`,
> so **the base is a minimum in both axes** — the tablet sees the *same* width and extra
> height (1152×864), not less width. The spread is one-sided: baseline everywhere, +25%
> forward view on tall phones. Real, bounded, and in the forgiving direction. Equalising it
> means an aspect-compensated `Camera2D.zoom`, which is still open.

```
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
```
…with **no** `window/size/viewport_width`/`viewport_height` and **no**
`display/window/handheld/orientation`.

Two consequences:

- **The base resolution is the engine default (1152×648), which is not what the game is
  designed around.** Your constants — `ground_y = 192`, player spawn `(64,136)`, camera
  at `y=136`, chunk width 512 — read like a much smaller design resolution. Whatever the
  intent, it is currently implicit in an engine default rather than declared.
- **`aspect = expand` + no declared base size means the visible world width varies with
  device aspect ratio.** A 20:9 phone sees meaningfully further ahead than a 4:3 tablet.
  On an auto-runner where the only skill is reaction time, that is a *difficulty*
  difference, not a cosmetic one. Your obstacle spacing constants
  (`SPAWN_LOOKAHEAD_WORLD_X = 800`, `CLUSTER_TIGHT_GAP = 260`) were tuned against one
  particular field of view.
- **Orientation is unset**, so Android will use the manifest default. For a side-scroller
  this needs to be pinned to landscape (or sensor-landscape).

Related: **`export_presets.cfg` is gitignored.** [verified] Every piece of Android
configuration — orientation, permissions, min SDK, signing, architectures — exists only
on your machine and is one `rm -rf` from gone. I understand not wanting keystore paths in
git, but the presets file is the *only* record of how the APK is built.

### B5. Physics tick rate is not pinned in `project.godot` — [verified]

`CLAUDE.md` warns: *"Some terrain constants derive from `1.0/physics_ticks_per_second` —
changing the tick rate silently changes level geometry."* But `project.godot` has no
`physics/common/physics_ticks_per_second` line at all — you're relying on the engine
default being 60. The exact value the docs call load-bearing is the one value not written
down anywhere the engine reads. Same for `physics/common/physics_interpolation` (docs say
OFF; it's absent, i.e. default). Pin both explicitly.

### B6. The save file is rewritten on every slider tick — [verified], mobile-relevant

`music_slider.value_changed` → `GameServices.set_music_volume()` → `save_store.save_to_disk()`,
which does a full `FileAccess.open(WRITE)` + `JSON.stringify` + `store_string`. With
`step = 0.05` on a 0–1 slider, a single drag across the bar fires up to 20 writes; a
finger dragging back and forth fires many more. On Android that's synchronous flash I/O
on the main thread during a menu interaction. Save on `drag_ended` / on unpause instead.

Minor, same file: `save_to_disk()` never calls `flush()` or `close()`. It works (the
`FileAccess` `RefCounted` closes on scope exit), but it's implicit, and on a platform that
can kill the process at any moment I'd make it explicit.

### B7. Touch input edge cases — [verified], mobile-only

- **Multi-touch is unfiltered.** `Main._input` buffers a jump for *every*
  `InputEventScreenTouch` with `pressed == true`, regardless of `event.index`. Two
  fingers = two `buffer_jump()` calls. Currently idempotent (both just set the same
  timer), so it's latent rather than active — but the moment jump becomes hold-sensitive
  or a second gesture is added, it's a real bug.
- **No `index` tracking for release,** so any future hold/charge mechanic has nothing to
  build on.
- **`is_pause_button_press` compares raw `event.position` against
  `pause_button.get_global_rect()`.** [likely] Correct *today* only because the
  `CanvasLayer` has an identity transform. Add any `CanvasLayer.offset`/`scale`/`follow_viewport`
  and the hit test silently drifts off the button while still returning plausible
  results. Going through the control's own transform would be robust.
- **Both input paths can fire for one tap on Android.** `emulate_mouse_from_touch`
  defaults on, `InputSetup` binds left-click to `ui_accept`, *and* `Main._input` handles
  the touch directly. Your measurements say the `ui_accept` edge never lands on device;
  if that changes across a Godot version or a device, you get double delivery. Harmless
  now, worth a comment noting it's load-bearing.

### B8. Obstacles are on collision layer 1 for no reason — [verified]

`obstacle.tscn` sets `collision_layer = 1` (coins and powerups correctly use layer 2).
Nothing benefits from it, and it means obstacles show up in any future layer-1 query,
raycast, or shapecast. Combined with `collision_mask = 1`, every terrain chunk that
overlaps an obstacle fires `body_entered` — handled by the group guard, but it's needless
per-frame signal traffic in the region the player is actually in.

### B9. `ensure_segment_cache_for_world_x` has no sanity bound — [verified], low probability

```gdscript
while world_x >= get_cached_segment_end_x(highest_cached_segment_index):
    cache_next_segment()
```
If `world_x` is ever NaN, `inf`, or absurdly large (a physics blowup, a bad probe
argument, a future "teleport" feature), this is an unbounded loop allocating a dictionary
entry per iteration — a hang, not an error. A cap that `push_error`s after N iterations
would convert a freeze into a diagnosable failure. **[assumption]** low priority, but the
failure mode is the worst kind.

### B10. Correlated hash draws in the forced-non-flat path — [verified], cosmetic

`get_non_flat_segment_selection` and `get_medium_mix_segment_type` both derive from
`get_segment_hash(i) >> 8`. When the "no two flats in a row" rule forces a non-flat pick
that lands on the medium mix, the hill-vs-valley choice is perfectly determined by the
same value that chose the mix. I worked the arithmetic: because the non-flat total weight
(84) is even, the parity stays 50/50 in aggregate, so **there is no distribution bug**.
It's a latent coupling, not a live defect — but the two decisions are supposed to be
independent draws and aren't. Changing any weight to make the total odd would turn this
into a real bias.

### B11. Dead / vestigial state — [verified], cosmetic

- `Main.total_world_rebase_shift` is accumulated and never read.
- `initialize_chunks()` and `initialize_segments()` both assign `next_*_index` twice; the
  first assignment is dead.
- `get_chunk_surface_sample_world_xs(..., include_segment_boundaries)` — both call sites
  pass `true`. Dead parameter.
- `TerrainGenerator._ready` uses `get_node()` (which errors) where every other resolver in
  the project uses `get_node_or_null()`, then null-checks anyway.

---

## 4. Headless harnesses

The harness discipline is good and `docs/development/debugging.md` is one of the better
docs in the project. Three specific gaps:

**H1. `camera_shake_probe.gd` measures a game with the debug instrumentation still on.**
[verified] It sets `require_start_screen`, `debug_spawning_disabled` ×2, and the camera
knobs — but it never sets `player.DEBUG_SHOW_PLAYER_STATE = false` or
`DEBUG_LOG_FREEZE_REPRO = false`, which `freeze_search.gd`, `floor_flicker_probe.gd` and
`terrain_invariant_check.gd` all do. So every measured frame also builds ~14 formatted
strings, runs `get_floor_collision_data()` twice, and does two terrain segment lookups.
For a probe whose entire subject is *frame-to-frame timing noise*, that's a fourth
measurement trap to add to the three the docs already list. **[likely]** it doesn't change
the conclusions (the effect is per-frame constant work, not jitter), but it should be
turned off for the same reason the powerup flag was added.

**H2. The docs table overstates coverage.** [verified]
`debugging.md` lists four flags and says "the existing ones in `scripts/debug/` already
have them." Only three files reference `world_rebase_enabled` at all
(`freeze_search`, `freeze_replay_runner`, `stall_recovery_probe`). `camera_shake_probe`
and `floor_flicker_probe` don't set it — behaviourally fine, since the default is `true`,
but the doc claims a guarantee the code doesn't provide, and that's how the original
regression happened.

**H3. The `debug_spawning_disabled` workaround is a symptom, not a fix.** [verified]
Three separate files carry comments saying `set_physics_process(false)` "does not
reliably suppress `_physics_process` in headless harness runs (verified:
`is_physics_processing()` reported false while `_physics_process` kept firing)." That
description is unusual enough that I'd treat the diagnosis as unresolved rather than
settled — it's more consistent with the node being re-enabled, the flag being set before
the node enters the tree, or `set_physics_process` racing `add_child`, than with the
engine ignoring the call. **[assumption]** Worth 30 minutes to pin down, because the same
belief is now cited as justification in three places and one archived probe.

**H4. 18 archived one-offs in the same directory as the 5 live gates.** `CLAUDE.md` warns
about this and `model_validation_dump.gd` still calls live API (`get_segment_type`,
`get_segment_tier`, `is_mega_drop_segment`) so it at least still compiles. Moving the
archived ones to `scripts/debug/archive/` would make "is this a gate?" answerable from
the path instead of from a doc.

---

## 5. Performance (Android)

Two findings dominate; everything else is noise next to them.

### P1. The shipping build runs full debug instrumentation every physics frame — [verified]

`player.gd:42–44` ship as `true`. Per physics frame, at 60Hz, in the shipping build:

- `update_debug_state_label()` — `is_on_floor()`, `get_floor_normal()`,
  `get_slide_collision_count()`, **`get_floor_collision_data()`** (loops all slide
  collisions, dot-products each), **`get_terrain_segment_label_at_x()`** (cache-ensure +
  binary search + dict lookups), and ~10 `%`-format string allocations concatenated.
- `record_freeze_repro_frame()` — **a second** `get_floor_collision_data()`, **a second**
  `get_terrain_segment_label_at_x()`, an 8-field formatted string, plus
  `Array.append` + `pop_front` on a 20-element `Array[String]`.

That's roughly **25+ transient String allocations and 2 full floor-collision analyses per
frame, 3,600 allocations/second**, none of which anyone will ever look at in a shipped
build. GDScript strings are refcounted heap objects; this is the allocation profile that
produces intermittent stutter on mid-range Android. **[likely]** — I haven't profiled it,
but the shape is unambiguous.

`DEBUG_ALLOW_MANUAL_SPEED_CONTROL = true` also ships, meaning arrow keys change speed. No
effect on phone, but it's a live cheat on any desktop build.

### P2. `get_collision_chord_slope_angle()` rebuilds a whole chunk's sample array every frame — [verified]

Called once per physics frame from `Player.get_slope_tangent()`. Each call:

1. `get_chunk_surface_sample_world_xs(chunk_start, chunk_end, 32, true)` — allocates a
   fresh `Array[float]`, appends 33 samples, each through `add_unique_sample_world_x`,
   which **linearly scans the array it's building** → ~545 float comparisons.
2. `add_segment_boundary_sample_world_xs` → 2 cache-ensures + 2 binary searches.
3. `sort()` on 33+ floats.
4. A linear scan to find the bracketing pair.
5. Two `get_terrain_height()` calls, each doing cache-ensure + binary search + dict lookups.

Every frame. To retrieve **a value that is already baked into the chunk's
`ConcavePolygonShape2D`** — the comment even says it "reuses the identical sample-point
construction `build_chunk_surface` feeds into `ConcavePolygonShape2D`, so the two can't
disagree." Caching the per-chunk sample array at chunk-build time and indexing into it
would make this an O(1) lookup with zero allocation and, by construction, *more* tightly
coupled to the collision shape than it is now. **[assumption]** This is the single
highest-value optimisation available and it's behaviour-preserving.

### P3. Chunk construction cost — [verified], lower priority

At `MAX_SPEED` (750px/s) with 512px chunks, a chunk is built roughly every 0.68s.
`build_chunk_surface` does 33 + 33 samples, each a full `get_terrain_height()`, plus two
`get_chunk_surface_sample_world_xs()` calls with the same O(n²) dedup, plus a
`ConcavePolygonShape2D` allocation and physics-server registration. **[likely]** this is
your visible frame-spike source on Android once P1 and P2 are gone. Amortising chunk
building across frames, or pooling chunks instead of free/instantiate, would smooth it.

### P4. Smaller items

- **Node churn instead of pooling.** [verified] Chunks, coin groups, coins, obstacles and
  powerups are all instantiate-and-free. Steady-state that's a few nodes/second of
  allocation, plus `ConcavePolygonShape2D` per chunk. Pooling chunks in particular is
  cheap to add.
- **`PowerupManager` is the only system on `_process`** rather than `_physics_process`.
  [verified] Real-time-correct either way, but it means boost expiry can land
  mid-physics-step and it's the one clock in the game not tied to the physics tick.
  Inconsistent.
- **The two full-screen `Overlay` ColorRects** (start + pause) are always in the tree.
  Hidden `Control`s don't draw, so this is fine — noting it only because on the mobile
  renderer full-screen alpha rects are the usual overdraw suspect if you add more.
- **Unbounded segment caches** (see §2g) — memory, not CPU, but it's monotonic.

---

## 6. Maintainability

### Code smells worth naming

1. **Comment-to-code ratio is inverted in places.** `main.gd` has ~110 lines of comment to
   ~135 of code; `player.gd:247–295` is a 48-line comment on a 2-line function. The
   *content* is valuable — measured results and rejected approaches — but it belongs in
   `docs/research/`, which is where `CLAUDE.md` already says it goes. Right now the same
   investigation is described in both places and the two can drift.
2. **"Debug" naming for shipped behaviour.** `debug_weight_*` are the real terrain
   weights; `debug_replay_session_seed` is the real seed override. Prefixing production
   knobs with `debug_` makes it unclear what's safe to strip.
3. **`@export` on the Player debug flags contradicts the project's own hardest-won rule.**
   [verified] `Main.world_rebase_enabled`, `GameManager.require_start_screen`, and both
   spawners' `debug_spawning_disabled` are all deliberately *not* `@export`ed, with long
   comments explaining that `main.tscn` silently serialising an export is how the freeze
   regressed for weeks. `Player`'s four debug flags **are** `@export`ed. I checked both
   `.tscn` files — they are not currently serialised — but one Inspector click on
   `player.tscn` bakes them in permanently, and the affected flags control whether the
   game does 3,600 string allocations per second. Same trap, same file family, opposite
   decision.
4. **Magic invariants held only by comment.** The player spawn `(64,136) = 192 - 32 - 24`
   relationship is documented in `CLAUDE.md` and enforced nowhere. `OBSTACLE_HALF_HEIGHT
   = 16.0` must match `obstacle.tscn`'s `RectangleShape2D` and is enforced nowhere.
   `capsule_half_height` at least reads the shape at runtime — that's the pattern the
   other two want.
5. **Five different node-resolution styles**: `@onready get_node_or_null` with a literal
   path (Player), `@export NodePath` + `get_node_or_null` (most systems), `@export
   NodePath` + `get_node` (TerrainGenerator), `get_parent() as Main` (GameManager), and
   `/root/Main/Player` absolute fallback (BackgroundGenerator). Pick one.

### What would make future changes safer

- **Explicit process priorities** on Main / Player / TerrainGenerator / spawners, so the
  ordering the comments rely on is declared rather than incidental. (Addresses §2a.)
- **A terrain-model unit gate that doesn't instantiate `main.tscn`.** The segment model
  and cache are pure; testing them against a plain object would be fast enough to run on
  every change, and would have caught the seed-0 spawner bug.
- **A pre-release checklist** that flips the four `DEBUG_*` flags off — or better, derive
  them from `OS.is_debug_build()` so shipping can't forget.
- **A "layout invariants" check** in the terrain gate: assert the player spawn matches
  `ground_y + surface_y_offset - capsule_half_height`, and that `OBSTACLE_HALF_HEIGHT`
  matches the obstacle scene's shape.

---

## 7. Verdict

### Already good — keep doing this

- Measured, documented physics work with **negative results recorded**. The
  "ALSO TRIED and reverted, do not retry without new evidence" blocks in
  `get_slope_tangent()` are worth more than most test suites.
- Single-autoload discipline and the `GameServices.resolve()` pattern.
- `set_state()` as the sole owner of pause + screen visibility.
- Pure, seeded generation with per-system hash salts.
- Spawners parented under `TerrainGenerator` so rebasing is free.
- The `docs/` split, and `CLAUDE.md` staying a map rather than a manual.
- Honest known-issues list, including "SEGMENT CUT, not fixed."

### Concerning

- The shipping build is instrumented like a probe (§P1).
- Per-frame recomputation of static per-chunk geometry (§P2).
- Correctness resting on undeclared scene-tree order and `_ready()` timing (§2a, §2b).
- Android is genuinely unconfigured — orientation, base resolution, lifecycle, and the
  export preset isn't even in git (§B3, §B4).
- `Main` and `TerrainGenerator` are each carrying 3–4 concerns and still growing.

### Fix now — before audio

1. **`free()` → `queue_free()`** at the four physics-bearing sites (§B1). One-line fixes,
   removes a whole class of device-only crash.
2. **Turn off the four `Player.DEBUG_*` flags for real builds**, ideally via
   `OS.is_debug_build()`, and drop the `@export` while you're there (§P1, §6.3).
3. **Cache the per-chunk collision sample array** so `get_collision_chord_slope_angle()`
   stops rebuilding it every frame (§P2).
4. **Pin `project.godot`**: `physics_ticks_per_second`, base viewport size, and handheld
   orientation (§B4, §B5).
5. **Add the `player`/`terrain_generator` null guard to `ObstacleSpawner`** (§B2).
6. **Un-gitignore `export_presets.cfg`** (or commit a sanitised copy) so the Android build
   config exists somewhere other than your laptop (§B4).
7. **Debounce the volume-slider save** to `drag_ended` (§B6).

Items 1, 2, 5 and 7 are each under ten lines. Item 4 is config. Only item 3 is real work.

### Fix soon — before the codebase grows further

- Android lifecycle: back button → pause, focus-out → pause, save on suspend (§B3).
- Explicit process priorities (§2a).
- `ObstacleSpawner`'s missing init-deferral flag, before someone refactors it into the
  seed-0 bug (§2b).
- `GameManager._ready()` failing loudly instead of into a half-configured state (§2c).
- Extract the camera out of `Main` (§1).
- Move archived probes to `scripts/debug/archive/` (§H4).
- Fix `camera_shake_probe`'s missing debug-flag opt-out and the `debugging.md` coverage
  claim (§H1, §H2).

### Can wait

- Splitting `terrain_generator.gd` into model / cache / lifecycle / geometry.
- De-duplicating the four spawn-window implementations and the four hash functions.
- Segment cache pruning.
- Node pooling for chunks and pickups.
- Moving the long investigation comments into `docs/research/`.
- Obstacle collision layer 1 → 2 (§B8).
- The dead vars and parameters in §B11.
- The `hash >> 8` coupling in §B10 — but re-check it if you ever change a segment weight.
