# Handoff — background

Rewritten 2026-08-24. The previous version described the panorama as an unwired experiment
and was written around `PineLine`; both had been false for eight commits, and it was sending
sessions back toward finished work. The investigation history it carried now lives in
`docs/research/background_differentiation.md` — read that only if you need to know what was
already ruled out.

**Working agreement, still in force:** one numbered sub-step at a time, commit it alone, stop
and wait for an explicit "go." Flag anything with real bug potential, or with a much cheaper
alternative, before building it. Don't self-verify visuals with screenshots — the owner checks
in-game faster.

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
`art_source/background/arch_spike_massif.png` by `scripts/tools/build_pano_strip.py`, and the
rebuild is deterministic — verified byte-identical during the 2026-08-24 review. The `.xcf`
working files for that panel are in `art_source/background/`.

The raster-vs-biome-tint question that killed the three earlier raster attempts was answered:
greyscale × flat tint reconstructs the reference to within 3–5/255, so a baked panel does
survive the multiply. That measurement is why this attempt shipped where the others did not.

## Open decisions — the owner's call, not a cleanup

Three findings from the 2026-08-24 review are background numbers, deliberately left untouched
so they land with the visual pass rather than a hygiene commit. Full detail in
`docs/review/2026-08-24-code-and-repo-review.md`, items #3, #4 and #5.

1. **Parallax depth was flattened.** Near-to-far went from 10:1 (`0.30 … 0.03`) to 3.3:1
   (`0.05 … 0.015`), and the fastest layer is now 6× slower than it was. The owner's stated
   reason the old background worked was *"the front layer moves faster than the ones behind
   it."* Whether this was a deliberate re-tune for the panorama or drift across eight commits
   is not recoverable from the commits. Four numbers in `main.tscn`.
2. **The panorama repeats every ~55 s** at `MAX_SPEED` (40,956 world px), on the most visible
   layer, with 56% of it on screen at once. Cheapest levers: raise `motion_scale` (also helps
   1, but shortens the loop in time), or bake a wider strip. **Do not** add a second offset
   copy — `motion_mirroring` is one span by construction and a second sprite reintroduces the
   tear `centered = false` exists to prevent.
3. **`scenery_near` is never rendered.** `depth_t` now tops out at 0.45, so only the far 45%
   of every palette's `scenery_far → scenery_near` ramp reaches the screen, and
   `biome_schedule_check` measures the authored endpoints — so it cannot see this. Nothing is
   broken today (`pale_morning` is the tightest at 0.100 against a 0.08 floor) but the gate
   would keep passing all the way to collapse. Fixing the gate to read the scene's real
   `depth_t` is the durable half of this.

## Before trusting this file

Re-run the fast gates — `shipping_values_check`, `biome_schedule_check`,
`terrain_invariant_check`. After any silhouette or palette change, also run the three windowed
visual gates (`sky_layer_check`, `ice_look_capture`, `biome_contact_sheet`), which **must run
without `--headless`**.

## Still in view

The **aurora borealis** (`docs/development/aurora_borealis.md`, CLAUDE.md build-order #12) is
fully planned, not started, and is the feature the game is named after. Sky-only, purely
cosmetic, rides its own blend ramp like the frozen lake. It was deliberately sequenced *after*
the background settles the composition its ribbons sit against — which, with the panorama
shipped, is closer to true than it was.
