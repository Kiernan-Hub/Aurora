# Cleanup audit — 2026-08-10

Full read of every `.gd`, `.tscn`, `.tres`, `.md` and `project.godot` in the repo. Scope was
**organisation, doc rot and latent bugs** — explicitly *not* physics, terrain shape or game
feel. Nothing in the "fixed" section below touches collision, the velocity model, terrain
geometry or game state.

Baseline at time of audit: 14,535 lines of GDScript across 47 files, 195 tracked files.
`git` hygiene is clean — no stray artifacts tracked, `.gitignore` correctly covers `.godot/`,
probe logs, APKs and `export_credentials.cfg`.

Gates run after the fixes: terrain shape **PASS** (0 violations, max slope 20.13° unchanged),
biome check **PASS**, chasm probe **PASS** (48/48, 0 recoveries), floor flicker smoke
`--frames=2000` **PASS** (0.0000 flip rate everywhere, 0 recoveries / 0 stuck), new shipping
values check behaving correctly in all three states.

> **Second pass, same day:** everything in "Real bugs found" was subsequently fixed except the
> powerup debug override — see **Round 2** at the bottom. Items are left written as found so the
> reasoning survives; the fix is noted inline on each.

---

## Fixed in this pass

All comment/doc/type-annotation only, except the `sky_layer_check` guard.

1. **Three doc comments had drifted onto the wrong function.** Same failure mode each time —
   a new function was inserted between an existing comment block and the function it
   described, leaving the original function undocumented and the new one carrying two stacked
   blocks that contradicted each other:
   - `terrain_generator.gd` — `get_exit_drop_offset()`'s block sat above
     `get_pending_exit_drop_at_world_x()`.
   - `player.gd` — `apply_grounded_floor_snap()`'s block (the whole floor-flicker
     derivation) sat above `is_boost_gliding_over_drop()`.
   - `main.gd` — `get_vertical_camera_target()`'s block sat above
     `update_glide_vertical_follow_state()`.

   These matter more than normal comment rot: all three are the *measured* justifications for
   fixes this project paid weeks for, and each was attached to a function that doesn't do what
   it describes.

2. **`CHASM_EXIT_DROP` carried a stale pre-phase-3 comment** directly contradicting the
   current one immediately above it — 12 lines ending "Deferred to Phase 3 with that fix",
   when phase 3 shipped in `b3d05fd`. Replaced with what the constant now actually is (the
   default for a variant with no `exit_drop` of its own).

3. **`sky_layer_check.gd` now refuses to run under `--headless`.** It diffs rendered frames;
   headless has no rendering device, so every capture is blank, every layer diffs to 0/255,
   and it reports **19 confident, meaningless violations** — every claimed layer in every
   biome "invisible". This is the same blank-frame trap the file's own header already records
   for `Engine.time_scale = 0`, with the sign flipped (there everything measured as fully
   visible and the gate *passed*). Both directions are worse than an error. Note `quit()` in
   `_init()` does not stop one `_process` pass, so the abort is latched.

4. **`flight_trail.gd:37`** used `var streak := Line2D.new()` — the only `:=` in the codebase,
   against `architecture.md`'s "Never `:=`". Now explicitly typed.

5. **Doc rot corrected:**
   - `CLAUDE.md` scene graph was missing `FarPeaks`, `BirdFlock`, `GroundTreeSpawner`,
     `GlideCoinSpawner` and `BiomeDirector`; described `SkyBackdrop` as a "static gradient"
     (it now carries stars, glow and a sun/moon and rebakes during transitions); and listed
     `State` without `SHOP`.
   - `CLAUDE.md` said "six gates maintained, other 18 archived". There are now ten maintained
     (six physics + `biome_schedule_check` + `sky_layer_check` + `ice_look_capture` +
     `biome_contact_sheet`) and ~19 archived. `debugging.md` was already correct; CLAUDE.md
     had not caught up, and it is the file that gets read first.
   - `architecture.md` — documented what `SHOP` actually does (modal, `shop_return_state`).
   - `dead_code.md` — obstacle hit calls `absorb_hit()`, not `die()`; parallax is four layers
     at 0.03–0.3, not one at 0.3.

---

## Real bugs found

*(All five were found in pass 1 and left unfixed pending your call. Four were fixed in pass 2 —
see the `FIXED` note on each.)*

### 1. A held shield powerup is silently destroyed by an unrelated glide landing

**FIXED** — `not has_shield` guard in `update_glide_landing_shield()`.

`player.gd`, `update_glide_landing_shield()`. `gain_shield()` has exactly two callers: the
shield powerup (untimed, `INF`) and the glide-landing grant (1s timer). The glide path sets
`is_shield_from_glide_landing = true` **unconditionally**, and 1s later does
`has_shield = false` unconditionally. Nothing checks whether a real shield was already held.

Sequence: collect a shield → don't get hit (it's untimed, so it persists) → later collect
glide → land → 1s later the purchased shield is gone. Worse, nothing emits `shield_consumed`,
so `PowerupManager.active_effects` still contains `EFFECT_SHIELD`: the manager and the player
now disagree, and the next obstacle kills you.

The comment at `player.gd:161-163` claims the opposite — "a shield actually EARNED via a
shield powerup mid-flight is never clipped by this timer". That's true of `absorb_hit()` only,
not of timer expiry.

Reachable in ordinary play: shield is weight 13 and glide 15 out of ~100, and shield never
expires on its own.

Minimal fix (2 lines, no physics surface):
```gdscript
elif is_glide_landing_shield_pending and is_on_floor():
    is_glide_landing_shield_pending = false
    if not has_shield:          # don't clobber a real shield
        gain_shield()
        is_shield_from_glide_landing = true
        glide_landing_shield_timer = GLIDE_LANDING_SHIELD_DURATION
```

### 2. `glide_coin_spawner.spawn_trail_coin()` — the documented fallback doesn't exist

**FIXED** — fallback implemented, with the void-failing candidates kept ineligible.

The function ends with a comment saying "place the last candidate anyway rather than silently
dropping the coin", and then no such placement happens — the loop just falls off the end. So
when all `MAX_PLACEMENT_ATTEMPTS` candidates land too close to an existing coin (or over a
void), the coin *is* silently dropped, which is exactly what the comment says it avoids.
Cosmetic only, but comment and code disagree; pick one.

### 3. `biome_distance` is printed by the gate, never asserted

**FIXED** — new `shipping_values_check.gd` covers this and ten other knobs. See Round 2.

`biome_schedule_check.gd:120` prints `biome_distance=`, and `HANDOFF.md` calls that a
"tripwire". It isn't one — nothing compares it to 75000. I ran the gate against the TEMP
value currently in your working tree and it returned **`PASS  biome_distance=7500.0`**.

Given that TEMP values are live right now in `biome_director.gd` and `obstacle_spawner.gd`,
nothing mechanically prevents committing them. A three-line assertion in the gate would
(`biome_director.gd` is a `const`, so the check is free).

### 4. Three spawners are missing the null guard the other two document as load-bearing

**FIXED** — guard added to all three.

`obstacle_spawner.gd` and `powerup_spawner.gd` both open `_physics_process` with an explicit
null guard and a comment explaining why: `set_physics_process(false)` in `_ready()` is
documented (`debugging.md`) as **not reliably suppressing `_physics_process` in headless
harness runs**.

`coin_spawner.gd`, `ground_tree_spawner.gd` and `glide_coin_spawner.gd` all call
`set_physics_process(false)` on failure and then dereference `terrain_generator` / `player`
in `_physics_process` with no guard. If the documented unreliability bites, those three throw
instead of no-oping. Same three-line pattern as the other two.

### 5. Editor playtests never see the real powerup schedule

**NOT FIXED, deliberately** — see Round 2 for why.

`powerup_spawner.gd:47,52`:
```gdscript
var debug_first_powerup_time_override: float = 5.0 if OS.is_debug_build() else -1.0
var debug_first_powerup_effect_override: StringName = PowerupManager.EFFECT_GLIDE if OS.is_debug_build() else &""
```
Every editor run's first powerup is **always glide, always at 5s**. That's correct for the
phase-3 glide work it was written for, and stale now — it means no editor playtest ever
exercises the real first-spawn draw, and any "the powerups feel wrong" impression is measured
against a rigged first pickup. Release builds are unaffected. Suggest setting the effect
override back to `&""` and keeping the time override.

---

## Organisation observations (no action taken)

### Comment density is the codebase's dominant cost

Roughly **4,000 of 14,535 GDScript lines are comments (~28%)**, and in the core files it is
much higher: `world_rebaser.gd` 75%, `biome_palette.gd` 58%, `obstacle_spawner.gd` 49%,
`main.gd` 43%, `terrain_generator.gd` 39% (673 comment lines).

This is mostly a genuine asset — the "measured X, tried Y, reverted, do not retry" blocks are
why this project doesn't relitigate solved problems, and they should stay. But three specific
failure modes have appeared, and all three showed up in this audit:

- comments drifting onto the wrong function (three instances, fixed above);
- two generations of a comment stacked and contradicting each other (`CHASM_EXIT_DROP`, fixed);
- comments asserting behaviour the code doesn't have (`spawn_trail_coin`, the shield claim).

The pattern: **long blocks describing an investigation are safe; long blocks describing what
the adjacent code does are the ones that rot.** Where a comment states an invariant, prefer
pointing at the gate that enforces it (as the `CHASM_LEAD_IN_LENGTH` block already does)
rather than restating the invariant.

### `GameManager` is the one file drifting toward a god object

575 lines, 28 `@export` NodePaths, 23 node references, 25 functions, and it currently owns:
screen state machine, coin score, trick rewards, the shop UI and purchases, volume sliders,
save/persistence calls, SFX triggers, upgrade application, and Android lifecycle. Every other
file in the project is genuinely one-concern.

**Not recommending a refactor now** — it works, it's well commented, and splitting it means
touching the pause/visibility invariant, which is the one thing `CLAUDE.md` marks as
single-owner. If it grows again (missions, zones), the natural seam is to lift the shop into
its own `ShopScreen` node owning its own wiring and calling back into `set_state()`; that
alone removes 9 NodePaths and ~90 lines. Worth doing *before* missions, not after.

### Speculative palette fields

`coin_color`, `obstacle_color`, `mist_strength`, `reflection_strength` are authored in all
eight `.tres` files, blended every transition frame by `blend_into()`, and gated by
`biome_schedule_check` — and read by **nothing**. (`star_density` was in this list until
`6a9560f` wired it.) That's four fields × eight palettes of data maintained ahead of use.

Defensible as authored-ahead-of-renderer (`biome_palette.gd` says so explicitly), and the
per-frame cost is four `lerpf` calls, i.e. nothing. Flagging only because it's the kind of
thing that quietly becomes permanent: either land the renderers or drop the fields. They are
items 4/6/7 on `HANDOFF.md`'s list.

### `sky_backdrop.build_moon_texture()` runs a 65,536-iteration GDScript loop in `_ready()`

**RESOLVED 2026-08-27 — the function is gone.** The moon is authored art now
(`MOON_TEXTURE`, a `preload`), so this loop is not paid on any scene load. It was removed for
appearance rather than for speed — the procedural crescent rendered as an eclipse — but it
closes this item outright. The starfield and sky bakes below still stand.

Per pixel: two `Vector2.distance_to`, a `Gradient.sample`, a `smoothstep`, a `lerpf` and an
`Image.set_pixel`. Plus the starfield image (1024×576 alloc) and the sky bake (2048 px).

This is paid on **every scene load, and restart is `reload_current_scene()`** — so every
death→restart pays it again, on the phone. I did not measure it (needs a windowed run), and
it may well be fine. Worth timing on device before shipping; if it bites, the fix is caching
the two celestial textures statically across reloads rather than making them cheaper.

### Minor inconsistencies

- `sky_backdrop.gd` and `snow_drift.gd` have no `class_name`, so `biome_director` can't get a
  compile-checked call and carries `resolve_palette_consumer()` + `has_method()` guards to
  compensate. Adding `class_name` to both would let the compiler do it and delete that
  function.
- `obstacle.gd` has no `class_name`; `coin.gd` and `powerup.gd` both do.
- `background_generator.remove_segment()` uses synchronous `free()` inside
  `_physics_process`, where `terrain_generator`, `coin_spawner` and `ground_tree_spawner` all
  use `queue_free()` with a comment explaining why. It is *safe* here (Polygon2D/TextureRect,
  no physics bodies) but it's the one place the rule is broken without saying so.
- `bird_flock.gd` declares `viewport_width`/`viewport_height` mid-file rather than in the var
  block; also reassigns `bird_states[i] = state` where `state` is already a reference, so the
  write is a no-op.
- Unreferenced symbols: `UpgradeStore.UPGRADE_IDS`, `UpgradeStore.is_maxed()`,
  `PowerupManager.is_effect_active()`. All three are plausible future API — left alone, noted
  so a future sweep doesn't have to rediscover them. (These are the *only* unreferenced
  symbols in the whole codebase, which is a good sign.)
- `glide_coin_spawner` uses global `randf_range()` where every other spawner uses a seeded
  pure hash keyed on `session_seed`. Means glide coin layout is not replayable from a seed.
  Cosmetic, and `architecture.md` already explains why this spawner sidesteps the seed — but
  it's the one break in an otherwise universal contract.
- `game_manager._on_player_jumped()` is an empty `pass` with a comment (jump SFX muted
  2026-08-04). Intentional and documented; fine.

### `CLAUDE.md` is 196 lines against its own stated ~175 cap

It was 193 before this pass; I spent +3 net to document five nodes that were missing from the
scene graph entirely, and compressed the build-order and gates sections to pay for most of it.
Getting to 175 now means deleting content you deliberately put there, which isn't an
organisation-pass call. If you want it back under: the two highest-value cuts are §1's chasm
detail and §8's ice-tile mechanics (~8 lines), both of which are fully covered by `terrain.md`
and `biomes.md` respectively and are the only build-order entries that explain *mechanism*
rather than *status*.

### `HANDOFF.md` is stale — recommend deleting, but **not doing it while another session is live**

It says "read this, then delete this file". It is out of date in three ways: item 8 (stars) is
done as of `6a9560f`; the TEMP values it records (25000/10000) are not the ones now in the
tree (7500/2000); and the loose end it lists as "untracked, recommend deleting"
(`art_source/glacier_teal_faceted_depth_panel.png`) **is now tracked**. Its two open questions
(judge the dissolve, decide the biome cadence) are still genuinely open, which is presumably
why it survived. Since visual work is in progress in another terminal right now, I left it
alone — delete it once the cadence decision lands, moving that decision into `biomes.md`.

---

## On scope creep

You raised keeping this lean. The current shape is healthy: one autoload, one concern per
file, no framework, no dependency, 195 files, ~1.3MB of assets. Nothing here reads as
Brawl-Stars-shaped.

The two things that would actually make it heavy, in order:

1. **`scripts/debug/` is 7,441 lines — 51% as much code as the game itself**, and ~19 of its
   29 files are archived one-offs that `CLAUDE.md` says never to trust. They cost nothing at
   runtime (never loaded outside an explicit `--script` run), so this is not a performance
   problem; it is a *comprehension* problem, and it is the single biggest source of "which of
   these do I believe?" in the repo. Suggestion, no action taken: move the archived ones to
   `scripts/debug/archive/` so the live gates are visually obvious in a directory listing.
   Zero risk — they're invoked by explicit path, and `debugging.md` already lists which is
   which.
2. **Authoring data ahead of renderers** (the four palette fields). Cheap individually; the
   habit is what compounds.

Everything else — six powerups, eight biomes, five screens, one upgrade track — is small.

---

# Round 2 — same day, fixes applied

Pass 1 above was read-only plus comment/doc corrections. This pass turned the findings into
code. Everything here is small and was gate-verified; nothing touches collision, terrain
geometry, the velocity model or the camera.

## New: `scripts/debug/shipping_values_check.gd` — run before every commit

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/debug/shipping_values_check.gd
```

~0.2s. Closes the hole behind finding 3, and it turned out to be a bigger hole than that one
knob. Every debug knob in this project is a plain `var` *on purpose* so the editor can't
serialise it into `main.tscn` — but the unpaid cost of that choice is that **no gate could see
one left flipped.** `ObstacleSpawner.debug_spawning_disabled` was documented as "check by hand";
`biome_distance`'s "tripwire" was only ever a printed number.

Two halves, and the second is the stronger:

1. **Source-level default of eleven knobs**, read off `.new()`-ed instances.
2. **A text scan of `main.tscn`** for any line starting `debug_`, `world_rebase_enabled` or
   `require_start_screen`. Text rather than a property read, because the text catches a property
   this file has never heard of — which is the actual failure mode.

Verified in all three states: caught all three live TEMP values (exit 1); `--allow-temp`
downgrades to `WARN` and exits 0; and injecting `world_rebase_enabled = false` into `main.tscn`
was caught **at the exact line**. That last test is the one worth noting — during it the script
*default* still read `true`, which is precisely why half 1 alone would not have caught the
original freeze regression. `main.tscn` was restored and confirmed clean by `git diff`.

Current output against your working tree (three TEMP values live, as intended):

```
ObstacleSpawner.debug_spawning_disabled    true      != false
BiomeDirector.BIOME_DISTANCE               7500.0    != 75000.0
BiomeDirector.TRANSITION_DISTANCE          2000.0    != 12000.0
SHIPPING_VALUES_CHECK FAIL  3 knob(s) not at shipping values
```

## Fixes

| # | Fix | Risk |
|---|---|---|
| 1 | `not has_shield` guard so a glide landing can't destroy a held shield powerup | Behaviour, intended; no physics surface |
| 2 | `spawn_trail_coin()` fallback now exists; void-failing candidates stay ineligible | Cosmetic (glide coins) |
| 4 | Null guard added to `coin_spawner`, `ground_tree_spawner`, `glide_coin_spawner` | None — no behaviour change in normal play |
| — | `class_name Obstacle` added, matching `coin.gd` / `powerup.gd` | None |

## Deliberately NOT done

- **Finding 5, the powerup debug override.** `debug_first_powerup_effect_override` pins the
  first editor pickup to `glide` at 5s. It is stale relative to its phase-3 origin — but a
  guaranteed early glide is genuinely *useful* for eyeballing sky work, which is what the other
  terminal is doing right now. Changing a debug default underneath a live playtest is its own
  kind of unhelpful. Flip it back to `&""` when the visual pass lands.
- **`class_name` on `sky_backdrop.gd` / `snow_drift.gd`** (which would let the compiler check
  `apply_palette` and delete `BiomeDirector.resolve_palette_consumer()`). Correct change, wrong
  moment: it edits `biome_director.gd`, which the other session is actively editing. Conflict
  risk beats the tidiness win.
- **Archiving the ~19 dead probes into `scripts/debug/archive/`.** Still recommended, still not
  done: probe filenames are referenced by name in code comments across `player.gd` and
  `terrain_generator.gd`, so the move makes those stale unless they move with it. Worth one
  focused pass, not a drive-by.
- **The long physics gates** (freeze-search, floor-flicker full form at ~3.5h). Nothing in
  either pass touches segments, collision, the player velocity model or the camera; the
  shield/coin changes are unreachable from those gates anyway (both disable powerups, so glide
  never activates). Chasm probe + floor-flicker smoke were run instead and both passed.
