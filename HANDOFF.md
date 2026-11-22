# Handoff

## START HERE — desktop audit and polish, 2026-11-22

**Branch: `play/next`. Latest skating change: `8fa0bdb` (smooth recovery).**
The previous long phone-review handoff is archived at the top of `docs/history.md`.
Read this section and "Next actions"; the remainder is older obstacle-system reference.

### Stability audit

- Mobile suspend now pauses and banks progress once, clearing stale jump input in the run and
  The Melt. Android Back dismisses Reset Progress before leaving its shop.
- Failed run saves stay on results even when Home or Android Back retries the write. Retrying
  preserves the same rewards. A failed reset preserves progress. A scratch Android APK export
  and a desktop run from its exported data passed.
- The Android preset excludes root review screenshots named `Screenshot *.png`. The export
  check catches both the original resource and its imported texture path.
- The Melt keeps a failed reward save available when the player tries Home or Restart. The shop
  saves a skater purchase and its equipped choice together. Both paths passed fault-injection
  checks. See `docs/review/2026-11-22-desktop-stability-audit.md`.
- Slow obstacle searches were about 30% faster in the desktop benchmark with identical terrain
  and placements. Evidence and coverage: `docs/review/2026-11-21-mobile-readiness-audit.md`.
- A follow-up made terrain sampling cheaper and skipped 27% of ice repaints in the palette
  benchmark, with identical sampled geometry and ice colors. A real-time replay caught its
  largest draw gap just after focus loss. A window with no gameplay loaded also lost draw
  callbacks around focus changes. Measurements: `docs/research/frame_hitches_desktop.md`.

### Desktop review

- **Rewards:** crowded results give the mission and 50th-glide chests their own named taps.
  Regular overflow shows its batch size and highest tier. Rewards still bank before the reveal.
  The run HUD has outlined text; shop prices and locked achievement hints are easier to read.
- **Terrain/hazards:** fast falls tighten vertical camera follow. The plunge now shows the
  landing ice before touchdown, and normal camera metrics matched the prior build. Timed
  pickups keep 100px apart, and the pickup guard checks the full length of thin ice and other
  spans. Rendered runs cleared all three island gaps and stayed grounded over a mountain.
- **The Melt:** the faceted ice rift and outlined labels hold up against bright scenery.
  The portal caches its static drawing and only the core light pulses. The bonus screen shows
  the next chest threshold and updates the best time when the reward saves. Portal placement
  waits for enough time before the next obstacle pattern. Contact checks the actual return
  corridor, so an upcoming offscreen pattern cannot veto a safe jump into the rift.
  In a rendered run, a jump into a naturally spawned portal at 4:24 survived 36.47s,
  saved the Aurora chest once and returned to the same run pose and clock. Eight seeded
  simulations without powerups found a clear return corridor at contact.
- Review captures: `art_source/ui_review/2026-11-21-desktop-review.jpg`.
- The 50th-glide chest and achievement could arrive together with the notice overlapping Home.
  The notice now moves to the bottom right on the results screen. Rendered checks verify the
  reward pays once and the notice clears the results column at both desktop and phone widths.
- Removed a redundant spike-scene preload that caused a resource load cycle during Android
  export. The spawner already loads the same scene from its piece table when needed. A run
  launched from the exported pack spawned the spike with its collision script connected.
- The prior four seeded 12-minute headless runs exercised the live obstacle scheduler with invincibility
  and chasms enabled. Slowest decisions in tier 8 were 8.6–9.6 ms on the M4, with 74–78 late
  placements per run and zero stall recoveries.
- A rendered 12-minute desktop run with invincibility and a 60 fps cap placed 158
  patterns with zero stall recoveries. Late pattern scheduling peaked at 20.65 ms.
  From 8:00 onward, the 95th-percentile frame gap was 17.58 ms and 23 of 14,394
  gaps exceeded 25 ms. The 902 ms outlier was not attributed to a specific system.

### Current skating — owner review pending

- **Latest request:** the backward stroke is good, perhaps slightly farther; lifting and
  returning looked jerky / like "two movements". Keep the timing and smooth the recovery.
- **Current default: B - Smoother return**, shared by all five skaters and MeltView.
  Full two-leg cycle **2.0s**; alternating strokes **1.0s**; accelerating backward push
  **0.30s**, return **0.70s**. Modest **12px** lift; backward endpoint **-31px** (was-29).
  Planting leads directly into the next push, with no held extension or settling pause.
- Lift and forward travel now follow one shared arc. Push timing meets horizontal return
  acceleration at toe-off to remove the sharp change between the two curves. Physics,
  hitboxes, textures, shaders, effects and mesh/submission counts are unchanged.
- **Latest before/after:** `art_source/ui_review/2026-11-16-smooth-recovery.mp4`.
  Prior Quick push is on the left, current smoother return on the right, at the same clock.
  Both show close-up and all five skaters at game size. **This latest pass is not approved.**
- Earlier A/B/C, slow7.2s phrases, low airborne-overlap and high-knee attempts are historical
  references. Do not restore their holds or timings as if they were the owner's latest choice.
  Full reference/iteration notes: `docs/research/skating_motion_reference.md`.

### Other current work / review status

- Owner likes collection/customizations and tier/mission visuals. **Really? is approved.**
  The polished Melt portal, Still Water exit and terrain have been reviewed on desktop.
- **High-glide milestones are built, review pending:** same Really? qualification of >=6s
  uninterrupted held ascent and >=3,000px actual climb; there is no literal height ceiling.
  **10th:** "still??". **50th:** "fine, here you go" and an Ultra Mega Super Duper Chest:
  **1,000 coins + three Aurora rewards**, unique unowned finds while any remain, otherwise
  existing200–300 coin jackpots per exhausted reward. Existing Aurora art/reveal reused;
  this is a one-off bundle, not a new spawn tier. Qualification/reward tuning can be reviewed.
- Optional Save v5 `high_glide_count`, achievement flags and loot save atomically per qualifying
  flight; failed writes roll everything back. An existing Really? proves one known prior
  ascent, not a reconstructed lifetime total. Stats/reset are covered. Loot banks immediately;
  the run-end reveal is only a session-local receipt and cannot pay again. No run-score or
  coin-mission credit. See `docs/development/architecture.md` for these contracts.
- Chest tiers, permanent cosmetic collection, persistent missions, tap-to-open reveals, card
  shop, Sora headings and UI art are already built. Do not list them as missing work.

### Validation

- On November 22, all 15 full gates and all 14 rendered UI cases passed. The prior visual
  pass covered sky, ice and biome transitions. Both chasm gates passed with the plunge framing
  check (796 trials total). The old camera failed all eight plunge phases in 504 trials.
- The motion checks cover full cycles, fixed bones, blade contact, coasting, boundaries,
  acceleration through toe-off and early combined lift/forward motion. Second differences
  use1ms samples to avoid single-precision Vector2 rounding noise. Smoothness step limits
  use a4s reference cadence so the requested speedup alone does not falsely fail the path.
- The known editor rewrite of `project.godot` (only removed pins/comments and key order)
  was restored under CLAUDE's standing rule. Check status after every engine run.

### Desktop constraints

- **The owner explicitly requested desktop-only testing.** Android testing is parked.
  The ignored `aura-playtest.apk` is from the prior review, before the desktop polish.
- Automated desktop previews: **Master -24dB in memory or `--audio-driver Dummy`**. Never
  change saved volumes. Use the probe's in-memory SaveStore for automated dev/death tests;
  dev mode's99,999 wallet top-up otherwise writes the real save.
- If a desktop game is already running, stop/relaunch it to load the latest script changes.
  No need to control or close the owner's other applications during continuation.

### Next actions, in order

1. Review owner feedback on skating, the glide milestones and the portal using desktop captures.
   Tune where feedback or a reproducible issue calls for it.
2. **The owner decides when to merge `play/next` into `main`.** Backup pushes to
   `play/next` were explicitly requested.
3. The later reward ideas are a cosmetic choice after five missions, collection-set rewards
   and personal-best encouragement. Flag costly or bug-prone options before starting.

### Standing test traps

- New `class_name` needs one import before gates. Add a `/tmp` log file to every Godot command.
- Headless never draws. Visual changes need the three rendered checks; input/UI logic uses
  `regression_probe --ui-only` with a renderer and memory save. The paused lake check requests
  its own redraws because an unfocused desktop window can stop drawing.
- Headless frame counts are not real time without `--fixed-fps 60`; await tween completion.
- Keep gameplay resolving `GameServices.resolve(self)`, null-guarded; do not add bare Services
  references, new globals or physics changes for animation. Keep the code clean and lean.

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
  `check_spawn_placement`). `aurora_calm_probe` reads the spike scene path from `PIECE_KINDS`.
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
