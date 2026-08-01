extends Node2D

class_name ObstacleSpawner

# Same reasoning as CoinSpawner: a child of TerrainGenerator so world rebasing
# (which shifts TerrainGenerator.position.y directly in main.gd) carries every
# spawned obstacle along for free, with no rebase handling of its own needed.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")

const OBSTACLE_SCENE: PackedScene = preload("res://scenes/obstacles/obstacle.tscn")
# Half of obstacle.tscn's RectangleShape2D size (32x32), so the box sits on top of
# the surface rather than centered on it or floating above it.
const OBSTACLE_HALF_HEIGHT: float = 16.0
const OBSTACLE_SLOT_INCLUDE_CHANCE: float = 0.18
# Only place on close-to-flat ground: an obstacle glued to a slope reads as
# unfair (its hitbox stops matching what the eye expects the moment the surface
# tilts under it), and a steep approach also eats into the player's reaction
# window. get_slope_angle_at_x is the analytic (cosmetic) angle -- fine here,
# unlike Player.get_slope_tangent(), since nothing physical rides on this value.
const OBSTACLE_MAX_SLOPE_ANGLE: float = deg_to_rad(6.0)
# The old hand-placed obstacle at (68,56) killed the player mid-jump at t=0.10s
# (docs/development/dead_code.md) because it sat inside the player's very first
# few physics steps. Keeping every candidate well past chunk_count_behind's
# span at spawn avoids resurrecting that failure mode.
const MIN_SAFE_START_WORLD_X: float = 900.0
# Minimum world-x gap enforced against the PREVIOUS spawned obstacle (stateful,
# not a pure function of chunk_index alone -- unlike terrain shape, obstacle
# placement has no purity requirement, and a gap check needs the last placement
# to reason about). At speed cap (500px/s) this is ~0.6s of reaction time,
# comfortably more than coyote time + jump buffer (0.12s each) combined.
const OBSTACLE_MIN_GAP: float = 320.0
const HASH_MASK: int = 0x7fffffff
# Distinct multiplier pair from both TerrainGenerator.get_segment_hash and
# CoinSpawner.get_slot_hash so none of the three hash sequences correlate,
# even though all three ultimately key off the same session_seed.
const HASH_INDEX_MULTIPLIER: int = 2654435761
const HASH_MIX_MULTIPLIER: int = 1274126177

var terrain_generator: TerrainGenerator
var player: CharacterBody2D
var next_chunk_index: int = 0
var active_obstacle_groups: Dictionary[int, Node2D] = {}
var has_initialized_obstacle_groups: bool = false
var last_obstacle_world_x: float = -INF


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as CharacterBody2D
	if terrain_generator == null or player == null:
		push_error("ObstacleSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)
		return


func _physics_process(_delta: float) -> void:
	# Deferred out of _ready() for the same reason as CoinSpawner: this node is a
	# child of TerrainGenerator, Godot runs child _ready() before parent _ready(),
	# and TerrainGenerator's segment cache (which get_terrain_height/
	# get_slope_angle_at_x depend on) isn't built until its own _ready() runs.
	if not has_initialized_obstacle_groups:
		has_initialized_obstacle_groups = true
		initialize_obstacle_groups()

	var chunk_width: float = terrain_generator.chunk_width
	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	var target_chunk_index: int = player_chunk_index + terrain_generator.chunk_count_ahead
	var despawn_chunk_index: int = player_chunk_index - terrain_generator.chunk_count_behind

	while next_chunk_index <= target_chunk_index:
		spawn_obstacle_group(next_chunk_index)
		next_chunk_index += 1

	var chunk_indices: Array[int] = active_obstacle_groups.keys()
	for chunk_index: int in chunk_indices:
		if chunk_index < despawn_chunk_index:
			remove_obstacle_group(chunk_index)


func initialize_obstacle_groups() -> void:
	var chunk_width: float = terrain_generator.chunk_width
	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	next_chunk_index = player_chunk_index - terrain_generator.chunk_count_behind
	for chunk_index: int in range(player_chunk_index - terrain_generator.chunk_count_behind, player_chunk_index + terrain_generator.chunk_count_ahead + 1):
		spawn_obstacle_group(chunk_index)
	next_chunk_index = player_chunk_index + terrain_generator.chunk_count_ahead + 1


func spawn_obstacle_group(chunk_index: int) -> void:
	if active_obstacle_groups.has(chunk_index):
		return

	var chunk_width: float = terrain_generator.chunk_width
	var chunk_start_x: float = float(chunk_index) * chunk_width
	var group: Node2D = Node2D.new()
	group.position = Vector2(chunk_start_x + (chunk_width * 0.5), terrain_generator.ground_y)
	add_child(group)
	active_obstacle_groups[chunk_index] = group

	# One candidate slot per chunk, at a hash-jittered fraction of the chunk so
	# placements don't all line up at the same relative offset.
	var fraction: float = 0.15 + (get_chunk_hash(1, chunk_index) * 0.7)
	var world_x: float = chunk_start_x + (fraction * chunk_width)

	if get_chunk_hash(0, chunk_index) > OBSTACLE_SLOT_INCLUDE_CHANCE:
		return
	if world_x < MIN_SAFE_START_WORLD_X:
		return
	if world_x - last_obstacle_world_x < OBSTACLE_MIN_GAP:
		return
	if absf(terrain_generator.get_slope_angle_at_x(world_x)) > OBSTACLE_MAX_SLOPE_ANGLE:
		return

	var local_x: float = world_x - chunk_start_x - (chunk_width * 0.5)
	var local_y: float = terrain_generator.get_terrain_height(world_x) - OBSTACLE_HALF_HEIGHT

	var obstacle: Area2D = OBSTACLE_SCENE.instantiate() as Area2D
	obstacle.position = Vector2(local_x, local_y)
	group.add_child(obstacle)
	last_obstacle_world_x = world_x


func remove_obstacle_group(chunk_index: int) -> void:
	if not active_obstacle_groups.has(chunk_index):
		return

	var group: Node2D = active_obstacle_groups[chunk_index]
	active_obstacle_groups.erase(chunk_index)
	group.free()


# Pure function of (session_seed, chunk_index, channel) -> [0, 1). Same style as
# TerrainGenerator.get_segment_hash / CoinSpawner.get_slot_hash, with its own
# multiplier pair (see HASH_INDEX_MULTIPLIER/HASH_MIX_MULTIPLIER) so this
# sequence doesn't correlate with either.
func get_chunk_hash(channel: int, chunk_index: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ ((chunk_index * 2 + channel) * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)
