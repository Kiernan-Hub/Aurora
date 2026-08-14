extends Node2D

class_name RareCoinSpawner

# One high-value coin, roughly once a minute, hung at a height only a FULLY UPGRADED jump
# reaches. It is the one object in the game whose position is a statement about the upgrade
# tree: seeing it and missing it is the intended experience at every level below the last.
#
# A child of TerrainGenerator for the same reason as CoinSpawner and GlideCoinSpawner --
# world rebasing shifts TerrainGenerator.position.y directly (main.gd, ~every 26s) and every
# descendant inherits that shift for free. As with GlideCoinSpawner, this node sits directly
# under TerrainGenerator with no offset of its own, so a coin's local position IS already in
# the same space get_terrain_height() returns.
#
# WHY A SEPARATE NODE AND NOT A THIRD MODE INSIDE CoinSpawner. Two different lifetimes:
# CoinSpawner's coins belong to a CHUNK and die with it, these are timed and despawn behind
# the player like an obstacle. Folding them in would mean one node running two unrelated
# lifecycle models over one array. The whole file is ~120 lines because it copies
# PowerupSpawner's shape exactly.
#
# NOT PULLED BY THE COIN MAGNET, deliberately. The magnet lives in CoinSpawner and only walks
# its own chunk groups, so this needs no code to opt out -- but it is a decision, not an
# accident: MAGNET_RADIUS is 220px and the coin hangs at 174, so a magnet would hand it to a
# level-0 player and delete the reason it is up there.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")

signal coin_collected(value: int)

# Same plain-var (never @export) debug knob as ObstacleSpawner's -- see its note. Nothing in
# the harness set flips this today: a rare coin is an Area2D on layer 2 that only reacts to
# the player group, so it cannot affect a physics measurement. It exists so that a future
# probe which does care has the same switch in the same place as its neighbours.
var debug_spawning_disabled: bool = false

const RARE_COIN_SCENE: PackedScene = preload("res://scenes/pickups/rare_coin.tscn")

# THE NUMBER THIS WHOLE FILE EXISTS FOR. Height above the terrain surface, in the same local-y
# units get_terrain_height() returns, and it is derived, not tasted:
#
#   apex          = JUMP_VELOCITY^2 / (2 * GRAVITY) = (640 * m)^2 / 3200 = 128 * m^2
#   grab ceiling  = 48 + apex + coin radius(10) = 58 + 128 * m^2
#
# (48 = the player capsule's full height from centre to top, twice the 24px half-height: the
# capsule's TOP is what reaches, and it starts one half-height above the surface.)
#
#   level   0     1     2     3     4
#   m       0.60  0.70  0.80  0.90  1.00
#   apex    46.1  62.7  81.9  103.7 128.0
#   ceiling 104.1 120.7 139.9 161.7 186.0
#
# 174 sits 12.3px above level 3's ceiling and 12px below level 4's -- the widest margin the
# gap allows, which matters because both errors are silent (too low and the reward is not
# exclusive, too high and it is unobtainable and reads as a bug).
#
# THIS IS COUPLED TO FOUR CONSTANTS IN THREE FILES: Player.JUMP_VELOCITY, Player.GRAVITY,
# UpgradeStore.JUMP_MULTIPLIERS' last two entries, and rare_coin.tscn's CircleShape2D radius.
# Move any of them and this must be re-derived. terrain_invariant_check's
# check_rare_coin_height() asserts the whole table above, so it fails the build instead.
const RARE_COIN_CLEARANCE: float = 174.0

# The jump powerup multiplies jump velocity by sqrt(2), which DOUBLES the apex -- so a level-0
# player holding one reaches 150px and a level-1 player 183px. That is not a leak in the rule
# above, it is the powerup doing exactly what it says: the coin stays out of reach of every
# level below the last for an ordinary jump, and a powerup is the one thing that changes it.

# Cadence, timed against SpeedManager.elapsed_time rather than spaced in world_x, for the
# reason ObstacleSpawner's own note gives: the two-phase speed ramp makes a fixed px spacing
# take wildly different real time depending on where in the ramp it lands.
const FIRST_RARE_COIN_TIME: float = 45.0
const RARE_COIN_INTERVAL_MIN: float = 50.0
const RARE_COIN_INTERVAL_MAX: float = 70.0
# A slot can be rejected (slope, a non-flat take-off run, or a void inside the jump's reach).
# Retrying shortly rather than advancing the schedule is the difference between "roughly once a
# minute" and "once a minute unless the terrain says no", which over a long run is a visibly
# different game.
#
# 1.0s, down from 3.0, because the flat-take-off rule cut the share of acceptable slots to
# about 6% (measured over four seeds, 1446 samples each). At 3s a rejected slot cost ~48s of
# expected extra wait, which quietly halved how often the diamond appeared; at 1s it is ~16s.
const REJECTED_SLOT_RETRY_DELAY: float = 1.0

# Mirrors the other spawners' forward lookahead so the coin enters from off-screen.
const SPAWN_LOOKAHEAD_WORLD_X: float = 800.0
const DESPAWN_BEHIND_WORLD_X: float = 1500.0
# Only over near-flat ground. Jumping from a slope changes both the apex and where it lands
# relative to the coin, which is exactly the derivation above coming apart -- and the same
# reason ObstacleSpawner has this rule, at the same 6 degrees.
const MAX_SLOPE_ANGLE: float = deg_to_rad(6.0)
# ...and the slope test alone is not enough, because it only samples the coin's own x. A hill
# crest reads as near-flat there while the whole take-off run is a slope, and the player then
# jumps from ground nothing like the flat the 174px clearance was derived on -- so the coin is
# unreachable on exactly the terrain where it looks reachable. The coin's segment, and the
# ground the player takes off from, must therefore BE flat segments.
#
# BEHIND the coin only. A max jump is 0.8s of airtime, 600px at MAX_SPEED, so take-off is
# ~300px before the coin -- and where the player LANDS has no bearing on whether they can reach
# it. Requiring flat on both sides is not merely stricter, it is unsatisfiable: flat segments
# are 640px and get_segment_selection() forbids two in a row, so no point has 320px of flat on
# both sides. Measured, it accepted 0 slots on two of three seeds.
const FLAT_TAKEOFF_SPAN: float = 320.0
# A max jump is 0.8s of airtime -- 600px at MAX_SPEED -- so the player who goes for this coin
# commits to a landing that far ahead. Ground must exist across the whole arc or the reward is
# a trap. Same shape and same margin as OBSTACLE_VOID_CLEARANCE_AHEAD.
const VOID_CLEARANCE: float = 700.0

const HASH_MASK: int = 0x7fffffff
# Its own multiplier pair, so this sequence does not correlate with the coin slots, the
# obstacle cadence, the powerup schedule or the segment selection -- all of which key off the
# same session_seed.
const HASH_INDEX_MULTIPLIER: int = 2891336453
const HASH_MIX_MULTIPLIER: int = 2654435761

var terrain_generator: TerrainGenerator
var player: Player
var next_coin_time: float = FIRST_RARE_COIN_TIME
var next_coin_index: int = 0
var active_coins: Array[Coin] = []
var has_initialized_schedule: bool = false


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as Player
	if terrain_generator == null or player == null:
		push_error("RareCoinSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)


# NOT in _ready(): this node is a child of TerrainGenerator, children ready before parents,
# and get_coin_hash() reads session_seed -- still 0 there. PowerupSpawner shipped exactly
# this bug (identical schedule every session, measured 2026-08-03).
func initialize_schedule() -> void:
	next_coin_time = FIRST_RARE_COIN_TIME + (get_coin_hash(0) * (RARE_COIN_INTERVAL_MAX - RARE_COIN_INTERVAL_MIN))


func _physics_process(_delta: float) -> void:
	# Explicit null guard rather than trusting _ready()'s set_physics_process(false): that
	# call is documented (docs/development/debugging.md) as not reliably suppressing
	# _physics_process in headless harness runs. Same guard as every sibling spawner.
	if terrain_generator == null or player == null:
		return

	# Before the disabled check, so a harness that flips the flag mid-run still finds a
	# correctly seeded schedule -- same ordering and same reason as PowerupSpawner.
	if not has_initialized_schedule:
		has_initialized_schedule = true
		initialize_schedule()

	if debug_spawning_disabled:
		return

	if player.speed_manager.elapsed_time >= next_coin_time:
		var world_x: float = player.global_position.x + SPAWN_LOOKAHEAD_WORLD_X
		if try_spawn_rare_coin(world_x):
			next_coin_index += 1
			next_coin_time += RARE_COIN_INTERVAL_MIN + (get_coin_hash(next_coin_index) * (RARE_COIN_INTERVAL_MAX - RARE_COIN_INTERVAL_MIN))
		else:
			next_coin_time += REJECTED_SLOT_RETRY_DELAY

	despawn_trailing_coins()


# Returns false when the slot was rejected, so the caller can retry instead of burning this
# minute's coin on a stretch of terrain that could not carry it.
func try_spawn_rare_coin(world_x: float) -> bool:
	if absf(terrain_generator.get_slope_angle_at_x(world_x)) > MAX_SLOPE_ANGLE:
		return false
	if not is_flat_over_span(world_x - FLAT_TAKEOFF_SPAN, world_x):
		return false
	if not terrain_generator.has_ground_over_world_x_span(world_x - VOID_CLEARANCE, world_x + VOID_CLEARANCE):
		return false

	var local_y: float = terrain_generator.get_terrain_height(world_x) - RARE_COIN_CLEARANCE
	var coin: Coin = RARE_COIN_SCENE.instantiate() as Coin
	coin.position = Vector2(world_x, local_y)
	coin.collected.connect(_on_coin_collected)
	add_child(coin)
	active_coins.append(coin)
	return true


# True only if every segment between the take-off point and the coin is a FLAT segment -- not
# merely flat-looking at one sample. Walks segment indices rather than sampling heights,
# because that is the actual question: a hill segment is disqualified even where its crest is
# momentarily level.
#
# ensure_segment_cache_for_world_x() before EVERY find_segment_index_at_x(), including the one
# for the far end: without it the binary search silently clamps to the cached range and returns
# a wrong segment (CLAUDE.md).
func is_flat_over_span(from_world_x: float, to_world_x: float) -> bool:
	terrain_generator.ensure_segment_cache_for_world_x(from_world_x)
	var first_segment_index: int = terrain_generator.find_segment_index_at_x(from_world_x)
	terrain_generator.ensure_segment_cache_for_world_x(to_world_x)
	var last_segment_index: int = terrain_generator.find_segment_index_at_x(to_world_x)

	for segment_index: int in range(first_segment_index, last_segment_index + 1):
		if terrain_generator.get_segment_selection(segment_index) != TerrainGenerator.SEGMENT_SELECTION_FLAT:
			return false
	return true


func despawn_trailing_coins() -> void:
	var despawn_world_x: float = player.global_position.x - DESPAWN_BEHIND_WORLD_X
	for index: int in range(active_coins.size() - 1, -1, -1):
		var coin: Coin = active_coins[index]
		if not is_instance_valid(coin):
			active_coins.remove_at(index)
		elif coin.position.x < despawn_world_x:
			# queue_free(), not free(): this runs inside _physics_process and a coin is a
			# live Area2D monitor. Same reasoning as TerrainGenerator.remove_chunk().
			coin.queue_free()
			active_coins.remove_at(index)


# Pure function of (session_seed, coin_index) -> [0, 1), same style as CoinSpawner.
# get_slot_hash and ObstacleSpawner.get_cluster_hash.
func get_coin_hash(coin_index: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ ((coin_index + 1) * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)


func _on_coin_collected(value: int) -> void:
	coin_collected.emit(value)
