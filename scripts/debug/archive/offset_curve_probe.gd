extends SceneTree

# Diagnostic (2026-07-30), read-only. Follow-up to scripts/debug/chord_aim_probe.gd:
# that probe found the residual sub-pixel bounce (post is_on_floor() flicker fix,
# cb8998b) scales with terrain CURVATURE, not steepness or collision-polyline
# resolution, and is carried by frames where move_and_slide() finds no fresh
# collision (floor-snap re-seats the body instead). An "aim along the step's
# endpoint chord instead of a single start tangent" fix was tried on that theory and
# measured to NOT work (see the ALSO TRIED note on Player.get_slope_tangent()) --
# proof the simple tangent-averaging model isn't the exact quantity being corrected.
#
# WHAT THIS PROBE TESTS: not a tangent/velocity model at all, but the exact
# equilibrium GEOMETRY of a capsule (radius r) resting on a piecewise-linear
# collision polyline. For a line through (left_x,left_h)-(right_x,right_h) at angle
# theta = atan2(right_h-left_h, right_x-left_x), a circle of radius r resting on top
# of it has:
#   contact_x  = center_x - r*sin(theta)      [already confirmed by chord_aim_probe:
#                                               obs_off matches pred_off]
#   center_y   = line_h_at(center_x) - r/cos(theta)
# (derivation: contact point lies ON the line; center = contact + r*up_normal, where
# up_normal = (sin theta, -cos theta); substituting and simplifying the sin/cos terms
# via sin^2+cos^2=1 gives the r/cos(theta) form -- this is the "CLAUDE.md hypothesis
# 2" that chord_aim_probe's plan flagged but never isolated cleanly, since that probe
# always compared against tangent-based predictions, not this exact target height.)
#
# This defines a continuous "offset curve" target_y(x) EXCEPT at polyline vertices,
# where the bracketing segment (and therefore theta and the line itself) changes
# discontinuously -- a real, unavoidable feature of a circle rolling over a polygon,
# not a bug by itself. The question this probe answers: does Godot's actual solver
# (move_and_slide + floor snap) track this curve smoothly within a segment and only
# jump at the true vertex crossings (meaning the bounce is real, inherent capsule
# geometry -- not fixable by changing player.gd's velocity aim), or does it deviate
# from the curve even mid-segment (meaning something else, not geometry, is doing the
# correcting)?
#
# Per grounded frame, with both endpoints of the step evaluated on their OWN natural
# bracket (so the curve is genuinely pointwise, discontinuities included):
#   predicted_delta_y = target_y(world_x_now) - target_y(world_x_prev)
#   offset_residual   = actual last_physics_displacement.y - predicted_delta_y
#   segment_transition = bracket differs between world_x_prev and world_x_now
#
# EXPECTED IF THE BOUNCE IS INHERENT CIRCLE-ON-POLYLINE GEOMETRY (not a code bug):
#   offset_residual ~= 0 on BOTH transition and non-transition frames (Godot's own
#   contact resolution already tracks this curve correctly, vertices included).
# EXPECTED IF IT IS SPECIFICALLY A VERTEX-CROSSING ARTIFACT (fixable, e.g. by
#   substepping or floor_snap_length):
#   offset_residual ~= 0 on non-transition frames, large only at segment_transition.
# EXPECTED IF GODOT ISN'T TRACKING r/cos(theta) AT ALL (fixable at the source, e.g.
#   correcting get_slope_tangent's reference height, not just its angle):
#   offset_residual is elevated on BOTH transition and non-transition frames within
#   curved segments, and near-zero on flat / constant-slope segments.
#
# No player.gd or terrain_generator.gd code is touched by this probe.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/archive/offset_curve_probe.gd -- \
#       --seeds=941462462,2160065702 --frames=20000 [--trace=small_hill --tracelines=40]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852"
const OUT_OF_SCOPE_LABEL: String = "mega_drop"


class LabelStats:
	var grounded_frames: int = 0
	var valid_samples: int = 0
	var transition_frames: int = 0
	var residual_sum_transition: float = 0.0
	var residual_samples_transition: int = 0
	var residual_sum_stable: float = 0.0
	var residual_samples_stable: int = 0
	var theta_jump_sum: float = 0.0


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 20000)
	var trace_label: String = get_string_argument("--trace", "")
	var trace_lines: int = get_int_argument("--tracelines", 0)

	print("OFFSET_BEGIN\tgodot=%s\tframes_per_seed=%d" % [
		Engine.get_version_info()["string"], frame_limit,
	])
	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		await run_seed(session_seed, frame_limit, trace_label, trace_lines)
	print("OFFSET_END")
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

	var capsule_radius: float = get_capsule_radius(player)
	var per_label: Dictionary = {}
	var trace_budget: int = trace_lines
	var previous_world_x: float = player.global_position.x
	var previous_grounded_model: bool = player.is_using_grounded_model
	var has_previous_frame: bool = false

	for frame_index: int in range(frame_limit):
		await physics_frame

		var world_x: float = player.global_position.x
		var label: String = segment_label_at(terrain_generator, world_x)
		var is_grounded: bool = player.is_on_floor()

		if is_grounded:
			if not per_label.has(label):
				per_label[label] = LabelStats.new()
			var stats: LabelStats = per_label[label]
			stats.grounded_frames += 1

			if has_previous_frame and previous_grounded_model:
				var now: Dictionary = offset_curve_target(terrain_generator, capsule_radius, world_x)
				var prev: Dictionary = offset_curve_target(terrain_generator, capsule_radius, previous_world_x)
				var predicted_delta_y: float = now["target_y"] - prev["target_y"]
				var offset_residual: float = player.last_physics_displacement.y - predicted_delta_y
				var is_transition: bool = now["bracket_left_x"] != prev["bracket_left_x"]

				stats.valid_samples += 1
				if is_transition:
					stats.transition_frames += 1
					stats.residual_sum_transition += absf(offset_residual)
					stats.residual_samples_transition += 1
					stats.theta_jump_sum += absf(rad_to_deg(now["theta"] - prev["theta"]))
				else:
					stats.residual_sum_stable += absf(offset_residual)
					stats.residual_samples_stable += 1

				if trace_budget > 0 and label == trace_label:
					trace_budget -= 1
					print("OFFSET_TRACE\tx=%.3f\ttheta_now=%+.4f\ttheta_prev=%+.4f\ttransition=%s\ttarget_y_now=%.4f\ttarget_y_prev=%.4f\tpred_dy=%+.4f\tactual_dy=%+.4f\toffset_residual=%+.4f" % [
						world_x, rad_to_deg(now["theta"]), rad_to_deg(prev["theta"]), str(is_transition),
						now["target_y"], prev["target_y"], predicted_delta_y,
						player.last_physics_displacement.y, offset_residual,
					])

		previous_world_x = world_x
		previous_grounded_model = player.is_using_grounded_model
		has_previous_frame = true

	print("OFFSET_RESULT\tseed=%d\tdistance=%.0f" % [session_seed, player.global_position.x])
	print("    %-20s %8s %10s %12s %13s %10s %10s" % [
		"segment", "frames", "transitions", "res@transit", "res@stable", "ratio", "mean_dtheta",
	])
	var labels: Array = per_label.keys()
	labels.sort()
	for label: String in labels:
		var stats: LabelStats = per_label[label]
		var res_transit: float = ratio_float(stats.residual_sum_transition, stats.residual_samples_transition)
		var res_stable: float = ratio_float(stats.residual_sum_stable, stats.residual_samples_stable)
		print("    %-20s %8d %10d %12.4f %13.4f %10.2f %10.4f%s" % [
			label, stats.grounded_frames, stats.transition_frames, res_transit, res_stable,
			res_transit / maxf(res_stable, 0.0001),
			ratio_float(stats.theta_jump_sum, stats.transition_frames),
			"   (out of scope)" if label == OUT_OF_SCOPE_LABEL else "",
		])

	main.queue_free()
	await process_frame


# The equilibrium center height for a capsule of radius r resting on the collision
# polyline segment that BRACKETS world_x, plus that segment's identity (its left
# sample x, used as a cheap bracket-equality test) and angle. Mirrors
# TerrainGenerator.get_collision_chord_slope_angle's own bracket search exactly, so
# this can't disagree with what the real ConcavePolygonShape2D was built from.
func offset_curve_target(terrain_generator: TerrainGenerator, capsule_radius: float, world_x: float) -> Dictionary:
	var chunk_width: float = terrain_generator.chunk_width
	var chunk_index: int = int(floor(world_x / chunk_width))
	var chunk_start_x: float = float(chunk_index) * chunk_width
	var chunk_end_x: float = chunk_start_x + chunk_width
	var collision_sample_count: int = maxi(ceili(chunk_width / TerrainGenerator.MAX_COLLISION_SEGMENT_LENGTH), 2)
	var sample_world_xs: Array[float] = terrain_generator.get_chunk_surface_sample_world_xs(chunk_start_x, chunk_end_x, collision_sample_count, true)

	var left_world_x: float = sample_world_xs[0]
	var right_world_x: float = sample_world_xs[sample_world_xs.size() - 1]
	for sample_index: int in range(sample_world_xs.size() - 1):
		if world_x >= sample_world_xs[sample_index] and world_x <= sample_world_xs[sample_index + 1]:
			left_world_x = sample_world_xs[sample_index]
			right_world_x = sample_world_xs[sample_index + 1]
			break

	var left_height: float = terrain_generator.get_terrain_height(left_world_x)
	var right_height: float = terrain_generator.get_terrain_height(right_world_x)
	var theta: float = atan2(right_height - left_height, right_world_x - left_world_x)
	var line_h_at_x: float = left_height + tan(theta) * (world_x - left_world_x)
	var target_y: float = line_h_at_x - (capsule_radius / cos(theta))
	return {"target_y": target_y, "bracket_left_x": left_world_x, "theta": theta}


func get_capsule_radius(player: Player) -> float:
	var collision_shape: CollisionShape2D = player.get_node("CollisionShape2D") as CollisionShape2D
	var capsule: CapsuleShape2D = collision_shape.shape as CapsuleShape2D
	if capsule == null:
		return 16.0
	return capsule.radius


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
