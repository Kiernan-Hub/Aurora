extends SceneTree

# TEMPORARY audit tool (E1/E2). Instantiates main.tscn with a forced seed and
# dumps the authoritative terrain state so it can be diffed against an external
# reimplementation. Read-only with respect to game logic: no physics is stepped.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/model_validation_dump.gd -- \
#       --seed=2160065702 --window=226800 --span=512

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SESSION_SEED: int = 2160065702
const DEFAULT_WINDOW_CENTER: float = 226800.0
const DEFAULT_WINDOW_SPAN: float = 512.0
const COLLISION_GRID_STEP: float = 16.0


func _init() -> void:
	var session_seed: int = get_int_argument("--seed", DEFAULT_SESSION_SEED)
	var window_center: float = get_float_argument("--window", DEFAULT_WINDOW_CENTER)
	var window_span: float = get_float_argument("--span", DEFAULT_WINDOW_SPAN)

	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	root.add_child(main)

	# _ready() is deferred to the first frame when add_child happens inside
	# SceneTree._init(). Without this the segment cache is never initialized and
	# ensure_segment_cache_for_world_x spins forever on missing dictionary keys.
	await process_frame

	if terrain_generator.get_session_seed() != session_seed:
		print("DUMP_FATAL\tseed_mismatch\texpected=%d\tactual=%d" % [session_seed, terrain_generator.get_session_seed()])
		quit(1)
		return
	if terrain_generator.segment_start_x_cache.is_empty():
		print("DUMP_FATAL\tsegment_cache_empty")
		quit(1)
		return

	dump_environment(terrain_generator, player)
	dump_derived_constants(terrain_generator)
	dump_segments(terrain_generator, window_center + window_span + 4096.0)
	dump_heights(terrain_generator, window_center - window_span, window_center + window_span)
	dump_collision_vertices(terrain_generator, window_center)

	print("DUMP_END")
	main.queue_free()
	quit(0)


func dump_environment(terrain_generator: TerrainGenerator, player: Player) -> void:
	print("DUMP_ENV\tgodot_version\t%s" % Engine.get_version_info()["string"])
	print("DUMP_ENV\tsession_seed\t%d" % terrain_generator.get_session_seed())
	print("DUMP_ENV\tphysics_ticks_per_second\t%d" % Engine.physics_ticks_per_second)
	print("DUMP_ENV\tphysics_interpolation_setting\t%s" % str(ProjectSettings.get_setting("physics/common/physics_interpolation", false)))
	print("DUMP_ENV\tplayer_floor_max_angle_rad\t%.10f" % player.floor_max_angle)
	print("DUMP_ENV\tplayer_floor_max_angle_deg\t%.10f" % rad_to_deg(player.floor_max_angle))
	print("DUMP_ENV\tplayer_floor_snap_length\t%.10f" % player.floor_snap_length)
	print("DUMP_ENV\tplayer_safe_margin\t%.10f" % player.safe_margin)
	print("DUMP_ENV\tplayer_max_slides\t%d" % player.max_slides)
	print("DUMP_ENV\tplayer_motion_mode\t%d" % player.motion_mode)
	print("DUMP_ENV\tplayer_up_direction\t%s" % str(player.up_direction))
	print("DUMP_ENV\tplayer_floor_constant_speed\t%s" % str(player.floor_constant_speed))
	print("DUMP_ENV\tplayer_floor_stop_on_slope\t%s" % str(player.floor_stop_on_slope))
	print("DUMP_ENV\tsession_floor_max_angle\t%.10f" % terrain_generator.session_floor_max_angle)
	print("DUMP_ENV\tsession_floor_snap_length\t%.10f" % terrain_generator.session_floor_snap_length)
	print("DUMP_ENV\tchunk_width\t%.10f" % terrain_generator.chunk_width)
	print("DUMP_ENV\theight_sample_count\t%d" % terrain_generator.height_sample_count)
	print("DUMP_ENV\tsurface_y_offset\t%.10f" % terrain_generator.surface_y_offset)
	print("DUMP_ENV\tground_y\t%.10f" % terrain_generator.ground_y)

	var default_body: CharacterBody2D = CharacterBody2D.new()
	print("DUMP_ENV\tENGINE_DEFAULT_floor_max_angle_deg\t%.10f" % rad_to_deg(default_body.floor_max_angle))
	print("DUMP_ENV\tENGINE_DEFAULT_max_slides\t%d" % default_body.max_slides)
	print("DUMP_ENV\tENGINE_DEFAULT_safe_margin\t%.10f" % default_body.safe_margin)
	print("DUMP_ENV\tENGINE_DEFAULT_floor_snap_length\t%.10f" % default_body.floor_snap_length)
	default_body.free()


func dump_derived_constants(terrain_generator: TerrainGenerator) -> void:
	print("DUMP_DERIVED\tmega_drop_angle\t%.10f" % terrain_generator.get_mega_drop_angle())
	print("DUMP_DERIVED\tmega_drop_slope\t%.10f" % terrain_generator.get_mega_drop_slope())
	print("DUMP_DERIVED\tmega_drop_segment_length\t%.10f" % terrain_generator.get_mega_drop_segment_length())
	print("DUMP_DERIVED\tmega_drop_segment_vertical_drop\t%.10f" % terrain_generator.get_mega_drop_segment_vertical_drop())
	print("DUMP_DERIVED\tlarge_valley_drop_length\t%.10f" % terrain_generator.get_large_valley_drop_length())
	print("DUMP_DERIVED\tlarge_valley_rise_length\t%.10f" % terrain_generator.get_large_valley_rise_length())


func dump_segments(terrain_generator: TerrainGenerator, cache_through_world_x: float) -> void:
	terrain_generator.ensure_segment_cache_for_world_x(cache_through_world_x)
	var highest_index: int = terrain_generator.highest_cached_segment_index
	for segment_index: int in range(0, highest_index + 1):
		print("DUMP_SEG\t%d\t%.10f\t%.10f\t%.10f\t%s\t%d\t%d\t%s" % [
			segment_index,
			terrain_generator.segment_start_x_cache[segment_index],
			terrain_generator.get_segment_length(segment_index),
			terrain_generator.get_segment_baseline(segment_index),
			terrain_generator.get_segment_selection_label(segment_index),
			terrain_generator.get_segment_type(segment_index),
			terrain_generator.get_segment_tier(segment_index),
			str(terrain_generator.is_mega_drop_segment(segment_index)),
		])


func dump_heights(terrain_generator: TerrainGenerator, start_world_x: float, end_world_x: float) -> void:
	var world_x: float = start_world_x
	while world_x <= end_world_x:
		print("DUMP_H\t%.10f\t%.10f" % [world_x, terrain_generator.get_terrain_height(world_x)])
		world_x += 1.0


func dump_collision_vertices(terrain_generator: TerrainGenerator, window_center: float) -> void:
	# Reproduce exactly what build_chunk_surface feeds into ConcavePolygonShape2D
	# for the chunk containing window_center.
	var chunk_index: int = int(floor(window_center / terrain_generator.chunk_width))
	var chunk_start_x: float = float(chunk_index) * terrain_generator.chunk_width
	var chunk_end_x: float = chunk_start_x + terrain_generator.chunk_width
	var collision_sample_count: int = maxi(ceili(terrain_generator.chunk_width / COLLISION_GRID_STEP), 2)
	var sample_world_xs: Array[float] = terrain_generator.get_chunk_surface_sample_world_xs(
		chunk_start_x, chunk_end_x, collision_sample_count, true
	)
	print("DUMP_CHUNK\t%d\t%.10f\t%.10f\t%d" % [chunk_index, chunk_start_x, chunk_end_x, sample_world_xs.size()])
	for sample_index: int in range(sample_world_xs.size()):
		var world_x: float = sample_world_xs[sample_index]
		print("DUMP_V\t%d\t%.10f\t%.10f" % [sample_index, world_x, terrain_generator.get_terrain_height(world_x)])


func get_int_argument(argument_name: String, default_value: int) -> int:
	var raw_value: String = get_raw_argument(argument_name)
	if raw_value.is_empty():
		return default_value
	return raw_value.to_int()


func get_float_argument(argument_name: String, default_value: float) -> float:
	var raw_value: String = get_raw_argument(argument_name)
	if raw_value.is_empty():
		return default_value
	return raw_value.to_float()


func get_raw_argument(argument_name: String) -> String:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix)
	return ""
