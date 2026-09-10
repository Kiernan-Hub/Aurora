# Aurora borealis audit — 2026-09-09

**Follow-up:** all six implementation findings below were subsequently addressed, still uncommitted. [Fixes and verification](/Users/kjh/Documents/aura/art_source/audits/aurora-2026-09-09/fixes/README.md). This report and its code line references describe the pre-fix revision; the calm remains unbuilt.

The implemented feature is not ready to sign off. Its main green curtain is largely hidden by scenery, the night gate does not protect the event's duration, and there are persistence and reset defects. The remaining calm plan also needs revision before implementation.

Audited `claude/aurora-reconcile` at `d29012e`, the implementation and reconciliation history, and the working-tree changes. Initially the latter were the two 10-second overrides; temporary director logging was added by another session during this audit and is included below. No gameplay code, settings, scenes, or existing edits were changed by this audit.

Scope included the director, all curtain construction and animation, biome blending, scene wiring, cumulative clock and banking, save migration/reset/completion, pause/death/restart, both set-piece directors, obstacle/terrain interfaces, achievement wiring, validation scripts, and the reconciled plan and handoff.

## Findings in the implementation

### 1. P1 — The scenery hides the main green curtain

[Band placement](/Users/kjh/Documents/aura/scripts/systems/sky_backdrop.gd:155) puts the green texture rectangle between viewport fractions 0.06 and 0.58. Its bright hem is approximately 84% down that rectangle, around screen y=0.50 before waves and bob. The opaque ridge stack begins much higher. All bands draw behind it.

This is visible in the actual Godot Mobile renderer, not just inferred from constants. At full blend, elapsed=8 s, on `starlit_night`, the green band alone contributed a maximum of **23/255** with scenery, versus **131/255** with only the parallax scenery hidden. Its mean absolute RGB contribution fell from **4.3846 to 0.0745**, a roughly **98.3% reduction**. At elapsed=36 s its visible peak was only 18/255. Teal and violet contribute more of the visible effect; the defining green hem and rays are behind the ridges.

Evidence: [normal frame, green band only](/Users/kjh/Documents/aura/art_source/audits/aurora-2026-09-09/bands_true_8_0.png), [same frame with parallax scenery hidden](/Users/kjh/Documents/aura/art_source/audits/aurora-2026-09-09/bands_false_8_0.png), [all three curtains in the normal scene](/Users/kjh/Documents/aura/art_source/audits/aurora-2026-09-09/night_1152_on.png).

Reposition/reshape the curtains against the real open-sky area, then verify their individual contribution with scenery present. Increasing brightness alone does not expose an occluded hem. No shader rewrite is necessary to address this.

### 2. P1 — An eligible start can leave most of the event over dawn

[The phase machine](/Users/kjh/Documents/aura/scripts/systems/aurora_director.gd:188) checks darkness only in IDLE. ACTIVE unconditionally plays the remaining 61 seconds. The comment that a 61-second event fits inside a roughly 100-second biome “even if” it starts partway through is false.

Reproduced with shipping timing and no night bypass: rotation 0, biome world x=582,000, and the deadline already due. The event starts at night amount **0.8573**. Eight seconds later, at 750 px/s, night amount is **0.4899** while aurora blend is **1.0**. At 20 seconds it is fully `arctic_dawn` (**0.28**), and the aurora stays at full blend through 53 seconds.

Require sufficient remaining night for the event's maximum travel, or explicitly control the sky/fade when night ends. The current test answers only whether this instant is eligible. The uncommitted 10-second biome cycle makes this defect particularly obvious, but it also exists at shipping values.

### 3. P2 — Debug sightings still change persistent progress and scheduling

The [read-side override](/Users/kjh/Documents/aura/scripts/systems/aurora_director.gd:298) avoids directly storing a 10-second interval, but it still reaches the normal [completion writer](/Users/kjh/Documents/aura/scripts/systems/aurora_director.gd:335). That increments `aurora_count`, advances the deadline, writes the save, and emits the ordinary completion signal.

Reproduction: banked time=100, existing deadline=1900, run elapsed=71, interval override=10. Completing the preview persisted **count=1 and deadline=1971**. This contradicts the comment that nothing reaches disk; once the achievement is connected, previews can also award it.

Latch whether a sighting is a preview and keep its completion out of progression, or isolate preview saves by design. Merely restoring the knob afterwards does not undo the saved changes.

### 4. P2 — Resetting from the start screen disables auroras for the next run

[Reset](/Users/kjh/Documents/aura/scripts/systems/save_store.gd:253) writes `next_aurora_due_seconds=-1`. Scheduling happens only in the director's `_ready()`, which has already run when the start-screen shop opens. Closing that shop and pressing Start uses the same scene.

Reproduced through the actual GameManager shop/reset/start callbacks: state=PLAYING, elapsed=1900, night amount=1, **deadline=-1 and due=false**. It stays unscheduled until a scene reload, regardless of how long the player survives. This differs from a fresh install and delays the first post-reset event by an entire run plus the new interval.

Notify the director on reset or initialize an unscheduled IDLE deadline through an idempotent path that also works after `_ready()`.

### 5. P2 — Completion saves a deadline against a clock it has not saved

[Completion](/Users/kjh/Documents/aura/scripts/systems/aurora_director.gd:350) correctly uses banked plus unbanked time to calculate the deadline, but `save_to_disk()` serializes only the banked total. If the process terminates before a later pause/death banks the run, the persisted completion survives while the time underlying its deadline does not.

Native reproduction: banked clock=36,000, uninterrupted run=2,400. After completion and reloading the file, clock=**36,000**, deadline=**40,200**. The next event needs **4,200 seconds**, not 1,800. A normal focus-out or death banks time and avoids this; the defect is the inconsistent completed-event snapshot on an unclean exit.

Bank the current run through GameManager before the existing completion save, keeping its banking watermark synchronized. Do not simply add the elapsed time to SaveStore independently.

### 6. P2 — The required visual gate never tests an aurora

[The layer table](/Users/kjh/Documents/aura/scripts/debug/sky_layer_check.gd:90) contains glow, celestial body, stars, sky tint, and ice effects. It contains no aurora bands, and the harness never calls `apply_aurora()` or forces a sighting. It pauses after a 90-frame warmup, well before a normal event.

The unmodified gate passed **9 palettes / 44 layer measurements** in this audit while the green-occlusion defect remained. Headless gates also intentionally skip the director. Thus the handoff's required `sky_layer_check` run is regression coverage for existing layers, not proof that the ribbons work.

Extend the existing rendered gate to drive the full aurora ramp and measure the curtains against the real scenery. Include a zero-blend comparison, night-boundary case, and ordinary/wide viewports. This can remain one maintained visual gate.

## Uncommitted state

- [Aurora interval override](/Users/kjh/Documents/aura/scripts/systems/aurora_director.gd:114) and [biome duration override](/Users/kjh/Documents/aura/scripts/systems/biome_director.gd:233) are both **10.0**, versus shipping **0.0**. They are plain runtime values and are not limited to debug exports. **Shipping-values fails on exactly these two knobs.** Keep them for an intentional preview, but do not ship them.
- The newly added `_debug_print_timer` and IDLE/ACTIVE diagnostic prints run in release builds too. The existing shipping gate does not detect these prints. Remove them or guard them with `OS.is_debug_build()` before shipping. The label `aurora_bands_ready` currently checks only whether `apply_aurora` exists, not whether any bands were built or are visible, so a true log value cannot diagnose the composition issue above. The later ACTIVE log does inspect band 0, but visibility, alpha, and a nonzero rectangle still do not prove that scenery leaves it exposed.

## Findings in the remaining plan

These are implementation risks in the proposed work, not claims that the unfinished calm/wash/camera already exists.

### Natural clear stretches are too rare for the proposed duration

Measured Route B with the real terrain generator, shipping chasm placement, real segment lengths including oversized hills and drop chasms, and distances from one void's far edge to the next void's near edge. The sweep used **256 deterministic seeds**, **5,600 segments per seed**, and **25,218 inter-void gaps**.

Only **3 gaps** reached 61,000 px. The maximum was **61,920 px**; **none** reached 61,000 plus the current roughly 1,382-world-pixel screen width. Without any recovery margin, the eligible-start distance fraction was **0.0000023927**, or **0.000239%**. This is before requiring simultaneous night, and excludes forced lakes. It is a sample, not a proof that no seed can ever qualify.

The plan's suggested cheap route is therefore not a practical default at the stated upper bound. Retaining a minute of guaranteed calm calls for the carefully reserved range, or a deliberate change to duration/protection requirements. Do not implement repeated long lookahead queries every frame while hoping a suitable gap appears.

### “No obstacles is one term” omits hazards already spawned

[The plan](/Users/kjh/Documents/aura/docs/development/aurora_borealis.md:210) discusses skipping future slots only. ObstacleSpawner already has active nodes up to 800 px ahead, and the aurora currently starts immediately on eligibility. A spawn predicate cannot remove those nodes; the player can still hit one during arrival.

Define the protected range and entry transition, including existing obstacles. Either reserve the range early enough that none are ever placed there, clear the affected nodes, or wait until the entry is demonstrably safe. Test actual bodies, including one spawned just before eligibility. The issue applies to both chasm routes.

### Reservation, night eligibility, and set-piece overlap need a shared entry rule

Route A reserves terrain beyond the cache watermark. Starting the 61-second timer at reservation time would leave the approach outside the protected band. The event should start on safe entry, with darkness revalidated there. Existing sampled/cached terrain must never be retroactively changed.

Neither director currently arbitrates with the other. Their stored/cumulative clocks can both be due on the same run, so overlapping lake and aurora states are possible. Before adding ice/camera writers, define mutual exclusion or explicit composition for both ARMED and ACTIVE lake states. Preventing one director from overwriting the other's ice ramp is necessary; merely mentioning that the events “should not overlap” does not implement that rule.

### Budget and ice claims need correction

- The overdraw paragraph counts the three curtains as one layer and omits the full-screen star TextureRect. Their rectangles cover approximately **1.26 screen areas in aggregate** before clipping/bob, not one; a literal pass count and a full-screen-equivalent fill estimate are different measures. Count actual overlapping passes and measure the complete stack before claiming the four-layer budget is met. This audit does **not** establish that the phone GPU budget is exceeded.
- Three 512×192 LA8 textures use **589,824 bytes (576 KiB)** of raw image data, not the claimed approximately 295 KB. That latter number is the pixel count. GPU storage may differ.
- `gloss_strength` is already written by `TerrainGenerator.refresh_ice_appearance()` from the lake blend. It is not an unused future hook. A separate aurora contribution must be composed there deliberately rather than treated as a free second writer of lake state.
- The wash section first claims the unchanged palette contrast floors remain sufficient, then correctly says the final composited background invalidates that assurance. Keep the latter rule: unchanged coin color does not imply unchanged contrast.
- Several comments still say once per hour and that viewport dimensions are unset. The current interval is 30 minutes and the base viewport is pinned. These are documentation corrections, not separate runtime findings.

## What worked and what was verified

| Verification | Result |
|---|---|
| Current working tree, `check.sh` with writable log path | 4/5 pass; shipping-values fails on the two deliberate 10-second knobs |
| Isolated copy with committed knob values restored | 5/5 pass |
| Existing rendered `sky_layer_check`, Godot 4.7 / Mobile / Metal / Apple M4 | Pass: 9 palettes, 44 layer measurements; no aurora coverage |
| Temporary direct-method checks | 50 assertions pass: legacy scheduling, deadline persistence/idempotence, due boundary, banked/unbanked arithmetic, ramp endpoints, terminal completion, abort, reset sentinel, band construction, horizontal overscan, hidden/input-transparent controls |
| Native scene pause/death | Active elapsed remains 20.0 while paused; death hides all bands and grants no completion |
| Aurora on/off captures | Both night palettes and dawn, 1152×648 and 1440×648; visible differences measured |
| Zero-blend restoration | Rendered output exactly matches the no-aurora baseline |
| Actual three-band bake | About 22.6 ms on this Mac; not a phone benchmark |
| Chasm gap measurement | 25,218 gaps; result above |
| Whitespace diff check | Clean |

The new deadline migration avoids the old lifetime-backlog problem, and the shared GameManager arithmetic avoids pause double-counting. The ramp, death cleanup, additive material construction, horizontal coverage, and input filtering behaved as intended. The calm, wash, ground light, camera framing, and achievement remain explicitly unimplemented; their absence is not misreported here as an accidental regression.

Engine execution used a temporary copy with SaveStore paths redirected to `/private/tmp/aura-aurora-audit/`, so feature probes did not mutate the player's real save. The normal gate runner initially crashed on its sandbox-inaccessible default log path; redirecting the log resolved that. Native rendering required execution outside the filesystem sandbox. Physics regression gates were used as regression evidence only; no calm terrain is implemented for them to validate.

Physical Android fill rate, thermal behavior, and the complete future event remain unverified. No broad physics sweep was warranted for this read-only audit of an implementation that does not yet change terrain or movement.

## Evidence and next steps

The [evidence directory](/Users/kjh/Documents/aura/art_source/audits/aurora-2026-09-09/README.md) contains screenshots and temporary probe sources, under the existing `art_source/.gdignore`. They are audit reproductions, not additions to the maintained test suite.

Fix and remeasure visible curtain placement first. Then resolve night-duration, reset, and preview/completion persistence behavior, and add actual aurora coverage to the existing visual gate. For the calm, use the measurements above to make the reservation decision explicitly, with safe entry, existing-obstacle handling, and lake coordination designed together. Nothing in this audit requires a third shader, another autoload, or a new global progression system.
