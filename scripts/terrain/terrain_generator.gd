extends Node2D

class_name TerrainGenerator

const CHUNK_SCENE: PackedScene = preload("res://scenes/terrain/terrain_chunk.tscn")

@export var player_path: NodePath
@export var chunk_width: float = 512.0
@export var chunk_count_ahead: int = 6
@export var chunk_count_behind: int = 2
@export var ground_y: float = 192.0
@export var surface_y_offset: float = -32.0
@export var height_sample_count: int = 32
@export var hill_amplitude: float = 34.0
@export var hill_wavelength: float = 900.0
@export var detail_amplitude: float = 12.0
@export var detail_wavelength: float = 380.0
@export var terrain_depth: float = 600.0

var player: CharacterBody2D
var next_chunk_index: int = 0
var active_chunks: Dictionary[int, Node2D] = {}

const LIGHT_CHUNK_COLOR: Color = Color(0.92, 0.97, 1.0)
const DARK_CHUNK_COLOR: Color = Color(0.78, 0.86, 0.93)
const SLOPE_SAMPLE_DISTANCE: float = 2.0
const MAX_COLLISION_SEGMENT_LENGTH: float = 16.0
const DEBUG_TERRAIN_LOGGING: bool = false


func _ready() -> void:
	player = get_node(player_path) as CharacterBody2D
	if player == null:
		push_error("TerrainGenerator requires a valid player_path.")
		set_physics_process(false)
		return

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
	var broad_hill: float = sin((world_x / hill_wavelength) * TAU) * hill_amplitude
	var detail_hill: float = sin((world_x / detail_wavelength) * TAU + 1.2) * detail_amplitude
	return surface_y_offset + broad_hill + detail_hill


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
