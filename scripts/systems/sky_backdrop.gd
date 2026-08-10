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
# Midpoints of the two segments, so the starting sky is the same straight ramp it always was.
const SKY_UPPER_COLOR: Color = Color(0.67, 0.775, 0.885)
const SKY_LOWER_COLOR: Color = Color(0.81, 0.875, 0.935)
const GRADIENT_TEXTURE_HEIGHT: int = 256
# The sky varies HORIZONTALLY as well now (palette.sky_tint_left/right), so the texture can no
# longer be one stretched column -- and it can no longer be a GradientTexture2D at all, since
# that is a 1-D gradient projected across the image and cannot express two independent axes.
# It is baked by hand instead, from the vertical Gradient times a horizontal tint lerp.
#
# EIGHT columns is not a resolution compromise. The horizontal term is a straight lerp between
# two colours, and the canvas filter interpolates linearly between texels, so two columns would
# already be exact; eight is headroom for a future non-linear tint and still only 2048 pixels
# to walk when a transition rebakes it every frame.
const SKY_TEXTURE_WIDTH: int = 8

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

# --- Sun / moon disc ---------------------------------------------------------------------
# Solid across the first two stops, then a shoulder and a soft halo out to the rect edge. The
# shoulder is two stops rather than one so the disc's edge is softened by roughly a pixel at
# any size -- a hard cut would alias badly on a small bright circle over a flat sky.
const CELESTIAL_TEXTURE_SIZE: int = 256
const CELESTIAL_FALLOFF_OFFSETS: PackedFloat32Array = [0.0, 0.36, 0.42, 0.66, 1.0]
const CELESTIAL_FALLOFF_ALPHAS: PackedFloat32Array = [1.0, 1.0, 0.62, 0.18, 0.0]
# The rect is this much larger than the solid disc, so palette.celestial_size can mean the
# radius of the disc you actually see rather than the radius of its invisible halo.
# 1/2.6 = 0.385, which is where the alpha shoulder above sits.
const CELESTIAL_HALO_SCALE: float = 2.6
const STARTING_CELESTIAL_STRENGTH: float = 0.0
# The moon is the SAME disc with a bite taken out of it. A sun and a moon that differ only in
# tint are indistinguishable in play -- both read as "a pale dot" -- and a crescent is the one
# shape nobody has to think about. Units are fractions of the texture's half-width, so they
# line up with the gradient offsets above: the solid core ends around 0.39.
const MOON_CUT_RADIUS: float = 0.36
const MOON_CUT_OFFSET: Vector2 = Vector2(0.16, -0.05)
# Not cut to fully transparent: a trace of the dark limb keeps it reading as a sphere rather
# than as a detached sliver.
const MOON_CUT_RESIDUAL: float = 0.06
# Soft edge on the cut, in the same fractional units, so the terminator is not aliased.
const MOON_CUT_SOFTNESS: float = 0.012

# --- Stars -------------------------------------------------------------------------------
# Built in code rather than shipped as a PNG, the same way snow_drift.gd builds its flake dot
# and build_sky_texture() builds the gradient. One less asset to import, and it cannot go
# stale against a palette.
#
# 16:9 so the scale factor is the same on both axes at the common aspect, which keeps stars
# ROUND. A square texture stretched to a 16:9 viewport squashes every dot to 0.63 of its
# height, and a one-pixel dot squashed like that flickers in and out as it lands on and off
# the pixel grid.
const STAR_TEXTURE_SIZE: Vector2i = Vector2i(1024, 576)
# Scattered uniformly, so only the ones that land in the open sky band above the ridgeline are
# ever seen -- roughly a third. That is correct (stars do not show through mountains) and the
# count is chosen for what survives, not for what is drawn.
const STAR_COUNT: int = 300
# Fixed, so the sky is the same every run. NOT derived from session_seed: background code must
# never read it (visuals.md), and a starfield that reshuffles per run is a bug, not variety.
const STAR_RNG_SEED: int = 20260810
# Ceiling on the brightest star at star_density 1.0. Full white reads as pinpricks of paint.
const STAR_MAX_ALPHA: float = 0.9
# Fraction of stars that get a faint halo ring, so the field has a couple of sizes in it.
const STAR_HALO_CHANCE: float = 0.22
const STAR_HALO_ALPHA_SCALE: float = 0.3
const STARTING_STAR_DENSITY: float = 0.0

# The VERTICAL definition, five stops. Held so apply_palette() can recolour in place: it is
# sampled per row when the sky is rebaked, never rendered directly.
var sky_gradient: Gradient
# Reused across rebakes rather than reallocated -- a transition rebakes every frame it moves,
# and ImageTexture.update() wants the same size image each time anyway.
var sky_image: Image
var sky_texture: ImageTexture
# The bloom. Recoloured, moved and resized through its ANCHORS in apply_palette(), so it
# needs no _process, no resize handler and no viewport read -- see position_glow().
var sky_glow: TextureRect
var sky_stars: TextureRect
# The disc. Unlike the glow this is laid out in PIXELS (see palette.celestial_size), so its
# layout inputs are retained and reapplied whenever the viewport resizes.
var sky_celestial: TextureRect
var celestial_position: Vector2 = Vector2(0.5, 0.3)
var celestial_size: float = 0.03
# Both built once; apply_celestial() swaps between them. Safe to swap outright rather than
# cross-dissolve because NO TWO ADJACENT BIOMES BOTH HAVE A DISC -- see apply_celestial().
var celestial_sun_texture: Texture2D
var celestial_moon_texture: Texture2D


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

	# Above the gradient but BELOW the glow, so a dawn or dusk bloom washes the stars out near
	# the light instead of stars sitting on top of the sun. Draw order is tree order.
	sky_stars = TextureRect.new()
	sky_stars.name = "SkyStars"
	sky_stars.texture = build_star_texture()
	sky_stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# COVERED, not SCALE. Scaling to fit would stretch the field by the viewport's aspect and
	# turn every star into an ellipse; covering crops instead, so stars stay round on any
	# device and the only cost is losing some off the edges -- of which there are 300.
	sky_stars.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_stars.visible = STARTING_STAR_DENSITY > 0.0
	add_child(sky_stars)

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

	# Added last, so the disc draws over its own halo rather than under it.
	celestial_sun_texture = build_celestial_texture()
	celestial_moon_texture = build_moon_texture()
	sky_celestial = TextureRect.new()
	sky_celestial.name = "SkyCelestial"
	sky_celestial.texture = celestial_sun_texture
	sky_celestial.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky_celestial.stretch_mode = TextureRect.STRETCH_SCALE
	sky_celestial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_celestial.visible = STARTING_CELESTIAL_STRENGTH > 0.0
	add_child(sky_celestial)

	# The disc is the one thing here sized in pixels, so it is the one thing that does not
	# follow the viewport for free. Everything else in this file is anchored and needs no
	# signal. Reapplied rather than recomputed from a palette, because the palette that was
	# last pushed is a blended instance the director keeps mutating.
	get_viewport().size_changed.connect(layout_celestial)


# Called by biome_director.gd only. Never called under --headless.
func apply_palette(palette: BiomePalette) -> void:
	if sky_gradient == null:
		return
	# offsets and colors assigned as whole arrays rather than element-wise: Gradient only
	# emits its changed signal (and so only re-bakes the texture) on a property set, and a
	# per-element set_color/set_offset would bake three times per frame instead of two.
	set_gradient_stops(palette.sky_mid_offset, palette.sky_top, palette.sky_upper,
		palette.sky_mid, palette.sky_lower, palette.sky_horizon)
	bake_sky_texture(palette.sky_tint_left, palette.sky_tint_right)

	apply_stars(palette)
	apply_glow(palette)
	apply_celestial(palette)


# star_density has been authored in all eight palettes since the biome pass landed and read by
# nothing until now. It rides CHANNEL_ATMOSPHERE, with the snow -- stars are weather, not light.
#
# Density scales ALPHA rather than hiding individual stars, and the field is baked with a wide
# spread of per-star brightness so that works out: as alpha comes down the faint majority drop
# below perception first and only the brightest remain. Fading a uniform field would read as
# "dimmer stars"; fading a varied one reads as "fewer stars", which is what is wanted.
func apply_stars(palette: BiomePalette) -> void:
	if sky_stars == null:
		return
	sky_stars.visible = palette.star_density > 0.0
	if not sky_stars.visible:
		return
	sky_stars.modulate = Color(1.0, 1.0, 1.0, palette.star_density * STAR_MAX_ALPHA)


func apply_glow(palette: BiomePalette) -> void:
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


func apply_celestial(palette: BiomePalette) -> void:
	if sky_celestial == null:
		return
	sky_celestial.visible = palette.celestial_strength > 0.0
	if not sky_celestial.visible:
		return
	# Swapped outright rather than cross-dissolved between two stacked nodes, the way the ice
	# pattern has to be. That is only safe because no two ADJACENT biomes both have a disc, so
	# celestial_strength is always 0 somewhere in every transition that changes this -- the
	# swap happens while the node is invisible. If a second disc is ever authored next to an
	# existing one, this becomes a visible pop mid-transition and needs the two-node treatment.
	sky_celestial.texture = celestial_moon_texture if palette.celestial_is_moon else celestial_sun_texture
	var celestial_modulate: Color = palette.celestial_color
	celestial_modulate.a = palette.celestial_color.a * palette.celestial_strength
	sky_celestial.modulate = celestial_modulate
	celestial_position = palette.celestial_position
	celestial_size = palette.celestial_size
	layout_celestial()


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


# The disc, laid out in PIXELS rather than by anchor box -- because it has to be round.
#
# All four anchors collapse to the same point (its centre), and the offsets then carry a
# SQUARE pixel extent out from there. That is the whole trick: the anchor keeps the centre in
# the right place on any viewport, while the offsets keep the shape circular regardless of
# aspect ratio. Anchoring it the way the glow is anchored would make the radius a fraction of
# width horizontally and of height vertically, squashing the sun by 1.78:1 on a 16:9 screen.
#
# Radius derives from viewport HEIGHT on both axes, so the disc keeps a constant apparent size
# relative to how much sky there is, rather than growing on a wider phone.
func layout_celestial() -> void:
	if sky_celestial == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# The texture's solid core is only 1/CELESTIAL_HALO_SCALE of the rect, so the rect has to
	# be scaled up for celestial_size to mean the radius of the disc that is actually visible.
	var halo_radius: float = celestial_size * CELESTIAL_HALO_SCALE * viewport_size.y

	sky_celestial.anchor_left = celestial_position.x
	sky_celestial.anchor_right = celestial_position.x
	sky_celestial.anchor_top = celestial_position.y
	sky_celestial.anchor_bottom = celestial_position.y
	sky_celestial.offset_left = -halo_radius
	sky_celestial.offset_right = halo_radius
	sky_celestial.offset_top = -halo_radius
	sky_celestial.offset_bottom = halo_radius


func build_sky_texture() -> ImageTexture:
	sky_gradient = Gradient.new()
	set_gradient_stops(SKY_MID_OFFSET, SKY_TOP_COLOR, SKY_UPPER_COLOR, SKY_MID_COLOR,
		SKY_LOWER_COLOR, SKY_HORIZON_COLOR)

	sky_image = Image.create(SKY_TEXTURE_WIDTH, GRADIENT_TEXTURE_HEIGHT, false, Image.FORMAT_RGB8)
	sky_texture = ImageTexture.create_from_image(sky_image)
	bake_sky_texture(Color.WHITE, Color.WHITE)
	return sky_texture


# The five stops. The two extra offsets are DERIVED, at the midpoint of each segment, rather
# than being two more palette fields: what the extra stops are for is bending the ramp's
# colour, and letting their positions move too would be four interacting numbers to author per
# biome for no gain the colours cannot already express.
func set_gradient_stops(mid_offset: float, top: Color, upper: Color, mid: Color,
		lower: Color, horizon: Color) -> void:
	# Whole-array assignment, not per-element: Gradient emits `changed` on every property set,
	# and this is rebaked every frame of a transition.
	sky_gradient.offsets = PackedFloat32Array([
		0.0,
		mid_offset * 0.5,
		mid_offset,
		mid_offset + ((1.0 - mid_offset) * 0.5),
		1.0,
	])
	sky_gradient.colors = PackedColorArray([top, upper, mid, lower, horizon])


# Bakes the vertical ramp times the horizontal tint into sky_image.
#
# Separable, so it costs one Gradient sample per ROW plus a multiply per pixel, not a sample
# per pixel. 8x256 is 2048 pixels; at 60fps through a transition that is well under a tenth of
# a millisecond, and outside a transition apply_palette is not called at all (the director
# early-outs on unchanged progress).
#
# The tints are MULTIPLIERS, so this can only darken -- which is what keeps it safe on an LDR
# renderer where anything above 1.0 is silently clamped.
func bake_sky_texture(tint_left: Color, tint_right: Color) -> void:
	if sky_image == null:
		return

	# Hoisted out of the row loop: the horizontal term does not depend on y.
	var column_tints: Array[Color] = []
	for x: int in range(SKY_TEXTURE_WIDTH):
		var across: float = float(x) / float(SKY_TEXTURE_WIDTH - 1)
		column_tints.append(tint_left.lerp(tint_right, across))

	for y: int in range(GRADIENT_TEXTURE_HEIGHT):
		var down: float = float(y) / float(GRADIENT_TEXTURE_HEIGHT - 1)
		var band: Color = sky_gradient.sample(down)
		for x: int in range(SKY_TEXTURE_WIDTH):
			var tint: Color = column_tints[x]
			sky_image.set_pixel(x, y, Color(band.r * tint.r, band.g * tint.g, band.b * tint.b))

	sky_texture.update(sky_image)


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


# The starfield, scattered once at a fixed seed.
#
# LA8 rather than RGBA8: the stars are white and their colour comes from modulate, so only
# luminance and alpha are ever needed. Halves the image to ~1.1MB.
func build_star_texture() -> ImageTexture:
	var image: Image = Image.create(STAR_TEXTURE_SIZE.x, STAR_TEXTURE_SIZE.y, false, Image.FORMAT_LA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = STAR_RNG_SEED

	for star_index: int in range(STAR_COUNT):
		# Inset by one pixel so a halo never needs bounds-checking.
		var x: int = rng.randi_range(1, STAR_TEXTURE_SIZE.x - 2)
		var y: int = rng.randi_range(1, STAR_TEXTURE_SIZE.y - 2)
		# The wide brightness spread is what makes star_density read as COUNT rather than as
		# dimming -- see apply_stars().
		var brightness: float = rng.randf_range(0.3, 1.0)
		image.set_pixel(x, y, Color(1.0, 1.0, 1.0, brightness))

		if rng.randf() < STAR_HALO_CHANCE:
			var halo: Color = Color(1.0, 1.0, 1.0, brightness * STAR_HALO_ALPHA_SCALE)
			image.set_pixel(x - 1, y, halo)
			image.set_pixel(x + 1, y, halo)
			image.set_pixel(x, y - 1, halo)
			image.set_pixel(x, y + 1, halo)

	return ImageTexture.create_from_image(image)


# The disc: an opaque core with a soft halo. Same radial idiom as the glow, but the alpha is
# held flat at 1.0 across the first two stops, which is what makes it read as a body rather
# than as a second, smaller bloom. White here too -- the colour rides on modulate.
func build_celestial_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	var disc_colors: PackedColorArray = PackedColorArray()
	for stop_index: int in range(CELESTIAL_FALLOFF_ALPHAS.size()):
		disc_colors.append(Color(1.0, 1.0, 1.0, CELESTIAL_FALLOFF_ALPHAS[stop_index]))
	gradient.offsets = CELESTIAL_FALLOFF_OFFSETS
	gradient.colors = disc_colors

	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = CELESTIAL_TEXTURE_SIZE
	texture.height = CELESTIAL_TEXTURE_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

# The moon: the same disc and halo, with an offset circle subtracted to leave a crescent.
#
# Baked into an Image rather than assembled from gradients, because subtracting one circle
# from another is not something a radial GradientTexture2D can express. Same falloff stops as
# the sun, so the two still belong to the same sky -- only the SHAPE differs, which is the
# whole point: a sun and a moon that differ only in tint are indistinguishable in play.
func build_moon_texture() -> ImageTexture:
	var falloff: Gradient = Gradient.new()
	var moon_colors: PackedColorArray = PackedColorArray()
	for stop_index: int in range(CELESTIAL_FALLOFF_ALPHAS.size()):
		moon_colors.append(Color(1.0, 1.0, 1.0, CELESTIAL_FALLOFF_ALPHAS[stop_index]))
	falloff.offsets = CELESTIAL_FALLOFF_OFFSETS
	falloff.colors = moon_colors

	var image: Image = Image.create(CELESTIAL_TEXTURE_SIZE, CELESTIAL_TEXTURE_SIZE, false, Image.FORMAT_LA8)
	var half: float = float(CELESTIAL_TEXTURE_SIZE) * 0.5
	var centre: Vector2 = Vector2(half, half)
	var cut_centre: Vector2 = centre + (MOON_CUT_OFFSET * half)

	for y: int in range(CELESTIAL_TEXTURE_SIZE):
		for x: int in range(CELESTIAL_TEXTURE_SIZE):
			var point: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			# Normalised so 1.0 is the edge midpoint -- the same units the gradient offsets and
			# the MOON_CUT_* constants are written in.
			var radius: float = point.distance_to(centre) / half
			var alpha: float = falloff.sample(clampf(radius, 0.0, 1.0)).a

			# 0 well inside the cut, 1 well outside, smooth across the terminator.
			var outside_cut: float = smoothstep(
				MOON_CUT_RADIUS - MOON_CUT_SOFTNESS,
				MOON_CUT_RADIUS + MOON_CUT_SOFTNESS,
				point.distance_to(cut_centre) / half)
			alpha *= lerpf(MOON_CUT_RESIDUAL, 1.0, outside_cut)

			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(image)
