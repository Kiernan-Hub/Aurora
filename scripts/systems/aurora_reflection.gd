extends Node2D

class_name AuroraReflection

# THE AURORA IN THE ICE. One full-screen quad that mirrors the sky -- curtains, moon, stars,
# ridges, the skater -- down into the protected flat, for the sixty seconds the event lasts and
# not present at all for the rest of the run.
#
# WHY THIS EXISTS AS ITS OWN NODE, AND WHY IT IS NOT A SECOND MODE ON LakeReflection.
# It runs shaders/frozen_lake_reflection.gdshader, the same shader the lake uses, because that
# shader is a measured, screen-reading mirror with depth fade, a weighted three-tap blur, a
# sqrt-perspective ripple and a world-x mapping -- all of which the Aurora wanted and none of
# which is lake-specific. What IS lake-specific lives entirely in its uniforms, so this node
# needed no shader change at all. But lake_reflection.gd derives its visibility from ONE
# director's phase, deliberately, so that no two call sites can disagree about whether the
# mirror is up; threading a second director through that file would give away the property its
# header is built around. A sibling node touches the lake's code zero times.
#
# THE TWO NEVER CO-OCCUR. Aurora and Frozen Lake reserve non-overlapping spans (see
# AuroraDirector's arbitration), so only one of these quads is ever visible, and the
# backbuffer copy that hint_screen_texture forces is only ever paid once.
#
# COMPRESSION IS THE NUMBER THAT MATTERS HERE, and it is the one place this diverges hard from
# the lake's authored intent. The lake mirrors a fixed 1:1 because it reflects tall pines
# standing at its own shore. The Aurora reflects THE SKY, so its compression is DERIVED from
# where the ice line currently sits -- get_fill_compression() -- and is the largest value that
# still reaches the bottom of the frame.
#
# Do not replace it with a constant. A constant was tried (3.0) and failed the owner review in
# both directions at once: squashed reflection, empty lower quarter. The arithmetic is in the
# comment on COMPRESSION_MIN.
#
# A Node2D placed as a sibling AFTER TerrainGenerator in main.tscn, for exactly the reason
# lake_reflection.gd documents: a later sibling CanvasItem draws over the world and under the UI
# layer by tree order alone, with no z_index and no same-layer tie-break.
#
# BUT DELIBERATELY BEFORE AuroraBladeGlow, which LakeReflection sits after. The glow is a halo
# centred on the real contact point, so roughly its lower half lives BELOW the ice line -- the
# one band this quad paints. Drawing the mirror first leaves the glow wholly intact. The lake
# never had to care because no blade glow exists during a lake crossing.
#
# Default process_mode (INHERIT), so the wobble freezes on every menu for free -- which is why
# the shader takes a wobble_time uniform instead of reading TIME.

const REFLECTION_SHADER: Shader = preload("res://shaders/frozen_lake_reflection.gdshader")

# Overdraw on every side; the view rect is derived in floats and an exact fit can leave a
# hairline of unpainted ice at an edge on some frames.
const QUAD_MARGIN: float = 8.0

# --- Where this departs from the lake's authored uniforms, and why each one moves -------------
# COMPRESSION IS COMPUTED PER FRAME, NOT A CONSTANT. See get_fill_compression().
#
# It was a constant 3.0 for exactly one owner review, and that was wrong in both directions at
# once: the reflection was visibly squashed into the top of the slab AND the bottom of the
# screen was empty. Both are the same arithmetic. The shader samples
#     mirror_uv.y = waterline - depth * compression
# so the mirror runs out of frame to sample at depth = waterline / compression. At waterline
# 0.59 and compression 3.0 that is depth 0.197 -- the reflection cannot exist below screen y
# 0.79 no matter what the fade or the strength say, and `inside` zeroes it with a hard step,
# which is the pale seam the owner saw at the cutoff.
#
# The fill condition is therefore: waterline / compression >= 1 - waterline.
# The value that makes the mirror exactly fill the visible ice is waterline / (1 - waterline).
# 1.0 is a TRUE 1:1 MIRROR and is the target, not a compromise: a reflection is only squashed
# because compression is above 1. The fill constraint is a CEILING, not a value to sit on --
# taking the maximum that fills (1.44 here) was the second version of this and the owner's
# verdict was still "a little squished". Any value at or below the ceiling fills, so the right
# choice is the LEAST squashed one that fits, which is 1.0 wherever the ceiling allows it.
#
# At waterline 0.59 a 1:1 mirror reaches screen y 0.59 - 0.41 = 0.18 at the bottom of the
# frame, which is still inside the curtains -- so nothing is given up by not compressing.
# The ceiling only bites if the ice line ever sits above mid-screen, which the camera ramp
# does not do; the min() is there so that case degrades to "fills, slightly squashed" rather
# than to an empty band.
const COMPRESSION_TRUE_MIRROR: float = 1.0
const COMPRESSION_MIN: float = 0.8
# Far stronger than the lake's 0.55: this is the whole point of the node, and the surface under
# it is dark night ice rather than a bright daylit sheet.
const AURORA_REFLECTION_STRENGTH: float = 0.85
# The lake's 0.22 is tuned to die by the lower third. The Aurora wants the light to carry down
# the whole slab -- that dead bottom half is the complaint this node exists to answer. Raised
# from 0.62 once the fill fix meant the bottom of the frame actually had a reflection to keep:
# at 0.62 the far end was down to exp(-0.41/0.62) = 0.52 of strength, and the brightest part of
# the sky lands there.
const AURORA_FADE_DEPTH: float = 0.80
# A touch softer than the lake's 0.0022. Compressed reflections concentrate detail, and the
# curtains are broad soft shapes that survive -- and want -- more blur than pine tips do.
const AURORA_BLUR: float = 0.0034
# The lake's bright snow shelf is a SHORELINE. There is no shore here: the flat runs straight
# past the player. Left low rather than zero so the ice line still reads as an edge.
const AURORA_SHELF_STRENGTH: float = 0.22
# Broader and stronger than the lake's: this is the aurora's light pooling on the ice, and it
# breathes with the ripple clock, which is what stops the slab reading as dead.
const AURORA_GLARE_STRENGTH: float = 0.11
const AURORA_GLARE_DEPTH: float = 0.26
const AURORA_GLARE_SOFTNESS: float = 0.30
# Slower and wider than the lake's tight shore ripple. Big calm surface, long swells.
const AURORA_WOBBLE_AMPLITUDE: float = 0.0052
const AURORA_WOBBLE_FREQUENCY: float = 15.0
const AURORA_WOBBLE_SPEED: float = 0.9
# The stress-line banding, a little more present than the lake's so the sheet has some texture
# for the reflected light to sit on.
const AURORA_BAND_STRENGTH: float = 0.016

# The mirror arrives slightly after the sky does. Without this the ice lights up on the same
# frame the curtains do, which reads as a filter switching on; with it the sky appears and the
# ice answers it.
const REFLECTION_ONSET: float = 0.18

@export var player_path: NodePath = NodePath("../Player")
@export var camera_path: NodePath = NodePath("../Camera2D")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")

var player: Node2D
var camera: Camera2D
var terrain_generator: TerrainGenerator
var material_ref: ShaderMaterial = null
var disabled: bool = false

# The wobble's own clock, advanced from the blend pushes rather than read from TIME.
var wobble_time: float = 0.0
var view_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	visible = false

	# Locally computed, never services.is_headless, which is assigned in GameServices._ready()
	# and can still read false here. The director hard-skips headless anyway.
	if DisplayServer.get_name() == "headless":
		disabled = true
		return

	player = get_node_or_null(player_path) as Node2D
	camera = get_node_or_null(camera_path) as Camera2D
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	if player == null or camera == null or terrain_generator == null:
		# Null-guarded rather than fatal, as every other Aurora consumer is: a missing mirror
		# is a plainer aurora, not a broken game.
		disabled = true
		push_warning("AuroraReflection disabled: missing player, camera or terrain.")
		return

	material_ref = ShaderMaterial.new()
	material_ref.shader = REFLECTION_SHADER
	material = material_ref
	apply_static_uniforms()


# PUSHED by AuroraDirector.push_blend(), not pulled from its phase. That is the convention every
# other Aurora consumer already follows, and it is why this node needs no director reference:
# one clock, one dispatch, one set of nodes that answer it.
#
# The single most important line here is the visibility toggle. A hidden CanvasItem is never
# rendered, so the backbuffer copy that hint_screen_texture forces never happens -- this mirror
# costs exactly nothing for the twenty-nine minutes of every thirty that no aurora is up.
func apply_aurora(blend: float, _elapsed: float) -> void:
	if disabled or material_ref == null:
		return
	var strength: float = clampf(blend, 0.0, 1.0)
	# Eased in after the sky, then remapped back to full so the crest still reaches 1.0.
	var amount: float = clampf(
		(strength - REFLECTION_ONSET) / maxf(1.0 - REFLECTION_ONSET, 0.001), 0.0, 1.0)

	var is_active: bool = amount > 0.0
	if visible != is_active:
		visible = is_active
	if not is_active:
		return

	# Advanced from the director's own cadence rather than a local delta, so it cannot drift
	# from the event clock and it stops with the tree.
	wobble_time += get_physics_process_delta_time()

	var view_world_size: Vector2 = get_visible_world_size()
	var half_height: float = view_world_size.y * 0.5
	# A WORLD y through get_surface_world_y(), which adds the generator's own position -- so
	# world rebasing is accounted for upstream and is invisible here. The aurora flat is dead
	# flat, so the player's x is as good as any other.
	var surface_world_y: float = terrain_generator.get_surface_world_y(player.global_position.x)
	var view_top_y: float = camera.global_position.y - half_height
	var ice_line: float = (surface_world_y - view_top_y) / maxf(half_height * 2.0, 1.0)

	# Following by position rather than by redrawing: the geometry is the same rect every frame.
	global_position = camera.global_position

	# The ice UNDER this quad is painted from these same two colours by
	# TerrainGenerator.refresh_ice_appearance(), so whatever shows through while the ramp is
	# still partly transparent already matches and no step appears at the boundary.
	material_ref.set_shader_parameter("shore_color", terrain_generator.effective_ice_surface)
	material_ref.set_shader_parameter("far_color", terrain_generator.effective_ice_depth)

	# World-space mapping for the x-varying features. Without it they key on screen position and
	# sit still while the world slides past underneath, which reads as dirt on the lens.
	material_ref.set_shader_parameter(
		"world_left_x", camera.global_position.x - view_world_size.x * 0.5)
	material_ref.set_shader_parameter("world_width", view_world_size.x)
	# Recomputed every frame because the ice line MOVES: AuroraDirector's camera ramp lifts the
	# terrain from ~0.55 to 0.59 across the encounter, and aspect="expand" changes it per device.
	# A constant cannot satisfy the fill condition at every one of those values.
	material_ref.set_shader_parameter("reflection_compression", get_fill_compression(ice_line))
	material_ref.set_shader_parameter("waterline", ice_line)
	material_ref.set_shader_parameter("lake_amount", amount)
	material_ref.set_shader_parameter("wobble_time", wobble_time)


# Everything that never changes over an encounter, written once. Only the frame-varying
# uniforms are pushed per frame.
func apply_static_uniforms() -> void:
	material_ref.set_shader_parameter("reflection_strength", AURORA_REFLECTION_STRENGTH)
	material_ref.set_shader_parameter("reflection_fade_depth", AURORA_FADE_DEPTH)
	material_ref.set_shader_parameter("reflection_blur", AURORA_BLUR)
	material_ref.set_shader_parameter("shelf_strength", AURORA_SHELF_STRENGTH)
	material_ref.set_shader_parameter("glare_strength", AURORA_GLARE_STRENGTH)
	material_ref.set_shader_parameter("glare_depth", AURORA_GLARE_DEPTH)
	material_ref.set_shader_parameter("glare_softness", AURORA_GLARE_SOFTNESS)
	material_ref.set_shader_parameter("wobble_amplitude", AURORA_WOBBLE_AMPLITUDE)
	material_ref.set_shader_parameter("wobble_frequency", AURORA_WOBBLE_FREQUENCY)
	material_ref.set_shader_parameter("wobble_speed", AURORA_WOBBLE_SPEED)
	material_ref.set_shader_parameter("band_strength", AURORA_BAND_STRENGTH)


# The compression that makes the mirror exactly reach the bottom of the frame, so there is no
# starved band below it and no hard `inside` cutoff on screen. Clamped only to keep a degenerate
# ice line (one near the top or bottom of the frame, which the camera ramp never produces) from
# asking for an absurd value.
#
# This is ALSO the un-squish: it returns a true 1:1 mirror whenever the frame allows one, and
# only compresses when a high ice line would otherwise leave a starved band at the bottom.
func get_fill_compression(ice_line: float) -> float:
	var fill_ceiling: float = ice_line / maxf(1.0 - ice_line, 0.001)
	return clampf(minf(COMPRESSION_TRUE_MIRROR, fill_ceiling), COMPRESSION_MIN, COMPRESSION_TRUE_MIRROR)


# World-space size of what the camera can see. Derived from the viewport and the zoom rather
# than the project's base resolution, because aspect="expand" makes that base a MINIMUM -- a
# 20:9 phone genuinely sees more world, and a quad sized off the base would leave a strip
# unmirrored.
func get_visible_world_size() -> Vector2:
	var size: Vector2 = get_viewport_rect().size / camera.zoom
	if not size.is_equal_approx(view_size):
		view_size = size
		queue_redraw()
	return view_size


func _draw() -> void:
	if view_size == Vector2.ZERO:
		return
	# Centred on the node's own origin, which apply_aurora() pins to the camera. Full-screen on
	# purpose -- the shader's header has the Mobile-renderer backbuffer reason, and everything
	# above the ice line is clipped to alpha 0 there rather than by shrinking this rect.
	var size: Vector2 = view_size + Vector2(QUAD_MARGIN, QUAD_MARGIN) * 2.0
	draw_rect(Rect2(-size * 0.5, size), Color.WHITE)
