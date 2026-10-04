extends ParallaxLayer

class_name BackgroundStrip

# One background layer drawn from a looping raster panorama instead of generated
# geometry. Sibling of background_generator.gd, not a replacement for it: main.tscn
# uses this for the FRONTMOST layer (the stitched ice panorama, depth_t 0.45) and that
# file for the three ranges behind it, and BiomeDirector recolours both the same way.
#
# WHY THIS IS NOT BackgroundGenerator WITH A TEXTURE
#
#   That file exists to make a skyline out of nothing -- three octaves, a per-layer
#   hash, segment spawning and recycling keyed on the player's x, and a haze band per
#   segment. A panorama needs none of it. The art already contains its skyline, its
#   internal depth and its own baked fog, so what is left is "put this texture on the
#   layer and repeat it", which ParallaxLayer.motion_mirroring does natively.
#
#   The practical consequence is that this script has NO _physics_process at all.
#   background_generator.gd's header warns that all headless gates instantiate
#   main.tscn, so its per-frame index arithmetic runs on every gate frame with no
#   opt-out; this layer costs those gates nothing, because after _ready() it does
#   nothing. Whatever is on screen is Godot repeating one Sprite2D.
#
# WHY THE TEXTURE CARRIES ALPHA, AND WHY IT MUST KEEP CARRYING IT
#
#   SkyBackdrop is CanvasLayer -200 and ParallaxBackground is -100, so the sun, the
#   moon, the stars and the planned aurora ALL draw BEHIND this layer. The source
#   painting is opaque RGB with a sky in it; shipped that way it covers every one of
#   them. docs/development/visuals.md, "There has to BE a sky", records this bug
#   having already happened once: the parallax layers covered the frame edge to edge
#   and all four sun discs measured 0/255 on screen.
#
#   scripts/tools/build_pano_strip.py keys that sky out. The ice stays opaque and
#   still occludes the sun; the fog comes through at PARTIAL alpha, so the sun shows
#   through the haze, which is what haze does. Never swap in an opaque texture here.
#
# WHY THERE IS NO HAZE NODE
#
#   background_generator.gd builds a haze band per segment because a flat silhouette
#   has no way to dissolve into the distance on its own. This texture's fog is
#   painted in and survives as partial alpha, so a haze band on top would fog it
#   twice. The near layers keep theirs -- each layer's haze veils only its own layer.
#
# THE ICE PLAIN BELOW THE WATERLINE (2026-10-03)
#
#   The panorama's reflections fade out a little below its waterline, and below them
#   there used to be only MidRidge's flat fill. Terrain normally covers that, but every
#   layer is screen-locked vertically, so a high double jump or glide lifts the camera,
#   drops the terrain toward the bottom edge and uncovers it: the owner's "white void".
#   So this layer also draws a plain, behind the strip, from the waterline down past
#   the bottom edge. It is transparent at the waterline, so frames in ordinary play stay
#   as they were and no edge can form against the fill behind it. It then ramps to a
#   palette colour, with faint perspective streaks that make it read as ground. It
#   needs no camera, physics or terrain change.
#
# LOAD-BEARING CONSTRAINTS
#
#   * motion_scale.y MUST stay 0, same as every other layer. Vertical parallax was
#     tried and reverted (dead_code.md); it is also what keeps this layer immune to
#     main.gd's world rebase.
#   * X is never world-rebased (world_rebaser.gd rebases Y only), so the scroll
#     offset this layer mirrors against grows without bound. That is fine here and
#     the arithmetic is worth writing down: at motion_scale 0.05 and MAX_SPEED 750,
#     an hour of play reaches ~135,000 layer-local px, nowhere near float32's exact
#     integer range. There is no counterpart to the terrain's rebase to add.
#   * Do NOT read TerrainGenerator.session_seed here. ParallaxBackground is
#     main.tscn's first child, so this _ready() runs before TerrainGenerator's and
#     the seed is still 0 -- the ordering trap architecture.md documents. Nothing in
#     this file is seeded, and it should stay that way: the panorama is a fixed loop.

# The texture is placed by naming where its SKYLINE and its WATERLINE should land on
# screen, rather than by a scale and an offset. Those two fractions are the things
# that actually matter compositionally -- how much sky is left above the ice, and
# where the ice meets the water that the terrain then covers -- and they hold their
# meaning when the viewport changes, which a pixel offset does not. Scale and
# position are derived from them.
@export var strip_texture: Texture2D
# Where the tallest ice tops out, as a fraction of viewport HEIGHT. visuals.md
# measured the composition constraint this answers to: the old FarPeaks topped out
# at y ~= 0.21 and anything above that starts eating the sky the celestial disc
# needs. Raising this number lowers the mountains.
@export_range(0.0, 1.0) var skyline_y_fraction: float = 0.26
# Where the panorama's waterline sits, same units. The reflections below it are
# drawn but mostly covered by terrain, which is the intent -- the waterline reads as
# the base of the ice rather than as the top of a lake.
@export_range(0.0, 1.0) var horizon_y_fraction: float = 0.50
# The two rows of strip_texture that the fractions above refer to. Properties of the
# ART, not of the game, which is why they live here as data rather than as constants:
# build_pano_strip.py measures and prints both, so re-baking or replacing the
# panorama is a rebuild plus two numbers, with no code change.
@export var source_skyline_y: float = 242.0
@export var source_horizon_y: float = 489.0
# Where this layer sits in the depth stack: 0 = furthest, 1 = nearest. Identical
# meaning to background_generator.gd's, and read by the same palette call, so the
# eight biome palettes need no entry for this layer.
@export_range(0.0, 1.0) var depth_t: float = 0.0
# Starting colour only. biome_director.gd overwrites it through apply_palette() on
# the first frame. It is still what shows under --headless, where the director
# returns early having applied nothing.
@export var silhouette_color: Color = Color(0.74, 0.81, 0.9)

# Aurora response weight, composed with silhouette_color. The response itself is shared with
# background_generator.gd, which owns its constants and the reasoning behind them.
var aurora_blend: float = 0.0

# How far down the plain runs, in the same viewport-height units as the fractions above. Those
# units are not quite screen units: ParallaxBackground draws every layer at the camera's zoom
# (measured: this layer's scale is 0.833 and its y is 0), so 1.0 lands ~83% of the way down the
# screen and the real bottom edge is 1/zoom = 1.2. The camera only ever zooms IN from there (the
# Aurora's ×1.055), so 1.5 leaves margin for any zoom down to 0.67.
const PLAIN_BOTTOM_FRACTION: float = 1.5
# Baked once. It is stretched to one panorama loop wide (~3.9× at the base viewport), which only
# lengthens the streaks, and to ~1:1 vertically. It wraps in x, so the loop has no seam.
const PLAIN_TEXTURE_SIZE: Vector2i = Vector2i(1024, 512)
const PLAIN_RNG_SEED: int = 20261003
# THE STREAKS ARE WHAT MAKES IT READ AS GROUND. A gradient alone was built first and the owner
# could not see it: a smooth empty field is still a void, whatever its colour. These are
# darker dashes, like distant pressure ridges and floes. In perspective they are thin, short,
# dense and faint at the waterline, and thicker, longer, sparser and stronger toward the viewer.
#
# The darkest a streak gets, as a multiplier off the plain colour.
const PLAIN_STREAK_DARKNESS: float = 0.2
# Depth (fraction of the texture height) where streaks reach full strength. In ordinary play only
# the top ~9% is uncovered, so they stay faint there.
const PLAIN_STREAK_FULL_DEPTH: float = 0.35
# Each row of streaks sits this many times deeper than the last: perspective spacing.
const PLAIN_ROW_GROWTH_MIN: float = 1.08
const PLAIN_ROW_GROWTH_MAX: float = 1.16

var strip_sprite: Sprite2D
# Null under --headless, which renders nothing and should not pay for the bake.
var plain_sprite: Sprite2D


func _ready() -> void:
	if strip_texture == null:
		push_error("BackgroundStrip requires a strip_texture.")
		return

	# Added BEFORE the strip, so it draws behind it and the panorama's floes and
	# reflections sit on top of it. Tree order is draw order. Locally computed from
	# DisplayServer, never Services.is_headless (see sky_backdrop.gd's aurora bands).
	if DisplayServer.get_name() != "headless":
		plain_sprite = Sprite2D.new()
		plain_sprite.name = "Plain"
		plain_sprite.texture = build_plain_texture()
		plain_sprite.centered = false
		# Starting colour only, from the palette defaults. The director overwrites it on
		# frame one, the same as silhouette_color.
		plain_sprite.modulate = get_plain_color(BiomePalette.new())
		add_child(plain_sprite)

	strip_sprite = Sprite2D.new()
	strip_sprite.name = "Strip"
	strip_sprite.texture = strip_texture
	# Top-left anchored, so the layer's contents start exactly at local x 0 and span
	# [0, width). motion_mirroring repeats that span, and a centred sprite would put
	# half of it at negative x and tear the loop.
	strip_sprite.centered = false
	# THE SILHOUETTE COLOUR LIVES HERE. The texture is stored near-greyscale in a
	# fixed bright band precisely so Godot's texture * modulate reproduces the
	# painted look under any biome tint -- see build_pano_strip.py. One property
	# write recolours the whole layer, however many copies motion_mirroring draws.
	strip_sprite.modulate = silhouette_color
	add_child(strip_sprite)

	apply_viewport_size()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


# Called by biome_director.gd only. Never called under --headless.
func apply_palette(palette: BiomePalette) -> void:
	silhouette_color = palette.get_scenery_color(depth_t)
	refresh_silhouette()
	if plain_sprite != null:
		plain_sprite.modulate = get_plain_color(palette)


# The nearest scenery the palette authors, veiled by the nearest haze it authors: what a ridge
# layer at depth_t 1.0 would show below its skyline. So the plain needs no palette field, and
# it follows every biome and crossfade. It also keeps chasms readable, because a void shows
# this plain behind it. In all eight biomes its luminance stays at least 0.19 above the
# deepest terrain fill (ice_depth × 0.38), and 0.12 above it at the darkest streak.
#
# It does not take the Aurora response. Under a full Aurora the ridge fill it replaces moves
# by 4/255 at most, because the darkening silhouette and the brightening haze cancel out.
# A plain that stays put therefore matches it.
static func get_plain_color(palette: BiomePalette) -> Color:
	var haze: Color = palette.get_haze_color(1.0)
	return palette.get_scenery_color(1.0).lerp(Color(haze.r, haze.g, haze.b), haze.a)


# Pushed by AuroraDirector.push_blend(), duck-typed like every other Aurora consumer. This is
# the FRONTMOST background layer -- the big ice shapes in the owner's screenshot -- so it is the
# one that most visibly failed to catch the light.
func apply_aurora(blend: float, elapsed: float) -> void:
	var target: float = BackgroundGenerator.get_aurora_scenery_weight(blend, elapsed, depth_t)
	if is_equal_approx(target, aurora_blend):
		return
	aurora_blend = target
	refresh_silhouette()


# THE ONE WRITER of strip_sprite.modulate, so the biome and the Aurora compose rather than
# clobber. silhouette_color stays the pure palette value; see background_generator.gd.
func refresh_silhouette() -> void:
	if strip_sprite == null:
		return
	strip_sprite.modulate = silhouette_color.lerp(
		BackgroundGenerator.get_aurora_scenery_color(depth_t), aurora_blend)


# Desktop window resize only -- handheld orientation is pinned to landscape.
func _on_viewport_size_changed() -> void:
	apply_viewport_size()


# Scale and vertical placement both derive from the two fractions. Re-read rather
# than assumed, because project.godot's aspect="expand" means the height genuinely
# varies per device.
func apply_viewport_size() -> void:
	if strip_sprite == null or strip_texture == null:
		return

	var viewport_height: float = get_viewport_rect().size.y
	var source_span: float = source_horizon_y - source_skyline_y
	if source_span <= 0.0:
		push_error("BackgroundStrip: source_horizon_y must be below source_skyline_y.")
		return

	# The scale that makes skyline-to-waterline in the texture cover
	# skyline-to-waterline on screen.
	var target_span: float = (horizon_y_fraction - skyline_y_fraction) * viewport_height
	var display_scale: float = target_span / source_span
	strip_sprite.scale = Vector2(display_scale, display_scale)
	# Then slide it so the waterline lands where it was asked to.
	strip_sprite.position = Vector2(
		0.0,
		(horizon_y_fraction * viewport_height) - (source_horizon_y * display_scale)
	)

	# The loop. In layer-local px, which is world px * motion_scale.x -- so the
	# distance this covers in the world is this number divided by motion_scale.x,
	# and THAT is how long the panorama runs before a player sees it again.
	var loop_width: float = strip_texture.get_width() * display_scale
	motion_mirroring = Vector2(loop_width, 0.0)

	# Exactly one loop wide, so mirroring tiles the plain along with the strip. Its
	# top is the strip's waterline.
	if plain_sprite == null:
		return
	var plain_top: float = horizon_y_fraction * viewport_height
	plain_sprite.position = Vector2(0.0, plain_top)
	plain_sprite.scale = Vector2(loop_width / PLAIN_TEXTURE_SIZE.x,
		(PLAIN_BOTTOM_FRACTION * viewport_height - plain_top) / PLAIN_TEXTURE_SIZE.y)


# Near-white, so modulate carries the colour and a biome push is one property write with no
# re-bake, the same as the strip. The base alpha ramps from 0 at the waterline to 1 at
# fraction 1.0 (~83% down the screen) and holds below that. Then the streaks go on top.
# Everything is in fractions, so the texture never depends on the viewport and is built once.
# Seeded with a constant, never session_seed (see the header): the plain is a fixed loop too.
func build_plain_texture() -> ImageTexture:
	var size: Vector2i = PLAIN_TEXTURE_SIZE
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var opaque_row: float = size.y * (1.0 - horizon_y_fraction) / (PLAIN_BOTTOM_FRACTION - horizon_y_fraction)
	for row: int in range(size.y):
		image.fill_rect(Rect2i(0, row, size.x, 1), Color(1.0, 1.0, 1.0, get_plain_alpha(row, opaque_row)))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = PLAIN_RNG_SEED
	# Depth is the fraction of the texture's height below the waterline. Shallower rows than
	# this would be under a texel apart and too faint to see anyway.
	var depth: float = 0.03
	while depth < 1.0:
		var row: int = int(depth * size.y)
		var thickness: int = 1 + roundi(depth * 20.0)
		var strength: float = smoothstep(0.0, PLAIN_STREAK_FULL_DEPTH, depth) * rng.randf_range(0.4, 1.0)
		# Dashes across one full width from a random start; about a third of the row is covered.
		var x: float = rng.randf() * size.x
		var end_x: float = x + size.x
		while x < end_x:
			var length: float = size.x * (0.01 + 0.12 * depth) * rng.randf_range(0.5, 1.5)
			draw_plain_streak(image, x, length, row, thickness, strength, opaque_row)
			x += length * rng.randf_range(2.0, 5.0)
		depth *= rng.randf_range(PLAIN_ROW_GROWTH_MIN, PLAIN_ROW_GROWTH_MAX)
	return ImageTexture.create_from_image(image)


# One soft streak: a sine bump across its thickness and along its length, so it has no hard
# edge or end and reads as a smear of shadow on the ice rather than a ruled line. Drawn as
# stepped fill_rects (a few px each once stretched), because per-pixel writes cost far more.
# Wrapped at the right edge, so the loop has no seam. Its alpha is never below the base ramp's,
# so a streak near the waterline shows faintly over the fill behind it.
func draw_plain_streak(image: Image, start_x: float, length: float, row: int, thickness: int,
		strength: float, opaque_row: float) -> void:
	var width: int = image.get_width()
	var steps: int = clampi(int(length / 6.0), 3, 16)
	var step_length: float = length / steps
	for offset: int in range(thickness):
		var y: int = row + offset
		if y >= image.get_height():
			return
		var across: float = sin(PI * (offset + 0.5) / thickness)
		for step: int in range(steps):
			var weight: float = strength * across * sin(PI * (step + 0.5) / steps)
			var shade: float = 1.0 - PLAIN_STREAK_DARKNESS * weight
			var color: Color = Color(shade, shade, shade, maxf(get_plain_alpha(y, opaque_row), weight))
			var left: int = posmod(int(start_x + step * step_length), width)
			var span: int = maxi(int(step_length + 1.0), 1)
			image.fill_rect(Rect2i(left, y, mini(span, width - left), 1), color)
			if left + span > width:
				image.fill_rect(Rect2i(0, y, left + span - width, 1), color)


static func get_plain_alpha(row: int, opaque_row: float) -> float:
	return clampf(float(row) / maxf(opaque_row, 1.0), 0.0, 1.0)
