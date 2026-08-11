# Aura — endless 2D skater (Godot 4.7, GDScript, Mobile renderer)

Alto's-Adventure-style endless downhill skater: the player auto-runs right at a speed
that ramps over time, riding an infinite, seeded, procedurally generated terrain. All
on-screen art is placeholder `ColorRect`/`Polygon2D`.

**Priority order:** terrain stability > physics/collision correctness > game feel.
Missions, upgrades and visual polish stay deprioritized until the core loop is stable.

## Where things are documented

This file is the map. Everything else is one level down, read on demand.

| Doc | Open it when |
|---|---|
| `docs/development/architecture.md` | Touching scene wiring, `GameManager`, `Services`, persistence, or adding a system |
| `docs/development/terrain.md` | Working inside the generator, chunk lifecycle, or segment shapes |
| `docs/development/physics.md` | Changing player movement, collision, stall watchdogs, or the camera |
| `docs/development/input.md` | Any input change — desktop *or* touch |
| `docs/development/visuals.md` | Touching the background, scenery, palette or draw order |
| `docs/development/biomes.md` | Any colour that changes over a run — palettes, the director, a transition, `shaders/ice.gdshader` |
| `docs/development/ice_panels.md` | Making a new ice tile — panel requirements, prompts, the `--check` validator |
| `docs/development/debugging.md` | Running a gate, or reviving an archived probe |
| `docs/development/dead_code.md` | Something looks reachable but isn't |
| `docs/review/*.md` | Point-in-time external audits. Read the newest before a cleanup pass — it's the running list of known-but-unfixed debt |
| `docs/research/*.md` | Archive of closed investigations. **Not required reading** — open one only when a section here points you at it |

**Finishing an investigation?** Put the conclusion here (what's true, what to avoid, one
pointer) and the full log — measurements, ruled-out approaches — in `docs/research/`.

## AI editing rules

Inspect connected files and find the root cause before changing anything. Prefer
targeted changes; preserve existing architecture unless you propose and explain first.

`project.godot`: features `4.7` + `Mobile`, physics **60 Hz**, interpolation **OFF**.
Some terrain constants derive from `1.0/physics_ticks_per_second` — changing the tick
rate silently changes level geometry.

## Run / debug / test

No test suite, no build script. Godot lives at
`/Applications/Godot.app/Contents/MacOS/Godot` (play with `--path .`; opens a window and
blocks, so only when asked).

**Six headless gates:** terrain-shape check (fast, physics-free), freeze-replay,
freeze-search (the one that actually finds stalls — replay alone isn't sufficient),
floor-flicker, camera-shake, chasm. Run the terrain check after any segment/shape change, the
physics ones after any player/collision/segment change, camera-shake after any change to the
camera follow in `main.gd`, and chasm after anything touching voids, fall death or the boost
velocity model. Commands, flags and watchdog mechanics in `docs/development/debugging.md`.
**Plus four visual checks**, because the six above are blind to biome code (`BiomeDirector`
returns early under `--headless`): `biome_schedule_check.gd` (~1s, palette data) and — all
three of these **must run WITHOUT `--headless`**, they diff or save rendered frames —
`sky_layer_check.gd`, `ice_look_capture.gd`, `biome_contact_sheet.gd`. **Plus one maintained
*diagnostic*** (windowed too): `ice_seam_probe.gd` A/Bs tile bytes inside one frozen frame to
tell a tile's content from a rendering artifact. It prints and never fails — read it, don't
gate on it. Reach for it when a new ice tile reads as a line on screen.
Log any new seed that trips `FREEZE_REPRO` in `docs/research/freeze_bug.md` before fixing it.

**Before every commit: `shipping_values_check.gd`** (~0.2s). Every debug knob is a plain `var`
so the editor can't serialise it — which also means no other gate can see one left flipped.
This one fails on all of them, and on any `debug_*` override reaching `main.tscn`.
`--allow-temp` to WARN instead while eyeballing.

**Only those eleven are maintained.** The other ~19 files in `scripts/debug/` are archived
one-offs that mostly predate the start screen — they measure a *paused* game and print
confident, meaningless numbers rather than failing. Never trust one without reviving it.

## Scene graph (`scenes/main.tscn`)

```
Main (Node2D, scripts/main.gd)
├── SkyBackdrop       CanvasLayer -200 ← sky_backdrop.gd; gradient + stars/glow/sun-moon,
│                     rebaked only while a transition moves
├── ParallaxBackground  FarPeaks/FarRidge/MidRidge/PineLine, motion_scale.y ALWAYS 0
│                     one background_generator.gd each, differing only by @export
├── BirdFlock         CanvasLayer -60, visible only while gliding ← bird_flock.gd
├── SnowDrift         CanvasLayer -50 (behind all gameplay) ← snow_drift.gd
├── Player            position (64,136), safe_margin 1.0  ← player.tscn
├── TerrainGenerator  player_path = ../Player
│   ├── CoinSpawner       per-chunk coin slots
│   ├── ObstacleSpawner   timed clusters; a hit calls Player.absorb_hit()
│   ├── PowerupSpawner    timed pickups, one weighted table (see Build order §5)
│   ├── GroundTreeSpawner decorative, global grid keyed on session_seed
│   └── GlideCoinSpawner  air coins, only while Player.is_glide_active
├── BiomeDirector     the ONLY reader of a BiomePalette; returns early under --headless
├── Camera2D          position (0,136), zoom 0.833
├── GameManager       State { START, PLAYING, PAUSED, DEAD, SHOP }
├── PowerupManager    effect timers; drives Player.start_boost etc.
├── SfxPlayer         6-voice AudioStreamPlayer pool on the SFX bus
└── CanvasLayer       Start/Pause/Death/ShopScreen (all process_mode=ALWAYS),
					  PauseButton, Timer/Coin/Powerup labels
```

Wiring is by sibling path. There is **exactly one autoload** — `Services`
(`class_name GameServices`) — new globals need a real justification. **Never write
`Services.x` in gameplay code**; use `GameServices.resolve(self)` and null-guard it, or
you break every headless probe. `GameManager.set_state()` is the **only** place allowed
to touch `get_tree().paused` or a screen's visibility. Reasoning: `architecture.md`.

## Things that break silently

- **World rebasing must stay on.** `Main.world_rebase_enabled` isn't `@export`ed —
  exporting it once serialised to `false` and reintroduced the freeze for weeks.
  (`docs/research/freeze_bug.md`)
- **Spawners under `TerrainGenerator` must not read `session_seed` in `_ready()`** —
  children ready before parents, so it's still 0 there. Initialise seed-derived state on
  the first `_physics_process`; shipped as a real bug (identical powerup schedule every
  session). (`architecture.md`)
- **`get_terrain_height` must stay pure** in `(session_seed, world_x)`. Chunk visuals,
  collision, player tilt and the debug HUD all sample it independently.
- **Always `ensure_segment_cache_for_world_x(x)` before `find_segment_index_at_x(x)`**,
  or the binary search silently clamps and returns the wrong segment.
- **Player spawn `(64,136)` is a manual invariant**: `ground_y(192) +
  surface_y_offset(-32) − capsule half-height(24)`. Change either without updating
  `Player` in `main.tscn` and it starts embedded in, or dropping toward, the terrain.
- **Any long-running harness needs `debug_chasm_disabled = true`**, next to the two
  `debug_spawning_disabled` flags, or a chasm death reports a confident wrong number
  (`freeze_search`/`camera_shake_probe` take `--chasms=1` to opt back in).
- **A chasm's *void* is flat, and must stay flat** — zero added slope, steepest terrain still
  20.13°. Anything ≥ `floor_max_angle` is a wall and wedges the player (`large_valley`, three
  weeks). `exit_drop` is a **step exactly at the far lip**, never a ramp across the void (a
  ramp aims a boosting player down it instead of returning the 0 that carries the skim).
- **Scaling a hill scales length *and* amplitude together** (`BIG_HILL_SCALES`): peak slope is
  `atan(π·magnitude/length)`, and both hill types already sit at the 20.13° ceiling, so
  raising amplitude alone walks into that same wall-wedge failure.
- **Every `Area2D` has terrain chunks entering it.** Player/chunks/obstacles are layer 1;
  coins/powerups layer 2; everything masks layer 1. `obstacle.gd`, `coin.gd`, `powerup.gd`
  each filter with `body.is_in_group("player")` — drop that and a chunk collects/kills.
- **The jump upgrade curve may not exceed ×1.0224.** `CHASM_LEAD_IN_LENGTH` (900) bounds
  max-upgrade × the √2 powerup; above that a boosted jump lands *inside* the void.
  `check_upgrade_curve()` fails the build if raised. Same reason **double jump is ruled
  out** — see `physics.md`'s "Double jump — ruled out" for why a cooldown doesn't help.
- **The autoload *node* exists under `--headless --script`** though the global `Services`
  identifier doesn't. `GameManager.apply_upgrades()` must skip headless, or gates measure
  whatever jump level is in *your* `save.dat` (measured: 48/48 → 8 failures). Checks
  `DisplayServer` directly, not `services.is_headless`.

## Known issues

- **Residual sub-pixel bounce on curved terrain — open, deferred**, not fixable at the
  input/movement level. Revisit only on a confirmed-visible complaint (`terrain_jitter.md`).
- **`mega_drop` shakiness — SEGMENT CUT, not fixed** (2026-08-01),
  `MEGA_DROP_SELECTION_WEIGHT = 0`. Six mitigations measured, none worked — read
  `docs/research/camera_shake.md` before spending more time here.
- **FIXED, don't re-investigate:** boost-into-obstacle-cluster death (2026-08-04);
  `is_on_floor()` flicker on rising terrain (2026-07-29, `floor_flicker.md`).
- **"View snaps forward/backward for half a second" — unreproduced**, watchdogs stayed 0.

## Dead / disabled code — check before "fixing"

The old **terrain-driven** obstacle placement in `terrain_generator.gd` and vertical
background parallax were removed entirely, not left disabled — don't resurrect either
(not the same as the current, live `ObstacleSpawner`). Don't touch `project.godot` /
`.godot/` / `*.uid` / `icon.svg` unless asked. History: `docs/development/dead_code.md`.

## Build order / status

1. Core loop (terrain + movement) — **working**. **Chasms**: a void every ~30–95s, three
   *hazard* widths plus a survivable `chasm_drop` every 2nd chasm (**periodic, not
   weighted**). Hills roll a **10% oversized variant**, ×1.5/×2 on *both* axes (`terrain.md`)
2. Speed scaling — **working**. Two-phase ramp: 100→500 px/s over 10s, then 500→750 over
   the next 110s, capping at `MAX_SPEED` (750) at t=120s
3. Coins + score — **working**. `SaveStore` (v2) persists a versioned best score, plus a
   **coin wallet** every run banks into on death and per-upgrade levels
4. Obstacles + death — **working**. Singles from t=20s, then every 12–30s. A boosting
   player breaks through instead of dying (see §5)
5. **Powerups — working, six kinds** (2026-08-06): speed boost, jump boost, coin magnet,
   doubler, shield, glide — one `POWERUP_TABLE` row and one `active_effects` entry each;
   `can_end_effect()` blocks speed boost/glide from expiring over a void. **Airborne
   tricks** pay a bonus `speed_boost` down that same path — no new velocity model
6. Screens — **working**. START/PLAYING/PAUSED/DEAD/SHOP
7. **Audio — working (SFX only).** 6-voice pool on the SFX bus, sliders flush on drag end,
   no music track yet. Behind a locally-computed `is_headless` (`Services` isn't ready in
   harness `_init()`)
8. **Visual polish — sky pass and ice variation done** (2026-08-10), gameplay art still
   placeholder rects. **Eight `BiomePalette`s cycle every 75 000 world-px**, crossfading on
   five staggered channels. Colour still needs no shader — `Polygon2D` already renders
   `texture * vertex_color`. **Exactly one `.gdshader` exists** (`shaders/ice.gdshader`, ice
   band only): a two-tile noise dissolve, a per-biome `ice_contrast`, and a parked `gloss`.
   **Sky**: five-stop gradient baked with a horizontal wash, a directional glow on the
   ridgeline, a sun/moon disc on two biomes (the moon is a crescent), and a starfield. The
   parallax layers were lowered so a sky exists at all — it was 2.4% of the frame.
   **Ice**: the tile's V axis is depth below the ride surface, plus a world_x hue drift and a
   snow cap whose depth varies with world_x. `biomes.md`, `visuals.md`, `ice_panels.md`

9. **Upgrades — vertical slice working** (2026-08-04). One track (jump, five levels), SHOP
   screen, banked coins; player starts weak, buys to baseline. Missions/zones not started

Debug instrumentation derives from `OS.is_debug_build()` — on under the editor and every
probe, off in a release export, so it can't ship by forgetting a flag (`physics.md`).

**Still unset: the base viewport size.** No `window/size/viewport_width`/`height`, so
`aspect="expand"` lets visible world width vary with device aspect ratio — a difficulty
difference between phones on an auto-runner, not a cosmetic one. Needs a deliberate
decision — `docs/review/2026-08-03-architecture-audit.md` §B4.

---

**Keep this file under ~175 lines.** Only the most important things belong here: the
general direction of the project, and the traps that cost real time when someone doesn't
know them. Add something only if it's genuinely necessary at this level — otherwise it
goes in `docs/development/` (how something works) or `docs/research/` (what an
investigation found).

one thing i want to say (im the user, so this is important) if something has a lot of potenital to make more bugs or is gonna be exceeslsivey hard when theres another option, then jhsut flag it and let me know. i am prioritixzing this to be clean code. if a big drop is too much terrain changing, then we just add a chasm instead, for exmaple
