extends SceneTree

# Read-only comparison of the actual rig at close-up and normal game scale.
# -- --out=/tmp/aura-strokes captures 12 seconds at 24 fps, then exits.
# Without --out it animates until the window is closed. Excluded from exports.
class Board extends Control:
	var poses: Array[Array] = []
	var seconds: float = 0.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("202c3b"))
		for style: int in range(SkaterRig.STROKES.size()):
			var left: float = style * 300.0
			var stroke: Dictionary = SkaterRig.STROKES[style]
			draw_string(ThemeDB.fallback_font, Vector2(left + 16, 30), stroke["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
			draw_string(ThemeDB.fallback_font, Vector2(left + 16, 55), "%.1fs per push" % (stroke["cycle"] * 0.5), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("b7cbdd"))
			if style == SkaterRig.DEFAULT_STROKE:
				draw_string(ThemeDB.fallback_font, Vector2(left + 16, 80), "Current pick", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("89dfda"))
			draw_line(Vector2(left + 5, 340), Vector2(left + 295, 340), Color("a3cce5"))
			SkaterRig.draw_into(self, poses[style][0], seconds, 1.0, Vector2(left + 150, 220), 1.5)
			draw_string(ThemeDB.fallback_font, Vector2(left + 16, 390), "Normal game size / all skaters", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b7cbdd"))
			draw_line(Vector2(left + 5, 455), Vector2(left + 295, 455), Color("a3cce5"))
			for skin: int in range(Skins.SKINS.size()):
				SkaterRig.draw_into(self, poses[style][skin], seconds, 1.0, Vector2(left + 30 + skin * 60, 432.333), 0.283333)
			if style > 0:
				draw_line(Vector2(left, 12), Vector2(left, 480), Color("3b5065"))

var board: Board
var output: String = ""


func _init() -> void:
	call_deferred("run")


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	root.content_scale_size = Vector2i(1200, 490)
	root.size = Vector2i(1200, 490)
	board = Board.new()
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for style: int in range(SkaterRig.STROKES.size()):
		var skins: Array = []
		for skin: Dictionary in Skins.SKINS:
			skins.append(SkaterRig.create_draw_data(load(skin["frames"]), style))
		board.poses.append(skins)
	if output.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Could not create preview directory: " + output)
		quit(1)
		return
	for frame: int in range(288):
		board.seconds = float(frame) / 24.0
		board.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%03d.png" % frame))
	print("SKATING_PREVIEW captured 288 frames at 24 fps: " + output)
	quit()


func _process(delta: float) -> bool:
	if board != null and output.is_empty():
		board.seconds += delta
		board.queue_redraw()
	return false
