extends SceneTree

# Diagnostic (2026-07-30) for the residual sub-pixel vertical bounce that survived the
# is_on_floor() flicker fix (cb8998b).
#
# FINDING: the bounce is floor-snap displacement on CURVED terrain. The grounded model
# aims the body along the surface tangent, which is a straight line while the surface
# curves away from it, so ~36% of grounded frames on a curved segment end with no fresh
# slide collision and are re-seated by floor snapping. Read the res_contact /
# res_nocont columns: on hills the no-contact frames carry ~2.2x the residual of
# contact frames, while on the constant-slope sustained_downhill control the two are
# equal, and on flat ground both are ~0.
#
# Two hypotheses were tested here and REFUTED; do not re-run them:
#   - aim chord != contact chord (the r*sin(theta) contact lead). The geometry is real
#     (obs_off matches pred_off) but residual ANTI-correlates with it. That turned out
#     to be a confound: mismatch is a proxy for contact provenance, since mis_nocont
#     (0.10-0.18) is far below the overall mis_rate (0.52-0.56), so "agreeing" frames
#     are predominantly the high-residual no-contact ones.
#   - collision polyline resolution. Halving MAX_COLLISION_SEGMENT_LENGTH twice
#     (16/8/4) left hill residual flat at 0.25-0.31; only gentle_uphill scaled.
#
# Residual is the load-bearing metric: actual vertical motion minus what the grounded
# model commanded, so unlike gap_wobble it does not depend on the field-vs-chord
# distinction. It scales with speed^1 and with curvature, NOT with steepness
# (mega_drop at 28.6deg is quieter than hills at 13.2deg) and NOT with chord length.
# Signed means (pred_res / act_res) are ~0 on hills: this is oscillation, not drift.
# On mega_drop alone act_res is consistently -0.11 to -0.13 -- a real systematic
# upward bias, and a lead for the separate, still-open mega_drop jitter issue.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/chord_aim_probe.gd -- \
#       --seeds=941462462,2160065702 --frames=20000 [--trace=small_hill --tracelines=40]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852"
# Bucket edges for |mismatch|, in degrees. The question is whether gap wobble rises
# with mismatch, so the buckets only need to separate "agreeing" from "disagreeing".
const MISMATCH_BUCKET_EDGES_DEG: Array[float] = [0.1, 1.0, 5.0]
const BUCKET_NAMES: Array[String] = ["<0.1deg", "0.1-1deg", "1-5deg", ">5deg"]
# Excluded from the verdict by the user's instruction: the severe jitter there is a
# separate, still-open issue. Still printed, just flagged.
const OUT_OF_SCOPE_LABEL: String = "mega_drop"


class Bucket:
	var frames: int = 0
	var gap_delta_sum: float = 0.0
	var gap_delta_samples: int = 0
	var abs_motion_y_sum: float = 0.0
	var residual_sum: float = 0.0
	var residual_samples: int = 0


class LabelStats:
	var grounded_frames: int = 0
	var residual_sum: float = 0.0
	var residual_samples: int = 0
	var residual_sum_agreeing: float = 0.0
	var residual_samples_agreeing: int = 0
	var residual_sum_mismatched: float = 0.0
	var residual_samples_mismatched: int = 0
	# Same split, but against the PREVIOUS frame's mismatch. residual_y describes the
	# step that ended on this frame, so it was determined by the aim/contact geometry
	# the body had one frame earlier. If the anti-correlation is a pairing artifact,
	# these two columns invert relative to the ones above.
	var residual_sum_prev_agreeing: float = 0.0
	var residual_samples_prev_agreeing: int = 0
	var residual_sum_prev_mismatched: float = 0.0
	var residual_samples_prev_mismatched: int = 0
	# Direct test of the radius x curvature model: the center rides the offset curve,
	# whose tangent equals the surface tangent at the CONTACT point, so the vertical
	# motion the model fails to command is step * (sin(field slope at contact) -
	# sin(field slope at center)), measured on the continuous height field.
	var predicted_residual_sum: float = 0.0
	var paired_actual_residual_sum: float = 0.0
	var prediction_samples: int = 0
	# Does a frame WITHOUT a fresh slide collision behave differently? get_floor_normal()
	# has nothing new to report on such a frame, so the "mismatch" it yields may be a
	# stale reading rather than a real disagreement -- and with no contact there is also
	# nothing to correct the body, so residual should be ~0.
	var no_contact_frames: int = 0
	var residual_sum_contact: float = 0.0
	var residual_samples_contact: int = 0
	var residual_sum_no_contact: float = 0.0
	var residual_samples_no_contact: int = 0
	var mismatch_frames_no_contact: int = 0
	var mismatch_frames: int = 0
	var abs_mismatch_sum: float = 0.0
	var max_abs_mismatch: float = 0.0
	var abs_slope_sum: float = 0.0
	var gap_sum: float = 0.0
	var gap_delta_sum: float = 0.0
	var gap_delta_samples: int = 0
	var offset_error_sum: float = 0.0
	var offset_samples: int = 0
	var observed_offset_sum: float = 0.0
	var predicted_offset_sum: float = 0.0


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 20000)
	var trace_label: String = get_string_argument("--trace", "")
	var trace_lines: int = get_int_argument("--tracelines", 0)
	# Pins speed instead of letting SpeedManager ramp, so residual can be measured as
	# a function of step length. Two candidate lead distances explain a
	# chord-invariant residual -- the contact lead r*sin(theta), which does not depend
	# on speed, and the per-frame step speed*delta, which is linear in it. Residual is
	# (lead * curvature * step), so the first predicts residual ~ speed and the second
	# residual ~ speed^2. Doubling speed tells them apart.
	var pinned_speed: int = get_int_argument("--speed", 0)

	print("CHORD_BEGIN\tgodot=%s\tframes_per_seed=%d" % [
		Engine.get_version_info()["string"], frame_limit,
	])

	var totals: Array[Bucket] = make_buckets()
	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		var seed_buckets: Array[Bucket] = await run_seed(session_seed, frame_limit, trace_label, trace_lines, pinned_speed)
		for bucket_index: int in range(totals.size()):
			totals[bucket_index].frames += seed_buckets[bucket_index].frames
			totals[bucket_index].gap_delta_sum += seed_buckets[bucket_index].gap_delta_sum
			totals[bucket_index].gap_delta_samples += seed_buckets[bucket_index].gap_delta_samples
			totals[bucket_index].abs_motion_y_sum += seed_buckets[bucket_index].abs_motion_y_sum
			totals[bucket_index].residual_sum += seed_buckets[bucket_index].residual_sum
			totals[bucket_index].residual_samples += seed_buckets[bucket_index].residual_samples

	print("CHORD_SUMMARY  (all seeds pooled, %s excluded)" % OUT_OF_SCOPE_LABEL)
	print("    %-10s %8s  %10s  %10s  %10s" % ["|mismatch|", "frames", "gap_wobble", "|motion_y|", "residual"])
	for bucket_index: int in range(totals.size()):
		var bucket: Bucket = totals[bucket_index]
		print("    %-10s %8d  %10.4f  %10.4f  %10.4f" % [
			BUCKET_NAMES[bucket_index], bucket.frames,
			ratio_float(bucket.gap_delta_sum, bucket.gap_delta_samples),
			ratio_float(bucket.abs_motion_y_sum, bucket.frames),
			ratio_float(bucket.residual_sum, bucket.residual_samples),
		])
	print("CHORD_END")
	quit(0)


func run_seed(session_seed: int, frame_limit: int, trace_label: String, trace_lines: int, pinned_speed: int) -> Array[Bucket]:
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
	var buckets: Array[Bucket] = make_buckets()
	var trace_budget: int = trace_lines
	var previous_gap: float = 0.0
	var has_previous_frame: bool = false
	# Everything needed to reconstruct the vertical motion the grounded model asked
	# for, from the state it actually read (pre-move position = previous frame's
	# post-move position).
	var physics_delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	var previous_world_x: float = player.global_position.x
	var previous_speed: float = player.speed_manager.current_speed
	var previous_grounded_model: bool = player.is_using_grounded_model
	var previous_abs_mismatch_deg: float = 0.0
	var previous_predicted_residual: float = 0.0
	var has_previous_geometry: bool = false

	for frame_index: int in range(frame_limit):
		if pinned_speed > 0:
			player.speed_manager.current_speed = float(pinned_speed)
		await physics_frame

		var world_x: float = player.global_position.x
		var label: String = segment_label_at(terrain_generator, world_x)
		var surface_gap: float = (player.global_position.y + player.capsule_half_height) - terrain_generator.get_surface_world_y(world_x)
		var gap_delta: float = absf(surface_gap - previous_gap)
		var had_previous_frame: bool = has_previous_frame
		previous_gap = surface_gap
		has_previous_frame = true

		# The bounce metric that does NOT depend on the field-vs-chord distinction:
		# how far the body's vertical motion diverged from what the velocity model
		# commanded. On a body riding flush along a chord this is ~0; every pixel of
		# it is the solver or the floor snap correcting the model after the fact.
		var commanded_motion_y: float = sin(terrain_generator.get_collision_chord_slope_angle(previous_world_x)) * previous_speed * physics_delta
		var residual_y: float = player.last_physics_displacement.y - commanded_motion_y
		var residual_is_valid: bool = had_previous_frame and previous_grounded_model and player.is_on_floor()
		previous_world_x = world_x
		previous_speed = player.speed_manager.current_speed
		previous_grounded_model = player.is_using_grounded_model

		if not player.is_on_floor():
			continue

		if not per_label.has(label):
			per_label[label] = LabelStats.new()
		var stats: LabelStats = per_label[label]

		var aim_angle: float = terrain_generator.get_collision_chord_slope_angle(world_x)
		# Chord direction is (cos t, sin t) with +y down, so the up-facing normal is
		# (sin t, -cos t). Inverting that gives the supporting chord's angle directly.
		var floor_normal: Vector2 = player.get_floor_normal()
		var contact_angle: float = atan2(floor_normal.x, -floor_normal.y)
		var mismatch_deg: float = rad_to_deg(aim_angle - contact_angle)
		var abs_mismatch_deg: float = absf(mismatch_deg)

		stats.grounded_frames += 1
		stats.abs_mismatch_sum += abs_mismatch_deg
		stats.max_abs_mismatch = maxf(stats.max_abs_mismatch, abs_mismatch_deg)
		stats.abs_slope_sum += absf(rad_to_deg(contact_angle))
		stats.gap_sum += surface_gap
		var is_mismatched: bool = abs_mismatch_deg > MISMATCH_BUCKET_EDGES_DEG[0]
		if is_mismatched:
			stats.mismatch_frames += 1
		# Split within the segment, so the comparison isn't confounded by mismatched
		# frames simply being more common on the steeper, bumpier segments.
		if residual_is_valid:
			stats.residual_sum += absf(residual_y)
			stats.residual_samples += 1
			if is_mismatched:
				stats.residual_sum_mismatched += absf(residual_y)
				stats.residual_samples_mismatched += 1
			else:
				stats.residual_sum_agreeing += absf(residual_y)
				stats.residual_samples_agreeing += 1
			if has_previous_geometry:
				if previous_abs_mismatch_deg > MISMATCH_BUCKET_EDGES_DEG[0]:
					stats.residual_sum_prev_mismatched += absf(residual_y)
					stats.residual_samples_prev_mismatched += 1
				else:
					stats.residual_sum_prev_agreeing += absf(residual_y)
					stats.residual_samples_prev_agreeing += 1
				stats.predicted_residual_sum += previous_predicted_residual
				stats.paired_actual_residual_sum += residual_y
				stats.prediction_samples += 1
		if had_previous_frame:
			stats.gap_delta_sum += gap_delta
			stats.gap_delta_samples += 1

		# Geometry check: does the contact point actually sit r*sin(theta) behind the
		# center? If not, the whole premise of this probe is wrong and the mismatch
		# column below means nothing.
		var floor_collision: Dictionary = player.get_floor_collision_data()
		var observed_offset: float = 0.0
		var predicted_offset: float = 0.0
		var field_slope_center: float = terrain_generator.get_slope_angle_at_x(world_x)
		var field_slope_contact: float = field_slope_center
		var has_fresh_contact: bool = player.get_slide_collision_count() > 0
		if not has_fresh_contact:
			stats.no_contact_frames += 1
			if is_mismatched:
				stats.mismatch_frames_no_contact += 1
		if residual_is_valid:
			if has_fresh_contact:
				stats.residual_sum_contact += absf(residual_y)
				stats.residual_samples_contact += 1
			else:
				stats.residual_sum_no_contact += absf(residual_y)
				stats.residual_samples_no_contact += 1
		if not floor_collision.is_empty():
			var contact_position: Vector2 = floor_collision["position"]
			observed_offset = world_x - contact_position.x
			predicted_offset = capsule_radius * sin(contact_angle)
			field_slope_contact = terrain_generator.get_slope_angle_at_x(contact_position.x)
			stats.observed_offset_sum += observed_offset
			stats.predicted_offset_sum += predicted_offset
			stats.offset_error_sum += absf(observed_offset - predicted_offset)
			stats.offset_samples += 1
		# Signed, and carried to the NEXT frame, because it predicts the residual of the
		# step that starts here.
		previous_predicted_residual = (sin(field_slope_contact) - sin(field_slope_center)) * player.speed_manager.current_speed * physics_delta
		previous_abs_mismatch_deg = abs_mismatch_deg
		has_previous_geometry = true

		if label != OUT_OF_SCOPE_LABEL:
			var bucket: Bucket = buckets[get_bucket_index(abs_mismatch_deg)]
			bucket.frames += 1
			bucket.abs_motion_y_sum += absf(player.last_physics_displacement.y)
			if residual_is_valid:
				bucket.residual_sum += absf(residual_y)
				bucket.residual_samples += 1
			if had_previous_frame:
				bucket.gap_delta_sum += gap_delta
				bucket.gap_delta_samples += 1

		if trace_budget > 0 and label == trace_label:
			trace_budget -= 1
			print("CHORD_TRACE\tx=%.3f\taim=%+.4f\tcontact=%+.4f\tmismatch=%+.4f\tobs_off=%+.3f\tfield_center=%+.4f\tfield_contact=%+.4f\tresidual_y=%+.4f\tpredicted_next=%+.4f\tgap=%+.4f" % [
				world_x, rad_to_deg(aim_angle), rad_to_deg(contact_angle), mismatch_deg,
				observed_offset, rad_to_deg(field_slope_center), rad_to_deg(field_slope_contact),
				residual_y if residual_is_valid else 0.0, previous_predicted_residual,
				player.get_slide_collision_count(),
			])

	print("CHORD_RESULT\tseed=%d\tdistance=%.0f" % [session_seed, player.global_position.x])
	print("    %-20s %7s %8s %9s %9s %9s %10s %9s %9s %9s %10s %10s %10s %10s %10s %10s %10s %9s %11s %10s %10s" % [
		"segment", "frames", "mis_rate", "mean_mis", "max_mis", "mean_slope",
		"gap_wobble", "mean_gap", "obs_off", "pred_off",
		"residual", "res_agree", "res_mismat", "res_pAgree", "res_pMism",
		"pred_res", "act_res", "noContact", "res_contact", "res_nocont", "mis_nocont",
	])
	var labels: Array = per_label.keys()
	labels.sort()
	for label: String in labels:
		var stats: LabelStats = per_label[label]
		print("    %-20s %7d %8.4f %9.4f %9.4f %9.4f %10.4f %+9.4f %+9.3f %+9.3f %10.4f %10.4f %10.4f %10.4f %10.4f %+10.4f %+10.4f %9.4f %11.4f %10.4f %10.4f%s" % [
			label, stats.grounded_frames,
			ratio(stats.mismatch_frames, stats.grounded_frames),
			ratio_float(stats.abs_mismatch_sum, stats.grounded_frames),
			stats.max_abs_mismatch,
			ratio_float(stats.abs_slope_sum, stats.grounded_frames),
			ratio_float(stats.gap_delta_sum, stats.gap_delta_samples),
			ratio_float(stats.gap_sum, stats.grounded_frames),
			ratio_float(stats.observed_offset_sum, stats.offset_samples),
			ratio_float(stats.predicted_offset_sum, stats.offset_samples),
			ratio_float(stats.residual_sum, stats.residual_samples),
			ratio_float(stats.residual_sum_agreeing, stats.residual_samples_agreeing),
			ratio_float(stats.residual_sum_mismatched, stats.residual_samples_mismatched),
			ratio_float(stats.residual_sum_prev_agreeing, stats.residual_samples_prev_agreeing),
			ratio_float(stats.residual_sum_prev_mismatched, stats.residual_samples_prev_mismatched),
			ratio_float(stats.predicted_residual_sum, stats.prediction_samples),
			ratio_float(stats.paired_actual_residual_sum, stats.prediction_samples),
			ratio(stats.no_contact_frames, stats.grounded_frames),
			ratio_float(stats.residual_sum_contact, stats.residual_samples_contact),
			ratio_float(stats.residual_sum_no_contact, stats.residual_samples_no_contact),
			ratio(stats.mismatch_frames_no_contact, stats.no_contact_frames),
			"   (out of scope)" if label == OUT_OF_SCOPE_LABEL else "",
		])

	main.queue_free()
	await process_frame
	return buckets


func make_buckets() -> Array[Bucket]:
	var buckets: Array[Bucket] = []
	for bucket_index: int in range(BUCKET_NAMES.size()):
		buckets.append(Bucket.new())
	return buckets


func get_bucket_index(abs_mismatch_deg: float) -> int:
	for edge_index: int in range(MISMATCH_BUCKET_EDGES_DEG.size()):
		if abs_mismatch_deg < MISMATCH_BUCKET_EDGES_DEG[edge_index]:
			return edge_index
	return MISMATCH_BUCKET_EDGES_DEG.size()


func get_capsule_radius(player: Player) -> float:
	var collision_shape: CollisionShape2D = player.get_node("CollisionShape2D") as CollisionShape2D
	var capsule: CapsuleShape2D = collision_shape.shape as CapsuleShape2D
	if capsule == null:
		return 16.0
	return capsule.radius


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
