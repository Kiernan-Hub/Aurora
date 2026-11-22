extends Coin

class_name MeltPortal

var entry_guard: Callable


class RiftVisual extends Node2D:
	const TITLE_FONT: Font = preload("res://assets/ui/fonts/display.tres")
	const INK: Color = Color(0.06, 0.09, 0.17)
	const FROST: Color = Color(0.77, 0.94, 1.0)
	const RIM: PackedVector2Array = [
		Vector2(0, -42), Vector2(17, -29), Vector2(29, -6), Vector2(22, 22),
		Vector2(3, 41), Vector2(-15, 29), Vector2(-28, 6), Vector2(-22, -21),
	]
	const OPENING: PackedVector2Array = [
		Vector2(1, -33), Vector2(12, -23), Vector2(21, -5), Vector2(15, 18),
		Vector2(2, 32), Vector2(-10, 23), Vector2(-21, 4), Vector2(-16, -16),
	]

	func _ready() -> void:
		# The ice and lettering are static draw commands. Only the light inside
		# changes, as one CanvasItem property on a tween that pauses with the run.
		var light := Polygon2D.new()
		light.polygon = PackedVector2Array([
			Vector2(0, -26), Vector2(6, -7), Vector2(13, -1), Vector2(5, 5),
			Vector2(1, 24), Vector2(-5, 7), Vector2(-12, 0), Vector2(-5, -6),
		])
		light.color = Color(0.94, 0.83, 0.98)
		add_child(light)
		var pulse: Tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(light, "modulate:a", 0.52, 1.0)
		pulse.tween_property(light, "modulate:a", 1.0, 1.0)

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.16, 1.12))
		draw_colored_polygon(RIM, Color(0.41, 0.77, 0.98, 0.18))
		draw_set_transform(Vector2.ZERO)
		draw_colored_polygon(RIM, INK)
		for i: int in range(RIM.size()):
			var next: int = (i + 1) % RIM.size()
			var facet := PackedVector2Array([RIM[i], RIM[next], OPENING[next], OPENING[i]])
			draw_colored_polygon(facet, FROST.lerp(Color(0.37, 0.57, 0.77), float(i % 4) * 0.24))
		draw_colored_polygon(OPENING, Color(0.13, 0.14, 0.27))
		draw_colored_polygon(PackedVector2Array([
			OPENING[7], OPENING[0], OPENING[3], OPENING[4], OPENING[5], OPENING[6],
		]), Color(0.34, 0.26, 0.44))
		draw_line(RIM[7], RIM[0], FROST, 1.5, true)
		draw_line(RIM[0], RIM[1], FROST, 1.5, true)
		draw_caption(TITLE_FONT, "The Melt", -52.0, 17)
		draw_caption(ThemeDB.fallback_font, "Jump to enter", 59.0, 13)

	func draw_caption(font: Font, caption: String, baseline: float, font_size: int) -> void:
		var start := Vector2(-font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5, baseline)
		draw_string_outline(font, start, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, INK)
		draw_string(font, start, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, FROST)


func _ready() -> void:
	var rift := RiftVisual.new()
	rift.name = "Visual"
	add_child(rift)
	super._ready()
	set_process(false)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	# An existing flight/boost keeps its ordinary behavior instead of being confiscated.
	if body.get(&"is_glide_active") or body.get(&"is_boosting"):
		return
	if entry_guard.is_valid() and not entry_guard.call():
		return
	super._on_body_entered(body)
