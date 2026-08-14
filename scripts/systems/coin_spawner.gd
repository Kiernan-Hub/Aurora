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
# 0.30, not the 0.4 this shipped with, because an included slot now spawns a THREE-coin arc
# COIN_ARC_CHANCE of the time. The flat-ground arithmetic is 0.30 * (0.7*1 + 0.3*3) = 0.48
# coins per slot, but roughly 40% of arc rolls are refused for slope (see
# COIN_ARC_MAX_GROUND_DROP) and fall back to a single coin, which lands the MEASURED density
# at ~0.42 -- against 0.40 before arcs. Do not re-derive that 0.40 from these constants alone;
# it is a property of the terrain too, which is why terrain_invariant_check measures it per
# seed rather than asserting the product. JUMP_UPGRADE_COSTS is costed against it.
const COIN_SLOT_INCLUDE_CHANCE: float = 0.30
# Above the sampled surface height, in the same local-y units build_chunk_surface
# uses (get_terrain_height() is already ground_y-relative). Low enough to be
# grabbed while grounded (player capsule half-height is 24px), high enough that
# a coin never renders inside the terrain fill.
const COIN_SURFACE_CLEARANCE: float = 34.0

# --- Arcs -----------------------------------------------------------------------------
# The point of the arc is that a coin can be MISSED. At COIN_SURFACE_CLEARANCE 34 every
# ground coin in the game sits under the 58px standing grab ceiling, so the entire currency
# is collected with zero input -- which is also why an in-run combo counter was pointless
# until this existed.
const COIN_ARC_CHANCE: float = 0.3
const COIN_ARC_COIN_COUNT: int = 3
# The middle coin. 92 clears the 58px no-jump line by a wide margin, so the arc always costs
# a jump, and sits 12px under the 104px ceiling of jump level 0 -- the WEAKEST upgrade, since
# a coin the starting player cannot reach reads as a bug rather than a goal. Asserted against
# both ceilings in terrain_invariant_check.check_coin_arc_height().
const COIN_ARC_PEAK_CLEARANCE: float = 92.0
# The two shoulders sit on the jump parabola through that peak, not on an arbitrary lower
# line: 0.5 * GRAVITY(1600) * (60 / run_speed)^2 is 11.5px of drop at 500 px/s and 5.1px at
# 750, so 8px is the whole speed range to within ~4px -- far inside the grab window that a
# 10px coin radius plus the capsule's height gives. All three are above the 58px free line.
const COIN_ARC_SHOULDER_CLEARANCE: float = 84.0
# Half the 153.6px gap between neighbouring slots (0.3 * chunk_width 512), so two arcs in
# adjacent slots still leave a coin-sized gap instead of reading as one long chain.
const COIN_ARC_SPACING_X: float = 60.0
# An arc's clearances are measured per coin against the ground under THAT coin, so on a slope
# the arc tilts with the terrain while a real jump does not. Over the 120px span, 24px is
# about 11 degrees; steeper than that and the slot falls back to a single ground coin rather
# than hanging a shoulder out of reach. Same reasoning as RareCoinSpawner's flatness test.
const COIN_ARC_MAX_GROUND_DROP: float = 24.0
# Distinct from TerrainGenerator's own HASH_INDEX_MULTIPLIER/HASH_MIX_MULTIPLIER
# salt so this hash sequence never collides with segment-selection hashing, even
# though the two draw on the same session_seed and operate on different index
# domains (chunk_index here vs segment_index there).
const HASH_MASK: int = 0x7fffffff
const HASH_INDEX_MULTIPLIER: int = 2246822519
const HASH_MIX_MULTIPLIER: int = 3266489917
# A second, independent pair for the arc roll. Offsetting the slot index into the existing
# sequence would NOT be independent -- its index domain is chunk_index * 3 + slot_index, so any
# constant offset lands on a real slot in a later chunk and the two decisions correlate.
const ARC_HASH_INDEX_MULTIPLIER: int = 668265263
const ARC_HASH_MIX_MULTIPLIER: int = 2654435761

# Coin magnet powerup (PowerupManager.EFFECT_COIN_MAGNET), driven externally via
# set_magnet_active() the same way PowerupManager drives Player.start_boost/end_boost --
# this node has no idea a powerup exists, it just pulls when told to.
const MAGNET_RADIUS: float = 220.0
const MAGNET_PULL_SPEED: float = 900.0

var terrain_generator: TerrainGenerator
var player: CharacterBody2D
var next_chunk_index: int = 0
var active_coin_groups: Dictionary[int, Node2D] = {}
var has_initialized_coin_groups: bool = false
var magnet_active: bool = false

# The current biome's coin colour, pushed by BiomeDirector.push_palette(). Absolute, not a
# multiplicative tint like tree_tint: a coin has to stay unmistakably a coin in every biome,
# so the palettes author the final colour rather than a factor over one.
#
# WHY NOT modulate ON THIS NODE, which is how trees and birds do it: modulate multiplies,
# and multiplying the shipped gold can only ever darken it -- the dark biomes need it
# BRIGHTER. Stamping the colour also costs nothing per frame, where a tint would still need
# this same plumbing to reach glide coins with their own bonus colour.
#
# has_biome_color stays false until a palette arrives, so coins keep coin.tscn's authored
# colour under --headless (BiomeDirector returns early there) and in every gate.
var has_biome_color: bool = false
var biome_coin_color: Color = Color.WHITE


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as CharacterBody2D
	if terrain_generator == null or player == null:
		push_error("CoinSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)
		return


func _physics_process(delta: float) -> void:
	# Explicit null guard rather than trusting _ready()'s set_physics_process(false): that call
	# is documented (docs/development/debugging.md) as not reliably suppressing _physics_process
	# in headless harness runs, and everything below dereferences both of these. Same guard, for
	# the same reason, as ObstacleSpawner and PowerupSpawner.
	if terrain_generator == null or player == null:
		return

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

	if magnet_active:
		apply_magnet_pull(delta)


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
		var group_origin_x: float = chunk_start_x + (chunk_width * 0.5)
		if get_arc_hash(chunk_index, slot_index) < COIN_ARC_CHANCE and can_fit_arc_at_world_x(world_x):
			for arc_index: int in range(COIN_ARC_COIN_COUNT):
				var offset_x: float = get_arc_offset_x(arc_index)
				spawn_coin(group, group_origin_x, world_x + offset_x, get_arc_clearance(arc_index))
			continue

		spawn_coin(group, group_origin_x, world_x, COIN_SURFACE_CLEARANCE)


# One coin at a world x, positioned relative to the chunk group's origin. Returns quietly if
# there is no ground under it: a coin over a chasm is unreachable bait, because
# get_terrain_height() returns the LIP height across a void and the coin would hang in mid-air.
# Checked PER COIN rather than per slot so an arc that reaches over a lip loses only the coins
# that are actually over the hole.
func spawn_coin(group: Node2D, group_origin_x: float, world_x: float, clearance: float) -> void:
	if not terrain_generator.has_ground_at_world_x(world_x):
		return

	var coin: Coin = COIN_SCENE.instantiate() as Coin
	coin.position = Vector2(world_x - group_origin_x, terrain_generator.get_terrain_height(world_x) - clearance)
	coin.collected.connect(_on_coin_collected)
	if has_biome_color:
		coin.set_visual_color(biome_coin_color)
	group.add_child(coin)


func get_arc_offset_x(arc_index: int) -> float:
	return (float(arc_index) - (float(COIN_ARC_COIN_COUNT - 1) * 0.5)) * COIN_ARC_SPACING_X


func get_arc_clearance(arc_index: int) -> float:
	var is_peak: bool = arc_index == (COIN_ARC_COIN_COUNT - 1) / 2
	return COIN_ARC_PEAK_CLEARANCE if is_peak else COIN_ARC_SHOULDER_CLEARANCE


# The arc's shape only makes sense over ground that is near enough to flat -- see
# COIN_ARC_MAX_GROUND_DROP. Pure in (session_seed, world_x), like everything else that reads
# the height field, so a slot's decision is identical every time the chunk is rebuilt.
func can_fit_arc_at_world_x(world_x: float) -> bool:
	var lowest_height: float = INF
	var highest_height: float = -INF
	for arc_index: int in range(COIN_ARC_COIN_COUNT):
		var sample_x: float = world_x + get_arc_offset_x(arc_index)
		if not terrain_generator.has_ground_at_world_x(sample_x):
			return false
		var height: float = terrain_generator.get_terrain_height(sample_x)
		lowest_height = minf(lowest_height, height)
		highest_height = maxf(highest_height, height)
	return (highest_height - lowest_height) <= COIN_ARC_MAX_GROUND_DROP


# Repaints the coins already on screen as well as every one spawned from here on, the same
# way terrain_generator.apply_ice_palette() repaints live chunks -- a transition that only
# reached NEW coins would walk a visible colour boundary down the slope.
#
# Called every frame of a crossfade, so the early-out is what keeps the steady state free.
func apply_biome_color(color: Color) -> void:
	if has_biome_color and biome_coin_color.is_equal_approx(color):
		return
	has_biome_color = true
	biome_coin_color = color
	for group: Node2D in active_coin_groups.values():
		if not is_instance_valid(group):
			continue
		for child: Node in group.get_children():
			var coin: Coin = child as Coin
			if coin != null:
				coin.set_visual_color(color)


func remove_coin_group(chunk_index: int) -> void:
	if not active_coin_groups.has(chunk_index):
		return

	var group: Node2D = active_coin_groups[chunk_index]
	active_coin_groups.erase(chunk_index)
	# queue_free(), not free(): this runs inside _physics_process and the group's children
	# are live Area2D monitors. Same reasoning as TerrainGenerator.remove_chunk().
	group.queue_free()


func set_magnet_active(active: bool) -> void:
	magnet_active = active


# Pulls every uncollected coin within MAGNET_RADIUS toward the player. Moves
# global_position, not the coin's parent-relative position: this runs fresh every physics
# frame rather than caching anything across frames, so it is unaffected by world
# rebasing -- global_position is recomputed from the current chunk-group transform on
# every read/write, the same as get_slope_tangent() reading global_position each frame.
# Collection itself is untouched: the coin's own Area2D.body_entered still does that, so
# the magnet only moves coins into pickup range, it never collects them directly.
#
# A pulled coin can end up outside the world-x span of the chunk group that owns it, so
# remove_coin_group() (keyed on the GROUP's chunk index, not the coin's live position)
# could in principle free it a chunk early. Harmless in practice: at MAGNET_PULL_SPEED the
# coin reaches the player and is collected well within a second, long before its native
# chunk falls behind chunk_count_behind.
func apply_magnet_pull(delta: float) -> void:
	for group: Node2D in active_coin_groups.values():
		for child: Node in group.get_children():
			var coin: Coin = child as Coin
			if coin == null or not is_instance_valid(coin) or coin.has_been_collected:
				continue
			if coin.global_position.distance_to(player.global_position) > MAGNET_RADIUS:
				continue
			coin.global_position = coin.global_position.move_toward(player.global_position, MAGNET_PULL_SPEED * delta)


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


# "Does this included slot become an arc?" -- see ARC_HASH_INDEX_MULTIPLIER for why this is a
# separate sequence rather than an offset into get_slot_hash's.
func get_arc_hash(chunk_index: int, slot_index: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ ((chunk_index * 3 + slot_index) * ARC_HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 16)) & HASH_MASK
	mixed_value = (mixed_value * ARC_HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)
