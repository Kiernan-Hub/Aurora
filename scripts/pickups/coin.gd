extends Area2D

class_name Coin

signal collected(value: int)

@export var value: int = 1

var has_been_collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


# The ONE place that knows how a coin is drawn. Both spawners push a biome's coin_color
# through here rather than reaching for the ColorRect themselves, so swapping the
# placeholder rect for a sprite (build order §8) is a change to this function alone --
# see visuals.md's art-swap traps, where the loose get_node("ColorRect") was one of four.
#
# Safe to call the frame the scene is instantiated, before add_child(): an instanced
# scene's children exist immediately, they just haven't entered the tree.
func set_visual_color(color: Color) -> void:
	var visual: ColorRect = get_node_or_null("ColorRect") as ColorRect
	if visual != null:
		visual.color = color


func _on_body_entered(body: Node2D) -> void:
	if has_been_collected:
		return
	if not body.is_in_group("player"):
		return

	has_been_collected = true
	set_deferred("monitoring", false)
	collected.emit(value)
	queue_free()
