extends Node2D

class_name ThinIce

# THIN ICE: a stretch of ground that cracks under a player who stays on it too long at a time.
# Each landing gets a fresh GRACE_SECONDS, so it is crossed by skipping like a stone -- land,
# tap, land, tap -- and the jump buffer makes the rhythm forgiving. A short patch is one jump.
#
# A SPAN CHECK, NOT AN Area2D. It adds no floor, no wall and no velocity: every physics frame it
# asks one question of the player and calls absorb_hit() past the grace, exactly the path an
# obstacle hit takes. So the player physics, and the freeze/wall-wedge history with it, never
# sees it. Nothing opens in the terrain; the crack is only drawn.
#
# Ordering: a child of ObstacleSpawner under TerrainGenerator, which comes after Player in the
# tree, so this reads the frame's post-move is_on_floor() -- the same end-of-frame grounded state
# terrain_invariant_check's fairness model counts.

# How long the player may stay grounded on the patch at a time. Tuned by feel on the phone.
# The epsilon keeps 12 frames legal despite float accumulation, which is what the fairness
# model assumes (13 frames crack).
const GRACE_SECONDS: float = 0.2
const GRACE_EPSILON: float = 0.0001
# The overlay sits JUST ABOVE the surface line: terrain chunks are added to TerrainGenerator
# after the spawners, so they draw over anything at or below the line, and there is no z_index.
const OVERLAY_LIFT: float = 4.0
const OVERLAY_WIDTH: float = 6.0
const OVERLAY_SAMPLE_STEP: float = 16.0
# A patch that has cracked (through a shield) stays visible, faded, so the player sees why the
# shield is gone.
const CRACKED_ALPHA: float = 0.3

var player: Player
var start_x: float = 0.0
var end_x: float = 0.0
var grounded_time: float = 0.0
var is_armed: bool = true
var overlay: Line2D


# Called by ObstacleSpawner before add_child(). The node sits on the surface at start_x; the
# overlay follows the surface to end_x, sampled through the same pure height field chunks use.
func setup(new_player: Player, terrain: TerrainGenerator, new_start_x: float, new_end_x: float, color: Color) -> void:
	player = new_player
	start_x = new_start_x
	end_x = new_end_x
	position = Vector2(start_x, terrain.ground_y + terrain.get_terrain_height(start_x))
	overlay = Line2D.new()
	overlay.name = "Overlay"
	overlay.width = OVERLAY_WIDTH
	overlay.default_color = color
	var sample_x: float = start_x
	while true:
		var surface_y: float = terrain.ground_y + terrain.get_terrain_height(sample_x)
		overlay.add_point(Vector2(sample_x - start_x, surface_y - position.y - OVERLAY_LIFT))
		if sample_x >= end_x:
			break
		sample_x = minf(sample_x + OVERLAY_SAMPLE_STEP, end_x)
	add_child(overlay)


func set_visual_color(color: Color) -> void:
	if overlay != null:
		overlay.default_color = color


# World-space extent, for AuroraDirector, which otherwise finds bodies by collision shape.
func get_world_rect() -> Rect2:
	return Rect2(global_position.x, global_position.y - OVERLAY_LIFT, end_x - start_x, OVERLAY_LIFT)


func _physics_process(delta: float) -> void:
	if not is_armed or player == null:
		return
	# A boosting player skims over for free: jump input is suppressed for the whole boost, and
	# it matches "a boost breaks through".
	var player_x: float = player.global_position.x
	if player_x < start_x or player_x >= end_x or not player.is_on_floor() \
			or player.is_boosting or player.is_dead:
		grounded_time = 0.0
		return
	grounded_time += delta
	if grounded_time > GRACE_SECONDS + GRACE_EPSILON:
		# Disarmed either way: a shield that absorbed the crack must not be asked again on the
		# very next frame, which it would be while the player is still standing here.
		is_armed = false
		overlay.modulate.a = CRACKED_ALPHA
		player.absorb_hit()
