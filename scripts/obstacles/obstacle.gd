extends Area2D

class_name Obstacle

var has_triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


# Same contract as Coin.set_visual_color(): the only place that knows how an obstacle is
# drawn, so ObstacleSpawner never touches the ColorRect by name and the eventual sprite
# swap lands here. Callable before add_child().
func set_visual_color(color: Color) -> void:
	var visual: ColorRect = get_node_or_null("ColorRect") as ColorRect
	if visual != null:
		visual.color = color


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
	# A speed boost already forces the grounded, gravity-free velocity model regardless
	# of terrain (see the LOAD-BEARING FOR CHASMS note on Player.is_using_grounded_model)
	# -- letting it also plow through obstacles for free is the same "boosting is
	# unstoppable" contract, not a new one. has_shield is untouched here, so a shielded
	# but non-boosting hit still costs the shield exactly as before.
	if player.is_boosting:
		return
	player.absorb_hit()
