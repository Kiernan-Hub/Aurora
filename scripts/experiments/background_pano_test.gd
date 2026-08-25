extends Node2D

# Throwaway seam test: scrolls the three fog-panorama panels in order
# archtower -> spikefield -> massif (the "5, 3, 4" order picked by eye) so the seams can
# be judged at gameplay-like scroll speed. Not wired into main.tscn or
# background_generator.gd -- this is standalone, run this scene directly.

@export var cycle_seconds: float = 20.0

const PANEL_PATHS: Array[String] = [
	"res://assets/textures/experiments/fog_pano_archtower.png",
	"res://assets/textures/experiments/fog_pano_spikefield.png",
	"res://assets/textures/experiments/fog_pano_massif.png",
]

var strip_width: float = 0.0
var scroll_speed: float = 0.0
var strip_a: Node2D
var strip_b: Node2D


func _ready() -> void:
	var textures: Array[Texture2D] = []
	for path: String in PANEL_PATHS:
		textures.append(load(path) as Texture2D)

	var viewport_height: float = get_viewport_rect().size.y
	var panel_size: Vector2 = textures[0].get_size()
	var display_scale: float = viewport_height / panel_size.y

	strip_a = build_strip(textures, display_scale)
	strip_a.position.y = -viewport_height * 0.5
	add_child(strip_a)
	strip_b = build_strip(textures, display_scale)
	strip_b.position = Vector2(strip_width, -viewport_height * 0.5)
	add_child(strip_b)

	scroll_speed = strip_width / cycle_seconds


func build_strip(textures: Array[Texture2D], display_scale: float) -> Node2D:
	var strip: Node2D = Node2D.new()
	var x: float = 0.0
	for texture: Texture2D in textures:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2(display_scale, display_scale)
		sprite.position = Vector2(x, 0.0)
		strip.add_child(sprite)
		x += texture.get_size().x * display_scale
	strip_width = x
	return strip


func _process(delta: float) -> void:
	strip_a.position.x -= scroll_speed * delta
	strip_b.position.x -= scroll_speed * delta
	if strip_a.position.x <= -strip_width:
		strip_a.position.x += 2.0 * strip_width
	if strip_b.position.x <= -strip_width:
		strip_b.position.x += 2.0 * strip_width
