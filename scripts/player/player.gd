extends CharacterBody2D

class_name Player

const SPEED_MANAGER_SCRIPT: Script = preload("res://scripts/systems/speed_manager.gd")
const GRAVITY: float = 1600.0
const JUMP_VELOCITY: float = -640.0
const FLOOR_SNAP_LENGTH: float = 18.0
const ROTATION_SMOOTHNESS: float = 12.0

@onready var color_rect: ColorRect = $ColorRect

var speed_manager: RefCounted
var did_print_velocity: bool = false


func _ready() -> void:
	speed_manager = SPEED_MANAGER_SCRIPT.new() as RefCounted
	floor_snap_length = FLOOR_SNAP_LENGTH
	floor_stop_on_slope = false
	floor_constant_speed = true
	velocity = Vector2(speed_manager.current_speed, 0.0)
	color_rect.color = Color(0.85, 0.93, 1.0)
	color_rect.pivot_offset = color_rect.size * 0.5


func _physics_process(delta: float) -> void:
	speed_manager.update(delta)

	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY

	if is_on_floor() and velocity.y >= 0.0:
		var slope_tangent: Vector2 = get_slope_tangent()
		velocity = slope_tangent * speed_manager.current_speed
		var target_rotation: float = slope_tangent.angle()
		color_rect.rotation = lerp_angle(color_rect.rotation, target_rotation, ROTATION_SMOOTHNESS * delta)
	else:
		velocity.x = speed_manager.current_speed
		velocity.y += GRAVITY * delta
		color_rect.rotation = lerp_angle(color_rect.rotation, 0.0, ROTATION_SMOOTHNESS * delta)

	if Engine.get_physics_frames() % 60 == 0:
		print(velocity)
		
	move_and_slide()


func get_slope_tangent() -> Vector2:
	var floor_normal: Vector2 = get_floor_normal()
	var slope_tangent: Vector2 = Vector2(-floor_normal.y, floor_normal.x).normalized()
	if slope_tangent.x < 0.0:
		slope_tangent = -slope_tangent
	return slope_tangent
