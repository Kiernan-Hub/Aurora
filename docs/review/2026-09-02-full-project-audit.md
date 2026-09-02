# Aura audit — 2026-09-02 (full project)

Read-only pass over the whole tree at `97e68e2`. Nothing in the game was changed; this file is
the only addition. Every claim below was checked against the files as they stand.

## What was and was NOT run

**No gate was run.** This session is a Linux container; `check.sh` points at
`/Applications/Godot.app/...` and no Godot binary is reachable here (a download was attempted
and the proxy returned 403). So this is a **static** audit: reasoning over the source, not
measurement. Anything below phrased as "measured" is arithmetic over constants in the repo,
not an engine run.

Consequence, and it matters for how to read finding #1: the finding is a coordinate-space
mismatch that is fully determined by the source, but it has **not** been confirmed on screen.
The first step on it should be to look at a rare coin in game, which costs a minute.

## Status of the 2026-08-24 list

Re-verified, not taken on trust:

| Item | State now |
|---|---|
| #1 playtime double-count | **Fixed.** `GameManager.get_unbanked_seconds()` exists and `frozen_lake_director.gd:186` uses it |
| #2 `HANDOFF.md` misdirects | Fixed, with one line already stale again — see P2 |
| #3/#4/#5 parallax + gate | Closed as recorded; `main.tscn` carries 0.015/0.025/0.035/0.05 and `depth_t` 0.0/0.15/0.30/0.45 |
| #6 X precision cliff | Closed |
| #7 segment caches never pruned | **Still open.** Sized below |
| #8 process priority / #9 Godot 4.7.2 | Declined on evidence; agreed, no reason to re-raise |
| #10 validation runner | `scripts/check.sh` exists, four gates + export-content |
| P2: `build_iceberg_sprites.py`, orphan `.import`s, stale `PineLine` docs, `aura.apk` at root | All gone |
| P2: export preset | Real app id, version, icons, and an `exclude_filter` a gate verifies |
| P2: Music slider does nothing | **Still open** |
| P2: `mist_strength` has no renderer | **Still open** — authored in all 8 palettes, blended, read by nothing |

---

## P0 — real defect

### 1. `RareCoinSpawner` and `GlideCoinSpawner` place every coin `ground_y` (192px) too high

`rare_coin_spawner.gd:183`, `glide_coin_spawner.gd:186`, `glide_coin_spawner.gd:230`

`get_terrain_height()` returns an offset **relative to `ground_y`**, not a
TerrainGenerator-local y. Every other consumer in the project adds `ground_y` back, in one of
two ways:

| Consumer | How it re-adds `ground_y` |
|---|---|
| `terrain_generator.build_chunk_surface` | `chunk.position.y = ground_y`, points at `get_terrain_height()` |
| `coin_spawner.spawn_coin` | group node at `y = ground_y`, coin local y is the clearance |
| `ground_tree_spawner.spawn_tree_group` | group node at `y = ground_y` |
| `obstacle_spawner.spawn_obstacle` | `ground_y + get_terrain_height(x) - half_height`, explicit |
| `powerup_spawner.spawn_powerup` | `ground_y + get_terrain_height(x) - clearance`, explicit |
| `terrain_generator.get_surface_world_y` | `global_position.y + ground_y + get_terrain_height(x)` |

`RareCoinSpawner` and `GlideCoinSpawner` do **neither**. They sit at local `(0,0)` under
`TerrainGenerator` (no `position` in `main.tscn`) and `add_child()` the coin with
`position.y = get_terrain_height(x) - clearance`. The `ground_y` term is simply absent.

Both files' headers state the opposite in prose — *"a coin's local position IS already in the
same space `get_terrain_height()` returns"* (`rare_coin_spawner.gd:12`, and the same claim at
`glide_coin_spawner.gd:34`). That claim is where the bug lives: `get_terrain_height()`'s frame
is `ground_y`-relative, and `CoinSpawner`'s own comment says so in as many words
(`coin_spawner.gd:30`, *"get_terrain_height() is already ground_y-relative"*).

**Arithmetic.** Surface in TerrainGenerator space is `ground_y + h = 192 + h`. These spawners
place at `h - clearance`. The gap is therefore `clearance + 192`, not `clearance`:

| Object | Authored clearance | Actual clearance |
|---|---|---|
| Rare coin (`RARE_COIN_CLEARANCE`) | 174 | **366** |
| Glide bonus diamond (`BONUS_SURFACE_CLEARANCE`) | 130 | **322** |
| Glide trail coins (`TRAIL_CLEARANCE_MIN/MAX`) | 60–1900 | **252–2092** |

**The rare coin is currently uncollectable at every upgrade level, with or without the
powerup.** `rare_coin_spawner.gd`'s own derivation gives a max-upgrade grab ceiling of 186px,
and 314px with the ×√2 jump powerup. 366 clears both. That is the game's highest-value regular
pickup (25, ~once a minute) and the entire stated payoff of the jump upgrade track — build
order #3 and #9 both rest on it.

The glide bonus diamond at 322px is in the same position: the player is descending at the point
it spawns (200px past where the glide ended), so it is a near-certain miss. The trail field
still works — a glide climbs at up to 600 px/s for 7s — but its floor moved from 60px to 252px,
so the low coins meant to be catchable straight off the launch are gone.

**No gate can see this.** `terrain_invariant_check.check_rare_coin_height()` and
`check_coin_line_height()` assert the *constants* against the jump table, and
`measure_coin_density()` asks `CoinSpawner` what it would build but only counts, never reading a
y. Nothing in the project compares a spawned node's position against `get_surface_world_y()`.
This is the same shape as review #5: a gate that guards a property rather than the code path.

**Cheapest fix** — one line per file, in `_ready()` after the generator resolves:

```gdscript
position.y = terrain_generator.ground_y
```

That makes the two spawners match `CoinSpawner`'s group convention exactly, leaves every `.x`
comparison in both files untouched (`position.x` is still world x), and keeps world rebasing
working, since the offset is relative to `TerrainGenerator`. Adding `ground_y +` at the three
call sites is equivalent; the node offset is fewer places to get wrong later.

**Worth adding with the fix, not instead of it:** a gate that instantiates each spawner in a
real scene and asserts `coin.global_position.y` against
`terrain_generator.get_surface_world_y(coin.global_position.x)`. That is the check that would
have caught this, and it would cover all six spawners at once.

---

## P1 — inconsistencies with the project's own contracts

### 2. `GlideCoinSpawner` is the only scoring spawner that is not seeded

`glide_coin_spawner.gd:160`, `:173`, `:185` use bare `randf_range()` — Godot's global RNG,
seeded at process start. Every other spawner in the project derives its draws from a hash of
`(session_seed, index)` with its own multiplier pair. Checked exhaustively: the only other
`randf` in shipping code is `flight_trail.gd` and `bird_flock.gd`, both purely cosmetic, plus
the deliberate `randomize()` calls that create `session_seed` and the biome rotation.

Consequences, both real but neither urgent:

- `debug_replay_session_seed` does not reproduce a run that involved a glide. Any freeze or
  stall found during a glide is not replayable by seed, which is the one debugging tool this
  project leans on hardest (`FREEZE_REPRO`, `debugging.md`).
- 30 coins × up to 15 value is a meaningful score contribution that is not a function of the
  seed, so two players on the same seed do not score the same.

The 2026-08-24 review's "confirmed healthy" line — *"the six spawner hash functions use
genuinely distinct multiplier pairs"* — counts six hash functions, but `GlideCoinSpawner` is
not among the files that have one. There are five seeded spawners plus `background_generator`.

Fix is a `get_field_hash(coin_index, channel)` in the same shape as
`PowerupSpawner.get_powerup_hash`, with the coin index as the counter. Three draws per coin
(spawn time, edge margin, clearance) means three channels.

### 3. Segment caches still grow for the whole run (review #7, sized)

`terrain_generator.gd:110-113`. Sizing it now that it has been deferred twice, so the decision
has a number behind it rather than a shrug:

Weighted mean segment length is ~732px (16% flat @640, 16% small hill @480, 42% medium @640,
16% downhill @960, 10% uphill @960, all hills ×1.075 for the 10% oversized roll). At
`MAX_SPEED` 750 that is **~1.0 segments/second**, so ~3,700 per hour: four dictionary entries
plus a 5–9 key `Dictionary` each. Order of a couple of MB per hour, dominated by the spec
dictionaries.

That is not a phone-killer for a session that lasts minutes, and it matches the six 36–55
minute soaks that finished at a steady 75 fps. **It stays a "measure before touching"
item** — the write-ahead rule in `arm_lake()` and deterministic seed replay both depend on
cached history staying available, and the review already says not to prune casually. Nothing
here changes that; it just puts a bound on the thing being deferred.

### 4. Biome phase is banked on death but not on a restart

`game_manager.gd:528` sets `BiomeDirector.session_biome_phase` inside `_on_player_died()` only.
`_on_quick_restart_pressed()` and `_on_restart_pressed()` reload the scene without banking it.

So a player who restarts from the pause screen — the normal reaction to a bad opening — never
advances the biome and replays the same colours indefinitely. Dying advances it correctly.

This is an asymmetry with `bank_playtime()`, which fires on *every* `PLAYING → not-PLAYING`
transition and therefore already covers the restart paths. Low impact, but it is the same
class of drift as the playtime double-count (#1 of the last review), and the fix is the same
shape: bank the phase where the playtime is banked, rather than at one specific exit.

---

## P2 — hygiene

- **`HANDOFF.md:8` is stale again.** It says local is *"ahead of `origin/main` by two unpushed
  commits (`f7e500d`, `9c91c42`)"*. Both are pushed; `origin/main` is at `97e68e2` = `HEAD`.
  This is the second audit in a row to find the "Start here" block's git claim false. Consider
  dropping the sync state from the file entirely — `git status` is authoritative and free,
  and a stale claim there is worse than no claim.
- **The Music slider still does nothing audible.** The `Music` bus exists, `GameServices`
  builds a `music_player`, and nothing anywhere assigns `.stream` except `SfxPlayer`. A player
  will drag it, hear nothing, and read it as a bug. Hide it or label it until music ships.
- **`BiomePalette.mist_strength` still has no renderer.** Authored in all eight palettes
  (0.2–0.8), blended at `biome_palette.gd:330`, read by nothing. Speculative data no gate
  covers.
- **The rare coin takes no per-biome colour and no gate checks its contrast.** Deliberate and
  documented (`coin.gd:63`) — it keeps its authored gold so one diamond means one thing. But
  `biome_schedule_check`'s contrast floor covers `coin_color` and `obstacle_color` only, so the
  single highest-value pickup has no readability guarantee against any of the nine palettes.
  Worth one assertion against `GAMEPLAY_CONTRAST_BACKGROUNDS` using the sprite's own colour.
- **Repo weight.** `art_source/` is 72 MB tracked, of which ~20.7 MB is three `.xcf` GIMP
  files, and `.git` is 71 MB. It is `.gdignore`d so none of it exports, but every clone pays
  for it. Git LFS, or keeping the `.xcf`s outside the repo, if clone time ever matters.
  `assets/textures/experiments/` (3.8 MB) is still tracked, though it is now correctly
  excluded from the export.
- **`CLAUDE.md` is 181 lines against its own ~175 target.** Trivial, noted only because the
  file asks to be held to it.
- Two dead statements, both harmless: `terrain_generator.initialize_chunks()` assigns
  `next_chunk_index` twice (the first is overwritten), and `player.update_stuck_detection()`
  sets `stuck_event_reported = true` then clears it four lines later.

---

## Confirmed healthy (checked, no action)

- Every documented invariant in `CLAUDE.md`'s "Things that break silently" holds in the code:
  no `Services.x` in gameplay, no `z_index` anywhere, `set_state()` is the only writer of
  `get_tree().paused`, all three `Area2D` handlers filter on `is_in_group("player")`, no
  spawner reads `session_seed` in `_ready()`, `get_terrain_height` takes no runtime input but
  `lake_segment_index`, and `arm_lake()` is its only writer.
- `LAKE_ARM_LEAD_SEGMENTS = 2` is exactly right and not one segment of slack more:
  `cache_next_segment()` builds the spec for `highest + 1`, so `highest + 2` is the first index
  guaranteed uncached. The defensive `segment_spec_cache.has()` in the while condition is what
  keeps that local.
- Every debug knob is at its shipping value, and `main.tscn` carries no `debug_*` override.
- `TRICK_SPIN_PERIOD` 0.9s against a max flat airtime of 0.8s is deliberate and documented; I
  went looking for it as a bug and it is a measurement.
- `LakeReflection` re-anchors to the camera every frame, and `SkateTrack`/`SkateSpray` both
  handle `total_world_rebase_shift` explicitly — all three sit outside `TerrainGenerator` and
  all three are rebase-correct.
- `SaveStore.save_to_disk()` writes to a temp path and renames, so a crash mid-write cannot
  corrupt the save.
- The 13 files in `scripts/debug/` are the documented 12 gates plus `ice_seam_probe.gd`; the
  directory still answers "is this a gate?" correctly.

## Suggested order

1. **Look at a rare coin in game** (one minute), then fix #1 if it reads as described. It is
   two one-line changes and it restores the payoff of the whole upgrade track.
2. Add the spawned-position gate alongside that fix — it is what makes #1 not happen again,
   and it covers all six spawners.
3. #2 (seed the glide field) whenever the glide is next touched. Not urgent on its own, but it
   is the one hole in seed replay and that tool is load-bearing here.
4. The P2 sweep — Music slider label, `HANDOFF.md`'s git line — as a single small commit.
5. #3 and #4 stay parked. Neither is urgent and #3 explicitly wants a measurement first.
