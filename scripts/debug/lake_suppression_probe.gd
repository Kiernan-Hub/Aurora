extends SceneTree

# Asserts that NOTHING SPAWNS ON A FROZEN LAKE.
#
# WHY THIS IS NOT PART OF terrain_invariant_check. That file is geometry-only by contract --
# "no physics, no player input, no stall reproduction required" -- and it proves two things
# about the lake already: check_frozen_lake() proves the SHAPE, check_lake_arming() proves the
# ARMING. Neither can prove suppression, because suppression is not a property of the height
# field. Six spawners each ask terrain_generator.is_lake_world_x() and skip a slot when it says
# yes, and the only way to know all six actually do that is to run them and look.
#
# WHY IT MATTERS MORE THAN IT SOUNDS. Jumping is disabled across a lake (Player
# is_jump_suppressed, input.md). So a coin line, an air coin or a rare coin placed on a lake is
# unreachable by construction, and an OBSTACLE placed on one is unavoidable by construction --
# a guaranteed death in a stretch where the jump button does nothing. Every one of those fails
# silently: the terrain is still perfectly flat, every geometry gate still passes.
#
# THE GAP THIS CLOSES. The six guards were added in step 4 of the lake plan and read at the
# time, but nothing has ever checked them since, and a seventh spawner would not be reminded to
# add one. This is the check that notices.
#
# WHAT IT DOES NOT COVER. FrozenLakeDirector hard-skips headless, so no probe can reach a
# NATURALLY armed lake -- this pins one with debug_force_lake_segment_index, exactly as
# check_frozen_lake does. It therefore proves the spawners honour a lake, not that a lake ever
# arms. That half is check_lake_arming's.
#
# Usage:
#   godot --headless --path . --script res://scripts/debug/lake_suppression_probe.gd
#   godot --headless --path . --script res://scripts/debug/lake_suppression_probe.gd -- --seed=123

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

# Same index check_frozen_lake pins, for the same reasons: past CHASM_MIN_SEGMENT_INDEX, clear
# of the opening terrain, and clear of a chasm on index-1/index/index+1.
const LAKE_TEST_SEGMENT_INDEX: int = 200

# The six spawners, by node path under TerrainGenerator. Named rather than discovered so that
# ADDING A SEVENTH SPAWNER WITHOUT ADDING IT HERE is a visible omission in this list rather than
# a silent hole -- discovery would quietly "cover" a new spawner while asserting nothing new.
const SPAWNER_PATHS: Array[String] = [
	"TerrainGenerator/CoinSpawner",
	"TerrainGenerator/ObstacleSpawner",
	"TerrainGenerator/PowerupSpawner",
	"TerrainGenerator/GroundTreeSpawner",
	"TerrainGenerator/GlideCoinSpawner",
	"TerrainGenerator/RareCoinSpawner",
]

# Hard cap so a probe that stops making progress fails instead of hanging -- the failure mode
# debugging.md opens with. 7500px at MAX_SPEED is ~600 frames; this is an order of magnitude of
# headroom, not a tuned number.
const MAX_FRAMES: int = 6000

var main: Node
var terrain_generator: TerrainGenerator
var player: Player
var game_manager: GameManager


func _init() -> void:
	var session_seed: int = get_int_argument("--seed", 683407368)

	main = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	game_manager = main.get_node("GameManager") as GameManager

	terrain_generator.debug_replay_session_seed = session_seed
	terrain_generator.debug_force_lake_segment_index = LAKE_TEST_SEGMENT_INDEX
	# Chasms off: a no-input run reaches a void, runs off the lip and dies, which would end the
	# measurement early and report as a suppression pass. The lake is the subject, not chasms.
	terrain_generator.debug_chasm_disabled = true
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	game_manager.require_start_screen = false

	# EVERY SPAWNER STAYS ON. This is the one harness in the project that must not set
	# debug_spawning_disabled -- the whole measurement is what they do or do not place.

	root.add_child(main)
	await physics_frame

	var lake_start_x: float = terrain_generator.get_lake_start_x()
	var lake_end_x: float = terrain_generator.get_lake_end_x()
	if absf((lake_end_x - lake_start_x) - TerrainGenerator.LAKE_SEGMENT_LENGTH) > 1.0:
		print("LAKE_SUPPRESSION_RESULT status=FAIL reason=no_lake_at_index_%d" % LAKE_TEST_SEGMENT_INDEX)
		quit(1)
		return

	print("LAKE_SUPPRESSION_BEGIN seed=%d index=%d span=[%.1f, %.1f]" % [
		session_seed, LAKE_TEST_SEGMENT_INDEX, lake_start_x, lake_end_x,
	])

	warp_to(lake_start_x + 1.0)

	# Collected across the whole crossing rather than checked once at the end: a spawner places
	# items ahead of the player and despawns them behind, so an item that appeared on the lake
	# at frame 40 can be gone by the time the player reaches the far shore.
	var offenders: Dictionary = {}
	var frames: int = 0
	while player.global_position.x < lake_end_x and frames < MAX_FRAMES:
		# Re-asserted every frame for the reason chasm_probe documents: a death pauses the tree,
		# Player._physics_process stops, and the loop would never advance again.
		if player.is_dead:
			player.is_dead = false
			game_manager.set_state(GameManager.State.PLAYING)
		await physics_frame
		frames += 1
		scan_for_offenders(lake_start_x, lake_end_x, offenders)

	var violations: Array[String] = []
	if frames >= MAX_FRAMES:
		violations.append("LAKE_CROSSING_DID_NOT_FINISH frames=%d x=%.1f end=%.1f" % [
			frames, player.global_position.x, lake_end_x,
		])
	for spawner_name: String in offenders.keys():
		var hit: Dictionary = offenders[spawner_name]
		violations.append("SPAWNED_ON_LAKE spawner=%s count=%d first=%s at world_x=%.1f" % [
			spawner_name, int(hit["count"]), String(hit["node"]), float(hit["x"]),
		])

	print("LAKE_SUPPRESSION_RESULT frames=%d spawners=%d status=%s" % [
		frames, SPAWNER_PATHS.size(), "PASS" if violations.is_empty() else "FAIL",
	])
	for violation: String in violations:
		print("    ", violation)

	quit(0 if violations.is_empty() else 1)


# Anything a spawner has placed whose x falls strictly inside the lake span. Strictly inside
# matters: an item exactly ON a seam is legitimately the neighbouring segment's, and the lake's
# own end_x is the next segment's start_x.
#
# COUNT ITEMS, NEVER CONTAINERS -- debugging.md's measurement trap, and the first version of this
# file walked straight into it. CoinSpawner and GroundTreeSpawner each wrap a chunk's items in an
# unnamed Node2D group positioned at the chunk, so a naive recursive walk sees those groups,
# finds their x inside the lake, and reports thousands of violations. AN EMPTY GROUP INSIDE THE
# LAKE IS THE CORRECT RESULT: the chunk still exists, it just holds no coins. The group is
# evidence of suppression WORKING, not failing.
#
# Hence the explicit two-level shape below rather than a blind recursion. It matches all six:
#   CoinSpawner        -> group -> Coin        (items at depth 2)
#   GroundTreeSpawner  -> group -> tree Node2D (items at depth 2)
#   Obstacle/Powerup/GlideCoin/RareCoin spawners -> item (depth 1)
func scan_for_offenders(lake_start_x: float, lake_end_x: float, offenders: Dictionary) -> void:
	for spawner_path: String in SPAWNER_PATHS:
		var spawner: Node = main.get_node_or_null(spawner_path)
		if spawner == null:
			# A missing spawner is itself a finding -- the path list above is the contract.
			var missing_key: String = spawner_path.get_file()
			if not offenders.has(missing_key):
				offenders[missing_key] = {"count": 1, "node": "<MISSING NODE>", "x": 0.0}
			continue

		var spawner_name: String = spawner_path.get_file()
		for child: Node in spawner.get_children():
			if is_spawned_item(child):
				record_if_on_lake(child as Node2D, spawner_name, lake_start_x, lake_end_x, offenders)
				continue
			# Not an item, so it is a per-chunk group: its CHILDREN are the items.
			for grandchild: Node in child.get_children():
				var tree_or_coin: Node2D = grandchild as Node2D
				if tree_or_coin != null:
					record_if_on_lake(tree_or_coin, spawner_name, lake_start_x, lake_end_x, offenders)


func is_spawned_item(node: Node) -> bool:
	return node is Coin or node is Obstacle or node is Powerup


# Deduplicated by instance id, because this runs every frame for the whole crossing and the same
# coin would otherwise be counted 600 times. The count reported is DISTINCT OFFENDING NODES.
func record_if_on_lake(item: Node2D, spawner_name: String, lake_start_x: float, lake_end_x: float, offenders: Dictionary) -> void:
	var world_x: float = item.global_position.x
	if world_x <= lake_start_x or world_x >= lake_end_x:
		return

	if not offenders.has(spawner_name):
		offenders[spawner_name] = {"count": 0, "node": item.name, "x": world_x, "seen": {}}
	var seen: Dictionary = offenders[spawner_name]["seen"]
	var id: int = item.get_instance_id()
	if seen.has(id):
		return
	seen[id] = true
	offenders[spawner_name]["count"] = int(offenders[spawner_name]["count"]) + 1


func warp_to(world_x: float) -> void:
	game_manager.set_state(GameManager.State.PLAYING)
	player.is_dead = false
	player.velocity = Vector2.ZERO
	# Past PHASE1_DURATION so the ramp is in its slow phase and the pin below stays pinned --
	# setting elapsed_time alone does NOT set the speed, which is a trap debugging.md records.
	player.speed_manager.elapsed_time = SpeedManager.PHASE1_DURATION + 1.0
	player.speed_manager.current_speed = SpeedManager.MAX_SPEED
	player.global_position = Vector2(
		world_x,
		terrain_generator.get_surface_world_y(world_x) - player.capsule_half_height,
	)
	# Rebuild chunks around the warp target. next_chunk_index only ever INCREASES, so a warp
	# leaves the destination with no collision unless the chunks are rebuilt -- the player then
	# falls through the world and dies ~32 frames later, which would read as a lake failure.
	for chunk_index: int in terrain_generator.active_chunks.keys():
		terrain_generator.remove_chunk(chunk_index)
	terrain_generator.initialize_chunks()


func get_int_argument(argument_name: String, default_value: int) -> int:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_int()
	return default_value
