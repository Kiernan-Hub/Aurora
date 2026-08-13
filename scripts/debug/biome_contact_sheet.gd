extends SceneTree

# Renders every biome in the cycle from one run, for judging palettes side by side.
#
# Not a gate. Companion to ice_look_capture.gd: that one shows what a real run looks
# like, this one answers "do all eight actually work" without playing for the ~13
# minutes a full cycle takes at BIOME_DISTANCE.
#
#   godot --path . --script res://scripts/debug/biome_contact_sheet.gd -- --out=/tmp/biome
#
# Works by suspending BiomeDirector._process and driving apply_palette_for_world_x()
# by hand at the CENTRE of each biome's span -- centre, so every shot is a settled
# palette rather than a point part-way through a crossfade. The game itself is
# untouched: the player never moves, no constant is overridden, and nothing here runs
# unless this script is the entry point.
#
# APPLY, WAIT, *THEN* CAPTURE -- never apply and capture in one frame.
# root.get_texture() hands back the frame that has already been rendered, so capturing
# straight after setting a palette silently saves the PREVIOUS biome's colours. The
# first version of this file did exactly that and produced a contact sheet shifted by
# one, which read as "all eight palettes look the same" and nearly sent a real palette
# rewrite after a bug that was entirely in this script.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const WARMUP_FRAMES: int = 40
# Frames between setting a palette and capturing it. Needs to cover at least one render
# plus snow_drift's density lerp, which eases rather than snapping.
const SETTLE_FRAMES: int = 8

var main: Node2D
var director: BiomeDirector
var output_prefix: String = "/tmp/biome"
var frame_index: int = 0
var biome_index: int = 0
var settle_countdown: int = 0
var awaiting_capture: bool = false


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
	# The capture window loses focus immediately and GameManager pauses on
	# NOTIFICATION_APPLICATION_FOCUS_OUT, so PLAYING is re-asserted every frame.
	var game_manager: GameManager = main.get_node("GameManager") as GameManager
	if game_manager.state != GameManager.State.PLAYING:
		game_manager.set_state(GameManager.State.PLAYING)
	paused = false
	(main.get_node("CanvasLayer") as CanvasLayer).visible = false

	if frame_index < WARMUP_FRAMES:
		return false

	if director == null:
		director = main.get_node("BiomeDirector") as BiomeDirector
		# Hand control over: otherwise the next frame recomputes the palette from the
		# player's real x and overwrites whatever this script just set.
		director.set_process(false)

	if settle_countdown > 0:
		settle_countdown -= 1
		return false

	if awaiting_capture:
		capture_current()
		awaiting_capture = false
		biome_index += 1
		return false

	if biome_index >= BiomeDirector.BIOME_CYCLE.size():
		quit(0)
		return true

	# Mid-biome, so the palette is fully settled and not part-way through a crossfade.
	director.apply_palette_for_world_x((float(biome_index) + 0.5) * BiomeDirector.BIOME_DISTANCE)
	settle_countdown = SETTLE_FRAMES
	awaiting_capture = true
	return false


func capture_current() -> void:
	# Through the director, not BIOME_CYCLE[biome_index]: the arc is rotated by a random amount
	# each session (BiomeDirector.session_cycle_rotation), so indexing the authored array would
	# label every capture with the wrong biome.
	var palette: BiomePalette = director.get_cycle_palette(biome_index)
	var image: Image = root.get_texture().get_image()
	image.save_png("%s_%d.png" % [output_prefix, biome_index])
	# Printed so the sheet can be checked against the data instead of by eye: the top
	# sky pixel must match this palette's sky_top, or the capture is off by a frame again.
	print("biome=%d %s  sky_top_expected=%s  sky_top_rendered=%s" % [
		biome_index, palette.resource_path.get_file().get_basename(), palette.sky_top,
		image.get_pixel(4, 2)])
