extends SceneTree

# Settles whether the SCREEN position of the world is snapped to whole pixels.
#
# Frame captures on the steep mega_drop face showed the terrain tracking the
# camera closely and then periodically lurching a whole pixel and snapping back
# (+1px, then -1px a frame or two later), while the camera itself moves in
# perfectly smooth fractional steps. That is the signature of the rendered
# position being rounded. Anti-aliasing reduced the measured jerk but did not
# remove those whole-pixel corrections, which points at the TRANSFORM rather
# than the rasterisation.
#
# This measures it directly and unambiguously, with no image processing: it
# projects a FIXED WORLD POINT through the actual canvas/viewport transform
# every physics frame and logs where it lands on screen.
#
#   screen_pos fractional and smoothly varying -> transform is not snapped,
#       and any whole-pixel motion is pure rasterisation of hard edges (fix is
#       anti-aliasing / rendering, and the transform is innocent).
#   screen_pos integral, or its delta quantised -> something IS snapping the
#       canvas transform (project settings `rendering/2d/snap/*`, or the
#       `canvas_items` stretch mode), and that is the bug.
#
# Also dumps the relevant project settings so the answer is self-contained.
#
# Runs WINDOWED (the stretch/canvas transform is meaningless headless).
#
# Usage:
#   Godot --path . --script res://scripts/debug/canvas_transform_probe.gd -- \
#       [--seed=941462462] [--frames=240]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SPEED_CAP: float = 500.0
const MIN_SLOPE_RADIANS: float = 0.55

var main: Node
var player: Player
var terrain_generator: TerrainGenerator
var camera_2d: Camera2D
var frames_wanted: int = 240
var logged: int = 0
var started: bool = false
var reference_world_point: Vector2 = Vector2.ZERO


func _init() -> void:
	var seed_text: String = get_string_argument("--seed", "941462462")
	frames_wanted = get_int_argument("--frames", 240)

	main = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = seed_text.to_int()
	root.add_child(main)
	await physics_frame
	camera_2d = main.camera_2d

	print("=== RELEVANT PROJECT SETTINGS ===")
	for setting_name: String in [
		"rendering/2d/snap/snap_2d_transforms_to_pixel",
		"rendering/2d/snap/snap_2d_vertices_to_pixel",
		"display/window/stretch/mode",
		"display/window/stretch/aspect",
		"display/window/stretch/scale",
		"display/window/size/viewport_width",
		"display/window/size/viewport_height",
	]:
		print("  %s = %s" % [setting_name, str(ProjectSettings.get_setting(setting_name, "<unset>"))])
	print("  window size          = ", DisplayServer.window_get_size())
	print("  root content_scale_mode    = ", root.content_scale_mode)
	print("  root content_scale_stretch = ", root.content_scale_stretch)
	print("  root content_scale_factor  = ", root.content_scale_factor)
	print("  root content_scale_size    = ", root.content_scale_size)
	print("")
	print("frame,camera_x,camera_y,screen_x,screen_y,d_screen_x,d_screen_y,d_camera_x,d_camera_y")

	var previous_screen: Vector2 = Vector2.ZERO
	var previous_camera: Vector2 = Vector2.ZERO
	var have_previous: bool = false

	while logged < frames_wanted:
		await physics_frame
		player.speed_manager.current_speed = SPEED_CAP
		var world_x: float = player.global_position.x
		if not started:
			if terrain_generator.get_segment_spec(terrain_generator.find_segment_index_at_x(world_x))["label"] != "mega_drop":
				continue
			if absf(terrain_generator.get_slope_angle_at_x(world_x)) < MIN_SLOPE_RADIANS:
				continue
			started = true
			# A world point that never moves; its screen position is therefore a
			# pure readout of the transform.
			reference_world_point = Vector2(round(world_x / 512.0) * 512.0, 0.0)

		# The full world->screen chain, exactly what the renderer applies.
		var transform: Transform2D = camera_2d.get_viewport().get_screen_transform() * camera_2d.get_viewport().get_canvas_transform()
		var screen_position: Vector2 = transform * reference_world_point
		var camera_position: Vector2 = camera_2d.global_position

		if have_previous:
			print("%d,%.4f,%.4f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
				logged,
				camera_position.x, camera_position.y,
				screen_position.x, screen_position.y,
				screen_position.x - previous_screen.x, screen_position.y - previous_screen.y,
				camera_position.x - previous_camera.x, camera_position.y - previous_camera.y,
			])
		previous_screen = screen_position
		previous_camera = camera_position
		have_previous = true
		logged += 1

	quit()


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
