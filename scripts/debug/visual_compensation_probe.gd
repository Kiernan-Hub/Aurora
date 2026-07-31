extends SceneTree

# Diagnostic (2026-07-30), read-only in effect. Consumes the TEMPORARY visual-only
# compensation added to Player: color_rect is detached (top_level=true) and, once per
# physics tick (not _process -- the compensated value is defined per physics step, so
# this sidesteps the earlier headless _process-cadence issue entirely), rendered at
# the body's FINAL position minus the single-step vertical discrepancy
# move_and_slide() introduced relative to what the grounded model actually requested.
# Not general smoothing: recomputed fresh from real positions every tick, no history.
#
# Compares, once per physics tick:
#   raw jitter      = frame-to-frame |delta| of player.global_position.y (physics)
#   visual jitter    = frame-to-frame |delta| of color_rect.global_position.y (compensated)
#   lag/detachment   = |color_rect.global_position.y - player.global_position.y| each
#                      frame -- how far the compensated visual drifts from the real
#                      body. Should stay small and bounded, not grow over time.
# Categorized FLAT / CONSTANT_SLOPE / HILL_PEAK / HILL_OFF_PEAK exactly like
# solver_correction_probe.gd for direct comparability with that baseline.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/visual_compensation_probe.gd -- \
#       --seeds=941462462,2160065702,3188032853,222894852 --frames=9000
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852"
const HILL_LABELS: Array[String] = ["medium_hill", "medium_valley", "small_hill"]
# ColorRect's rest position is Vector2(-16, -24) relative to the body origin (see
# scenes/player/player.tscn) -- a fixed, by-design offset, not detachment. Subtracted
# out of the lag metric below so lag measures actual visual-vs-physics divergence,
# not this constant.
const COLOR_RECT_LOCAL_OFFSET_Y: float = -24.0


class Bucket:
	var frames: int = 0
	var raw_delta_sum: float = 0.0
	var visual_delta_sum: float = 0.0
	var lag_sum: float = 0.0
	var max_lag: float = 0.0
	# Reversal rate isolates NOISE from legitimate large-but-smooth curvature-
	# following motion, which raw |delta_y| cannot: a hill's intended trajectory has
	# large frame-to-frame deltas too, just consistently signed until curvature
	# itself changes. A sign flip between consecutive deltas is a local zigzag --
	# what "jittery" actually looks like to a player -- regardless of magnitude.
	var raw_reversals: int = 0
	var visual_reversals: int = 0
	var reversal_samples: int = 0


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 9000)

	print("VCOMP_BEGIN\tgodot=%s\tframes_per_seed=%d" % [
		Engine.get_version_info()["string"], frame_limit,
	])

	var totals: Dictionary = {
		"FLAT": Bucket.new(), "CONSTANT_SLOPE": Bucket.new(),
		"HILL_PEAK": Bucket.new(), "HILL_OFF_PEAK": Bucket.new(),
	}
	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		await run_seed(session_seed, frame_limit, totals)

	print("VCOMP_SUMMARY  (all seeds pooled)")
	print("    %-16s %8s %13s %13s %10s %10s" % [
		"category", "frames", "raw_jitter", "visual_jitter", "mean_lag", "max_lag",
	])
	print("    %-16s %8s %10s %10s" % ["category", "frames", "raw_rev", "visual_rev"])
	for category: String in ["FLAT", "CONSTANT_SLOPE", "HILL_OFF_PEAK", "HILL_PEAK"]:
		var bucket: Bucket = totals[category]
		print("    %-16s %8d %13.4f %13.4f %10.4f %10.4f" % [
			category, bucket.frames,
			ratio_float(bucket.raw_delta_sum, bucket.frames),
			ratio_float(bucket.visual_delta_sum, bucket.frames),
			ratio_float(bucket.lag_sum, bucket.frames),
			bucket.max_lag,
		])
	for category: String in ["FLAT", "CONSTANT_SLOPE", "HILL_OFF_PEAK", "HILL_PEAK"]:
		var bucket: Bucket = totals[category]
		print("    %-16s %8d %10.4f %10.4f" % [
			category, bucket.frames,
			ratio(bucket.raw_reversals, bucket.reversal_samples),
			ratio(bucket.visual_reversals, bucket.reversal_samples),
		])
	print("VCOMP_END")
	quit(0)


func run_seed(session_seed: int, frame_limit: int, totals: Dictionary) -> void:
	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	var color_rect: Control = player.get_node("ColorRect") as Control
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	root.add_child(main)
	await physics_frame

	var previous_raw_y: float = player.global_position.y
	var previous_visual_y: float = color_rect.global_position.y
	var has_previous: bool = false
	var previous_field_slope_sign: float = 0.0
	var has_previous_sign: bool = false
	var previous_raw_delta: float = 0.0
	var previous_visual_delta: float = 0.0
	var has_previous_delta: bool = false

	for frame_index: int in range(frame_limit):
		var was_grounded_model: bool = player.is_using_grounded_model
		await physics_frame

		var world_x: float = player.global_position.x
		var label: String = segment_label_at(terrain_generator, world_x)
		var raw_y: float = player.global_position.y
		var visual_y: float = color_rect.global_position.y
		var lag: float = absf((visual_y - COLOR_RECT_LOCAL_OFFSET_Y) - raw_y)

		if not was_grounded_model or not player.is_on_floor():
			previous_raw_y = raw_y
			previous_visual_y = visual_y
			has_previous = true
			previous_field_slope_sign = 0.0
			has_previous_sign = false
			continue

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
			previous_raw_y = raw_y
			previous_visual_y = visual_y
			has_previous = true
			continue

		var raw_delta: float = raw_y - previous_raw_y
		var visual_delta: float = visual_y - previous_visual_y
		if has_previous:
			var bucket: Bucket = totals[category]
			bucket.frames += 1
			bucket.raw_delta_sum += absf(raw_delta)
			bucket.visual_delta_sum += absf(visual_delta)
			bucket.lag_sum += lag
			bucket.max_lag = maxf(bucket.max_lag, lag)
			if has_previous_delta:
				bucket.reversal_samples += 1
				if signf(raw_delta) != signf(previous_raw_delta) and not is_zero_approx(raw_delta):
					bucket.raw_reversals += 1
				if signf(visual_delta) != signf(previous_visual_delta) and not is_zero_approx(visual_delta):
					bucket.visual_reversals += 1

		previous_raw_y = raw_y
		previous_visual_y = visual_y
		has_previous = true
		previous_raw_delta = raw_delta
		previous_visual_delta = visual_delta
		has_previous_delta = true

	print("VCOMP_RESULT\tseed=%d\tdistance=%.0f\tstall_recoveries=%d\tstuck_events=%d" % [
		session_seed, player.global_position.x, player.debug_stall_recovery_count, player.debug_stuck_event_count,
	])

	main.queue_free()
	await process_frame


func ratio_float(total: float, count: int) -> float:
	return total / maxf(float(count), 1.0)


func ratio(count: int, total: int) -> float:
	return float(count) / maxf(float(total), 1.0)


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
