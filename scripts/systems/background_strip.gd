extends ParallaxLayer

class_name BackgroundStrip

# One background layer drawn from a looping raster panorama instead of generated
# geometry. Sibling of background_generator.gd, not a replacement for it: main.tscn
# uses this for the far layer (the stitched ice panorama) and that file for the near
# ones, and BiomeDirector recolours both the same way.
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
# LOAD-BEARING CONSTRAINTS
#
#   * motion_scale.y MUST stay 0, same as every other layer. Vertical parallax was
#     tried and reverted (dead_code.md); it is also what keeps this layer immune to
#     main.gd's world rebase.
#   * X is never world-rebased (world_rebaser.gd rebases Y only), so the scroll
#     offset this layer mirrors against grows without bound. That is fine here and
#     the arithmetic is worth writing down: at motion_scale 0.03 and MAX_SPEED 750,
#     an hour of play reaches ~81,000 layer-local px, nowhere near float32's exact
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

var strip_sprite: Sprite2D


func _ready() -> void:
	if strip_texture == null:
		push_error("BackgroundStrip requires a strip_texture.")
		return

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
	if strip_sprite != null:
		strip_sprite.modulate = silhouette_color


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
	motion_mirroring = Vector2(strip_texture.get_width() * display_scale, 0.0)
