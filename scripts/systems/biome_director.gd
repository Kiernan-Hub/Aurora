extends Node

class_name BiomeDirector

# Drives the scenery through a cycle of BiomePalettes as the run goes on, and is the ONLY
# thing in the project that reads one. Nothing here touches gameplay: no collision, no
# terrain geometry, no velocity, no state machine. If a physics gate ever notices this
# node exists, something has gone wrong.
#
# WHY DISTANCE AND NOT A CLOCK. The schedule is a pure function of
# player.global_position.x, which main.gd never world-rebases ("X is never world-rebased")
# and which terrain_generator.gd already uses as the ice texture's UV axis. That makes the
# biome at any point deterministic and replayable, the same contract get_terrain_height
# holds -- so a headless check can assert the whole schedule without simulating time.
#
# WHY THE TRANSITION IS FIVE CROSSFADES, NOT ONE. Fading every colour on one curve reads
# as a global dip, like someone turning a dimmer. Real light doesn't do that: the sky goes
# first, the air follows, and the ground is last because it is only reflecting what the
# sky is doing. CHANNEL_CURVES below is that offset, and it is the difference between the
# change feeling like weather and feeling like a cutover.
#
# LOAD-BEARING CONSTRAINTS -- the same ones every background file in this project carries:
#
#   * All six headless gates instantiate scenes/main.tscn, so this runs on every gate frame
#     with no opt-out flag, and a PARSE ERROR HERE HANGS THE GATES RATHER THAN FAILING
#     THEM (docs/development/visuals.md trap 3). Hence: headless returns early having
#     applied nothing at all, leaving every consumer on the daylight constants it shipped
#     with, so gate pixels are byte-identical to before this file existed.
#   * is_headless is computed locally from DisplayServer, NEVER from Services.is_headless
#     -- freeze_replay_runner.gd builds Main inside its _init(), before the autoload's
#     deferred _ready() has flushed (trap 4). snow_drift.gd shipped exactly this bug.
#   * set_process(false) happens BEFORE the headless return, not after (trap 6).
#   * Nothing is allocated per frame. The blend writes into one preallocated scratch
#     palette; the weights array is built once in _ready().

const PALETTE_PALE_MORNING: BiomePalette = preload("res://resources/biomes/pale_morning.tres")
const PALETTE_GLACIER_TEAL: BiomePalette = preload("res://resources/biomes/glacier_teal.tres")
const PALETTE_MAUVE_HAZE: BiomePalette = preload("res://resources/biomes/mauve_haze.tres")
const PALETTE_SUNSET_ROSE: BiomePalette = preload("res://resources/biomes/sunset_rose.tres")
const PALETTE_VIOLET_DUSK: BiomePalette = preload("res://resources/biomes/violet_dusk.tres")
const PALETTE_TWILIGHT_BLUE: BiomePalette = preload("res://resources/biomes/twilight_blue.tres")
const PALETTE_STARLIT_NIGHT: BiomePalette = preload("res://resources/biomes/starlit_night.tres")
const PALETTE_ARCTIC_DAWN: BiomePalette = preload("res://resources/biomes/arctic_dawn.tres")

# A day arc, and it wraps: arctic_dawn leads back into pale_morning, so a long run reads as
# time passing rather than as a shuffle. Adjacent entries are deliberately near neighbours
# in colour -- the crossfade only has to cover one step, never day-to-night in one go.
# STARTS ON A SATURATED BLUE, not on the palest entry. Every run begins at world_x 64, so
# whatever sits at index 0 is the whole first impression -- and opening on pale_morning made
# the ice read as grey concrete for the first ~2 minutes. Order is still a day arc, just
# rotated to begin at dawn rather than mid-morning.
const BIOME_CYCLE: Array[BiomePalette] = [
	PALETTE_ARCTIC_DAWN,
	PALETTE_PALE_MORNING,
	PALETTE_GLACIER_TEAL,
	PALETTE_MAUVE_HAZE,
	PALETTE_SUNSET_ROSE,
	PALETTE_VIOLET_DUSK,
	PALETTE_TWILIGHT_BLUE,
	PALETTE_STARLIT_NIGHT,
]

# World px per biome. At MAX_SPEED (750 px/s) this is ~100s; through the early ramp, where
# the average is nearer 550 px/s, it is ~2.3 minutes. Distance rather than time means a
# faster player sees more of the world, not the same amount of it faster.
const BIOME_DISTANCE: float = 75000.0
# How much of the END of each biome's distance is spent crossfading into the next. Must
# stay well under BIOME_DISTANCE or biomes never fully settle. 12000px is ~16s at cap.
const TRANSITION_DISTANCE: float = 12000.0

# [start, end] for each channel, as fractions of the transition window. Sky leads, the air
# follows it, the ice trails because ground colour is mostly reflected skylight. Indexed by
# BiomePalette.CHANNEL_*; order here must match those constants.
const CHANNEL_CURVES: Array[Vector2] = [
	Vector2(0.00, 0.70), # CHANNEL_SKY
	Vector2(0.08, 0.82), # CHANNEL_SCENERY
	Vector2(0.28, 1.00), # CHANNEL_ICE
	Vector2(0.05, 0.75), # CHANNEL_ATMOSPHERE
	Vector2(0.35, 1.00), # CHANNEL_GAMEPLAY
]

# Below this change in blend progress, re-pushing the palette would be invisible. Outside a
# transition progress is pinned at exactly 0, so this is what makes the steady state free.
const PROGRESS_EPSILON: float = 0.002

@export var player_path: NodePath = NodePath("../Player")
@export var sky_backdrop_path: NodePath = NodePath("../SkyBackdrop")
@export var parallax_path: NodePath = NodePath("../ParallaxBackground")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")
@export var snow_path: NodePath = NodePath("../SnowDrift/SnowParticles")
@export var ground_trees_path: NodePath = NodePath("../TerrainGenerator/GroundTreeSpawner")
@export var bird_flock_path: NodePath = NodePath("../BirdFlock/Flock")

var is_headless: bool = false
var player: CharacterBody2D
var sky_backdrop: Node
var background_layers: Array[BackgroundGenerator] = []
var terrain_generator: TerrainGenerator
var snow: Node
var ground_trees: Node2D
var bird_flock: Node2D

# Written into every frame of a transition instead of allocating a new Resource.
var blended: BiomePalette = BiomePalette.new()
var channel_weights: PackedFloat32Array = PackedFloat32Array()
var applied_biome_index: int = -1
var applied_progress: float = -1.0


func _ready() -> void:
	# Locally computed, never Services.is_headless -- see the header note.
	is_headless = DisplayServer.get_name() == "headless"
	if is_headless:
		set_process(false)
		return

	channel_weights.resize(BiomePalette.CHANNEL_COUNT)

	player = get_node_or_null(player_path) as CharacterBody2D
	if player == null:
		push_error("BiomeDirector requires a valid player_path.")
		set_process(false)
		return

	# sky_backdrop.gd and snow_drift.gd carry no class_name, so these two are the only
	# consumers the compiler cannot check the call against -- a renamed or mistyped
	# apply_palette on either would otherwise fail silently at runtime, leaving that one
	# element frozen on its starting colour while everything around it moved. Checked once
	# here instead, loudly.
	sky_backdrop = resolve_palette_consumer(sky_backdrop_path)
	snow = resolve_palette_consumer(snow_path)
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	ground_trees = get_node_or_null(ground_trees_path) as Node2D
	bird_flock = get_node_or_null(bird_flock_path) as Node2D

	var parallax: Node = get_node_or_null(parallax_path)
	if parallax != null:
		for layer: Node in parallax.get_children():
			var background_layer: BackgroundGenerator = layer as BackgroundGenerator
			if background_layer != null:
				background_layers.append(background_layer)

	# Push frame one, so the run opens already inside its first biome instead of spending
	# the first seconds on whatever the constants happen to be.
	apply_palette_for_world_x(player.global_position.x)


# _process, not _physics_process: this is presentation only and nothing downstream of it
# is simulated. Keeping it off the physics tick also means it can never contribute to a
# stall the freeze gates would have to explain.
func _process(_delta: float) -> void:
	apply_palette_for_world_x(player.global_position.x)


# Pure in world_x, which is the whole point -- see the header. Split out from _process so
# a headless check can drive it directly without a running game.
func apply_palette_for_world_x(world_x: float) -> void:
	# floor(), not int(), so a negative x (the player starts at 64 but the camera and the
	# background both address negative world space) still walks the cycle backwards in
	# order rather than folding around zero.
	var cycle_position: float = world_x / BIOME_DISTANCE
	var biome_index: int = int(floor(cycle_position))
	var distance_into_biome: float = (cycle_position - float(biome_index)) * BIOME_DISTANCE

	var transition_start: float = BIOME_DISTANCE - TRANSITION_DISTANCE
	var progress: float = 0.0
	if distance_into_biome > transition_start:
		progress = clampf((distance_into_biome - transition_start) / TRANSITION_DISTANCE, 0.0, 1.0)

	if biome_index == applied_biome_index and absf(progress - applied_progress) < PROGRESS_EPSILON:
		return
	applied_biome_index = biome_index
	applied_progress = progress

	var from_palette: BiomePalette = get_cycle_palette(biome_index)
	var to_palette: BiomePalette = get_cycle_palette(biome_index + 1)
	for channel_index: int in range(BiomePalette.CHANNEL_COUNT):
		channel_weights[channel_index] = get_channel_weight(channel_index, progress)
	BiomePalette.blend_into(from_palette, to_palette, channel_weights, blended)
	# The ice PATTERN is the one thing `blended` cannot carry -- a crossfade between two tiles
	# needs both endpoints and the weight, not a single value. So they ride alongside it to the
	# one consumer that renders ice. See BiomePalette.ice_texture.
	push_palette(blended, from_palette.ice_texture, to_palette.ice_texture, channel_weights[BiomePalette.CHANNEL_ICE])


func resolve_palette_consumer(consumer_path: NodePath) -> Node:
	var consumer: Node = get_node_or_null(consumer_path)
	if consumer == null:
		push_error("BiomeDirector could not resolve %s." % consumer_path)
		return null
	if not consumer.has_method("apply_palette"):
		push_error("BiomeDirector: %s has no apply_palette()." % consumer_path)
		return null
	return consumer


# posmod so the cycle wraps in both directions; a run that somehow addresses negative world
# x still lands on a real palette rather than an out-of-range index.
func get_cycle_palette(cycle_index: int) -> BiomePalette:
	return BIOME_CYCLE[posmod(cycle_index, BIOME_CYCLE.size())]


# smoothstep rather than a raw ramp so each channel eases in AND out. A linear colour lerp
# has a visible corner at both ends of the window -- the moment it starts and the moment it
# stops are both readable as events, which is exactly what this pass exists to avoid.
func get_channel_weight(channel_index: int, progress: float) -> float:
	var curve: Vector2 = CHANNEL_CURVES[channel_index]
	return smoothstep(curve.x, curve.y, progress)


func push_palette(palette: BiomePalette, from_ice_texture: Texture2D, to_ice_texture: Texture2D, ice_weight: float) -> void:
	if sky_backdrop != null:
		sky_backdrop.apply_palette(palette)
	for background_layer: BackgroundGenerator in background_layers:
		background_layer.apply_palette(palette)
	if terrain_generator != null:
		terrain_generator.apply_ice_palette(palette, from_ice_texture, to_ice_texture, ice_weight)
	if snow != null:
		snow.apply_palette(palette)
	# Trees and birds need no script change at all: a biome's effect on a foreground object
	# genuinely IS a multiplicative tint, and modulate propagates to every child for free,
	# including ones spawned later.
	if ground_trees != null:
		ground_trees.modulate = palette.tree_tint
	if bird_flock != null:
		# RGB ONLY. bird_flock.gd writes modulate.a every frame for its glide fade; taking
		# the whole Color here would fight it and the birds would never fade out.
		bird_flock.modulate.r = palette.bird_tint.r
		bird_flock.modulate.g = palette.bird_tint.g
		bird_flock.modulate.b = palette.bird_tint.b
