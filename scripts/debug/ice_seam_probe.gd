extends SceneTree

# Diagnostic for the reported "hard vertical seam / colour banding" in the ice. NOT a gate --
# it prints measurements, it does not pass or fail.
#
#   godot --path . --script res://scripts/debug/ice_seam_probe.gd -- --out=/tmp/seam --old=/tmp/old
#
# MUST NOT run with --headless: BiomeDirector returns early there, so ice_hue_variance stays
# 0, the drift never runs, and the thing under investigation cannot appear.
#
# WHY IT A/Bs INSIDE ONE FROZEN FRAME, AND WHY THAT IS NOT OPTIONAL.
# The terrain seed is per-session and the player is moving, so two RUNS of this script see
# different terrain from a different camera x -- measured drift of ~25 world px in the camera
# by the first capture. Comparing a number from run A against run B is therefore comparing two
# different landscapes, and it produced a confidently wrong "the fix worked" once already.
# So: settle, PAUSE THE TREE, capture, swap the tile textures in place, capture again, restore.
# Both frames then share one camera, one terrain and one palette, and the only difference is
# the bytes in the texture.
#
# --old=DIR points at a directory of previous-version tiles with the SAME BASENAMES as the ones
# in assets/textures/terrain. Omit it to just capture and report without an A/B.
#
# SceneTree.paused, never Engine.time_scale = 0 -- the latter zeroes the physics delta, trips
# the stall watchdog and fires a world rebase, leaving the world off screen (debugging.md,
# "Measurement traps").
# Rendering still runs while paused, which is what makes the swap visible.
#
# APPLY, WAIT, *THEN* CAPTURE: root.get_texture() returns the frame already rendered.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const WARMUP_FRAMES: int = 40
const SETTLE_FRAMES: int = 8
# One frame would do for the texture swap -- no easing is involved, unlike a palette change --
# but two costs nothing and removes the question.
const SWAP_FRAMES: int = 2
# How many scrolled captures to take per biome, and how many unfrozen frames between them.
# DRIFT_CAPTURES and DRIFT_FRAMES together span enough camera travel to be unambiguous.
const DRIFT_CAPTURES: int = 3
const DRIFT_FRAMES: int = 3

enum Stage { APPLY, CAPTURE_CURRENT, CAPTURE_OLD, DRIFT }

var main: Node2D
var director: BiomeDirector
var terrain: TerrainGenerator
var output_prefix: String = "/tmp/seam"
var old_tile_dir: String = ""
var frame_index: int = 0
var probe_index: int = 0
var settle_countdown: int = 0
var stage: Stage = Stage.APPLY
var frozen: bool = false
var swapped_bands: Array[Polygon2D] = []
var swapped_textures: Array[Texture2D] = []
var drift_index: int = 0


func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_prefix = argument.trim_prefix("--out=")
		elif argument.begins_with("--old="):
			old_tile_dir = argument.trim_prefix("--old=")
	main = MAIN_SCENE.instantiate() as Node2D
	(main.get_node("GameManager") as GameManager).require_start_screen = false
	root.add_child(main)
	paused = false


func _process(_delta: float) -> bool:
	frame_index += 1
	# Only while the world is meant to be running. Once frozen, re-asserting PLAYING and
	# unpausing every frame would defeat the freeze the whole comparison rests on.
	if not frozen:
		var game_manager: GameManager = main.get_node("GameManager") as GameManager
		if game_manager.state != GameManager.State.PLAYING:
			game_manager.set_state(GameManager.State.PLAYING)
		paused = false
	(main.get_node("CanvasLayer") as CanvasLayer).visible = false

	if frame_index < WARMUP_FRAMES:
		return false

	if director == null:
		director = main.get_node("BiomeDirector") as BiomeDirector
		director.set_process(false)
		terrain = main.get_node("TerrainGenerator") as TerrainGenerator
		hide_everything_but_terrain()

	if settle_countdown > 0:
		settle_countdown -= 1
		return false

	match stage:
		Stage.APPLY:
			if probe_index >= BiomeDirector.BIOME_CYCLE.size():
				quit(0)
				return true
			# Centre of the biome's span: a settled palette, never part-way through a
			# crossfade. Settled is also the only honest place to A/B the BASE tile -- mid
			# transition the shader is mixing in an overlay this swap does not touch.
			director.apply_palette_for_world_x((float(probe_index) + 0.5) * BiomeDirector.BIOME_DISTANCE)
			settle_countdown = SETTLE_FRAMES
			stage = Stage.CAPTURE_CURRENT
		Stage.CAPTURE_CURRENT:
			frozen = true
			paused = true
			report(label_for(probe_index))
			capture(label_for(probe_index) + "_current")
			if old_tile_dir.is_empty():
				finish_probe()
			else:
				swap_in_old_tiles()
				settle_countdown = SWAP_FRAMES
				stage = Stage.CAPTURE_OLD
		Stage.CAPTURE_OLD:
			capture(label_for(probe_index) + "_old")
			restore_tiles()
			drift_index = 0
			frozen = false
			paused = false
			settle_countdown = DRIFT_FRAMES
			stage = Stage.DRIFT
		Stage.DRIFT:
			# Unfrozen for a couple of frames so the world scrolls a little, then frozen and
			# captured again. Comparing this against the previous capture answers the one
			# question that splits the whole search in half: a feature of the ICE translates
			# with the camera, a feature of the RENDERING stays put on screen. Nothing else
			# here can tell those apart, and every detector so far has been able to find
			# either without knowing which it had.
			frozen = true
			paused = true
			capture("%s_drift%d" % [label_for(probe_index), drift_index])
			print("    drift%d camera_x=%.2f" % [drift_index, (main.get_node("Camera2D") as Camera2D).global_position.x])
			drift_index += 1
			if drift_index >= DRIFT_CAPTURES:
				finish_probe()
			else:
				frozen = false
				paused = false
				settle_countdown = DRIFT_FRAMES
	return false


# Leaves ONLY the terrain (and the sky behind it) on screen.
#
# NOT cosmetic. Every automated pass over these captures that did not do this found a tree
# trunk, a coin or the player instead of a seam -- three times, each time as a confident
# number: a 28/255 "step" that was a trunk crossing the sample row, and a 7.4/255 "line at
# 9.9x median" that was the same trunk's edge. A vertical sprite boundary is exactly the
# signal a vertical-seam detector is built to find, so the only reliable fix is to take the
# sprites out of the frame rather than to filter them out afterwards.
#
# The spawners are Node2D and the trees/coins are their children, so hiding the parent is
# enough. Nothing is restored: this script renders frames and exits.
func hide_everything_but_terrain() -> void:
	for path: String in [
		"Player", "SnowDrift", "BirdFlock",
		"TerrainGenerator/GroundTreeSpawner", "TerrainGenerator/CoinSpawner",
		"TerrainGenerator/PowerupSpawner", "TerrainGenerator/GlideCoinSpawner",
		"TerrainGenerator/ObstacleSpawner",
	]:
		var node: CanvasItem = main.get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = false


# Named, not just numbered: the arc is rotated by a random amount each session
# (BiomeDirector.session_cycle_rotation), so "settled_3" alone no longer identifies a tile.
func label_for(index: int) -> String:
	var palette: BiomePalette = director.get_cycle_palette(index)
	return "settled_%d_%s" % [index, palette.resource_path.get_file().get_basename()]


func finish_probe() -> void:
	drift_index = 0
	frozen = false
	paused = false
	probe_index += 1
	stage = Stage.APPLY


func capture(label: String) -> void:
	root.get_texture().get_image().save_png("%s_%s.png" % [output_prefix, label])


func live_bands() -> Array[Polygon2D]:
	var bands: Array[Polygon2D] = []
	for chunk: Node2D in terrain.active_chunks.values():
		for child: Node in chunk.get_children():
			var band: Polygon2D = child as Polygon2D
			if band != null and band.name.begins_with("IceBand"):
				bands.append(band)
	return bands


# Replaces each band's tile with the same-named file from --old=, remembering what was there.
# Same OUTPUT_SIZE by contract (biome_schedule_check's EXPECTED_ICE_TILE_SIZE), so Polygon2D
# normalises the existing UVs identically and the geometry cannot shift under the swap.
func swap_in_old_tiles() -> void:
	swapped_bands.clear()
	swapped_textures.clear()
	var cache: Dictionary = {}
	for band: Polygon2D in live_bands():
		var file_name: String = band.texture.resource_path.get_file()
		if not cache.has(file_name):
			var image: Image = Image.new()
			if image.load("%s/%s" % [old_tile_dir, file_name]) != OK:
				push_error("could not load old tile %s/%s" % [old_tile_dir, file_name])
				return
			cache[file_name] = ImageTexture.create_from_image(image)
		swapped_bands.append(band)
		swapped_textures.append(band.texture)
		band.texture = cache[file_name]


func restore_tiles() -> void:
	for index: int in range(swapped_bands.size()):
		swapped_bands[index].texture = swapped_textures[index]
	swapped_bands.clear()
	swapped_textures.clear()


func collect_surface_samples() -> Array:
	var samples: Array = []
	var horizontal_scale: float = terrain.ice_band_texture.get_size().x / TerrainGenerator.ICE_TILE_WORLD_WIDTH
	for band: Polygon2D in live_bands():
		var row_size: int = band.vertex_colors.size() / 2
		for vertex_index: int in range(row_size):
			samples.append([band.uv[vertex_index].x / horizontal_scale, band.vertex_colors[vertex_index]])
	samples.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return samples


func channel_delta_255(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0


func report(label: String) -> void:
	var samples: Array = collect_surface_samples()
	var shared_worst: float = 0.0
	var step_worst: float = 0.0
	var shared_count: int = 0
	for i: int in range(samples.size() - 1):
		var delta: float = channel_delta_255(samples[i][1], samples[i + 1][1])
		if float(samples[i + 1][0]) - float(samples[i][0]) < 0.5:
			shared_count += 1
			shared_worst = maxf(shared_worst, delta)
		else:
			step_worst = maxf(step_worst, delta)

	var camera: Camera2D = main.get_node("Camera2D") as Camera2D
	print("%s  weight=%.3f variance=%.3f surface=%s base=%s" % [
		label, terrain.ice_overlay_weight, terrain.ice_hue_variance,
		terrain.ice_surface_tint, terrain.ice_band_texture.resource_path.get_file()])
	print("    boundaries=%d worst_shared=%.2f/255 worst_neighbour_step=%.2f/255 | camera_x=%.2f view=%s" % [
		shared_count, shared_worst, step_worst, camera.global_position.x,
		Vector2(root.get_texture().get_size())])
