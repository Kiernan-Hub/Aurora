extends Node2D

class_name FlightTrail

# Manga-style speed lines, not a particle system: short Line2D streaks spawned as
# children so they trail behind the player using ordinary local-space movement, with
# no global/world-position or camera math involved.

const STREAK_LENGTH: float = 14.0
const SPAWN_INTERVAL: float = 0.05
const STREAK_LIFETIME: float = 0.25
const STREAK_SPEED: float = 260.0
const STREAK_COLOR: Color = Color(0.75, 0.95, 1.0, 0.85)
const VERTICAL_SPREAD: float = 10.0

var time_remaining: float = 0.0
var spawn_timer: float = 0.0
var streak_length: float = STREAK_LENGTH
var streak_width: float = 2.0
var cosmetic_active: bool = false


func configure(style: Dictionary) -> void:
	cosmetic_active = not style.is_empty()
	streak_length = style.get("length", STREAK_LENGTH)
	streak_width = style.get("width", 2.0)


func _process(delta: float) -> void:
	var skater: CharacterBody2D = get_parent() as CharacterBody2D
	var skating: bool = cosmetic_active and skater != null and skater.is_on_floor() and skater.velocity.x > 0.0
	if time_remaining <= 0.0 and not skating:
		return

	time_remaining = maxf(time_remaining - delta, 0.0)
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = SPAWN_INTERVAL
		_spawn_streak(skating)


func play(duration: float) -> void:
	time_remaining = duration
	spawn_timer = 0.0


func _spawn_streak(skating: bool = false) -> void:
	var streak: Line2D = Line2D.new()
	streak.width = streak_width
	streak.default_color = STREAK_COLOR
	var y_offset: float = randf_range(-VERTICAL_SPREAD, VERTICAL_SPREAD)
	var slope: float = 0.0
	if skating:
		var skater: CharacterBody2D = get_parent() as CharacterBody2D
		var normal: Vector2 = skater.get_floor_normal()
		slope = normal.x / maxf(-normal.y, 0.1)
		# The emitter sits behind the body; follow the blade's ground line on hills too.
		y_offset = float(skater.get("capsule_half_height")) - 3.0 + position.x * slope + randf_range(-1.5, 1.5)
	streak.add_point(Vector2(0.0, y_offset))
	streak.add_point(Vector2(-streak_length, y_offset - streak_length * slope))
	add_child(streak)

	var tween: Tween = create_tween()
	tween.tween_property(streak, "position", Vector2(-STREAK_SPEED * STREAK_LIFETIME, -STREAK_SPEED * STREAK_LIFETIME * slope), STREAK_LIFETIME)
	tween.parallel().tween_property(streak, "modulate:a", 0.0, STREAK_LIFETIME)
	tween.tween_callback(streak.queue_free)
