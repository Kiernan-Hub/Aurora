extends Line2D

class_name SkateTrack

# The glowing line the blades etch into the frozen lake -- the second half of the skate trail,
# and the lake's third visual after the mirror and the spray. Same division of labour as both:
# FrozenLakeDirector owns WHEN, this node owns nothing but the look, and it READS the director's
# phase rather than being told.
#
# WHY A Line2D AND NOT PARTICLES, WHICH IS THE OPPOSITE CHOICE FROM SkateSpray. The spray is
# hundreds of independent motes with their own physics, which is what a particle system is for.
# This is one continuous mark whose whole character is that it is CONNECTED and lies exactly
# where the blades went -- a thing particles cannot express, because each one would have to
# separately know about its neighbours to avoid gaps.
#
# AND WHY THAT IS NOT scripts/effects/flight_trail.gd's MISTAKE. That file is the project's one
# previous trail attempt and the owner's verdict on it was "geometric and just bad". It spawned
# UNCONNECTED 14px straight Line2D sticks with a random y jitter, so it read as a scatter of
# tally marks rather than as a path. The failure was the construction, not the class: one
# continuous polyline sampled every physics frame (12.5px apart at MAX_SPEED) is a smooth curve,
# and on the lake -- which is dead flat -- it is a straight horizontal line with nothing to
# facet. Nothing here reuses that file.
#
# WHERE IT SITS IN main.tscn: between LakeReflection and SkateSpray. Above the mirror because at
# lake_amount 1.0 that quad is opaque and IS the lake surface, and below the spray because the
# etch is IN the ice while the chips are above it. Tree order is the whole mechanism -- no
# z_index anywhere, the rule LakeReflection's header sets out.

# Measured off `glossy biome trail.png` (1435x1096, skate line at y=760) with the excess
# brightness over surrounding ice sampled along the track, then converted through the visible
# world rectangle at the pinned viewport (1382 x 778 world px).
#
# The measurement, in full, because it is unusually clean: the core sits at a FIXED y=760±4 with
# a 6-9px FWHM, and its excess decays almost perfectly LINEARLY with distance behind the skates
# -- +145 luma at the blade, +95 at 800px, +57 at 500px, +15 at 200px, +3 at 860px. Colour runs
# near-white-blue hot (234,246,254) at the blade to a cool dim blue (81,118,165) as it dies.
#
# A linear decay is why the gradient below is close to a straight ramp rather than the ease-out
# that would be the instinct. The etch does not fade like a light switching off; it fades like a
# groove healing over.

# 6-9px FWHM of a 1096px frame is ~0.7%, so ~5 world px.
const TRACK_WIDTH: float = 5.0
# The tail thins as well as dims -- a line that only loses alpha keeps a visible constant-width
# edge all the way to its end and reads as a drawn stroke that someone cut off.
const TRACK_TAIL_WIDTH_SCALE: float = 0.55

# Reference: legible to ~860px behind the blade, which at MAX_SPEED (750 px/s) is ~1.15s.
#
# AGE, NOT DISTANCE, for the reason SkateSpray uses a lifetime: the etch heals over time, so a
# slower player leaves a proportionally shorter mark. Distance-capping would instead make a
# crawling player trail an enormous stripe. Nothing in either file reads the current speed.
const TRACK_LIFETIME: float = 1.15

# ================= WHY THIS LINE IS NOT ADDITIVE, AND THE SPRAY IS =================
#
# The first pass of this file WAS additive, copying SkateSpray's reasoning, and it shipped as a
# solid white bar -- the owner's words, "it's just a single white line". Measured off that
# screenshot, and this is the whole lesson:
#
#   The night reference's ice is (92,127,175), luma 122. THIS BUILD'S LAKE IS (182,208,238),
#   luma 205. Headroom to white is R +73, G +47, B +17.
#
# At 0.55 strength the core clipped to exactly (255,255,255) everywhere past the first ~400px.
# A CLIPPED SIGNAL CARRIES NO INFORMATION: the gradient, the width taper and the cyan were all
# still being computed correctly and none of them could be seen. The far tail at low alpha still
# measured (221,241,254), correctly cyan -- so the shape was right and only the level was wrong.
#
# AND THE LEVEL COULD NOT SIMPLY BE LOWERED. Blue has 17 luma of headroom, so additive light on
# pale blue ice saturates BLUE FIRST and can only ever drift toward white -- the exact opposite
# of the cyan it was meant to produce. Additive cannot make a cyan glow on a bright blue surface
# at any strength.
#
# So on this lake a glow is made of SATURATION plus a modest luminance lift, not of added light,
# and the line blends normally. This is the project's own standing finding on a second axis:
# "it looks grey usually means saturation, not brightness" (CLAUDE.md, biomes.md) -- here it
# looked WHITE, and the answer was the same one.
#
# THE SPRAY STAYS ADDITIVE ON PURPOSE. Its chips are tiny, sparse and short-lived, so clipping a
# few dozen pixels of them reads as a hot specular spark, which is what a glint IS. This is a
# continuous line across most of the screen width, where the same clipping is just a bar.
# ===================================================================================

# The soft outer glow. Wide and faint -- this is what makes the mark read as GLOWING rather than
# as a stroke someone drew, and a single hard-edged line was most of why the first pass landed
# flat even before the clipping.
const TRACK_HALO_WIDTH_SCALE: float = 3.2
const TRACK_HALO_STRENGTH: float = 0.30
# The bright inner core, laid over the halo.
const TRACK_CORE_STRENGTH: float = 0.95

# If contact is lost and regained further away than this, the line is cleared rather than
# bridged. Jumping is suppressed on the lake, so the only way to leave the ice is to enter it
# mid-glide -- which try_arm() documents it cannot prevent. Without this, touching back down
# draws one straight chord across the whole gap: a perfectly geometric line through empty ice,
# which is exactly the artefact this effect cannot afford.
const TRACK_RESUME_GAP: float = 40.0

@export var player_path: NodePath = NodePath("../Player")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")
@export var lake_director_path: NodePath = NodePath("../FrozenLakeDirector")

var player: Player
var terrain_generator: TerrainGenerator
var lake_director: FrozenLakeDirector
var main_node: Main

# The bright inner line, drawn over this node's soft halo.
#
# TWO Line2Ds, AND THE ROLES ARE THIS WAY ROUND FOR DRAW ORDER. A child CanvasItem draws above
# its parent, and the core has to sit on top of the halo, so THIS node is the halo and the core
# is the child -- not the other way about, which would put the soft wide glow over the sharp one
# and mud it. The child holds no state: it is handed a copy of this node's points once a frame
# and has no idea the lake exists.
var core_line: Line2D = null

# Birth time of each point, parallel to `points` and in the same order, so the head of the line
# is the newest entry in both. Kept as a separate array because Line2D has nowhere to hang it.
var point_ages: PackedFloat32Array = PackedFloat32Array()

# This node's own clock, advanced in _physics_process. Not Time.get_ticks_msec(): that keeps
# running while the tree is paused, so a track would silently age out behind a pause menu. Same
# reasoning as LakeReflection's wobble_time.
var track_time: float = 0.0

var last_rebase_shift: float = 0.0


func _ready() -> void:
	clear_points()
	visible = false

	# Locally computed, never services.is_headless, which is assigned in GameServices._ready()
	# and can still read false here -- the ordering trap CLAUDE.md records twice. The director
	# hard-skips headless too, so this could never draw; the guard is so no gate pays for the
	# per-frame poll either.
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return

	player = get_node_or_null(player_path) as Player
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	lake_director = get_node_or_null(lake_director_path) as FrozenLakeDirector
	main_node = get_parent() as Main
	if player == null or terrain_generator == null or lake_director == null or main_node == null:
		# Null-guarded rather than fatal, exactly as the mirror, the spray and the director are:
		# a missing etch is a plainer lake, not a broken game.
		push_warning("SkateTrack disabled: missing player, terrain, lake director or Main.")
		set_physics_process(false)
		return

	# This node is the halo; see core_line's declaration for why that is the parent and not the
	# child. Ordinary alpha blending on both -- the header has the measurement that ruled additive
	# out on this surface.
	apply_line_style(self, TRACK_WIDTH * TRACK_HALO_WIDTH_SCALE, build_halo_gradient())

	core_line = Line2D.new()
	core_line.name = "TrackCore"
	apply_line_style(core_line, TRACK_WIDTH, build_core_gradient())
	core_line.width_curve = build_width_curve()
	add_child(core_line)

	last_rebase_shift = main_node.total_world_rebase_shift


# Shared between the halo and the core so the two cannot drift apart in shape and only differ in
# the three things they are meant to differ in: width, colour and strength.
#
# Round throughout: a square end cap is a visible little brick at the blade, and mitre joints on
# a polyline sampled this finely produce spikes wherever the sampling jitters.
func apply_line_style(line: Line2D, line_width: float, line_gradient: Gradient) -> void:
	line.width = line_width
	line.gradient = line_gradient
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.modulate = Color(1.0, 1.0, 1.0, 0.0)


# _physics_process for LakeReflection's reason: the etch is pinned to a surface y read out of
# the generator, and main.gd moves the player in the physics tick. Sampling on the render tick
# would lay this frame's point against a different moment's world.
func _physics_process(delta: float) -> void:
	var is_active: bool = lake_director.phase == FrozenLakeDirector.Phase.ACTIVE

	if not is_active and points.size() == 0:
		visible = false
		return

	track_time += delta

	# ONLY Y IS REBASED (world_rebaser.gd), and a lake is dead flat, so a shift is all but
	# impossible mid-crossing -- see SkateSpray's note for the one glide case that could still
	# reach it.
	#
	# THE RESPONSE HERE IS THE OPPOSITE OF THE SPRAY'S, AND THAT IS THE POINT. Live particles are
	# owned by the GPU and nothing can move them, so the spray can only drop its chips. These
	# points are an array this file owns, so the shift can simply be applied to them and the mark
	# survives intact. The shift is always a whole multiple of a power of two, so adding it is
	# exact in binary and cannot round the geometry.
	var rebase_shift: float = main_node.total_world_rebase_shift
	if rebase_shift != last_rebase_shift:
		apply_rebase(rebase_shift - last_rebase_shift)
		last_rebase_shift = rebase_shift

	if is_active:
		append_point()
	expire_points()

	visible = points.size() >= 2
	if not visible:
		return

	# One assignment, and the core is fully described by it -- it holds no state of its own.
	core_line.points = points

	# Everything cosmetic about this set piece rides the director's one ramp, so the etch cannot
	# arrive before the ice is blue or outlast the mirror at the far shore.
	var lake_blend: float = lake_director.get_lake_blend()
	modulate.a = lake_blend * TRACK_HALO_STRENGTH
	core_line.modulate.a = lake_blend * TRACK_CORE_STRENGTH


# One point per physics frame, which at MAX_SPEED is a point every 12.5 world px -- dense enough
# that the polyline is a curve rather than a chain of segments, and on this dead-flat surface a
# straight line regardless.
func append_point() -> void:
	# Only while the blades are actually on the ice. Entering a lake mid-glide is possible and
	# try_arm() documents that it cannot be prevented at arm time; an etch drawn under a floating
	# player is the effect announcing that nobody checked. Same guard as the spray's emitting.
	if not player.is_on_floor():
		return

	# The blades meet the ice at the surface, not at the capsule's centre, and the surface is
	# read from the generator rather than derived from the capsule half-height so this cannot
	# drift out of agreement with the geometry the mirror is drawn against -- LakeReflection pins
	# its waterline to the identical call, and SkateSpray its emitter.
	var contact_point: Vector2 = Vector2(
		player.global_position.x,
		terrain_generator.get_surface_world_y(player.global_position.x),
	)

	# Contact regained across a gap: start a new mark rather than bridging. See TRACK_RESUME_GAP.
	var point_count: int = points.size()
	if point_count > 0 and contact_point.distance_to(points[point_count - 1]) > TRACK_RESUME_GAP:
		clear_points()
		point_ages.clear()

	add_point(contact_point)
	point_ages.append(track_time)


# Drops points older than TRACK_LIFETIME from the TAIL of the line, which is index 0 -- points
# are appended at the head, so the array is always in age order and only the front can expire.
# That ordering is what makes this a while-loop over the front rather than a filter over all of
# them.
func expire_points() -> void:
	var oldest_allowed: float = track_time - TRACK_LIFETIME
	var expired_count: int = 0
	while expired_count < point_ages.size() and point_ages[expired_count] < oldest_allowed:
		expired_count += 1
	if expired_count == 0:
		return

	for _removed in expired_count:
		remove_point(0)
	point_ages = point_ages.slice(expired_count)


func apply_rebase(shift: float) -> void:
	for point_index in points.size():
		set_point_position(point_index, points[point_index] + Vector2(0.0, shift))


# Brightness along the line. Line2D samples a gradient from the FIRST point (offset 0) to the
# LAST (offset 1), and points are appended at the head, so offset 1 is the blade and offset 0 is
# the oldest surviving tail.
#
# Close to a straight ramp because the measurement is: excess luma runs +145 / +95 / +57 / +15 /
# +3 at 0 / 800 / 500 / 200 / 860 px behind, which is near-linear. The instinct here is an
# ease-out, and it would be wrong -- a groove healing over is not a light switching off. Colour
# runs with it, cyan in the body to near-white at the blade, for the reason SkateSpray's header
# gives at length: the core of a highlight is the colour of the light, the body is the colour of
# the material, and cyan separates from the lake's authored blue where a neutral white dissolves
# into it.
func build_core_gradient() -> Gradient:
	var glow: Gradient = Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.35, 0.78, 1.0])
	# Measured against the lake's own (182,208,238). Every colour here is chosen so the line is
	# BRIGHTER AND MORE SATURATED than the ice rather than trying to out-brighten it: the body at
	# (133,219,255) actually has LESS RED than the ice does, which is what makes it read as cyan
	# instead of as a pale smear, and the head only lifts luma by ~40. Nothing can clip, because
	# nothing is being added.
	glow.colors = PackedColorArray([
		Color(0.42, 0.76, 1.00, 0.0),
		Color(0.52, 0.86, 1.00, 0.38),
		Color(0.72, 0.94, 1.00, 0.80),
		Color(0.96, 1.00, 1.00, 1.0),
	])
	return glow


# The halo carries the same ramp at a fraction of the alpha and none of the white -- a soft glow
# should be the colour of the material all the way through, with only the core going white-hot,
# or the whole mark washes out to the pale smear the first pass produced.
func build_halo_gradient() -> Gradient:
	var glow: Gradient = Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.35, 0.78, 1.0])
	glow.colors = PackedColorArray([
		Color(0.42, 0.76, 1.00, 0.0),
		Color(0.48, 0.82, 1.00, 0.34),
		Color(0.55, 0.88, 1.00, 0.72),
		Color(0.62, 0.92, 1.00, 1.0),
	])
	return glow


# Thickness along the line, sampled the same way as the gradient: index 0 is the tail. Held near
# full for most of the line and pulled in only near the end, because the reference's track keeps
# a consistent 6-9px core and dies by dimming, not by narrowing -- the taper is here to kill the
# blunt end, not to reshape the mark.
func build_width_curve() -> Curve:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, TRACK_TAIL_WIDTH_SCALE))
	curve.add_point(Vector2(0.25, 0.92))
	curve.add_point(Vector2(1.0, 1.0))
	return curve
