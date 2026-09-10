extends Node2D

class_name AuroraWisps

# Three quiet arcs behind gameplay. They are rebuilt from the current player/surface and
# Aurora clock each frame, so there is no trail history to repair during a world rebase.
const WISP_COUNT: int = 3
const POINT_COUNT: int = 9
const TRAVEL_SPAN: float = 760.0
const TRAVEL_SPEED: float = 32.0
const LENGTHS: Array[float] = [190.0, 150.0, 118.0]
const HEIGHTS: Array[float] = [-70.0, -112.0, -44.0]
const ARCS: Array[float] = [22.0, 16.0, 12.0]
const WIDTHS: Array[float] = [4.5, 3.5, 2.8]
const STRENGTHS: Array[float] = [0.17, 0.13, 0.10]
const COLORS: Array[Color] = [
	Color(0.25, 1.0, 0.70),
	Color(0.28, 0.90, 1.0),
	Color(0.72, 0.45, 1.0),
]
const PHASE_OFFSETS: Array[float] = [0.08, 0.46, 0.76]

@export var player_path: NodePath = NodePath("../Player")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")

var player: Player
var terrain_generator: TerrainGenerator
var wisps: Array[Line2D] = []
var disabled: bool = false


func _ready() -> void:
	visible = false
	if DisplayServer.get_name() == "headless":
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
		wisp.points = build_wisp_points(LENGTHS[index], ARCS[index])
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
		# Fade before wrapping across the bounded travel span; no line pops between edges.
		var edge_fade: float = smoothstep(0.0, 0.14, cycle) \
			* (1.0 - smoothstep(0.86, 1.0, cycle))
		wisps[index].modulate = Color(1.0, 1.0, 1.0,
			event_strength * STRENGTHS[index] * edge_fade)
	visible = true


func build_wisp_points(length: float, arc: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(POINT_COUNT)
	for point_index: int in range(POINT_COUNT):
		var u: float = float(point_index) / float(POINT_COUNT - 1)
		points[point_index] = Vector2((u - 0.5) * length, -sin(PI * u) * arc)
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
