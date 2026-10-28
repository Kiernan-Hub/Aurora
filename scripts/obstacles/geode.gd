extends ThinIce

class_name Geode

# A GEODE: gold-veined ice on the ground that only a SLAM landing on it breaks, for coins. The
# slam's first job beyond dodging, and a real choice: diving early to hit it shortens the jump,
# which can land you in front of whatever comes next. Scheduled only for a player who owns the
# slam (ObstacleSpawner.get_pattern); harmless to everyone, never a hitbox.
#
# A ThinIce subclass for the span plumbing (placement, Aurora bounds, lake suppression, despawn),
# not for its rules: it never cracks and is never tinted. Broken by Player.landed, which fires
# while is_slamming still holds (player.gd clears it after the emit).

signal broken(value: int)

const GEODE_TEXTURE: Texture2D = preload("res://assets/sprites/hazards/geode.png")
# Must equal GEODE_WORLD_WIDTH in build_hazard_sprites.py; the sprite is baked at 3x.
const WORLD_WIDTH: float = 56.0
const VALUE: int = 10
# A slam landing this far past either end still counts: the capsule is wider than a point.
const SLAM_REACH: float = 24.0
# Sunk this far into the surface so it sits IN the ice; the chunk draws over the buried part.
const SINK: float = 3.0
const BREAK_DURATION: float = 0.25

var visual: Sprite2D


func build_visual(terrain: TerrainGenerator, _color: Color) -> void:
	var center_x: float = (start_x + end_x) * 0.5
	var surface_y: float = terrain.ground_y + terrain.get_terrain_height(center_x) - position.y
	visual = Sprite2D.new()
	visual.name = "Visual"
	visual.texture = GEODE_TEXTURE
	visual.scale = Vector2.ONE / 3.0
	var height: float = GEODE_TEXTURE.get_height() / 3.0
	visual.position = Vector2(center_x - start_x, surface_y - height * 0.5 + SINK)
	add_child(visual)
	player.landed.connect(_on_player_landed)


func get_world_rect() -> Rect2:
	var height: float = GEODE_TEXTURE.get_height() / 3.0
	return Rect2(global_position.x, global_position.y - height, end_x - start_x, height)


func set_visual_color(_color: Color) -> void:
	pass


func _physics_process(_delta: float) -> void:
	pass


func _on_player_landed() -> void:
	if not is_armed or not player.is_slamming or player.is_dead:
		return
	var player_x: float = player.global_position.x
	if player_x < start_x - SLAM_REACH or player_x >= end_x + SLAM_REACH:
		return
	is_armed = false
	broken.emit(VALUE)
	var shatter: Tween = create_tween().set_parallel()
	shatter.tween_property(visual, "scale", visual.scale * 1.4, BREAK_DURATION)
	shatter.tween_property(visual, "modulate:a", 0.0, BREAK_DURATION)
