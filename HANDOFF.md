# Handoff

## START HERE — where the work stands, 2026-11-15

**To continue: you are on branch `play/next`. Everything is committed, nothing is pushed, `main` is
untouched.** `./scripts/check.sh --full` passes all 15 gates as of `0ce2e78`. Read this section and
"Next actions"; the rest of the file is reference.

**Nothing on this branch has been played by the owner.** It was built in one long session with the
owner mostly away, verified by gates and by two short windowed renders. Treat every look and feel
call below as unconfirmed.

### What `play/next` contains (26 commits on top of `main`)

Merged in, built 2026-10-29 and never played:
- **Island chasms** (`terrain/island-chasm`): every 4th chasm window, two floating floes over one
  long void, three gaps (`terrain.md`, "Island chasms").
- **Three elements** (`elements/black-ice-geode`): black ice, slam geodes, ice vents (Hazards table).
- **The UI pass** (`ui/stats-sounds-theme`): menu sounds, one theme, Stats screen, distance, four
  run achievements, four bought skaters, sparkle colours (`architecture.md`).

Built 2026-11-15, in commit order:
1. **Bug fix, predates the branch:** a world rebase on the frame the player lands from a drop
   chasm dropped them through the floor. `Main.apply_world_rebase()` now calls
   `force_update_transform()` on every chunk (`terrain.md`, "The plunge").
2. **Mountains:** ×3/×4 hills and valleys from segment 60, same 20.13° slope (`terrain.md`).
3. **The plunge:** a 1,400px drop chasm every 4th chasm window. Cadence: drop, hazard, plunge, islands.
4. **Late tiers:** tier 7 (6:30) five mixed pairs, tier 8 (8:00) three triples, room floor 2.0s
   (was 2.5), reached about 11:00. Every row has 9+ frames in the fairness proof.
5. **HUD:** run distance beside the clock (`TimerLabel`, widened).
6. **Bug fix, also reachable on `main`:** any fall over ~1,440 px/s could tunnel through the floor
   (a drop-chasm landing, a slam). `Player.move_and_slide_in_fall_steps()` splits fast falls into
   moves of 16px at most; slower frames are unchanged (`physics.md`, last section). New gate
   `chasm_plunge` in `check.sh --full`.
7. **Chests:** `RareCoinSpawner` hangs a chest every 80–120s (first at 30–50s) at 84px, reachable
   at every jump level; "Chests: N" on the HUD. At death `ChestRewards.TABLE` rolls each (15–35
   coins 55%, 50–90 30%, jackpot 200–300 10%, an unowned skater 5%), banked in `record_run`'s one
   write. `ChestReveal` opens them on the death screen: rattle, flash, lid thrown back, rays, gold
   spray, count-up, three synthesised sounds (`build_ui_sfx.py`). The chest is polygons in
   `chest.tscn`: placeholder art. Chest and rare coin skip any spot within 500px or 1s of a hazard
   (`ObstacleSpawner.is_clear_for_pickup`). `regression_probe` case `chests`.
8. **Shop as cards:** an upgrades row and a skaters row with pictures, pips on Jump, prices on
   buttons, unaffordable cards dimmed, Reset Progress small and last
   (`GameManager.build_shop_rows`). Shop, Stats and Skaters backdrops are opaque (the death screen
   showed through).
9. **Dev mode:** two start-screen buttons, debug builds only (`scripts/systems/dev_mode.gd`, whose
   header lists every value). "Dev mode" tops the wallet to 99,999 **in the real save**, cycles a
   biome every 20s, triples powerups, a chest about every 40s, a lake every 3 min of play, an
   aurora 100s into each run. "Dev can't die": hazards pass through and a fall into a void lands
   you past it. It sets the existing debug knobs at runtime from a `user://dev_mode` flag, so no
   source default changes and `shipping_values_check` still holds them.

### Next actions, in order

1. **The owner plays `play/next`** (dev mode makes this quick). What to look at:
   - the card shop: layout, whether seven cards fit a phone, the skater pictures. **Never seen by
     anyone, including the session that built it.**
   - the chest in a run (placeholder art), the reveal's timing, the three chest sounds (never heard)
   - the plunge's landing and camera (1.3s of fall; the landing is off screen at the lip)
   - mountains at speed; whether 8:00+ is hard in a good way ("Dev can't die" gets there)
   - HUD text on a phone: "Chests: N   Coins: N" and the distance beside the clock
   - from the merged branches: islands, black ice, vents, geodes, theme, menu sounds, skaters
2. **If it holds up, merge `play/next` into `main`** (fast-forward). The owner decides; do not
   merge or push unprompted.
3. **Requested by the owner, not started:**
   - **Run goals / missions** ("slam 3 geodes", "reach 2 km"), shown at the start and ticked off
     in the HUD, with a chest as the reward. Agreed as the step after chests; the strongest
     "one more run" driver and the game has none.
   - **Real art from ChatGPT.** The owner has a style prompt (clean, minimal low-poly ice, light
     greyscale on real alpha, never "cozy") and will save files under `art_source/`. Wanted first:
     a chest sprite, UI icons (jump, slam, double jump, coin, lock), a display font from Google
     Fonts. Wire them in when they exist. Decide with the owner where scenery may go: ground
     decoration was removed twice for competing with hazards.
   - **More "game feel" hooks**, in the order proposed: near-miss ("120 m from your best" on the
     death screen, a marker where the best run ended), a progress bar toward the next unlock,
     a collection grid of locked silhouettes, a daily chest/streak last.
   - **Chest sounds/pacing tuning** once the owner has heard them: one row each in
     `build_ui_sfx.py`; `ChestReveal.RATTLE_SECONDS` (0.55).
4. **Flagged, undone:**
   - The 2.0s room floor means more obstacle searches per minute, and A3 (search cost on the phone
     at combo tiers) is still unmeasured. If late frames show past 8:00, set
     `ObstacleSpawner.BREATHING_ROOM_FLOOR` back to 2.5 first.
   - A coin trail down the plunge was considered and not built: the fall arc depends on speed and
     on whether the player jumped, so a fixed trail would often miss.
   - `docs/history.md` has not been given this session's or the 2026-10-29 session's entry beyond
     the section moved there today.
5. Still open from before: one long phone run past 5:00 with logcat (`OBSTACLE_SEARCH_SLOWEST`,
   `debugging.md`), and the owner tests under "Owner: tests still owed" in `docs/history.md`.

### Traps met this session (each cost time)

- **A new `class_name` needs one `--headless --import` before any gate**, or a gate hangs on a
  parse error until its time limit (`check.sh` looked stuck for 7 minutes).
- **Engine runs stripped `project.godot`'s pins again** (during a windowed run). Standing rule in
  `CLAUDE.md`: if the diff only removes pins/comments, `git checkout -- project.godot`. Run
  `git status` after ANY engine run.
- **Headless never runs `_draw()`.** Drawing code (`ChestReveal.ChestStage`) must be rendered in a
  window once to find errors; `regression_probe` only proves its logic.
- **Without `--fixed-fps 60` a headless run's frames are not real time.** A test that waits N
  frames for a tween fails under `check.sh`; `await tween.finished` instead (`chests` case).
- **A windowed test loses focus and the game pauses itself.** Re-set `State.PLAYING` each frame.
- **Never test dev mode or a death against the real save.** Swap an in-memory `SaveStore` into
  `Services` first, as `regression_probe` does; dev mode's wallet top-up writes `save.dat`.
- **Anything pinned to a world_x past segment 60 moves when segment lengths change.** The
  mountains moved `PLACED_FAIRNESS_CASES`' control; it now sits before segment 60.
- **zsh does not word-split `$args`**: pass a gate's arguments literally, or the probe silently
  runs with defaults (a "PASS" over a quarter of the trials).
- **Codex / sandboxed agents:** add `--log-file /tmp/godot.log` to every Godot command
  (`check.sh` already does).

### On the phone

Still the 2026-10-05 debug export (the old `main`), save kept. `play/next` has not been exported.
A fresh debug export gets the dev-mode buttons; a release export does not.

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
| **Spike** | Jump | its silhouette (convex hull) inside a 32×32 box on the ground | `obstacle.tscn` + `obstacle.gd` |
| **Floe** | Stay down | 32×136 column, **64→200px** above the surface. The sprite is exactly the hitbox | `floe.tscn` + `obstacle.gd` |
| **Shard** | Stay down, or clear it at jump level 3+ | its silhouette inside a 32×32 box at **64–96px** | `shard.tscn` + `obstacle.gd` |
| **Thin ice** | Keep hopping | An x span, not a body: >**12 grounded frames** (0.2s) in a row cracks it; each landing resets | `scripts/obstacles/thin_ice.gd` (`ThinIce`) |
| **Black ice** (2026-10-28) | Commit early | A `ThinIce` subclass span you **cannot take off from** (`Player.is_on_black_ice()` at the one ground take-off site; a tap stays buffered). Harmless alone; before a spike, jump before it or after it. Dark glass, never tinted | `black_ice.gd` (`BlackIce`) |
| **Geode** (2026-10-28) | Slam it (reward) | A `SpriteSpan` (a `ThinIce` subclass drawn as one untinted sprite), never a hitbox: a **slam landing** within 24px of it pays **10 coins** (via `geode_broken`, combo/doubler apply). Scheduled only if the player owns the slam. Gold | `geode.gd` (`Geode`) |
| **Vent** (2026-10-28) | Jump EARLY | A 48px `SpriteSpan` that **forces a take-off**: grounded on it, `Player`'s ordinary ground jump fires with no tap (`is_on_vent()`, same site as black ice). Not a new velocity: the launch IS a jump, so chasm reach and every proof hold. Before a floe at 0.5s, being launched carries you into it, so you jump over the vent early enough to be down before the floe. Deep teal: the pale-cyan generation was 0.09 from the ice | `vent.gd` (`Vent`) |

- All three bodies run `obstacle.gd`, so hit → `absorb_hit()`, a shield absorbs one, and a boosting
  player breaks through. Thin ice: a boost skims over; a shield absorbs the crack and the patch
  **disarms** (fades to 30%). A crack plays `crack.wav` (synthesised, `build_crack_sfx.py`) via
  `ObstacleSpawner.thin_ice_cracked`; a fatal one also sinks the sprite through the ice
  (`Player.sink_through_ice`), seen because every death screen now fades in over 0.6s
  (`GameManager.DEATH_SCREEN_FADE_SECONDS`). Its overlay is an 8px `Line2D` tiling a cracked-crust strip, its straight
  bottom 1px under the surface line, because chunks draw over anything at or below it (and so hide the join).
- **All four hazards are art** (2026-10-28, ChatGPT-generated, low-poly ice; the look is clean minimal
  ice, never "cozy"): light-greyscale `Visual` `Sprite2D`s (and the thin-ice strip) that the biome's
  obstacle colour multiplies over, baked by `scripts/tools/build_hazard_sprites.py` from
  `art_source/hazards/`: the three bodies to exactly 3× their hitbox, the strip to 3× `OVERLAY_WIDTH`
  with a crossfaded seam. `biome_schedule_check` holds the contrast floor on each one as drawn (lowest 0.63).
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
| 2 | 1:00 | `floe`, `shard` (w1 each); `geode` (w1, slam owners) | 6s |
| 3 | 1:45 | `ice_short` 0.3s (w2), `ice_long` 1.2s (w1), `black` 0.6s (w1), `vent` (w1) | 5s |
| 4 | 2:30 | pairs: `spike_floe`, `spike_shard`, `floe_spike`, `shard_spike` (0.5s apart), `spike_spike` (0.7s), `ice_spike`, `black_spike` (w2), `geode_spike` (slam owners), `vent_floe` (0.5s, w2) | 4s |
| 5 | 3:30 | triples: `spike_floe_spike` (1.0s), `floe_spike_shard` (1.1s), `spike_black_spike` (0.95s; 1.25s starved) | 3.5s |
| 6 | 5:00 | — | 3.5s |
| 7 | 6:30 | pairs: `ice_floe`, `shard_ice`, `vent_shard`, `vent_spike`, `vent_ice` | 3.0s |
| 8 | 8:00 | triples: `black_floe_spike`, `vent_floe_spike`, `ice_spike_floe` (w2 each) | 2.75s shrinking 0.25s/min to the **2.0s floor** (~11:00) |

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
  its height, and the overlay's `OVERLAY_LIFT`.
- **`check_spawn_lookahead()`**: see Camera.

### Where to tune

| Want to change | Knob |
|---|---|
| How dense the run gets, and when | `TIERS` (`start`, `room`), `BREATHING_ROOM_FLOOR` (2.0), `BREATHING_ROOM_SHRINK_PER_SECOND`, `BREATHING_ROOM_JITTER` (0.3) |
| Which patterns, how often, timings | `PATTERNS` (`weight`, `at`, `length`). Re-run `check.sh`: the proof has the final say |
| The tutorial pause | `FIRST_APPEARANCE_EXTRA_ROOM` (1.5s) |
| Thin ice forgiveness | `ThinIce.GRACE_SECONDS` (0.2) |
| Hazard sizes | `PIECE_KINDS`, the scene's `RectangleShape2D` (the check enforces they match) **and** the `HAZARDS` row in `build_hazard_sprites.py`, then re-run it |
| Forward view | `Main.PLAYER_SCREEN_X_FRACTION` (0.30). Lower = more view; lookaheads are checked against it |

---

## How to run things

`./scripts/check.sh` before every commit; `--full` after any player, collision, segment or
air-move change; the visual three without `--headless` after a visual change. Commands, the cloud
container setup and every gate's arguments: `docs/development/debugging.md`. After ANY engine
run: `git status` (standing rule in `CLAUDE.md`).

---

## The obstacle plan: done through step 8

### Core rules (still hold)
- **No hazard touches the player's physics**: overlap checks and span checks only.
- **You don't control speed**, so the only decision is when to leave the ground (plus the air moves).
  Motion is decoration only.
- **Patterns are authored in seconds** and proven on flat ground for a player who owns nothing. The
  air moves only ever **add** options (the landing-window rule), so "fair without them ⇒ fair with them".

The air moves' design as built, including where it departs from the plan (the left/right split, no
formula-only 2× check), is at the top of this file and in `input.md` / `physics.md`.

### Step 8 — Art: DONE, played and merged 2026-10-28
One commit each: **8a** spike/floe/shard sprites, **8b** thin-ice crack strip, **8c** spike and shard
collide on their silhouette (a convex hull inside the old box, so every fairness proof still holds),
**8d** landing/slam glint bursts (`LandingBurst`, SkateSpray's look), **8e** crack sound, sink death,
and a 0.6s death-screen fade on every death. The art came from ChatGPT; prompts must say clean,
minimal ice, never "cozy". **Ground decoration: SKIPPED by the owner.** It was removed once
(2026-09-27) for competing with hazards, and the hazards are now ice art that covers both
shapes decoration could take: upright reads as a spike/floe/shard, flat reads as thin ice.

### Open questions (owner). **Defaults in bold** are what's built unless the owner says otherwise
1. Slam **smashes a spike you land on** (like the boost)? **Off**; try it once the slam has been played.
2. Unlock prices: **slam 300, double jump 900**. Placeholders.
3. Should coins avoid floe columns? **No guard for now** (checklist item 6).
4. Hazard colour stays red-family? **Yes**: the art pass kept it (greyscale sprites × the red obstacle colour).

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
| Warmth meter (cold drains, embers refill) | The strongest "different" idea of the 2026-10-28 six, and the most bug-prone: every long harness would need a `debug_*` off-switch (the chasm trap), and lake/Aurora (spawners suppressed) would need the drain paused |
| Launch kickers / updrafts | Change velocity mid-run, which the chasm reach math does not model (same as bounce floes and wind). **The vent is the lean version**: it forces an ordinary jump instead, so nothing new is modelled |
| Thin ice under a floe (hop the ice, stay down under the floe) | Measured 2026-10-28: 5-frame window at every placement tried (0.6–1.0s of ice), under the 7-frame bar |
| Whiteout blizzard | Shrinks the forward view below what `check_spawn_lookahead()` guarantees; it would need its own set piece like the Aurora |
| Apex bells (targets at jump-apex height) | Already exists in effect: the 132px air coin lines |


---

## Contracts and traps for whoever touches this next

**`ObstacleSpawner`'s outside contract. Keep these, or change them together with their users:**
- Node path `TerrainGenerator/ObstacleSpawner`, `class_name ObstacleSpawner` (Aurora + biome directors).
- `debug_spawning_disabled` (a plain var, set by 6 probes, watched by `shipping_values_check`).
- `spawn_obstacle(x, kind = spike)`, `spawn_thin_ice(start, end)` (now a wrapper of `spawn_span(kind, start, end)`), `is_black_ice_at(x)` / `is_vent_at(x)` (Player, UNTYPED: naming the class from `player.gd` closes a load cycle), `active_obstacles` (`aurora_calm_probe`,
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
