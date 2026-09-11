extends Node2D

class_name AuroraWings

# A brief side-profile wing apparition, not a movement mode. Six immutable feather arcs sit
# behind the skater; the Aurora clock only changes their transform and opacity.
const APPEAR_START_SECONDS: float = 20.0
const APPEAR_FULL_SECONDS: float = 27.0
const RELEASE_START_SECONDS: float = 44.0
const RELEASE_END_SECONDS: float = 51.0
const MAX_STRENGTH: float = 0.52
const FEATHER_COLORS: Array[Color] = [
	Color(0.34, 1.0, 0.78),
	Color(0.35, 0.91, 1.0),
	Color(0.72, 0.48, 1.0),
]
const FEATHER_POINTS: Array[Array] = [
	[Vector2(0, -5), Vector2(-25, -30), Vector2(-57, -46), Vector2(-82, -38)],
	[Vector2(0, -2), Vector2(-31, -18), Vector2(-65, -25), Vector2(-94, -12)],
	[Vector2(0, 2), Vector2(-34, -6), Vector2(-66, 3), Vector2(-84, 19)],
	[Vector2(2, 1), Vector2(-20, 20), Vector2(-49, 33), Vector2(-70, 27)],
	[Vector2(2, 4), Vector2(-25, 29), Vector2(-53, 48), Vector2(-77, 43)],
	[Vector2(3, 7), Vector2(-20, 38), Vector2(-43, 59), Vector2(-63, 55)],
]

@export var player_path: NodePath = NodePath("../Player")

var player: Player
var feathers: Array[Line2D] = []
var disabled: bool = false


func _ready() -> void:
	visible = false
	if DisplayServer.get_name() == "headless":
		disabled = true
		return
	player = get_node_or_null(player_path) as Player
	if player == null:
		disabled = true
		push_warning("AuroraWings disabled: missing player.")
		return

	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for index: int in range(FEATHER_POINTS.size()):
		var feather: Line2D = Line2D.new()
		feather.name = "Feather%d" % index
		feather.points = PackedVector2Array(FEATHER_POINTS[index])
		feather.width = 4.0 if index < 3 else 3.2
		feather.gradient = build_feather_gradient(FEATHER_COLORS[index % FEATHER_COLORS.size()])
		feather.joint_mode = Line2D.LINE_JOINT_ROUND
		feather.begin_cap_mode = Line2D.LINE_CAP_ROUND
		feather.end_cap_mode = Line2D.LINE_CAP_ROUND
		feather.antialiased = true
		feather.material = additive
		feathers.append(feather)
		add_child(feather)


func apply_aurora(blend: float, elapsed: float) -> void:
	if disabled:
		return
	var strength: float = get_wing_strength(blend, elapsed)
	if strength <= 0.0 or (not player.is_on_floor() and not player.is_aurora_flight_active):
		visible = false
		return
	global_position = player.global_position + Vector2(-2.0, -8.0).rotated(player.animated_sprite.rotation)
	rotation = player.animated_sprite.rotation
	var breath: float = 1.0 + 0.055 * sin(elapsed * 1.15)
	scale = Vector2(1.0, breath)
	modulate = Color(1.0, 1.0, 1.0, strength * MAX_STRENGTH)
	visible = true


func get_wing_strength(blend: float, elapsed: float) -> float:
	var arrival: float = smoothstep(APPEAR_START_SECONDS, APPEAR_FULL_SECONDS, elapsed)
	var release: float = 1.0 - smoothstep(RELEASE_START_SECONDS, RELEASE_END_SECONDS, elapsed)
	return clampf(blend, 0.0, 1.0) * arrival * release


func build_feather_gradient(color: Color) -> Gradient:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.72, 1.0])
	gradient.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.15),
		Color(color.r, color.g, color.b, 1.0),
		Color(color.r, color.g, color.b, 0.62),
		Color(color.r, color.g, color.b, 0.0),
	])
	return gradient
