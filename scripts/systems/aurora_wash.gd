extends CanvasLayer

class_name AuroraWash

# A single, restrained screen-space light wash between the background weather/ridges
# and every gameplay object. AuroraDirector owns the clock; this node owns only the look.
const WASH_COLOR: Color = Color(0.12, 0.86, 0.56, 1.0)
const MAX_OPACITY: float = 0.11
const TEXTURE_HEIGHT: int = 128

var wash: TextureRect


func _ready() -> void:
	wash = TextureRect.new()
	wash.name = "Wash"
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.texture = build_wash_texture()
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.visible = false
	add_child(wash)


func apply_aurora(blend: float, _elapsed: float) -> void:
	if wash == null:
		return
	var strength: float = clampf(blend, 0.0, 1.0)
	wash.visible = strength > 0.0
	wash.modulate = Color(1.0, 1.0, 1.0, strength)


# Transparent overhead, broadest around the horizon, then quiet again near the floor.
# The hard opacity ceiling lives in the pixels, so no caller can accidentally turn this
# into a flat fog sheet by passing a value above one.
func build_wash_texture() -> Texture2D:
	var image: Image = Image.create(1, TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in range(TEXTURE_HEIGHT):
		var t: float = float(y) / float(TEXTURE_HEIGHT - 1)
		var upper_rise: float = smoothstep(0.20, 0.58, t)
		var lower_fall: float = 1.0 - smoothstep(0.72, 1.0, t)
		var color: Color = WASH_COLOR
		color.a = MAX_OPACITY * upper_rise * lower_fall
		image.set_pixel(0, y, color)
	return ImageTexture.create_from_image(image)
