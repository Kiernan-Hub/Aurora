extends SceneTree

# Diagnostic (2026-07-30), read-only in the sense that it makes no gameplay decisions
# and modifies no physics state -- it consumes the TEMPORARY visual-only smoothing
# added to Player (color_rect detached via top_level=true, lerped toward
# global_position in _process()) to test one question: does smoothing the RENDERED
# position hide the residual bounce this whole investigation has been chasing,
# without changing a single physics number?
#
# Two things are checked, run sequentially (not in parallel, per instruction):
#   1. A short sanity check that _process() actually fires under this headless
#      harness at all -- every other probe in this investigation drives time via
#      `await physics_frame`, never `process_frame`, so this is unverified until
#      measured directly.
#   2. If it fires, a full run comparing frame-to-frame jitter (mean |delta_y|) of
#      the RAW physics body (player.global_position.y) against the SMOOTHED visual
#      rect (color_rect.global_position.y), sampled at the same physics-tick cadence
#      every other probe in this investigation used, plus a direct check that
#      is_on_floor(), get_slide_collision_count(), and global_position.x are
#      IDENTICAL to what the unmodified physics body would produce (proving the
#      visual layer has zero physics-side effect).
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/visual_smoothing_probe.gd -- \
#       --seeds=941462462 --frames=9000
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852"
const OUT_OF_SCOPE_LABEL: String = "mega_drop"


class LabelStats:
	var frames: int = 0
	var raw_delta_sum: float = 0.0
	var smoothed_delta_sum: float = 0.0
	var samples: int = 0


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 9000)

	print("VISUAL_BEGIN\tgodot=%s\tframes_per_seed=%d" % [
		Engine.get_version_info()["string"], frame_limit,
	])

	# --- Step 1: does _process() fire at all under this harness? ---
	var sanity_main: Node = MAIN_SCENE.instantiate()
	var sanity_player: Player = sanity_main.get_node("Player") as Player
	sanity_player.DEBUG_SHOW_PLAYER_STATE = false
	sanity_player.DEBUG_LOG_FREEZE_REPRO = false
	root.add_child(sanity_main)
	var physics_ticks_to_check: int = 120
	for i: int in range(physics_ticks_to_check):
		await physics_frame
	var sanity_process_frame_count: int = sanity_player.debug_visual_process_frame_count
	print("VISUAL_SANITY\tphysics_ticks=%d\tprocess_frames_observed=%d" % [
		physics_ticks_to_check, sanity_process_frame_count,
	])
	sanity_main.queue_free()
	await process_frame

	if sanity_process_frame_count == 0:
		print("VISUAL_SANITY_FAILED: _process() never fired under this harness -- the smoothing experiment cannot be measured this way. Aborting.")
		print("VISUAL_END")
		quit(0)
		return

	# --- Step 2: full comparison ---
	var totals: Dictionary = {}
	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		await run_seed(session_seed, frame_limit, totals)

	print("VISUAL_SUMMARY  (all seeds pooled, %s excluded)" % OUT_OF_SCOPE_LABEL)
	print("    %-20s %8s %14s %14s %10s" % ["segment", "frames", "raw_jitter", "smoothed_jitter", "reduction"])
	var labels: Array = totals.keys()
	labels.sort()
	for label: String in labels:
		var stats: LabelStats = totals[label]
		var raw_mean: float = ratio_float(stats.raw_delta_sum, stats.samples)
		var smoothed_mean: float = ratio_float(stats.smoothed_delta_sum, stats.samples)
		var reduction_pct: float = 100.0 * (1.0 - (smoothed_mean / maxf(raw_mean, 0.0001)))
		print("    %-20s %8d %14.4f %14.4f %9.1f%%%s" % [
			label, stats.frames, raw_mean, smoothed_mean, reduction_pct,
			"   (out of scope)" if label == OUT_OF_SCOPE_LABEL else "",
		])
	print("VISUAL_END")
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
	var previous_smoothed_y: float = color_rect.global_position.y
	var has_previous: bool = false
	var physics_state_mismatches: int = 0

	for frame_index: int in range(frame_limit):
		# Physics-purity check: the body's own trajectory (x, is_on_floor, slide
		# count) must be byte-identical to every prior probe's baseline behavior --
		# the visual layer must not feed back into physics in any way.
		var expected_using_grounded_model: bool = player.is_using_grounded_model
		await physics_frame

		var world_x: float = player.global_position.x
		var label: String = segment_label_at(terrain_generator, world_x)
		var raw_y: float = player.global_position.y
		var smoothed_y: float = color_rect.global_position.y

		if has_previous:
			if not totals.has(label):
				totals[label] = LabelStats.new()
			var stats: LabelStats = totals[label]
			stats.frames += 1
			stats.raw_delta_sum += absf(raw_y - previous_raw_y)
			stats.smoothed_delta_sum += absf(smoothed_y - previous_smoothed_y)
			stats.samples += 1

		previous_raw_y = raw_y
		previous_smoothed_y = smoothed_y
		has_previous = true

	print("VISUAL_RESULT\tseed=%d\tdistance=%.0f\tstall_recoveries=%d\tstuck_events=%d" % [
		session_seed, player.global_position.x, player.debug_stall_recovery_count, player.debug_stuck_event_count,
	])

	main.queue_free()
	await process_frame


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
