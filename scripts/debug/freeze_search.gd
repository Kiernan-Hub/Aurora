extends SceneTree

# TEMPORARY audit tool (E4b). Brute-force search over the INPUT dimension for a
# deterministic reproduction of the real freeze.
#
# E4 showed the freeze never occurs in a no-input replay: on flat ground the player
# rides on floor snap with slide_collision_count == 0, so nothing can wedge. Slide
# collisions only appear after a landing. This sweeps jump schedules and sub-pixel
# start phases looking for  grounded && |velocity.x| >= 1 && |motion.x| ~ 0.
#
# Many trials run inside one process: the segment cache is a pure function of the
# seed, so it is built once and reused; each trial just re-warps the player.
#
# Nothing in scripts/player or scripts/terrain is modified.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const STALL_MIN_VELOCITY_X: float = 1.0
const STALL_MAX_MOTION_X: float = 0.01
const NEAR_STALL_FRACTION: float = 0.25
const REBASE_TRIGGER_ABS_Y: float = 2048.0
const REBASE_QUANTUM: float = 1024.0

# Jump patterns
const PATTERN_NONE: int = 0
const PATTERN_SINGLE: int = 1
const PATTERN_PERIODIC: int = 2
const PATTERN_AUTO: int = 3

var terrain_generator: TerrainGenerator
var player: Player


func _init() -> void:
	var session_seed: int = get_int_argument("--seed", 2160065702)
	var warp_base: float = get_float_argument("--warp", 226300.0)
	var end_x: float = get_float_argument("--to", 227100.0)
	var phase_steps: int = get_int_argument("--phases", 64)
	var phase_step_px: float = get_float_argument("--phasestep", 0.25)

	var main: Node = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	(main as Main).world_rebase_enabled = get_int_argument("--rebase", 0) == 1
	var stray: Node = main.get_node_or_null("Obstacle")
	if stray != null:
		stray.queue_free()
	root.add_child(main)
	await physics_frame

	print("SEARCH_BEGIN\tseed=%d\twarp_base=%.2f\tend_x=%.1f\tphases=%d x %.3fpx" % [
		session_seed, warp_base, end_x, phase_steps, phase_step_px,
	])

	var trials: int = 0
	var stall_trials: int = 0
	var near_stall_trials: int = 0
	var best_min_motion: float = 1e9
	var best_description: String = "none"
	var max_slides_seen: int = 0

	for phase_index: int in range(phase_steps):
		var warp_x: float = warp_base + (float(phase_index) * phase_step_px)
		var schedules: Array[Vector2i] = build_schedules()
		for schedule: Vector2i in schedules:
			trials += 1
			var result: Dictionary = await run_trial(warp_x, end_x, schedule.x, schedule.y, session_seed)
			max_slides_seen = maxi(max_slides_seen, int(result["max_slides"]))
			var min_motion: float = float(result["min_motion_x"])
			if min_motion < best_min_motion:
				best_min_motion = min_motion
				best_description = "warp=%.2f pattern=%d param=%d min_motion=%.6f max_slides=%d" % [
					warp_x, schedule.x, schedule.y, min_motion, int(result["max_slides"]),
				]
			if bool(result["stalled"]):
				stall_trials += 1
				print("SEARCH_HIT\twarp=%.2f\tpattern=%d\tparam=%d" % [warp_x, schedule.x, schedule.y])
				for line: String in result["log"]:
					print("    %s" % line)
			elif min_motion < NEAR_STALL_FRACTION * (500.0 / 60.0):
				near_stall_trials += 1

	print("SEARCH_RESULT\tseed=%d\trebase=%d" % [session_seed, get_int_argument("--rebase", 0)])
	print("    trials              : %d" % trials)
	print("    trials with a STALL : %d" % stall_trials)
	print("    trials near-stalling: %d  (min motion.x < %.2f px)" % [near_stall_trials, NEAR_STALL_FRACTION * (500.0 / 60.0)])
	print("    max slide count seen: %d" % max_slides_seen)
	print("    worst trial         : %s" % best_description)
	print("SEARCH_END")
	quit(0)


func build_schedules() -> Array[Vector2i]:
	var schedules: Array[Vector2i] = []
	if get_int_argument("--scan", 0) == 1:
		schedules.append(Vector2i(PATTERN_AUTO, 0))
		schedules.append(Vector2i(PATTERN_NONE, 0))
		for period: int in [11, 19, 31]:
			schedules.append(Vector2i(PATTERN_PERIODIC, period))
		return schedules
	schedules.append(Vector2i(PATTERN_NONE, 0))
	schedules.append(Vector2i(PATTERN_AUTO, 0))
	for period: int in [7, 11, 13, 17, 19, 23, 29, 37]:
		schedules.append(Vector2i(PATTERN_PERIODIC, period))
	for single_frame: int in range(0, 90, 6):
		schedules.append(Vector2i(PATTERN_SINGLE, single_frame))
	return schedules


func run_trial(warp_x: float, end_x: float, pattern: int, param: int, session_seed: int) -> Dictionary:
	var trial_frame_cap: int = get_int_argument("--trialframes", 400)
	reset_player(warp_x)
	await physics_frame

	var min_motion_x: float = 1e9
	var max_slides: int = 0
	var stalled: bool = false
	var log: Array[String] = []
	var recent: Array[String] = []

	for frame_index: int in range(trial_frame_cap):
		var want_jump: bool = false
		if pattern == PATTERN_SINGLE:
			want_jump = frame_index == param
		elif pattern == PATTERN_PERIODIC:
			want_jump = (frame_index % maxi(param, 1)) == 0
		elif pattern == PATTERN_AUTO:
			want_jump = player.is_on_floor()
		if want_jump:
			Input.action_press("ui_accept")
		else:
			Input.action_release("ui_accept")

		await physics_frame

		var motion_x: float = player.last_physics_displacement.x
		var slides: int = player.get_slide_collision_count()
		max_slides = maxi(max_slides, slides)
		min_motion_x = minf(min_motion_x, motion_x)

		var record: String = "x=%.4f y=%.2f vx=%.3f vy=%.3f motion_x=%.6f floor=%s fn=%s slides=%d seg=%s%s" % [
			player.global_position.x, player.global_position.y, player.velocity.x, player.velocity.y,
			motion_x, str(player.is_on_floor()), str(player.get_floor_normal()), slides,
			segment_label_at(player.global_position.x), describe_collisions(),
		]
		recent.append(record)
		if recent.size() > 6:
			recent.pop_front()

		if player.is_on_floor() and absf(player.velocity.x) >= STALL_MIN_VELOCITY_X and absf(motion_x) <= STALL_MAX_MOTION_X:
			stalled = true
			for line: String in recent:
				log.append(line)
			break

		if player.global_position.x > end_x:
			break

	Input.action_release("ui_accept")
	return {"min_motion_x": min_motion_x, "max_slides": max_slides, "stalled": stalled, "log": log}


func reset_player(warp_x: float) -> void:
	terrain_generator.position.y = 0.0
	var surface_y: float = terrain_generator.ground_y + terrain_generator.get_terrain_height(warp_x)
	player.global_position = Vector2(warp_x, surface_y - 24.0)
	player.velocity = Vector2(500.0, 0.0)
	player.speed_manager.current_speed = SpeedManager.MAX_SPEED
	player.coyote_timer = 0.0
	player.jump_buffer_timer = 0.0
	player.last_physics_displacement = Vector2.ZERO
	var player_chunk: int = int(floor(warp_x / terrain_generator.chunk_width))
	terrain_generator.next_chunk_index = player_chunk - terrain_generator.chunk_count_behind


func segment_label_at(world_x: float) -> String:
	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	return terrain_generator.get_segment_selection_label(terrain_generator.find_segment_index_at_x(world_x))


func describe_collisions() -> String:
	var text: String = ""
	for collision_index: int in range(player.get_slide_collision_count()):
		var collision: KinematicCollision2D = player.get_slide_collision(collision_index)
		text += " n%d=(%.6f,%.6f)@(%.3f,%.3f)" % [
			collision_index, collision.get_normal().x, collision.get_normal().y,
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
