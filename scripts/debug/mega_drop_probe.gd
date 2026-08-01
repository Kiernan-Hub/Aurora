extends SceneTree

# Read-only measurement probe for the "smooth first half, shaky second half" report
# on the ~40.5 degree mega_drop segment (2026-07-31 investigation). Deliberately NOT
# a continuation of docs/research/terrain_jitter.md: that investigation's headline
# metric (sign-reversal rate of frame-to-frame delta_y) is structurally blind on a
# fast descent -- at ~3.2px/frame of sustained downward motion, a sub-pixel
# correction cannot flip the sign -- and every metric in that investigation and in
# jitter_frequency_probe.gd is vertical-only. Nothing in this repo has ever
# differenced player.global_position.x. This probe does not assume the cause; it
# reports raw per-axis numbers for four candidate mechanisms and leaves attribution
# to whoever reads the output.
#
# Candidates instrumented here (see the plan doc for the reasoning):
#   H1 horizontal CharacterBody2D depenetration (move_and_slide's own contact
#      correction, split from the requested step)
#   H2 camera hard-lock transmitting body motion 1:1 to the screen
#   H3 sprite (ColorRect) rotation jitter, independent of ground contact
#   H4 collision-chord quantization (the 16px chord's angle steps every ~4 frames)
# plus the previously-investigated H5 (vertical solver correction) and an explicit
# "other" bucket: absolute magnitudes are printed for everything so a mechanism this
# list didn't anticipate is still visible in the numbers.
#
# mega_drop's shape (evaluate_segment_offset / get_transition_profile in
# terrain_generator.gd) is symmetric in SLOPE but not in CURVATURE: the first half
# (progress < 0.5) is convex -- terrain falls away from a straight step -- and the
# second half is concave -- terrain flattens INTO a straight step, which is exactly
# the geometry that forces move_and_slide() to depenetrate the capsule out of the
# surface every frame. That is the whole reason this probe bins by decile of
# progress through the segment instead of pooling the segment like every prior
# probe: pooling front and back halves together is what let mega_drop read as
# "quiet" before.
#
# One timing fact that matters for reading the camera columns: Main._physics_process
# runs BEFORE Player/TerrainGenerator in sibling order (see main.gd's own comment),
# so each frame's camera_2d.global_position.x is set from the PREVIOUS frame's
# already-settled player.x, not this frame's. Camera x is therefore always exactly
# one physics frame stale, not smoothed -- "screen offset" below
# (player.global_position - camera_2d.global_position) is this frame's raw motion,
# visible on screen regardless of anything the camera itself does.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/mega_drop_probe.gd -- \
#       --seeds=941462462,2160065702,3188032853,222894852 --frames=9000 \
#       [--megadroponly=1] [--speed=0] [--deciles=10]
#
#   --megadroponly=1 (default) zeroes every debug_weight_* except mega_drop so the
#     generated world is back-to-back mega_drop segments -- thousands of binned
#     samples from a short run. The per-segment shape is a pure function of its own
#     spec regardless of what else is in the world, so this cannot manufacture the
#     effect; run with --megadroponly=0 to confirm against the natural mix.
#   --speed=N pins speed_manager.current_speed to N every frame (0 = normal ramp).
#     Depenetration magnitude (H1) and chord-quantization magnitude (H4) are
#     expected to scale differently with speed, which is how this probe tells them
#     apart without touching player.gd.
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852"
# Approximate distance from the ColorRect's pivot (its own center, per player.gd's
# _ready) to a corner, for converting rotation jitter into a comparable px figure:
# corner_displacement ≈ r * |delta_rotation|. Rect is 32x48 (see player.tscn); half
# diagonal = sqrt(16^2+24^2) ≈ 28.8.
const ROTATION_CORNER_RADIUS: float = 28.8
const ROTATION_CLAMP_EPSILON: float = 0.0005
const CHORD_ANGLE_EPSILON: float = 0.00005


class BinStats:
	var frames: int = 0
	var airborne_frames: int = 0
	var grounded_frames: int = 0

	var requested_dx_abs_sum: float = 0.0
	var requested_dy_abs_sum: float = 0.0

	# H1/H5: move_and_slide()'s own correction, split from the requested step.
	var slide_dx_abs_sum: float = 0.0
	var slide_dy_abs_sum: float = 0.0
	var slide_dx_reversals: int = 0
	var slide_dx_reversal_samples: int = 0
	var slide_dy_reversals: int = 0
	var slide_dy_reversal_samples: int = 0
	var slide_collision_count_sum: int = 0

	# The forced sub-pixel floor snap (apply_grounded_floor_snap), separate from slide.
	var snap_dx_abs_sum: float = 0.0
	var snap_dy_abs_sum: float = 0.0

	# H2: camera motion and the resulting on-screen player offset.
	var cam_dx_abs_sum: float = 0.0
	var cam_dx2_abs_sum: float = 0.0
	var cam_dx_reversals: int = 0
	var cam_dx_reversal_samples: int = 0
	var screen_offset_dx_abs_sum: float = 0.0
	var screen_offset_dx2_abs_sum: float = 0.0

	# H3: sprite rotation.
	var rotation_delta_abs_sum: float = 0.0
	var rotation_delta2_abs_sum: float = 0.0
	var rotation_reversals: int = 0
	var rotation_reversal_samples: int = 0
	var rotation_clamped_frames: int = 0
	var corner_displacement_abs_sum: float = 0.0

	# H4: collision-chord angle quantization (proxied by the grounded velocity angle,
	# which IS the chord angle used to aim that frame's step -- see get_slope_tangent).
	var chord_crossings: int = 0
	var chord_angle_step_abs_sum: float = 0.0

	# Contact quality, for cross-checking against the H1-H5 story.
	var gap_sum: float = 0.0
	var gap_delta_abs_sum: float = 0.0
	var gap_delta_samples: int = 0

	# Floor normal angle (get_floor_normal(), Godot's own resolved contact normal --
	# distinct from the analytic slope H3 uses and the collision-chord angle H4
	# uses: this is what move_and_slide() itself believes the surface direction was
	# THIS frame, after resolving contact).
	var floor_normal_delta_abs_sum: float = 0.0
	var floor_normal_reversals: int = 0
	var floor_normal_reversal_samples: int = 0


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 9000)
	var mega_drop_only: bool = get_int_argument("--megadroponly", 1) != 0
	var pinned_speed: float = get_float_argument("--speed", 0.0)
	var decile_count: int = get_int_argument("--deciles", 10)

	print("MEGA_DROP_BEGIN\tgodot=%s\tframes_per_seed=%d\tmegadroponly=%s\tpinned_speed=%.1f\tdeciles=%d" % [
		Engine.get_version_info()["string"], frame_limit, str(mega_drop_only), pinned_speed, decile_count,
	])

	var totals: Dictionary = {}
	var total_recoveries: int = 0
	var total_stuck: int = 0
	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		var result: Dictionary = await run_seed(session_seed, frame_limit, mega_drop_only, pinned_speed, decile_count, totals)
		total_recoveries += int(result["recoveries"])
		total_stuck += int(result["stuck"])

	print("MEGA_DROP_SUMMARY  (all seeds pooled, recoveries=%d stuck=%d)" % [total_recoveries, total_stuck])
	print("    %-16s %6s %6s %9s %9s | %9s %9s %7s %7s | %9s %9s | %9s %9s %7s %9s %9s | %9s %9s %7s %9s | %6s %9s | %9s %9s | %9s %7s" % [
		"bin", "frames", "air%", "req|dx|", "req|dy|",
		"slide|dx|", "slide|dy|", "sl_dx%", "sl_dy%",
		"snap|dx|", "snap|dy|",
		"cam|dx|", "cam|d2x|", "cam_rev", "scrn|dx|", "scrn|d2x|",
		"rot|d|", "rot|d2|", "rot_rev", "clamp%",
		"chords", "ch|dth|",
		"gap", "gap|d|",
		"fn|d|", "fn_rev",
	])
	var bin_keys: Array = totals.keys()
	bin_keys.sort_custom(func(a: String, b: String) -> bool: return bin_sort_key(a) < bin_sort_key(b))
	for bin_key: String in bin_keys:
		var stats: BinStats = totals[bin_key]
		print("    %-16s %6d %6.1f %9.4f %9.4f | %9.4f %9.4f %7.1f %7.1f | %9.4f %9.4f | %9.4f %9.4f %7.3f %9.4f %9.4f | %9.5f %9.5f %7.3f %9.1f | %6d %9.5f | %9.4f %9.4f | %9.5f %7.3f" % [
			bin_key, stats.frames,
			100.0 * ratio(stats.airborne_frames, stats.frames),
			ratio_float(stats.requested_dx_abs_sum, stats.frames),
			ratio_float(stats.requested_dy_abs_sum, stats.frames),
			ratio_float(stats.slide_dx_abs_sum, stats.frames),
			ratio_float(stats.slide_dy_abs_sum, stats.frames),
			100.0 * safe_div(stats.slide_dx_abs_sum, stats.requested_dx_abs_sum),
			100.0 * safe_div(stats.slide_dy_abs_sum, stats.requested_dy_abs_sum),
			ratio_float(stats.snap_dx_abs_sum, stats.frames),
			ratio_float(stats.snap_dy_abs_sum, stats.frames),
			ratio_float(stats.cam_dx_abs_sum, stats.frames),
			ratio_float(stats.cam_dx2_abs_sum, stats.frames),
			ratio(stats.cam_dx_reversals, stats.cam_dx_reversal_samples),
			ratio_float(stats.screen_offset_dx_abs_sum, stats.frames),
			ratio_float(stats.screen_offset_dx2_abs_sum, stats.frames),
			ratio_float(stats.rotation_delta_abs_sum, stats.grounded_frames),
			ratio_float(stats.rotation_delta2_abs_sum, stats.grounded_frames),
			ratio(stats.rotation_reversals, stats.rotation_reversal_samples),
			100.0 * ratio(stats.rotation_clamped_frames, stats.grounded_frames),
			stats.chord_crossings,
			ratio_float(stats.chord_angle_step_abs_sum, maxi(stats.chord_crossings, 1)),
			ratio_float(stats.gap_sum, stats.grounded_frames),
			ratio_float(stats.gap_delta_abs_sum, stats.gap_delta_samples),
			ratio_float(stats.floor_normal_delta_abs_sum, stats.floor_normal_reversal_samples),
			ratio(stats.floor_normal_reversals, stats.floor_normal_reversal_samples),
		])
	print("MEGA_DROP_END")
	quit(0)


func run_seed(session_seed: int, frame_limit: int, mega_drop_only: bool, pinned_speed: float, decile_count: int, totals: Dictionary) -> Dictionary:
	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	if mega_drop_only:
		terrain_generator.debug_weight_flat = 0
		terrain_generator.debug_weight_small_hill = 0
		terrain_generator.debug_weight_medium_hill_valley_mix = 0
		terrain_generator.debug_weight_big_downhill = 0
		terrain_generator.debug_weight_gentle_uphill = 0
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	root.add_child(main)
	await physics_frame

	var camera_2d: Camera2D = main.camera_2d
	# SceneTree has no get_physics_process_delta_time(); physics is fixed-tick (see
	# CLAUDE.md: "physics 60 Hz"), so derive delta from the tick rate instead.
	var physics_delta: float = 1.0 / float(Engine.get_physics_ticks_per_second())

	var previous_rebase_total: float = 0.0
	var previous_recovery_count: int = 0
	var has_previous_cam: bool = false
	var previous_cam_x: float = 0.0
	var previous_cam_dx: float = 0.0
	var has_previous_cam_dx: bool = false
	var previous_screen_offset_x: float = 0.0
	var previous_screen_offset_dx: float = 0.0
	var has_previous_screen_offset_dx: bool = false
	var has_previous_rotation: bool = false
	var previous_rotation: float = 0.0
	var previous_rotation_delta: float = 0.0
	var has_previous_rotation_delta: bool = false
	var has_previous_slide_dx: bool = false
	var previous_slide_dx: float = 0.0
	var has_previous_slide_dy: bool = false
	var previous_slide_dy: float = 0.0
	var has_previous_chord_angle: bool = false
	var previous_chord_angle: float = 0.0
	var previous_gap: float = 0.0
	var has_previous_gap: bool = false
	var has_previous_floor_normal_angle: bool = false
	var previous_floor_normal_angle: float = 0.0
	var previous_floor_normal_delta: float = 0.0
	var has_previous_floor_normal_delta: bool = false

	for frame_index: int in range(frame_limit):
		if pinned_speed > 0.0:
			player.speed_manager.current_speed = pinned_speed
		await physics_frame

		var discontinuity: bool = (
			not is_equal_approx(main.total_world_rebase_shift, previous_rebase_total)
			or player.debug_stall_recovery_count != previous_recovery_count
		)
		previous_rebase_total = main.total_world_rebase_shift
		previous_recovery_count = player.debug_stall_recovery_count

		var world_x: float = player.global_position.x
		terrain_generator.ensure_segment_cache_for_world_x(world_x)
		var segment_index: int = terrain_generator.find_segment_index_at_x(world_x)
		var spec: Dictionary = terrain_generator.get_segment_spec(segment_index)
		var label: String = String(spec["label"])
		var bin_key: String = resolve_bin_key(label, world_x, terrain_generator, segment_index, spec, decile_count)
		if bin_key.is_empty():
			continue

		if not totals.has(bin_key):
			totals[bin_key] = BinStats.new()
		var stats: BinStats = totals[bin_key]
		stats.frames += 1

		var grounded: bool = player.is_on_floor()
		if grounded:
			stats.grounded_frames += 1
		else:
			stats.airborne_frames += 1

		# --- H1/H5: split this frame's motion into requested vs. slide-correction vs.
		# snap-correction, entirely from same-frame Player fields (immune to world
		# rebase, which shifts pre-move and post-move positions by the same amount).
		var position_before_move: Vector2 = player.debug_position_after_snap - player.last_physics_displacement
		var requested_step: Vector2 = player.debug_velocity_before_slide * physics_delta
		var slide_correction: Vector2 = (player.debug_position_after_slide - position_before_move) - requested_step
		var snap_correction: Vector2 = player.debug_position_after_snap - player.debug_position_after_slide

		stats.requested_dx_abs_sum += absf(requested_step.x)
		stats.requested_dy_abs_sum += absf(requested_step.y)
		stats.slide_dx_abs_sum += absf(slide_correction.x)
		stats.slide_dy_abs_sum += absf(slide_correction.y)
		stats.snap_dx_abs_sum += absf(snap_correction.x)
		stats.snap_dy_abs_sum += absf(snap_correction.y)
		stats.slide_collision_count_sum += player.get_slide_collision_count()

		if has_previous_slide_dx:
			stats.slide_dx_reversal_samples += 1
			if signf(slide_correction.x) != signf(previous_slide_dx) and not is_zero_approx(slide_correction.x) and not is_zero_approx(previous_slide_dx):
				stats.slide_dx_reversals += 1
		previous_slide_dx = slide_correction.x
		has_previous_slide_dx = true

		if has_previous_slide_dy:
			stats.slide_dy_reversal_samples += 1
			if signf(slide_correction.y) != signf(previous_slide_dy) and not is_zero_approx(slide_correction.y) and not is_zero_approx(previous_slide_dy):
				stats.slide_dy_reversals += 1
		previous_slide_dy = slide_correction.y
		has_previous_slide_dy = true

		# --- H2: camera motion and on-screen player offset (see file header re: the
		# one-frame camera-x lag from sibling processing order).
		var cam_x: float = camera_2d.global_position.x
		var screen_offset_x: float = player.global_position.x - cam_x

		if discontinuity:
			has_previous_cam = false
			has_previous_cam_dx = false
			has_previous_screen_offset_dx = false
		if has_previous_cam:
			var cam_dx: float = cam_x - previous_cam_x
			stats.cam_dx_abs_sum += absf(cam_dx)
			if has_previous_cam_dx:
				stats.cam_dx_reversal_samples += 1
				stats.cam_dx2_abs_sum += absf(cam_dx - previous_cam_dx)
				if signf(cam_dx) != signf(previous_cam_dx) and not is_zero_approx(cam_dx) and not is_zero_approx(previous_cam_dx):
					stats.cam_dx_reversals += 1
			previous_cam_dx = cam_dx
			has_previous_cam_dx = true
		previous_cam_x = cam_x
		has_previous_cam = true

		if has_previous_screen_offset_dx:
			var screen_dx: float = screen_offset_x - previous_screen_offset_x
			stats.screen_offset_dx_abs_sum += absf(screen_dx)
			stats.screen_offset_dx2_abs_sum += absf(screen_dx - previous_screen_offset_dx)
			previous_screen_offset_dx = screen_dx
		previous_screen_offset_x = screen_offset_x
		has_previous_screen_offset_dx = true

		# --- H3: sprite rotation (recompute the same target the player logic uses,
		# purely for the clamp-engagement reading -- rotation itself is read directly).
		var rotation: float = player.color_rect.rotation
		if discontinuity:
			has_previous_rotation = false
			has_previous_rotation_delta = false
		if grounded:
			var target_angle: float = terrain_generator.get_slope_angle_at_x(world_x)
			if absf(rotation - target_angle) < ROTATION_CLAMP_EPSILON:
				stats.rotation_clamped_frames += 1
		if has_previous_rotation:
			var rotation_delta: float = rotation - previous_rotation
			stats.rotation_delta_abs_sum += absf(rotation_delta)
			stats.corner_displacement_abs_sum += ROTATION_CORNER_RADIUS * absf(rotation_delta)
			if has_previous_rotation_delta:
				stats.rotation_reversal_samples += 1
				stats.rotation_delta2_abs_sum += absf(rotation_delta - previous_rotation_delta)
				if signf(rotation_delta) != signf(previous_rotation_delta) and not is_zero_approx(rotation_delta) and not is_zero_approx(previous_rotation_delta):
					stats.rotation_reversals += 1
			previous_rotation_delta = rotation_delta
			has_previous_rotation_delta = true
		previous_rotation = rotation
		has_previous_rotation = true

		# --- H4: chord angle, proxied by the grounded velocity heading (exactly what
		# get_slope_tangent() aimed this frame's requested step along).
		if grounded and player.is_using_grounded_model:
			var chord_angle: float = atan2(player.debug_velocity_before_slide.y, player.debug_velocity_before_slide.x)
			if has_previous_chord_angle and absf(chord_angle - previous_chord_angle) > CHORD_ANGLE_EPSILON:
				stats.chord_crossings += 1
				stats.chord_angle_step_abs_sum += absf(chord_angle - previous_chord_angle)
			previous_chord_angle = chord_angle
			has_previous_chord_angle = true

		# --- floor normal: Godot's own resolved contact direction this frame, as
		# distinct from the analytic slope (H3) and the collision-chord heading (H4)
		# -- this is what move_and_slide() decided the surface was, after resolving
		# whatever contact/penetration it found.
		if discontinuity:
			has_previous_floor_normal_angle = false
			has_previous_floor_normal_delta = false
		if grounded:
			var floor_normal: Vector2 = player.get_floor_normal()
			var floor_normal_angle: float = atan2(floor_normal.y, floor_normal.x)
			if has_previous_floor_normal_angle:
				var floor_normal_delta: float = angle_difference(previous_floor_normal_angle, floor_normal_angle)
				stats.floor_normal_delta_abs_sum += absf(floor_normal_delta)
				stats.floor_normal_reversal_samples += 1
				if has_previous_floor_normal_delta:
					if signf(floor_normal_delta) != signf(previous_floor_normal_delta) and not is_zero_approx(floor_normal_delta) and not is_zero_approx(previous_floor_normal_delta):
						stats.floor_normal_reversals += 1
				previous_floor_normal_delta = floor_normal_delta
				has_previous_floor_normal_delta = true
			previous_floor_normal_angle = floor_normal_angle
			has_previous_floor_normal_angle = true
		else:
			has_previous_floor_normal_angle = false
			has_previous_floor_normal_delta = false

		# --- contact quality cross-check.
		var surface_gap: float = (player.global_position.y + player.capsule_half_height) - terrain_generator.get_surface_world_y(world_x)
		if grounded:
			stats.gap_sum += surface_gap
		if has_previous_gap and not discontinuity:
			stats.gap_delta_abs_sum += absf(surface_gap - previous_gap)
			stats.gap_delta_samples += 1
		previous_gap = surface_gap
		has_previous_gap = true

	print("MEGA_DROP_RESULT\tseed=%d\tdistance=%.0f\trecoveries=%d\tstuck=%d" % [
		session_seed, player.global_position.x, player.debug_stall_recovery_count, player.debug_stuck_event_count,
	])
	var result: Dictionary = {
		"recoveries": player.debug_stall_recovery_count,
		"stuck": player.debug_stuck_event_count,
	}
	main.queue_free()
	await process_frame
	return result


func resolve_bin_key(label: String, world_x: float, terrain_generator: TerrainGenerator, segment_index: int, spec: Dictionary, decile_count: int) -> String:
	if label == "mega_drop":
		var segment_start_x: float = terrain_generator.segment_start_x_cache[segment_index]
		var segment_length: float = float(spec["length"])
		var progress: float = (world_x - segment_start_x) / segment_length
		var decile: int = clampi(int(progress * float(decile_count)), 0, decile_count - 1)
		return "mega_drop:%02d" % decile
	if label == "sustained_downhill" or label == "flat":
		return label
	return ""


func bin_sort_key(bin_key: String) -> String:
	# Sorts mega_drop:00..mega_drop:09 in numeric order (not lexicographic, which
	# would already work for 2-digit deciles, but keeps this correct if --deciles
	# is raised past 2 digits) and pushes the whole-segment controls after it.
	if bin_key.begins_with("mega_drop:"):
		var decile_text: String = bin_key.trim_prefix("mega_drop:")
		return "0_%04d" % decile_text.to_int()
	return "1_" + bin_key


func ratio(count: int, total: int) -> float:
	return float(count) / maxf(float(total), 1.0)


func ratio_float(total: float, count: int) -> float:
	return total / maxf(float(count), 1.0)


func safe_div(numerator: float, denominator: float) -> float:
	if is_zero_approx(denominator):
		return 0.0
	return numerator / denominator


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


func get_float_argument(argument_name: String, default_value: float) -> float:
	var raw_value: String = get_string_argument(argument_name, "")
	if raw_value.is_empty():
		return default_value
	return raw_value.to_float()
