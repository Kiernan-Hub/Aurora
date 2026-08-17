extends ParallaxLayer

class_name BackgroundGenerator

# One layer of background scenery: a recycled strip of silhouette, plus the haze that
# veils it. main.tscn attaches this same script to four ParallaxLayers (FarPeaks, FarRidge,
# MidRidge, ShardLine) which differ only by their @export values -- the recycling logic
# exists once, and a new layer is a scene edit rather than a new script.
#
# HOW DEPTH IS PRODUCED, since it is not obvious from any single value:
#
#   * Colour. Distant ridges sit closer to the sky colour and near ones further from it
#     (atmospheric perspective). Under a PALE sky that means far = lighter, so FarRidge is
#     the lightest scenery and the near layers the darkest.
#
#     ShardLine IS A DELIBERATE EXCEPTION and its depth_t is 0.32, not 1.0. Its ice masses
#     are meant to read as pale ice, and at depth_t 1.0 they took the near palette colour
#     (~0.45 red), which no vertex colour can lighten -- vertex_colors only ever multiply
#     DOWN. They came out reading as grey rock. The reference look carries distance by
#     CONTRAST rather than by darkness: near ice is about as light as far ice, just
#     crisper. Don't "fix" this back to 1.0 without also solving why the masses go muddy.
#   * Parallax rate. Far layers scroll slower. ShardLine keeps the 0.3 that was already
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
const SHAPE_SHARDS: int = 1

@export var player_path: NodePath
@export_enum("Ridge:0", "Shards:1") var shape_kind: int = SHAPE_RIDGE
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
# Ignored unless shape_kind is Shards.
@export var shard_spacing: float = 52.0
@export var shard_height_min: float = 26.0
@export var shard_height_max: float = 52.0

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
# --- Ice masses (shape_kind = Shards) ------------------------------------------------------
# Width as a multiple of height. Above 1.0 a mass is wider than it is tall, and once that
# width exceeds shard_spacing neighbouring masses OVERLAP -- which is the point. The
# reference look is a continuous drift of ice running off both edges of the screen, not a
# row of separate mountains, and overlap is what turns one into the other. At the shipped
# 52px spacing and 26-58px heights this is already true for every mass above ~33px.
const MASS_WIDTH_RATIO: float = 1.6
# Vertices along one mass's skyline; MASS_TOP_POINTS - 1 is therefore the facet count. Six
# points = five facets per form, each a large fraction of the width. Raising this is how
# the background goes back to reading as noise -- generated art that came in at ~5px facets
# is exactly what this number exists to prevent.
const MASS_TOP_POINTS: int = 6
# Floor for a skyline vertex as a fraction of the mass height, before the taper. Keeps a
# mass from collapsing to a flat lump when every hash draw lands low.
const MASS_MIN_PEAK: float = 0.34
# Hash slots consumed per mass: jitter, height, skew and width, then one per skyline
# vertex. Must stay >= MASS_HASH_SLOT_SKYLINE + MASS_TOP_POINTS. Everything about a mass
# is drawn from this one
# block, so no two properties can share a draw and correlate -- if the stride were smaller
# than the block a mass consumes, mass N's skyline would collide with mass N+k's jitter and
# the field would develop a visible repeat.
const MASS_HASH_STRIDE: int = 10
const MASS_HASH_SLOT_JITTER: int = 0
const MASS_HASH_SLOT_HEIGHT: int = 1
const MASS_HASH_SLOT_SKEW: int = 2
const MASS_HASH_SLOT_WIDTH: int = 3
const MASS_HASH_SLOT_SKYLINE: int = 4
# Where a mass's summit sits across its own width, as a fraction. Kept off both 0 and 1 so
# the taper below never divides by zero. The FIRST cut of this had no skew at all -- every
# summit landed at 0.5 and the field rendered as a row of identical symmetrical tents,
# because a centred taper re-imposes the symmetry the per-vertex skyline hash removes.
const MASS_SKEW_MIN: float = 0.22
const MASS_SKEW_MAX: float = 0.78
# Width variance, multiplying MASS_WIDTH_RATIO. Width is deliberately NOT a pure function
# of height: when it was, a tall mass was just a scaled-up short one and the whole field
# read as one shape at several sizes. Independent variance is what makes a squat wide berg
# and a tall narrow spire come out of the same generator.
const MASS_WIDTH_VARIANCE_MIN: float = 0.62
const MASS_WIDTH_VARIANCE_MAX: float = 1.55
# Shoulder fullness. 1.0 is a straight taper to the feet, which reads as a cone; below 1.0
# the flanks bulge and the form reads as a solid mass of ice instead.
const MASS_SHOULDER_FULLNESS: float = 0.62
# How far below its root point a mass's base edge is buried, so the flat bottom never shows
# against the layer fill it sits on.
const MASS_ROOT_SINK: float = 4.0
# The high-key value set. NOTHING here may go below MASS_VALUE_FLOOR -- the full reasoning
# is in build_ice_mass, but briefly: these are multiplied by the palette colour and then by
# the haze band, so a value that looks merely "mid grey" here arrives near black on screen
# and the ice reads as rock. Measured against the reference, which bottoms out around 0.75.
const MASS_VALUE_FLOOR: float = 0.80
const MASS_SILHOUETTE_VALUE: float = 0.92
const MASS_FACET_VALUES: Array[float] = [1.0, 0.90, 0.96, 0.86, 0.93]
# How much darker a facet's base vertex is than its two top vertices.
const MASS_FACET_FALLOFF: float = 0.06
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
	if shape_kind == SHAPE_SHARDS:
		build_shards(segment, segment_origin_x)
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


# Shards are placed on a global grid so a shard's identity is its absolute index, not its
# position within a segment -- that is what keeps a shard at the same x with the same
# height no matter which segment happens to contain it.
#
# MASS_HASH_STRIDE slots per mass -- see the constant for the slot map and why one stride
# has to cover every property a mass draws.
func build_shards(segment: Node2D, segment_origin_x: float) -> void:
	var first_shard_index: int = int(floor(segment_origin_x / shard_spacing))
	var last_shard_index: int = int(floor((segment_origin_x + segment_width) / shard_spacing))
	for shard_index: int in range(first_shard_index, last_shard_index + 1):
		# Jitter keeps the grid from reading as a grid. Bounded to under half the spacing,
		# so masses cannot reorder -- they overlap by width (MASS_WIDTH_RATIO), which is
		# controlled, rather than by wandering off their own slot, which would not be.
		var hash_base: int = shard_index * MASS_HASH_STRIDE
		var jitter: float = (get_hash_unit_float(hash_base + MASS_HASH_SLOT_JITTER) - 0.5) * shard_spacing * 0.7
		var shard_x: float = (float(shard_index) * shard_spacing) + jitter
		if shard_x < segment_origin_x or shard_x >= segment_origin_x + segment_width:
			continue

		var shard_height: float = shard_height_min + (get_hash_unit_float(hash_base + MASS_HASH_SLOT_HEIGHT) * (shard_height_max - shard_height_min))
		var mass: Node2D = build_ice_mass(shard_height, shard_index)
		mass.name = "Shard%d" % shard_index
		# Rooted ON the ridge line, so the mass reads as broken ice pushing out of the hill
		# rather than floating in front of it. Sunk by MASS_ROOT_SINK so the flat base edge
		# is buried under the layer's own fill and can never show a seam against it -- the
		# "the ice doesn't even touch" read that the first shard cut produced.
		mass.position = Vector2(shard_x - segment_origin_x, base_y - get_ridge_height(shard_x) + MASS_ROOT_SINK)
		segment.add_child(mass)


# ONE ice mass: an opaque silhouette with large flat facets laid over it.
#
# WHY THIS IS BUILT FROM POLYGONS AND NOT A SPRITE. Two rounds of generated ice art failed
# on exactly the four things this function fixes with a constant apiece -- the value range
# crept dark and read as grey rock, facets came out ~5px and mushed into noise, silhouettes
# came out symmetrical, and every form was an isolated object rather than part of a mass.
# Facet count, value range and silhouette are parameters here, and the overlap falls out of
# the scatter spacing for free. See the handoff notes for the two rejected art rounds.
#
# THE FACETS MUST STAY OPAQUE. The sun and moon live on SkyBackdrop at layer -200, behind
# ParallaxBackground's -100, and they hide behind this layer purely because these polygons
# are solid. Give a facet alpha and the sun shines through the mountain.
#
# Values are deliberately HIGH-KEY -- nothing below MASS_VALUE_FLOOR. Distant ice is nearly
# flat in value; strong form shadows read as stone. These are also multiplied twice more
# before they reach the screen (by ridges_root.modulate, then by the haze band over them),
# and the near layer's palette colour is around 0.45 red, so a facet drawn at 0.45 here
# lands near 0.2 on screen. Darkening this is how the background stops looking like ice.
func build_ice_mass(mass_height: float, mass_index: int) -> Node2D:
	var mass: Node2D = Node2D.new()
	var hash_base: int = mass_index * MASS_HASH_STRIDE
	var width_variance: float = lerpf(MASS_WIDTH_VARIANCE_MIN, MASS_WIDTH_VARIANCE_MAX, get_hash_unit_float(hash_base + MASS_HASH_SLOT_WIDTH))
	var half_width: float = mass_height * MASS_WIDTH_RATIO * width_variance * 0.5
	var skew: float = lerpf(MASS_SKEW_MIN, MASS_SKEW_MAX, get_hash_unit_float(hash_base + MASS_HASH_SLOT_SKEW))

	# The skyline of this one mass: MASS_TOP_POINTS vertices, each height hashed
	# independently so the outline is irregular rather than a tidy pyramid. The taper still
	# pulls both ends to zero -- that is what lets neighbouring masses interlock at their
	# feet rather than butt together as separate objects -- but it now peaks at `skew`
	# instead of at the centre, so the two flanks are different lengths and no two masses
	# share a profile.
	var top: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(MASS_TOP_POINTS):
		var across: float = float(point_index) / float(MASS_TOP_POINTS - 1)
		# Distance from the near foot toward the summit, normalised per flank: 0 at
		# whichever foot this vertex is closer to, 1 at the summit.
		var toward_summit: float = across / skew if across < skew else (1.0 - across) / (1.0 - skew)
		var taper: float = pow(sin(clampf(toward_summit, 0.0, 1.0) * PI * 0.5), MASS_SHOULDER_FULLNESS)
		var height_unit: float = get_hash_unit_float(hash_base + MASS_HASH_SLOT_SKYLINE + point_index)
		var point_height: float = mass_height * lerpf(MASS_MIN_PEAK, 1.0, height_unit) * taper
		top.append(Vector2(lerpf(-half_width, half_width, across), -point_height))

	# The silhouette, closed across the bottom. Drawn first and never faceted, so however
	# the facets above land there is always solid geometry occluding the sky behind it.
	var outline: PackedVector2Array = PackedVector2Array()
	outline.append(Vector2(-half_width, MASS_ROOT_SINK))
	outline.append_array(top)
	outline.append(Vector2(half_width, MASS_ROOT_SINK))

	var silhouette: Polygon2D = Polygon2D.new()
	silhouette.name = "Silhouette"
	silhouette.polygon = outline
	silhouette.vertex_colors = build_flat_vertex_colors(outline.size(), MASS_SILHOUETTE_VALUE)
	mass.add_child(silhouette)

	# One facet per span of the skyline, each dropped to the base to make a big triangle.
	# MASS_TOP_POINTS is 6, so that is five facets across a form -- large by construction,
	# which is the whole point. The value alternates so adjacent facets always read as two
	# different planes of the same solid rather than as flat colour.
	for facet_index: int in range(MASS_TOP_POINTS - 1):
		var left_point: Vector2 = top[facet_index]
		var right_point: Vector2 = top[facet_index + 1]
		var facet: Polygon2D = Polygon2D.new()
		facet.name = "Facet%d" % facet_index
		facet.polygon = PackedVector2Array([
			left_point,
			right_point,
			Vector2((left_point.x + right_point.x) * 0.5, MASS_ROOT_SINK),
		])
		# Per-vertex, not flat: the two top vertices sit one step lighter than the base
		# vertex, so each facet carries a shallow vertical falloff. Same technique as
		# terrain_generator.build_fill_vertex_colors(), and the reason a flat `color` would
		# be ignored here anyway (visuals.md, trap 9).
		var facet_value: float = MASS_FACET_VALUES[facet_index % MASS_FACET_VALUES.size()]
		facet.vertex_colors = PackedColorArray([
			make_mass_color(facet_value),
			make_mass_color(facet_value),
			make_mass_color(maxf(facet_value - MASS_FACET_FALLOFF, MASS_VALUE_FLOOR)),
		])
		mass.add_child(facet)

	return mass


# Opaque by construction -- see the occlusion note in build_ice_mass.
func make_mass_color(value: float) -> Color:
	return Color(value, value, value, 1.0)


func build_flat_vertex_colors(vertex_count: int, value: float) -> PackedColorArray:
	var colors: PackedColorArray = PackedColorArray()
	for _vertex_index: int in range(vertex_count):
		colors.append(make_mass_color(value))
	return colors


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
