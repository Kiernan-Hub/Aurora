extends SceneTree

# TEMPORARY audit tool (E4). Reproduces the real in-game freeze on a known seed and
# optionally applies a TEST-ONLY world rebase, to measure before/after.
#
# Nothing in scripts/player or scripts/terrain is modified. The rebase is applied
# from outside by shifting two node transforms:
#   - TerrainGenerator.position.y  (chunks are its children, so current AND future
#     chunks inherit the shift automatically)
#   - Player.global_position.y     (same delta, so relative geometry is preserved)
# The shift is snapped to a multiple of 1024 so it is exact in binary and cannot
# itself introduce rounding.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/freeze_ab_runner.gd -- \
#     --seed=2160065702 --warp=226000 --from=226700 --to=227100 --rebase=1
#
#   --warp=0 disables warm-start and runs from spawn (slow: ~28k/~47k frames).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const REBASE_TRIGGER_ABS_Y: float = 2048.0
const REBASE_QUANTUM: float = 1024.0
const STALL_MIN_VELOCITY_X: float = 1.0
const STALL_MAX_MOTION_X: float = 0.01
const NORMAL_ANOMALY_DEG: float = 1.0
const MAX_LOGGED_FRAMES: int = 40


func _init() -> void:
	var session_seed: int = get_int_argument("--seed", 2160065702)
	var warp_x: float = get_float_argument("--warp", 0.0)
	var window_from: float = get_float_argument("--from", 226700.0)
	var window_to: float = get_float_argument("--to", 227100.0)
	var rebase_enabled: bool = get_int_argument("--rebase", 0) == 1
	var frame_limit: int = get_int_argument("--frames", 60000)

	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	(main.get_node("GameManager") as GameManager).require_start_screen = false
	# Remove the hand-placed test hazard so an early jump cannot end the run.
	var stray_obstacle: Node = main.get_node_or_null("Obstacle")
	if stray_obstacle != null:
		stray_obstacle.queue_free()
	# ObstacleSpawner schedules clusters off Player.speed_manager.elapsed_time, a
	# clock that keeps running for up to frame_limit (default 60000) frames here. A
	# stray obstacle spawned near the warped target window could collide and pause
	# the tree via GameManager, stopping Player._physics_process and reading as a
	# false stall/anomaly rather than a real one. Disabled for the same reason the
	# hand-placed hazard above is removed: this probe measures collision/contact
	# behavior against the terrain, not obstacle gameplay.
	# See freeze_search.gd for why this is debug_spawning_disabled, not
	# set_physics_process(false) -- the latter does not reliably work here.
	(main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner).debug_spawning_disabled = true
	(main.get_node("TerrainGenerator/PowerupSpawner") as PowerupSpawner).debug_spawning_disabled = true
	# Chasms too. Without this the run reaches a chasm, the player runs off the lip and dies,
	# GameManager pauses the tree, and every number below becomes meaningless rather than
	# failing -- the exact way debug_spawning_disabled was needed for the spawners.
	(main.get_node("TerrainGenerator") as TerrainGenerator).debug_chasm_disabled = true
	root.add_child(main)
	await physics_frame

	print("AB_BEGIN\tseed=%d\twarp=%.1f\trebase=%s\twindow=[%.0f,%.0f]" % [
		session_seed, warp_x, str(rebase_enabled), window_from, window_to,
	])

	if warp_x > 0.0:
		warm_start(terrain_generator, player, warp_x)
		await physics_frame
		await physics_frame

	var total_rebase_shift: float = 0.0
	var rebase_count: int = 0
	var frames_in_window: int = 0
	var stall_frames: int = 0
	var normal_anomaly_frames: int = 0
	var max_normal_deviation_deg: float = 0.0
	var max_slide_count: int = 0
	var logged_frames: int = 0
	var motion_x_sum: float = 0.0
	var min_motion_x: float = 1e9
	var expected_motion_sum: float = 0.0
	var severe_slow_frames: int = 0
	var start_window_x: float = 0.0
	var reached_window: bool = false

	var jump_period: int = get_int_argument("--jump", 0)
	for frame_index: int in range(frame_limit):
		# Scripted jumping. Landing is what produces real slide collisions; riding
		# flat ground yields slide_collision_count == 0, so a no-input replay can
		# never reproduce a slides=4 signature.
		if jump_period > 0:
			if frame_index % jump_period == 0:
				Input.action_press("ui_accept")
			elif frame_index % jump_period == 1:
				Input.action_release("ui_accept")
		await physics_frame

		var world_x: float = player.global_position.x
		if world_x > window_to and reached_window:
			break

		if rebase_enabled:
			var contact_world_y: float = terrain_generator.position.y + terrain_generator.ground_y + terrain_generator.get_terrain_height(world_x)
			if absf(contact_world_y) > REBASE_TRIGGER_ABS_Y:
				var shift: float = -roundf(contact_world_y / REBASE_QUANTUM) * REBASE_QUANTUM
				terrain_generator.position.y += shift
				player.global_position.y += shift
				total_rebase_shift += shift
				rebase_count += 1

		if world_x < window_from:
			continue
		if not reached_window:
			start_window_x = world_x
		reached_window = true
		frames_in_window += 1
		var expected_motion: float = player.speed_manager.current_speed / 60.0
		expected_motion_sum += expected_motion
		if player.last_physics_displacement.x < 0.25 * expected_motion:
			severe_slow_frames += 1

		var motion_x: float = player.last_physics_displacement.x
		motion_x_sum += motion_x
		min_motion_x = minf(min_motion_x, motion_x)
		var grounded: bool = player.is_on_floor()
		var slide_count: int = player.get_slide_collision_count()
		max_slide_count = maxi(max_slide_count, slide_count)

		# Expected surface normal from the authoritative height field.
		var terrain_angle: float = terrain_generator.get_slope_angle_at_x(world_x)
		var expected_normal: Vector2 = Vector2(sin(terrain_angle), -cos(terrain_angle))
		var deviation_deg: float = 0.0
		if grounded:
			deviation_deg = rad_to_deg(absf(player.get_floor_normal().angle_to(expected_normal)))
			if deviation_deg > NORMAL_ANOMALY_DEG:
				normal_anomaly_frames += 1
				max_normal_deviation_deg = maxf(max_normal_deviation_deg, deviation_deg)

		var is_stall: bool = grounded and absf(player.velocity.x) >= STALL_MIN_VELOCITY_X and absf(motion_x) <= STALL_MAX_MOTION_X
		if is_stall:
			stall_frames += 1

		if logged_frames < MAX_LOGGED_FRAMES and (is_stall or deviation_deg > NORMAL_ANOMALY_DEG):
			logged_frames += 1
			print("AB_FRAME\t%s\tx=%.4f\tworld_y=%.2f\tvx=%.3f\tvy=%.3f\tmotion_x=%.6f\tfloor=%s\tfn=(%.6f,%.6f)\texpected=(%.6f,%.6f)\tdev=%.4f\tslides=%d\tseg=%s\tterrain_y=%.3f%s" % [
				"STALL" if is_stall else "NORMDEV",
				world_x, player.global_position.y, player.velocity.x, player.velocity.y, motion_x,
				str(grounded), player.get_floor_normal().x, player.get_floor_normal().y,
				expected_normal.x, expected_normal.y, deviation_deg, slide_count,
				segment_label_at(terrain_generator, world_x),
				terrain_generator.get_terrain_height(world_x),
				describe_collisions(player),
			])

	print("AB_RESULT\tseed=%d\trebase=%s" % [session_seed, str(rebase_enabled)])
	print("    frames_in_window      : %d" % frames_in_window)
	print("    stall frames          : %d" % stall_frames)
	print("    normal-anomaly frames : %d   (max deviation %.4f deg)" % [normal_anomaly_frames, max_normal_deviation_deg])
	print("    max slide collisions  : %d" % max_slide_count)
	print("    mean motion.x         : %.6f    min motion.x: %.6f" % [
		motion_x_sum / maxf(float(frames_in_window), 1.0),
		min_motion_x if frames_in_window > 0 else 0.0,
	])
	print("    severe-slowdown frames: %d   (motion.x < 25%% of speed/60)" % severe_slow_frames)
	print("    throughput efficiency : %.4f   (actual travel / ideal travel)" % (motion_x_sum / maxf(expected_motion_sum, 0.0001)))
	print("    distance covered      : %.1f px  (from x=%.1f to x=%.1f)" % [
		player.global_position.x - start_window_x, start_window_x, player.global_position.x,
	])
	print("    rebases applied       : %d   (total shift %.1f)" % [rebase_count, total_rebase_shift])
	print("    final player world y  : %.2f" % player.global_position.y)
	print("AB_END")
	quit(0)


func warm_start(terrain_generator: TerrainGenerator, player: Player, warp_x: float) -> void:
	# Place the player on the surface at warp_x and re-point the chunk streamer so
	# it only builds the local window instead of every chunk from the origin.
	var surface_y: float = terrain_generator.position.y + terrain_generator.ground_y + terrain_generator.get_terrain_height(warp_x)
	player.global_position = Vector2(warp_x, surface_y - 24.0)
	player.velocity = Vector2(500.0, 0.0)
	# The speed ramp caps ~62 s in; by these world_x values the real run is at
	# MAX_SPEED. Without this the probe runs at 300 px/s and samples a completely
	# different sub-pixel phase against the 16 px collision grid.
	player.speed_manager.current_speed = SpeedManager.MAX_SPEED
	var player_chunk: int = int(floor(warp_x / terrain_generator.chunk_width))
	terrain_generator.next_chunk_index = player_chunk - terrain_generator.chunk_count_behind
	print("AB_WARM\twarp_x=%.1f\tsurface_y=%.3f\tplayer_y=%.3f\tchunk=%d\tspeed=%.1f" % [
		warp_x, surface_y, player.global_position.y, player_chunk, player.speed_manager.current_speed,
	])


func segment_label_at(terrain_generator: TerrainGenerator, world_x: float) -> String:
	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	return terrain_generator.get_segment_selection_label(terrain_generator.find_segment_index_at_x(world_x))


func describe_collisions(player: Player) -> String:
	var text: String = ""
	for collision_index: int in range(player.get_slide_collision_count()):
		var collision: KinematicCollision2D = player.get_slide_collision(collision_index)
		text += "\t n%d=(%.6f,%.6f)@(%.3f,%.3f)" % [
			collision_index,
			collision.get_normal().x, collision.get_normal().y,
			collision.get_position().x, collision.get_position().y,
		]
	return text


func get_int_argument(argument_name: String, default_value: int) -> int:
	var raw: String = get_raw_argument(argument_name)
	return default_value if raw.is_empty() else raw.to_int()


func get_float_argument(argument_name: String, default_value: float) -> float:
	var raw: String = get_raw_argument(argument_name)
	return default_value if raw.is_empty() else raw.to_float()


func get_raw_argument(argument_name: String) -> String:
	var prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""
