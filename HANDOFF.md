# Handoff

## Start here

**Aura** is an Alto's-Adventure-style endless 2D skater in Godot 4.7 (GDScript, Mobile renderer,
Android). `CLAUDE.md` is the map — read it first; it points at everything else. This file is the
running log of *where the work is*, newest section first.

As of **2026-09-03**, head `13d89b6`. The core loop, chasms, coins, powerups, upgrades,
achievements, the frozen lake and the background are all shipped and working. Gameplay art is
still placeholder rects.

> ## 🌌 IN PROGRESS — THE AURORA BOREALIS. Read this before anything else on this page.
>
> **Branch: `claude/aurora-borealis-design-1rpnt8`.** Everything below this block predates the
> aurora and is background; none of it is blocking.
>
> **The plan is `docs/development/aurora_borealis.md` (~770 lines) and it is finished.** Read it
> in full before touching aurora code. It is not a sketch — every open question the old stub
> carried is closed by owner decision, and it has been through **three rounds of external review
> that found real errors**, each corrected in place with the evidence. Do not re-litigate its
> decisions; do not re-derive its numbers.
>
> ### Where we are
>
> | Phase | State |
> |---|---|
> | 0 — the plan | **DONE.** `432acf9`, revised `c68e947`, `a1989d6`, `f62ff1f` |
> | 1 — `GameManager.get_total_playtime_seconds()` extracted, lake calls it | **DONE, `02964b2`. GATES NOT RUN** — see below |
> | 2 — shader + `AuroraSky` + wash + camera, behind one debug knob | **NEXT** |
> | 3–8 | see the plan's Phases table |
>
> ### What to do next
>
> 1. **Run `./scripts/check.sh` against `02964b2`.** It has never been run on this change. The
>    sessions doing this work run in a Linux container with **no Godot binary** — the project's
>    Godot is a macOS app bundle — so *every* gate in this feature is owed on the owner's machine.
>    Never write "gates pass" for aurora work without having actually run them.
> 2. Then phase 2, which is deliberately look-only: no scheduling, no terrain, nothing gameplay
>    can see. Its debug knob gets its `shipping_values_check` row **in the same commit**.
>
> ### How this work is running
>
> - **One numbered phase at a time, committed alone, then stop for an explicit "go."** The
>   standing working agreement, and it is being followed literally here.
> - **An external reviewer (the owner's other assistant) reads each commit on the branch and
>   sends findings back through the owner.** It has caught genuine bugs three rounds running,
>   including two introduced by a previous round's fix. Treat its findings as real and verify
>   them against the code rather than accepting or dismissing them on tone.
> - **Verify claims, don't inherit them.** Every number in the plan that turned out to be wrong
>   was wrong because someone reasoned from a plausible constant instead of reading it
>   (`CHASM_SEGMENT_LENGTH` is not a typical segment length; `MAX_SPEED` is not the fastest the
>   player moves; a camera lift does not lower a screen-locked ridge).
>
> ### Live hazard for whoever picks this up
>
> **`origin/main` and the owner's local `main` have diverged.** As of 2026-09-05 origin is at
> `122bf4b` while the owner's machine carried unpushed work — an RNG-reuse change in
> `biome_director.gd`, a void-expiry HUD fix in `powerup_manager.gd`, and lake docs. The aurora's
> dark-window rule reads `biome_director.gd`. **Run
> `git rev-list --left-right --count origin/main...main` before trusting any reading of it** —
> this page has gone stale on exactly that claim three times.

**The working tree is clean and `./scripts/check.sh` passes all five gates in 25s** (verified
2026-09-02). Everything below is a loose end, not a break.

**The 2026-08-24 review list is finished except #7.** Two items were killed on evidence rather
than done (#9, #8 — see below), and the last cheap one is built. What is left on it is #7,
segment caches never being pruned, which carries a read-this-first warning.

**The 2026-09-02 audit is worked through: #1–#10 closed on 2026-09-03**, #11–#14 deliberately
left (see the status block at the top of `docs/review/2026-09-02-audit.md`). It found one real
shipped defect — both coin spawners placing 192px too high — and the gate gap that hid it.

> ## ✅ FINISH THIS FIRST — what is actually left
>
> Nothing here is broken; `check.sh` is green. Two of the four loose ends from the 2026-08-27
> visual session are **done** and are recorded that way so nobody redoes them:
>
> - ~~1. `debug_biome_seconds` left at `10.0` in the working tree~~ — **DONE.** It is back at
>   `0.0`, the tree is clean, and `shipping_values_check` passes.
> - ~~4. The open night-length decision (A/B/C)~~ — **DONE, option A shipped** in `e3beb3a`.
>   Night is 2/8 of the arc. See "CLOSED decision — how much night", below, which is kept for
>   its reasoning and its disc rule, not as an open item.
>
> **What remains, in order:**
>
> 1. ~~**`sky_layer_check.gd` is OWED**~~ — **SETTLED 2026-09-02 by the owner in-game.** They
>    played the arc and called the visuals good: night reads as night, the two night biomes stay
>    distinct, the emerald ice is green at depth, the moon is a clean full disc on the right, and
>    the silhouettes followed the sky down. **That is the project's accepted verification for
>    visuals** — the owner judges in-game faster than any capture, and the gate's own doc says the
>    owner judges the final look. Re-run the gate only if a sky/palette change lands that the
>    owner has *not* seen. The original entry, and what to suspect if it ever goes red, follows.
>
>    It is a gate
>    (exits non-zero), it **must run without `--headless`** (`debugging.md`), and it has not run
>    since 2026-08-26. Five commits landed after that run — `glacier_teal`'s emerald ice, three
>    moon fixes, and `twilight_blue`'s night rewrite — and **every headless gate is blind to
>    biome code**, because `BiomeDirector` returns early under `--headless`. `check.sh` being
>    green says nothing here.
>
>    ```
>    /Applications/Godot.app/Contents/MacOS/Godot --path . --script res://scripts/debug/sky_layer_check.gd
>    ```
>
>    **What to suspect if it fails:** `twilight_blue` walked straight at this gate's documented
>    failure mode. Option A turned the glow into *cool moonlight* and darkened the sky it sits
>    on, in the same commit. If those two colours converged, the glow now contributes under
>    24/255 and is invisible — which is exactly the defect (11/255) this gate was built for.
>
> 2. **`ice_look_capture.gd` and `biome_contact_sheet.gd` are NOT owed in the same sense.**
>    Neither asserts anything; both just save PNGs for a human to look at. The owner judges the
>    final look in-game and has `debug_biome_seconds` for the whole-cycle view, which does the
>    contact sheet's job better. Run them to catch gross breakage before handing over a visual
>    change — not as a gate.
>
> 3. **Nothing is unpushed** as of 2026-09-03 — `origin/main` and `main` are level at `07b9060`.
>    **Never trust this line; run `git rev-list --left-right --count origin/main...main`.** It has
>    gone stale three times now, because it is the one claim here that a fresh session acts on
>    immediately and the one that expires the moment anybody pushes.
>
> After those, the project is genuinely clean. The next real feature is the aurora, which needs
> a planning pass before any code — see "Still in view".

> ## ⏸ THE PLAYTEST IS STILL RUNNING — owner-reported findings outrank everything
>
> The owner is working through the game hands-on and reporting what looks wrong, usually with
> screenshots. **Four visual findings came in on 2026-08-27 and are fixed** (see the session
> section below); more are expected. When findings arrive, work those before anything in the
> "next three things" list — that is review debt, this is observed-broken behaviour.
>
> **What that session taught, and it held every time:** these read as taste complaints and were
> all *measurable causes*. Sample the colours, profile the texture, print the radial falloff —
> do not tune by eye. Twice the obvious reading of the symptom was wrong ("the green looks bad"
> was **not** a hue problem; the disc under the moon was **not** the sky). Twice the first fix
> had to be redone as a result.
>
> **Do not** start the aurora, re-open the review list, or kick off a long gate run mid-playtest.
> **Do** ask which items are reproducible if it isn't stated — `FREEZE_REPRO` in `debugging.md`
> is the standing rule for anything that smells like a stall.

**After the playtest and the cleanup above — next three things:**

1. ~~Godot 4.7.2 (review #9)~~ — **DECLINED 2026-08-26**, see below. Don't re-raise it.
2. **#8, `main.gd` process priorities** — **downgraded 2026-08-26**, it is close to a no-op.
   Read the finding below before spending the physics gate suite on it.
3. **The aurora borealis** — the game's namesake. **Not ready to code**: its own doc's
   "Sequencing" section says plan it fully first, and three open questions are undecided.
   The next step there is a *planning pass producing a doc*, not an implementation step.

**Two live hazards, both cost a session if you don't know them:**

- **An engine run can silently rewrite `project.godot` AND scene files**, dropping authored
  values and every comment. **Corrected 2026-08-26:** it is *not* caused by `--editor` or the
  APK exports (both measured byte-clean) — the trigger is a project-setting **save**. As of
  2026-08-27 `shipping_values_check` text-scans `project.godot`, so a dropped pin goes red;
  **scene files still have no such cover**, so run **`git status`** after any engine run and
  revert what you did not change on purpose. Full table: `docs/development/debugging.md`,
  "Engine commands that rewrite `project.godot`".
- **`./aura.apk` at the repo root is from 2026-08-03** — three weeks and ~20 commits stale, kept
  only because it is gitignored. `debugging.md`'s Android instructions say to re-export before
  installing; do that rather than trusting the file sitting there.

**Working agreement, in force:** one numbered sub-step at a time, commit it alone, stop and wait
for an explicit "go". Flag anything with real bug potential, or with a much cheaper alternative,
before building it. Don't self-verify visuals with screenshots — the owner checks in-game faster.

---

The sections below run newest first. The older ones are all background work, which is **parked
in a shippable state, not finished** — read "Where things actually stand" before touching it.

## Last session — 2026-09-03: the audit's one real bug, and the gate shape that missed it

Six commits, working through the 2026-09-02 audit end to end. `check.sh` green at every step.

**The headline: rare coins and glide coins have been placed 192px too high since each file's
first commit.** `get_terrain_height()` returns an offset *from* `ground_y`, not a
TerrainGenerator-local y, and both spawners left the `ground_y` term out — while their own header
comments argued at length that it was unnecessary. The rare coin's whole reason to exist is that
its 174px clearance sits in the ~24px gap between the top two jump levels; it was actually at
366px, out of reach at every level, powerup included. The glide field's "skims the surface" 60px
floor was really 252px.

**Verified by measurement, not by reading.** A throwaway probe instantiated `main.tscn`, called
each spawner's own placement function and compared against `get_surface_world_y()` — 366.0 and
322.0 before, 174.0 and 130.0 after. The owner had believed this was already fixed in an earlier
session; it was not, and reflog/all-branches/stash confirmed no such fix ever existed. **Measure
before trusting a "we already did that", including your own.**

**Why nothing caught it, which is the more useful half.** Every item-height check in
`terrain_invariant_check` asserts a relationship *between constants* — and a constant stays
perfectly correct while the code consuming it puts the object somewhere else. `check_rare_coin_height()`
passed the entire time, because 174 was still 174. `check_spawn_placement()` is the fix: it
instantiates the scene, calls all six spawners' real placement functions, and measures the node
that actually appeared. Mutation-tested both ways.

**The glide field is owner-verified in play and needs no retune.** Its vertical *spread* was not
touched — only the anchor moved — so `TRAIL_CLEARANCE_MIN/MAX` still describe the same 1840px
band, and the owner confirmed on 2026-09-03 that the field reads correctly 192px lower. The
original eyeball-tuning happened at the wrong offset and turned out to survive the correction.
**Nothing from the audit is left open except #11–#14, which were deferred on purpose.**

Also closed: seven unwatched debug knobs added to `shipping_values_check` (40 now, was 33),
including one whose "derives from `is_debug_build()`" comment was false and which therefore
shipped whatever it held; `mist_strength` deleted after confirming no fog layer exists anywhere;
the abandoned `experiments/` background line deleted (3.8MB); a dead remote branch deleted; and
five pieces of documentation that were not stale but *wrong* — most notably `build_pano_strip.py`
calibrating from a `depth_t` the layer has never had.

**`CLAUDE.md` is back at exactly 175**, its own cap, after a compression pass. No trap was
removed to get there — the 12 lines came out of wrapping and one duplicated sentence in the
footer, and every constant, file name and rule was checked as still present afterwards.

## Earlier — 2026-08-28: night got longer, and the review knob learned to survive death

Two commits, both data or one script. No gameplay, physics, terrain or collision file touched.

- **`e3beb3a` — `twilight_blue` deepened into a real night.** This is option A of the open
  decision below, which is now closed. Night went from 1/8 of the day arc to 2/8. Full values
  and reasoning are in that section.
- **`10aeb66` — `BiomeDirector`'s review knob now resumes after a death**, the way the real
  session phase already did. Reviewing palettes with `debug_biome_seconds` used to restart the
  colour clock on every death, which made the fast-forward useless for exactly the long
  eyeballing sessions it exists for.

**Nothing visual has been verified since.** `sky_layer_check` last ran 2026-08-26, before both
of these and before the four commits of the 08-27 pass. See the top of this file.

---

## Earlier — 2026-08-27 visual pass: the green, the moon, the night sky

Seven commits, all data or one script, **no gameplay/physics/terrain/collision file touched**.
Driven by the owner playtesting with `debug_biome_seconds` and screenshotting what looked wrong.
The pattern worth carrying: **every one of these was a measurable cause, not a matter of taste**,
and in two cases the first fix was wrong because the symptom was misread.

### `glacier_teal`'s ice — "ugly green" → emerald (`65628dc`, `4855eb8`, `c5bcfe0`)

Three commits because the first two misread the request. **The owner wants it GREEN** — there is
already plenty of blue in the arc — just a better green. `65628dc` turned it cyan and was wrong.

**The murk was never the hue, it was red.** The original depth colour `(0.44, 0.87, 0.78)` had a
fine green-teal hue but `r/g = 0.51`, and red that high desaturates a green toward olive. Deep
ice is capped at `ice_depth × 0.38` (`ICE_TILE_DEPTH_FLOOR`) and that multiply **preserves the
ratio**, so the bottom of every hill rendered `(0.17, 0.33, 0.30)` at saturation 0.33 — mud. No
hue change fixes that while r stays up.

Final values came from **sampling the owner's National Geographic emerald-iceberg reference**,
not from taste. Masking to genuinely green pixels needs `g` above **both** `r` and `b` — a first
pass matching only `g > r` returned hue 193–204, which was the blue sky. Three candidates
measured; took the hero berg's jade-emerald at ~145°.

**Saturation is pushed well past the photograph on purpose.** Photos of ice carry atmospheric
light (all three references sit at r/g 0.6–0.8, saturation 0.15–0.35); reproducing that
faithfully reproduces the mud, because of the ×0.38 floor. Match the hue, roughly double the
saturation.

| | original | now |
|---|---|---|
| `ice_surface` | 0.72, 0.98, 0.91 — hue 164, sat 0.87 | **0.54, 0.93, 0.70** — hue 145 |
| `ice_depth` | 0.44, 0.87, 0.78 — r/g 0.51 | **0.14, 0.72, 0.34** — hue 141, r/g 0.19 |
| at ×0.38 floor | 0.17, 0.33, 0.30 — **sat 0.33** | 0.05, 0.27, 0.13 — **sat 0.67** |

**Both ends now sit at 141–145°**, so the band stays green top to bottom and the variation comes
from luminance (0.83 → 0.57) and saturation. Earlier attempts left the depth at 166° — teal — so
it read green at the crest and teal in the troughs, which is what kept looking wrong.
`ice_hue_variance` 0.13 → 0.17. If it needs to go greener, **push the hue toward 135, not the
saturation** — there is little headroom left before `MIN_GAMEPLAY_CONTRAST` starts fighting.

### The moon — three separate bugs (`6933860`, `f11db01`, `4508d90`)

1. **It rendered as an eclipse.** `MOON_CUT_RADIUS` was 0.36, the same as the lit core, offset by
   only `|(0.16, −0.05)| = 0.17`. Since 0.17 < 0.36 the cut **contained the disc's centre**, so
   the middle was multiplied to the 6% residual and only the rim stayed bright.
2. **Replaced with authored art** from `art_source/background/moons.png`, panel 6 of 8. The
   procedural builder is deleted — which also closed a real perf item, the 65,536-iteration
   `build_moon_texture()` loop paid on every scene load (both review docs updated).
3. **A grey disc appeared under it.** I had baked the art's halo in by subtracting a sky floor —
   but the source panel's sky brightens toward the horizon, so it left a ~5% white veil to the
   rect edge, cut to zero by a hard clamp at 2.55×. That clamp was the visible arc. Alpha is now
   the disc and nothing else, zero by 1.20×. **`SkyGlow` already draws the bloom** at the moon's
   own position, so a baked one was doubling it.

Full write-up, including the two properties of the PNG that were each got wrong once, is in
`biomes.md`, "The sun / moon disc".

### The night sky order (`a375388`)

The sun's glow arcs correctly left→right across the day. The **moon** was at x 0.30, left,
immediately before `arctic_dawn` glows at 0.16, also left — two lights on the same side, which
read as the sun rising right behind the moon. Moved to **0.62**, so it sets on the right and
leaves the left clear for dawn; rule 1 forces its two neighbours to copy the position.

Also fixed: **the moon was fading in wearing the sun's texture.** `celestial_is_moon` is the one
celestial field that does not interpolate — it snaps at the halfway point while
`celestial_strength` lerps the whole way. Both neighbours are now `is_moon = true` (strength 0,
so nothing renders; the flag only picks the texture the fade uses).

An attempt to make the moon *arc* across two night biomes was **rejected by
`biome_schedule_check`** and reverted — that is option C below.

## CLOSED decision — how much night the day arc should have (option A, `e3beb3a`)

> **DECIDED AND SHIPPED 2026-08-28: option A.** `twilight_blue` was deepened into a real night —
> gradient darkened to roughly a third of the way down to `starlit_night`, horizontal tint
> dropped to white (no warm band), the glow turned into cool moonlight at the moon's own slot,
> `star_density` 0.6 → 0.85, and scenery/haze/tree/bird tints followed the sky down so the
> silhouettes would not read as dusk against a night sky. **Night is now 2/8 of the arc.** The
> two night biomes stay distinct: `twilight_blue` is violet-leaning with no disc,
> `starlit_night` is deeper neutral navy with the moon and full stars.
>
> **B and C were not done and are still available** if night still reads short. C in particular
> is the only fix for *"the moon pops up all of a sudden"* — option A cannot address that.
> **`sky_layer_check` has not run since this shipped** (see the top of this file). The rest of
> this section is kept for its reasoning and, above all, for the disc rule at the end, which
> constrains anything anyone does to the sky next.

Raised by the owner 2026-08-27 while playtesting with `debug_biome_seconds`: *"mostly sun, some
night time, but like 2 night time or 3 isn't really enough."*

Today exactly **one** of the eight palettes is真 night (`starlit_night`, `star_density` 1.0).
`violet_dusk` (0.3) and `twilight_blue` (0.6) are dusk and twilight, not night. So night is 1/8
of the arc, ~1.7 min of a ~13.7 min cycle.

Three ways up, cheapest first:

- **A — deepen `twilight_blue` into a real night.** Darken its sky, push `star_density` 0.6 →
  ~0.85. Night reads as 2/8. **Data only, no new files, no cycle-length change, no doc updates.**
  It cannot get a second moon (see the disc rule below).
- **B — add a 9th palette, `deep_night`, after `starlit_night`.** Night becomes 3/9 and the arc
  keeps its order. Costs: one new `.tres`, a `BIOME_CYCLE` entry, and the cycle grows 8 × 75 000
  → 9 × 75 000 px (13.7 → 15.4 min). **"Eight" is written into `CLAUDE.md`, `biomes.md` and the
  build-order table** and would all need updating. `biome_schedule_check` prints `palettes=N` and
  should pass unchanged.
- **C — give `SkyCelestial` the two-node cross-dissolve `IceBand` already has.** This is the only
  thing that unlocks **the moon arcing across the night** (rising left, setting right) instead of
  sitting in one slot, and it is the real fix for *"the moon pops up all of a sudden"*. Real code
  in `sky_backdrop.gd` plus relaxing one `biome_schedule_check` rule. Medium risk, and it touches
  the one visual system whose gates need a window.

**The disc rule, which shapes all three** — `biome_schedule_check` enforces two things that are
not obvious from the palettes, and it caught an attempt to break both:

1. **No two adjacent biomes may both have a disc**, because `celestial_is_moon` snaps at the
   transition midpoint while `celestial_strength` lerps — so the texture would swap mid-fade.
2. **A disc-less biome must copy its disc-having neighbour's `celestial_position`**, or the disc
   slides across the sky as it fades. *This is why every palette shares one of two positions* —
   it is not redundancy, it is the rule.

A and B are compatible; C subsumes the moon half of both. **Recommendation was: A now** (minutes,
zero structural cost), then C only if the pop-in still reads wrong once night is longer. **A was
taken.** C remains the open follow-up, gated on whether the pop-in still reads wrong.

**The moon image arrived and is in** — `art_source/background/moons.png`, eight variants; panel
6 ("FULL MOON") is the one wired up. The other seven are still there if the crescent is ever
wanted: swapping is a one-line change to `MOON_TEXTURE`, though a crescent needs a larger
`celestial_size` to stay legible at this scale, and the extraction has two traps in it — see
`biomes.md`, "The sun / moon disc".

## Last sessions — 2026-08-26 → 27: two review items killed, one gate hardened

Two commits, `f7e500d` (docs) and `9c91c42` (the gate), both since pushed. Nothing outside
`scripts/debug/shipping_values_check.gd` and docs was touched — no gameplay, physics, terrain,
scene or shader file — so nothing here needs a gate suite to trust. `check.sh` green throughout,
5/5 in 25s, unchanged timing.

The through-line of both: **three standing claims turned out to be wrong when measured**, and
each had been costing something. Details below, but the pattern is worth carrying — this project
documents its traps well enough that the docs themselves become the thing nobody re-checks.

### #9 (Godot 4.7.2) — DECLINED, don't re-raise

4.7.2 is real and safe (released 2026-08-18, 57 fixes, "no known incompatibilities"), and so is
4.7.1 before it (78 fixes). We are on `4.7.stable`. It was still declined, on the evidence:

- **Nothing in either release touches this project.** 4.7.2 is Linux IME under KDE, Windows
  high-polling-rate mice, editor UI, PCSS **3D** shadows, 3D nav debug, **multiplayer**
  replication, mbedTLS. 4.7.1's nearest miss is an Android soft-keyboard backspace fix — Aura
  has no text input. Aura is single-player, 2D, no networking, no 3D. Zero relevant fixes.
- **The upgrade changes no file in the repo.** `config/features` stays
  `PackedStringArray("4.7", "Mobile")` across the whole 4.7.x line, so there is no "isolated
  commit" to make — the entire task is reinstalling the editor and templates, then re-running
  the fast five, chasm, lake, the three windowed visual gates and a device build.
- That is an hour-plus of the owner's time for fixes aimed at KDE and multiplayer.

**Revisit when** something actually breaks and 4.7.x is a suspect, or when 4.8 ships something
wanted. Do **not** move to the 4.8 development line.

### #8 (`main.gd` process priorities) — DOWNGRADED, the review's premise doesn't hold

The review says a *"scene reorder that looks cosmetic changes rebase and camera timing."*
Checked against `main.tscn`: **`Player` and `TerrainGenerator` are children of `Main`, not
siblings of it** (`parent="."`, and `Main` is the root). A parent's `_physics_process` always
runs before its children's, verified in-engine on 4.7.stable:

```
DEFAULT (all priorities 0): ["Main(parent)", "Player(child)", "TerrainGen(child)"]
```

So the ordering `apply_world_rebase()` depends on (`main.gd:219`) is **structural**. Reordering
`Main`'s children among themselves cannot break `Main`-before-both, which is the failure the
review was worried about. What is left is a one-line `process_priority` that documents intent
and provably changes nothing — **not** a behaviour change deserving the full physics gate suite.
Do it as a comment or a no-op pin if you like, cheaply; don't schedule gates for it.

### The `project.godot` "stripping" hazard was over-stated — corrected in the docs

The standing warning said `--editor` and both APK exports rewrite `project.godot`. **Measured on
a throwaway copy: they don't.** A cold import with `.godot/` deleted, and a full signed
`--export-debug` APK, both left `project.godot` byte-identical and touched no tracked file.

The real trigger is **a project-setting save** — which is consistent with both incidents, since
both happened while the icon/bundle id were being edited. The mechanism is documented Godot
behaviour: a setting equal to its engine default is never written, and all four pinned keys are
pinned *at* their defaults. Full write-up, with the reproduction, in `debugging.md`, "Engine
commands that rewrite `project.godot`". `CLAUDE.md`'s bullet was corrected to match.

**This makes the danger sharper, not smaller:** the four pins are invisible in the file and
`shipping_values_check` read them back identically, so if an engine default ever moved, level
geometry would change silently.

### The text-scan hardening is BUILT — 2026-08-27, review #9's last loose end

`shipping_values_check` now has a second half, `check_project_godot_declares_pins()`: it scans
`project.godot` as text and fails if any of the eight pinned keys is missing. The two halves are
complementary and the file says so — the runtime read catches a value that *drifted*, the text
scan catches a pin that *vanished*, and neither can see the other's failure.

**The reason it went unbuilt for months was a wrong premise**, which this file used to carry:
that the editor strips those keys on every open, so a text scan would cry wolf and get disabled.
It doesn't (see above), so the scan sits quiet through ordinary work.

Mutation-tested: deleting the four default-equal pins made **the runtime half still pass on all
four** — exactly the hole — while the text scan caught all four and exited 1. `--allow-temp`
still downgrades to a warning and exits 0. `check.sh` green, 5/5 in 25s, no timing change.

## Earlier — 2026-08-25, shipping hygiene: review items #6 and #10 are closed

Four commits, all pushed (`bfad804`, `1be85a0`, `4604b08`, `bd27aa8`). `origin/main` is level.
Nothing here touched physics, collision, spawning, terrain or `main.tscn`.

- **`./scripts/check.sh` exists — one command, ~25s, the before-every-commit tier.** It runs
  `shipping_values_check`, `biome_schedule_check`, `terrain_invariant_check` (`--seeds=8
  --to=300000`, hardcoded so nobody shortens it into a meaningless FAIL), `lake_suppression_probe`,
  and an export-content check. It runs **all five even after one fails**. Mutation-tested by
  flipping `debug_chasm_disabled`: two gates caught it, exit 1.
- **Project import is deliberately NOT in the runner**, against the letter of review #10. Import is
  `--headless --editor --quit`; an `--editor` run strips the pinned physics settings out of
  `project.godot`, and terrain constants derive from `physics_ticks_per_second`. A validation script
  that silently changes level geometry is worse than none. `--export-pack` was checked and does
  *not* rewrite it, which is the only reason the export check can live in a runner.
- **The export-content check verifies `exclude_filter` actually does something** — it had been in
  `export_presets.cfg` since 2026-08-24 with nothing watching it. Its forbidden list is hardcoded
  rather than read from the preset, on purpose: deriving it would make the check agree with the
  preset by construction, including when someone deletes a line from it. Mutation-tested by
  blanking `exclude_filter` — 3 of 4 paths appeared, run went red.
- **`CLAUDE.md` trimmed 201 → 179 lines**, back under its own ~175 cap. Every trap and number
  survives; four cuts removed text duplicated one level down and still linked from here.
- **The release preset is real now**: `com.kiernan.aura`, `"Aura"`, `0.1.0` / code 1, launcher
  icons cut from `art_source/aura.png` (a 3×3 sheet of nine candidates — the owner picked row 1
  col 2, the aurora). Debug keystore left alone; nothing is being published yet.

### Deferred, and fine to leave: the themed icon is the Godot robot

`launcher_icons/adaptive_monochrome_432x432` is empty, and **an empty path does not mean "no
layer"** — Godot substitutes the project icon. So on Android 13+ with themed icons enabled the
launcher shows 23,679 opaque pixels of Godot logo. Confirmed by unzipping a built APK, which is
the only way to see it.

**Explicitly deferred by the owner on 2026-08-25 — worry about it later.** It is not urgent:
nothing is being published, and it only appears in themed-icon mode. Deriving a silhouette from
the aurora tile was tried at six thresholds and produces unreadable mush — a photographic scene
has no single-colour reduction — so the fix is a **simple drawn mark** (peaks plus an arc, or
similar), which is a design decision, not a build step. Pick the mark, save it 432×432 on
transparency, point the preset at it, re-export and unzip to confirm.

The same trap already bit the *foreground* layer and is handled there: it points at a
deliberately fully-transparent PNG, because a blank path would have put the Godot logo on top of
the aurora. Don't "clean up" that empty-looking file. Full detail: `docs/development/visuals.md`,
"The app icon".

### Next, in order

**Superseded 2026-08-26 — read the top of this file first.** The owner's playtest list outranks
all of it, and the first two items are closed:

1. ~~**#9, Godot 4.7.2**~~ — **DECLINED**, reasons in the 2026-08-26 section. Don't re-raise.
2. ~~**#8, `main.gd`'s process priorities**~~ — **DOWNGRADED**; the review's premise doesn't
   hold (`Player`/`TerrainGenerator` are children of `Main`, so the ordering is structural).
   No gate suite required.
3. **The aurora borealis** — the next real feature, `docs/development/aurora_borealis.md`.
   **Planning pass first, not code**: three open questions are undecided (forced flat segment
   or not; procedural shader vs. authored sprites — and a third `.gdshader` needs real
   justification, the budget is exactly two and both are owned by ice; fixed palette vs.
   biome-reactive). Its doc also names a prerequisite — "ice canyon walls / shard spires, extra
   sky elements" — which looks **stale**: the background shipped 2026-08-24 as the baked raster
   panorama and the iceberg-sprite plan was abandoned. **Confirm with the owner** whether that
   background work is done-enough before planning the ribbons against the current sky stack.

~~Unbuilt and cheap, good filler: the `shipping_values_check` text-scan of `project.godot`~~ —
**built 2026-08-27**, see the section above. The review list has nothing cheap left on it.

Also still open from the review, not urgent: #7 (segment caches are never pruned — **read the
warning there before touching it**, `arm_lake()`'s write-ahead rule and deterministic replay both
depend on cached history staying available).

### The three visual gates are no longer owed — run 2026-08-26, all clean

They had been outstanding since the background commit that moved `source_skyline_y` 242 → 302.
Run with a window, as they must be; `project.godot` verified clean after each.

- **`sky_layer_check` PASS** — 9 biomes, 45 layers measured, every claimed layer above the
  24/255 floor. Tightest: `first_light` ice contrast at 13 against its own 10/255 floor.
- **`biome_contact_sheet`** — all eight render distinctly and the day arc reads in order.
- **`ice_look_capture`** — three frames, no funnel warp and no wash-out (the two failures this
  capture exists to catch). The widened panorama parallaxes correctly: different silhouettes at
  `player_x` 271 / 1645 / 7048, with the arch arriving only in the last. **No regression from
  the `source_skyline_y` change.**

**Two contact-sheet rows print an empty biome name, and that is not a bug.** `resolve_variant()`
returns `base.make_variant()`, a duplicated *in-memory* resource with no `resource_path`, and the
sheet labels rows from `palette.resource_path`. A blank label means "a rare variant rolled for
this session's salt" — rows 4 and 5 were `sunset_rose` (`variant_chance` 0.5) and `violet_dusk`
(0.2), the two most likely to roll. Only those two and `glacier_teal` have a variant at all.
Labelling them `<base> (variant)` is a one-line change in the debug script, not made.

### Read before you run any Godot command: the `project.godot` strip is wider than documented

**`--export-debug` and `--export-release` strip `project.godot`, not just `--editor`.** It
happened during this session's icon verification: `viewport_width`/`viewport_height`,
`physics_ticks_per_second`, `physics_interpolation` and every explanatory comment in the file were
deleted. Caught by `git status` and reverted; nothing shipped, and the tree is clean.

**`shipping_values_check` does NOT catch this — measured, it PASSES on the stripped file.** The
gate reads `ProjectSettings` at runtime, and the stripped keys fall back to engine defaults that
currently *equal* the pinned values. Nothing looks wrong until an engine default moves, which is
exactly what item 1 above could cause. `--export-pack` is safe and is the only export form
`check.sh` uses.

So: **`git diff project.godot` after any editor or export run**, and treat a clean `check.sh` as
no evidence at all on this one point. The cheap hardening — text-scan `project.godot` for the
pinned keys, the way the gate already text-scans `main.tscn` and for the same stated reason — is
written up in the review under #9 and **not built**.

## Older session — 2026-08-25, the three open background decisions are closed

All three of the "Open decisions" below were resolved in one pass, one commit each. **Read
each item's own status line rather than this summary** — they carry the numbers.

- **#2, the panorama repeat: measured, closed.** 106.1 s at `MAX_SPEED`, up from 54.6 s; 29%
  of the strip on screen at once, down from 56%. The loop is now 1.06 biome cycles, so a repeat
  cannot land inside one biome.
- **#1, parallax depth: decided, keeping 3.3:1.** No scene change. The two items are coupled —
  restoring 10:1 by raising `IceStrip` would have cut the loop to 35.4 s, worse than the defect
  #2 started as.
- **#3, the gate's blind spot: fixed.** `biome_schedule_check` reads the scene's real `depth_t`
  now. No palette data changed.

**Nothing in this pass touched physics, collision, spawning, or `main.tscn`.** The only code
change is inside a debug gate. `shipping_values_check` and `biome_schedule_check` both PASS;
the three windowed visual gates were **not** run and did not need to be, since no rendered
value moved — but they are still owed from the 2026-08-25 background commit below, which did
move one (`source_skyline_y` 242 → 302).

Next, per `docs/review/2026-08-24-code-and-repo-review.md`'s "Suggested order": the release
preset + export-content check and the one fast validation runner (#6 and #10, same exclude
list, do them together), then Godot 4.7.2 (#9), then `main.gd`'s process priorities (#8). The
**aurora borealis** is the next real feature and the background is no longer in its way.

Rewritten 2026-08-24. The previous version described the panorama as an unwired experiment
and was written around `PineLine`; both had been false for eight commits, and it was sending
sessions back toward finished work. The investigation history it carried now lives in
`docs/research/background_differentiation.md` — read that only if you need to know what was
already ruled out.

**Working agreement, still in force:** one numbered sub-step at a time, commit it alone, stop
and wait for an explicit "go." Flag anything with real bug potential, or with a much cheaper
alternative, before building it. Don't self-verify visuals with screenshots — the owner checks
in-game faster.

## Older session — 2026-08-25, background called done for now

**Background is being parked here, not finished.** It's in a shippable, decent-looking state;
the three open decisions from 2026-08-24 (below) are still open, and nothing here should read
as "resolved" without checking that section first.

What changed:

- **The panorama source is wider.** `art_source/background/pano.png` (5220px) supersedes
  `arch_spike_massif.png` (3548px) as `build_pano_strip.py`'s input — a fourth panel
  (`sharp.png`) was hand-stitched onto the existing art in GIMP, aligned and seam-blended by
  eye. This is a step toward open item #2 below (the panorama repeating every ~55s), since a
  wider strip takes longer to loop at the same `motion_scale` — **but the new cycle time was
  not re-measured against `MAX_SPEED`.** Do that before calling #2 closed.
- **Two smudge-tool artifacts were removed from the source.** GIMP editing left faint circular
  blotches in the empty-sky band (~y<280 of 887), invisible until a biome multiplied the layer,
  much like the "faint rectangles" failure mode `build_pano_strip.py`'s docstring already warns
  about — same symptom, different cause. Patched programmatically (soft inpaint from a blurred
  fill, not hand-painted) rather than by hand in GIMP; see the diff on `pano.png` if the method
  needs to be repeated.
- **`ice_pano.png` rebaked**, and `main.tscn`'s `IceStrip.source_skyline_y` updated 242 → 302
  to match — the blotches had been faint enough to misread as sparse "ice" by the build's sky
  model, so removing them changed where it thinks the real skyline starts. **This value moves
  whenever the art above the skyline changes; re-run the build and re-check it, don't assume
  it's stable.**
- `art_source/background/mountains.png` (an unused spare) deleted; `sharp.png`, `pano2.png`,
  `next.png` added as reference/working material. Detail on all of it in `art_source/README.md`.
- The lake reflection mirroring the now-distant mountains 1:1 was raised and deliberately left
  alone — `reflection_compression` is a documented, already-fought-over knob (see the shader's
  own comment), and the "too close" read is more an artifact of flat-silhouette art than
  something the shader should be pulled on for polish. Revisit only with a real complaint.

Gates run before this commit: `shipping_values_check`, `biome_schedule_check` — both PASS.
**Not run:** freeze-search, floor-flicker, chasm, camera-shake, `lake_suppression_probe`, or the
three windowed visual gates. Nothing here touches physics, collision, or spawning, but the
visual three (`sky_layer_check`, `ice_look_capture`, `biome_contact_sheet`) are the ones that
would actually catch a regression from the skyline_y change or the new source width — run them
before trusting this further, especially before touching background again.

## Older session — 2026-08-24, organization pass

Not background work. A cleanup pass against the two same-day reviews, then everything was
pushed: `origin/main` had been 16 commits behind and now has all of it.

- The two reviews were folded into one, `docs/review/2026-08-24-code-and-repo-review.md`.
  It is the single source for what is still open; **read its "Suggested order" before
  starting anything organizational.**
- **One real bug fixed:** pausing inflated cumulative playtime, so the frozen lake could
  arrive in a single run. `GameManager.get_unbanked_seconds()` now owns that arithmetic, and
  the planned aurora should reuse it rather than reading `Main.elapsed_time`.
- `art_source/` split into `terrain/` and `background/` (recorded as renames), and the
  panorama's source is tracked now — it was untracked and unbacked.
- Debug and experiment material no longer ships: `export_presets.cfg` has an
  `exclude_filter`. The rest of the release preset is still not release-shaped.
- `build_iceberg_sprites.py` deleted (dead), plus a sweep of `PineLine` and pre-split
  `art_source/` paths through the docs and tool headers.

Gates run: `shipping_values_check`, `biome_schedule_check`, `lake_suppression_probe` — all
PASS. **Not run:** freeze-search, floor-flicker, and the three windowed visual gates. Nothing
touched physics or rendering, but the visual three are the ones that would catch a background
regression if you want certainty before editing.

Still open, cheapest first: the release preset proper (#6), one fast validation runner (#10),
Godot 4.7.2 (#9), process priorities on `main.gd` (#8), and making `biome_schedule_check` read
the scene's real `depth_t` (#5).

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
`art_source/background/pano.png` (as of 2026-08-25; previously `arch_spike_massif.png`) by
`scripts/tools/build_pano_strip.py`. The rebuild is deterministic on a given source — that was
verified byte-identical for `arch_spike_massif.png` during the 2026-08-24 review, not
re-verified for `pano.png` yet. The `.xcf` working files are in `art_source/background/`.

The raster-vs-biome-tint question that killed the three earlier raster attempts was answered:
greyscale × flat tint reconstructs the reference to within 3–5/255, so a baked panel does
survive the multiply. That measurement is why this attempt shipped where the others did not.

## Open decisions — the owner's call, not a cleanup

Three findings from the 2026-08-24 review are background numbers, held back from the hygiene
commits so they could land with the visual pass instead. Full detail in
`docs/review/2026-08-24-code-and-repo-review.md`, items #3, #4 and #5. **Each states its own
status below — read that before acting on it, not this heading.**

1. **Parallax depth — DECIDED 2026-08-25, keeping the current 3.3:1.** Near-to-far had gone
   from 10:1 (`0.30 … 0.03`) to 3.3:1 (`0.05 … 0.015`) when the panorama landed, and whether
   that was a re-tune or drift across eight commits was not recoverable from the commits. The
   owner's call is to keep it. **No change to `main.tscn`; the four numbers stand.**

   **Do not "restore" the old ratio later without reading this, because #1 and #2 are coupled
   and the obvious fix is the bad one.** `motion_mirroring` is fixed in *layer* px, so the loop
   distance is `mirror ÷ motion_scale` — raising the front layer to get separation shortens
   the loop in direct proportion:

   | front `motion_scale` | ratio | loop @ `MAX_SPEED` |
   |---|---|---|
   | 0.05 (now) | 3.3:1 | **106.1 s** |
   | 0.15 (10:1 by raising the front) | 10:1 | **35.4 s** |

   That is worse than the 54.6 s that made #2 a defect in the first place. Restoring 10:1 by
   raising `IceStrip` would spend the entire widen and then some.

   **If the flatness is ever actually complained about, lower the back layers instead** — it
   preserves the old spread's shape and costs nothing in loop period, because the front layer
   never moves: `0.05 / 0.0233 / 0.0100 / 0.0050` (front → back). Untested, and the far layers
   would be very nearly static, which may read worse than the flatness does. Not doing it on
   spec.
2. **The panorama's repeat — CLOSED 2026-08-25, measured.** It was ~55 s at `MAX_SPEED`
   (40,956 world px) with 56% of the strip on screen at once. After the widen it is **106.1 s
   / 79,590 world px, 29% on screen**:

   | | 2026-08-24 | now |
   |---|---|---|
   | source | 3548×887 | 5220×887 |
   | `source_skyline_y` | 242 | 302 |
   | `display_scale` | 0.577 | 0.762 |
   | `motion_mirroring.x` | 2048 layer px | 3979 layer px |
   | loop | 40,956 world px / 54.6 s | **79,590 world px / 106.1 s** |
   | on screen at once | 56% (70% on a 1440 phone) | **29% (36%)** |

   **Nearly 2×, not the ~47% the wider source alone would buy, and the reason is worth
   keeping**: `display_scale` is `(horizon_y_fraction − skyline_y_fraction) · viewport_height
   ÷ (source_horizon_y − source_skyline_y)`, so moving `source_skyline_y` 242 → 302 shrank the
   source span 247 → 187 and scaled the whole strip up 32%. 1.47 × 1.32 = 1.94. **Anything that
   moves `source_skyline_y` moves the loop period too** — the two are not independent knobs.

   The useful comparison is the biome cycle, 75,000 px: the loop was 0.55 of one and is now
   **1.06**, so a repeat can no longer land inside the same biome. Calling that enough.

   One consequence checked while measuring, since it is the failure mode
   `background_strip.gd`'s header warns about: at `display_scale` 0.762 the strip is 676 px
   tall on a 648 px viewport and now **covers the full screen height**, where at 0.577 it
   spanned y 74–586 and structurally could not reach the celestial discs at y-fraction
   0.08–0.09. Measured on the baked texture: the keyed sky band above the skyline has **mean
   alpha 0.05–0.45 / 255** (max 62 in isolated pixels). It does not occlude anything. Re-check
   this if the key-out in `build_pano_strip.py` is ever loosened.

   **Do not** add a second offset copy if this ever needs more — `motion_mirroring` is one span
   by construction and a second sprite reintroduces the tear `centered = false` exists to
   prevent. The remaining levers are the same two: raise `motion_scale`, or bake wider still.
3. **`scenery_near` is never rendered — GATE FIXED 2026-08-25, the data left alone.**
   `depth_t` tops out at 0.45, so only the far 45% of every palette's
   `scenery_far → scenery_near` ramp reaches the screen. Nothing was broken
   (`pale_morning` is the tightest at 0.100 against a 0.08 floor) but `biome_schedule_check`
   measured the *authored* endpoints and would have kept passing all the way to collapse.

   The durable half is done: the gate now reads the four layers' `depth_t` out of `main.tscn`
   via `SceneState` and applies the floor at that real range, printing it on the PASS line as
   `scenery_depth=0.00..0.45`. **No palette and no `depth_t` was changed** — the numbers are
   the same, something is finally watching them.

   **What this means for authoring, and it is the part worth remembering:** an authored
   `scenery_far`/`scenery_near` pair is roughly **twice** the separation that lands on screen.
   Widening the palette and spreading the layers' `depth_t` are interchangeable fixes and the
   gate's failure text names both.

## Before trusting this file

Run `./scripts/check.sh` (~25s, five gates). After any silhouette or palette change, also run
the three windowed visual gates (`sky_layer_check`, `ice_look_capture`, `biome_contact_sheet`),
which **must run without `--headless`** and so can never join the runner.

## Still in view

The **aurora borealis** (`docs/development/aurora_borealis.md`, CLAUDE.md build-order #12) is
fully planned, not started, and is the feature the game is named after. Sky-only, purely
cosmetic, rides its own blend ramp like the frozen lake. It was deliberately sequenced *after*
the background settles the composition its ribbons sit against — which, with the panorama
shipped, is closer to true than it was.
