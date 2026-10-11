# Project cleanliness and maintenance audit — 2026-10-04

**Current audit: this section is Claude's action list.** The earlier audits below are preserved
as history; their priorities, branch tables and old repro line numbers are not current.

Baseline: `2486c9c`, branch `claude/implementation-t58fc3`; working tree was clean at the start.
**Only `audit.md` was changed.** No fixes, deletions, settings changes, commits, pushes or merges.

## Assessment

The project does **not** need a rewrite or a new framework. Runtime ownership is generally
sensible: one Services autoload, separate persistence/catalog components, table-driven powerups
and obstacles, and scene-local presentation systems. Most cleanup value is in contradictory
instructions, unused feature scaffolding, a few duplicated paths, and missing regression coverage.
There are also reproduced UI/persistence and gameplay defects, validation blind spots, and a
measured placement-performance concern. The second pass challenged the first report with boundary
cases, failure injection and an export mutation; its additions are A14–A19.

The runtime has 42 GDScript files and 13,635 lines: 5,686 comment-only lines, 1,713 blank lines,
and 6,236 remaining lines (including declarations). Terrain's 2,303 lines contain 996 comments;
Player's 1,185 contain 453. File length alone substantially overstates executable complexity.
Do not split everything into tiny classes just to make those numbers smaller.

Scope: runtime scripts, scene/resource wiring, shaders, asset references, persistence, input/menu
paths, spawner lifecycle, validation scripts, export configuration and current documentation.
This is a source/behavior audit with targeted measurements, not an exhaustive proof of every
input sequence or a new visual/device acceptance pass. Remote branch state was not refreshed.

## Claude's checklist

P2 = worthwhile corrective work; P3 = lower-priority cleanup or bounded follow-up.
A3 requires profiling; A13 is conditional future work; A18 requires a visual decision. These are
not instructions to implement every possible abstraction or retune approved art. There is no newly
established P0/P1 blocker. Each item below states what evidence exists and what completion means.

- [x] **A1 / P2:** Surface save failures instead of reporting a durable purchase success. *(2026-10-04: purchase only; reset/record_run still ignore it.)*
- [x] **A2 / P2:** Refresh death-screen wallet/best after shop purchases and progress reset.
- [ ] **A3 / P2:** Profile and reduce repeated obstacle-placement work without weakening fairness. *(2026-10-04: measurement added, `OBSTACLE_SEARCH_SLOWEST` in debug logcat. Cheap-clauses-first measured ~no gain, so no result-identical speedup exists. 2026-10-05 phone: 4.10 ms worst through 72 s (solo pieces); combo tiers still unmeasured.)*
- [x] **A4 / P2:** Make existing integration gates routinely runnable; cover save/menu/input regressions. *(`regression_probe` in the fast tier, in-memory save; `check.sh --full`; per-gate time limit.)*
- [x] **A5 / P2:** Reconcile current documentation and mark historical fixes as resolved. *(2026-10-04: contradictions fixed; HANDOFF 536 → 280 lines, the rest in `docs/history.md`. The older audits below stay here for now: code comments cite "audit.md, finding 1".)*
- [x] **A6 / P2:** Test coin readability using its actual sprite/tint contract. *(`biome_schedule_check` measures the real sprite × coin_color against every background; lowest 0.64.)*
- [x] **A7 / P3:** Remove the verified unused scaffolding listed below.
- [x] **A8 / P3:** Consolidate the two scene-reload paths.
- [x] **A9 / P3:** Trim historical essays in source; keep behavior-critical invariants nearby. *(The four named files, comments only, one commit each; 226 comment lines removed, every invariant and research pointer kept. Other files only when next touched.)*
- [x] **A10 / P3:** Make biome captures cover all nine base palettes reproducibly. *(Pinned rotation 0 and a no-variant salt; labelled files; exit 1 on a failed save.)*
- [x] **A11 / P2:** Protect source-art exclusion in the export gate. *(Mutation in a disposable copy not re-run.)*
- [x] **A12 / P3:** Give historical artifacts a clear retention/indexing policy. *(`art_source/README.md`: per-folder purpose and rule. No files deleted; that is the owner's call.)*
- [ ] **A13 / P3:** Keep future extractions small and tied to an actual maintenance need.
- [x] **A14 / P2:** Preserve buffered landing jumps when air upgrades are owned. *(Landing window judged one frame early; `landing_edge` + `landing_model` in `air_move_probe`.)*
- [x] **A15 / P2:** Stop late pickup callbacks from changing an already-finalized run.
- [x] **A16 / P2:** Make physics gates fail on detected failures/incomplete runs. *(Also: `check.sh` now fails a gate whose script doesn't parse/load. Godot exits 0 then.)*
- [x] **A17 / P3:** Reject non-finite/out-of-range save numbers field by field.
- [x] **A18 / P3:** Resolve the skate-track halo/core modulation contract after visual review. *(Owner kept the look: each line fades via self_modulate, core strength now states its real 0.285 x blend^2. Pixel-identical by construction.)*
- [x] **A19 / P3:** Reuse unchanged Aurora streak gradients.

### A1 — Purchases report success when persistence fails

**Evidence:** `scripts/systems/save_store.gd:206` returns `void` on every path, including open,
write and rename failures. `scripts/systems/upgrade_store.gd:172` debits the wallet, grants the
level, calls it, and unconditionally returns `true`. `scripts/game/game_manager.gd:756` then
plays success feedback and applies the upgrade. The previous truncated-save fix is present;
this is a separate failure-propagation problem.

**Reproduced in an isolated copy:** save wallet 1,000 successfully; create a directory at the
temporary-save filename to force `FileAccess.open` to fail; purchase Slam; reload a fresh store.

```text
AUDIT_PURCHASE returned=true memory_wallet=700 memory_slam=1 disk_wallet=1000 disk_slam=0
```

The old disk save survives correctly, but after relaunch the apparently successful purchase is
gone and the old wallet returns. This does not demonstrate permanent coin loss.

**Change:** return an explicit save result. Let purchase success mean a successfully persisted
transaction; on failure restore the pre-purchase memory values and give concise failure feedback.
Inspect reset/settings callers for the same false-success presentation, without conflating
`record_run()`'s existing “new best” return value with save success. Preserve atomic replacement
and the existing write/flush checks.

**Done when:** successful purchase survives reload; open/write/rename failure preserves the last
good disk save and does not announce/grant a successful purchase. Tests must use isolated paths.

### A2 — Death-screen values become stale after visiting the shop

**Evidence:** `scripts/game/game_manager.gd:565–586` constructs `death_stats_label.text` once at
death. `_on_buy_pressed()` and `_on_reset_progress_confirmed()` refresh only the shop;
`_on_shop_close_pressed()` and Android Back simply reveal the old death screen. The wallet
purchase case is already documented from the October 4 phone test in `HANDOFF.md:22` and remains
unfixed in this baseline. Reset also leaves the stored best/wallet portion stale by inspection.

**Change:** keep a small run-result snapshot, and one label-refresh method that combines those
run facts with the current saved wallet/best. Refresh when returning to DEAD, including Android
Back. Preserve Coins/Time as the completed run's result. Do **not** call `_on_player_died()` to
refresh: that would bank the run again.

**Done when:** death → shop → buy → Back and death → shop → reset → Back show correct persisted
values, retain appropriate run results, and never award the same run's coins twice.

### A3 — Obstacle search repeats expensive terrain work in one physics tick

**Evidence:** `scripts/systems/obstacle_spawner.gd:292`, `:413`, `:459–509`.
A scheduled combo tries up to 13 starts, repeatedly walks its span/approaches, and on rejection
can perform another search for a solo fallback. This is actual repeated work, not a file-size
concern. HANDOFF already flags this as a possible source of late frames.

Measured here on the Mac, headless, with a prewarmed terrain cache, seed `683407368`, speed 750,
250 positions per row (`x = 20000 + i * 1000`, `i=0..249`), timing `find_legal_offset()`:

| Pattern | Median | 95th percentile | Maximum |
|---|---:|---:|---:|
| spike | 0.246 ms | 0.751 ms | 1.124 ms |
| spike_floe_spike | 0.428 ms | 6.804 ms | 11.102 ms |
| floe_spike_shard | 0.519 ms | 7.835 ms | 11.700 ms |

A 60 Hz frame has 16.67 ms for **all** work. These timings exclude solo fallback, node creation
and rendering; they are a microbenchmark, not measured Android stutter or a whole-frame profile.

**Change:** instrument natural failed/successful searches on the phone first. Then reduce repeated
queries or reject impossible spans earlier, locally within this search. Avoid a global cache or
multi-frame scheduler unless simpler changes are insufficient. Preserve the first legal offset,
seeded decisions, write-ahead reservation rules and all safety clauses. Never reduce sampling or
weaken fairness thresholds merely to improve the timing.

**Done when:** identical placements for a deterministic comparison corpus, unchanged fairness and
density results, and measured improvement in worst-case search/frame timing on target hardware.

### A4 — Routine validation misses important integration and failure paths

**Evidence:** `scripts/check.sh:60–65` runs four GDScript gates and the export check. It omits the
existing `air_move_probe.gd` and `aurora_calm_probe.gd`. The former verifies shop row population,
not purchases. No active probe exercises failed save writes, malformed save fields, the touch-index
release sequence, or the pause-menu biome banking callbacks. Earlier fixes for these paths exist,
but their historical ad-hoc reproductions are not maintained regression gates.

**Change:** include the two existing integration probes in a documented normal command, or add one
small explicit integration tier to this runner. Add focused behavioral regressions for A1/A2,
malformed save containers, multi-touch release, and pause → restart/home phase continuity. Keep
physics and rendered checks selectable; a new testing framework is unnecessary. Give gate processes
a timeout with useful output so an accidental paused harness cannot hang the whole runner forever.

**Isolation matters:** Services still loads a real save in headless runs; rendering enables more
production behavior. Visual probes instantiate the ordinary scene and do not establish an isolated
SaveStore themselves. Do not assume `--headless`, `--log-file`, or a temporary project directory
isolates `user://`. This audit explicitly redirected both save filenames in its temporary copy.
Establish one documented scratch-save harness procedure for every test that can purchase, reset,
finish events, or leave PLAYING. Do not delete production headless guards as a cleanup shortcut.

**Done when:** one discoverable command runs the selected gates, listed historical regressions have
positive and negative cases, and a developer's normal save is byte-identical after the test run.

### A5 — Current instructions contradict one another

**Evidence/examples:**

- `README.md:34` says exactly twelve maintained checks. There are 15 top-level `.gd` debug files:
  14 maintained checks/capture tools plus `ice_seam_probe`, the non-asserting diagnostic. The debug
  inventory also needs to distinguish pass/fail gates from captures and metric-only probes.
- `CLAUDE.md:9` still says obstacles are “next up”; its later build table and the current code say
  they are built. `HANDOFF.md` is 536 lines despite the stated “current state only” contract.
- HANDOFF's top records October 4 Android testing, while its later sections still say no Android
  build or actual purchases have run. Retain A5/A8 and readability/density as unverified; do not
  erase the device results or turn partial acceptance into complete acceptance.
- `scripts/check.sh:27–32` still attributes automatic setting stripping to an editor run;
  `docs/development/debugging.md` first makes similar broad claims and later corrects them.
  Keep one current account of the settings-save trigger, with the measured exceptions.
- `scripts/autoload/services.gd:12` says script runs do not register autoloads, while `:37–42`
  correctly says the node does exist. The `resolve()` comment and an UpgradeStore comment repeat
  the wrong claim. Distinguish the global identifier from the node and its initialization order.
- `CLAUDE.md`/CoinSpawner/BiomeDirector still describe coins as absolute colors; the Sprite2D
  implementation multiplies the texture by `modulate` (see A6).
- `shaders/ice.gdshader:3` says it is the only shader; three exist. Several “future lake/audio”
  comments describe already implemented features.
- `docs/review/2026-09-20-project-audit.md` still presents its four bugs as open, although the current
  implementations address them. Root audit history contains later resolutions, forcing readers
  to reconcile several reports themselves.

**Change:** use README for entry commands, CLAUDE for enduring constraints, HANDOFF for current
state/next work, and `docs/history.md`/research for history. Make `debugging.md` the authoritative
check inventory and link it elsewhere. Add dated resolution notes to old audits rather than
silently rewriting their original findings. Archive superseded HANDOFF sections and, on a later
documentation pass, older root audit sections while preserving links/reproduction context.

**Done when:** a new contributor can identify current work, run checks and understand headless
behavior without reconciling contradictory instructions. Keep the safety invariants intact.

### A6 — The contrast gate does not model the current coin renderer

**Evidence:** `scripts/pickups/coin.gd:60–86` uses `target.modulate = color`; the coin scene's
Visual is a textured Sprite2D. `scripts/debug/biome_schedule_check.gd:476–506` compares the raw
`palette.coin_color` against raw palette backgrounds, treating it like the old absolute fill.
It never measures the coin texture multiplied by that color. It also explicitly checks authored
endpoints only. This is a coverage/contract mismatch, **not proof that today's coins are unreadable**.

**Change:** retain cheap palette-authoring checks but label their scope accurately. Add a small
rendered readability check/review using the actual sprite in each biome and representative channel
transitions; account for outline/highlight/body rather than asserting every pixel has one color.
Do not recolor approved art just to satisfy the old metric. Keep collision/scale unchanged.

**Done when:** a material degradation of the rendered coin can be caught even if all authored
palette colors still pass, and the docs describe the actual multiplicative tint.

### A7 — Remove unused scaffolding, not useful shared behavior

Checked declarations/call sites across runtime, scenes/resources, active probes and archive scripts.
The following are concrete cleanup candidates; recheck references immediately before deleting.

| Location | Evidence | Smallest cleanup |
|---|---|---|
| `scripts/autoload/services.gd:58–64,88–92` | MusicPlayer is created but never assigned a stream or played. AuroraAudio owns the actual ambient voice. | Remove the empty player/property and obsolete future-music explanation; retain Music bus volume controls. |
| `scripts/game/game_manager.gd:214,539–543`; `scripts/systems/sfx_player.gd:13,65` | Every jump calls a no-op handler; `play_jump()` has no callers. | Remove the no-op connection/handler and unused SFX wrapper/preload. Preserve Player's `jumped` signal, which probes use. Remove/archive the unused WAV and its import metadata together only after reference recheck. |
| `scripts/systems/background_generator.gd:50–54,84–86,353–354,425–460` | All three authored generator layers are ridges (`shape_kind = 0`); no script/scene selects pines. | Remove dormant pine generation and its Inspector knobs if keeping the current art direction; update the obsolete pines section in visuals.md. This is unused by the current project, not an engine-unreachable branch. |
| `scripts/systems/upgrade_store.gd:135,158` | `get_max_jump_multiplier()` and `is_maxed()` have no callers. | Delete the unused wrappers unless an immediate caller is part of the same change. |
| `scripts/systems/achievement_manager.gd:131` | `is_unlocked()` has no callers; no gallery uses it. | Remove the speculative API until needed. Keep the live achievement table, trigger listeners and persistence. |
| `scripts/systems/glide_coin_spawner.gd:247–255` | All three callers pass `null` for `tint`; none uses its Color branch. | Remove the unused parameter/branch; preserve biome tinting and the bonus diamond exception. |

**Done when:** no missing refs/import errors, fast/integration checks pass, and the relevant rendered
sky/pickup checks pass. Do not introduce a generic “shared spawner” base class for a few similar loops.

### A8 — Two reload handlers duplicate the same transition contract

**Evidence:** `scripts/game/game_manager.gd:633–659`. Home and quick restart both play a click,
bank biome phase when paused, save settings, unpause and reload. Quick restart additionally sets
`pending_quick_restart`. Past biome-banking fixes had to update both copies.

**Change:** put that sequence in one small helper with an explicit quick-start parameter; retain
clear button callbacks. Route the reload-only unpause through that helper and document its bounded
exception to `set_state()` ownership. No state-machine framework is needed.

**Done when:** restart/home from PAUSED and DEAD preserve phase/settings, choose the intended next
screen, and do not double-bank coins/playtime. Preserve draw order and scene-reload semantics.

### A9 — Historical explanations obscure small live implementations

**Evidence:** `scripts/systems/world_rebaser.gd` has 83 comment-only lines out of 96 for one short
function; SaveStore has 144 of 287; SkyBackdrop has 429 of 843. Many blocks retain both an old
claim and its later correction. Research documents already hold much of this history.

**Change:** retain a concise contract, the essential “why”, and one research link at each sensitive
site. Move measurements, abandoned designs and dated rebuttals to the existing research document.
Start with WorldRebaser, Services, SaveStore and GameManager's playtime comments. Preserve warnings
about pure terrain sampling, seed-ready order, floor/chasm behavior, save atomicity and draw order.

**Done when:** live behavior is easy to scan without losing the reason a non-obvious guard exists.
Avoid arbitrary line-count targets, deleting all comments, or merely duplicating the essays elsewhere.

### A10 — The biome contact sheet omits a rotating palette

**Evidence:** `scripts/debug/biome_contact_sheet.gd:81–87` captures absolute indices 0 through 7,
while `BiomeDirector.get_cycle_base_palette()` reserves index 0 for `first_light` outside the
8-palette rotation. Result: intro + seven rotating palettes. Rotation and variants are session-random,
so the omitted palette and variant selection are not a stable comparison baseline. This older audit
observation is still present. `sky_layer_check` independently covers all nine; this is a capture-tool defect.

**Change:** capture intro separately plus a complete eight-entry cycle; fix rotation/variant salt
for the baseline and identify palette/variant in filenames or a manifest. Capture variants explicitly
if needed. Check image-save errors instead of always ending successfully after an unsuccessful write.

**Done when:** nine distinct base palettes are represented with stable labels/order and write failures
are reported. Run rendered, with scratch save isolation; headless output cannot validate this tool.

### A11 — Export validation omits the largest accidental-bloat path

**Evidence:** `scripts/check.sh:78–83` forbids debug and experiment paths but not `art_source/`.
The tracked source/reference tree is **96.39 MiB**, versus **8.63 MiB** under assets. Its
`.gdignore` currently prevents import. With `export_filter="all_resources"`, losing that protection
makes source art eligible for import/export while the current forbidden-path list still passes.

**Second-pass mutation confirmed:** a full disposable copy, including source art, exported a
7,052,072-byte pack with the ignore file. Removing only `art_source/.gdignore`, reimporting, and
exporting produced **67,246,304 bytes**: +60,194,232 bytes (about **57.4 MiB**), with 196
`art_source/` byte-string matches and none of the existing four forbidden prefixes. The matches
are a byte scan, not a parsed resource count. This confirms a latent protection gap; the current
unmodified export does **not** contain source art.

**Change:** add `res://art_source` to the independent export exclusion assertions and explicitly
check that its `.gdignore` remains present. Exercise the protection in a disposable project containing
the source art. Do not infer exclusion solely from the preset or from a copy that omitted source files.

**Done when:** the normal export passes and removing the source-art import protection in the disposable
fixture causes a failure. Do not weaken the existing independent forbidden-path check.

### A12 — Repository weight is mostly art provenance, not runtime code

**Evidence:** tracked `art_source/background/` is 38.21 MiB, terrain inputs 29.20 MiB,
historical `art_source/audits/` artifacts 19.82 MiB, and Aurora references 5.78 MiB. No nonempty
tracked files were byte-identical in the content-hash scan. Archived GDScript/probe material is only
about 0.19 MiB; deleting it will not materially shrink this repository.

**Change:** bring `art_source/README.md` up to date with its current directories and distinguish
active build inputs, approved reference art, and historical captures. Stop accumulating duplicate
new screenshots/logs in several reports. For obsolete audit outputs, preserve a compact conclusion
and the minimum evidence needed to reproduce it; remove only verified superseded artifacts during
an explicit cleanup. Existing working art/source/reference files should remain recoverable.

**Done when:** each large retained group has a clear purpose; new build products stay ignored.
Deleting tracked files does not shrink existing Git history—no history rewrite or LFS migration is
justified by this audit. The root APK/idsig and `.godot/` are already ignored, not tracked-code bloat.

### A13 — Limit future extraction to real responsibility boundaries

This is a direction for subsequent feature work, not a prerequisite cleanup rewrite.

- `TerrainGenerator` owns topology/collision and roughly `:814–1229,2166–2303` of ice/snow
  presentation. If another visual feature expands it, extract the cohesive painter/build logic
  while keeping geometry, cache/reservation ownership, and coordinate conventions in place.
- `GameManager` mixes state transitions with shop row construction/formatting (`:776–830`).
  A small shop view/controller is reasonable when the shop next grows; the current three-row
  table does not justify a UI framework or global event bus.
- SkyBackdrop builds three deterministic Aurora masks on every scene reload (`:376–403,563–652`);
  BackgroundStrip rebuilds its deterministic plain texture (`:143–146,263`). Measure restart
  time before adding a tiny immutable texture cache or build-time asset. This audit did not
  measure those construction costs; cache only immutable data, not mutable materials/palettes.
- Player landing prediction (`:396–411`), actual physics (`:414–545`) and the fairness simulator
  (`scripts/debug/terrain_invariant_check.gd`) encode related motion rules. Add a small corpus
  comparing prediction with real landing frames at slopes/seams and weakest/strongest jump
  settings when changing them. Do not combine the test oracle and runtime into one function
  merely to remove “duplication”; that would make both agree on the same bug. **A14 now supplies
  a concrete failing corpus case; address that behavior before considering any extraction.**

**Done when:** an extraction reduces the number of places a real change touches, with identical
behavior and appropriate regression coverage. If it only creates indirection, leave it alone.

### A14 — Air upgrades can steal a valid buffered landing jump

**P2 / reproduced behavior.** `scripts/player/player.gd:344–346,396–411,466–478` uses a
point-height landing prediction to decide whether a tap should remain buffered or become an
air move. Actual capsule collision/contact can land a frame earlier. At the buffer boundary,
the predicted extra frame makes the same tap become Double Jump or Slam after buying that
upgrade, although without it the tap produces an ordinary jump after landing.

**Reproduction:** use the setup/warp pattern from `air_move_probe.gd` in an isolated-save copy.
Use seed `683407368`, disable chasms and obstacle/powerup/rare-coin spawning, start PLAYING,
warp to `x=20000` at surface minus capsule half-height, rebuild chunks, clear movement/shield/
buffer state, set jump multiplier `1.0`, speed `750`, and speed-manager elapsed time `200`.
Wait 10 physics frames, call `buffer_jump()`, await one physics frame. In a zero-based loop,
call `buffer_jump(is_slam_owned)` before awaiting frame 51. Repeat with neither air upgrade,
Double Jump only, and Slam only; count landing frames and air-move flags:

| Owned upgrade | Prediction at second tap | First subsequent landing (loop frame + 1) | Air move consumed | Ordinary jump after landing |
|---|---:|---:|---|---|
| Neither | 6 frames | 56 | No | Yes |
| Double Jump | 6 frames | 94 | Yes | No |
| Slam | 6 frames | 55 | Yes | No |

At the tap, x was approximately `20774.03` and vertical velocity `746.67`. The no-upgrade
control lands in five frames. A wider scan of 300 jumps (`x=20000+317*i`, 100 locations,
velocity multipliers `0.6`, `1.0`, `sqrt(2)`) found 458 frame samples differing from actual
landing, by at most one frame, including 15 boundary samples predicting six instead of five.
These are samples within jumps, **not** 458 broken jumps or a measured player failure rate.
The `sqrt(2)` case represents the effective maximum jump with the jump powerup.

**Change:** reconcile the buffer decision with actual collision/contact timing, including slopes
and seams. Use a conservative boundary only if tests establish its limits; do not blindly expand
all buffers or weaken Slam's void checks. Keep the independent physics test oracle. This upgrades
A13's previously hypothetical prediction-drift concern to a concrete regression.

**Done when:** the late tap preserves the ordinary landing jump with either upgrade owned, earlier
intentional air taps still work, and a slope/seam/jump-strength corpus passes at the pinned 60 Hz.
This reproduction uses the common `buffer_jump()` path; Android touch dispatch itself was not tested.

### A15 — Same-step pickups can mutate a run after death finalization

**P2 / reproduced behavior.** `scripts/pickups/coin.gd:83–95` checks collection/group membership,
but not whether the player has died. `scripts/game/game_manager.gd:667–672` accepts the resulting
score update in any state. `_on_player_died()` has already captured the score and, outside headless,
banked the run at `:565–586`. Pausing the tree does not cancel already pending collision callbacks.

**Reproduction:** in the same isolated scene/seed setup as A14, settle a live player at `x=20000`,
with no shield/boost. Instantiate `scenes/obstacles/obstacle.tscn` and `scenes/pickups/coin.tscn`
as children of Main, both at `player.position + Vector2(15, 0)`. Connect the coin's `collected`
signal to `game_manager._on_coin_collected`. Add the obstacle before the coin and await physics.
The actual collision callbacks yield `dead=true`, `coin_count=1`, but death text `Coins: 0`.
Reverse creation order and both score/text are 1. This is an order-dependent result using real
Area2D callbacks, not a direct call to the death handler. Ordinary coins are not excluded by
obstacle placement, so simultaneous contact is a reachable category; no natural seed/frequency
was measured. The headless repro skips wallet writes; the production banking consequence follows
from the same handler ordering, rather than a measured device save.

**Change:** establish a simple terminal-run policy. At minimum, reject late scoring after death
and prevent already-dead bodies from consuming pickups. Review `powerup.gd:17–28` and
`PowerupManager.start_effect()` for the same pending-callback admission problem. Do not add a
new global event bus. If design wants to count all same-frame rewards, finalize after them
consistently instead of partially counting them after banking.

**Done when:** both collision orders satisfy the chosen policy, score/death summary/banked amount
agree, and no post-death pickup starts an effect or sound. A pickup processed while the player
is still alive can remain valid; this need not force equal reward totals for both orders.

### A16 — Several physics “gates” report success even on detected failures

**P2 / confirmed failure-path test.** `freeze_replay_runner.gd:70` and `freeze_search.gd:127`
unconditionally call `quit(0)`. `floor_flicker_probe.gd:82` likewise exits successfully regardless
of its summary. The scripts live under `scripts/debug/`; the latter describes itself as a
regression gate and says it asserts metrics, but prints rather than enforces them.

In a disposable copy of `freeze_replay_runner.gd`, change only
`game_manager.require_start_screen = false` to `true`, then run `--frames=10`. It reports
`status=tree_paused frame=1`, yet the process exit status is **0**. This deliberately broken
harness proves the reporting flaw; it does **not** establish a new freeze in the game.
The source also returns zero after `freeze_detected`, `stall_recovered`, or nonzero search stalls.

**Change:** fail on unambiguous hard failures, incomplete/zero-trial runs, and unexpected pause.
For floor/contact thresholds, define a justified baseline and tolerance rather than copying
historical comments (the existing sub-pixel claim conflicts with the observed 1.8633 px max).
Keep subjective camera/visual metrics explicitly diagnostic until a defensible threshold exists.
Document which commands are automated gates and which require reading the output. A4's integration
runner should consume these meaningful results, not equate process completion with correctness.

**Done when:** intentional failure injections exit nonzero; the unchanged baseline still passes
its justified criteria. Inspect failures and counts as well as the final process status.

### A17 — Save-field validation accepts non-finite and out-of-range numbers

**P3 / corrupt-save robustness, reproduced.** `scripts/systems/save_store.gd:123–184` validates
numeric types, but `_is_number()` does not validate finiteness or safe integer range. In this
engine, valid JSON numeric text `1e309` parses to infinity. A v3 scratch save containing this
value produced `best_time=inf`, `total_playtime_seconds=inf`, `next_aurora_due_seconds=inf`, and
wallet/upgrade integers `9223372036854775807`. `-42` was accepted as negative best score/time.
This is a malformed/hand-edited-save edge case, not evidence that ordinary writes generate it.
It matters because the intended load policy promises field-level recovery from corrupt data.

**Change:** require finite numbers, reject integer values outside a safely supported range before
conversion, and validate fields according to their domain. Keep nonnegative stats nonnegative;
preserve the negative “unscheduled” Aurora sentinel and valid unknown upgrade/achievement IDs.
Reject only the invalid field, leaving other recoverable progress intact. Do not add a schema
framework or make SaveStore depend on UpgradeStore's current catalog.

**Done when:** finite normal numbers, old versions, unknown IDs, wrong container types, negative
stats and overflowing exponents are covered; one bad field cannot poison clocks or currency.

### A18 — Skate-track core strength also inherits the halo strength

**P3 / confirmed code contract, visual decision required.** `scripts/systems/skate_track.gd:157–161`
parents `core_line` under the halo Line2D. At `:220–222`, the halo's `modulate.a` is
`lake_blend * 0.30` and the child's is `lake_blend * 0.95`. Godot's
[CanvasItem modulation contract](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-modulate)
propagates `modulate` to child CanvasItems. Therefore the core receives **0.285 × blend²** before
its gradient alpha, not the apparently independent 0.95 × blend described by these controls.
Changing “halo strength” also changes the core, and their fade ramps differ.

**Change:** first compare against the approved lake look. If the two strengths are intended to be
independent, use `self_modulate` for the halo or an unmodulated parent with sibling lines, retaining
tree draw order. If the current compounded look is intentional, document the effective values and
make the controls honest. Do not automatically brighten an already approved effect by 3.33×.

**Done when:** halo/core controls and ramp behavior match the stated contract, with rendered
captures at partial/full blend. No rendered image was obtained in this audit; this is not a claim
that the shipped track looks wrong. AuroraBladeGlow already uses siblings and has no such cascade.

### A19 — Aurora streaks rebuild an unchanged Gradient on every visible frame

**P3 / small local cleanup, not a measured stutter.** `scripts/systems/aurora_streaks.gd:129–130`
calls `build_taper_gradient()` every time `apply_aurora()` updates a visible streak. Its color is
a pure function of the streak index, which stays constant throughout that streak. This repeatedly
allocates identical Gradient resources while only placement/geometry/opacity need updating.

**Change:** assign the gradient when the streak index changes, or reuse the few immutable color
gradients. Keep viewport-dependent geometry responsive to camera zoom. A general effects pool,
shared caching service, or new class hierarchy would cost more complexity than it saves.

**Done when:** gradient identity remains stable within one streak, changes appropriately between
colors, and the rendered effect is unchanged. No device frame-time improvement is claimed here.

## Things already organized well — preserve them

- One Services autoload; SaveStore/UpgradeStore responsibilities are separated.
- Runtime scenes/assets, source art, current development docs and research have distinct homes.
- Obstacle/powerup/shop catalogs are data-driven already; do not replace them with a plugin system.
- Chunk/object cleanup is present; collision-sample caches are pruned. Segment-history caches are
  intentionally retained to support deterministic lookup. No memory-leak claim is established here.
- Lake/Aurora reflection share one shader but have different activation/framing contracts. Their
  few common quad methods do not justify merging their directors or adding a class hierarchy.
- No missing literal runtime `res://` paths were found. All asset/scene/resource/shader files had
  literal non-debug references in the scan; references alone do not prove behavioral use (A7).
- No tracked APK/AAB, `.godot` cache or signing-credential file was found in the path inventory.
  This was not a full secret-history audit.
- The previous save write/field-validation, multi-touch and biome-phase fixes are present. Do not
  re-implement them from an obsolete audit. Keep their missing regression coverage on the action list.
- Leave disabled mega-drop behavior and X-axis rebasing alone; their existing investigations explain
  why they are not a quick “cleanup”. Do not retune gameplay, add pooling everywhere, or reorganize
  every scene/script directory without a demonstrated benefit.

## Validation performed for this audit

Engine: `4.7.stable.official.5b4e0cb0f` on this Mac. Engine runs used a disposable copy of tracked
project files plus the existing import cache, with both SaveStore filenames redirected to that
copy. The first copy omitted source art; the second included all tracked source art and reproduced
A11 by removing its ignore file **only in that copy**, importing and exporting pack files. No
fresh-clone bootstrap, APK install, release signing or on-device acceptance was performed.

| Check | Result |
|---|---|
| `scripts/check.sh` | 5/5 PASS, 72 seconds; includes 8-seed terrain/fairness checks and pack-content check |
| `air_move_probe.gd` | 14/14 PASS |
| `aurora_calm_probe.gd` | 182,974 assertions PASS; 2 live integration cases |
| `chasm_probe.gd -- --seed=683407368 --chasms=3 --phases=4` | 120 trials, 0 failures |
| `floor_flicker_probe.gd -- --frames=20000` | 6 seeds; 0 stall recoveries/stuck events; worst uphill flip rate 0; largest snap 1.8633 px |
| `freeze_replay_runner.gd -- --seed=941462462 --frames=60000 --runs=1` | 60,000 frames; no freeze; 0 recoveries |
| `freeze_search.gd -- --seed=941462462 --warp=175000 --to=178000 --phases=8 --phasestep=0.25 --scan=1 --trialframes=500 --rebase=1` | 40 trials; 0 stalls/near-stalls |
| Isolated purchase failure injection | A1 reproduced; last good disk save preserved |
| Placement microbenchmark | A3 timings above; 750 searches total |
| Literal path, unused-symbol/call-site and duplicate-content scans | Findings/limits above; no missing literal paths or exact duplicate nonempty files |
| Second-pass landing corpus | 300 jumps; 458 mismatching frame samples, max 1-frame difference; 15 buffer-boundary samples (A14) |
| Second-pass air-upgrade boundary controls | Same tap becomes a landing jump unowned, Double Jump/Slam when owned (A14) |
| Same-step real coin/hazard collisions, both creation orders | Post-death score mismatch reproduced in hazard-first ordering (A15) |
| Deliberately paused freeze harness | Reports `tree_paused`, exit 0; false-success path confirmed (A16) |
| Full-source export mutation | 7,052,072 → 67,246,304 bytes; current forbidden checks miss source art (A11) |
| Corrupt numeric save inputs | `1e309`, `-1e309`, `1e30`, `-42` accepted beyond intended field domains (A17) |

For standalone probe commands, prepend:
`/Applications/Godot.app/Contents/MacOS/Godot --headless --fixed-fps 60 --log-file /tmp/aura-audit-engine.log --path <isolated-project> --script res://scripts/debug/`.
Do not run the purchase failure injection against the normal save. The floor-contact and freeze
probes include diagnostics, so the table reports their observed metrics rather than inventing
assertion coverage. Several runs emitted the known macOS certificate-access error from
`get_system_ca_certificates`; no GDScript error appeared in the successful probes. The purchase
injection intentionally produced a SaveStore error. Import/export also logged editor-settings and
ADB permission errors in this environment, although the pack files were produced and inspected.
An attempted native minimal render returned no image/output, so it supplies no visual validation.
This is not a warning-free certification.

Not rerun: rendered visual/capture gates, camera metric probe, device touch/audio/layout/thermal
acceptance, release signing/store requirements, long-run X precision soak. Existing October 4
device results remain historical evidence, not work performed in this audit.

## Second-pass corrections and limits

- A11 is now experimentally confirmed, replacing the first pass's inspection-only evidence.
- A13's landing-model concern is now a reproduced defect (A14), not just future maintenance advice.
- Physics checks' first-pass results remain the observed clean metrics listed above. A16 explains
  why a successful exit alone is insufficient; no new natural freeze was found.
- The original “two concrete defects” summary understated the result; A14/A15 add gameplay issues.
- A18 is a modulation/intent mismatch requiring visual review, and A19 is allocation cleanup.
  Neither is evidence of bad artwork or device stutter. A3 remains a Mac microbenchmark.
- Rechecked and rejected: start-screen reset does **not** permanently unschedule Aurora;
  its IDLE branch calls `schedule_if_unscheduled()` again. Likewise, retained segment history is
  intentional, and unused-looking shaders/assets should not be deleted solely by filename.
- Headless checks skip production persistence/rendering branches. Temporary reproductions use
  isolated saves and are evidence, not maintained regressions; carry their essential cases into
  the repository's existing probes when implementing fixes. Android input, thermal performance,
  current art/audio acceptance and real disk-failure UX still need their relevant environments.

## Suggested implementation order

1. Add focused regressions and fix A14/A15, then A1/A2; make hard-failure checks meaningful (A16).
2. Reconcile active instructions (A5), make integration checks and scratch-save isolation routine,
   and close contrast/capture/export gaps (A4/A6/A10/A11). Add finite numeric validation (A17).
3. Remove verified unused scaffolding and collapse reload duplication (A7/A8); reuse streak
   gradients (A19). Trim source history as a separate reviewable documentation change (A9).
4. Profile placement on the phone before optimization (A3), and resolve the track contract with
   approved visual comparisons (A18).
5. Apply the artifact retention policy (A12); consider A13 extractions only when actual work needs them.


---

Older audits, archived 2026-10-11 (not the current action list):
- `docs/review/2026-09-27-obstacle-branch-audit.md` (the "finding 1" the code comments cite)
- `docs/review/2026-09-24-organization-audit.md`
