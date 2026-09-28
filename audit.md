# Obstacle branch audit — 2026-09-27

**For Claude: fix finding 1 before merging. Finding 2 is fixed in the commit adding this entry.**
The older September 24 audit remains below as historical context; its branch table is not current.

Reviewed `4f4c2c5..8fdbfab` (latest session) and `main..8fdbfab` (whole obstacle branch),
starting with HANDOFF.md's Audit guide, the top docs/history.md entry and CLAUDE.md.
Branch: `claude/implementation-t58fc3`. The separate `cbabd0f` log-path fix arrived after the
original audit and was preserved. The owner subsequently authorized this write-up, straightforward
fixes, a commit and a push to this branch. No merge was requested.

## 1. P1 — OPEN: the placement guard accepts an unfair spike

References: `scripts/systems/obstacle_spawner.gd:453–459` (footprint guard),
`:464–473` (slope sampling), `scripts/debug/terrain_invariant_check.gd:1338–1342`
(flat-ground model), `:1397` (fairness simulation).

The slope check covers only the pattern's hitbox span, not the ground used for take-off.
A single spike checks just its 32px footprint. The fairness model assumes flat ground
throughout the approach and arc. Passing that model therefore does not prove fairness at
all placements accepted by the live guard, even when the spike itself is nearly level.

Measured with the real Player, collision terrain and spawned spike:

- Seed `683407368`, spike centre `x=21060`, local analytic slope about `-2.039°`.
- `is_footprint_legal(... PATTERNS[0], 21060, speed)` accepts it.
- No shield, air moves or powerups; jump level 0 (`0.60`).
- At 750 px/s, 48 take-off timings at each of four starting offsets (0, 3.125, 6.25,
  9.375px): **0/192 survived**. Death occurred at the spike, not a preceding chasm.
- Max-level (`1.0`) control at the same placement: **26/48 survived**.
- Follow-up at 577 px/s (closer to the ordinary ramp at this early world position):
  **0/192 level-0 survivors**, **27/48 max-level survivors**. The original follow-up
  started the speed clock at 44s; the embedded reproduction uses the same phase-2 acceleration.
- Nearby legal placements did have surviving level-0 timings in the initial sweep.

Limits: this is a sweep of ordinary single-jump timings, not an exhaustive search of arbitrary
input histories. Placement was forced through the real spawner after checking legality; the
normal scheduler's hash was not replayed to establish a natural spawn at this exact x.
The evidence establishes a hole in the accepted-placement/fairness contract, not its frequency.

**Next work:** reproduce below, then choose a conservative approach/landing guard or validate
accepted placements against the real terrain. Prefer a small guard backed by live cases over
another general-purpose physics simulator. Do not just lower the seven-frame fairness threshold
or strengthen the starting jump: that hides the mismatch or changes other reach guarantees.
A blanket larger flat-span guard may starve placement, so measure density/acceptance too.
Retain a regression for this position and positive controls, cover combos and all jump levels
with/without jump powerup, and rerun placement-rate, fairness and physics checks. Narrow
HANDOFF/CLAUDE claims of universal fairness until the live placements support them.

## 2. P2 — FIXED: desktop slam-side holds were ignored

References: `scripts/systems/input_setup.gd:50–57`,
`scripts/player/player.gd:1066–1071`, `scripts/debug/air_move_probe.gd:298–315`.

S/right-click pressed the slam action, but the shared spin/glide hold reader only recognized
`ui_accept` and touch. Holding the desktop slam side through a ground jump therefore did not
spin, and holding it during a glide did not thrust; the left touchscreen hold already did both.
The original diagnostic printed `slam_action=true held=false`, with `ui_accept` returning true.

Implemented the small fix: `is_glide_input_held()` recognizes either desktop action. Existing
lake suppression and active-glide exemption remain before that check. Added two behavioral
cases to `air_move_probe`: hold each action from the ground, observe a spin and glide thrust,
and assert the hold did not cause an extra jump or slam. **14/14 PASS** after the change.
These drive actions synthetically; they do not certify OS key/mouse or Android event delivery.

## Verification and remaining risks

Original audit on Godot 4.7.stable, Mac:

| Check | Result |
|---|---|
| `./scripts/check.sh` | 5/5 PASS |
| `air_move_probe.gd` | 12/12 PASS before fix; 14/14 after fix |
| `chasm_probe.gd -- --seed=683407368 --chasms=3 --phases=4` | 120/120; zero recoveries |
| `freeze_search.gd -- --seed=941462462 --warp=175000 --to=178000 --phases=8 --phasestep=0.25 --scan=1 --trialframes=500 --rebase=1` | 40 trials, zero stalls; same with `--slam=1` and `--double=1` |
| `floor_flicker_probe.gd -- --frames=20000` | Six seeds; zero recoveries/stuck; worst uphill flip rate 0; worst grounded gravity 0.0009; largest snap 1.8633px |
| `aurora_calm_probe.gd` | PASS, 182,974 assertions |
| `camera_shake_probe.gd -- --seed=941462462 --frames=7000 --warmup=120` | Fresh main comparison: mean 9.87px both; max main 13.79px, branch 13.82px |
| `sky_layer_check.gd` without `--headless` | PASS, 9 biomes / 44 layers |

For each `.gd` command above, prepend:
`/Applications/Godot.app/Contents/MacOS/Godot --log-file /tmp/aura-audit.log --headless --fixed-fps 60 --path . --script res://scripts/debug/`.
Omit `--headless` for sky. Run `git status --short` after EVERY engine invocation,
including each invocation inside check.sh (use a temporary GODOT wrapper if needed).

Post-fix checks: fast five **5/5**, air moves **14/14**, chasm **120/120**, and all three
freeze searches **zero stalls**. Floor-flicker: **zero recoveries/stuck** across six seeds.
Freeze replay: **60,000 frames, no_freeze**, using `freeze_replay_runner.gd -- --seed=941462462
--frames=60000 --runs=1` with the same headless/fixed-fps prefix. `git diff --check` passed.
Initial sandbox runs crashed opening `user://logs`; temporary log redirection resolved it.
The sandboxed rendered run aborted, then passed outside the sandbox. Some headless runs emitted
a macOS certificate-access error despite passing; results are not claimed to be warning-free.
No tracked project/scene rewrite occurred. The concurrent check.sh change became `cbabd0f`.

Still unverified: actual Android touch delivery/build-on-device, physical desktop bindings,
real shop button purchases and persistence, phone layout, obstacle readability/density and feel.
`air_move_probe.gd:318–326` only checks populated shop rows, not purchases. HANDOFF.md:25–63
has the full manual checklist. The landing-window predictor's edge on slopes remains untested
on a phone (`player.gd:344–346`). No broad architecture rewrite is warranted; the table-driven
shop is reasonable. The main maintenance risk is separate gameplay, landing-prediction and
fairness physics models drifting apart, which finding 1 demonstrates.

## Self-contained reproduction for finding 1

This actively steps the real scene. It is a diagnostic, not a release gate; it prints observations
and exits 0 even when every attempt dies. Extract the following GDScript block to `/tmp`:

```sh
python3 - <<'PYCODE'
from pathlib import Path
text = Path('audit.md').read_text()
Path('/tmp/aura-fairness-repro.gd').write_text(text.split('```gdscript\n', 1)[1].split('```', 1)[0])
PYCODE
/Applications/Godot.app/Contents/MacOS/Godot --log-file /tmp/aura-fairness.log --headless --fixed-fps 60 --path . --script /tmp/aura-fairness-repro.gd -- --speed=750
git status --short
# Repeat with --speed=577, then git status again.
```

Before a placement fix, expect `LEGAL=true`, empty survivors for phases 0–3, and a nonempty
max-upgrade control (phase 4). A guard fix may instead make `LEGAL=false`; this diagnostic
intentionally still forces the old bad placement so its physics can be inspected independently.

```gdscript
extends SceneTree
# Live diagnostic, not a passing release gate. No class_name/import needed.
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 683407368
const PINNED_SPEED: float = 400.0
var main: Node
var player: Player
var terrain_generator: TerrainGenerator
var game_manager: GameManager
var obstacle_spawner: ObstacleSpawner

func _init() -> void:
	main = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	game_manager = main.get_node("GameManager") as GameManager
	obstacle_spawner = main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner
	terrain_generator.debug_replay_session_seed = SEED
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	game_manager.require_start_screen = false
	obstacle_spawner.debug_spawning_disabled = true
	(main.get_node("TerrainGenerator/PowerupSpawner") as PowerupSpawner).debug_spawning_disabled = true
	root.add_child(main)
	await physics_frame
	var speed: float = 750.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="):
			speed = float(arg.trim_prefix("--speed="))
	print("LEGAL=", ObstacleSpawner.is_footprint_legal(terrain_generator, ObstacleSpawner.PATTERNS[0], 21060.0, speed), " speed=", speed)
	for phase: int in range(5):
		var x: float = 21060.0
		print("CANDIDATE ", x, " slope ",rad_to_deg(terrain_generator.get_slope_angle_at_x(x)))
		var survived: Array[int] = []
		for tap: int in range(48):
			warp(x - 500.0 + float(phase % 4) * 3.125, false, false)
			player.upgrade_jump_multiplier = 1.0 if phase == 4 else 0.6
			player.speed_manager.current_speed = speed
			player.speed_manager.elapsed_time = 200.0
			for f: int in range(10):
				await physics_frame
			obstacle_spawner.spawn_obstacle(x)
			for f: int in range(65):
				if f == tap:
					player.buffer_jump()
				await physics_frame
				if player.is_dead or player.global_position.x > x + 100.0:
					break
			if not player.is_dead:
				survived.append(tap)

		print("AUDIT_SPIKE phase=",phase," x=",x," slope=",rad_to_deg(terrain_generator.get_slope_angle_at_x(x))," survivors=",survived)
	quit()

func warp(world_x: float, owns_slam: bool, owns_double_jump: bool) -> void:
	game_manager.set_state(GameManager.State.PLAYING)
	player.is_dead = false
	player.end_boost()
	player.end_glide()
	player.velocity = Vector2.ZERO
	player.jump_buffer_timer = 0.0
	player.coyote_timer = 0.0
	player.is_slamming = false
	player.has_double_jumped = false
	# A glide case leaves its landing shield pending; it would absorb the next case's hit.
	player.has_shield = false
	player.is_glide_landing_shield_pending = false
	player.is_shield_from_glide_landing = false
	player.glide_landing_shield_timer = 0.0
	player.has_slam = owns_slam
	player.has_double_jump = owns_double_jump
	player.speed_manager.elapsed_time = SpeedManager.PHASE1_DURATION + 1.0
	player.speed_manager.current_speed = PINNED_SPEED
	player.global_position = Vector2(world_x, terrain_generator.get_surface_world_y(world_x) - player.capsule_half_height)
	for chunk_index: int in terrain_generator.active_chunks.keys():
		terrain_generator.remove_chunk(chunk_index)
	terrain_generator.initialize_chunks()
	for obstacle: Node2D in obstacle_spawner.active_obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	obstacle_spawner.active_obstacles.clear()


```

---

# Organization and branch audit — 2026-09-24

Reviewed local HEAD `ae200cb` on `claude/aurora-reconcile`: repository layout, Git history,
resource references, validation runner, export filtering, service ownership, persistence,
touch handling and menu restart paths. This is an organization/maintenance audit, not a
complete gameplay or Android release certification. No gameplay code or branch was changed.

## Findings, in priority order

1. **Back up the six local commits.** GitHub branch tips were verified with `git ls-remote`.
   The feature branch on GitHub ends at `e157a6b`; local HEAD is six commits ahead. Those six
   include the September 20 audit and four fixes for save handling, touch input and biome
   restart continuity. They are committed locally but not present on either GitHub branch.
   Push the feature branch before integration; no force push is needed for the observed tips.

2. **The usual validation command omits important coverage.** `scripts/check.sh:51` runs
   four headless scripts plus an export-content check, but not `aurora_calm_probe.gd`.
   The four recent fixes also have no maintained regression checks exercising failed save
   writes, malformed save containers, multi-touch release or pause-menu phase banking.
   Searching the active probes found no tests of those save/input/restart entry points.
   The prior audit's reproductions are useful evidence, but not repeatable checked-in gates.
   Add isolated-save regression coverage and include the Aurora integration cases in the
   normal runner. There is no tracked GitHub Actions workflow; the checks depend on being
   run manually. A clean-checkout import and pinned engine/templates would be prerequisites
   for useful CI, not just adding a workflow file.

3. **Current-state documentation has drifted.** `README.md:34` says there are exactly twelve
   maintained checks, while fourteen `.gd` scripts now sit directly under `scripts/debug/`
   (plus the shell export check). Its claim that every headless gate is blind to biome code
   is too broad: the Aurora probe explicitly exercises scheduling/night queries.
   The September 20 audit still presents all four findings as open even though commits
   `7b844a2`, `e5ba888`, `9f07726` and `ae200cb` address them. `HANDOFF.md` has no entry for
   those fixes. Add a resolution note to the historical audit, update the current handoff,
   and keep one authoritative check inventory. Old engine-rewrite claims in the runner and
   debugging guide also contradict later measured corrections in those same docs.
   `scripts/autoload/services.gd:12` says script runs do not register autoloads, while the
   newer code/docs correctly distinguish the missing global identifier from a present node.
   These contradictions risk future agents undoing correct work or trusting incomplete tests.

4. **Keep large runtime files from accumulating unrelated responsibilities.** Terrain is
   2,303 lines, Player 1,055, SkyBackdrop 843 and GameManager 788, including extensive comments.
   Size alone is not a defect. Existing separation into directors, spawners, persistence and
   upgrade services is sensible. Move long historical explanations to research documents;
   extract cohesive behavior only when a real change needs it. A broad rewrite would add
   risk, especially around terrain sampling, sibling draw order and world rebasing.

5. **Release acceptance remains separate from clean organization.** The Android preset
   remains APK-oriented with blank SDK overrides; signing/store setup and physical-device
   acceptance remain documented unfinished work. Empty SDK overrides are defaults, not an
   independently established defect. This audit did not verify release signing, Android
   frame rate, thermal behavior, touch delivery or visual/audio acceptance.

## What is already clean

- Clear separation of runtime scripts, scenes, shipped assets, development docs, research,
  historical audits and ignored source art. One services autoload owns persistence/upgrades.
- No missing literal runtime `res://` file references in the scanned scripts/scenes/resources.
- No tracked credentials, keystore, `.godot` cache or Android build output found by path scan
  (this is not a full secret-history scan).
- Source art is `.gdignore`d. Debug/experiment export filtering passes its actual pack check.
- The latest save code checks write/flush success before rename, validates field/container
  types, tracks held touch indices and banks biome phase on paused restart/home paths.
  These fixes were inspected; their original fault-injection cases were not rerun here.
- Approximately 97 MB of source art and historical captures versus 8.8 MB of runtime assets.
  This is repository weight, not evidence that source art ships. No deletion is warranted
  solely from these sizes.

## Validation performed

- Fast runner: **5/5 PASS**, 38 seconds, including export content.
- Full Aurora probe: **182,974 assertions PASS**, two live integration cases.
- Literal runtime-resource reference scan: no missing paths.
- `git diff --check`: passed.
- The first headless attempt crashed after the sandbox denied Godot's normal user log path.
  Reran successfully using a temporary launcher that adds `--log-file /tmp/...`; repository
  runner unchanged. Aurora also emitted a macOS system error before completing successfully;
  no GDScript error was reported. This is not claimed as warning-free execution.
- No rendered visual gates, broader physics probes, Android install or fresh-clone setup run.
- A concurrent edit to `CLAUDE.md` appeared during inspection; left intact. Engine runs did
  not change tracked project settings/scenes. This report is the only file this audit added.

## Why this branch exists and how to return to main

A branch is a named line of saved project versions. `claude/` is just a naming prefix;
`aurora-reconcile` records the job it was created for. Commit `d29012e` combined two separately
planned/part-built Aurora branches. GitHub `main` already received an earlier version via
merge `9dbd938` (PR #1), but subsequent work continued on this feature branch.

Verified state:

| Reference | Commit | Relationship |
|---|---|---|
| Local feature branch | `ae200cb` | Current working code; six commits not pushed |
| GitHub feature branch | `e157a6b` | Behind local feature branch by six commits |
| GitHub main | `9dbd938` | Earlier Aurora merge |
| Local main | `60007f4` | Behind GitHub main by 25 commits |

`origin/main...HEAD` reports one commit only on main (the earlier merge commit) and 31 only
on the feature branch. A read-only three-way merge preview reported no conflicts. That is
integration evidence, not proof of runtime correctness or a guarantee against future changes.

**Do not merely switch to the existing local main expecting the latest game.** That checks out
older files; it does not transfer feature work. With committed changes preserved, switching
itself does not erase them, but running the older game can also rewrite newer save data without
new fields. Avoid testing old branches against valuable progression.

Recommended sequence: finish/preserve concurrent edits; push this feature branch; open a PR
against updated main; review and run checks plus the outstanding visual/device acceptance;
merge; then update and switch local main. Keep the feature branch until integration is
verified. For future work, branch from updated main for a bounded change and merge it when
ready instead of using one feature branch indefinitely.

## Integration follow-up — 2026-09-24

The owner authorized bringing this work onto `main`. The earlier branch table and findings
above describe the pre-integration snapshot, not the branch state after the merge.

- Preserving this report at the owner's requested root path, `audit.md`, and the existing
  three-line `CLAUDE.md` edit documenting project-settings recovery.
- Remote tips refreshed; Git push access verified. GitHub CLI is not authenticated, so
  integration uses an ordinary Git merge and push instead of creating a pull request.
- Rendered sky gate: **PASS**, all nine palettes, 44 measured layers, including Aurora
  checks at both viewport widths and both night palettes.
- Visual checks run in a temporary copy with save paths redirected to temporary files;
  the owner's progression is not used or modified. No gameplay changes are part of
  this integration. Android acceptance and the maintenance findings above remain open.
- Ice capture completed with three images; the final frame was inspected and showed no
  obvious rendering breakage. Biome capture completed with eight images; the night frame
  was inspected. As noted in the earlier audit, this capture tool substitutes the intro
  palette for one rotating palette; the separate sky gate covers all nine.
