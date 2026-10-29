extends SpriteSpan

class_name Vent

# An ICE VENT: a jet of frost that launches anyone who skates onto it -- black ice's opposite, a
# take-off the player cannot refuse and cannot time. Alone it is a free airtime; before a floe it
# means jump EARLY, over the vent, so you are down again before the floe instead of still in the
# air. The launch is Player's own ground jump (Player.is_on_vent), so its arc is every proof's
# arc; this node only draws the vent and puffs it on launch.

const VENT_TEXTURE: Texture2D = preload("res://assets/sprites/hazards/vent.png")
# Must equal VENT_WORLD_WIDTH in build_hazard_sprites.py. Wide enough that even at MAX_SPEED the
# player's centre spends 3+ frames on it, so the launch can never be stepped over between ticks.
const WORLD_WIDTH: float = 48.0
const PUFF_SCALE: float = 1.25
const PUFF_DURATION: float = 0.2


func get_sprite_texture() -> Texture2D:
	return VENT_TEXTURE


func build_visual(terrain: TerrainGenerator, color: Color) -> void:
	super.build_visual(terrain, color)
	player.jumped.connect(_on_player_jumped)


# A double jump also emits jumped, but never from the floor.
func _on_player_jumped() -> void:
	if not covers_x(player.global_position.x) or not player.is_on_floor():
		return
	var puff: Tween = create_tween()
	puff.tween_property(visual, "scale", Vector2.ONE * SPRITE_SCALE * PUFF_SCALE, PUFF_DURATION * 0.3)
	puff.tween_property(visual, "scale", Vector2.ONE * SPRITE_SCALE, PUFF_DURATION * 0.7)
