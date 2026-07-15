extends Node2D

class_name Main

@onready var player: CharacterBody2D = $Player
@onready var camera_2d: Camera2D = $Camera2D

var camera_y: float = 0.0


func _ready() -> void:
	camera_y = camera_2d.global_position.y
	camera_2d.make_current()
	camera_2d.global_position = Vector2(player.global_position.x, camera_y)


func _physics_process(_delta: float) -> void:
	camera_2d.global_position = Vector2(player.global_position.x, camera_y)
