extends ThinIce

class_name SpriteSpan

# A span drawn as ONE untinted sprite centred on it instead of a tinted strip: Geode and Vent.
# Each is a ThinIce subclass for the span plumbing (placement, Aurora bounds, lake suppression,
# despawn), not for its rules: it never cracks and no biome repaints it -- each is authored in
# its own colour, the way coins are.

# Sprites are baked at 3x their world size (build_hazard_sprites.py, bake_by_width).
const SPRITE_SCALE: float = 1.0 / 3.0
# Sunk this far into the surface so it sits IN the ice; the chunk draws over the buried part.
const SINK: float = 3.0

var visual: Sprite2D


func get_sprite_texture() -> Texture2D:
	return null


func build_visual(terrain: TerrainGenerator, _color: Color) -> void:
	var center_x: float = (start_x + end_x) * 0.5
	var surface_y: float = terrain.ground_y + terrain.get_terrain_height(center_x) - position.y
	visual = Sprite2D.new()
	visual.name = "Visual"
	visual.texture = get_sprite_texture()
	visual.scale = Vector2.ONE * SPRITE_SCALE
	visual.position = Vector2(center_x - start_x, surface_y - get_sprite_height() * 0.5 + SINK)
	add_child(visual)


func get_sprite_height() -> float:
	return get_sprite_texture().get_height() * SPRITE_SCALE


func get_world_rect() -> Rect2:
	return Rect2(global_position.x, global_position.y - get_sprite_height(), end_x - start_x, get_sprite_height())


func set_visual_color(_color: Color) -> void:
	pass


func _physics_process(_delta: float) -> void:
	pass
