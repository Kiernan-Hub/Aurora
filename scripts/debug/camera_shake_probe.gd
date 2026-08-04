extends SceneTree

# Headless probe for the mega_drop / hill-crest "camera shake" reported in
# playtest (2026-08-01), measuring the quantity that actually corresponds to
# what the eye sees -- which the whole prior investigation was NOT measuring.
#
# WHY A NEW METRIC. Three rounds of probing (mega_drop_probe.gd, then
# mega_drop_visual_probe.gd twice) chased `contact_anomaly_len`: how far the
# reported KinematicCollision2D contact POINT moves versus the body. Every
# hypothesis built on it died (floor-snap, frame-timing hitch, segment-entry
# transition), and playtest reported the shake unchanged throughout. The
# playtest description is why: the sprite never loses contact and looks
# perfectly glued to the terrain at 45 degrees -- it is the whole VIEW that
# shakes. Sprite-vs-terrain agreement is a pure world-space relationship that
# never involves the camera, so it can look impeccable while the view judders.
# Contact-point reporting was never going to show that.
#
# WHAT ACTUALLY SHOWS IT. The terrain is static in world space, so the
# on-screen motion of the entire world IS the camera's per-frame displacement.
# Uneven camera displacement = the world scrolling at a stuttering rate =
# perceived shake. The metric is therefore the SECOND difference of camera
# position ("jerk"): the frame-to-frame change in scroll rate.
#
#     camera_delta[n] = camera_pos[n] - camera_pos[n-1]      (scroll rate)
#     camera_jerk[n]  = camera_delta[n] - camera_delta[n-1]  (change in it)
#
# Perfectly smooth scrolling has jerk 0. The only legitimate jerk is the speed
# ramp (ACCELERATION 3.2 px/s^2 => 3.2/3600 ~= 0.0009 px/frame^2), so anything
# above ~0.001 px/frame^2 is judder, not intended acceleration.
#
# ALTERNATION. Judder that reverses direction every frame is far more visible
# than the same magnitude drifting one way, so sign flips in camera_delta and
# the alternating fraction are tracked separately from raw magnitude.
#
# Also verifies the suspected one-frame camera lag directly (main.gd's camera
# update runs in Main._physics_process, and Main is the scene root, so it runs
# BEFORE the Player child moves): camera_x[n] should equal player_x[n-1].
#
# Usage (headless, no window needed):
#   Godot --headless --path . --script res://scripts/debug/camera_shake_probe.gd -- \
#       [--seed=941462462] [--frames=20000] [--top=12]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
# Below this, per-frame jerk is indistinguishable from the intended speed ramp
# (~0.0009 px/frame^2) plus float noise.
const JERK_NOISE_FLOOR: float = 0.001


class SegmentStats:
	var label: String = ""
	var frame_count: int = 0
	var jerk_x_sum: float = 0.0
	var jerk_x_max: float = 0.0
	var jerk_x_max_world_x: float = 0.0
	var jerk_y_sum: float = 0.0
	var jerk_y_max: float = 0.0
	# Frames whose camera_delta.x moved opposite to the previous frame's change
	# -- i.e. the scroll rate reversed direction, the visually loudest case.
	var alternating_x_count: int = 0
	var scroll_rate_min: float = 0.0
	var scroll_rate_max: float = 0.0
	var has_scroll_rate: bool = false
	# Correlation test for the grounded/airborne x-speed discontinuity: the
	# grounded model uses cos(slope)*speed and the airborne model uses the full
	# speed, so every floor-state flip steps the scroll rate by
	# (1 - cos(slope))*speed. If that is the mechanism, high-jerk frames should
	# be overwhelmingly floor-flip frames.
	var floor_flip_count: int = 0
	var high_jerk_count: int = 0
	var high_jerk_with_flip_count: int = 0

	func mean_jerk_x() -> float:
		return jerk_x_sum / maxf(float(frame_count), 1.0)

	func mean_jerk_y() -> float:
		return jerk_y_sum / maxf(float(frame_count), 1.0)

	func alternating_fraction() -> float:
		return float(alternating_x_count) / maxf(float(frame_count), 1.0)

	func floor_flip_fraction() -> float:
		return float(floor_flip_count) / maxf(float(frame_count), 1.0)

	func high_jerk_flip_fraction() -> float:
		return float(high_jerk_with_flip_count) / maxf(float(high_jerk_count), 1.0)


var main: Node
var player: Player
var terrain_generator: TerrainGenerator
var camera_2d: Camera2D

var frame_budget: int = 20000
var top_count: int = 12
var warmup_frames: int = 60

var segment_stats: Dictionary = {}
var worst_frames: Array[Dictionary] = []

var previous_camera_pos: Vector2 = Vector2.ZERO
var previous_camera_delta: Vector2 = Vector2.ZERO
var previous_player_x: float = 0.0
var have_previous_frame: bool = false
var have_previous_delta: bool = false
var previous_is_on_floor: bool = false
# A jerk this large cannot come from the speed ramp; used to select the
# "visible judder" population for the floor-flip correlation.
const HIGH_JERK_THRESHOLD: float = 0.1

# Direct check of the one-frame-stale camera hypothesis.
var lag_match_count: int = 0
var lag_sample_count: int = 0
var lag_max_error: float = 0.0
# How far the camera actually trails the player (player_x - camera_x). This is
# forward visibility given up, so it is the cost side of any smoothing.
var follow_distance_sum: float = 0.0
var follow_distance_max: float = 0.0
var follow_distance_count: int = 0


func _init() -> void:
	var seed_text: String = get_string_argument("--seed", "941462462")
	frame_budget = get_int_argument("--frames", 20000)
	top_count = get_int_argument("--top", 12)
	warmup_frames = get_int_argument("--warmup", 60)

	main = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = seed_text.to_int()
	# --smoothness=0 reproduces the pre-2026-08-01 rigid `camera.x = player.x`
	# follow, so before/after numbers come from the same binary and the same
	# seed rather than from a checkout swap.
	var smoothness_text: String = get_string_argument("--smoothness", "")
	if not smoothness_text.is_empty():
		(main as Main).camera_horizontal_smoothness = smoothness_text.to_float()
	(main as Main).camera_lead_enabled = get_int_argument("--lead", 1) != 0
	(main.get_node("GameManager") as GameManager).require_start_screen = false
	# Off explicitly, not just by default. This probe's entire subject is frame-to-frame
	# timing noise, and the instrumentation these gate is ~25 String allocations plus two
	# full floor-collision analyses per frame. As of 2026-08-03 both default to
	# OS.is_debug_build(), which is TRUE under this harness -- so without these two lines
	# the measurement carries the debug tax, exactly the trap the other gates avoid.
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	# ObstacleSpawner schedules clusters off Player.speed_manager.elapsed_time, and
	# this probe runs long enough (thousands of frames, no input) to reach the first
	# one. A collision would pause the tree via GameManager, freezing camera_x/
	# camera_y (Main._physics_process stops too) while this probe's own frame loop
	# keeps recording -- producing one huge fake jerk spike at the death frame, then
	# hundreds/thousands of frozen frames all misreported as one "segment" with
	# near-zero jerk. Disabled for the same reason freeze_search.gd disables it:
	# this measures camera-follow behavior against the terrain, not obstacle
	# gameplay. (Found via an 8.5 px/frame^2 spike with scroll_rate_x=0.0000 at
	# world_x=11356 in a 7000-frame run, which vanished when truncated to frames
	# before the first cluster's ~20s trigger.)
	# See freeze_search.gd for why this is debug_spawning_disabled, not
	# set_physics_process(false) -- the latter does not reliably work here (the
	# 8.5 px/frame^2 spike this comment block originally referenced was itself
	# caused by that fix being a no-op: the obstacle death still happened).
	(main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner).debug_spawning_disabled = true
	(main.get_node("TerrainGenerator/PowerupSpawner") as PowerupSpawner).debug_spawning_disabled = true
	# Chasms off by default for the same reason: a no-input run reaches one, runs off the lip
	# and dies, which pauses the tree and turns the rest of the run into frozen frames
	# misreported as one near-zero-jerk segment.
	#
	# --chasms=1 exists as an escape hatch, but note this probe drives NO input, so it cannot
	# jump a chasm -- an enabled run is only meaningful with --frames kept short enough to stop
	# before the first void (terrain_invariant_check reports each seed's first_x). The chasm
	# label itself is not really measurable here, and does not need to be: the lips are level,
	# so a landing produces no vertical camera step, and chasm_probe.gd already asserts landings
	# are clean.
	(main.get_node("TerrainGenerator") as TerrainGenerator).debug_chasm_disabled = get_int_argument("--chasms", 0) == 0
	# Natural default segment mix on purpose: the point is comparing shake
	# ACROSS segment types (playtest says flat is clean, gentle crests are a
	# tiny vertical shake, mega_drop is severe), which a forced single-segment
	# run cannot show.
	root.add_child(main)
	await physics_frame
	camera_2d = main.camera_2d

	print("CAMERA_SHAKE_PROBE_BEGIN seed=%s frames=%d horizontal_smoothness=%.2f" % [
		seed_text, frame_budget, (main as Main).camera_horizontal_smoothness,
	])
	for frame_index: int in range(frame_budget):
		await physics_frame
		# Skip the opening frames: a smoothed follow legitimately spends its
		# first frames falling back to its steady-state lag, and that one-time
		# transient is not the judder being measured.
		record_frame(frame_index >= warmup_frames)

	report()
	quit()


func record_frame(collect: bool) -> void:
	var camera_pos: Vector2 = camera_2d.global_position
	var player_x: float = player.global_position.x
	var is_on_floor: bool = player.is_on_floor()

	# Rebasing shifts camera and player by the same exact power-of-two amount,
	# so it cancels out of camera_delta -- except on the single frame it fires,
	# where it would read as a 1024px "jerk". Detect and skip those frames
	# rather than let one bookkeeping shift dominate every statistic.
	var is_rebase_frame: bool = false
	if have_previous_frame and absf(camera_pos.y - previous_camera_pos.y) > 512.0:
		is_rebase_frame = true

	if have_previous_frame and not is_rebase_frame:
		var camera_delta: Vector2 = camera_pos - previous_camera_pos
		if have_previous_delta and collect:
			var jerk: Vector2 = camera_delta - previous_camera_delta
			accumulate(player_x, camera_delta, jerk, is_on_floor != previous_is_on_floor)
		previous_camera_delta = camera_delta
		have_previous_delta = true

		# camera_x[n] should equal player_x[n-1] if the camera is reading a
		# pre-move player position (Main is the scene root, so its
		# _physics_process runs before the Player child's).
		var lag_error: float = absf(camera_pos.x - previous_player_x)
		lag_sample_count += 1
		lag_max_error = maxf(lag_max_error, lag_error)
		if lag_error < 0.0001:
			lag_match_count += 1

		if collect:
			var follow_distance: float = player_x - camera_pos.x
			follow_distance_sum += follow_distance
			follow_distance_max = maxf(follow_distance_max, follow_distance)
			follow_distance_count += 1
	elif is_rebase_frame:
		have_previous_delta = false

	previous_camera_pos = camera_pos
	previous_player_x = player_x
	previous_is_on_floor = is_on_floor
	have_previous_frame = true


func accumulate(player_x: float, camera_delta: Vector2, jerk: Vector2, floor_state_flipped: bool) -> void:
	var label: String = get_segment_label_at(player_x)
	if not segment_stats.has(label):
		var created: SegmentStats = SegmentStats.new()
		created.label = label
		segment_stats[label] = created
	var stats: SegmentStats = segment_stats[label]

	var jerk_x: float = absf(jerk.x)
	var jerk_y: float = absf(jerk.y)
	stats.frame_count += 1
	stats.jerk_x_sum += jerk_x
	if jerk_x > stats.jerk_x_max:
		stats.jerk_x_max = jerk_x
		stats.jerk_x_max_world_x = player_x
	stats.jerk_y_sum += jerk_y
	stats.jerk_y_max = maxf(stats.jerk_y_max, jerk_y)
	if jerk.x * previous_camera_delta.x < 0.0 and jerk_x > JERK_NOISE_FLOOR:
		stats.alternating_x_count += 1
	if floor_state_flipped:
		stats.floor_flip_count += 1
	if jerk_x > HIGH_JERK_THRESHOLD:
		stats.high_jerk_count += 1
		if floor_state_flipped:
			stats.high_jerk_with_flip_count += 1
	if not stats.has_scroll_rate:
		stats.scroll_rate_min = camera_delta.x
		stats.scroll_rate_max = camera_delta.x
		stats.has_scroll_rate = true
	else:
		stats.scroll_rate_min = minf(stats.scroll_rate_min, camera_delta.x)
		stats.scroll_rate_max = maxf(stats.scroll_rate_max, camera_delta.x)

	worst_frames.append({
		"world_x": player_x,
		"label": label,
		"jerk_x": jerk_x,
		"jerk_y": jerk_y,
		"jerk_len": jerk.length(),
		"scroll_rate": camera_delta.x,
	})


func get_segment_label_at(world_x: float) -> String:
	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	var segment_index: int = terrain_generator.find_segment_index_at_x(world_x)
	return String(terrain_generator.get_segment_spec(segment_index)["label"])


func report() -> void:
	print("")
	print("=== CAMERA ONE-FRAME LAG CHECK ===")
	var lag_fraction: float = float(lag_match_count) / maxf(float(lag_sample_count), 1.0)
	print("camera_x[n] == player_x[n-1] on %d/%d frames (%.1f%%), max error %.6f px" % [
		lag_match_count, lag_sample_count, lag_fraction * 100.0, lag_max_error,
	])
	print("follow distance (player_x - camera_x): mean %.2f px, max %.2f px" % [
		follow_distance_sum / maxf(float(follow_distance_count), 1.0), follow_distance_max,
	])

	print("")
	print("=== CAMERA JERK BY SEGMENT (px/frame^2; smooth scrolling == 0) ===")
	print("%-20s %7s %11s %10s %13s %9s %s" % [
		"segment", "frames", "mean_jerk_x", "max_jerk_x", "at_world_x", "alt_frac", "scroll_rate_x range",
	])
	var labels: Array = segment_stats.keys()
	labels.sort()
	for label: String in labels:
		var stats: SegmentStats = segment_stats[label]
		print("%-20s %7d %11.5f %10.5f @x=%-10.0f %8.1f%% %.4f .. %.4f" % [
			stats.label, stats.frame_count,
			stats.mean_jerk_x(), stats.jerk_x_max, stats.jerk_x_max_world_x,
			stats.alternating_fraction() * 100.0,
			stats.scroll_rate_min, stats.scroll_rate_max,
		])

	worst_frames.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["jerk_len"]) > float(b["jerk_len"]))
	print("")
	print("=== WORST %d FRAMES BY CAMERA JERK ===" % top_count)
	for frame_index: int in range(mini(top_count, worst_frames.size())):
		var entry: Dictionary = worst_frames[frame_index]
		print("world_x=%10.2f  %-20s jerk=(%.5f, %.5f)  scroll_rate_x=%.4f" % [
			float(entry["world_x"]), String(entry["label"]),
			float(entry["jerk_x"]), float(entry["jerk_y"]), float(entry["scroll_rate"]),
		])
	print("")
	print("CAMERA_SHAKE_PROBE_END")


func get_string_argument(argument_name: String, default_value: String) -> String:
	var prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return default_value


func get_int_argument(argument_name: String, default_value: int) -> int:
	var raw_value: String = get_string_argument(argument_name, "")
	if raw_value.is_empty():
		return default_value
	return raw_value.to_int()
