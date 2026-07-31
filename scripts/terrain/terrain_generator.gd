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
@export var debug_log_segment_selection: bool = false
@export var debug_replay_session_seed: int = -1
# Complexity dial for bisecting terrain bugs to a single feature: set any weight to 0
# to remove that shape from the world entirely, using the same weight<=0 skip already
# present in get_non_flat_segment_selection/get_weighted_segment_selection. Ladder
# example -- flat-only: zero every weight below except debug_weight_flat. +hills: also
# raise debug_weight_medium_hill_valley_mix. +downhill/uphill: also raise those two.
# +mega_drop: also raise debug_weight_mega_drop. Defaults reproduce the shipping mix.
@export var debug_weight_flat: int = DEFAULT_WEIGHT_FLAT
@export var debug_weight_small_hill: int = DEFAULT_WEIGHT_SMALL_HILL
@export var debug_weight_medium_hill_valley_mix: int = DEFAULT_WEIGHT_MEDIUM_HILL_VALLEY_MIX
@export var debug_weight_big_downhill: int = DEFAULT_WEIGHT_BIG_DOWNHILL
@export var debug_weight_gentle_uphill: int = DEFAULT_WEIGHT_GENTLE_UPHILL
@export var debug_weight_mega_drop: int = MEGA_DROP_SELECTION_WEIGHT

var player: CharacterBody2D
var next_chunk_index: int = 0
var active_chunks: Dictionary[int, Node2D] = {}
var session_seed: int = 0
var session_floor_max_angle: float = 0.0
var segment_start_x_cache: Dictionary[int, float] = {}
var segment_length_cache: Dictionary[int, float] = {}
var segment_baseline_cache: Dictionary[int, float] = {}
var segment_spec_cache: Dictionary[int, Dictionary] = {}
var lowest_cached_segment_index: int = 0
var highest_cached_segment_index: int = 0
var segment_selection_weight_table: Array[Dictionary] = []

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
const SMALL_SEGMENT_LENGTH: float = 480.0
const MEDIUM_SEGMENT_LENGTH: float = 640.0
const SUSTAINED_DOWNHILL_LENGTH: float = 960.0
const SUSTAINED_DOWNHILL_DROP: float = 160.0
const GENTLE_UPHILL_LENGTH: float = SUSTAINED_DOWNHILL_LENGTH
const GENTLE_UPHILL_RISE: float = 28.0
const MEGA_DROP_TOTAL_VERTICAL_DROP: float = 1080.0
const MEGA_DROP_FLOOR_ANGLE_FRACTION: float = 0.9
const MEGA_DROP_SELECTION_WEIGHT: int = 10
const TERRAIN_FILL_DEPTH_MARGIN: float = 4096.0
const SMALL_HILL_AMPLITUDE: float = 56.0
const MEDIUM_HILL_AMPLITUDE: float = 74.0
const DEFAULT_WEIGHT_FLAT: int = 16
const DEFAULT_WEIGHT_SMALL_HILL: int = 16
const DEFAULT_WEIGHT_MEDIUM_HILL_VALLEY_MIX: int = 42
const DEFAULT_WEIGHT_BIG_DOWNHILL: int = 16
const DEFAULT_WEIGHT_GENTLE_UPHILL: int = 10
const HASH_MASK: int = 0x7fffffff
const HASH_INDEX_MULTIPLIER: int = 374761393
const HASH_MIX_MULTIPLIER: int = 668265263
const DEBUG_TERRAIN_LOGGING: bool = false
const DEBUG_SEGMENT_SELECTION_LOG_COUNT: int = 80


func _ready() -> void:
	player = get_node(player_path) as CharacterBody2D
	if player == null:
		push_error("TerrainGenerator requires a valid player_path.")
		set_physics_process(false)
		return

	session_seed = get_initial_session_seed()
	session_floor_max_angle = player.floor_max_angle
	segment_selection_weight_table = build_segment_selection_weight_table()
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


func build_segment_selection_weight_table() -> Array[Dictionary]:
	return [
		{"selection": SEGMENT_SELECTION_FLAT, "weight": debug_weight_flat},
		{"selection": SEGMENT_SELECTION_SMALL_HILL, "weight": debug_weight_small_hill},
		{"selection": SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX, "weight": debug_weight_medium_hill_valley_mix},
		{"selection": SEGMENT_SELECTION_BIG_DOWNHILL, "weight": debug_weight_big_downhill},
		{"selection": SEGMENT_SELECTION_GENTLE_UPHILL, "weight": debug_weight_gentle_uphill},
		{"selection": SEGMENT_SELECTION_MEGA_DROP, "weight": debug_weight_mega_drop},
	]


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


# Single dispatch point for terrain shape. Every other place that used to branch on
# segment_type/tier independently (baseline_delta, length, the selection label) now
# reads the same SegmentSpec this builds, so there is exactly one place that decides
# what a segment looks like.
func get_terrain_height(world_x: float) -> float:
	ensure_segment_cache_for_world_x(world_x)
	var segment_index: int = find_segment_index_at_x(world_x)
	var segment_start_x: float = segment_start_x_cache[segment_index]

	var segment_x: float = world_x - segment_start_x
	var spec: Dictionary = get_segment_spec(segment_index)
	var segment_baseline: float = get_segment_baseline(segment_index)
	var segment_progress: float = segment_x / float(spec["length"])
	return segment_baseline + evaluate_segment_offset(spec, segment_progress)


# The height offset from baseline at a given progress [0, 1] through the segment.
# Evaluating this at progress=1.0 is exactly the segment's baseline delta -- see
# get_segment_baseline_delta() -- so continuity between segments is guaranteed by
# construction instead of by a hand-maintained duplicate of each shape's endpoint.
func evaluate_segment_offset(spec: Dictionary, segment_progress: float) -> float:
	var segment_type: int = int(spec["type"])
	var magnitude: float = float(spec["magnitude"])
	if segment_type == SEGMENT_TYPE_FLAT:
		return 0.0
	if segment_type == SEGMENT_TYPE_DOWNHILL:
		return get_transition_profile(segment_progress) * magnitude
	if segment_type == SEGMENT_TYPE_UPHILL:
		return -get_transition_profile(segment_progress) * magnitude
	if segment_type == SEGMENT_TYPE_HILL:
		# Godot's Y axis points down, so subtracting raises the hill visually.
		return -get_curve_profile(segment_progress) * magnitude

	# Adding the same profile mirrors the hill into a valley below baseline.
	return get_curve_profile(segment_progress) * magnitude


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
	segment_spec_cache.clear()
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


# Derived, not hand-written: evaluating the segment's own shape function at
# progress=1.0 is its endpoint value by definition, so this cannot drift out of sync
# with evaluate_segment_offset the way a separately-maintained delta could.
func get_segment_baseline_delta(segment_index: int) -> float:
	return evaluate_segment_offset(get_segment_spec(segment_index), 1.0)


func get_segment_tier(segment_index: int) -> int:
	return int(get_segment_spec(segment_index)["tier"])


func get_segment_length(segment_index: int) -> float:
	return float(get_segment_spec(segment_index)["length"])


func get_segment_type(segment_index: int) -> int:
	return int(get_segment_spec(segment_index)["type"])


func get_segment_selection_label(segment_index: int) -> String:
	return String(get_segment_spec(segment_index)["label"])


# mega_drop is a single segment (not the old 4-linear-segment chain), so this is a
# direct label check with no recursion or neighbour lookback.
func is_mega_drop_segment(segment_index: int) -> bool:
	return String(get_segment_spec(segment_index)["label"]) == "mega_drop"


func get_segment_spec(segment_index: int) -> Dictionary:
	if not segment_spec_cache.has(segment_index):
		segment_spec_cache[segment_index] = build_segment_spec(segment_index)
	return segment_spec_cache[segment_index]


# The one place that decides what a segment IS: its shape, length, magnitude (drop
# depth / rise height / hill-or-valley amplitude -- one field, since evaluate_segment_offset
# uses it identically per type), tier, and debug label. Everything else in this file
# reads this instead of re-deriving it.
func build_segment_spec(segment_index: int) -> Dictionary:
	var segment_selection: int = get_segment_selection(segment_index)

	if segment_selection == SEGMENT_SELECTION_MEGA_DROP:
		return {
			"type": SEGMENT_TYPE_DOWNHILL,
			"tier": SEGMENT_TIER_MEDIUM,
			"length": get_mega_drop_length(),
			"magnitude": MEGA_DROP_TOTAL_VERTICAL_DROP,
			"label": "mega_drop",
		}
	if segment_selection == SEGMENT_SELECTION_FLAT:
		return {
			"type": SEGMENT_TYPE_FLAT,
			"tier": SEGMENT_TIER_MEDIUM,
			"length": MEDIUM_SEGMENT_LENGTH,
			"magnitude": 0.0,
			"label": "flat",
		}
	if segment_selection == SEGMENT_SELECTION_BIG_DOWNHILL:
		return {
			"type": SEGMENT_TYPE_DOWNHILL,
			"tier": SEGMENT_TIER_MEDIUM,
			"length": SUSTAINED_DOWNHILL_LENGTH,
			"magnitude": SUSTAINED_DOWNHILL_DROP,
			"label": "sustained_downhill",
		}
	if segment_selection == SEGMENT_SELECTION_GENTLE_UPHILL:
		return {
			"type": SEGMENT_TYPE_UPHILL,
			"tier": SEGMENT_TIER_MEDIUM,
			"length": GENTLE_UPHILL_LENGTH,
			"magnitude": GENTLE_UPHILL_RISE,
			"label": "gentle_uphill",
		}
	if segment_selection == SEGMENT_SELECTION_SMALL_HILL:
		return {
			"type": SEGMENT_TYPE_HILL,
			"tier": SEGMENT_TIER_SMALL,
			"length": SMALL_SEGMENT_LENGTH,
			"magnitude": SMALL_HILL_AMPLITUDE,
			"label": "small_hill",
		}

	# SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX
	var segment_type: int = get_medium_mix_segment_type(segment_index)
	var label: String = "medium_hill" if segment_type == SEGMENT_TYPE_HILL else "medium_valley"
	return {
		"type": segment_type,
		"tier": SEGMENT_TIER_MEDIUM,
		"length": MEDIUM_SEGMENT_LENGTH,
		"magnitude": MEDIUM_HILL_AMPLITUDE,
		"label": label,
	}


func get_mega_drop_angle() -> float:
	return session_floor_max_angle * MEGA_DROP_FLOOR_ANGLE_FRACTION


# Length whose PEAK chord angle (of the same ease-in/out profile every other feature
# uses) lands exactly at get_mega_drop_angle(). Same derivation the old large_valley
# floor-angle minimum used: the ease curve's steepest point has slope
# (TOTAL_VERTICAL_DROP / length) * (PI / 2), solved for length at the target angle.
# floor_max_angle > 0 always in this project (see CLAUDE.md), so no zero-angle guard.
func get_mega_drop_length() -> float:
	return (MEGA_DROP_TOTAL_VERTICAL_DROP * PI) / (2.0 * tan(get_mega_drop_angle()))


func create_session_seed() -> int:
	var seed_generator: RandomNumberGenerator = RandomNumberGenerator.new()
	seed_generator.randomize()
	return int(seed_generator.randi())


func get_segment_selection(segment_index: int) -> int:
	var segment_selection: int = get_unconstrained_segment_selection(segment_index)
	if segment_selection != SEGMENT_SELECTION_FLAT:
		return segment_selection

	var previous_segment_selection: int = get_unconstrained_segment_selection(segment_index - 1)
	if previous_segment_selection != SEGMENT_SELECTION_FLAT:
		return segment_selection

	# The "no two flats in a row" rule assumes some other shape has weight to spend --
	# true whenever the shipping mix is in play. At the flat-only complexity level
	# every non-flat weight is 0, so there is no alternative to fall back to; without
	# this guard get_non_flat_segment_selection's fallback would force a hill in
	# anyway, breaking flat-only bisection. get_segment_selection_total_weight floors
	# at 1 for safe division elsewhere, so the raw sum is checked directly here.
	if not has_any_non_flat_weight():
		return segment_selection

	return get_non_flat_segment_selection(segment_index)


func has_any_non_flat_weight() -> bool:
	for entry: Dictionary in segment_selection_weight_table:
		var selection: int = int(entry["selection"])
		var weight: int = int(entry["weight"])
		if selection != SEGMENT_SELECTION_FLAT and weight > 0:
			return true
	return false


func get_unconstrained_segment_selection(segment_index: int) -> int:
	return get_weighted_segment_selection(get_segment_hash(segment_index))


func get_non_flat_segment_selection(segment_index: int) -> int:
	var total_weight: int = get_segment_selection_total_weight(false)
	var random_value: int = (get_segment_hash(segment_index) >> 8) % total_weight
	var accumulated_weight: int = 0
	for entry: Dictionary in segment_selection_weight_table:
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
	for entry: Dictionary in segment_selection_weight_table:
		var weight: int = int(entry["weight"])
		if weight <= 0:
			continue
		accumulated_weight += weight
		if weighted_value < accumulated_weight:
			return int(entry["selection"])
	return SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX


func get_segment_selection_total_weight(include_flat: bool) -> int:
	var total_weight: int = 0
	for entry: Dictionary in segment_selection_weight_table:
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


func get_slope_angle_at_x(world_x: float) -> float:
	var left_height: float = get_terrain_height(world_x - SLOPE_SAMPLE_DISTANCE)
	var right_height: float = get_terrain_height(world_x + SLOPE_SAMPLE_DISTANCE)
	return atan2(right_height - left_height, SLOPE_SAMPLE_DISTANCE * 2.0)


# The slope of the actual 16px-ish chord the collision polyline uses at world_x, not
# the continuous height field. get_slope_angle_at_x's +/-2px finite difference is an
# analytic approximation that can disagree with the physical chord underfoot by a
# couple of degrees on curved terrain -- the player was being aimed along that
# analytic angle while physically resting on the chord, injecting spurious vertical
# velocity every chord. Reuses the identical sample-point construction
# build_chunk_surface feeds into ConcavePolygonShape2D, so the two can't disagree.
func get_collision_chord_slope_angle(world_x: float) -> float:
	var chunk_index: int = int(floor(world_x / chunk_width))
	var chunk_start_x: float = float(chunk_index) * chunk_width
	var chunk_end_x: float = chunk_start_x + chunk_width
	var collision_sample_count: int = maxi(ceili(chunk_width / MAX_COLLISION_SEGMENT_LENGTH), 2)
	var sample_world_xs: Array[float] = get_chunk_surface_sample_world_xs(chunk_start_x, chunk_end_x, collision_sample_count, true)

	var left_world_x: float = sample_world_xs[0]
	var right_world_x: float = sample_world_xs[sample_world_xs.size() - 1]
	for sample_index: int in range(sample_world_xs.size() - 1):
		if world_x >= sample_world_xs[sample_index] and world_x <= sample_world_xs[sample_index + 1]:
			left_world_x = sample_world_xs[sample_index]
			right_world_x = sample_world_xs[sample_index + 1]
			break

	var left_height: float = get_terrain_height(left_world_x)
	var right_height: float = get_terrain_height(right_world_x)
	return atan2(right_height - left_height, right_world_x - left_world_x)


func apply_chunk_color(chunk: StaticBody2D, chunk_index: int) -> void:
	var terrain_fill: Polygon2D = chunk.get_node_or_null("TerrainFill") as Polygon2D
	if terrain_fill == null:
		return

	if chunk_index % 2 == 0:
		terrain_fill.color = LIGHT_CHUNK_COLOR
	else:
		terrain_fill.color = DARK_CHUNK_COLOR
