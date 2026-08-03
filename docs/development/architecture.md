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

## The three spawners live under TerrainGenerator on purpose

`CoinSpawner`, `ObstacleSpawner` and `PowerupSpawner` are children of
`TerrainGenerator`. Two separate reasons, both load-bearing:

**World rebasing.** `main.gd` shifts `TerrainGenerator.position.y` directly, so every
descendant — chunks, coin groups, obstacles, pickups — is carried along for free. A
spawner moved out of that subtree needs its own rebase handling or its contents drift
off the terrain after the first rebase (~26s in).

**Seed availability.** Godot runs `_ready()` on children **before** their parent, and
`TerrainGenerator._ready()` is what assigns `session_seed`. So at a spawner's `_ready()`
time the seed is still **0**. Anything seed-derived must therefore be initialised on the
first `_physics_process`, never in `_ready()`.

`CoinSpawner` (`has_initialized_coin_groups`) and `PowerupSpawner`
(`has_initialized_schedule`) both do this. `ObstacleSpawner` sidesteps it — its first
cluster time is a plain constant, and every later draw happens during
`_physics_process`.

Getting this wrong is **completely silent**. It was a real bug: `PowerupSpawner` drew
its first-spawn times in `_ready()` and so hashed seed 0 every session, making three
different replay seeds produce byte-identical schedules (39.812038s / 19.395459s every
time). Fixed 2026-08-03.

## GameManager owns all state transitions

`GameManager` runs an explicit `State { START, PLAYING, PAUSED, DEAD }` machine.
`set_state()` is the **only** place in the project allowed to touch `get_tree().paused`
or any screen's visibility — don't set either anywhere else. Adding a transition means
adding it to the enum, not writing `paused = true` somewhere new.

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

## Persistence

Everything goes through `Services.save_store` (`scripts/systems/save_store.gd`), a
**versioned** `user://save.dat`. Add fields there; never write the file directly.

Failure policy is deliberately asymmetric: a failed **read** (missing, unreadable,
malformed, wrong type) silently yields defaults, because a corrupt save must never stop
someone playing. A failed **write** calls `push_error`, because that one is a real bug
and silently losing a best score is worse than a log line.

A file with no `version` key is treated as v0 and upgraded in place on the next write.

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
