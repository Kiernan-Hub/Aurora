extends SceneTree

# Live A/B toggle for the edge-aliasing ("shimmer/crawl") hypothesis.
#
# WHY THIS EXISTS. Three rounds of position-level investigation (contact-point
# anomaly, floor-snap, frame-timing, segment-entry, camera jerk) all failed to
# move the perceived mega_drop shake, and render_pacing_probe.gd then showed
# frame pacing is flawless (100% of rendered frames = exactly 1 physics step,
# 16.667ms, zero dropped/doubled). So what moves on screen is NOT a position
# error and NOT a pacing error.
#
# Remaining candidate: the terrain is an un-antialiased Polygon2D and
# `rendering/anti_aliasing/quality/msaa_2d` is unset (= disabled). A hard-edged
# polygon with a 40.5-degree boundary has a stair-step aliasing pattern along
# that edge; scrolling it by sub-pixel amounts each frame makes those steps
# CRAWL. That is a rasterization artifact, immune to every position fix tried,
# and it scales with edge angle -- horizontal edges (flat) cannot crawl at all,
# shallow diagonals barely do, and the steepest slope in the game crawls worst.
# That is exactly the reported severity ranking.
#
# HOW TO USE. Play normally and wait for (or speed into) a mega_drop, then tap
# the toggle key repeatedly while watching the terrain edge. If the shimmer
# visibly stops and starts with the setting, the hypothesis is confirmed and
# the fix is the project setting, not any further physics work.
#
#   SPACE / up / down : normal play controls (jump, speed up/down)
#   M : cycle MSAA 2D   disabled -> 2x -> 4x -> 8x -> disabled
#   N : toggle Polygon2D.antialiased on every terrain chunk (independent of
#       MSAA; covers the case where MSAA alone is not enough)
#
# Current mode is drawn on screen and printed to the console on every change.
#
# Usage (must be windowed -- do NOT pass --headless):
#   Godot --path . --script res://scripts/debug/archive/aa_toggle_probe.gd -- [--seed=941462462]
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

const MSAA_MODE_NAMES: Array[String] = ["disabled", "2x", "4x", "8x"]


class InputRelay extends Node:
	var on_cycle_msaa: Callable
	var on_toggle_polygon_aa: Callable
	var on_toggle_max_speed: Callable

	func _unhandled_key_input(event: InputEvent) -> void:
		var key_event: InputEventKey = event as InputEventKey
		if key_event == null or not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_M:
			on_cycle_msaa.call()
		elif key_event.keycode == KEY_N:
			on_toggle_polygon_aa.call()
		elif key_event.keycode == KEY_S:
			on_toggle_max_speed.call()


var main: Node
var player: Player
var terrain_generator: TerrainGenerator
var status_label: Label
var msaa_mode: int = 0
var polygon_antialiased: bool = false
var force_max_speed: bool = true

# mega_drop peaks at 40.5 degrees. The measured quantisation only shows on the
# steep face, so the readout calls that out explicitly -- an earlier by-eye A/B
# of this same toggle was inconclusive because it was almost certainly done on
# flat ground or the mega_drop crest, where there is nothing to see.
const STEEP_SLOPE_RADIANS: float = 0.5
const SPEED_CAP: float = 500.0


func _init() -> void:
	var seed_text: String = get_string_argument("--seed", "941462462")

	main = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = seed_text.to_int()
	root.add_child(main)
	await physics_frame

	var relay: InputRelay = InputRelay.new()
	relay.on_cycle_msaa = _cycle_msaa
	relay.on_toggle_polygon_aa = _toggle_polygon_antialiased
	relay.on_toggle_max_speed = _toggle_max_speed
	root.add_child(relay)

	build_status_label()
	msaa_mode = root.msaa_2d
	refresh_status()

	print("AA_TOGGLE_PROBE ready - M cycles MSAA 2D, N toggles Polygon2D.antialiased")
	# Terrain chunks are spawned and freed continuously, so a chunk created
	# after N was pressed would come back un-antialiased. Re-apply every physics
	# frame so the setting actually holds across the whole run.
	while true:
		await physics_frame
		if force_max_speed:
			player.speed_manager.current_speed = SPEED_CAP
		if polygon_antialiased:
			apply_polygon_antialiasing(true)
		refresh_status()


func build_status_label() -> void:
	var canvas_layer: CanvasLayer = CanvasLayer.new()
	canvas_layer.layer = 120
	root.add_child(canvas_layer)
	status_label = Label.new()
	status_label.position = Vector2(8, 320)
	status_label.add_theme_font_size_override("font_size", 18)
	canvas_layer.add_child(status_label)


func _cycle_msaa() -> void:
	msaa_mode = (msaa_mode + 1) % MSAA_MODE_NAMES.size()
	root.msaa_2d = msaa_mode as Viewport.MSAA
	refresh_status()
	print("MSAA 2D -> ", MSAA_MODE_NAMES[msaa_mode])


func _toggle_polygon_antialiased() -> void:
	polygon_antialiased = not polygon_antialiased
	apply_polygon_antialiasing(polygon_antialiased)
	refresh_status()
	print("Polygon2D.antialiased -> ", polygon_antialiased)


func _toggle_max_speed() -> void:
	force_max_speed = not force_max_speed
	refresh_status()
	print("force max speed -> ", force_max_speed)


func apply_polygon_antialiasing(enabled: bool) -> void:
	for chunk: Node in terrain_generator.get_children():
		var terrain_fill: Polygon2D = chunk.get_node_or_null("TerrainFill") as Polygon2D
		if terrain_fill != null:
			terrain_fill.antialiased = enabled


func refresh_status() -> void:
	var world_x: float = player.global_position.x
	var slope: float = terrain_generator.get_slope_angle_at_x(world_x)
	var segment: String = String(terrain_generator.get_segment_spec(
		terrain_generator.find_segment_index_at_x(world_x))["label"])
	var is_steep: bool = absf(slope) >= STEEP_SLOPE_RADIANS and segment == "mega_drop"
	var marker: String = ">>> STEEP FACE - COMPARE HERE <<<" if is_steep else "(not steep - keep going)"
	status_label.text = "[M] MSAA 2D: %s    [N] Polygon2D.antialiased: %s    [S] force max speed: %s\nsegment: %s   slope: %.1f deg\n%s" % [
		MSAA_MODE_NAMES[msaa_mode], str(polygon_antialiased), str(force_max_speed),
		segment, rad_to_deg(slope), marker,
	]


func get_string_argument(argument_name: String, default_value: String) -> String:
	var prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return default_value
