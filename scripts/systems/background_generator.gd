extends ParallaxLayer

class_name BackgroundGenerator

@export var player_path: NodePath
@export var segment_width: float = 1024.0
@export var segment_count_ahead: int = 2
@export var segment_count_behind: int = 1
@export var segment_height: float = 2048.0
@export var segment_y: float = -1024.0

var player: CharacterBody2D
var next_segment_index: int = 0
var active_segments: Dictionary[int, ColorRect] = {}

const LIGHT_SEGMENT_COLOR: Color = Color(0.65, 0.82, 0.98)
const DARK_SEGMENT_COLOR: Color = Color(0.57, 0.76, 0.94)


func _ready() -> void:
	player = get_node(player_path) as CharacterBody2D
	if player == null:
		push_error("BackgroundGenerator requires a valid player_path.")
		set_physics_process(false)
		return

	initialize_segments()


func _physics_process(_delta: float) -> void:
	if player == null:
		return

	var background_x: float = player.global_position.x * motion_scale.x
	var player_segment_index: int = int(floor(background_x / segment_width))
	var target_segment_index: int = player_segment_index + segment_count_ahead
	var despawn_segment_index: int = player_segment_index - segment_count_behind

	while next_segment_index <= target_segment_index:
		spawn_segment(next_segment_index)
		next_segment_index += 1

	var segment_indices: Array[int] = active_segments.keys()
	for segment_index: int in segment_indices:
		if segment_index < despawn_segment_index:
			remove_segment(segment_index)


func initialize_segments() -> void:
	var background_x: float = player.global_position.x * motion_scale.x
	var player_segment_index: int = int(floor(background_x / segment_width))
	next_segment_index = player_segment_index - segment_count_behind
	for segment_index: int in range(player_segment_index - segment_count_behind, player_segment_index + segment_count_ahead + 1):
		spawn_segment(segment_index)
	next_segment_index = player_segment_index + segment_count_ahead + 1


func spawn_segment(segment_index: int) -> void:
	if active_segments.has(segment_index):
		return

	var segment: ColorRect = ColorRect.new()
	segment.size = Vector2(segment_width, segment_height)
	segment.position = Vector2(float(segment_index) * segment_width, segment_y)
	segment.color = LIGHT_SEGMENT_COLOR if segment_index % 2 == 0 else DARK_SEGMENT_COLOR
	add_child(segment)
	active_segments[segment_index] = segment


func remove_segment(segment_index: int) -> void:
	if not active_segments.has(segment_index):
		return

	var segment: ColorRect = active_segments[segment_index]
	active_segments.erase(segment_index)
	segment.free()