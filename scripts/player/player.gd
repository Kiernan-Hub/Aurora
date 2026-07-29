extends CharacterBody2D

class_name Player

signal died
signal debug_freeze_detected(session_seed: int)

const SPEED_MANAGER_SCRIPT: Script = preload("res://scripts/systems/speed_manager.gd")
const GRAVITY: float = 1600.0
const JUMP_VELOCITY: float = -640.0
const COYOTE_TIME_DURATION: float = 0.12
const JUMP_BUFFER_DURATION: float = 0.12
const FLOOR_SNAP_LENGTH: float = 18.0
const ROTATION_SMOOTHNESS: float = 12.0
const DEBUG_SLOPE_LOGGING: bool = false
# Fast enough to sweep the full INITIAL_SPEED..MAX_SPEED range in well under a
# second, since the point is skipping the ~62s automatic ramp during testing.
const MANUAL_SPEED_ADJUST_RATE: float = 300.0

@export var DEBUG_ALLOW_MANUAL_SPEED_CONTROL: bool = true
@export var DEBUG_SHOW_PLAYER_STATE: bool = true
@export var DEBUG_LOG_FREEZE_REPRO: bool = true
@export_range(10, 20, 1) var DEBUG_FREEZE_HISTORY_FRAME_COUNT: int = 20

@onready var color_rect: ColorRect = $ColorRect
@onready var terrain_generator: TerrainGenerator = get_node_or_null("../TerrainGenerator") as TerrainGenerator

var speed_manager: RefCounted
var is_dead: bool = false
var debug_rotation_timer: float = 0.0
var airborne_rotation: float = 0.0
var was_grounded_last_frame: bool = false
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var debug_state_label: Label
var last_physics_displacement: Vector2 = Vector2.ZERO
var debug_physics_frame: int = 0
var debug_freeze_event_count: int = 0
var debug_freeze_reported: bool = false
var debug_frame_history: Array[String] = []

const DEBUG_FREEZE_MIN_VELOCITY_X: float = 1.0
const DEBUG_FREEZE_MAX_MOTION_X: float = 0.01


func _ready() -> void:
	if not is_in_group("player"):
		add_to_group("player")
	speed_manager = SPEED_MANAGER_SCRIPT.new() as RefCounted
	floor_snap_length = FLOOR_SNAP_LENGTH
	floor_stop_on_slope = false
	floor_constant_speed = true
	velocity = Vector2(speed_manager.current_speed, 0.0)
	color_rect.color = Color(0.85, 0.93, 1.0)
	color_rect.pivot_offset = color_rect.size * 0.5
	airborne_rotation = color_rect.rotation
	if terrain_generator == null:
		push_error("Player requires a TerrainGenerator sibling.")
	setup_debug_state_label()


func _physics_process(delta: float) -> void:
	speed_manager.update(delta)
	if DEBUG_ALLOW_MANUAL_SPEED_CONTROL:
		apply_manual_speed_input(delta)

	if is_on_floor():
		coyote_timer = COYOTE_TIME_DURATION
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("ui_accept"):
		jump_buffer_timer = JUMP_BUFFER_DURATION
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	if coyote_timer > 0.0 and jump_buffer_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		jump_buffer_timer = 0.0

	if is_on_floor() and velocity.y >= 0.0:
		var slope_tangent: Vector2 = get_slope_tangent()
		velocity = slope_tangent * speed_manager.current_speed
	else:
		velocity.x = speed_manager.current_speed
		velocity.y += GRAVITY * delta

	var position_before_move: Vector2 = global_position
	move_and_slide()
	last_physics_displacement = global_position - position_before_move
	if TerrainGenerator.DEBUG_TERRAIN_LOGGING or DEBUG_SLOPE_LOGGING:
		var slide_collision_count: int = get_slide_collision_count()
		print("slide_collision_count=", slide_collision_count)
		if slide_collision_count > 0:
			for collision_index: int in range(slide_collision_count):
				var collision: KinematicCollision2D = get_slide_collision(collision_index)
				print("slide_collision[", collision_index, "] collider=", collision.get_collider().name, " normal=", collision.get_normal(), " position=", collision.get_position())
	update_visual_rotation(delta)
	update_debug_state_label()
	record_freeze_repro_frame()


func update_visual_rotation(delta: float) -> void:
	if terrain_generator == null:
		return

	var is_grounded: bool = is_on_floor()
	var logged_target_angle: float = color_rect.rotation
	if is_grounded:
		var terrain_angle: float = terrain_generator.get_slope_angle_at_x(global_position.x)
		# This exponential response is always in [0, 1), unlike smoothness * delta.
		# Clamp it to the current target's side of upright so a rapidly reversing
		# slope cannot leave the sprite tilted farther than the sampled terrain.
		var interpolation_weight: float = 1.0 - exp(-ROTATION_SMOOTHNESS * delta)
		var smoothed_rotation: float = lerp_angle(color_rect.rotation, terrain_angle, interpolation_weight)
		if terrain_angle >= 0.0:
			color_rect.rotation = clampf(smoothed_rotation, 0.0, terrain_angle)
		else:
			color_rect.rotation = clampf(smoothed_rotation, terrain_angle, 0.0)
		airborne_rotation = color_rect.rotation
		logged_target_angle = terrain_angle
	elif was_grounded_last_frame:
		airborne_rotation = color_rect.rotation

	if not is_grounded:
		color_rect.rotation = airborne_rotation

	if DEBUG_SLOPE_LOGGING:
		debug_rotation_timer += delta
		if debug_rotation_timer >= 0.5:
			debug_rotation_timer = 0.0
			print("player x=", global_position.x, " target_angle=", logged_target_angle, " rotation=", color_rect.rotation, " grounded=", is_grounded, " velocity=", velocity)

	was_grounded_last_frame = is_grounded


func apply_manual_speed_input(delta: float) -> void:
	if Input.is_action_pressed("ui_up"):
		speed_manager.apply_manual_adjustment(MANUAL_SPEED_ADJUST_RATE * delta)
	if Input.is_action_pressed("ui_down"):
		speed_manager.apply_manual_adjustment(-MANUAL_SPEED_ADJUST_RATE * delta)


func get_slope_tangent() -> Vector2:
	var floor_normal: Vector2 = get_floor_normal()
	var slope_tangent: Vector2 = Vector2(-floor_normal.y, floor_normal.x).normalized()
	if slope_tangent.x < 0.0:
		slope_tangent = -slope_tangent
	return slope_tangent


func setup_debug_state_label() -> void:
	if not DEBUG_SHOW_PLAYER_STATE:
		return

	var canvas_layer: CanvasLayer = get_node_or_null("../CanvasLayer") as CanvasLayer
	if canvas_layer == null:
		push_error("Player debug overlay requires a CanvasLayer sibling.")
		return

	debug_state_label = Label.new()
	debug_state_label.name = "PlayerStateDebugLabel"
	debug_state_label.offset_left = 8.0
	debug_state_label.offset_top = 8.0
	debug_state_label.offset_right = 360.0
	debug_state_label.offset_bottom = 120.0
	debug_state_label.add_theme_font_size_override("font_size", 12)
	canvas_layer.add_child(debug_state_label)


func update_debug_state_label() -> void:
	if debug_state_label == null:
		return

	var grounded: bool = is_on_floor()
	var floor_normal_text: String = "none"
	if grounded:
		floor_normal_text = str(get_floor_normal())
	var slide_collision_count: int = get_slide_collision_count()

	debug_state_label.text = (
		"velocity.x: %.3f\n" % velocity.x
		+ "velocity.y: %.3f\n" % velocity.y
		+ "motion.x: %.3f\n" % last_physics_displacement.x
		+ "is_on_floor: %s\n" % str(grounded)
		+ "floor_normal: %s\n" % floor_normal_text
		+ "world_x: %.3f\n" % global_position.x
		+ "segment: %s" % get_current_terrain_segment_label()
		+ "\nsession_seed: %d" % get_terrain_session_seed()
		+ "\nslide_collisions: %d" % slide_collision_count
		+ "\nfloor_collision: %s" % get_floor_collision_text(floor_normal_text)
	)


func get_current_terrain_segment_label() -> String:
	return get_terrain_segment_label_at_x(global_position.x)


func get_terrain_segment_label_at_x(world_x: float) -> String:
	if terrain_generator == null:
		return "unknown"

	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	var segment_index: int = terrain_generator.find_segment_index_at_x(world_x)
	return terrain_generator.get_segment_selection_label(segment_index)


func get_terrain_session_seed() -> int:
	if terrain_generator == null:
		return 0
	return terrain_generator.get_session_seed()


func get_floor_collision_text(floor_normal_text: String) -> String:
	var floor_collision: Dictionary = get_floor_collision_data()
	if floor_collision.is_empty():
		return "none"

	var collision_position: Vector2 = floor_collision["position"]
	return "x: %.3f, normal: %s, chunk: %d, segment: %s" % [
		collision_position.x,
		str(floor_collision["normal"]),
		floor_collision["chunk_index"],
		floor_collision["segment_label"],
	]


func get_floor_collision_data() -> Dictionary:
	var floor_collision_data: Dictionary = {}
	if not is_on_floor() or get_slide_collision_count() == 0:
		return floor_collision_data

	var floor_normal: Vector2 = get_floor_normal()
	var best_floor_collision: KinematicCollision2D
	var best_normal_match: float = -1.0
	for collision_index: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(collision_index)
		var normal_match: float = collision.get_normal().dot(floor_normal)
		if normal_match > best_normal_match:
			best_floor_collision = collision
			best_normal_match = normal_match

	if best_floor_collision == null:
		return floor_collision_data

	var collision_position: Vector2 = best_floor_collision.get_position()
	var collision_normal: Vector2 = best_floor_collision.get_normal()
	floor_collision_data["position"] = collision_position
	floor_collision_data["normal"] = collision_normal
	floor_collision_data["chunk_index"] = get_terrain_chunk_index_at_x(collision_position.x)
	floor_collision_data["segment_label"] = get_terrain_segment_label_at_x(collision_position.x)
	return floor_collision_data


func get_terrain_chunk_index_at_x(world_x: float) -> int:
	if terrain_generator == null:
		return 0
	return floori(world_x / terrain_generator.chunk_width)


func record_freeze_repro_frame() -> void:
	if not DEBUG_LOG_FREEZE_REPRO:
		return

	debug_physics_frame += 1
	var grounded: bool = is_on_floor()
	var floor_normal_text: String = "none"
	if grounded:
		floor_normal_text = str(get_floor_normal())
	var floor_collision: Dictionary = get_floor_collision_data()
	var floor_collision_text: String = "none"
	if not floor_collision.is_empty():
		var collision_position: Vector2 = floor_collision["position"]
		floor_collision_text = "point=(%.3f, %.3f) normal=%s chunk=%d segment=%s" % [
			collision_position.x,
			collision_position.y,
			str(floor_collision["normal"]),
			floor_collision["chunk_index"],
			floor_collision["segment_label"],
		]

	var frame_record: String = "frame=%d world_x=%.3f velocity_x=%.3f motion_x=%.6f on_floor=%s floor_normal=%s slide_collisions=%d floor_collision=%s" % [
		debug_physics_frame,
		global_position.x,
		velocity.x,
		last_physics_displacement.x,
		str(grounded),
		floor_normal_text,
		get_slide_collision_count(),
		floor_collision_text,
	]
	debug_frame_history.append(frame_record)
	var history_limit: int = maxi(DEBUG_FREEZE_HISTORY_FRAME_COUNT, 1)
	if debug_frame_history.size() > history_limit:
		debug_frame_history.pop_front()

	var freeze_detected: bool = (
		grounded
		and absf(velocity.x) >= DEBUG_FREEZE_MIN_VELOCITY_X
		and absf(last_physics_displacement.x) <= DEBUG_FREEZE_MAX_MOTION_X
	)
	if freeze_detected and not debug_freeze_reported:
		debug_freeze_reported = true
		debug_freeze_event_count += 1
		print("FREEZE_REPRO seed=", get_terrain_session_seed(), " event=", debug_freeze_event_count)
		for history_record: String in debug_frame_history:
			print("FREEZE_REPRO ", history_record)
		debug_freeze_detected.emit(get_terrain_session_seed())
	elif not freeze_detected:
		debug_freeze_reported = false


func die() -> void:
	if is_dead:
		return

	is_dead = true
	died.emit()
