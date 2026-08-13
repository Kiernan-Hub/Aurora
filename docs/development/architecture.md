# Architecture & conventions

How the scene is wired and what owns what. `CLAUDE.md` has the scene-graph diagram and
the two or three rules that break things silently; this file has the reasoning.

## Wiring is by sibling path

Nodes find each other through `@export var ..._path: NodePath` defaults pointing at
siblings (`NodePath("../Player")`), resolved with `get_node_or_null` and null-guarded.
The house pattern for a missing node is `push_error(...)` + `set_physics_process(false)`
— but see the caveat on that call in `debugging.md`, it does not reliably suppress
`_physics_process` in headless harness runs, so hot paths need an explicit null guard
too.

`BackgroundGenerator` falls back to `/root/Main/Player` if `player_path` is unset.
(Ignore any older doc claiming `GameState.gd` exists — it doesn't.)

## The spawners live under TerrainGenerator on purpose

`CoinSpawner`, `ObstacleSpawner`, `PowerupSpawner`, `GroundTreeSpawner` (decorative,
`docs/development/visuals.md`), `GlideCoinSpawner` and `RareCoinSpawner` are children of
`TerrainGenerator`.
Two separate reasons, both load-bearing:

**World rebasing.** `main.gd` shifts `TerrainGenerator.position.y` directly, so every
descendant — chunks, coin groups, obstacles, pickups — is carried along for free. A
spawner moved out of that subtree needs its own rebase handling or its contents drift
off the terrain after the first rebase (~26s in).

**Seed availability.** Godot runs `_ready()` on children **before** their parent, and
`TerrainGenerator._ready()` is what assigns `session_seed`. So at a spawner's `_ready()`
time the seed is still **0**. Anything seed-derived must therefore be initialised on the
first `_physics_process`, never in `_ready()`.

`CoinSpawner` (`has_initialized_coin_groups`), `PowerupSpawner` and `RareCoinSpawner`
(`has_initialized_schedule` in both) all do this. `ObstacleSpawner` sidesteps it — its first
cluster time is a plain constant, and every later draw happens during
`_physics_process`. `GlideCoinSpawner` sidesteps it differently: it never reads
`session_seed` at all — a glide is powerup-timed and player-steered, not a function of
`(session_seed, world_x)`, so there is nothing to precompute. It spawns coins ahead of the
player's live x each physics frame instead, but each coin's y comes from
`terrain_generator.get_terrain_height(x)`, not the player's own altitude — an earlier
version anchored to the player and produced a straight vertical column of coins on any
real climb, and worked against the mechanic's own point (an unbounded glide is meant to
be discouraged, not rewarded, by the trail following the player up). Being a plain child
of `TerrainGenerator` with no offset of its own is what makes this free: its local
coordinates already are `get_terrain_height()`'s frame, so no `global_position`
conversion is needed either, and it stays correctly aligned across a world rebase without
needing to know one happened.

Getting this wrong is **completely silent**. It was a real bug: `PowerupSpawner` drew
its first-spawn times in `_ready()` and so hashed seed 0 every session, making three
different replay seeds produce byte-identical schedules (39.812038s / 19.395459s every
time). Fixed 2026-08-03.

## GameManager owns all state transitions

`GameManager` runs an explicit `State { START, PLAYING, PAUSED, DEAD, SHOP }` machine.
`set_state()` is the **only** place in the project allowed to touch `get_tree().paused`
or any screen's visibility — don't set either anywhere else. Adding a transition means
adding it to the enum, not writing `paused = true` somewhere new.

`SHOP` needs no pause semantics of its own — `paused = new_state != PLAYING` already covers
it. It is a *modal* over whichever screen opened it (START's Upgrades button or DEAD's Shop
button), so `shop_return_state` records which, and that screen stays visible underneath;
closing returns there rather than always to DEAD. Purchases apply to the next run, and there
is deliberately no path that mutates player stats mid-run.

This was previously implicit in "`get_tree().paused` plus whichever `Control` happens to
be visible". That works for two screens and stops working at four: a pause screen makes
"paused" ambiguous (menu pause or death pause?) and the audio layer will need to know
which transition it is reacting to.

Two transitions call `Input.action_release(&"ui_accept")` on the way out — start and
resume. Without it, the same tap that dismissed the screen still reads as just-pressed
on the first physics frame back in play, i.e. a free involuntary jump. See `input.md`.

Restart is `get_tree().reload_current_scene()`, and it unpauses first: the tree-wide
paused flag is **not** reset by the reload, so leaving it true rebuilds the scene into a
frozen world.

`GameManager._notification()` adds the Android lifecycle triggers (added 2026-08-03,
there was no `_notification` anywhere before that) — back button and focus loss. Both
route through `set_state()`, so they are new *triggers*, not a second pause mechanism.
Back is pause mid-run / resume on the pause screen / quit on START and DEAD, which
requires `application/config/quit_on_go_back=false` in `project.godot` or Godot quits
before the notification arrives. Focus-out pauses only from PLAYING and deliberately does
**not** auto-resume on focus-in. `GameManager` sets `process_mode = ALWAYS` so these
still arrive while the tree is paused; it has no `_process`, so that costs nothing.

## Persistence

Everything goes through `Services.save_store` (`scripts/systems/save_store.gd`), a
**versioned** `user://save.dat`. Add fields there; never write the file directly.

Failure policy is deliberately asymmetric: a failed **read** (missing, unreadable,
malformed, wrong type) silently yields defaults, because a corrupt save must never stop
someone playing. A failed **write** calls `push_error`, because that one is a real bug
and silently losing a best score is worse than a log line.

A file with no `version` key is treated as v0 and upgraded in place on the next write.

**v2 (2026-08-04)** added meta-progression: `coin_wallet` (spendable currency, distinct
from `best_score`, which stays the run-score stat) and `upgrades`, an open
`Dictionary[String, int]` of upgrade id → level. Reading a v1 file yields wallet 0 and
level 0 everywhere, which is exactly the correct new-player state, so as with v0 → v1
there is no explicit conversion step. Two traps when adding fields of this shape:
`JSON.parse_string` returns an **untyped** Dictionary — assigning one straight into a
`Dictionary[String, int]` fails at runtime, so copy key by key — and JSON round-trips
every number as a float, so the `int()` casts are mandatory.

Keeping upgrades in an open dictionary rather than a field per upgrade means adding an
upgrade *type* needs no version bump; only a new top-level *concept* (zone progress,
mission state) does. Unknown ids from a newer build survive a round-trip and are clamped
to a legal level by `UpgradeStore.get_level`, so saves stay compatible in both directions.

`record_run()` **always writes now**, where it used to write only on a new best: every
run banks its coins, so there is always something to persist. It is still exactly one
disk write per death. Anything that needs to persist per-run state should go through it
rather than adding a second write.

## The one autoload

There is **exactly one**: `Services` (`scripts/autoload/services.gd`, `class_name
GameServices`), added 2026-08-03. Everything else is still sibling-path wiring, and a
new global needs a real justification.

**Why it's allowed.** Restart destroys and rebuilds every node in `main.tscn`, so
anything that must outlive a run — the save file, volume settings, and later music that
shouldn't restart on every death — cannot live in that scene. The no-autoload rule it
breaks was about `@export` *scene serialization* (`docs/research/freeze_bug.md`), which
an autoload has no exposure to: no scene to serialize into, no Inspector to drift from.
Nothing in that file is `@export`, for the same reason nothing in `Main` or
`GameManager` is.

**Never write `Services.x` in gameplay code.** `--headless --script` runs don't register
autoloads, so a direct reference is a *compile* error there — the script fails to load
entirely, its class resolves to `Nil`, and every probe line configuring it fails against
`Nil`. The gate then sits paused forever with no useful output. Use
`GameServices.resolve(self)` and null-guard the result; services are optional by
contract. Full mechanism and the sibling `class_name`-cache trap: `debugging.md`.

The `class_name` is `GameServices`, not `Services`, because a `class_name` identical to
the autoload's global name is a hard conflict.

Autoloads **are** instantiated in `--headless --script` runs, so this file executes
inside every probe. It carries an `is_headless` flag for that reason — anything added
there that touches audio, rendering or input must sit behind it.

## Order-sensitivity to watch for

`TerrainGenerator._ready()` reads `player.floor_max_angle` into
`session_floor_max_angle`. `Player` never sets that explicitly, so the read isn't
order-sensitive today — but sibling `_ready()` order **has** been load-bearing here
before (`docs/research/freeze_bug.md`). Check before assuming a new `_ready()`-time
`player.*` read is safe.

## Code conventions

- Static typing on everything, including loop variables and typed dicts/arrays.
- Never `:=`. Explicit return type always.
- Tunables are `const`, not `@export`, unless a human genuinely needs to sweep them in
  the Inspector. Anything that is a *fix* rather than a knob must not be `@export` at
  all — see the `world_rebase_enabled` regression in `CLAUDE.md`.
- Systems stay one-file-per-concern under `scripts/systems/`.
