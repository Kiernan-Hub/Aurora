extends SceneTree

# Geometry-only terrain validator. Samples the height field directly and asserts the
# invariants the generator is supposed to guarantee -- no physics, no player input, no
# stall reproduction required.
#
# Why this exists: every terrain bug found so far was detectable as a pure geometry
# fact, but the only tool that could detect one was a physics-stall reproduction
# (freeze_search.gd), which needs the right seed AND the right sub-pixel start phase
# AND the right input schedule. The large_valley drop face was 80.4 degrees -- a
# property of the height field alone, checkable in under a second -- and it took a week
# to find. This script turns that class of bug into a few seconds of sampling.
#
# It also converts the load-bearing comments in terrain_generator.gd (the ones warning
# "combine with maxf(), never minf()") into something that can actually fail.
#
# Usage:
#   godot --headless --path . --script res://scripts/debug/terrain_invariant_check.gd \
#       -- --seeds=8 --to=200000
#   godot --headless --path . --script res://scripts/debug/terrain_invariant_check.gd \
#       -- --seed=941462462 --to=300000
#
# Exit code is 0 only if every seed passes, so this is usable as a gate.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

const DEFAULT_SEED_COUNT: int = 8
const DEFAULT_START_WORLD_X: float = 0.0
const DEFAULT_END_WORLD_X: float = 200000.0
# 1px is the finest resolution that matters: the collision polyline is built at 16px
# and the player capsule is 32px wide, so anything narrower than a pixel cannot be
# what the physics engine trips over.
const DEFAULT_SAMPLE_STEP: float = 1.0
# A single 1px step that moves Y by more than this is a step/cliff, not a slope. Kept
# well above the steepest legal 1px rise (tan(45 deg) * 1px = 1.0px) so a legitimately
# steep face is reported as an angle violation rather than a discontinuity.
const DISCONTINUITY_STEP_Y: float = 4.0
# Where check_frozen_lake() pins its lake. Any index past CHASM_MIN_SEGMENT_INDEX works; 200
# is deep enough to be well clear of the opening terrain and, on the seed below, lands clear
# of a chasm on all three of index-1/index/index+1 (the check asserts that rather than
# assuming it, and tells you to move this if it ever stops being true).
const LAKE_TEST_SEGMENT_INDEX: int = 200
# The lake is built from a literal constant and a magnitude of exactly 0.0, so its flatness
# and its seams are exact in binary rather than approximately equal -- there is no
# accumulating arithmetic to absorb. Anything above float noise is a real defect.
const LAKE_EPSILON: float = 1e-6
# Slope is compared against floor_max_angle, which is what CharacterBody2D uses to
# decide "floor" vs "wall". Anything at or past it is terrain the player can wedge
# against. A hair of tolerance absorbs float noise in the finite difference.
const SLOPE_ANGLE_TOLERANCE_RADIANS: float = 0.0035
# Seeds are drawn from a fixed generator so a failing run is reproducible verbatim.
const SEED_SWEEP_BASE: int = 1
const MAX_REPORTED_VIOLATIONS_PER_SEED: int = 5
const PROGRESS_SAMPLE_INTERVAL: int = 250000

# --- Chasm assertions ----------------------------------------------------------------
# The height-field pass above cannot see a void at all, and that is by design: a chasm is a
# FLAT segment whose get_terrain_height() returns the LIP height across the void, so the field
# stays continuous and both existing assertions pass with no false positives and no exemption.
# That is the payoff of the lip-height representation -- but it also means a gate that only
# samples the height field would silently pass a completely broken chasm. Hence a second pass.
#
# This pass walks SEGMENTS (a few hundred over a 300,000px range), not the 1px sample loop, so
# it costs effectively nothing.

# How flat the ground on either side of a void must be, and over what distance. Catches a
# lead-in shortened past a neighbouring shape, or a future non-flat chasm variant.
const CHASM_LIP_FLATNESS_MARGIN: float = 96.0
const CHASM_LIP_FLATNESS_TOLERANCE_Y: float = 0.001
# Matching tolerance for "a collision vertex exists exactly on this lip". Must exceed
# TerrainGenerator.add_unique_sample_world_x's 0.001 dedupe window: a lip within 0.001 of an
# existing sample is legitimately collapsed onto it, which is geometrically identical.
const CHASM_LIP_VERTEX_TOLERANCE_X: float = 0.002
# A void must be at most this fraction of the jump reach available where it sits. 0.55 leaves
# the takeoff window at roughly half the airtime rather than a frame-perfect input.
#
# THIS IS THE ASSERTION THAT MAKES VARYING THE CHASM SAFE. Width and exit drop are meant to
# vary; when they do, this is what fails the build before an unclearable chasm ships, using
# the real SpeedManager ramp and the real jump arithmetic rather than a remembered estimate.
const CHASM_MAX_REACH_FRACTION: float = 0.55
# Over a range at least this wide, finding zero chasms is a FAILURE, not a silent pass: a
# rarity regression that stops generating them entirely would make every assertion above
# trivially true.
const CHASM_MIN_RANGE_FOR_PRESENCE: float = 100000.0
# Slack required on top of the lead-in's minimum, so the invariant is not resting on an exact
# tie between two independently-edited constants.
const CHASM_LEAD_IN_MARGIN: float = 32.0
# A void must be WIDER than the distance a player crosses in the time it takes to fall
# exit_drop, or it can be cleared by running straight off the near lip and landing on a lower
# far lip -- a "chasm" that is not a hazard at all. Vacuous at exit_drop 0 (an unjumped player
# falls forever), so this asserts nothing today; it exists so that Phase 2's width table cannot
# be extended with a drop in Phase 3 without this failing first.
const CHASM_MIN_HAZARD_MARGIN: float = 24.0
# The mirror of CHASM_MIN_HAZARD_MARGIN, for variants that are meant to be crossed by running
# off the edge: how much further than the void a no-input run-off must carry the player, so
# clearing it is comfortable rather than a photo finish at the slowest legal arrival speed.
const CHASM_DROP_CROSSING_MARGIN: float = 96.0

# Player capsule half-height, from player.tscn's CapsuleShape2D -- the same 24 the manual
# spawn-position invariant in CLAUDE.md is derived from.
const PLAYER_CAPSULE_HALF_HEIGHT: float = 24.0
# How much clear air the rare coin must keep on BOTH sides of its reachability window. The
# window itself is only ~24px wide (the gap between the top two jump levels' ceilings), so
# this is deliberately small; it exists to stop the clearance being tuned to the exact edge,
# where a rounding difference decides whether the game's rarest pickup exists.
const RARE_COIN_REACH_MARGIN: float = 6.0
# The standing grab ceiling: capsule reach plus the coin's radius, no jump at all. A coin hung
# in an air line must clear this by a real margin or the line costs no input, which is the
# entire reason it exists. 8px is roughly a frame of vertical travel at the top of a jump.
const COIN_LINE_FREE_GRAB_MARGIN: float = 8.0
# Clear air the line must keep on both sides of its max-jump-only window. Small for the same
# reason RARE_COIN_REACH_MARGIN is: the window is only ~24px wide, so this exists to stop the
# clearance being tuned to the exact edge.
const COIN_LINE_REACH_MARGIN: float = 6.0
# Slowest speed a line's end coins have to be catchable at. A jump apexing on the middle coin
# has fallen 0.5 * GRAVITY * (spacing/speed)^2 by the time it reaches an end, and the slower the
# run, the further it has fallen -- so the slowest speed in the ramp is the binding case.
const COIN_LINE_SLOWEST_SPEED: float = SpeedManager.PHASE1_TARGET_SPEED
# Coins per candidate slot. It was 0.40 while air lines rolled at 0.3; the project owner cut
# them to 0.1 wanting coins less frequent overall, and this target followed the measurement
# down rather than the include chance being raised to defend the old number -- fewer coins was
# the ask. JUMP_UPGRADE_COSTS is still costed against 0.40, so upgrades take roughly 16% longer
# in raw coins, which the combo multiplier (up to 3x) more than covers on a clean run.
#
# The tolerance is wide because the measurement is genuinely seed-dependent: how much of the
# sampled range is flat enough for a line varies. Observed 0.3163 to 0.3521 across 8 seeds.
const COIN_DENSITY_TARGET: float = 0.34
const COIN_DENSITY_TOLERANCE: float = 0.05


func _init() -> void:
	var explicit_seed: int = get_int_argument("--seed", -1)
	var seed_count: int = maxi(get_int_argument("--seeds", DEFAULT_SEED_COUNT), 1)
	var start_world_x: float = get_float_argument("--from", DEFAULT_START_WORLD_X)
	var end_world_x: float = get_float_argument("--to", DEFAULT_END_WORLD_X)
	var sample_step: float = maxf(get_float_argument("--step", DEFAULT_SAMPLE_STEP), 0.01)

	var session_seeds: Array[int] = []
	if explicit_seed >= 0:
		session_seeds.append(explicit_seed)
	else:
		session_seeds = build_seed_sweep(seed_count)

	print("TERRAIN_INVARIANT_CHECK seeds=", session_seeds.size(), " range=[%.0f, %.0f]" % [start_world_x, end_world_x], " step=%.2f" % sample_step)

	# Seed-independent, so it runs once rather than per seed: the variant table and the lead-in
	# are constants, and whether they are self-consistent has nothing to do with which seed or
	# world_x range was asked for. It runs FIRST because a table failure makes every per-seed
	# chasm result downstream uninteresting.
	var variant_violations: Array[String] = check_chasm_variant_table()
	print("TERRAIN_INVARIANT_CHASM_TABLE variants=", TerrainGenerator.CHASM_VARIANTS.size(),
		" status=", "PASS" if variant_violations.is_empty() else "FAIL")
	for violation: String in variant_violations:
		print("    ", violation)

	# Seed-independent for the same reason, and cheap. Grouped with the table check rather
	# than given its own gate because it is the same kind of claim: a constant in one file
	# implying something about a constant in another.
	var rare_coin_violations: Array[String] = check_rare_coin_height()
	print("TERRAIN_INVARIANT_RARE_COIN clearance=%.1f" % RareCoinSpawner.RARE_COIN_CLEARANCE,
		" status=", "PASS" if rare_coin_violations.is_empty() else "FAIL")
	for violation: String in rare_coin_violations:
		print("    ", violation)
	variant_violations.append_array(rare_coin_violations)

	var coin_line_violations: Array[String] = check_coin_line_height()
	print("TERRAIN_INVARIANT_COIN_LINE clearance=%.1f end_drop=%.1f jitter=%.1f" % [CoinSpawner.COIN_LINE_CLEARANCE, CoinSpawner.COIN_LINE_END_DROP, CoinSpawner.COIN_LINE_JITTER],
		" status=", "PASS" if coin_line_violations.is_empty() else "FAIL")
	for violation: String in coin_line_violations:
		print("    ", violation)
	variant_violations.append_array(coin_line_violations)

	# Needs a scene (the generator must be in the tree to have a seed), so it cannot join the
	# three constant-only checks above -- but it is still seed-independent in everything it
	# asserts, so it runs once against the first seed rather than per seed.
	var lake_violations: Array[String] = await check_frozen_lake(session_seeds[0])
	variant_violations.append_array(lake_violations)

	var failed_seed_count: int = 0
	for session_seed: int in session_seeds:
		var seed_passed: bool = await check_session_seed(session_seed, start_world_x, end_world_x, sample_step)
		if not seed_passed:
			failed_seed_count += 1

	print("TERRAIN_INVARIANT_RESULT seeds_checked=", session_seeds.size(), " seeds_failed=", failed_seed_count)
	if not variant_violations.is_empty():
		print("TERRAIN_INVARIANT_RESULT status=FAIL")
		quit(1)
		return

	if failed_seed_count > 0:
		print("TERRAIN_INVARIANT_RESULT status=FAIL")
		quit(1)
		return

	print("TERRAIN_INVARIANT_RESULT status=PASS")
	quit(0)


func build_seed_sweep(seed_count: int) -> Array[int]:
	var session_seeds: Array[int] = []
	var seed_generator: RandomNumberGenerator = RandomNumberGenerator.new()
	seed_generator.seed = SEED_SWEEP_BASE
	for seed_index: int in range(seed_count):
		session_seeds.append(int(seed_generator.randi() & 0x7fffffff))
	return session_seeds


func check_session_seed(session_seed: int, start_world_x: float, end_world_x: float, sample_step: float) -> bool:
	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	# The height field is a pure function of (session_seed, world_x), so nothing here
	# depends on the player actually moving -- but the scene must be in the tree for
	# _ready() to snapshot floor_max_angle into the generator before sampling.
	player.DEBUG_LOG_FREEZE_REPRO = false
	player.DEBUG_SHOW_PLAYER_STATE = false
	root.add_child(main)
	await physics_frame

	var max_slope_angle: float = player.floor_max_angle
	var report: Dictionary = sample_height_field(terrain_generator, start_world_x, end_world_x, sample_step, max_slope_angle)
	var chasm_report: Dictionary = check_chasms(terrain_generator, start_world_x, end_world_x)
	var coin_spawner: CoinSpawner = main.get_node("TerrainGenerator/CoinSpawner") as CoinSpawner
	var coin_report: Dictionary = measure_coin_density(terrain_generator, coin_spawner, start_world_x, end_world_x)
	print_seed_report(session_seed, report, max_slope_angle)
	print_chasm_report(session_seed, chasm_report)
	var coin_violations: Array[String] = coin_report["violations"]
	print("TERRAIN_INVARIANT_COIN_DENSITY seed=", session_seed,
		" coins_per_slot=%.4f" % float(coin_report["coins_per_slot"]),
		" lines=", coin_report["line_count"], " slots=", coin_report["slot_count"],
		" status=", "PASS" if coin_violations.is_empty() else "FAIL")
	for violation: String in coin_violations:
		print("    ", violation)

	main.queue_free()
	await process_frame
	return int(report["violation_count"]) == 0 and int(chasm_report["violation_count"]) == 0 and coin_violations.is_empty()


# The frozen lake set piece: a runtime-injected 7500px flat segment that suppresses every
# spawner and disables jumping while the player crosses it. Four claims, none of which is
# visible from the generator alone, and all four fail silently in play -- a lake with a slope
# in it just reads as ordinary terrain, and a lake with a void in it is a jump-or-die hazard
# in a stretch where the jump button does nothing.
#
# Pinned through debug_force_lake_segment_index rather than arm_lake(), so this measures the
# geometry with no FrozenLakeDirector, no save file and no playtime involved.
#
# Runs on ONE seed rather than the sweep: the lake spec is a constant, so the only thing a
# second seed varies is the baseline the flat sits at, which the constant-height assertion is
# already invariant to.
func check_frozen_lake(session_seed: int) -> Array[String]:
	var violations: Array[String] = []

	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	terrain_generator.debug_force_lake_segment_index = LAKE_TEST_SEGMENT_INDEX
	player.DEBUG_LOG_FREEZE_REPRO = false
	player.DEBUG_SHOW_PLAYER_STATE = false
	root.add_child(main)
	await physics_frame

	var lake_start_x: float = terrain_generator.get_lake_start_x()
	var lake_end_x: float = terrain_generator.get_lake_end_x()

	# 1. The span is the length the spec claims. A mismatch means something upstream is
	#    overriding the spec -- most likely the chasm branch winning the ordering.
	var span: float = lake_end_x - lake_start_x
	if absf(span - TerrainGenerator.LAKE_SEGMENT_LENGTH) > LAKE_EPSILON:
		violations.append("LAKE_SPAN_WRONG span=%.3f expected=%.3f (index %d is not a lake)" % [
			span, TerrainGenerator.LAKE_SEGMENT_LENGTH, LAKE_TEST_SEGMENT_INDEX,
		])

	# 2. Dead flat, and dead flat is the WHOLE safety argument for injecting terrain at
	#    runtime: zero slope cannot reach floor_max_angle, so no wall-wedge is reachable here
	#    no matter what the lake lands next to. Sampled at 1px like the main sweep.
	var lake_height: float = terrain_generator.get_terrain_height(lake_start_x)
	var worst_deviation: float = 0.0
	var worst_deviation_x: float = lake_start_x
	var sample_x: float = lake_start_x
	while sample_x < lake_end_x:
		var deviation: float = absf(terrain_generator.get_terrain_height(sample_x) - lake_height)
		if deviation > worst_deviation:
			worst_deviation = deviation
			worst_deviation_x = sample_x
		# 4. And there is ground the whole way. A void anywhere inside the lake is the one
		#    thing the feature must never contain.
		if not terrain_generator.has_ground_at_world_x(sample_x):
			violations.append("LAKE_VOID_INSIDE world_x=%.1f" % sample_x)
			break
		sample_x += 1.0
	if worst_deviation > LAKE_EPSILON:
		violations.append("LAKE_NOT_FLAT worst_deviation=%.6f at world_x=%.1f" % [
			worst_deviation, worst_deviation_x,
		])

	# 3. Both seams are C0. Free by construction (magnitude 0 means the baseline delta derives
	#    to 0.0), which is exactly why it is worth asserting -- "free by construction" is a
	#    claim about code that can be edited.
	var entry_step: float = absf(terrain_generator.get_terrain_height(lake_start_x)
			- terrain_generator.get_terrain_height(lake_start_x - 1.0))
	var exit_step: float = absf(terrain_generator.get_terrain_height(lake_end_x)
			- terrain_generator.get_terrain_height(lake_end_x - 1.0))
	if entry_step > DISCONTINUITY_STEP_Y:
		violations.append("LAKE_ENTRY_SEAM_STEP step=%.3f at world_x=%.1f" % [entry_step, lake_start_x])
	if exit_step > DISCONTINUITY_STEP_Y:
		violations.append("LAKE_EXIT_SEAM_STEP step=%.3f at world_x=%.1f" % [exit_step, lake_end_x])

	# 5. No chasm may touch the lake or either neighbouring segment. arm_lake() enforces this
	#    at runtime; with a PINNED index it cannot, so a hit here means the pinned index is
	#    unsuitable for the gate rather than that the feature is broken -- the message says so.
	for offset: int in [-1, 0, 1]:
		if terrain_generator.is_chasm_segment_index(LAKE_TEST_SEGMENT_INDEX + offset):
			violations.append("LAKE_TEST_INDEX_MEETS_CHASM index=%d offset=%d -- pick a different LAKE_TEST_SEGMENT_INDEX" % [
				LAKE_TEST_SEGMENT_INDEX, offset,
			])

	print("TERRAIN_INVARIANT_LAKE seed=", session_seed, " index=", LAKE_TEST_SEGMENT_INDEX,
		" span=[%.1f, %.1f]" % [lake_start_x, lake_end_x],
		" flatness=%.6f" % worst_deviation,
		" status=", "PASS" if violations.is_empty() else "FAIL")
	for violation: String in violations:
		print("    ", violation)

	main.queue_free()
	await process_frame
	return violations


func sample_height_field(terrain_generator: TerrainGenerator, start_world_x: float, end_world_x: float, sample_step: float, max_slope_angle: float) -> Dictionary:
	var violations: Array[String] = []
	var violation_count: int = 0
	var worst_slope_angle: float = 0.0
	var worst_slope_world_x: float = start_world_x
	var slope_angle_limit: float = max_slope_angle + SLOPE_ANGLE_TOLERANCE_RADIANS

	var previous_world_x: float = start_world_x
	var previous_height: float = terrain_generator.get_terrain_height(previous_world_x)
	if not is_finite(previous_height):
		violations.append("non_finite height at world_x=%.3f" % previous_world_x)
		violation_count += 1

	var sample_index: int = 0
	var world_x: float = start_world_x + sample_step
	while world_x <= end_world_x:
		var height: float = terrain_generator.get_terrain_height(world_x)
		sample_index += 1
		if sample_index % PROGRESS_SAMPLE_INTERVAL == 0:
			print("  ...sampled %d points, at world_x=%.0f" % [sample_index, world_x])

		if not is_finite(height):
			violation_count += 1
			if violations.size() < MAX_REPORTED_VIOLATIONS_PER_SEED:
				violations.append("non_finite height at world_x=%.3f" % world_x)
			previous_world_x = world_x
			previous_height = height
			world_x += sample_step
			continue

		var delta_height: float = height - previous_height
		var delta_x: float = world_x - previous_world_x
		var slope_angle: float = absf(atan2(delta_height, delta_x))

		# The one legal discontinuity in the generator: a drop chasm's far lip, where the field
		# steps from near-lip height down to the landing. Recognised structurally -- the
		# previous sample was inside a drop void and this one is not -- rather than by
		# tolerating any large step, so an accidental cliff anywhere else still fails.
		#
		# Skipped for the slope MAXIMUM too, not just the assertions: the step is near-vertical
		# and would otherwise become the reported max_slope, hiding the real steepest terrain.
		# check_one_chasm asserts the step's exact size, so nothing here goes unchecked.
		var stepped_off_drop_lip: bool = (
			terrain_generator.get_pending_exit_drop_at_world_x(previous_world_x) > 0.0
			and terrain_generator.get_pending_exit_drop_at_world_x(world_x) <= 0.0
			and delta_height > 0.0
		)
		if stepped_off_drop_lip:
			previous_world_x = world_x
			previous_height = height
			world_x += sample_step
			continue

		if slope_angle > worst_slope_angle:
			worst_slope_angle = slope_angle
			worst_slope_world_x = world_x

		if absf(delta_height) > DISCONTINUITY_STEP_Y:
			violation_count += 1
			if violations.size() < MAX_REPORTED_VIOLATIONS_PER_SEED:
				violations.append("C0_DISCONTINUITY at world_x=%.3f dy=%.3f over dx=%.3f segment=%s" % [
					world_x,
					delta_height,
					delta_x,
					terrain_generator.get_segment_selection_label(terrain_generator.find_segment_index_at_x(world_x)),
				])
		elif slope_angle > slope_angle_limit:
			violation_count += 1
			if violations.size() < MAX_REPORTED_VIOLATIONS_PER_SEED:
				violations.append("SLOPE_EXCEEDS_FLOOR_MAX_ANGLE at world_x=%.3f angle=%.2fdeg limit=%.2fdeg segment=%s" % [
					world_x,
					rad_to_deg(slope_angle),
					rad_to_deg(max_slope_angle),
					terrain_generator.get_segment_selection_label(terrain_generator.find_segment_index_at_x(world_x)),
				])

		previous_world_x = world_x
		previous_height = height
		world_x += sample_step

	var report: Dictionary = {}
	report["violations"] = violations
	report["violation_count"] = violation_count
	report["worst_slope_angle"] = worst_slope_angle
	report["worst_slope_world_x"] = worst_slope_world_x
	report["sample_count"] = sample_index + 1
	return report


# Validates TerrainGenerator's chasm CONSTANTS against the real SpeedManager ramp and the real
# jump arithmetic, independently of what any particular seed happened to generate.
#
# check_one_chasm() below already tests every chasm the sweep actually walks over, but that is
# a sample: a variant's WORST case is a chasm sitting at the earliest segment index it is
# allowed to occupy, and no finite seed sweep is guaranteed to contain one. This checks that
# worst case directly, for every variant, so the min_segment_index values in the table are
# derived numbers rather than ones that happened not to be caught.
func check_chasm_variant_table() -> Array[String]:
	var violations: Array[String] = []

	# 1. The lead-in must exceed the maximum reach of any jump, which is a JUMP-BOOSTED one at
	#    MAX_SPEED. Below this, a jump taken before the chasm's segment even begins can land in
	#    the void, which is the bug this replaced a comment about (see CHASM_LEAD_IN_LENGTH).
	var boosted_reach: float = get_jump_reach_with_multiplier(
		SpeedManager.MAX_SPEED, TerrainGenerator.CHASM_EXIT_DROP, PowerupManager.JUMP_BOOST_VELOCITY_MULTIPLIER,
	)
	var required_lead_in: float = boosted_reach + CHASM_LEAD_IN_MARGIN
	if TerrainGenerator.CHASM_LEAD_IN_LENGTH < required_lead_in:
		violations.append("CHASM_LEAD_IN_TOO_SHORT lead_in=%.1f required=%.1f (boosted reach=%.1f at %.0f px/s)" % [
			TerrainGenerator.CHASM_LEAD_IN_LENGTH, required_lead_in, boosted_reach, SpeedManager.MAX_SPEED,
		])

	for variant: Dictionary in TerrainGenerator.CHASM_VARIANTS:
		var label: String = String(variant["label"])
		var void_length: float = float(variant["void_length"])
		var min_segment_index: int = int(variant["min_segment_index"])

		# 2. Clearable at the variant's own worst-case position. SMALL_SEGMENT_LENGTH is the
		#    shortest segment there is, so index * SMALL_SEGMENT_LENGTH is a hard lower bound on
		#    the world_x of that segment -- the same conservative conversion the generator's
		#    min_segment_index gate relies on.
		var earliest_void_start_x: float = (float(min_segment_index) * TerrainGenerator.SMALL_SEGMENT_LENGTH) + TerrainGenerator.CHASM_LEAD_IN_LENGTH
		var min_speed: float = get_min_speed_at_world_x(earliest_void_start_x)
		var variant_exit_drop: float = float(variant.get("exit_drop", TerrainGenerator.CHASM_EXIT_DROP))
		var jump_reach: float = get_jump_reach(min_speed, variant_exit_drop)
		var max_allowed_width: float = jump_reach * CHASM_MAX_REACH_FRACTION
		if void_length > max_allowed_width:
			violations.append("CHASM_VARIANT_NOT_CLEARABLE %s width=%.1f max_allowed=%.1f at earliest world_x=%.1f (speed=%.1f reach=%.1f) -- raise min_segment_index to >= %d" % [
				label, void_length, max_allowed_width, earliest_void_start_x, min_speed, jump_reach,
				get_required_min_segment_index(void_length),
			])

		# 3. Below the global chasm gate the variant is unreachable, which is a table typo
		#    rather than a safety problem -- but a silently dead variant is exactly the kind of
		#    thing that makes a width distribution quietly wrong.
		if min_segment_index < TerrainGenerator.CHASM_MIN_SEGMENT_INDEX:
			violations.append("CHASM_VARIANT_BELOW_GLOBAL_MIN %s min_segment_index=%d global=%d" % [
				label, min_segment_index, TerrainGenerator.CHASM_MIN_SEGMENT_INDEX,
			])

		# 4. The void plus its run-up plus the flatness margin the lip check needs must fit
		#    inside the segment, or the far lip lands in whatever shape comes next and
		#    CHASM_LIP_NOT_FLAT starts firing for a reason that is really a length bug.
		#
		#    A drop variant needs more than that: the player is airborne past the far lip for
		#    the rest of the fall, so the landing flat must outlast the longest crossing, which
		#    is the one taken at MAX_SPEED.
		var variant_segment_length: float = float(variant.get("segment_length", TerrainGenerator.CHASM_SEGMENT_LENGTH))
		var required_segment_length: float = TerrainGenerator.CHASM_LEAD_IN_LENGTH + void_length + CHASM_LIP_FLATNESS_MARGIN
		if variant_exit_drop > 0.0:
			var longest_crossing: float = SpeedManager.MAX_SPEED * sqrt(2.0 * variant_exit_drop / Player.GRAVITY)
			required_segment_length = maxf(required_segment_length, TerrainGenerator.CHASM_LEAD_IN_LENGTH + longest_crossing + CHASM_LIP_FLATNESS_MARGIN)
		if variant_segment_length < required_segment_length:
			violations.append("CHASM_SEGMENT_TOO_SHORT %s segment=%.1f required=%.1f" % [
				label, variant_segment_length, required_segment_length,
			])

	return violations


# The lowest segment index at which a void of this width passes CHASM_MAX_REACH_FRACTION.
# Reported alongside a CHASM_VARIANT_NOT_CLEARABLE failure so the fix is a number to paste
# rather than an afternoon of solving the ramp by hand.
# The rare coin's whole design is "only a fully upgraded jump reaches it", and that claim is
# an arithmetic relationship between constants in FOUR files: RareCoinSpawner's clearance,
# Player's JUMP_VELOCITY/GRAVITY, UpgradeStore's last two JUMP_MULTIPLIERS, and the collision
# radius inside rare_coin.tscn. Nothing about it is visible from any one of them, and both
# ways of getting it wrong are silent in play -- a coin the second-best jump can reach looks
# exactly like one it cannot, and an unreachable coin looks like a bug in the spawner.
#
# The radius is read out of the SCENE, not restated here, because "someone made the pickup
# bigger" is the single most likely way this breaks -- a larger circle raises the ceiling.
func check_rare_coin_height() -> Array[String]:
	var violations: Array[String] = []
	var multipliers: Array[float] = UpgradeStore.JUMP_MULTIPLIERS
	if multipliers.size() < 2:
		violations.append("UpgradeStore.JUMP_MULTIPLIERS has fewer than two levels -- the rare coin's 'top level only' rule has nothing to mean")
		return violations

	var scene_root: Node = RareCoinSpawner.RARE_COIN_SCENE.instantiate()
	var collision_shape: CollisionShape2D = scene_root.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var circle: CircleShape2D = collision_shape.shape as CircleShape2D if collision_shape != null else null
	if circle == null:
		violations.append("rare_coin.tscn has no CollisionShape2D holding a CircleShape2D -- the reach derivation cannot be checked")
		scene_root.free()
		return violations
	var coin_radius: float = circle.radius
	scene_root.free()

	# Capsule half-height doubled: the player's capsule centre starts one half-height above the
	# surface and it is the TOP of the capsule that reaches the coin.
	var capsule_reach: float = PLAYER_CAPSULE_HALF_HEIGHT * 2.0
	var clearance: float = RareCoinSpawner.RARE_COIN_CLEARANCE

	var top_multiplier: float = multipliers[multipliers.size() - 1]
	var second_multiplier: float = multipliers[multipliers.size() - 2]
	var top_ceiling: float = capsule_reach + get_jump_apex(top_multiplier) + coin_radius
	var second_ceiling: float = capsule_reach + get_jump_apex(second_multiplier) + coin_radius

	if clearance > top_ceiling - RARE_COIN_REACH_MARGIN:
		violations.append("rare coin at %.1f is out of reach of a MAX jump (ceiling %.1f, margin %.1f) -- the reward is unobtainable and reads as a bug"
			% [clearance, top_ceiling, RARE_COIN_REACH_MARGIN])
	if clearance < second_ceiling + RARE_COIN_REACH_MARGIN:
		violations.append("rare coin at %.1f is within reach of jump level %d (ceiling %.1f, margin %.1f) -- it stops being a max-upgrade reward"
			% [clearance, multipliers.size() - 2, second_ceiling, RARE_COIN_REACH_MARGIN])
	return violations


# Coin air lines. Three coins hung in a near-flat line, high enough to cost a real jump. The
# end coins hang a little lower than the middle so ONE jump takes all three -- a jump apexing on
# the middle coin has already fallen by the time it reaches an end, and a ruler-flat line drops
# those end coins out of the pickup radius at the slower end of the speed ramp.
#
# Every edge here is silent in play: a line no jump can finish looks exactly like a line that is
# merely hard, and a line hung a pixel above some upgrade level's ceiling looks exactly like one
# hung a pixel below it -- until that player never quite gets it.
#
#   1. the line is inside a max jump's reach          (or it is bait nobody can finish)
#   2. it is not within a rounding error of ANY jump level's ceiling
#                                                     (or one level's players get a coin flip)
#   3. the end coins are inside the pickup radius of the trajectory AT THE SLOWEST SPEED
#                                                     (or the line is three grabs, not one jump)
#   4. an end coin can never be hung above the middle one   (or it is above the curve entirely)
#   5. every coin, jitter included, clears the standing grab ceiling      (or it is free)
func check_coin_line_height() -> Array[String]:
	var violations: Array[String] = []

	var scene_root: Node = CoinSpawner.COIN_SCENE.instantiate()
	var collision_shape: CollisionShape2D = scene_root.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var circle: CircleShape2D = collision_shape.shape as CircleShape2D if collision_shape != null else null
	if circle == null:
		violations.append("coin.tscn has no CollisionShape2D holding a CircleShape2D -- the reach derivation cannot be checked")
		scene_root.free()
		return violations
	var coin_radius: float = circle.radius
	scene_root.free()

	var multipliers: Array[float] = UpgradeStore.JUMP_MULTIPLIERS
	if multipliers.size() < 2:
		violations.append("UpgradeStore.JUMP_MULTIPLIERS has fewer than two levels -- the line's 'max upgrade takes all three' rule has nothing to mean")
		return violations

	var capsule_reach: float = PLAYER_CAPSULE_HALF_HEIGHT * 2.0
	var standing_ceiling: float = capsule_reach + coin_radius
	var top_ceiling: float = capsule_reach + get_jump_apex(multipliers[multipliers.size() - 1]) + coin_radius

	var clearance: float = CoinSpawner.COIN_LINE_CLEARANCE
	if clearance > top_ceiling - COIN_LINE_REACH_MARGIN:
		violations.append("air line at %.1f is out of reach of a MAX jump (ceiling %.1f, margin %.1f) -- nobody can finish it"
			% [clearance, top_ceiling, COIN_LINE_REACH_MARGIN])

	# Which levels reach a line is a design choice and may move. Sitting ON one of those
	# boundaries is never the choice: that level's players see a coin they can take only on a
	# perfect frame, which is indistinguishable from a broken spawner.
	for level: int in range(multipliers.size()):
		var ceiling: float = capsule_reach + get_jump_apex(multipliers[level]) + coin_radius
		if absf(clearance - ceiling) < COIN_LINE_REACH_MARGIN:
			violations.append("air line at %.1f sits %.1fpx from jump level %d's grab ceiling %.1f (margin %.1f) -- that level gets a coin flip, not a rule"
				% [clearance, absf(clearance - ceiling), level, ceiling, COIN_LINE_REACH_MARGIN])

	# How far a jump apexing on the middle coin has fallen by the time it reaches an end coin,
	# at the slowest speed a line can be met at. The end coin has to be within the pickup radius
	# of that, or one jump stops taking the whole line.
	var travel_time: float = CoinSpawner.COIN_LINE_SPACING_X / COIN_LINE_SLOWEST_SPEED
	var trajectory_drop: float = 0.5 * Player.GRAVITY * travel_time * travel_time
	var end_error: float = absf(trajectory_drop - CoinSpawner.COIN_LINE_END_DROP)
	if end_error > coin_radius:
		violations.append("a line's end coins sit %.1fpx off the trajectory at %.0f px/s (drop %.1f vs COIN_LINE_END_DROP %.1f, pickup radius %.1f) -- one jump can no longer take all three"
			% [end_error, COIN_LINE_SLOWEST_SPEED, trajectory_drop, CoinSpawner.COIN_LINE_END_DROP, coin_radius])

	# An end coin must never be able to out-rank the middle one: the jump traces a curve with
	# its top at the middle coin, so an end coin ABOVE that sits above the trajectory entirely
	# and cannot be caught. Holds as long as the droop is at least the jitter range.
	if CoinSpawner.COIN_LINE_END_DROP < CoinSpawner.COIN_LINE_JITTER:
		violations.append("COIN_LINE_JITTER %.1f exceeds COIN_LINE_END_DROP %.1f -- an end coin can be hung above the middle one, which puts it above the arc a jump traces"
			% [CoinSpawner.COIN_LINE_JITTER, CoinSpawner.COIN_LINE_END_DROP])

	# Jitter only ever lowers a coin, so the deepest possible coin is the one to check.
	var lowest: float = clearance - CoinSpawner.COIN_LINE_END_DROP - CoinSpawner.COIN_LINE_JITTER
	if lowest < standing_ceiling + COIN_LINE_FREE_GRAB_MARGIN:
		violations.append("the lowest coin a line can produce, %.1f, is inside the standing grab ceiling %.1f (margin %.1f) -- it costs no input, which is the only reason the line exists"
			% [lowest, standing_ceiling, COIN_LINE_FREE_GRAB_MARGIN])

	return violations


# Coins per slot, MEASURED by asking the spawner what it would build over the sampled range,
# rather than multiplying the constants out. The two differ: a line roll over ground too steep
# to hang a line on falls back to a single coin, so the real density is a property of the
# terrain as well as of CoinSpawner, and no closed form over the constants is true.
#
# This is the number UpgradeStore.JUMP_UPGRADE_COSTS is sized against. It was 0.40 before air
# lines existed, and the include chance was re-tuned to land back on it.
func measure_coin_density(terrain_generator: TerrainGenerator, spawner: CoinSpawner, start_world_x: float, end_world_x: float) -> Dictionary:
	var chunk_width: float = terrain_generator.chunk_width
	var first_chunk: int = int(floor(start_world_x / chunk_width))
	var last_chunk: int = int(floor(end_world_x / chunk_width))
	var slot_count: int = 0
	var coin_count: int = 0
	var line_count: int = 0

	for chunk_index: int in range(first_chunk, last_chunk + 1):
		var chunk_start_x: float = float(chunk_index) * chunk_width
		for slot_index: int in range(CoinSpawner.COIN_SLOT_FRACTIONS.size()):
			slot_count += 1
			if spawner.get_slot_hash(chunk_index, slot_index) > CoinSpawner.COIN_SLOT_INCLUDE_CHANCE:
				continue
			var world_x: float = chunk_start_x + (CoinSpawner.COIN_SLOT_FRACTIONS[slot_index] * chunk_width)
			if spawner.get_line_hash(chunk_index, slot_index) < CoinSpawner.COIN_LINE_CHANCE and spawner.can_fit_line_at_world_x(world_x):
				line_count += 1
				coin_count += CoinSpawner.COIN_LINE_COIN_COUNT
				continue
			if terrain_generator.has_ground_at_world_x(world_x):
				coin_count += 1

	var coins_per_slot: float = float(coin_count) / maxf(float(slot_count), 1.0)
	var violations: Array[String] = []
	if absf(coins_per_slot - COIN_DENSITY_TARGET) > COIN_DENSITY_TOLERANCE:
		violations.append("coin density %.4f per slot is outside %.2f +/- %.2f -- UpgradeStore.JUMP_UPGRADE_COSTS is costed against that number, so the whole meta-progression re-times"
			% [coins_per_slot, COIN_DENSITY_TARGET, COIN_DENSITY_TOLERANCE])
	return {
		"coins_per_slot": coins_per_slot,
		"line_count": line_count,
		"slot_count": slot_count,
		"violations": violations,
	}


# Apex of a jump at the given upgrade multiplier: v^2 / 2g, with v scaled by the multiplier.
func get_jump_apex(jump_velocity_multiplier: float) -> float:
	var jump_speed: float = absf(Player.JUMP_VELOCITY) * jump_velocity_multiplier
	return (jump_speed * jump_speed) / (2.0 * Player.GRAVITY)


func get_required_min_segment_index(void_length: float) -> int:
	var required_reach: float = void_length / CHASM_MAX_REACH_FRACTION
	var airtime: float = get_jump_airtime(TerrainGenerator.CHASM_EXIT_DROP, 1.0)
	var required_speed: float = required_reach / airtime
	if required_speed > SpeedManager.MAX_SPEED:
		return -1

	# Inverse of get_min_speed_at_world_x's phase 2 branch.
	var phase1_distance: float = (SpeedManager.INITIAL_SPEED * SpeedManager.PHASE1_DURATION) + (0.5 * SpeedManager.PHASE1_ACCELERATION * pow(SpeedManager.PHASE1_DURATION, 2.0))
	var required_world_x: float = phase1_distance
	if required_speed > SpeedManager.PHASE1_TARGET_SPEED:
		required_world_x += (pow(required_speed, 2.0) - pow(SpeedManager.PHASE1_TARGET_SPEED, 2.0)) / (2.0 * SpeedManager.PHASE2_ACCELERATION)

	# The lead-in is part of the distance travelled before the void, so it counts toward the
	# requirement rather than against it.
	var required_segment_start_x: float = maxf(required_world_x - TerrainGenerator.CHASM_LEAD_IN_LENGTH, 0.0)
	return maxi(ceili(required_segment_start_x / TerrainGenerator.SMALL_SEGMENT_LENGTH), TerrainGenerator.CHASM_MIN_SEGMENT_INDEX)


func check_chasms(terrain_generator: TerrainGenerator, start_world_x: float, end_world_x: float) -> Dictionary:
	var violations: Array[String] = []
	var violation_count: int = 0
	var void_starts: Array[float] = []
	var min_width: float = 0.0
	var max_width: float = 0.0

	terrain_generator.ensure_segment_cache_for_world_x(start_world_x)
	var segment_index: int = terrain_generator.find_segment_index_at_x(start_world_x)
	while true:
		terrain_generator.ensure_segment_cache_through(segment_index)
		var segment_start_x: float = terrain_generator.segment_start_x_cache[segment_index]
		if segment_start_x > end_world_x:
			break

		var void_span: Dictionary = terrain_generator.get_void_span_for_segment(segment_index)
		if not void_span.is_empty():
			var void_start_x: float = float(void_span["start_x"])
			var void_end_x: float = float(void_span["end_x"])
			var void_width: float = void_end_x - void_start_x
			if void_starts.is_empty():
				min_width = void_width
				max_width = void_width
			min_width = minf(min_width, void_width)
			max_width = maxf(max_width, void_width)
			void_starts.append(void_start_x)

			for violation: String in check_one_chasm(terrain_generator, segment_index, void_start_x, void_end_x):
				violation_count += 1
				if violations.size() < MAX_REPORTED_VIOLATIONS_PER_SEED:
					violations.append(violation)

		segment_index += 1

	# Spacing, checked across the whole sweep rather than per chasm.
	var min_spacing: float = 0.0
	var max_spacing: float = 0.0
	# Offsets are drawn from [MARGIN, WINDOW - MARGIN - 1], so the tightest possible pair is a
	# chasm at the last legal offset of one window followed by one at the first legal offset of
	# the next: (WINDOW - (WINDOW - MARGIN - 1)) + MARGIN = 2 * MARGIN + 1 segments. Converted
	# at the SHORTEST possible segment length, which is the only bound that holds regardless of
	# the shape mix.
	var min_spacing_segments: int = (2 * TerrainGenerator.CHASM_WINDOW_EDGE_MARGIN_SEGMENTS) + 1
	var min_spacing_world_x: float = float(min_spacing_segments) * TerrainGenerator.SMALL_SEGMENT_LENGTH
	for spacing_index: int in range(1, void_starts.size()):
		var spacing: float = void_starts[spacing_index] - void_starts[spacing_index - 1]
		if spacing_index == 1:
			min_spacing = spacing
			max_spacing = spacing
		min_spacing = minf(min_spacing, spacing)
		max_spacing = maxf(max_spacing, spacing)
		if spacing < min_spacing_world_x:
			violation_count += 1
			if violations.size() < MAX_REPORTED_VIOLATIONS_PER_SEED:
				violations.append("CHASM_SPACING too close at world_x=%.1f spacing=%.1f min=%.1f" % [
					void_starts[spacing_index], spacing, min_spacing_world_x,
				])

	if void_starts.is_empty() and (end_world_x - start_world_x) >= CHASM_MIN_RANGE_FOR_PRESENCE:
		violation_count += 1
		violations.append("CHASM_NONE_GENERATED over %.0fpx -- rarity regression, or debug_chasm_disabled leaked into the scene" % (end_world_x - start_world_x))

	var chasm_report: Dictionary = {}
	chasm_report["violations"] = violations
	chasm_report["violation_count"] = violation_count
	chasm_report["void_count"] = void_starts.size()
	chasm_report["first_void_x"] = void_starts[0] if not void_starts.is_empty() else 0.0
	chasm_report["min_spacing"] = min_spacing
	chasm_report["max_spacing"] = max_spacing
	chasm_report["min_width"] = min_width
	chasm_report["max_width"] = max_width
	return chasm_report


func check_one_chasm(terrain_generator: TerrainGenerator, segment_index: int, void_start_x: float, void_end_x: float) -> Array[String]:
	var violations: Array[String] = []
	var void_width: float = void_end_x - void_start_x

	if void_width <= 0.0:
		violations.append("CHASM_WIDTH non-positive at world_x=%.1f width=%.3f" % [void_start_x, void_width])
		return violations

	# 1. Both lips, and the ground either side of them, must be exactly level. This is the
	#    entire safety argument for the feature: a chasm adds no slope to the world, so it
	#    cannot reproduce the large_valley wall-wedge. If this fails, that argument is void.
	#
	#    With a drop chasm the far side is level too, just exit_drop lower, so each side is
	#    checked against its OWN lip height. That turns the step into an assertion rather than
	#    an exemption: the far lip must sit exactly exit_drop below the near one, and the whole
	#    void must still read as flat near-lip ground (the property the boosted skim needs).
	var spec: Dictionary = terrain_generator.get_segment_spec(segment_index)
	var exit_drop: float = float(spec.get("exit_drop", 0.0))
	var lip_height: float = terrain_generator.get_terrain_height(void_start_x)
	var far_lip_height: float = lip_height + exit_drop
	var flatness_expectations: Array[Array] = [
		[void_start_x - CHASM_LIP_FLATNESS_MARGIN, lip_height],
		[void_start_x, lip_height],
		# Inside the void, which must read as near-lip ground however deep the far lip is.
		[void_end_x - CHASM_LIP_FLATNESS_TOLERANCE_Y, lip_height],
		[void_end_x, far_lip_height],
		[void_end_x + CHASM_LIP_FLATNESS_MARGIN, far_lip_height],
	]
	for expectation: Array in flatness_expectations:
		var world_x: float = float(expectation[0])
		var expected_height: float = float(expectation[1])
		var height: float = terrain_generator.get_terrain_height(world_x)
		if absf(height - expected_height) > CHASM_LIP_FLATNESS_TOLERANCE_Y:
			violations.append("CHASM_LIP_NOT_FLAT at world_x=%.1f dy=%.4f expected=%.4f (void starts %.1f drop=%.1f)" % [
				world_x, height - expected_height, expected_height, void_start_x, exit_drop,
			])
			break

	# 2. Not before the hard minimum world_x the minimum-speed derivation assumes.
	var earliest_void_world_x: float = float(TerrainGenerator.CHASM_MIN_SEGMENT_INDEX) * TerrainGenerator.SMALL_SEGMENT_LENGTH
	if void_start_x < earliest_void_world_x:
		violations.append("CHASM_TOO_EARLY at world_x=%.1f earliest=%.1f" % [void_start_x, earliest_void_world_x])

	# 3. A collision vertex must sit exactly on each lip, in every chunk the lip falls inside.
	#    Without one, a ~16px chord straddles the lip: the midpoint test in build_chunk_surface
	#    then either leaves a partial chord hanging over the void or eats a slice of real
	#    ground. This is the one geometry bug the height field literally cannot express, so it
	#    is the only thing here that has to look at the collision samples directly.
	violations.append_array(check_chasm_lip_vertices(terrain_generator, void_start_x))
	violations.append_array(check_chasm_lip_vertices(terrain_generator, void_end_x))

	# 4. Clearable at the slowest speed the player can possibly have arrived here with.
	var min_speed: float = get_min_speed_at_world_x(void_start_x)
	var jump_reach: float = get_jump_reach(min_speed, exit_drop)
	if void_width > jump_reach * CHASM_MAX_REACH_FRACTION:
		violations.append("CHASM_NOT_CLEARABLE at world_x=%.1f width=%.1f reach=%.1f (speed=%.1f drop=%.1f) max_allowed=%.1f" % [
			void_start_x, void_width, jump_reach, min_speed, exit_drop, jump_reach * CHASM_MAX_REACH_FRACTION,
		])

	# 5. The other side of the same coin: a void with a lower far lip can be crossed by running
	#    straight off the edge, no jump at all, if it is narrow enough relative to the drop.
	#    Evaluated at MAX_SPEED rather than the arrival speed because that is the strictest
	#    direction -- faster means further, means more likely to be free.
	#
	#    Inert at exit_drop 0 (fall_distance is 0, so any positive width passes), which is every
	#    chasm today. It is here so that Phase 3's drop variants cannot ship as non-hazards.
	#
	#    Scoped to must_be_jumped variants. chasm_drop is deliberately not a hazard -- it is
	#    the spectacle beat -- so for it this assertion is not merely inapplicable, it is
	#    backwards, and #6 asserts the opposite property instead.
	var must_be_jumped: bool = bool(spec.get("must_be_jumped", true))
	if exit_drop > 0.0 and must_be_jumped:
		var free_fall_time: float = sqrt(2.0 * exit_drop / Player.GRAVITY)
		var free_crossing_width: float = SpeedManager.MAX_SPEED * free_fall_time
		if void_width < free_crossing_width + CHASM_MIN_HAZARD_MARGIN:
			violations.append("CHASM_TRIVIALLY_CLEARABLE at world_x=%.1f width=%.1f drop=%.1f free_crossing=%.1f -- clearable without jumping at %.0f px/s" % [
				void_start_x, void_width, exit_drop, free_crossing_width, SpeedManager.MAX_SPEED,
			])

	# 6. The drop chasm's own safety argument, and the inverse of #5: it must be crossable by
	#    running straight off the near lip with NO input at all, at the slowest speed it can be
	#    reached with. This is the whole contract -- it is scenery, not a hazard, and a player
	#    who does nothing must survive it.
	#
	#    Checked at min_speed because slow is the strictest direction here: less horizontal
	#    travel per unit of fall.
	if not must_be_jumped:
		if exit_drop <= 0.0:
			violations.append("CHASM_DROP_WITHOUT_DROP at world_x=%.1f -- must_be_jumped=false needs a non-zero exit_drop, or nothing carries the player across" % void_start_x)
		else:
			var run_off_time: float = sqrt(2.0 * exit_drop / Player.GRAVITY)
			var run_off_reach: float = min_speed * run_off_time
			if run_off_reach < void_width + CHASM_DROP_CROSSING_MARGIN:
				violations.append("CHASM_DROP_NOT_CROSSABLE at world_x=%.1f width=%.1f drop=%.1f run_off_reach=%.1f (speed=%.1f) required=%.1f" % [
					void_start_x, void_width, exit_drop, run_off_reach, min_speed, void_width + CHASM_DROP_CROSSING_MARGIN,
				])

			# The far lip must also arrive before FALL_DEATH_DEPTH does. Player.update_fall_death
			# measures against the far lip inside a drop void (get_pending_exit_drop_at_world_x),
			# so what this really asserts is that the drop is deep enough to be that reference --
			# a shallow drop under a wide void would put the player past the death depth while
			# still airborne over the void.
			var crossing_time: float = void_width / min_speed
			var depth_at_far_lip: float = 0.5 * Player.GRAVITY * pow(crossing_time, 2.0)
			if depth_at_far_lip > exit_drop + Player.FALL_DEATH_DEPTH:
				violations.append("CHASM_DROP_FALL_DEATH at world_x=%.1f width=%.1f drop=%.1f depth_at_far_lip=%.1f limit=%.1f" % [
					void_start_x, void_width, exit_drop, depth_at_far_lip, exit_drop + Player.FALL_DEATH_DEPTH,
				])

	return violations


func check_chasm_lip_vertices(terrain_generator: TerrainGenerator, lip_world_x: float) -> Array[String]:
	var violations: Array[String] = []
	var chunk_width: float = terrain_generator.chunk_width
	# A lip exactly on a chunk boundary is already a vertex of both chunks via the uniform
	# progress=0 / progress=1 samples, so only strictly-interior positions need checking.
	var chunk_index: int = int(floor(lip_world_x / chunk_width))
	var chunk_start_x: float = float(chunk_index) * chunk_width
	if is_equal_approx(lip_world_x, chunk_start_x):
		return violations

	terrain_generator.ensure_chunk_collision_samples(chunk_index)
	var sample_world_xs: PackedFloat64Array = terrain_generator.chunk_collision_sample_xs[chunk_index]
	for sample_world_x: float in sample_world_xs:
		if absf(sample_world_x - lip_world_x) <= CHASM_LIP_VERTEX_TOLERANCE_X:
			return violations

	violations.append("CHASM_COLLISION_NOT_CUT: no collision vertex on lip world_x=%.3f in chunk %d" % [lip_world_x, chunk_index])
	return violations


# The slowest speed the player can possibly have when reaching world_x.
#
# Conservative by construction: it assumes x-progress equals speed, but the grounded model
# advances x at speed * cos(slope), so the player actually arrives LATER and therefore FASTER
# than this. A speed boost only helps. Manual debug speed control can go below it, but that is
# gated on OS.is_debug_build() and is not a shipping path.
func get_min_speed_at_world_x(world_x: float) -> float:
	var phase1_distance: float = (SpeedManager.INITIAL_SPEED * SpeedManager.PHASE1_DURATION) + (0.5 * SpeedManager.PHASE1_ACCELERATION * pow(SpeedManager.PHASE1_DURATION, 2.0))
	if world_x <= phase1_distance:
		# 100t + 20t^2 = x
		var phase1_time: float = (-SpeedManager.INITIAL_SPEED + sqrt(pow(SpeedManager.INITIAL_SPEED, 2.0) + (2.0 * SpeedManager.PHASE1_ACCELERATION * world_x))) / SpeedManager.PHASE1_ACCELERATION
		return SpeedManager.INITIAL_SPEED + (SpeedManager.PHASE1_ACCELERATION * phase1_time)

	var phase2_distance: float = world_x - phase1_distance
	var phase2_time: float = (-SpeedManager.PHASE1_TARGET_SPEED + sqrt(pow(SpeedManager.PHASE1_TARGET_SPEED, 2.0) + (2.0 * SpeedManager.PHASE2_ACCELERATION * phase2_distance))) / SpeedManager.PHASE2_ACCELERATION
	return minf(SpeedManager.PHASE1_TARGET_SPEED + (SpeedManager.PHASE2_ACCELERATION * phase2_time), SpeedManager.MAX_SPEED)


# Horizontal distance covered by a jump taken from the near lip that ends exit_drop below it.
# The jump powerup only lengthens it, so ignoring it stays conservative HERE -- clearability is
# about the weakest jump. CHASM_LEAD_IN_TOO_SHORT wants the opposite bound and passes the
# multiplier explicitly.
func get_jump_reach(speed: float, exit_drop: float) -> float:
	return get_jump_reach_with_multiplier(speed, exit_drop, 1.0)


func get_jump_reach_with_multiplier(speed: float, exit_drop: float, jump_velocity_multiplier: float) -> float:
	return speed * get_jump_airtime(exit_drop, jump_velocity_multiplier)


# Solving 0.5 * GRAVITY * t^2 + JUMP_VELOCITY * t = exit_drop for the positive root; at
# exit_drop 0 and multiplier 1 this is the familiar 2 * 640 / 1600 = 0.8s.
func get_jump_airtime(exit_drop: float, jump_velocity_multiplier: float) -> float:
	var launch_speed: float = -Player.JUMP_VELOCITY * jump_velocity_multiplier
	return (launch_speed + sqrt(pow(launch_speed, 2.0) + (2.0 * Player.GRAVITY * exit_drop))) / Player.GRAVITY


func print_chasm_report(session_seed: int, chasm_report: Dictionary) -> void:
	var violation_count: int = int(chasm_report["violation_count"])
	print("TERRAIN_INVARIANT_CHASM seed=", session_seed,
		" status=", "PASS" if violation_count == 0 else "FAIL",
		" voids=", int(chasm_report["void_count"]),
		" first_x=%.1f" % float(chasm_report["first_void_x"]),
		" width=[%.3f, %.3f]" % [float(chasm_report["min_width"]), float(chasm_report["max_width"])],
		" spacing=[%.1f, %.1f]" % [float(chasm_report["min_spacing"]), float(chasm_report["max_spacing"])])

	var violations: Array = chasm_report["violations"]
	for violation: String in violations:
		print("    ", violation)
	if violation_count > violations.size():
		print("    ...and ", violation_count - violations.size(), " more")


func print_seed_report(session_seed: int, report: Dictionary, max_slope_angle: float) -> void:
	var violation_count: int = int(report["violation_count"])
	var status: String = "PASS" if violation_count == 0 else "FAIL"
	print("TERRAIN_INVARIANT_SEED seed=", session_seed,
		" status=", status,
		" samples=", int(report["sample_count"]),
		" violations=", violation_count,
		" max_slope=%.2fdeg" % rad_to_deg(float(report["worst_slope_angle"])),
		" at_world_x=%.1f" % float(report["worst_slope_world_x"]),
		" floor_max_angle=%.2fdeg" % rad_to_deg(max_slope_angle))

	var violations: Array = report["violations"]
	for violation: String in violations:
		print("    ", violation)
	if violation_count > violations.size():
		print("    ...and ", violation_count - violations.size(), " more")


func get_int_argument(argument_name: String, default_value: int) -> int:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_int()
	return default_value


func get_float_argument(argument_name: String, default_value: float) -> float:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_float()
	return default_value
