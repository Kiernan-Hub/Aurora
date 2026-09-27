# Handoff

## 2026-09-27 — clean slate. Next work: obstacles

**Nothing is in flight.** `main` is clean, every gate is green, and all audit findings are fixed.
Older sessions live in `docs/history.md`; **none of that is a to-do**.

### What closed this session

| Item | Result |
|---|---|
| Android device review (S26) | **PASSED.** Owner ran the checklist: SFX audible, volume slider mutes, Back pauses mid-run, Back on START closes the app (intended). Stutter fix `1caf2d7` already shipped |
| Fast five (`check.sh`) | **5/5 PASS** |
| Windowed visual gates, first run since `1caf2d7` | `sky_layer_check` **PASS** (9 biomes, 44 layers, both aurora night palettes). `ice_look_capture` + `biome_contact_sheet` captured; frames inspected, no breakage |
| 2026-09-20 audit's 4 findings | All fixed and merged (`7b844a2`, `e5ba888`, `9f07726`, `ae200cb`) |
| `project.godot` strip | Happened again (pins + comments). Restored under the standing rule |

### Parked on purpose. Not blocking; don't start any of these unprompted

- **Aurora look calls:** wings rework (blocked on a reference image the owner never sent), bloom
  (recommended no). The owner has accepted the aurora as it is.
- **Natural-aurora playtest:** rarity is measured, never played. It happens whenever the owner plays.
- ~0.5 slightly late frames/s on the phone, cause unmeasured. Next lever if needed: move the ice recolour into shader uniforms.
- True 120 Hz on phones needs physics interpolation. That's a big change; flagged, not started.
- Play Store release signing / store config.

### Next: obstacles. Plan APPROVED by the owner 2026-09-27

**Diagnosis (why it's too easy):** two obstacles are never on screen together (≥4s apart =
3000px+ at speed, screen shows ~1400–1700); one hazard with one answer; difficulty plateaus at
~2:30 (speed caps 2:00, density 2:30); a stack of free passes (untimed shield, boost breaks
through and defers spawns, glide landing shield, every landed trick = 3s invulnerable boost);
the player sits mid-screen, so only ~0.9–1.15s of forward view at 750 px/s.

**Structure:** tiers inside ONE endless run — a new hazard idea roughly every minute, each
introduced alone with extra room the first time. Hazards come in **patterns** of 2–3 pieces
inside one screen, with breathing room between. **Declined for now:** levels (scope, fights the
seeded world), checkpoints (rewinding ~10 systems mid-run is a bug magnet), pick-a-difficulty
(cheap later, once tiers exist).

**Hazard vocabulary — every one an `Area2D`; none adds a floor, wall or velocity change:**
ground spike (jump) · floating shard hanging off a floating ice floe (stay down; levels 3–4 can
jump it) · thin ice (land and it cracks after ~0.2s — skip across it). **Flagged, not planned:**
standable floating islands (the physics assumes the floor is the height field in ≥4 places;
edges are walls), bounce floes (extra reach near chasms), wind (mid-air velocity change),
biome-tied hazards (headless gates are blind to biomes). Moving hazards add no decisions — the
player can't change arrival time — so motion is flair only.

**Build order, one step per commit, stop after each:** 1) camera: player left of centre (~40%
more forward view) + raise the 800px spawn lookaheads, which also fixes the on-screen pop-in on
20:9 phones · 2) pattern scheduler + a frame-by-frame fairness check in `terrain_invariant_check`
(patterns authored in SECONDS: on flat ground jump height over time is speed-independent), spikes
only so play is unchanged · 3) floating shard/floe · 4) thin ice · 5) tiers + multi-piece
patterns, tuned by play.

**Known traps for this work:** thin-ice cracks can't be drawn by a spawner (chunks are added
after the spawners and draw over the surface line; no `z_index`) · thin ice must let a boosting
player through (no jumping while boosting) · the contrast gate forces red-dominant hazards.

**Open question:** the owner asked for an unlockable permanent **double jump**. It was ruled out
on 2026-08-06 (`physics.md`); the costs and a cheaper alternative were put to the owner — record
the answer here.

Current code state, so the next chat doesn't have to rediscover it:
- **Code:** `scripts/systems/obstacle_spawner.gd` (232 lines, under `TerrainGenerator` like all
  five spawners), `scripts/obstacles/obstacle.gd` (39 lines, `Area2D`), `scenes/obstacles/obstacle.tscn`.
  Art is a **placeholder 32×32 `ColorRect`**.
- **Behaviour:** singles only (multi-obstacle clusters were cut on purpose). The first arrives at t=20 s,
  then density ramps in 30 s windows up to 6 per window, with a hard 4 s minimum gap. Placed only on
  slopes ≤ 6°, with 700 px of void clearance ahead / 200 behind, spawn lookahead 800 px. A hit
  calls `Player.absorb_hit()` (a shield absorbs it); a **boosting player breaks through**.
- **Traps that apply here** (`CLAUDE.md` + the art-swap memory):
  - The `body.is_in_group("player")` filter in `obstacle.gd` is load-bearing: terrain chunks enter every `Area2D`.
  - `OBSTACLE_HALF_HEIGHT` (16) is hand-matched to the collision shape; a sprite/size change must move both.
  - The obstacle colour is an **absolute per-biome colour**, held to a contrast floor by `biome_schedule_check`.
  - `terrain_invariant_check.check_obstacle_clearance()` derives jump clearance from
    `FIRST_CLUSTER_TIME` and the obstacle size. Taller obstacles can fail it, correctly.
  - `check_spawn_placement()` measures where a really-placed obstacle lands; keep it passing.
  - Obstacles are suppressed on the frozen lake and the Aurora flat; a new kind must respect both.
- **Gates to run after obstacle changes:** `check.sh`, plus freeze-search and chasm
  (`docs/development/debugging.md`). Owner's rule: if an idea is bug-prone or much harder than
  an alternative, **flag it and offer the simpler option** before building.

### Where the rest went

- **Past sessions:** `docs/history.md`, newest first. Not required reading.
- **Phone testing** (device, adb, export/install, frame-timing method): `docs/development/debugging.md`, "Android device testing".
- **This file keeps only the current state.** At the end of a session, move its section to the top of
  `docs/history.md` and replace it here.
