extends Area2D

class_name Coin

signal collected(value: int)

@export var value: int = 1

var has_been_collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


# The ONE place that knows how a coin is drawn. Both spawners push a biome's coin_color
# through here rather than reaching for the visual themselves -- see visuals.md's art-swap
# traps, where the loose get_node("ColorRect") was one of four.
#
# The visual is now a Sprite2D, so the biome colour is a MULTIPLY over the sprite's own
# gold, not the absolute fill the ColorRect took. All nine palettes author a warm gold at
# or below the sprite's own, so the multiply only deepens it; it can never brighten, which
# is why the palettes stay the readable-contrast source of truth for biome_schedule_check.
#
# The rare coin uses this scene's script but no spawner pushes a colour into it, so the
# diamond keeps modulate WHITE and renders as authored.
#
# Safe to call the frame the scene is instantiated, before add_child(): an instanced
# scene's children exist immediately, they just haven't entered the tree.
func set_visual_color(color: Color) -> void:
	var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem
	if visual != null:
		visual.modulate = color


func _on_body_entered(body: Node2D) -> void:
	if has_been_collected:
		return
	if not body.is_in_group("player"):
		return

	has_been_collected = true
	set_deferred("monitoring", false)
	collected.emit(value)
	queue_free()
