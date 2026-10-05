extends SceneTree

# Renders every biome from one run, for judging palettes side by side: first_light (absolute
# index 0, outside the cycle) and then all eight cycle palettes, nine shots.
#
# Not a gate. Companion to ice_look_capture.gd: that one shows what a real run looks
# like, this one answers "do all nine actually work" without playing for the ~13
# minutes a full cycle takes at BIOME_DISTANCE. Exits 1 if any image failed to save.
#
#   godot --path . --script res://scripts/debug/biome_contact_sheet.gd -- --out=/tmp/biome
#
# REPRODUCIBLE ORDER. The game rotates the arc and rolls rare variants per launch; this pins
# the rotation to 0 (the authored order) and the variant salt to one that rolls no variant on
# indices 0-8 today, so two runs give the same sheet of BASE palettes. Files are
# <out>_<index>_<palette>[_variant].png, so a variant that does roll (variant_chance changed)
# is labelled, not silent. It used to capture indices 0-7: first_light plus only seven of the
# eight, a random seven each launch.
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
const PINNED_VARIANT_SALT: int = 2
# first_light, then the whole cycle.
var capture_count: int = BiomeDirector.BIOME_CYCLE.size() + 1
var save_failures: int = 0

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
	BiomeDirector.session_cycle_rotation = 0
	BiomeDirector.session_variant_salt = PINNED_VARIANT_SALT
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

	if biome_index >= capture_count:
		quit(1 if save_failures > 0 else 0)
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
	var base: BiomePalette = director.get_cycle_base_palette(biome_index)
	# A variant is a duplicate with no resource_path, so the name comes from its base.
	var label: String = base.resource_path.get_file().get_basename() + ("" if palette == base else "_variant")
	var image: Image = root.get_texture().get_image()
	var path: String = "%s_%d_%s.png" % [output_prefix, biome_index, label]
	var error: Error = image.save_png(path) if image != null else ERR_CANT_CREATE
	if error != OK:
		save_failures += 1
		push_error("biome_contact_sheet: could not save %s (error %d)" % [path, error])
		return
	# Printed so the sheet can be checked against the data instead of by eye: the top-left sky
	# pixel should match this palette's sky_top, and must not match the PREVIOUS shot's, or the
	# capture is off by a frame again. A glow reaching that corner warms it (arctic_dawn's sits
	# at the top left), so a near-miss there is the palette, not the capture.
	print("biome=%d %s  sky_top_expected=%s  sky_top_rendered=%s" % [
		biome_index, label, palette.sky_top, image.get_pixel(4, 2)])
