extends SceneTree

# Baseline measurement for the "hide the jitter without eliminating it" investigation
# (2026-07-31). Read-only: makes no gameplay decisions, writes no physics state.
#
# The mean-|delta_y| metric used earlier in this investigation (visual_smoothing_probe.gd,
# since deleted) can't tell a hill-crest bob apart from a legitimate cliff fall -- both
# are "large delta_y".
# This probe splits vertical motion into two frequency bands per segment label:
#
#   HF (what we want to cancel): sign-reversal rate of frame-to-frame delta_y, and mean
#   |second difference| (delta_y - previous_delta_y). A real fall/jump/drop has one sign
#   for many consecutive frames -- low reversal rate, small second difference relative to
#   the delta itself. The measured bounce is a ~2-frame-period back-and-forth -- high
#   reversal rate by construction.
#
#   LF (what must be preserved): mean signed delta_y over a rolling window (net vertical
#   progress), i.e. the sustained component. A washout/high-pass filter must leave this
#   alone; a low-pass filter (the reverted smoothing experiment) attenuates it too, which
#   is exactly the failure mode this metric is designed to catch.
#
# Also reads the REAL camera (main.camera_2d.global_position.y) from a live scene tree
# rather than simulating it offline, so "cam" columns show what actually reaches the
# screen and "body" columns show the untouched physics ground truth for comparison.
#
# HISTORY (2026-08-03): this probe used to carry a third set of "presn" (presentation)
# columns reading Player.get_presentation_y(), plus a --washout flag toggling
# Player.DEBUG_VISUAL_JITTER_WASHOUT_ENABLED. That visual washout filter was the
# 2026-07-31 mitigation attempt, and it was REVERTED as imperceptible in play (see
# docs/research/terrain_jitter.md) -- but this probe was left referencing the deleted
# API, so every run since died at "Invalid assignment of property
# 'DEBUG_VISUAL_JITTER_WASHOUT_ENABLED'" and printed an empty summary table. Those
# columns are gone; body-vs-camera is what remains measurable.
#
# World rebasing (main.gd, +-1024 discrete jumps every ~26s) and stall recovery
# (player.gd recover_from_stall, a teleport) are both discontinuities that would corrupt
# delta_y if crossed -- both are detected and the frame pair spanning them is excluded
# rather than counted as motion.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/archive/jitter_frequency_probe.gd -- \
#       --seeds=941462462,2160065702,3188032853,222894852 --frames=9000 [--jump=180]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852"
const NET_PROGRESS_WINDOW: int = 30


class LabelStats:
	var frames: int = 0
	var body_delta_samples: int = 0
	var body_delta_abs_sum: float = 0.0
	var body_reversals: int = 0
	var body_reversal_samples: int = 0
	var body_second_diff_abs_sum: float = 0.0
	var body_second_diff_samples: int = 0
	var camera_delta_abs_sum: float = 0.0
	var camera_delta_samples: int = 0
	var camera_reversals: int = 0
	var camera_reversal_samples: int = 0
	var net_progress_abs_sum: float = 0.0
	var net_progress_samples: int = 0


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 9000)
	var jump_period: int = get_int_argument("--jump", 0)

	print("JITTER_BEGIN\tgodot=%s\tframes_per_seed=%d\tjump_period=%d" % [
		Engine.get_version_info()["string"], frame_limit, jump_period,
	])

	var totals: Dictionary = {}
	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		await run_seed(session_seed, frame_limit, jump_period, totals)

	print("JITTER_SUMMARY  (all seeds pooled)")
	print("    %-20s %8s %12s %10s %14s %12s %10s %14s" % [
		"segment", "frames", "body|delta|", "body_rev", "body|d2|",
		"cam|delta|", "cam_rev", "net_prog/win",
	])
	var labels: Array = totals.keys()
	labels.sort()
	for label: String in labels:
		var stats: LabelStats = totals[label]
		print("    %-20s %8d %12.5f %10.4f %14.5f %12.5f %10.4f %14.4f" % [
			label, stats.frames,
			ratio_float(stats.body_delta_abs_sum, stats.body_delta_samples),
			ratio(stats.body_reversals, stats.body_reversal_samples),
			ratio_float(stats.body_second_diff_abs_sum, stats.body_second_diff_samples),
			ratio_float(stats.camera_delta_abs_sum, stats.camera_delta_samples),
			ratio(stats.camera_reversals, stats.camera_reversal_samples),
			ratio_float(stats.net_progress_abs_sum, stats.net_progress_samples),
		])
	print("JITTER_END")
	quit(0)


func run_seed(session_seed: int, frame_limit: int, jump_period: int, totals: Dictionary) -> void:
	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	# The three harness opt-outs (docs/development/debugging.md). Without the first,
	# GameManager holds get_tree().paused on the start screen for the whole run, Player
	# never gets a _physics_process, and every column below is measured on a motionless
	# body -- a silent all-zeros "pass". This probe predates the start screen and was
	# missing all three until 2026-08-03.
	(main.get_node("GameManager") as GameManager).require_start_screen = false
	(main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner).debug_spawning_disabled = true
	(main.get_node("TerrainGenerator/PowerupSpawner") as PowerupSpawner).debug_spawning_disabled = true
	# Chasms too. Without this the run reaches a chasm, the player runs off the lip and dies,
	# GameManager pauses the tree, and every number below becomes meaningless rather than
	# failing -- the exact way debug_spawning_disabled was needed for the spawners.
	(main.get_node("TerrainGenerator") as TerrainGenerator).debug_chasm_disabled = true
	root.add_child(main)
	await physics_frame

	var previous_body_y: float = player.global_position.y
	var previous_body_delta: float = 0.0
	var has_previous_body_delta: bool = false
	var previous_camera_y: float = main.camera_2d.global_position.y
	var previous_camera_delta: float = 0.0
	var has_previous_camera_delta: bool = false
	var previous_rebase_total: float = 0.0
	var previous_recovery_count: int = 0
	var net_progress_window: Array[float] = []

	for frame_index: int in range(frame_limit):
		if jump_period > 0:
			if frame_index % jump_period == 0:
				Input.action_press("ui_accept")
			elif frame_index % jump_period == 1:
				Input.action_release("ui_accept")
		await physics_frame

		var discontinuity: bool = (
			not is_equal_approx(main.total_world_rebase_shift, previous_rebase_total)
			or player.debug_stall_recovery_count != previous_recovery_count
		)
		previous_rebase_total = main.total_world_rebase_shift
		previous_recovery_count = player.debug_stall_recovery_count

		var world_x: float = player.global_position.x
		var label: String = segment_label_at(terrain_generator, world_x)
		if not player.is_on_floor():
			label = "AIRBORNE"
		if not totals.has(label):
			totals[label] = LabelStats.new()
		var stats: LabelStats = totals[label]
		stats.frames += 1

		var body_y: float = player.global_position.y
		var camera_y: float = main.camera_2d.global_position.y

		if discontinuity:
			has_previous_body_delta = false
			has_previous_camera_delta = false
		else:
			var body_delta: float = body_y - previous_body_y
			stats.body_delta_abs_sum += absf(body_delta)
			stats.body_delta_samples += 1
			if has_previous_body_delta:
				stats.body_reversal_samples += 1
				if signf(body_delta) != signf(previous_body_delta) and not is_zero_approx(body_delta) and not is_zero_approx(previous_body_delta):
					stats.body_reversals += 1
				stats.body_second_diff_abs_sum += absf(body_delta - previous_body_delta)
				stats.body_second_diff_samples += 1
			previous_body_delta = body_delta
			has_previous_body_delta = true

			var camera_delta: float = camera_y - previous_camera_y
			stats.camera_delta_abs_sum += absf(camera_delta)
			stats.camera_delta_samples += 1
			if has_previous_camera_delta:
				stats.camera_reversal_samples += 1
				if signf(camera_delta) != signf(previous_camera_delta) and not is_zero_approx(camera_delta) and not is_zero_approx(previous_camera_delta):
					stats.camera_reversals += 1
			previous_camera_delta = camera_delta
			has_previous_camera_delta = true

			net_progress_window.append(body_delta)
			if net_progress_window.size() > NET_PROGRESS_WINDOW:
				net_progress_window.pop_front()
			if net_progress_window.size() == NET_PROGRESS_WINDOW:
				var window_sum: float = 0.0
				for windowed_delta: float in net_progress_window:
					window_sum += windowed_delta
				stats.net_progress_abs_sum += absf(window_sum)
				stats.net_progress_samples += 1

		previous_body_y = body_y
		previous_camera_y = camera_y

	# distance is the sanity check that the run actually happened: a paused run leaves
	# the player at its spawn x of 64.
	print("JITTER_RESULT\tseed=%d\tdistance=%.0f\trecoveries=%d\tstuck=%d" % [
		session_seed, player.global_position.x, player.debug_stall_recovery_count, player.debug_stuck_event_count,
	])
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
