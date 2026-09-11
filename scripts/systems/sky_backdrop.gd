extends CanvasLayer

# The sky: one static, full-screen vertical gradient. No scrolling, no recycling, no
# _process and no _physics_process -- it is built once in _ready() and never touched
# again, which is what keeps it free inside the six headless gates (every one of them
# instantiates scenes/main.tscn, so everything in this file runs on every gate frame).
#
# Deliberately a CanvasLayer holding an ANCHORED Control, rather than anything in world
# space or a fixed-size rect:
#
#   * The pinned 1152x648 base uses stretch/aspect="expand", so the visible
#     rect still varies with device aspect ratio. Full-rect anchors cover it.
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
# THE MOON IS AUTHORED ART, unlike the sun disc, the glow and the stars above it, which are
# all built in code. Those are pure gradients that a few constants describe exactly. A moon is
# not: the thing that makes one read as a moon rather than a pale dot is surface detail, and
# the procedural version tried to buy that with a terminator cut. It failed badly -- the cut
# disc was the same radius as the lit core and offset less than that radius, so it covered the
# centre and left a bright rim around a dark middle. On screen that is a diamond-ring eclipse.
#
# Extracted from art_source/background/moons.png, panel 6 of the 8 the owner supplied. Alpha is
# GEOMETRIC -- a solid disc with a one-pixel soft edge -- because the moon is a body and its
# craters must not make it see-through, which is the trap the first extraction fell into. Only
# the halo outside the body is brightness-derived, taken from the art. Luminance carries the
# crater shading (0.72..1.0), so palette.celestial_color still tints the whole thing exactly as
# it tinted the flat white disc.
#
# The crop is 2.6x the disc radius, matching CELESTIAL_HALO_SCALE, so every palette's authored
# celestial_size still means the radius of the disc you actually see.
const MOON_TEXTURE: Texture2D = preload("res://assets/textures/background/moon_full.png")

# --- Aurora borealis ---------------------------------------------------------------------
# The game's namesake, and the ONLY thing in this file that is not always-on: it is visible for
# ~61 seconds roughly once per 30 minutes of cumulative playtime and hidden the rest of the time.
# AuroraDirector owns when; this file owns nothing but the look. See apply_aurora().
#
# THREE CURTAINS, NOT ONE. A single band reads as a smear; three at different heights, hues,
# drift rates and breathing periods is what makes it read as depth. The count is the whole
# reason the bands are a loop over parallel constant arrays rather than three named nodes.
const AURORA_BAND_COUNT: int = 3
const AURORA_CURTAIN_SHADER: Shader = preload("res://shaders/aurora_curtain.gdshader")
const AURORA_REVEAL_SECONDS: float = 12.0
const AURORA_REVEAL_STAGGER: float = 0.65
# Per band, front (lowest, greenest) to back (highest, faintest). Index-aligned; all five
# arrays must stay the same length as AURORA_BAND_COUNT.
#
# FIXED COLOURS, NEVER A PALETTE LOOKUP, and this is a decision with a precedent behind it:
# lake_reflection.gd records the owner's 2026-08-14 call that a set piece must be recognisable
# on sight rather than recoloured by whichever biome it happens to interrupt, and
# BiomePalette.reflection_strength was DELETED rather than wired up for it. Same reasoning here.
# The biome still reaches the aurora, and only this way -- through the sky it is drawn over.
# THESE ARE ADDITIVE LIGHT, NOT PAINT, and that changes how they have to be authored: the
# band's own channel values land on the sky's directly, so anything left in a channel the sky
# is already strong in is wasted. The first draft used Color(0.24, 1.00, 0.56) for the green
# and it rendered CYAN, because starlit_night's upper sky is already b 0.42-0.48 and additive
# blending can only push blue further up. Blue is pulled almost out of the green here for that
# reason -- measured, not guessed: it moves the green hem from G/B 1.26 to 1.53.
#
# THE CEILING IS THE SKY, and it is worth knowing before anyone tries to make this greener. No
# additive layer can reduce the sky's own blue, so over these two palettes a fully saturated
# green is unreachable by construction. Making the aurora brighter does not fix it; it clips.
# Array[Color], not PackedColorArray, and Array[Vector2] below for the same reason: those two
# are the forms this project has already proven a const can hold (biome_director.gd's
# CHANNEL_CURVES). This file's own note above GLOW_FALLOFF_OFFSETS records the neighbouring
# trap -- a const initialiser must be a constant expression, so the explicit-constructor form
# is a parse error where the bare literal is fine.
const AURORA_BAND_COLORS: Array[Color] = [
	Color(0.05, 1.00, 0.24), # green, the one people picture
	Color(0.08, 0.86, 0.62), # teal, the bridge between the other two
	Color(0.60, 0.20, 1.00), # violet, highest and faintest
]
# Relative strength. The green carries it; the violet is a suggestion, not a second curtain.
#
# THE CEILING HERE IS CLIPPING, and it was measured against the real palettes rather than
# reasoned about. At [1.00, 0.44, 0.36] -- the values that looked right against a guessed dark
# sky -- 4.6% of the screen blows out to flat white over twilight_blue, which is the brighter of
# the two night biomes (sky_top 0.26, 0.28, 0.50). At these values the peak is 1.03 with 0.02%
# clipped, and that remainder is the brightest pixels of the hem itself, where a white-hot core
# is what an aurora actually looks like. Raise any of these three and re-measure both palettes.
const AURORA_BAND_WEIGHTS: PackedFloat32Array = [0.70, 0.28, 0.24]
# The bright hems must sit ABOVE the opaque ridges, not merely the rect tops.
# These bounds keep the green hem near y=0.18 and the other hems higher; the
# soft upper tails can extend offscreen. Verified with scenery present.
const AURORA_BAND_TOPS: PackedFloat32Array = [-0.11, -0.16, -0.20]
const AURORA_BAND_BOTTOMS: PackedFloat32Array = [0.23, 0.17, 0.13]
# Seconds per full horizontal drift cycle, and per brightness breath. Deliberately coprime-ish
# and none of them a divisor of another: bands that share a period visibly pulse together, which
# reads as one object flickering rather than three curtains moving independently.
const AURORA_DRIFT_PERIODS: PackedFloat32Array = [47.0, 31.0, 71.0]
const AURORA_BREATH_PERIODS: PackedFloat32Array = [13.0, 19.0, 23.0]
# How far a band slides, as a fraction of viewport width.
const AURORA_DRIFT_SPAN: float = 0.16
# The vertical bob, as a fraction of viewport height. An order of magnitude smaller than the
# drift on purpose: curtains move sideways, and a band that visibly rises and falls reads as the
# whole sky sliding rather than as light moving through it.
const AURORA_BAND_BOB: float = 0.012
# How much wider than the screen each rect is, per side. Must exceed AURORA_DRIFT_SPAN or a
# drifting band walks its own edge into view. This is why the texture needs no seamless wrap:
# the rect is simply always wider than what it has to cover.
const AURORA_OVERSCAN: float = 0.6
# Floor on the breath, so a band never fully disappears mid-aurora.
const AURORA_BREATH_FLOOR: float = 0.72

# 512 wide because the horizontal wave is the only thing in the image with structure, and 192
# tall because the vertical falloff is smooth -- three of these is 576 KiB in LA8, against the
# starfield's 1.1 MB. LA8 for the same reason the stars use it: the curtains are white and their
# colour comes from modulate.
const AURORA_TEXTURE_SIZE: Vector2i = Vector2i(512, 192)
# Fixed, so the aurora is the same shape every time it appears. NOT derived from session_seed --
# background code must never read it (visuals.md), and this is a set piece whose whole job is to
# be recognisable.
const AURORA_RNG_SEED: int = 20260907
# Where the bright lower hem sits in the texture, and how far it waves, as fractions of texture
# height. A curtain is defined by that hem: bright along the bottom edge, fading upward. Getting
# this backwards -- a soft blob centred in the band -- is what makes an aurora read as fog.
const AURORA_HEM_BASE: float = 0.84
const AURORA_HEM_WAVE: float = 0.15
# How far the glow reaches UP from the hem, and how quickly it stops BELOW it, both as fractions
# of texture height. Asymmetric on purpose and by a lot: that asymmetry IS the shape.
const AURORA_RISE: float = 0.58
const AURORA_HEM_SOFT: float = 0.06
# Exponent on the climb. Above 1 so the curtain is brightest at the hem and thins as it rises.
const AURORA_RISE_EXPONENT: float = 1.5
# Vertical striations. Real curtains are made of rays; without these the bands are flat ribbons.
#
# FOUR OCTAVES WITH FALLING AMPLITUDE, not N sines of similar frequency, and the difference is
# the whole reason the rays are visible at all. The first draft averaged three sines drawn from
# one 9-34 range: an average of similar frequencies converges on a constant, so the term sat
# near 0.81 across the whole width and produced NO striation. A product of them instead has the
# opposite failure -- the mean collapses toward the floor and the curtain goes muddy.
#
# What works is a weighted sum across separated frequency bands with amplitude falling as
# frequency rises: the low octave gives broad bright and dim regions, the high ones lay fine
# rays over them, and the mean stays put. Each entry is [min, max] Hz across the texture width;
# the ranges are separated rather than adjacent so two octaves cannot land on each other and
# beat into a regular comb.
const AURORA_RAY_BANDS: Array[Vector2] = [
	Vector2(3.0, 5.0),
	Vector2(9.0, 14.0),
	Vector2(23.0, 33.0),
	Vector2(51.0, 68.0),
]
const AURORA_RAY_AMPLITUDES: PackedFloat32Array = [0.42, 0.28, 0.19, 0.11]
# How much of a column's brightness survives in the darkest gap between rays.
const AURORA_RAY_FLOOR: float = 0.28

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
# The curtains, front to back. Built once in _ready() and then only ever recoloured and moved --
# nothing here is rebuilt per frame, unlike the sky gradient, which a transition rebakes.
var aurora_bands: Array[TextureRect] = []
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

	# SKIPPED ENTIRELY UNDER --headless, and this one is about COST, not about pixels.
	#
	# The bands are built visible = false and AuroraDirector hard-skips headless, so a gate could
	# never see them either way -- gate output is byte-identical with or without this guard. What
	# it saves is the bake: three 512x192 images is ~295,000 pixels of work, against the
	# starfield's 300, and every one of the six headless gates instantiates main.tscn. freeze_search
	# builds the scene repeatedly. Paying a third of a second per scene build for three textures
	# that are then never drawn is the kind of cost that turns a 25-second runner into a slow one.
	#
	# Locally computed from DisplayServer, never Services.is_headless, which is assigned in
	# GameServices._ready() and can still read false here (CLAUDE.md records this twice;
	# snow_drift.gd shipped exactly that bug). This is the ONLY headless branch in this file --
	# everything above and below it runs everywhere, which is what keeps the header's promise
	# that a gate sees the same sky it always saw.
	if DisplayServer.get_name() != "headless":
		build_aurora_bands()

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
	celestial_moon_texture = MOON_TEXTURE
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


# BETWEEN THE STARS AND THE GLOW, and that position is a decision rather than a convenience.
# Draw order is tree order, so this puts the curtains OVER the starfield -- an aurora occludes
# the stars behind it -- and UNDER both the horizon bloom and the disc. The moon reading as in
# front of a ribbon is the physically wrong one and the right-looking one: SkyCelestial is the
# only hard-edged body in this stack, and a soft additive band crossing it reads as a smear on
# the lens rather than as sky.
#
# Split out of _ready() only so the headless guard above is one line rather than a wrapped block.
# It must stay called from exactly where it is: the bands are added to the tree BETWEEN
# sky_stars and sky_glow, and moving the call moves the curtains in the draw order.
func build_aurora_bands() -> void:
	for band_index: int in range(AURORA_BAND_COUNT):
		var band: TextureRect = TextureRect.new()
		band.name = "SkyAurora%d" % band_index
		band.texture = build_aurora_texture(band_index)
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# SCALE, not KEEP_ASPECT_COVERED. The stars need covering because a stretched dot stops
		# being round; a curtain has no shape to preserve, and stretching it to the rect is
		# exactly what makes the band span whatever viewport it is handed.
		band.stretch_mode = TextureRect.STRETCH_SCALE
		# MANDATORY, not tidiness -- see the gradient's note. Control defaults to
		# MOUSE_FILTER_STOP and these rects are wider than the screen; left at the default they
		# are three stacked input eaters sitting under the pause button.
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Each band owns its parameters, sharing shader code and the existing baked art.
		# Additive light still needs the night gate; the shader adds folds and a spatial
		# arrival, not more brightness or another draw pass.
		var curtain_material: ShaderMaterial = ShaderMaterial.new()
		curtain_material.shader = AURORA_CURTAIN_SHADER
		curtain_material.set_shader_parameter("band_phase", float(band_index) * 2.1)
		band.material = curtain_material
		# Hidden until an aurora is actually running. Same rule as the glow's, and for the same
		# reason: a fully transparent full-screen TextureRect still rasterises every pixel it
		# covers, and three of them stacked is the fill-rate cost that matters on a mobile GPU.
		# At blend 0 this whole feature is byte-identical to not existing.
		band.visible = false
		add_child(band)
		aurora_bands.append(band)


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
	# terrain_generator.paint_snow_cap()'s `visible = snow_cap_strength > 0`.
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


# THE AURORA'S ONLY ENTRY POINT. Called by AuroraDirector every physics frame an aurora is
# running, and by nothing else. BiomeDirector must never call this -- the aurora is fixed and
# playtime-gated; the palette cycle is distance-driven, and the two meeting is the "just another
# biome" failure the fixed colours above exist to prevent.
#
# `blend` is the director's visibility envelope. The directional reveal and folds are
# deterministic functions of its elapsed clock, never a second independently advancing timer.
#
# WHY THE CLOCK IS PASSED IN RATHER THAN KEPT HERE, and it is the load-bearing reason this file
# still has no _process. Every one of the six headless gates instantiates main.tscn, so
# everything in this file runs on every gate frame; the header's claim that it is built once in
# _ready() and never touched again is what keeps that free. Advancing a timer here would spend
# it. AuroraDirector already holds active_elapsed, hard-skips headless, and stops on every menu
# with the rest of the tree -- so an aurora paused halfway through resumes halfway through, and
# a gate pays nothing.
#
# ALSO NOT TIME.get_ticks_msec() OR A SHADER'S TIME: both keep running while the tree is paused.
# That is the same trap frozen_lake_reflection.gdshader takes a wobble_time uniform to avoid, and
# the rule applies to a Phase 2b shader here too -- it reads these values as uniforms, it does
# not grow a clock.
func apply_aurora(blend: float, elapsed: float) -> void:
	if aurora_bands.is_empty():
		return

	var is_showing: bool = blend > 0.0
	for band_index: int in range(aurora_bands.size()):
		var band: TextureRect = aurora_bands[band_index]
		band.visible = is_showing
		if not is_showing:
			continue
		var curtain_material: ShaderMaterial = band.material as ShaderMaterial
		curtain_material.set_shader_parameter("event_elapsed", elapsed)
		curtain_material.set_shader_parameter("reveal_progress", clampf(
			(elapsed - float(band_index) * AURORA_REVEAL_STAGGER) / AURORA_REVEAL_SECONDS,
			0.0, 1.0))

		# The breath. Each band on its own period so they cannot pulse together -- see
		# AURORA_BREATH_PERIODS. Floored, so a curtain dims rather than vanishing.
		var breath: float = AURORA_BREATH_FLOOR + ((1.0 - AURORA_BREATH_FLOOR) \
				* (0.5 + (0.5 * sin(TAU * elapsed / AURORA_BREATH_PERIODS[band_index]))))

		var band_color: Color = AURORA_BAND_COLORS[band_index]
		band_color.a = AURORA_BAND_WEIGHTS[band_index] * breath * blend
		band.modulate = band_color

		# The drift, and the vertical bob that rides at half its rate so the two never line up
		# into one diagonal slide.
		var drift_phase: float = TAU * elapsed / AURORA_DRIFT_PERIODS[band_index]
		var drift: float = sin(drift_phase) * AURORA_DRIFT_SPAN
		var bob: float = cos(drift_phase * 0.5) * AURORA_BAND_BOB

		# Anchors, like position_glow() -- fractions of the parent rect, so this is correct on
		# any viewport with no resize signal to connect and nothing to recompute when the window
		# changes. That matters here for the same reason it does there: the pinned base
		# size still expands with aspect ratio, so the visible rect differs per device.
		#
		# The rect is wider than the screen by AURORA_OVERSCAN on each side, which is what lets
		# the texture be an ordinary image rather than a seamless one: a band can drift its full
		# span without ever walking an edge into view.
		band.anchor_left = -AURORA_OVERSCAN + drift
		band.anchor_right = 1.0 + AURORA_OVERSCAN + drift
		band.anchor_top = AURORA_BAND_TOPS[band_index] + bob
		band.anchor_bottom = AURORA_BAND_BOTTOMS[band_index] + bob
		# Anchors alone do not move a Control -- the offsets are pixel deltas from them and
		# retain whatever the last layout left behind. Zeroing them is what makes the rect
		# exactly the anchored box. Same note as position_glow()'s, same failure if omitted.
		band.offset_left = 0.0
		band.offset_right = 0.0
		band.offset_top = 0.0
		band.offset_bottom = 0.0


# One curtain, baked once. Same idiom as build_star_texture(): an LA8 Image walked in code, with
# the colour left to modulate so one bake serves every appearance and nothing is ever rebuilt.
#
# THE SHAPE IS THE POINT, and it is worth stating because the obvious implementation is wrong. A
# curtain is not a soft band centred on a line -- that reads as fog. It is a bright HEM with a
# long fade UPWARD from it and a quick stop below, and it is made of vertical rays. Three terms,
# in the order they matter:
#
#   1. hem(x)  -- a wandering lower edge, two sines at unrelated frequencies so it never repeats
#                 visibly across the width.
#   2. the asymmetric falloff around it -- AURORA_RISE up, AURORA_HEM_SOFT down. The ratio here
#                 is ~9:1, and that asymmetry is what the eye reads as "hanging".
#   3. rays(x) -- vertical striations, summed sines floored at AURORA_RAY_FLOOR. Without these
#                 the band is a flat ribbon; with them it has structure to catch the breath.
#
# band_index only seeds the RNG, so the three curtains are the same construction with different
# numbers rather than three hand-authored shapes -- which is what keeps adding a fourth free.
func build_aurora_texture(band_index: int) -> ImageTexture:
	# WRITTEN AS RAW BYTES, NOT set_pixel(), and this one is a measurement rather than a style
	# preference. build_star_texture() above sets 300 pixels and set_pixel() is fine for that;
	# this walks 98,304 per band and three bands is ~295,000. A bound set_pixel() call per pixel
	# at that count is a visible hitch on scene load on a phone -- and scene load is every
	# restart, not just launch. Filling a PackedByteArray and handing it to create_from_data()
	# does the same work with no per-pixel call into the engine.
	#
	# LA8 is two bytes per pixel, luminance then alpha. resize() ZERO-FILLS, so every pixel the
	# falloff skips is already transparent and costs nothing -- which is most of the image, since
	# a curtain only occupies the band around its hem.
	var width: int = AURORA_TEXTURE_SIZE.x
	var height: int = AURORA_TEXTURE_SIZE.y
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(width * height * 2)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# Offset rather than reseeded from scratch, so the three bands are deterministic against one
	# another as well as across runs.
	rng.seed = AURORA_RNG_SEED + band_index

	# The hem's two waves and the rays', drawn once and held: everything below is a pure function
	# of x and y given these, which is what makes the bake one pass with no allocation in it.
	var hem_frequency_a: float = rng.randf_range(1.2, 2.1)
	var hem_frequency_b: float = rng.randf_range(3.3, 5.2)
	var hem_phase_a: float = rng.randf_range(0.0, TAU)
	var hem_phase_b: float = rng.randf_range(0.0, TAU)
	# One frequency drawn per octave, inside that octave's own band -- see AURORA_RAY_BANDS for
	# why the bands are separated rather than one wide range.
	var ray_frequencies: PackedFloat32Array = PackedFloat32Array()
	var ray_phases: PackedFloat32Array = PackedFloat32Array()
	var ray_amplitude_total: float = 0.0
	for octave: int in range(AURORA_RAY_BANDS.size()):
		var band_range: Vector2 = AURORA_RAY_BANDS[octave]
		ray_frequencies.append(rng.randf_range(band_range.x, band_range.y))
		ray_phases.append(rng.randf_range(0.0, TAU))
		ray_amplitude_total += AURORA_RAY_AMPLITUDES[octave]

	var rise_pixels: float = AURORA_RISE * float(height)
	var hem_soft_pixels: float = AURORA_HEM_SOFT * float(height)

	for x: int in range(width):
		var across: float = float(x) / float(width - 1)

		# Where this column's bright edge sits. Two sines, so the wander has a long shape with a
		# shorter one riding on it rather than reading as a single sine wave.
		var hem: float = AURORA_HEM_BASE \
				+ (AURORA_HEM_WAVE * 0.62 * sin((across * TAU * hem_frequency_a) + hem_phase_a)) \
				+ (AURORA_HEM_WAVE * 0.38 * sin((across * TAU * hem_frequency_b) + hem_phase_b))
		var hem_pixels: float = hem * float(height)

		# The rays: the octaves summed at their own amplitudes, then normalised by the amplitude
		# total so the term lands in 0..1 whatever the weights are.
		var ray_sum: float = 0.0
		for octave: int in range(ray_frequencies.size()):
			ray_sum += AURORA_RAY_AMPLITUDES[octave] \
					* (0.5 + (0.5 * sin((across * TAU * ray_frequencies[octave]) + ray_phases[octave])))
		var rays: float = AURORA_RAY_FLOOR + ((1.0 - AURORA_RAY_FLOOR) * (ray_sum / ray_amplitude_total))

		# Only the rows the curtain actually reaches. Everything outside this span is already 0
		# from the resize, so clamping the loop is what makes the empty majority of the image
		# free rather than merely cheap.
		var first_row: int = maxi(int(floor(hem_pixels - rise_pixels)), 0)
		var last_row: int = mini(int(ceil(hem_pixels + hem_soft_pixels)), height - 1)

		for y: int in range(first_row, last_row + 1):
			# Positive above the hem, negative below it. Y grows downward.
			var above: float = hem_pixels - float(y)
			var falloff: float = 0.0
			if above >= 0.0:
				# The long climb. Exponent above 1 so the curtain is brightest at the hem and
				# thins as it rises, rather than being a uniform slab with soft ends.
				falloff = pow(clampf(1.0 - (above / rise_pixels), 0.0, 1.0), AURORA_RISE_EXPONENT)
			else:
				# The quick stop underneath. Squared, so the hem reads as an edge without being
				# a hard line that would alias on a soft image.
				falloff = pow(clampf(1.0 + (above / hem_soft_pixels), 0.0, 1.0), 2.0)
			# THE RAYS WASH OUT WITH HEIGHT, which is the last thing that stops this reading as a
			# printed pattern: lerp(1.0, rays, falloff) applies them at full depth along the hem,
			# where falloff is 1, and fades them to nothing at the top of the climb, where the
			# curtain should be a smooth glow. Real rays behave this way, and it costs one lerp.
			var alpha: int = int(falloff * (1.0 + ((rays - 1.0) * falloff)) * 255.0)
			if alpha <= 0:
				continue
			var offset: int = ((y * width) + x) * 2
			pixels[offset] = 255
			pixels[offset + 1] = alpha

	return ImageTexture.create_from_image(
			Image.create_from_data(width, height, false, Image.FORMAT_LA8, pixels))


# Places the bloom by ANCHOR rather than by position/size in pixels.
#
# Anchors are fractions of the parent rect, which is exactly what glow_position and
# glow_radius already are -- so the layout is correct on any viewport with no resize signal
# to connect, no get_viewport_rect() read, and nothing to recompute when the window changes.
# That matters more here than usual: project.godot pins a base viewport and stretches with
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
