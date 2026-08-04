extends SceneTree

# Behavioural gate for chasms. terrain_invariant_check.gd proves the GEOMETRY is right
# (lips level, void cut out of the collision shape, width clearable on paper); nothing there
# runs physics, so nothing there proves a chasm actually behaves.
#
# Four trials per chasm, each starting from the same warp onto the lead-in flat:
#
#   no_jump  -- the player must FALL IN AND DIE. If this passes trivially (player survives
#               without jumping) the void is not actually cut out of the collision shape and
#               every other result here is meaningless.
#   jump     -- jumping in the takeoff window must clear it and land on the far lip, with
#               zero stall recoveries. The far lip is an exposed open chord end in a
#               ConcavePolygonShape2D segment soup, which is the highest-risk geometry in the
#               feature: a capsule landing exactly there is classic snag geometry.
#   late     -- a jump taken as late as coyote time allows must still clear. This is the
#               real takeoff window, not the paper one.
#   boost    -- a speed boost taken into a chasm must carry the player across. Jumping is
#               suppressed for the boost's full 3s (player.gd), so if the boost did NOT glide
#               the player over, a boosted chasm would be unavoidable death -- the same class
#               as the obstacle/boost issue in CLAUDE.md's Known issues. The glide is
#               emergent (it falls out of is_boosting forcing the gravity-free grounded model
#               plus get_collision_chord_slope_angle returning 0 over the void), so it is
#               exactly the kind of behaviour that a future refactor breaks silently. This is
#               the only gate that would catch it.
#
# Usage:
#   godot --headless --path . --script res://scripts/debug/chasm_probe.gd -- \
#       [--seed=683407368] [--chasms=3]

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

# How far before the near lip the player is warped in, and how far past the far lip a trial
# must reach to count as cleared.
const APPROACH_WORLD_X: float = 420.0
const CLEARED_MARGIN_WORLD_X: float = 260.0
# Enough frames to cross approach + void + margin at any speed the ramp can produce.
const TRIAL_FRAME_BUDGET: int = 400
# Sub-pixel start-phase sweep, borrowed from freeze_search.gd. Every trial otherwise starts on
# the same x and so lands on the far lip at the same sub-pixel offset every time -- and the far
# lip is an exposed open chord end in a segment soup, which is where a capsule + safe_margin
# snag would live if one existed. freeze_search cannot cover it: that probe drives no input, so
# with chasms on it just falls in and dies (it does still prove the NEAR lip never wedges).
const PHASE_STEP_WORLD_X: float = 0.25

var main: Node
var terrain_generator: TerrainGenerator
var player: Player
var game_manager: GameManager
# --speed=750 re-runs every trial at cap speed. Default 0 = the slowest speed the player could
# actually have reached each chasm at, which is the case that has to work.
var speed_override: float = 0.0
var phase_count: int = 4


func _init() -> void:
	var session_seed: int = get_int_argument("--seed", 683407368)
	var chasm_budget: int = maxi(get_int_argument("--chasms", 3), 1)
	speed_override = float(get_int_argument("--speed", 0))
	phase_count = maxi(get_int_argument("--phases", 4), 1)

	main = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	game_manager = main.get_node("GameManager") as GameManager
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	game_manager.require_start_screen = false
	# Chasms are the subject here, so unlike every other harness this one leaves them ON.
	# The two spawners stay off for the usual reason: an obstacle death mid-trial would pause
	# the tree and misreport as a chasm failure.
	(main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner).debug_spawning_disabled = true
	(main.get_node("TerrainGenerator/PowerupSpawner") as PowerupSpawner).debug_spawning_disabled = true
	root.add_child(main)
	await physics_frame

	var void_spans: Array[Dictionary] = find_void_spans(chasm_budget)
	print("CHASM_PROBE_BEGIN seed=%d chasms=%d" % [session_seed, void_spans.size()])
	if void_spans.is_empty():
		print("CHASM_PROBE_RESULT status=FAIL reason=no_chasms_found")
		quit(1)
		return

	var failures: int = 0
	var trials: int = 0
	for void_span: Dictionary in void_spans:
		for trial_mode: String in ["no_jump", "jump", "late", "boost"]:
			for phase_index: int in range(phase_count):
				trials += 1
				var passed: bool = await run_trial(void_span, trial_mode, float(phase_index) * PHASE_STEP_WORLD_X)
				if not passed:
					failures += 1

	print("CHASM_PROBE_RESULT trials=%d failures=%d status=%s" % [
		trials, failures, "PASS" if failures == 0 else "FAIL",
	])
	quit(0 if failures == 0 else 1)


func find_void_spans(chasm_budget: int) -> Array[Dictionary]:
	var void_spans: Array[Dictionary] = []
	var segment_index: int = 0
	while void_spans.size() < chasm_budget and segment_index < 4000:
		terrain_generator.ensure_segment_cache_through(segment_index)
		var void_span: Dictionary = terrain_generator.get_void_span_for_segment(segment_index)
		if not void_span.is_empty():
			void_spans.append(void_span)
		segment_index += 1
	return void_spans


# One trial. Returns whether the observed outcome matched the expected one.
func run_trial(void_span: Dictionary, trial_mode: String, phase_offset_world_x: float) -> bool:
	var near_lip_x: float = float(void_span["start_x"])
	var far_lip_x: float = float(void_span["end_x"])
	reset_player(near_lip_x - APPROACH_WORLD_X + phase_offset_world_x)

	if trial_mode == "boost":
		(main.get_node("PowerupManager") as PowerupManager).start_speed_boost()

	# A jump is armed to fire the frame the player is within one jump reach of the lip. "late"
	# holds it until the player is actually past the lip, exercising coyote time -- the thing
	# that turns the paper takeoff window into the real one.
	var jump_trigger_x: float = near_lip_x - ((far_lip_x - near_lip_x) * 0.5)
	if trial_mode == "late":
		jump_trigger_x = near_lip_x + 1.0

	var has_jumped: bool = false
	var reached_x: float = player.global_position.x
	var landed_past_far_lip: bool = false
	for _frame_index: int in range(TRIAL_FRAME_BUDGET):
		if (trial_mode == "jump" or trial_mode == "late") and not has_jumped and player.global_position.x >= jump_trigger_x:
			player.buffer_jump()
			has_jumped = true
		await physics_frame
		if player.is_dead:
			break
		reached_x = maxf(reached_x, player.global_position.x)
		# "Cleared" means LANDED past the far lip, not merely travelled past it horizontally.
		# Distance alone is not enough: at 750 px/s the player crosses a 220px void in 0.29s
		# having fallen only ~69px, so a body that is still descending toward its death sails
		# past a pure-distance threshold and reports as a clean crossing. Requiring floor
		# contact is what makes this measure the thing that matters.
		#
		# is_on_floor() is also true during a boost glide only once the far lip is actually
		# underfoot, so this stays honest for that mode too.
		if reached_x >= far_lip_x + CLEARED_MARGIN_WORLD_X and player.is_on_floor():
			landed_past_far_lip = true
			break

	var survived: bool = not player.is_dead and landed_past_far_lip
	var expects_survival: bool = trial_mode != "no_jump"
	var recoveries: int = player.debug_stall_recovery_count
	# A stall recovery is a stop-ship regardless of the outcome: it means the body wedged and
	# a watchdog papered over it, which is exactly the large_valley failure the lips are
	# supposed to make impossible.
	var passed: bool = survived == expects_survival and recoveries == 0

	print("  CHASM_TRIAL void=[%.1f, %.1f] mode=%-7s speed=%.0f survived=%s expected=%s reached=%.1f recoveries=%d %s" % [
		near_lip_x, far_lip_x, trial_mode, player.speed_manager.current_speed,
		survived, expects_survival, reached_x, recoveries,
		"ok" if passed else "*** FAIL ***",
	])
	return passed


# The slowest speed the player can possibly have on reaching world_x, by inverting the
# SpeedManager ramp. Same derivation as terrain_invariant_check.get_min_speed_at_world_x, and
# conservative for the same reason: it assumes x-progress equals speed, but the grounded model
# advances x at speed * cos(slope), so the real player arrives later and faster.
#
# Pinning this is NOT optional. Trials run from a warp, so elapsed_time bears no relation to
# world_x: without the pin the first trial runs at the start-of-run ~100 px/s and reports a
# jump that cannot clear a gap sized for 545 px/s. That is a probe artefact reported as a
# feature failure -- exactly the "measure the quantity that matters" trap in
# docs/research/camera_shake.md. Pinning current_speed directly is the established pattern here
# (see the comment on SpeedManager.update).
func get_min_speed_at_world_x(world_x: float) -> float:
	var phase1_distance: float = (SpeedManager.INITIAL_SPEED * SpeedManager.PHASE1_DURATION) + (0.5 * SpeedManager.PHASE1_ACCELERATION * pow(SpeedManager.PHASE1_DURATION, 2.0))
	if world_x <= phase1_distance:
		var phase1_time: float = (-SpeedManager.INITIAL_SPEED + sqrt(pow(SpeedManager.INITIAL_SPEED, 2.0) + (2.0 * SpeedManager.PHASE1_ACCELERATION * world_x))) / SpeedManager.PHASE1_ACCELERATION
		return SpeedManager.INITIAL_SPEED + (SpeedManager.PHASE1_ACCELERATION * phase1_time)

	var phase2_distance: float = world_x - phase1_distance
	var phase2_time: float = (-SpeedManager.PHASE1_TARGET_SPEED + sqrt(pow(SpeedManager.PHASE1_TARGET_SPEED, 2.0) + (2.0 * SpeedManager.PHASE2_ACCELERATION * phase2_distance))) / SpeedManager.PHASE2_ACCELERATION
	return minf(SpeedManager.PHASE1_TARGET_SPEED + (SpeedManager.PHASE2_ACCELERATION * phase2_time), SpeedManager.MAX_SPEED)


func reset_player(world_x: float) -> void:
	# The tree is paused whenever a trial ended in death; unpause before re-seating, since a
	# paused tree stops Player._physics_process and the next trial would never advance.
	game_manager.set_state(GameManager.State.PLAYING)
	player.is_dead = false
	player.debug_stall_recovery_count = 0
	player.end_boost()
	player.velocity = Vector2.ZERO
	# Past PHASE1_DURATION so the ramp uses the slow phase-2 acceleration (2.27 px/s^2, ~15
	# px/s over a whole trial) and the pin below stays effectively pinned.
	player.speed_manager.elapsed_time = SpeedManager.PHASE1_DURATION + 1.0
	player.speed_manager.current_speed = speed_override if speed_override > 0.0 else get_min_speed_at_world_x(world_x)
	player.global_position = Vector2(
		world_x,
		terrain_generator.get_surface_world_y(world_x) - player.capsule_half_height,
	)


func get_int_argument(argument_name: String, default_value: int) -> int:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_int()
	return default_value
