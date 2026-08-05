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


func _process(delta: float) -> void:
	if time_remaining <= 0.0:
		return

	time_remaining -= delta
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = SPAWN_INTERVAL
		_spawn_streak()


func play(duration: float) -> void:
	time_remaining = duration
	spawn_timer = 0.0


func _spawn_streak() -> void:
	var streak := Line2D.new()
	streak.width = 2.0
	streak.default_color = STREAK_COLOR
	var y_offset: float = randf_range(-VERTICAL_SPREAD, VERTICAL_SPREAD)
	streak.add_point(Vector2(0.0, y_offset))
	streak.add_point(Vector2(-STREAK_LENGTH, y_offset))
	add_child(streak)

	var tween: Tween = create_tween()
	tween.tween_property(streak, "position:x", -STREAK_SPEED * STREAK_LIFETIME, STREAK_LIFETIME)
	tween.parallel().tween_property(streak, "modulate:a", 0.0, STREAK_LIFETIME)
	tween.tween_callback(streak.queue_free)
