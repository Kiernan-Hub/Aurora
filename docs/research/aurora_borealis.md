> **CLOSED HISTORY, 2026-09-16.** The current Aurora doc is `docs/development/aurora_borealis.md`.
> Everything below is the planning, slice-by-slice and look-pass record as it stood, followed by
> the Aurora entries moved out of `HANDOFF.md`. Much of it is superseded — for example "no forced
> flat segment", "Route A not built" and "compression 3.0" are all no longer true. Read it for the
> reasoning and measurements behind a decision, never as a description of the code.

# Aurora borealis — the plan and the state

## The look pass — 2026-09-13, current source of truth for appearance

Six owner review rounds refined the Aurora's appearance. **None of it touched the lifecycle,
terrain reservation, flight or camera** — `aurora_calm_probe` stayed PASS at 163,746 assertions
throughout, and every `check.sh` was 4/5 on the three declared TEMP knobs alone.

**`art_source/aurora_reference/` holds four owner-generated reference images and is the design
authority for this feature.** Open them before answering a look question. They settled three
separate wrong turns in a single reading, and every one of those had been argued for plausibly
first.

### What the light now does, sky downward

| Consumer | Behaviour |
|---|---|
| Curtains | Three bands, hems at 0.176 / 0.117 / 0.077, heights ~0.62 / 0.58 / 0.54 |
| **Streaks** | One ribbon crosses the view every ~7s for ~1.15s, alternating direction |
| Parallax layers | **Darken** into silhouette; far/near split preserved |
| Haze | Colour shifts slightly green AND alpha rises, 0.38 → 0.59 |
| Wash | Reaches the screen floor, drifts and breathes, ceiling 0.34 |
| **Wisps** | **DISABLED** — concept was wrong, see below |
| Reflection | True 1:1 mirror filling the ice, compression derived per frame |
| Blade glow | Untouched by owner instruction |

### The four things that will be got wrong again without this section

**1. Reflection compression is derived, never constant.** The shader samples
`mirror_uv.y = waterline - depth * compression`, so the mirror runs out of frame to sample at
`depth = waterline / compression`. A constant 3.0 put that at 0.197 — no reflection could exist
below screen y 0.79, giving an empty lower quarter and a squashed mirror from one number. The fill
ceiling is `waterline / (1 - waterline)` (~1.44), but **any value at or below it fills, so the
right choice is the least squashed: 1.0, a true mirror.** At waterline 0.59 a 1:1 mirror still
reaches screen y 0.18 at the bottom of the frame, inside the curtains, so nothing is given up.
It must stay derived because the ice line moves — the camera ramp lifts it 0.55 → 0.59 and
`aspect="expand"` shifts it per device.

**2. Curtain hem and band height are independent, and growth goes UP.** The hem sits at
`AURORA_HEM_BASE` (0.84) of the rect measured from its top. Growing a band downward drags its hem
down with it; doing that put all three hems behind the background haze and ice panorama, which
draw in front of the sky layer. The curtains rendered correctly and were simply occluded. Height
is what matters — `AURORA_RISE` is a fraction of it, so taller bands give the rays 0.36 of the
viewport to climb instead of 0.20. Keep `T + 0.84 * (B - T)` at the hem values above, or
re-measure **with the background present**.

**3. The scenery DARKENS. It does not go green and it does not brighten.** `starlit_night` authors
`scenery_far` (0.38, 0.44, 0.62) against `sky_horizon` (0.46, 0.52, 0.68) — nearly identical, so
the ridges normally melt into the sky. The Aurora adds green light to the **sky layer only**, so
the sky brightens and the ridges do not, and two masses of similar brightness in different hues
meet along a hard polygon edge. That is a seam. Tinting the ridges green put the aurora's hue on
rock; brightening them produced a pale lavender slab that clashed harder. In all four references
the peaks are dark silhouettes against a bright sky: dark-against-bright reads as intentional,
equal-brightness-different-hue reads as a mistake.

**4. The haze is what actually softens the boundary**, and it does it with ALPHA, not colour —
the one deliberate exception to `refresh_haze()`'s own rule. `AURORA_HAZE_ALPHA_GAIN` is the dial
for edge softness independent of every colour decision.

### `AuroraWisps` is disabled, and the reason generalises

Owner: "those wisps r terrible". The problem was the concept. Persistent ribbons hanging at
mid-screen belong to nothing — they never touch the ice, never descend from the curtains, and
neither occlude nor are occluded by anything, so they read as squiggles drawn over the scene.
Tuning them from three static arcs to six undulating ones made it **worse**, because it drew more
attention to the flaw. The node is kept behind `WISPS_ENABLED` because the likely rework is
vertical shafts descending from the curtains to the ice, which would reuse its whole structure.

`AuroraStreaks` is the same material used correctly: a streak is an **event** that appears,
crosses and leaves, so nothing lingers to be scrutinised. It derives entirely from the event clock
(`floor(elapsed / INTERVAL)` plus the remainder), so it holds no state, needs no death cleanup and
is pause-frozen for free, and it is mirrored by `AuroraReflection` at no cost because it draws
ahead of that quad. Its sweep direction **alternates rather than hashing**: the hash was well
distributed over many indices (111/200) but an encounter only plays the first eight, where it gave
seven leftward streaks and one rightward — identically every time, since the indices are fixed.

### Still open

The **wings rework** is blocked on a reference image that was promised and never arrived; it is the
element the owner has been least happy with. **Bloom** remains an unanswered owner question — there
is no `WorldEnvironment` in the project at all, making it the largest remaining lever and the only
one needing a decision, since glow is screen-space over the whole game and the Mobile renderer's
most expensive feature (the director can gate `glow_enabled` to the encounter). Two reference
findings are unbuilt: **brighter ice**, and a reflection that reads as a soft vertical smear of
colour rather than a crisp mirror of shapes. **`sky_layer_check` is owed** on the curtain geometry
and the streaks, and needs a window.

## Owner review and the visual answer — 2026-09-12

The 2026-09-11 owner review rejected the encounter's reach, not its correctness: **"it just reads
as an aurora borealis on top"**. Two screenshots made the cause plain. The sky carried the whole
event while roughly **45% of the frame** — the protected flat — sat as a dead dark slab, and the
midground band between them was unlit. Verdicts were: light must reach the world (**keep the
curtains as-is**), wisps read as plain static lines, wings need a rework against a reference the
owner is supplying, and **the grounded blade glow is right — do not touch it**.

**What the light now lands on, sky downward:**

| Consumer | What it does | Where |
|---|---|---|
| Curtains | Unchanged, by owner instruction | `sky_backdrop.gd` |
| Four parallax layers | Silhouettes lerp toward an aurora green on one slow breath | `background_generator.gd`, `background_strip.gd` |
| Wash | Reaches the screen floor, drifts and breathes | `aurora_wash.gd` |
| Wisps | Six ribbons undulating on two travelling waves | `aurora_wisps.gd` |
| **Reflection** | **The sky mirrored into the ice** | `aurora_reflection.gd` |
| Blade glow | Unchanged, by owner instruction | `aurora_blade_glow.gd` |

**`AuroraReflection` is the centrepiece and it added no shader.** It runs the existing
`shaders/frozen_lake_reflection.gdshader` — already a measured screen-reading mirror with depth
fade, a weighted three-tap blur, a sqrt-perspective ripple and a world-x mapping — because
everything lake-specific about that shader lives in its uniforms. It is a **sibling node, not a
second mode on `lake_reflection.gd`**: that file derives visibility from one director's phase
deliberately, so two call sites cannot disagree about whether the mirror is up. Aurora and Frozen
Lake reserve non-overlapping spans, so only one quad is ever visible and the forced backbuffer
copy is only ever paid once.

**`reflection_compression` 3.0 is the load-bearing number**, against the lake's 1.0. The lake
mirrors 1:1 because it reflects pines standing at its own shore. The Aurora reflects the SKY, at
screen y 0.05–0.25 while the ice line sits near 0.55 — at 1:1 a pixel would have to be at y
0.85–1.05 to catch it, i.e. off the bottom of the frame. **Do not "restore" it to 1.0.**

**It sits BEFORE `AuroraBladeGlow` in tree order**, where `LakeReflection` sits after. The glow is
a halo centred on the real contact point, so its lower half is below the ice line — the one band
this quad paints. Reordering those two siblings eats the glow the owner asked to keep.

**Both background layers compose, never clobber.** `silhouette_color` stays the pure palette value
and `refresh_silhouette()` is the sole writer of `modulate`, so a biome transition landing
mid-encounter recomputes from both inputs — the same rule, and the same reason, as
`TerrainGenerator.refresh_ice_appearance()`.

The wash's ceiling moved 0.11 → 0.15 → 0.34. **The 0.15 pass was measured off a screenshot as
doing nothing visible at all**; it is a back layer at CanvasLayer -45, behind every gameplay
object, so it cannot affect coin or obstacle contrast at any value.

Still open: the wings rework (blocked on the owner's reference image), and owner acceptance of
this pass. The release gate below is unchanged.

## Current implementation, verification, and release gate — 2026-09-11

Aurora is fully implemented on `claude/aurora-reconcile` through `9db1fb9` (pushed to `origin`).
It is a 61-second, once-per-run experience due every 30 minutes of cumulative playtime, gated to
**past 130s into a run** (`MIN_RUN_TIME_SECONDS`, the lake's number), and able to begin only when
the full presentation has enough remaining night (`star_density >= 0.8`). The run-time gate is
about the SPEED RAMP, not pacing: the reserved flat is cut at `MAX_SPEED` while the event ends on a
clock, so a still-accelerating player covers less of it than it was sized for and rides the rest as
dead flat. A preview interval bypasses the gate so review sessions need no second knob.

**A protected flat is always longer than its event, by design.** At cap the reservation is
~59,846px (~80s) against ~45,750px of presentation, so roughly **12 seconds of empty, obstacle-free
flat follows the fade** and ~3s precedes it. `ENTRY_WAIT_DISTANCE` (10,000px) is budget for an
existing movement effect to expire and land before entry; when none is running, that budget
becomes tail.

**The GLIDE sets that floor, not the boost.** `SPEED_BOOST_DURATION` is 3s, but `GLIDE_DURATION`
is 7s and glide leaves `velocity.x = current_speed` untouched — 7 × `MAX_SPEED` is 5,250px, plus
up to ~750px more because `begin_aurora()` also needs `is_on_floor()` and a glide can expire at
altitude. Worst case ~6,000px; the constant is ~1.7× that. A glide powerup can also be collected
*after* the reservation but before the flat (suppression only covers `overlaps_aurora_flat()`),
so refusing to reserve mid-effect would not remove the need for the budget. Sizing this against
the boost alone argues for halving it and is wrong.

A failed entry (night lapsed, conflict) spends the whole reservation with no event at all — rare,
since reserve and entry are ~3s apart and share `is_sky_ready()`, and unfixable after the fact
because the terrain is immutable once armed. Trimming the tail means trimming
`ENTRY_WAIT_DISTANCE`, not shortening a flat that has already been written — and undershooting
fails `has_duration_room()` at entry, which skips the aurora *and* still spends the reservation. A single
`AuroraDirector` clock drives the protected write-ahead flat/recovery and every presentation
consumer: curtains, wash, ice response, camera, blade glow, snow, rear wisps, wings, guided
flight, and ambience. It also owns the completion signal; `AchievementManager` remains the sole
writer of the once-only `under_the_aurora` achievement.

Safety policy is now concrete: the reservation is immutable and ahead of all visible bodies;
existing bodies are never removed; newly spawned obstacles and boost/glide pickups are suppressed
inside the passage; coins and non-movement powerups continue; Aurora and Frozen Lake reserve
non-overlapping spans; and entry fails closed if a real floor contact, full night duration, room,
or conflict is absent. The Player's one 96px crest flight runs from 27–45 seconds, preserves
horizontal speed, rejects buffered jumps during flight/landing, and returns ordinary input after
one real landing.

Verification is green: the complete `aurora_calm_probe.gd` passes 163,746 assertions across
preview and credited encounters; native `sky_layer_check.gd` passes at 1152×648 and 1440×648; and
the 20,000-frame ordinary camera/movement regression passes unchanged. The only shipping-values
differences are deliberate preview values: `debug_biome_seconds = 10.0`,
`debug_aurora_interval_override = 10.0`, and `debug_aurora_ignore_night = true`. Restore them to
`0.0`, `0.0`, and `false`, then run the normal shipping gate before release.

The remaining acceptance work is qualitative: review full motion, camera, flight and ambience on
a real night at normal biome pace; check Android frame pacing, input feel, and speaker/headphone
balance; then make only evidence-led tuning changes. The dated slice and planning records below
are retained as history; this section is the current source of truth.

## Slice 12 — dedicated Aurora ambience implemented

Aurora now owns a quiet 12-second seamless stereo bed generated locally from periodic harmonics
(24kHz PCM, 1.10MiB), avoiding licensing and network dependencies. A dedicated `AuroraAudio` node
uses one long-form player on the existing Music bus; it never occupies the six-voice one-shot SFX
pool. The director's existing appearance ramp controls gain, capped at 0.55 linear over a source
measuring −14.5dBFS peak / −21.6dBFS RMS. The already-wired saved Music volume control is now visible
on the pause screen.

The native gate proves runtime forward looping, bounded crest gain, pause/resume, exact zero state
and death cleanup. The last-to-first sample step matches ordinary sample progression because every
carrier and amplitude envelope completes an integer number of cycles in the file. The headless
contract remains intact: no audio player or AudioServer access occurs there. Final sound taste and
Android speaker/headphone balance remain owner/device review rather than a numeric claim.

## Slice 11 — bounded guided crest flight implemented

The wing apparition now accompanies one guided flight arc inside the already protected flat. From
27–32 seconds the skater rises smoothly toward 96px above the ice, holds through the broad crest,
then returns from 40–45 seconds. Horizontal speed and the underlying acceleration clock remain
unchanged. This is a dedicated Player state rather than normal glide or a powerup: it has a hard
altitude target, a 260px/s vertical cap, no collision bypass, no invulnerability and no extra timer.
Jump input is neutral only while the flight/landing handoff owns the body, preventing a stale press
from firing on touchdown; ordinary input resumes after the one real landing.

The complete calm probe passes 163,746 assertions across preview and credited encounters. It
measures 1,079 bounded flight frames, 95.999px peak altitude, exactly one landing, rejected buffered
jumps during the arc, unchanged horizontal speed, safe camera placement, death cleanup, continued
coin/progression behavior and restored grounded
movement well before recovery. The fast gates pass except the three intentional TEMP preview
values, and the windowed composition gate passes at both widths/night palettes. Owner feel and
Android frame/input review remain required because deterministic correctness is not motion taste.
The established 20,000-frame ordinary camera/movement regression also passes unchanged.

## Slice 10 — visual wing apparition implemented

A brief six-feather light fan now appears behind the grounded skater from 20–51 seconds, reaching
full strength for the broad Aurora crest. This is the safe wing-visual fallback, not flight: it
does not touch position, velocity, collision, speed, input or player state, and it hides whenever
the skater is airborne. Six immutable `Line2D` shapes are built once; the existing event clock
changes only their transform and opacity. There are no particles, trails, timers or rebase state.

The windowed gate proves behind-gameplay ordering, zero cleanup, bounded timing, paused-frame
identity and 65/255 isolated visibility at 1152×648 and 1440×648 across both night palettes.
Captures are in `art_source/audits/aurora-wings-slice/`. The complete calm probe was green at
159,415 assertions at this slice. The controlled flight followed in slice 11 after separate
movement proof, and the ambient bed followed in slice 12.

## Slice 9 — restrained camera composition implemented

Aurora now eases the existing camera into a 1.055× zoom and lifts the flat terrain line to 0.59 of
screen height. Both ride the director's single appearance ramp. `Main` remains the sole camera
writer, captures the authored scene zoom at startup instead of duplicating its literal, and
restores it before the protected recovery ends. Ordinary horizontal follow/lead remains intact;
glide has explicit priority. Rotation, shake, letterboxing, input locks and a second controller
were deliberately excluded.

The live calm probe directly measures a 1.054999× peak, 0.590000 settled terrain fraction, zero
rotation, glide priority and authored-zoom restoration across preview and real encounters. The
full probe passes 159,415 assertions. The established 20,000-frame camera-shake gate and the
windowed Aurora composition gate also pass. Owner motion/taste and Android review remain owed.

## Slice 8 — sparse rear wisps implemented

Three small tapered arcs now drift around the skater during the Aurora. They are code-built
`Line2D`s placed before Player and TerrainGenerator, so every gameplay object structurally renders
over them. Their immutable nine-point shapes are built once; each frame only position and alpha
change as deterministic functions of the existing event clock. Edge fades hide the bounded travel
wrap. There are no particles, textures, shaders, trail history, per-frame arrays or rebase state.

The windowed gate checks draw order, child count, zero cleanup, paused-frame identity, visible
clock-driven drift and an isolated 43/255 contribution at 1152×648 and 1440×648 across both night
palettes. Full-composition captures are in `art_source/audits/aurora-wisps-slice/`. Owner motion and
Android review remain owed; no foreground strand was added because crossing gameplay silhouettes
would create the readability risk this behind-world construction avoids.

## Slice 7 — completion achievement implemented

The first complete, non-preview Aurora now grants the permanent `under_the_aurora` achievement,
displayed as “Under the Aurora.” `AchievementManager` remains the only writer: it listens to the
director's existing `aurora_finished` signal, while the director stays unaware of achievements.
The saved flag, not `aurora_count`, is the idempotence gate, so later sightings do not re-award it.
No save-version bump, gallery, reward payload or new UI was added; the existing toast handles it.

`aurora_calm_probe.gd` now injects an in-memory save into the achievement manager before manually
driving headless completion. It proves preview, partial and death cases award nothing; real
completion grants once, emits once and includes the flag in the saved snapshot; repeated finish
does not re-grant. The full probe passes 152,095 assertions. Fast functional gates pass except the
three intentional TEMP preview values.

## Slice 6 — bounded snow choreography implemented

Aurora now gathers the existing snowfall toward one broad midpoint crest and releases it through
the existing fade. `AuroraDirector.get_aurora_snow_blend()` derives the curve from the event clock;
`snow_drift.gd` remains the sole owner of particle density and composes biome × glide × Aurora into
one clamped `amount_ratio` target. Peak density is 1.45× the active night biome: about 56→81 visible
flakes in `starlit_night` and 70→102 in `twilight_blue`, both inside the already allocated 126-flake
pool. No emitter, particle allocation, texture, material, velocity change or independent timer was
added.

The windowed gate checks zero-state cleanup, the 1.3–1.6× crest bound and the existing full Aurora
composition at both widths/night palettes. Fast functional gates pass except the three intentional
TEMP preview values. Motion, pause/resume feel and Android fill-rate still need owner/device review;
the existing behind-gameplay layer keeps flakes structurally away from player/pickup readability.

## Slice 5 — grounded blade connection implemented

A compact cyan-green halo and short bright core now pin the Aurora to the skater's actual blade
contact. `AuroraBladeGlow` is code-built once, reads the real terrain surface and slope, and is
shown only while the player is grounded. The existing director ramp drives it; there is no new
timer, shader, trail history, particle pool, movement mode or rebase state. Jumping stops the
effect immediately rather than drawing light across empty air.

The windowed gate now isolates the blade pixels from the sky/wash/ice response and checks grounded
crest visibility plus zero-state cleanup at both widths and both night palettes. Captures are in
`art_source/audits/aurora-blade-slice/`. Wisps and snow were deliberately left out: they add
overlap and particle cost and should be judged separately. Owner/device review remains owed.

## Slice 4 — world light connection implemented

The single Aurora ramp now drives two restrained world responses. `AuroraWash`, a code-built
vertical gradient at `CanvasLayer -45`, lightly colors the ridges and background snow while
remaining structurally behind the player, terrain, coins and every other gameplay object. The
same ramp enters `TerrainGenerator.set_aurora_ice_blend()`, where it is composed with the existing
biome/lake appearance in the one function that already owns ice tint, variance and gloss. It keeps
the tile, cracks, rolling surface and deep-body contrast; there is no new shader or per-chunk clock.

The windowed sky gate passes at 1152×648 and 1440×648 with the complete sky/wash/ice response,
including zero-state restoration and layer/input checks. Captures are in
`art_source/audits/aurora-world-slice/`. The fast gates pass except for the three intentional TEMP
preview values. Owner motion/taste review and Android fill-rate testing remain required. Camera,
snow choreography, blade/wisp atmosphere, wings/flight, achievement and sound remain separate.

## Slice 3 — live calm safety implemented

This slice turns the foundation into the active event without adding camera, ice/world response,
snowfall, wings/flight, achievement or sound. Aurora reserves its immutable flat span while due
at night, past every existing obstacle/powerup collision extent. It then waits in `PENDING_ENTRY`
until the player has enough remaining span and is grounded without boost or ordinary glide. The
event begins only if the whole 61-second window still fits under a valid night sky. Any failed,
late or conflicted entry moves to recovery; the terrain remains untouched and the encounter does
not grant credit.

Within the span new obstacle nodes and boost/glide pickups are skipped. Existing visible objects
are never deleted. Existing boost or glide can expire before entry; boost/glide activation is
also refused inside the span, including the boost granted by an airborne trick. Coins, all other
powerups and jumping remain active. Aurora takes priority when it is simultaneously due and night;
an already armed or active Frozen Lake blocks the Aurora, and later reservations are non-overlapping.

The expanded `aurora_calm_probe.gd` passes 152,086 assertions headless and 14,708 in a native
window, covering terrain seams, lifecycle failures, pause, death, preview isolation, real credit,
spawn resumption and lake arbitration. The native harness reports an existing audio-resource
warning during shutdown only. `sky_layer_check.gd` still passes at both render widths. TEMP preview
knobs remain intentionally enabled for owner review.

## Slice 2 — flat terrain foundation proved, live integration next

The owner accepted slice 1's sky appearance and asked for the next step. This slice implements
**only the reserved flat terrain API and its proof**, not live calm activation. The existing
TEMP preview still shows Aurora over ordinary terrain. The director, obstacles, powerups, camera,
and flight are unchanged in this slice.

The request for flat ground permits a simpler design than the earlier rolling-range plan:
`TerrainGenerator.arm_aurora_flat(length)` commits **one long flat segment**, using the same
zero-magnitude shape as the lake. Normal 512px streaming chunks still draw and collide with it.
The API rejects non-finite/too-short lengths and repeated reservations, chooses beyond the
contiguous watermark **and every sparse cached spec**, and avoids a chasm at either adjacent
segment. Its index/length persist after the event and across cache rebuilds. No height already
sampled can change. Flat entry/exit have positional continuity; this does not yet promise final
camera smoothness or a safe path from the player to the entrance.

For now the geometry APIs conservatively exclude lake and Aurora reservations for the entire
scene: whichever is already reserved prevents the other from arming. This is an explicit
foundation limitation, not completed due/deferred scheduling. Live integration must resolve the
intended event arbitration and recovery policy before enabling the call.

`aurora_calm_probe.gd` tests eight seeds, sparse cache reads, rejected requests, immutable prior
heights/specs, exact flatness, real ground presence, both boundaries, repeat-arm rejection, lake
exclusion, and cache rebuild persistence. Four real collision traversals cover two seeds at
750 px/s ordinary/unshielded and 1000 px/s boosted, crossing both seams with no input and no
watchdog recovery. They exercise deep-run Y rebasing and verify bounded streaming chunk counts.
The proof uses a conservative 69,192px span (61 × 1000 plus 4096px at each end); final live sizing
must derive from the selected entry/recovery and powerup policy. No slowdown is introduced.

**Results:** foundation PASS, 137,363 assertions; freeze search 1,600 trials with no stalls;
freeze replay 60,000 frames without recovery; floor-contact sweep with no recovery/stuck events;
chasm probe 60 trials PASS. Physics probes used `--fixed-fps 60`, keeping 60Hz simulated steps.
Fast checks pass except the previously documented TEMP/missing-pin shipping-values failure.
Deliberately shortening the passage and inserting a void in isolated source copies each made
the proof FAIL. Obstacles and powerups are disabled in the geometry traversals; these results
are explicitly **not** evidence of spawn suppression or active-effect exclusion.

### Test isolation defect discovered during this slice

The headless autoload can still resolve to real Services. `GameManager.bank_playtime()` skips
headless, but `_on_player_died()` nevertheless called `SaveStore.record_run()`, which saves coins
and best-run stats. During the deliberately broken void test, the live save's modification time
matched the test (2026-09-09 23:10:24 local). Coins/best stats may have changed; no trustworthy
pre-test save snapshot exists, so no guessed rollback was made. Aurora scheduling/count and
playtime are guarded on separate paths; no intentional edits were made to the save.

Fixed the root cause: headless death now skips `record_run()`. Added an in-memory save regression
that checks neither wallet mutation nor disk-write invocation occurs. The new traversal probe also
detaches GameManager from Services. Remaining verification ran from a copied project named
`AuraFlatProbeIsolated`, with a separate user-data directory. Do not assume headless alone isolates
all save paths when writing future probes. The user was informed of the possible stat change.

**Next slice:** live pending-entry integration with night recheck and sufficient remaining flat
length, actual obstacle exclusion/previously spawned-object checks, no boost or ordinary glide
(including already-active effects and trick awards), completion/recovery and lake arbitration.
Do not simply call the flat API at visual onset. Camera and Aurora-wing flight follow that proof.

## Current direction and first implementation slice — 2026-09-09 follow-up

This checkpoint supersedes the planning-only status and older recommendations below.
The owner authorized incremental implementation, explicitly asking not to build it all at once.

**Updated direction:** no actual speed reduction. Audio was initially deferred; slice 12 later added
an original, locally generated ambient bed with no external licensing dependency.
Keep sky/world/ice light, camera, snow and achievement. Explore a reserved **flat** protected
passage, suppress boost and ordinary glide during the encounter (including trick-earned boost
and existing effects/pickups at entry), and develop the signature as skating → brief controlled
Aurora-wing flight → skating. The safer wing-visual fallback arrived in slice 10 and the separately
bounded guided flight followed in slice 11. Existing normal glide was not reused because it is not
a stable-height flight implementation. Obstacle-only event protection is a possible alternative to suppression,
not repeated grants of the consumable/tinting shield; chasm safety still requires terrain work.

**Slice 1 implemented: directional sky arrival and internal curtain folds only.**
`shaders/aurora_curtain.gdshader` reuses the existing baked textures with additive blending,
bounded UV deformation, and a feathered screen-space reveal. Three independent materials share
shader code. Arrival takes 12 seconds, with 0.65-second staggering per secondary band; the last
band is fully revealed at 13.3 seconds. The existing director still owns the 61-second envelope
and elapsed clock. No shader TIME, extra draw pass, new movement mode, or terrain change.

The existing windowed sky check now asserts right-side onset, left-side completion, paused-frame
identity, and internal movement independently of rect drift/breath. It retains per-band visibility,
zero-blend/death restoration and night-window checks. It passes for both night skies at 1152×648
and 1440×648. Captures are in `art_source/audits/aurora-curtain-slice/`; those gate captures change
the sky palette directly while holding the surrounding scene fixed, so they prove sky behavior,
not a fully composed nighttime world. Owner motion/taste review and Android performance remain.

Fast five: biome schedule, terrain invariant, lake suppression and export content pass.
Shipping-values fails on the three requested TEMP overrides and four **pre-existing missing
explicit project pins** (viewport width/height, tick rate, interpolation). `project.godot` was
byte-compared with its start-of-turn snapshot and left unchanged. The TEMP settings remain on.

**Next:** review this sky slice in motion, then design/prove the reserved flat passage and entry /
exit / powerup policy before enabling camera or flight changes. World lighting and wing effects
remain later reviewable slices. No implementation of those systems is implied by this checkpoint.

## Experience redesign — owner brief, 2026-09-09 evening

**Status: planning only. No implementation in this pass.** This section is the current proposed
creative direction and delivery plan. The implementation record below is retained for its audit
evidence and engineering constraints. Where its creative restrictions or sequencing conflict with
this section, this section supersedes them **as a proposal**, not as a claim that code changed or
that the owner approved every suggested effect.

The owner's current request is to make Aurora the project's signature experience: beautiful,
immersive, clean, and worth anticipating, rather than colors sitting above ordinary gameplay.
Their example includes a camera move, slower skating, light arriving from the upper right and
spreading across the sky, quieter foreground wisps, responsive ice, building snowfall, and an
ethereal glow at the blades. Those are inspiration to explore, not a mandatory checklist to stack
at full strength. The instruction for this session is to brainstorm and document, **not start**.
Old instructions embedded in project history are context; they do not authorize implementation.

### 1. Where we actually are

Checked against the working tree for this planning pass:

| Area | Actual checkpoint |
|---|---|
| Branch / committed head | `claude/aurora-reconcile` / `d29012e` |
| Working tree | Already dirty on arrival: audit fixes, documents, evidence, project settings, and preview settings. None committed by this pass |
| Aurora | Director, 61-second envelope, stored 30-minute deadline, full-window night prediction, three baked additive curtains |
| Audit verification | Earlier audit records fast five, rendered captures at 1152×648 and 1440×648, and 76 lifecycle/prediction assertions. These are prior results, not tests rerun here |
| TEMP settings right now | Aurora interval `10.0`; night bypass `true`; biome cycle `10.0` seconds. Left as requested |
| Preview progression | Preview status is latched; preview completion skips Aurora credit/deadline advancement. Ordinary playtime still banks |
| Missing experience | Safe calm, background light, Aurora ice response, camera treatment, slowdown, foreground wisps, blade glow, event audio, achievement |
| Owner review | Visibility is established by the supplied screenshot; the experience is explicitly **not accepted as special enough** |

The screenshot shows broad luminous bands over a landscape that largely keeps its ordinary
appearance. The skater is small and visually disconnected from the light; there is no visible
response linking sky, air, ice, and blades. A still image cannot establish motion quality, but
the code confirms the present motion is whole-band drift/bob/breath, without a spatial arrival.
Because night is bypassed and biomes are accelerated, this image is not a shipping-night color
reference. That does not invalidate the owner's central criticism about the missing experience.

The frozen lake is a useful contrast in *design*: terrain, controls, surface treatment, framing,
and trails all agree that something has happened. In the current code it changes camera target Y,
not `Camera2D.zoom`. Aurora should have an equally coherent identity without inheriting its flat
terrain, jump lock, mirrored sheet, or etched lake trail.

### 2. Recommended creative direction: travel into living light

The skater keeps moving through a rolling winter landscape as a distant light becomes a place
she is passing through. First a narrow green fold appears ahead, high on the right. It unfurls
leftward overhead. The mountains catch a little of its color, then the ice and the air near her
respond. The camera moves closer just enough to make her part of the scene. A small glow gathers
under the blades; one or two faint ribbons pass nearby. Snow builds, catches the light, and
briefly feels suspended in it. The whole scene takes one slow breath at its peak. Then nearby
light releases first, the sky lingers, and ordinary skating returns with room to recover.

The emotional sequence is **notice → approach → enter → belong → release**. A minute of uniform
maximum brightness cannot deliver that sequence. The sky is the lead, the skater is its human
anchor, and the world response connects them. Each supporting effect needs a job and a quiet
interval. Do not solve the current flatness by making every layer brighter.

**Recommended essential package:** safe rolling passage; directional sky reveal with moving
folds; mild framing/zoom; restrained mountain and ice response; local blade aura; sparse near
wisps; snowfall choreography; a deliberate exit. Audio is strongly recommended once a suitable
asset exists. Actual slowdown is a separately proved enhancement, not a dependency that prevents
the rest from becoming excellent.

**What makes it Aurora rather than the lake:** undulating terrain stays; jumping stays; the sky
has huge scale and the ground only receives light; the local trail dissolves into air instead of
engraving a mirror. The calm removes danger without converting the landscape into a flat sheet.

### 3. Full encounter storyboard

Use the existing **61 seconds** for the first complete candidate. All timings below are authored
starting points, not measured final values. Pending terrain entry happens before t=0 and is not
part of the spectacle. Do not add an unbudgeted prelude or afterglow outside the safety/night span.

| Time | What the player sees and feels | Main technical dependency |
|---|---|---|
| Before 0 | Ordinary gameplay. The event is due and a future safe passage is reserved; no distracting promise while live hazards remain | Reservation, lake arbitration, entry validation |
| 0–4 s: first light | A slim fold appears at the upper right. Sky elsewhere stays dark. Audio, if present, enters very softly. Ordinary framing starts to relax only after safety is confirmed | Directional reveal; master envelope rises |
| 4–8 s: unfurl | The fold spreads right-to-left, revealing striated curtains. A faint response touches distant scenery; camera begins its gentle move | Screen-space reveal independent of texture drift |
| 8–16 s: entry | Overhead coverage becomes wide. Ice catches green/cyan in its upper body. A small blade glow appears; first near wisp passes. Camera reaches its authored target | Light composition, grounding, sparse VFX |
| 16–31 s: immersion | Curtains slowly fold rather than slide as rigid slabs. Snow gains density and lateral drift. A quieter interval leaves time to enjoy skating | Bounded motion, snow composition |
| 31–41 s: crest | One broad wave of brightness travels across the sky. Ice answers with a weaker, slightly delayed pulse. Snow is fullest; a violet edge or tiny rose accent appears high above | Shared crest phase with staggered responses |
| 41–53 s: breathing room | Near effects thin. Sky keeps shape and scale. No repeated crescendo or new surprise; skating remains satisfying | Long, quieter plateau |
| 53–61 s: release | Wisps and blade halo disappear early; snow and ice return toward current biome values. Camera and optional speed return smoothly. The last sky fold fades last, without a hard wipe | Separate derived exit curves within the master envelope |
| After 61 s | All presentation contributions are exactly zero. Protected terrain continues through camera/speed settling and a readable approach to the next hazard | Recovery span and bounded settling |

The early right-side reveal should be unmistakable without looking like a loading bar. Use an
irregular, feathered frontier with folds emerging at staggered depths, not a vertical rectangle
that opens. At peak, curtains can span nearly the entire *width of available sky*, while dark
gaps remain. “Across the entire screen” does not mean painting opaque light over the landscape.

Prototype shorter and longer edits only after this sequence exists: roughly 45–50 seconds if the
middle drags, or 65–75 if the arrival needs more space. Every duration revision must update night
prediction, reservation length, recovery, tests, and audio together. Preserve rarity through the
existing clock; do not increase frequency to compensate for a weak event.

### 4. Effect possibilities and recommended choices

| Idea | Why it helps | Recommendation / cost |
|---|---|---|
| Right-to-left arrival | Gives the sky intent and a place to approach | Essential; moderate visual work |
| Moving folds and fine vertical rays | Makes the aurora feel alive instead of like drifting colored wallpaper | Essential; shader or mesh prototype |
| Gentle close framing | Makes the small skater emotionally present | Essential candidate, contingent on camera/readability review |
| Actual speed easing | Creates a bodily change in pace | Optional first release; high interaction risk |
| Mountain light response | Connects the sky to the world without more scenery | Essential, low strength |
| Ice receiving traveling color | Gives the large lower frame a reason to belong to the event | Essential; retain texture and depth |
| Glow at blade contact | Gives a clear local focal point | Essential; compact, no full-body recolor |
| Near wisps behind and briefly in front | Makes the skater feel inside the light | Essential at sparse density; overdraw/occlusion review |
| Snow building into a crest | Provides visible atmosphere and progression | Essential but restrained; no blizzard |
| Broad ambient swell and soft skate shimmer | Gives the sequence weight without louder graphics | Strongly recommended; asset and audio mixing work |
| Subtle upper-sky rose/red accent | Adds a rare crest detail to green/cyan/violet | Optional color study; not a rainbow cycle |
| Darkening the sky slightly under the event | Can increase saturated-light contrast without clipping | Optional if real-night captures show a need; owner-mediated sky channel |
| Sparkles on occasional ice facets | Adds small discoveries on repeated sightings | Later polish, sparse and deterministic |
| Hair/clothing rim light | Strengthens the local light response | Later, sprite-aware mask; avoid obscuring silhouette |
| Gentle one-time haptic onset | Adds tactility on supported phones | Later, opt-out and device proof |
| Small recurring variations | Keeps repeated sightings alive | Later; a few authored variants, same recognizable sequence |
| Full reflected sky on rolling ice | Spectacular in theory | Expensive; surface mapping and readability risk; not recommended initially |
| Screen distortion, bloom chain, chromatic fringe | Can suggest energy | Poor fit for clean readability; omit from recommended design |
| Camera roll/shake, flashing beams, whiteout | Adds intensity | Conflicts with calm and mobile comfort; reject |
| Flattening hills or levitating the skater | Makes a new traversal mode | Duplicates lake or changes physics heavily; reject for this direction |
| Scripted birds, constellations, meteor finale | Could add discovery | Competes with the headline; park unless the finished sequence needs it |

This is an exploration menu, not a promise to implement every row. Spending effort on a strong
arrival and local connection is more valuable than adding ten unrelated particle effects.

### 5. Sky art and rendering plan

**Shape language.** Give the main green curtain a narrow, luminous lower hem, broken fine rays
above it, and longer soft folds higher up. Cyan supports depth. Violet occupies thinner upper
edges and quieter secondary curtains. Preserve dark windows between folds. Avoid three equally
thick, parallel horizontal bands and uniformly smooth gradients; those read as a ceiling.

**Motion language.** Separate large shape travel, medium folding, and fine ray shimmer. Large
folds change slowly; fine structure moves subtly inside them. The hero crest travels once across
the span instead of making the whole sky pulse in sync. Microvariation may differ between bands,
but the broad reveal and crest must share a clock. No strobing or rapid hue rotation.

**Proposed shader is justified by deformation and masking, not by color alone.** The old
“no third shader” preference is reopened by this brief's explicit willingness to use shaders.
The existing additive textures remain a usable baseline and potential fallback; they are not a
reason to constrain the final result to whole-rectangle motion.

| Approach | Strength | Limitation | Role |
|---|---|---|---|
| Existing baked textures, translated and faded | Small change; known appearance and materials | Cannot convincingly deform internal folds; reveal needs care | Baseline / fallback |
| Segmented ribbon mesh with baked texture | Can bend silhouette with bounded CPU work | UV/stretching and tessellation seams; still needs a feathered reveal solution | Alternative if shader path underperforms |
| One dedicated 2D curtain shader using baked noise/shape textures | Spatial reveal, internal drift, hem/ray separation in one owned material | Fragment cost, material instances, compilation/pacing must be measured | Recommended prototype |
| Low-resolution offscreen composite | May reduce expensive shading area and permit one soft composite | Extra target, blur/upscale artifacts, memory and pass cost; not automatically faster | Conditional optimization only |
| Volumetric raymarch or scene-wide postprocessing | Large theoretical freedom | Unnecessary mobile expense and integration burden for this 2D look | Do not pursue initially |

The candidate curtain shader should use a small fixed number of texture samples and simple
bounded warps: a low-frequency fold field, a finer ray pattern, a shaped hem, and a reveal mask.
Avoid per-fragment procedural octave stacks when a baked texture communicates the same thing.
Do not prescribe an exact sample budget as “fast enough” without Android measurements.

**Reveal contract:** normalized viewport X controls arrival, with a soft frontier moving from
right to left. Texture UV controls the internal fold motion. Keep those coordinates distinct so
overscan and drifting textures cannot shift the arrival edge unexpectedly. The frontier must be
outside the right edge at zero and beyond the left edge at full reveal. Overscan must cover the
maximum warp, drift, and all supported aspect ratios without exposing a rectangular edge.

Use director-provided elapsed time for all shader animation; do not introduce a free-running
shader clock that continues through pause. Hide draws at zero. Reuse resources and materials;
compile/prewarm through a tested loading path so first appearance does not create the worst hitch
of the event. Asset preparation must not add expensive texture builds on every activation.

**Composition constraint:** opaque ridges currently occupy much of the upper-middle frame.
Position the strongest hem in genuinely open sky. A camera Y move changes terrain framing, but
the vertically screen-locked ridges do not simply move out of the way. Zoom also affects the
background and may actually crop useful sky. Measure the visible sky under the proposed camera,
rather than treating zoom-in as a reliable way to reveal more of it. If more sky is necessary,
first reshape/reposition curtains; an Aurora-specific background layout is a separate higher-risk
composition experiment, not a resurrection of ordinary vertical parallax.

### 6. Light across the landscape and ice

The screen should feel illuminated by one source, not globally tinted by one overlay. Start
with the same palette family and a shared broad crest, but use different strengths by depth.

**Background:** prototype the documented wash at `CanvasLayer -45`, behind world objects and
in front of background snow/ridges. Shape it vertically and cap opacity; it should suggest colored
air without erasing ridge separation. If it reads as a sheet of fog, prefer a small additive
contribution composed by the existing background color owner for each depth layer. Do not add
normal maps and dynamic lights across every mountain just to make a gentle color response.
The wash alone does not create actual object lighting; judge the result honestly.

**Ice:** make the upper ice catch green/cyan, with quieter violet in selected portions and the
deep body remaining dark enough to hold the world down. Retain cracks, texture, and rolling
surface shape. Do not copy the lake's flattening or full-screen mirror. Start with an Aurora blend
composed inside `TerrainGenerator.refresh_ice_appearance()`; it already owns the final lake/biome
appearance and writes `gloss_strength`. Aurora must not become a second independent uniform writer.

If a uniform tint still feels disconnected, add one broad moving light band to the existing ice
shader. Mask it by the ice's own surface-depth coordinates, not an assumed horizontal screen
floor. Drive its broad timing from the same crest as the sky; physical ray tracing is unnecessary.
World X can anchor continuity across chunks, while surface-relative depth prevents color from
floating above hills. Check far-travel precision, chunk seams, and Y rebasing. A phase anchored
only to a chunk's local UV will visibly restart at each seam.

Color-study candidates: (A) emerald/cyan with violet sky edges; (B) stronger cyan with occasional
violet reflection; (C) the same base with a very small rose accent at the crest. Recommend A as
the signature. Red is a possibility from the owner's example, not a requirement to cycle the ice
through green, blue, and red. Reject any candidate that makes the floor look like molten neon.

Additive light cannot subtract the underlying sky's blue, and more additive brightness can clip
to white. First judge against actual night. If stronger green still needs a darker substrate,
compose a restrained event contribution through the sky's owner; never modify palette resources
or freeze the day clock behind its back. On release, recover the **current** biome, not a stored
entry palette, because biome transitions continue during the encounter.

### 7. The skater inside the light: wisps and blade aura

**Blade aura:** a compact soft cyan-green halo just under/around actual blade contact, a brighter
thin core, and a short fading wake. Suggested study size is roughly 1–2 skater widths, with a
0.4–0.9 second wake; tune on a phone at real player scale. This is emitted light and air, not a
long line permanently drawn on the ice. Keep body/clothing colors readable. The user's new glow
request reopens the earlier prohibition on any player light response, but does not require a
global sprite recolor.

Gate contact emission on grounded contact. On a jump, stop laying new floor light and let old
samples expire; a tiny airborne blade glimmer may remain, visibly detached from the ground.
Never connect a trail across a jump/glide gap. Sample real surface positions including `ground_y`,
align short contact elements to the slope, and prevent the halo from cutting deep through a hill.
Do not fake contact by pinning the entire effect to the screen.

**Near wisps:** mostly thin, translucent arcs behind/around the skater; occasionally one tiny
foreground strand crosses near the blades or trails behind her. Start with 1–3 near ribbons
visible, not a full-screen fog layer. Use low contrast and clean tapered ends, with clear gaps
around her body and pickup silhouettes. They should drift past her rather than track every body
motion as a rigid attached halo. Avoid a ring that resembles the shield or a trail that resembles
the speed-boost reward.

A small authored wisp atlas or textured ribbon mesh is enough for the first candidate. Reuse the
curtain shader only if the same behavior really fits; do not grow a mode-heavy universal material
to avoid a tiny dedicated local effect. Start with geometric placement/exclusion around gameplay
objects; only consider screen-space masks if actual overlap remains a readability problem.

**Draw order and coordinates:** sky stays at -200, background at -100, ordinary snow at -50,
proposed wash at -45, world at 0, UI at 1. Near effects need explicit tree placement within the
world; the front accent is a small world node after terrain and below UI. A rear effect before
the player can be occluded by terrain, which already draws after the player. Verify actual pixels
at crests/troughs instead of assuming sibling names prove visibility. Do not raise ordinary snow
or the background wash over gameplay to achieve foreground depth.

Existing `skate_spray.gd` and `skate_track.gd` are reference implementations, not drop-in Aurora
features: they are lake-gated and carry flat-surface assumptions. Reuse a small proven texture or
ground-contact helper if useful; keep the distinct looks and lifecycle ownership clear. Any
world-space lingering particles/history need correct Y-rebase handling; player parenting alone
does not repair already emitted world-space particles. Screen-space sky/wisps need a clear
world-to-screen mapping if they follow the player. Test rebase mid-trail and mid-glide.

### 8. Snow and sound as choreography

**Snow should gather, crest, and release.** Begin near the current biome amount, rise toward
roughly 1.3–1.6× the current visible density as a starting study, and add modest lateral travel.
Keep most flakes small. The crest may contain a few brighter flakes catching cyan, with the
majority retaining subdued snow colors. “Faster and faster” works as a finite build toward the
crest; accelerating for the full minute would read as a storm and overwhelm the calm.

`snow_drift.gd` already composes biome density with glide using a preallocated particle pool and
`amount_ratio`. Add Aurora as another input to **that owner**, with a bounded combined target.
Do not let the director write particle properties that `_process()` or `apply_palette()` then
overwrites. Existing headroom already serves glide; multiplying an Aurora factor does not prove
the pool has spare capacity. Measure combined maximum density, cap or resize the pool at setup,
and avoid reallocating it during the event. Check whether velocity edits affect only newborn
particles; use gradual emission behavior or a small separate accent emitter if immediate shared
drift would otherwise cause discontinuity. Verify particle pause/resume in the actual renderer.

**Audio direction:** soft airy onset, a low warm harmonic bed, restrained high shimmer at the
crest, and a gentle release. Keep blade contact and pickups readable; avoid constant chimes on
every flake and a dramatic trailer-style impact. The sequence should still make sense muted.

The current project has a six-voice one-shot SFX pool and no event music bed. An Aurora loop
needs its own lifecycle-aware player/mixing path rather than occupying that pool for a minute.
Use a licensed/original seamless ambient asset, optional onset/release accents, and an authored
gain curve. Integrate existing volume controls and pause behavior; no hard-coded volume that
ignores user settings. Duck competing ambience only if present, not critical pickup/UI cues.
Loop boundaries, restart, app backgrounding, and death must not click or leak audio. No audio
asset was sourced or generated during this planning pass.

### 9. Camera and pace: precise proposals, separate risks

**Camera candidate:** begin with a relative zoom of `authored_zoom × 1.04–1.08` and a modest
vertical composition shift, roughly 3–5% of viewport height as a study range. Larger Godot zoom
values magnify. Capture the authored value; never replace it with an assumed literal. Ease in
over the opening 8–12 seconds and return during the closing 8 seconds. Compare with framing-only
and a subtle pull-back candidate in actual play, because zoom-in may sacrifice too much sky.
Recommend mild zoom-in only if both the skater and open sky benefit in the rendered composition.

`Main` remains the one camera writer. Compose event framing there; do not attach a competing
camera tween to the director. Preserve horizontal follow/lead. Glide visibility takes priority:
reduce Aurora zoom/framing toward the normal glide-safe view while airborne as needed, then
blend back without a snap. Lake framing is excluded by arbitration. No camera roll, shake,
letterboxing, or input lock. Keep pause controls stationary and usable.

Camera target restoration is not the same as camera arrival. Define a measurable settling
tolerance and maximum expected settling time; the safety margin covers both. At maximum zoom,
measure forward visible distance in screen pixels/world units and restore normal hazard preview
before hazards can re-enter the approach. A motion-reduced variant can keep static framing and
the same light sequence; plan the setting only alongside the project's actual settings UI.

**Actual slowdown candidate:** ordinary speed multiplier around 0.85–0.92 (study start 0.88),
smoothly applied during the protected span. At 750 px/s this would be about 660 px/s. It should
feel like gliding into quieter air, not losing control or braking. Compare against unchanged
speed before deciding that more physics code improves the experience.

Do not use `Engine.time_scale`: that would alter event timing, particles, physics, input feel,
effect timers, and cumulative-playtime semantics together. Keep the base `SpeedManager` ramp
running normally; compose an event contribution at the resolved movement-speed seam. Do not
overwrite `current_speed` every frame: its incremental ramp and debug pinning are intentional.
Audit recovery/watchdog paths too: some currently use `speed_manager.current_speed` directly.

**Recommended boost policy for the prototype:** boosts retain their established speed and
timers; they override the ordinary Aurora slowdown. Do not silently devalue an earned powerup.
Return to the reduced ordinary target through a proved transition after boost expiration.
Keep the reservation/night bound at the existing 1000 px/s even if normal speed is reduced.
Jump and glide controls remain intact. Slower horizontal travel changes jump landing locations,
coin collection opportunities, and slope interactions; it is a gameplay change, not just VFX.
If the transition needs a broad powerup redesign, retain normal speed for the first release.

Alternative: communicate calm through framing, slower curtain folds, gentler sound, and lighter
near motion, while movement is unchanged. Do not fake slowdown by changing terrain parallax or
camera horizontal lag; that introduces slipping scenery or gives away reaction distance.

### 10. Calm reservation and lifecycle design

The visual plan needs a real safe passage before camera or pace changes become live. Preserve
rolling terrain, suppress obstacle bodies, and exclude chasm geometry throughout the protected
range. Keep death/fall/stall watchdog logic active. A shield or invulnerability flag would hide
defects and can leave the player falling forever; safety must come from the terrain and bodies.

The audit's natural-gap route remains rejected at the current duration: 0.000239% eligible
distance before recovery/night is not a useful encounter cadence. The recommended route is the
write-once, write-ahead segment reservation described in the implementation record below.

**Proposed lifecycle:** `IDLE → PENDING_ENTRY → ACTIVE → RECOVERY → DONE`; these states are
design names, not present code. Keep artistic beats as time curves within ACTIVE rather than
adding a gameplay state for each light effect.

1. While due, arbitrate before touching terrain. A lake already ARMED/ACTIVE wins; an Aurora
   already pending/active/recovering blocks new lake arming. For simultaneous unclaimed requests,
   propose fixed Aurora priority because it needs night; implement the same rule in both sibling
   queries, not “whichever node happened to process first.” Deadlines stay due while deferred.
2. Select an unsampled future range strictly beyond `highest_cached_segment_index` and any
   conflicting cached specs. Validate every reserved index is absent from `segment_spec_cache`.
   Range selection must not call normal getters that populate the very range being reserved.
3. Reserve atomically: either the whole range is valid or nothing changes. Then establish its
   actual world bounds through normal generation. The terrain predicate uses the immutable
   reservation, never `aurora_active` or a clock.
4. Suppress future obstacles by position, including full body extent and approach/exit margins.
   Inspect already-spawned bodies. Prefer placing the protected start beyond visible/live bodies
   so they never need to vanish on screen. Any cleanup of already-spawned protected bodies must
   occur safely offscreen and be verified on actual collision shapes, not just sprite centers.
5. Wait for grounded, stable entry sufficiently inside the range to accommodate the player body
   and approach buffer. Do not begin over a void or an unresolved airborne approach. Recheck
   enough night and enough remaining protected distance at the actual start. If glide delays
   safe entry too far, skip the event for this run instead of shortening protection.
6. Start the visual clock only after entry succeeds. Freeze that clock under pause. Preserve
   preview latching across pending entry as well as active time, so a preview reservation cannot
   become credited merely by toggling TEMP settings off before entry.
7. At the end of presentation, zero all cosmetic contributions and restore camera/speed targets.
   Recovery keeps set-piece exclusion while movement/framing settles and the trailing protected
   approach is traversed. Do not release arbitration while the other event could overlap this
   unfinished passage.
8. Completion credit remains once, after the defined completed encounter. Recommended boundary:
   after the 61-second presentation has completed and restoration has reached safe tolerances;
   then use the existing bank-before-save path. The later empty reserved tail need not delay the
   achievement, but lake arbitration remains held until safe release. Make this distinction
   explicit in code/tests if completion and arbitration release differ.

**Failed pending entry:** never unreserve or rewrite sampled terrain. A failed night/entry check
abandons the appearance for this run, retains the harmless immutable terrain reservation, and
leaves the deadline due for a later run. Release exclusivity only after the reserved span has
been passed safely. This conservative fallback may leave an uneventful safe stretch; count such
cases in development to avoid silently making Aurora rarer. Do not repeatedly arm ranges within
one run or hold a player waiting inside a finite band for the next night.

**Sizing, with units:**

```
active distance bound = maximum supported world-X speed × full presentation seconds
                      = 1000 px/s × 61 s = 61,000 px
protected length      >= entry allowance + active distance bound
                         + maximum speed × bounded settling time
                         + recovery/readability distance + body/spawn extent allowance
segment count         >= ceil(protected length / minimum legal reserved segment length)
```

All allowances go inside the division. Use the actual minimum length for the selected no-chasm
segment set, not an unverified constant. For reference, one screen is about 1382 world px at
1152 width with the current zoom, but about 1728 world px at 1440 width. “One screen” must derive
from the widest supported restored camera, not the base viewport. Normal speed reduction does
not justify shrinking the worst-case reservation. Slowing down may instead leave a longer quiet
tail; measure its duration and experience. Never remove protection early to hide excess tail.

Night prediction must cover any still-visible aftereffects/settling interval, if the selected
design extends light beyond 61 seconds. With all light zero at 61, the recovery need only retain
terrain safety. Entry prediction must account for the approach and be revalidated on arrival;
checking 61 seconds of night at reservation time alone is insufficient.

### 11. Ownership, curves, and restoration

One director owns eligibility, event elapsed time, preview status, lifecycle, and the master
visibility envelope. Consumers own their rendering or gameplay property. **One clock does not
mean every effect must have an identical fade.** The new choreography deliberately extends the
old “one ramp” rule: named deterministic curves derived from that one clock may stagger reveal,
camera, ice, snow, local light, and crest. No independent timers or unmanaged tweens.

Prefer a small explicit set of getters/values over a generic event graph or new autoload. Keep
existing `get_aurora_blend()` compatible for consumers that only need visibility. Document curve
units and endpoints; every cosmetic contribution is exactly neutral outside the event.

| Owner / likely file | Planned responsibility |
|---|---|
| `scripts/systems/aurora_director.gd` | Pending entry, recovery, shared curves, sibling arbitration, completion; retain schedule protections |
| `scripts/terrain/terrain_generator.gd` | Atomic immutable range, pure queries, composed ice appearance |
| `scripts/systems/frozen_lake_director.gd` | Matching arbitration and due-preserving deferral |
| Existing obstacle spawner | Position/body-aware suppression and safe treatment of existing bodies |
| `scripts/systems/sky_backdrop.gd` | Curtain resources, bounds, material values and zero-visibility behavior |
| Proposed `shaders/aurora_curtain.gdshader` | Bounded deformation, ray/hem appearance, spatial reveal; only if prototype chosen |
| `scripts/main.gd` | Sole camera composition and restoration |
| `scripts/player/player.gd` / speed seam | Optional resolved-speed contribution, all related movement/recovery reads audited |
| `scripts/systems/snow_drift.gd` | Single composed snow target from biome, glide, Aurora |
| Small proposed local Aurora VFX node | Blade contact glow, short-lived wake, bounded wisps, rebase cleanup |
| `scripts/systems/biome_director.gd` and background consumers | Only if a composed background/sky light input is necessary; palette remains authoritative |
| Small event audio owner | Loop, gain envelope, pause/cleanup and existing volume controls |
| `scripts/systems/achievement_manager.gd` | One permanent ID and connection to completed, non-preview signal |
| `scenes/main.tscn` | Explicit new local VFX/audio nodes and verified draw order; no unrelated scene cleanup |

On pause: freeze event progress, shader clock, particles, and intended audio behavior together.
On death/restart/home/scene teardown: hide draws, stop emission/audio, clear trail history, restore
camera/speed inputs, and grant no partial credit. On resume: continue the same beat without a
new onset or emission burst. Test mobile suspend/resume through GameManager's existing flow.
Do not assume a missing visual consumer means all gameplay dependencies are safe: missing sky
can mean a quieter feature, but missing reservation/entry dependencies must prevent active entry.

Restore contributions to zero rather than blindly restoring cached material colors: biomes,
glide, and powerups may have changed since entry. Camera returns to authored base plus its current
normal follow state; speed returns to the current base/boost policy. No shared material may
retain event state into the next run.

### 12. Performance and comfort plan

The objective is a smooth, repeatable phone experience, not merely a good still. The existing
three curtain textures use 576 KiB raw LA8 data; that is not a total GPU-memory estimate. Existing
visible clipped curtain area is recorded around 0.53 screen equivalents, but the redesign may
change it. Count draws, shaded overlap area, texture memory, particles, and CPU work separately.

Start with cropped sky draws, one cheap background response, ice material reuse, and small local
effects. Do not add a fullscreen translucent quad per idea. The project's four-fullscreen-alpha
budget is a design constraint to measure against, not a claim that three curtains are one pass.
Disable invisible nodes and emissions. Build textures/preallocate once, with loading cost also
measured. Do not turn on a global rendering feature for one glow before local sprites are tried.

Profile normal night versus identical-seed Aurora, first onset versus later frames, and repeated
events in a sustained 10–15 minute device session. Record target phone, resolution, renderer,
refresh/FPS cap, frame-time median/p95/p99, visible hitches, and any thermal/frame-pacing drift.
If targeting 60 FPS, 16.7 ms is the total frame budget; the event receives only measured spare
headroom, not the full 16.7 ms. No hardware-specific performance promise is established here.

Suggested reduction order if needed: reduce near-particle density and wisp overlap; reduce
secondary curtain detail/area; simplify warp texture sampling; replace spatial ice response with
the composed tint; evaluate a lower-resolution curtain path only with comparative measurements.
Preserve the arrival, main curtain shape, blade connection, and exit even on a simpler look.
Do not build a dynamic quality manager unless measurements justify it; one good default and a
small static fallback are easier to maintain than many runtime tiers.

Comfort/readability: no flashes, full-screen distortion, accelerating camera, or whiteout. Keep
HUD and input available, and check coin/powerup/player contrast in final composited pixels. A
palette-data gate cannot see a near wisp over a pickup or light washing out its background.

### 13. Delivery plan after a later implementation go-ahead

Each stage should produce one reviewable question or result. A separate commit does not mean an
unfinished unsafe feature should be enabled. Stages 2–3 form one coherent calm deliverable;
obstacle-only suppression is not a shipping milestone. This pass performs none of these stages.

| Stage | Work / deliverable | Acceptance before continuing |
|---|---|---|
| 0. Preserve baseline | Review existing audit diff, retain its evidence, separate TEMP values from a future shipping commit; capture real-night baseline | Audit fixes understandable; current look and device baseline recorded |
| 1. Art/sequence prototype | Compare rigid baseline vs deforming/revealing curtains in a controlled scene; camera candidates; rough blade/wisp and ice color studies | Arrival is legible, sky still has shape, skater belongs; owner sees a moving sequence |
| 2. Calm proof | Specify and exercise immutable range, entry/night recheck, obstacle bodies, lake tie-break, failure/recovery cases using production terrain | Direct safety assertions and ordinary unboosted traversal pass; no sampled height changes |
| 3. Calm integration | Wire pending/active/recovery lifecycle to proven range and spawners together, with preview/save behavior | Full physics regression plus event-specific tests; no unsafe partial enablement |
| 4. Sky choreography | Chosen curtain implementation and derived reveal/crest/exit curves | Windowed sky coverage, pause/resize/night-boundary tests, device frame pacing |
| 5. World connection | Background response and ice response in their owners | Readable depth and pickups, seamless chunks, exact current-biome restoration |
| 6. Local atmosphere | Blade aura, sparse rear/front wisps, composed snow | Grounded/jump/glide/rebase cases clean; peak density stays readable |
| 7. Camera | Mild zoom/framing with glide priority and bounded recovery | Camera regression, screen-motion capture, safe hazard visibility after release |
| 8. Pace experiment | Compare unchanged speed with a proved ordinary-speed multiplier; keep only if better | Jump/boost/glide/stall/coin behavior and restored pace pass; no broad rewrite needed |
| 9. Sound / completion | Ambient assets/mix and one achievement after verified non-preview completion | Volume controls, pause/death/restart, once-only award and save reload pass |
| 10. Full authored pass | Tune timing/strengths together; remove effects that compete; validate sustained device run | Complete encounter passes quality bar below, including reduced-cost fallback if required |
| 11. Shipping handoff | Restore TEMP defaults when preparing release, update current docs and shader count if changed, run required checks | No preview settings ship; only verified results recorded; clean reviewable diff |

Stage 1 is a visual prototype, not a way to put unprotected camera/pace changes into the live run.
Future implementation may combine small adjacent presentation commits for review convenience,
but must keep terrain safety and speed risk explicit. Do not repeatedly run every physics gate
for color-only edits; match checks to changes and run the complete required tier at integration.

### 14. Validation cases that actually prove the feature

**Terrain/lifecycle:** one maintained Aurora calm probe should directly inspect actual segment
specs/heights and obstacle bodies, not merely assert the suppression predicate. Run ordinary,
unshielded, unboosted, no-input traversal as well as maximum-speed coverage: boost itself can
survive the hazards and is therefore not proof that hazards were removed. Mutation-check that
reintroducing a chasm/obstacle or shortening the band makes the relevant assertion fail.

Cover cached-spec rejection above the watermark, an obstacle spawned just before eligibility,
body extent straddling the boundary, entry while airborne, delay until too little range remains,
late-night arrival, simultaneous lake/Aurora due, existing armed lake, abandoned reservation,
death during pending/active/recovery, one completion only, restart, and terrain sampling after
the event. An immutable safe segment must remain the same after its cosmetic timer reaches zero.

**Movement/camera:** ordinary and boosted traversal at varied speeds; boost gained/expired near
entry and exit; glide starts/ends during framing; maximum jump upgrade; oversized hills;
multiple Y rebases; recovery into the first real hazard with normal forward view. If slowdown
is adopted, assert every movement/recovery path resolves speed consistently and does not reset
the base acceleration clock. Verify exposure of pickups, not just absence of deaths.

**Rendered composition:** fixed real-night palettes and their transitions, baseline 1152×648
and wide 1440×648, resize during reveal, ground crest/trough and glide height, first/peak/last
frames and moving clips. Inspect individual layers and final composite. Measure curtain presence
with scenery visible, clipped highlights, player/pickup contrast, no rectangular edges, and
zero-contribution restoration. Pixel equivalence comparisons need the same frozen biome/time
state; moving normal snow otherwise makes a before/after diff meaningless.

**Clocks and saves:** isolated/copied saves for unscheduled/reset state, existing deadline,
uninterrupted long run, completion bank-before-save, reload, and preview toggles during pending
and active. Ordinary playtime continues; Aurora preview credit does not. Default headless runs
skip the director, so the calm probe must deliberately exercise the terrain API and scheduling
tests must explicitly drive the lifecycle without touching the real save. A green headless suite
does not verify shader appearance, particle pause, or night-color composition.

Use the fast five; the terrain slice owes freeze-search, freeze-replay, floor-flicker, chasm,
lake suppression and the new calm proof. Camera work owes camera-shake plus rendered zoom
inspection (position-only metrics miss magnification motion). Visual work uses the existing
windowed sky gate and ice/contact-sheet captures. Native prior audit results remain historical
until rerun against the changed lifecycle. Check source diffs after any engine run.

**Owner acceptance:** watch the full encounter on a real night at shipping biome pace, muted and
with audio, and on the target phone. Also test a second appearance: the same sequence should
still feel rewarding once surprise is gone. Debug night bypass is for fast state inspection,
not color approval. If it feels like “ordinary gameplay under colored stripes,” the work is not
done even when every correctness test passes.

### 15. Quality bar, decisions, and explicit tradeoffs

The finished event must have a recognizable arrival, a local connection to the skater, a clear
crest, and an unhurried exit. Sky folds remain distinguishable at phone size. Ice retains depth.
The player can look up safely while still choosing to jump and collect. No supporting effect
needs to scream to be noticed. On completion, controls, framing, speed, colors, audio, and saves
all behave normally, and the next hazard feels fair.

The most expensive **necessary** part is the calm's terrain reservation and safe lifecycle. The
most promising visual investment is the directional, deforming curtain. The easiest strong local
payoff is blade light. The largest **optional** bug surface is actual slowdown. The most likely
GPU trap is stacking large translucent wisps, snow, wash, and curtain passes. The largest art
trap is losing dark space and making every surface equally saturated.

Recommended choices to carry into a later implementation review:

- Keep the 30-minute stored deadline, night gating, one event per run, and rolling terrain.
- Start with the 61-second storyboard and one signature emerald/cyan/violet identity.
- Prototype a dedicated curtain shader against the baked-texture baseline; accept extra shader
  code if it demonstrably improves shape, arrival, and phone performance together.
- Build the complete safe calm before enabling live framing/pace effects.
- Aim for mild close framing, sparse near wisps, blade contact light, upper-ice response, and a
  single snow/brightness crest. Keep every supporting layer subordinate to the sky and skater.
- Test real slowdown separately; retain normal physics pace if the benefit is small.
- Add event sound once assets/mixing are ready; do not postpone the visual sequence for assets.
- Keep dynamic reflection, full-body lighting, elaborate variants, and haptics as later options.

These choices are recommendations, not newly settled owner decisions. The request authorizes this
complete written plan only. **Next action is review of the direction; implementation has not begun.**

---

## Earlier implementation record — retained audit context

The sections below describe the reconciled baseline and earlier plan. In particular, old
“no third shader,” “never player light,” identical-ramp restrictions, camera pull-back wording,
and separate obstacle/chasm shipping steps are superseded by the proposed redesign above.
Statements that TEMP defaults are off describe the earlier audit checkpoint; they are on now.
Purity, save integrity, draw-order, headless, and measured audit findings remain relevant.

**This is the feature the game is named after.** Build-order #12.

**RECONCILED 2026-09-09 from two branches that had each planned and part-built it.** They agreed
on more than they disagreed, but they disagreed on things that matter, and the merge resolved
every one by owner decision rather than by picking a side. Where this file states a decision, it
is settled; where it says a route is open, it genuinely is.

| | State |
|---|---|
| The director, its clock and its phase machine | **BUILT** |
| The ribbons — three code-built curtains in `SkyBackdrop` | **BUILT**, repositioned and rendered in-engine 2026-09-09 |
| The schedule — stored deadline, 30 min, night gate | **BUILT**, reconciled and audit fixes verified 2026-09-09 |
| The calm — no obstacles, no chasms | **IN SCOPE, NOT BUILT.** The live work |
| The wash, and the ground catching the light | **IN SCOPE, NOT BUILT** |
| The camera pull-back | Planned, not built |
| The achievement | Two edits, not written |

## Current checkpoint — review before more code

The audited sky/scheduling implementation is ready for owner review, but remains uncommitted.
The six fixes are verified in the desktop renderer and the fast checks; they are not a claim that
the finished set piece exists. In particular, the calm, wash, ground response, camera, and
achievement still have no shipping code.

### What to test now

The owner should judge the curtain height, brightness, ray definition, and drift in a real night
run. The critical question is whether the now-visible green hem reads as an aurora over the ridge
line, rather than as a bright ceiling. Test the target Android device for frame pacing and thermal
behavior through repeated appearances. The automated renderer proves the curtain appears in the
right stack; it cannot make either taste or device-performance decisions.

Preview knobs are progression-isolated. An interval/night/biome preview cannot initialize a
deadline, increment the count, move an existing deadline, or emit the completion signal. Keep the
night bypass for state-machine inspection only: it deliberately permits a daytime composition that
is not valid visual approval.

### Next work, in order

1. Commit the reviewed audit fixes alone.
2. Make the calm a design/probe step before writing terrain code. The measured natural-gap route
   is not viable. Specify Route A's reserved range, safe entry point, treatment of already-spawned
   obstacles, recovery margin, and lake mutual exclusion in one design with a testable invariant.
3. Implement and validate that complete calm slice. Do not separately ship only obstacle
   suppression: it cannot remove obstacles already spawned and it would leave chasms live.
4. Add the wash, ground response, camera, and achievement as independent follow-ups after the
   calm is safe. Each should retain the director's one blend and respect its owning subsystem.

## What it is

A rare spectacle on the cumulative-playtime clock — **every 30 minutes**, against the lake's 20 —
that turns about a minute of ordinary play into something to look up at. Everything rides one
ramp, `AuroraDirector.get_aurora_blend()`.

It is still `GameManager.State.PLAYING` throughout, exactly as a lake is. Nothing here goes near
`get_tree().paused` or a screen's visibility; `set_state()` remains the only thing allowed to.

### Why it can't just be colours in the sky

The parallax ridges are **opaque** and their tops sit at y 0.21–0.45 (`visuals.md`, "There has to
BE a sky"). A strictly sky-only aurora is therefore confined to the top ~40% of the frame with a
hard mountain edge under it, and the other 60% of the screen carries on exactly as before. That
reads as a nice sky, not as an event.

**This is the argument for the calm and the wash**, and it is why the sky-only version built today
is a first phase rather than the finished feature. The owner's framing on 2026-09-09 was *"I want
everything to turn bright and beautiful"* — the light reaching the whole frame, and the hazards
standing down so there is time to look at it.

## Decisions

Consolidated from both branches. Do not re-litigate these without the owner.

| Question | Decision | When |
|---|---|---|
| Interval | **30 min** of cumulative playtime | 2026-09-09 |
| Schedule shape | **A stored deadline**, never `count × interval` | 2026-09-09 |
| Which sky | **Night for the entire event**, blended `star_density` >= 0.8 across the maximum travel span | 2026-09-07 |
| Duration | 45 s hold + two 8 s fades = **61 s** | 2026-09-07, proposed not measured |
| Forced flat segment | **No.** Terrain keeps rolling | 2026-09-07 |
| Ribbon rendering | **Code-built textures, additive `CanvasItemMaterial`.** Not a third shader | 2026-09-07 |
| Colour identity | **Fixed** green/violet, never per-biome | 2026-09-07 |
| Hazards | **Removed for the duration** — no obstacles, no chasms | 2026-09-09 |
| Reach of the light | **Sky + background + the ground.** Never coins, obstacles or the player | 2026-09-09 |

### What the reconciliation changed, and why

Both branches were wrong about something. Recorded because each was load-bearing.

| Was | Is | Why it mattered |
|---|---|---|
| `(aurora_count + 1) × INTERVAL`, the device `frozen_lake_count` uses | A **stored deadline**, `next_aurora_due_seconds` | The lake's device is only safe because its count and the playtime clock were born together at v3. The aurora lands in saves already holding hours, so a multiple is retroactively owed many times over and pays out **back to back** until the count catches up — the rarity of the headline feature destroyed on the first launch after the update |
| 60 minutes | **30 minutes** | Owner decision. It is not "three times the lake"; rarity comes from the night gate as much as the clock |
| Eligibility by palette identity (cycle slots 5–7) | **Blended `star_density` >= 0.8** | Simpler, already authored on all eight palettes, already blended every frame, and it excludes the crossfade shoulders for free with no second list to drift. The palette-identity design and the long argument about which slots qualify are **superseded** — ignore any older copy of this file that reasons about cycle slots |
| A third `.gdshader` for the curtains | An additive `CanvasItemMaterial` | A built-in, so the two-shader budget is untouched. Measured to work; see the ribbons below |
| "The aurora must never arm terrain" | **The calm is in scope**, and the constraint is narrower than that | The two halves of the calm are not equally risky, and one of them touches no terrain at all |

## The architectural rule this feature must not break

`CLAUDE.md`: **`get_terrain_height` must stay pure in `(session_seed, world_x)`.** It has exactly
one permitted runtime input today, `lake_segment_index`, and **`arm_lake()` is its only writer** —
write-once and write-ahead, above `highest_cached_segment_index`, so arming can only ever *extend*
the height field, never contradict a sample already taken. Chunk visuals, collision, player tilt
and the debug HUD all sample it independently, so a range that moved after a sample would make
them disagree inside a single frame.

One branch read that as **"the aurora must never arm terrain"** and built the feature sky-only
around it. That instinct is right and the rule is real. But the rule is not "never touch terrain"
— it is *"any runtime input to the height field takes the write-once, write-ahead deal."* The lake
proves the deal is takeable. What follows is that the two halves of the calm have **completely
different risk**, and they must not be built in one step.

## What is built

### The director — `scripts/systems/aurora_director.gd`

Owns **when**: the clock, the phase machine (`IDLE -> ACTIVE -> DONE`, terminal), and the one ramp.
`SkyBackdrop` owns the look and *reads* the ramp; `BiomeDirector` owns what time of day it is;
`SaveStore` owns the counters; `AchievementManager` will listen. Nothing reaches into another
system to do that system's job.

- **One aurora per run, maximum.** `DONE` is terminal, as the lake's is. Nothing is lost by it:
  the deadline only moves in `finish_aurora()`, so a deadline crossed in a run that ended early is
  still crossed and the next run is immediately due. This is also what will keep a calm band's
  terrain reservation write-once for the life of a scene.
- **Hard-skips headless as the first statement in `_ready()`.** Not an optimisation — the trigger
  reads cumulative playtime out of the developer's own `save.dat`. It is also what keeps
  `AchievementManager` safe, since that file has no headless guard of its own and says so.
- **Default `process_mode` (INHERIT)**, so an aurora freezes on every menu for free.
- `push_blend()` is **the one seam the look arrives through**. A later phase that replaces the
  curtains replaces what is behind that call and nothing else.

### Audit fixes — 2026-09-09

The green hem was behind the opaque ridges. The three rectangles now put their hems in open
sky; the existing rendered gate measures each curtain with scenery present at 1152×648 and
1440×648, checks the director ramp and exact zero-blend/death restoration, and rejects the
late-night boundary that reproduced the scheduling defect. Measured full-strength green
contribution is now 124–128/255 across both night palettes and widths (previously 23/255 in the
occlusion reproduction). The bake, fixed colors, and additive material remain the same.

Preview status is latched at entry and whenever a debug setting is enabled during ACTIVE.
Interval, night-bypass, and accelerated/pinned-biome previews do not initialize a deadline or
credit a completed event. Turning the setting off before completion cannot earn credit.
Ordinary gameplay playtime banking is unchanged; this protects aurora progression, not all
progress during a playtest. Previously triggered previews are not proof that a save changed:
only completed previews reached the completion writer, and the real save has not been repaired.

Completion banks through GameManager before saving both the clock and its next deadline.
IDLE rechecks an unscheduled sentinel, so a reset in the start-screen shop needs no scene reload.
The debug defaults are restored and the temporary logs removed.

### The ribbons

Three curtains as `TextureRect`s in `SkyBackdrop`, between `SkyStars` and `SkyGlow`, driven only
by `apply_aurora(blend, elapsed)`. Both arguments come from the director and **neither may be
recomputed on the far side** — that is what lets `sky_backdrop.gd` keep its promise of having no
`_process` at all, which is what makes it free inside every headless gate.

**The shape was validated before it was written**, by porting the bake to Python and rendering it
against the two night palettes' real gradients. Not a substitute for the engine — it cannot see
draw order, the additive material, or `expand` on a device — but it caught two defects that would
each have cost a play session:

1. **The rays were invisible.** The first draft averaged three sines from one 9–34 range. An
   average of similar frequencies converges on a constant: the term sat near 0.81 across the whole
   width, so there was no striation at all — a smooth ribbon, which reads as fog. A *product* of
   them fails the other way and goes muddy. What works is **four octaves with amplitude falling as
   frequency rises**.
2. **It blew out to white.** Against the palettes as authored — `twilight_blue`'s `sky_top` is
   `(0.26, 0.28, 0.50)`, far brighter than assumed — **4.6% of the screen clipped to flat white**.
   The shipped weights measure peak 1.03 / 0.02% clipped, and that remainder is the hem's own core,
   where a white-hot centre is correct.

**A third finding, and it is a ceiling rather than a bug.** Under additive blending no layer can
*reduce* the sky's blue. Over these palettes (upper-sky blue 0.42–0.54) a fully saturated green is
unreachable by construction. Pulling blue out of the green's own colour moved the hem from G/B 1.26
to 1.53, which is as far as it goes; more brightness does not help, it clips. **If a greener aurora
is ever wanted the lever is the palette's blue, which is a biome change, not a sky one.**

**Why additive.** An aurora emits. Alpha-blended it can only darken toward its own colour, so a
green curtain comes out as flat paint. `BLEND_MODE_ADD` on a `CanvasItemMaterial` is a built-in,
not a `.gdshader`. The trap it introduces is exactly why the night gate exists: additive over a
bright sky blows out, so `debug_aurora_ignore_night` shows a composition the game never ships.

- **`visible = blend > 0.0`, never alpha 0.** A transparent full-screen `TextureRect` still
  rasterises every pixel it covers. At blend 0 this feature is byte-identical to not existing,
  which is what makes it incapable of moving a gate result.
- `mouse_filter = MOUSE_FILTER_IGNORE` on every rect, or they are full-screen input eaters under
  the pause button.
- The texture is baked **once** in `_ready()`, as a `PackedByteArray` handed to
  `create_from_data()` rather than per-pixel `set_pixel()` — that one was a real scene-load hitch.
  The bake is **skipped entirely under `--headless`**.

## The schedule

```
due  <=>  saved_playtime + unbanked_this_run  >=  next_aurora_due_seconds
```

**A stored deadline, not `(aurora_count + 1) × INTERVAL`.** `SaveStore.next_aurora_due_seconds`
carries the full reasoning in the place a reader will hit it.

```
unscheduled (a v3 save, or a reset):  -1.0, and -1.0 is NOT due
scheduled at _ready() or first IDLE after reset:                 total_playtime_seconds       + AURORA_INTERVAL_SECONDS
pushed on completion:                  get_total_playtime_seconds() + AURORA_INTERVAL_SECONDS
```

**The two clocks in those last lines differ on purpose, and getting it wrong re-creates the backlog
inside a single run.** `total_playtime_seconds` is the *banked* total, and `bank_playtime()` only
fires on a `PLAYING -> not-PLAYING` transition — so during a long uninterrupted run it is stale by
the entire run so far. Scheduling at `_ready()` from the bare field is correct precisely because it
runs at scene load with nothing unbanked yet. Scheduling on **completion** from that same bare
field, after a 40-minute unbroken session, writes a deadline already ten minutes in the past and
the next aurora fires as soon as the sky is dark again. **Test the completion path on a run with no
pause in it**, the only case that exposes it.

Completion now banks the unbanked time before its single save, so the persisted deadline and clock remain consistent even if the process exits before a later pause.

**`-1.0` rather than `0.0` is load-bearing.** Zero reads as "due immediately" to any `>=`
comparison, so an unscheduled save would fire on the first frame — the same bug in a new hat.
Absence therefore needs no migration and **no version bump**: a v3 file yields `-1.0` and is
scheduled at load, the same honest reading v2->v3 gave playtime itself. The clock starts now rather
than being back-dated.

**Cumulative playtime comes from `GameManager.get_total_playtime_seconds()`**, which both directors
call. It was computed independently in each of them until the reconciliation — two copies of a sum
whose wrong version (the saved total alone) silently reschedules a set piece. That helper has **no
headless guard of its own, deliberately**; the guard belongs in the callers, and its comment says
why.

### The night gate

The current blended `star_density` must be at least 0.8, and
`BiomeDirector.get_minimum_night_ahead(61, SPEED_BOOST_SPEED)` must also be at least 0.8.
The latter queries the same atmosphere curve at both endpoints and every intervening biome
boundary. Each transition is monotonic, so this bounds the entire interval without advancing
or repainting the biome. At 1000 px/s the shipping bound is 61,000 world pixels.

A deadline reached late in starlit_night therefore waits for the next sufficiently long night.
This is intentionally more restrictive than checking only the launch frame. Accelerated biome
previews use their synthetic cycle speed; a 10-second biome cycle cannot fit a 61-second night
event. Use the rendered gate's fixed-night captures to judge the look quickly, or the explicit
night bypass for a progression-free timing preview (not color approval).

## The calm — in scope, not built

**Owner decision 2026-09-09: the hazards stand down for the duration.** This is what makes the
aurora more than a nice sky, and it is the only part that touches anything outside presentation.

### The two halves are not equally risky, and must not ship together

| | Touches `get_terrain_height`? | Cost |
|---|---|---|
| **No obstacles** | **No.** Obstacles are spawned *nodes* | Spawn suppression plus safe-entry handling for existing nodes |
| **No chasms** | **Yes.** A chasm is geometry | A real decision — two routes below |

**No obstacles needs both future suppression and existing-node handling.** Keep the spawn-slot
check beside `is_lake_world_x`, but define a reserved protected span before the event begins.
Obstacles may already be up to 800 px ahead: skip predicates cannot remove them retroactively.
Start the visual timer only once the approach is clear and the player has entered the protected
span, or explicitly remove affected existing nodes safely. The eventual probe must place an
obstacle just before eligibility and assert on actual remaining bodies.

**Coins and powerups keep spawning.** Only the thing that can kill you is removed. A minute of free
collection while the sky does something is a reward, and suppressing all six spawners the way the
lake does would make the aurora a dead zone six times longer than the lake's.

### No chasms — reservation is the planned route

**Route A — a second write-once range.** `arm_calm(start_index, end_index)`, taking the identical
deal `arm_lake()` takes: the only writer of the range, indices strictly greater than
`highest_cached_segment_index`, **and every index in the range also absent from
`segment_spec_cache`** — `arm_lake()` treats that second check as defensive because the watermark
guarantees it for a single index, but `get_segment_spec()` can populate the cache beyond the
watermark without advancing it, so for a *range* it is load-bearing. Then one more early-out in
`is_chasm_segment_index()`, which is already a pure function of `segment_index` and already gated by
`debug_chasm_disabled`.

Two traps if this route is taken. **Choosing the range must not cache the terrain it is about to
change** — walking the ordinary segment getters forward would populate the spec cache for exactly
the indices the arm then wants to alter, and the arm would correctly refuse. Use a conservative
bound from the minimum legal segment length instead, `ceil(footprint / SMALL_SEGMENT_LENGTH)`, with
the recovery margin **inside** the division. And **never implement it as "no chasms while the
aurora is active"** — a time-conditioned height field is a different value depending on when you
asked, and the four independent samplers would disagree inside one frame.

**Route B was measured and rejected as the default at this duration.** The audit swept 256
seeds × 5,600 segments with real segment lengths and void edges: only 3 of 25,218 gaps reached
61,000 px; the longest was 61,920 px. None included even one current screen (~1,382 world px)
of recovery margin. Eligible-start distance without a margin was 0.000239%, before requiring
night. This sample is not an impossibility proof, but it makes waiting for a natural gap an
impractical cadence. Full results and the reproduction are in
`docs/review/2026-09-09-aurora-audit.md`.

**Route A is planned, not implemented.** Preserve the write-once/write-ahead rules above.
A reservation is not the event start: introduce a pending-entry state, wait for the player to
reach the safe span, and recheck sufficient night there. Size the reservation for travel during
the event plus camera settling/recovery. Never edit already sampled terrain to clear the approach.

Before adding ice or camera consumers, define lake arbitration in both directors: an ARMED or
ACTIVE lake blocks an aurora reservation; a pending or ACTIVE aurora blocks lake arming. Each
deadline remains due while deferred. Reserve this through sibling queries, without another
autoload or a second time-dependent terrain predicate. Keep the implementation and its terrain
probe together in the later calm step; no such range or arbitration exists today.

### How long the calm must be

Sized from the **fastest the player can possibly be moving**, not the fastest they usually are:

```
event duration      61 s        (45 hold + two 8 s fades, as built)
worst-case speed    1000 px/s   (SPEED_BOOST_SPEED, NOT MAX_SPEED's 750)
event footprint     61,000 px
recovery margin     + one screen and change, so the first hazard is not on the fade
```

**Powerups keep spawning during an aurora**, and `SPEED_BOOST_SPEED` is 1000
(`powerup_manager.gd:26`). A band sized at `MAX_SPEED` can be outrun by a player who picks up a
boost late in the hold, who then reaches live terrain while the curtains are still up.

This is a **derived upper bound, not a prediction** — the supremum of distance over the interval.
It is not tight: a boost lasts 3 s, so 61 seconds of continuous boost is impossible and the typical
footprint is nearer 47,000 px. That slack is the point. Over-reserving costs *more calm*, which is
harmless; under-reserving costs a death during the centrepiece.

### Death is never disabled, the hazards are removed

`player.gd:147` states the constraint and it is not negotiable: `has_shield` is obstacle-only, and
`update_fall_death()` and both watchdogs stay untouched, because *a shield that swallowed
fall-death would leave the player falling forever behind the terrain* — worse than the death it
prevented. **A blanket "can't die" flag for the aurora is the same bug wearing a different name.**

With no chasms there is nothing to fall into; with no obstacles there is nothing to hit. The player
genuinely cannot die and not one line of the death path changed — the same reasoning as the lake
locking the jump *input* rather than making jumping harmless. The stall watchdogs stay live
throughout: they catch bugs, not gameplay.

## Making the light reach the whole frame

The owner's ask on 2026-09-09. Three layers, in increasing cost, and **none of them recolours a
gameplay object.**

1. **The sky** — built.
2. **The mountains and the snow: a wash.** A `ColorRect` on a `CanvasLayer` at **-45**, in front of
   the ridges (`ParallaxBackground` is -100) and `SnowDrift` (-50), and **behind every canvas item
   at layer 0**. That number is the entire safety argument: at -45 the ice, coins, obstacles and
   player are *structurally incapable* of being tinted by it, so gameplay objects retain their own colors. Final composited contrast must still be checked: changing the background can reduce readability even when the object color is untouched. **Do not raise it above 0.** Wanted: `MOUSE_FILTER_IGNORE`, a vertical profile
   rather than a flat veil (strongest near the horizon where light would pool), and a hard opacity
   cap so ridge-to-ridge separation survives.
3. **The ground itself: the ice blend.** `TerrainGenerator.set_lake_ice_blend()` is the working
   precedent — a single-entry blend that already lerps ice surface, depth and hue variance
   together, driven by the lake today. The aurora drives the same shape off its own ramp. The ice
   shader already has `gloss_strength`, actively written from the lake blend in
   `refresh_ice_appearance()`. Compose the aurora contribution there; it is not an unused field
   available to a second independent writer. **This is the lever for "the ground catches it too" — not a palette
   field, and not raising the wash layer.**

**What stays uncoloured, and this is a rule not a default:** coins, obstacles and the player.
`CLAUDE.md` — a biome may shift the two objects the player must *read*, never recolour them. The
calm removes obstacles anyway, so the live question is only coins and the player, and both stay.

**Contrast is no longer proven by the palette gates.** `biome_schedule_check` reasons about palette
*data*; the wash changes the background behind a coin without touching the coin's colour. That
readability claim has to be re-checked on final pixels with every layer present, including a player
at glide height. This is not a gate failure waiting to happen — it is a gate that will keep passing
while saying nothing about the case.

### Overdraw budget

`visuals.md` budgets four full-screen alpha layers. Count actual passes and covered area
separately: stars, glow, snow, three curtain draws, the proposed wash, and any lake reflection.
The repositioned curtain rects sum to 1.0 screen area before clipping; their negative tops mean
only about 0.53 screen area is inside the viewport, with bob changing that slightly. Neither
number is a count of compositing passes. The bake uses 576 KiB of raw LA8 data (three
512×192×2 images). Measure the full event on Android before claiming it fits the fill budget.

## The camera

Implemented in slice 9. **The frozen lake still does not zoom** — `apply_lake_framing()` only
lerps the camera's target Y so the shore sits at `LAKE_HORIZON_FRACTION` (0.56). Aurora adds a
separate restrained 1.055× zoom and target-Y framing at 0.59, both blended by
`get_aurora_blend()`.

**A framing lift does not lower the mountains.** Every `motion_scale` in `main.tscn` is `(x, 0)` —
vertical parallax was tried and reverted — so the ridges are **vertically screen-locked** and moving
the camera's target y slides the *terrain* down the screen while the ridgeline stays put. The lift
is still worth having as a composition effect; it just is not the "more sky" lever. **Zoom is.**
`ParallaxBackground.ignore_camera_zoom` defaults to false, so zoom scales the ridges and the
panorama too. Normally that makes zoom the riskier of the two, since base size and zoom are one
decision and only their ratio is field of view — which on an auto-runner is reaction time. **During
an aurora that objection does not apply, because there is nothing left to react to.**

Cheaper than expected: the three live readers of `camera.zoom` (`main.gd:340`,
`lake_reflection.gd:149`, `glide_coin_spawner.gd:218`) all re-read per frame, so an animated zoom
needs no invalidation anywhere.

The implementation preserves all three constraints: glide forces the Aurora camera blend to zero;
the authored zoom is captured in `_ready()`; and the extra zoom filter settles inside the protected
recovery span. `camera_shake_probe` passes on the commit. Because that probe measures position, the
live calm probe separately measures zoom/framing/restoration; owner review still owes the final
motion judgment.

## The headless contract

Every gate instantiates `main.tscn`, so all of this runs on every gate frame.

- `is_headless` computed **locally** from `DisplayServer.get_name()`, never `Services.is_headless`,
  which is assigned in `GameServices._ready()` and can still read false depending on node order.
  `snow_drift.gd` and `sfx_player.gd` both shipped that bug.
- `set_process(false)` / `set_physics_process(false)` **before** the headless return, not after.
- Every dependency `get_node_or_null` + null-guarded; a missing one is a `push_warning` and a
  disabled feature, never fatal. A missing aurora is a missing spectacle, not a broken game.
- **A parse error in any of these hangs the gates rather than failing them.** Run `check.sh`.

**Because the director hard-skips headless, no gate can arm a calm band and no terrain gate can
move.** Read that as regression isolation and nothing more. It is emphatically *not* evidence that
the aurora works — a green `freeze-search` with no band armed has not exercised one line of the
feature. It also means **no headless gate reaches the schedule at all**:
`get_total_playtime_seconds()`, the deadline and the night gate are all invisible to the fast five.
Know which claims a green run is not making.

## Proving the calm

Only if Route A is taken. Route B needs no terrain probe, because it writes no terrain — that is
most of its appeal.

**One new probe, `aurora_calm_probe.gd`,** headless, modelled on `lake_suppression_probe.gd` —
which exists for the identical reason and pins its set piece the same way. It arms a forced band,
snapshots heights and specs before and after, walks the spawners, and drives no-input traversals.

> **A BOOSTED TRAVERSAL PROVES NOTHING ON ITS OWN.** A boosting player is already immune to both
> hazards the calm removes: `obstacle.gd:37` returns early on `player.is_boosting`, and
> `player.gd:355`/`540` keep the grounded gravity-free model on over a void, so they skim straight
> across a chasm. **That test passes on a band with every chasm and obstacle still in it** — the
> "passes with the feature deleted" failure the eighteen archived probes are a monument to.
>
> So the traversal runs **twice**: **ordinary, unshielded, no boost, no input**, which is the case
> that actually asserts the terrain is safe; and **boosted**, which asserts the band is long enough
> — **assert duration coverage, not arrival.** At `t = EVENT_DURATION` the player must still be
> inside the band with the recovery margin in front of them. A probe that only checks "got to the
> end alive" passes on a band half the length it should be.
>
> The direct assertions stay regardless: no chasm segment in the range, and no obstacle **body**
> actually spawned in it. Assert on the spawned node, never on the predicate.

**This is deliberately one probe, not a matrix.** `CLAUDE.md` holds at *"twelve maintained checks,
and only twelve"*, and eighteen archived probes are evidence of what happens to gates nobody
maintains. The scheduling and save cases are better as one manual pass over a **copy** of a real
save.

## What is left

One numbered step at a time, each its own commit, stop for a "go" between them.

| # | Commit | Gates owed |
|---|---|---|
| — | Reconcile the branches | `check.sh` + project import — **DONE 2026-09-09** |
| A | **Ribbons repositioned; aurora coverage added to the existing visual gate. DONE on desktop** | Owner look and device frame times remain |
| B | **DONE: gap sweep makes Route B impractical; Route A planned** | Measurement recorded in the audit |
| C | **No obstacles** — future suppression and already-spawned bodies, coordinated with safe entry | `check.sh`, actual-body assertions |
| D | **No chasms**, by the chosen route (+ `aurora_calm_probe.gd` same commit if Route A) | **`check.sh`, freeze-search, freeze-replay, floor-flicker, chasm, `lake_suppression_probe`**, and the probe |
| E | **The wash** at `CanvasLayer -45` | `check.sh`, `sky_layer_check`, owner look |
| F | **The ice blend** off the aurora ramp | `check.sh`, `ice_look_capture`, owner look |
| G | **The camera** | `check.sh`, `camera_shake_probe`, owner look |
| H | **The achievement** — one `ACHIEVEMENTS` row, one `.connect()` on `aurora_finished` | `check.sh` |
| I | Full-event validation, then `CLAUDE.md` / `visuals.md` / this file | everything, plus the three windowed gates |

**Desktop verification for A is complete.** Owner review and device frame times remain; every later visual step is composed against these curtains.

**D is the only step a physics gate can see**, which is why it is alone in its commit and carries
the whole physics tier.

## Things that break silently

- **Never `Services.x`** — `GameServices.resolve(self)`, null-guarded. The global identifier does
  not exist under `--headless --script` even though the autoload node does.
- **Debug knobs are plain `var`, never `@export`.** An exported bool serialises into `main.tscn` and
  ships silently — the `world_rebase_enabled` regression exactly. Every new knob gets its
  `shipping_values_check` row **in the same commit**, because a plain `var` is invisible to every
  other gate.
- **The interval override must never reach disk.** It is a read-side bypass in `is_aurora_due()` for
  exactly that reason, and both deadline initialization and completion skip preview events. Rewriting the stored deadline
  instead would both persist a playtest cadence into a real save *and* fail to work, since a save
  scheduled hours ago is still waiting on that number.
- **`git status` after ANY engine run.** A settings save rewrites `project.godot` *and* scene files,
  dropping the pins and every comment. `shipping_values_check` text-scans `project.godot`; **scene
  files still have no such cover**, and this feature adds nodes to one. (A plain `--editor --quit`
  import measured **byte-identical** on 2026-09-09, consistent with the 2026-08-26 finding.)
- **`aurora_count` is a statistic, not the schedule.** Anything that reads it as a threshold index
  re-creates the backlog.
- **Achievement ids are save data.** Renaming one un-earns it for everyone. Pick the name once.

## Open, and deliberately not decided yet

- **The reservation implementation.** Route A is planned from the measured gap scarcity; its entry, recovery, and lake arbitration rules above must be enforced by the later terrain probe.
- **Fill rate on a real phone.** The one thing that could genuinely hurt the game rather than merely
  look wrong, and it cannot be answered from a desktop. Measure with the complete event — curtains,
  wash, snow, pickups, moving camera — over repeated events at device resolution.
- **The duration numbers** (45 s + 8 s) are proposed, not measured. Judge in play.
- **Whether the calm should also suppress powerups.** Currently no. A speed boost during an aurora
  is either a great moment or a thing that rushes you through it; watch one before deciding.
- **Whether "waits for night" is too rare in play.** Only playtesting answers it. The fallback is a
  sky-channel override handed through `BiomeDirector.push_palette` so the aurora could pull the sky
  toward night itself — a known road, not a redesign.
- **Ambient audio.** There is no lake sound either, and the SFX pool is five one-shots with no music
  bed. The strongest argument the project has for ambience, and it needs an asset that does not
  exist. Out of scope; worth raising after the visual lands.

---

# Former HANDOFF.md Aurora entries, 2026-09-07 → 2026-09-13

## Aurora look pass — 2026-09-13, READ THIS FIRST

The Aurora is **correct and gated green; what has been iterating is its LOOK**, across six owner
review rounds. Nothing below changed the lifecycle, the terrain reservation, the flight or the
camera. `aurora_calm_probe` last ran PASS at **163,746 assertions** and every `check.sh` in this
pass was 4/5, failing only on the three declared TEMP knobs.

**`art_source/aurora_reference/` (four images) is now the design authority.** The owner generated
them; they are committed. When a look question comes up, open those before guessing — three
separate wrong turns below were settled by them in one look.

### Commits, newest first

| Commit | What |
|---|---|
| `2e158ca` | **`AuroraStreaks`** — occasional light ribbons crossing the view |
| `9383637` | Scenery DARKENS into silhouette; haze alpha rises to kill the sky/ridge seam |
| `8c17299` | Curtain hems back above the scenery (fixes `b22a815`) |
| `b22a815` | Curtain bands given real height; reference images land |
| `e05351b` | Aurora light gets colour range; **wisps switched OFF** |
| `eb72534` | Reflection becomes a true 1:1 mirror |
| `130bf78` | Reflection compression derived per frame so it fills the ice |

### The traps, all earned the hard way

- **`AuroraReflection` compression is DERIVED PER FRAME, never a constant** (`get_fill_compression`).
  The shader samples `mirror_uv.y = waterline - depth * compression`, so the mirror runs out of
  frame at `depth = waterline / compression`. A constant 3.0 meant no reflection could exist below
  screen y 0.79 — an empty lower quarter AND a squashed mirror, from one number. The fill ceiling
  is `waterline / (1 - waterline)`; **1.0 is the target**, not the ceiling — any value at or below
  fills, so take the least squashed one. Ice line moves (camera ramp 0.55→0.59, `expand` per
  device), which is why it cannot be a constant.
- **Curtain hem position and band height are INDEPENDENT.** The hem sits at `AURORA_HEM_BASE`
  (0.84) of the rect measured from its TOP, so **a band is grown by moving its TOP up, never its
  bottom down**. Growing downward dragged all three hems behind the background haze and ice
  panorama, which draw in FRONT of the sky layer — the curtains rendered fine and were simply
  invisible. Keep `T + 0.84 * (B - T)` at 0.176 / 0.117 / 0.077, or re-measure **with the
  background present**.
- **The scenery response is a DARKEN, and this took three tries.** `starlit_night` authors
  `scenery_far` (0.38, 0.44, 0.62) against `sky_horizon` (0.46, 0.52, 0.68) — nearly identical, so
  ridges normally melt into the sky. The Aurora adds green to the SKY LAYER ONLY, so equal
  brightness in different hues meets on a hard polygon edge. Tinting the ridges green (v1) put the
  aurora's hue on rock; brightening them (v2) made a pale lavender slab. The references are
  unanimous: **peaks are DARK silhouettes against a bright sky.** Dark-against-bright reads as
  intentional; equal-brightness-different-hue reads as a seam.
- **Haze ALPHA rises during the Aurora** (0.38 → 0.59, capped 0.78). Deliberate exception to
  `refresh_haze()`'s own "colour only" rule — the thickening veil is what actually dissolves the
  ridge tops. `AURORA_HAZE_ALPHA_GAIN` is the dial for edge softness alone.
- **A hash that passes a distribution test can still be biased where it is USED.**
  `AuroraStreaks` hashed sweep direction: 111/200 below 0.5 over many indices, but an encounter
  only ever plays the **first eight**, and there it gave seven leftward and one rightward — in
  every aurora, forever, since the indices are fixed. Direction now strictly alternates. Check the
  range you actually consume, not the population.

### Disabled, and why — do not just switch it back on

**`AuroraWisps` is OFF** (`WISPS_ENABLED = false`). Owner: "those wisps r terrible". The problem is
the CONCEPT, not the parameters: persistent ribbons hanging at mid-screen belong to nothing — they
never touch the ice, never descend from the curtains, and neither occlude nor are occluded. Tuning
them (three static arcs → six undulating ones) made it worse by drawing the eye. The node is kept
because the likely rework is **vertical shafts descending from the curtains to the ice**, which
reuses its entire structure. `AuroraStreaks` is the counter-example that may work: a streak is an
EVENT that crosses and leaves, not decoration that sits there.

### Open

1. **The wings are still untouched and still blocked** — the owner said a reference image was
   coming and it never arrived. It is the element they have been least happy with. **Ask for it.**
2. **Bloom is an unanswered question, asked twice.** There is **no `WorldEnvironment` anywhere in
   this project** — no glow, no post-process. It is the single biggest remaining "make it GLOW"
   lever and the only item needing an owner decision, because it is screen-space over the WHOLE
   game and the Mobile renderer's most expensive feature. Mitigation is clean: `AuroraDirector`
   flips `glow_enabled` at entry/exit so it costs nothing the other 29 minutes.
3. **Two more reference findings unbuilt:** the ice should be BRIGHTER (pale cyan, sometimes
   lighter than the sky), and the reflection should read as a soft vertical smear of colour rather
   than a crisp mirror of shapes.
4. **`sky_layer_check` is OWED** — on the curtain geometry and on the streaks. It needs a window
   and cannot run headless, so nothing but arithmetic has verified either.
5. The three TEMP knobs are still on. Ship order is unchanged: owner accepts the look → restore
   knobs → `check.sh` 5/5 → three windowed gates → merge.

## Visual pass — 2026-09-12, READ THIS FIRST

The 2026-09-11 audit closed the Aurora's *correctness*. The owner then reviewed it and rejected
its *reach*: **"it just reads as an aurora borealis on top"**. Two screenshots showed why — the
sky carried the whole event while ~45% of the frame (the protected flat) was a dead dark slab,
with an unlit band between them. Nothing was broken; the light simply stopped at the horizon.

**Owner verdicts, and they are binding:**

| Verdict | Status |
|---|---|
| Light must reach the world — **keep the curtains as-is** | Done, this pass |
| Wisps read as plain static lines | Done, this pass |
| Wings need a rework and should sway | **BLOCKED on the owner's reference image — do not start** |
| **The grounded blade glow is right — do not touch it** | Honoured; see the tree-order note below |

| Commit | What |
|---|---|
| `ea2a932` | Comment-only: the wisps were never "rebuilt each frame" |
| `5bcfdc4` | Wash reaches the screen floor, drifts and breathes |
| `00e521f` | **`AuroraReflection` — the sky mirrored into the ice** |
| `401a4d8` | Wash ceiling 0.15 → 0.34 |
| `00c469f` | Six undulating wisp ribbons |

**The reflection added NO shader.** It reuses `shaders/frozen_lake_reflection.gdshader`, whose
lake-specific behaviour was already entirely in uniforms. It is a sibling node, **not** a second
mode on `lake_reflection.gd` — that file derives visibility from one director's phase on purpose.

**Two numbers not to "fix" later:**
- **`AURORA_COMPRESSION` 3.0**, against the lake's 1.0. The lake mirrors 1:1 because it reflects
  pines at its own shore; the Aurora reflects the SKY, which at 1:1 lands at screen y 0.85–1.05 —
  off the bottom of the frame. Restoring 1.0 makes the reflection invisible.
- **`AuroraReflection` sits BEFORE `AuroraBladeGlow`** in `main.tscn`, where `LakeReflection` sits
  after. The glow's lower half is below the ice line, the one band the quad paints. Swapping those
  two siblings eats the glow the owner explicitly asked to keep.

**The `project.godot` strip recurred on 2026-09-11**, from an owner play session — not from a gate.
`check.sh` and `--script` runs were both measured clean again in this pass. `git status` after ANY
play session, still.

Verified this pass: `aurora_calm_probe` **PASS, 163,746 assertions**, identical to baseline, both
live cases, flight and camera metrics unchanged. `check.sh` 4/5, failing only on the three declared
TEMP knobs. **Both gates are headless and `AuroraReflection` disables itself there** — they prove
the lifecycle is intact, not that the mirror renders. That remains owner review.

## Audit pass — 2026-09-11, READ THIS FIRST

The Aurora branch was audited end to end against `CLAUDE.md`, this file, `aurora_borealis.md` and
the `2026-09-09` review. **No defect was found in the Aurora implementation itself.** All six
findings of the 2026-09-09 audit are genuinely fixed in code (verified by reading it, not by
trusting the doc): occluded green hem, night-duration eligibility, preview progression writes,
reset rescheduling, completion clock banking, and the gate that never tested an aurora. Write-ahead
terrain purity holds, lake/Aurora arbitration is symmetric, and the new Player flight state leaves
the boost/chasm velocity model untouched.

What the audit *did* find was a missing gate, three unrun regressions, and doc wording pointing at
the wrong file. All three are now closed:

`claude/aurora-reconcile` is at **`8396247`**, pushed to `origin`, working tree clean:

| Commit | What |
|---|---|
| `357f957` | `AuroraDirector.MIN_RUN_TIME_SECONDS = 130.0` (the lake's number) + TEMP-wording corrections |
| `8396247` | Comments-only: why `ENTRY_WAIT_DISTANCE` is 10,000 and must not be trimmed |

**The run-time gate.** `is_aurora_due()` now refuses before 130s into a run. This is about the
SPEED RAMP, not pacing: the flat is cut at `MAX_SPEED` while the event ends on a 61s clock, so a
still-accelerating player covers less of it than it was sized for — entering at t=20s (~530px/s)
left ~28,000px of dead protected flat. `FrozenLakeDirector` has had this gate since it shipped; the
Aurora had none. The check sits BELOW the preview branch on purpose, so a 10s review interval still
bypasses it and no second knob enters `shipping_values_check`'s table.

### Verified, with numbers — do not re-run these to "make sure"

| Gate | Result |
|---|---|
| `aurora_calm_probe.gd` | PASS, **163,746** assertions, both live cases, credited completion intact |
| `freeze-search` | PASS — 40 trials, **0 stalls, 0 near-stalls**, worst `min_motion` 8.36px |
| `freeze-replay` | PASS — 60,000 frames, `no_freeze`, **0 stall recoveries** |
| `floor-flicker` | PASS — **6 seeds × 20,000 frames, 0 recoveries, 0 stuck**, max forced snap 1.86px |
| `check.sh` | 4/5 — fails **only** on the three declared TEMP knobs |

The three physics regressions had been owed since **slice 2**, when the Aurora was terrain-only.
Slice 11 then added a whole Player movement state and slice 9 changed camera framing, and neither
re-ran them. They are green now. `git status` was checked after every engine run — no scene or
`project.godot` strip.

### Accepted costs — DOCUMENTED, NOT BUGS. Do not re-open.

- **A protected flat is always longer than its event.** ~59,846px reserved against ~45,750px of
  presentation, so **~12s of empty obstacle-free flat follows the fade** and ~3s precedes it. This
  is the price of guaranteeing the calm on immutable terrain.
- **`ENTRY_WAIT_DISTANCE` (10,000px) must not be trimmed.** The GLIDE sets its floor, not the
  boost: `GLIDE_DURATION` 7s × `MAX_SPEED` = 5,250px, plus ~750px because `begin_aurora()` needs
  `is_on_floor()` and a glide can expire at altitude. Worst case ~6,000px; 10,000 is ~1.7×. Sizing
  it against `SPEED_BOOST_DURATION` (3s) argues for halving it and **is wrong — that mistake was
  made and corrected in this pass.** Undershooting fails `has_duration_room()` at entry, which
  skips the aurora *and* still spends the whole reservation.
- **A failed entry spends the whole reservation** with no event. Rare (reserve and entry are ~3s
  apart and share `is_sky_ready()`) and unfixable after the fact, since arming is immutable.

### Left before ship, in order

1. Restore the three knobs: `biome_director.gd` `debug_biome_seconds` → `0.0`;
   `aurora_director.gd` `debug_aurora_interval_override` → `0.0`, `debug_aurora_ignore_night` → `false`
2. `./scripts/check.sh` must then be 5/5
3. The three windowed visual gates at shipping pace (`sky_layer_check`, `ice_look_capture`,
   `biome_contact_sheet`) — these need a window, no `--headless`
4. Owner motion/audio review + Android speaker/headphone/frame-input testing

Minor, unfixed, low value: `aurora_wisps.gd:4` says the wisps are "rebuilt each frame" — they are
built once and only repositioned. `frozen_lake_director.gd:218` reaches for `"../AuroraDirector"`
by hardcoded string rather than an `@export NodePath` like every other dependency in that file.
`AuroraWings` may flicker for a few frames during the `is_aurora_flight_landing` gap around t=45.

## Current Aurora state — 2026-09-11

The complete Aurora encounter is implemented on `claude/aurora-reconcile` (feature work landed
through `9db1fb9`; see the audit section above for the current head). It is a 61-second, once-per-run event due every 30 minutes of
cumulative playtime, gated to past 130s into a run (`MIN_RUN_TIME_SECONDS` — the flat is cut at
`MAX_SPEED` but ends on a clock, so an accelerating player leaves dead flat behind) and by enough
remaining night for the full encounter. The current scene is
intentionally in **TEMP preview mode**. The three knobs are committed as SOURCE defaults, not as
scene properties — `main.tscn` holds none of them, because all three are plain vars the editor
cannot serialise. They are `BiomeDirector.debug_biome_seconds = 10.0` (`biome_director.gd`),
`AuroraDirector.debug_aurora_interval_override = 10.0` and
`AuroraDirector.debug_aurora_ignore_night = true` (`aurora_director.gd`). It is reviewable now but
not shippable until those three are restored to `0.0`, `0.0`, and `false` respectively.

One director clock owns the entire presentation: protected write-ahead flat and recovery; new
obstacle/boost/glide suppression; night/lake arbitration; curtains, world wash and ice response;
camera framing; blade glow; snow; rear wisps; six-feather wings; one bounded 96px crest flight;
the Music-bus ambient bed; and the once-only `under_the_aurora` achievement. Existing visible
objects are never removed; coins and non-movement powerups continue. The player returns to normal
grounded input before recovery ends.

Latest evidence: `aurora_calm_probe.gd` passes 163,746 assertions across preview and credited
encounters; `sky_layer_check.gd` passes native at 1152×648 and 1440×648; the 20,000-frame ordinary
camera/movement regression passes. `shipping_values_check.gd -- --allow-temp` reports only the
three deliberate preview values. Remaining work is owner motion/audio taste review and Android
speaker/headphone/frame-input testing, then restoring the shipping defaults and running the clean
shipping gate. Do not add another Aurora subsystem until that acceptance pass identifies a concrete
issue.

## Latest — slice 12: Aurora ambient bed

Aurora now has a dedicated 12-second seamless stereo ambient loop generated locally from periodic
harmonics (24kHz PCM, 1.10MiB), so it has no licensing dependency. `AuroraAudio` owns one player on
the existing Music bus rather than occupying the six-voice SFX pool. The director's existing ramp
controls gain, capped at 0.55 linear over a source measuring −14.5dBFS peak / −21.6dBFS RMS. The
pause screen's already-wired Music control is now visible.

The native gate proves forward looping, bounded crest gain, pause/resume, exact zero state and
death cleanup. The WAV's last-to-first sample step matches its ordinary sample progression because
every carrier and amplitude envelope completes an integer number of cycles. Final sound taste and
Android speaker/headphone balance remain owner/device review, not something numeric gates settle.

## Latest — slice 11: bounded Aurora crest flight

The wing apparition now carries the skater through one guided crest arc over the already protected
flat: five seconds rising, roughly eight near 96px altitude, and five seconds descending. Horizontal
speed and the base speed ramp continue unchanged. This is a dedicated Player state, not ordinary
glide or a powerup; it has a hard 96px target, 260px/s vertical cap, no collision bypass and no
invulnerability. Jump input is neutral only during flight/landing, then ordinary input resumes.

The complete calm probe passes 163,746 assertions across preview and credited encounters. It
measures 1,079 bounded flight frames, 95.999px peak altitude, exactly one landing, buffered-input
rejection, unchanged horizontal speed, safe camera placement, death cleanup, continued coins,
camera framing and fully restored grounded movement
before recovery. Fast gates pass except the three intentional TEMP preview values; the rendered
gate passes at both widths/night palettes. Owner feel and Android testing are still required.
The established 20,000-frame ordinary camera/movement regression also passes unchanged.

## Latest — slice 10: visual Aurora wings

A brief six-feather light apparition now opens behind the grounded skater from 20–51 seconds,
reaching full strength for the Aurora crest. It is deliberately visual only: no levitation,
movement state, collision, input, speed, particles, trail history or independent timer. The
immutable `Line2D` geometry is built once and the existing Aurora clock changes only transform and
opacity. It stays structurally behind Player and TerrainGenerator and hides while airborne.

The rendered gate passes at both widths/night palettes, measuring 65/255 isolated visibility,
paused-frame identity, bounded timing, draw order and cleanup. Captures are in
`art_source/audits/aurora-wings-slice/`. The full calm probe passed 159,415 assertions at this
slice. The controlled flight and ambient bed were deliberately added in later, separately verified
slices 11 and 12.

## Latest — slice 9: Aurora camera composition

Aurora now eases the authored camera into a restrained 1.055× zoom while lifting the terrain line
from its ordinary ~0.55 position to 0.59 of screen height. The director's existing appearance
ramp drives both changes; Main remains the sole camera writer, captures the scene-authored zoom,
and restores it before the protected recovery ends. Glide has explicit priority. There is no
rotation, shake, input change or second camera controller.

The complete calm probe passes 159,415 assertions and directly measures the zoom cap, 0.590
settled framing, zero rotation, glide priority and restoration. The 20,000-frame camera-shake gate
and windowed Aurora composition gate also pass. Fast gates pass except the three intentional TEMP
preview values. Owner motion/taste and device review remain owed.

## Latest — slice 8: sparse rear wisps

Three small tapered `Line2D` arcs now drift near the skater, structurally behind Player,
TerrainGenerator and every gameplay object. Shapes are immutable and built once; the existing
Aurora clock changes only line position/alpha, with edge fading at the bounded wrap. No particles,
textures, shaders, trail history, per-frame arrays or rebase state were added.

The windowed gate proves draw order, cleanup, pause stability, drift and 43/255 isolated visibility
at both widths/night palettes. Captures are in `art_source/audits/aurora-wisps-slice/`. Foreground
wisps were deliberately skipped to protect pickup/player readability. Owner/device review is owed.

## Latest — slice 7: Aurora completion achievement

The first complete, non-preview encounter now grants `under_the_aurora` (“Under the Aurora”).
`AchievementManager` listens to the existing `aurora_finished` signal and remains the only
achievement writer; AuroraDirector has no achievement dependency. The existing toast displays it,
and the open v3 achievement dictionary needs no version bump.

The isolated lifecycle probe proves preview, partial and death cases grant nothing, a real finish
persists/emits once, and repeated finish is idempotent: 152,095 assertions pass. Fast functional
gates pass except the three intentional TEMP preview values. No gallery or reward was added.

## Latest — slice 6: snow gathers and releases

The existing snow emitter now composes biome, glide and Aurora into one bounded density target.
Aurora adds a broad clock-derived crest, peaking at 1.45× the active night biome (roughly 81 or 102
visible flakes) within the already allocated 126-flake pool. There is no new emitter, allocation,
material, velocity mutation or timer. Snow stays on `CanvasLayer -50`, behind all gameplay objects.

The windowed gate checks cleanup and the 1.3–1.6× target bound at both widths/night palettes; fast
functional gates pass except the three intentional TEMP preview values. Owner/device motion and
fill-rate review remain owed. Wisps, camera, flight, achievement and sound are still separate.

## Latest — slice 5: grounded blade glow

Aurora now has one local connection to the skater: a compact code-built cyan-green halo and short
core at the real terrain contact, aligned to the slope and hidden whenever the player is airborne.
It uses the existing Aurora ramp and adds no shader, particles, trail history, timer or movement
state. The rendered gate isolates its pixels from the sky/world response and checks cleanup at both
widths and both night palettes. Captures are in `art_source/audits/aurora-blade-slice/`.

Wisps and snow remain separate because they add overlap and GPU/particle cost. Camera and flight
remain the highest bug-surface candidates. TEMP preview values remain on for owner review.

## Latest — slice 4: the light reaches the world

Aurora's existing ramp now drives one `CanvasLayer -45` vertical wash and a composed ice response.
The wash remains behind every gameplay object; the ice change stays inside
`TerrainGenerator.refresh_ice_appearance()`, alongside biome and lake inputs. It adds no shader,
timer, movement change or per-chunk state. The upper ice catches emerald/cyan while the deep body,
tile, cracks and rolling terrain remain readable.

The windowed sky gate passes at both widths with sky, wash and ice active, including restoration,
draw-layer and input-transparency assertions. Fast gates pass except for the three intentional TEMP
preview knobs. Captures are in `art_source/audits/aurora-world-slice/`. Owner/device review is still
owed. Camera, snow, blade/wisp atmosphere, wings/flight, achievement and sound are still separate;
camera/flight remain the highest bug-surface options and should not be bundled into this slice.

## Latest — slice 3: live calm safety is in

The Aurora now reserves a write-ahead flat passage and enters it through a small lifecycle:
`PENDING_ENTRY` waits until there is room for the whole 61-second presentation, then `ACTIVE`
runs it, and `RECOVERY` carries the player safely beyond the reserved boundary. A late entry,
daylight, a visible conflicting hazard, boost, or glide skips the appearance without changing
already-written terrain.

The reservation starts beyond the actual collision extents of existing obstacles and powerups;
those visible objects are never removed. New obstacles and boost/glide pickups are suppressed
inside the passage. Existing boost or glide is allowed to end before entry; trick boosts use the
same guard. Coins, other powerups and jumping remain available. Aurora wins when it is due at
night, while an already armed or active lake blocks Aurora; later lake/Aurora reservations choose
non-overlapping spans.

`aurora_calm_probe.gd` now proves geometry, entry rejection, death handling, two full live
encounters (preview and real credit), pause stability, spawn resumption and lake arbitration:
152,086 assertions headless and 14,708 native. The windowed sky gate also passes. Native shutdown
still reports its existing audio-harness resource warning. Camera, ice/world lighting, snowfall,
wings/flight, achievement and sound remain separate future slices. TEMP preview switches remain on.

## Latest — slice 2: flat foundation, not live yet

Owner accepted the sky slice. Added `arm_aurora_flat(length)` and `aurora_calm_probe.gd`.
One immutable future flat segment; no sampled terrain changes. Eight geometry seeds / four
ordinary-and-boosted collision traversals pass, including both seams, duration coverage, Y rebase,
and bounded chunks. Freeze search/replay, floor contact and chasm regressions pass.
Live Aurora still uses ordinary terrain: safe entry, obstacle/powerup policy and arbitration are
next. Geometry currently permits only one of lake/Aurora per scene, conservatively.

Found and fixed headless death saving run stats despite playtime banking being disabled. The
void mutation test may have changed live coins/best stats; user informed, no pre-test copy to
restore. New probe detaches Services and tests the headless guard with an in-memory save; final
checks use a separate test project/user directory. Details and results are in the latest section
of `docs/development/aurora_borealis.md`. TEMP and project settings are unchanged.

## Latest Aurora slice — directional sky arrival

Owner authorized incremental implementation after the experience brainstorm. First slice adds
`shaders/aurora_curtain.gdshader`: right-to-left reveal and internal folds using existing curtain
textures. Windowed sky check passes with new reveal/pause/deformation assertions at both widths.
Four fast checks pass; shipping-values reports the three intentional TEMP overrides plus four
project pins already missing at turn start. Project settings were not changed.

Updated direction: no slowdown; sound deferred; flat protected passage and brief Aurora-wing
flight are the proposed next safety/design work, with boost/normal glide excluded during the
encounter. Terrain, camera, flight, ice light and local VFX are not implemented by this slice.
See the current checkpoint in `docs/development/aurora_borealis.md`; older plans below are history.
Owner motion review and Android performance are still required; do not treat rendered visibility
as acceptance of the completed look. TEMP remains on.

## Aurora — current state and next work, 2026-09-09

The audit-fix implementation is complete but **uncommitted**. It fixes curtain occlusion,
night-window eligibility, preview progression writes, reset rescheduling, completion clock
banking, and missing rendered coverage. Temporary preview defaults and diagnostic prints are
gone. The current tree passes the fast five; the rendered sky gate now includes the curtains at
1152×648 and 1440×648; 76 native lifecycle/prediction assertions also pass. See
`docs/review/2026-09-09-aurora-audit.md` and its `art_source/audits/` evidence.

The visual core is now ready for an owner look and a device check. The calm, wash, ice light,
camera, and achievement are **not built**. This is deliberate: the calm would touch terrain and
must not be folded into a visual follow-up.

### What the owner should test now

1. Review the curtain composition in a running game: the green hem should sit above the opaque
   ridge line, with readable rays rather than a flat glow. Judge its height, strength, and motion
   on a real night palette. The rendered captures are evidence, not final taste.
2. Run the current build on the target Android device through several appearances and watch frame
   pacing and heat. Desktop rendering established visibility, not mobile fill-rate safety.
3. If using a temporary preview knob, remember it is now progression-isolated: an event started
   under interval/night/biome preview settings cannot initialize or advance aurora progress. A
   night bypass is useful for checking state flow, not for judging colors authored over night.

### Recommended next steps

1. Accept the current visual/scheduling fixes and commit them as their own reviewable change.
   Do not mix the pending calm work into that commit.
2. Make a **design-and-probe pass only** for the calm. Route B, waiting for a naturally clear
   stretch, was measured at 0.000239% eligible distance before recovery margin and is not viable.
   Route A needs a write-once, write-ahead terrain reservation, safe entry, existing-obstacle
   handling, and lake arbitration designed and tested together.
3. Only after that proof is accepted, implement the calm in one terrain-focused slice with its
   probe and physics regression tier. The wash, ice light, camera, and achievement then remain
   separate, low-coupling visual/product slices.

Do not treat the old “What to do next” section below as current; it predates the audit fixes and
gap measurement. It is retained as history.


## From "Start here" — the reconciliation note, 2026-09-09

> ## 🌌 THE AURORA BOREALIS — TWO BRANCHES RECONCILED 2026-09-09. Read this first.
>
> **Branch: `claude/aurora-reconcile`**, cut from `claude/aurora-borealis-audit-fqbpzh` with
> `claude/aurora-borealis-design-1rpnt8` merged into it. Both of those had independently planned
> AND part-built the aurora, with different plans, different phase numbering and two different
> "phase 1"s. **Neither is the trunk any more. Do not commit to either.**
>
> **The plan is `docs/development/aurora_borealis.md` (464 lines), rewritten as one document.**
> Read it before touching aurora code. Any older copy that reasons about a third `.gdshader`, an
> `AuroraSky` CanvasLayer at −190, or eligibility by *palette identity across cycle slots 5–7* is
> superseded — those were real designs on one branch and the other branch built something better.
>
> ### What is built, and what it does
>
> | | State |
> |---|---|
> | `AuroraDirector` — clock, phase machine, one ramp | **BUILT** |
> | Three code-built curtains in `SkyBackdrop`, additive `CanvasItemMaterial` | **BUILT.** Nobody has seen them in the engine |
> | Schedule — stored deadline, 30 min, night gate | **BUILT**, reconciled today |
> | The calm — no obstacles, no chasms | **IN SCOPE, NOT BUILT.** The live work |
> | Wash + ground catching the light | **IN SCOPE, NOT BUILT** |
> | Camera, achievement | Planned, not built |
>
> ### The owner decisions that settled the merge, 2026-09-09
>
> - **30 minutes**, not 60. The other branch's "three times the lake's twenty" reasoning is gone.
> - **The hazards stand down** during an aurora — obstacles and chasms both. One branch had built
>   the feature around *"the aurora must never arm terrain"*; that rule is real but narrower than
>   it was written, and the plan now splits the calm into its two very different halves.
> - **The light should reach the whole frame** — "everything bright and beautiful". Sky, then the
>   mountains via a wash at `CanvasLayer −45`, then the ground via the `set_lake_ice_blend()`
>   precedent. **Never coins, obstacles or the player**, and the wash never rises above layer 0.
>
> ### Two real defects were fixed in the merge, not carried
>
> 1. **The schedule would have paid out a backlog.** `(aurora_count + 1) × INTERVAL` is safe for
>    the lake only because `frozen_lake_count` and `total_playtime_seconds` were born together at
>    v3. The aurora lands in saves that **already hold hours**, so every threshold up to the
>    player's lifetime total was already crossed — roughly one aurora per run, back to back, until
>    the count caught up. Replaced by a stored deadline, `SaveStore.next_aurora_due_seconds`, with
>    `-1.0` as an explicit UNSCHEDULED sentinel because `0.0` reads as "due now". **No version bump
>    needed** — absence resolves correctly.
> 2. **The playtime sum had been written twice.** `AuroraDirector` carried a verbatim copy of the
>    lake's old function. Both now call `GameManager.get_total_playtime_seconds()`.
>
> Also fixed while merging: the interval override used to be consulted by the code that WRITES the
> deadline, which would have persisted a playtest cadence into a real save — and would not even
> have worked, since an already-scheduled save ignores a shortened interval. It is a read-side
> bypass now.
>
> ### Gates — RUN, 2026-09-09, on this Mac
>
> **The project import their branch owed is done**, and `project.godot` came back
> **byte-identical** (consistent with the 2026-08-26 measurement that import is not the stripping
> trigger). The new `aurora_director.gd.uid` is committed — the repo tracks all 67 of them, and
> that branch shipped a `.gd` without one because it had no Godot.
>
> **`./scripts/check.sh` — 5/5 PASS**, including `shipping_values` now instantiating
> `AuroraDirector` for its two knobs.
>
> **Godot IS available to a session running on the owner's Mac** (`/Applications/Godot.app/...`).
> The older note here saying every gate is owed to the owner because the session has no binary is
> true of a *container* session only — **check before assuming**, and discharge in-session.
>
> ### What to do next
>
> 1. **Look at the ribbons in the engine, and run `sky_layer_check.gd` WITHOUT `--headless`.**
>    This is the one owed thing, it is cheap, and everything later is composed against it. The
>    curtains were validated by a Python render of the real palettes — good enough to catch two
>    real defects, not good enough to judge a sky.
> 2. **Measure the chasm-gap question** before building the calm's second half. It decides between
>    a second write-once terrain range (Route A) and simply not starting unless the stretch ahead
>    is already chasm-free (Route B, which touches the height field not at all). The plan has the
>    arithmetic sketch; **do not pick by argument.**
> 3. Then the calm's free half (obstacles), then the wash, then the ground.
>
> ### How this work runs
>
> - **One numbered step at a time, committed alone, then stop for an explicit "go."**
> - **No headless gate reaches the aurora's schedule at all** — the director hard-skips headless,
>   so `get_total_playtime_seconds()`, the deadline and the night gate are invisible to the fast
>   five. Green proves the feature broke nothing; it proves nothing about the feature.
> - **Verify claims, don't inherit them.** Every number that turned out wrong across both branches
>   was wrong because someone reasoned from a plausible constant instead of reading it.

## Latest session — 2026-09-07, aurora Phase 2a (the ribbons)

> ### ✅ RUN 2026-09-09 — import and the fast five are done; the windowed gate is not
>
> Written without a Godot binary, then discharged on the owner's Mac during the branch
> reconciliation: **project import done** (`project.godot` byte-identical afterwards),
> **`check.sh` 5/5 PASS**. **Still genuinely owed:**
> **`sky_layer_check.gd` WITHOUT `--headless`**, because this is a sky change the owner has not
> seen and that gate is the one built for a new soft layer in this exact stack (it caught a glow
> contributing 11/255 and being invisible). `git status` after the import.

Three curtains as `TextureRect`s in `SkyBackdrop`, between `SkyStars` and `SkyGlow`, driven only
by `apply_aurora(blend, elapsed)` — the seam Phase 1 left. `AuroraDirector` passes both values;
**`sky_backdrop.gd` still has no `_process`**, which is what keeps it free inside the six
headless gates.

**The shape was measured before it was written.** The bake was ported to Python and rendered
against the two night palettes' real gradients. Not a substitute for the engine — it cannot see
draw order, the material, or `expand` on a device — but it caught two defects that would each
have cost a play session:

- **The rays were invisible.** Averaging three sines from one narrow frequency range converges
  on a constant (~0.81 flat), so there was no striation at all — a smooth ribbon, which reads as
  fog. A product of them fails the other way and goes muddy. Four octaves with amplitude falling
  as frequency rises is what works.
- **It blew out to white.** The first weights looked right against a *guessed* dark sky. Against
  the palettes as authored — `twilight_blue`'s `sky_top` is `(0.26, 0.28, 0.50)`, much brighter
  than assumed — **4.6% of the screen clipped**. Shipped values measure peak 1.03, 0.02% clipped,
  and that remainder is the hem's own core.

**A ceiling worth knowing before anyone tries to make it greener:** additive light cannot reduce
the sky's blue, and the upper night sky is blue 0.42–0.54. A fully saturated green is unreachable
over these palettes by construction. Pulling blue out of the green's own colour got the hem from
G/B 1.26 to 1.53; brightness does not help, it clips. The only remaining lever is the palette,
which is a biome change, not a sky one.

**Additive is a `CanvasItemMaterial`, NOT a third `.gdshader`** — the two-shader budget is
untouched. It is also why the night gate is load-bearing rather than cosmetic: additive over a
bright sky blows out, so `debug_aurora_ignore_night` shows a composition the game never ships.

**One cost fix:** the bake is ~295,000 pixels against the starfield's 300, so the whole
construction is **skipped under `--headless`** (gate output is byte-identical either way — the
bands are built `visible = false` and the director hard-skips headless) and the image is filled as
a `PackedByteArray` through `create_from_data()` rather than per-pixel `set_pixel()`.

**Phase 2b (a shader) is expected, not avoided** — the owner said so explicitly. 2a is a first
draft whose job is to be judged. `aurora_borealis.md` records the three rules that keep 2b a
drop-in: timing stays in the director, `apply_aurora()` stays the only seam, and the layout stays
data on the node rather than baked into the texture.

**Phase 3 (the achievement) is next and is two edits**, both in `achievement_manager.gd`.

## Latest session — 2026-09-07, aurora Phase 1 (no visuals)

> ### ⚠️ NOTHING HERE HAD BEEN RUN — **discharged 2026-09-09, see the top of this page**
>
> Kept as the record of how it shipped. The container this was written in had no Godot binary, so
> **`./scripts/check.sh` did not execute and the engine had never parsed any of it.** Both steps
> below were done during the branch reconciliation: import clean, `check.sh` 5/5. The two steps
> were:
>
> 1. **A project import.** `class_name AuroraDirector` is new, and `shipping_values_check.gd`
>    now does `AuroraDirector.new()` — which cannot resolve until the class is registered.
>    CLAUDE.md keeps import as a manual step for exactly this. `scripts/systems/aurora_director.gd.uid`
>    will be generated by that import; it is not in the commit.
> 2. **`./scripts/check.sh`.** Expect `shipping_values` to be the one that moves — it gained two
>    knobs.
>
> **`git status` after the import**, per the standing rule: a settings save rewrites
> `project.godot` *and* scene files, and this commit adds a node to `main.tscn`.
>
> The physics tier is **not** owed — nothing here touches physics, collision or spawning. The
> visual tier is not owed either: Phase 1 draws nothing.

Phase 1 is the director and its bookkeeping, deliberately with **no visuals at all**, so the
schedule can be proven before any pixel is argued about.

| File | Change |
|---|---|
| `scripts/systems/aurora_director.gd` | New, ~250 lines, modelled closely on `frozen_lake_director.gd` so the pair reads as siblings |
| `scripts/systems/save_store.gd` | `aurora_count` — read, written, reset. **No version bump**; reasoning on the field |
| `scripts/systems/biome_director.gd` | `get_night_amount()`, one line, its only new public surface |
| `scenes/main.tscn` | `AuroraDirector` node under `Main` |
| `scripts/debug/shipping_values_check.gd` | Both new debug knobs, same commit as the knobs |

**The four owner decisions it was built to** (2026-09-07): sky-only with no forced terrain
segment; **night only**, gated on blended `star_density` >= 0.8; a fixed green/violet identity,
never per-biome; and **code-built ribbon textures first with a shader explicitly still on the
table** — the owner's words were that they are willing to spend time and usage on this part, so
the cheap version is a first draft to be judged, not the intended end state. Phase 2 in
`aurora_borealis.md` says how to build 2a so 2b can replace it without touching anything else.

**Two things were dropped from the plan as unnecessary, and both are simplifications:** the
proposed chasm-proximity check and the airborne check in the arm condition. The lake needs its
equivalents because it commits geometry *and* locks input; this locks nothing, so a bad moment
to start just means the player looks up a second later — and the 8s fade-in is longer than a
chasm takes to clear. Adding them would have meant new `TerrainGenerator` API for a problem
that does not exist.

**`push_blend()` is the only seam Phase 2 arrives through.** It calls `apply_aurora(blend)` on
`SkyBackdrop` if that method exists and does nothing otherwise — so **Phase 1 landed without
editing `sky_backdrop.gd` at all**, and a Phase 1 regression cannot be hiding in the sky stack.

**Where the numbers are soft:** `AURORA_DURATION_SECONDS` (45) and `AURORA_FADE_SECONDS` (8) are
proposed, not measured. Judge them in play. Their ceiling is the biome — a night biome holds
~100s at cap, so the 61s total fits inside one comfortably, and much past ~90s risks the sky
brightening underneath the ribbons.

## Latest session — 2026-09-07, aurora planning pass

**No code changed. Docs only.** `docs/development/aurora_borealis.md` was rewritten from a
sketch with three open questions into a four-phase implementation order. What the audit found,
shortest first:

- **The record was wrong in three places.** This file and `background_differentiation.md` both
  called the aurora "fully planned"; its own doc ended on three unresolved questions and a
  sequencing note. Both claims are corrected.
- **The sequencing prerequisite is stale and is now closed on evidence.** It said the "ice
  canyon walls / shard spires" background work had to land first. The background shipped
  2026-08-24 as the baked panorama, the iceberg line was deleted the same day, the raster route
  failed three times, and the only live remaining option (procedural ridge reshaping) changes
  the **silhouette**, not the sky. `SkyBackdrop` is layer -200 and `ParallaxBackground` is -100,
  so the ribbons sit behind every silhouette by construction. **The two are independent and can
  be done in either order.** Worth one line of owner confirmation, not a blocker.
- **One question the old plan missed, and it is the important one: night-only or not.** The
  trigger is cumulative playtime; sky colour is a function of distance. They are independent, so
  as designed the first aurora can fire over `pale_morning` — which reads as a rendering bug,
  not a spectacle. The recommended gate needs no new data: `star_density` is already authored
  per palette and already blended every frame, and a threshold of >= 0.8 on the blended value is
  exactly the two night biomes.
- **The "forced flat segment like the lake's" question is settled by architecture, not taste.**
  `CLAUDE.md` makes `arm_lake()` the sole writer of `get_terrain_height`'s one permitted runtime
  input. A second terrain-arming set piece puts a second writer on that invariant. Sky-only
  means `terrain_generator.gd` is not in the diff at all, which is what makes this the cheapest
  major feature left.
- **Recommended against starting with a third shader.** `SkyBackdrop` already builds three of
  its four layers in code as `Gradient`/`Image` bakes; ribbons are the same class of object as
  the glow. Try code-built LA8 bands moved by anchor first — no new shader, no imported asset,
  no art pipeline. If the owner says it reads flat, shader #3 then has a real justification and
  a reference to beat.

**Gates: none run this session, and none could be** — this container had no Godot binary
(`/Applications/Godot.app/...` is a macOS path). No code changed here, so nothing was owed, but do
not read "docs only" as "verified". **A desktop session CAN run them; the fast five were run on
2026-09-09** — see the top of this page.

**All four Phase 0 decisions were answered the same day, and Phase 1 was written** — see the
section directly below.

> ## THE REVIEW LISTS ARE CLOSED — 2026-09-03
>
> **Both of them.** There is no outstanding review debt, and the next session should pick a
> feature rather than go looking for one here.
>
> - **The 2026-08-24 review is finished.** Two items were killed on evidence rather than done
>   (#9 Godot 4.7.2, #8 process priorities), and the last one, **#7 segment-cache pruning, is
>   closed won't-fix on a measurement**: ~1.06 KB per segment, ~3.7 MB per hour, and bounded by
>   the *run* rather than the session because restart reloads the scene and clears all four
>   caches. Pruning would re-derive baselines by backward subtraction, which is not bit-identical
>   to the forward addition that built them — a `get_terrain_height` purity violation traded for
>   3.7 MB/hr. The table and the one safe future option are in that review under #7.
> - **The 2026-09-02 audit is finished.** #1–#10 closed on 2026-09-03, **#12's four minor items
>   closed** the same day, and **#13/#14 are recommended to stay open permanently** — they are
>   size observations with no defect behind them, and both put a load-bearing file
>   (`terrain_generator.gd`, `main.tscn`) in the blast radius of a pure tidying change. Do them
>   bundled with work that already touches those files, never as a cleanup pass. Reasoning is
>   under "Why 13 and 14 should stay open" in the audit.
> - **Still genuinely open, and tiny:** two run clocks, `Main.elapsed_time` and
>   `SpeedManager.elapsed_time` (audit #11's other half).
>
> The audit found one real shipped defect — both coin spawners placing 192px too high — and the
> gate shape that hid it. That is written up below and is the most useful thing either list
> produced.

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

> ## ✅ THE PLAYTEST PHASE IS CLOSED — 2026-09-03
>
> It ran from 2026-08-26 and every finding it produced is fixed: four visual ones on 08-27 (the
> green, the moon, the night sky) and the coin-height defect on 09-03, all owner-verified in
> play. **It is no longer a standing phase that outranks other work** — the project is back to
> "pick something and do it".
>
> **What it taught is the part to keep, and it held every single time:** these arrive sounding
> like taste complaints and were *all* measurable causes. Sample the colours, profile the
> texture, print the radial falloff, measure where the node actually lands — do not tune by eye
> and do not reason from the constant. Twice the obvious reading of the symptom was wrong ("the
> green looks bad" was **not** a hue problem; the disc under the moon was **not** the sky), and
> both times the first fix had to be redone.
>
> **If the owner starts reporting findings again, that outranks everything here again** — it is
> observed-broken behaviour and the rest of this file is review debt. Ask which items are
> reproducible if it isn't stated; `FREEZE_REPRO` in `debugging.md` is the standing rule for
> anything that smells like a stall.

**What is actually next — the list is one item long now:**

1. ~~Godot 4.7.2 (review #9)~~ — **DECLINED 2026-08-26**, see below. Don't re-raise it.
2. ~~**#8, `main.gd` process priorities**~~ — **downgraded 2026-08-26**, close to a no-op.
   Read the finding below before spending the physics gate suite on it.
3. **The aurora borealis** — the game's namesake, and with both review lists closed it is the
   only thing left in view. **The planning pass is DONE (2026-09-07)** —
   `docs/development/aurora_borealis.md` is now a phased implementation order, and its stale
   background prerequisite was checked and closed on evidence (see the 2026-09-07 section at the
   top of this file). **It is still not ready to code**: four decisions in that doc's "Phase 0"
   are the owner's and they change what gets built. Get those four answered, then Phase 1.

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
