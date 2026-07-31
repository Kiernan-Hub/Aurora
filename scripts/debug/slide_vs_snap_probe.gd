extends SceneTree

# Diagnostic (2026-07-30), consumes the read-only instrumentation added to
# Player (debug_position_after_slide, debug_position_after_snap) to split each
# frame's vertical motion into two components:
#   slide_delta_y = position after move_and_slide() minus position before the step
#   snap_delta_y  = position after apply_grounded_floor_snap() minus after slide
# slide_delta_y + snap_delta_y == last_physics_displacement.y exactly (both are
# straight subtractions of the same global_position samples player.gd already takes).
#
# This follows two prior probes in this investigation:
#   - chord_aim_probe.gd: residual (actual vertical motion minus what the grounded
#     model commanded) scales with terrain curvature and is ~2.2x larger on frames
#     with no fresh slide collision than on frames with one.
#   - offset_curve_probe.gd: REFUTED the idea that this is capsule-on-polyline-vertex
#     geometry. Residual on "stable" frames (no bracket change, target curve provably
#     linear) is statistically equal to residual on transition frames -- ruling out
#     both the vertex-fillet and the r/cos(theta) resting-height models as sufficient
#     explanations, since a purely geometric account should be ~0 on stable frames.
#
# This probe asks the next direct question: is the correction coming from
# move_and_slide()'s own contact/slide resolution, or from the floor-snap step that
# runs after it? It also tracks get_slide_collision_count() and the exported
# floor_collision text per frame, per a gameplay-observed correlation: smooth
# sections apparently hold a STABLE slide_collision_count (0 or 1, never changing),
# while jittery sections show it flickering between 0 and 1 frame to frame. This is
# tested here as a candidate signature of the mechanism, not assumed.
#
# No player.gd behavior changes: the two fields this reads are pure position
# snapshots taken at existing call sites, added with zero control-flow change.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/slide_vs_snap_probe.gd -- \
#       --seeds=941462462,2160065702 --frames=20000 [--trace=small_hill --tracelines=40]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852"
const OUT_OF_SCOPE_LABEL: String = "mega_drop"


class LabelStats:
	var grounded_frames: int = 0
	var abs_slide_dy_sum: float = 0.0
	var abs_snap_dy_sum: float = 0.0
	var snap_nonzero_frames: int = 0
	var slide_only_frames: int = 0
	var snap_only_frames: int = 0
	var both_frames: int = 0
	var neither_frames: int = 0
	# Contact-report stability, per the gameplay observation: does
	# get_slide_collision_count() (0 or >0) change from the previous frame?
	var contact_flip_frames: int = 0
	var abs_slide_dy_sum_stable_contact: float = 0.0
	var samples_stable_contact: int = 0
	var abs_slide_dy_sum_flipped_contact: float = 0.0
	var samples_flipped_contact: int = 0
	var abs_snap_dy_sum_stable_contact: float = 0.0
	var abs_snap_dy_sum_flipped_contact: float = 0.0
	# slide_dy is dominated by the LEGITIMATE across-slope descent/climb, not error --
	# so the decisive numbers are the two residual components (deviation from the
	# tangent the grounded model actually commanded), which sum to exactly the
	# residual chord_aim_probe.gd already measured as one combined quantity.
	var residual_slide_sum: float = 0.0
	var residual_snap_sum: float = 0.0
	var residual_samples: int = 0
	var residual_slide_sum_stable_contact: float = 0.0
	var residual_slide_sum_flipped_contact: float = 0.0


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 20000)
	var trace_label: String = get_string_argument("--trace", "")
	var trace_lines: int = get_int_argument("--tracelines", 0)

	print("SLIDESNAP_BEGIN\tgodot=%s\tframes_per_seed=%d" % [
		Engine.get_version_info()["string"], frame_limit,
	])
	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		await run_seed(session_seed, frame_limit, trace_label, trace_lines)
	print("SLIDESNAP_END")
	quit(0)


func run_seed(session_seed: int, frame_limit: int, trace_label: String, trace_lines: int) -> void:
	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	root.add_child(main)
	await physics_frame

	var per_label: Dictionary = {}
	var trace_budget: int = trace_lines
	var previous_had_contact: bool = false
	var has_previous_contact_sample: bool = false
	var physics_delta: float = 1.0 / float(Engine.physics_ticks_per_second)

	for frame_index: int in range(frame_limit):
		var position_before_move: Vector2 = player.global_position
		# Same commanded-tangent model chord_aim_probe.gd validated: the angle
		# get_slope_tangent() actually reads at the top of THIS frame, before it moves.
		var commanded_angle: float = terrain_generator.get_collision_chord_slope_angle(position_before_move.x)
		var commanded_speed: float = player.speed_manager.current_speed
		await physics_frame

		var world_x: float = player.global_position.x
		var label: String = segment_label_at(terrain_generator, world_x)
		var is_grounded: bool = player.is_on_floor()
		var slide_collision_count: int = player.get_slide_collision_count()
		var has_contact: bool = slide_collision_count > 0

		if is_grounded and player.is_using_grounded_model:
			if not per_label.has(label):
				per_label[label] = LabelStats.new()
			var stats: LabelStats = per_label[label]
			stats.grounded_frames += 1

			var slide_dy: float = player.debug_position_after_slide.y - position_before_move.y
			var snap_dy: float = player.debug_position_after_snap.y - player.debug_position_after_slide.y
			var abs_slide_dy: float = absf(slide_dy)
			var abs_snap_dy: float = absf(snap_dy)
			# commanded_speed captured BEFORE the physics step ran this frame is what
			# get_slope_tangent() actually multiplied the tangent by (speed_manager
			# updates before velocity is computed, so this matches, not last frame's).
			var commanded_dy: float = sin(commanded_angle) * commanded_speed * physics_delta
			var residual_slide: float = slide_dy - commanded_dy
			var residual_snap: float = snap_dy

			stats.abs_slide_dy_sum += abs_slide_dy
			stats.abs_snap_dy_sum += abs_snap_dy
			stats.residual_slide_sum += absf(residual_slide)
			stats.residual_snap_sum += absf(residual_snap)
			stats.residual_samples += 1
			if not is_zero_approx(snap_dy):
				stats.snap_nonzero_frames += 1

			var slide_significant: bool = abs_slide_dy > 0.01
			var snap_significant: bool = abs_snap_dy > 0.01
			if slide_significant and snap_significant:
				stats.both_frames += 1
			elif slide_significant:
				stats.slide_only_frames += 1
			elif snap_significant:
				stats.snap_only_frames += 1
			else:
				stats.neither_frames += 1

			if has_previous_contact_sample:
				var contact_flipped: bool = has_contact != previous_had_contact
				if contact_flipped:
					stats.contact_flip_frames += 1
					stats.abs_slide_dy_sum_flipped_contact += abs_slide_dy
					stats.abs_snap_dy_sum_flipped_contact += abs_snap_dy
					stats.samples_flipped_contact += 1
					stats.residual_slide_sum_flipped_contact += absf(residual_slide)
				else:
					stats.abs_slide_dy_sum_stable_contact += abs_slide_dy
					stats.abs_snap_dy_sum_stable_contact += abs_snap_dy
					stats.samples_stable_contact += 1
					stats.residual_slide_sum_stable_contact += absf(residual_slide)

			if trace_budget > 0 and label == trace_label:
				trace_budget -= 1
				var floor_collision: Dictionary = player.get_floor_collision_data()
				var floor_collision_text: String = "none" if floor_collision.is_empty() else "x=%.2f" % (floor_collision["position"] as Vector2).x
				print("SLIDESNAP_TRACE\tx=%.3f\tslides=%d\tfloor_collision=%s\tslide_dy=%+.4f\tsnap_dy=%+.4f\tres_slide=%+.4f\tres_snap=%+.4f\tcontact_flip=%s" % [
					world_x, slide_collision_count, floor_collision_text, slide_dy, snap_dy,
					residual_slide, residual_snap,
					str(has_contact != previous_had_contact) if has_previous_contact_sample else "n/a",
				])

		previous_had_contact = has_contact
		has_previous_contact_sample = true

	print("SLIDESNAP_RESULT\tseed=%d\tdistance=%.0f" % [session_seed, player.global_position.x])
	print("    %-20s %8s %11s %10s %9s %9s %10s %10s %10s" % [
		"segment", "frames", "res_slide", "res_snap", "flipRate", "snapRate",
		"resSlide@flip", "resSlide@stbl", "flip/stbl",
	])
	var labels: Array = per_label.keys()
	labels.sort()
	for label: String in labels:
		var stats: LabelStats = per_label[label]
		var res_flip: float = ratio_float(stats.residual_slide_sum_flipped_contact, stats.samples_flipped_contact)
		var res_stable: float = ratio_float(stats.residual_slide_sum_stable_contact, stats.samples_stable_contact)
		print("    %-20s %8d %11.4f %10.4f %9.4f %9.4f %10.4f %10.4f %10.2f%s" % [
			label, stats.grounded_frames,
			ratio_float(stats.residual_slide_sum, stats.residual_samples),
			ratio_float(stats.residual_snap_sum, stats.residual_samples),
			ratio(stats.contact_flip_frames, stats.grounded_frames),
			ratio(stats.snap_nonzero_frames, stats.grounded_frames),
			res_flip, res_stable, res_flip / maxf(res_stable, 0.0001),
			"   (out of scope)" if label == OUT_OF_SCOPE_LABEL else "",
		])

	main.queue_free()
	await process_frame


func ratio(count: int, total: int) -> float:
	return float(count) / maxf(float(total), 1.0)


func ratio_float(total: float, count: int) -> float:
	return total / maxf(float(count), 1.0)


func segment_label_at(terrain_generator: TerrainGenerator, world_x: float) -> String:
	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	return terrain_generator.get_segment_selection_label(terrain_generator.find_segment_index_at_x(world_x))


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
