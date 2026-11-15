extends SpriteSpan

class_name Geode

# A GEODE: gold-veined ice on the ground that only a SLAM landing on it breaks, for coins. The
# slam's first job beyond dodging, and a real choice: diving early to hit it shortens the jump,
# which can land you in front of whatever comes next. Scheduled only for a player who owns the
# slam (ObstacleSpawner.get_pattern); harmless to everyone, never a hitbox. Broken by
# Player.landed, which fires while is_slamming still holds (player.gd clears it after the emit).

signal broken(value: int)

const GEODE_TEXTURE: Texture2D = preload("res://assets/sprites/hazards/geode.png")
# Must equal GEODE_WORLD_WIDTH in build_hazard_sprites.py.
const WORLD_WIDTH: float = 56.0
const VALUE: int = 10
# A slam landing this far past either end still counts: the capsule is wider than a point.
const SLAM_REACH: float = 24.0
const BREAK_DURATION: float = 0.25


func get_sprite_texture() -> Texture2D:
	return GEODE_TEXTURE


func build_visual(terrain: TerrainGenerator, color: Color) -> void:
	super.build_visual(terrain, color)
	player.landed.connect(_on_player_landed)


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
