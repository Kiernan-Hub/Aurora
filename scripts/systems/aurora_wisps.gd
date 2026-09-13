extends Node2D

class_name AuroraWisps

# Ribbons of light drifting past the skater, structurally behind Player, TerrainGenerator and
# every gameplay object.
#
# THEY USED TO BE THREE STILL ARCS AND THEY READ AS DRAWN LINES. Owner review, 2026-09-11:
# "the wisps look like plain lines, no life/movement to them". They were three fixed arcs at
# alpha 0.17/0.13/0.10 whose points were built once and only ever translated -- so each one was
# a rigid shape sliding sideways, which is exactly what a drawn line does and nothing that
# light does.
#
# WHAT CHANGED, AND THE ONE INVARIANT THAT DID NOT. The local point array is now rewritten each
# frame from a travelling wave, so a ribbon undulates along its own length instead of holding a
# fixed curve. That is cheap -- WISP_COUNT x POINT_COUNT is 78 points -- and it does NOT
# reintroduce the hazard the old comment was guarding: every point is in LOCAL space and is
# recomputed from scratch each frame, so nothing here stores a world coordinate and there is
# still no trail history to repair during a world rebase. The node is re-anchored to the
# current player/surface each frame exactly as before.
#
# OFF PENDING A REWORK. Owner review 2026-09-13: "those wisps r terrible". They are, and the
# problem is not the parameters -- it is the concept. Detached ribbons hanging at mid-screen
# read as squiggles drawn over the scene, because they belong to nothing: they do not touch the
# ice, they do not descend from the curtains, and they do not occlude or get occluded by
# anything. Six of them undulating made that worse, not better, by drawing the eye to it.
#
# Left disabled rather than deleted because a reference image is coming and the likely rework
# is to turn these into VERTICAL SHAFTS descending from the curtains to the ice -- which would
# reuse this node's whole structure (immutable Line2D geometry, the travel/edge-fade cycle, the
# additive material, the rebase-safe local points) and would also answer the owner's separate
# request for "beams of light streaking". Flip this to true to see the old behaviour.
const WISPS_ENABLED: bool = false
const WISP_COUNT: int = 6
const POINT_COUNT: int = 13
const TRAVEL_SPAN: float = 900.0
const TRAVEL_SPEED: float = 34.0
const LENGTHS: Array[float] = [230.0, 186.0, 142.0, 268.0, 160.0, 120.0]
const HEIGHTS: Array[float] = [-78.0, -124.0, -46.0, -168.0, -210.0, -96.0]
const ARCS: Array[float] = [26.0, 18.0, 13.0, 30.0, 21.0, 15.0]
const WIDTHS: Array[float] = [5.5, 4.2, 3.2, 6.0, 4.6, 3.4]
# Roughly 2.5x the old values. The old set was authored when the wisps were the only thing
# happening below the sky; they now compete with a lit ice sheet and were invisible against it.
const STRENGTHS: Array[float] = [0.42, 0.34, 0.26, 0.46, 0.30, 0.22]
const COLORS: Array[Color] = [
	Color(0.25, 1.0, 0.70),
	Color(0.28, 0.90, 1.0),
	Color(0.72, 0.45, 1.0),
	Color(0.40, 1.0, 0.62),
	Color(0.55, 0.80, 1.0),
	Color(0.90, 0.60, 1.0),
]
const PHASE_OFFSETS: Array[float] = [0.08, 0.46, 0.76, 0.27, 0.61, 0.91]

# The travelling wave that gives a ribbon its life. Frequency is in full cycles along the
# ribbon's own length, so it is independent of how long that ribbon is; amplitude is a fraction
# of the ribbon's arc height, so a big ribbon waves proportionally rather than every ribbon
# waving by the same pixel count.
const WAVE_CYCLES: float = 1.6
const WAVE_SPEED: float = 1.1
const WAVE_AMPLITUDE: float = 0.85
# A second, slower wave at an incommensurate rate. One sine alone reads as a mechanical wobble;
# two that never line up read as drift.
const WAVE2_CYCLES: float = 0.7
const WAVE2_SPEED: float = 0.61
const WAVE2_AMPLITUDE: float = 0.55
# Each ribbon also breathes in brightness, so they do not all sit at one constant alpha.
const PULSE_SPEED: float = 0.73
const PULSE_DEPTH: float = 0.30

@export var player_path: NodePath = NodePath("../Player")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")

var player: Player
var terrain_generator: TerrainGenerator
var wisps: Array[Line2D] = []
var disabled: bool = false


func _ready() -> void:
	visible = false
	if not WISPS_ENABLED or DisplayServer.get_name() == "headless":
		disabled = true
		return

	player = get_node_or_null(player_path) as Player
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	if player == null or terrain_generator == null:
		disabled = true
		push_warning("AuroraWisps disabled: missing player or terrain.")
		return

	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for index: int in range(WISP_COUNT):
		var wisp: Line2D = Line2D.new()
		wisp.name = "Wisp%d" % index
		wisp.width = WIDTHS[index]
		wisp.gradient = build_taper_gradient(COLORS[index])
		wisp.points = build_wisp_points(LENGTHS[index], ARCS[index], PHASE_OFFSETS[index], 0.0)
		wisp.joint_mode = Line2D.LINE_JOINT_ROUND
		wisp.begin_cap_mode = Line2D.LINE_CAP_ROUND
		wisp.end_cap_mode = Line2D.LINE_CAP_ROUND
		wisp.antialiased = true
		wisp.material = additive
		wisps.append(wisp)
		add_child(wisp)


func apply_aurora(blend: float, elapsed: float) -> void:
	if disabled:
		return
	var event_strength: float = clampf(blend, 0.0, 1.0)
	if event_strength <= 0.0:
		visible = false
		return

	global_position = Vector2(
		player.global_position.x,
		terrain_generator.get_surface_world_y(player.global_position.x),
	)
	for index: int in range(wisps.size()):
		var cycle: float = fposmod(
			elapsed * TRAVEL_SPEED / TRAVEL_SPAN + PHASE_OFFSETS[index], 1.0)
		var centre_x: float = lerpf(-TRAVEL_SPAN * 0.55, TRAVEL_SPAN * 0.45, cycle)
		wisps[index].position = Vector2(centre_x, HEIGHTS[index])
		# The shape itself moves now, not just the node. See the header on why rewriting these
		# local points each frame is still rebase-safe.
		wisps[index].points = build_wisp_points(
			LENGTHS[index], ARCS[index], PHASE_OFFSETS[index], elapsed)
		# Fade before wrapping across the bounded travel span; no line pops between edges.
		var edge_fade: float = smoothstep(0.0, 0.14, cycle) \
			* (1.0 - smoothstep(0.86, 1.0, cycle))
		var pulse: float = 1.0 - PULSE_DEPTH * (0.5 - 0.5 * cos(
			TAU * (elapsed * PULSE_SPEED + PHASE_OFFSETS[index])))
		wisps[index].modulate = Color(1.0, 1.0, 1.0,
			event_strength * STRENGTHS[index] * edge_fade * pulse)
	visible = true


# The base arc plus two travelling waves. `phase` separates the ribbons so they never undulate
# in unison, and `elapsed` is the event clock -- at 0 this returns the old static arc, which is
# what _ready() builds before the first push arrives.
func build_wisp_points(length: float, arc: float, phase: float, elapsed: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(POINT_COUNT)
	var offset: float = phase * TAU
	for point_index: int in range(POINT_COUNT):
		var u: float = float(point_index) / float(POINT_COUNT - 1)
		var base: float = -sin(PI * u) * arc
		var wave: float = sin(u * TAU * WAVE_CYCLES - elapsed * WAVE_SPEED + offset) \
			* arc * WAVE_AMPLITUDE
		var wave2: float = sin(u * TAU * WAVE2_CYCLES - elapsed * WAVE2_SPEED + offset * 1.7) \
			* arc * WAVE2_AMPLITUDE
		# Pinned at both ends: the taper gradient already fades the tips to nothing, and letting
		# them swing as freely as the middle makes the ribbon flick rather than flow.
		var envelope: float = sin(PI * u)
		points[point_index] = Vector2((u - 0.5) * length, base + (wave + wave2) * envelope)
	return points


func build_taper_gradient(color: Color) -> Gradient:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.20, 0.50, 0.80, 1.0])
	gradient.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, 0.55),
		Color(color.r, color.g, color.b, 1.0),
		Color(color.r, color.g, color.b, 0.55),
		Color(color.r, color.g, color.b, 0.0),
	])
	return gradient
