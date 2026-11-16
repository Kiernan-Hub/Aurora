# Handoff

## START HERE — where the work stands, 2026-11-16

**To continue: you are on branch `play/next`. Owner requested a commit and push of all current
phone-review changes on 2026-11-16 for backup; `main` is untouched.** Current validation is listed below. Read this section
and "Next actions"; the rest of the file is reference.

**Owner likes the collection/customizations and current visual additions, including the latest
chest/mission pass.** Requested slightly more upward lake spray, now adjusted. Unreviewed
terrain/pacing and other gameplay feel remain unapproved.

### Latest owner review / current priority

**Latest correction — continuous overlapping B (2026-11-16, review pending).**
Owner clarified that there must be **no pause**: "one long fluid motion"; as one foot is
almost back, the other should already push backward. This supersedes earlier requests or
interpretations mentioning rest, a settle phase, a held extension or completing one foot's
return before the other leg starts.

- The default **B - Continuous** preserves the4.6s full cycle /2.3s alternating cadence.
  Each foot drives backward over1.33s, then flows directly into a1.24s low return. The next
  leg starts when the returning foot is about88% home, overlapping for0.276s. There is no
  extension hold or stop-and-wait handoff. Cosine easing replaces the endpoint-heavy quintic
  sweep on this default. Quiet upper body and low recovery remain; gameplay physics unchanged.
- Preview: `art_source/ui_review/2026-11-16-continuous-handoff.mp4` (original B vs new default).
  Normal skating and MeltView share it. Phone remains disconnected; install later over USB.
- Motion regression explicitly checks opposing foot velocities during the overlap and bounds
  any near-still interval to4/120s rather than accepting smooth-but-paused trajectories.
  All six standard gates pass (125s), including21 headless cases; all12 rendered cases
  and all three visual checks pass. One rendered lake-exit run timed out; its repeat passed
  with no production changes.
- On entry, `project.godot` had only the known editor rewrite (removed pins/comments and
  key reordering). Restored the committed viewport/physics pins under CLAUDE's standing rule.

**Previous direction — B with reference-based refinement (2026-11-16, review pending).**
Owner prefers B Long push to the later7.2s version and requested real skating references,
a modest B refinement and an in-game trial. Default is now **B - Refined glide**.

- B's cadence stays close:2.3s per alternating stroke (was2.1s),4.6s full cycle. Each stroke
  has a0.64s drive,0.87s extended glide,0.67s low foot return and0.12s transfer. The free
  leg finishes extending while the other blade supports it; recovery lift envelope drops17→8 source
  pixels, upper-body rocking is halved and the knee loads then rises gently into the glide.
  The previous B and sustained versions remain preview references. No physics/effect changes.
- Reviewed two public Pexels clips frame by frame and read primary coaching guidance.
  YouTube/browser playback could not be accessed; do not claim those tutorials were watched.
  Sources and the distinction between observation and animation interpretation are recorded
  in `docs/research/skating_motion_reference.md`. No third-party video/art was added to the repo.
- New comparison: `art_source/ui_review/2026-11-16-refined-b.mp4` (original B vs refined B).
  The shared rig updates normal play and MeltView. Phone remains unplugged/unchanged;
  USB installation is deferred as requested. High-glide milestones are unchanged.
- Motion/phase regression passes across all six styles and five skins: maximum joint step
  1.242 source px at120Hz, zero planted-blade height error. All six standard gates pass (122s), as do all12 rendered cases and all three visual checks.

**Previous build — sustained strokes and high-glide milestones (2026-11-16). Desktop review
pending; phone unplugged. Owner explicitly deferred USB installation until later.**

- **Skating rhythm revised:** the old opposing sweeps read as `1 2 1 2`. Owner's target is
  `1 2 2 2 2 3`: one long deep push/stroke, steadily bring that foot back, briefly rest, then
  alternate — "just like irl". The new default completes one leg's entire phrase while the
  other supports it. Each3.6s phrase is62% backward drive (~2.23s),32% gradual lifted return
  (~1.15s),6% settle (~0.22s); a full two-leg cycle is7.2s. The supporting blade stays planted.
  The same continuous rig/art,72 vertices and three draw submissions remain; physics is unchanged.
  Preview: `art_source/ui_review/2026-11-16-sustained-stroke.mp4` compares the prior B attempt
  with the new rhythm, enlarged plus all five characters at normal game size. A/B/C remain
  reference attempts, not approved choices. That build defaulted to the sustained stroke; refined B now supersedes it.
- **Glide milestones built:** a full high glide uses the existing Really? qualification,
  >=6s uninterrupted held ascent and >=3,000px actual climb. There is no literal height ceiling.
  The **10th** grants **"still??"**; the **50th** grants **"fine, here you go"** and one
  **Ultra Mega Super Duper Chest**:1,000 coins plus three Aurora rewards, unique unowned finds
  while any remain (each exhausted reward falls back to200–300 coins). These are provisional
  tuning choices offered to the owner, not a new spawn tier. Existing Aurora art/reveal reused.
- **Durability:** optional Save v5 `high_glide_count` persists each qualifying flight once,
  together with any new achievement flags and loot in one atomic write. Failure rolls count,
  flags, wallet and finds back together; no toast or receipt is emitted until success.
  Previously owned Really? establishes one known ascent; earlier uncounted flights cannot be
  reconstructed. Reset clears the count; Stats shows it. No run-score or mission-coin credit.
  The50th chest's contents bank immediately; GameManager queues only its run-end reveal.
  Quitting before that reveal cannot lose the loot; reveal taps never pay again. The visual
  receipt is session-only, like other chest reveals. No new global, shader or effect system.
- **Owner's description to retain:** 1=push,2=in process of pushing,3=rest; preferred phrase
  `1 2 2 2 2 3 | 1 2 2 2 2 3`. Merely slowing the same loop misses the request.
- **Validation so far:**21 headless regression cases,12 rendered cases and all three visual
  checks pass. New cases check complete phrase order/support,10/50 thresholds, failed-save
  retry, unique bundle loot, JSON/reset/migration and no double payment at death/opening.
  All15 full gates pass (222s). No engine setting pins changed.

- **Stronger skating options (2026-11-16, rhythm revision now requested):** owner found the first
  continuous rig too subtle and requested more forceful backward pushes and longer strokes.
  Comparison offers A Strong (1.8s per alternating push), B Long push (2.1s), C Deep push
  (2.4s), alongside the previous 1.4s. Foot sweep grows from25 to42/47/53 source pixels,
  with deeper loading, a forward lean and a clearer lifted recovery. B was the source default;
  the phone still has the previous continuous build. No gameplay/physics changes or new art.
  Preview: `art_source/ui_review/2026-11-16-skating-options.mp4` (and GIF).
  `scripts/debug/skating_preview.gd` is a reusable, export-excluded comparison tool; it draws
  enlarged motion plus all five characters at normal game size without touching saves.
  Motion regression now samples complete cycles of every style/skin, checking continuous
  joints, fixed bone lengths, coasting, >40px stronger sweeps and planted blade contact.
  Validation:19 headless and11 rendered cases pass, as do all three visual checks. Stronger
  strokes maintain planted blade height exactly; maximum joint step is0.967 source px at120Hz.
- **Really? is approved.** The portal is a welcome addition but remains provisional and needs
  substantial polish. Owner wants Aura to stay clean, magical and elegant; flag feature growth
  that adds performance cost. Fixing existing behavior takes priority over adding modes/items.
- **Still Water exit bugs reproduced:** old reflection painted over hills beyond the shore
  (4,941 / 7,921 changed pixel samples outside the lake at two aspect ratios). A single touch or
  keyboard press at exit was dropped. The spike approach guard also accepted takeoff inside a
  jump-locked lake while the spike itself stood beyond the boundary.
- **Fix implemented:** reflection uses a fixed lake surface and is clipped to its world-X span
  with a 128px inner edge fade. Full-screen geometry/backbuffer path is retained. Controls return
  on the final 1,500px of flat ice, when the exit fade starts; spike placement requires its complete weak-
  jump takeoff span to be dry. New18th headless regression and10th rendered case cover these
  failures. Full 15 gates pass (230s); all 10 rendered cases pass, including zero painted
  samples outside the lake and successful touch/key exit jumps. All three visual scripts pass, including Aurora reflection with lake clipping opt-in.
  Verified APK exported and installed over USB. Existing gameplay saves remain in place.
- **Spray revised again:** upward kick 36–120px/s, narrow near-vertical fan, drag 55–95 and
  lake-only lift −22. Same70 glints, .90s lifetime and sprite size. Ordinary landing bursts keep
  their previous motion. The earlier20–90px/s adjustment was still too low for the owner.
- **First continuous skating pass (superseded in source; still on phone):** owner rejected the weighted four-pose
  attempt as jerky and asked for “oneeee twooooo” strokes. `SkaterRig` now deforms the existing
  rest artwork every render frame: two IK legs, rigid blades, gentle weight shift and smooth
  coasting transitions. A 2.8s cycle alternates long pushes. All five characters and MeltView
  share it. Parent AnimatedSprite2D carries outfits, shields, slope/trick tilt and squash;
  headless keeps its original sprite. Gameplay physics/hitboxes and raster art are unchanged.
  Bounded cost: 72 vertices, 80 triangles, three submissions per drawn skater, no new textures
  or effect systems. Legacy SpriteFrames retain original timing for fallback/menus.
  Motion/lifecycle tests pass: 19 headless cases, 11 rendered cases and all three visual checks.
  Native pixel checks confirm all five outfit masks and inherited shield tint. All15 full gates
  passed (225s). APK verified, installed over USB and launched; Aura-only focused screenshot
  confirms the start screen and existing mission progress. APK increase: 8,361 bytes (~8 KiB).
  The old timing GIF is rejected; new preview is
  `art_source/ui_review/2026-11-15-continuous-skating.gif`.



### Phone-review continuation

- Installed a separate **Aura Playtest** (`com.kiernan.aura.playtest`), exported from a temporary
  copy. Its save is isolated from the existing Aura app. APK: `aura-playtest.apk` (ignored).
- **Desktop test audio:** owner reported painfully loud test SFX. Keep automated previews
  at Master -24 dB (in memory), or use `--audio-driver Dummy`; never change the saved volumes.
- **Phone access constraint from the owner:** USB only, Aura only. No other app or unrelated data;
  no wireless debugging. Check Aura Playtest is foreground before screenshots.
- Owner requested immediate max speed in dev mode, tap-to-open chests, and reported releasing
  Pause sometimes activated Home. Dev runs now start at 750 with encounter clocks still at zero;
  normal runs retain the speed ramp. Death-screen chests now wait for a tap per reveal.
- Pause touch bug reproduced with rendered input: showing the menu during the button's down
  signal lets the same touch activate Home on release. Main now consumes the press before opening
  the menu. `regression_probe --ui-only` covers touch/mouse, quick/held Pause, fresh Resume,
  dev speed and chest interaction; run with a renderer, not headless.
- **Chest collection built:** nine permanent finds (three skate trails, three outfit colours,
  three display-only ice charms). Skaters → Chest finds shows the shelf and outfit/trail pickers.
  Normal chest weights: small coins 40%, larger coins 20%, jackpot 5%, skater 5%, cosmetic 30%.
  Cosmetics cannot repeat while any remain unowned; exhausted item/skater rows pay a jackpot.
  One existing FlightTrail draws equipped streaks near the blades, and a small outfit shader
  replaces clothing hues while preserving hair/skin. No collision or movement changes.
- **Save v5:** v4 cosmetics/selected_cosmetics plus mission ID, progress and completion count.
  Older progress carries forward; new fields default to the first mission with zero progress. Chest finds ride record_run's existing single write. Equip writes
  roll back on failure; reset clears finds and picks. `collection` regression covers migration,
  malformed data, serialization, unique rolls, ownership, independent equip and reset.
- **Visual pass built:** generated closed/open ice-and-gold chest art, six small UI glyphs,
  distinct trail icons, larger collection cards with explicit Equip/Equipped/Collected states,
  lock badges, a primary-action button style, and Sora display headings. The run HUD/debug
  overlay is hidden on menus. Source art/prompt: `art_source/chests/`; reproducible small
  sprites: `build_chest_sprites.py`. Preview: `art_source/ui_review/2026-11-15.png`.
- **Chest tiers:** Normal 70% (small gold glow), Rare 25% (larger blue glow, 60% cosmetic
  chance), Aurora 5% (distinct purple art and rotating teal/violet ring; guarantees an unowned
  cosmetic, or jackpot after exhaustion). Normal cosmetic chance is 30%. Tier survives actual
  spawn/collect/death/reveal; collision and spawn cadence unchanged. Dev mode cycles all three
  tiers, with a seed-dependent starting tier. Source/prompt: `art_source/chests/AURORA_PROMPT.md`.
- **Persistent missions:** one goal at a time: earn 100 coins, travel 2,000m, collect 3 chests,
  smash 3 geodes (only with owned Slam). Targets rise gently to at most 3x. Start/Pause show
  the goal and Rare reward; a compact HUD shows progress. Progress banks on pause/focus loss
  and death using existing writes. Completion remains pending across sessions until the next
  death awards one Rare chest alongside physical chests, then advances the goal. Reveal taps
  never grant rewards. Stats includes completed missions; reset clears them.
- **Validation:** full 15 gates passed (227s). All seven rendered regression cases and three
  visual checks pass. Mutation checks detect pause double-credit and dropped pickup tiers.
  The rendered test accounts for the existing settings write on Resume separately from banking.
  APK packages v5/tier scripts and font license; source art is excluded. Tier/mission additions
  add 78,981 bytes (~77 KiB) over the previous visual build.
- **Phone:** continuous-skating update installed over USB; Aura Playtest process and focused
  start screen verified. Existing mission progress remains visible. Screenshots must check the
  focused window, not merely a resumed activity; no capture or tap without confirmed Aura focus.



- **Lake spray adjustment:** owner asked for a little more vertical motion. Kick changed
  16–78 → 20–90px/s, direction closer to upright, fan 46° → 36°. Existing drag, lift, chip
  count and lifetime stay the same. LandingBurst explicitly overrides these throw parameters.
  Before/after rendered lake captures confirm active emission and a modest taller trail.
  All three visual checks pass; updated Android build installed over USB.
- **The Melt built (owner review pending):** a rare optional jump-in portal at a seeded
  4–7 minutes into a run (once per run); dev mode tries from 12s, still awaiting a legal slot.
  Portal uses the chest spawner's flat/jump/void/hazard checks and rechecks the corridor at
  collection. A separate one-button ice-platform course has crumbling ledges and accelerating
  melt, Rare chest at 15s and Aurora at 30s. Three tested jump timings survive about 36.5s;
  the rift closes at 60s at latest. Bonuses bank immediately, without changing run score or
  coin missions. Results include a saved personal best (also in Stats).
- **Run suspension:** GameManager.BONUS pauses the normal world intact. Only the isolated
  model/view runs; Pause/Back/focus loss stop it, Resume returns to BONUS. Home/Restart abandon
  the round and rebuild normally. A successful result returns through a two-second countdown
  to the exact frozen pose/clock with input buffers cleared. No terrain teleport or new autoload.
- **Reward durability:** SaveStore.bank_bonus writes coins, finds and personal best together,
  restoring all changed fields on failure. The prepared chest roll survives retries; an
  already-paid result cannot pay twice. `best_melt_seconds` is an optional v5 statistic, default0.
- **“Really?” achievement:** at the end of one glide, >=6s of uninterrupted held ascent and
  >=3,000px of actual climb earns the existing toast. There is no height ceiling and movement
  is unchanged. Per-tick displacement is rebase-safe; headless triggers cannot save. A real
  rendered flight earned it at ~7.02s / 4,065px. Short or interrupted flights do not qualify.
  Failed achievement writes now roll back ownership and suppress the toast so a later glide
  can retry. This also fixes the same existing failure case for the other achievements.
- **Review/checks:** two read-only subagents reviewed gameplay and saving. Their findings led
  to entry-time safety rechecks, real scheduled-portal overlap coverage and failed-save retry
  coverage. All15 headless/physics gates pass (231s), including17 regression cases. Nine rendered cases
  pass, as do all3 visual checks. APK grows by25,480 bytes (~25 KiB). USB installation
  completed successfully; own app process verified.


### What `play/next` contains (26 commits on top of `main`)

Merged in, built 2026-10-29 and never played:
- **Island chasms** (`terrain/island-chasm`): every 4th chasm window, two floating floes over one
  long void, three gaps (`terrain.md`, "Island chasms").
- **Three elements** (`elements/black-ice-geode`): black ice, slam geodes, ice vents (Hazards table).
- **The UI pass** (`ui/stats-sounds-theme`): menu sounds, one theme, Stats screen, distance, four
  run achievements, four bought skaters, sparkle colours (`architecture.md`).

Built 2026-11-15, in commit order:
1. **Bug fix, predates the branch:** a world rebase on the frame the player lands from a drop
   chasm dropped them through the floor. `Main.apply_world_rebase()` now calls
   `force_update_transform()` on every chunk (`terrain.md`, "The plunge").
2. **Mountains:** ×3/×4 hills and valleys from segment 60, same 20.13° slope (`terrain.md`).
3. **The plunge:** a 1,400px drop chasm every 4th chasm window. Cadence: drop, hazard, plunge, islands.
4. **Late tiers:** tier 7 (6:30) five mixed pairs, tier 8 (8:00) three triples, room floor 2.0s
   (was 2.5), reached about 11:00. Every row has 9+ frames in the fairness proof.
5. **HUD:** run distance beside the clock (`TimerLabel`, widened).
6. **Bug fix, also reachable on `main`:** any fall over ~1,440 px/s could tunnel through the floor
   (a drop-chasm landing, a slam). `Player.move_and_slide_in_fall_steps()` splits fast falls into
   moves of 16px at most; slower frames are unchanged (`physics.md`, last section). New gate
   `chasm_plunge` in `check.sh --full`.
7. **Chests:** `RareCoinSpawner` hangs a chest every 80–120s (first at 30–50s) at 84px, reachable
   at every jump level; "Chests: N" on the HUD. At death `ChestRewards.TABLE` rolls each (15–35
   coins 40%, 50–90 20%, jackpot 200–300 5%, an unowned skater 5%, new cosmetic 30%; Rare/Aurora above), banked in `record_run`'s one
   write. `ChestReveal` waits for a tap on the death screen, then rattles, flashes and blends to
   the open pose, with rays, gold spray, count-up and three synthesised sounds (`build_ui_sfx.py`).
   The generated chest sprites come from `art_source/chests/`; see the visual pass above. Chest and rare coin skip any spot within 500px or 1s of a hazard
   (`ObstacleSpawner.is_clear_for_pickup`). `regression_probe` case `chests`.
8. **Shop as cards:** an upgrades row and a skaters row with pictures, pips on Jump, prices on
   buttons, unaffordable cards dimmed, Reset Progress small and last
   (`GameManager.build_shop_rows`). Shop, Stats and Skaters backdrops are opaque (the death screen
   showed through).
9. **Dev mode:** two start-screen buttons, debug builds only (`scripts/systems/dev_mode.gd`, whose
   header lists every value). "Dev mode" tops the wallet to 99,999 **in the real save**, cycles a
   biome every 20s, triples powerups, a chest about every 40s, a lake every 3 min of play, an
   aurora 100s into each run. "Dev can't die": hazards pass through and a fall into a void lands
   you past it. It sets the existing debug knobs at runtime from a `user://dev_mode` flag, so no
   source default changes and `shipping_values_check` still holds them.

### Next actions, in order

1. **Owner tries continuous overlapping B in the game and reviews the10th/50th glide milestones above.**
   Tune from that feedback. Install over USB when the owner reconnects the phone; the
   installed app still has the first continuous build. A/B/C remain unapproved references.
2. **The owner plays `play/next`** (dev mode makes this quick). What to look at:
   - the card shop: layout, whether seven cards feel comfortable on a phone, the skater pictures.
	 Rendered at both aspect ratios; owner review is still pending.
   - all three chest tiers in a run, reveal timing and mission completion/reward across runs
   - the plunge's landing and camera (1.3s of fall; the landing is off screen at the lip)
   - mountains at speed; whether 8:00+ is hard in a good way ("Dev can't die" gets there)
   - HUD text on a phone: "Chests: N   Coins: N" and the distance beside the clock
   - from the merged branches: islands, black ice, vents, geodes, theme, menu sounds, skaters
3. **If it holds up, merge `play/next` into `main`** (fast-forward). The owner decides; do not
   merge or push unprompted.
4. **Retention follow-up, after the owner plays the new missions/tiers:**
   - Consider a five-mission milestone that lets the player choose a cosmetic, collection-set
     rewards, then personal-best encouragement. These are planned, not built.
   - Tune mission targets and chest sounds/pacing from play. Existing art, icons, collection
     and display font are built; do not list them as missing work.
5. **Flagged, undone:**
   - The 2.0s room floor means more obstacle searches per minute, and A3 (search cost on the phone
	 at combo tiers) is still unmeasured. If late frames show past 8:00, set
	 `ObstacleSpawner.BREATHING_ROOM_FLOOR` back to 2.5 first.
   - A coin trail down the plunge was considered and not built: the fall arc depends on speed and
	 on whether the player jumped, so a fixed trail would often miss.
6. Still open from before: one long phone run past 5:00 with logcat (`OBSTACLE_SEARCH_SLOWEST`,
   `debugging.md`), and the owner tests under "Owner: tests still owed" in `docs/history.md`.

### Traps met this session (each cost time)

- **A new `class_name` needs one `--headless --import` before any gate**, or a gate hangs on a
  parse error until its time limit (`check.sh` looked stuck for 7 minutes).
- **Engine runs stripped `project.godot`'s pins again** (during a windowed run). Standing rule in
  `CLAUDE.md`: if the diff only removes pins/comments, `git checkout -- project.godot`. Run
  `git status` after ANY engine run.
- **Headless never runs `_draw()`.** Drawing code (`ChestReveal.ChestStage`) must be rendered in a
  window once to find errors; `regression_probe` only proves its logic.
- **Without `--fixed-fps 60` a headless run's frames are not real time.** A test that waits N
  frames for a tween fails under `check.sh`; `await tween.finished` instead (`chests` case).
- **A windowed test loses focus and the game pauses itself.** Re-set `State.PLAYING` each frame.
- **Never test dev mode or a death against the real save.** Swap an in-memory `SaveStore` into
  `Services` first, as `regression_probe` does; dev mode's wallet top-up writes `save.dat`.
- **Anything pinned to a world_x past segment 60 moves when segment lengths change.** The
  mountains moved `PLACED_FAIRNESS_CASES`' control; it now sits before segment 60.
- **zsh does not word-split `$args`**: pass a gate's arguments literally, or the probe silently
  runs with defaults (a "PASS" over a quarter of the trials).
- **Codex / sandboxed agents:** add `--log-file /tmp/godot.log` to every Godot command
  (`check.sh` already does).

### On the phone

The existing **Aura** app remains the 2026-10-05 debug export (old `main`), with its save kept.
The separate **Aura Playtest** app now holds `play/next` plus the phone-review fixes
above, with its own save. Dev-mode buttons are debug-only; release exports omit them.

---

## What the game does now (the obstacle system as built)

### Camera (step 1)
- The player sits at **`Main.PLAYER_SCREEN_X_FRACTION` = 0.30** from the left. The camera target is
  `player_x + (0.5 − 0.30) × viewport width ÷ live zoom`, also applied in `_ready()` (no swoop), so
  every aspect ratio and the Aurora zoom keep the same fraction.
- Forward view: **968px** on 16:9 (was 691), **1,179px** on the owner's 19.5:9, **1,210px** on 20:9.
  Per-device table: `visuals.md`.
- Everything spawned ahead is at **≥1,500px** (obstacle, rare coin, powerup). `check_spawn_lookahead()`
  asserts every lookahead clears a **21:9** screen (1,270px) + 64px.

### Hazards

| Kind | Answer | Hitbox | Code |
|---|---|---|---|
| **Spike** | Jump | its silhouette (convex hull) inside a 32×32 box on the ground | `obstacle.tscn` + `obstacle.gd` |
| **Floe** | Stay down | 32×136 column, **64→200px** above the surface. The sprite is exactly the hitbox | `floe.tscn` + `obstacle.gd` |
| **Shard** | Stay down, or clear it at jump level 3+ | its silhouette inside a 32×32 box at **64–96px** | `shard.tscn` + `obstacle.gd` |
| **Thin ice** | Keep hopping | An x span, not a body: >**12 grounded frames** (0.2s) in a row cracks it; each landing resets | `scripts/obstacles/thin_ice.gd` (`ThinIce`) |
| **Black ice** (2026-10-28) | Commit early | A `ThinIce` subclass span you **cannot take off from** (`Player.is_on_black_ice()` at the one ground take-off site; a tap stays buffered). Harmless alone; before a spike, jump before it or after it. Dark glass, never tinted | `black_ice.gd` (`BlackIce`) |
| **Geode** (2026-10-28) | Slam it (reward) | A `SpriteSpan` (a `ThinIce` subclass drawn as one untinted sprite), never a hitbox: a **slam landing** within 24px of it pays **10 coins** (via `geode_broken`, combo/doubler apply). Scheduled only if the player owns the slam. Gold | `geode.gd` (`Geode`) |
| **Vent** (2026-10-28) | Jump EARLY | A 48px `SpriteSpan` that **forces a take-off**: grounded on it, `Player`'s ordinary ground jump fires with no tap (`is_on_vent()`, same site as black ice). Not a new velocity: the launch IS a jump, so chasm reach and every proof hold. Before a floe at 0.5s, being launched carries you into it, so you jump over the vent early enough to be down before the floe. Deep teal: the pale-cyan generation was 0.09 from the ice | `vent.gd` (`Vent`) |

- All three bodies run `obstacle.gd`, so hit → `absorb_hit()`, a shield absorbs one, and a boosting
  player breaks through. Thin ice: a boost skims over; a shield absorbs the crack and the patch
  **disarms** (fades to 30%). A crack plays `crack.wav` (synthesised, `build_crack_sfx.py`) via
  `ObstacleSpawner.thin_ice_cracked`; a fatal one also sinks the sprite through the ice
  (`Player.sink_through_ice`), seen because every death screen now fades in over 0.6s
  (`GameManager.DEATH_SCREEN_FADE_SECONDS`). Its overlay is an 8px `Line2D` tiling a cracked-crust strip, its straight
  bottom 1px under the surface line, because chunks draw over anything at or below it (and so hide the join).
- **All four hazards are art** (2026-10-28, ChatGPT-generated, low-poly ice; the look is clean minimal
  ice, never "cozy"): light-greyscale `Visual` `Sprite2D`s (and the thin-ice strip) that the biome's
  obstacle colour multiplies over, baked by `scripts/tools/build_hazard_sprites.py` from
  `art_source/hazards/`: the three bodies to exactly 3× their hitbox, the strip to 3× `OVERLAY_WIDTH`
  with a crossfaded seam. `biome_schedule_check` holds the contrast floor on each one as drawn (lowest 0.63).
  Measured contrast of that red vs every biome's scenery and sky is **≥ 0.65** (`sunset_rose` worst),
  above the 0.5 gate.
- **Runtime-verified** in the real scene: thin ice cracks on exactly the 13th grounded frame;
  hopping each landing survives; a shield absorbs, disarms and survives.

### Scheduler (`scripts/systems/obstacle_spawner.gd`)
- **`PIECE_KINDS`**: scene path, half width, half height, centre height above the surface, `floating`.
  **`PATTERNS`**: `{id, tier, weight, pieces: [{kind, at (s), length (s, thin ice only)}]}`.
- **`TIERS`**, each `{start, room}`. "Room" is the breathing room from one pattern's **end** to the
  next one's start, jittered ±30% and never below the floor:

| Tier | From | New | Room |
|---|---|---|---|
| 1 | 0:20 | `spike` (w2) | the original ramp: ~1 per 30s window rising toward one every 5s, 4s floor |
| 2 | 1:00 | `floe`, `shard` (w1 each); `geode` (w1, slam owners) | 6s |
| 3 | 1:45 | `ice_short` 0.3s (w2), `ice_long` 1.2s (w1), `black` 0.6s (w1), `vent` (w1) | 5s |
| 4 | 2:30 | pairs: `spike_floe`, `spike_shard`, `floe_spike`, `shard_spike` (0.5s apart), `spike_spike` (0.7s), `ice_spike`, `black_spike` (w2), `geode_spike` (slam owners), `vent_floe` (0.5s, w2) | 4s |
| 5 | 3:30 | triples: `spike_floe_spike` (1.0s), `floe_spike_shard` (1.1s), `spike_black_spike` (0.95s; 1.25s starved) | 3.5s |
| 6 | 5:00 | — | 3.5s |
| 7 | 6:30 | pairs: `ice_floe`, `shard_ice`, `vent_shard`, `vent_spike`, `vent_ice` | 3.0s |
| 8 | 8:00 | triples: `black_floe_spike`, `vent_floe_spike`, `ice_spike_floe` (w2 each) | 2.75s shrinking 0.25s/min to the **2.0s floor** (~11:00) |

- **Each attempt**: draw a pattern for the current tier. A kind not yet seen this run is swapped for
  its solo pattern, with **+1.5s room before and after** (the tutorial). Floating patterns wait out a
  glide; every pattern waits out a boost. Then a **forward search**: the lookahead, then every 50px up to
  600px further. A combo that fits nowhere **falls back to its first piece alone**; if even that
  fails, retry in 1s. The next room counts from where the pattern really ended.
- **Footprint guard** (`is_footprint_legal`, static): ≤6° across the whole span (**except
  thin-ice-only patterns**), not on the lake, ground over `[start − 200, end + 950]`, off the Aurora
  flat. 950 = the boosted max jump's 848px + margin (it was 700: a late boosted jump could land in a chasm).
  **Approach** (2026-09-28): over the weakest jump's reach before each spike, no ground >2px below its base.
- **Measured in the live game** (7 min, 2 seeds, unkillable player): patterns per minute **2, 8, 11,
  12–15, 14–15, 14–15, 16**. That's ~51 in the first 5 min, vs **18–25** before this work: the old code
  silently dropped ~60% of slots. By minute 7 one starts every ~4s; **~12% arrive as combos**. Per
  attempt: singles place ~90%, thin ice ~96%, pairs 24–35%, triples 13–20%. **All measured before the
  approach clause**: spikes now place ~67%, pairs 9–25%, triples 2–7%, so fewer combos. Not re-measured live.

### New checks (all in `check.sh` via `terrain_invariant_check`, all mutation-tested; see `debugging.md`)
- **`check_pattern_fairness()`**: every pattern simulated at 60 Hz on flat ground, **5 jump levels ×
  {plain, √2 powerup} × {the tier's opening speed, 750}**. The only input is when to leave the ground. It
  asserts a surviving line exists and its tightest take-off window is **≥ 7 frames**
  (`PATTERN_MIN_WINDOW_FRAMES`). The lone spike measures 7: 8.57 continuous, the old "~8.6 frames".
  It also asserts both breathing-room floors outlast the longest jump (1.13s) + 0.3s.
- **`check_placed_pattern_fairness()`** (per seed, 2026-09-28): the same model on the **real ground** of
  sampled placements the forward search accepts. It's what proves the guard; the flat proof only proves the table.
- **Per seed**: each pattern's placement rate through the game's own `find_legal_offset()` (floors
  0.32 / 0.04 / 0.01 for 1 / 2 / 3 pieces since the approach clause; were 0.45 / 0.12 / 0.06), plus **`weakest_hop`**: the weakest jump's airtime up the
  steepest measured slope must be ≥ 4 frames (it is 8.2 at 20.13°). That is what makes thin ice's
  slope exemption safe.
- **`check_spawn_placement()`** places **every** kind and checks its height above the surface, that its real
  hitbox matches its `PIECE_KINDS` row, and that it **is an `Obstacle`** (has its script). Thin ice:
  its height, and the overlay's `OVERLAY_LIFT`.
- **`check_spawn_lookahead()`**: see Camera.

### Where to tune

| Want to change | Knob |
|---|---|
| How dense the run gets, and when | `TIERS` (`start`, `room`), `BREATHING_ROOM_FLOOR` (2.0), `BREATHING_ROOM_SHRINK_PER_SECOND`, `BREATHING_ROOM_JITTER` (0.3) |
| Which patterns, how often, timings | `PATTERNS` (`weight`, `at`, `length`). Re-run `check.sh`: the proof has the final say |
| The tutorial pause | `FIRST_APPEARANCE_EXTRA_ROOM` (1.5s) |
| Thin ice forgiveness | `ThinIce.GRACE_SECONDS` (0.2) |
| Hazard sizes | `PIECE_KINDS`, the scene's `RectangleShape2D` (the check enforces they match) **and** the `HAZARDS` row in `build_hazard_sprites.py`, then re-run it |
| Forward view | `Main.PLAYER_SCREEN_X_FRACTION` (0.30). Lower = more view; lookaheads are checked against it |

---

## How to run things

`./scripts/check.sh` before every commit; `--full` after any player, collision, segment or
air-move change; the visual three without `--headless` after a visual change. Commands, the cloud
container setup and every gate's arguments: `docs/development/debugging.md`. After ANY engine
run: `git status` (standing rule in `CLAUDE.md`).

---

## The obstacle plan: done through step 8

### Core rules (still hold)
- **No hazard touches the player's physics**: overlap checks and span checks only.
- **You don't control speed**, so the only decision is when to leave the ground (plus the air moves).
  Motion is decoration only.
- **Patterns are authored in seconds** and proven on flat ground for a player who owns nothing. The
  air moves only ever **add** options (the landing-window rule), so "fair without them ⇒ fair with them".

The air moves' design as built, including where it departs from the plan (the left/right split, no
formula-only 2× check), is at the top of this file and in `input.md` / `physics.md`.

### Step 8 — Art: DONE, played and merged 2026-10-28
One commit each: **8a** spike/floe/shard sprites, **8b** thin-ice crack strip, **8c** spike and shard
collide on their silhouette (a convex hull inside the old box, so every fairness proof still holds),
**8d** landing/slam glint bursts (`LandingBurst`, SkateSpray's look), **8e** crack sound, sink death,
and a 0.6s death-screen fade on every death. The art came from ChatGPT; prompts must say clean,
minimal ice, never "cozy". **Ground decoration: SKIPPED by the owner.** It was removed once
(2026-09-27) for competing with hazards, and the hazards are now ice art that covers both
shapes decoration could take: upright reads as a spike/floe/shard, flat reads as thin ice.

### Open questions (owner). **Defaults in bold** are what's built unless the owner says otherwise
1. Slam **smashes a spike you land on** (like the boost)? **Off**; try it once the slam has been played.
2. Unlock prices: **slam 300, double jump 900**. Placeholders.
3. Should coins avoid floe columns? **No guard for now** (checklist item 6).
4. Hazard colour stays red-family? **Yes**: the art pass kept it (greyscale sprites × the red obstacle colour).

Answered and built: floating hazards wait out a glide; tier timings from the plan's table; step 5 as
option A (owner confirmed); the rare coin stays reachable by a level-1 double jump; the trick boost stays,
except after a double jump; the air moves split left (slam) / right (double jump) (owner).

### Ideas flagged and NOT planned (the owner's rule: bug-prone or much harder → flag it)

| Idea | Why not |
|---|---|
| Floating islands you can **stand on** | The player physics assumes the floor is the height field in ≥4 places (slope aim, stall recovery, camera baseline; island edges are walls, the `large_valley` wedge class). The floe gets the look for none of that |
| Bounce floes (land on top, get relaunched) | A relaunch from height reaches further, so it needs its own chasm clearance. Maybe later |
| Wind/gusts | Changes velocity mid-air, which the chasm reach math doesn't model |
| Hazards tied to the biome | Every headless gate is blind to biome code |
| Moving/timed hazards as a *mechanic* | No decisions added (fixed arrival time), and they cost reading time. Decoration only |
| Levels + infinite mode, checkpoints | They fight the seeded world; resuming mid-run rewinds ~10 systems. Tiers give the "chapter" feel |
| Pick your difficulty | **Later, cheap now tiers exist**: "Hard" = start at tier 3. Needs separate best scores (a save change) |
| Warmth meter (cold drains, embers refill) | The strongest "different" idea of the 2026-10-28 six, and the most bug-prone: every long harness would need a `debug_*` off-switch (the chasm trap), and lake/Aurora (spawners suppressed) would need the drain paused |
| Launch kickers / updrafts | Change velocity mid-run, which the chasm reach math does not model (same as bounce floes and wind). **The vent is the lean version**: it forces an ordinary jump instead, so nothing new is modelled |
| Thin ice under a floe (hop the ice, stay down under the floe) | Measured 2026-10-28: 5-frame window at every placement tried (0.6–1.0s of ice), under the 7-frame bar |
| Whiteout blizzard | Shrinks the forward view below what `check_spawn_lookahead()` guarantees; it would need its own set piece like the Aurora |
| Apex bells (targets at jump-apex height) | Already exists in effect: the 132px air coin lines |


---

## Contracts and traps for whoever touches this next

**`ObstacleSpawner`'s outside contract. Keep these, or change them together with their users:**
- Node path `TerrainGenerator/ObstacleSpawner`, `class_name ObstacleSpawner` (Aurora + biome directors).
- `debug_spawning_disabled` (a plain var, set by 6 probes, watched by `shipping_values_check`).
- `spawn_obstacle(x, kind = spike)`, `spawn_thin_ice(start, end)` (now a wrapper of `spawn_span(kind, start, end)`), `is_black_ice_at(x)` / `is_vent_at(x)` (Player, UNTYPED: naming the class from `player.gd` closes a load cycle), `active_obstacles` (`aurora_calm_probe`,
  `check_spawn_placement`). `OBSTACLE_SCENE` (preloaded; `aurora_calm_probe`).
- Read by `terrain_invariant_check`: `OBSTACLE_HALF_HEIGHT`, `FIRST_PATTERN_TIME`, `PIECE_KINDS`, `PATTERNS`, `TIERS`,
  `RECURRING_PATTERN_MIN_INTERVAL_FLOOR`, `BREATHING_ROOM_FLOOR`, `MIN_SAFE_START_WORLD_X`,
  `OBSTACLE_VOID_CLEARANCE_AHEAD`, `SPAWN_LOOKAHEAD_WORLD_X`, the static `get_pattern_span()`,
  `is_footprint_legal()`, `find_legal_offset()`.
- `apply_biome_color()` (`biome_director`). It stays under `TerrainGenerator` (rebasing) and never reads
  `session_seed` in `_ready()`.

**Traps found or confirmed this session:**
- **Never turn `PIECE_KINDS` scenes back into `preload()`.** It makes a load cycle: when
  `ObstacleSpawner` loads first, `floe.tscn`/`shard.tscn` come back with **no script** (hazards that can't
  hurt anyone), with no error in the game. `check_spawn_placement` now fails on it.
- **A hazard without a collision shape is invisible to `AuroraDirector`** unless
  `get_body_bounds()` knows it, and invisible to `lake_suppression_probe` unless `is_spawned_item()` knows
  it. Both know `ThinIce`; a new shapeless kind must be added to both.
- **Long combos starve on this terrain.** The per-seed placement floors fail a pattern the search can
  rarely place. Keep combos short or accept the fallback rate. Every extra spike in a combo also needs
  flat-or-falling ground before it (the approach clause), which is why spike-heavy combos are the rarest.
- **The flat proof proves the table, not the guard.** Any change that lets the guard accept more ground
  (slope limit, approach tolerance, a new exemption) must pass `check_placed_pattern_fairness()`; the
  flat proof can't see it. Don't lower `PATTERN_MIN_WINDOW_FRAMES` to make that check pass.
- **Thin ice's slope exemption depends on `weakest_hop`.** Lowering the weakest jump multiplier or
  steepening terrain fails it; then restore the slope rule for thin ice.
- **Two spikes closer than ~0.6s are unbeatable at some jump level** (0.3s = 0 frames): a higher jump
  stays up longer and carries you into the next piece. The proof catches it; don't hand-tune around it.
- **New `class_name` ⇒ one import before headless runs** (open the editor, or `--headless --import`).
- Still true: terrain chunks enter every `Area2D` (keep the player-group filter in `obstacle.gd`); place at
  `ground_y + get_terrain_height(x) − clearance`; anything spawned ahead must clear the forward view;
  `apply_upgrades()` skips headless, so probes set `has_slam`/`has_double_jump` themselves; the frame
  after a glide launch reads `is_on_floor()` true; any new `debug_*` knob goes into `shipping_values_check`.

---

## Parked on purpose. Not blocking; don't start any of these unprompted

- **Aurora look calls:** wings rework (blocked on a reference image the owner never sent), bloom
  (recommended no). The owner has accepted the aurora as it is.
- **Natural-aurora playtest:** rarity is measured, never played. It happens whenever the owner plays.
- ~0.5 slightly late frames/s on the phone, cause unmeasured. The obstacle search is now logged
  (`OBSTACLE_SEARCH_SLOWEST`, next actions 2); the other lever is moving the ice recolour into shader uniforms.
- True 120 Hz on phones needs physics interpolation. That's a big change; flagged, not started.
- Play Store release signing / store config.

## Where the rest went

- **Past sessions:** `docs/history.md`, newest first. The top entry is this session's full log. Not required reading.
- **Phone testing** (device, adb, export/install, frame-timing method): `docs/development/debugging.md`, "Android device testing".
- **This file keeps only the current state.** At the end of a session, move its section to the top of
  `docs/history.md` and replace it here.
