extends Resource

class_name BiomePalette

# One scenery mood, as pure data. Every colour the background pass used to hardcode across
# sky_backdrop.gd, background_generator.gd, terrain_generator.gd, snow_drift.gd,
# ground_tree_spawner.gd and bird_flock.gd now lives here instead, and biome_director.gd
# is the only thing that reads it.
#
# THIS FILE HAS NO SCENE-TREE ACCESS AND NO STATE. It is data plus one pure blend
# function. That is deliberate: all six headless gates instantiate scenes/main.tscn, so
# anything with a _process here would run on every gate frame forever.
#
# WHY MULTIPLIERS, NOT COLOURS, FOR THE ICE:
# Polygon2D renders `texture_sample * vertex_color` and ignores `.color` outright once
# vertex_colors is populated -- see docs/development/visuals.md trap 9, which cost someone
# a debugging session. ice_surface/ice_depth are therefore multipliers against
# ICE_TERRAIN_TEXTURE, not the fill colour itself. This is also exactly the operation a
# tint shader would perform, which is why this pass needs no shader at all.
#
# That multiply only produces the intended hue against a GREYSCALE tile, which
# ice_depth_gradient.png is. It also carries the whole light-to-dark depth ramp itself, so
# the ice fields below must vary HUE rather than brightness -- see their note.
#
# PARALLAX COLOURS ARE FAR/NEAR ENDPOINTS, NOT ONE ENTRY PER LAYER. Each
# BackgroundGenerator carries a depth_t (0 = furthest, 1 = nearest) and lerps between
# these two, so adding a fifth parallax layer needs no edit to any of the eight palettes,
# and no palette can accidentally break the far-lighter-than-near ordering that produces
# the depth read in the first place.

# --- Transition channels -------------------------------------------------------------
# A biome change is not one crossfade, it is five overlapping ones. Each group of fields
# below blends on its own channel, and biome_director.gd gives each channel a different
# start/end within the transition window -- so the sky has already shifted by the time the
# ice follows it, the way real light changes. Indices into the weights array passed to
# blend_into(); the director owns the timing curves.
const CHANNEL_SKY: int = 0
const CHANNEL_SCENERY: int = 1
const CHANNEL_ICE: int = 2
const CHANNEL_ATMOSPHERE: int = 3
const CHANNEL_GAMEPLAY: int = 4
const CHANNEL_COUNT: int = 5

@export_group("Sky")
@export var sky_top: Color = Color(0.60, 0.72, 0.86)
@export var sky_mid: Color = Color(0.74, 0.83, 0.91)
@export var sky_horizon: Color = Color(0.88, 0.92, 0.96)
# Two extra stops, halfway through each of the segments above. Three stops can only produce a
# ramp that is straight between them, so a real sky -- which holds its deep blue over most of
# the frame and then turns hard near the horizon -- is not expressible. These let it BEND.
# Set to the exact midpoint of their neighbours, the result is identical to the 3-stop ramp,
# which is what most of the palettes do; only the evening ones bend.
@export var sky_upper: Color = Color(0.67, 0.775, 0.885)
@export var sky_lower: Color = Color(0.81, 0.875, 0.935)
# Left-to-right MULTIPLIERS over the whole vertical ramp, so the sky varies horizontally as
# well as vertically -- the other half of what makes the reference frames read as lit from
# somewhere. Multipliers rather than colours for the same reason the ice tints are: they can
# only ever darken, so they cannot push a channel past 1.0 on an LDR renderer. White is
# "no horizontal variation" and is the default.
#
# These are a WASH, not a light source: the bloom is SkyGlow's job. Authored to agree with it,
# warm on the side the glow sits and cool on the far side.
@export var sky_tint_left: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var sky_tint_right: Color = Color(1.0, 1.0, 1.0, 1.0)
# Where sky_mid sits between top and horizon. Past halfway keeps the pale band a horizon
# effect rather than a wash over the whole screen.
@export_range(0.05, 0.95) var sky_mid_offset: float = 0.58

# --- Directional glow -----------------------------------------------------------------
# A soft radial bloom over the gradient, at a point on screen. The reason it exists: the sky
# is a VERTICAL gradient, so without this every biome is lit uniformly from above and reads
# flat. The reference art's dawn and sunset frames are the same palette family as ours -- what
# separates them is that the light visibly comes from somewhere.
#
# Straight alpha, not additive. A warm bloom over a blue sky should pull the sky toward the
# warm hue, which is what an alpha blend does; additive pushes toward white and loses the hue
# the biome is named for. The Mobile renderer is LDR (components clamp at 1.0), so a bright
# glow is achieved by darkening what surrounds it, not by overbright -- same as the reference.
@export var glow_color: Color = Color(1.0, 0.92, 0.80, 1.0)
# Centre, in SCREEN fractions: (0,0) top-left, (1,1) bottom-right. Fractions rather than
# pixels because project.godot pins no viewport size and uses stretch/aspect="expand", so
# there is no pixel coordinate that means the same thing on two devices.
@export var glow_position: Vector2 = Vector2(0.5, 0.62)
# Half-extent, as a fraction of viewport width (x) and height (y). Two axes rather than one
# radius so the bloom can be a wide horizon wash rather than only ever a circle -- and so its
# shape is authored, not inherited from whatever aspect ratio the device happens to have.
@export var glow_radius: Vector2 = Vector2(0.55, 0.45)
# 0 hides the layer outright, which is the common case: a flat overcast biome wants no
# directional light at all and should not pay a full-screen alpha blend to say so.
@export_range(0.0, 1.0) var glow_strength: float = 0.0

# --- Sun / moon disc ------------------------------------------------------------------
# The light SOURCE, where the glow above is the light it casts. Authored at the same
# position as the glow so the two agree about where the light is coming from.
#
# NOT EVERY BIOME HAS ONE, and that is the point: a disc appearing in all eight would read as
# a decal rather than as weather. The four that do are the ones where you would actually see
# it -- a risen sun, a clear midday, a setting sun, a moon. The four that do not are the two
# overcast/hazy biomes, where cloud is the reason you cannot see it, and the two dusk biomes,
# where the sun has already gone below the horizon. Those are narrative beats, not omissions.
@export var celestial_color: Color = Color(1.0, 0.96, 0.88, 1.0)
@export var celestial_position: Vector2 = Vector2(0.5, 0.3)
# Radius of the SOLID disc, as a fraction of viewport HEIGHT. Height rather than width
# because it is the axis that reads as "how big in the sky"; and unlike the glow this is a
# real pixel size, because a sun has to be ROUND. Anchors are per-axis fractions, so anchoring
# a disc the way the glow is anchored would squash it by the aspect ratio -- 1.78:1 on a 16:9
# screen. The soft halo around it extends further, by CELESTIAL_HALO_SCALE.
@export_range(0.0, 0.2) var celestial_size: float = 0.03
# 0 means this biome has no disc at all, and skips the draw.
@export_range(0.0, 1.0) var celestial_strength: float = 0.0
# Crescent instead of a full disc. A sun and a moon that differ only in tint read as the same
# pale dot in play, so the shape carries it.
#
# This is the ONE field here that snaps rather than blends -- see blend_into(). That is safe
# only because no two ADJACENT biomes both have a disc, so celestial_strength is 0 somewhere in
# every transition that changes this and the swap happens while nothing is drawn. Authoring a
# second disc next to an existing one breaks that silently, which is why
# biome_schedule_check.gd asserts the no-adjacent-discs rule directly.
@export var celestial_is_moon: bool = false

@export_group("Scenery")
# Furthest parallax layer (depth_t 0) and nearest (depth_t 1); the layers in between
# interpolate. Under a pale sky far must be LIGHTER than near, under a dark sky darker --
# that inversion is the whole reason these are palette data and not constants.
@export var scenery_far: Color = Color(0.74, 0.81, 0.90)
@export var scenery_near: Color = Color(0.45, 0.56, 0.69)
# Same far/near split for the haze that veils each layer. Alpha is meaningful and is
# blended too: it is the mist-density difference between biomes.
@export var haze_far: Color = Color(0.88, 0.92, 0.96, 0.40)
@export var haze_near: Color = Color(0.85, 0.90, 0.95, 0.52)
# Multiplied over the foreground trees rooted in the terrain. White = the authored colours
# in ground_tree_spawner.gd; a dark biome pulls them down without needing four fields.
@export var tree_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var bird_tint: Color = Color(1.0, 1.0, 1.0, 1.0)

@export_group("Ice")
# Multipliers against the ice tile: at the surface line, and FILL_GRADIENT_DEPTH below it.
#
# THESE CARRY HUE, NOT BRIGHTNESS (changed 2026-08-08). The tile's V axis is now depth, so
# the tile itself owns the whole light-to-dark ramp -- it runs 1.0 at the surface down to
# ~0.52 at the gradient stop. If ice_depth is also much darker than ice_surface the two
# ramps multiply and deep ice goes black. So keep them at similar luminance and let them
# differ in HUE: pale and slightly desaturated at the surface, deeper and more saturated
# below, which is what the reference art actually does.
#
# ice_surface is also what makes the ride line read, now that the rim Line2Ds are gone: the
# tile's bright snow band is multiplied by it, so a dark ice_surface dims the one edge the
# player tracks. biome_schedule_check.gd enforces a floor on it.
@export var ice_surface: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var ice_depth: Color = Color(0.83, 0.88, 0.98, 1.0)
# The ice PATTERN for this biome, or null for terrain_generator.gd's default smooth tile.
# Only the biomes whose reference panel is not smooth set this, so six of the eight palettes
# leave it null rather than restating the default.
#
# THIS IS THE ONE FIELD blend_into() DOES NOT CARRY, and the reason is structural: a
# Polygon2D samples exactly one texture, so a crossfade between two tiles needs BOTH
# endpoints and the weight at once, which a single blended palette cannot express. So the
# director hands the pair straight to terrain_generator.apply_ice_palette(), which stacks two
# bands and dissolves between them. See docs/development/biomes.md.
#
# Was snapped at the midpoint of the ice channel until 2026-08-09 (option B), which left a
# hard vertical edge at the boundary chunk. Two separate things made that read badly: a
# brightness step, fixed in the tiles themselves, and the pattern break, fixed by the
# dissolve. Do not reintroduce a snap here.
#
# The variants must all share the default tile's depth ramp -- build_ice_texture.py enforces
# it and biome_schedule_check.gd gates it. During a dissolve BOTH tiles are on screen at
# once, so a ramp mismatch is now a brightness wobble across the whole view rather than a
# step at one seam.
@export var ice_texture: Texture2D = null
# How far the surface tint drifts warm/cool along the ride line, as a low-frequency function
# of world_x. Without it a whole screen of ice is exactly one colour, because ice_surface is
# written to every surface vertex identically -- the tile supplies texture but no colour
# variation at all, since it is greyscale.
#
# Surface row only: the depth row keeps ice_depth untouched, so the band still meets the flat
# deep fill at exactly the colour the fill uses and no seam appears at the bottom of the band.
# It is also the truer read -- patches are a surface phenomenon.
#
# 0 opts out, which is right for a biome whose ice should read as clean and uniform.
@export_range(0.0, 0.3) var ice_hue_variance: float = 0.0
# Snow settled on the ride line, as a band whose DEPTH varies with world_x.
#
# The tile already paints a snow band in its top rows, but the tile repeats every
# ICE_TILE_WORLD_WIDTH (1200px), so that band has the same profile forever. This one never
# repeats. It is a variable-depth geometric band, NOT the constant-width Line2D stroke that
# was removed in 2026-08-08 -- see the tombstone in terrain_generator.gd.
#
# 0 hides it outright, which is right for a biome whose ice should read as bare and swept.
@export var snow_cap_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 1.0) var snow_cap_strength: float = 0.0

@export_group("Atmosphere")
@export var snow_tint: Color = Color(1.0, 1.0, 1.0, 0.42)
# Scales how much of the particle pool emits. The pool is allocated once at its maximum,
# so this costs nothing to vary.
@export_range(0.0, 1.0) var snow_density_scale: float = 1.0

@export_group("Optional layers")
# Authored now, inert until each layer's own phase ships. A palette is complete data from
# day one; the renderers arrive one at a time. See docs/development/biomes.md.
@export_range(0.0, 1.0) var mist_strength: float = 0.0
@export_range(0.0, 1.0) var reflection_strength: float = 0.0
@export_range(0.0, 1.0) var star_density: float = 0.0

@export_group("Gameplay contrast")
# Phase 2. Coin and obstacle colours were tuned against a bright sky (visuals.md, "Why
# daylight"), so the dark biomes need their own values or they stop being readable.
# Unused until then; the defaults are today's shipped colours.
@export var coin_color: Color = Color(0.98, 0.82, 0.15, 1.0)
@export var obstacle_color: Color = Color(1.0, 0.1, 0.1, 1.0)


# Blends `from` toward `to` and writes the result into `out`, one weight per channel.
#
# Writes into a caller-owned instance rather than returning a new one: this runs every
# frame of a transition, inside every headless gate, and allocating a Resource per frame
# would be the one genuinely hot thing in the whole biome system.
static func blend_into(from: BiomePalette, to: BiomePalette, weights: PackedFloat32Array, out: BiomePalette) -> void:
	var sky: float = weights[CHANNEL_SKY]
	out.sky_top = from.sky_top.lerp(to.sky_top, sky)
	out.sky_mid = from.sky_mid.lerp(to.sky_mid, sky)
	out.sky_horizon = from.sky_horizon.lerp(to.sky_horizon, sky)
	out.sky_upper = from.sky_upper.lerp(to.sky_upper, sky)
	out.sky_lower = from.sky_lower.lerp(to.sky_lower, sky)
	out.sky_tint_left = from.sky_tint_left.lerp(to.sky_tint_left, sky)
	out.sky_tint_right = from.sky_tint_right.lerp(to.sky_tint_right, sky)
	out.sky_mid_offset = lerpf(from.sky_mid_offset, to.sky_mid_offset, sky)
	out.glow_color = from.glow_color.lerp(to.glow_color, sky)
	# Position and radius interpolate too, so the light SOURCE travels across the sky during a
	# transition rather than one bloom fading out while a second fades in somewhere else. When
	# either end has strength 0 the moving glow is invisible anyway, so this costs nothing in
	# the common case and is the whole effect in a dawn-to-sunset pair.
	out.glow_position = from.glow_position.lerp(to.glow_position, sky)
	out.glow_radius = from.glow_radius.lerp(to.glow_radius, sky)
	out.glow_strength = lerpf(from.glow_strength, to.glow_strength, sky)
	out.celestial_color = from.celestial_color.lerp(to.celestial_color, sky)
	# Position is interpolated even between a biome that has a disc and one that does not, so
	# the disc fades out where it stands instead of sliding across the sky on its way to a
	# position nobody authored. That only works because the disc-less palettes still author a
	# sensible celestial_position -- see their note.
	out.celestial_position = from.celestial_position.lerp(to.celestial_position, sky)
	out.celestial_size = lerpf(from.celestial_size, to.celestial_size, sky)
	out.celestial_strength = lerpf(from.celestial_strength, to.celestial_strength, sky)
	# Snaps at the halfway point: a bool cannot be interpolated, and the two textures cannot be
	# cross-dissolved without a second node. Safe only under the no-adjacent-discs rule, which
	# guarantees the disc is invisible whenever this value actually differs between endpoints.
	out.celestial_is_moon = to.celestial_is_moon if sky >= 0.5 else from.celestial_is_moon

	var scenery: float = weights[CHANNEL_SCENERY]
	out.scenery_far = from.scenery_far.lerp(to.scenery_far, scenery)
	out.scenery_near = from.scenery_near.lerp(to.scenery_near, scenery)
	out.haze_far = from.haze_far.lerp(to.haze_far, scenery)
	out.haze_near = from.haze_near.lerp(to.haze_near, scenery)
	out.tree_tint = from.tree_tint.lerp(to.tree_tint, scenery)
	out.bird_tint = from.bird_tint.lerp(to.bird_tint, scenery)

	var ice: float = weights[CHANNEL_ICE]
	out.ice_surface = from.ice_surface.lerp(to.ice_surface, ice)
	out.ice_depth = from.ice_depth.lerp(to.ice_depth, ice)
	out.ice_hue_variance = lerpf(from.ice_hue_variance, to.ice_hue_variance, ice)
	out.snow_cap_color = from.snow_cap_color.lerp(to.snow_cap_color, ice)
	out.snow_cap_strength = lerpf(from.snow_cap_strength, to.snow_cap_strength, ice)
	# ice_texture is deliberately NOT written -- see its note. A blended palette structurally
	# cannot express a pattern crossfade, which needs both endpoint tiles plus the weight, so
	# the director passes those three to terrain_generator.apply_ice_palette() alongside this
	# palette. Cleared rather than left holding the last run's value, so anything that reads
	# ice_texture off a BLENDED palette fails visibly instead of rendering something stale.
	out.ice_texture = null

	var atmosphere: float = weights[CHANNEL_ATMOSPHERE]
	out.snow_tint = from.snow_tint.lerp(to.snow_tint, atmosphere)
	out.snow_density_scale = lerpf(from.snow_density_scale, to.snow_density_scale, atmosphere)
	out.mist_strength = lerpf(from.mist_strength, to.mist_strength, atmosphere)
	out.reflection_strength = lerpf(from.reflection_strength, to.reflection_strength, atmosphere)
	out.star_density = lerpf(from.star_density, to.star_density, atmosphere)

	var gameplay: float = weights[CHANNEL_GAMEPLAY]
	out.coin_color = from.coin_color.lerp(to.coin_color, gameplay)
	out.obstacle_color = from.obstacle_color.lerp(to.obstacle_color, gameplay)


# The silhouette/haze colour for a layer at `depth_t` (0 = furthest, 1 = nearest).
func get_scenery_color(depth_t: float) -> Color:
	return scenery_far.lerp(scenery_near, depth_t)


func get_haze_color(depth_t: float) -> Color:
	return haze_far.lerp(haze_near, depth_t)
