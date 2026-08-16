extends SceneTree

# Measures the RENDER layer, which every previous probe on this bug missed.
#
# WHY. camera_shake_probe.gd cut measured per-physics-frame camera jerk by 84%
# and playtest reported no clear improvement. That is the third metric on this
# bug to decouple from perception, and all three shared one blind spot: they
# sampled positions once per PHYSICS tick (60Hz fixed). What reaches the eye is
# sampled once per RENDER frame, at display refresh rate, and
# `physics_interpolation` is not set in project.godot -- so it is OFF, and a
# rendered frame shows whatever position the last physics tick happened to
# leave behind.
#
# When refresh rate != physics rate, that alone produces judder no amount of
# position smoothing can touch. At 120Hz refresh against 60Hz physics the world
# advances on only every other rendered frame (steps per render frame
# 1,0,1,0,...); if the accumulator drifts you get an irregular 1,0,1,1,0
# pattern, which is far more visible than a clean 60fps cadence. Either way the
# on-screen displacement alternates between 0px and a full physics step -- a
# ~100%-amplitude stutter that is invisible to a physics-tick-sampled probe
# because at that layer the motion is perfectly smooth.
#
# WHAT IT REPORTS
#   - display refresh rate vs. physics tick rate vs. achieved render FPS
#   - histogram of physics steps per rendered frame (the key number: anything
#     other than a steady 1 means the world is not advancing once per frame)
#   - render-frame pacing jitter (wall-clock delta between rendered frames)
#   - camera displacement measured PER RENDERED FRAME, including what fraction
#     of rendered frames showed zero movement -- the direct stutter amplitude
#
# Runs WINDOWED (must not be --headless: there is no real swapchain, vsync or
# refresh rate in headless, so the entire measurement would be meaningless).
# Self-terminating so it needs no external kill.
#
# Usage:
#   Godot --path . --script res://scripts/debug/archive/render_pacing_probe.gd -- \
#       [--seed=941462462] [--seconds=20]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const LOG_FILE_PATH: String = "res://scripts/debug/archive/render_pacing_probe_output.log"

class RenderSampler extends Node:
	var on_render_frame: Callable

	func _process(_delta: float) -> void:
		on_render_frame.call()


var main: Node
var player: Player
var camera_2d: Camera2D
var log_file: FileAccess

var warmup_start_usec: int = -1
var measure_start_usec: int = -1

var run_seconds: float = 20.0

var previous_camera_pos: Vector2 = Vector2.ZERO
var previous_camera_delta: Vector2 = Vector2.ZERO
var previous_physics_frames: int = 0
var previous_wall_usec: int = 0
var have_previous: bool = false
var have_previous_delta: bool = false

# steps-per-rendered-frame histogram, indexed by step count (clamped to 4+)
var step_histogram: Array[int] = [0, 0, 0, 0, 0]
var render_frame_count: int = 0
var zero_motion_frames: int = 0

var render_delta_sum: float = 0.0
var render_delta_min: float = 1.0e9
var render_delta_max: float = 0.0

# Per-rendered-frame camera displacement: this is literally how far the world
# slides on screen between two things the user actually sees.
var render_move_sum: float = 0.0
var render_move_max: float = 0.0
var render_jerk_sum: float = 0.0
var render_jerk_max: float = 0.0
var render_jerk_count: int = 0


func _init() -> void:
	var seed_text: String = get_string_argument("--seed", "941462462")
	run_seconds = get_float_argument("--seconds", 20.0)

	log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)

	main = MAIN_SCENE.instantiate()
	var terrain_generator: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = seed_text.to_int()
	root.add_child(main)
	await physics_frame
	camera_2d = main.camera_2d

	log_line("RENDER_PACING_PROBE_BEGIN seed=%s seconds=%.1f" % [seed_text, run_seconds])
	# Read the project setting rather than a node/SceneTree property: the
	# property's location moved across 4.x and guessing wrong aborts the whole
	# probe, while the setting name has been stable.
	log_line("physics_ticks_per_second=%d  physics_interpolation=%s" % [
		Engine.physics_ticks_per_second,
		str(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
	])
	log_line("screen_refresh_rate=%.2f Hz  vsync_mode=%d  max_fps=%d" % [
		DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen()),
		DisplayServer.window_get_vsync_mode(),
		Engine.max_fps,
	])

	# Sampling is driven by a real Node's _process rather than
	# `await process_frame` in this coroutine: the await form silently never
	# resumed here (probe exited cleanly having logged only its header), and a
	# node callback is the dependable way to get one call per rendered frame.
	var sampler: RenderSampler = RenderSampler.new()
	sampler.on_render_frame = _on_render_frame
	root.add_child(sampler)


# Warm up past window creation and first-frame shader/compile stalls before
# counting, or those land in the pacing histogram as phantom dropped frames.
func _on_render_frame() -> void:
	if warmup_start_usec < 0:
		warmup_start_usec = Time.get_ticks_usec()
		return
	if float(Time.get_ticks_usec() - warmup_start_usec) / 1000000.0 < 2.0:
		return

	if measure_start_usec < 0:
		measure_start_usec = Time.get_ticks_usec()
		previous_physics_frames = Engine.get_physics_frames()
		previous_wall_usec = Time.get_ticks_usec()
		return

	sample_render_frame()

	if float(Time.get_ticks_usec() - measure_start_usec) / 1000000.0 >= run_seconds:
		report()
		quit()


func sample_render_frame() -> void:
	var wall_usec: int = Time.get_ticks_usec()
	var physics_frames: int = Engine.get_physics_frames()
	var camera_pos: Vector2 = camera_2d.global_position

	var steps: int = physics_frames - previous_physics_frames
	previous_physics_frames = physics_frames

	var render_delta_ms: float = float(wall_usec - previous_wall_usec) / 1000.0
	previous_wall_usec = wall_usec

	render_frame_count += 1
	step_histogram[clampi(steps, 0, 4)] += 1
	render_delta_sum += render_delta_ms
	render_delta_min = minf(render_delta_min, render_delta_ms)
	render_delta_max = maxf(render_delta_max, render_delta_ms)

	if have_previous:
		var camera_delta: Vector2 = camera_pos - previous_camera_pos
		var move_length: float = camera_delta.length()
		render_move_sum += move_length
		render_move_max = maxf(render_move_max, move_length)
		if move_length < 0.0001:
			zero_motion_frames += 1
		if have_previous_delta:
			var jerk: float = (camera_delta - previous_camera_delta).length()
			render_jerk_sum += jerk
			render_jerk_max = maxf(render_jerk_max, jerk)
			render_jerk_count += 1
		previous_camera_delta = camera_delta
		have_previous_delta = true
	previous_camera_pos = camera_pos
	have_previous = true


func report() -> void:
	var frames: float = maxf(float(render_frame_count), 1.0)
	log_line("")
	log_line("=== RENDER PACING (%d rendered frames) ===" % render_frame_count)
	log_line("mean render delta %.3f ms (=> %.1f fps), min %.3f, max %.3f" % [
		render_delta_sum / frames, 1000.0 / maxf(render_delta_sum / frames, 0.0001),
		render_delta_min, render_delta_max,
	])
	log_line("")
	log_line("=== PHYSICS STEPS PER RENDERED FRAME ===")
	log_line("(a steady 1 is ideal; 0s and 2s mean the world does not advance once per frame)")
	for step_count: int in range(step_histogram.size()):
		var label: String = str(step_count) if step_count < 4 else "4+"
		log_line("  %2s steps : %6d frames (%5.1f%%)" % [
			label, step_histogram[step_count], float(step_histogram[step_count]) / frames * 100.0,
		])
	log_line("")
	log_line("=== ON-SCREEN CAMERA MOTION, PER RENDERED FRAME ===")
	log_line("frames with ZERO movement : %d (%.1f%%)  <-- stutter amplitude" % [
		zero_motion_frames, float(zero_motion_frames) / frames * 100.0,
	])
	log_line("mean movement %.4f px, max %.4f px" % [render_move_sum / frames, render_move_max])
	log_line("mean render-rate jerk %.4f px, max %.4f px" % [
		render_jerk_sum / maxf(float(render_jerk_count), 1.0), render_jerk_max,
	])
	log_line("")
	log_line("RENDER_PACING_PROBE_END")


func log_line(text: String) -> void:
	print(text)
	if log_file != null:
		log_file.store_line(text)
		log_file.flush()


func get_string_argument(argument_name: String, default_value: String) -> String:
	var prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return default_value


func get_float_argument(argument_name: String, default_value: float) -> float:
	var raw_value: String = get_string_argument(argument_name, "")
	if raw_value.is_empty():
		return default_value
	return raw_value.to_float()
