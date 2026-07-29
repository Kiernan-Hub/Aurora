extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SESSION_SEED: int = 941462462
const DEFAULT_RUN_COUNT: int = 1
# 60000 frames is ~16.7 minutes of play, ~500,000 world_x. Every freeze recorded so
# far sits beyond world_x 175,000, i.e. past frame ~25,000 -- the old 400-frame
# default covered 0.4% of that distance and reported no_freeze regardless.
const DEFAULT_MAX_PHYSICS_FRAMES: int = 60000
const DEFAULT_HISTORY_FRAME_COUNT: int = 20
const PROGRESS_FRAME_INTERVAL: int = 5000


func _init() -> void:
	var session_seed: int = get_int_argument("--seed", DEFAULT_SESSION_SEED)
	var run_count: int = maxi(get_int_argument("--runs", DEFAULT_RUN_COUNT), 1)
	var max_physics_frames: int = maxi(get_int_argument("--frames", DEFAULT_MAX_PHYSICS_FRAMES), 1)
	# Defaults to the shipping configuration. Pass --rebase=0 to A/B against the
	# broken one; world_rebase_enabled is no longer exported, so this is the only
	# way to disable it.
	var rebase_enabled: bool = get_int_argument("--rebase", 1) == 1
	for run_index: int in range(run_count):
		var main: Node = MAIN_SCENE.instantiate()
		var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
		var player: Player = main.get_node("Player") as Player
		terrain_generator.debug_replay_session_seed = session_seed
		player.DEBUG_LOG_FREEZE_REPRO = true
		player.DEBUG_FREEZE_HISTORY_FRAME_COUNT = DEFAULT_HISTORY_FRAME_COUNT
		(main as Main).world_rebase_enabled = rebase_enabled
		root.add_child(main)

		var event_count_at_run_start: int = player.debug_freeze_event_count
		var completed_frames: int = max_physics_frames
		for frame_index: int in range(max_physics_frames):
			await physics_frame
			if (frame_index + 1) % PROGRESS_FRAME_INTERVAL == 0:
				print("FREEZE_REPLAY_PROGRESS frame=", frame_index + 1, " world_x=%.1f" % player.global_position.x, " world_y=%.1f" % player.global_position.y)
			if player.debug_freeze_event_count > event_count_at_run_start:
				completed_frames = frame_index + 1
				print("FREEZE_REPLAY_RUN_RESULT run=", run_index + 1, " seed=", session_seed, " rebase=", int(rebase_enabled), " status=freeze_detected frame=", completed_frames)
				break
			if paused:
				completed_frames = frame_index + 1
				print("FREEZE_REPLAY_RUN_RESULT run=", run_index + 1, " seed=", session_seed, " rebase=", int(rebase_enabled), " status=tree_paused frame=", completed_frames)
				break

		if player.debug_freeze_event_count == event_count_at_run_start and not paused:
			# A recovery means the watchdog had to unwedge the player, i.e. a stall
			# still happened -- that is a failure, not a pass.
			var status: String = "no_freeze" if player.debug_stall_recovery_count == 0 else "stall_recovered"
			print("FREEZE_REPLAY_RUN_RESULT run=", run_index + 1, " seed=", session_seed, " rebase=", int(rebase_enabled), " status=", status, " frames=", completed_frames, " stall_recoveries=", player.debug_stall_recovery_count, " world_x=%.1f" % player.global_position.x)
		main.queue_free()
		await process_frame
		paused = false

	quit(0)


func get_int_argument(argument_name: String, default_value: int) -> int:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_int()
	return default_value
