extends Node2D

class_name TerrainGenerator

const CHUNK_SCENE: PackedScene = preload("res://scenes/terrain/terrain_chunk.tscn")

@export var player_path: NodePath
@export var chunk_width: float = 512.0
@export var chunk_count_ahead: int = 6
@export var chunk_count_behind: int = 2
@export var ground_y: float = 192.0

var player: CharacterBody2D
var next_chunk_index: int = 0
var active_chunks: Dictionary[int, Node2D] = {}

const LIGHT_CHUNK_COLOR: Color = Color(0.92, 0.97, 1.0)
const DARK_CHUNK_COLOR: Color = Color(0.78, 0.86, 0.93)


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
	apply_chunk_color(chunk, chunk_index)
	add_child(chunk)
	active_chunks[chunk_index] = chunk
	print("spawn chunk ", chunk_index)


func remove_chunk(chunk_index: int) -> void:
	if not active_chunks.has(chunk_index):
		return

	var chunk: Node2D = active_chunks[chunk_index]
	active_chunks.erase(chunk_index)
	chunk.free()
	print("free chunk ", chunk_index)


func apply_chunk_color(chunk: StaticBody2D, chunk_index: int) -> void:
	var color_rect: ColorRect = chunk.get_node_or_null("ColorRect") as ColorRect
	if color_rect == null:
		return

	if chunk_index % 2 == 0:
		color_rect.color = LIGHT_CHUNK_COLOR
	else:
		color_rect.color = DARK_CHUNK_COLOR