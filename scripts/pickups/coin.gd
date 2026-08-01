extends Area2D

class_name Coin

signal collected(value: int)

@export var value: int = 1

var has_been_collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if has_been_collected:
		return
	if not body.is_in_group("player"):
		return

	has_been_collected = true
	set_deferred("monitoring", false)
	collected.emit(value)
	queue_free()
