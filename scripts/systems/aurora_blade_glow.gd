extends Node2D

class_name AuroraBladeGlow

# A compact contact light, driven entirely by AuroraDirector's existing ramp.
# No trail or particles in this slice: the glow marks the skater/ice connection without
# creating another lifetime, pool, or rebase problem.
const TEXTURE_SIZE: Vector2i = Vector2i(96, 32)
const HALO_COLOR: Color = Color(0.24, 1.0, 0.72, 1.0)
const HALO_STRENGTH: float = 0.52
const CORE_COLOR: Color = Color(0.72, 1.0, 0.94, 0.90)
const CORE_LENGTH: float = 34.0
const CORE_WIDTH: float = 2.2
const CONTACT_Y_OFFSET: float = -2.0

@export var player_path: NodePath = NodePath("../Player")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")

var player: Player
var terrain_generator: TerrainGenerator
var halo: Sprite2D
var core: Line2D
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
		push_warning("AuroraBladeGlow disabled: missing player or terrain.")
		return

	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	halo = Sprite2D.new()
	halo.name = "Halo"
	halo.texture = build_halo_texture()
	halo.material = additive
	add_child(halo)

	core = Line2D.new()
	core.name = "Core"
	core.points = PackedVector2Array([
		Vector2(-CORE_LENGTH * 0.5, 0.0),
		Vector2(CORE_LENGTH * 0.5, 0.0),
	])
	core.width = CORE_WIDTH
	core.default_color = CORE_COLOR
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode = Line2D.LINE_CAP_ROUND
	core.antialiased = true
	core.material = additive
	add_child(core)


func apply_aurora(blend: float, _elapsed: float) -> void:
	if disabled:
		return
	var strength: float = clampf(blend, 0.0, 1.0)
	if strength <= 0.0 or not player.is_on_floor():
		visible = false
		return

	global_position = Vector2(
		player.global_position.x,
		terrain_generator.get_surface_world_y(player.global_position.x) + CONTACT_Y_OFFSET,
	)
	rotation = terrain_generator.get_slope_angle_at_x(player.global_position.x)
	halo.modulate = Color(1.0, 1.0, 1.0, strength * HALO_STRENGTH)
	core.modulate = Color(1.0, 1.0, 1.0, strength)
	visible = true


func build_halo_texture() -> Texture2D:
	var image: Image = Image.create(TEXTURE_SIZE.x, TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	var centre: Vector2 = Vector2(TEXTURE_SIZE) * 0.5
	for y: int in range(TEXTURE_SIZE.y):
		for x: int in range(TEXTURE_SIZE.x):
			var offset: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5) - centre) / centre
			var distance: float = offset.length()
			var color: Color = HALO_COLOR
			color.a = pow(1.0 - smoothstep(0.08, 1.0, distance), 1.8)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
