extends SceneTree

# Throwaway visual capture for the ice pass. Runs main.tscn WITH a renderer (no
# --headless) and saves viewport PNGs, so a terrain/texture change can be checked
# without asking the project owner to be the renderer.
#
#   godot --path . --script res://scripts/debug/ice_look_capture.gd -- --out=/tmp/ice

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const WARMUP_FRAMES: int = 30
const SHOT_FRAMES: Array[int] = [90, 400, 900]

var main: Node2D
var output_prefix: String = "/tmp/ice"
var frame_index: int = 0
var shots_taken: int = 0


func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_prefix = argument.trim_prefix("--out=")
	main = MAIN_SCENE.instantiate() as Node2D
	(main.get_node("GameManager") as GameManager).require_start_screen = false
	root.add_child(main)
	paused = false


func _process(_delta: float) -> bool:
	frame_index += 1
	if frame_index < WARMUP_FRAMES:
		return false
	# The capture window loses focus the moment it opens, and GameManager pauses on
	# NOTIFICATION_APPLICATION_FOCUS_OUT -- so the state is re-asserted every frame or
	# every shot is of the pause overlay.
	var game_manager: GameManager = main.get_node("GameManager") as GameManager
	if game_manager.state != GameManager.State.PLAYING:
		game_manager.set_state(GameManager.State.PLAYING)
	paused = false
	(main.get_node("CanvasLayer") as CanvasLayer).visible = false

	if SHOT_FRAMES.has(frame_index):
		var image: Image = root.get_texture().get_image()
		var path: String = "%s_%d.png" % [output_prefix, frame_index]
		image.save_png(path)
		print("saved ", path, "  player_x=", (main.get_node("Player") as Node2D).global_position.x)
		shots_taken += 1
	if shots_taken >= SHOT_FRAMES.size():
		quit(0)
	return false
