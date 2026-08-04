extends SceneTree

# Regression gate for the is_on_floor() flicker on rising terrain (fixed 2026-07-29).
#
# The bug: on an uphill the grounded velocity model aims the body ALONG the rising
# surface, so velocity.y < 0. Two things followed from that one sign:
#   1. The step is tangential, so move_and_slide() found no contact at all
#      (slide_collision_count == 0) and is_on_floor() went false...
#   2. ...and Godot's own floor snapping, which exists to fix exactly that, is
#      suppressed whenever velocity faces up_direction (CharacterBody2D's
#      _snap_on_floor early-returns on vel_dir_facing_up). So nothing re-seated it.
# The next frame ran the gravity model, fell the ~0.4px back onto the surface, and
# the cycle repeated at ~2-frame period. The body never actually left the terrain.
#
# What this probe asserts, per segment label and per slope sign:
#   - floor-flip rate: was ~0.36 on uphill frames vs ~0.01 on downhill before the fix
#   - gravity model running on a grounded body: was ~0.23-0.33 on rising segments
#   - forced-snap displacement: must stay sub-pixel, or the snap is cancelling real
#     airtime instead of closing a sub-pixel gap
#   - contact quality (surface-gap wobble, vertical-motion reversals, airborne
#     fraction), so a fix that trades flicker for worse contact cannot pass quietly
#
# Metric definitions are local to this file: the harness that produced the historical
# 0.210px / 4.09% figures no longer exists, so numbers here are only comparable
# against a baseline run of this same script.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/floor_flicker_probe.gd -- \
#       --seeds=941462462,2160065702 --frames=20000 [--trace=gentle_uphill --tracelines=40]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852,12345,987654321"
const FLAT_SLOPE_EPSILON: float = 0.001


class SegmentStats:
	var frames: int = 0
	var flips: int = 0
	var grounded_frames: int = 0
	var gravity_model_while_grounded: int = 0
	var gap_sum: float = 0.0
	var gap_delta_sum: float = 0.0
	var gap_delta_samples: int = 0
	var motion_y_reversals: int = 0
	var motion_y_samples: int = 0
	var forced_snaps: int = 0
	var forced_snap_y_sum: float = 0.0


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 20000)
	var trace_label: String = get_string_argument("--trace", "")
	var trace_lines: int = get_int_argument("--tracelines", 0)
	# The fix rewrote the jump gate, so the jump has to be exercised: a no-input
	# replay never sets is_jump_ascending and would pass with the jump fully broken.
	var jump_period: int = get_int_argument("--jump", 0)

	print("FLICKER_BEGIN\tgodot=%s\tframes_per_seed=%d" % [
		Engine.get_version_info()["string"], frame_limit,
	])
	var worst_uphill_flip_rate: float = 0.0
	var worst_gravity_while_grounded: float = 0.0
	var worst_snap_y: float = 0.0
	var total_recoveries: int = 0
	var total_stuck_events: int = 0

	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		var result: Dictionary = await run_seed(session_seed, frame_limit, trace_label, trace_lines, jump_period)
		worst_uphill_flip_rate = maxf(worst_uphill_flip_rate, result["uphill_flip_rate"])
		worst_gravity_while_grounded = maxf(worst_gravity_while_grounded, result["worst_gravity_while_grounded"])
		worst_snap_y = maxf(worst_snap_y, result["forced_snap_max_y"])
		total_recoveries += int(result["stall_recoveries"])
		total_stuck_events += int(result["stuck_events"])

	print("FLICKER_SUMMARY")
	print("    worst uphill flip rate               : %.4f" % worst_uphill_flip_rate)
	print("    worst gravity-model-while-grounded   : %.4f" % worst_gravity_while_grounded)
	print("    largest forced floor snap (px)       : %.4f" % worst_snap_y)
	print("    stall recoveries / stuck events      : %d / %d" % [total_recoveries, total_stuck_events])
	print("FLICKER_END")
	quit(0)


func run_seed(session_seed: int, frame_limit: int, trace_label: String, trace_lines: int, jump_period: int) -> Dictionary:
	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	(main.get_node("GameManager") as GameManager).require_start_screen = false
	# Same reasoning as camera_shake_probe.gd / freeze_search.gd: ObstacleSpawner's
	# clusters are scheduled off live elapsed_time, and this probe runs long enough
	# (frame_limit, no input) to reach one. A collision pauses the tree via
	# GameManager, which would stop Player._physics_process mid-run and misreport as
	# a stall/stuck event rather than reflecting real floor-contact behavior.
	# debug_spawning_disabled, not set_physics_process(false) -- the latter does
	# not reliably work here (verified by direct instrumentation: _physics_process
	# kept firing every frame regardless).
	(main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner).debug_spawning_disabled = true
	(main.get_node("TerrainGenerator/PowerupSpawner") as PowerupSpawner).debug_spawning_disabled = true
	# Chasms too. Without this the run reaches a chasm, the player runs off the lip and dies,
	# GameManager pauses the tree, and every number below becomes meaningless rather than
	# failing -- the exact way debug_spawning_disabled was needed for the spawners.
	(main.get_node("TerrainGenerator") as TerrainGenerator).debug_chasm_disabled = true
	root.add_child(main)
	await physics_frame

	var per_label: Dictionary = {}
	var uphill_frames: int = 0
	var uphill_flips: int = 0
	var downhill_frames: int = 0
	var downhill_flips: int = 0
	var flat_frames: int = 0
	var flat_flips: int = 0
	var airborne_frames: int = 0
	var trace_budget: int = trace_lines
	var previous_grounded: bool = player.is_on_floor()
	var jump_count: int = 0
	var airborne_streak: int = 0
	var max_airborne_streak: int = 0
	var streak_apex_height: float = 0.0
	var apex_height_sum: float = 0.0
	var max_apex_height: float = 0.0
	var completed_streaks: int = 0
	var previous_forced_snap_count: int = 0
	var previous_gap: float = 0.0
	var previous_jump_ascending: bool = false
	var previous_motion_y: float = 0.0
	var has_previous_frame: bool = false

	for frame_index: int in range(frame_limit):
		if jump_period > 0:
			if frame_index % jump_period == 0:
				Input.action_press("ui_accept")
			elif frame_index % jump_period == 1:
				Input.action_release("ui_accept")
		await physics_frame

		var world_x: float = player.global_position.x
		var grounded: bool = player.is_on_floor()
		var label: String = segment_label_at(terrain_generator, world_x)
		var slope_angle: float = terrain_generator.get_slope_angle_at_x(world_x)
		var flipped: bool = has_previous_frame and grounded != previous_grounded
		# Negative gap = capsule bottom above the sampled surface. Sub-pixel values are
		# normal: safe_margin is 1.0, so the solver deliberately holds the body off.
		var surface_gap: float = (player.global_position.y + player.capsule_half_height) - terrain_generator.get_surface_world_y(world_x)
		var motion_y: float = player.last_physics_displacement.y

		if not per_label.has(label):
			per_label[label] = SegmentStats.new()
		var stats: SegmentStats = per_label[label]
		stats.frames += 1
		# Attribute each forced snap to the segment it fired on, and record how far it
		# moved the body: a snap that only closes a sub-pixel gap is corrective, while a
		# multi-pixel one would mean real airtime is being cancelled.
		if player.debug_forced_floor_snap_count > previous_forced_snap_count:
			stats.forced_snaps += 1
			stats.forced_snap_y_sum += player.debug_forced_floor_snap_last_y
		previous_forced_snap_count = player.debug_forced_floor_snap_count
		if flipped:
			stats.flips += 1
		if grounded:
			stats.grounded_frames += 1
			if not player.is_using_grounded_model:
				stats.gravity_model_while_grounded += 1
			stats.gap_sum += surface_gap
		else:
			airborne_frames += 1
			airborne_streak += 1
			streak_apex_height = maxf(streak_apex_height, -surface_gap)

		# Contact quality is measured across EVERY consecutive frame pair, not only
		# pairs where both frames were grounded. Gating on grounded-ness excludes the
		# flicker's own fall-back-onto-the-surface transitions -- the largest gap steps
		# in the run -- which would flatter a pre-fix baseline against a post-fix one.
		if has_previous_frame:
			stats.gap_delta_sum += absf(surface_gap - previous_gap)
			stats.gap_delta_samples += 1
			stats.motion_y_samples += 1
			if signf(motion_y) != signf(previous_motion_y) and not is_zero_approx(motion_y):
				stats.motion_y_reversals += 1

		# Slope sign in screen space: +y is down, so a negative angle is rising ground.
		if slope_angle < -FLAT_SLOPE_EPSILON:
			uphill_frames += 1
			if flipped:
				uphill_flips += 1
		elif slope_angle > FLAT_SLOPE_EPSILON:
			downhill_frames += 1
			if flipped:
				downhill_flips += 1
		else:
			flat_frames += 1
			if flipped:
				flat_flips += 1

		if trace_budget > 0 and label == trace_label:
			trace_budget -= 1
			print("FLICKER_TRACE\tx=%.3f\tfloor=%d\tprev_floor=%d\tmodel=%s\tvy=%.4f\tmotion_y=%.5f\tgap=%.4f\tslope_deg=%.4f\tslides=%d%s" % [
				world_x, int(grounded), int(previous_grounded),
				"GROUNDED" if player.is_using_grounded_model else "GRAVITY",
				player.velocity.y, motion_y, surface_gap, rad_to_deg(slope_angle),
				player.get_slide_collision_count(), "\tFLIP" if flipped else "",
			])

		if grounded and airborne_streak > 0:
			max_airborne_streak = maxi(max_airborne_streak, airborne_streak)
			completed_streaks += 1
			apex_height_sum += streak_apex_height
			max_apex_height = maxf(max_apex_height, streak_apex_height)
			airborne_streak = 0
			streak_apex_height = 0.0
		if player.is_jump_ascending and not previous_jump_ascending:
			jump_count += 1
		previous_jump_ascending = player.is_jump_ascending
		previous_grounded = grounded
		previous_gap = surface_gap
		previous_motion_y = motion_y
		has_previous_frame = true

	var uphill_flip_rate: float = ratio(uphill_flips, uphill_frames)
	print("FLICKER_RESULT\tseed=%d\tdistance=%.0f" % [session_seed, player.global_position.x])
	print("    by slope sign : uphill frames=%6d flip_rate=%.4f | downhill frames=%6d flip_rate=%.4f | flat frames=%6d flip_rate=%.4f" % [
		uphill_frames, uphill_flip_rate,
		downhill_frames, ratio(downhill_flips, downhill_frames),
		flat_frames, ratio(flat_flips, flat_frames),
	])
	print("    jumps=%d  airborne_streaks=%d  max_streak=%d frames  apex mean=%.2f px max=%.2f px" % [
		jump_count, completed_streaks, max_airborne_streak,
		ratio_float(apex_height_sum, completed_streaks), max_apex_height,
	])
	print("    airborne fraction=%.4f  forced_snaps=%d (max %.4f px)  recoveries=%d  stuck=%d" % [
		ratio(airborne_frames, frame_limit), player.debug_forced_floor_snap_count,
		player.debug_forced_floor_snap_max_y, player.debug_stall_recovery_count,
		player.debug_stuck_event_count,
	])
	var worst_gravity_while_grounded: float = 0.0
	var labels: Array = per_label.keys()
	labels.sort()
	for label: String in labels:
		var stats: SegmentStats = per_label[label]
		var gravity_rate: float = ratio(stats.gravity_model_while_grounded, stats.grounded_frames)
		worst_gravity_while_grounded = maxf(worst_gravity_while_grounded, gravity_rate)
		print("    %-20s frames=%6d flip_rate=%.4f gravity_while_grounded=%.4f mean_gap=%+.4f gap_wobble=%.4f vy_reversals=%.4f snaps=%.4f/frame mean_snap=%.4f" % [
			label, stats.frames, ratio(stats.flips, stats.frames), gravity_rate,
			ratio_float(stats.gap_sum, stats.grounded_frames),
			ratio_float(stats.gap_delta_sum, stats.gap_delta_samples),
			ratio(stats.motion_y_reversals, stats.motion_y_samples),
			ratio(stats.forced_snaps, stats.frames),
			ratio_float(stats.forced_snap_y_sum, stats.forced_snaps),
		])

	var result: Dictionary = {
		"uphill_flip_rate": uphill_flip_rate,
		"worst_gravity_while_grounded": worst_gravity_while_grounded,
		"forced_snap_max_y": player.debug_forced_floor_snap_max_y,
		"stall_recoveries": player.debug_stall_recovery_count,
		"stuck_events": player.debug_stuck_event_count,
	}
	main.queue_free()
	await process_frame
	# get_tree().paused is tree-wide, not scoped to this seed's `main` instance:
	# if this seed's run ended with GameManager having paused it (e.g. a death),
	# every LATER seed in _init()'s sequential loop would otherwise start already
	# paused and never process a single physics frame -- frozen at spawn for its
	# entire run, misreported as whatever near-zero/never-moved stats that implies.
	# Explicit reset here means each seed always starts from a clean slate
	# regardless of how the previous one ended.
	paused = false
	return result


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
