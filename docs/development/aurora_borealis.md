# Aurora borealis — the plan and the state

## Slice 10 — visual wing apparition implemented

A brief six-feather light fan now appears behind the grounded skater from 20–51 seconds, reaching
full strength for the broad Aurora crest. This is the safe wing-visual fallback, not flight: it
does not touch position, velocity, collision, speed, input or player state, and it hides whenever
the skater is airborne. Six immutable `Line2D` shapes are built once; the existing event clock
changes only their transform and opacity. There are no particles, trails, timers or rebase state.

The windowed gate proves behind-gameplay ordering, zero cleanup, bounded timing, paused-frame
identity and 65/255 isolated visibility at 1152×648 and 1440×648 across both night palettes.
Captures are in `art_source/audits/aurora-wings-slice/`. The complete calm probe remains green at
159,415 assertions. Actual controlled flight remains unbuilt and is now an explicit optional
follow-up, contingent on accepting this visual direction before taking on movement risk.

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

**Updated direction:** no actual speed reduction; audio deferred until the owner supplies it.
Keep sky/world/ice light, camera, snow and achievement. Explore a reserved **flat** protected
passage, suppress boost and ordinary glide during the encounter (including trick-earned boost
and existing effects/pickups at entry), and develop the signature as skating → brief controlled
Aurora-wing flight → skating. Controlled flight is still an unbuilt, separately proved candidate;
the safer wing-visual fallback while skating was implemented in slice 10. Existing normal glide
is not a stable-height flight implementation. Obstacle-only event protection is a possible alternative to suppression,
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
