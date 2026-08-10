extends SceneTree

# Measures what each optional sky layer ACTUALLY puts on screen, in pixels, per biome.
#
# WHY THIS EXISTS. biome_schedule_check.gd proves the sky data is well-formed -- colours in
# range, anchors on screen, blend_into carrying every field. It cannot prove any of it is
# VISIBLE, and the glow shipped in 92c7867 passing every one of those checks while
# contributing 11/255 at its peak, which is nothing. Numbers being valid and pixels being
# different are two separate claims and only this file makes the second one.
#
#   godot --path . --script res://scripts/debug/sky_layer_check.gd
#
# NOT --headless: this has to render. Exit code is 0 only if every layer that a biome claims
# to have clears MIN_PEAK_CONTRIBUTION, so it is usable as a gate despite needing a window.
#
# METHOD. For each palette and each layer, two captures of the SAME frame with the only
# difference being that layer's `visible`, and the peak per-channel difference between them is
# that layer's contribution. Three things make the difference mean only that layer, and each
# was learned by getting it wrong:
#
#   1. SceneTree.paused. Without a freeze the world scrolls between the two captures and the
#      diff measures terrain motion -- which is what made an earlier attempt report 22% of
#      pixels changed by a glow that was actually contributing nothing.
#
#      IT MUST BE `paused`, NOT `Engine.time_scale = 0`, and this file shipped the wrong one
#      once. time_scale 0 makes the physics delta zero, which trips the stall watchdog, fires
#      a world rebase, and -- because the camera follow is delta-driven and therefore frozen
#      too -- leaves the entire world off screen. Every capture is then a beautiful empty sky
#      with nothing in front of it, so every layer measures as fully visible and the gate
#      passes while the player can see none of it. That is exactly what happened: the glow
#      and disc reported 37-97/255 against a blank frame while being completely hidden behind
#      the parallax ridges in the real game.
#   2. The palette is pushed straight to SkyBackdrop.apply_palette() rather than through a
#      world_x, so terrain and snow never move between biomes either.
#   3. APPLY, WAIT, *THEN* CAPTURE. root.get_texture() hands back the frame already rendered,
#      so capturing in the same frame as the change silently measures the previous state.
#      Same trap biome_contact_sheet.gd documents at its head.
#
# A LAYER A BIOME DOES NOT CLAIM IS NOT A FAILURE. A palette with celestial_strength = 0 has
# deliberately no disc -- four of the eight are authored that way. Those are reported as "--"
# and skipped, and only a layer whose strength is above zero has to clear the floor.
#
# WHAT A FAILURE MEANS. Almost always one of: the layer sits where scenery covers it, or its
# colour is too close to the sky colour it blends over (a near-white glow on a near-white sky
# moves nothing however high the strength), or the strength is simply too low.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const WARMUP_FRAMES: int = 90
const SETTLE_FRAMES: int = 6
# Peak difference, in 0-255 units, that a claimed layer must produce somewhere on screen.
# Calibrated against measurement, not taste: the original glow authoring produced 11-12 for
# the weakest biomes and read as "no glow at all" in game, while 33+ read as present. 24 sits
# between them with margin on both sides.
const MIN_PEAK_CONTRIBUTION: int = 24

# [label, palette field, mode]
#
# MODE_VISIBLE toggles a child node of SkyBackdrop, which is how an optional overlay layer is
# measured. MODE_TINT has no node to toggle: the horizontal sky tint is baked INTO the sky
# gradient texture, so its baseline is the same palette with the tints neutralised to white
# and the difference between the two bakes is its contribution. Same two-capture shape either
# way, so the rest of this file does not care which it is.
const MODE_VISIBLE: String = "visible"
const MODE_TINT: String = "tint"
const LAYERS: Array[Array] = [
	["SkyGlow", "glow_strength", MODE_VISIBLE],
	["SkyCelestial", "celestial_strength", MODE_VISIBLE],
	["SkyStars", "star_density", MODE_VISIBLE],
	["SkyTint", "", MODE_TINT],
]

var main: Node2D
var backdrop: Node
var frame_index: int = 0
var biome_index: int = 0
var layer_index: int = 0
var phase: int = 0
var settle: int = 0
var armed: bool = false
var started: bool = false
var baseline: Image
# [biome_index][layer_index] -> peak, or -1 for "biome does not claim this layer"
var peaks: Array[PackedInt32Array] = []


func _init() -> void:
	main = MAIN_SCENE.instantiate() as Node2D
	(main.get_node("GameManager") as GameManager).require_start_screen = false
	root.add_child(main)
	paused = false


func _process(_delta: float) -> bool:
	frame_index += 1
	# The UI layer is hidden so labels never land in a capture.
	(main.get_node("CanvasLayer") as CanvasLayer).visible = false

	if frame_index < WARMUP_FRAMES:
		# During warmup only: the window loses focus immediately and GameManager pauses on
		# FOCUS_OUT, so PLAYING is re-asserted until the world has built and settled.
		var game_manager: GameManager = main.get_node("GameManager") as GameManager
		if game_manager.state != GameManager.State.PLAYING:
			game_manager.set_state(GameManager.State.PLAYING)
		paused = false
		return false

	# From here the tree stays paused: nothing processes, nothing rebases, rendering
	# continues, and the world stays exactly where it is between the two captures. This
	# script is a SceneTree, so its own _process keeps running regardless.
	paused = true

	if not started:
		started = true
		# Hand control over, or the next frame recomputes the palette from the player's real x
		# and overwrites whatever this script set.
		(main.get_node("BiomeDirector") as BiomeDirector).set_process(false)
		backdrop = main.get_node("SkyBackdrop")
		for layer: Array in LAYERS:
			# MODE_TINT has no node of its own -- it is baked into the sky texture.
			if layer[2] != MODE_VISIBLE:
				continue
			if backdrop.get_node_or_null(NodePath(layer[0])) == null:
				print("SKY_LAYER_CHECK FAIL  SkyBackdrop has no ", layer[0], " child")
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
			peaks[biome_index][layer_index] = measure_peak(baseline, root.get_texture().get_image())
		phase += 1
		if phase > 1:
			phase = 0
			layer_index += 1
			if layer_index >= LAYERS.size():
				layer_index = 0
				biome_index += 1
		return false

	if biome_index >= BiomeDirector.BIOME_CYCLE.size():
		report()
		return true

	var palette: BiomePalette = BiomeDirector.BIOME_CYCLE[biome_index]
	while peaks.size() <= biome_index:
		var row: PackedInt32Array = PackedInt32Array()
		row.resize(LAYERS.size())
		row.fill(-1)
		peaks.append(row)

	# Skip a layer this biome does not claim, rather than measuring it as zero and failing.
	if not claims_layer(palette, layer_index):
		layer_index += 1
		if layer_index >= LAYERS.size():
			layer_index = 0
			biome_index += 1
		return false

	if LAYERS[layer_index][2] == MODE_TINT:
		# Phase 0 bakes the same sky with the horizontal tints removed. duplicate() so the
		# real palette resource is never mutated -- it is the one the game loads.
		var probe: BiomePalette = palette
		if phase == 0:
			probe = palette.duplicate() as BiomePalette
			probe.sky_tint_left = Color.WHITE
			probe.sky_tint_right = Color.WHITE
		backdrop.apply_palette(probe)
	else:
		# Applied straight to the backdrop, so terrain and everything else stay put and only
		# the sky changes between biomes.
		backdrop.apply_palette(palette)
		# apply_palette sets each layer's visible from its strength; override only the layer
		# under test, so every other layer is identical in both captures and cancels out.
		(backdrop.get_node(NodePath(LAYERS[layer_index][0])) as CanvasItem).visible = phase == 1
	settle = SETTLE_FRAMES
	armed = true
	return false


# A biome "claims" a toggled layer when its strength is above zero, and claims the horizontal
# tint when either end is not white -- white being the documented "no horizontal variation".
func claims_layer(palette: BiomePalette, index: int) -> bool:
	if LAYERS[index][2] == MODE_TINT:
		return palette.sky_tint_left != Color.WHITE or palette.sky_tint_right != Color.WHITE
	return float(palette.get(LAYERS[index][1])) > 0.0


# Exact peak per-channel difference over EVERY pixel, compared as raw bytes.
#
# Full density, not strided, and that matters as soon as a layer is made of small features: a
# star is a ONE PIXEL dot, and a 4px stride samples any given one with probability 1/16. The
# earlier strided-plus-dense-window version was written for the glow (a smooth blob hundreds
# of pixels across) and would have under-reported the starfield badly enough to fail it.
#
# Raw bytes rather than get_pixel(): converting both frames to RGB8 and walking the
# PackedByteArrays is a flat integer loop, which is fast enough in GDScript to afford full
# density over ~750k pixels, where 1.5M get_pixel() calls per measurement would not be.
# Converting mutates the images, which is fine -- each is used for exactly one comparison.
func measure_peak(without_layer: Image, with_layer: Image) -> int:
	without_layer.convert(Image.FORMAT_RGB8)
	with_layer.convert(Image.FORMAT_RGB8)
	var without_bytes: PackedByteArray = without_layer.get_data()
	var with_bytes: PackedByteArray = with_layer.get_data()
	if without_bytes.size() != with_bytes.size():
		return 0

	var peak: int = 0
	for byte_index: int in range(without_bytes.size()):
		var difference: int = absi(int(with_bytes[byte_index]) - int(without_bytes[byte_index]))
		if difference > peak:
			peak = difference
	return peak


func report() -> void:
	var failures: Array[String] = []
	print("")
	print("biome              SkyGlow   SkyCelestial   SkyStars   SkyTint")
	print("---------------------------------------------------------------")
	for cycle_index: int in range(peaks.size()):
		var palette: BiomePalette = BiomeDirector.BIOME_CYCLE[cycle_index]
		var cells: PackedStringArray = PackedStringArray()
		for column: int in range(LAYERS.size()):
			var peak: int = peaks[cycle_index][column]
			if peak < 0:
				cells.append("      --")
				continue
			cells.append("%4d%s" % [peak, " LOW!" if peak < MIN_PEAK_CONTRIBUTION else "     "])
			if peak < MIN_PEAK_CONTRIBUTION:
				failures.append("%s %s peaks at %d/255, below the %d floor -- it is on screen but not visible. Raise its strength, move it into unoccluded sky, or pick a colour further from this biome's sky colours"
					% [palette.resource_path.get_file().get_basename(), LAYERS[column][0], peak, MIN_PEAK_CONTRIBUTION])
		print("%-18s %s  %s  %s  %s" % [palette.resource_path.get_file().get_basename(),
			cells[0], cells[1], cells[2], cells[3]])

	var claimed: int = 0
	for row: PackedInt32Array in peaks:
		for peak: int in row:
			if peak >= 0:
				claimed += 1
	print("")
	if failures.is_empty():
		print("SKY_LAYER_CHECK PASS  biomes=%d  layers_measured=%d  floor=%d/255"
			% [peaks.size(), claimed, MIN_PEAK_CONTRIBUTION])
		quit(0)
		return
	print("SKY_LAYER_CHECK FAIL  ", failures.size(), " violation(s)")
	for failure: String in failures:
		print("    ", failure)
	quit(1)
