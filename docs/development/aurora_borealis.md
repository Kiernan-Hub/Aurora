# Aurora borealis — planned, not started

**This is the feature the game is named after.** Treat it as a real major feature, not
visual polish: plan it out fully before touching code, the way the frozen lake was planned
before "Frozen lake complete" (`docs/research/`, and `terrain.md`/`visuals.md`).

## What it is

A rare, spectacle-only event, structurally the sibling of the frozen lake
(`FrozenLakeDirector`, `terrain.md` §10) but rarer and purely cosmetic — there is no
gameplay lockout equivalent needed beyond what the lake already proves out (jump lock,
spawner suppression), because the point of the aurora is "stop and watch the sky," not a
new mechanic.

- **Trigger:** cumulative playtime, same mechanism as the lake (`SaveStore`'s cumulative
  playtime counter), but a much longer interval — roughly **every 60 minutes** of
  cumulative playtime, vs. the lake's 20. It should feel rare enough that seeing it is an
  event players mention, not a thing they learn to expect on a schedule.
- **Scope:** sky-only. Ribbons of colour across the sky layer, on top of / replacing the
  existing `SkyBackdrop` stack (`SkyCelestial`, `SkyStars`, `SkyGlow`, `SkyGradient`) for
  the duration. Does not touch terrain, ice tint, or collision — same boundary the biome
  system already holds (`biomes.md`: "It is scenery only").
- **It is its own biome slot, not a `BiomeDirector` cycle entry.** The eight `BiomePalette`
  resources rotate on world-px distance and are meant to feel like a day passing
  (`biomes.md`); the aurora is playtime-gated and rare by design, so it doesn't belong in
  `BIOME_CYCLE`. Model it the way the frozen lake sits *beside* the terrain generator
  rather than inside it: a dedicated `AuroraDirector` (or a mode on `BiomeDirector`, TBD
  during planning) that can override the sky stack when armed, independent of which of the
  eight palettes is currently active underneath.
- **Blend ramp:** follow the lake's precedent exactly — one `get_aurora_blend()` function
  that every cosmetic piece rides (ribbon opacity/intensity, camera framing if any, star
  brightness), the same discipline note in `terrain.md` §10 ("everything cosmetic rides ONE
  ramp"). Don't let two different systems independently fade the same event.
- **First-time hook:** the frozen lake's first crossing grants the game's first achievement
  (`architecture.md` §11). The aurora's first sighting should get the same treatment —
  `AchievementManager` already listens for signals rather than the reverse, so this is a
  table row plus one `.connect()` once the director exists.

## Open questions to resolve before implementation

- Does the aurora coincide with a normal terrain segment (player keeps skating through it),
  or does it want its own forced flat/simple segment like the lake's 7500px stretch, so the
  player isn't fighting terrain while looking up? Leaning toward **no forced segment** —
  the point is a sky event during ordinary play, not a second set piece — but confirm this
  once the visual is prototyped, since a busy terrain moment competing with the sky for
  attention could undercut the "just watch it" feeling.
- Ribbon rendering approach: procedural (shader, cheap, infinitely varied) vs. a small
  number of authored sprite/texture layers cross-faded (matches the "no realism, flat/vector"
  direction, cheaper to art-direct, easier to keep consistent with the ice-canyon sky work
  below). Given the project's shader budget is currently exactly two, both owned by ice
  (`visuals.md`), a third shader needs the same standard of justification — decide this
  deliberately, not by default.
- Does it get a distinct colour identity from the eight existing biome palettes, or does it
  recolour itself to whatever palette is active underneath? Given how special this is meant
  to feel, a **fixed, unmistakable aurora palette** (green/violet ribbons regardless of time
  of day) is probably right — it should never be confused for "just another biome."

## Sequencing

Not scheduled yet. The near-term background work (ice canyon walls / shard spires, extra
sky elements — see `visuals.md`) should land first and settle what the sky layer stack
looks like without the aurora, since the aurora's ribbons need to sit correctly against
whatever the new silhouette/sky composition ends up being. Revisit this doc to turn the
open questions above into a real phased plan once that lands.
