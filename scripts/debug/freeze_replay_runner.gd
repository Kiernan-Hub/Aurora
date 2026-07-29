extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SESSION_SEED: int = 2160065702
const DEFAULT_RUN_COUNT: int = 1
const DEFAULT_MAX_PHYSICS_FRAMES: int = 36000
const DEFAULT_HISTORY_FRAME_COUNT: int = 20


func _init() -> void:
	var session_seed: int = get_int_argument("--seed", DEFAULT_SESSION_SEED)
	var run_count: int = maxi(get_int_argument("--runs", DEFAULT_RUN_COUNT), 1)
	var max_physics_frames: int = maxi(get_int_argument("--frames", DEFAULT_MAX_PHYSICS_FRAMES), 1)
	for run_index: int in range(run_count):
		var main: Node = MAIN_SCENE.instantiate()
		var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
		var player: Player = main.get_node("Player") as Player
		terrain_generator.debug_replay_session_seed = session_seed
		player.DEBUG_LOG_FREEZE_REPRO = true
		player.DEBUG_FREEZE_HISTORY_FRAME_COUNT = DEFAULT_HISTORY_FRAME_COUNT
		root.add_child(main)

		var event_count_at_run_start: int = player.debug_freeze_event_count
		for frame_index: int in range(max_physics_frames):
			await physics_frame
			if player.debug_freeze_event_count > event_count_at_run_start:
				print("FREEZE_REPLAY_RUN_RESULT run=", run_index + 1, " seed=", session_seed, " status=freeze_detected frame=", frame_index + 1)
				break
			if paused:
				print("FREEZE_REPLAY_RUN_RESULT run=", run_index + 1, " seed=", session_seed, " status=tree_paused frame=", frame_index + 1)
				break

		if player.debug_freeze_event_count == event_count_at_run_start and not paused:
			print("FREEZE_REPLAY_RUN_RESULT run=", run_index + 1, " seed=", session_seed, " status=no_freeze frames=", max_physics_frames)
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
