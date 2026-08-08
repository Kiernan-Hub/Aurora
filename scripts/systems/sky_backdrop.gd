extends CanvasLayer

# The sky: one static, full-screen vertical gradient. No scrolling, no recycling, no
# _process and no _physics_process -- it is built once in _ready() and never touched
# again, which is what keeps it free inside the six headless gates (every one of them
# instantiates scenes/main.tscn, so everything in this file runs on every gate frame).
#
# Deliberately a CanvasLayer holding an ANCHORED Control, rather than anything in world
# space or a fixed-size rect:
#
#   * project.godot sets no window/size/viewport_width or _height and uses
#     stretch/aspect="expand", so the visible rect genuinely varies with device aspect
#     ratio. Full-rect anchors cover it on every device; a fixed size would be a guess
#     that letterboxes or overdraws somewhere. (That unset base size is a real open
#     decision -- docs/review/2026-08-03-architecture-audit.md B4 -- but it is not this
#     file's to make, so this file simply survives either answer.)
#   * A CanvasLayer is screen space, so main.gd's world rebase -- which shifts Y roughly
#     every 26s -- cannot move it. Same reason every ParallaxLayer keeps motion_scale.y
#     at 0; see docs/development/dead_code.md, "Vertical parallax -- tried, reverted".
#
# main.tscn sets layer = -200, behind ParallaxBackground's engine default of -100.

# Day reading of the reference art (the reference itself is a night scene; the palette
# family, the layering and the negative space carry over, the darkness does not). Pale
# toward the horizon so the distant ridges have something to dissolve into, and so the
# near-white terrain still separates cleanly from the sky above it.
const SKY_TOP_COLOR: Color = Color(0.60, 0.72, 0.86)
const SKY_MID_COLOR: Color = Color(0.74, 0.83, 0.91)
const SKY_HORIZON_COLOR: Color = Color(0.88, 0.92, 0.96)
# Where SKY_MID_COLOR sits between top and horizon. Past halfway, so the upper sky holds
# its deeper blue over most of the frame and the pale band stays a horizon effect rather
# than washing out the whole screen.
const SKY_MID_OFFSET: float = 0.58
# Sampled vertically and stretched horizontally, so only the height needs resolution.
const GRADIENT_TEXTURE_HEIGHT: int = 256


func _ready() -> void:
	var sky: TextureRect = TextureRect.new()
	sky.name = "SkyGradient"
	sky.texture = build_sky_texture()
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	# MANDATORY, not tidiness: Control defaults to MOUSE_FILTER_STOP, and this one covers
	# the entire screen. Left at the default it is a full-screen input eater sitting under
	# the pause button and every menu.
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sky)


func build_sky_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, SKY_MID_OFFSET, 1.0])
	gradient.colors = PackedColorArray([SKY_TOP_COLOR, SKY_MID_COLOR, SKY_HORIZON_COLOR])

	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	# 1px wide: the gradient is purely vertical, and STRETCH_SCALE with the project's
	# default linear canvas filtering spreads that single column across any width.
	texture.width = 1
	texture.height = GRADIENT_TEXTURE_HEIGHT
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture
