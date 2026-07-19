extends CharacterBody2D

class_name Player

signal died

const SPEED_MANAGER_SCRIPT: Script = preload("res://scripts/systems/speed_manager.gd")
const GRAVITY: float = 1600.0
const JUMP_VELOCITY: float = -640.0
const COYOTE_TIME_DURATION: float = 0.12
const JUMP_BUFFER_DURATION: float = 0.12
const FLOOR_SNAP_LENGTH: float = 18.0
const ROTATION_SMOOTHNESS: float = 12.0
const DEBUG_SLOPE_LOGGING: bool = false

@onready var color_rect: ColorRect = $ColorRect
@onready var terrain_generator: TerrainGenerator = get_node_or_null("../TerrainGenerator") as TerrainGenerator

var speed_manager: RefCounted
var is_dead: bool = false
var debug_rotation_timer: float = 0.0
var airborne_rotation: float = 0.0
var was_grounded_last_frame: bool = false
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0


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


func _physics_process(delta: float) -> void:
	speed_manager.update(delta)

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

	move_and_slide()
	if TerrainGenerator.DEBUG_TERRAIN_LOGGING or DEBUG_SLOPE_LOGGING:
		var slide_collision_count: int = get_slide_collision_count()
		print("slide_collision_count=", slide_collision_count)
		if slide_collision_count > 0:
			for collision_index: int in range(slide_collision_count):
				var collision: KinematicCollision2D = get_slide_collision(collision_index)
				print("slide_collision[", collision_index, "] collider=", collision.get_collider().name, " normal=", collision.get_normal(), " position=", collision.get_position())
	update_visual_rotation(delta)


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


func get_slope_tangent() -> Vector2:
	var floor_normal: Vector2 = get_floor_normal()
	var slope_tangent: Vector2 = Vector2(-floor_normal.y, floor_normal.x).normalized()
	if slope_tangent.x < 0.0:
		slope_tangent = -slope_tangent
	return slope_tangent


func die() -> void:
	if is_dead:
		return

	is_dead = true
	died.emit()
