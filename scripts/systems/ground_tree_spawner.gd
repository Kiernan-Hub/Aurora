extends Node2D

class_name GroundTreeSpawner

# Foreground ICE FORMATIONS rooted in the terrain surface, unlike the ParallaxLayer shard
# silhouettes in background_generator.gd which are decorative and never touch the actual
# ridden ground.
#
# The class, the node name in main.tscn, biome_director's ground_trees_path and the
# palettes' tree_tint all still say "tree", from when these were conifers. Those names are
# WIRING -- renaming them means touching the scene, the director's export default and nine
# palette resources for no behavioural gain -- so they are left as historical names rather
# than churned. Nothing here spawns a tree. Modeled directly on coin_spawner.gd's chunk lifecycle:
# a child of TerrainGenerator so it inherits world-rebase Y shifts for free (see that
# file's header comment), spawning/despawning in lockstep with the same chunk window
# TerrainGenerator itself uses.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")

# Global grid, not per-chunk slots: a tree's identity is its absolute index, so it keeps
# the same x/height regardless of which chunk currently contains it (same reasoning as
# background_generator.build_pines).
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

# Pale on purpose. biome_director.gd tints this whole spawner with palette.tree_tint,
# which ranges from (1, 1, 1) down to starlit_night's (0.42, 0.48, 0.68) -- every one a
# MULTIPLIER, so a colour authored dark here can only get darker and would go black at
# night. The three tones are body, lit face, and the crest highlight along the top edge.
const ICE_BODY_COLOR: Color = Color(0.62, 0.74, 0.86)
const ICE_LIT_COLOR: Color = Color(0.8, 0.89, 0.96)
const ICE_CREST_COLOR: Color = Color(0.93, 0.97, 1.0)

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


# A chunky ice formation rooted at (0, 0) -- the caller positions that origin exactly on
# the terrain surface line. Flat-shaded polygons only, matching the project's "no textures
# anywhere" rule.
#
# Replaces the three-tier conifer this spawner drew until the background became icebergs
# on open water, where a pine forest in the play area was the loudest wrong note on
# screen. THE SPAWNER ITSELF IS UNCHANGED -- spacing, jitter, tilt, the hash and the chunk
# lifecycle all still work exactly as they did; only the shape and its colours moved.
#
# DELIBERATELY SIMPLE, and expected to be replaced by real art. Three polygons is enough
# to read as ice at gameplay speed, and anything more detailed is work thrown away when
# the painted sprites land.
#
# The foot is FLAT and has width. A shape tapering to nothing at both feet is a mound, and
# HANDOFF records mounds reading as rock however they are shaded; ice meets ground at an
# edge. Same rule as build_shard_polygon in background_generator.gd.
func build_tree(tree_height: float) -> Node2D:
	var formation: Node2D = Node2D.new()
	var half_width: float = tree_height * 0.42

	var body: Polygon2D = Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-half_width, 0.0),
		Vector2(-half_width * 0.92, -tree_height * 0.42),
		Vector2(-half_width * 0.45, -tree_height * 0.86),
		Vector2(half_width * 0.1, -tree_height),
		Vector2(half_width * 0.68, -tree_height * 0.6),
		Vector2(half_width, -tree_height * 0.22),
		Vector2(half_width * 0.9, 0.0),
	])
	body.color = ICE_BODY_COLOR
	formation.add_child(body)

	# The sunlit right face, as its own wedge off the apex. One flat plane catching light
	# is what separates ice from a rounded snow lump at this size.
	var lit_face: Polygon2D = Polygon2D.new()
	lit_face.polygon = PackedVector2Array([
		Vector2(half_width * 0.1, -tree_height),
		Vector2(half_width * 0.68, -tree_height * 0.6),
		Vector2(half_width, -tree_height * 0.22),
		Vector2(half_width * 0.9, 0.0),
		Vector2(half_width * 0.34, 0.0),
		Vector2(half_width * 0.2, -tree_height * 0.5),
	])
	lit_face.color = ICE_LIT_COLOR
	formation.add_child(lit_face)

	var crest: Polygon2D = Polygon2D.new()
	crest.polygon = PackedVector2Array([
		Vector2(-half_width * 0.45, -tree_height * 0.86),
		Vector2(half_width * 0.1, -tree_height),
		Vector2(half_width * 0.02, -tree_height * 0.88),
		Vector2(-half_width * 0.4, -tree_height * 0.76),
	])
	crest.color = ICE_CREST_COLOR
	formation.add_child(crest)

	return formation


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
