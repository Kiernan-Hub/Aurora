extends CharacterBody2D

class_name Player

const FORWARD_SPEED: float = 220.0
const GRAVITY: float = 1600.0
const JUMP_VELOCITY: float = -640.0
const FLOOR_SNAP_LENGTH: float = 18.0

@onready var color_rect: ColorRect = $ColorRect


func _ready() -> void:
	floor_snap_length = FLOOR_SNAP_LENGTH
	velocity = Vector2(FORWARD_SPEED, 0.0)
	color_rect.color = Color(0.85, 0.93, 1.0)


func _physics_process(delta: float) -> void:
	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0

	velocity.x = FORWARD_SPEED
	move_and_slide()