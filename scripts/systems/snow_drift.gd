extends GPUParticles2D

# Drifting snow. GPUParticles2D rather than a hand-rolled drifter so the per-frame cost
# is zero CPU -- the particles are simulated on the GPU and this script runs only in
# _ready() and on a viewport resize.
#
# WHERE IT SITS IS A GAMEPLAY DECISION, NOT A VISUAL ONE. main.tscn parents this to a
# CanvasLayer at layer = -50: behind everything in the world (default layer 0), in front
# of ParallaxBackground (-100). Snow drifting OVER an obstacle or a coin is the one thing
# in the whole atmosphere pass that could genuinely cost readability, so it is placed
# where it structurally cannot -- the terrain, coins, powerups, obstacles and player all
# draw on top of it. Do not raise this layer above 0.
#
# Screen space also means the world rebase (main.gd, ~every 26s) cannot move it, and the
# drift reads as weather in front of the camera rather than as objects in the world.

const FLAKE_COUNT: int = 70
const FLAKE_LIFETIME: float = 16.0
# Fraction of the viewport width the emitter spans, centered. Wider than the screen so
# the sideways drift below cannot leave a bare edge.
const EMITTER_WIDTH_FRACTION: float = 1.3
const EMITTER_HEIGHT: float = 12.0
# How far above the top edge flakes are born, so none pop into existence on screen.
const EMITTER_MARGIN_Y: float = 40.0
const FALL_SPEED_MIN: float = 14.0
const FALL_SPEED_MAX: float = 38.0
# Gentle and mostly downward. The x component is what makes it drift rather than rain.
const FALL_DIRECTION: Vector3 = Vector3(-0.22, 1.0, 0.0)
const FALL_SPREAD_DEGREES: float = 14.0
const FALL_GRAVITY: Vector3 = Vector3(0.0, 6.0, 0.0)
const FLAKE_SCALE_MIN: float = 0.22
const FLAKE_SCALE_MAX: float = 0.65
# Soft, not bright. Snow reading as a haze of movement rather than as discrete white
# dots is most of what keeps it calm instead of busy.
const FLAKE_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.42)
const FLAKE_TEXTURE_SIZE: int = 16

# Extra headroom above FLAKE_COUNT so a glide can thicken the snowfall without a jarring
# pop: `amount` is allocated at the larger figure once, and amount_ratio (which scales how
# much of that pool is actively emitting) is what actually varies, smoothly, at runtime.
# This is here to give a high glide -- where the camera pulls back and the actual terrain
# shrinks to a sliver of screen, see docs/development/visuals.md, "Terrain fill shading"
# -- something moving to read besides a flat fill. GPUParticles2D simulates on the GPU, so
# the idle headroom costs nothing on CPU.
const GLIDE_DENSITY_MULTIPLIER: float = 1.8
const BASE_AMOUNT_RATIO: float = 1.0 / GLIDE_DENSITY_MULTIPLIER
const GLIDE_AMOUNT_RATIO: float = 1.0
const INTENSITY_SMOOTHNESS: float = 4.0

@export var player_path: NodePath

var is_headless: bool = false
var player: CharacterBody2D
# Set by biome_director.gd. Scales the glide lerp below rather than replacing it, so a
# low-snowfall biome still thickens during a glide -- the two are independent reasons for
# the snow to change and neither should cancel the other out.
var biome_density_scale: float = 1.0


func _ready() -> void:
	# Computed locally from DisplayServer, never read from Services.is_headless: at least
	# one harness (freeze_replay_runner.gd) adds Main inside its _init(), before the
	# autoload's deferred _ready() has flushed, so Services.is_headless is still its
	# default false at this point. Same reasoning, and the same one-line check, as
	# sfx_player.gd -- which shipped exactly that bug and had it measured.
	#
	# All six gates instantiate main.tscn, so without this they would each carry a live
	# particle system for tens of thousands of frames for no observable reason.
	is_headless = DisplayServer.get_name() == "headless"
	if is_headless:
		emitting = false
		set_process(false)
		return

	amount = int(FLAKE_COUNT * GLIDE_DENSITY_MULTIPLIER)
	amount_ratio = BASE_AMOUNT_RATIO
	lifetime = FLAKE_LIFETIME
	# A full lifetime of preroll, so the first frame of a run already has snow mid-fall
	# instead of an empty sky filling in over 16 seconds.
	preprocess = FLAKE_LIFETIME
	texture = build_flake_texture()
	modulate = FLAKE_MODULATE
	process_material = build_process_material()
	apply_viewport_size()
	get_viewport().size_changed.connect(apply_viewport_size)

	player = resolve_player()
	set_process(player != null)


func resolve_player() -> CharacterBody2D:
	var resolved_player: CharacterBody2D = null
	if player_path != NodePath():
		resolved_player = get_node_or_null(player_path) as CharacterBody2D
	if resolved_player == null:
		resolved_player = get_node_or_null("/root/Main/Player") as CharacterBody2D
	return resolved_player


# Purely cosmetic and soft-optional: if player resolution ever fails, the base snowfall
# above still runs exactly as before, just without the glide boost.
func _process(delta: float) -> void:
	var target_ratio: float = GLIDE_AMOUNT_RATIO if player.is_glide_active else BASE_AMOUNT_RATIO
	target_ratio *= biome_density_scale
	var interpolation_weight: float = 1.0 - exp(-INTENSITY_SMOOTHNESS * delta)
	amount_ratio = lerpf(amount_ratio, target_ratio, interpolation_weight)


# Called by biome_director.gd only. Never called under --headless -- and note this node's
# own headless branch has already set_process(false) and returned by then, so the density
# below would go nowhere anyway.
func apply_palette(palette: BiomePalette) -> void:
	modulate = palette.snow_tint
	biome_density_scale = palette.snow_density_scale


# Emitter geometry is the only thing here that depends on the window, and the window size
# is genuinely unknown (project.godot pins no viewport size and stretches with
# aspect="expand"), so it is read rather than assumed -- and re-read on resize.
func apply_viewport_size() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	position = Vector2(viewport_size.x * 0.5, -EMITTER_MARGIN_Y)

	var material: ParticleProcessMaterial = process_material as ParticleProcessMaterial
	if material == null:
		return
	material.emission_box_extents = Vector3(viewport_size.x * EMITTER_WIDTH_FRACTION * 0.5, EMITTER_HEIGHT, 1.0)
	# Long enough for the slowest flake to clear the bottom edge within its lifetime, so
	# flakes never blink out mid-screen. visibility_rect keeps the whole fall on screen
	# for culling purposes -- GPUParticles2D culls against this rect, not the window.
	visibility_rect = Rect2(
		-viewport_size.x * EMITTER_WIDTH_FRACTION * 0.5,
		0.0,
		viewport_size.x * EMITTER_WIDTH_FRACTION,
		viewport_size.y + (EMITTER_MARGIN_Y * 2.0),
	)


func build_process_material() -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.direction = FALL_DIRECTION
	material.spread = FALL_SPREAD_DEGREES
	material.initial_velocity_min = FALL_SPEED_MIN
	material.initial_velocity_max = FALL_SPEED_MAX
	material.gravity = FALL_GRAVITY
	material.scale_min = FLAKE_SCALE_MIN
	material.scale_max = FLAKE_SCALE_MAX
	return material


# A soft round dot, built in code rather than shipped as a .png: it is 16px of radial
# gradient, and the project has no texture pipeline for background art (the player sprite
# is the only imported image in the game).
func build_flake_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.7),
		Color(1.0, 1.0, 1.0, 0.0),
	])

	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = FLAKE_TEXTURE_SIZE
	texture.height = FLAKE_TEXTURE_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
