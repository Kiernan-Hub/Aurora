extends Node2D

class_name CoinSpawner

# Sibling-relative, not absolute, because this node is meant to live as a child of
# TerrainGenerator: world rebasing (main.gd apply_world_rebase) shifts
# TerrainGenerator.position.y directly, and every descendant -- chunks and this
# node's coin groups alike -- inherits that shift for free. A standalone spawner
# outside the TerrainGenerator subtree would need its own rebase handling or its
# coins would drift out of alignment with the terrain after the first rebase.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")

signal coin_collected(value: int)

const COIN_SCENE: PackedScene = preload("res://scenes/pickups/coin.tscn")
# Fixed candidate x positions within a chunk, as a fraction of chunk_width. Each
# slot is independently included or not (see get_slot_hash) so coins don't
# appear in every chunk at identical spacing.
const COIN_SLOT_FRACTIONS: Array[float] = [0.2, 0.5, 0.8]
const COIN_SLOT_INCLUDE_CHANCE: float = 0.4
# Above the sampled surface height, in the same local-y units build_chunk_surface
# uses (get_terrain_height() is already ground_y-relative). Low enough to be
# grabbed while grounded (player capsule half-height is 24px), high enough that
# a coin never renders inside the terrain fill.
const COIN_SURFACE_CLEARANCE: float = 34.0
# Distinct from TerrainGenerator's own HASH_INDEX_MULTIPLIER/HASH_MIX_MULTIPLIER
# salt so this hash sequence never collides with segment-selection hashing, even
# though the two draw on the same session_seed and operate on different index
# domains (chunk_index here vs segment_index there).
const HASH_MASK: int = 0x7fffffff
const HASH_INDEX_MULTIPLIER: int = 2246822519
const HASH_MIX_MULTIPLIER: int = 3266489917

var terrain_generator: TerrainGenerator
var player: CharacterBody2D
var next_chunk_index: int = 0
var active_coin_groups: Dictionary[int, Node2D] = {}
var has_initialized_coin_groups: bool = false


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as CharacterBody2D
	if terrain_generator == null or player == null:
		push_error("CoinSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)
		return


func _physics_process(_delta: float) -> void:
	# Deliberately not done in _ready(): this node is a child of TerrainGenerator
	# (see terrain_generator_path doc comment above), and Godot runs _ready() on
	# children before their parent, so TerrainGenerator's own _ready() -- which
	# builds session_seed and the segment cache get_terrain_height() depends on --
	# has not run yet at this node's _ready() time. Every node's _ready() has run
	# by the first _physics_process(), regardless of process order between
	# siblings, so deferring here is the safe point.
	if not has_initialized_coin_groups:
		has_initialized_coin_groups = true
		initialize_coin_groups()

	var chunk_width: float = terrain_generator.chunk_width
	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	var target_chunk_index: int = player_chunk_index + terrain_generator.chunk_count_ahead
	var despawn_chunk_index: int = player_chunk_index - terrain_generator.chunk_count_behind

	while next_chunk_index <= target_chunk_index:
		spawn_coin_group(next_chunk_index)
		next_chunk_index += 1

	var chunk_indices: Array[int] = active_coin_groups.keys()
	for chunk_index: int in chunk_indices:
		if chunk_index < despawn_chunk_index:
			remove_coin_group(chunk_index)


func initialize_coin_groups() -> void:
	var chunk_width: float = terrain_generator.chunk_width
	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	next_chunk_index = player_chunk_index - terrain_generator.chunk_count_behind
	for chunk_index: int in range(player_chunk_index - terrain_generator.chunk_count_behind, player_chunk_index + terrain_generator.chunk_count_ahead + 1):
		spawn_coin_group(chunk_index)
	next_chunk_index = player_chunk_index + terrain_generator.chunk_count_ahead + 1


func spawn_coin_group(chunk_index: int) -> void:
	if active_coin_groups.has(chunk_index):
		return

	var chunk_width: float = terrain_generator.chunk_width
	var chunk_start_x: float = float(chunk_index) * chunk_width
	var group: Node2D = Node2D.new()
	group.position = Vector2(chunk_start_x + (chunk_width * 0.5), terrain_generator.ground_y)
	add_child(group)
	active_coin_groups[chunk_index] = group

	for slot_index: int in range(COIN_SLOT_FRACTIONS.size()):
		if get_slot_hash(chunk_index, slot_index) > COIN_SLOT_INCLUDE_CHANCE:
			continue

		var world_x: float = chunk_start_x + (COIN_SLOT_FRACTIONS[slot_index] * chunk_width)
		# A coin over a chasm is unreachable bait: get_terrain_height() returns the LIP
		# height inside a void, so without this the coin renders in mid-air. Skipping is
		# free here -- there are three independent slots per chunk.
		if not terrain_generator.has_ground_at_world_x(world_x):
			continue

		var local_x: float = world_x - chunk_start_x - (chunk_width * 0.5)
		var local_y: float = terrain_generator.get_terrain_height(world_x) - COIN_SURFACE_CLEARANCE

		var coin: Coin = COIN_SCENE.instantiate() as Coin
		coin.position = Vector2(local_x, local_y)
		coin.collected.connect(_on_coin_collected)
		group.add_child(coin)


func remove_coin_group(chunk_index: int) -> void:
	if not active_coin_groups.has(chunk_index):
		return

	var group: Node2D = active_coin_groups[chunk_index]
	active_coin_groups.erase(chunk_index)
	# queue_free(), not free(): this runs inside _physics_process and the group's children
	# are live Area2D monitors. Same reasoning as TerrainGenerator.remove_chunk().
	group.queue_free()


func _on_coin_collected(value: int) -> void:
	coin_collected.emit(value)


# Pure function of (session_seed, chunk_index, slot_index) -> [0, 1), same style as
# TerrainGenerator.get_segment_hash but with an independent multiplier pair so this
# sequence never lines up with segment-selection hashing.
func get_slot_hash(chunk_index: int, slot_index: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ ((chunk_index * 3 + slot_index) * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)
