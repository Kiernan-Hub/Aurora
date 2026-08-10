# Handoff — ice pattern crossfade (2026-08-09, session 4)

**Read this, do "Do this first", then delete this file.** It is a session handoff, not
permanent documentation. Everything durable already lives in `docs/development/biomes.md`
and `docs/development/debugging.md`.

Nothing in this work touches collision, terrain geometry, the velocity model or any game
state. It is scenery only.

---

## Where we left off

The hard seam where the ice pattern changed between biomes is **fixed and committed**. It had
two causes, and both are dealt with:

1. **A brightness step.** The variant tiles didn't share the default tile's depth ramp, and
   the tile is a multiplier, so the chunk boundary was a flat ~12% jump across a vertical
   line. Fixed in `build_ice_texture.py`, which now rescales every variant onto the default
   ramp automatically.
2. **The pattern break itself.** Fixed by replacing option B (snap the tile per chunk) with
   **option A, a two-band cross-dissolve**. Every ground run now carries two stacked
   `Polygon2D`s — base = outgoing tile, overlay = incoming tile at `alpha = ice channel
   weight`.

Full design notes: `biomes.md`, "How the pattern crossfades: two stacked bands".

### All gates green

| Gate | Result |
|---|---|
| Biome check | PASS — 8 palettes, `ice_variants=2`, ramp + no-snap assertions |
| Terrain shape | PASS — 8 seeds, 0 violations, max slope 20.13° unchanged |
| Floor flicker | PASS — 0.0000 uphill flip rate, 0/0 recoveries/stuck |
| Camera shake | PASS — mean follow 9.87px, `flat` mean jerk 0.00569, **bit-identical to the clean-HEAD baseline** |
| Dissolve probe | PASS — throwaway, see below |
| Freeze replay / search | **Not run.** Nothing in this change touches segments, collision, the player or the velocity model, and they cost hours. Run them if you disagree. |

**The band code is invisible to every gate**, because `BiomeDirector` returns early under
`--headless` and so `apply_ice_palette()` — and therefore `repaint_chunk()` — never runs. It
was verified once with a throwaway probe that built a real `Main` and drove
`apply_ice_palette()` by hand across the weight: bands built in pairs, overlay hidden at
weight 0, correct tile and alpha on each band mid-dissolve, a chunk born mid-dissolve matching
the ones already on screen, and the weight-1 → next-frame-weight-0 handoff showing the same
tile. Checked against a deliberately broken `repaint_ice_band()` before being trusted, then
deleted rather than added to the 18 archived one-offs `CLAUDE.md` warns about. Rebuild it if
band construction changes again.

---

## Do this first, next session

### 1. THREE TEMP DEBUG VALUES ARE LIVE IN THE WORKING TREE — uncommitted, on purpose

```
scripts/systems/biome_director.gd
  BIOME_DISTANCE      25000.0  # TEMP -- real value 75000.0
  TRANSITION_DISTANCE 10000.0  # TEMP -- real value 12000.0
scripts/systems/obstacle_spawner.gd
  debug_spawning_disabled = true   # TEMP -- real value false
```

These exist so the biome cycle can be eyeballed without dying or waiting. **The committed
tree has the real values** — these three lines are working-tree-only, and `git diff` is the
whole story.

Tripwires: the biome gate prints `biome_distance=` on its PASS line (anything but `75000.0`
is not shippable). **Nothing at all catches the obstacle flag** — it is a plain var precisely
so it cannot be serialised into `main.tscn`, which also means no gate reads it. Check by hand.

Note obstacles are off but **chasms are not**, so a debug run can still die in a void.
`debug_chasm_disabled` sits next to it if you want a fully deathless run.

At the temp values: ~50s for the opening biome, ~39s for the next, settling to ~33s at cap
speed, with a ~14s colour crossfade whose last ~11s is the ice dissolve.

### 2. Judge the dissolve in game — the one thing no gate can decide

Not yet eyeballed at the current settings. Two patterns at 50/50 is a double exposure by
nature; the tiles are low-contrast depth ramps so it should read as the cracks reshaping, but
that is a by-eye call. `glacier_teal` (biome 3) → `mauve_haze` (biome 4) is the only place two
*different* tiles meet, so it is the only place the dissolve is visible at all.

Watch for:
1. The dissolve reading as a dissolve, not as a fade to mush. **If it disappoints, the fix is
   narrowing the ice channel's curve so the 50/50 point is passed through faster — not a
   shader.**
2. No pop at either end of the window. The invariant says there is none and the probe
   confirmed the tile is identical across the handoff frame, but eyes beat both.
3. `glacier_teal` reading pale/flat.
4. `four.png` has no real snow band, so the ramp match lifts its top rows into a bright band
   with little internal structure. If it reads as a flat white bar, ease `RAMP_MATCH_STRENGTH`
   to ~0.7 and rebuild — **do not turn the match off**, it is what killed the brightness step.
5. `mauve_haze`'s surface reading as a hard stroke instead of a snow band.

Tile figures after the ramp match:

| tile | ride line | 5% | 50% | seam err |
|---|---|---|---|---|
| smooth (reference) | 0.98 | 0.93 | 0.49 | 0.0028 |
| faceted (`four.png`, `glacier_teal`) — was 0.86 / 0.85 / 0.66 | 0.98 | 0.91 | 0.49 | 0.0046 |
| cracked (`five.png`, `mauve_haze`) — was 0.94 / 0.72 / 0.55 | 0.97 | 0.91 | 0.50 | 0.0110 |

Gate-measured ramp deviation is now 0.002 and 0.004 against a 0.02 tolerance.

### 3. Decide the real biome cadence — still open, still blocks shipping

At the real 75000, a full 8-biome cycle is ~13.7 min and a 2-minute run doesn't finish
biome 1. Costed alternatives: **25000** (~40s/biome early, ~33s at cap, ~5 min full cycle) or
**40000** (~53s/biome, ~8 min full cycle). The temp value above is 25000, so this session is
effectively a live test of that option — form an opinion while judging item 2.
Don't revert to 75000 on autopilot.

---

## Loose ends

- `assets/textures/terrain/glacier_teal_faceted_depth_panel.png` (untracked, plus its
  `.import`) — leftover raw panel from an earlier attempt, nothing references it. Deliberately
  **not** committed and **not** deleted without asking. Recommend deleting.
- `CLAUDE.md` is 193 lines against its own ~175 cap. The old "`repaint_chunk()` must never
  touch the texture" trap is now **dead and reversed** — with two bands there is a halfway, so
  it writes both textures every call. Good thing it was never promoted into `CLAUDE.md`; don't
  add it now.
- `debugging.md` now records that **floor-flicker's full gate form takes ~3h20m**, not the
  ~33 min it used to claim. The tick rate is genuinely 60Hz (the 2000-frame form and
  camera-shake both hit it exactly) and the full run is ~6x off that anyway, at ~1% CPU.
  Unexplained; a probe-runtime mystery, not a game bug. **Possible cause, reported by the
  owner: the laptop was shut/asleep for part of the run**, which would fully account for it —
  worth re-timing on a machine left awake before treating it as real.

## Still to do, in priority order

1. Judge the dissolve in game (above). Nothing else here is blocked by it.
2. Decide the biome cadence (above). Blocks shipping.
3. Revert the three TEMP values when done eyeballing.
4. Gameplay contrast pass — `coin_color`/`obstacle_color` are authored and read by nothing.
   No art dependency, safest remaining item.
5. Trees — still flat silhouettes, cheap fix in `ground_tree_spawner.gd`.
6. Mist/fog layer — `mist_strength` authored, read by nothing.
7. Reflection layer — `reflection_strength` authored, read by nothing. Real risk: not
   automatically rebase-safe, must parent under a rebased node or use `motion_scale = 0`.
8. Stars — `star_density` authored, read by nothing.

**Explicitly not planned:** hill silhouette shape variants (would need two ridge sets
cross-dissolving per parallax layer — costed and rejected in session 2), and a `.gdshader`
for the ice (option C — the two-band dissolve already gets the result).
