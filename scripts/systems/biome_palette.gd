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
# Where sky_mid sits between top and horizon. Past halfway keeps the pale band a horizon
# effect rather than a wash over the whole screen.
@export_range(0.05, 0.95) var sky_mid_offset: float = 0.58

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
	out.sky_mid_offset = lerpf(from.sky_mid_offset, to.sky_mid_offset, sky)

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
