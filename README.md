# Aura

An endless 2D downhill skater in the Alto's Adventure tradition — Godot 4.7, GDScript, Mobile
renderer, targeting Android. The player auto-runs right at a speed that ramps over time, on
infinite seeded procedural terrain.

Shipped and working: the core loop, chasms, coins and scoring, six powerups, airborne tricks, a
jump-upgrade track with a shop, achievements, a frozen-lake set piece, and an eight-palette biome
cycle over a baked panorama background. **Gameplay art is still placeholder rects.**

## Getting started

Godot 4.7 is required — the project pins `4.7` and the Mobile renderer, physics at 60 Hz with
interpolation off. On macOS the engine lives at `/Applications/Godot.app/Contents/MacOS/Godot`.

```bash
# play it
/Applications/Godot.app/Contents/MacOS/Godot --path .

# open the editor
/Applications/Godot.app/Contents/MacOS/Godot --editor --path .
```

There is no build script and no test framework — validation is a set of Godot scripts run as
gates (below).

## Checks

```bash
./scripts/check.sh          # the fast five, ~25s — run before every commit
./scripts/check.sh -v       # same, but print every gate's output
```

Twelve maintained checks exist in three tiers, and only twelve — everything else lives in
`scripts/debug/archive/`, so the directory answers "is this a gate?".

| Tier | What | When |
|---|---|---|
| **fast** | the five in `check.sh` | before every commit |
| **physics** | freeze-search, freeze-replay, floor-flicker, chasm, camera-shake | after any player, collision or segment change — minutes each |
| **visual** | `sky_layer_check`, `ice_look_capture`, `biome_contact_sheet` | after any visual change — **must run WITHOUT `--headless`** |

The visual three can never join a headless runner: `BiomeDirector` returns early under
`--headless`, so **every headless gate is blind to biome code**. Commands and full descriptions
are in `docs/development/debugging.md`.

> **Run `git status` after any engine run.** A project-settings *save* can rewrite
> `project.godot` and scene files, dropping pinned settings and authored properties. A gate
> text-scans `project.godot` for the eight pins; scene files have no such cover.

## Release

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-debug Android ./aura.apk
```

The `Android` preset carries the real application id (`com.kiernan.aura`), version, launcher and
adaptive icons, and an `exclude_filter` that keeps debug probes and experiments out of the pack —
`check.sh`'s fifth gate fails the build if any of them reach it. Still deliberately open: the
debug keystore, APK rather than AAB, empty `min_sdk`/`target_sdk`, and the themed icon.

The `aura.apk` at the repo root is gitignored and usually stale — re-export rather than
installing it.

## Documentation

**`CLAUDE.md` is the map** — the project's direction, and the traps that have cost real time.
Read it first. Everything else is one level down:

| Path | What |
|---|---|
| `docs/development/` | how each system works — architecture, terrain, physics, input, visuals, biomes, ice panels, debugging |
| `docs/research/` | closed investigations; not required reading |
| `docs/review/` | point-in-time audits and the running debt list |
| `HANDOFF.md` | where the work actually is, newest first |

Reference art and tool inputs live in `art_source/`, which is `.gdignore`d — never at the repo
root, which is imported into the export.
