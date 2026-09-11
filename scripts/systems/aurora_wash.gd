extends CanvasLayer

class_name AuroraWash

# A single, restrained screen-space light wash between the background weather/ridges
# and every gameplay object. AuroraDirector owns the clock; this node owns only the look.
const WASH_COLOR: Color = Color(0.12, 0.86, 0.56, 1.0)
const MAX_OPACITY: float = 0.15
const TEXTURE_HEIGHT: int = 128
const TEXTURE_WIDTH: int = 96
# What the floor of the gradient keeps, as a fraction of the horizon peak. The old curve fell
# to ZERO by the bottom of the screen -- the one strip where the player and the terrain
# actually are -- which is most of why the light read as "only up top".
const FLOOR_KEEP: float = 0.55
# Broad horizontal lobes, so there is something in the pixels for the drift to move.
const LOBE_DEPTH: float = 0.35
# The rect is grown past the screen on both sides and slid inside that margin, so an edge can
# never enter view. Anchored offsets, so this is correct at every viewport width.
const DRIFT_MARGIN: float = 220.0
const DRIFT_PERIOD: float = 23.0
# Two incommensurate periods: the breath must not visibly loop with the drift over 61s.
const BREATH_PERIOD: float = 17.0
const BREATH_DEPTH: float = 0.28

var wash: TextureRect


func _ready() -> void:
	wash = TextureRect.new()
	wash.name = "Wash"
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.offset_left = -DRIFT_MARGIN
	wash.offset_right = DRIFT_MARGIN
	wash.texture = build_wash_texture()
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.visible = false
	add_child(wash)


# The clock was already being passed and thrown away. The sky folds and moves; a still tint
# under it reads as a filter over the scene rather than as light falling into it, which is
# the whole complaint. Nothing here changes the curtains -- only the world response.
func apply_aurora(blend: float, elapsed: float) -> void:
	if wash == null:
		return
	var strength: float = clampf(blend, 0.0, 1.0)
	wash.visible = strength > 0.0
	if strength <= 0.0:
		return

	var drift: float = sin(TAU * elapsed / DRIFT_PERIOD)
	wash.offset_left = -DRIFT_MARGIN + drift * DRIFT_MARGIN
	wash.offset_right = DRIFT_MARGIN + drift * DRIFT_MARGIN

	var breath: float = 1.0 + BREATH_DEPTH * sin(TAU * elapsed / BREATH_PERIOD)
	wash.modulate = Color(1.0, 1.0, 1.0, strength * breath)


# Transparent overhead, broadest around the horizon, then settling to FLOOR_KEEP of that peak
# rather than to nothing. The hard opacity ceiling still lives in the pixels, so no caller can
# turn this into a flat fog sheet by passing a value above one -- BREATH_DEPTH is accounted for
# in MAX_OPACITY, which is why the ceiling did not rise by the full amount it looks like.
func build_wash_texture() -> Texture2D:
	var image: Image = Image.create(TEXTURE_WIDTH, TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in range(TEXTURE_HEIGHT):
		var t: float = float(y) / float(TEXTURE_HEIGHT - 1)
		var upper_rise: float = smoothstep(0.20, 0.58, t)
		var lower_fall: float = lerpf(1.0, FLOOR_KEEP, smoothstep(0.72, 1.0, t))
		for x: int in range(TEXTURE_WIDTH):
			var u: float = float(x) / float(TEXTURE_WIDTH - 1)
			# Two lobes at different rates so the drift never reads as a single sliding band.
			var lobe: float = 1.0 - LOBE_DEPTH * (
				0.6 * (0.5 - 0.5 * cos(TAU * u)) + 0.4 * (0.5 - 0.5 * cos(TAU * u * 2.0 + 1.1)))
			var color: Color = WASH_COLOR
			color.a = MAX_OPACITY * upper_rise * lower_fall * lobe
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
