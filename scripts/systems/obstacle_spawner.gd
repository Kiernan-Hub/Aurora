extends Node2D

class_name ObstacleSpawner

# Same reasoning as CoinSpawner: a child of TerrainGenerator so world rebasing
# (which shifts TerrainGenerator.position.y directly in main.gd) carries every
# spawned obstacle along for free.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")

# Debug/testing aid, same pattern as Main.world_rebase_enabled / Player.
# DEBUG_LOG_FREEZE_REPRO / GameManager.require_start_screen: a plain script var,
# not @export (so it can't get silently serialized into main.tscn), checked
# directly in _physics_process(). Deliberately NOT done via set_physics_process(
# false) -- that call does not reliably suppress this node's _physics_process in
# the headless debug-harness contexts that need it (verified: is_physics_processing()
# reported false while _physics_process kept firing every frame regardless).
# Harnesses that run long enough to reach a cluster's trigger time
# (freeze_search.gd, freeze_ab_runner.gd, stall_recovery_probe.gd,
# camera_shake_probe.gd, floor_flicker_probe.gd, freeze_replay_runner.gd) set this
# to true before add_child(main).
var debug_spawning_disabled: bool = false

const OBSTACLE_SCENE: PackedScene = preload("res://scenes/obstacles/obstacle.tscn")
# Half of obstacle.tscn's RectangleShape2D size (32x32), so the box sits on top of
# the surface rather than centered on it or floating above it.
const OBSTACLE_HALF_HEIGHT: float = 16.0
# Only place on close-to-flat ground: an obstacle glued to a slope reads as
# unfair (its hitbox stops matching what the eye expects the moment the surface
# tilts under it), and a steep approach also eats into the player's reaction
# window. get_slope_angle_at_x is the analytic (cosmetic) angle -- fine here,
# unlike Player.get_slope_tangent(), since nothing physical rides on this value.
const OBSTACLE_MAX_SLOPE_ANGLE: float = deg_to_rad(6.0)
# Clamp on how close to spawn a cluster can ever land: the old hand-placed
# obstacle at (68,56) killed the player mid-jump at t=0.10s
# (docs/development/dead_code.md) because it sat inside the player's very
# first few physics steps. FIRST_CLUSTER_TIME being 20s already keeps well
# clear of this in practice; this is just a floor.
const MIN_SAFE_START_WORLD_X: float = 900.0

# Cluster cadence is timed against Player.speed_manager.elapsed_time, not a
# fixed world_x spacing: with the two-phase speed ramp (SpeedManager), a fixed
# world_x interval would take wildly different real time to reach depending on
# when in the ramp it falls, which is exactly the "not actually once a minute"
# bug this replaces.
#
# The first cluster is small and shows up quickly; every cluster after it is
# bigger and keeps recurring at a fresh random interval, so obstacles get MORE
# frequent as a run goes on, not less.
const FIRST_CLUSTER_TIME: float = 20.0
const FIRST_CLUSTER_MIN_COUNT: int = 1
const FIRST_CLUSTER_MAX_COUNT: int = 3
# The 2nd cluster's absolute time is itself randomized in this window (not a
# fixed point), and every cluster after that recurs at a fresh random interval
# drawn from the same window, measured from the previous cluster's time --
# "anywhere from 50-70 seconds" as an ongoing cadence, not a one-off gap.
const RECURRING_CLUSTER_MIN_INTERVAL: float = 50.0
const RECURRING_CLUSTER_MAX_INTERVAL: float = 70.0
const RECURRING_CLUSTER_MIN_COUNT: int = 1
const RECURRING_CLUSTER_MAX_COUNT: int = 5

# Passability for a multi-obstacle cluster has exactly two safe regimes: gap
# far enough apart that a jump over one obstacle lands clear of the next
# (reaction + re-jump), or close enough together that a SINGLE jump clears the
# whole run of them. The dangerous middle ground is a gap close to the jump's
# own landing distance, which risks landing on top of the next obstacle.
# Jump horizontal reach (very roughly, flat ground) is
# 2*(-JUMP_VELOCITY/GRAVITY)*speed = 0.8*speed. FIRST_CLUSTER_TIME (20s) is
# the earliest an obstacle ever appears, and SpeedManager's ramp is
# monotonically non-decreasing after that, so speed at t=20s (~523px/s, reach
# ~418px) is the lowest reach any cluster will ever be judged against, and
# MAX_SPEED (750px/s, reach 600px) is the highest. TIGHT sits under the lower
# bound; WIDE sits over the upper bound, with margin on both.
const CLUSTER_TIGHT_GAP_WORLD_X: float = 260.0
const CLUSTER_WIDE_GAP_WORLD_X: float = 700.0

# Mirrors the chunk spawners' forward lookahead so a cluster is never seen
# popping into existence right underfoot.
const SPAWN_LOOKAHEAD_WORLD_X: float = 800.0
# Well behind the player is safe to free -- a cluster this far back is done
# regardless of whether it was cleared or hit.
const DESPAWN_BEHIND_WORLD_X: float = 1500.0
const HASH_MASK: int = 0x7fffffff
# Distinct multiplier pair from both TerrainGenerator.get_segment_hash and
# CoinSpawner.get_slot_hash so none of the hash sequences correlate, even
# though all three ultimately key off the same session_seed.
const HASH_INDEX_MULTIPLIER: int = 2654435761
const HASH_MIX_MULTIPLIER: int = 1274126177

var terrain_generator: TerrainGenerator
var player: Player
var next_cluster_time: float = FIRST_CLUSTER_TIME
var next_cluster_index: int = 0
var active_obstacles: Array[Node2D] = []


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as Player
	if terrain_generator == null or player == null:
		push_error("ObstacleSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if debug_spawning_disabled:
		return

	while player.speed_manager.elapsed_time >= next_cluster_time:
		spawn_cluster(next_cluster_index)
		next_cluster_index += 1
		var interval: float = RECURRING_CLUSTER_MIN_INTERVAL + (get_cluster_hash(next_cluster_index, 1) * (RECURRING_CLUSTER_MAX_INTERVAL - RECURRING_CLUSTER_MIN_INTERVAL))
		next_cluster_time += interval

	var despawn_world_x: float = player.global_position.x - DESPAWN_BEHIND_WORLD_X
	for index: int in range(active_obstacles.size() - 1, -1, -1):
		var obstacle: Node2D = active_obstacles[index]
		if not is_instance_valid(obstacle):
			active_obstacles.remove_at(index)
		elif obstacle.position.x < despawn_world_x:
			# queue_free(), not free(): this runs inside _physics_process and an obstacle
			# is an Area2D. Same reasoning as TerrainGenerator.remove_chunk(). It is
			# dropped from active_obstacles in the same step, so the extra frame it
			# survives is not observable here.
			obstacle.queue_free()
			active_obstacles.remove_at(index)


func spawn_cluster(cluster_index: int) -> void:
	var min_count: int = FIRST_CLUSTER_MIN_COUNT if cluster_index == 0 else RECURRING_CLUSTER_MIN_COUNT
	var max_count: int = FIRST_CLUSTER_MAX_COUNT if cluster_index == 0 else RECURRING_CLUSTER_MAX_COUNT
	var obstacle_count: int = min_count + int(get_cluster_hash(cluster_index, 0) * float(max_count - min_count + 1))
	var gap_world_x: float = CLUSTER_TIGHT_GAP_WORLD_X if get_cluster_hash(cluster_index, 2) < 0.5 else CLUSTER_WIDE_GAP_WORLD_X
	var cluster_start_world_x: float = maxf(MIN_SAFE_START_WORLD_X, player.global_position.x + SPAWN_LOOKAHEAD_WORLD_X)

	for slot_index: int in range(obstacle_count):
		var world_x: float = cluster_start_world_x + (float(slot_index) * gap_world_x)
		# Skip (don't reposition) a slot that lands on a slope -- a shorter
		# cluster is fine, an obstacle glued to a slope isn't (see
		# OBSTACLE_MAX_SLOPE_ANGLE above).
		if absf(terrain_generator.get_slope_angle_at_x(world_x)) > OBSTACLE_MAX_SLOPE_ANGLE:
			continue
		spawn_obstacle(world_x)


func spawn_obstacle(world_x: float) -> void:
	var world_y: float = terrain_generator.ground_y + terrain_generator.get_terrain_height(world_x) - OBSTACLE_HALF_HEIGHT
	var obstacle: Area2D = OBSTACLE_SCENE.instantiate() as Area2D
	obstacle.position = Vector2(world_x, world_y)
	add_child(obstacle)
	active_obstacles.append(obstacle)


# Pure function of (session_seed, cluster_index, channel) -> [0, 1). Same
# style as TerrainGenerator.get_segment_hash / CoinSpawner.get_slot_hash, with
# its own multiplier pair so this sequence doesn't correlate with either.
# channel 0 = obstacle count, 1 = recurrence interval, 2 = gap style.
func get_cluster_hash(cluster_index: int, channel: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ ((cluster_index * 3 + channel) * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)
