extends Node2D

class_name LakeReflection

# The frozen lake's mirror surface: one full-screen quad carrying
# shaders/frozen_lake_reflection.gdshader, drawn over the ice for the ten seconds the lake
# lasts and not present at all for the other nineteen minutes fifty.
#
# Division of labour, matching every other piece of this feature. FrozenLakeDirector owns WHEN
# (its Phase), TerrainGenerator owns the geometry, and this node owns nothing but the look. It
# READS the director's phase rather than being told: a push would need a call site in
# begin_lake(), one in finish_lake() and a third in _on_player_died() -- three places that can
# disagree about whether the mirror is up -- whereas `visible = (phase == ACTIVE)` is true by
# construction from the one variable that already means what it says.
#
# A Node2D, NOT A CanvasLayer, and it is a sibling placed after TerrainGenerator in main.tscn.
# A CanvasLayer at layer 0 draws above the root viewport canvas REGARDLESS of tree position
# (that is exactly why the UI layer works), so "between the world and the UI" would rest on a
# same-layer tie-break this project has never relied on and that inverts silently if anyone
# reorders the scene. A later sibling CanvasItem in the root canvas draws after Sky (-200),
# Parallax (-100), Birds (-60), Snow (-50), Player and TerrainGenerator, and before the UI
# layer, using tree order alone -- the rule the project already documents ("no z_index
# anywhere").
#
# Default process_mode (INHERIT), so the wobble freezes on every menu for free. That is the
# whole reason the shader takes a wobble_time uniform instead of reading TIME, which keeps
# running while the tree is paused.

const REFLECTION_SHADER: Shader = preload("res://shaders/frozen_lake_reflection.gdshader")

# The quad is grown by this much on every side. The view rectangle is derived from the camera
# and the zoom in floats, so an exact fit can leave a hairline of unpainted ice at an edge on
# some frames; a few pixels of overdraw is cheaper than reasoning about the rounding.
const QUAD_MARGIN: float = 8.0

# THE SAME LAKE EVERY TIME, and that is the owner's call (2026-08-14): it is a set piece the
# player meets roughly every twenty minutes, so it has to be recognisable on sight rather than
# recoloured by whichever biome it happens to interrupt. What keeps it inside the world anyway is
# that the shader SMEARS the columns above the waterline down the sheet -- so the biome's own sky,
# ridges and pines light the lake without any palette value reaching it.
#
# THIS IS WHY THERE IS NO PER-BIOME REFLECTION KNOB. `BiomePalette.reflection_strength` existed,
# authored 0.2-0.7 across all nine palettes and read by nothing; it predated the decision above and
# was deleted on 2026-08-15 rather than wired up here. Nothing in this file should grow a palette
# lookup -- the biome reaches the lake through what the mirror reflects, and only through that.

@export var player_path: NodePath = NodePath("../Player")
@export var camera_path: NodePath = NodePath("../Camera2D")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")
@export var lake_director_path: NodePath = NodePath("../FrozenLakeDirector")

var player: Node2D
var camera: Camera2D
var terrain_generator: TerrainGenerator
var lake_director: FrozenLakeDirector
var material_ref: ShaderMaterial = null

# The wobble's own clock. Advanced here rather than read from TIME; see the header.
var wobble_time: float = 0.0

# Size of the visible world rectangle, cached so _draw() only reruns when it actually changes
# (a window resize). The quad follows the camera by MOVING, not by being rebuilt.
var view_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	visible = false

	# Locally computed, never services.is_headless, which is assigned in GameServices._ready()
	# and can still read false here. Nothing to draw without a display server, and the director
	# hard-skips headless anyway, so this would never become visible -- the guard is so that no
	# gate pays for the per-frame poll either.
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return

	player = get_node_or_null(player_path) as Node2D
	camera = get_node_or_null(camera_path) as Camera2D
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	lake_director = get_node_or_null(lake_director_path) as FrozenLakeDirector
	if player == null or camera == null or terrain_generator == null or lake_director == null:
		# Null-guarded rather than fatal, exactly as FrozenLakeDirector is: a missing mirror is
		# a plainer lake, not a broken game.
		push_warning("LakeReflection disabled: missing player, camera, terrain or lake director.")
		set_physics_process(false)
		return

	material_ref = ShaderMaterial.new()
	material_ref.shader = REFLECTION_SHADER
	material = material_ref


# _physics_process, not _process: the waterline is derived from the camera, and main.gd moves
# the camera in _physics_process. Sampling on the render tick instead would read the camera
# from a different moment than the frame being drawn was composed with, which on a set piece
# whose entire premise is a horizontal line at the player's feet would show up as that line
# swimming against the ice.
func _physics_process(delta: float) -> void:
	# THE SINGLE MOST IMPORTANT LINE HERE. A hidden CanvasItem is never rendered, so the
	# backbuffer copy that hint_screen_texture forces never happens either -- the mirror costs
	# exactly nothing for the 19m50s of every 20 minutes that no lake is being crossed.
	var is_active: bool = lake_director.phase == FrozenLakeDirector.Phase.ACTIVE
	if visible != is_active:
		visible = is_active
	if not is_active:
		return

	wobble_time += delta

	var view_world_size: Vector2 = get_visible_world_size()
	var half_height: float = view_world_size.y * 0.5
	# The waterline is a WORLD y read through get_surface_world_y(), which adds the generator's
	# own position -- so world rebasing is already accounted for and this needs no knowledge of
	# it. On the lake the surface is dead flat, so the player's x is as good as any other.
	var surface_world_y: float = terrain_generator.get_surface_world_y(player.global_position.x)
	var view_top_y: float = camera.global_position.y - half_height
	var waterline: float = (surface_world_y - view_top_y) / maxf(half_height * 2.0, 1.0)

	# Following by position rather than by redrawing: the quad's geometry is the same rect
	# every frame, so there is nothing to rebuild unless the window resized.
	global_position = camera.global_position

	# The gradient's two ends come from the generator rather than being restated here, because the
	# ice UNDER this quad is painted with the same two colours -- that is what shows through while
	# the entry ramp is still partly transparent, and a second copy of the numbers would put a
	# visible step at each shore the moment either was edited. Pushed per frame, not once in
	# _ready(), because get_lake_tint() moves them with the biome (see LAKE_BIOME_HUE_WEIGHT).
	material_ref.set_shader_parameter("shore_color", terrain_generator.get_lake_tint(TerrainGenerator.LAKE_ICE_SURFACE))
	material_ref.set_shader_parameter("far_color", terrain_generator.get_lake_tint(TerrainGenerator.LAKE_ICE_DEPTH))

	# World-space mapping for every x-varying feature in the shader -- the shelf's irregularity and
	# the banding's phase. Without it they would key on screen position and sit still while the
	# world slid past underneath, which reads as dirt on the lens.
	material_ref.set_shader_parameter("world_left_x", camera.global_position.x - view_world_size.x * 0.5)
	material_ref.set_shader_parameter("world_width", view_world_size.x)

	material_ref.set_shader_parameter("waterline", waterline)
	# The director's ramp, the same one the ice's colour rides, so the surface arrives and leaves
	# as one thing. At 1.0 this quad is opaque and IS the lake.
	material_ref.set_shader_parameter("lake_amount", lake_director.get_lake_blend())
	material_ref.set_shader_parameter("wobble_time", wobble_time)


# World-space size of what the camera can see. Derived from the viewport and the zoom rather
# than from the project's base resolution, because aspect="expand" makes that base a MINIMUM --
# a 20:9 phone genuinely sees more world than a 16:9 one, and a quad sized off the base would
# leave the extra strip unmirrored.
func get_visible_world_size() -> Vector2:
	var size: Vector2 = get_viewport_rect().size / camera.zoom
	if not size.is_equal_approx(view_size):
		view_size = size
		queue_redraw()
	return view_size


func _draw() -> void:
	if view_size == Vector2.ZERO:
		return
	# Centred on the node's own origin, which _physics_process pins to the camera. Full-screen
	# on purpose -- the shader's header has the Mobile-renderer backbuffer reason, and the top
	# half is clipped to alpha 0 there rather than by shrinking this rect.
	var size: Vector2 = view_size + Vector2(QUAD_MARGIN, QUAD_MARGIN) * 2.0
	draw_rect(Rect2(-size * 0.5, size), Color.WHITE)
