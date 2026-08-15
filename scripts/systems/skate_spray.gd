extends GPUParticles2D

class_name SkateSpray

# Ice chips thrown up by the skates while the frozen lake is being crossed. The lake's second
# visual after the mirror, and the same shape as the first: FrozenLakeDirector owns WHEN, this
# node owns nothing but the look, and it READS the director's phase rather than being told --
# `emitting = (phase == ACTIVE)` is true by construction from the one variable that already
# means it, with no call site in begin_lake() or finish_lake() to fall out of step.
#
# GPUParticles2D, exactly as SnowDrift is, so the per-frame cost is one transform write and the
# simulation runs on the GPU. Nothing here allocates during a crossing.
#
# WHERE IT SITS IN main.tscn IS LOAD-BEARING. A sibling placed AFTER LakeReflection: at
# lake_amount 1.0 that quad is opaque and IS the lake surface, so spray drawn before it is
# spray drawn underneath the ice. Tree order is the whole mechanism -- no z_index anywhere,
# the same rule LakeReflection's header sets out.
#
# NOT under a CanvasLayer, unlike SnowDrift. That one is weather in front of the camera and
# wants screen space; this is chips lying on the world, and the entire effect is that they get
# LEFT BEHIND as the player runs on. It has to be in the world to do that.

# Every number below is measured off `glossy biome trail.png` (1435x1096, skate line at y=760)
# and converted through the visible world rectangle at the pinned viewport -- 1382 x 778 world
# px. Nothing here was chosen by eye.

# Reference: the spray band runs y=670..775 against a skate line at 760, so it throws ~90px of
# a 1096px frame above the line -- 8.2%, or ~64 world px. But the MEDIAN bright pixel sits at
# 759, dead on the line. That combination is the whole character of the effect: most of the
# spray stays low and a thin tail reaches high, which is what a velocity spread plus gravity
# produces and what a single average velocity does not.
const CHIP_LIFETIME: float = 0.90
# Fewer than the reference's raw blob count, deliberately, and cut TWICE from it: 180 measured,
# 120 on the "it looks like snow" pass, 70 after the owner played that one ("too much coming
# off", "less stuff floating away"). A dense field of pale dots IS snow spray; ice is a small
# number of separable glints that each catch the light, and past a certain density the eye stops
# resolving them individually and reads the whole thing as dust again. See "WHY THIS IS ICE AND
# NOT SNOW" below -- count is one of the four things carrying that.
const CHIP_COUNT: int = 70

# Reference: the trail is legible ~800px behind her, 56% of the frame width, so ~770 world px --
# 1.03s at MAX_SPEED (750 px/s). CHIP_LIFETIME is 0.90 and therefore ~675px, pulled in from the
# measurement on the owner's "less stuff floating away". Trail length is not a constant anywhere
# in this file: the chips carry almost no horizontal velocity of their own, so the player simply
# runs out from under them and the length falls out of lifetime x speed. That is also why
# nothing here reads the current speed -- a slower player leaves a proportionally shorter trail,
# which is correct.
# THE CHIPS DO NOT FALL, AND THAT IS THE OWNER'S DIRECTION, NOT A SIMULATION RESULT.
# ("float up a little bit and stay at her level and drift behind her, not fall down.")
#
# Two earlier passes both threw a ballistic arc -- up fast, then down under gravity -- and both
# read as snow being shot out of the blades, because an arc is the signature of a THROWN OBJECT.
# The eye reads the parabola and infers mass. What the owner is describing is the opposite
# reading: motes light enough to hang in the air, which is what ice dust caught in a light
# actually does, and is also what leaves the glints on screen long enough to be seen twinkling.
#
# So the model is now: a small upward kick, killed almost immediately by heavy drag, against
# gravity near enough to zero that nothing ever comes back down inside a chip's lifetime. The
# chips end up parked in world space at roughly the height they reached, and the trail behind
# the player is produced entirely by the player leaving them there at 750 px/s.
const CHIP_VELOCITY_MIN: float = 16.0
const CHIP_VELOCITY_MAX: float = 78.0
# Up, and back. Wide and low: ice skitters off the surface it broke from, it does not fountain.
const CHIP_DIRECTION: Vector3 = Vector3(-0.5, -1.0, 0.0)
const CHIP_SPREAD_DEGREES: float = 46.0
# Not zero, and the sign is deliberate: a FAINT LIFT, so the field creeps upward by ~2px over a
# lifetime instead of hanging with the unnatural stillness of exactly zero. True zero g reads as
# a freeze-frame. Far too weak to produce an arc.
const CHIP_GRAVITY: Vector3 = Vector3(0.0, -6.0, 0.0)
# Air drag, and it is now the dominant force rather than a garnish -- this is what converts the
# kick into a hover. At the fast end, 78 px/s against 105 damping stops a chip in 0.74s having
# risen 78^2 / (2 * 105) = ~29 world px; at the slow end it barely leaves the blade. So most
# chips sit within a few px of the skate line and a few reach ~29px, which is the "float up a
# little bit and stay at her level" the owner asked for.
#
# THE REFERENCE MEASURES A 64px THROW AND THIS IS DELIBERATELY WELL UNDER IT. That measurement
# is a still frame of a skater braking hard; this is one crossing a lake at 750 px/s, and the
# owner has now rejected the measured arc twice. Recorded as an aesthetic override rather than
# quietly relabelled as a measurement.
const CHIP_DAMPING_MIN: float = 62.0
const CHIP_DAMPING_MAX: float = 130.0
# Each glint is a four-point star, so it has an orientation, and identical orientation across
# 120 particles reads as printed wallpaper. Random birth angle plus a slow tumble means the
# flares sweep past each other.
const CHIP_ANGLE_DEGREES: float = 180.0
const CHIP_ANGULAR_VELOCITY: float = 70.0
# Reference: the band reaches ~15px of 1096 BELOW the line, ~11 world px. Chips are born just
# under the blade and the box is barely wider than the contact patch.
const CHIP_EMISSION_EXTENTS: Vector3 = Vector3(5.0, 2.0, 1.0)

# ============================ WHY THIS IS ICE AND NOT SNOW ============================
#
# The first pass of this file built its sprite by copying snow_drift.gd's build_flake_texture()
# outright -- a soft round white puff, alpha-blended. That is a snowflake. Same shape, same
# neutral colour, same blending, and the owner's verdict was immediate: snow being shot out.
#
# Four things separate the two materials, and NOT ONE OF THEM IS "MORE GLOW". Turning the
# brightness up on a round white puff gives a brighter round white puff.
#
#   1. SHAPE. Snow is a soft round blob with no orientation -- it scatters light evenly because
#      it is a crystal aggregate full of air. Ice is a flat fracture face: it has facets, so it
#      throws a hard specular GLINT with flares along its edges. Hence a four-point star with a
#      white-hot core, built pixel by pixel in build_glint_texture(), rather than a radial
#      gradient. This is the single biggest one.
#   2. BLENDING. Snow SITS ON the surface and hides it, which is alpha blending, and against a
#      lake that is already pale blue the result is exactly the bland grey-white the owner saw.
#      A glint is light ARRIVING, which is additive -- it brightens the ice underneath instead
#      of covering it. That is where "glisten" actually comes from.
#   3. COLOUR. Snow is neutral. Ice is not: it takes its colour from what it is made of, so the
#      flares are cyan and only the specular core is white. A cyan flare added onto blue lake
#      ice shifts the hue as well as the level, which is what reads as a material rather than
#      as dust.
#   4. TWINKLE. A facet only catches the light while it happens to face it, so a real ice
#      scatter FLICKERS. The chips pulse over their own lifetime (build_twinkle_ramp), and since
#      they are born continuously the field shimmers rather than pulsing in unison.
#
# Restraint is deliberate -- the owner asked for "not too glowy". CHIP_ADD_STRENGTH is the one
# knob to turn if it is over or under, and it is the FIRST thing to reach for; changing the
# colours to fix a brightness problem is how this effect goes back to looking like dust.
# ======================================================================================

# Bigger than the 16px flake it replaces, because a four-point star needs pixels for its flares
# to be flares rather than a fat plus sign.
const CHIP_TEXTURE_SIZE: int = 32
const CHIP_SCALE_MIN: float = 0.10
const CHIP_SCALE_MAX: float = 0.55

# How tight the specular core is. Higher is a smaller, harder highlight -- this is what keeps
# the middle reading as a glint rather than as a glowing ball.
const GLINT_CORE_TIGHTNESS: float = 5.2
# Flare thinness across each axis. Large numbers, because a facet's flare is a spike.
const GLINT_FLARE_THINNESS: float = 13.0
# The vertical flare is deliberately shorter than the horizontal one -- roughly 2:1 measured off
# the built sprite. A perfectly symmetric cross reads as a drawn asterisk; an uneven one reads
# as a chip lying at an angle, and the random birth rotation then points them every way.
const GLINT_FLARE_H_WEIGHT: float = 0.80
const GLINT_FLARE_V_WEIGHT: float = 0.62
const GLINT_FLARE_H_LENGTH: float = 0.95
const GLINT_FLARE_V_LENGTH: float = 0.62

# The specular core: white, because a specular highlight is the colour of the LIGHT, not of the
# material.
const CHIP_CORE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
# The flares: the material's own colour, and cyan rather than the blue of the ice itself. Cyan
# is what a thin broken edge transmits, and it separates from the lake's authored blue instead
# of dissolving into it -- the same "check saturation before brightness" finding the ice band
# already cost this project weeks over (CLAUDE.md, and biomes.md).
const CHIP_FLARE_COLOR: Color = Color(0.55, 0.90, 1.0, 1.0)

# Overall additive strength. THE FIRST KNOB TO TOUCH if the spray is too hot or too shy -- the
# lake surface is already bright (brighter at the shore than its own sky, on purpose), so
# additive light on top clips to white fast. Under 1.0 so the glints add colour before they add
# blowout.
const CHIP_ADD_STRENGTH: float = 0.82

# Per-particle hue spread, small. Enough that the scatter is not 120 copies of one swatch, not
# so much that stray chips read as a different substance.
const CHIP_HUE_VARIATION: float = 0.035

# Culling rect, in this node's own local space and therefore anchored on the skates. It has to
# cover where the chips GO, not where they are born -- with local_coords off they stream ~770px
# to the left while the node stays with the player. Godot culls the whole system against this
# rect, so an under-sized one makes the entire spray blink out at a screen edge.
const VISIBILITY_MARGIN: float = 140.0
const VISIBILITY_TRAIL: float = 900.0

@export var player_path: NodePath = NodePath("../Player")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")
@export var lake_director_path: NodePath = NodePath("../FrozenLakeDirector")

var player: Player
var terrain_generator: TerrainGenerator
var lake_director: FrozenLakeDirector

# Last observed Main.total_world_rebase_shift. See _physics_process for why a change in it has
# to nuke the live particles rather than being corrected.
var last_rebase_shift: float = 0.0
var main_node: Main


func _ready() -> void:
	emitting = false

	# Locally computed, never services.is_headless, which is assigned in GameServices._ready()
	# and can still read false here -- the ordering trap CLAUDE.md records twice, and the one
	# snow_drift.gd's header documents against a harness that adds Main inside _init(). The
	# director hard-skips headless too, so this could never emit; the guard is so that no gate
	# carries a live particle system for tens of thousands of frames either.
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return

	player = get_node_or_null(player_path) as Player
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	lake_director = get_node_or_null(lake_director_path) as FrozenLakeDirector
	main_node = get_parent() as Main
	if player == null or terrain_generator == null or lake_director == null or main_node == null:
		# Null-guarded rather than fatal, exactly as LakeReflection and the director are: a
		# missing spray is a plainer lake, not a broken game.
		push_warning("SkateSpray disabled: missing player, terrain, lake director or Main.")
		set_physics_process(false)
		return

	amount = CHIP_COUNT
	lifetime = CHIP_LIFETIME
	# THE ONE SETTING THIS EFFECT CANNOT DO WITHOUT. With local_coords on, every chip rides the
	# emitter and the spray becomes a costume pinned to the player's boots instead of a trail
	# left on the ice.
	local_coords = false
	# No preprocess, deliberately, unlike SnowDrift's full-lifetime preroll: snow must already
	# be mid-fall on frame one, whereas a trail that exists before the first stride is a trail
	# somebody else left.
	texture = build_glint_texture()
	# Additive, and this is point 2 of the header -- without it the glints cover the ice instead
	# of lighting it, and the whole thing collapses back into pale dust. A CanvasItemMaterial on
	# the node rather than a shader: the project owns exactly two .gdshaders, both ice's, and
	# adding a third needs a reason (CLAUDE.md). A stock blend mode is not a reason.
	var additive_material: CanvasItemMaterial = CanvasItemMaterial.new()
	additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive_material
	# RGB white here so the sprite's own core/flare colouring survives unmultiplied; the alpha is
	# what _physics_process drives, and under ADD it scales how much light lands.
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	process_material = build_process_material()
	visibility_rect = Rect2(
		-VISIBILITY_TRAIL,
		-VISIBILITY_MARGIN,
		VISIBILITY_TRAIL + VISIBILITY_MARGIN,
		VISIBILITY_MARGIN * 2.0,
	)
	last_rebase_shift = main_node.total_world_rebase_shift


# _physics_process, not _process, and for LakeReflection's reason: the emitter is pinned to a
# surface y read out of the generator, and main.gd moves the player and the camera in the
# physics tick. Sampling on the render tick would place this frame's chips against a different
# moment's world.
func _physics_process(_delta: float) -> void:
	var is_active: bool = lake_director.phase == FrozenLakeDirector.Phase.ACTIVE

	# Emit only while the blades are actually on the ice. Entering a lake mid-glide is possible
	# and documented as such in the director's try_arm() -- it cannot be prevented at arm time --
	# and spray thrown from a player floating six feet up is the effect announcing that nobody
	# checked.
	emitting = is_active and player.is_on_floor()
	if not is_active:
		# Left with the emitter idle rather than hidden: chips already in the air have to finish
		# their arc past the far shore, and `visible = false` would delete the tail of the trail
		# at the exact frame the player leaves the ice.
		modulate.a = 0.0
		return

	# ONLY Y IS REBASED (world_rebaser.gd), and a lake is dead flat, so the player's y is
	# constant across a crossing and a shift is all but impossible to see here -- it fires on
	# drift past 2048px from the origin, and the frame before the lake began had already
	# cleared it. All but: a glide climbing near that boundary could still cross it. With
	# local_coords off, live chips are stored in world space and NOTHING can move them, so the
	# only honest response to a 1024px shift under them is to drop them. One frame of missing
	# trail against a 1024px displaced streak is not a close call.
	if main_node.total_world_rebase_shift != last_rebase_shift:
		last_rebase_shift = main_node.total_world_rebase_shift
		restart()

	# The blades meet the ice at the surface, not at the capsule's centre, and the surface is
	# read from the generator rather than derived from the capsule half-height so this cannot
	# drift out of agreement with the geometry the mirror is drawn against -- LakeReflection
	# pins its waterline to the identical call.
	global_position = Vector2(
		player.global_position.x,
		terrain_generator.get_surface_world_y(player.global_position.x),
	)

	# Everything cosmetic about this set piece rides the director's one ramp, so the spray
	# cannot arrive before the ice is blue or outlast the mirror at the far shore. Applied to
	# alpha rather than to the emission rate: fading the rate would thin the trail from the
	# skates outward, whereas the whole thing fading together is what every other lake element
	# does.
	modulate.a = lake_director.get_lake_blend() * CHIP_ADD_STRENGTH


func build_process_material() -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = CHIP_EMISSION_EXTENTS
	material.direction = CHIP_DIRECTION
	material.spread = CHIP_SPREAD_DEGREES
	material.initial_velocity_min = CHIP_VELOCITY_MIN
	material.initial_velocity_max = CHIP_VELOCITY_MAX
	material.gravity = CHIP_GRAVITY
	material.scale_min = CHIP_SCALE_MIN
	material.scale_max = CHIP_SCALE_MAX
	material.damping_min = CHIP_DAMPING_MIN
	material.damping_max = CHIP_DAMPING_MAX
	material.angle_min = -CHIP_ANGLE_DEGREES
	material.angle_max = CHIP_ANGLE_DEGREES
	material.angular_velocity_min = -CHIP_ANGULAR_VELOCITY
	material.angular_velocity_max = CHIP_ANGULAR_VELOCITY
	material.hue_variation_min = -CHIP_HUE_VARIATION
	material.hue_variation_max = CHIP_HUE_VARIATION
	material.color_ramp = build_twinkle_ramp()
	return material


# Point 4 of the header: the flicker. Brightness over each chip's own lifetime, and it does two
# jobs at once, which is why it is not a plain fade.
#
# The ENVELOPE is the reference's measurement -- brightness along the trail decays smoothly with
# distance behind the skates, and distance behind IS age here, so the decay is a fact about the
# reference rather than a taste. The RIPPLE riding on it is the twinkle: a facet only throws a
# highlight while it happens to be angled at the light, so a real ice scatter does not dim
# evenly, it winks. Chips are born continuously and each rides its own copy of this curve, so
# the field shimmers instead of pulsing in unison.
#
# Never starts at full: a glint that exists at full brightness on its first frame pops.
func build_twinkle_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.08, 0.30, 0.50, 0.72, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.52),
		Color(1.0, 1.0, 1.0, 0.90),
		Color(1.0, 1.0, 1.0, 0.34),
		Color(1.0, 1.0, 1.0, 0.0),
	])

	var ramp: GradientTexture1D = GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


# A specular glint: a hard white core with cyan flares along two axes. Point 1 of the header,
# and the single change that stops this reading as snow.
#
# WHY THIS IS NOT A GradientTexture2D. A radial gradient can only make a round soft blob -- it
# is precisely the shape that says "snow", and the first pass of this file used one because it
# was copied from snow_drift.gd. A star needs per-pixel work, so the image is composed by hand
# here. Built once in _ready() on 32x32 = 1024 pixels; the cost is invisible and it is paid at
# load, not during a crossing.
#
# Built in code rather than shipped as a .png for the reason snow_drift.gd gives: the project
# has no texture pipeline for effect art, and the player sprite is the only imported image in
# the game.
#
# Squared by MULTIPLICATION throughout, never pow(). That is a GLSL rule rather than a GDScript
# one (pow() with a negative base is undefined and NaN-propagates across a whole quad -- it bit
# the lake's glare and ice.gdshader's gloss), but keeping one habit across both languages is
# cheaper than remembering which file is which.
func build_glint_texture() -> ImageTexture:
	var image: Image = Image.create(CHIP_TEXTURE_SIZE, CHIP_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center: float = float(CHIP_TEXTURE_SIZE - 1) * 0.5

	for pixel_y in CHIP_TEXTURE_SIZE:
		for pixel_x in CHIP_TEXTURE_SIZE:
			# Normalised to [-1, 1] from the centre, so every constant above is resolution
			# independent and CHIP_TEXTURE_SIZE can change without retuning them.
			var dx: float = (float(pixel_x) - center) / center
			var dy: float = (float(pixel_y) - center) / center

			var radius: float = sqrt((dx * dx) + (dy * dy))
			var core_falloff: float = radius * GLINT_CORE_TIGHTNESS
			var core: float = exp(-(core_falloff * core_falloff))

			# Each flare is a spike: a thin Gaussian across one axis, faded out along the other so
			# it tapers to a point instead of running to the sprite's edge as a bar.
			#
			# THE TAPER IS SQUARED, AND THAT IS NOT A DETAIL. A linear taper leaves the flare at
			# useful brightness across nearly the whole sprite width -- rendered out, the first
			# version of this was a uniform horizontal BAR, which at 120 particles is 120 little
			# dashes and is precisely the geometric speed-line look that made the old
			# scripts/effects/flight_trail.gd unusable. Squaring pulls the ends in to points.
			var taper_horizontal: float = maxf(0.0, 1.0 - (absf(dx) / GLINT_FLARE_H_LENGTH))
			var flare_across_y: float = dy * GLINT_FLARE_THINNESS
			var flare_horizontal: float = exp(-(flare_across_y * flare_across_y)) \
					* taper_horizontal * taper_horizontal * GLINT_FLARE_H_WEIGHT

			var taper_vertical: float = maxf(0.0, 1.0 - (absf(dy) / GLINT_FLARE_V_LENGTH))
			var flare_across_x: float = dx * GLINT_FLARE_THINNESS
			var flare_vertical: float = exp(-(flare_across_x * flare_across_x)) \
					* taper_vertical * taper_vertical * GLINT_FLARE_V_WEIGHT

			var intensity: float = minf(1.0, core + flare_horizontal + flare_vertical)
			if intensity <= 0.0:
				image.set_pixel(pixel_x, pixel_y, Color(0.0, 0.0, 0.0, 0.0))
				continue

			# Point 3 of the header, and the reason the colour lives IN the sprite rather than in
			# modulate: the core is the colour of the light and the flares are the colour of the
			# material, so a single flat tint cannot express it. Weighted by the core's own
			# strength, so white-hot in the middle and cyan out along the spikes.
			var chip_color: Color = CHIP_FLARE_COLOR.lerp(CHIP_CORE_COLOR, clampf(core, 0.0, 1.0))
			chip_color.a = intensity
			image.set_pixel(pixel_x, pixel_y, chip_color)

	return ImageTexture.create_from_image(image)
