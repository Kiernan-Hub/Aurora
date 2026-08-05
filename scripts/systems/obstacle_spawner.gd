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
# Chasm exclusion around an obstacle slot. AHEAD covers the maximum jump reach (600px at
# MAX_SPEED) plus margin, because an obstacle that forces a jump into a void is unavoidable
# death. BEHIND only has to stop an obstacle sitting on the landing side of a far lip.
const OBSTACLE_VOID_CLEARANCE_AHEAD: float = 700.0
const OBSTACLE_VOID_CLEARANCE_BEHIND: float = 200.0
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
# Every "cluster" is exactly one obstacle -- multi-obstacle groups (formerly
# 1-5 with a tight/wide gap between them) were cut in favor of frequent
# singles, which reads as a harder, steadier stream of hazards rather than a
# quiet stretch followed by a wall of boxes. FIRST_CLUSTER_TIME is left
# untouched: terrain_invariant_check's check_obstacle_clearance() derives the
# slowest speed an obstacle is ever judged against from this constant, and
# lowering it tightens that jump-clearance window rather than loosening it.
const FIRST_CLUSTER_TIME: float = 20.0
# Cadence ramps up in OBSTACLE_RAMP_WINDOW-second steps: ~1 obstacle in the
# first window, ~2 in the second, ~3 in the third, and so on, each window's
# obstacles spread by a randomized interval (not evenly spaced) drawn around
# that window's average. target_count is clamped at OBSTACLE_RAMP_MAX_COUNT
# so the density stops climbing once it's already denser than the speed ramp
# (which caps at t=120s, MAX_SPEED) can justify -- otherwise an endless run
# eventually asks for an impossible obstacle-per-second rate.
const OBSTACLE_RAMP_WINDOW: float = 30.0
const OBSTACLE_RAMP_MAX_COUNT: int = 6
# Absolute floor under the random interval regardless of how dense the ramp
# above wants to go, so a jittered-down roll can never land two obstacles
# closer together than a player has time to react to.
const RECURRING_CLUSTER_MIN_INTERVAL_FLOOR: float = 4.0

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
	# Explicit null guard rather than trusting _ready()'s set_physics_process(false):
	# that call is documented (docs/development/debugging.md) as not reliably
	# suppressing _physics_process in headless harness runs, and everything below
	# dereferences both of these.
	if terrain_generator == null or player == null:
		return

	if debug_spawning_disabled:
		return

	# not player.is_boosting: a boost forces the grounded model and suppresses jump
	# input for its full 3s (player.gd, is_boosting), so a cluster landing inside one
	# is unavoidable death (CLAUDE.md Known Issues). Withholding next_cluster_time's
	# advance, rather than skipping the cluster outright, means the wait ends the
	# instant the boost does -- and spawn_cluster always places its obstacle
	# SPAWN_LOOKAHEAD_WORLD_X ahead of wherever the player currently is, so one
	# spawned right as the boost ends still gets the same reaction-time lookahead as
	# any other. A boost (3s) can never span two trigger times (12-30s apart), so
	# this doesn't need the catch-up a `while` gives the despawn loop below.
	if player.speed_manager.elapsed_time >= next_cluster_time and not player.is_boosting:
		spawn_cluster()
		next_cluster_index += 1
		var interval_bounds: Vector2 = get_interval_bounds(player.speed_manager.elapsed_time)
		var interval: float = interval_bounds.x + (get_cluster_hash(next_cluster_index) * (interval_bounds.y - interval_bounds.x))
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


# The randomized interval band for the window elapsed_time currently falls in --
# see the ramp comment above OBSTACLE_RAMP_WINDOW. +/-30% jitter around the
# window's average keeps the cadence from reading as a metronome while still
# landing roughly the target obstacle count per window.
func get_interval_bounds(elapsed_time: float) -> Vector2:
	var window: int = int(elapsed_time / OBSTACLE_RAMP_WINDOW)
	var target_count: int = mini(window + 1, OBSTACLE_RAMP_MAX_COUNT)
	var average_interval: float = OBSTACLE_RAMP_WINDOW / float(target_count)
	var min_interval: float = maxf(RECURRING_CLUSTER_MIN_INTERVAL_FLOOR, average_interval * 0.7)
	var max_interval: float = maxf(min_interval + 0.1, average_interval * 1.3)
	return Vector2(min_interval, max_interval)


# Places (up to) one obstacle. Takes no index now that count/gap randomization is gone
# (multi-obstacle groups were cut, see the comment above FIRST_CLUSTER_TIME) -- kept as
# a distinct function from spawn_obstacle() because it's the one that applies the
# slope/chasm placement rules, where spawn_obstacle() is the unconditional placer.
func spawn_cluster() -> void:
	var world_x: float = maxf(MIN_SAFE_START_WORLD_X, player.global_position.x + SPAWN_LOOKAHEAD_WORLD_X)
	# Skip (don't reposition) a slot that lands on a slope -- a missed obstacle
	# this cycle is fine, an obstacle glued to a slope isn't (see
	# OBSTACLE_MAX_SLOPE_ANGLE above).
	if absf(terrain_generator.get_slope_angle_at_x(world_x)) > OBSTACLE_MAX_SLOPE_ANGLE:
		return
	# Second reason to skip, and this one is safety-critical rather than cosmetic. An
	# obstacle within one jump reach BEFORE a chasm's near lip is unavoidable death:
	# clearing the obstacle commits the player to a landing, and that landing is in the
	# void. Max reach is 0.8s airtime * MAX_SPEED 750 = 600px, so the exclusion runs
	# OBSTACLE_VOID_CLEARANCE_AHEAD past the obstacle and a shorter margin behind it.
	if not terrain_generator.has_ground_over_world_x_span(world_x - OBSTACLE_VOID_CLEARANCE_BEHIND, world_x + OBSTACLE_VOID_CLEARANCE_AHEAD):
		return
	spawn_obstacle(world_x)


func spawn_obstacle(world_x: float) -> void:
	var world_y: float = terrain_generator.ground_y + terrain_generator.get_terrain_height(world_x) - OBSTACLE_HALF_HEIGHT
	var obstacle: Area2D = OBSTACLE_SCENE.instantiate() as Area2D
	obstacle.position = Vector2(world_x, world_y)
	add_child(obstacle)
	active_obstacles.append(obstacle)


# Pure function of (session_seed, cluster_index) -> [0, 1), used to draw the next
# recurrence interval. Same style as TerrainGenerator.get_segment_hash /
# CoinSpawner.get_slot_hash, with its own multiplier pair so this sequence doesn't
# correlate with either.
func get_cluster_hash(cluster_index: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ (cluster_index * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)
