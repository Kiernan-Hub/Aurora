extends SceneTree

# Measures what the sky glow ACTUALLY puts on screen, in pixels, per biome.
#
# WHY THIS EXISTS. biome_schedule_check.gd proves the glow data is well-formed -- colours in
# range, anchors on screen, blend_into carrying every field. It cannot prove the glow is
# VISIBLE, and the first version of the glow shipped passing every one of those checks while
# contributing 11/255 at its peak, which is nothing. Numbers being valid and pixels being
# different are two separate claims and only this file makes the second one.
#
#   godot --path . --script res://scripts/debug/glow_contribution_check.gd
#
# NOT --headless: this has to render. Exit code is 0 only if every biome clears
# MIN_PEAK_CONTRIBUTION, so it is usable as a gate despite needing a window.
#
# METHOD. For each palette, two captures of the SAME frame with the only difference being
# SkyGlow.visible, and the peak per-channel difference between them is the glow's
# contribution. Three things make that difference mean only the glow:
#
#   1. Engine.time_scale = 0. Without it the world scrolls between the two captures and the
#      diff measures terrain motion -- which is what made an earlier attempt at this report
#      22% of pixels changed by a glow that was actually contributing nothing.
#   2. The palette is pushed straight to SkyBackdrop.apply_palette() rather than through a
#      world_x, so terrain and snow never move between biomes either.
#   3. APPLY, WAIT, *THEN* CAPTURE. root.get_texture() hands back the frame already rendered,
#      so capturing in the same frame as the change silently measures the previous state.
#      Same trap biome_contact_sheet.gd documents at its head.
#
# WHAT A FAILURE MEANS. Almost always one of: the glow sits where scenery covers it, or its
# colour is too close to the sky colour it blends over (a near-white glow on a near-white sky
# moves nothing however high the strength), or the strength is simply too low.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const WARMUP_FRAMES: int = 40
const SETTLE_FRAMES: int = 6
# Peak difference, in 0-255 units, that a biome's glow must produce somewhere on screen.
# Calibrated against measurement, not taste: the original authoring produced 11-12 for the
# weakest biomes and read as "no glow at all" in game, while 33+ read as present. 24 sits
# between them with margin on both sides.
const MIN_PEAK_CONTRIBUTION: int = 24
# Every 4th pixel on both axes. The glow is a smooth blob hundreds of pixels across, so a
# full walk costs 16x more GDScript for no resolution that matters.
const SAMPLE_STRIDE: int = 4

var main: Node2D
var backdrop: Node
var glow: TextureRect
var frame_index: int = 0
var biome_index: int = 0
var phase: int = 0
var settle: int = 0
var armed: bool = false
var baseline: Image
var peaks: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	main = MAIN_SCENE.instantiate() as Node2D
	(main.get_node("GameManager") as GameManager).require_start_screen = false
	root.add_child(main)
	paused = false


func _process(_delta: float) -> bool:
	frame_index += 1
	# The window loses focus immediately and GameManager pauses on FOCUS_OUT, so PLAYING is
	# re-asserted every frame. The UI layer is hidden so labels never land in a capture.
	var game_manager: GameManager = main.get_node("GameManager") as GameManager
	if game_manager.state != GameManager.State.PLAYING:
		game_manager.set_state(GameManager.State.PLAYING)
	paused = false
	(main.get_node("CanvasLayer") as CanvasLayer).visible = false
	if frame_index < WARMUP_FRAMES:
		return false

	if glow == null:
		Engine.time_scale = 0.0
		# Hand control over, or the next frame recomputes the palette from the player's real x
		# and overwrites whatever this script set.
		(main.get_node("BiomeDirector") as BiomeDirector).set_process(false)
		backdrop = main.get_node("SkyBackdrop")
		glow = backdrop.get_node_or_null("SkyGlow") as TextureRect
		if glow == null:
			print("GLOW_CHECK FAIL  SkyBackdrop has no SkyGlow child")
			quit(1)
			return true

	if settle > 0:
		settle -= 1
		return false

	if armed:
		armed = false
		if phase == 0:
			baseline = root.get_texture().get_image()
		else:
			peaks.append(measure_peak(baseline, root.get_texture().get_image()))
		phase += 1
		if phase > 1:
			phase = 0
			biome_index += 1
		return false

	if biome_index >= BiomeDirector.BIOME_CYCLE.size():
		report()
		return true

	backdrop.apply_palette(BiomeDirector.BIOME_CYCLE[biome_index])
	# apply_palette sets visible from glow_strength; override it for the baseline pass so a
	# biome that legitimately has no glow still produces a comparable pair.
	glow.visible = phase == 1
	settle = SETTLE_FRAMES
	armed = true
	return false


func measure_peak(without_glow: Image, with_glow: Image) -> int:
	var peak: float = 0.0
	for y: int in range(0, without_glow.get_height(), SAMPLE_STRIDE):
		for x: int in range(0, without_glow.get_width(), SAMPLE_STRIDE):
			var a: Color = without_glow.get_pixel(x, y)
			var b: Color = with_glow.get_pixel(x, y)
			peak = maxf(peak, absf(b.r - a.r))
			peak = maxf(peak, absf(b.g - a.g))
			peak = maxf(peak, absf(b.b - a.b))
	return int(round(peak * 255.0))


func report() -> void:
	var failures: Array[String] = []
	print("")
	print("biome              strength   posY   peak/255   peak%")
	print("-----------------------------------------------------")
	for cycle_index: int in range(peaks.size()):
		var palette: BiomePalette = BiomeDirector.BIOME_CYCLE[cycle_index]
		var peak: int = peaks[cycle_index]
		print("%-18s %6.2f   %5.2f   %8d   %5.1f%%%s" % [
			palette.resource_path.get_file().get_basename(),
			palette.glow_strength, palette.glow_position.y,
			peak, 100.0 * float(peak) / 255.0,
			"   <-- BELOW FLOOR" if peak < MIN_PEAK_CONTRIBUTION else "",
		])
		if peak < MIN_PEAK_CONTRIBUTION:
			failures.append("%s glow peaks at %d/255, below the %d floor -- it is on screen but not visible. Raise glow_strength, move glow_position into unoccluded sky, or pick a glow_color further from this biome's sky colours"
				% [palette.resource_path.get_file().get_basename(), peak, MIN_PEAK_CONTRIBUTION])

	# Walked by hand: PackedInt32Array has no min()/max(), unlike Array.
	var weakest: int = peaks[0] if peaks.size() > 0 else 0
	var strongest: int = weakest
	for peak: int in peaks:
		weakest = mini(weakest, peak)
		strongest = maxi(strongest, peak)

	print("")
	if failures.is_empty():
		print("GLOW_CHECK PASS  biomes=%d  floor=%d/255  weakest=%d  strongest=%d"
			% [peaks.size(), MIN_PEAK_CONTRIBUTION, weakest, strongest])
		quit(0)
		return
	print("GLOW_CHECK FAIL  ", failures.size(), " violation(s)")
	for failure: String in failures:
		print("    ", failure)
	quit(1)
