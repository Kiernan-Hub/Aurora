extends SceneTree

# Behavioural gate for the air moves (2026-09-27): the rules chasm_probe cannot see. chasm_probe
# proves the moves are SAFE around voids; this proves they do what the design says everywhere
# else, on the real Player in the real scene. Every case asserts; exit 1 on any failure.
#
#   slam_fires        a slam-side tap mid-arc dives: airtime drops well below a plain jump's.
#   slam_unowned      the same tap without the unlock changes nothing.
#   landing_window    a tap 4 frames before touchdown, on EITHER side with both moves owned, is the
#                     ordinary landing jump: no slam, no double jump, and a second jump fires.
#   slam_over_void    slam-side taps on every frame over a void: no slam starts over it (the dive
#                     would come down in it), one does once past it, and the player lives.
#   double_fires      a jump-side tap mid-arc is a second jump: airtime grows, and the airtime is
#                     still marked as double-jumped on the landing frame (guardrail B reads that).
#   double_once       a second jump-side tap in the same airtime is ignored.
#   wrong_side        a tap on the side of a move you do not own does nothing (both directions).
#   trick_after_double  hold through a jump + double jump and land a flip: coins, NO boost
#                     (guardrail B). The handler alone still boosts a plain trick (control).
#   glide_floating    a glide pickup's forced launch into a floe survives (Obstacle.is_floating);
#                     the same launch without a glide dies; a spike still kills a glider.
#   shop_rows         the shop builds one label + button per UpgradeStore.TRACKS row.
#   held_controls     either desktop action held from take-off spins and supplies glide thrust.
#   landing_edge      at 750 px/s on real hills, every tap in the frames before touchdown has the
#                     same outcome with either move owned as with neither: owning a move never
#                     turns a landing jump into an air move (audit.md A14, which was this exact spot).
#   landing_model     the landing prediction against real touchdowns, 100 spots x 3 jump strengths:
#                     always within one frame. will_buffered_jump_fire() relies on the EARLY side
#                     (touchdown never 2+ frames before the prediction): the rounded capsule meets
#                     a slope before its centre does. Late touchdowns (collision follows straight
#                     chords, which sit below the height field on a crest) cannot cause a steal.
#
# Every case but the last two runs on the first chasm's lead-in, which is flat, at a pinned
# 400 px/s so a double jump's ~1.35s arc still lands on it. Probes get no upgrades (GameManager.apply_upgrades() skips
# headless), so each case sets has_slam / has_double_jump itself.
#
# Usage (uncapped, same results as real time -- debugging.md):
#   godot --headless --fixed-fps 60 --path . --script res://scripts/debug/air_move_probe.gd

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 683407368
const PINNED_SPEED: float = 400.0
# Start of each case, back from the first chasm's near lip; the lead-in is 900px long.
const START_BEFORE_LIP: float = 880.0
const MID_ARC_TAP_FRAME: int = 20
# The landing cases' hilly stretch: the audit's reproduction spot, then every 317px from it.
const HILLS_START_X: float = 20000.0
const HILLS_STEP_X: float = 317.0
const HILLS_SPOTS: int = 100
const JUMP_STRENGTHS: Array[float] = [0.6, 1.0, 1.41421356]

var main: Node
var player: Player
var terrain_generator: TerrainGenerator
var game_manager: GameManager
var obstacle_spawner: ObstacleSpawner
var near_lip_x: float = 0.0
var far_lip_x: float = 0.0
var jump_count: int = 0
var failures: int = 0
var cases: int = 0


func _init() -> void:
	main = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	game_manager = main.get_node("GameManager") as GameManager
	obstacle_spawner = main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner
	terrain_generator.debug_replay_session_seed = SEED
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	game_manager.require_start_screen = false
	obstacle_spawner.debug_spawning_disabled = true
	(main.get_node("TerrainGenerator/PowerupSpawner") as PowerupSpawner).debug_spawning_disabled = true
	root.add_child(main)
	player.jumped.connect(func() -> void: jump_count += 1)
	await physics_frame

	var void_span: Dictionary = find_first_hazard_void()
	near_lip_x = float(void_span["start_x"])
	far_lip_x = float(void_span["end_x"])
	var start_x: float = near_lip_x - START_BEFORE_LIP

	var plain: int = await airtime(start_x, false, false, -1, false)

	var slam: int = await airtime(start_x, true, false, MID_ARC_TAP_FRAME, true)
	expect("slam_fires", slam < plain - 10, "airtime %d vs plain %d" % [slam, plain])
	var slam_unowned: int = await airtime(start_x, false, false, MID_ARC_TAP_FRAME, true)
	expect("slam_unowned", slam_unowned == plain, "airtime %d vs plain %d" % [slam_unowned, plain])

	for is_slam_side: bool in [true, false]:
		var window: Dictionary = await tap_run(start_x, PINNED_SPEED, plain - 4, true, true, is_slam_side)
		expect("landing_window", not window["moved"] and window["jumps"] == 2,
			"%s side: air move=%s jumps=%d" % ["slam" if is_slam_side else "jump", window["moved"], window["jumps"]])

	var over_void: Dictionary = await slam_over_void()
	expect("slam_over_void", over_void["over"] == 0 and over_void["after"] >= 1 and not player.is_dead,
		"slams over void=%d after=%d dead=%s" % [over_void["over"], over_void["after"], player.is_dead])

	var double: int = await airtime(start_x, false, true, MID_ARC_TAP_FRAME, false)
	var marked: bool = player.has_double_jumped
	expect("double_fires", double > plain + 10 and marked, "airtime %d vs plain %d, marked at landing=%s" % [double, plain, marked])
	var double_twice: int = await airtime(start_x, false, true, MID_ARC_TAP_FRAME, false, MID_ARC_TAP_FRAME + 15)
	expect("double_once", double_twice == double, "two taps %d vs one %d" % [double_twice, double])

	var slam_side_double_owner: int = await airtime(start_x, false, true, MID_ARC_TAP_FRAME, true)
	var jump_side_slam_owner: int = await airtime(start_x, true, false, MID_ARC_TAP_FRAME, false)
	expect("wrong_side", slam_side_double_owner == plain and jump_side_slam_owner == plain,
		"slam-side tap, double owner %d; jump-side tap, slam owner %d; plain %d" % [slam_side_double_owner, jump_side_slam_owner, plain])

	await trick_after_double(start_x)
	await glide_floating(start_x)
	shop_rows()
	await held_controls(start_x)
	await landing_edge()
	await landing_model()

	print("AIR_MOVE_PROBE_RESULT cases=%d failures=%d status=%s" % [cases, failures, "PASS" if failures == 0 else "FAIL"])
	quit(0 if failures == 0 else 1)


func expect(case_name: String, passed: bool, detail: String) -> void:
	cases += 1
	if not passed:
		failures += 1
	print("  AIR_MOVE_CASE %-18s %s  %s" % [case_name, "PASS" if passed else "*** FAIL ***", detail])


func find_first_hazard_void() -> Dictionary:
	for segment_index: int in range(4000):
		terrain_generator.ensure_segment_cache_through(segment_index)
		var span: Dictionary = terrain_generator.get_void_span_for_segment(segment_index)
		if not span.is_empty() and bool(terrain_generator.get_segment_spec(segment_index).get("must_be_jumped", true)):
			return span
	return {}


# Same re-seat as chasm_probe.reset_player(), including the chunk rebuild a backward warp needs,
# and clearing every piece of per-airtime and input state a previous case could leave behind.
func warp(world_x: float, owns_slam: bool, owns_double_jump: bool, speed: float = PINNED_SPEED) -> void:
	game_manager.set_state(GameManager.State.PLAYING)
	player.is_dead = false
	player.end_boost()
	player.end_glide()
	player.velocity = Vector2.ZERO
	player.jump_buffer_timer = 0.0
	player.coyote_timer = 0.0
	player.is_slamming = false
	player.has_double_jumped = false
	# A glide case leaves its landing shield pending; it would absorb the next case's hit.
	player.has_shield = false
	player.is_glide_landing_shield_pending = false
	player.is_shield_from_glide_landing = false
	player.glide_landing_shield_timer = 0.0
	player.has_slam = owns_slam
	player.has_double_jump = owns_double_jump
	player.speed_manager.elapsed_time = SpeedManager.PHASE1_DURATION + 1.0
	player.speed_manager.current_speed = speed
	player.global_position = Vector2(world_x, terrain_generator.get_surface_world_y(world_x) - player.capsule_half_height)
	for chunk_index: int in terrain_generator.active_chunks.keys():
		terrain_generator.remove_chunk(chunk_index)
	terrain_generator.initialize_chunks()
	for obstacle: Node2D in obstacle_spawner.active_obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	obstacle_spawner.active_obstacles.clear()


func settle(speed: float = PINNED_SPEED) -> void:
	for frame: int in range(10):
		await physics_frame
	player.speed_manager.current_speed = speed


# Frames from take-off to touchdown, with optional taps (frame numbers after take-off).
func airtime(start_x: float, owns_slam: bool, owns_double_jump: bool, tap_frame: int, is_slam_side: bool, second_tap_frame: int = -1) -> int:
	warp(start_x, owns_slam, owns_double_jump)
	await settle()
	player.buffer_jump()
	await physics_frame
	var frames: int = 1
	while not player.is_on_floor() and frames < 300:
		if frames == tap_frame or frames == second_tap_frame:
			player.buffer_jump(is_slam_side)
		await physics_frame
		frames += 1
	return frames


# A jump, then a second tap tap_frame frames after take-off. "moved" is whether the FIRST airtime
# used an air move; "jumps" counts every jumped emit, so a landing jump makes it 2. Not keyed on
# jump_count alone: a double jump emits jumped too.
func tap_run(world_x: float, speed: float, tap_frame: int, owns_slam: bool, owns_double_jump: bool, is_slam_side: bool) -> Dictionary:
	warp(world_x, owns_slam, owns_double_jump, speed)
	await settle(speed)
	jump_count = 0
	player.buffer_jump()
	await physics_frame
	var moved: bool = false
	var airtime: int = -1
	for frames: int in range(1, 200):
		if frames == tap_frame:
			player.buffer_jump(is_slam_side)
		await physics_frame
		if airtime < 0:
			moved = moved or player.is_slamming or player.has_double_jumped
			if player.is_on_floor():
				airtime = frames
		elif frames > airtime + 3:
			break
	return {"moved": moved, "jumps": jump_count, "airtime": airtime}


# Every tap from 12 frames before touchdown to touchdown, at the audit's spot and speed: whatever
# the tap does with neither move owned (a landing jump, or nothing once the buffer runs out), it
# must do the same with either one owned. 12 frames back reaches past the 7.2-frame buffer, so
# the sweep also has to see the owned moves fire there, or it never crossed the boundary.
func landing_edge() -> void:
	var speed: float = SpeedManager.MAX_SPEED
	var plain: Dictionary = await tap_run(HILLS_START_X, speed, -1, false, false, false)
	var landing: int = int(plain["airtime"])
	var stolen: Array[String] = []
	var landing_jumps: int = 0
	var early_moves: int = 0
	for tap_frame: int in range(landing - 12, landing + 1):
		var unowned: Dictionary = await tap_run(HILLS_START_X, speed, tap_frame, false, false, false)
		var is_landing_jump: bool = unowned["jumps"] == 2
		if is_landing_jump:
			landing_jumps += 1
		for owns_slam: bool in [true, false]:
			var owned: Dictionary = await tap_run(HILLS_START_X, speed, tap_frame, owns_slam, not owns_slam, owns_slam)
			if is_landing_jump and (owned["moved"] or owned["jumps"] != 2):
				stolen.append("%s@%d" % ["slam" if owns_slam else "double", tap_frame])
			if tap_frame == landing - 12 and owned["moved"]:
				early_moves += 1
	expect("landing_edge", stolen.is_empty() and landing_jumps > 0 and early_moves == 2,
		"touchdown at %d; landing jumps unowned %d/13; stolen %s; moves 12 frames out %d/2" % [
			landing, landing_jumps, stolen, early_moves])


func landing_model() -> void:
	var speed: float = SpeedManager.MAX_SPEED
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	var samples: int = 0
	var one_early: int = 0
	var one_late: int = 0
	var wrong: Array[String] = []
	for spot: int in range(HILLS_SPOTS):
		var world_x: float = HILLS_START_X + HILLS_STEP_X * float(spot)
		if not has_ground_through(world_x, world_x + speed * 2.0):
			continue
		for strength: float in JUMP_STRENGTHS:
			warp(world_x, false, false, speed)
			player.upgrade_jump_multiplier = strength
			await settle(speed)
			player.buffer_jump()
			await physics_frame
			var predictions: Array[int] = []
			while not player.is_on_floor() and predictions.size() < 200:
				predictions.append(player.get_landing_frame(player.velocity.y, INF, 200, false, delta))
				await physics_frame
			var touchdown: int = predictions.size()
			for sample: int in range(touchdown):
				var actual: int = touchdown - sample
				samples += 1
				if actual == predictions[sample] - 1:
					one_early += 1
				elif actual == predictions[sample] + 1:
					one_late += 1
				elif actual != predictions[sample]:
					wrong.append("x=%.0f j=%.2f predicted %d actual %d" % [world_x, strength, predictions[sample], actual])
	player.upgrade_jump_multiplier = 1.0
	expect("landing_model", wrong.is_empty() and samples > 3000,
		"%d samples: touchdown 1 frame early %d, 1 late %d, further off %d %s" % [
			samples, one_early, one_late, wrong.size(), wrong.slice(0, 3)])


func has_ground_through(from_x: float, to_x: float) -> bool:
	var x: float = from_x
	while x <= to_x:
		if not terrain_generator.has_ground_at_world_x(x):
			return false
		x += 16.0
	return true


func slam_over_void() -> Dictionary:
	warp(near_lip_x - 700.0, true, false)
	player.speed_manager.current_speed = 600.0
	var has_jumped: bool = false
	var over: int = 0
	var after: int = 0
	var was_slamming: bool = false
	for frame: int in range(300):
		var x: float = player.global_position.x
		if not has_jumped and x >= near_lip_x - 150.0:
			player.buffer_jump()
			has_jumped = true
		elif x >= near_lip_x:
			player.buffer_jump(true)
		await physics_frame
		if player.is_dead:
			break
		if player.is_slamming and not was_slamming:
			if player.global_position.x < far_lip_x:
				over += 1
			else:
				after += 1
		was_slamming = player.is_slamming
		if player.is_on_floor() and player.global_position.x > far_lip_x + 200.0:
			break
	return {"over": over, "after": after}


func trick_after_double(start_x: float) -> void:
	var tricks: Array[int] = []
	var record_trick: Callable = func(spins: int) -> void: tricks.append(spins)
	player.trick_completed.connect(record_trick)
	warp(start_x, false, true)
	await settle()
	var coins_before: int = game_manager.coin_count
	# Pressed on the ground: that press is the jump, and holding it on is the spin.
	Input.action_press(&"ui_accept")
	await physics_frame
	for frames: int in range(1, 300):
		if frames == MID_ARC_TAP_FRAME:
			player.buffer_jump(false)
		await physics_frame
		if player.is_on_floor() and frames > 5:
			break
	Input.action_release(&"ui_accept")
	await physics_frame
	player.trick_completed.disconnect(record_trick)
	expect("trick_after_double", tricks.size() == 1 and game_manager.coin_count > coins_before and not player.is_boosting,
		"tricks=%s coins=+%d boosting=%s" % [tricks, game_manager.coin_count - coins_before, player.is_boosting])

	# Control: the handler itself still boosts a trick with no double jump in its airtime.
	warp(start_x, false, false)
	await settle()
	game_manager._on_player_trick_completed(1)
	var control_boosted: bool = player.is_boosting
	(main.get_node("PowerupManager") as PowerupManager).end_effect(PowerupManager.EFFECT_SPEED_BOOST)
	await physics_frame
	# Set with no frame in between: a grounded frame clears it, which is exactly its contract.
	player.has_double_jumped = true
	game_manager._on_player_trick_completed(1)
	expect("trick_boost_control", control_boosted and not player.is_boosting,
		"plain trick boosted=%s, after double jump boosted=%s" % [control_boosted, player.is_boosting])
	if player.is_boosting:
		(main.get_node("PowerupManager") as PowerupManager).end_effect(PowerupManager.EFFECT_SPEED_BOOST)


# A floe a quarter-second ahead of a launch that rises into its column.
func glide_floating(start_x: float) -> void:
	var outcomes: Dictionary = {}
	for case_name: String in ["glide", "plain_launch", "spike_while_gliding"]:
		warp(start_x, false, false)
		await settle()
		while not player.is_on_floor():
			await physics_frame
		if case_name == "spike_while_gliding":
			obstacle_spawner.spawn_obstacle(player.global_position.x + PINNED_SPEED * 0.2, ObstacleSpawner.PIECE_SPIKE)
			await physics_frame
			player.is_glide_active = true
		else:
			obstacle_spawner.spawn_obstacle(player.global_position.x + PINNED_SPEED * 0.25, ObstacleSpawner.PIECE_FLOE)
			await physics_frame
			if case_name == "glide":
				player.start_glide()
			else:
				player.velocity.y = Player.GLIDE_LAUNCH_VELOCITY
				player.is_jump_ascending = true
		var touched: bool = false
		for frame: int in range(90):
			await physics_frame
			var piece: Obstacle = obstacle_spawner.active_obstacles[-1] as Obstacle
			touched = touched or piece.has_triggered
			if player.is_dead:
				break
		outcomes[case_name] = {"dead": player.is_dead, "touched": touched}
		player.end_glide()
	expect("glide_floating",
		not outcomes["glide"]["dead"] and outcomes["glide"]["touched"]
			and outcomes["plain_launch"]["dead"] and outcomes["spike_while_gliding"]["dead"],
		"glide into floe: touched=%s dead=%s; plain launch dead=%s; spike while gliding dead=%s" % [
			outcomes["glide"]["touched"], outcomes["glide"]["dead"],
			outcomes["plain_launch"]["dead"], outcomes["spike_while_gliding"]["dead"]])


func held_controls(start_x: float) -> void:
	for action: StringName in [&"ui_accept", Player.SLAM_ACTION]:
		warp(start_x, true, true)
		await settle()
		jump_count = 0
		Input.action_press(action)
		for frame: int in range(20):
			await physics_frame
		var spun: bool = player.trick_rotation_progress > 0.0
		var only_ground_jump: bool = jump_count == 1 and not player.is_slamming and not player.has_double_jumped
		player.start_glide()
		var launch_velocity: float = player.velocity.y
		await physics_frame
		var thrust: bool = player.velocity.y < launch_velocity
		Input.action_release(action)
		player.end_glide()
		expect("held_controls", spun and only_ground_jump and thrust,
			"%s: spin=%s ground jump only=%s glide thrust=%s" % [action, spun, only_ground_jump, thrust])


func shop_rows() -> void:
	game_manager.refresh_shop()
	var labels: Array[String] = []
	for track: Dictionary in UpgradeStore.TRACKS:
		var row: Dictionary = game_manager.shop_rows.get(String(track["id"]), {})
		if not row.is_empty():
			labels.append((row["label"] as Label).text)
	expect("shop_rows", labels.size() == UpgradeStore.TRACKS.size() and labels.all(func(text: String) -> bool: return not text.is_empty()),
		"rows=%d/%d %s" % [labels.size(), UpgradeStore.TRACKS.size(), labels])
