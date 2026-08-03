extends Node2D

class_name PowerupSpawner

# Same reasoning as CoinSpawner/ObstacleSpawner: a child of TerrainGenerator so
# world rebasing (which shifts TerrainGenerator.position.y directly in main.gd)
# carries every spawned powerup along for free.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")

signal powerup_collected(effect: StringName)

# Same contract as ObstacleSpawner.debug_spawning_disabled, and for a sharper reason:
# a speed powerup snaps current_speed to a flat 1000 px/s (PowerupManager.
# SPEED_BOOST_SPEED) for 3s, well above MAX_SPEED's 750, and a probe player collects
# every pickup it runs into. Left on, that injects two instantaneous speed step-changes
# per boost into any measurement of scroll rate or camera motion. It was measured:
# camera_shake_probe with powerups live reported flat mean jerk 0.0066 against the
# documented 0.002 baseline, with scroll_rate_x topping out at 17.2 px/frame -- 1032
# px/s, impossible under the ramp alone -- and that was the tell.
#
# Every harness that steps past FIRST_POWERUP_MIN_TIME (freeze_search.gd,
# freeze_ab_runner.gd, stall_recovery_probe.gd, camera_shake_probe.gd,
# floor_flicker_probe.gd, freeze_replay_runner.gd) sets this true before add_child(main).
var debug_spawning_disabled: bool = false

const SPEED_POWERUP_SCENE: PackedScene = preload("res://scenes/pickups/speed_powerup.tscn")
const JUMP_POWERUP_SCENE: PackedScene = preload("res://scenes/pickups/jump_powerup.tscn")
# Above the sampled surface, low enough to be grabbed while grounded (player
# capsule half-height is 24px) -- same reasoning as CoinSpawner's clearance.
const POWERUP_SURFACE_CLEARANCE: float = 40.0

# Cadence is timed against Player.speed_manager.elapsed_time, not a fixed
# world_x spacing -- same reasoning as ObstacleSpawner: with the two-phase
# speed ramp, a fixed world_x interval covers wildly different real time
# depending on where in the ramp it falls.
#
# No powerup of either kind ever appears before this. Each kind's first spawn
# is then drawn uniformly from [FIRST_POWERUP_MIN_TIME, FIRST_POWERUP_MIN_TIME
# + (MAX - MIN)), so the earliest possible spawn is exactly this floor. Every
# spawn after that recurs at a fresh interval drawn from [MIN, MAX), measured
# from the previous one -- speed and jump powerups run on independent
# schedules, each averaging (MIN+MAX)/2 = 60s, i.e. "once a minute each".
const FIRST_POWERUP_MIN_TIME: float = 15.0
const POWERUP_INTERVAL_MIN: float = 30.0
const POWERUP_INTERVAL_MAX: float = 90.0
# Mirrors the chunk spawners' forward lookahead so pickups are never seen
# popping into existence.
const SPAWN_LOOKAHEAD_WORLD_X: float = 1500.0
# Well behind the player is safe to free -- an uncollected pickup this far back
# (e.g. jumped over) is unreachable again.
const DESPAWN_BEHIND_WORLD_X: float = 1500.0
const HASH_MASK: int = 0x7fffffff
# Distinct multiplier pair from TerrainGenerator.get_segment_hash,
# CoinSpawner.get_slot_hash, and ObstacleSpawner.get_cluster_hash so this
# sequence doesn't correlate with any of them, even though all key off the
# same session_seed.
const HASH_INDEX_MULTIPLIER: int = 40503
const HASH_MIX_MULTIPLIER: int = 2246822519

var terrain_generator: TerrainGenerator
var player: Player
var next_speed_powerup_time: float = -1.0
var next_jump_powerup_time: float = -1.0
var next_speed_powerup_index: int = 0
var next_jump_powerup_index: int = 0
var active_powerups: Array[Node2D] = []
var has_initialized_schedule: bool = false


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as Player
	if terrain_generator == null or player == null:
		push_error("PowerupSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)


# The first-spawn draws are deliberately NOT made in _ready(), for the same reason
# CoinSpawner defers initialize_coin_groups(): this node is a child of TerrainGenerator,
# Godot runs _ready() on children before their parent, and get_powerup_hash() reads
# TerrainGenerator.session_seed -- which is still 0 at that point. Measured 2026-08-03:
# three different replay seeds all produced the identical pair of first-spawn times
# (39.812038s / 19.395459s), because every one of them hashed seed 0. Every node's
# _ready() has run by the first _physics_process(), so this is the safe point.
func initialize_schedule() -> void:
	next_speed_powerup_time = FIRST_POWERUP_MIN_TIME + get_powerup_hash(0, 0, 0) * (POWERUP_INTERVAL_MAX - POWERUP_INTERVAL_MIN)
	next_jump_powerup_time = FIRST_POWERUP_MIN_TIME + get_powerup_hash(0, 1, 0) * (POWERUP_INTERVAL_MAX - POWERUP_INTERVAL_MIN)


func _physics_process(_delta: float) -> void:
	# Explicit null guard rather than trusting _ready()'s set_physics_process(false):
	# that call is documented (docs/development/debugging.md) as not reliably
	# suppressing _physics_process in headless harness runs, and everything below
	# dereferences both of these.
	if terrain_generator == null or player == null:
		return

	# Runs even when spawning is disabled, so a harness that flips the flag mid-run
	# still finds a correctly seeded schedule rather than the -1.0 sentinel.
	if not has_initialized_schedule:
		has_initialized_schedule = true
		initialize_schedule()

	if debug_spawning_disabled:
		return

	var elapsed_time: float = player.speed_manager.elapsed_time
	var lookahead_world_x: float = player.global_position.x + SPAWN_LOOKAHEAD_WORLD_X

	while elapsed_time >= next_speed_powerup_time:
		spawn_powerup(SPEED_POWERUP_SCENE, lookahead_world_x, &"speed_boost")
		next_speed_powerup_index += 1
		var interval: float = POWERUP_INTERVAL_MIN + (get_powerup_hash(next_speed_powerup_index, 0, 1) * (POWERUP_INTERVAL_MAX - POWERUP_INTERVAL_MIN))
		next_speed_powerup_time += interval

	while elapsed_time >= next_jump_powerup_time:
		spawn_powerup(JUMP_POWERUP_SCENE, lookahead_world_x, &"jump_boost")
		next_jump_powerup_index += 1
		var interval: float = POWERUP_INTERVAL_MIN + (get_powerup_hash(next_jump_powerup_index, 1, 1) * (POWERUP_INTERVAL_MAX - POWERUP_INTERVAL_MIN))
		next_jump_powerup_time += interval

	var despawn_world_x: float = player.global_position.x - DESPAWN_BEHIND_WORLD_X
	for index: int in range(active_powerups.size() - 1, -1, -1):
		var powerup: Node2D = active_powerups[index]
		if not is_instance_valid(powerup):
			active_powerups.remove_at(index)
		elif powerup.position.x < despawn_world_x:
			# queue_free(), not free(): this runs inside _physics_process and a powerup is
			# an Area2D. Same reasoning as TerrainGenerator.remove_chunk().
			powerup.queue_free()
			active_powerups.remove_at(index)


func spawn_powerup(scene: PackedScene, world_x: float, effect: StringName) -> void:
	var world_y: float = terrain_generator.ground_y + terrain_generator.get_terrain_height(world_x) - POWERUP_SURFACE_CLEARANCE
	var powerup: Powerup = scene.instantiate() as Powerup
	powerup.position = Vector2(world_x, world_y)
	powerup.collected.connect(_on_powerup_collected.bind(effect))
	add_child(powerup)
	active_powerups.append(powerup)


func _on_powerup_collected(effect: StringName) -> void:
	powerup_collected.emit(effect)


# Pure function of (session_seed, powerup_index, channel, sub_channel) -> [0, 1).
# Same style as ObstacleSpawner.get_cluster_hash; channel separates the speed
# (0) and jump (1) schedules, sub_channel separates first-spawn draws (0) from
# recurrence-interval draws (1) within a schedule.
func get_powerup_hash(powerup_index: int, channel: int, sub_channel: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ (((powerup_index * 4 + channel * 2 + sub_channel) + 1) * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)
