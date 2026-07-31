extends SceneTree

# Diagnostic (2026-07-30), read-only. Next step after the safe_margin sweep (which
# reduced residual ~3.2-3.9x but did not eliminate it, and cost real safety margin at
# one known-bad location -- not adopted).
#
# Direct test of the current hypothesis: is move_and_slide()'s own correction the
# source of the visible vertical bounce, and does its magnitude scale with terrain
# curvature specifically (not steepness, not chord resolution -- both already ruled
# out by chord_aim_probe.gd and offset_curve_probe.gd)?
#
# Per grounded frame, using ONLY existing read-only instrumentation on Player
# (debug_velocity_before_slide, debug_position_after_slide -- added 2026-07-30 for
# slide_vs_snap_probe.gd) plus standard CharacterBody2D methods (get_floor_normal(),
# get_slide_collision_count()) -- no new game-code changes:
#   requested_movement = velocity_before_slide * physics_delta  (what the grounded
#     model asked move_and_slide() to do this step)
#   actual_movement     = position_after_slide - position_before  (what actually
#     happened, BEFORE any snap runs -- isolates move_and_slide()'s own correction)
#   vertical_diff        = actual_movement.y - requested_movement.y
#   floor_normal_before / floor_normal_after  (state at the start vs. end of this
#     frame's move_and_slide() call)
#   collision_count      = get_slide_collision_count() after the call
#
# Compared across three terrain categories:
#   FLAT               segment label "flat"
#   CONSTANT_SLOPE      segment label "sustained_downhill" (near-constant grade --
#                       the control used throughout this investigation)
#   HILL_PEAK           medium_hill / medium_valley / small_hill frames where the
#                       analytic field slope (get_slope_angle_at_x) crosses zero
#                       from the previous frame -- the exact curvature peak/trough,
#                       not just "on a hill"
#   HILL_OFF_PEAK       medium_hill / medium_valley / small_hill frames NOT at a
#                       sign crossing -- curved, but away from the sharpest point
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/solver_correction_probe.gd -- \
#       --seeds=941462462,2160065702,3188032853,222894852 --frames=9000
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852"
const HILL_LABELS: Array[String] = ["medium_hill", "medium_valley", "small_hill"]
const OUT_OF_SCOPE_LABEL: String = "mega_drop"


class Bucket:
	var frames: int = 0
	var abs_vertical_diff_sum: float = 0.0
	var normal_delta_deg_sum: float = 0.0
	var collision_count_sum: int = 0
	var zero_collision_frames: int = 0


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 9000)

	print("SOLVER_BEGIN\tgodot=%s\tframes_per_seed=%d" % [
		Engine.get_version_info()["string"], frame_limit,
	])

	var totals: Dictionary = {
		"FLAT": Bucket.new(), "CONSTANT_SLOPE": Bucket.new(),
		"HILL_PEAK": Bucket.new(), "HILL_OFF_PEAK": Bucket.new(),
	}
	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		await run_seed(session_seed, frame_limit, totals)

	print("SOLVER_SUMMARY  (all seeds pooled)")
	print("    %-16s %8s %14s %16s %12s %10s" % [
		"category", "frames", "|vertical_diff|", "normal_delta_deg", "mean_slides", "zero_col_rate",
	])
	for category: String in ["FLAT", "CONSTANT_SLOPE", "HILL_OFF_PEAK", "HILL_PEAK"]:
		var bucket: Bucket = totals[category]
		print("    %-16s %8d %14.4f %16.4f %12.4f %10.4f" % [
			category, bucket.frames,
			ratio_float(bucket.abs_vertical_diff_sum, bucket.frames),
			ratio_float(bucket.normal_delta_deg_sum, bucket.frames),
			ratio_float(float(bucket.collision_count_sum), bucket.frames),
			ratio(bucket.zero_collision_frames, bucket.frames),
		])
	print("SOLVER_END")
	quit(0)


func run_seed(session_seed: int, frame_limit: int, totals: Dictionary) -> void:
	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	root.add_child(main)
	await physics_frame

	var physics_delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	var previous_field_slope_sign: float = 0.0
	var has_previous_sign: bool = false

	for frame_index: int in range(frame_limit):
		var position_before: Vector2 = player.global_position
		var floor_normal_before: Vector2 = player.get_floor_normal()
		var was_using_grounded_model: bool = player.is_using_grounded_model
		await physics_frame

		if not (was_using_grounded_model and player.is_on_floor()):
			previous_field_slope_sign = 0.0
			has_previous_sign = false
			continue

		var world_x: float = player.global_position.x
		var label: String = segment_label_at(terrain_generator, world_x)

		var requested_movement: Vector2 = player.debug_velocity_before_slide * physics_delta
		var actual_movement: Vector2 = player.debug_position_after_slide - position_before
		var vertical_diff: float = actual_movement.y - requested_movement.y
		var floor_normal_after: Vector2 = player.get_floor_normal()
		var normal_delta_deg: float = rad_to_deg(floor_normal_before.angle_to(floor_normal_after))
		var collision_count: int = player.get_slide_collision_count()

		var field_slope: float = terrain_generator.get_slope_angle_at_x(world_x)
		var field_slope_sign: float = signf(field_slope)
		var is_peak_transition: bool = has_previous_sign and field_slope_sign != previous_field_slope_sign and field_slope_sign != 0.0 and previous_field_slope_sign != 0.0
		previous_field_slope_sign = field_slope_sign
		has_previous_sign = true

		var category: String = ""
		if label == "flat":
			category = "FLAT"
		elif label == "sustained_downhill":
			category = "CONSTANT_SLOPE"
		elif label in HILL_LABELS:
			category = "HILL_PEAK" if is_peak_transition else "HILL_OFF_PEAK"
		else:
			continue  # gentle_uphill, mega_drop: not part of this comparison

		var bucket: Bucket = totals[category]
		bucket.frames += 1
		bucket.abs_vertical_diff_sum += absf(vertical_diff)
		bucket.normal_delta_deg_sum += absf(normal_delta_deg)
		bucket.collision_count_sum += collision_count
		if collision_count == 0:
			bucket.zero_collision_frames += 1

	main.queue_free()
	await process_frame


func ratio(count: int, total: int) -> float:
	return float(count) / maxf(float(total), 1.0)


func ratio_float(total: float, count: int) -> float:
	return total / maxf(float(count), 1.0)


func segment_label_at(terrain_generator: TerrainGenerator, world_x: float) -> String:
	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	return terrain_generator.get_segment_selection_label(terrain_generator.find_segment_index_at_x(world_x))


func get_string_argument(argument_name: String, default_value: String) -> String:
	var prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return default_value


func get_int_argument(argument_name: String, default_value: int) -> int:
	var raw_value: String = get_string_argument(argument_name, "")
	if raw_value.is_empty():
		return default_value
	return raw_value.to_int()
