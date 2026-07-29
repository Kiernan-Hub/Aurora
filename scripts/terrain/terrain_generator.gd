extends Node2D

class_name TerrainGenerator

const CHUNK_SCENE: PackedScene = preload("res://scenes/terrain/terrain_chunk.tscn")
const OBSTACLE_SCENE: PackedScene = preload("res://scenes/obstacles/obstacle.tscn")

@export var player_path: NodePath
@export var chunk_width: float = 512.0
@export var chunk_count_ahead: int = 6
@export var chunk_count_behind: int = 2
@export var ground_y: float = 192.0
@export var surface_y_offset: float = -32.0
@export var height_sample_count: int = 32
@export var debug_log_segment_selection: bool = false
@export var debug_replay_session_seed: int = -1

var player: CharacterBody2D
var next_chunk_index: int = 0
var active_chunks: Dictionary[int, Node2D] = {}
var last_obstacle_world_x: float = -1000000000.0
var session_seed: int = 0
var session_floor_snap_length: float = Player.FLOOR_SNAP_LENGTH
var session_floor_max_angle: float = 0.0
var segment_start_x_cache: Dictionary[int, float] = {}
var segment_length_cache: Dictionary[int, float] = {}
var segment_baseline_cache: Dictionary[int, float] = {}
var lowest_cached_segment_index: int = 0
var highest_cached_segment_index: int = 0

const LIGHT_CHUNK_COLOR: Color = Color(0.92, 0.97, 1.0)
const DARK_CHUNK_COLOR: Color = Color(0.78, 0.86, 0.93)
const SLOPE_SAMPLE_DISTANCE: float = 2.0
const MAX_COLLISION_SEGMENT_LENGTH: float = 16.0
const SEGMENT_TYPE_FLAT: int = 0
const SEGMENT_TYPE_HILL: int = 1
const SEGMENT_TYPE_VALLEY: int = 2
const SEGMENT_TYPE_DOWNHILL: int = 3
const SEGMENT_TYPE_UPHILL: int = 4
const SEGMENT_SELECTION_FLAT: int = 0
const SEGMENT_SELECTION_SMALL_HILL: int = 1
const SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX: int = 2
const SEGMENT_SELECTION_BIG_DOWNHILL: int = 3
const SEGMENT_SELECTION_GENTLE_UPHILL: int = 4
const SEGMENT_SELECTION_MEGA_DROP: int = 5
const SEGMENT_TIER_SMALL: int = 0
const SEGMENT_TIER_MEDIUM: int = 1
const SEGMENT_TIER_LARGE: int = 2
const SMALL_SEGMENT_LENGTH: float = 480.0
const MEDIUM_SEGMENT_LENGTH: float = 640.0
const SUSTAINED_DOWNHILL_LENGTH: float = 960.0
const SUSTAINED_DOWNHILL_DROP: float = 160.0
const GENTLE_UPHILL_LENGTH: float = SUSTAINED_DOWNHILL_LENGTH
const GENTLE_UPHILL_RISE: float = 28.0
const LARGE_VALLEY_DROP_LENGTH: float = 48.0
const LARGE_VALLEY_RISE_LENGTH: float = 420.0
const LARGE_VALLEY_FLOOR_LENGTH: float = 192.0
const LARGE_VALLEY_DEPTH: float = 180.0
const MEGA_DROP_TOTAL_VERTICAL_DROP: float = 1080.0
const MEGA_DROP_SEGMENT_COUNT: int = 4
const MEGA_DROP_FLOOR_ANGLE_FRACTION: float = 0.9
const MEGA_DROP_SELECTION_WEIGHT: int = 10
const TERRAIN_FILL_DEPTH_MARGIN: float = 4096.0
const SMALL_HILL_AMPLITUDE: float = 56.0
const MEDIUM_HILL_AMPLITUDE: float = 74.0
const SEGMENT_SELECTION_WEIGHT_TABLE: Array[Dictionary] = [
	{"selection": SEGMENT_SELECTION_FLAT, "weight": 16},
	{"selection": SEGMENT_SELECTION_SMALL_HILL, "weight": 16},
	{"selection": SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX, "weight": 42},
	{"selection": SEGMENT_SELECTION_BIG_DOWNHILL, "weight": 16},
	{"selection": SEGMENT_SELECTION_GENTLE_UPHILL, "weight": 10},
	{"selection": SEGMENT_SELECTION_MEGA_DROP, "weight": MEGA_DROP_SELECTION_WEIGHT},
]
const HASH_MASK: int = 0x7fffffff
const HASH_INDEX_MULTIPLIER: int = 374761393
const HASH_MIX_MULTIPLIER: int = 668265263
const MIN_SAFE_START_DISTANCE: float = 440.0
const MIN_OBSTACLE_GAP: float = 250.0
const OBSTACLE_EDGE_PADDING: float = 24.0
const OBSTACLE_SURFACE_Y_OFFSET: float = -16.0
const DEBUG_TERRAIN_LOGGING: bool = false
const DEBUG_SEGMENT_SELECTION_LOG_COUNT: int = 80


func _ready() -> void:
	player = get_node(player_path) as CharacterBody2D
	if player == null:
		push_error("TerrainGenerator requires a valid player_path.")
		set_physics_process(false)
		return

	session_seed = get_initial_session_seed()
	session_floor_snap_length = player.floor_snap_length
	session_floor_max_angle = player.floor_max_angle
	initialize_segment_cache()
	if debug_log_segment_selection:
		log_debug_segment_selection(0, DEBUG_SEGMENT_SELECTION_LOG_COUNT)
	initialize_chunks()


func get_initial_session_seed() -> int:
	if debug_replay_session_seed >= 0:
		print("Terrain replay seed: ", debug_replay_session_seed)
		return debug_replay_session_seed
	return create_session_seed()


func get_session_seed() -> int:
	return session_seed


func _physics_process(_delta: float) -> void:
	if player == null:
		return

	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	var target_chunk_index: int = player_chunk_index + chunk_count_ahead
	var despawn_chunk_index: int = player_chunk_index - chunk_count_behind

	while next_chunk_index <= target_chunk_index:
		spawn_chunk(next_chunk_index)
		next_chunk_index += 1

	var chunk_indices: Array[int] = active_chunks.keys()
	for chunk_index: int in chunk_indices:
		if chunk_index < despawn_chunk_index:
			remove_chunk(chunk_index)


func initialize_chunks() -> void:
	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	next_chunk_index = player_chunk_index - chunk_count_behind
	for chunk_index: int in range(player_chunk_index - chunk_count_behind, player_chunk_index + chunk_count_ahead + 1):
		spawn_chunk(chunk_index)
	next_chunk_index = player_chunk_index + chunk_count_ahead + 1


func spawn_chunk(chunk_index: int) -> void:
	if active_chunks.has(chunk_index):
		return

	var chunk: StaticBody2D = CHUNK_SCENE.instantiate() as StaticBody2D
	if chunk == null:
		push_error("Failed to instance terrain chunk scene.")
		return

	chunk.position = Vector2((float(chunk_index) * chunk_width) + (chunk_width * 0.5), ground_y)
	build_chunk_surface(chunk, chunk_index)
	# spawn_chunk_obstacle(chunk, chunk_index)
	apply_chunk_color(chunk, chunk_index)
	add_child(chunk)
	active_chunks[chunk_index] = chunk
	if DEBUG_TERRAIN_LOGGING:
		print("spawn chunk ", chunk_index)


func remove_chunk(chunk_index: int) -> void:
	if not active_chunks.has(chunk_index):
		return

	var chunk: Node2D = active_chunks[chunk_index]
	active_chunks.erase(chunk_index)
	chunk.free()
	if DEBUG_TERRAIN_LOGGING:
		print("free chunk ", chunk_index)


func spawn_chunk_obstacle(chunk: StaticBody2D, chunk_index: int) -> void:
	if is_chunk_overlapping_mega_drop(chunk_index):
		return

	var half_chunk_width: float = chunk_width * 0.5
	var usable_half_width: float = maxi(half_chunk_width - OBSTACLE_EDGE_PADDING, 0.0)
	var obstacle_local_x_offset: float = randf_range(-usable_half_width, usable_half_width)
	var obstacle_world_x: float = (float(chunk_index) * chunk_width) + (chunk_width * 0.5) + obstacle_local_x_offset
	if obstacle_world_x < MIN_SAFE_START_DISTANCE:
		return
	if is_world_x_in_mega_drop(obstacle_world_x):
		return

	if obstacle_world_x - last_obstacle_world_x < MIN_OBSTACLE_GAP:
		return

	var obstacle: Area2D = OBSTACLE_SCENE.instantiate() as Area2D
	if obstacle == null:
		push_error("Failed to instance obstacle scene.")
		return

	var surface_height: float = get_terrain_height(obstacle_world_x)
	obstacle.position = Vector2(obstacle_local_x_offset, surface_height + OBSTACLE_SURFACE_Y_OFFSET)
	chunk.add_child(obstacle)
	last_obstacle_world_x = obstacle_world_x


func build_chunk_surface(chunk: StaticBody2D, chunk_index: int) -> void:
	var collision_shape: CollisionShape2D = chunk.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var terrain_fill: Polygon2D = chunk.get_node_or_null("TerrainFill") as Polygon2D
	if collision_shape == null or terrain_fill == null:
		push_error("TerrainChunk requires CollisionShape2D and TerrainFill nodes.")
		return

	var surface_points: PackedVector2Array = PackedVector2Array()
	var segment_points: PackedVector2Array = PackedVector2Array()
	var chunk_start_x: float = float(chunk_index) * chunk_width
	var chunk_end_x: float = chunk_start_x + chunk_width
	var visual_sample_count: int = maxi(height_sample_count, 2)
	var collision_sample_count: int = maxi(ceili(chunk_width / MAX_COLLISION_SEGMENT_LENGTH), 2)
	var visual_sample_world_xs: Array[float] = get_chunk_surface_sample_world_xs(chunk_start_x, chunk_end_x, visual_sample_count, true)
	var collision_sample_world_xs: Array[float] = get_chunk_surface_sample_world_xs(chunk_start_x, chunk_end_x, collision_sample_count, true)
	var previous_collision_point: Vector2 = Vector2.ZERO

	for world_x: float in visual_sample_world_xs:
		var local_x: float = world_x - chunk_start_x - (chunk_width * 0.5)
		var surface_point: Vector2 = Vector2(local_x, get_terrain_height(world_x))
		surface_points.append(surface_point)

	for sample_index: int in range(collision_sample_world_xs.size()):
		var world_x: float = collision_sample_world_xs[sample_index]
		var local_x: float = world_x - chunk_start_x - (chunk_width * 0.5)
		var point: Vector2 = Vector2(local_x, get_terrain_height(world_x))
		if sample_index > 0:
			segment_points.append(previous_collision_point)
			segment_points.append(point)
		previous_collision_point = point

	var collision: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
	collision.set_segments(segment_points)
	collision_shape.shape = collision

	var fill_points: PackedVector2Array = surface_points.duplicate()
	var fill_bottom_y: float = get_fill_bottom_y(surface_points)
	fill_points.append(Vector2(chunk_width * 0.5, fill_bottom_y))
	fill_points.append(Vector2(-chunk_width * 0.5, fill_bottom_y))
	terrain_fill.polygon = fill_points


func get_fill_bottom_y(surface_points: PackedVector2Array) -> float:
	var max_surface_y: float = surface_points[0].y
	for surface_point: Vector2 in surface_points:
		max_surface_y = maxf(max_surface_y, surface_point.y)
	return max_surface_y + TERRAIN_FILL_DEPTH_MARGIN


func get_chunk_surface_sample_world_xs(chunk_start_x: float, chunk_end_x: float, sample_count: int, include_segment_boundaries: bool) -> Array[float]:
	var sample_world_xs: Array[float] = []
	var safe_sample_count: int = maxi(sample_count, 2)
	for sample_index: int in range(safe_sample_count + 1):
		var progress: float = float(sample_index) / float(safe_sample_count)
		add_unique_sample_world_x(sample_world_xs, chunk_start_x + (progress * (chunk_end_x - chunk_start_x)))

	if include_segment_boundaries:
		add_segment_boundary_sample_world_xs(sample_world_xs, chunk_start_x, chunk_end_x)

	sample_world_xs.sort()
	return sample_world_xs


func add_segment_boundary_sample_world_xs(sample_world_xs: Array[float], chunk_start_x: float, chunk_end_x: float) -> void:
	ensure_segment_cache_for_world_x(chunk_start_x)
	ensure_segment_cache_for_world_x(chunk_end_x)
	var first_segment_index: int = find_segment_index_at_x(chunk_start_x)
	var last_segment_index: int = find_segment_index_at_x(chunk_end_x - 0.001)
	for segment_index: int in range(first_segment_index + 1, last_segment_index + 1):
		add_unique_sample_world_x(sample_world_xs, segment_start_x_cache[segment_index])


func add_unique_sample_world_x(sample_world_xs: Array[float], world_x: float) -> void:
	for existing_world_x: float in sample_world_xs:
		if absf(existing_world_x - world_x) <= 0.001:
			return
	sample_world_xs.append(world_x)


func get_terrain_height(world_x: float) -> float:
	ensure_segment_cache_for_world_x(world_x)
	var segment_index: int = find_segment_index_at_x(world_x)
	var segment_start_x: float = segment_start_x_cache[segment_index]

	var segment_x: float = world_x - segment_start_x
	var segment_type: int = get_segment_type(segment_index)
	var segment_baseline: float = get_segment_baseline(segment_index)
	if segment_type == SEGMENT_TYPE_FLAT:
		return segment_baseline
	if segment_type == SEGMENT_TYPE_DOWNHILL and is_mega_drop_segment(segment_index):
		return segment_baseline + (get_mega_drop_slope() * segment_x)
	if segment_type == SEGMENT_TYPE_DOWNHILL:
		var downhill_progress: float = segment_x / SUSTAINED_DOWNHILL_LENGTH
		return segment_baseline + (get_transition_profile(downhill_progress) * SUSTAINED_DOWNHILL_DROP)
	if segment_type == SEGMENT_TYPE_UPHILL:
		var uphill_progress: float = segment_x / GENTLE_UPHILL_LENGTH
		return segment_baseline - (get_transition_profile(uphill_progress) * GENTLE_UPHILL_RISE)
	if segment_type == SEGMENT_TYPE_VALLEY and get_segment_tier(segment_index) == SEGMENT_TIER_LARGE:
		return get_large_valley_height(segment_x, segment_baseline)

	var segment_progress: float = segment_x / get_segment_length(segment_index)
	var hill_amplitude: float = get_segment_amplitude(segment_index)
	if segment_type == SEGMENT_TYPE_HILL:
		# Godot's Y axis points down, so subtracting raises the hill visually.
		return segment_baseline - (get_curve_profile(segment_progress) * hill_amplitude)

	# Adding the same profile mirrors the hill into a valley below baseline.
	return segment_baseline + (get_curve_profile(segment_progress) * hill_amplitude)


func get_large_valley_height(segment_x: float, segment_baseline: float) -> float:
	var drop_length: float = get_large_valley_drop_length()
	if segment_x < drop_length:
		return segment_baseline + (get_transition_profile(segment_x / drop_length) * LARGE_VALLEY_DEPTH)

	var floor_end_x: float = drop_length + LARGE_VALLEY_FLOOR_LENGTH
	if segment_x <= floor_end_x:
		return segment_baseline + LARGE_VALLEY_DEPTH

	var rise_length: float = get_large_valley_rise_length()
	var rise_progress: float = (segment_x - floor_end_x) / rise_length
	return segment_baseline + ((1.0 - get_transition_profile(rise_progress)) * LARGE_VALLEY_DEPTH)


# World-space Y of the terrain surface at world_x. get_terrain_height() alone is a
# local offset from ground_y; this adds the generator's own Y, which world rebasing
# moves, so callers outside the chunk hierarchy get a coordinate they can compare
# against global_position.
func get_surface_world_y(world_x: float) -> float:
	return global_position.y + ground_y + get_terrain_height(world_x)


func get_segment_baseline(segment_index: int) -> float:
	ensure_segment_cache_through(segment_index)
	return segment_baseline_cache[segment_index]


func initialize_segment_cache() -> void:
	segment_start_x_cache.clear()
	segment_length_cache.clear()
	segment_baseline_cache.clear()
	segment_start_x_cache[0] = 0.0
	segment_length_cache[0] = get_segment_length(0)
	segment_baseline_cache[0] = surface_y_offset
	lowest_cached_segment_index = 0
	highest_cached_segment_index = 0


func ensure_segment_cache_for_world_x(world_x: float) -> void:
	if world_x >= 0.0:
		while world_x >= get_cached_segment_end_x(highest_cached_segment_index):
			cache_next_segment()
	else:
		while world_x < segment_start_x_cache[lowest_cached_segment_index]:
			cache_previous_segment()


func ensure_segment_cache_through(segment_index: int) -> void:
	while highest_cached_segment_index < segment_index:
		cache_next_segment()
	while lowest_cached_segment_index > segment_index:
		cache_previous_segment()


func cache_next_segment() -> void:
	var previous_segment_index: int = highest_cached_segment_index
	var segment_index: int = previous_segment_index + 1
	var segment_start_x: float = get_cached_segment_end_x(previous_segment_index)
	segment_start_x_cache[segment_index] = segment_start_x
	segment_length_cache[segment_index] = get_segment_length(segment_index)
	segment_baseline_cache[segment_index] = segment_baseline_cache[previous_segment_index] + get_segment_baseline_delta(previous_segment_index)
	highest_cached_segment_index = segment_index


func cache_previous_segment() -> void:
	var next_segment_index: int = lowest_cached_segment_index
	var segment_index: int = next_segment_index - 1
	var segment_length: float = get_segment_length(segment_index)
	segment_start_x_cache[segment_index] = segment_start_x_cache[next_segment_index] - segment_length
	segment_length_cache[segment_index] = segment_length
	segment_baseline_cache[segment_index] = segment_baseline_cache[next_segment_index] - get_segment_baseline_delta(segment_index)
	lowest_cached_segment_index = segment_index


func get_cached_segment_end_x(segment_index: int) -> float:
	return segment_start_x_cache[segment_index] + segment_length_cache[segment_index]


func find_segment_index_at_x(world_x: float) -> int:
	var lower_index: int = lowest_cached_segment_index
	var upper_index: int = highest_cached_segment_index
	while lower_index <= upper_index:
		var middle_index: int = floori(float(lower_index + upper_index) / 2.0)
		var middle_start_x: float = segment_start_x_cache[middle_index]
		var middle_end_x: float = get_cached_segment_end_x(middle_index)
		if world_x < middle_start_x:
			upper_index = middle_index - 1
		elif world_x >= middle_end_x:
			lower_index = middle_index + 1
		else:
			return middle_index
	return clampi(lower_index, lowest_cached_segment_index, highest_cached_segment_index)


func get_segment_baseline_delta(segment_index: int) -> float:
	if is_mega_drop_segment(segment_index):
		return get_mega_drop_segment_vertical_drop()

	var segment_type: int = get_segment_type(segment_index)
	if segment_type == SEGMENT_TYPE_DOWNHILL:
		return SUSTAINED_DOWNHILL_DROP
	if segment_type == SEGMENT_TYPE_UPHILL:
		return -GENTLE_UPHILL_RISE
	return 0.0


func get_segment_tier(segment_index: int) -> int:
	var segment_selection: int = get_segment_selection(segment_index)
	if segment_selection == SEGMENT_SELECTION_SMALL_HILL:
		return SEGMENT_TIER_SMALL
	if segment_selection == SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX and get_medium_mix_segment_type(segment_index) == SEGMENT_TYPE_VALLEY:
		var tier_random_value: int = get_segment_hash(segment_index) >> 4
		if tier_random_value % 2 == 0:
			return SEGMENT_TIER_LARGE
	return SEGMENT_TIER_MEDIUM


func get_segment_length(segment_index: int) -> float:
	if is_mega_drop_segment(segment_index):
		return get_mega_drop_segment_length()

	if get_segment_type(segment_index) == SEGMENT_TYPE_FLAT:
		return MEDIUM_SEGMENT_LENGTH
	if get_segment_type(segment_index) == SEGMENT_TYPE_DOWNHILL:
		return SUSTAINED_DOWNHILL_LENGTH
	if get_segment_type(segment_index) == SEGMENT_TYPE_UPHILL:
		return GENTLE_UPHILL_LENGTH
	if get_segment_type(segment_index) == SEGMENT_TYPE_VALLEY and get_segment_tier(segment_index) == SEGMENT_TIER_LARGE:
		return get_large_valley_drop_length() + LARGE_VALLEY_FLOOR_LENGTH + get_large_valley_rise_length()
	if get_segment_tier(segment_index) == SEGMENT_TIER_SMALL:
		return SMALL_SEGMENT_LENGTH
	return MEDIUM_SEGMENT_LENGTH


func get_segment_amplitude(segment_index: int) -> float:
	if get_segment_tier(segment_index) == SEGMENT_TIER_SMALL:
		return SMALL_HILL_AMPLITUDE
	return MEDIUM_HILL_AMPLITUDE


func get_large_valley_drop_length() -> float:
	var physics_delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	var target_drop_per_tick: float = session_floor_snap_length + (0.5 * Player.GRAVITY * physics_delta * physics_delta)
	var target_slope: float = (target_drop_per_tick / (SpeedManager.INITIAL_SPEED * physics_delta)) * 1.1
	var maximum_drop_length: float = (LARGE_VALLEY_DEPTH * PI) / (target_slope * 2.0)
	return minf(LARGE_VALLEY_DROP_LENGTH, maximum_drop_length)


func get_large_valley_rise_length() -> float:
	return maxf(LARGE_VALLEY_RISE_LENGTH, get_large_valley_drop_length())


func is_mega_drop_segment(segment_index: int) -> bool:
	for segment_offset: int in range(MEGA_DROP_SEGMENT_COUNT):
		if is_mega_drop_start_segment(segment_index - segment_offset):
			return true
	return false


func is_mega_drop_start_segment(segment_index: int) -> bool:
	if get_segment_selection(segment_index) != SEGMENT_SELECTION_MEGA_DROP:
		return false
	for segment_offset: int in range(1, MEGA_DROP_SEGMENT_COUNT):
		if is_mega_drop_start_segment(segment_index - segment_offset):
			return false
	return true


func get_mega_drop_angle() -> float:
	return session_floor_max_angle * MEGA_DROP_FLOOR_ANGLE_FRACTION


func get_mega_drop_slope() -> float:
	return tan(get_mega_drop_angle())


func get_mega_drop_segment_vertical_drop() -> float:
	return MEGA_DROP_TOTAL_VERTICAL_DROP / float(MEGA_DROP_SEGMENT_COUNT)


func get_mega_drop_segment_length() -> float:
	var slope: float = get_mega_drop_slope()
	if slope <= 0.0:
		return MEGA_DROP_TOTAL_VERTICAL_DROP / float(MEGA_DROP_SEGMENT_COUNT)
	return get_mega_drop_segment_vertical_drop() / slope


func is_world_x_in_mega_drop(world_x: float) -> bool:
	ensure_segment_cache_for_world_x(world_x)
	return is_mega_drop_segment(find_segment_index_at_x(world_x))


func is_chunk_overlapping_mega_drop(chunk_index: int) -> bool:
	var chunk_start_x: float = float(chunk_index) * chunk_width
	var chunk_end_x: float = chunk_start_x + chunk_width
	ensure_segment_cache_for_world_x(chunk_start_x)
	ensure_segment_cache_for_world_x(chunk_end_x)
	var first_segment_index: int = find_segment_index_at_x(chunk_start_x)
	var last_segment_index: int = find_segment_index_at_x(chunk_end_x - 0.001)
	for segment_index: int in range(first_segment_index, last_segment_index + 1):
		if is_mega_drop_segment(segment_index):
			return true
	return false


func create_session_seed() -> int:
	var seed_generator: RandomNumberGenerator = RandomNumberGenerator.new()
	seed_generator.randomize()
	return int(seed_generator.randi())


func get_segment_type(segment_index: int) -> int:
	if is_mega_drop_segment(segment_index):
		return SEGMENT_TYPE_DOWNHILL

	var segment_selection: int = get_segment_selection(segment_index)
	if segment_selection == SEGMENT_SELECTION_FLAT:
		return SEGMENT_TYPE_FLAT
	if segment_selection == SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX:
		return get_medium_mix_segment_type(segment_index)
	if segment_selection == SEGMENT_SELECTION_BIG_DOWNHILL:
		return SEGMENT_TYPE_DOWNHILL
	if segment_selection == SEGMENT_SELECTION_GENTLE_UPHILL:
		return SEGMENT_TYPE_UPHILL
	if segment_selection == SEGMENT_SELECTION_MEGA_DROP:
		return SEGMENT_TYPE_DOWNHILL
	return SEGMENT_TYPE_HILL


func get_segment_selection(segment_index: int) -> int:
	var segment_selection: int = get_unconstrained_segment_selection(segment_index)
	if segment_selection != SEGMENT_SELECTION_FLAT:
		return segment_selection

	var previous_segment_selection: int = get_unconstrained_segment_selection(segment_index - 1)
	if previous_segment_selection != SEGMENT_SELECTION_FLAT:
		return segment_selection

	return get_non_flat_segment_selection(segment_index)


func get_unconstrained_segment_selection(segment_index: int) -> int:
	return get_weighted_segment_selection(get_segment_hash(segment_index))


func get_non_flat_segment_selection(segment_index: int) -> int:
	var total_weight: int = get_segment_selection_total_weight(false)
	var random_value: int = (get_segment_hash(segment_index) >> 8) % total_weight
	var accumulated_weight: int = 0
	for entry: Dictionary in SEGMENT_SELECTION_WEIGHT_TABLE:
		var selection: int = int(entry["selection"])
		var weight: int = int(entry["weight"])
		if selection == SEGMENT_SELECTION_FLAT or weight <= 0:
			continue
		accumulated_weight += weight
		if random_value < accumulated_weight:
			return selection
	return SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX


func get_weighted_segment_selection(random_value: int) -> int:
	var total_weight: int = get_segment_selection_total_weight(true)
	var weighted_value: int = random_value % total_weight
	var accumulated_weight: int = 0
	for entry: Dictionary in SEGMENT_SELECTION_WEIGHT_TABLE:
		var weight: int = int(entry["weight"])
		if weight <= 0:
			continue
		accumulated_weight += weight
		if weighted_value < accumulated_weight:
			return int(entry["selection"])
	return SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX


func get_segment_selection_total_weight(include_flat: bool) -> int:
	var total_weight: int = 0
	for entry: Dictionary in SEGMENT_SELECTION_WEIGHT_TABLE:
		var selection: int = int(entry["selection"])
		var weight: int = int(entry["weight"])
		if weight <= 0:
			continue
		if not include_flat and selection == SEGMENT_SELECTION_FLAT:
			continue
		total_weight += weight
	return maxi(total_weight, 1)


func get_medium_mix_segment_type(segment_index: int) -> int:
	var random_value: int = get_segment_hash(segment_index) >> 8
	if random_value % 2 == 0:
		return SEGMENT_TYPE_HILL
	return SEGMENT_TYPE_VALLEY


func get_segment_hash(segment_index: int) -> int:
	var mixed_value: int = (session_seed ^ (segment_index * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return mixed_value


func get_curve_profile(segment_progress: float) -> float:
	return pow(sin(segment_progress * PI), 2.0)


func get_transition_profile(segment_progress: float) -> float:
	return 0.5 - (0.5 * cos(segment_progress * PI))


func log_debug_segment_selection(start_segment_index: int, segment_count: int) -> void:
	print("Terrain segment selection debug: session_seed=", session_seed)
	for segment_index: int in range(start_segment_index, start_segment_index + segment_count):
		print(
			"segment ",
			segment_index,
			": ",
			get_segment_selection_label(segment_index)
		)


func get_segment_selection_label(segment_index: int) -> String:
	if is_mega_drop_segment(segment_index):
		if is_mega_drop_start_segment(segment_index):
			return "mega_drop_start"
		return "mega_drop"

	var segment_selection: int = get_segment_selection(segment_index)
	if segment_selection == SEGMENT_SELECTION_FLAT:
		return "flat"
	if segment_selection == SEGMENT_SELECTION_SMALL_HILL:
		return "small_hill"
	if segment_selection == SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX:
		if get_medium_mix_segment_type(segment_index) == SEGMENT_TYPE_HILL:
			return "medium_hill"
		if get_segment_tier(segment_index) == SEGMENT_TIER_LARGE:
			return "large_valley"
		return "medium_valley"
	if segment_selection == SEGMENT_SELECTION_BIG_DOWNHILL:
		return "sustained_downhill"
	if segment_selection == SEGMENT_SELECTION_GENTLE_UPHILL:
		return "gentle_uphill"
	if segment_selection == SEGMENT_SELECTION_MEGA_DROP:
		return "mega_drop_start"
	return "unknown"


func get_slope_angle_at_x(world_x: float) -> float:
	var left_height: float = get_terrain_height(world_x - SLOPE_SAMPLE_DISTANCE)
	var right_height: float = get_terrain_height(world_x + SLOPE_SAMPLE_DISTANCE)
	return atan2(right_height - left_height, SLOPE_SAMPLE_DISTANCE * 2.0)


func apply_chunk_color(chunk: StaticBody2D, chunk_index: int) -> void:
	var terrain_fill: Polygon2D = chunk.get_node_or_null("TerrainFill") as Polygon2D
	if terrain_fill == null:
		return

	if chunk_index % 2 == 0:
		terrain_fill.color = LIGHT_CHUNK_COLOR
	else:
		terrain_fill.color = DARK_CHUNK_COLOR
