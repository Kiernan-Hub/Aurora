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
# camera_shake_probe with powerups live reported flat mean jerk 0.0066, with scroll_rate_x
# topping out at 17.2 px/frame -- 1032 px/s, impossible under the ramp alone -- and the
# scroll rate was the tell.
#
# Use the SCROLL RATE, not the jerk, to spot this. The "0.002 flat baseline" this comment
# used to cite as the jerk comparison no longer matches what the probe prints: on this
# branch a clean tree measures flat mean jerk 0.00580 (seed 941462462, 7000 frames,
# warmup 120), verified 2026-08-05 by stashing and re-running. 0.0066-vs-0.002 therefore
# looks like a much sharper signal than it is, and it cost a full A/B to rule out.
# scroll_rate_x is unambiguous: nothing but a boost can exceed MAX_SPEED's 12.5 px/frame.
#
# Every harness that steps past FIRST_POWERUP_MIN_TIME (freeze_search.gd,
# freeze_ab_runner.gd, stall_recovery_probe.gd, camera_shake_probe.gd,
# floor_flicker_probe.gd, freeze_replay_runner.gd) sets this true before add_child(main).
#
# NOTE for anyone verifying a change to THIS file: because every gate sets this, no gate
# can see a spawner regression. They all report green with powerups completely broken.
# A change here has to be checked with spawning left ON.
var debug_spawning_disabled: bool = false

# Forces every spawn to one effect, for editor testing of a specific powerup without
# waiting on the weighted draw. Debug-only convenience, never set in shipped code.
var debug_forced_effect: StringName = &""

# The full powerup catalogue: one row per kind, and the ONLY place a kind is declared.
#
# Replaced a per-kind schedule (each with its own next-time var, hash channel and while
# loop) on 2026-08-05. That structure cost a copy-pasted block per powerup AND scaled the
# spawn RATE with the number of kinds -- two kinds on independent 60s-average schedules is
# a pickup every ~30s, so six kinds would have been one every ~10s. Here the schedule is
# fixed and the table only decides WHICH kind, so adding a powerup changes variety without
# touching density.
#
# `weight` is relative, not a percentage; get_weighted_effect_index() normalises. A kind's
# expected spacing is (average interval) * (total weight / its weight).
const POWERUP_TABLE: Array[Dictionary] = [
	{
		"effect": PowerupManager.EFFECT_SPEED_BOOST,
		"scene": preload("res://scenes/pickups/speed_powerup.tscn"),
		"weight": 22.0,
	},
	{
		"effect": PowerupManager.EFFECT_JUMP_BOOST,
		"scene": preload("res://scenes/pickups/jump_powerup.tscn"),
		"weight": 22.0,
	},
]

# Above the sampled surface, low enough to be grabbed while grounded (player
# capsule half-height is 24px) -- same reasoning as CoinSpawner's clearance.
const POWERUP_SURFACE_CLEARANCE: float = 40.0

# Cadence is timed against Player.speed_manager.elapsed_time, not a fixed
# world_x spacing -- same reasoning as ObstacleSpawner: with the two-phase
# speed ramp, a fixed world_x interval covers wildly different real time
# depending on where in the ramp it falls.
#
# No powerup appears before this. The first spawn is drawn uniformly from
# [FIRST_POWERUP_MIN_TIME, FIRST_POWERUP_MIN_TIME + (MAX - MIN)), so the earliest possible
# spawn is exactly this floor. Every spawn after that recurs at a fresh interval drawn from
# [MIN, MAX), measured from the previous one.
#
# [18, 42) averages 30s, which is deliberately the SAME total pickup density the two
# independent 60s-average schedules produced before the table existed. Variety comes from
# POWERUP_TABLE; the player does not get more pickups per minute than they used to.
const FIRST_POWERUP_MIN_TIME: float = 15.0
const POWERUP_INTERVAL_MIN: float = 18.0
const POWERUP_INTERVAL_MAX: float = 42.0
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
# Hash channels: one draw decides WHEN the next powerup comes, an independent one decides
# WHICH kind it is. Separate channels so retuning the interval cannot shuffle the kind
# sequence, and vice versa.
const HASH_CHANNEL_INTERVAL: int = 0
const HASH_CHANNEL_KIND: int = 1

var terrain_generator: TerrainGenerator
var player: Player
var next_powerup_time: float = -1.0
var next_powerup_index: int = 0
var active_powerups: Array[Node2D] = []
var has_initialized_schedule: bool = false


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as Player
	if terrain_generator == null or player == null:
		push_error("PowerupSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)


# The first-spawn draw is deliberately NOT made in _ready(), for the same reason
# CoinSpawner defers initialize_coin_groups(): this node is a child of TerrainGenerator,
# Godot runs _ready() on children before their parent, and get_powerup_hash() reads
# TerrainGenerator.session_seed -- which is still 0 at that point. Measured 2026-08-03:
# three different replay seeds all produced the identical pair of first-spawn times
# (39.812038s / 19.395459s), because every one of them hashed seed 0. Every node's
# _ready() has run by the first _physics_process(), so this is the safe point.
func initialize_schedule() -> void:
	next_powerup_time = FIRST_POWERUP_MIN_TIME + get_powerup_hash(0, HASH_CHANNEL_INTERVAL) * (POWERUP_INTERVAL_MAX - POWERUP_INTERVAL_MIN)


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

	while elapsed_time >= next_powerup_time:
		var table_row: Dictionary = POWERUP_TABLE[get_weighted_effect_index(next_powerup_index)]
		spawn_powerup(table_row["scene"], lookahead_world_x, table_row["effect"])
		next_powerup_index += 1
		next_powerup_time += POWERUP_INTERVAL_MIN + (get_powerup_hash(next_powerup_index, HASH_CHANNEL_INTERVAL) * (POWERUP_INTERVAL_MAX - POWERUP_INTERVAL_MIN))

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


# Index into POWERUP_TABLE for the given spawn, drawn from the kind channel and weighted.
# Pure in (session_seed, powerup_index) like every other selection in the project, so a
# replayed seed lays out the identical powerup sequence.
func get_weighted_effect_index(powerup_index: int) -> int:
	if debug_forced_effect != &"":
		for index: int in range(POWERUP_TABLE.size()):
			if POWERUP_TABLE[index]["effect"] == debug_forced_effect:
				return index

	var total_weight: float = 0.0
	for table_row: Dictionary in POWERUP_TABLE:
		total_weight += table_row["weight"]

	var target_weight: float = get_powerup_hash(powerup_index, HASH_CHANNEL_KIND) * total_weight
	var accumulated_weight: float = 0.0
	for index: int in range(POWERUP_TABLE.size()):
		accumulated_weight += POWERUP_TABLE[index]["weight"]
		if target_weight < accumulated_weight:
			return index
	# Only reachable if the hash returns exactly 1.0, which it cannot -- but a spawn with
	# no kind would be a null scene, so fall back rather than trusting that.
	return POWERUP_TABLE.size() - 1


func spawn_powerup(scene: PackedScene, world_x: float, effect: StringName) -> void:
	# Nudged past a void rather than skipped, unlike a coin slot: this is a scheduled reward
	# with no second chance, and silently dropping it would surface as "powerups sometimes
	# just don't come" long after anyone remembers why.
	world_x = terrain_generator.get_next_ground_world_x(world_x)
	var world_y: float = terrain_generator.ground_y + terrain_generator.get_terrain_height(world_x) - POWERUP_SURFACE_CLEARANCE
	var powerup: Powerup = scene.instantiate() as Powerup
	powerup.position = Vector2(world_x, world_y)
	powerup.collected.connect(_on_powerup_collected.bind(effect))
	add_child(powerup)
	active_powerups.append(powerup)


func _on_powerup_collected(effect: StringName) -> void:
	powerup_collected.emit(effect)


# Pure function of (session_seed, powerup_index, channel) -> [0, 1).
# Same style as ObstacleSpawner.get_cluster_hash; channel separates the interval draw
# from the kind draw so the two sequences are independent.
func get_powerup_hash(powerup_index: int, channel: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ (((powerup_index * 2 + channel) + 1) * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)
