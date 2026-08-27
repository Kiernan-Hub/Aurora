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

# THE OPENING BIOME, AND IT IS NOT IN THE CYCLE. Substituted for cycle index 0 -- the
# ABSOLUTE index, never the wrapped one -- so it plays once at the top of a session and is
# then gone until the app is relaunched. When the cycle comes back around to that slot
# (index 8, 16, ...) it resolves to whatever this session's rotation puts there -- a real,
# saturated palette either way -- so nothing is lost by opening somewhere quieter.
#
# WHY: index 0 is the entire first impression, and the first ten seconds of a session should
# not be the most exciting thing on offer. This is pale and nearly colourless -- no glow, no
# disc, no stars -- and its tile is the faintest in the project on purpose.
#
# WHAT MAKES "ONCE" TRUE is get_persisted_phase() being monotonic; see its note. Nothing
# here tracks whether the intro has been spent, because with a phase that only ever grows,
# absolute index 0 is unreachable a second time by construction.
const PALETTE_FIRST_LIGHT: BiomePalette = preload("res://resources/biomes/first_light.tres")

# A day arc, and it wraps: starlit_night leads back into arctic_dawn, so a long run reads as
# time passing rather than as a shuffle. Adjacent entries are deliberately near neighbours in
# colour -- the crossfade only has to cover one step, never day-to-night in one go.
#
# THE SEQUENCE IS FIXED; ONLY THE ENTRY POINT MOVES. Each session rotates it by a random
# amount (session_cycle_rotation), so a launch might open on sunset_rose and run
# sunset_rose -> violet_dusk -> twilight_blue -> starlit_night -> arctic_dawn -> ..., but it
# always runs the arc in order. This array's indices are also the stable index space every
# gate and probe addresses palettes by.
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
# stay well under BIOME_DISTANCE or biomes never fully settle. 24000px is ~32s at cap.
# Raised from 12000 on 2026-08-13 -- user watched it in play and preferred the slower
# crossfade over the original. This is the intended value going forward, not a temp
# debug tweak, but it's only had that one look; revisit if it ever reads as sluggish.
const TRANSITION_DISTANCE: float = 24000.0

# How far apart two neighbouring palettes' celestial_position may sit when either of them
# owns a disc. The disc fades in and out AT that position, and position interpolates on the
# same channel as strength -- so a neighbour that disagrees makes the disc slide across the
# sky while fading (it shipped once and read as "the moon went bottom-right to top-left").
# Mirrored by biome_schedule_check.gd, which asserts it against every rotation the game can draw.
const MAX_DISC_DRIFT: float = 0.02

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
@export var coin_spawner_path: NodePath = NodePath("../TerrainGenerator/CoinSpawner")
@export var glide_coin_spawner_path: NodePath = NodePath("../TerrainGenerator/GlideCoinSpawner")
@export var obstacle_spawner_path: NodePath = NodePath("../TerrainGenerator/ObstacleSpawner")

var is_headless: bool = false
var player: CharacterBody2D
var sky_backdrop: Node
var background_layers: Array[BackgroundGenerator] = []
# The raster far layer. A second typed array rather than one array of Node: both
# element types are then still checked by the compiler, which is the whole reason
# resolve_palette_consumer() exists for the two scripts that carry no class_name.
var background_strips: Array[BackgroundStrip] = []
var terrain_generator: TerrainGenerator
var snow: Node
var ground_trees: Node2D
var bird_flock: Node2D
var coin_spawner: CoinSpawner
var glide_coin_spawner: GlideCoinSpawner
var obstacle_spawner: ObstacleSpawner

# Written into every frame of a transition instead of allocating a new Resource.
var blended: BiomePalette = BiomePalette.new()
var channel_weights: PackedFloat32Array = PackedFloat32Array()
var applied_biome_index: int = -1
var applied_progress: float = -1.0

# Where the previous run in THIS SESSION left off, in world px. GameManager banks it on
# death; the next run adds it to world_x before the cycle maths and so resumes the colour
# scheme it died in. One full cycle is ~13.7 minutes at shipping values, which nobody plays
# in a sitting, so without this most of the eight palettes are unreachable in practice.
#
# Orthogonal to session_cycle_rotation below: the phase says HOW FAR ALONG the session is, the
# rotation says WHERE IN THE ARC it started. Both are static and both die with the process, so
# a run picks up exactly where the last one left off.
#
# STATIC, AND THEREFORE DELIBERATELY NOT SAVED. It survives the reload_current_scene() a
# restart does, exactly like GameManager.pending_quick_restart, and dies with the process.
# So runs chain within a sitting, but every fresh launch opens on BIOME_CYCLE[0] again --
# which is the point: that slot was chosen as the whole first impression (see the cycle's
# note above), and persisting to disk would eventually open the game straight into the
# night biome for a returning player. It also means no save format change, so a phase can
# never be a thing that arrives corrupt from disk.
static var session_biome_phase: float = 0.0

# WHERE THIS SESSION ENTERS THE DAY ARC. Drawn once per process, lazily, on the first palette
# lookup: a rotation of BIOME_CYCLE, not a reordering of it. -1 means "not drawn yet".
#
# WHAT IT DOES. The intro still owns absolute index 0. Index 1 -- the first real biome, and
# every biome after it -- is BIOME_CYCLE[cycle_index + rotation], so a launch might open
# first_light -> sunset_rose -> violet_dusk -> twilight_blue -> ... and the next one
# first_light -> mauve_haze -> sunset_rose -> ... Different every launch, and still the arc.
#
# WHY A ROTATION AND NOT A SHUFFLE. The eight are authored as a day passing, and every colour
# in them assumes it: ice brightness tracks sky brightness along the arc (ice_surface 0.863 ->
# 0.625 alongside sky_top 0.773 -> 0.244), and each crossfade only has to cover one step
# between near neighbours. A shuffle (built and reverted, 2026-08-12) puts night ice under a
# morning sky and asks one transition to cover day-to-night. A rotation changes the entry point
# and nothing else, so EVERY adjacency the palettes were authored against still holds -- which
# is also why the disc rules need no filtering here: the ring is untouched.
#
# WHY IT IS STATIC. session_biome_phase carries across a death and a reload_current_scene(), so
# the rotation has to as well -- redrawing per run would move the palette out from under a
# phase that says "you were three biomes in", and dying would visibly change the sky. Static
# also means it dies with the process: a new launch is a new entry point, which is the feature.
static var session_cycle_rotation: int = -1

# Pins the phase at 0, so every run reopens on the intro biome instead of resuming.
#
# WHY THIS NEEDS TO EXIST. The intro is index 0 only, and the phase advances on every death
# and survives a restart -- so at the shipping BIOME_DISTANCE it is the first ~3 minutes of a
# cold launch, and at the 7500 playtest value only ~19 SECONDS, after which one death puts it
# out of reach until the app is fully relaunched. Iterating on how it looks is therefore
# almost impossible without this: three rounds of colour edits were made and eyeballed against
# a different biome entirely before anyone noticed.
#
# Plain var, not @export, for the same reason as every other knob here -- an exported bool can
# serialise into main.tscn and ship silently. shipping_values_check fails on it.
var debug_pin_intro_biome: bool = false

# TEMP REVIEW KNOB: seconds per biome. 0.0 is off and is the shipping value.
#
# Set it to e.g. 10.0 to walk the whole day arc in ~90 seconds instead of ~13.7 minutes, for
# eyeballing every palette in one sitting. shipping_values_check fails on any non-zero value.
#
# COLOUR ONLY, WHICH IS THE POINT. This feeds a SYNTHETIC world_x into the existing pure
# apply_palette_for_world_x() rather than shrinking BIOME_DISTANCE. Two reasons:
#
#   * Nothing else's numbers move. BIOME_DISTANCE is also read by get_persisted_phase() and by
#     biome_schedule_check's contrast floor; shrinking it would change what those mean, and the
#     gate would be measuring a schedule the game never ships. Here the constant is untouched
#     and only this director's *view* of the cycle is accelerated.
#   * The background does NOT speed up. Player speed, terrain and the parallax scroll all run
#     off player.global_position.x and never look at this. So the world moves at its normal
#     rate underneath while the sky, ice, scenery and object colours race -- which is exactly
#     what you want to review, and is why this cannot be done by just running the game faster.
#
# Time-based rather than distance-based deliberately: the speed ramp means a fixed distance is
# ~75s of biome early in a run and ~10s at cap, so a distance knob would not give a steady
# interval. Transitions scale with it -- TRANSITION_DISTANCE is 32% of BIOME_DISTANCE, so at
# 10.0 each biome holds ~6.8s and cross-fades ~3.2s.
#
# Starts at 0, so a run opens on the intro biome (absolute cycle index 0) and then walks the
# rotated cycle -- i.e. you see first_light plus all eight. It deliberately ignores
# biome_phase_offset, and get_persisted_phase() still uses the real world_x, so a review
# session cannot write a bogus phase into save.dat.
var debug_biome_seconds: float = 0.0

# Only advanced while the knob above is on.
var debug_biome_elapsed: float = 0.0

# This instance's copy, read once in _ready(). Held separately from the static so that
# apply_palette_for_world_x stays pure in world_x -- see get_persisted_phase().
var biome_phase_offset: float = 0.0


func _ready() -> void:
	# Locally computed, never Services.is_headless -- see the header note.
	is_headless = DisplayServer.get_name() == "headless"
	if is_headless:
		set_process(false)
		return

	channel_weights.resize(BiomePalette.CHANNEL_COUNT)

	# AFTER the is_headless return above, deliberately. A gate that restarts the scene more
	# than once would otherwise accumulate phase across its own iterations and measure a
	# different biome each time -- the same class of mistake as reading the developer's
	# save.dat, which GameManager.apply_upgrades() guards against for its jump level
	# (CLAUDE.md -- it cost 8 failures once). Headless keeps the offset at 0 and applies
	# nothing anyway.
	biome_phase_offset = 0.0 if debug_pin_intro_biome else session_biome_phase

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
	coin_spawner = get_node_or_null(coin_spawner_path) as CoinSpawner
	glide_coin_spawner = get_node_or_null(glide_coin_spawner_path) as GlideCoinSpawner
	obstacle_spawner = get_node_or_null(obstacle_spawner_path) as ObstacleSpawner

	var parallax: Node = get_node_or_null(parallax_path)
	if parallax != null:
		for layer: Node in parallax.get_children():
			var background_layer: BackgroundGenerator = layer as BackgroundGenerator
			if background_layer != null:
				background_layers.append(background_layer)
				continue
			var strip_layer: BackgroundStrip = layer as BackgroundStrip
			if strip_layer != null:
				background_strips.append(strip_layer)

	# Push frame one, so the run opens already inside its first biome instead of spending
	# the first seconds on whatever the constants happen to be.
	apply_palette_for_world_x(player.global_position.x + biome_phase_offset)


# _process, not _physics_process: this is presentation only and nothing downstream of it
# is simulated. Keeping it off the physics tick also means it can never contribute to a
# stall the freeze gates would have to explain.
func _process(delta: float) -> void:
	# Synthetic world_x from elapsed time -- see debug_biome_seconds. Colour only; nothing
	# downstream of the palette push reads this value.
	if debug_biome_seconds > 0.0:
		debug_biome_elapsed += delta
		apply_palette_for_world_x(debug_biome_elapsed / debug_biome_seconds * BIOME_DISTANCE)
		return

	apply_palette_for_world_x(player.global_position.x + biome_phase_offset)


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


# What GameManager banks into session_biome_phase on death, so the next run resumes this
# run's colour scheme. Takes the player's world_x rather than reading it, so the caller
# owns the "when".
#
# MONOTONIC ON PURPOSE, and this is what makes the opening biome a one-shot. An earlier
# version folded this into one cycle with fposmod, which is the obvious thing to do with a
# periodic schedule -- but it also meant a long enough run wrapped the phase back toward 0,
# so absolute index 0 recurred and the intro played again mid-session. Letting the phase
# only ever grow makes "index 0 happens exactly once per session" true by construction,
# with no spent-flag to keep in sync. It also matches how the schedule already reads
# world_x, which grows without bound within a run for the same reason.
#
# The precision worry the fposmod was answering does not apply at this scale: a GDScript
# float is a double, and even a ten-hour sitting at MAX_SPEED is ~2.7e7 px, nowhere near
# where a 53-bit mantissa starts quantising. What made an accumulator dangerous in the
# earlier design was that it was written to DISK and compounded across relaunches; this one
# dies with the process (see session_biome_phase).
#
# maxf because a negative phase is not a state any run can reach, and feeding one back in
# would put the next run at a negative index -- which posmods to a real palette rather than
# failing, i.e. it would be silently wrong.
#
# X is safe to use raw here -- world_rebaser.gd shifts Y only (main.gd:258).
func get_persisted_phase(world_x: float) -> float:
	return maxf(world_x + biome_phase_offset, 0.0)


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
#
# The index 0 case is checked BEFORE the posmod, and that is the whole mechanism behind the
# one-shot opening biome -- see PALETTE_FIRST_LIGHT. Index 8 posmods to slot 0 and gets that
# slot's palette; only the literal first pass gets the intro. Blending is unaffected: the
# caller asks for index and index + 1, so first_light crossfades into whatever the session put
# in slot 1 through exactly the same five channels as any other pair.
#
# STILL PURE IN cycle_index within a process, which is what apply_palette_for_world_x's
# contract rests on -- the rotation is drawn once and then never changes.
func get_cycle_palette(cycle_index: int) -> BiomePalette:
	return resolve_variant(get_cycle_base_palette(cycle_index), cycle_index)


# WHICH BIOME index lands on, before any rare-variant roll -- so it answers "where in the day
# arc is this", where get_cycle_palette answers "what gets drawn". A variant is a duplicate
# resource and therefore fails an identity comparison against BIOME_CYCLE, so anything
# reasoning about ORDER or IDENTITY must come through here. biome_schedule_check's arc-order
# and one-shot-intro claims do exactly that, and failed against get_cycle_palette when
# variants landed.
func get_cycle_base_palette(cycle_index: int) -> BiomePalette:
	if cycle_index == 0:
		return PALETTE_FIRST_LIGHT
	return BIOME_CYCLE[posmod(cycle_index + get_session_cycle_rotation(), BIOME_CYCLE.size())]


# --- Rare variants --------------------------------------------------------------------
# Three palettes carry an alternate look rolled per visit (see BiomePalette's variant group).
#
# KEYED ON cycle_index, NOT ROLLED LIVE. get_cycle_palette is contracted to be pure in
# cycle_index, and everything above rests on that: the caller asks for index and index + 1
# every frame of a transition, chunks repaint from it long after they spawned, and the ice
# dissolve holds both endpoint tiles at once. A coin flip at call time would hand the same
# index two different palettes and the ice would pop mid-crossfade.
#
# The salt makes the sequence differ between launches while staying fixed within one, exactly
# like session_cycle_rotation -- and for the same reason it is static: a death rebuilds the
# node, and re-rolling there would let a player reroll the rare variant by dying.
static var session_variant_salt: int = -1
# Resolved variants, keyed by the base palette's instance id. At most one entry per palette
# that has a variant, built on first use. Duplicating per call instead would allocate a
# Resource inside the transition loop, which is the one thing blend_into exists to avoid.
static var variant_cache: Dictionary = {}


static func get_session_variant_salt() -> int:
	if session_variant_salt < 0:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		session_variant_salt = rng.randi() & 0x7FFFFFFF
	return session_variant_salt


static func resolve_variant(base: BiomePalette, cycle_index: int) -> BiomePalette:
	if base.variant_chance <= 0.0:
		return base
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cycle_index, get_session_variant_salt()))
	if rng.randf() >= base.variant_chance:
		return base
	var key: int = base.get_instance_id()
	if not variant_cache.has(key):
		variant_cache[key] = base.make_variant()
	return variant_cache[key]


# Lazy rather than built in _ready() so that every caller goes through one path: the gates and
# probes construct a bare BiomeDirector and call get_cycle_palette() without a scene tree, and
# a headless _ready() returns before it could build anything.
static func get_session_cycle_rotation() -> int:
	if session_cycle_rotation < 0:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		session_cycle_rotation = pick_cycle_rotation(rng)
	return session_cycle_rotation


# Uniform over the rotations whose OPENING TRANSITION is safe, which is the only adjacency a
# rotation can get wrong. Every other pair is a pair the arc was authored with; the one the arc
# does not contain is first_light -> whatever lands at index 1, and that is exactly the seam
# every session plays. With the disc positions as authored this rules out one of the eight
# (starlit_night's moon sits at 0.30 while first_light parks celestial_position at 0.46, so the
# moon would slide across the sky as it faded in), leaving seven entry points.
#
# Enumerated rather than sampled-and-retried: there are only eight candidates, so the legal set
# is cheaper to build than a rejection loop is to reason about.
static func pick_cycle_rotation(rng: RandomNumberGenerator) -> int:
	var allowed: PackedInt32Array = get_allowed_rotations()
	if allowed.is_empty():
		# Unreachable unless first_light gains a disc AND every palette disagrees with it about
		# position. 0 is the authored arc, which opens on pale_morning as it always did.
		push_error("BiomeDirector: no rotation opens safely from first_light; falling back to the authored arc.")
		return 0
	return allowed[rng.randi_range(0, allowed.size() - 1)]


# Shared with biome_schedule_check, which asserts the seam holds for every rotation the game
# can draw -- the gate must not restate this list or the two drift apart.
static func get_allowed_rotations() -> PackedInt32Array:
	var allowed: PackedInt32Array = PackedInt32Array()
	for rotation: int in range(BIOME_CYCLE.size()):
		var opening: BiomePalette = BIOME_CYCLE[posmod(1 + rotation, BIOME_CYCLE.size())]
		if pair_is_disc_safe(PALETTE_FIRST_LIGHT, opening):
			allowed.append(rotation)
	return allowed


static func pair_is_disc_safe(from_palette: BiomePalette, to_palette: BiomePalette) -> bool:
	var from_has_disc: bool = from_palette.celestial_strength > 0.0
	var to_has_disc: bool = to_palette.celestial_strength > 0.0
	if from_has_disc and to_has_disc:
		return false
	if not from_has_disc and not to_has_disc:
		return true
	return from_palette.celestial_position.distance_to(to_palette.celestial_position) <= MAX_DISC_DRIFT


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
	for background_strip: BackgroundStrip in background_strips:
		background_strip.apply_palette(palette)
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
	# Coins and obstacles cannot go through modulate the way trees and birds do: they are
	# spawned individually into three different parents, and -- more importantly -- a biome
	# is allowed to SHIFT them and never to tint them into its own scheme, so what travels
	# here is an absolute colour. Each spawner stamps it on spawn and repaints what is
	# already on screen; all three early-out when the colour has not moved, which is what
	# keeps the steady state (progress pinned at 0) free.
	if coin_spawner != null:
		coin_spawner.apply_biome_color(palette.coin_color)
	if glide_coin_spawner != null:
		glide_coin_spawner.apply_biome_color(palette.coin_color)
	if obstacle_spawner != null:
		obstacle_spawner.apply_biome_color(palette.obstacle_color)
