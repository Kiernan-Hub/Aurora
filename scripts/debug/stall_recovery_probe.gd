extends SceneTree

# Verifies Player.recover_from_stall() actually unwedges a real stall.
#
# The other harnesses cannot test this: freeze_search.gd and freeze_replay_runner.gd
# both BREAK on the first stalled frame, and the watchdog only fires on the
# STALL_RECOVERY_FRAME_THRESHOLD'th consecutive one. This one deliberately keeps
# stepping through the stall so the recovery path is exercised.
#
# Reproduces the stall the scan found at seed 941462462 / warp 175000.75 /
# no input, with world rebasing OFF so the bad contact normal still occurs.
#
# Expected: motion.x collapses to 0, STALL_RECOVERY prints within a few frames,
# motion.x returns to ~8.3 px/frame, and the run ends with recoveries >= 1.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const STALL_MAX_MOTION_X: float = 0.01


func _init() -> void:
	var session_seed: int = get_int_argument("--seed", 941462462)
	var warp_x: float = get_float_argument("--warp", 175000.75)
	var frame_count: int = get_int_argument("--frames", 400)
	var rebase_enabled: bool = get_int_argument("--rebase", 0) == 1

	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	(main as Main).world_rebase_enabled = rebase_enabled
	root.add_child(main)
	await physics_frame

	terrain_generator.position.y = 0.0
	var surface_y: float = terrain_generator.ground_y + terrain_generator.get_terrain_height(warp_x)
	player.global_position = Vector2(warp_x, surface_y - player.capsule_half_height)
	player.velocity = Vector2(SpeedManager.MAX_SPEED, 0.0)
	player.speed_manager.current_speed = SpeedManager.MAX_SPEED
	player.last_physics_displacement = Vector2.ZERO
	terrain_generator.next_chunk_index = int(floor(warp_x / terrain_generator.chunk_width)) - terrain_generator.chunk_count_behind

	print("PROBE_BEGIN seed=%d warp=%.2f rebase=%d frames=%d" % [session_seed, warp_x, int(rebase_enabled), frame_count])

	var stalled_frames: int = 0
	var recoveries_at_start: int = player.debug_stall_recovery_count
	for frame_index: int in range(frame_count):
		await physics_frame
		var motion_x: float = player.last_physics_displacement.x
		if player.is_on_floor() and absf(motion_x) <= STALL_MAX_MOTION_X:
			stalled_frames += 1
			print("PROBE_STALL frame=%d x=%.3f motion_x=%.6f fn=%s slides=%d recoveries=%d" % [
				frame_index, player.global_position.x, motion_x, str(player.get_floor_normal()),
				player.get_slide_collision_count(), player.debug_stall_recovery_count,
			])
		elif stalled_frames > 0 and player.debug_stall_recovery_count > recoveries_at_start:
			print("PROBE_RESUMED frame=%d x=%.3f motion_x=%.6f" % [frame_index, player.global_position.x, motion_x])
			stalled_frames = 0

	print("PROBE_END stalled_frames=%d recoveries=%d final_x=%.1f" % [
		stalled_frames, player.debug_stall_recovery_count - recoveries_at_start, player.global_position.x,
	])
	quit(0)


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
