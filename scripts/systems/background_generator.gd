extends ParallaxLayer

class_name BackgroundGenerator

# One layer of background scenery: a recycled strip of silhouette, plus the haze that
# veils it. main.tscn attaches this same script to three ParallaxLayers (FarRidge,
# MidRidge, PineLine) which differ only by their @export values -- the recycling logic
# exists once, and a new layer is a scene edit rather than a new script.
#
# HOW DEPTH IS PRODUCED, since it is not obvious from any single value:
#
#   * Colour. Distant ridges sit closer to the sky colour and near ones further from it
#     (atmospheric perspective). Under a PALE sky that means far = lighter, so FarRidge is
#     the lightest scenery and PineLine the darkest.
#   * Parallax rate. Far layers scroll slower. PineLine keeps the 0.3 that was already
#     shipped and proven; the two ridge layers are slower still, so this change only ever
#     moves background pixels *less* per frame than before, never more.
#   * Haze. Each layer owns two child containers, built once in _ready(): "Ridges" then
#     "Haze". Because Haze is added second it draws over every silhouette in ITS OWN
#     layer and only that layer -- so layer N's haze veils layer N, and layer N+1's
#     silhouette then draws crisply on top of it. That recession comes out of tree order
#     alone: no z_index (the project has none anywhere), no extra ParallaxLayers, and no
#     draw-order ambiguity at segment seams.
#
# LOAD-BEARING CONSTRAINTS -- each of these is a bug someone already paid for:
#
#   * motion_scale.y MUST stay 0 on every layer using this script. Vertical parallax was
#     tried and reverted: it snapped the background on every world rebase (~26s) and lost
#     its coverage after a few mega drops. docs/development/dead_code.md, "Vertical
#     parallax -- tried, reverted". Screen-locked vertically is also what makes this file
#     immune to main.gd's rebase, which shifts Y on TerrainGenerator/Player/Camera2D only.
#   * NEVER read TerrainGenerator.session_seed here. ParallaxBackground is main.tscn's
#     FIRST child, so this _ready() runs before TerrainGenerator's and session_seed is
#     still 0 at that point -- the exact ordering trap architecture.md documents, which
#     shipped once as an identical powerup schedule every session. Silhouettes are keyed
#     on rng_salt, a per-layer constant, instead. The background needs no session
#     variety: it is a function of world x, and an endless runner never revisits an x.
#   * All six headless gates instantiate scenes/main.tscn, so everything in this file
#     runs on every gate frame with no opt-out flag. Keep _physics_process to the index
#     arithmetic it already was; do no per-frame node work.

const SHAPE_RIDGE: int = 0
const SHAPE_PINES: int = 1

@export var player_path: NodePath
@export_enum("Ridge:0", "Pines:1") var shape_kind: int = SHAPE_RIDGE
@export var segment_width: float = 1024.0
@export var segment_count_ahead: int = 2
@export var segment_count_behind: int = 1
# Where this layer's skyline sits, as a fraction of viewport HEIGHT rather than a pixel
# count: project.godot pins no viewport size and stretches with aspect="expand", so the
# window height is genuinely unknown at author time. Read at _ready and again on resize.
@export var base_y_fraction: float = 0.52
# Where this layer sits in the depth stack: 0 = the furthest layer, 1 = the nearest. The
# biome palette stores only a far and a near colour and every layer lerps between them by
# this value, so adding a fifth parallax layer needs no edit to any of the eight palettes,
# and no palette can accidentally invert the far/near ordering that produces the depth
# read. Set per-instance in main.tscn alongside motion_scale.
@export_range(0.0, 1.0) var depth_t: float = 0.5
# Starting colours only. biome_director.gd overwrites both through apply_palette() on the
# first frame of a run. They are still what shows under --headless (where the director
# returns early having applied nothing, so the gates see the pre-biome background exactly)
# and if the director ever fails to resolve this layer.
@export var silhouette_color: Color = Color(0.62, 0.72, 0.83)
@export var ridge_height_min: float = 40.0
@export var ridge_height_max: float = 150.0
# Multiplies the three wave periods below. Larger = broader, lazier landforms, which is
# what distance looks like.
@export var ridge_period_scale: float = 1.0
@export var haze_color: Color = Color(0.88, 0.92, 0.96, 0.5)
# How far ABOVE base_y the haze starts fading in from fully transparent.
@export var haze_rise: float = 130.0
# Per-layer hash salt. Any two layers sharing a salt would generate the same skyline.
@export var rng_salt: int = 0
# Ignored unless shape_kind is Pines.
@export var pine_spacing: float = 52.0
@export var pine_height_min: float = 26.0
@export var pine_height_max: float = 52.0

var player: CharacterBody2D
var next_segment_index: int = 0
var active_segments: Dictionary[int, Node2D] = {}
var active_haze: Dictionary[int, Control] = {}
var ridges_root: Node2D
var haze_root: Node2D
# Built once and shared by every haze band in this layer.
var haze_texture: GradientTexture2D
var wave_phases: PackedFloat64Array = PackedFloat64Array()
var base_y: float = 0.0
var fill_bottom_y: float = 0.0

# Three octaves. Amplitudes sum to 1.0 so the combined wave lands in [-1, 1] exactly and
# the normalisation below needs no magic scaling.
#
# WAVELENGTHS, in pixels -- i.e. the on-screen distance between two peaks, NOT a sin()
# divisor. get_ridge_height converts with TAU. Written this way because the first cut of
# this file fed them straight to sin(x / period), making the real wavelengths 2*PI larger
# (~16000px for the first octave) and every skyline a straight diagonal line. These are
# comparable to the ~1150px screen width on purpose: an octave much longer than the
# viewport cannot read as a mountain, only as a slope.
const RIDGE_WAVE_WAVELENGTHS: Array[float] = [1500.0, 660.0, 280.0]
const RIDGE_WAVE_AMPLITUDES: Array[float] = [0.55, 0.30, 0.15]
# >1 pushes the distribution toward the low end: broad calm valleys with occasional
# distinct peaks, rather than an evenly bumpy horizon. Negative space is most of the
# reference's composition and all of its calm.
const RIDGE_PEAK_SHARPNESS: float = 1.5
# Vertices per segment across the skyline. 64 over 1024px is 16px per step -- roughly 17
# samples across the shortest octave above, which is what keeps peaks rounded rather than
# faceted. These are static nodes built once per segment, so the cost is one-off.
const RIDGE_SAMPLE_COUNT: int = 64
# How far past the bottom of the screen the silhouette fill extends. Only needs to
# survive the camera's vertical excursion, since terrain draws in front and covers the
# rest; generous because that excursion is unbounded during a glide.
const FILL_DEPTH_MARGIN: float = 900.0
const HAZE_TEXTURE_HEIGHT: int = 128
# Integer mix, same shape as TerrainGenerator.get_segment_hash -- but salted per layer
# and never touching session_seed. See the ordering note in the header comment.
const HASH_MASK: int = 0x7fffffff
const HASH_INDEX_MULTIPLIER: int = 374761393
const HASH_MIX_MULTIPLIER: int = 668265263
const HASH_UNIT_RESOLUTION: int = 100000


func _ready() -> void:
	player = resolve_player()
	if player == null:
		push_error("BackgroundGenerator requires a valid Player node.")
		set_physics_process(false)
		return

	ridges_root = Node2D.new()
	ridges_root.name = "Ridges"
	# THE SILHOUETTE COLOUR LIVES HERE, not on the polygons -- see build_ridge_polygon.
	ridges_root.modulate = silhouette_color
	add_child(ridges_root)
	haze_root = Node2D.new()
	haze_root.name = "Haze"
	add_child(haze_root)

	build_wave_phases()
	# apply_viewport_size() FIRST: build_haze_texture() places its opacity stop using
	# base_y and fill_bottom_y, which are 0 until that call.
	apply_viewport_size()
	haze_texture = build_haze_texture()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	initialize_segments()


# Called by biome_director.gd only. Never called under --headless.
#
# Two property writes for the entire layer, however many segments are live: the silhouette
# rides ridges_root.modulate, and every haze band in this layer shares ONE GradientTexture2D
# (build_haze_band hands out the same `haze_texture` to all of them), so recolouring that
# single gradient recolours every band at once -- including bands spawned later.
func apply_palette(palette: BiomePalette) -> void:
	silhouette_color = palette.get_scenery_color(depth_t)
	haze_color = palette.get_haze_color(depth_t)

	if ridges_root != null:
		ridges_root.modulate = silhouette_color
	if haze_texture != null and haze_texture.gradient != null:
		# Offsets are untouched: where the band reaches full opacity is a function of
		# haze_rise and the viewport, not of the biome. Only the colours move.
		haze_texture.gradient.colors = PackedColorArray([
			Color(haze_color.r, haze_color.g, haze_color.b, 0.0),
			haze_color,
			haze_color,
		])


func resolve_player() -> CharacterBody2D:
	var resolved_player: CharacterBody2D = null

	if player_path != NodePath():
		resolved_player = get_node_or_null(player_path) as CharacterBody2D

	if resolved_player == null:
		resolved_player = get_node_or_null("/root/Main/Player") as CharacterBody2D

	return resolved_player


func _physics_process(_delta: float) -> void:
	if player == null:
		return

	var background_x: float = player.global_position.x * motion_scale.x
	var player_segment_index: int = int(floor(background_x / segment_width))
	var target_segment_index: int = player_segment_index + segment_count_ahead
	var despawn_segment_index: int = player_segment_index - segment_count_behind

	while next_segment_index <= target_segment_index:
		spawn_segment(next_segment_index)
		next_segment_index += 1

	var segment_indices: Array[int] = active_segments.keys()
	for segment_index: int in segment_indices:
		if segment_index < despawn_segment_index:
			remove_segment(segment_index)


func initialize_segments() -> void:
	var background_x: float = player.global_position.x * motion_scale.x
	var player_segment_index: int = int(floor(background_x / segment_width))
	next_segment_index = player_segment_index - segment_count_behind
	for segment_index: int in range(player_segment_index - segment_count_behind, player_segment_index + segment_count_ahead + 1):
		spawn_segment(segment_index)
	next_segment_index = player_segment_index + segment_count_ahead + 1


# base_y and the fill depth are the only window-dependent values here. Re-read rather
# than assumed, because "expand" aspect means the height varies per device.
func apply_viewport_size() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	base_y = viewport_size.y * base_y_fraction
	fill_bottom_y = viewport_size.y + FILL_DEPTH_MARGIN


# Desktop window resize only -- handheld orientation is pinned to landscape. Rebuilding
# outright is correct rather than lazy: every segment's geometry is a function of base_y,
# and a resize is rare enough that the node churn is irrelevant.
func _on_viewport_size_changed() -> void:
	if player == null:
		return
	apply_viewport_size()
	# The haze gradient's opacity stop is derived from the new base_y too, so it is
	# rebuilt alongside the segments rather than left stale.
	haze_texture = build_haze_texture()
	var segment_indices: Array[int] = active_segments.keys()
	for segment_index: int in segment_indices:
		remove_segment(segment_index)
	initialize_segments()


func spawn_segment(segment_index: int) -> void:
	if active_segments.has(segment_index):
		return

	var segment_origin_x: float = float(segment_index) * segment_width

	var segment: Node2D = Node2D.new()
	segment.name = "Segment%d" % segment_index
	segment.position = Vector2(segment_origin_x, 0.0)
	segment.add_child(build_ridge_polygon(segment_origin_x))
	if shape_kind == SHAPE_PINES:
		build_pines(segment, segment_origin_x)
	ridges_root.add_child(segment)
	active_segments[segment_index] = segment

	var haze: Control = build_haze_band()
	haze.position = Vector2(segment_origin_x, base_y - haze_rise)
	haze_root.add_child(haze)
	active_haze[segment_index] = haze


func remove_segment(segment_index: int) -> void:
	if not active_segments.has(segment_index):
		return

	var segment: Node2D = active_segments[segment_index]
	active_segments.erase(segment_index)
	segment.free()

	if active_haze.has(segment_index):
		var haze: Control = active_haze[segment_index]
		active_haze.erase(segment_index)
		haze.free()


# The skyline, as one closed Polygon2D: the sampled ridge across the top, then straight
# down and back to close it off below the screen.
func build_ridge_polygon(segment_origin_x: float) -> Polygon2D:
	var points: PackedVector2Array = PackedVector2Array()
	var step: float = segment_width / float(RIDGE_SAMPLE_COUNT)
	# <=, so the last vertex lands exactly on the segment's right edge. That vertex and
	# the next segment's first are the same x fed to the same pure function, so the two
	# polygons meet at an identical y and the seam is invisible by construction.
	for sample_index: int in range(RIDGE_SAMPLE_COUNT + 1):
		var local_x: float = float(sample_index) * step
		points.append(Vector2(local_x, base_y - get_ridge_height(segment_origin_x + local_x)))
	points.append(Vector2(segment_width, fill_bottom_y))
	points.append(Vector2(0.0, fill_bottom_y))

	var ridge: Polygon2D = Polygon2D.new()
	ridge.name = "Ridge"
	ridge.polygon = points
	# WHITE, deliberately: ridges_root.modulate carries the actual silhouette colour and
	# multiplies down through every segment and pine under it. That is what lets a biome
	# transition recolour this whole layer with one property write per frame, including
	# segments that have not spawned yet -- instead of walking every polygon in the layer.
	ridge.color = Color.WHITE
	return ridge


# Pure in (rng_salt, x). Continuity across segment boundaries is a property of the
# function, not of any bookkeeping -- the same discipline that keeps
# TerrainGenerator.get_terrain_height pure in (session_seed, world_x).
func get_ridge_height(x: float) -> float:
	var wave: float = 0.0
	for wave_index: int in range(RIDGE_WAVE_WAVELENGTHS.size()):
		var wavelength: float = RIDGE_WAVE_WAVELENGTHS[wave_index] * ridge_period_scale
		wave += sin((TAU * x / wavelength) + wave_phases[wave_index]) * RIDGE_WAVE_AMPLITUDES[wave_index]

	var normalized: float = clampf((wave * 0.5) + 0.5, 0.0, 1.0)
	return ridge_height_min + (pow(normalized, RIDGE_PEAK_SHARPNESS) * (ridge_height_max - ridge_height_min))


func build_wave_phases() -> void:
	wave_phases = PackedFloat64Array()
	for wave_index: int in range(RIDGE_WAVE_WAVELENGTHS.size()):
		wave_phases.append(get_hash_unit_float(wave_index) * TAU)


# Trees are placed on a global grid so a tree's identity is its absolute index, not its
# position within a segment -- that is what keeps a tree at the same x with the same
# height no matter which segment happens to contain it.
func build_pines(segment: Node2D, segment_origin_x: float) -> void:
	var first_tree_index: int = int(floor(segment_origin_x / pine_spacing))
	var last_tree_index: int = int(floor((segment_origin_x + segment_width) / pine_spacing))
	for tree_index: int in range(first_tree_index, last_tree_index + 1):
		# Jitter keeps the grid from reading as a grid. Bounded to under half the
		# spacing, so trees cannot reorder or stack.
		var jitter: float = (get_hash_unit_float(tree_index * 3) - 0.5) * pine_spacing * 0.7
		var tree_x: float = (float(tree_index) * pine_spacing) + jitter
		if tree_x < segment_origin_x or tree_x >= segment_origin_x + segment_width:
			continue

		var tree_height: float = pine_height_min + (get_hash_unit_float((tree_index * 3) + 1) * (pine_height_max - pine_height_min))
		var pine: Polygon2D = Polygon2D.new()
		pine.name = "Pine%d" % tree_index
		# Rooted ON the ridge line, so the tree line reads as growing out of the hill
		# rather than floating in front of it.
		pine.position = Vector2(tree_x - segment_origin_x, base_y - get_ridge_height(tree_x))
		pine.polygon = build_pine_polygon(tree_height)
		# White for the same reason as the ridge: ridges_root.modulate tints it.
		pine.color = Color.WHITE
		segment.add_child(pine)


# A two-tier conifer, drawn from the apex clockwise. Deliberately simple: at this scale
# the silhouette is what carries, and detail would only add noise behind the play area.
func build_pine_polygon(tree_height: float) -> PackedVector2Array:
	var half_width: float = tree_height * 0.21
	return PackedVector2Array([
		Vector2(0.0, -tree_height),
		Vector2(half_width * 0.56, -tree_height * 0.52),
		Vector2(half_width * 0.32, -tree_height * 0.52),
		Vector2(half_width, 0.0),
		Vector2(-half_width, 0.0),
		Vector2(-half_width * 0.32, -tree_height * 0.52),
		Vector2(-half_width * 0.56, -tree_height * 0.52),
	])


# Transparent at the top, full haze by the time it reaches the skyline, and holding that
# value all the way down -- so the band has no bottom edge to notice. The silhouette
# dissolving into fog at its base is the single strongest depth cue in the reference.
func build_haze_band() -> Control:
	var haze: TextureRect = TextureRect.new()
	haze.name = "HazeBand"
	haze.texture = haze_texture
	haze.size = Vector2(segment_width, (fill_bottom_y - base_y) + haze_rise)
	haze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	haze.stretch_mode = TextureRect.STRETCH_SCALE
	# Control defaults to MOUSE_FILTER_STOP, and these tile across the whole screen.
	# Without this they are input eaters sitting under the pause button.
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return haze


func build_haze_texture() -> GradientTexture2D:
	var transparent_haze: Color = Color(haze_color.r, haze_color.g, haze_color.b, 0.0)
	# Where the band reaches full opacity: exactly at base_y, i.e. after haze_rise of the
	# band's total height.
	var full_haze_offset: float = clampf(haze_rise / maxf((fill_bottom_y - base_y) + haze_rise, 1.0), 0.02, 0.98)

	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, full_haze_offset, 1.0])
	gradient.colors = PackedColorArray([transparent_haze, haze_color, haze_color])

	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1
	texture.height = HAZE_TEXTURE_HEIGHT
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture


func get_hash_unit_float(index: int) -> float:
	return float(get_layer_hash(index) % HASH_UNIT_RESOLUTION) / float(HASH_UNIT_RESOLUTION)


func get_layer_hash(index: int) -> int:
	var mixed_value: int = (rng_salt ^ ((index + 1) * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return mixed_value
