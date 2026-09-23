# Project audit — 2026-09-20

Baseline: `e157a6b` on `claude/aurora-reconcile`. Read-only review of runtime code, scene wiring,
resources, shaders, persistence, input, progression, set pieces, and export configuration.
No gameplay fixes were made. A concurrent edit to Aurora ice colors in
`scripts/terrain/terrain_generator.gd` appeared during the review and was left untouched;
this report does not approve that edit.

## Findings

### P1 — A failed temporary save write can destroy the last good save

Location: `scripts/systems/save_store.gd:207–213`.

`save_to_disk()` checks whether the temporary file opened and whether its rename succeeded,
but never checks whether the payload was fully written. A short write can therefore be followed
by a successful rename, replacing the valid save with truncated JSON. Next launch silently
loads fresh progression. Atomic rename only protects the replacement operation, not the data
being renamed.

Reproduced with a copy of SaveStore whose two paths point exclusively into `/tmp`, an existing
wallet of 456, a larger payload, and a 4,096-byte process file-size limit with SIGXFSZ ignored.
The save returned without reporting a write failure and replaced the old file:

```
SAVE_BYTES=4096 VALID_JSON=false
RELOADED_WALLET=0
```

The limit is fault injection for a failed/short filesystem write, not a claim that ordinary
saves exceed 4 KB. Fix: validate write/flush success before closing and renaming; preserve the
existing save on any failure. Add a failure-path regression check using isolated save paths.

### P2 — One malformed save field prevents unrelated valid progress from loading

Location: `scripts/systems/save_store.gd:119–144`, also line 166.

Only the top-level JSON value is type-checked. Nested dictionaries and numeric values are cast
without validating their types. A valid JSON save containing `"settings": []` raises an invalid
Dictionary cast and exits `load_from_disk()` before wallet/upgrades/achievements are loaded.
`"upgrades": []` and numeric fields containing arrays fail similarly. A later ordinary save
can persist those partially loaded defaults over otherwise recoverable progress.

Isolated reproduction: version 3, wallet 456, jump level 4, and only settings changed to an array
produced `Invalid cast: could not convert value to Dictionary`, then wallet 0 and no upgrades.
With only upgrades malformed, wallet remained 456 but upgrades and later fields were skipped.

Fix: validate each field/container before conversion, default only invalid fields, and load the
valid remainder. Validate into local values before publishing state if all-or-nothing loading
is preferred; do not rely on casts as validation.

### P2 — Releasing another finger drops held glide input

Location: `scripts/main.gd:186–191`.

The touch handler stores the last event's `pressed` value in one boolean and ignores touch
index. Hold finger 0, tap with finger 1, then release finger 1: the game reports no held touch
while finger 0 remains down. `Player.is_glide_input_held()` reads that boolean, so glide thrust
and airborne spinning stop until another press arrives.

Direct event reproduction (desktop action explicitly released):

```
index=0 down=true  held=true  glide_thrust=true
index=1 down=true  held=true  glide_thrust=true
index=1 down=false held=false glide_thrust=false
```

Fix: track the controlling touch index or a set of held touch indices, preserving pause-button
exclusion and clearing state on leaving PLAYING. This is a handler-level reproduction;
physical Android input delivery was not tested.

### P2 — Pause → Restart/Home rewinds the biome phase

Location: `scripts/game/game_manager.gd:618–638`; compare phase banking at lines 566–567.

Biome progress is banked only on death. Both pause-menu reload paths discard the current run's
phase, so restarting mid-run returns to the phase from the previous death. On a fresh launch
this makes the supposedly one-shot opening biome repeat; repeated voluntary restarts can also
prevent progression toward night even while cumulative playtime grows.

Reproduced both callbacks with the player at x=100,000, offset 0 and stored phase 0:
`get_persisted_phase()` reports 100,000 before restart; stored phase remains 0 after either
reload request. Persistence was disabled in the probe; the real save was not modified.

Fix: bank the biome phase before either live-run reload, using the same calculation as death.
Avoid banking twice for restart from DEAD, whose phase was already recorded.

## Validation

- Fast runner: **5/5 PASS**, including export-content verification.
- Chasm probe: **60 trials, 0 failures**, including glide, jump, late jump, boost and no-input.
- Freeze search: **1,600 trials, 0 stalls and 0 near-stalls**, rebasing enabled, seed 2160065702.
- Freeze replay: **60,000 frames, no freeze, 0 stall recoveries**, seed 941462462, reached
  x=714,308 with rebasing enabled.
- Floor-contact probe: six seeds × 20,000 frames; **0 recoveries / 0 stuck events**, worst
  uphill flip rate 0.0000; residual curved-ground motion remains the previously documented issue.
- Camera diagnostic: 7,000 frames, seed 941462462, completed; this prints metrics rather than
  asserting a pass threshold. No new camera defect established.
- Aurora gameplay probe: **182,974 assertions PASS** earlier in this same audit session.
- Windowed sky gate: **PASS** earlier in the session, including streak reflections and cleanup.
- Windowed ice captures: three frames generated; final frame inspected, no new rendering defect established.
- Runtime `res://` references scanned: **none missing**.
- Windowed biome captures generated and a night frame inspected. The capture script iterates
  absolute indices 0–7: first_light replaces one of the eight rotating palettes, so these images
  do **not** cover the full nine-palette set. The sky gate separately covers all nine.

## Limits and priorities

Fix the failed-write path first, then save validation and the two input/menu state defects.
No architectural rewrite is needed for these findings. Existing Android release-signing/store
configuration work remains open; no Android device or release-store submission was tested.
Synthetic input checks establish handler behavior, not physical touch delivery. Native captures
on this Mac do not establish Android fill-rate, audio balance or thermal performance.
