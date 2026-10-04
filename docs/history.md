# Session history

Everything that used to pile up in `HANDOFF.md`, moved here verbatim, **newest first**. When a
session ends, its `HANDOFF.md` section moves to the top of this file and `HANDOFF.md` keeps only
the current state. **This is history, not a to-do list**: many entries are superseded, and some
contradict the code. `CLAUDE.md` holds the current truth.

## 2026-09-28/29 — audit finding 1 fixed (spike approach); `debug_start_wallet`

Session on the Mac. The owner asked "read handoff.md and continue", then for free coins to test the
shop ("start me off with max tokens"), then to wrap up. **Nothing was committed**; the working tree
holds all of it (see `HANDOFF.md`'s top section for the file list and the commit steps).

- **Finding 1.** The flat-ground fairness proof let through spikes placed just past a climb. A
  terrain-aware run of the same model over accepted placements put it at ~1 in 5 spikes unbeatable
  at jump level 0 or 1 (3 seeds), plus spike-first combos. The model was matched against the audit's
  live harness at 9 positions and was never optimistic. Fix: the guard's APPROACH clause (2px,
  over the weakest jump's reach), `floe_spike_shard`'s shard 1.0s → 1.1s, placement floors lowered to the
  measured 0.32 / 0.04 / 0.01, and `check_placed_pattern_fairness()` in `terrain_invariant_check`
  (mutation-tested three ways). A "flat band" guard was measured and ruled out (22% placement).
  Everything measured, including the forward-search cost, is in `docs/research/spike_approach_fairness.md`.
- **Throwaway tools, not kept:** a terrain-aware copy of the fairness model with sweep and candidate-guard
  modes, and audit.md's live harness parameterised by `--seed/--x/--mult`. Both lived in the session
  scratchpad. The model is now `get_pattern_takeoff_window(..., terrain, start_x)` in the gate itself.
- **`GameManager.debug_start_wallet`**: tops the saved wallet up on every scene load (debug builds,
  not headless), watched by `shipping_values_check`. Left ON at 9999 at session end for the owner's shop
  tests, which blocks `check.sh` until it's reset.

The HANDOFF section this session replaced, verbatim:

> ## Audit follow-up — 2026-09-27
>
> Read **`audit.md` first**: the obstacle placement guard accepts a spike that the weakest jump
> could not clear in the live timing sweep, despite the flat-ground fairness gate passing.
> Resolve that finding before merging; the earlier green gates below do not cover it.
> The small desktop S/right-click hold mismatch is fixed, with two new behavioral cases:
> `air_move_probe` now expects **14/14**. The audit includes a self-contained fairness reproduction,
> results, limits and next steps for Claude. The prior session details below remain historical.

## 2026-09-27 (late) — Mac review of steps 1–5; the air moves (steps 6–7); `air_move_probe`

Session on the Mac, after the cloud session that built steps 1–5. The owner asked, in order:
"pull and tell me where we're at", then "do whatever you think is best" (they were away), then "go"
on the air moves, then "keep going" to step 7 with the left/right split, then this write-up.
Commits: `91a64b5`, `da4a857`, `e3bbf2b`, and the one adding `air_move_probe.gd` and this entry.
Everything stays on `claude/implementation-t58fc3`; nothing was merged.

### 1. Review of the cloud session's steps 1–5

- **Every gate re-run on the Mac** (the cloud ran Linux): `check.sh` 5/5, freeze-search 0 stalls,
chasm 48/48, `aurora_calm_probe` PASS 182,974 assertions, `sky_layer_check` PASS (9 biomes, 44 layers).
A headless `--import` came first, because `ThinIce` is a new `class_name`.
- **Camera shake, measured against `main` on the same Mac** in a temporary worktree, both with
`--fixed-fps 60`. Follow distance mean 9.87px on both (max 13.79 main, 13.82 branch), and every
segment's mean jerk within ±0.002. The cloud's "11.37 / 14.23" were Linux numbers; compare like with
like. The camera move adds no shake.
- **Things that might assume a centred player, checked in code:**
  - the glide-coin trail spawns past `camera.global_position` + half the view, so it follows the offset;
  - streaks follow the camera;
  - both reflections read the surface at the player's x on dead-flat ground;
  - `AuroraDirector.get_recovery_distance()` uses the full visible width + 512, which still covers
the 0.7 × width forward view;
  - wings attach to the player;
  - the bird flock is screen-space.

None needed a change.
- **Boost ending mid-pattern: not a problem.** A boost moves the player 3,000px (3s × 1,000). The
farthest a piece can be placed ahead is 1,500 lookahead + 600 search + 750 (a triple's last piece at
1.0s × 750) = 2,850. So everything placed before a boost is behind the player when it ends.
- **Found: a glide pickup could force an unavoidable floe death** (`91a64b5`). `start_glide()`
launches at 480 px/s up whether wanted or not. With thrust held from the first frame (net +1,200 up,
capped at 600 px/s), the feet clear a floe's 200px top only at ~0.34s, about 260px at 750 px/s.
Unheld, the apex is 72px, inside the 64–200 column. The scheduler's "floating patterns wait out a
glide" rule only covers pieces placed *during* a glide. Fix: `Obstacle.is_floating`, set from
`PIECE_KINDS`, with a glider passing floating pieces the way a booster breaks spikes.
  - Runtime test: a glide into a floe survives (touched), the same launch without a glide dies, and
a spike still kills a glider.
  - `check_spawn_placement` asserts the flag. Mutation-tested: deleting the assignment fails floe and shard.
  - Rejected alternative: make the powerup and obstacle spawners avoid each other in both spawn
orders (coupling).
  - Estimated frequency before the fix: roughly one death per ~100 min of late play.

### 2. The editor re-tabs `HANDOFF.md`

`--headless --import`, and later the owner opening the editor, re-saved `HANDOFF.md` with 4+-space
indents turned into tabs (whitespace only). Cause: `.godot/editor/editor_layout.cfg` keeps
`HANDOFF.md` and `CLAUDE.md` as open script-editor tabs. `CLAUDE.md` survives because its
continuations use 2 spaces. Reverted twice with `git checkout -- HANDOFF.md`. `HANDOFF.md` now has no
line starting with 4+ spaces (lazy list continuations), so there is nothing left to convert.

### 3. Step 6: shop rows + slam (`da4a857`)

- **Shop:** `UpgradeStore.TRACKS` is the shop, and `GameManager.build_shop_rows()` builds a
label and button per row. The hand-authored `JumpLabel`/`BuyJumpButton` were deleted from
`main.tscn`; no scene connection referenced them. A track's max level is its cost count, so
`check_upgrade_curve()` now asserts the jump track lists `JUMP_MULTIPLIERS.size() − 1` costs.
- **Slam:** one air-move site after the ground-jump branch, reading the shared jump buffer.
  - `velocity.y = 1200`, then gravity capped at 1,600. That is √(2·1600·800), the drop chasm's own
run-off speed, held by `check_slam_limits()`.
  - The landing-window rule (`will_buffered_jump_fire`): a tap still live on the frame after touchdown
stays the landing jump. It simulates the airborne integration over the height field with the
remaining buffer.
  - The void guard: the simulated dive (`get_landing_frame`, up to 60 frames) must have ground at
every sampled x.
- **Caught in review, before commit:** in a drop chasm's descent the player can already be falling
faster than 1,200, and setting it would *slow* the fall. The slam is now refused there.
- **Found while designing: the input conflict.** "Hold in the air = spin" starts with a press, and
that press is a tap, so for a slam owner it slams. It was flagged to the owner; the alternative, slam
on a short tap's release, was not built (latency, and press-timing code on the touch path).
- **Verified:**
  - Chasm 72/72, with the new `slam_void` (taps every frame from the near lip) and `slam_lip` (taps
every frame from take-off: a hop-slam loop along the run-up). 0 recoveries.
  - freeze-search `--slam=1`: 0 stalls.
  - A runtime test: a tap at frame 20 cut airtime 48 → 26; unowned it did nothing; a tap 4 frames
before landing gave no slam and two jumps; over a void, 0 slams, then 1 after.
- The owner's desktop "press again doesn't slam" was correct behaviour: their save had 34 coins and
no upgrades.

### 4. Step 7: double jump + the side split (`e3bbf2b`)

- **The owner assumed "slam is left side, double jump is right side".** The plan was one button in
sequence (first air tap = double jump, second = slam), under which an owner of both could never
slam without double-jumping first. The split was built:
  - `buffer_jump(is_slam_side)`: touch's left half is the slam side (`Main._input`);
  - desktop: `ui_accept` is the jump side, and a new `slam` action (S, right click; not the arrows,
which debug builds use for speed) is the slam side;
  - on the ground and inside the landing window, any tap jumps.
- **Double jump:** a ground-strength impulse replacing vertical speed, once per airtime, none while
slamming.
  - Guardrail A: the feet must be above `get_surface_world_y + get_pending_exit_drop`.
  - Guardrail B: `Player.has_double_jumped` is cleared at the start of the first grounded frame, so the
landing-frame trick handler can still read it, and the handler skips the boost.
- **`GameManager.debug_unlock_air_moves`** grants both for desktop testing. `shipping_values_check`
fails while it's on (mutation-tested).
- **No formula-only "2× reach" check** (plan deviation): it could only re-derive its own model.
The rare coin and upgrade-curve comments were restated as single-jump bounds, and the obstacle void
clearance comment says a double jump is the player's call.

### 5. Test-harness bugs found, and how

1. **`chasm_probe.reset_player()` never cleared the jump buffer.** The first run of the new trials
had 5 failures on the one hazard chasm (seed 683407368's three chasms are drop, hazard, drop):
  - `double_late` survived 3 of 4;
  - `double_rescue` died 2 of 4.

The trace showed phase 2 of `double_late` starting *airborne*, 110px above the lip at −22px. The
previous trial's last tap was still buffered and fired a jump at the warp point. Fix: clear the
buffer and coyote timer in the reset.
2. **`double_rescue` tapped on exactly the last frame above the lip.** On some phases float rounding
meant the probe never saw that frame (feet −10.2 → 0.0 in one step), so it never tapped. A fixed 12px
window was then skipped whole by the boosted arc (−12.9 → +1.8, ~15px per frame). Fix: the window is
one frame of the current fall plus 1px. 120/120 after.
3. **`air_move_probe`, found while writing it:**
  - A double jump also emits `jumped`, so keying "first airtime" on a jump count ended the check
exactly when the thing it looked for happened. It now tracks the first landing.
  - The grounded frame clears `has_double_jumped`, so the control sets it with no frame in between.
  - A glide case left its landing shield pending, and it absorbed the next case's floe hit (plain
launch "survived"). The warp now clears the shield state.

### 6. `air_move_probe.gd`: the throwaway tests, made a maintained gate

Twelve asserting cases, about 1s uncapped; the file header lists them. Mutation-tested, one at a
time. Each broken rule failed exactly its cases:
- guardrail B → both trick cases;
- the landing-window rule → both `landing_window` cases;
- glide pass-through → `glide_floating`;
- side selection → `double_fires`, `wrong_side`, `trick_after_double`;
- the slam void guard → `slam_over_void`.

### 7. Final gate results (Mac, Godot 4.7.stable)

- `check.sh` 5/5 (~55–65s).
- `air_move_probe` 12/12.
- Chasm 120/120, 0 recoveries.
- Freeze-search 0 stalls, plain, `--slam=1` and `--double=1`.
- Floor-flicker, full 20,000 frames × 6 seeds in 76s with `--fixed-fps`: 0 recoveries, 0 stuck, worst
uphill flip rate 0.0000, worst gravity-while-grounded 0.0009, largest forced snap 1.86px.
- `aurora_calm_probe` PASS 182,974.

**Not done:** anything on the phone, anything visual, the desktop key/mouse bindings, and a real shop
purchase. All are listed in `HANDOFF.md`, "Owner: every test nobody has done yet".

## 2026-09-27 — Obstacles + air moves: the approved plan, steps 1–5 built (HANDOFF as of `5addd81`)

**Steps 1–5 are BUILT** on branch `claude/implementation-t58fc3`, not merged to `main` yet. The
owner said to keep going through the obstacle steps (2–5) and stop before the air moves (6–7).
**Next action: the owner plays it (phone and desktop) and tunes by feel. Then says "go" for step 6
(slam), which needs an on-device input test.** Older sessions live in `docs/history.md`; none of
that is a to-do.

### Step 5 — built 2026-09-27: tiers + combos (option A, see "Step 5 decision")

- **`TIERS`** replaces `TIER_START_TIMES`: `{start, room}` per tier, from the plan's table (20s ramp,
  1:00 6s, 1:45 5s, 2:30 4s, 3:30 3.5s, 5:00 3.5s shrinking 0.25s/min to the **2.5s floor**, ±30%
  jitter). Room is measured from a pattern's **end** to the next one's start. Tier 1 keeps the old
  interval ramp. The check asserts both floors outlast the longest jump (1.13s) + 0.3s.
- **Combos, short on purpose.** Tier 4: `spike_floe`, `spike_shard`, `floe_spike`, `shard_spike`
  (0.5s apart), `spike_spike` (0.7s), `ice_spike`. Tier 5: `spike_floe_spike`, `floe_spike_shard`
  (1.0s). All proven: 9 frames each, `floe_spike_shard` exactly 7 (level 2 +boost). A sweep through
  the model showed two spikes are **unbeatable at every level closer than ~0.6s** (0.3s = 0 frames),
  hence 0.7.
- **Forward search**: each attempt tries the lookahead and every 50px up to 600px beyond it. A
  single places ~90%, a pair ~24–35%, a triple ~13–20% of attempts (per seed, via the game's own
  `find_legal_offset`). **A combo that doesn't fit falls back to its first piece alone**, so
  the run never goes quiet. The next room counts from where the pattern really landed.
- **First appearance**: a kind the run hasn't shown yet comes as its solo pattern, with 1.5s of
  extra room before and after.
- **Guard simplified**: flat across the **whole** span, unless the pattern is thin ice only.
- **Measured in the live game** (7 min, 2 seeds, unkillable player): patterns per minute
  **2, 8, 11, 12–15, 14–15, 14–15, 16**. That's ~51 in the first 5 min, against **18–25** hazards
  today. By minute 7 one starts every ~4s. About **12% arrive as combos**, including 3-piece ones.
- Gates: `check.sh` 5/5 (`terrain_invariant` now ~31s), freeze-search 0 stalls, chasm 48/48,
  `aurora_calm_probe` PASS 182,974.

**What the owner should feel for:** is 1:00–2:30 too dense now? It is ~2.5× today. Are the
combos readable at 750 px/s? Does thin ice read as "keep hopping"? Every number above is a
starting value in `TIERS` / `PATTERNS`.

### Step 4 — built 2026-09-27: thin ice

- **`ThinIce`** (`scripts/obstacles/thin_ice.gd`, a new `class_name`: **run the import once**, i.e. open
  the editor, before `check.sh`). It is a span check: a player grounded on it for more than
  **0.2 s (12 frames)** at a time calls `absorb_hit()`. Each landing resets the timer. A boost skims
  over for free. A shield absorbs the crack and the patch **disarms** (fades to 30%). The overlay is
  a `Line2D` drawn **4 px above** the surface line, where chunks can't cover it, in the absolute
  obstacle colour, and biome pushes recolour it.
- Patterns (tier 3, from **1:45**): `ice_short` 0.3 s (one jump clears it), weight 2, and `ice_long`
  1.2 s (the skip), weight 1. `TIER_START_TIMES` is `[20, 60, 105]`.
- **Deviation from the plan: thin ice skips the footprint's 6° slope rule.** Held to 6°, a 1.2 s
  patch fits ~5% of the ground. Thin ice never touches physics, and a slope only shortens or lengthens
  the hops. What makes that safe is now asserted per seed: the weakest jump still leaves the
  steepest measured ground for ≥4 frames (measured **8.2** at 20.13°). Body pieces keep the rule
  across the whole stretch between them. Placement: ice ~95%, bodies ~33%.
- The fairness model counts grounded frames on ice (13 cracks, reset per landing): `ice_short` 34
  frames, `ice_long` 12 (the grace). Mutation: grace 0.05 s ⇒ `ice_long` 3 frames, FAIL.
- **Runtime-verified in the real scene:** standing cracks on exactly the **13th** grounded frame;
  hopping each landing survives; a shield absorbs, disarms and survives.
- Coverage holes closed: `lake_suppression_probe.is_spawned_item()` knows `ThinIce`, and
  **`AuroraDirector.get_body_bounds()`** reports thin ice's span. The director found bodies only by
  collision shape, so thin ice was invisible to its reservation and to the probe's "no hazard on the
  flat" assertion.
- **Deferred to the art/audio pass (step 8), flagged:** the crack SFX and the "player sinks" death. A
  crack that kills already plays the death sound. Both need new assets plus wiring for a placeholder.
- Gates: `check.sh` 5/5, `aurora_calm_probe` PASS 182,974. Live smoke run: 8 patches from 1:45.

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

### Step 5 decision (owner): how to get combos onto hilly terrain — **A was built; B/C are still open**

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

### Step 4 — Thin ice (small–medium) — **BUILT, see the top of this file**
- `ThinIce` node (span check, above). Spawned as a piece kind.
- **Visual:** a crackled overlay sitting **just above** the surface line (see traps).
- Crack SFX: a placeholder through the existing pool.
- `lake_suppression_probe.is_spawned_item()` must learn `ThinIce` (see traps). `check_spawn_placement()`
  covers it.
- Tier 3 patterns go live. Owner tunes the grace (~0.2s) by feel on the phone.

### Step 5 — Tiers + multi-piece patterns (medium) — **BUILT as option A, see the top of this file**
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

## Android device review — 2026-09-25

**Where we are:** on `main`, clean, pushed (`1caf2d7`). Mid-way through the Android device
review (the last item before calling the Aurora work done). The biome-transition stutter is
FIXED. **The very next step is the audio + back-button checklist below. The owner has not
reported results yet.** Ask them for results; don't assume a pass.

### Next step: owner runs this on the phone and reports back

1. **Sound:** tap Start, play ~20 s. Jump and coin SFX audible? (Music is only the Aurora's
   ambient loop, so silence between SFX during a normal run is expected.)
2. **Volume slider:** pause, slider to zero, resume. SFX gone? Then restore it.
3. **Back mid-run:** should PAUSE, not quit. Back again resumes (`GameManager`, `NOTIFICATION_WM_GO_BACK_REQUEST`).
4. **Back on START/DEAD:** app closes. That's intended. On SHOP, back closes the shop.

To confirm audio from the Mac while they play: `adb shell dumpsys audio`, then look for the app's
players in the playback configurations (package `com.kiernan.aura`).

**After that, remaining (from the 2026-09-20 notes below):** owner look decisions (wings
reference image, bloom, ice/reflection), a shipping-pace playtest that waits for a natural
aurora (rarity is measured, never played), and the three windowed visual gates.

### Device setup (all working as of this session)

| Thing | Value |
|---|---|
| Phone | Galaxy S26 Ultra, `SM-S948U`, serial `R3GL20AE8BK`, 1440×3120 @ 120 Hz, Adreno 840, Vulkan |
| adb | `~/Library/Android/sdk/platform-tools/adb`, **not on PATH** |
| Export | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-debug "Android" ./aura.apk` (headless, doesn't touch `project.godot`; `aura.apk` is git-ignored) |
| Install | `adb install -r aura.apk`, then `adb shell monkey -p com.kiernan.aura -c android.intent.category.LAUNCHER 1` |
| USB | Phone must be on **"Transferring files"**. Samsung sometimes flips back to "charging only" after an install. adb kept working anyway |

- **Java path was blank → export failed.** The 2026-09-23 `ulimit` accident truncated the global
  `editor_settings-4.7.tres`. Fixed by setting `export/android/java_sdk_path` to
  `/Applications/Android Studio.app/Contents/jbr/Contents/Home` (backup of the old file in the
  session scratchpad; the truncated original is `editor_settings-4.7.tres.broken`).
  **A Godot editor (PID 37609) has been open since 2026-09-24 12:30 with the blank value in
  memory. Quitting it may write the blank back.** If the export says "A valid Java SDK path is
  required", re-set that line with the editor closed.
- **Relaunching right after `am force-stop`** once failed with "Failed to create vulkan window".
  It was a race; the next launch was fine. Wait a second between them.
- **The app sits PAUSED on the Start screen**, so `_process`-driven code does nothing until the
  owner taps Start.

### `project.godot` strip, 2026-09-24: restored, and now a standing rule

Stripped again at 12:30 (all four default-equal pins plus every comment). It coincided with that
editor opening. Restored with `git checkout -- project.godot`; `CLAUDE.md` now says to do
exactly that without asking whenever the diff is only removed pins/comments. **Also:** the
owner's ChatGPT/Codex app was launching Godot on this project at the same time. Four macOS
crash reports at 12:33, `com.openai.codex` coalition. Two agents opening Godot on one project
is a plausible repeat trigger. Mentioned to the owner; nothing done about it.

### Stutter investigation: what was measured (full write-up in `physics.md`, "Render rate on phones")

- Uncapped 120 Hz: ~1 late frame/s normally, **~7/s through a biome transition**, one ~120 ms freeze.
- **`application/run/max_fps.mobile=60` tried and REVERTED, it was worse.** The surface still
  requests 120 Hz and `max_fps` is a sleep timer, so it beat every 0.9 s. Owner also asked
  about 90 Hz (worse, 60 doesn't divide it) and true 120 Hz (needs physics interpolation,
  a big change, flagged and not started).
- Temporary per-second logcat profiling (removed before commit): **GPU ~5.5 ms of 8.3, never
  the bottleneck.** `BiomeDirector.push_palette` cost ~3 ms/push × ~12/s, half sky/background,
  half the terrain chunk repaint.
- **Fix `1caf2d7`:** `PROGRESS_EPSILON` 0.002 → 0.004, plus `_process` defers the terrain-ice half
  to the next frame. **Transition late frames 2.1/s → 0.53/s, the same as outside a transition.**
- **Still open, small:** ~0.5 slightly-late frames/s everywhere, cause unmeasured. Restarts
  cost ~80–90 ms (expected). Next lever if transitions ever hitch again: move the ice recolour
  into `ice.gdshader` uniforms.
- **Method, reusable:** frame timing = `adb shell "dumpsys SurfaceFlinger --latency '<layer>'"`,
  where `<layer>` is the full `... SurfaceView[com.kiernan.aura/...]@0(BLAST)#NNN` name from
  `dumpsys SurfaceFlinger --list` (it changes every launch). It only holds ~128 frames, so poll
  every ~0.5 s and dedupe. `adb logcat -G 16M` (caps at 5 MiB) so a long run isn't lost.

## Aurora — 2026-09-20, shipping defaults and streak coverage

Restored the three preview defaults to shipping values (`0.0`, `0.0`, `false`).
`sky_layer_check` now isolates both streak directions at 6.575 s and 13.575 s,
checks visible sky contribution and reflected ice contribution, pause stability,
zero-blend cleanup and the quiet interval. The windowed gate passed at both widths
and both night palettes. `check.sh` **5/5 PASS**; `aurora_calm_probe` **182,974 assertions PASS**.

Remaining: other windowed gates, shipping-pace playtest, Android review, and owner look decisions.
Earlier TEMP-default and 4/5 notes below describe the previous state.

## Aurora — 2026-09-20, audit #2

**Audit of the whole feature, second pass. No defect in the gameplay logic** — the schedule, the
reservation, entry/recovery, arbitration and the exclusion rules all re-read clean, and the two
things that came out of it were a documented-open flicker and a coverage hole.

| What | Detail |
|---|---|
| **Wings flicker — FIXED** | They hid on `not is_on_floor()`, but the crest releases at t = 45 s and the wings run to t = 51 s, so they blinked out for the frames the body spent falling back to the ice. `is_aurora_flight_landing` already names exactly that window; it is now part of the test. No timer, no new state |
| **The schedule and the night gate now have a gate** | `aurora_calm_probe` grew `check_schedule()` and `check_night_gate()`. PASS at **182,974** assertions (was 163,746), and the whole integration half still runs in ~2.5 s |

**What the night check is actually for.** The gate needs one *contiguous* night band longer than
the 61 s lookahead. The arc gives **142,125 px** against 61,000 px, an opening of **108.3 s in
every 800 s cycle** — which reproduces the 2026-09-16 hand measurement exactly, in all eight
rotations. One palette edit can close that, and **nothing else in the project would report it**:
taking `twilight_blue` from 0.85 to 0.75 leaves a band still wide enough to fit the event, drops
the opening to 20 s per cycle, and every other gate stays green. Verified by doing it.

**Two things the check does NOT prove, stated so a PASS is not over-read.** The over-report
assertion (`get_minimum_night_ahead` vs a 25 px scan) **cannot currently fail** — the arc has a
single night band, so no window can hold night at both ends and day in the middle. Deleting the
boundary loop from `get_minimum_night_ahead` leaves the probe green; it is kept as the guard for
a future second night pocket or shorter cycle, not as a live proof. And rarity is still
**measured, never played**.

**Worth knowing:** a bare `BiomeDirector` still carries the committed TEMP `debug_biome_seconds =
10.0`, and at that value the night lookahead reaches 457,000 px and never clears — the first
version of this check reported a night opening of zero for every rotation. `check_night_gate()`
pins the shipping values, the way `make_case()` already does for `ControlledNight`.

`check.sh` is unchanged at 4/5 — still only the three declared TEMP knobs. The list below stands.

## Aurora — 2026-09-16

**The current state is `docs/development/aurora_borealis.md`** — short, and rewritten this day to
match the code. Every earlier Aurora entry from this file (2026-09-07 → 09-13) moved verbatim to
the end of `docs/research/aurora_borealis.md`; they are history and several contradict the code.

**Audit + lean pass, 2026-09-16.** Gameplay logic re-read end to end, no defect found.
`aurora_calm_probe` PASS at **163,746** assertions after the changes; `check.sh` 4/5, failing only
on the three declared TEMP knobs.

| Commit | What |
|---|---|
| `2f19ff8` | `BackgroundStrip` no longer copies `BackgroundGenerator`'s Aurora constants — shared statics |
| `f8c9adb` | **Wisps deleted** (script, node, director push, and `sky_layer_check`'s wisp assertions, which would have failed with them disabled) |
| `111b780` | Spawners use `AuroraDirector.BODY_CLEARANCE`; lake director's Aurora lookup is an `@export` path |
| this | Docs condensed; history moved to `docs/research/` |

**Next, in order:**
1. Owner decisions: wings reference image, bloom (recommended no), brighter ice / smear reflection.
2. Restore the TEMP knobs: `BiomeDirector.debug_biome_seconds` → `0.0`,
   `AuroraDirector.debug_aurora_interval_override` → `0.0`, `debug_aurora_ignore_night` → `false`.
3. `check.sh` 5/5, then `sky_layer_check`, `ice_look_capture`, `biome_contact_sheet` in a window.
4. A shipping-pace playtest that waits for a natural aurora — **rarity is measured, not played**:
   the night gate is open ~108 s of every 800 s, on top of the 130 s run gate.
5. Android: fill rate and audio. Then merge.

## Start here

**Aura** is an Alto's-Adventure-style endless 2D skater in Godot 4.7 (GDScript, Mobile renderer,
Android). `CLAUDE.md` is the map — read it first; it points at everything else. This file is the
running log of *where the work is*, newest section first.

As of **2026-09-06**, branch head `245ad80` — the merge of `main` into this branch. The core
loop, chasms, coins, powerups, upgrades, achievements, the frozen lake and the background are all
shipped and working. Gameplay art is still placeholder rects.

**The working tree is clean and `./scripts/check.sh` passes all five gates** (re-verified
2026-09-09, 5/5, on the commit that carries this note). Everything below is a loose end, not a break.

> ### `project.godot` was stripped again between 2026-09-06 and 2026-09-08 — caught, restored
>
> Found by an audit of the aurora step. Something saved project settings after the 09-06 green
> run and dropped all four pins that equal an engine default — `viewport_width`,
> `viewport_height`, `physics_ticks_per_second`, `physics_interpolation` — plus **every comment
> in the file**. Nothing observable changed, which is exactly what makes it dangerous:
> `physics_ticks_per_second` is level geometry, and the comments were the only record of why any
> of it is pinned.
>
> **`shipping_values_check` failed on all four, by name, with the fix in its own output.** The
> text-scan gate built on 2026-08-27 did precisely the job it was built for. `git checkout --
> project.godot` restored it and the fast five went green.
>
> **Scene files still have no such cover.** `git status` showed `project.godot` as the only
> modified file this time, so nothing else was touched — but that was verified, not assumed, and
> the standing rule is unchanged: **`git status` after ANY engine run.**

## Last session — 2026-09-03: the audit's one real bug, and the gate shape that missed it

Six commits, working through the 2026-09-02 audit end to end. `check.sh` green at every step.

**The headline: rare coins and glide coins have been placed 192px too high since each file's
first commit.** `get_terrain_height()` returns an offset *from* `ground_y`, not a
TerrainGenerator-local y, and both spawners left the `ground_y` term out — while their own header
comments argued at length that it was unnecessary. The rare coin's whole reason to exist is that
its 174px clearance sits in the ~24px gap between the top two jump levels; it was actually at
366px, out of reach at every level, powerup included. The glide field's "skims the surface" 60px
floor was really 252px.

**Verified by measurement, not by reading.** A throwaway probe instantiated `main.tscn`, called
each spawner's own placement function and compared against `get_surface_world_y()` — 366.0 and
322.0 before, 174.0 and 130.0 after. The owner had believed this was already fixed in an earlier
session; it was not, and reflog/all-branches/stash confirmed no such fix ever existed. **Measure
before trusting a "we already did that", including your own.**

**Why nothing caught it, which is the more useful half.** Every item-height check in
`terrain_invariant_check` asserts a relationship *between constants* — and a constant stays
perfectly correct while the code consuming it puts the object somewhere else. `check_rare_coin_height()`
passed the entire time, because 174 was still 174. `check_spawn_placement()` is the fix: it
instantiates the scene, calls all six spawners' real placement functions, and measures the node
that actually appeared. Mutation-tested both ways.

**The glide field is owner-verified in play and needs no retune.** Its vertical *spread* was not
touched — only the anchor moved — so `TRAIL_CLEARANCE_MIN/MAX` still describe the same 1840px
band, and the owner confirmed on 2026-09-03 that the field reads correctly 192px lower. The
original eyeball-tuning happened at the wrong offset and turned out to survive the correction.
**Nothing from the audit is left open except #11–#14, which were deferred on purpose.**

Also closed: seven unwatched debug knobs added to `shipping_values_check` (40 now, was 33),
including one whose "derives from `is_debug_build()`" comment was false and which therefore
shipped whatever it held; `mist_strength` deleted after confirming no fog layer exists anywhere;
the abandoned `experiments/` background line deleted (3.8MB); a dead remote branch deleted; and
five pieces of documentation that were not stale but *wrong* — most notably `build_pano_strip.py`
calibrating from a `depth_t` the layer has never had.

**`CLAUDE.md` is back at exactly 175**, its own cap, after a compression pass. No trap was
removed to get there — the 12 lines came out of wrapping and one duplicated sentence in the
footer, and every constant, file name and rule was checked as still present afterwards.

## Earlier — 2026-08-28: night got longer, and the review knob learned to survive death

Two commits, both data or one script. No gameplay, physics, terrain or collision file touched.

- **`e3beb3a` — `twilight_blue` deepened into a real night.** This is option A of the open
  decision below, which is now closed. Night went from 1/8 of the day arc to 2/8. Full values
  and reasoning are in that section.
- **`10aeb66` — `BiomeDirector`'s review knob now resumes after a death**, the way the real
  session phase already did. Reviewing palettes with `debug_biome_seconds` used to restart the
  colour clock on every death, which made the fast-forward useless for exactly the long
  eyeballing sessions it exists for.

**Nothing visual has been verified since.** `sky_layer_check` last ran 2026-08-26, before both
of these and before the four commits of the 08-27 pass. See the top of this file.

---

## Earlier — 2026-08-27 visual pass: the green, the moon, the night sky

Seven commits, all data or one script, **no gameplay/physics/terrain/collision file touched**.
Driven by the owner playtesting with `debug_biome_seconds` and screenshotting what looked wrong.
The pattern worth carrying: **every one of these was a measurable cause, not a matter of taste**,
and in two cases the first fix was wrong because the symptom was misread.

### `glacier_teal`'s ice — "ugly green" → emerald (`65628dc`, `4855eb8`, `c5bcfe0`)

Three commits because the first two misread the request. **The owner wants it GREEN** — there is
already plenty of blue in the arc — just a better green. `65628dc` turned it cyan and was wrong.

**The murk was never the hue, it was red.** The original depth colour `(0.44, 0.87, 0.78)` had a
fine green-teal hue but `r/g = 0.51`, and red that high desaturates a green toward olive. Deep
ice is capped at `ice_depth × 0.38` (`ICE_TILE_DEPTH_FLOOR`) and that multiply **preserves the
ratio**, so the bottom of every hill rendered `(0.17, 0.33, 0.30)` at saturation 0.33 — mud. No
hue change fixes that while r stays up.

Final values came from **sampling the owner's National Geographic emerald-iceberg reference**,
not from taste. Masking to genuinely green pixels needs `g` above **both** `r` and `b` — a first
pass matching only `g > r` returned hue 193–204, which was the blue sky. Three candidates
measured; took the hero berg's jade-emerald at ~145°.

**Saturation is pushed well past the photograph on purpose.** Photos of ice carry atmospheric
light (all three references sit at r/g 0.6–0.8, saturation 0.15–0.35); reproducing that
faithfully reproduces the mud, because of the ×0.38 floor. Match the hue, roughly double the
saturation.

| | original | now |
|---|---|---|
| `ice_surface` | 0.72, 0.98, 0.91 — hue 164, sat 0.87 | **0.54, 0.93, 0.70** — hue 145 |
| `ice_depth` | 0.44, 0.87, 0.78 — r/g 0.51 | **0.14, 0.72, 0.34** — hue 141, r/g 0.19 |
| at ×0.38 floor | 0.17, 0.33, 0.30 — **sat 0.33** | 0.05, 0.27, 0.13 — **sat 0.67** |

**Both ends now sit at 141–145°**, so the band stays green top to bottom and the variation comes
from luminance (0.83 → 0.57) and saturation. Earlier attempts left the depth at 166° — teal — so
it read green at the crest and teal in the troughs, which is what kept looking wrong.
`ice_hue_variance` 0.13 → 0.17. If it needs to go greener, **push the hue toward 135, not the
saturation** — there is little headroom left before `MIN_GAMEPLAY_CONTRAST` starts fighting.

### The moon — three separate bugs (`6933860`, `f11db01`, `4508d90`)

1. **It rendered as an eclipse.** `MOON_CUT_RADIUS` was 0.36, the same as the lit core, offset by
   only `|(0.16, −0.05)| = 0.17`. Since 0.17 < 0.36 the cut **contained the disc's centre**, so
   the middle was multiplied to the 6% residual and only the rim stayed bright.
2. **Replaced with authored art** from `art_source/background/moons.png`, panel 6 of 8. The
   procedural builder is deleted — which also closed a real perf item, the 65,536-iteration
   `build_moon_texture()` loop paid on every scene load (both review docs updated).
3. **A grey disc appeared under it.** I had baked the art's halo in by subtracting a sky floor —
   but the source panel's sky brightens toward the horizon, so it left a ~5% white veil to the
   rect edge, cut to zero by a hard clamp at 2.55×. That clamp was the visible arc. Alpha is now
   the disc and nothing else, zero by 1.20×. **`SkyGlow` already draws the bloom** at the moon's
   own position, so a baked one was doubling it.

Full write-up, including the two properties of the PNG that were each got wrong once, is in
`biomes.md`, "The sun / moon disc".

### The night sky order (`a375388`)

The sun's glow arcs correctly left→right across the day. The **moon** was at x 0.30, left,
immediately before `arctic_dawn` glows at 0.16, also left — two lights on the same side, which
read as the sun rising right behind the moon. Moved to **0.62**, so it sets on the right and
leaves the left clear for dawn; rule 1 forces its two neighbours to copy the position.

Also fixed: **the moon was fading in wearing the sun's texture.** `celestial_is_moon` is the one
celestial field that does not interpolate — it snaps at the halfway point while
`celestial_strength` lerps the whole way. Both neighbours are now `is_moon = true` (strength 0,
so nothing renders; the flag only picks the texture the fade uses).

An attempt to make the moon *arc* across two night biomes was **rejected by
`biome_schedule_check`** and reverted — that is option C below.

## CLOSED decision — how much night the day arc should have (option A, `e3beb3a`)

> **DECIDED AND SHIPPED 2026-08-28: option A.** `twilight_blue` was deepened into a real night —
> gradient darkened to roughly a third of the way down to `starlit_night`, horizontal tint
> dropped to white (no warm band), the glow turned into cool moonlight at the moon's own slot,
> `star_density` 0.6 → 0.85, and scenery/haze/tree/bird tints followed the sky down so the
> silhouettes would not read as dusk against a night sky. **Night is now 2/8 of the arc.** The
> two night biomes stay distinct: `twilight_blue` is violet-leaning with no disc,
> `starlit_night` is deeper neutral navy with the moon and full stars.
>
> **B and C were not done and are still available** if night still reads short. C in particular
> is the only fix for *"the moon pops up all of a sudden"* — option A cannot address that.
> **`sky_layer_check` has not run since this shipped** (see the top of this file). The rest of
> this section is kept for its reasoning and, above all, for the disc rule at the end, which
> constrains anything anyone does to the sky next.

Raised by the owner 2026-08-27 while playtesting with `debug_biome_seconds`: *"mostly sun, some
night time, but like 2 night time or 3 isn't really enough."*

Today exactly **one** of the eight palettes is真 night (`starlit_night`, `star_density` 1.0).
`violet_dusk` (0.3) and `twilight_blue` (0.6) are dusk and twilight, not night. So night is 1/8
of the arc, ~1.7 min of a ~13.7 min cycle.

Three ways up, cheapest first:

- **A — deepen `twilight_blue` into a real night.** Darken its sky, push `star_density` 0.6 →
  ~0.85. Night reads as 2/8. **Data only, no new files, no cycle-length change, no doc updates.**
  It cannot get a second moon (see the disc rule below).
- **B — add a 9th palette, `deep_night`, after `starlit_night`.** Night becomes 3/9 and the arc
  keeps its order. Costs: one new `.tres`, a `BIOME_CYCLE` entry, and the cycle grows 8 × 75 000
  → 9 × 75 000 px (13.7 → 15.4 min). **"Eight" is written into `CLAUDE.md`, `biomes.md` and the
  build-order table** and would all need updating. `biome_schedule_check` prints `palettes=N` and
  should pass unchanged.
- **C — give `SkyCelestial` the two-node cross-dissolve `IceBand` already has.** This is the only
  thing that unlocks **the moon arcing across the night** (rising left, setting right) instead of
  sitting in one slot, and it is the real fix for *"the moon pops up all of a sudden"*. Real code
  in `sky_backdrop.gd` plus relaxing one `biome_schedule_check` rule. Medium risk, and it touches
  the one visual system whose gates need a window.

**The disc rule, which shapes all three** — `biome_schedule_check` enforces two things that are
not obvious from the palettes, and it caught an attempt to break both:

1. **No two adjacent biomes may both have a disc**, because `celestial_is_moon` snaps at the
   transition midpoint while `celestial_strength` lerps — so the texture would swap mid-fade.
2. **A disc-less biome must copy its disc-having neighbour's `celestial_position`**, or the disc
   slides across the sky as it fades. *This is why every palette shares one of two positions* —
   it is not redundancy, it is the rule.

A and B are compatible; C subsumes the moon half of both. **Recommendation was: A now** (minutes,
zero structural cost), then C only if the pop-in still reads wrong once night is longer. **A was
taken.** C remains the open follow-up, gated on whether the pop-in still reads wrong.

**The moon image arrived and is in** — `art_source/background/moons.png`, eight variants; panel
6 ("FULL MOON") is the one wired up. The other seven are still there if the crescent is ever
wanted: swapping is a one-line change to `MOON_TEXTURE`, though a crescent needs a larger
`celestial_size` to stay legible at this scale, and the extraction has two traps in it — see
`biomes.md`, "The sun / moon disc".

## Last sessions — 2026-08-26 → 27: two review items killed, one gate hardened

Two commits, `f7e500d` (docs) and `9c91c42` (the gate), both since pushed. Nothing outside
`scripts/debug/shipping_values_check.gd` and docs was touched — no gameplay, physics, terrain,
scene or shader file — so nothing here needs a gate suite to trust. `check.sh` green throughout,
5/5 in 25s, unchanged timing.

The through-line of both: **three standing claims turned out to be wrong when measured**, and
each had been costing something. Details below, but the pattern is worth carrying — this project
documents its traps well enough that the docs themselves become the thing nobody re-checks.

### #9 (Godot 4.7.2) — DECLINED, don't re-raise

4.7.2 is real and safe (released 2026-08-18, 57 fixes, "no known incompatibilities"), and so is
4.7.1 before it (78 fixes). We are on `4.7.stable`. It was still declined, on the evidence:

- **Nothing in either release touches this project.** 4.7.2 is Linux IME under KDE, Windows
  high-polling-rate mice, editor UI, PCSS **3D** shadows, 3D nav debug, **multiplayer**
  replication, mbedTLS. 4.7.1's nearest miss is an Android soft-keyboard backspace fix — Aura
  has no text input. Aura is single-player, 2D, no networking, no 3D. Zero relevant fixes.
- **The upgrade changes no file in the repo.** `config/features` stays
  `PackedStringArray("4.7", "Mobile")` across the whole 4.7.x line, so there is no "isolated
  commit" to make — the entire task is reinstalling the editor and templates, then re-running
  the fast five, chasm, lake, the three windowed visual gates and a device build.
- That is an hour-plus of the owner's time for fixes aimed at KDE and multiplayer.

**Revisit when** something actually breaks and 4.7.x is a suspect, or when 4.8 ships something
wanted. Do **not** move to the 4.8 development line.

### #8 (`main.gd` process priorities) — DOWNGRADED, the review's premise doesn't hold

The review says a *"scene reorder that looks cosmetic changes rebase and camera timing."*
Checked against `main.tscn`: **`Player` and `TerrainGenerator` are children of `Main`, not
siblings of it** (`parent="."`, and `Main` is the root). A parent's `_physics_process` always
runs before its children's, verified in-engine on 4.7.stable:

```
DEFAULT (all priorities 0): ["Main(parent)", "Player(child)", "TerrainGen(child)"]
```

So the ordering `apply_world_rebase()` depends on (`main.gd:219`) is **structural**. Reordering
`Main`'s children among themselves cannot break `Main`-before-both, which is the failure the
review was worried about. What is left is a one-line `process_priority` that documents intent
and provably changes nothing — **not** a behaviour change deserving the full physics gate suite.
Do it as a comment or a no-op pin if you like, cheaply; don't schedule gates for it.

### The `project.godot` "stripping" hazard was over-stated — corrected in the docs

The standing warning said `--editor` and both APK exports rewrite `project.godot`. **Measured on
a throwaway copy: they don't.** A cold import with `.godot/` deleted, and a full signed
`--export-debug` APK, both left `project.godot` byte-identical and touched no tracked file.

The real trigger is **a project-setting save** — which is consistent with both incidents, since
both happened while the icon/bundle id were being edited. The mechanism is documented Godot
behaviour: a setting equal to its engine default is never written, and all four pinned keys are
pinned *at* their defaults. Full write-up, with the reproduction, in `debugging.md`, "Engine
commands that rewrite `project.godot`". `CLAUDE.md`'s bullet was corrected to match.

**This makes the danger sharper, not smaller:** the four pins are invisible in the file and
`shipping_values_check` read them back identically, so if an engine default ever moved, level
geometry would change silently.

### The text-scan hardening is BUILT — 2026-08-27, review #9's last loose end

`shipping_values_check` now has a second half, `check_project_godot_declares_pins()`: it scans
`project.godot` as text and fails if any of the eight pinned keys is missing. The two halves are
complementary and the file says so — the runtime read catches a value that *drifted*, the text
scan catches a pin that *vanished*, and neither can see the other's failure.

**The reason it went unbuilt for months was a wrong premise**, which this file used to carry:
that the editor strips those keys on every open, so a text scan would cry wolf and get disabled.
It doesn't (see above), so the scan sits quiet through ordinary work.

Mutation-tested: deleting the four default-equal pins made **the runtime half still pass on all
four** — exactly the hole — while the text scan caught all four and exited 1. `--allow-temp`
still downgrades to a warning and exits 0. `check.sh` green, 5/5 in 25s, no timing change.

## Earlier — 2026-08-25, shipping hygiene: review items #6 and #10 are closed

Four commits, all pushed (`bfad804`, `1be85a0`, `4604b08`, `bd27aa8`). `origin/main` is level.
Nothing here touched physics, collision, spawning, terrain or `main.tscn`.

- **`./scripts/check.sh` exists — one command, ~25s, the before-every-commit tier.** It runs
  `shipping_values_check`, `biome_schedule_check`, `terrain_invariant_check` (`--seeds=8
  --to=300000`, hardcoded so nobody shortens it into a meaningless FAIL), `lake_suppression_probe`,
  and an export-content check. It runs **all five even after one fails**. Mutation-tested by
  flipping `debug_chasm_disabled`: two gates caught it, exit 1.
- **Project import is deliberately NOT in the runner**, against the letter of review #10. Import is
  `--headless --editor --quit`; an `--editor` run strips the pinned physics settings out of
  `project.godot`, and terrain constants derive from `physics_ticks_per_second`. A validation script
  that silently changes level geometry is worse than none. `--export-pack` was checked and does
  *not* rewrite it, which is the only reason the export check can live in a runner.
- **The export-content check verifies `exclude_filter` actually does something** — it had been in
  `export_presets.cfg` since 2026-08-24 with nothing watching it. Its forbidden list is hardcoded
  rather than read from the preset, on purpose: deriving it would make the check agree with the
  preset by construction, including when someone deletes a line from it. Mutation-tested by
  blanking `exclude_filter` — 3 of 4 paths appeared, run went red.
- **`CLAUDE.md` trimmed 201 → 179 lines**, back under its own ~175 cap. Every trap and number
  survives; four cuts removed text duplicated one level down and still linked from here.
- **The release preset is real now**: `com.kiernan.aura`, `"Aura"`, `0.1.0` / code 1, launcher
  icons cut from `art_source/aura.png` (a 3×3 sheet of nine candidates — the owner picked row 1
  col 2, the aurora). Debug keystore left alone; nothing is being published yet.

### Deferred, and fine to leave: the themed icon is the Godot robot

`launcher_icons/adaptive_monochrome_432x432` is empty, and **an empty path does not mean "no
layer"** — Godot substitutes the project icon. So on Android 13+ with themed icons enabled the
launcher shows 23,679 opaque pixels of Godot logo. Confirmed by unzipping a built APK, which is
the only way to see it.

**Explicitly deferred by the owner on 2026-08-25 — worry about it later.** It is not urgent:
nothing is being published, and it only appears in themed-icon mode. Deriving a silhouette from
the aurora tile was tried at six thresholds and produces unreadable mush — a photographic scene
has no single-colour reduction — so the fix is a **simple drawn mark** (peaks plus an arc, or
similar), which is a design decision, not a build step. Pick the mark, save it 432×432 on
transparency, point the preset at it, re-export and unzip to confirm.

The same trap already bit the *foreground* layer and is handled there: it points at a
deliberately fully-transparent PNG, because a blank path would have put the Godot logo on top of
the aurora. Don't "clean up" that empty-looking file. Full detail: `docs/development/visuals.md`,
"The app icon".

### Next, in order

**Superseded 2026-08-26 — read the top of this file first.** The owner's playtest list outranks
all of it, and the first two items are closed:

1. ~~**#9, Godot 4.7.2**~~ — **DECLINED**, reasons in the 2026-08-26 section. Don't re-raise.
2. ~~**#8, `main.gd`'s process priorities**~~ — **DOWNGRADED**; the review's premise doesn't
   hold (`Player`/`TerrainGenerator` are children of `Main`, so the ordering is structural).
   No gate suite required.
3. **The aurora borealis** — the next real feature, `docs/development/aurora_borealis.md`.
   **Planning pass first, not code**: three open questions are undecided (forced flat segment
   or not; procedural shader vs. authored sprites — and a third `.gdshader` needs real
   justification, the budget is exactly two and both are owned by ice; fixed palette vs.
   biome-reactive). Its doc also names a prerequisite — "ice canyon walls / shard spires, extra
   sky elements" — which looks **stale**: the background shipped 2026-08-24 as the baked raster
   panorama and the iceberg-sprite plan was abandoned. **Confirm with the owner** whether that
   background work is done-enough before planning the ribbons against the current sky stack.

~~Unbuilt and cheap, good filler: the `shipping_values_check` text-scan of `project.godot`~~ —
**built 2026-08-27**, see the section above. The review list has nothing cheap left on it.

~~Also still open from the review, not urgent: #7 (segment caches are never pruned)~~ —
**CLOSED won't-fix 2026-09-03 on a measurement**, ~3.7 MB per hour and freed on every restart.
See the review's own #7 for the table and the risk argument.

### The three visual gates are no longer owed — run 2026-08-26, all clean

They had been outstanding since the background commit that moved `source_skyline_y` 242 → 302.
Run with a window, as they must be; `project.godot` verified clean after each.

- **`sky_layer_check` PASS** — 9 biomes, 45 layers measured, every claimed layer above the
  24/255 floor. Tightest: `first_light` ice contrast at 13 against its own 10/255 floor.
- **`biome_contact_sheet`** — all eight render distinctly and the day arc reads in order.
- **`ice_look_capture`** — three frames, no funnel warp and no wash-out (the two failures this
  capture exists to catch). The widened panorama parallaxes correctly: different silhouettes at
  `player_x` 271 / 1645 / 7048, with the arch arriving only in the last. **No regression from
  the `source_skyline_y` change.**

**Two contact-sheet rows print an empty biome name, and that is not a bug.** `resolve_variant()`
returns `base.make_variant()`, a duplicated *in-memory* resource with no `resource_path`, and the
sheet labels rows from `palette.resource_path`. A blank label means "a rare variant rolled for
this session's salt" — rows 4 and 5 were `sunset_rose` (`variant_chance` 0.5) and `violet_dusk`
(0.2), the two most likely to roll. Only those two and `glacier_teal` have a variant at all.
Labelling them `<base> (variant)` is a one-line change in the debug script, not made.

### Read before you run any Godot command: the `project.godot` strip is wider than documented

**`--export-debug` and `--export-release` strip `project.godot`, not just `--editor`.** It
happened during this session's icon verification: `viewport_width`/`viewport_height`,
`physics_ticks_per_second`, `physics_interpolation` and every explanatory comment in the file were
deleted. Caught by `git status` and reverted; nothing shipped, and the tree is clean.

**`shipping_values_check` does NOT catch this — measured, it PASSES on the stripped file.** The
gate reads `ProjectSettings` at runtime, and the stripped keys fall back to engine defaults that
currently *equal* the pinned values. Nothing looks wrong until an engine default moves, which is
exactly what item 1 above could cause. `--export-pack` is safe and is the only export form
`check.sh` uses.

So: **`git diff project.godot` after any editor or export run**, and treat a clean `check.sh` as
no evidence at all on this one point. The cheap hardening — text-scan `project.godot` for the
pinned keys, the way the gate already text-scans `main.tscn` and for the same stated reason — is
written up in the review under #9 and **not built**.

## Older session — 2026-08-25, the three open background decisions are closed

All three of the "Open decisions" below were resolved in one pass, one commit each. **Read
each item's own status line rather than this summary** — they carry the numbers.

- **#2, the panorama repeat: measured, closed.** 106.1 s at `MAX_SPEED`, up from 54.6 s; 29%
  of the strip on screen at once, down from 56%. The loop is now 1.06 biome cycles, so a repeat
  cannot land inside one biome.
- **#1, parallax depth: decided, keeping 3.3:1.** No scene change. The two items are coupled —
  restoring 10:1 by raising `IceStrip` would have cut the loop to 35.4 s, worse than the defect
  #2 started as.
- **#3, the gate's blind spot: fixed.** `biome_schedule_check` reads the scene's real `depth_t`
  now. No palette data changed.

**Nothing in this pass touched physics, collision, spawning, or `main.tscn`.** The only code
change is inside a debug gate. `shipping_values_check` and `biome_schedule_check` both PASS;
the three windowed visual gates were **not** run and did not need to be, since no rendered
value moved — but they are still owed from the 2026-08-25 background commit below, which did
move one (`source_skyline_y` 242 → 302).

Next, per `docs/review/2026-08-24-code-and-repo-review.md`'s "Suggested order": the release
preset + export-content check and the one fast validation runner (#6 and #10, same exclude
list, do them together), then Godot 4.7.2 (#9), then `main.gd`'s process priorities (#8). The
**aurora borealis** is the next real feature and the background is no longer in its way.

Rewritten 2026-08-24. The previous version described the panorama as an unwired experiment
and was written around `PineLine`; both had been false for eight commits, and it was sending
sessions back toward finished work. The investigation history it carried now lives in
`docs/research/background_differentiation.md` — read that only if you need to know what was
already ruled out.

**Working agreement, still in force:** one numbered sub-step at a time, commit it alone, stop
and wait for an explicit "go." Flag anything with real bug potential, or with a much cheaper
alternative, before building it. Don't self-verify visuals with screenshots — the owner checks
in-game faster.

## Older session — 2026-08-25, background called done for now

**Background is being parked here, not finished.** It's in a shippable, decent-looking state;
the three open decisions from 2026-08-24 (below) are still open, and nothing here should read
as "resolved" without checking that section first.

What changed:

- **The panorama source is wider.** `art_source/background/pano.png` (5220px) supersedes
  `arch_spike_massif.png` (3548px) as `build_pano_strip.py`'s input — a fourth panel
  (`sharp.png`) was hand-stitched onto the existing art in GIMP, aligned and seam-blended by
  eye. This is a step toward open item #2 below (the panorama repeating every ~55s), since a
  wider strip takes longer to loop at the same `motion_scale` — **but the new cycle time was
  not re-measured against `MAX_SPEED`.** Do that before calling #2 closed.
- **Two smudge-tool artifacts were removed from the source.** GIMP editing left faint circular
  blotches in the empty-sky band (~y<280 of 887), invisible until a biome multiplied the layer,
  much like the "faint rectangles" failure mode `build_pano_strip.py`'s docstring already warns
  about — same symptom, different cause. Patched programmatically (soft inpaint from a blurred
  fill, not hand-painted) rather than by hand in GIMP; see the diff on `pano.png` if the method
  needs to be repeated.
- **`ice_pano.png` rebaked**, and `main.tscn`'s `IceStrip.source_skyline_y` updated 242 → 302
  to match — the blotches had been faint enough to misread as sparse "ice" by the build's sky
  model, so removing them changed where it thinks the real skyline starts. **This value moves
  whenever the art above the skyline changes; re-run the build and re-check it, don't assume
  it's stable.**
- `art_source/background/mountains.png` (an unused spare) deleted; `sharp.png`, `pano2.png`,
  `next.png` added as reference/working material. Detail on all of it in `art_source/README.md`.
- The lake reflection mirroring the now-distant mountains 1:1 was raised and deliberately left
  alone — `reflection_compression` is a documented, already-fought-over knob (see the shader's
  own comment), and the "too close" read is more an artifact of flat-silhouette art than
  something the shader should be pulled on for polish. Revisit only with a real complaint.

Gates run before this commit: `shipping_values_check`, `biome_schedule_check` — both PASS.
**Not run:** freeze-search, floor-flicker, chasm, camera-shake, `lake_suppression_probe`, or the
three windowed visual gates. Nothing here touches physics, collision, or spawning, but the
visual three (`sky_layer_check`, `ice_look_capture`, `biome_contact_sheet`) are the ones that
would actually catch a regression from the skyline_y change or the new source width — run them
before trusting this further, especially before touching background again.

## Older session — 2026-08-24, organization pass

Not background work. A cleanup pass against the two same-day reviews, then everything was
pushed: `origin/main` had been 16 commits behind and now has all of it.

- The two reviews were folded into one, `docs/review/2026-08-24-code-and-repo-review.md`.
  It is the single source for what is still open; **read its "Suggested order" before
  starting anything organizational.**
- **One real bug fixed:** pausing inflated cumulative playtime, so the frozen lake could
  arrive in a single run. `GameManager.get_unbanked_seconds()` now owns that arithmetic, and
  the planned aurora should reuse it rather than reading `Main.elapsed_time`.
- `art_source/` split into `terrain/` and `background/` (recorded as renames), and the
  panorama's source is tracked now — it was untracked and unbacked.
- Debug and experiment material no longer ships: `export_presets.cfg` has an
  `exclude_filter`. The rest of the release preset is still not release-shaped.
- `build_iceberg_sprites.py` deleted (dead), plus a sweep of `PineLine` and pre-split
  `art_source/` paths through the docs and tool headers.

Gates run: `shipping_values_check`, `biome_schedule_check`, `lake_suppression_probe` — all
PASS. **Not run:** freeze-search, floor-flicker, and the three windowed visual gates. Nothing
touched physics or rendering, but the visual three are the ones that would catch a background
regression if you want certainty before editing.

Still open, cheapest first: the release preset proper (#6), one fast validation runner (#10),
Godot 4.7.2 (#9), process priorities on `main.gd` (#8), and making `biome_schedule_check` read
the scene's real `depth_t` (#5).

## Where things actually stand

The panorama **is wired into the shipping game**. `ParallaxBackground` has four layers, three
procedural and one raster, front to back:

| Layer | `motion_scale.x` | `depth_t` | Source |
|---|---|---|---|
| `IceStrip` | 0.05 | 0.45 | `assets/textures/background/ice_pano.png` |
| `MidRidge` | 0.035 | 0.30 | `background_generator.gd` |
| `FarRidge` | 0.025 | 0.15 | `background_generator.gd` |
| `FarPeaks` | 0.015 | 0.00 | `background_generator.gd` |

`IceStrip` is the **frontmost** layer, drawn in front of the three procedural ranges, at
`skyline_y_fraction 0.33` / `horizon_y_fraction 0.55`. It is driven by
`scripts/systems/background_strip.gd`.

`ice_pano.png` is **generated, not hand-placed**. It is baked from
`art_source/background/pano.png` (as of 2026-08-25; previously `arch_spike_massif.png`) by
`scripts/tools/build_pano_strip.py`. The rebuild is deterministic on a given source — that was
verified byte-identical for `arch_spike_massif.png` during the 2026-08-24 review, not
re-verified for `pano.png` yet. The `.xcf` working files are in `art_source/background/`.

The raster-vs-biome-tint question that killed the three earlier raster attempts was answered:
greyscale × flat tint reconstructs the reference to within 3–5/255, so a baked panel does
survive the multiply. That measurement is why this attempt shipped where the others did not.

## Open decisions — the owner's call, not a cleanup

Three findings from the 2026-08-24 review are background numbers, held back from the hygiene
commits so they could land with the visual pass instead. Full detail in
`docs/review/2026-08-24-code-and-repo-review.md`, items #3, #4 and #5. **Each states its own
status below — read that before acting on it, not this heading.**

1. **Parallax depth — DECIDED 2026-08-25, keeping the current 3.3:1.** Near-to-far had gone
   from 10:1 (`0.30 … 0.03`) to 3.3:1 (`0.05 … 0.015`) when the panorama landed, and whether
   that was a re-tune or drift across eight commits was not recoverable from the commits. The
   owner's call is to keep it. **No change to `main.tscn`; the four numbers stand.**

   **Do not "restore" the old ratio later without reading this, because #1 and #2 are coupled
   and the obvious fix is the bad one.** `motion_mirroring` is fixed in *layer* px, so the loop
   distance is `mirror ÷ motion_scale` — raising the front layer to get separation shortens
   the loop in direct proportion:

   | front `motion_scale` | ratio | loop @ `MAX_SPEED` |
   |---|---|---|
   | 0.05 (now) | 3.3:1 | **106.1 s** |
   | 0.15 (10:1 by raising the front) | 10:1 | **35.4 s** |

   That is worse than the 54.6 s that made #2 a defect in the first place. Restoring 10:1 by
   raising `IceStrip` would spend the entire widen and then some.

   **If the flatness is ever actually complained about, lower the back layers instead** — it
   preserves the old spread's shape and costs nothing in loop period, because the front layer
   never moves: `0.05 / 0.0233 / 0.0100 / 0.0050` (front → back). Untested, and the far layers
   would be very nearly static, which may read worse than the flatness does. Not doing it on
   spec.
2. **The panorama's repeat — CLOSED 2026-08-25, measured.** It was ~55 s at `MAX_SPEED`
   (40,956 world px) with 56% of the strip on screen at once. After the widen it is **106.1 s
   / 79,590 world px, 29% on screen**:

   | | 2026-08-24 | now |
   |---|---|---|
   | source | 3548×887 | 5220×887 |
   | `source_skyline_y` | 242 | 302 |
   | `display_scale` | 0.577 | 0.762 |
   | `motion_mirroring.x` | 2048 layer px | 3979 layer px |
   | loop | 40,956 world px / 54.6 s | **79,590 world px / 106.1 s** |
   | on screen at once | 56% (70% on a 1440 phone) | **29% (36%)** |

   **Nearly 2×, not the ~47% the wider source alone would buy, and the reason is worth
   keeping**: `display_scale` is `(horizon_y_fraction − skyline_y_fraction) · viewport_height
   ÷ (source_horizon_y − source_skyline_y)`, so moving `source_skyline_y` 242 → 302 shrank the
   source span 247 → 187 and scaled the whole strip up 32%. 1.47 × 1.32 = 1.94. **Anything that
   moves `source_skyline_y` moves the loop period too** — the two are not independent knobs.

   The useful comparison is the biome cycle, 75,000 px: the loop was 0.55 of one and is now
   **1.06**, so a repeat can no longer land inside the same biome. Calling that enough.

   One consequence checked while measuring, since it is the failure mode
   `background_strip.gd`'s header warns about: at `display_scale` 0.762 the strip is 676 px
   tall on a 648 px viewport and now **covers the full screen height**, where at 0.577 it
   spanned y 74–586 and structurally could not reach the celestial discs at y-fraction
   0.08–0.09. Measured on the baked texture: the keyed sky band above the skyline has **mean
   alpha 0.05–0.45 / 255** (max 62 in isolated pixels). It does not occlude anything. Re-check
   this if the key-out in `build_pano_strip.py` is ever loosened.

   **Do not** add a second offset copy if this ever needs more — `motion_mirroring` is one span
   by construction and a second sprite reintroduces the tear `centered = false` exists to
   prevent. The remaining levers are the same two: raise `motion_scale`, or bake wider still.
3. **`scenery_near` is never rendered — GATE FIXED 2026-08-25, the data left alone.**
   `depth_t` tops out at 0.45, so only the far 45% of every palette's
   `scenery_far → scenery_near` ramp reaches the screen. Nothing was broken
   (`pale_morning` is the tightest at 0.100 against a 0.08 floor) but `biome_schedule_check`
   measured the *authored* endpoints and would have kept passing all the way to collapse.

   The durable half is done: the gate now reads the four layers' `depth_t` out of `main.tscn`
   via `SceneState` and applies the floor at that real range, printing it on the PASS line as
   `scenery_depth=0.00..0.45`. **No palette and no `depth_t` was changed** — the numbers are
   the same, something is finally watching them.

   **What this means for authoring, and it is the part worth remembering:** an authored
   `scenery_far`/`scenery_near` pair is roughly **twice** the separation that lands on screen.
   Widening the palette and spreading the layers' `depth_t` are interchangeable fixes and the
   gate's failure text names both.

## Before trusting this file

Run `./scripts/check.sh` (~25s, five gates). After any silhouette or palette change, also run
the three windowed visual gates (`sky_layer_check`, `ice_look_capture`, `biome_contact_sheet`),
which **must run without `--headless`** and so can never join the runner.

## Still in view

The **aurora borealis** is built and in owner review — see the top of this file and
`docs/development/aurora_borealis.md`.
