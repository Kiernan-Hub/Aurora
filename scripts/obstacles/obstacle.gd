extends Area2D

var has_triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if has_triggered:
		return
	if not (body is CharacterBody2D):
		return
	if not body.is_in_group("player"):
		return

	has_triggered = true
	set_deferred("monitoring", false)
	var player: Player = body as Player
	player.absorb_hit()
