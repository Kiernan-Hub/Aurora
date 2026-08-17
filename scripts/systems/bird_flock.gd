extends Node2D

class_name BirdFlock

# Lives as a Node2D child of a CanvasLayer (BirdFlock/Flock in main.tscn), not attached to
# the CanvasLayer directly: CanvasLayer extends Node, not CanvasItem, so it has neither
# `modulate` nor `get_viewport_rect()` -- the same reason snow_drift.gd's script sits on
# the GPUParticles2D child rather than on the SnowDrift CanvasLayer itself.

# A handful of drifting bird silhouettes, screen-space like snow_drift.gd and for the same
# reason: world rebasing (main.gd, ~every 26s) cannot move a CanvasLayer.
#
# WHY THIS EXISTS: a high glide (main.gd's is_glide_vertical_follow_active) can put most of
# the screen over TerrainGenerator's fill polygon with the actual bumpy surface scrolled
# far below frame. terrain_generator.gd's FILL_GRADIENT_DEPTH shades the first ~560px of
# that fill so it doesn't read as one flat colour -- but the whole visible slice can be
# BEYOND that depth once the glide gets high enough, at which point it's back to a flat
# (if darker) colour with nothing left to tune: no fill-depth constant can promise coverage
# against an excursion that keeps growing. Birds are the fix for that ceiling case: they
# read as something happening on screen regardless of how far below the surface actually
# is, because they aren't tied to terrain depth at all.
#
# Only visible while gliding (see fade below) -- during ordinary low-altitude play they
# would just be clutter over the obstacles/coins the player is reading.

const BIRD_COUNT: int = 4
# Mid-dark, same family as ShardLine/MidRidge (docs/development/visuals.md palette) so a
# bird reads as part of the distant scenery rather than a foreground gameplay object.
const BIRD_COLOR: Color = Color(0.4, 0.49, 0.6, 0.88)
const WING_LENGTH_MIN: float = 12.0
const WING_LENGTH_MAX: float = 20.0
const WING_THICKNESS: float = 3.0
# Resting angle of each wing off the horizontal, degrees; flap swings between this and a
# higher raised angle.
const WING_REST_ANGLE_DEGREES: float = 18.0
const WING_FLAP_AMPLITUDE_DEGREES: float = 30.0
const FLAP_SPEED_MIN: float = 2.6
const FLAP_SPEED_MAX: float = 4.2
const DRIFT_SPEED_MIN: float = 16.0
const DRIFT_SPEED_MAX: float = 30.0
# Kept high on screen and above SnowDrift's fall band -- birds belong with the distant
# mountains, not mixed into the near snowfall.
const Y_FRACTION_MIN: float = 0.1
const Y_FRACTION_MAX: float = 0.38
const SPAWN_MARGIN: float = 40.0
const FADE_SMOOTHNESS: float = 2.5

@export var player_path: NodePath

var is_headless: bool = false
var player: CharacterBody2D
var birds: Array[Node2D] = []
var bird_states: Array[Dictionary] = []
var flock_alpha: float = 0.0
var time_elapsed: float = 0.0


func _ready() -> void:
	# Same reasoning and same one-line check as snow_drift.gd / sfx_player.gd: at least one
	# harness adds Main before the autoload's deferred _ready() has flushed, so this must be
	# computed locally rather than read from Services.is_headless.
	is_headless = DisplayServer.get_name() == "headless"
	if is_headless:
		set_process(false)
		return

	player = resolve_player()
	if player == null:
		set_process(false)
		return

	apply_viewport_size()
	get_viewport().size_changed.connect(apply_viewport_size)
	spawn_birds()
	set_process(true)


func resolve_player() -> CharacterBody2D:
	var resolved_player: CharacterBody2D = null
	if player_path != NodePath():
		resolved_player = get_node_or_null(player_path) as CharacterBody2D
	if resolved_player == null:
		resolved_player = get_node_or_null("/root/Main/Player") as CharacterBody2D
	return resolved_player


var viewport_width: float = 0.0
var viewport_height: float = 0.0


func apply_viewport_size() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	viewport_width = viewport_size.x
	viewport_height = viewport_size.y


func spawn_birds() -> void:
	for bird_index: int in range(BIRD_COUNT):
		var bird: Node2D = build_bird()
		add_child(bird)
		birds.append(bird)
		bird_states.append({
			"y_fraction": lerpf(Y_FRACTION_MIN, Y_FRACTION_MAX, float(bird_index) / maxf(float(BIRD_COUNT - 1), 1.0)),
			"speed": randf_range(DRIFT_SPEED_MIN, DRIFT_SPEED_MAX),
			"flap_speed": randf_range(FLAP_SPEED_MIN, FLAP_SPEED_MAX),
			"flap_phase": randf_range(0.0, TAU),
			"x": randf_range(0.0, 1.0),
		})
	modulate.a = 0.0


func build_bird() -> Node2D:
	var bird: Node2D = Node2D.new()
	var wing_length: float = randf_range(WING_LENGTH_MIN, WING_LENGTH_MAX)

	var left_wing: Polygon2D = build_wing_polygon(wing_length)
	left_wing.name = "LeftWing"
	left_wing.color = BIRD_COLOR
	bird.add_child(left_wing)

	var right_wing: Polygon2D = build_wing_polygon(wing_length)
	right_wing.name = "RightWing"
	right_wing.color = BIRD_COLOR
	right_wing.scale.x = -1.0
	bird.add_child(right_wing)

	return bird


# A thin quad running from the body outward, rotated by _process() to flap. Built pointing
# straight out along +x at rest; the caller mirrors and rotates it into a wing shape.
func build_wing_polygon(wing_length: float) -> Polygon2D:
	var wing: Polygon2D = Polygon2D.new()
	wing.polygon = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(wing_length, -WING_THICKNESS * 0.5),
		Vector2(wing_length, WING_THICKNESS * 0.5),
	])
	return wing


func _process(delta: float) -> void:
	time_elapsed += delta

	var target_alpha: float = 1.0 if player.is_glide_active else 0.0
	var interpolation_weight: float = 1.0 - exp(-FADE_SMOOTHNESS * delta)
	flock_alpha = lerpf(flock_alpha, target_alpha, interpolation_weight)
	modulate.a = flock_alpha

	# No motion cost while faded out -- skip the per-bird update rather than animate an
	# invisible flock every frame of ordinary (non-glide) play.
	if flock_alpha < 0.01:
		return

	for bird_index: int in range(birds.size()):
		var bird: Node2D = birds[bird_index]
		var state: Dictionary = bird_states[bird_index]

		var span_width: float = viewport_width + (SPAWN_MARGIN * 2.0)
		state["x"] = fmod(state["x"] + ((state["speed"] * delta) / maxf(span_width, 1.0)), 1.0)
		bird_states[bird_index] = state

		bird.position = Vector2(
			(state["x"] * span_width) - SPAWN_MARGIN,
			viewport_height * state["y_fraction"],
		)

		var flap: float = sin((time_elapsed * state["flap_speed"]) + state["flap_phase"])
		var wing_angle: float = deg_to_rad(WING_REST_ANGLE_DEGREES + (flap * WING_FLAP_AMPLITUDE_DEGREES))
		(bird.get_node("LeftWing") as Polygon2D).rotation = -wing_angle
		(bird.get_node("RightWing") as Polygon2D).rotation = wing_angle
