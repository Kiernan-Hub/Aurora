extends Node2D

class_name GroundTreeSpawner

# Foreground trees that are physically rooted in the terrain surface, unlike the
# ParallaxLayer pine silhouettes in background_generator.gd which are decorative and never
# touch the actual ridden ground. Modeled directly on coin_spawner.gd's chunk lifecycle:
# a child of TerrainGenerator so it inherits world-rebase Y shifts for free (see that
# file's header comment), spawning/despawning in lockstep with the same chunk window
# TerrainGenerator itself uses.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")

# Global grid, not per-chunk slots: a tree's identity is its absolute index, so it keeps
# the same x/height regardless of which chunk currently contains it (same reasoning as
# background_generator.build_shards).
const TREE_SPACING: float = 190.0
const TREE_INCLUDE_CHANCE: float = 0.5
const TREE_HEIGHT_MIN: float = 70.0
const TREE_HEIGHT_MAX: float = 128.0
# How far a tree's x can jitter off its grid slot, as a fraction of TREE_SPACING. Bounded
# under half so trees can never reorder or overlap their neighbours.
const TREE_JITTER_FRACTION: float = 0.55
# Clamped so a tree never tips past readability on the steepest terrain (20.13 deg, see
# CLAUDE.md); this only needs to read as "planted on the slope", not track it exactly.
const MAX_TREE_TILT: float = deg_to_rad(14.0)

const TRUNK_COLOR: Color = Color(0.36, 0.27, 0.22)
const FOLIAGE_COLOR: Color = Color(0.16, 0.32, 0.27)
const FOLIAGE_HIGHLIGHT_COLOR: Color = Color(0.22, 0.4, 0.34)
const SNOW_CAP_COLOR: Color = Color(0.93, 0.96, 0.99)

const HASH_MASK: int = 0x7fffffff
# Distinct from every other spawner's multiplier pair (CoinSpawner, TerrainGenerator,
# BackgroundGenerator) so none of these hash sequences ever line up by coincidence.
const HASH_INDEX_MULTIPLIER: int = 3141592653
const HASH_MIX_MULTIPLIER: int = 2718281829

var terrain_generator: TerrainGenerator
var player: CharacterBody2D
var next_chunk_index: int = 0
var active_tree_groups: Dictionary[int, Node2D] = {}
var has_initialized_tree_groups: bool = false


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as CharacterBody2D
	if terrain_generator == null or player == null:
		push_error("GroundTreeSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	# Explicit null guard rather than trusting _ready()'s set_physics_process(false): that call
	# is documented (docs/development/debugging.md) as not reliably suppressing _physics_process
	# in headless harness runs, and everything below dereferences both of these. Same guard, for
	# the same reason, as ObstacleSpawner and PowerupSpawner.
	if terrain_generator == null or player == null:
		return

	# session_seed isn't ready in _ready() -- same ordering trap as every other spawner
	# under TerrainGenerator (children ready before their parent).
	if not has_initialized_tree_groups:
		has_initialized_tree_groups = true
		initialize_tree_groups()

	var chunk_width: float = terrain_generator.chunk_width
	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	var target_chunk_index: int = player_chunk_index + terrain_generator.chunk_count_ahead
	var despawn_chunk_index: int = player_chunk_index - terrain_generator.chunk_count_behind

	while next_chunk_index <= target_chunk_index:
		spawn_tree_group(next_chunk_index)
		next_chunk_index += 1

	var chunk_indices: Array[int] = active_tree_groups.keys()
	for chunk_index: int in chunk_indices:
		if chunk_index < despawn_chunk_index:
			remove_tree_group(chunk_index)


func initialize_tree_groups() -> void:
	var chunk_width: float = terrain_generator.chunk_width
	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	next_chunk_index = player_chunk_index - terrain_generator.chunk_count_behind
	for chunk_index: int in range(player_chunk_index - terrain_generator.chunk_count_behind, player_chunk_index + terrain_generator.chunk_count_ahead + 1):
		spawn_tree_group(chunk_index)
	next_chunk_index = player_chunk_index + terrain_generator.chunk_count_ahead + 1


func spawn_tree_group(chunk_index: int) -> void:
	if active_tree_groups.has(chunk_index):
		return

	var chunk_width: float = terrain_generator.chunk_width
	var chunk_start_x: float = float(chunk_index) * chunk_width
	var chunk_end_x: float = chunk_start_x + chunk_width

	var group: Node2D = Node2D.new()
	group.position = Vector2(chunk_start_x, terrain_generator.ground_y)
	add_child(group)
	active_tree_groups[chunk_index] = group

	var first_tree_index: int = int(floor(chunk_start_x / TREE_SPACING))
	var last_tree_index: int = int(floor(chunk_end_x / TREE_SPACING))
	for tree_index: int in range(first_tree_index, last_tree_index + 1):
		if get_tree_hash_unit(tree_index, 0) > TREE_INCLUDE_CHANCE:
			continue

		var jitter: float = (get_tree_hash_unit(tree_index, 1) - 0.5) * TREE_SPACING * TREE_JITTER_FRACTION
		var world_x: float = (float(tree_index) * TREE_SPACING) + jitter
		if world_x < chunk_start_x or world_x >= chunk_end_x:
			continue
		# A tree over a chasm void has nothing to root into: get_terrain_height() only
		# returns the lip height there, which would plant it floating over the gap.
		if not terrain_generator.has_ground_at_world_x(world_x):
			continue
		# Nothing grows out of the frozen lake. Trees are decorative and collision-free, so
		# this is the one suppression here that is purely a look -- but a pine standing in
		# the middle of a mirror is the thing that would give the whole effect away.
		if terrain_generator.is_lake_world_x(world_x):
			continue

		var tree_height: float = TREE_HEIGHT_MIN + (get_tree_hash_unit(tree_index, 2) * (TREE_HEIGHT_MAX - TREE_HEIGHT_MIN))
		var local_x: float = world_x - chunk_start_x
		var local_y: float = terrain_generator.get_terrain_height(world_x)
		var tilt: float = clampf(terrain_generator.get_slope_angle_at_x(world_x), -MAX_TREE_TILT, MAX_TREE_TILT)

		var tree: Node2D = build_tree(tree_height)
		tree.position = Vector2(local_x, local_y)
		tree.rotation = tilt
		group.add_child(tree)


func remove_tree_group(chunk_index: int) -> void:
	if not active_tree_groups.has(chunk_index):
		return

	var group: Node2D = active_tree_groups[chunk_index]
	active_tree_groups.erase(chunk_index)
	group.queue_free()


# A three-tier conifer with a trunk and a snow-dusted top tier, rooted at (0, 0) -- the
# caller positions that origin exactly on the terrain surface line. Simple flat-shaded
# polygons only, matching the project's "no textures anywhere" rule.
func build_tree(tree_height: float) -> Node2D:
	var tree: Node2D = Node2D.new()

	var trunk_height: float = tree_height * 0.16
	var trunk_width: float = tree_height * 0.07
	var trunk: Polygon2D = Polygon2D.new()
	trunk.polygon = PackedVector2Array([
		Vector2(-trunk_width, 0.0),
		Vector2(trunk_width, 0.0),
		Vector2(trunk_width, -trunk_height),
		Vector2(-trunk_width, -trunk_height),
	])
	trunk.color = TRUNK_COLOR
	tree.add_child(trunk)

	var foliage_top: float = -tree_height
	var foliage_base: float = -trunk_height
	var tier_count: int = 3
	for tier_index: int in range(tier_count):
		var tier_fraction_bottom: float = float(tier_index) / float(tier_count)
		var tier_fraction_top: float = float(tier_index + 1) / float(tier_count)
		var tier_bottom_y: float = lerpf(foliage_base, foliage_top, tier_fraction_bottom)
		var tier_top_y: float = lerpf(foliage_base, foliage_top, tier_fraction_top) - (tree_height * 0.05)
		# Widest at the base tier, narrowing toward the apex.
		var tier_half_width: float = tree_height * 0.24 * (1.0 - (tier_fraction_bottom * 0.55))
		var tier: Polygon2D = Polygon2D.new()
		tier.polygon = PackedVector2Array([
			Vector2(0.0, tier_top_y),
			Vector2(tier_half_width, tier_bottom_y),
			Vector2(-tier_half_width, tier_bottom_y),
		])
		tier.color = FOLIAGE_HIGHLIGHT_COLOR if tier_index == tier_count - 1 else FOLIAGE_COLOR
		tree.add_child(tier)

	var snow_half_width: float = tree_height * 0.09
	var snow_cap: Polygon2D = Polygon2D.new()
	snow_cap.polygon = PackedVector2Array([
		Vector2(0.0, foliage_top),
		Vector2(snow_half_width, foliage_top + (tree_height * 0.14)),
		Vector2(-snow_half_width, foliage_top + (tree_height * 0.14)),
	])
	snow_cap.color = SNOW_CAP_COLOR
	tree.add_child(snow_cap)

	return tree


# Pure function of (session_seed, tree_index, salt) -> [0, 1). Same style as
# CoinSpawner.get_slot_hash but with its own multiplier pair so this sequence never lines
# up with any other spawner's.
func get_tree_hash_unit(tree_index: int, salt: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ (((tree_index * 5) + salt) * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)
