# Obstacle branch audit — 2026-09-27

**Both findings are FIXED.** Finding 1 on 2026-09-28 (`docs/research/spike_approach_fairness.md`);
finding 2 in the commit adding this entry.
The older September 24 audit remains below as historical context; its branch table is not current.

Reviewed `4f4c2c5..8fdbfab` (latest session) and `main..8fdbfab` (whole obstacle branch),
starting with HANDOFF.md's Audit guide, the top docs/history.md entry and CLAUDE.md.
Branch: `claude/implementation-t58fc3`. The separate `cbabd0f` log-path fix arrived after the
original audit and was preserved. The owner subsequently authorized this write-up, straightforward
fixes, a commit and a push to this branch. No merge was requested.

## 1. P1 — FIXED 2026-09-28: the placement guard accepts an unfair spike

**Resolution.** Confirmed and larger than one position: a terrain-aware run of the fairness model
over accepted placements found ~1 in 5 spikes unbeatable at jump level 0 or 1 (3 seeds), and the
model matched this reproduction at 9 positions (never optimistic). Fixed with a guard clause, per
"Next work": over the weakest jump's reach before each spike, no ground more than 2px below its
base. Backed by a gate, not a lowered threshold: `check_placed_pattern_fairness()` re-runs the proof
on the real ground of accepted placements (every level ± powerup, both speeds, combos included)
and pins this position as a regression, with a positive control. Placement rates were measured and
their floors moved (combos are now rarer). The claims in HANDOFF/CLAUDE were narrowed to "flat
proof for the table, real-ground check for the guard". Full log in the research doc above. The
original finding follows unchanged.

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
text = Path('docs/review/2026-09-27-obstacle-branch-audit.md').read_text()
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
