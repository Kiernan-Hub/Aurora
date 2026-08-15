# Aura — endless 2D skater (Godot 4.7, GDScript, Mobile renderer)

Alto's-Adventure-style endless downhill skater: the player auto-runs right at a speed that
ramps over time, riding an infinite, seeded, procedurally generated terrain. Gameplay art is
still placeholder `ColorRect`/`Polygon2D`.

**Priority order:** terrain stability > physics/collision correctness > game feel. Missions,
upgrades and visual polish stay deprioritized until the core loop is stable.

**Editing rules.** Inspect connected files and find the root cause before changing anything.
Prefer targeted changes; preserve existing architecture unless you propose and explain first.
`project.godot` is features `4.7` + `Mobile`, physics **60 Hz**, interpolation **OFF** — some
terrain constants derive from `1.0/physics_ticks_per_second`, so changing the tick rate
silently changes level geometry.

## Where things are documented

This file is the map; everything else is one level down, read on demand. Paths below are
under `docs/`.

| Doc | Open it when |
|---|---|
| `development/architecture.md` | Scene wiring, `GameManager`, `Services`, persistence, or adding a system |
| `development/terrain.md` | Inside the generator, chunk lifecycle, or segment shapes |
| `development/physics.md` | Player movement, collision, stall watchdogs, or the camera |
| `development/input.md` | Any input change — desktop *or* touch |
| `development/visuals.md` | Background, scenery, palette or draw order |
| `development/biomes.md` | Any colour that changes over a run — palettes, the director, a transition, `shaders/ice.gdshader` |
| `development/ice_panels.md` | Making a new ice tile — panel requirements, prompts, the `--check` validator |
| `development/debugging.md` | Running a gate, or reviving an archived probe |
| `development/dead_code.md` | Something looks reachable but isn't |
| `review/*.md` | Point-in-time audits — the running list of known-but-unfixed debt. Read the newest before a cleanup pass |
| `research/*.md` | Closed investigations. **Not required reading** — open one only when something here points at it |

**Finishing an investigation?** The conclusion goes here (what's true, what to avoid, one
pointer); the full log — measurements, ruled-out approaches — goes in `docs/research/`.

## Run / debug / test

No test suite, no build script. Godot is at `/Applications/Godot.app/Contents/MacOS/Godot`
(play with `--path .`; opens a window and blocks, so only when asked).

**Eleven maintained checks, and only eleven.** Commands and flags: `debugging.md`.

| Check | Run after |
|---|---|
| terrain-shape (fast, physics-free) | any segment/shape change |
| freeze-replay, **freeze-search**, floor-flicker | any player/collision/segment change. Freeze-search is the one that actually finds stalls — replay alone isn't sufficient |
| camera-shake | any change to the camera follow in `main.gd` |
| chasm | anything touching voids, fall death or the boost velocity model |
| `biome_schedule_check.gd` (~1s, palette data) | any palette change |
| `sky_layer_check.gd`, `ice_look_capture.gd`, `biome_contact_sheet.gd` | any visual change. **These three must run WITHOUT `--headless`** — they diff or save rendered frames |
| **`shipping_values_check.gd`** (~0.2s) | **every commit** |

The six headless gates are blind to biome code (`BiomeDirector` returns early under
`--headless`), which is the only reason the visual four exist. `shipping_values_check` is the
only thing watching the debug knobs: each is a plain `var` so the editor can't serialise it,
which also means no other gate can see one left flipped. It fails on all of them and on any
`debug_*` override reaching `main.tscn`; `--allow-temp` downgrades it to a warning.

Plus one *diagnostic*, `ice_seam_probe.gd` (windowed): A/Bs tile bytes inside one frozen frame
to tell a tile's content from a rendering artifact. It prints and never fails — reach for it
when a new ice tile reads as a line on screen. The other ~19 files in `scripts/debug/` are
archived one-offs that measure a *paused* game and print confident, meaningless numbers; never
trust one without reviving it. Log any new seed that trips `FREEZE_REPRO` in
`docs/research/freeze_bug.md` before fixing it.

## Scene wiring

**The annotated scene graph is the first section of `architecture.md`** — open it before
touching `main.tscn`. The rules that break things silently if you don't know them:

- Nodes find each other **by sibling path** (`NodePath("../Player")`), resolved with
  `get_node_or_null` and null-guarded. There is no service locator.
- **Exactly one autoload**, `Services` (`class_name GameServices`); a new global needs a real
  justification. **Never write `Services.x` in gameplay code** — use
  `GameServices.resolve(self)` and null-guard it, or you break every headless probe.
- `GameManager.set_state()` is the **only** place allowed to touch `get_tree().paused` or a
  screen's visibility.
- **Draw order is tree order plus `CanvasLayer.layer`; no `z_index` anywhere.** Reordering
  siblings reorders rendering.
- **The six spawners live under `TerrainGenerator`** so world rebasing carries them for free.

## Things that break silently

- **World rebasing must stay on.** `Main.world_rebase_enabled` isn't `@export`ed — exporting
  it once serialised to `false` and reintroduced the freeze for weeks. (`freeze_bug.md`)
- **Spawners under `TerrainGenerator` must not read `session_seed` in `_ready()`** — children
  ready before parents, so it's still 0 there. Initialise seed-derived state on the first
  `_physics_process`. Shipped as a real bug: identical powerup schedule every session.
- **`get_terrain_height` must stay pure** in `(session_seed, world_x)` — chunk visuals,
  collision, player tilt and the debug HUD all sample it independently. **One runtime input is
  allowed**, `lake_segment_index`, under a **write-once, write-ahead** rule: `arm_lake()` is its
  only writer and may only set it *above* `highest_cached_segment_index`, a segment nothing has
  computed, so arming can only **extend** the height field. Never assign it directly.
- **Always `ensure_segment_cache_for_world_x(x)` before `find_segment_index_at_x(x)`**, or the
  binary search silently clamps and returns the wrong segment.
- **Player spawn `(64,136)` is a manual invariant**: `ground_y(192) + surface_y_offset(-32) −
  capsule half-height(24)`. Change one without updating `Player` in `main.tscn` and it starts
  embedded in, or dropping toward, the terrain.
- **Any long-running harness needs `debug_chasm_disabled = true`**, next to the two
  `debug_spawning_disabled` flags, or a chasm death reports a confident wrong number
  (`freeze_search`/`camera_shake_probe` take `--chasms=1` to opt back in).
- **A chasm's *void* is flat and must stay flat** — zero added slope, steepest terrain still
  20.13°. Anything ≥ `floor_max_angle` is a wall and wedges the player (`large_valley`, three
  weeks). `exit_drop` is a **step exactly at the far lip**, never a ramp across the void: a ramp
  aims a boosting player down it instead of returning the 0 that carries the skim.
- **Scaling a hill scales length *and* amplitude together** (`BIG_HILL_SCALES`) — peak slope is
  `atan(π·magnitude/length)` and both hill types already sit at that 20.13° ceiling, so raising
  amplitude alone walks into the same wall-wedge failure.
- **The opening biome renders at ABSOLUTE cycle index 0 only**, and the session phase advances
  on every death and survives a restart — so it is the first ~3 min of a *cold launch*, and one
  death puts it out of reach. **Set `BiomeDirector.debug_pin_intro_biome` before editing
  `first_light.tres`**, or you are eyeballing a different biome (this happened).
- **Deep ice is hard-capped at `ice_depth × 0.38`** (`ICE_TILE_DEPTH_FLOOR`, matched to the tile
  builder's `OUTPUT_FLOOR`), so even a pure white tint renders as a 0.38 grey. When ice "looks
  grey", **check saturation before brightness** — the fix is usually widening `b − r`.
- **Every `Area2D` has terrain chunks entering it.** Player/chunks/obstacles are layer 1;
  coins/powerups layer 2; everything masks layer 1. `obstacle.gd`, `coin.gd` and `powerup.gd`
  each filter with `body.is_in_group("player")` — drop that and a chunk collects/kills.
- **A pickup's node scale scales its `Area2D`**, so art size *is* hitbox size and the two can
  never be tuned apart. `AIR_COIN_SCALE` 1.9 and the rare coin's 1.0 are both load-bearing.
- **The jump upgrade curve may not exceed ×1.0224.** `CHASM_LEAD_IN_LENGTH` (900) bounds
  max-upgrade × the √2 powerup; above that a boosted jump lands *inside* the void, and
  `check_upgrade_curve()` fails the build. Same reason **double jump is ruled out** —
  `physics.md` has why a cooldown doesn't help.
- **The autoload *node* exists under `--headless --script`** though the global `Services`
  identifier doesn't. `GameManager.apply_upgrades()` must skip headless, or gates measure
  whatever jump level is in *your* `save.dat` (measured: 48/48 → 8 failures). Check
  `DisplayServer` directly, never `services.is_headless`.

## Known issues

- **Residual sub-pixel bounce on curved terrain — open, deferred**, not fixable at the
  input/movement level. Revisit only on a confirmed-visible complaint (`terrain_jitter.md`).
- **`mega_drop` shakiness — SEGMENT CUT, not fixed**, `MEGA_DROP_SELECTION_WEIGHT = 0`. Six
  mitigations measured, none worked — read `camera_shake.md` before spending more time here.
- **FIXED, don't re-investigate:** boost-into-obstacle-cluster death; `is_on_floor()` flicker
  on rising terrain (`floor_flicker.md`). **Unreproduced:** "view snaps forward/backward for
  half a second", watchdogs stayed 0.
- **Removed entirely, don't resurrect:** the old *terrain-driven* obstacle placement inside
  `terrain_generator.gd` (not the same as the live `ObstacleSpawner`) and vertical background
  parallax. History in `dead_code.md`. Don't touch `project.godot` / `.godot/` / `*.uid` /
  `icon.svg` unless asked.

## Build order / status

All **working** unless said otherwise. The numbers here are load-bearing; the reasoning
behind each is in the doc named at the end of its row.

| # | Area | The parts you can't infer from the code |
|---|---|---|
| 1 | Core loop | **Chasms**: a void every ~30–95s, three *hazard* widths plus a survivable `chasm_drop` every 2nd chasm (**periodic, not weighted**). Hills roll a **10% oversized variant**, ×1.5/×2 on *both* axes. `terrain.md` |
| 2 | Speed | Two-phase ramp: 100→500 px/s over 10s, then 500→750 over the next 110s. `MAX_SPEED` 750 at t=120s |
| 3 | Coins + score | `SaveStore` **v3** — versioned best score, a **coin wallet** every run banks into on death, upgrade levels, cumulative playtime, achievements. **Rare coin** (25, ~60s) at `RARE_COIN_CLEARANCE` 174px, inside the 24px gap between the top two jump levels, so max-upgrade-only (or any level holding the ×√2 powerup). A coin slot rolls **10% into a 3-coin air line** (132px, clear of every jump ceiling). **In-run combo** off the run *total*: **×2 from 50, ×3 from 150**, never lost. `physics.md`, `architecture.md` |
| 4 | Obstacles | Singles from t=20s, then every 12–30s. A boosting player breaks through instead of dying |
| 5 | Powerups | Six kinds — speed boost, jump boost, magnet, doubler, shield, glide — one `POWERUP_TABLE` row and one `active_effects` entry each. `can_end_effect()` blocks speed boost/glide expiring over a void. **Airborne tricks** pay a bonus `speed_boost` down that same path, no new velocity model |
| 6 | Screens | START/PLAYING/PAUSED/DEAD/SHOP |
| 7 | Audio | SFX only, 6-voice pool, no music yet. Behind a locally-computed `is_headless` — `Services` isn't ready in harness `_init()` |
| 8 | Visual polish | Sky + ice variation done; gameplay art still placeholder rects. **Eight `BiomePalette`s cycle every 75 000 world-px**, plus `first_light` held OUTSIDE the cycle for absolute index 0 — it opens a session once and never recurs. **The eight are ROTATED, not reordered**: each launch enters the fixed day arc at a random point. A shuffle was built and reverted; the palettes are authored as a day passing and adjacency is load-bearing. **Coins and obstacles take an ABSOLUTE per-biome colour, never a tint** — a biome may shift the two objects the player must *read*, never recolour them — and `biome_schedule_check` holds a contrast floor. `biomes.md`, `visuals.md`, `ice_panels.md` |
| 9 | Upgrades | Vertical slice: one track (jump, five levels), SHOP screen, banked coins. Missions/zones not started |
| 10 | **Frozen lake** | The first set piece. Every 20 min of *cumulative* playtime, and only past 130s into a run, a forced 7500px flat segment is armed ahead of the player: jumping locked, all six spawners suppressed, ice takes a fixed authored blue under a full-screen reflection quad. Everything cosmetic rides ONE ramp, `FrozenLakeDirector.get_lake_blend()` — including the camera's framing. Skate spray and an etched track ride it too. The first crossing grants the game's first **achievement**. `terrain.md`, `visuals.md`, `input.md` |
| 11 | **Achievements** | `AchievementManager` is the ONLY writer of `SaveStore.achievements` (an open dictionary, so a new one needs no version bump). **Triggers come TO it** — it listens to signals systems already emit, never the reverse — so adding one is a table row plus one `.connect()`, both in that file. **Its ids are save data**: adding is free, renaming un-earns it for everyone. No gallery/rewards yet, and an addon was evaluated and declined. `architecture.md` |

**Two `.gdshader`s exist, both owned by ice** — `shaders/ice.gdshader` (the band: two-tile
noise dissolve, per-biome `ice_contrast`, plus a `flatten` and a `gloss` only the lake writes)
and `shaders/frozen_lake_reflection.gdshader`. Colour itself needs no shader: `Polygon2D`
already renders `texture * vertex_color`. A third needs a reason.

**Base viewport pinned 1152×648**, `aspect="expand"`, `Camera2D.zoom` 0.8333 → 1382×778 world
px visible. **Base size and zoom are one decision — only their ratio is field of view**, which
on an auto-runner is reaction time; never move one alone. `expand` makes the base a *minimum*,
so a 20:9 phone gets +25% forward view (open: an aspect-compensated zoom would equalise it,
and needs `camera_shake_probe` + a playtest). **Author raster art at ≈2× its world size** —
tables and the four art-swap traps in `visuals.md`. Reference art and tool inputs live in
`art_source/`, never at the repo root: the root is imported into the export, that folder is
`.gdignore`d.

Debug instrumentation derives from `OS.is_debug_build()` — on under the editor and every
probe, off in a release export, so it can't ship by forgetting a flag (`physics.md`).

---

**Keep this file under ~175 lines.** Only the most important things belong here: the
general direction of the project, and the traps that cost real time when someone doesn't
know them. Add something only if it's genuinely necessary at this level — otherwise it
goes in `docs/development/` (how something works) or `docs/research/` (what an
investigation found).

one thing i want to say (im the user, so this is important) if something has a lot of potenital to make more bugs or is gonna be exceeslsivey hard when theres another option, then jhsut flag it and let me know. i am prioritixzing this to be clean code. if a big drop is too much terrain changing, then we just add a chasm instead, for exmaple
