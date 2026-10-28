extends Node2D

class_name LandingBurst

# A puff of ice glints where the blades touch down: small on every landing, wider and faster on a
# slam. Purely cosmetic -- it listens to Player.landed and touches nothing the player does.
#
# THE LOOK IS SKATESPRAY'S, ON PURPOSE. The lake spray's glint texture, twinkle ramp and additive
# blend were tuned by the owner twice ("ice, not snow", "float, don't fall"); this borrows all of
# it through SkateSpray's static builders and only changes the throw. Turn its knobs there, not
# here, or the two effects stop being the same ice.
#
# TWO EMITTERS, ALTERNATING. restart() on a one-shot system kills its live chips, and thin ice is
# crossed by hopping, so landings can come ~0.3s apart, inside a burst's lifetime. Alternating
# means a burst is only ever restarted two landings later, after it has finished.
#
# In the world, not a CanvasLayer, so the chips are LEFT BEHIND on the ice as the player runs on,
# and AFTER SkateSpray in main.tscn so it draws above the lake mirror the same way.

const NORMAL_CHIPS: int = 10
const SLAM_CHIPS: int = 26
const BURST_LIFETIME: float = 0.6
# Up, fanned wide. A slam throws flatter and harder: the force of it goes out along the ice.
const NORMAL_SPREAD_DEGREES: float = 70.0
const SLAM_SPREAD_DEGREES: float = 85.0
const NORMAL_VELOCITY: Vector2 = Vector2(30.0, 100.0)
const SLAM_VELOCITY: Vector2 = Vector2(70.0, 180.0)
# Heavier drag than the spray's, so the puff stops within ~30px (slam ~90px) and hangs there.
const BURST_DAMPING: Vector2 = Vector2(180.0, 300.0)
# Chips are born along the contact patch, wider for a slam.
const NORMAL_EMISSION_EXTENTS: Vector3 = Vector3(8.0, 2.0, 1.0)
const SLAM_EMISSION_EXTENTS: Vector3 = Vector3(18.0, 2.0, 1.0)
const VISIBILITY_HALF_SIZE: float = 220.0

@export var player_path: NodePath = NodePath("../Player")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")

var player: Player
var terrain_generator: TerrainGenerator
var main_node: Main
var emitters: Array[GPUParticles2D] = []
var next_emitter: int = 0
# Last observed Main.total_world_rebase_shift. Live chips are stored in world space and a rebase
# cannot move them, so on a shift they are hidden until the next landing (SkateSpray's rule).
var last_rebase_shift: float = 0.0


func _ready() -> void:
	# Locally computed, never services.is_headless (SkateSpray's header has why). No gate needs it.
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return
	player = get_node_or_null(player_path) as Player
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	main_node = get_parent() as Main
	if player == null or terrain_generator == null or main_node == null:
		push_warning("LandingBurst disabled: missing player, terrain or Main.")
		set_physics_process(false)
		return

	var texture: Texture2D = SkateSpray.build_glint_texture()
	for i: int in 2:
		var emitter: GPUParticles2D = GPUParticles2D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		emitter.amount = SLAM_CHIPS
		emitter.lifetime = BURST_LIFETIME
		emitter.local_coords = false
		emitter.texture = texture
		var additive_material: CanvasItemMaterial = CanvasItemMaterial.new()
		additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		emitter.material = additive_material
		emitter.modulate = Color(1.0, 1.0, 1.0, SkateSpray.CHIP_ADD_STRENGTH)
		emitter.process_material = SkateSpray.build_process_material()
		emitter.visibility_rect = Rect2(-VISIBILITY_HALF_SIZE, -VISIBILITY_HALF_SIZE,
				VISIBILITY_HALF_SIZE * 2.0, VISIBILITY_HALF_SIZE * 2.0)
		add_child(emitter)
		emitters.append(emitter)
	last_rebase_shift = main_node.total_world_rebase_shift
	player.landed.connect(_on_player_landed)


func _physics_process(_delta: float) -> void:
	if main_node.total_world_rebase_shift != last_rebase_shift:
		last_rebase_shift = main_node.total_world_rebase_shift
		for emitter: GPUParticles2D in emitters:
			emitter.visible = false


func _on_player_landed() -> void:
	var is_slam: bool = player.is_slamming
	var emitter: GPUParticles2D = emitters[next_emitter]
	next_emitter = (next_emitter + 1) % emitters.size()
	var burst: ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
	burst.direction = Vector3(0.0, -1.0, 0.0)
	burst.spread = SLAM_SPREAD_DEGREES if is_slam else NORMAL_SPREAD_DEGREES
	var velocity: Vector2 = SLAM_VELOCITY if is_slam else NORMAL_VELOCITY
	burst.initial_velocity_min = velocity.x
	burst.initial_velocity_max = velocity.y
	burst.damping_min = BURST_DAMPING.x
	burst.damping_max = BURST_DAMPING.y
	burst.emission_box_extents = SLAM_EMISSION_EXTENTS if is_slam else NORMAL_EMISSION_EXTENTS
	emitter.amount_ratio = 1.0 if is_slam else float(NORMAL_CHIPS) / float(SLAM_CHIPS)
	emitter.global_position = Vector2(player.global_position.x,
			terrain_generator.get_surface_world_y(player.global_position.x))
	emitter.visible = true
	emitter.restart()
