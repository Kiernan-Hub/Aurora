# Handoff

## Where the project is — 2026-09-27, late. READ THIS FIRST

**Obstacle plan steps 1–7 are BUILT** on branch `claude/implementation-t58fc3`, **not merged to
`main`**, and every gate is green. The owner confirmed all eight decisions below and said to keep
going. **Neither air move has had its mandatory phone tap test** (the owner can't reach the phone
yet). Step 8 is the owner's art pass. This session's cloud build log is at the top of
`docs/history.md`; not required reading.

### Next actions, in order

1. **Owner: the phone tap test** for both air moves (checklist below). Needs coins: slam 300,
double jump 900. On desktop, `GameManager.debug_unlock_air_moves = true` grants both without
buying (`shipping_values_check` fails while it's on).
2. **Owner: play the obstacle half** on desktop and phone ("Owner checklist" below). After opening
the editor, run `git status`. The editor re-saves `HANDOFF.md` with tab indentation (whitespace
only; `git checkout -- HANDOFF.md`) and may strip `project.godot`'s pins (standing rule in `CLAUDE.md`).
3. **Tune by feel.** Every number is a starting value; the knobs are listed below. Any timing change
must still pass `./scripts/check.sh`. The fairness proof prints the tightest window per pattern and
fails if one goes below 7 frames.
4. **Merge to `main`** once happy: `git checkout main && git pull && git merge --ff-only
origin/claude/implementation-t58fc3 && git push`, or ask Claude to open a PR.

### The air moves as built (steps 6–7)

**Input.** One site in `player.gd` ("THE AIR-MOVE SITE"), fed by the shared jump buffer.
- On the ground, and in the landing window, **any tap jumps**, exactly as before.
- In the air, **the tap's side picks the move**: the left half of the screen slams, the right half
double-jumps. The owner asked for this split. It replaced the plan's one-button sequence (tap = double
jump, then tap = slam), under which an owner of both could never slam without double-jumping first.
- Desktop: Space/Enter/left click is the jump side; **S or right click** is the slam side (arrows
are debug speed control).
- **Landing-window rule:** a tap still live at touchdown stays the ordinary landing jump, which keeps
thin ice's rhythm and every fairness proof unchanged. A refused tap stays in the buffer.
- **Blocked** by lake, boost, Aurora flight and its landing latch, glide, and death.
- **Spin:** a jump-side press in the air still starts a spin (it double-jumps if owned, and the hold
carries on). A slam-side press is a slam for a slam owner, so spin from that side by holding through
the jump. The alternative, slam on a tap's release, adds latency and touch press-timing code. Revisit
only if it feels bad.

**Slam** (300). Sets `velocity.y` to 1,200 down, then gravity capped at 1,600 (the drop chasm's own
run-off speed, `check_slam_limits()`). One per airtime; it can only shorten a jump. It is refused
unless the simulated dive has ground all the way down, and refused when already falling faster
than 1,200, since it would slow you.

**Double jump** (900). A ground-strength impulse (upgrade and powerup included) replacing vertical
speed, one per airtime, none while slamming. Reach is at most 2× a single jump.
- **Guardrail A:** only while the feet are above the lip (the surface fall death measures against).
- **Guardrail B:** a trick after a double jump pays coins, no boost.
- A single jump's chasm, obstacle and rare-coin bounds are unchanged. A double jump carried into a
void, or reaching the rare coin from level 1, is the player's call (owner default, accepted).
- **Plan deviation:** no formula-only "2× bound" constant check. It would re-derive its own model
and could not see the real code, so the chasm trials exercise the real double jump instead.

**Shop.** `UpgradeStore.TRACKS` rows (`id`, `name`, `costs`, `hint`); `GameManager.build_shop_rows()`
builds one label and button each, and `JumpLabel`/`BuyJumpButton` are gone from `main.tscn`. A
track's max level is its cost count. Ids are save data: adding one needs no version bump, renaming one un-buys it.

**Verified:**
- `check.sh` 5/5.
- `chasm_probe` **120/120**, 0 recoveries. Ten trials per chasm, including `slam_void`, `slam_lip`,
`double_lip`, `double_rescue` (dies without a working double jump), `double_boost` and `double_late`
(must die: guardrail A refusing below the lip).
- `freeze_search` 0 stalls, plain, `--slam=1` and `--double=1`.
- `floor_flicker_probe` (full 20,000 frames, 76s with `--fixed-fps`): 0 recoveries, 0 stuck,
worst uphill flip rate 0.0000.
- `aurora_calm_probe` PASS.
- A throwaway runtime test of the real player:
  - a slam tap cuts airtime 48 → 26 frames; unowned, nothing changes;
  - a tap 4 frames before landing gives a landing jump, not a slam;
  - over a void, 0 slams, then 1 after it;
  - a double jump stretches airtime 53 → 81; a second tap is ignored; a slam-side tap with only the
double jump owned does nothing;
  - a flip after a double jump pays 5 coins and no boost, while the same handler without one boosts.
- Found on the way: `chasm_probe`'s reset never cleared the jump buffer, so a tap-every-frame trial
leaked a jump into the next one. It read as five guardrail failures. Fixed in `reset_player()`.

**Phone test (mandatory; the touch path has shipped broken twice):**
1. Buy both; each button shows OWNED.
2. Jump, then tap the **right** half at the top: a second jump.
3. Jump, then tap the **left** half: a dive.
4. Tap either half just before landing: a normal re-jump.
5. Tap left over a chasm: nothing. Fall off a lip, then tap right: nothing.
6. Hold through a jump: it still spins.
7. Without the unlocks, nothing changes.

### Commits on the branch

| Commit | Step | What |
|---|---|---|
| `413b43d` | 1 | Camera leads so the player sits 30% from the left; spawn lookaheads 800 → 1500; `check_spawn_lookahead()` |
| `1c59ead` | 1 | `camera_shake_probe` lag tolerance 0.01px (float32 rounding of the offset camera) |
| `ad9f586` | 2 | `ObstacleSpawner` becomes a pattern scheduler; one footprint guard; retry instead of drop; `check_pattern_fairness()` |
| `2e2738e` | 3 | Floating floe + shard; `TIER_START_TIMES`; placement check covers every kind |
| `2e49830` | 4 | Thin ice (`ThinIce`); Aurora director + lake probe learn it |
| `cf7c4ab` | fix | Hazard scenes load lazily (a load cycle left floes/shards script-less in some load orders) |
| `5addd81` | 5 | `TIERS`, short proven combos, forward search, fallback to singles, first-appearance rule |
| `4f4c2c5` | — | Cloud handoff; the session log moved to `docs/history.md` |
| `91a64b5` | fix | Mac review: a gliding player passes through floe/shard (decision 8) |
| `da4a857` | 6 | Shop rows from `UpgradeStore.TRACKS` + the slam; `check_slam_limits()`, `slam_*` chasm trials, `freeze_search --slam=1` |
| this one | 7 | Double jump + the left/right side split; guardrails A and B; `double_*` chasm trials, `freeze_search --double=1`; `debug_unlock_air_moves` |

Steps 1–5 were re-verified on the Mac: `check.sh` 5/5, freeze-search 0 stalls, `chasm_probe` 48/48,
`aurora_calm_probe` PASS 182,974 assertions, `sky_layer_check` PASS. `camera_shake_probe` measured
`main` and the branch on the same Mac: follow distance mean 9.87px on both, every segment's jerk
within noise, so the camera move adds no shake. **Nothing was checked visually or on the phone**;
that part is the owner's.

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
| 5 | 3:30 | triples: `spike_floe_spike`, `floe_spike_shard` (1.0s) | 3.5s |
| 6 | 5:00 | — | 3.5s shrinking 0.25s/min to the **2.5s floor** (~9:00) |

- **Each attempt**: draw a pattern for the current tier. A kind not yet seen this run is swapped for
  its solo pattern, with **+1.5s room before and after** (the tutorial). Floating patterns wait out a
  glide; every pattern waits out a boost. Then a **forward search**: the lookahead, then every 50px up to
  600px further. A combo that fits nowhere **falls back to its first piece alone**; if even that
  fails, retry in 1s. The next room counts from where the pattern really ended.
- **Footprint guard** (`is_footprint_legal`, static): ≤6° across the whole span (**except
  thin-ice-only patterns**), not on the lake, ground over `[start − 200, end + 950]`, off the Aurora
  flat. 950 = the boosted max jump's 848px + margin (it was 700: a late boosted jump could land in a chasm).
- **Measured in the live game** (7 min, 2 seeds, unkillable player): patterns per minute **2, 8, 11,
  12–15, 14–15, 14–15, 16**. That's ~51 in the first 5 min, vs **18–25** before this work: the old code
  silently dropped ~60% of slots. By minute 7 one starts every ~4s; **~12% arrive as combos**. Per
  attempt: singles place ~90%, thin ice ~96%, pairs 24–35%, triples 13–20%.

### New checks (all in `check.sh` via `terrain_invariant_check`, all mutation-tested; see `debugging.md`)
- **`check_pattern_fairness()`**: every pattern simulated at 60 Hz on flat ground, **5 jump levels ×
  {plain, √2 powerup} × {the tier's opening speed, 750}**. The only input is when to leave the ground. It
  asserts a surviving line exists and its tightest take-off window is **≥ 7 frames**
  (`PATTERN_MIN_WINDOW_FRAMES`). The lone spike measures 7: 8.57 continuous, the old "~8.6 frames".
  It also asserts both breathing-room floors outlast the longest jump (1.13s) + 0.3s.
- **Per seed**: each pattern's placement rate through the game's own `find_legal_offset()` (floors
  0.45 / 0.12 / 0.06 for 1 / 2 / 3 pieces), plus **`weakest_hop`**: the weakest jump's airtime up the
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

## Decisions Claude made without the owner: ALL CONFIRMED by the owner, 2026-09-27

1. **Step 5 was built as "option A: density first"**, not the plan's long 2–3-piece patterns. The
   terrain is rarely flat for long: 400px of ≤6° fits 15–19% of start positions, 800px 6–8%, 1,200px 3–4%
   (3 seeds). Long combos would almost never appear. So combos are short (0.5–1.0s), fall back to a
   single when they don't fit, and difficulty mostly comes from density. The alternatives, not built:
   - **B, flatten the ground under patterns** (a write-ahead flat reservation like the lake). Every combo fits, but it is a terrain change (priority #1) armed ~3,000px ahead, and the world looks flatter. Bug-prone.
   - **C, prove fairness on the real hills at spawn time.** A runtime solver that must mirror player physics exactly. Heavy on phones, and a mismatch is a false "fair".
2. **Thin ice is exempt from the 6° slope rule** (plan deviation). Held to it, a 1.2s patch fits ~5%
   of the ground. The exemption is sound only while the `weakest_hop` check passes.
3. **`PATTERN_MIN_WINDOW_FRAMES` = 7**, not the plan's ~8, because today's lone spike measures exactly 7.
4. **Powerup lookahead stays 1500**, not the plan's ~1800. It already clears the view with 230px spare.
5. **`ice_long` opens in tier 3 with `ice_short`** (weights 1 : 2), not strictly "short first, then long".
6. **Deferred to the art/audio pass:** the thin-ice crack SFX and the "player sinks" death. A crack that
   kills already plays the normal death sound. Both need new assets plus wiring.
7. **The failed-slot retry is a real difficulty change** from the old code, which dropped ~60% of slots.
   Intended ("too easy" was the brief), but it is why tiers 1–2 are already denser than before.
8. **A gliding player passes through floe and shard** (review on the Mac, after this handoff was
   first written). A glide pickup launches you 480 px/s upward whether you want it or not; even an
   instant thrust clears a floe's 200px top only ~0.34s (~260px) later. So a floe placed *before* the
   pickup and just past it was unavoidable. The "floating patterns wait out a glide" rule can't see it,
   since the floe was already there. Fix: `Obstacle.is_floating`, set from `PIECE_KINDS`, checked
   next to the boost break-through. Spikes still kill a glider. Runtime-verified (glide survives, the
   same launch without glide dies), and `check_spawn_placement` fails if the flag disagrees with the
   table (mutation-tested). The alternative was making the powerup and obstacle spawners avoid each
   other in both orders: more coupling for the same result.

## Owner checklist (phone + desktop)

1. **Feel of the density.** Is 1:00–2:30 now too busy, at ~2.5× the old count? Does 5:00+ get properly hard?
2. **Readability at 750 px/s**: floe and shard (they float against scenery), thin ice as "keep
   hopping", and the combos (e.g. spike→floe 0.5s, which needs an early jump).
3. **Thin ice grace**: is 0.2s right on touch?
4. **Camera at 30%**, on the start screen and in play; Aurora streaks, wings and framing with the player off-centre.
5. **The frozen lake's skate trail shows less of its tail.** It fades over ~860px, but only ~415–520px
   behind the player is on screen now. The near, bright half remains. Cosmetic.
6. **Possible overlap:** an air coin line (132px) or the rare coin (174px) can sit inside a floe's
   column (64–200px) when both land at the same x. Harmless (you can stay down), but it looks odd. Not guarded.
7. The first spike now appears no earlier than ~21.5s, not 20s (the first-appearance pause, plus any footprint retries).

---

## How to run things

- **Fast gates, before every commit:** `./scripts/check.sh` (Mac path built in; elsewhere
  `GODOT=/path/to/Godot ./scripts/check.sh`). ~50s.
- **Slow gates in seconds:** put **`--fixed-fps 60` before `--path`** and they run uncapped with
  identical results (verified on `aurora_calm_probe`: same assertions, same final positions, 15s instead
  of ~12min). Exact commands per gate are in `debugging.md`. Gates for the next steps: `check.sh`,
  `freeze_search`, `chasm_probe` (+ `floor_flicker_probe` for step 7).
- **In a cloud container** there is no Godot. Download the Linux build
  (`https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip`)
  into the scratchpad, then run **`--headless --path . --import` once** so the class cache knows `ThinIce`
  etc. Then `git status`: the import left `project.godot` untouched every time this session. The Android
  export check works there without templates.
- **After ANY engine run: `git status`.** Standing rule in `CLAUDE.md`.

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
  rarely place. Keep combos short or accept the fallback rate.
- **Thin ice's slope exemption depends on `weakest_hop`.** Lowering the weakest jump multiplier or
  steepening terrain fails it; then restore the slope rule for thin ice.
- **Two spikes closer than ~0.6s are unbeatable at some jump level** (0.3s = 0 frames): a higher jump
  stays up longer and carries you into the next piece. The proof catches it; don't hand-tune around it.
- **New `class_name` ⇒ one import before headless runs** (open the editor, or `--headless --import`).
- Still true: terrain chunks enter every `Area2D` (keep the player-group filter in `obstacle.gd`); place at
  `ground_y + get_terrain_height(x) − clearance`; anything spawned ahead must clear the forward view;
  `apply_upgrades()` skips headless, so probes set `has_slam`/`has_double_jump` themselves; the frame
  after a glide launch reads `is_on_floor()` true; any new `debug_*` knob goes into `shipping_values_check`.

**Docs updated this session:** `CLAUDE.md` (row 4, forward-view line), `visuals.md` (forward-view
table), `physics.md` (camera target), `terrain.md` (pattern failure codes, 950 clearance),
`debugging.md` (the new checks, `--fixed-fps`), `architecture.md` (scene graph line). Step 6 updated
`CLAUDE.md` row 9, `input.md` ("The air-move site"), `physics.md` (slam) and `debugging.md`. **Still to
update with step 7:** `CLAUDE.md` row 5 (guardrail B) and the "double jump ruled out" trap line, and
`physics.md`'s "Double jump — ruled out" section.

---

## Parked on purpose. Not blocking; don't start any of these unprompted

- **Aurora look calls:** wings rework (blocked on a reference image the owner never sent), bloom
  (recommended no). The owner has accepted the aurora as it is.
- **Natural-aurora playtest:** rarity is measured, never played. It happens whenever the owner plays.
- ~0.5 slightly late frames/s on the phone, cause unmeasured. Next lever if needed: move the ice recolour into shader uniforms.
- True 120 Hz on phones needs physics interpolation. That's a big change; flagged, not started.
- Play Store release signing / store config.

## Where the rest went

- **Past sessions:** `docs/history.md`, newest first. The top entry is this session's full log. Not required reading.
- **Phone testing** (device, adb, export/install, frame-timing method): `docs/development/debugging.md`, "Android device testing".
- **This file keeps only the current state.** At the end of a session, move its section to the top of
  `docs/history.md` and replace it here.
