extends SceneTree

# Diagnostic (2026-07-30), read-only. Third in this investigation chain:
#   - chord_aim_probe.gd: residual scales with curvature; ~2.2x larger on frames with
#     no fresh slide collision.
#   - offset_curve_probe.gd: REFUTED vertex-crossing / r*cos(theta) resting-height
#     geometry as sufficient causes -- residual on geometrically "stable" frames
#     (no bracket change) is statistically equal to residual at transitions.
#   - slide_vs_snap_probe.gd: residual splits ~65% move_and_slide()'s own contact
#     resolution / ~35% player.gd's explicit uphill floor-snap (0% on one-directional
#     segments, where that snap's gate never opens). Both channels correlate 3-8x
#     with whether get_slide_collision_count() flips between 0 and nonzero from the
#     previous frame, even though is_on_floor() itself never flickers.
#
# This probe answers: what does that flicker actually look like at the collision
# level? For every frame where slides flips OR residual is large, it dumps full
# pre/post state -- position and velocity before/after move_and_slide(), every slide
# collision's normal/position/collider, floor_normal/floor_angle/is_on_floor(), and
# the engine's own contact-resolution settings read directly off the live body
# (safe_margin, floor_snap_length, floor_max_angle, up_direction -- not re-declared
# here, so they can't drift out of sync with what's actually configured).
#
# It also classifies each such frame into one of:
#   CONTACT_DROP    slides>0 last frame, 0 this frame (collision test found nothing)
#   CONTACT_GAIN    slides==0 last frame, >0 this frame
#   NORMAL_CHANGE   slides>0 both frames, but floor_normal angle changed >0.5deg
#   NORMAL_STABLE   slides>0 both frames, floor_normal angle ~unchanged
#   NO_CONTACT      slides==0 both frames (only logged if residual is large; would
#                   mean floor-snap alone is producing displacement despite no slide
#                   collision at all this frame)
#
# Uses the read-only fields added to Player for this (2026-07-30): debug_position_
# after_slide/after_snap, debug_velocity_before_slide/after_slide. No movement code,
# constants, or collision shapes are touched.
#
# Usage:
#   Godot --headless --path . --script res://scripts/debug/contact_instability_probe.gd -- \
#       --seeds=941462462 --frames=9000 [--maxlogs=60] [--residual-threshold=0.15]
#       [--trace=medium_hill]  (restricts detailed logs to one segment label)
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_SEEDS: String = "941462462,2160065702,3188032853,222894852"
const NORMAL_CHANGE_THRESHOLD_DEG: float = 0.5


func _init() -> void:
	var seeds_text: String = get_string_argument("--seeds", DEFAULT_SEEDS)
	var frame_limit: int = get_int_argument("--frames", 9000)
	var max_logs: int = get_int_argument("--maxlogs", 60)
	var residual_threshold: float = get_float_argument("--residual-threshold", 0.15)
	var trace_label: String = get_string_argument("--trace", "")

	print("CONTACT_BEGIN\tgodot=%s\tframes_per_seed=%d\tmax_logs=%d\tresidual_threshold=%.3f" % [
		Engine.get_version_info()["string"], frame_limit, max_logs, residual_threshold,
	])

	var totals: Dictionary = {
		"CONTACT_DROP": 0, "CONTACT_GAIN": 0, "NORMAL_CHANGE": 0,
		"NORMAL_STABLE": 0, "NO_CONTACT": 0,
	}
	var logs_remaining: int = max_logs
	for seed_text: String in seeds_text.split(","):
		var session_seed: int = seed_text.strip_edges().to_int()
		logs_remaining = await run_seed(session_seed, frame_limit, logs_remaining, residual_threshold, trace_label, totals)

	print("CONTACT_CLASSIFICATION_TOTALS")
	for classification: String in totals.keys():
		print("    %-16s %d" % [classification, totals[classification]])
	print("CONTACT_END")
	quit(0)


func run_seed(session_seed: int, frame_limit: int, logs_remaining: int, residual_threshold: float, trace_label: String, totals: Dictionary) -> int:
	var main: Node = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	var player: Player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = session_seed
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	root.add_child(main)
	await physics_frame

	print("CONTACT_PHYSICS_SETTINGS\tseed=%d\tsafe_margin=%.4f\tfloor_snap_length=%.4f\tfloor_max_angle_deg=%.4f\tup_direction=%s\tfloor_stop_on_slope=%s\tfloor_constant_speed=%s" % [
		session_seed, player.safe_margin, player.floor_snap_length,
		rad_to_deg(player.floor_max_angle), str(player.up_direction),
		str(player.floor_stop_on_slope), str(player.floor_constant_speed),
	])

	var physics_delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	var previous_world_x: float = player.global_position.x
	var previous_slide_count: int = 0
	var previous_floor_normal: Vector2 = Vector2.UP
	var previous_had_floor_data: bool = false
	var has_previous_frame: bool = false

	for frame_index: int in range(frame_limit):
		var position_before_move: Vector2 = player.global_position
		var commanded_angle: float = terrain_generator.get_collision_chord_slope_angle(position_before_move.x)
		var commanded_speed: float = player.speed_manager.current_speed
		await physics_frame

		if logs_remaining <= 0:
			continue

		var world_x: float = player.global_position.x
		var label: String = segment_label_at(terrain_generator, world_x)
		var is_grounded: bool = player.is_on_floor()
		if not (is_grounded and player.is_using_grounded_model):
			previous_world_x = world_x
			has_previous_frame = false
			continue

		var slide_count: int = player.get_slide_collision_count()
		var floor_normal: Vector2 = player.get_floor_normal()

		var slide_dy: float = player.debug_position_after_slide.y - position_before_move.y
		var snap_dy: float = player.debug_position_after_snap.y - player.debug_position_after_slide.y
		var commanded_dy: float = sin(commanded_angle) * commanded_speed * physics_delta
		var residual: float = (slide_dy + snap_dy) - commanded_dy

		var slide_flipped: bool = has_previous_frame and (slide_count > 0) != (previous_slide_count > 0)
		var is_high_residual: bool = absf(residual) >= residual_threshold
		var should_log: bool = has_previous_frame and (slide_flipped or is_high_residual)
		if should_log and not trace_label.is_empty() and label != trace_label:
			should_log = false

		if should_log:
			var classification: String = classify(
				previous_slide_count, slide_count, previous_floor_normal, floor_normal, previous_had_floor_data,
			)
			totals[classification] = int(totals[classification]) + 1

			print("CONTACT_FRAME\tseed=%d\tx=%.3f\tsegment=%s\tclass=%s\tflip=%s\tresidual=%+.4f" % [
				session_seed, world_x, label, classification, str(slide_flipped), residual,
			])
			print("    pos_before=%s pos_after_slide=%s pos_after_snap=%s" % [
				str(position_before_move), str(player.debug_position_after_slide), str(player.debug_position_after_snap),
			])
			print("    vel_before_slide=%s vel_after_slide=%s" % [
				str(player.debug_velocity_before_slide), str(player.debug_velocity_after_slide),
			])
			print("    is_on_floor=%s slide_collision_count=%d (was %d) floor_normal=%s floor_angle_deg=%.4f" % [
				str(is_grounded), slide_count, previous_slide_count, str(floor_normal), rad_to_deg(atan2(floor_normal.x, -floor_normal.y)),
			])
			if slide_count > 0:
				for collision_index: int in range(slide_count):
					var collision: KinematicCollision2D = player.get_slide_collision(collision_index)
					var collider: Object = collision.get_collider()
					var collider_name: String = collider.name if collider is Node else str(collider)
					print("    slide[%d] normal=%s position=%s collider=%s travel=%s remainder=%s" % [
						collision_index, str(collision.get_normal()), str(collision.get_position()),
						collider_name, str(collision.get_travel()), str(collision.get_remainder()),
					])
			else:
				print("    slide[] (none reported)")

			logs_remaining -= 1
			if logs_remaining <= 0:
				print("CONTACT_LOG_LIMIT_REACHED")

		previous_world_x = world_x
		previous_slide_count = slide_count
		previous_floor_normal = floor_normal
		previous_had_floor_data = true
		has_previous_frame = true

	main.queue_free()
	await process_frame
	return logs_remaining


func classify(previous_slide_count: int, slide_count: int, previous_floor_normal: Vector2, floor_normal: Vector2, previous_had_floor_data: bool) -> String:
	var had_contact_before: bool = previous_slide_count > 0
	var has_contact_now: bool = slide_count > 0
	if had_contact_before and not has_contact_now:
		return "CONTACT_DROP"
	if not had_contact_before and has_contact_now:
		return "CONTACT_GAIN"
	if not has_contact_now:
		return "NO_CONTACT"
	if not previous_had_floor_data:
		return "NORMAL_STABLE"
	var normal_delta_deg: float = rad_to_deg(previous_floor_normal.angle_to(floor_normal))
	if absf(normal_delta_deg) > NORMAL_CHANGE_THRESHOLD_DEG:
		return "NORMAL_CHANGE"
	return "NORMAL_STABLE"


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


func get_float_argument(argument_name: String, default_value: float) -> float:
	var raw_value: String = get_string_argument(argument_name, "")
	if raw_value.is_empty():
		return default_value
	return raw_value.to_float()
