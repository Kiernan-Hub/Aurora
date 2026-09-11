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
# The ice band's contrast has its own floor -- see the note on LAYERS for why it cannot be held
# to the one above. Calibrated by measurement: across the eight biomes the peak comes out at
# very close to 78 * |1 - ice_contrast|, because the pixels that move most are the tile's
# surface rows and they are a fixed distance from CONTRAST_PIVOT. So this floor is really a
# floor on the AUTHORING -- 10/255 is |1 - contrast| >= 0.13, below which the field is set but
# is not a decision anyone would see. The first authoring pass had two biomes under it (5 and
# 9/255) and that is exactly what this caught.
const MIN_ICE_CONTRAST_CONTRIBUTION: int = 10

# [label, palette field, mode, OFF value, floor]
#
# MODE_VISIBLE toggles a child node of SkyBackdrop, which is how an optional overlay layer is
# measured. MODE_TINT has no node to toggle: the horizontal sky tint is baked INTO the sky
# gradient texture, so its baseline is the same palette with the tints neutralised to white
# and the difference between the two bakes is its contribution. Same two-capture shape either
# way, so the rest of this file does not care which it is.
# MODE_ICE is a third shape again: the ice hue drift is written into terrain vertex colours,
# so its baseline is the same palette with ice_hue_variance zeroed and pushed through
# TerrainGenerator.apply_ice_palette() rather than through the backdrop. Still two captures of
# one frame differing in one thing, which is all the rest of this file assumes.
#
# THE OFF VALUE IS NOT ALWAYS 0. Every layer here was a strength until ice_contrast, whose
# identity is 1.0 -- so "the same palette with this turned off" and "this biome claims this
# layer" both have to be asked against the field's own identity, not against zero. Zeroing
# ice_contrast would not be a baseline at all: it would flatten the tile to a flat grey and
# measure a difference far larger than the effect being tested.
#
# THE FLOOR IS PER ROW for the same reason. MIN_PEAK_CONTRIBUTION was calibrated on the sky
# overlays, which composite over open sky and can move a pixel most of the way to their own
# colour. Contrast cannot: it moves the tile toward or away from a pivot the tile is already
# near, and the surface rows it affects most sit at ~1.0 where a value above 1 clamps outright.
# Holding it to the sky floor would demand a flattening strong enough to wash the ice out.
const MODE_VISIBLE: String = "visible"
const MODE_TINT: String = "tint"
const MODE_ICE: String = "ice"
const LAYERS: Array[Array] = [
	["SkyGlow", "glow_strength", MODE_VISIBLE, 0.0, MIN_PEAK_CONTRIBUTION],
	["SkyCelestial", "celestial_strength", MODE_VISIBLE, 0.0, MIN_PEAK_CONTRIBUTION],
	["SkyStars", "star_density", MODE_VISIBLE, 0.0, MIN_PEAK_CONTRIBUTION],
	["SkyTint", "", MODE_TINT, 0.0, MIN_PEAK_CONTRIBUTION],
	["IceHue", "ice_hue_variance", MODE_ICE, 0.0, MIN_PEAK_CONTRIBUTION],
	["SnowCap", "snow_cap_strength", MODE_ICE, 0.0, MIN_PEAK_CONTRIBUTION],
	["IceContrast", "ice_contrast", MODE_ICE, 1.0, MIN_ICE_CONTRAST_CONTRIBUTION],
]

var main: Node2D
var backdrop: Node
var terrain: TerrainGenerator
var frame_index: int = 0
var biome_index: int = 0
var layer_index: int = 0
var phase: int = 0
var settle: int = 0
var armed: bool = false
var started: bool = false
# quit() inside _init() does not stop the tree from running _process once, and by then `main`
# is still null -- so the abort below has to be latched and re-checked there.
var aborted: bool = false
var checking_aurora: bool = false
var aurora_failures: Array[String] = []
var baseline: Image
# [biome_index][layer_index] -> peak, or -1 for "biome does not claim this layer"
var peaks: Array[PackedInt32Array] = []


func _init() -> void:
	# REFUSES to run under --headless rather than measuring it. There is no rendering device
	# there, so capture_rendered_frame() hands back a blank frame, every layer diffs to
	# 0/255, and this gate reports every claimed layer in every biome as invisible -- 19
	# confident, meaningless violations. That is the same blank-frame failure this file's header
	# already records for Engine.time_scale = 0, just with the sign flipped (there everything
	# measured as fully visible and the gate PASSED). Both directions are worse than an error,
	# which is what CLAUDE.md means about archived probes printing numbers instead of failing.
	if DisplayServer.get_name() == "headless":
		print("SKY_LAYER_CHECK FAIL  cannot run under --headless: this gate has to render.")
		print("    Re-run without --headless (it opens a window):")
		print("    /Applications/Godot.app/Contents/MacOS/Godot --path . --script res://scripts/debug/sky_layer_check.gd")
		aborted = true
		quit(1)
		return

	main = MAIN_SCENE.instantiate() as Node2D
	(main.get_node("GameManager") as GameManager).require_start_screen = false
	root.add_child(main)
	paused = false


func _process(_delta: float) -> bool:
	if aborted:
		return true
	if checking_aurora:
		return false

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
		terrain = main.get_node("TerrainGenerator") as TerrainGenerator
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
			baseline = capture_rendered_frame()
		else:
			peaks[biome_index][layer_index] = measure_peak(baseline, capture_rendered_frame())
		phase += 1
		if phase > 1:
			phase = 0
			layer_index += 1
			if layer_index >= LAYERS.size():
				layer_index = 0
				biome_index += 1
		return false

	if biome_index >= get_measured_palettes().size():
		checking_aurora = true
		check_aurora()
		return false

	var palette: BiomePalette = get_measured_palettes()[biome_index]
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

	if LAYERS[layer_index][2] == MODE_ICE:
		var ice_probe: BiomePalette = palette
		if phase == 0:
			ice_probe = palette.duplicate() as BiomePalette
			# Set whichever field this row names to ITS OWN off value, so one mode covers every
			# terrain-side palette scalar rather than needing a mode per field.
			ice_probe.set(LAYERS[layer_index][1], LAYERS[layer_index][3])
		# Straight to the generator, the way BiomeDirector.push_palette() does it. Weight 0 and
		# the same texture at both ends, so the pattern dissolve contributes nothing and the
		# only difference between the two captures is the drift.
		terrain.apply_ice_palette(ice_probe, ice_probe.ice_texture, ice_probe.ice_texture, 0.0)
	elif LAYERS[layer_index][2] == MODE_TINT:
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


# A biome "claims" a layer when its field differs from that field's OFF value, and claims the
# horizontal tint when either end is not white -- white being the documented "no horizontal
# variation". Not `> 0.0`: ice_contrast is off at 1.0 and a biome may deliberately sit below it.
func claims_layer(palette: BiomePalette, index: int) -> bool:
	if LAYERS[index][2] == MODE_TINT:
		return palette.sky_tint_left != Color.WHITE or palette.sky_tint_right != Color.WHITE
	return not is_equal_approx(float(palette.get(LAYERS[index][1])), float(LAYERS[index][3]))


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


# The opening biome first, then the cycle. first_light is NOT in BIOME_CYCLE (see
# BiomeDirector.PALETTE_FIRST_LIGHT), and it is the single palette every session is
# guaranteed to show -- so leaving it out would mean the one biome nobody can miss is the
# one biome nothing measures. It is also the likeliest to fail: it is deliberately pale and
# low-saturation, and the hue drift only ever darkens, so there is less to remove.
func get_measured_palettes() -> Array[BiomePalette]:
	var measured: Array[BiomePalette] = [BiomeDirector.PALETTE_FIRST_LIGHT]
	measured.append_array(BiomeDirector.BIOME_CYCLE)
	return measured


func report() -> void:
	var failures: Array[String] = aurora_failures.duplicate()
	print("")
	# Header built from LAYERS rather than written out, so adding a row cannot silently shift
	# every column under the wrong heading. Column width matches the "%4d LOW!" cells below.
	var header: String = "%-18s" % "biome"
	for layer: Array in LAYERS:
		header += "%-13s" % layer[0]
	print(header)
	print("-".repeat(header.length()))
	for cycle_index: int in range(peaks.size()):
		var palette: BiomePalette = get_measured_palettes()[cycle_index]
		var row_text: String = "%-18s" % palette.resource_path.get_file().get_basename()
		for column: int in range(LAYERS.size()):
			var peak: int = peaks[cycle_index][column]
			if peak < 0:
				row_text += "%-13s" % "  --"
				continue
			var floor_value: int = int(LAYERS[column][4])
			row_text += "%-13s" % ("%4d%s" % [peak, " LOW!" if peak < floor_value else ""])
			if peak < floor_value:
				failures.append("%s %s peaks at %d/255, below its %d floor -- it is on screen but not visible. Raise its strength, move it into unoccluded sky, or pick a colour further from this biome's sky colours"
					% [palette.resource_path.get_file().get_basename(), LAYERS[column][0], peak, floor_value])
		print(row_text)

	var claimed: int = 0
	for row: PackedInt32Array in peaks:
		for peak: int in row:
			if peak >= 0:
				claimed += 1
	print("")
	if failures.is_empty():
		print("SKY_LAYER_CHECK PASS  biomes=%d  layers_measured=%d  floor=%d/255 (ice contrast %d/255)"
			% [peaks.size(), claimed, MIN_PEAK_CONTRIBUTION, MIN_ICE_CONTRAST_CONTRIBUTION])
		quit(0)
		return
	print("SKY_LAYER_CHECK FAIL  ", failures.size(), " violation(s)")
	for failure: String in failures:
		print("    ", failure)
	quit(1)


# Render the actual director ramp against real scenery. In particular, a healthy
# green texture hidden behind the ridges must fail, even if violet still contributes.
func check_aurora() -> void:
	var director: AuroraDirector = main.get_node("AuroraDirector")
	var biome: BiomeDirector = main.get_node("BiomeDirector")
	var wash: CanvasLayer = main.get_node_or_null("AuroraWash") as CanvasLayer
	var blade_glow: Node2D = main.get_node_or_null("AuroraBladeGlow") as Node2D
	var snow: GPUParticles2D = main.get_node_or_null("SnowDrift/SnowParticles") as GPUParticles2D
	var wisps: Node2D = main.get_node_or_null("AuroraWisps") as Node2D
	var wings: Node2D = main.get_node_or_null("AuroraWings") as Node2D
	var aurora_audio: AuroraAudio = main.get_node_or_null("AuroraAudio") as AuroraAudio
	if wash == null or wash.layer != -45:
		aurora_failures.append("Aurora wash is missing or not structurally behind gameplay at layer -45")
	elif wash.get_node_or_null("Wash") == null \
			or (wash.get_node("Wash") as TextureRect).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		aurora_failures.append("Aurora wash is missing its input-transparent full-screen draw")
	if blade_glow == null or blade_glow.get_node_or_null("Halo") == null \
			or blade_glow.get_node_or_null("Core") == null:
		aurora_failures.append("Aurora blade glow is missing its halo or core")
	if snow == null or not snow.has_method("apply_aurora") \
			or not snow.has_method("get_target_amount_ratio"):
		aurora_failures.append("Snow does not expose one composed Aurora density target")
	if wisps == null or wisps.get_child_count() != 3 \
			or wisps.get_index() > main.get_node("Player").get_index() \
			or wisps.get_index() > main.get_node("TerrainGenerator").get_index():
		aurora_failures.append("Aurora wisps are missing or not structurally behind gameplay")
	if wings == null or wings.get_child_count() != 6 \
			or wings.get_index() > main.get_node("Player").get_index() \
			or wings.get_index() > main.get_node("TerrainGenerator").get_index():
		aurora_failures.append("Aurora wings are missing or not structurally behind gameplay")
	if aurora_audio == null or aurora_audio.audio_player == null:
		aurora_failures.append("Aurora dedicated audio player is missing")
	else:
		var audio_stream: AudioStreamWAV = aurora_audio.audio_player.stream as AudioStreamWAV
		if aurora_audio.audio_player.bus != AuroraAudio.MUSIC_BUS:
			aurora_failures.append("Aurora ambience does not use the existing Music volume bus")
		if audio_stream == null or audio_stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			aurora_failures.append("Aurora ambience is not imported as a forward loop")
	director.set_physics_process(false)
	var original_size: Vector2i = root.size
	for width: int in [1152, 1440]:
		root.size = Vector2i(width, 648)
		for palette: BiomePalette in [BiomeDirector.PALETTE_TWILIGHT_BLUE, BiomeDirector.PALETTE_STARLIT_NIGHT]:
			backdrop.apply_palette(palette)
			if snow != null:
				snow.call("apply_palette", palette)
			director.push_blend(0.0)
			if aurora_audio != null and (aurora_audio.audio_player.playing \
					or aurora_audio.applied_linear_gain != 0.0):
				aurora_failures.append("Aurora ambience does not restore its zero state")
			if not is_zero_approx(terrain.aurora_ice_blend) \
					or (wash != null and (wash.get_node("Wash") as TextureRect).visible) \
					or (blade_glow != null and blade_glow.visible) \
					or (wisps != null and wisps.visible) \
					or (wings != null and wings.visible) \
					or (snow != null and not is_zero_approx(float(snow.get("aurora_density_blend")))):
				aurora_failures.append("Aurora world response does not restore its zero state")
			var snow_baseline_ratio: float = float(snow.call("get_target_amount_ratio")) if snow != null else 0.0
			var clean: Image = await capture_aurora_frame()
			# Visual envelope only; safe-entry lifecycle is exercised by aurora_calm_probe.
			director.phase = AuroraDirector.Phase.ACTIVE
			director.active_elapsed = 0.0
			director.is_preview = true
			for elapsed: float in [0.0, 4.0, 8.0, 30.0, 53.0, 57.0, 61.0]:
				director.active_elapsed = elapsed
				director.push_blend(director.get_aurora_blend())
				if elapsed == 30.0 and (terrain.aurora_ice_blend < 0.99 \
						or (wash != null and not (wash.get_node("Wash") as TextureRect).visible) \
						or (blade_glow != null and not blade_glow.visible)):
					aurora_failures.append("Aurora crest does not reach wash, ice, and grounded blade glow")
				if elapsed == 30.0 and snow != null:
					var snow_crest_ratio: float = float(snow.call("get_target_amount_ratio"))
					var density_gain: float = snow_crest_ratio / maxf(snow_baseline_ratio, 0.001)
					if density_gain < 1.3 or density_gain > 1.6 or snow_crest_ratio > 1.0:
						aurora_failures.append("Aurora snow crest is outside its bounded 1.3-1.6x target")
				var frame: Image = await capture_aurora_frame()
				var peak: int = measure_peak(clean, frame)
				if (elapsed == 0.0 or elapsed == 61.0) and peak != 0:
					aurora_failures.append("Aurora does not restore the baseline at t=%s, width=%d" % [elapsed, width])
				elif elapsed > 0.0 and elapsed < 61.0 and peak < MIN_PEAK_CONTRIBUTION:
					aurora_failures.append("Aurora ramp is not visible at t=%s, width=%d" % [elapsed, width])
			# Isolate the blade contribution from the much larger sky/wash/ice changes.
			director.active_elapsed = 30.0
			director.push_blend(1.0)
			if aurora_audio != null:
				if not aurora_audio.audio_player.playing \
						or absf(aurora_audio.applied_linear_gain - AuroraAudio.MAX_LINEAR_GAIN) > 0.001:
					aurora_failures.append("Aurora ambience does not play at its bounded crest gain")
				aurora_audio._on_game_state_changed(GameManager.State.PAUSED)
				if not aurora_audio.audio_player.stream_paused:
					aurora_failures.append("Aurora ambience does not pause with gameplay")
				aurora_audio._on_game_state_changed(GameManager.State.PLAYING)
				if aurora_audio.audio_player.stream_paused:
					aurora_failures.append("Aurora ambience does not resume with gameplay")
			var blade_on: Image = await capture_aurora_frame()
			if blade_glow != null:
				blade_glow.visible = false
			var blade_off: Image = await capture_aurora_frame()
			var blade_peak: int = measure_peak(blade_off, blade_on)
			print("AURORA_BLADE width=%d palette=%s peak=%d floor=%d" % [
				width, palette.resource_path.get_file(), blade_peak, MIN_PEAK_CONTRIBUTION])
			if blade_peak < MIN_PEAK_CONTRIBUTION:
				aurora_failures.append("Aurora blade glow is too faint at width=%d: %d < %d" % [
					width, blade_peak, MIN_PEAK_CONTRIBUTION])
			director.push_blend(0.0)
			# Same isolation for the sparse rear wisps. Held frames must be byte-identical:
			# their drift is a function of the director clock, not a private timer.
			director.active_elapsed = 30.0
			director.push_blend(1.0)
			var wisps_on: Image = await capture_aurora_frame()
			var wisps_held: Image = await capture_aurora_frame()
			if measure_peak(wisps_on, wisps_held) != 0:
				aurora_failures.append("Aurora wisps move while their clock is paused")
			if wisps != null:
				wisps.visible = false
			var wisps_off: Image = await capture_aurora_frame()
			var wisps_peak: int = measure_peak(wisps_off, wisps_on)
			print("AURORA_WISPS width=%d palette=%s peak=%d floor=%d" % [
				width, palette.resource_path.get_file(), wisps_peak, MIN_PEAK_CONTRIBUTION])
			if wisps_peak < MIN_PEAK_CONTRIBUTION:
				aurora_failures.append("Aurora wisps are too faint at width=%d: %d < %d" % [
					width, wisps_peak, MIN_PEAK_CONTRIBUTION])
			if wisps != null:
				wisps.call("apply_aurora", 1.0, 20.0)
				var wisps_motion_a: Image = await capture_aurora_frame()
				wisps.call("apply_aurora", 1.0, 21.0)
				var wisps_motion_b: Image = await capture_aurora_frame()
				if measure_peak(wisps_motion_a, wisps_motion_b) == 0:
					aurora_failures.append("Aurora wisp clock does not produce visible drift")
			director.push_blend(0.0)
			# The wing apparition is brief, ground-only, deterministic, and behind gameplay.
			director.active_elapsed = 30.0
			director.push_blend(1.0)
			var wings_on: Image = await capture_aurora_frame()
			var wings_held: Image = await capture_aurora_frame()
			if measure_peak(wings_on, wings_held) != 0:
				aurora_failures.append("Aurora wings move while their clock is paused")
			if wings != null:
				wings.visible = false
			var wings_off: Image = await capture_aurora_frame()
			var wings_peak: int = measure_peak(wings_off, wings_on)
			print("AURORA_WINGS width=%d palette=%s peak=%d floor=%d" % [
				width, palette.resource_path.get_file(), wings_peak, MIN_PEAK_CONTRIBUTION])
			if wings_peak < MIN_PEAK_CONTRIBUTION:
				aurora_failures.append("Aurora wings are too faint at width=%d: %d < %d" % [
					width, wings_peak, MIN_PEAK_CONTRIBUTION])
			if wings != null:
				wings.call("apply_aurora", 1.0, 10.0)
				if wings.visible:
					aurora_failures.append("Aurora wings appear before their brief crest window")
				wings.call("apply_aurora", 1.0, 55.0)
				if wings.visible:
					aurora_failures.append("Aurora wings remain after their brief crest window")
			director.push_blend(0.0)
			# Arrival must begin on the right, then reach the left. Whole-screen fading
			# (or a reveal tied to drifting texture UV) must not pass on brightness alone.
			backdrop.apply_aurora(1.0, 4.0)
			var arrival: Image = await capture_aurora_frame()
			var left: Rect2i = Rect2i(0, 0, clean.get_width() / 4, clean.get_height() / 5)
			var right: Rect2i = Rect2i(clean.get_width() * 3 / 4, 0, clean.get_width() / 4, clean.get_height() / 5)
			if measure_peak(clean.get_region(left), arrival.get_region(left)) != 0 \
					or measure_peak(clean.get_region(right), arrival.get_region(right)) < MIN_PEAK_CONTRIBUTION:
				aurora_failures.append("Aurora arrival is not confined to the right at width=%d" % width)
			backdrop.apply_aurora(1.0, 16.0)
			var unfolded: Image = await capture_aurora_frame()
			if measure_peak(clean.get_region(left), unfolded.get_region(left)) < MIN_PEAK_CONTRIBUTION:
				aurora_failures.append("Aurora reveal never reaches the left at width=%d" % width)
			# No shader TIME: repeated frames while paused must remain identical.
			var held: Image = await capture_aurora_frame()
			if measure_peak(unfolded, held) != 0:
				aurora_failures.append("Aurora shader moves while its clock is paused")
			# Isolate internal deformation from the existing rect drift/bob and breath.
			for band: TextureRect in backdrop.aurora_bands:
				(band.material as ShaderMaterial).set_shader_parameter("event_elapsed", 25.0)
			var folded: Image = await capture_aurora_frame()
			if measure_peak(unfolded, folded) < 8:
				aurora_failures.append("Aurora internal folds do not visibly move")
			for argument: String in OS.get_cmdline_user_args():
				if argument.begins_with("--capture-dir="):
					var directory: String = argument.trim_prefix("--capture-dir=")
					DirAccess.make_dir_recursive_absolute(directory)
					var prefix: String = "%s/%s-%d" % [directory, palette.resource_path.get_file().get_basename(), width]
					clean.save_png(prefix + "-baseline.png")
					arrival.save_png(prefix + "-arrival.png")
					unfolded.save_png(prefix + "-unfolded.png")
					wisps_on.save_png(prefix + "-wisps.png")
					wings_on.save_png(prefix + "-wings.png")
			# Measure each band separately at full strength; the green carries the event.
			for selected: int in range(3):
				backdrop.apply_aurora(1.0, 8.0)
				for index: int in range(3):
					backdrop.aurora_bands[index].visible = index == selected
				var frame: Image = await capture_aurora_frame()
				var peak: int = measure_peak(clean, frame)
				var required: int = 64 if selected == 0 else MIN_PEAK_CONTRIBUTION
				print("AURORA_LAYER width=%d palette=%s band=%d peak=%d floor=%d" % [width, palette.resource_path.get_file(), selected, peak, required])
				if peak < required:
					aurora_failures.append("Aurora band %d is obscured/too faint at width=%d: %d < %d" % [selected, width, peak, required])
			director._on_player_died()
			if aurora_audio != null and aurora_audio.audio_player.playing:
				aurora_failures.append("Aurora death cleanup left ambience playing")
			var cleared: Image = await capture_aurora_frame()
			if measure_peak(clean, cleared) != 0:
				aurora_failures.append("Aurora death cleanup changed the baseline")
	root.size = original_size
	# The audited late-night start must be rejected with shipping timing. Restore all
	# session state afterwards; this query never applies a palette or changes the world.
	var old_rotation: int = BiomeDirector.session_cycle_rotation
	var old_offset: float = biome.biome_phase_offset
	var old_debug: float = biome.debug_biome_seconds
	BiomeDirector.session_cycle_rotation = 0
	biome.debug_biome_seconds = 0.0
	biome.biome_phase_offset = 582000.0 - biome.player.global_position.x
	if biome.get_minimum_night_ahead(61.0, 1000.0) >= AuroraDirector.NIGHT_THRESHOLD:
		aurora_failures.append("Late-night boundary incorrectly admits a full aurora")
	biome.biome_phase_offset = 450000.0 - biome.player.global_position.x
	if biome.get_minimum_night_ahead(61.0, 1000.0) < AuroraDirector.NIGHT_THRESHOLD:
		aurora_failures.append("Full night window incorrectly rejects an aurora")
	BiomeDirector.session_cycle_rotation = old_rotation
	biome.biome_phase_offset = old_offset
	biome.debug_biome_seconds = old_debug
	print("AURORA_CHECK ", "PASS" if aurora_failures.is_empty() else "FAIL")
	report()


func capture_aurora_frame() -> Image:
	for frame: int in range(SETTLE_FRAMES):
		await process_frame
	return capture_rendered_frame()


func capture_rendered_frame() -> Image:
	# An occluded desktop window may stop presenting even while process_frame
	# continues. Force a render so captures cannot repeatedly read a stale image.
	RenderingServer.force_draw()
	return root.get_texture().get_image()
