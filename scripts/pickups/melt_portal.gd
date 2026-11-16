extends Coin

class_name MeltPortal
var entry_guard: Callable

class Ring extends Node2D:
	var age: float = 0.0
	func _process(delta: float) -> void:
		age += delta
		queue_redraw()
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.7, 1.0))
		for i: int in range(3):
			var radius: float = 35.0 + float(i) * 3.0
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.55, 0.8, 1.0, 0.28 - i * 0.06), 5.0, true)
		draw_arc(Vector2.ZERO, 35.0, 0.0, TAU, 48, Color(0.7, 0.95, 1.0, 0.9), 1.5, true)
		draw_arc(Vector2.ZERO, 29.0, age * 0.6, age * 0.6 + PI * 1.3, 32, Color(0.7, 0.55, 1.0, 0.8), 2.5, true)
		draw_set_transform(Vector2.ZERO)
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(-37.0, -48.0), "THE MELT", HORIZONTAL_ALIGNMENT_CENTER, 74.0, 12, Color(0.85, 0.95, 1.0))
		draw_string(font, Vector2(-40.0, 59.0), "Jump to enter", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 10, Color(0.8, 0.9, 1.0))


func _ready() -> void:
	var ring: Ring = Ring.new()
	ring.name = "Visual"
	add_child(ring)
	spin_speed = 0.0
	spin_min_scale = 1.0
	super._ready()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	# An existing flight/boost keeps its ordinary behavior instead of being confiscated.
	if body.get(&"is_glide_active") or body.get(&"is_boosting"):
		return
	if entry_guard.is_valid() and not entry_guard.call():
		return
	super._on_body_entered(body)
