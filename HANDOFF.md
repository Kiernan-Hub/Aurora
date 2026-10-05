# Handoff

## Where the project is — 2026-10-04 (late). READ THIS FIRST

**Everything is committed and pushed** on `claude/implementation-t58fc3` (still not merged to
`main`). The obstacle system and the air moves are built. The owner's Mac playtest passed
(2026-10-03), phone test A passed 6 of 8 over adb (2026-10-04), and the white void below a high
jump is fixed and owner-approved. Those write-ups, the audit guide and the branch's commit table
moved to the top of `docs/history.md`.

**This session: the `audit.md` cleanup pass**, one commit per item. 17 of 19 items are closed:
- **Player-visible fixes.** With the slam or double jump owned, a tap 1–2 frames before touchdown
  could become an air move instead of the landing jump; now it is always the landing jump (A14,
  `air_move_probe` `landing_edge` + `landing_model`). The death screen's wallet and best follow a
  shop purchase or reset (A2, the phone-test bug). A coin or powerup touched on the death frame no
  longer counts (A15).
- **Save safety.** A purchase whose save fails rolls back and says so (A1). The loader rejects
  INF, huge and negative numbers field by field (A17).
- **Gates.** `check.sh` is now the **fast six** (`regression_probe`, against an in-memory save) and
  **`--full`** runs every asserting physics gate (14/14, ~3 min). Every gate has a time limit, and
  a gate script that fails to load now FAILS (Godot exits 0 then; it was hiding one). The freeze
  and floor-flicker gates exit non-zero on failure. `art_source` is guarded out of exports. The
  drawn coin (sprite × tint) has a contrast floor. The contact sheet covers all nine palettes.
- **Cleanup.** Dead code removed (empty music player, muted jump SFX and its WAV, the pine
  generator, unused wrappers), the two reload paths merged, streak gradients built once, the skate
  trail's halo/core strengths made independent (same look), docs reconciled.
- **Still open:** A3, the obstacle search's cost (measurement added, needs the phone: next
  actions), A9, trimming the comment essays in source (owner to choose how far), and archiving the
  older audits at the bottom of `audit.md`. A13 needs no action.

### Next actions, in order

1. **Owner: playtest (C) below, on the phone.** Also re-check that buying from the death screen
   then Back shows the new wallet. Items A5/A8 by thumb if you meet them.
2. **One phone run with logcat** (`adb logcat -s godot | grep OBSTACLE_SEARCH`, `debugging.md`,
   "Android device testing"): it says whether the obstacle search causes the late frames (A3).
3. **Tune by feel.** The knobs are in "Where to tune". Any timing change must still pass
   `./scripts/check.sh`, whose fairness proofs fail any pattern under 7 frames of take-off window.
4. **Merge to `main`** once happy: `git checkout main && git pull && git merge --ff-only
   origin/claude/implementation-t58fc3 && git push`, or ask Claude to open a PR.
   **`debug_start_wallet` must be 0.**
5. **Step 8, art** (owner): "Remaining plan" below.
6. After opening the editor, always run `git status`. It re-saves `HANDOFF.md` with tabs (whitespace
   only: `git checkout -- HANDOFF.md`) and may strip `project.godot`'s pins (standing rule in
   `CLAUDE.md`).

### Owner: tests still owed

**A. Phone.** 6 of 8 passed 2026-10-04 (`docs/history.md`). Not reached by blind adb taps: **5**, tap
left over a chasm does nothing, and once you've dropped below a lip a right tap does nothing (you
die); **8**, thin ice with either thumb keeps its hop rhythm. Both are `air_move_probe`'s logic.
For a fresh export with coins, set `GameManager.debug_start_wallet` (`game_manager.gd:58`) to 9999
locally and back to 0 before any commit (`check.sh` fails while it's on).

**C. Play the obstacle half** (phone and desktop):
1. **Density.** Is 1:00–2:30 now too busy, at ~2.5× the old count? Does 5:00+ get properly hard?
   Since the 2026-09-28 fix, combos are rarer (`docs/history.md`): do tiers 4–5 still feel like new ideas?
   Spikes now sit only on flats or at the foot of a descent, never just past a climb: repetitive?
2. **Readability at 750 px/s:** floe and shard against scenery, thin ice as "keep hopping", and the
combos (e.g. spike→floe 0.5s, which needs an early jump).
3. **Thin ice grace:** is 0.2s right on touch?
4. **Camera at 30%**, on the start screen and in play; Aurora streaks, wings and framing with the player off-centre.
5. **The frozen lake's skate trail shows less of its tail** (fades over ~860px; only ~415–520px behind the
player is on screen now). Cosmetic.
6. **Possible overlap:** an air coin line (132px) or the rare coin (174px) can sit inside a floe's column
(64–200px). Harmless, looks odd, not guarded.
7. The first spike now appears no earlier than ~21.5s, not 20s (first-appearance pause and retries).

**D. Visual, never checked by anyone:** hazard placeholders, the thin-ice overlay, the shop's three
code-built rows on a phone screen (font 13, same as the old authored row), and the slam's bigger
landing squash.

**E. Code paths no test reaches** (reviewed only):
- The slam refused while already falling faster than 1,200 px/s. It is only reachable in a drop
chasm's descent.
- Touch's half-screen split in `Main._input`. Same coordinate space as the pause-button hit test next
to it.
- An Android build of this code. `check.sh`'s export check packs it, but nothing has run it on a device.

---

## What the game does now (the obstacle system as built)

### Camera (step 1)
- The player sits at **`Main.PLAYER_SCREEN_X_FRACTION` = 0.30** from the left. The camera target is
  `player_x + (0.5 − 0.30) × viewport width ÷ live zoom`, also applied in `_ready()` (no swoop), so
  every aspect ratio and the Aurora zoom keep the same fraction.
- Forward view: **968px** on 16:9 (was 691), **1,179px** on the owner's 19.5:9, **1,210px** on 20:9.
  Per-device table: `visuals.md`.
- Everything spawned ahead is at **≥1,500px** (obstacle, rare coin, powerup). `check_spawn_lookahead()`
  asserts every lookahead clears a **21:9** screen (1,270px) + 64px.

### Hazards

| Kind | Answer | Hitbox | Code |
|---|---|---|---|
| **Spike** | Jump | 32×32 on the ground | `obstacle.tscn` + `obstacle.gd` |
| **Floe** | Stay down | 32×136 column, **64→200px** above the surface. The placeholder art is exactly the hitbox | `floe.tscn` + `obstacle.gd` |
| **Shard** | Stay down, or clear it at jump level 3+ | 32×32 at **64–96px** | `shard.tscn` + `obstacle.gd` |
| **Thin ice** | Keep hopping | An x span, not a body: >**12 grounded frames** (0.2s) in a row cracks it; each landing resets | `scripts/obstacles/thin_ice.gd` (`ThinIce`) |

- All three bodies run `obstacle.gd`, so hit → `absorb_hit()`, a shield absorbs one, and a boosting
  player breaks through. Thin ice: a boost skims over; a shield absorbs the crack and the patch
  **disarms** (fades to 30%). Its overlay is a red `Line2D` **4px above** the surface line, because
  chunks draw over anything at or below it.
- Placeholder art is red `ColorRect`s / `Line2D` in the absolute obstacle colour, repainted by biome pushes.
  Measured contrast of that red vs every biome's scenery and sky is **≥ 0.65** (`sunset_rose` worst),
  above the 0.5 gate.
- **Runtime-verified** in the real scene: thin ice cracks on exactly the 13th grounded frame;
  hopping each landing survives; a shield absorbs, disarms and survives.

### Scheduler (`scripts/systems/obstacle_spawner.gd`)
- **`PIECE_KINDS`**: scene path, half width, half height, centre height above the surface, `floating`.
  **`PATTERNS`**: `{id, tier, weight, pieces: [{kind, at (s), length (s, thin ice only)}]}`.
- **`TIERS`**, each `{start, room}`. "Room" is the breathing room from one pattern's **end** to the
  next one's start, jittered ±30% and never below the floor:

| Tier | From | New | Room |
|---|---|---|---|
| 1 | 0:20 | `spike` (w2) | the original ramp: ~1 per 30s window rising toward one every 5s, 4s floor |
| 2 | 1:00 | `floe`, `shard` (w1 each) | 6s |
| 3 | 1:45 | `ice_short` 0.3s (w2), `ice_long` 1.2s (w1) | 5s |
| 4 | 2:30 | pairs: `spike_floe`, `spike_shard`, `floe_spike`, `shard_spike` (0.5s apart), `spike_spike` (0.7s), `ice_spike` | 4s |
| 5 | 3:30 | triples: `spike_floe_spike` (1.0s), `floe_spike_shard` (1.1s) | 3.5s |
| 6 | 5:00 | — | 3.5s shrinking 0.25s/min to the **2.5s floor** (~9:00) |

- **Each attempt**: draw a pattern for the current tier. A kind not yet seen this run is swapped for
  its solo pattern, with **+1.5s room before and after** (the tutorial). Floating patterns wait out a
  glide; every pattern waits out a boost. Then a **forward search**: the lookahead, then every 50px up to
  600px further. A combo that fits nowhere **falls back to its first piece alone**; if even that
  fails, retry in 1s. The next room counts from where the pattern really ended.
- **Footprint guard** (`is_footprint_legal`, static): ≤6° across the whole span (**except
  thin-ice-only patterns**), not on the lake, ground over `[start − 200, end + 950]`, off the Aurora
  flat. 950 = the boosted max jump's 848px + margin (it was 700: a late boosted jump could land in a chasm).
  **Approach** (2026-09-28): over the weakest jump's reach before each spike, no ground >2px below its base.
- **Measured in the live game** (7 min, 2 seeds, unkillable player): patterns per minute **2, 8, 11,
  12–15, 14–15, 14–15, 16**. That's ~51 in the first 5 min, vs **18–25** before this work: the old code
  silently dropped ~60% of slots. By minute 7 one starts every ~4s; **~12% arrive as combos**. Per
  attempt: singles place ~90%, thin ice ~96%, pairs 24–35%, triples 13–20%. **All measured before the
  approach clause**: spikes now place ~67%, pairs 9–25%, triples 2–7%, so fewer combos. Not re-measured live.

### New checks (all in `check.sh` via `terrain_invariant_check`, all mutation-tested; see `debugging.md`)
- **`check_pattern_fairness()`**: every pattern simulated at 60 Hz on flat ground, **5 jump levels ×
  {plain, √2 powerup} × {the tier's opening speed, 750}**. The only input is when to leave the ground. It
  asserts a surviving line exists and its tightest take-off window is **≥ 7 frames**
  (`PATTERN_MIN_WINDOW_FRAMES`). The lone spike measures 7: 8.57 continuous, the old "~8.6 frames".
  It also asserts both breathing-room floors outlast the longest jump (1.13s) + 0.3s.
- **`check_placed_pattern_fairness()`** (per seed, 2026-09-28): the same model on the **real ground** of
  sampled placements the forward search accepts. It's what proves the guard; the flat proof only proves the table.
- **Per seed**: each pattern's placement rate through the game's own `find_legal_offset()` (floors
  0.32 / 0.04 / 0.01 for 1 / 2 / 3 pieces since the approach clause; were 0.45 / 0.12 / 0.06), plus **`weakest_hop`**: the weakest jump's airtime up the
  steepest measured slope must be ≥ 4 frames (it is 8.2 at 20.13°). That is what makes thin ice's
  slope exemption safe.
- **`check_spawn_placement()`** places **every** kind and checks its height above the surface, that its real
  hitbox matches its `PIECE_KINDS` row, and that it **is an `Obstacle`** (has its script). Thin ice:
  its height, and the overlay's 4px lift.
- **`check_spawn_lookahead()`**: see Camera.

### Where to tune

| Want to change | Knob |
|---|---|
| How dense the run gets, and when | `TIERS` (`start`, `room`), `BREATHING_ROOM_FLOOR` (2.5), `BREATHING_ROOM_SHRINK_PER_SECOND`, `BREATHING_ROOM_JITTER` (0.3) |
| Which patterns, how often, timings | `PATTERNS` (`weight`, `at`, `length`). Re-run `check.sh`: the proof has the final say |
| The tutorial pause | `FIRST_APPEARANCE_EXTRA_ROOM` (1.5s) |
| Thin ice forgiveness | `ThinIce.GRACE_SECONDS` (0.2) |
| Hazard sizes | `PIECE_KINDS` **and** the scene's `RectangleShape2D`/`ColorRect` together (the check enforces they match) |
| Forward view | `Main.PLAYER_SCREEN_X_FRACTION` (0.30). Lower = more view; lookaheads are checked against it |

---

## How to run things

`./scripts/check.sh` before every commit; `--full` after any player, collision, segment or
air-move change; the visual three without `--headless` after a visual change. Commands, the cloud
container setup and every gate's arguments: `docs/development/debugging.md`. After ANY engine
run: `git status` (standing rule in `CLAUDE.md`).

---

## Remaining plan: step 8

### Core rules (still hold)
- **No hazard touches the player's physics**: overlap checks and span checks only.
- **You don't control speed**, so the only decision is when to leave the ground (plus the air moves).
  Motion is decoration only.
- **Patterns are authored in seconds** and proven on flat ground for a player who owns nothing. The
  air moves only ever **add** options (the landing-window rule), so "fair without them ⇒ fair with them".

The air moves' design as built, including where it departs from the plan (the left/right split, no
formula-only 2× check), is at the top of this file and in `input.md` / `physics.md`.

### Step 8 — Art (owner)
Ice-crystal spike, floe + icicle (the island look must stay inside the 64–200px column, or the
hitbox and `PIECE_KINDS` change together), shard, thin-ice cracks, the crack SFX and sink death
(deferred from step 4), slam/landing effects, new ground decoration that must not look like a
hazard. Mind the four art-swap couplings (`visuals.md`) and the contrast gate (hazards stay
red-dominant unless that rule is revisited).

### Open questions (owner). **Defaults in bold** are what's built unless the owner says otherwise
1. Slam **smashes a spike you land on** (like the boost)? **Off**; try it once the slam has been played.
2. Unlock prices: **slam 300, double jump 900**. Placeholders.
3. Should coins avoid floe columns? **No guard for now** (checklist item 6).
4. Hazard colour stays red-family? **Yes, until the art pass.**

Answered and built: floating hazards wait out a glide; tier timings from the plan's table; step 5 as
option A (owner confirmed); the rare coin stays reachable by a level-1 double jump; the trick boost stays,
except after a double jump; the air moves split left (slam) / right (double jump) (owner).

### Ideas flagged and NOT planned (the owner's rule: bug-prone or much harder → flag it)

| Idea | Why not |
|---|---|
| Floating islands you can **stand on** | The player physics assumes the floor is the height field in ≥4 places (slope aim, stall recovery, camera baseline; island edges are walls, the `large_valley` wedge class). The floe gets the look for none of that |
| Bounce floes (land on top, get relaunched) | A relaunch from height reaches further, so it needs its own chasm clearance. Maybe later |
| Wind/gusts | Changes velocity mid-air, which the chasm reach math doesn't model |
| Hazards tied to the biome | Every headless gate is blind to biome code |
| Moving/timed hazards as a *mechanic* | No decisions added (fixed arrival time), and they cost reading time. Decoration only |
| Levels + infinite mode, checkpoints | They fight the seeded world; resuming mid-run rewinds ~10 systems. Tiers give the "chapter" feel |
| Pick your difficulty | **Later, cheap now tiers exist**: "Hard" = start at tier 3. Needs separate best scores (a save change) |


---

## Contracts and traps for whoever touches this next

**`ObstacleSpawner`'s outside contract. Keep these, or change them together with their users:**
- Node path `TerrainGenerator/ObstacleSpawner`, `class_name ObstacleSpawner` (Aurora + biome directors).
- `debug_spawning_disabled` (a plain var, set by 6 probes, watched by `shipping_values_check`).
- `spawn_obstacle(x, kind = spike)`, `spawn_thin_ice(start, end)`, `active_obstacles` (`aurora_calm_probe`,
  `check_spawn_placement`). `OBSTACLE_SCENE` (preloaded; `aurora_calm_probe`).
- Read by `terrain_invariant_check`: `OBSTACLE_HALF_HEIGHT`, `FIRST_PATTERN_TIME`, `PIECE_KINDS`, `PATTERNS`, `TIERS`,
  `RECURRING_PATTERN_MIN_INTERVAL_FLOOR`, `BREATHING_ROOM_FLOOR`, `MIN_SAFE_START_WORLD_X`,
  `OBSTACLE_VOID_CLEARANCE_AHEAD`, `SPAWN_LOOKAHEAD_WORLD_X`, the static `get_pattern_span()`,
  `is_footprint_legal()`, `find_legal_offset()`.
- `apply_biome_color()` (`biome_director`). It stays under `TerrainGenerator` (rebasing) and never reads
  `session_seed` in `_ready()`.

**Traps found or confirmed this session:**
- **Never turn `PIECE_KINDS` scenes back into `preload()`.** It makes a load cycle: when
  `ObstacleSpawner` loads first, `floe.tscn`/`shard.tscn` come back with **no script** (hazards that can't
  hurt anyone), with no error in the game. `check_spawn_placement` now fails on it.
- **A hazard without a collision shape is invisible to `AuroraDirector`** unless
  `get_body_bounds()` knows it, and invisible to `lake_suppression_probe` unless `is_spawned_item()` knows
  it. Both know `ThinIce`; a new shapeless kind must be added to both.
- **Long combos starve on this terrain.** The per-seed placement floors fail a pattern the search can
  rarely place. Keep combos short or accept the fallback rate. Every extra spike in a combo also needs
  flat-or-falling ground before it (the approach clause), which is why spike-heavy combos are the rarest.
- **The flat proof proves the table, not the guard.** Any change that lets the guard accept more ground
  (slope limit, approach tolerance, a new exemption) must pass `check_placed_pattern_fairness()`; the
  flat proof can't see it. Don't lower `PATTERN_MIN_WINDOW_FRAMES` to make that check pass.
- **Thin ice's slope exemption depends on `weakest_hop`.** Lowering the weakest jump multiplier or
  steepening terrain fails it; then restore the slope rule for thin ice.
- **Two spikes closer than ~0.6s are unbeatable at some jump level** (0.3s = 0 frames): a higher jump
  stays up longer and carries you into the next piece. The proof catches it; don't hand-tune around it.
- **New `class_name` ⇒ one import before headless runs** (open the editor, or `--headless --import`).
- Still true: terrain chunks enter every `Area2D` (keep the player-group filter in `obstacle.gd`); place at
  `ground_y + get_terrain_height(x) − clearance`; anything spawned ahead must clear the forward view;
  `apply_upgrades()` skips headless, so probes set `has_slam`/`has_double_jump` themselves; the frame
  after a glide launch reads `is_on_floor()` true; any new `debug_*` knob goes into `shipping_values_check`.

---

## Parked on purpose. Not blocking; don't start any of these unprompted

- **Aurora look calls:** wings rework (blocked on a reference image the owner never sent), bloom
  (recommended no). The owner has accepted the aurora as it is.
- **Natural-aurora playtest:** rarity is measured, never played. It happens whenever the owner plays.
- ~0.5 slightly late frames/s on the phone, cause unmeasured. The obstacle search is now logged
  (`OBSTACLE_SEARCH_SLOWEST`, next actions 2); the other lever is moving the ice recolour into shader uniforms.
- True 120 Hz on phones needs physics interpolation. That's a big change; flagged, not started.
- Play Store release signing / store config.

## Where the rest went

- **Past sessions:** `docs/history.md`, newest first. The top entry is this session's full log. Not required reading.
- **Phone testing** (device, adb, export/install, frame-timing method): `docs/development/debugging.md`, "Android device testing".
- **This file keeps only the current state.** At the end of a session, move its section to the top of
  `docs/history.md` and replace it here.
