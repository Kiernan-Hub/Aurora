extends SceneTree

# Geometry-only terrain validator. Samples the height field directly and asserts the
# invariants the generator is supposed to guarantee -- no physics, no player input, no
# stall reproduction required.
#
# Why this exists: every terrain bug found so far was detectable as a pure geometry
# fact, but the only tool that could detect one was a physics-stall reproduction
# (freeze_search.gd), which needs the right seed AND the right sub-pixel start phase
# AND the right input schedule. The large_valley drop face was 80.4 degrees -- a
# property of the height field alone, checkable in under a second -- and it took a week
# to find. This script turns that class of bug into a few seconds of sampling.
#
# It also converts the load-bearing comments in terrain_generator.gd (the ones warning
# "combine with maxf(), never minf()") into something that can actually fail.
#
# Usage:
#   godot --headless --path . --script res://scripts/debug/terrain_invariant_check.gd \
#       -- --seeds=8 --to=200000
#   godot --headless --path . --script res://scripts/debug/terrain_invariant_check.gd \
#       -- --seed=941462462 --to=300000
#
# Exit code is 0 only if every seed passes, so this is usable as a gate.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

const DEFAULT_SEED_COUNT: int = 8
const DEFAULT_START_WORLD_X: float = 0.0
const DEFAULT_END_WORLD_X: float = 200000.0
# 1px is the finest resolution that matters: the collision polyline is built at 16px
# and the player capsule is 32px wide, so anything narrower than a pixel cannot be
# what the physics engine trips over.
const DEFAULT_SAMPLE_STEP: float = 1.0
# A single 1px step that moves Y by more than this is a step/cliff, not a slope. Kept
# well above the steepest legal 1px rise (tan(45 deg) * 1px = 1.0px) so a legitimately
# steep face is reported as an angle violation rather than a discontinuity.
const DISCONTINUITY_STEP_Y: float = 4.0
# Slope is compared against floor_max_angle, which is what CharacterBody2D uses to
# decide "floor" vs "wall". Anything at or past it is terrain the player can wedge
# against. A hair of tolerance absorbs float noise in the finite difference.
const SLOPE_ANGLE_TOLERANCE_RADIANS: float = 0.0035
# Seeds are drawn from a fixed generator so a failing run is reproducible verbatim.
const SEED_SWEEP_BASE: int = 1
const MAX_REPORTED_VIOLATIONS_PER_SEED: int = 5
const PROGRESS_SAMPLE_INTERVAL: int = 250000


func _init() -> void:
	var explicit_seed: int = get_int_argument("--seed", -1)
	var seed_count: int = maxi(get_int_argument("--seeds", DEFAULT_SEED_COUNT), 1)
	var start_world_x: float = get_float_argument("--from", DEFAULT_START_WORLD_X)
	var end_world_x: float = get_float_argument("--to", DEFAULT_END_WORLD_X)
	var sample_step: float = maxf(get_float_argument("--step", DEFAULT_SAMPLE_STEP), 0.01)

	var session_seeds: Array[int] = []
	if explicit_seed >= 0:
		session_seeds.append(explicit_seed)
	else:
		session_seeds = build_seed_sweep(seed_count)

	print("TERRAIN_INVARIANT_CHECK seeds=", session_seeds.size(), " range=[%.0f, %.0f]" % [start_world_x, end_world_x], " step=%.2f" % sample_step)

	var failed_seed_count: int = 0
	for session_seed: int in session_seeds:
		var seed_passed: bool = await check_session_seed(session_seed, start_world_x, end_world_x, sample_step)
		if not seed_passed:
			failed_seed_count += 1

	print("TERRAIN_INVARIANT_RESULT seeds_checked=", session_seeds.size(), " seeds_failed=", failed_seed_count)
	if failed_seed_count > 0:
		print("TERRAIN_INVARIANT_RESULT status=FAIL")
		quit(1)
		return

	print("TERRAIN_INVARIANT_RESULT status=PASS")
	quit(0)


func build_seed_sweep(seed_count: int) -> Array[int]:
	var session_seeds: Array[int] = []
	var seed_generator: RandomNumberGenerator = RandomNumberGenerator.new()
	seed_generator.seed = SEED_SWEEP_BASE
	for seed_index: int in range(seed_count):
		session_seeds.append(int(seed_generator.randi() & 0x7fffffff))
	return session_seeds


func check_session_seed(session_seed: int, start_world_x: float, end_world_x: float, sample_step: float) -> bool:
	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	# The height field is a pure function of (session_seed, world_x), so nothing here
	# depends on the player actually moving -- but the scene must be in the tree for
	# _ready() to snapshot floor_max_angle into the generator before sampling.
	player.DEBUG_LOG_FREEZE_REPRO = false
	player.DEBUG_SHOW_PLAYER_STATE = false
	root.add_child(main)
	await physics_frame

	var max_slope_angle: float = player.floor_max_angle
	var report: Dictionary = sample_height_field(terrain_generator, start_world_x, end_world_x, sample_step, max_slope_angle)
	print_seed_report(session_seed, report, max_slope_angle)

	main.queue_free()
	await process_frame
	return int(report["violation_count"]) == 0


func sample_height_field(terrain_generator: TerrainGenerator, start_world_x: float, end_world_x: float, sample_step: float, max_slope_angle: float) -> Dictionary:
	var violations: Array[String] = []
	var violation_count: int = 0
	var worst_slope_angle: float = 0.0
	var worst_slope_world_x: float = start_world_x
	var slope_angle_limit: float = max_slope_angle + SLOPE_ANGLE_TOLERANCE_RADIANS

	var previous_world_x: float = start_world_x
	var previous_height: float = terrain_generator.get_terrain_height(previous_world_x)
	if not is_finite(previous_height):
		violations.append("non_finite height at world_x=%.3f" % previous_world_x)
		violation_count += 1

	var sample_index: int = 0
	var world_x: float = start_world_x + sample_step
	while world_x <= end_world_x:
		var height: float = terrain_generator.get_terrain_height(world_x)
		sample_index += 1
		if sample_index % PROGRESS_SAMPLE_INTERVAL == 0:
			print("  ...sampled %d points, at world_x=%.0f" % [sample_index, world_x])

		if not is_finite(height):
			violation_count += 1
			if violations.size() < MAX_REPORTED_VIOLATIONS_PER_SEED:
				violations.append("non_finite height at world_x=%.3f" % world_x)
			previous_world_x = world_x
			previous_height = height
			world_x += sample_step
			continue

		var delta_height: float = height - previous_height
		var delta_x: float = world_x - previous_world_x
		var slope_angle: float = absf(atan2(delta_height, delta_x))
		if slope_angle > worst_slope_angle:
			worst_slope_angle = slope_angle
			worst_slope_world_x = world_x

		if absf(delta_height) > DISCONTINUITY_STEP_Y:
			violation_count += 1
			if violations.size() < MAX_REPORTED_VIOLATIONS_PER_SEED:
				violations.append("C0_DISCONTINUITY at world_x=%.3f dy=%.3f over dx=%.3f segment=%s" % [
					world_x,
					delta_height,
					delta_x,
					terrain_generator.get_segment_selection_label(terrain_generator.find_segment_index_at_x(world_x)),
				])
		elif slope_angle > slope_angle_limit:
			violation_count += 1
			if violations.size() < MAX_REPORTED_VIOLATIONS_PER_SEED:
				violations.append("SLOPE_EXCEEDS_FLOOR_MAX_ANGLE at world_x=%.3f angle=%.2fdeg limit=%.2fdeg segment=%s" % [
					world_x,
					rad_to_deg(slope_angle),
					rad_to_deg(max_slope_angle),
					terrain_generator.get_segment_selection_label(terrain_generator.find_segment_index_at_x(world_x)),
				])

		previous_world_x = world_x
		previous_height = height
		world_x += sample_step

	var report: Dictionary = {}
	report["violations"] = violations
	report["violation_count"] = violation_count
	report["worst_slope_angle"] = worst_slope_angle
	report["worst_slope_world_x"] = worst_slope_world_x
	report["sample_count"] = sample_index + 1
	return report


func print_seed_report(session_seed: int, report: Dictionary, max_slope_angle: float) -> void:
	var violation_count: int = int(report["violation_count"])
	var status: String = "PASS" if violation_count == 0 else "FAIL"
	print("TERRAIN_INVARIANT_SEED seed=", session_seed,
		" status=", status,
		" samples=", int(report["sample_count"]),
		" violations=", violation_count,
		" max_slope=%.2fdeg" % rad_to_deg(float(report["worst_slope_angle"])),
		" at_world_x=%.1f" % float(report["worst_slope_world_x"]),
		" floor_max_angle=%.2fdeg" % rad_to_deg(max_slope_angle))

	var violations: Array = report["violations"]
	for violation: String in violations:
		print("    ", violation)
	if violation_count > violations.size():
		print("    ...and ", violation_count - violations.size(), " more")


func get_int_argument(argument_name: String, default_value: int) -> int:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_int()
	return default_value


func get_float_argument(argument_name: String, default_value: float) -> float:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_float()
	return default_value
