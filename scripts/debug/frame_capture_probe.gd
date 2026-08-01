extends SceneTree

# Captures real rendered frames to PNG so the shake can be measured from the
# PIXELS THE USER ACTUALLY SEES, instead of from an internal quantity that has
# to be argued to correspond to them.
#
# WHY. Every prior probe measured an internal number and every one of them
# decoupled from perception: contact-point anomaly, floor-snap displacement,
# frame-timing gaps, segment-entry, camera jerk (cut 84%, barely felt), render
# pacing (provably flawless), MSAA/edge aliasing (toggled live, no effect).
# The remaining honest move is to stop hypothesising about what moves and
# photograph it.
#
# Pairs with scripts/debug/analyze_frame_capture.py, which cross-correlates
# consecutive captures to recover how far the image ACTUALLY translated each
# frame, and how much of each frame fails to be explained by that translation
# (residual = something on screen moving differently from the global scroll).
#
# Capture starts only once the player is on a mega_drop, so the frames are of
# the segment under investigation rather than the approach to it.
#
# Runs WINDOWED (never --headless: no swapchain, nothing to capture).
# Self-terminating.
#
# Usage:
#   Godot --path . --script res://scripts/debug/frame_capture_probe.gd -- \
#       [--seed=941462462] [--frames=90] [--out=user://framecap]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
# mega_drop tops out at floor_max_angle * 0.9 = 40.5 degrees (0.707 rad); this
# gate keeps the capture on the genuinely steep face.
const MIN_CAPTURE_SLOPE_RADIANS: float = 0.55
const SPEED_CAP: float = 500.0


class CaptureDriver extends Node:
	var on_render_frame: Callable

	func _process(_delta: float) -> void:
		on_render_frame.call()


var main: Node
var player: Player
var terrain_generator: TerrainGenerator
var camera_2d: Camera2D

var frames_wanted: int = 90
var output_dir: String = "user://framecap"
var captured: int = 0
var warmup_frames_left: int = 120
var started: bool = false
var manifest: FileAccess
var polygon_antialiasing_wanted: bool = false


func _init() -> void:
	var seed_text: String = get_string_argument("--seed", "941462462")
	frames_wanted = get_int_argument("--frames", 90)
	output_dir = get_string_argument("--out", "user://framecap")

	DirAccess.make_dir_recursive_absolute(output_dir)

	main = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = seed_text.to_int()
	root.add_child(main)
	await physics_frame
	camera_2d = main.camera_2d

	# --msaa lets the capture A/B anti-aliasing objectively, instead of relying
	# on a by-eye toggle that may never have hit the steep face where the
	# quantisation actually shows.
	var msaa_level: int = get_int_argument("--msaa", 0)
	root.msaa_2d = msaa_level as Viewport.MSAA
	if get_int_argument("--polyaa", 0) != 0:
		polygon_antialiasing_wanted = true
	print("FRAME_CAPTURE msaa_2d=", msaa_level, " polygon_antialiased=", polygon_antialiasing_wanted)

	manifest = FileAccess.open(output_dir + "/manifest.csv", FileAccess.WRITE)
	manifest.store_line("index,world_x,camera_x,camera_y,player_x,player_y,sprite_rotation,segment")

	var driver: CaptureDriver = CaptureDriver.new()
	driver.on_render_frame = _on_render_frame
	root.add_child(driver)

	print("FRAME_CAPTURE_PROBE waiting for mega_drop, will capture ", frames_wanted, " frames to ", ProjectSettings.globalize_path(output_dir))


func _on_render_frame() -> void:
	if warmup_frames_left > 0:
		warmup_frames_left -= 1
		return

	var world_x: float = player.global_position.x

	# Run at the speed cap, not the 62s natural ramp: the reported shake is
	# worst at speed, and a probe that captures the ramp-up captures the mild
	# case. (First attempt at this capture also started at the mega_drop CREST,
	# where the surface is nearly flat -- rotation only reached 0.20 rad / 11
	# degrees. The reported shake is on the steep face, so gate on slope, not
	# merely on the segment label.)
	player.speed_manager.current_speed = SPEED_CAP

	# Chunks spawn and free continuously, so newly created ones would come back
	# un-antialiased; re-apply every frame so the setting holds all run.
	if polygon_antialiasing_wanted:
		for chunk: Node in terrain_generator.get_children():
			var terrain_fill: Polygon2D = chunk.get_node_or_null("TerrainFill") as Polygon2D
			if terrain_fill != null:
				terrain_fill.antialiased = true

	if not started:
		if get_segment_label_at(world_x) != "mega_drop":
			return
		if absf(terrain_generator.get_slope_angle_at_x(world_x)) < MIN_CAPTURE_SLOPE_RADIANS:
			return
		started = true
		print("FRAME_CAPTURE_BEGIN at world_x=", world_x, " slope=", terrain_generator.get_slope_angle_at_x(world_x), " rad")

	# Capturing the viewport forces a readback and makes frames take longer than
	# 16.7ms. That is fine and does NOT distort the measurement: the analysis
	# compares consecutive captured images to each other, and the physics step
	# between them is fixed at 1/60 regardless of how long the frame took.
	var image: Image = camera_2d.get_viewport().get_texture().get_image()
	image.save_png("%s/frame_%03d.png" % [output_dir, captured])
	manifest.store_line("%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.6f,%s" % [
		captured, world_x,
		camera_2d.global_position.x, camera_2d.global_position.y,
		player.global_position.x, player.global_position.y,
		player.color_rect.rotation,
		get_segment_label_at(world_x),
	])
	manifest.flush()
	captured += 1

	if captured >= frames_wanted:
		print("FRAME_CAPTURE_END captured=", captured)
		print("FRAME_CAPTURE_DIR ", ProjectSettings.globalize_path(output_dir))
		quit()


func get_segment_label_at(world_x: float) -> String:
	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	var segment_index: int = terrain_generator.find_segment_index_at_x(world_x)
	return String(terrain_generator.get_segment_spec(segment_index)["label"])


func get_string_argument(argument_name: String, default_value: String) -> String:
	var prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return default_value


func get_int_argument(argument_name: String, default_value: int) -> int:
	var raw_value: String = get_string_argument(argument_name, "")
	if raw_value.is_empty():
		return default_value
	return raw_value.to_int()
