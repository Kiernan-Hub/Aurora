# Handoff

## 2026-09-27 — Obstacles + air moves: the approved plan

**Steps 1–3 are BUILT** on branch `claude/implementation-t58fc3`, not merged to `main` yet. The
owner said to keep going through the obstacle steps (2–5) and stop before the air moves (6–7).
Older sessions live in `docs/history.md`; none of that is a to-do.

### Step 3 — built 2026-09-27: floating floe + shard

- `scenes/obstacles/floe.tscn` (hitbox **32×136**, 64→200px above the surface; the placeholder is exactly
  the hitbox) and `shard.tscn` (32×32 at 64–96px). Both run `obstacle.gd`, so hit, shield and boost
  break-through behave like the spike. Placeholder `ColorRect` in the absolute obstacle colour.
- `PIECE_KINDS` rows with `"floating": true`. A pattern holding one **waits out a glide** (open question 3's
  default). A new **`TIER_START_TIMES`** (`[20, 60]`): floe and shard join at 1:00. Weights are spike 2 : floe 1 : shard 1.
- `check_spawn_placement()` now places **every** kind, checks its height, and checks its real hitbox against the
  `PIECE_KINDS` row the proof reads (mutation-tested). Fairness uses each tier's own opening speed.
- **Contrast:** floating hazards are seen against scenery, not ice. Measured, obstacle red vs scenery
  and sky is ≥ **0.65** in every biome (`sunset_rose` the worst), above the gate's 0.5. No gate change.
- A runtime smoke run (real `main.tscn`, an unkillable player, 150s) placed 6 spikes, 3 shards and
  1 floe, all at the right height.
- Gates: `check.sh` 5/5, `aurora_calm_probe` PASS 182,974.
- **Not done: the first-appearance "extra room".** Every pattern is a single piece so far, so a new
  kind already arrives alone. The extra room lands with multi-piece patterns in step 5.
- **Possible look issue:** an air coin line (132px) or the rare coin (174px) can overlap a floe's column
  if both land at the same x. It is harmless, since you can stay down, but it looks odd. Not guarded.

### Step 2 — built 2026-09-27: pattern scheduler + fairness check

- `obstacle_spawner.gd` is a pattern scheduler. **`PATTERNS`**: pieces timed in seconds. **`PIECE_KINDS`**:
  scene, half width, half height, centre height above the surface. Spikes only, today's interval
  ramp. "cluster" is renamed to "pattern" throughout (`FIRST_PATTERN_TIME`, `get_pattern_hash`).
- **One footprint guard for the whole span**, static `is_footprint_legal()`: ≤6° sampled every 16px,
  not the lake, ground over `[start − 200, end + 950]`, off the Aurora flat. The void clearance is
  **700 → 950**, fixing the √2 miss. `spawn_obstacle()` keeps its own Aurora check.
- **A failed footprint now retries 1s later instead of being dropped. This is a play change.**
  The guard rejects ~60% of slots, so today most scheduled obstacles never appeared. Measured on real
  terrain over 5-min runs, 3 seeds: **18–25 obstacles → 30–33**, mean gap after 2:30 **8.6–10.7s →
  6.7–8.4s**. The audit's "one every 5s" was the *scheduled* rate, never the real one.
- **`check_pattern_fairness()`** (in `check.sh`): 60 Hz flat-ground model, 5 levels × ±powerup ×
  {speed at 20s, 750}. The backward search finds the tightest take-off window. The lone spike measures
  **7 frames**, and that is now `PATTERN_MIN_WINDOW_FRAMES`. Plus the breathing room vs the longest
  jump, and a per-seed **footprint acceptance** (spike 0.32–0.36, floor 0.25). All mutation-tested.
- Gates: `check.sh` 5/5, freeze-search 40 trials 0 stalls, chasm 48/48, `aurora_calm_probe` PASS 182,974.

**Found while building, and it decides step 5:** long patterns rarely fit this terrain. Share
of start positions where a span stays ≤6° with ground ahead, 3 seeds: 400px 15–19%, 800px 6–8%,
1,200px 3–4%. Even searching 1,500px forward, an 800px pattern fits only 22–31% of the time.
Singles fit ~100% with that search. **See "Step 5 decision" below.**

### Step 5 decision (owner): how to get combos onto hilly terrain

The plan's tier 4–6 difficulty is 2–3-piece patterns, whose whole span must be flat for the
fairness proof to hold. The terrain rarely has that (numbers above), so as planned those patterns
would appear seldom and the late game would barely get harder. Options:

- **A — Density first (recommended, lean).** Keep hazards mostly single pieces, which fit almost
  anywhere. Get difficulty from mixing the four kinds and shrinking the gap between hazards toward
  the floor (longest jump + margin, ~1.5s), so 2–3 hazards are on screen at once. Add only
  **short** combos (≤ ~0.6s, ≤ ~450px, ~50% placeable with a forward search). When a combo doesn't
  fit, fall back to a single rather than waiting. No terrain change, and the proof stays as is.
- **B — Flatten the ground under patterns.** A write-ahead flat reservation, like the lake's. Every
  combo fits, but it is a terrain change (priority #1), has to be armed ~3,000px ahead, and makes
  the world visibly flatter. Bug-prone; not recommended.
- **C — Prove fairness on the real hills at spawn time.** A runtime solver that must mirror
  player physics exactly (slope speeds, snapping). Heavy on phones, and any mismatch is a false
  "fair". Not recommended.

### Step 1 — built 2026-09-27 (cloud session)

- `main.gd`: `PLAYER_SCREEN_X_FRACTION = 0.30`. The camera target is `player_x + get_camera_forward_offset()`,
  where the offset is `(0.5 − 0.30) × viewport width ÷ live zoom`. It is also applied in `_ready()`.
  Forward view 691 → **968px** (16:9), 864 → **1,210px** (20:9).
- Lookaheads: obstacle 800 → **1500**, rare coin 800 → **1500**. **Powerup stays at 1500**
  (the plan said ~1800): it already clears the widest checked screen with 230px spare, and every
  object is ≤ 16px half-width. Keeping it also leaves `frozen_lake_director.gd`'s "+1500" reasoning true.
- **New constant check `check_spawn_lookahead()`** (in `check.sh` via `terrain_invariant`): every
  lookahead ≥ forward view on a **21:9** screen (1,270px) + 64px. Mutation-tested (800 fails).
- `camera_shake_probe` measures lag/follow distance against the new target, so its numbers stay
  comparable. Its lag-match tolerance is now 0.01px, because the offset camera x is rounded to float32.
  Rigid mode (`--smoothness=0`) read 79.5% with that rounding; it reads 100% again at 0.01px.
- **Gates** (Linux Godot 4.7.stable in the cloud container, not the Mac): `check.sh` **5/5 PASS**.
  `camera_shake_probe` (seed 941462462) is **unchanged**: follow distance mean 11.37 / max 14.23px
  (was 11.37 / 14.22), per-segment jerk within noise. `aurora_calm_probe` **PASS, 182,974
  assertions**, both live cases. Nothing else in the tree assumed a centred player: both reflections, the Aurora
  streaks and the glide-coin trail already use the real view rectangle, and the birds are screen-space.

**Owner, please look at these on the phone:**
1. The player at ~30% from the left, on the start screen and in play.
2. **The frozen lake's skate trail shows less of its tail.** It was tuned to fade over ~860px
   behind the blade, but only ~415px (16:9) to ~520px (20:9) is now visible behind the player.
   The near, brighter half remains. Cosmetic; tell me if it reads worse.
3. Aurora: streaks, wings and framing with the player off-centre.

This file is the single home for the plan until it's built. It covers the decisions, the design,
the build order, and the logistics (gates, traps, contracts, open questions).

### What happened this session

| Commit | What |
|---|---|
| `1d38bef` | Last session's doc moves (HANDOFF → `docs/history.md`) |
| `4d7208a` | **Removed the decorative ground ice formations** (`GroundTreeSpawner`, its `tree_tint` palette field in all 9 biomes, its probe/check entries). Owner: "annoying, I'll make it look good later". Last version lives at `1d38bef` |
| `4b06e93` | First version of this plan |

Gates after the removal: `check.sh` **5/5 PASS**. `sky_layer_check` **failed once** (1 violation)
on the first launch after the delete, which is the run where Godot rebuilt its class cache. It then
**passed 4/4**. The failing run's violation text wasn't kept, so the cause is likely but unproven.
If it fails again, keep the log.

### Decisions the owner made (2026-09-27)

1. **One endless run that gets harder the longer you go**, restructured as **tiers** (a new hazard
   idea about every minute) with hazards arriving in **patterns**. Levels and checkpoints are skipped
   for now; pick-your-difficulty may come later.
2. **New hazards:** ground spike, floating ice floe, floating shard, thin ice.
3. **Both air moves, as permanent shop unlocks:** **slam** (tap in the air to dive down) and
   **double jump**. This reopens the 2026-08-06 "double jump ruled out" note in `physics.md`, under
   the guardrails below.
4. The decorative ground ice is gone. Real decoration comes later with real art, and it must not
   look like a hazard.

---

## Part 1 — Why the game is too easy (audit, 2026-09-27)

| Problem | Numbers |
|---|---|
| **Two obstacles are never on screen at once** | Min gap 4s, average 5s at best: 3,000–3,750px at 750 px/s. The screen shows ~1,400–1,700px. Nothing to read ahead; every obstacle is an isolated tap. **The biggest problem** |
| One hazard, one answer | A 32×32 box, always "jump". The weakest jump (level 0) still clears it with a 139px / 0.265s window |
| Difficulty plateaus at ~2:30 | Speed caps at 2:00 (750 px/s), obstacle density at 2:30 (6 per 30s). After that only rare set pieces change |
| A stack of free passes | Untimed shield · a boost breaks through obstacles **and** spawns wait while you boost · 1s shield after a glide lands · **every landed trick grants a 3s speed boost = 3s you can't die** |
| Too little forward view | The player sits mid-screen: 691px ahead on 16:9 (0.92s at 750 px/s), ~860px on a 20:9 phone (1.15s). Half the screen shows the past |

**Smaller findings:**
- **Obstacles pop into view on phones.** They spawned 800px ahead, but a 20:9 screen showed ~860px
  ahead. The rare coin did the same. → **fixed in step 1** (both 1500, now checked).
- **The obstacle's chasm clearance has the √2 miss the chasm run-up had.**
  `OBSTACLE_VOID_CLEARANCE_AHEAD` (700) covers an unboosted jump (600px at 750 px/s) but not the
  jump-boost powerup's 848px. A *late* boosted jump over an obstacle sitting 700–850px before a void
  can land in it. An early jump is safe, so it's avoidable, but it's a reflex trap. → fixed in step 2's guard.
- The obstacle code still says "cluster" (clusters were cut). → renamed in step 2.
- `physics.md` said `FALL_DEATH_DEPTH` is 360; the code is 200. → **fixed in this commit.**

---

## Part 2 — The design

### Core rules that keep it lean

- **No hazard touches the player's physics.** Every hazard is an overlap check (`Area2D`, exactly like
  today's obstacle) or a plain x-span check (thin ice). None adds a floor, a wall or a velocity
  change, so the freeze/wall-wedge history can't come back through them.
- **You don't control speed, so you reach every x at a fixed time.** The only decision is *when to
  leave the ground* (plus the air moves). A moving or timed hazard therefore collapses into a fixed
  shape along your path. **Motion is decoration only**, never a mechanic.
- **Patterns are authored in SECONDS, not pixels.** On flat ground a jump's height over time doesn't
  depend on speed. So one frame-by-frame check can **prove** every pattern beatable at every jump
  level, with no seed sweep and no hand-derived spacing.
- **Fairness is proven for a player who owns nothing.** The air moves are unlocks and only ever *add*
  options (see the landing-window rule below), so a pattern that's fair without them stays fair with them.

### Structure: tiers and patterns

A **pattern** is 2–3 pieces inside about one screen, followed by **breathing room**. Difficulty now
comes from *combinations* and *shorter breathing room*, not from more speed (speed is tied to all
the chasm math and stays as is).

**First-appearance rule:** the first time a hazard kind shows up in a run, it comes alone, as a solo
pattern with extra room before and after. That's the tutorial; there's no tutorial text.

**Tier table: starting values, to be tuned by playing.** Speeds come from the existing ramp.

| Tier | From | Speed then | New | Breathing room |
|---|---|---|---|---|
| 1 | 0:20 | ~545 px/s | Ground spikes (today's obstacle) | today's cadence (~30s → 5s) |
| 2 | ~1:00 | ~615 | Floating floe, then floating shard | ~6s |
| 3 | ~1:45 | ~715 | Thin ice (short patches first, then long) | ~5s |
| 4 | ~2:30 | 750 | Two-piece patterns | ~4s |
| 5 | ~3:30 | 750 | Three-piece patterns | ~3.5s |
| 6 | ~5:00+ | 750 | Breathing room keeps shrinking to its floor | → **~2.5s floor** |

The breathing-room floor must stay above the longest plain jump (**1.13s**, level 4 with the jump
boost), or the end of one pattern can land you in the next. The check asserts this.

### Hazards

Jump reference (flat ground, from `physics.md`). The capsule is 32 wide and 48 tall, so its top sits
48px above the ground.

| Jump level | 0 | 1 | 2 | 3 | 4 | any + jump boost (×√2) |
|---|---|---|---|---|---|---|
| Apex (px) | 46.1 | 62.7 | 81.9 | 103.7 | 128.0 | ×2 (max 256) |
| Airtime (s) | 0.48 | 0.56 | 0.64 | 0.72 | 0.80 | ×1.41 (max 1.13) |

| Hazard | Answer | Spec (starting values) |
|---|---|---|
| **Ground spike** | Jump | Today's obstacle: 32×32 `Area2D`, `obstacle.gd`. Only the art changes (ice crystal, later) |
| **Floating floe** | Stay down | An ice island floating in the air with an icicle hanging to head height. **One hitbox column** from the icicle tip (**64px** above ground = capsule top 48 + 16 margin) up through the island. Staying grounded always passes under it; any jump near it hits it. This is the "floating islands" idea without a surface to stand on. Island height is the art pass's call; the check proves no *forced* jump in a pattern touches it |
| **Floating shard** | Stay down, **or go over if you can** | A small free-floating crystal, **32×32 at 64–96px** above ground. Levels 0–2 must stay under it (being airborne as you pass it hits it). **Levels 3–4 can jump over it** (level 3: ~0.2s / 147px window at 750 px/s; level 4: 0.4s / 300px). So upgrades open a new route instead of only making things easier. May bob gently as decoration |
| **Thin ice** | Keep hopping | A stretch of ground that cracks if you **stay on it longer than ~0.2s** (12 frames) at a time. Each landing gets a fresh 0.2s. You cross by skipping like a stone: land, tap, land, tap. The jump buffer (tap up to 0.12s before landing fires on touchdown) makes the rhythm forgiving. **Short patch** (~0.3s of travel) = clear it in one jump. **Long patch** (0.8–2.0s) = the skip. **This is the signature hazard** |

**Floe and shard are the same code as the spike**: `obstacle.gd` with a different scene (hitbox size,
height above ground). The hit logic is identical: the player-group filter, boost break-through,
`absorb_hit()`. So they are **not a new class**, and every probe that knows `Obstacle` already covers them.

**Thin ice is a span check, not an `Area2D`.** A small `ThinIce` node knows `[start_x, end_x]` and each
physics frame asks "is the player inside it, on the floor, and not boosting?" It runs a timer; past
the grace it calls `absorb_hit()`.
- **Boosting player:** passes over for free (you can't jump while boosting, and it matches "boost
  breaks through").
- **A shield (or the 1s glide-landing shield) absorbs a crack-through:** that patch then disarms,
  or the next frame would crack again.
- **The death is visual only:** the player sinks/vanishes. Nothing actually opens in the terrain.

**Example patterns** (times in seconds from the first piece; the fairness check has the final say):

| Pattern | Pieces | What it asks |
|---|---|---|
| `spike` | spike@0 | Jump (today's game) |
| `floe` / `shard` | floe@0 / shard@0 | Stay down (shard: or hop it at level 3+) |
| `ice_short` / `ice_long` | ice 0–0.3 / ice 0–1.2 | One jump over / skip across |
| `spike_floe` | spike@0, floe@0.9 | Jump early, so you land before the floe |
| `floe_spike` | floe@0, spike@0.6 | Stay under, then jump right after |
| `spike_spike` | spike@0, spike@1.0 | Two jumps (or one long boosted one) |
| `ice_under_shard` | ice 0–1.5, shard@0.7 | Keep hopping, but be on the ground at 0.7 (tier 5+) |

### Air moves (shop unlocks)

**One button does everything.** Here is the full input table once both moves exist:

| Input | On the ground | In the air |
|---|---|---|
| **Tap** | Jump (unchanged) | ① If you'll land within 0.12s: a normal queued landing jump (unchanged) · ② else the first air tap = **double jump** (if owned, unused this airtime) · ③ else = **slam** (if owned, unused) · ④ else ignored (unchanged) |
| **Hold** | Nothing | Spin (trick), or glide thrust while a glide is active (unchanged) |

So a player who owns both goes: jump → tap = second jump → tap = slam.

**Rule ① is the landing-window rule, and it's what makes the moves safe to add.** A tap just before
touching down keeps today's behaviour exactly. That:
- keeps the thin-ice skip rhythm intact;
- stops the double jump being burned by accident;
- is why "fair without the moves ⇒ fair with them" holds.

Landing time is predicted from height above the surface, vertical speed and gravity, since the
height field is pure.

**Both moves are decided at ONE site in `_physics_process`, from the shared jump buffer.** Both input
paths already feed that buffer (desktop polling, and touch via `buffer_jump()`), so the two paths can't
diverge. Touch has shipped broken twice (`input.md`).

**Both moves are blocked whenever a ground jump is**, plus while gliding:
- `is_jump_suppressed` (frozen lake);
- `is_boosting`;
- Aurora crest flight and its landing latch;
- `is_glide_active` (a tap is thrust there).

**Slam**

| | |
|---|---|
| Effect | `velocity.y` set to a dive speed (start ~1,200 px/s down), then normal gravity, **capped at 1,600 px/s**. That's the speed running off a drop chasm's lip already reaches, so collision meets nothing it hasn't already been tested against |
| Reach | Can only **shorten** a jump. Chasm math, rare coin and trick timing are untouched |
| Over a void | **Disabled.** Slamming there is instant, almost always accidental death |
| Why it's fun | The partner to floating hazards: jump the spike, slam down under the floe. Rewards skill, not forgiveness |
| Flair | Squash + snow burst on landing. **No screen shake**: the camera follow is measured and gated |

**Double jump**

| | |
|---|---|
| Effect | A second jump impulse mid-air: the same `JUMP_VELOCITY × upgrade × jump boost` as a ground jump, replacing current vertical speed |
| **Reach bound** | **Exactly 2× a single jump**, worked out 2026-09-27. Airtime is largest when the second impulse fires just before landing, giving two full jumps' worth. At 750 px/s: **1,200px** at max upgrade, **1,697px** with the jump boost. The old note feared an unknowable function; it's a simple bound, and a new constant check asserts it by sweeping every firing frame |
| Guardrail A | **Only while above the surface fall-death measures against** (`get_surface_world_y` + pending exit drop, the same function). This rules out hitting a chasm's far lip from underneath, which the physics has never been tested against. It still allows double-jumping during a drop chasm's descent |
| Guardrail B | **A trick landed in an airtime that used the double jump pays coins but no boost.** Otherwise nearly every double jump (up to 1.6s of air vs a 0.9s flip) is a free 3s invincibility button |
| Chasm policy | Restated: **a single jump from before the 900px run-up never reaches the void** (still asserted). A double jump can, and that's the player's call. By the time the second jump fires for max reach, the void is ≤600px ahead, which is on screen after step 1 |
| Rare coin | Level 1 + double jump reaches it (48 + 2×62.7 + 10 = 183px > 174). **Default: accept it** (the double jump is itself an expensive unlock). `check_rare_coin_height` states the new rule: max level, jump boost, or double jump |

**Shop side:** upgrades are saved in an open dictionary keyed by id (`save_store.gd:44`), so `"slam"` and
`"double_jump"` need **no save-version bump**, and `reset_progress()` clears them for free. The shop
screen is hard-wired to the jump track (`shop_jump_label`/`shop_jump_button` NodePaths). Step 6 turns
it into rows generated from an `UpgradeStore` table, rather than adding six more NodePaths.
**Placeholder prices: slam 300, double jump 900** (the whole jump track is 1,130).

### Ideas flagged and NOT planned (the owner's rule: bug-prone or much harder → flag it)

| Idea | Why not |
|---|---|
| Floating islands you can **stand on** | The player physics assumes the floor is the height field in ≥4 places. Slope aiming would angle you along the hill underneath; stall recovery would teleport you to the ground; the camera baseline assumes it; island edges are walls (the `large_valley` wedge class). The floe gets the look for none of that |
| Bounce floes (land on top, get relaunched) | Medium: a relaunch from height reaches further, so it needs its own chasm clearance. Maybe later |
| Wind/gusts that push you | Changes velocity mid-air, which the chasm reach math doesn't model |
| Hazards tied to the biome | Every headless gate is blind to biome code, so it would be untestable |
| Moving/timed hazards as a *mechanic* | They add no decisions (fixed arrival time) and cost reading time at 750 px/s. Decoration only |
| Levels + infinite mode | Level select, hand-made content, completion saves; fights the seeded world. Tiers give the "new chapter" feel |
| Checkpoints | Resuming mid-run rewinds ~10 systems (speed ramp, rebasing, lake/aurora directors, powerups, biome phase). The shield already works as a spare life |
| Pick your difficulty | **Later, cheap once tiers exist**: "Hard" = start at tier 3 with tighter windows. Needs separate best scores (a save change) |

---

## Part 3 — Build order

**One step per commit, `check.sh` before each, and stop after each for the owner's "go".**
Sizes are relative.

### Step 1 — Camera: more forward view (small) — **BUILT, see the top of this file**
- `main.gd`: add a constant forward offset to the camera's horizontal target, so the player sits at
  **~30% from the left**: `offset = (0.5 − 0.30) × visible world width`, read from the live viewport
  so every aspect ratio puts the player at the same screen fraction. The initial `camera_x` in `_ready()`
  gets the offset too (no swoop at spawn). The smoothing and lead are untouched.
- Result: forward view **691 → ~970px** on 16:9, **~860 → ~1,210px** on 20:9 (**~+40%**, 1.3–1.6s at 750 px/s).
- **Raise every spawn lookahead above the new forward view**, or things pop in: obstacle 800 →
  ~1,500, rare coin 800 → ~1,500, powerup 1,500 → ~1,800. Chunks (6×512 ahead) are fine.
- **Check anything that assumes the player is at screen centre:** Aurora wings/streaks, the glide-coin
  trail ("off the camera's right edge"), bird flock, start screen.
- Gates: `check.sh`, `camera_shake_probe`, then **the owner looks on the phone**. Docs: `visuals.md`'s
  forward-view table, `physics.md` camera section.

### Step 2 — Pattern scheduler + fairness check (medium) — **BUILT, see the top of this file**
- Rewrite `obstacle_spawner.gd` as a pattern scheduler, **spikes only**, reproducing today's cadence,
  so nothing changes in play. That proves the plumbing.
  - **`PATTERNS` table** (data): `{id, tier, weight, pieces: [{kind, at_s, length_s}]}`.
  - **Scheduling:** still on `speed_manager.elapsed_time`; still withheld while boosting. Patterns with
    floating pieces are also withheld while gliding (see open question 3).
  - **Placement:** `start_x = player.x + lookahead`, and each piece's `x = start_x + at_s × current_speed`.
  - **ONE footprint guard** for the whole span replaces today's four scattered checks:
    - slope ≤ 6° sampled across the span;
    - ground over `[start − 200, end + ~950]`, where **~950 = boosted reach 848 + margin, fixing the 700 miss**;
    - not the lake;
    - not the Aurora flat (+ `BODY_CLEARANCE`).
  - An illegal footprint **retries ~1s later** (the rare coin's pattern) instead of being lost.
  - The first-appearance rule, with per-run `introduced_kinds`.
  - Rename cluster → pattern.
- **`check_pattern_fairness()`** in `terrain_invariant_check` (constant-only, no scene):
  - Frame-by-frame at 60 Hz on flat ground, for a plain player (no air moves).
  - Coverage: every pattern × 5 jump levels × {plain, jump boost} × {slowest speed its tier appears at, 750}.
  - Model: capsule vs rect hitboxes, the thin-ice timer, takeoff from any grounded frame, a new jump after each landing.
  - Assert: **a surviving input exists**, and its tightest takeoff window is ≥ the tier's `MIN_WINDOW_FRAMES`
    (never below **4 frames / 67ms**; start ~8).
  - Also assert breathing room > 1.13s.
  - Today's `check_obstacle_clearance()` becomes the one-spike case. Keep its printout.
- The seed sweep **measures** patterns placed vs skipped per seed and asserts a density band (like
  coin density). A guard that skips everything must fail loudly.
- Gates: `check.sh`, `freeze-search`, `chasm_probe`, `aurora_calm_probe`.

### Step 3 — Floating floe + shard (small) — **BUILT, see the top of this file**
- Two new scenes using `obstacle.gd` (a column hitbox and a 32×32 hitbox). The spawner gets a per-kind
  `{half_height, clearance_above_ground}` table in place of the single `OBSTACLE_HALF_HEIGHT` (update
  the check that reads it).
- Placeholder art: `ColorRect` named **`ColorRect`** (`set_visual_color()` finds it by name) in the
  absolute obstacle colour.
- `check_spawn_placement()` measures a really-placed floe and shard against the surface.
- Tier 2 patterns go live. Gates: `check.sh`, `aurora_calm_probe`. Owner playtests.

### Step 4 — Thin ice (small–medium)
- `ThinIce` node (span check, above). Spawned as a piece kind.
- **Visual:** a crackled overlay sitting **just above** the surface line (see traps).
- Crack SFX: a placeholder through the existing pool.
- `lake_suppression_probe.is_spawned_item()` must learn `ThinIce` (see traps). `check_spawn_placement()`
  covers it.
- Tier 3 patterns go live. Owner tunes the grace (~0.2s) by feel on the phone.

### Step 5 — Tiers + multi-piece patterns (medium)
- The tier table, 2- and 3-piece patterns, and the breathing-room ramp to its floor. Every pattern
  passes the fairness check.
- **Tuned by the owner playing**, on the phone as well as desktop. This is where "too easy" is actually fixed.

### Step 6 — Shop rows + slam (medium)
- `UpgradeStore` gets a table of tracks (jump ×5 levels, slam ×1, double_jump ×1). The shop builds
  rows from it. `GameManager.apply_upgrades()` sets `Player.has_slam` / `has_double_jump`. It still
  skips headless, so **probes set those vars directly**.
- Slam in `player.gd` at the single air-move site, with the landing-window rule, the guards and the
  1,600 px/s cap.
- New constant check: the slam cap ≤ the run-off drop speed.
- `chasm_probe` trials: slam refused over a void; slam near a lip.
- Gates: `check.sh`, `chasm_probe`, `freeze-search`. **On-device input test is mandatory** (touch path).
- Docs: `input.md` (the air-move site), `physics.md`.

### Step 7 — Double jump (medium–large)
- At the same site, after the slam: guardrails A and B, the landing-window rule, all block flags.
- Checks:
  - the **2× reach bound** (sweep every firing frame);
  - `check_rare_coin_height` restated;
  - `check_upgrade_curve()` comments restated to "single jump";
  - `chasm_probe` trials: double jump at the lip, at max reach over each chasm width, **refused below
    the lip**, boosted, and during a drop chasm.
- Gates: `check.sh`, `chasm_probe`, `freeze-search`, `floor_flicker_probe`. **On-device input test.**
- Docs: rewrite the `physics.md` "Double jump — ruled out" section and `CLAUDE.md`'s pointer to it.

### Step 8 — Art (owner)
Ice-crystal spikes, the floe + icicle, the shard, the thin-ice cracks, slam/landing effects, and
new ground decoration. Mind the four art-swap couplings (`visuals.md`, memory) and the contrast gate.

---

## Part 4 — Logistics

### Working rules
- One step per commit; stop after each and wait for "go". `./scripts/check.sh` before every commit.
- After ANY engine run: `git status`. If `project.godot` lost only pins/comments, restore it
  (`git checkout -- project.godot`), rerun `check.sh`, and tell the owner. **Never auto-restore a scene file.**
- The owner's rule: bug-prone or much harder than an alternative → **flag it and offer the simpler
  option** before building.
- **Any input change needs an on-device check** (steps 6–7): export, `adb install -r`, and tap on
  the phone. Desktop can't exercise the touch path (`input.md`, `debugging.md` "Android device testing").
- The owner checks visuals in-game. Don't self-verify looks with screenshot captures unless debugging.

### Gates by step

| Step | `check.sh` | camera_shake | freeze-search | chasm | aurora_calm | floor_flicker | Phone |
|---|---|---|---|---|---|---|---|
| 1 camera | ✓ | ✓ | | | | | look |
| 2 scheduler | ✓ | | ✓ | ✓ | ✓ | | |
| 3 floating | ✓ | | | | ✓ | | play |
| 4 thin ice | ✓ | | | | ✓ | | play |
| 5 tiers | ✓ | | ✓ | ✓ | | | play |
| 6 slam | ✓ | | ✓ | ✓ | | | **input** |
| 7 double jump | ✓ | | ✓ | ✓ | | ✓ | **input** |

### `ObstacleSpawner`'s contract: things outside the file rely on these, so keep them
- Node path `TerrainGenerator/ObstacleSpawner` and `class_name ObstacleSpawner` (the Aurora and biome
  directors, 7 scripts).
- `debug_spawning_disabled`, a plain var set by 6 probes and checked by `shipping_values_check`.
- `spawn_obstacle(x)` + `active_obstacles`, used by `aurora_calm_probe` (×4) and `check_spawn_placement`.
- `OBSTACLE_SCENE` (`aurora_calm_probe`); `OBSTACLE_HALF_HEIGHT` and `FIRST_CLUSTER_TIME`
  (`terrain_invariant_check`), which can be renamed only together with the check.
- `apply_biome_color()` (`biome_director`).
- The spawner must stay under `TerrainGenerator` (world rebasing) and must not read `session_seed` in `_ready()`.

### Traps that apply to this work
- **Terrain chunks enter every `Area2D`.** Keep `body.is_in_group("player")` in `obstacle.gd`.
- **Thin-ice cracks can't be drawn by a spawner at the surface line.** Chunks are `add_child`ed to
  `TerrainGenerator` *after* the spawners, so they draw over anything at or below the surface, and
  there's no `z_index` anywhere. Draw the overlay just above the line, or follow `SkateTrack`'s
  sibling-after-`TerrainGenerator` pattern (with its own rebase handling).
- **`lake_suppression_probe.is_spawned_item()` only knows `Coin`/`Obstacle`/`Powerup`.** A new node
  class (`ThinIce`) would be treated as a per-chunk group, and its children scanned instead: a
  silent hole. Add it.
- **Place hazards at `ground_y + get_terrain_height(x) − clearance`** (the ground_y trap). Only
  `check_spawn_placement()` sees where a node really lands.
- **Anything that spawns ahead must spawn beyond the forward view**, which step 1 enlarges.
- **The contrast gate forces red-dominant hazards** (`biome_schedule_check`), so "ice" hazards will be
  red-family unless the owner revisits that rule at art time.
- **The frame after a glide launch reads `is_on_floor()` true** (`player.gd`, `start_glide`). The
  air-move site must not misread it. Covered by `is_glide_active` blocking the moves, but test it.
- **`GameManager.apply_upgrades()` skips headless.** Probes get no air moves unless they set
  `has_slam`/`has_double_jump` themselves, so a gate can pass while never exercising a move.
- Any new `debug_*` knob must be added to `shipping_values_check`, the only thing watching them.
- **Hazards stay off the lake and the Aurora flat.** Both are enforced by the single footprint guard;
  keep the Aurora check in the final placement path (`spawn_obstacle`).

### Open questions (owner). **Defaults in bold** are what gets built unless the owner says otherwise
1. Rare coin with the double jump: **accept that level 1+ reaches it**, or raise it for owners.
2. Slam **smashes a spike you land on** (like the boost does)? It gives the slam an attacking use.
   **Try it after step 6; off by default.**
3. Floating hazards while gliding: **held back** (a glider controls altitude and could fly into a
   floe), or allowed.
4. Unlock prices: **slam 300, double jump 900**. Placeholders.
5. Tier timings and breathing room: **the table above**, then tuned by play.
6. Hazard colour stays red-family (contrast gate)? **Yes, until the art pass.**
7. Trick boost: **keep**, except after a double jump (guardrail B).
8. Floe island height (art): **low, around 150–200px**, so it's visible mid-screen.

### Docs to update as steps land
- `CLAUDE.md`: row 4 (obstacles), row 5 (tricks), row 9 (upgrades), and the jump-upgrade trap line
  that says double jump is ruled out (step 7).
- `physics.md`: camera (step 1), slam/double jump (steps 6–7).
- `input.md`: the air-move site (step 6).
- `terrain.md`: the obstacle chasm clearance (step 2).
- `visuals.md`: forward view (step 1), hazard art sizes (step 8).
- `debugging.md`: the new checks in `terrain_invariant_check`.

---

## Current code state (so the next chat doesn't rediscover it)

- **Code:** `scripts/systems/obstacle_spawner.gd` (232 lines, one of five spawners under
  `TerrainGenerator`), `scripts/obstacles/obstacle.gd` (39 lines, `Area2D`), `scenes/obstacles/obstacle.tscn`.
  Art is a placeholder 32×32 `ColorRect`.
- **Behaviour:** singles only. First at t=20s, then density ramps in 30s windows up to 6 per window,
  with a hard 4s minimum gap. Placed only on slopes ≤ 6°, 700px void clearance ahead / 200 behind,
  lookahead 800px, and skipped (not retried) when a slot fails. A hit calls `Player.absorb_hit()`
  (a shield absorbs it); a boosting player breaks through; nothing spawns while boosting.
- **Player input today:** tap = jump (0.12s coyote + buffer), hold in the air = spin (trick) or glide
  thrust. **Hold on the ground does nothing** (unused). A landed flip pays coins + a 3s speed boost
  (`game_manager.gd:543`).
- **Shop:** one track (jump, 5 levels, 60/150/320/600 coins), hard-wired in `game_manager.gd` + `main.tscn`.
- **Score** is coins only; survival time isn't scored.

## Parked on purpose. Not blocking; don't start any of these unprompted

- **Aurora look calls:** wings rework (blocked on a reference image the owner never sent), bloom
  (recommended no). The owner has accepted the aurora as it is.
- **Natural-aurora playtest:** rarity is measured, never played. It happens whenever the owner plays.
- ~0.5 slightly late frames/s on the phone, cause unmeasured. Next lever if needed: move the ice recolour into shader uniforms.
- True 120 Hz on phones needs physics interpolation. That's a big change; flagged, not started.
- Play Store release signing / store config.

## Where the rest went

- **Past sessions:** `docs/history.md`, newest first. Not required reading.
- **Phone testing** (device, adb, export/install, frame-timing method): `docs/development/debugging.md`, "Android device testing".
- **This file keeps only the current state.** At the end of a session, move its section to the top of
  `docs/history.md` and replace it here.
