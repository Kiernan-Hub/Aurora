extends SceneTree

# Read-only comparison of the actual rig at close-up and normal game scale.
# -- --out=/tmp/aura-strokes captures at least8s/two full cycles at30fps, then exits.
# Without --out it animates until the window is closed. Excluded from exports.
const STYLES: Array[int] = [2, SkaterRig.DEFAULT_STROKE]
const FPS: int = 30
class Board extends Control:
	var poses: Array[Array] = []
	var seconds: float = 0.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("202c3b"))
		for column: int in range(STYLES.size()):
			var style: int = STYLES[column]
			var left: float = column * 450.0
			var stroke: Dictionary = SkaterRig.STROKES[style]
			draw_string(ThemeDB.fallback_font, Vector2(left + 16, 30), stroke["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
			draw_string(ThemeDB.fallback_font, Vector2(left + 16, 55), "%.1fs per push" % (stroke["cycle"] * 0.5), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("b7cbdd"))
			if style == SkaterRig.DEFAULT_STROKE:
				draw_string(ThemeDB.fallback_font, Vector2(left + 16, 80), "Same timing / one smooth recovery arc", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("89dfda"))
				var phase: float = fposmod(seconds / (stroke["cycle"] * 0.5), 1.0)
				var stage: String = "Accelerating backward push" if phase < SkaterRig.GLIDE_DRIVE_END else "Knee up / recover / plant"
				draw_string(ThemeDB.fallback_font, Vector2(left + 16, 105), stage, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			draw_line(Vector2(left + 5, 340), Vector2(left + 445, 340), Color("a3cce5"))
			SkaterRig.draw_into(self, poses[column][0], seconds, 1.0, Vector2(left + 225, 220), 1.5)
			draw_string(ThemeDB.fallback_font, Vector2(left + 16, 390), "Normal game size / all skaters", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b7cbdd"))
			draw_line(Vector2(left + 5, 455), Vector2(left + 445, 455), Color("a3cce5"))
			for skin: int in range(Skins.SKINS.size()):
				SkaterRig.draw_into(self, poses[column][skin], seconds, 1.0, Vector2(left + 65 + skin * 80, 432.333), 0.283333)
			if column > 0:
				draw_line(Vector2(left, 12), Vector2(left, 480), Color("3b5065"))

var board: Board
var output: String = ""


func _init() -> void:
	call_deferred("run")


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	root.content_scale_size = Vector2i(900, 490)
	root.size = Vector2i(900, 490)
	board = Board.new()
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for style: int in STYLES:
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
	var count: int = roundi(maxf(SkaterRig.CYCLE_SECONDS * 2.0, 8.0) * FPS)
	for frame: int in range(count):
		board.seconds = float(frame) / FPS
		board.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%03d.png" % frame))
	print("SKATING_PREVIEW captured %d frames at %d fps: %s" % [count, FPS, output])
	quit()


func _process(delta: float) -> bool:
	if board != null and output.is_empty():
		board.seconds += delta
		board.queue_redraw()
	return false
