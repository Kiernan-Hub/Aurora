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
@export var terrain_depth: float = 600.0

var player: CharacterBody2D
var next_chunk_index: int = 0
var active_chunks: Dictionary[int, Node2D] = {}
var last_obstacle_world_x: float = -1000000000.0
var session_seed: int = 0

const LIGHT_CHUNK_COLOR: Color = Color(0.92, 0.97, 1.0)
const DARK_CHUNK_COLOR: Color = Color(0.78, 0.86, 0.93)
const SLOPE_SAMPLE_DISTANCE: float = 2.0
const MAX_COLLISION_SEGMENT_LENGTH: float = 16.0
const SEGMENT_TYPE_FLAT: int = 0
const SEGMENT_TYPE_HILL: int = 1
const SEGMENT_TYPE_VALLEY: int = 2
const SEGMENT_TIER_SMALL: int = 0
const SEGMENT_TIER_MEDIUM: int = 1
const SMALL_SEGMENT_LENGTH: float = 480.0
const MEDIUM_SEGMENT_LENGTH: float = 640.0
const SMALL_HILL_AMPLITUDE: float = 28.0
const MEDIUM_HILL_AMPLITUDE: float = 46.0
const FLAT_WEIGHT_PERCENT: int = 15
const HILL_WEIGHT_PERCENT: int = 43
const HASH_MASK: int = 0x7fffffff
const HASH_INDEX_MULTIPLIER: int = 374761393
const HASH_MIX_MULTIPLIER: int = 668265263
const MIN_SAFE_START_DISTANCE: float = 440.0
const MIN_OBSTACLE_GAP: float = 250.0
const OBSTACLE_EDGE_PADDING: float = 24.0
const OBSTACLE_SURFACE_Y_OFFSET: float = -16.0
const DEBUG_TERRAIN_LOGGING: bool = false


func _ready() -> void:
	player = get_node(player_path) as CharacterBody2D
	if player == null:
		push_error("TerrainGenerator requires a valid player_path.")
		set_physics_process(false)
		return

	session_seed = create_session_seed()
	initialize_chunks()


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
	spawn_chunk_obstacle(chunk, chunk_index)
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
	var obstacle: Area2D = OBSTACLE_SCENE.instantiate() as Area2D
	if obstacle == null:
		push_error("Failed to instance obstacle scene.")
		return

	var half_chunk_width: float = chunk_width * 0.5
	var usable_half_width: float = maxi(half_chunk_width - OBSTACLE_EDGE_PADDING, 0.0)
	var obstacle_local_x_offset: float = randf_range(-usable_half_width, usable_half_width)
	var obstacle_world_x: float = (float(chunk_index) * chunk_width) + (chunk_width * 0.5) + obstacle_local_x_offset
	if obstacle_world_x < MIN_SAFE_START_DISTANCE:
		return

	if obstacle_world_x - last_obstacle_world_x < MIN_OBSTACLE_GAP:
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
	var visual_sample_count: int = maxi(height_sample_count, 2)
	var collision_sample_count: int = maxi(ceili(chunk_width / MAX_COLLISION_SEGMENT_LENGTH), 2)
	var previous_collision_point: Vector2 = Vector2.ZERO

	for sample_index: int in range(visual_sample_count + 1):
		var progress: float = float(sample_index) / float(visual_sample_count)
		var world_x: float = chunk_start_x + (progress * chunk_width)
		var local_x: float = (progress * chunk_width) - (chunk_width * 0.5)
		surface_points.append(Vector2(local_x, get_terrain_height(world_x)))

	for sample_index: int in range(collision_sample_count + 1):
		var progress: float = float(sample_index) / float(collision_sample_count)
		var world_x: float = chunk_start_x + (progress * chunk_width)
		var local_x: float = (progress * chunk_width) - (chunk_width * 0.5)
		var point: Vector2 = Vector2(local_x, get_terrain_height(world_x))
		if sample_index > 0:
			segment_points.append(previous_collision_point)
			segment_points.append(point)
		previous_collision_point = point

	var collision: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
	collision.set_segments(segment_points)
	collision_shape.shape = collision

	var fill_points: PackedVector2Array = surface_points.duplicate()
	fill_points.append(Vector2(chunk_width * 0.5, terrain_depth))
	fill_points.append(Vector2(-chunk_width * 0.5, terrain_depth))
	terrain_fill.polygon = fill_points


func get_terrain_height(world_x: float) -> float:
	var segment_index: int = 0
	var segment_start_x: float = 0.0
	if world_x >= 0.0:
		while world_x >= segment_start_x + get_segment_length(segment_index):
			segment_start_x += get_segment_length(segment_index)
			segment_index += 1
	else:
		while world_x < segment_start_x:
			segment_index -= 1
			segment_start_x -= get_segment_length(segment_index)

	var segment_x: float = world_x - segment_start_x
	var segment_type: int = get_segment_type(segment_index)
	if segment_type == SEGMENT_TYPE_FLAT:
		return surface_y_offset

	var segment_progress: float = segment_x / get_segment_length(segment_index)
	var hill_amplitude: float = get_segment_amplitude(segment_index)
	if segment_type == SEGMENT_TYPE_HILL:
		# Godot's Y axis points down, so subtracting raises the hill visually.
		return surface_y_offset - (get_curve_profile(segment_progress) * hill_amplitude)

	# Adding the same profile mirrors the hill into a valley below baseline.
	return surface_y_offset + (get_curve_profile(segment_progress) * hill_amplitude)


func get_segment_tier(segment_index: int) -> int:
	var random_value: int = get_segment_hash(segment_index) >> 4
	if random_value % 2 == 0:
		return SEGMENT_TIER_SMALL
	return SEGMENT_TIER_MEDIUM


func get_segment_length(segment_index: int) -> float:
	if get_segment_type(segment_index) == SEGMENT_TYPE_FLAT:
		return MEDIUM_SEGMENT_LENGTH
	if get_segment_tier(segment_index) == SEGMENT_TIER_SMALL:
		return SMALL_SEGMENT_LENGTH
	return MEDIUM_SEGMENT_LENGTH


func get_segment_amplitude(segment_index: int) -> float:
	if get_segment_tier(segment_index) == SEGMENT_TIER_SMALL:
		return SMALL_HILL_AMPLITUDE
	return MEDIUM_HILL_AMPLITUDE


func create_session_seed() -> int:
	var seed_generator: RandomNumberGenerator = RandomNumberGenerator.new()
	seed_generator.randomize()
	return int(seed_generator.randi())


func get_segment_type(segment_index: int) -> int:
	var segment_type: int = get_unconstrained_segment_type(segment_index)
	if segment_type != SEGMENT_TYPE_FLAT:
		return segment_type

	var previous_segment_type: int = get_unconstrained_segment_type(segment_index - 1)
	if previous_segment_type != SEGMENT_TYPE_FLAT:
		return segment_type

	return get_non_flat_segment_type(segment_index)


func get_unconstrained_segment_type(segment_index: int) -> int:
	var random_value: int = get_segment_hash(segment_index) % 100
	if random_value < FLAT_WEIGHT_PERCENT:
		return SEGMENT_TYPE_FLAT
	if random_value < FLAT_WEIGHT_PERCENT + HILL_WEIGHT_PERCENT:
		return SEGMENT_TYPE_HILL
	return SEGMENT_TYPE_VALLEY


func get_non_flat_segment_type(segment_index: int) -> int:
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
