extends CharacterBody2D

class_name Player

const SPEED_MANAGER_SCRIPT: Script = preload("res://scripts/systems/speed_manager.gd")
const GRAVITY: float = 1600.0
const JUMP_VELOCITY: float = -640.0
const FLOOR_SNAP_LENGTH: float = 18.0

@onready var color_rect: ColorRect = $ColorRect

var speed_manager: RefCounted
var did_print_velocity: bool = false


func _ready() -> void:
	speed_manager = SPEED_MANAGER_SCRIPT.new() as RefCounted
	floor_snap_length = FLOOR_SNAP_LENGTH
	velocity = Vector2(speed_manager.current_speed, 0.0)
	color_rect.color = Color(0.85, 0.93, 1.0)


func _physics_process(delta: float) -> void:
	speed_manager.update(delta)
	velocity.x = speed_manager.current_speed

	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0

	if Engine.get_physics_frames() % 60 == 0:
		print(velocity)
		
	move_and_slide()
