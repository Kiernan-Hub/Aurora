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

# These are now only the STARTING sky, not the sky. biome_director.gd overwrites them
# through apply_palette() below on the first frame of a run and again through every
# transition. They still matter in two cases: under --headless, where the director returns
# early having applied nothing (so all six gates see exactly the sky they saw before the
# biome pass existed), and as the value on screen if the director ever fails to resolve.
#
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

# --- Directional glow ------------------------------------------------------------------
# Square, and only 256 across: it is a smooth blob with no detail in it, so all the
# resolution buys is fewer banding steps once it is stretched across most of the screen.
const GLOW_TEXTURE_SIZE: int = 256
# Alpha falloff from the centre out. Roughly (1-t)^2 rather than the linear ramp two stops
# would give -- a linear falloff has a visible hard outer circle where it reaches zero,
# because the eye finds the discontinuity in the SLOPE, not in the value.
#
# ARRAY LITERAL, NOT PackedFloat32Array([...]). The explicit constructor is a CALL, and a call
# is not a constant expression, so `const X: PackedFloat32Array = PackedFloat32Array([...])`
# is a parse error -- while the bare literal converts at compile time and is fine. Do not
# "tidy" these back into the constructor form; the type annotation already does that work.
const GLOW_FALLOFF_OFFSETS: PackedFloat32Array = [0.0, 0.25, 0.5, 0.75, 1.0]
const GLOW_FALLOFF_ALPHAS: PackedFloat32Array = [1.0, 0.62, 0.32, 0.11, 0.0]
# The starting glow is OFF. Every one of the six headless gates instantiates main.tscn, and
# biome_director never applies a palette under --headless -- so this value is the sky they
# see. At 0 the node is hidden and this whole feature is byte-identical to not existing,
# which is what keeps 1a incapable of moving a gate result.
const STARTING_GLOW_STRENGTH: float = 0.0

# Held so apply_palette() can recolour the sky in place. A Gradient is mutable and
# GradientTexture2D re-bakes itself when its gradient changes, so a biome transition costs
# one 1x256 texture update per frame it actually moves -- no node work, no rebuild, and
# nothing for the _process this file still deliberately does not have to do.
var sky_gradient: Gradient
# The bloom. Recoloured, moved and resized through its ANCHORS in apply_palette(), so it
# needs no _process, no resize handler and no viewport read -- see position_glow().
var sky_glow: TextureRect


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

	# Added AFTER the gradient so it draws over it. Both are children of this CanvasLayer, so
	# draw order is tree order -- there is no z_index anywhere in the project.
	sky_glow = TextureRect.new()
	sky_glow.name = "SkyGlow"
	sky_glow.texture = build_glow_texture()
	sky_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky_glow.stretch_mode = TextureRect.STRETCH_SCALE
	sky_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_glow.visible = STARTING_GLOW_STRENGTH > 0.0
	add_child(sky_glow)


# Called by biome_director.gd only. Never called under --headless.
func apply_palette(palette: BiomePalette) -> void:
	if sky_gradient == null:
		return
	# offsets and colors assigned as whole arrays rather than element-wise: Gradient only
	# emits its changed signal (and so only re-bakes the texture) on a property set, and a
	# per-element set_color/set_offset would bake three times per frame instead of two.
	sky_gradient.offsets = PackedFloat32Array([0.0, palette.sky_mid_offset, 1.0])
	sky_gradient.colors = PackedColorArray([palette.sky_top, palette.sky_mid, palette.sky_horizon])

	if sky_glow == null:
		return
	# Hidden outright rather than drawn at alpha 0. A fully transparent full-screen TextureRect
	# still rasterises every pixel it covers, and on a mobile GPU stacked full-screen alpha is
	# the fill-rate cost that actually matters here -- same reasoning as
	# terrain_generator.paint_ice_band()'s `visible = opacity > 0`.
	sky_glow.visible = palette.glow_strength > 0.0
	if not sky_glow.visible:
		return
	var glow_modulate: Color = palette.glow_color
	glow_modulate.a = palette.glow_color.a * palette.glow_strength
	sky_glow.modulate = glow_modulate
	position_glow(palette.glow_position, palette.glow_radius)


# Places the bloom by ANCHOR rather than by position/size in pixels.
#
# Anchors are fractions of the parent rect, which is exactly what glow_position and
# glow_radius already are -- so the layout is correct on any viewport with no resize signal
# to connect, no get_viewport_rect() read, and nothing to recompute when the window changes.
# That matters more here than usual: project.godot pins no viewport size and stretches with
# aspect="expand", so the visible rect genuinely differs per device (see this file's header).
#
# The rect is deliberately NOT clamped to the screen. Fragments outside the viewport are
# scissored by the rasteriser before shading, so a bloom hanging off the left edge costs only
# the part you can see; clamping would instead squash the texture and change the shape of the
# falloff. The worst case is a centred glow large enough to cover everything, which is one
# full-screen alpha layer -- the budget this pass is working to.
func position_glow(glow_position: Vector2, glow_radius: Vector2) -> void:
	sky_glow.anchor_left = glow_position.x - glow_radius.x
	sky_glow.anchor_right = glow_position.x + glow_radius.x
	sky_glow.anchor_top = glow_position.y - glow_radius.y
	sky_glow.anchor_bottom = glow_position.y + glow_radius.y
	# Anchors alone do not move a Control -- the offsets are pixel deltas from them, and they
	# retain whatever the previous layout left behind. Zeroing them is what makes the rect
	# exactly the anchored box.
	sky_glow.offset_left = 0.0
	sky_glow.offset_right = 0.0
	sky_glow.offset_top = 0.0
	sky_glow.offset_bottom = 0.0


func build_sky_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, SKY_MID_OFFSET, 1.0])
	gradient.colors = PackedColorArray([SKY_TOP_COLOR, SKY_MID_COLOR, SKY_HORIZON_COLOR])
	sky_gradient = gradient

	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	# 1px wide: the gradient is purely vertical, and STRETCH_SCALE with the project's
	# default linear canvas filtering spreads that single column across any width.
	texture.width = 1
	texture.height = GRADIENT_TEXTURE_HEIGHT
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture


# The bloom itself: white, fading to transparent. The COLOUR comes from the TextureRect's
# modulate, so one texture serves every biome and a transition never rebakes it -- only the
# vertical sky gradient above does that.
#
# Same GradientTexture2D idiom snow_drift.gd already uses for its flake dot, just larger and
# with a softer tail.
func build_glow_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	var glow_colors: PackedColorArray = PackedColorArray()
	for stop_index: int in range(GLOW_FALLOFF_ALPHAS.size()):
		glow_colors.append(Color(1.0, 1.0, 1.0, GLOW_FALLOFF_ALPHAS[stop_index]))
	gradient.offsets = GLOW_FALLOFF_OFFSETS
	gradient.colors = glow_colors

	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = GLOW_TEXTURE_SIZE
	texture.height = GLOW_TEXTURE_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	# Centre out to the middle of the right edge, so gradient offset 1.0 lands exactly on the
	# rect's edge midpoint. The corners sit at distance ~1.41 and clamp to the final stop,
	# which is fully transparent -- so the blob never shows the square it is drawn in.
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
