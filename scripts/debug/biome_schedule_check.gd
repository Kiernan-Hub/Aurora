extends SceneTree

# Biome validator: asserts the palette data and the transition schedule directly, with no
# physics, no player and no rendering. Physics-free by the same reasoning as
# terrain_invariant_check.gd -- every failure this can catch is a pure fact about numbers,
# so it should not need a game running to catch it.
#
# WHY THIS EXISTS AS A SEPARATE GATE. The other six gates run --headless, and
# biome_director.gd deliberately returns early under --headless having applied nothing
# (see its header). That is what makes it impossible for this pass to move a gate result
# -- and it is also what makes the six of them completely blind to every line of biome
# code. Without this file the biome system is untested by construction. Same gap
# docs/development/debugging.md records for powerups, which all six gates also disable.
#
# What it checks:
#   1. Every palette in the cycle loads, and every colour component is in [0, 1].
#   2. ice_surface stays bright in every biome, and ice_depth stays close to it. The first
#      is the read of "this is the edge you ride on"; the second stops the palette ramp and
#      the tile's own depth ramp multiplying deep ice down to black.
#   3. Far scenery stays separated from near scenery, so the depth read survives every
#      palette (the far/near lerp in BiomePalette.get_scenery_color assumes it).
#   4. The schedule is pure in world_x: same x always yields the same biome and progress,
#      progress stays in [0, 1], and the cycle wraps in both directions.
#   5. Channel weights are monotonic, land exactly on 0 and 1 at the window ends, and
#      genuinely lead/trail each other rather than all moving together.
#   6. Blending never produces an out-of-range colour, and never allocates -- blend_into
#      must write into the caller's instance.
#   7. Every ice_texture variant shares the default tile's depth ramp, so the two tiles on
#      screen together during a pattern dissolve agree about brightness (MAX_ICE_RAMP_DEVIATION).
#   8. blend_into never carries ice_texture, at any weight -- the pattern crossfade needs both
#      endpoint tiles and cannot ride on a single blended value.
#
# Usage:
#   godot --headless --path . --script res://scripts/debug/biome_schedule_check.gd
#   godot --headless --path . --script res://scripts/debug/biome_schedule_check.gd -- --steps=4000
#
# Exit code is 0 only if every check passes, so this is usable as a gate.

const DEFAULT_SCHEDULE_STEPS: int = 2000
# Sweep several full cycles, and start well before zero: world_x is signed and the
# background addresses negative space, so the wrap has to hold on both sides of the origin.
const SWEEP_START_MULTIPLE: float = -2.5
const SWEEP_END_MULTIPLE: float = 10.5

# ice_surface is what the player actually tracks the ride line by, now that the rim Line2Ds
# are gone (2026-08-08) and the tile's bright snow band is multiplied by this instead.
#
# LOWERED 0.70 -> 0.55 after seeing it rendered. 0.70 was set before any of this existed on
# screen, and it turned out to force ice_surface to be near-white -- which, multiplied by a
# GREYSCALE tile, can only ever produce grey ice. That was the whole reason the cold biomes
# read as grey rather than blue: brightness was being protected at the direct expense of the
# only thing carrying biome colour in the shallow band, which is most of what is on screen.
# 0.55 still leaves the lip the brightest thing in the darkest frame (starlit_night's sky
# horizon is ~0.52), because the tile's own top rows are ~0.97 before this multiplies them.
const MIN_ICE_SURFACE_LUMINANCE: float = 0.55
# The tile's V axis now carries the whole depth ramp (1.0 -> ~0.52). If ice_depth is also
# much darker than ice_surface the two ramps multiply and deep ice goes black, so these two
# must stay close in luminance and differ in hue instead. Generous bound -- this is here to
# catch a palette drifting back into "depth = darker", not to police art -- and relaxed
# 0.45 -> 0.55 for the same reason as the floor above: a night biome legitimately wants deep
# ice much darker than its surface, and the reference art's night panel does exactly that.
const MAX_ICE_DEPTH_DARKENING: float = 0.55
# Far and near scenery must differ by at least this much luminance or the parallax layers
# collapse into one flat mass and the depth cue is gone.
const MIN_SCENERY_SEPARATION: float = 0.08

# --- Gameplay contrast (coin_color / obstacle_color) ---------------------------------------
#
# These two are the only colours in a palette a player must READ, not just see, and at
# MAX_SPEED an obstacle is on screen for well under a second. A biome is therefore allowed to
# shift them and never to harmonise them: the failure this section exists to catch is a coin
# or an obstacle authored to sit nicely inside its biome's scheme, which is the same thing as
# authoring it to hide.
#
# MEASURED AS RGB DISTANCE, NOT LUMINANCE SEPARATION, which was the obvious first choice and
# is wrong here: the shipped gold (0.98,0.82,0.15) is luma 0.79 against pale_morning ice at
# 0.85 -- a coin that has always been perfectly readable would fail a luminance floor on the
# brightest biome in the game. What actually carries the read is hue, so the check has to be
# able to see hue. Straight euclidean distance over RGB is crude but it is the crudeness that
# makes it hard to game.
const MIN_GAMEPLAY_CONTRAST: float = 0.5
# The backgrounds each is realistically seen against: the ride surface and the deep band
# under it, plus the sky at the horizon, which is what a glide coin and a jumped obstacle are
# silhouetted against. sky_top is deliberately absent -- nothing gameplay-carrying is ever up
# there. Variant ice colours are folded in by the check itself when a biome has them.
const GAMEPLAY_CONTRAST_BACKGROUNDS: Array[String] = ["ice_surface", "ice_depth", "sky_horizon"]
# A coin stays warm and an obstacle stays danger-coloured in EVERY biome, however far the
# biome shifts them. Both bounds are loose on purpose -- they are here to catch a coin drifting
# green under glacier_teal or an obstacle drifting violet under violet_dusk, not to pick the
# colour. The coin's is red-over-blue rather than a floor on red, because sunset_rose's coin is
# a deep amber -- against a warm sky the readable move is DARKER, not brighter -- and a floor on
# red would rule that out while still passing a green coin.
const MIN_COIN_RED_OVER_BLUE: float = 0.4
const MIN_OBSTACLE_RED_DOMINANCE: float = 0.35
# Float slop on smoothstep endpoints and colour lerps.
const EPSILON: float = 0.0005
# Every variant is built by scripts/tools/build_ice_texture.py at its OUTPUT_SIZE.
const EXPECTED_ICE_TILE_SIZE: int = 1024
# Catches EVERY variant vanishing at once -- a moved assets/ directory, a bad merge, a
# renamed file -- which is the realistic failure mode, since a null ice_texture is a legal
# value meaning "use the smooth tile". Deliberately not pinned to the exact count, so
# adding a variant does not also require editing this gate.
const MIN_ICE_VARIANTS: int = 1

# The tile every biome without a variant uses, and therefore the depth ramp all the variants
# have to agree with. Referenced through TerrainGenerator rather than re-preloaded so there
# is one path in the project, not two.
const DEFAULT_ICE_TILE: Texture2D = TerrainGenerator.ICE_TERRAIN_TEXTURE
# How far a variant's per-row mean brightness may drift from the default tile's, averaged
# over the sampled rows.
#
# WHY THIS IS A GATE. A biome swaps its tile one 512px chunk at a time, so there is a live
# vertical boundary in game with the old tile on one side and the new one on the other. Both
# are MULTIPLIERS, so if they disagree about how bright ice is at a given depth, that
# boundary is a flat brightness step and reads as a hard cutoff whatever the patterns do.
# build_ice_texture.py rescales every variant onto this ramp automatically -- but a tile
# rebuilt by any other route, or hand-edited, looks completely correct as a resource and
# loses that silently. Measured: the two matched variants sit at 0.002 and 0.004, while the
# unmatched faceted tile this replaced was ~0.10 (0.86 at the ride line against the default's
# 0.98). So this is set with ~5x headroom over a matched tile and ~5x under an unmatched one.
const MAX_ICE_RAMP_DEVIATION: float = 0.02
# The mismatch this catches is a whole-tile ramp disagreement, not a per-pixel one, so the
# comparison subsamples hard. A full 1024x1024 walk in GDScript would cost more than the rest
# of the gate put together and tell it nothing more.
const ICE_RAMP_ROW_STRIDE: int = 16
const ICE_RAMP_COLUMN_STRIDE: int = 8
# Steps across the ice channel's weight when checking that no pattern snap has crept back in.
# Swept rather than probed at the ends because a snap fires in the middle.
const ICE_CROSSFADE_PROBE_STEPS: int = 64

var failures: Array[String] = []
var ice_variant_count: int = 0


func _init() -> void:
	var schedule_steps: int = get_int_argument("--steps", DEFAULT_SCHEDULE_STEPS)

	check_palettes()
	if ice_variant_count < MIN_ICE_VARIANTS:
		failures.append("no palette resolved an ice_texture (expected at least %d) -- every pattern variant is missing, so the whole cycle silently fell back to the smooth tile"
			% MIN_ICE_VARIANTS)
	check_schedule_purity(schedule_steps)
	check_phase_offset()
	check_channel_curves()
	check_blending()

	print("")
	if failures.is_empty():
		print("BIOME_CHECK PASS  palettes=", BiomeDirector.BIOME_CYCLE.size(),
			" biome_distance=", BiomeDirector.BIOME_DISTANCE,
			" transition=", BiomeDirector.TRANSITION_DISTANCE,
			" ice_variants=", ice_variant_count,
			" steps=", schedule_steps)
		quit(0)
		return

	print("BIOME_CHECK FAIL  ", failures.size(), " violation(s)")
	for failure: String in failures:
		print("    ", failure)
	quit(1)


# BIOME_CYCLE plus the opening biome, which is deliberately NOT in the cycle (see
# BiomeDirector.PALETTE_FIRST_LIGHT). Every per-palette check below has to walk this rather
# than the cycle, or the one palette a player is guaranteed to see is the one palette
# nothing validates.
func get_all_palettes() -> Array[BiomePalette]:
	var all_palettes: Array[BiomePalette] = [BiomeDirector.PALETTE_FIRST_LIGHT]
	all_palettes.append_array(BiomeDirector.BIOME_CYCLE)
	return all_palettes


func check_palettes() -> void:
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	if cycle.is_empty():
		failures.append("BIOME_CYCLE is empty")
		return
	if BiomeDirector.PALETTE_FIRST_LIGHT == null:
		failures.append("PALETTE_FIRST_LIGHT failed to load -- the opening biome resolves to null and index 0 draws nothing")
		return
	# The intro replaces index 0 on the first pass, and the palette that follows it -- slot 1 of
	# a shuffled order -- can now be ANY of the eight. So the intro's tile has to differ from
	# all of them, not just from the one that used to sit there: a shared tile reads as the
	# pattern never changing across the opening transition, which is the one transition every
	# session plays.
	for palette_index: int in range(cycle.size()):
		if BiomeDirector.PALETTE_FIRST_LIGHT.ice_texture == cycle[palette_index].ice_texture:
			failures.append("first_light shares an ice_texture with %s, which the shuffle can put directly after it -- the opening biome is meant to be visibly quieter than whatever follows it"
				% cycle[palette_index].resource_path.get_file().get_basename())

	var palettes: Array[BiomePalette] = get_all_palettes()
	for palette_index: int in range(palettes.size()):
		var palette: BiomePalette = palettes[palette_index]
		if palette == null:
			failures.append("palette %d failed to load" % palette_index)
			continue
		var label: String = "first_light" if palette_index == 0 else "palette[%d]" % (palette_index - 1)

		for field_name: String in [
			"sky_top", "sky_mid", "sky_horizon", "glow_color", "celestial_color",
			"scenery_far", "scenery_near", "haze_far", "haze_near",
			"tree_tint", "bird_tint",
			"ice_surface", "ice_depth",
			"snow_tint", "coin_color", "obstacle_color",
		]:
			assert_color_in_range(label + "." + field_name, palette.get(field_name))

		check_glow_authoring(label, palette)
		check_glow_layout(label, palette)
		check_celestial_authoring(label, palette)
		check_celestial_layout(label, palette)
		check_star_authoring(label, palette)
		check_gameplay_contrast(label, palette)

		var surface_luminance: float = get_luminance(palette.ice_surface)
		if surface_luminance < MIN_ICE_SURFACE_LUMINANCE:
			failures.append("%s.ice_surface too dark (%.3f < %.3f) -- it multiplies the tile's snow band, so the ride line stops reading"
				% [label, surface_luminance, MIN_ICE_SURFACE_LUMINANCE])

		var depth_luminance: float = get_luminance(palette.ice_depth)
		if depth_luminance < surface_luminance * (1.0 - MAX_ICE_DEPTH_DARKENING):
			failures.append("%s.ice_depth much darker than ice_surface (%.3f vs %.3f) -- it multiplies with the tile's own depth ramp and deep ice goes black"
				% [label, depth_luminance, surface_luminance])

		var separation: float = absf(get_luminance(palette.scenery_far) - get_luminance(palette.scenery_near))
		if separation < MIN_SCENERY_SEPARATION:
			failures.append("%s scenery_far/near separation %.3f < %.3f -- parallax depth collapses"
				% [label, separation, MIN_SCENERY_SEPARATION])

		# ice_texture is allowed to be null (= the default smooth tile), so a .tres whose
		# ExtResource path went stale resolves to null and looks EXACTLY like a palette that
		# never wanted a variant. Nothing else in the project would notice: the six physics
		# gates disable the biome system outright, and in game the biome would simply keep
		# the smooth tile. Counted here so a silent loss of every variant is visible in the
		# PASS line rather than being something someone eventually notices by eye.
		if palette.ice_texture != null:
			ice_variant_count += 1
			if palette.ice_texture.get_size() != Vector2(EXPECTED_ICE_TILE_SIZE, EXPECTED_ICE_TILE_SIZE):
				failures.append("%s.ice_texture is %s, expected %dx%d -- a differently sized tile changes how fast the pattern repeats relative to the others"
					% [label, palette.ice_texture.get_size(), EXPECTED_ICE_TILE_SIZE, EXPECTED_ICE_TILE_SIZE])
			else:
				check_ice_ramp_matches_default(label, palette.ice_texture)

		# A rare variant's tile goes on screen next to a neighbouring biome's exactly as the
		# base tile does, so it is subject to the same size and depth-ramp rules. Checked
		# separately because it never appears in palette.ice_texture -- the roll happens in the
		# director, and this loop only ever sees the authored base.
		if palette.variant_ice_texture != null:
			if palette.variant_ice_texture.get_size() != Vector2(EXPECTED_ICE_TILE_SIZE, EXPECTED_ICE_TILE_SIZE):
				failures.append("%s.variant_ice_texture is %s, expected %dx%d -- a differently sized tile changes how fast the pattern repeats relative to the others"
					% [label, palette.variant_ice_texture.get_size(), EXPECTED_ICE_TILE_SIZE, EXPECTED_ICE_TILE_SIZE])
			else:
				check_ice_ramp_matches_default(label + " variant", palette.variant_ice_texture)


# The directional glow is placed by ANCHOR, in screen fractions -- sky_backdrop.position_glow().
# Anchors outside [0,1] are legal to Godot and will happily lay out a rect that is entirely
# off screen, so a typo here is not a crash and not a visible error either: it is a biome that
# quietly has no glow. These bounds are deliberately loose rather than [0,1], because a bloom
# hanging PARTLY off the edge is the normal case and the good-looking one (that is how a light
# source sits just past the frame). What they catch is a value in the wrong unit entirely --
# pixels instead of fractions, or a degrees/percent mix-up.
const MIN_GLOW_ANCHOR: float = -1.0
const MAX_GLOW_ANCHOR: float = 2.0
# Below this the layer is drawn but contributes nothing a player could see, which is almost
# certainly a mistake -- 0 exactly is the supported way to say "this biome has no directional
# light", and it skips the draw entirely.
const MIN_MEANINGFUL_GLOW_STRENGTH: float = 0.02


# Split from check_glow_layout deliberately. These two are AUTHORING rules -- they describe
# what a human may write in a .tres -- and neither is a valid thing to assert about a blended
# palette, because a crossfade legitimately passes through values no author would ever type.
# glow_strength is the sharp case: 0 is the documented way to say "this biome has no
# directional light", so every transition into or out of such a biome sweeps the whole range
# below MIN_MEANINGFUL_GLOW_STRENGTH on its way up. Running this check on blends would fail
# the gate for correct data. (It does not fire today only because no palette currently uses
# 0 -- caught by negative-testing this gate rather than by it passing.)
func check_glow_authoring(label: String, palette: BiomePalette) -> void:
	if palette.glow_radius.x <= 0.0 or palette.glow_radius.y <= 0.0:
		failures.append("%s.glow_radius %s has a non-positive axis -- the rect collapses and the bloom vanishes"
			% [label, palette.glow_radius])
	if palette.glow_strength > 0.0 and palette.glow_strength < MIN_MEANINGFUL_GLOW_STRENGTH:
		failures.append("%s.glow_strength %.4f is nonzero but invisible -- use exactly 0 to disable the glow, which also skips the draw"
			% [label, palette.glow_strength])


# Safe to assert about an authored palette AND a blended one: the anchors are a convex
# combination of the endpoints', so if both ends lay out on screen every frame between them
# does too -- and if one end does not, this catches it at both the endpoint and the blend.
func check_glow_layout(label: String, palette: BiomePalette) -> void:
	# Only the extremes need checking: the rect is the box between them, so if both corners are
	# in range every anchor derived from them is too.
	var anchors: Array[float] = [
		palette.glow_position.x - palette.glow_radius.x,
		palette.glow_position.x + palette.glow_radius.x,
		palette.glow_position.y - palette.glow_radius.y,
		palette.glow_position.y + palette.glow_radius.y,
	]
	for anchor: float in anchors:
		if anchor < MIN_GLOW_ANCHOR or anchor > MAX_GLOW_ANCHOR:
			failures.append("%s glow anchor %.3f outside [%.1f, %.1f] (position %s, radius %s) -- these are SCREEN FRACTIONS, not pixels; off-screen anchors lay out silently and the biome just has no glow"
				% [label, anchor, MIN_GLOW_ANCHOR, MAX_GLOW_ANCHOR, palette.glow_position, palette.glow_radius])
			return


# The disc is laid out in PIXELS around an anchored centre point (sky_backdrop.layout_celestial),
# so unlike the glow only its centre is a screen fraction. A disc is a body you are meant to
# SEE, not a wash that reads fine hanging off an edge, so this is tighter than the glow's
# bounds -- but still allows a little overhang for a sun sitting partly out of frame.
const MIN_CELESTIAL_POSITION: float = -0.2
const MAX_CELESTIAL_POSITION: float = 1.2
const MIN_MEANINGFUL_CELESTIAL_STRENGTH: float = 0.02
# Stars fade by alpha, so the dead range is a little wider than the other two layers'.
const MIN_MEANINGFUL_STAR_DENSITY: float = 0.05
# How far a disc may sit from where its neighbour parks celestial_position, in screen
# fractions, before the fade-in reads as travel rather than as an appearance. Small: the point
# is that they should be identical, and this is only slack for authoring noise. Taken from the
# director rather than restated, because the shuffle enforces the same number when it builds a
# session's order and the two drifting apart would make this gate pass what the game rejects.
const MAX_DISC_DRIFT: float = BiomeDirector.MAX_DISC_DRIFT


# Authoring rules only -- see check_glow_authoring for why these must never run against a
# blended palette.
func check_celestial_authoring(label: String, palette: BiomePalette) -> void:
	if palette.celestial_strength <= 0.0:
		return
	if palette.celestial_size <= 0.0:
		failures.append("%s.celestial_size is %.4f but celestial_strength is %.2f -- a disc with no radius draws nothing; set strength to 0 to say this biome has no disc"
			% [label, palette.celestial_size, palette.celestial_strength])
	if palette.celestial_strength < MIN_MEANINGFUL_CELESTIAL_STRENGTH:
		failures.append("%s.celestial_strength %.4f is nonzero but invisible -- use exactly 0 to disable the disc, which also skips the draw"
			% [label, palette.celestial_strength])


# Same authoring-only rule as the other two layers: 0 is how a biome says "no stars", and
# anything between 0 and the floor is a value that draws a layer nobody can see. The pixel
# floor lives in sky_layer_check.gd; this only catches the obviously-dead range.
func check_star_authoring(label: String, palette: BiomePalette) -> void:
	if palette.star_density > 0.0 and palette.star_density < MIN_MEANINGFUL_STAR_DENSITY:
		failures.append("%s.star_density %.4f is nonzero but invisible -- use exactly 0 to disable the starfield, which also skips the draw"
			% [label, palette.star_density])


# The coin and the obstacle have to stay readable in every biome, against everything they are
# realistically seen against. See MIN_GAMEPLAY_CONTRAST for why this is measured as an RGB
# distance and not as a luminance separation.
#
# Only the AUTHORED endpoints are checked, not the blend between them. That is sound because
# the check is a distance from a background that is itself interpolating on the same
# transition: both endpoints clearing the floor against their own backgrounds does not
# strictly prove every frame between them does, but a mid-transition frame is at most a few
# seconds long and no palette pair in the project comes close to the floor.
func check_gameplay_contrast(label: String, palette: BiomePalette) -> void:
	var backgrounds: Array[String] = GAMEPLAY_CONTRAST_BACKGROUNDS.duplicate()
	# A rare variant repaints the ice under a coin that is unchanged, so it is a background
	# these two are seen against exactly like the base ice is.
	if palette.variant_chance > 0.0:
		for variant_field: String in ["variant_ice_surface", "variant_ice_depth"]:
			if (palette.get(variant_field) as Color).a > 0.0:
				backgrounds.append(variant_field)

	for gameplay_field: String in ["coin_color", "obstacle_color"]:
		var gameplay_color: Color = palette.get(gameplay_field) as Color
		for background_field: String in backgrounds:
			var background_color: Color = palette.get(background_field) as Color
			var contrast: float = get_color_distance(gameplay_color, background_color)
			if contrast < MIN_GAMEPLAY_CONTRAST:
				failures.append("%s.%s is only %.3f from %s (< %.3f) -- it harmonises with the biome instead of reading against it, and this is one of the two colours a player has to read at 750 px/s"
					% [label, gameplay_field, contrast, background_field, MIN_GAMEPLAY_CONTRAST])

	var coin: Color = palette.coin_color
	if coin.r - coin.b < MIN_COIN_RED_OVER_BLUE or coin.g <= coin.b:
		failures.append("%s.coin_color (%.2f, %.2f, %.2f) has stopped reading as warm gold -- a biome may shift the coin, never recolour it"
			% [label, coin.r, coin.g, coin.b])

	var obstacle: Color = palette.obstacle_color
	if obstacle.r - maxf(obstacle.g, obstacle.b) < MIN_OBSTACLE_RED_DOMINANCE:
		failures.append("%s.obstacle_color (%.2f, %.2f, %.2f) has stopped reading as the danger colour -- red must dominate in every biome"
			% [label, obstacle.r, obstacle.g, obstacle.b])


# Euclidean over RGB. Alpha is ignored: every colour these compare is opaque.
func get_color_distance(first: Color, second: Color) -> float:
	return Vector3(first.r - second.r, first.g - second.g, first.b - second.b).length()


# Safe against authored and blended palettes alike: the centre is a convex combination of the
# endpoints', so if both ends are on screen so is every frame between them.
func check_celestial_layout(label: String, palette: BiomePalette) -> void:
	for axis: int in range(2):
		var coordinate: float = palette.celestial_position[axis]
		if coordinate < MIN_CELESTIAL_POSITION or coordinate > MAX_CELESTIAL_POSITION:
			failures.append("%s.celestial_position%s = %.3f outside [%.1f, %.1f] -- this is a SCREEN FRACTION, and a disc this far out is off frame entirely"
				% [label, ".x" if axis == 0 else ".y", coordinate, MIN_CELESTIAL_POSITION, MAX_CELESTIAL_POSITION])
			return


# See MAX_ICE_RAMP_DEVIATION for why a variant is required to share the default tile's
# light-to-dark ramp: the chunk boundary during a biome change is a live seam between the two
# tiles, and a ramp disagreement renders there as a brightness step.
func check_ice_ramp_matches_default(label: String, variant_texture: Texture2D) -> void:
	var reference_rows: PackedFloat32Array = sample_row_brightness(DEFAULT_ICE_TILE)
	var variant_rows: PackedFloat32Array = sample_row_brightness(variant_texture)
	if reference_rows.is_empty() or variant_rows.size() != reference_rows.size():
		failures.append("%s.ice_texture could not be compared against the default tile (%d vs %d sampled rows)"
			% [label, variant_rows.size(), reference_rows.size()])
		return

	var total_deviation: float = 0.0
	var worst_deviation: float = 0.0
	for row_index: int in range(reference_rows.size()):
		var deviation: float = absf(variant_rows[row_index] - reference_rows[row_index])
		total_deviation += deviation
		worst_deviation = maxf(worst_deviation, deviation)
	var mean_deviation: float = total_deviation / float(reference_rows.size())

	if mean_deviation > MAX_ICE_RAMP_DEVIATION:
		failures.append("%s.ice_texture's depth ramp is %.3f off the default tile's (max %.3f, worst row %.3f) -- rebuild it through scripts/tools/build_ice_texture.py, which matches the ramp automatically; unmatched, the chunk boundary at a biome change is a visible brightness step"
			% [label, mean_deviation, MAX_ICE_RAMP_DEVIATION, worst_deviation])


# Mean brightness of every ICE_RAMP_ROW_STRIDE-th row. The tiles are greyscale, so the red
# channel alone is the value -- and the tile's V axis is depth below the ride surface, so
# this array IS its depth ramp.
func sample_row_brightness(texture: Texture2D) -> PackedFloat32Array:
	var image: Image = texture.get_image()
	if image == null:
		return PackedFloat32Array()
	# An imported texture can arrive VRAM-compressed depending on the import preset, and
	# get_pixel() is not valid on a compressed Image.
	if image.is_compressed() and image.decompress() != OK:
		return PackedFloat32Array()

	var row_brightness: PackedFloat32Array = PackedFloat32Array()
	for y: int in range(0, image.get_height(), ICE_RAMP_ROW_STRIDE):
		var row_total: float = 0.0
		var sample_count: int = 0
		for x: int in range(0, image.get_width(), ICE_RAMP_COLUMN_STRIDE):
			row_total += image.get_pixel(x, y).r
			sample_count += 1
		row_brightness.append(row_total / float(sample_count))
	return row_brightness


# The whole reason the schedule is keyed on distance rather than a clock: it must be a pure
# function, so the same world_x always describes the same sky. Checked by evaluating the
# sweep twice and requiring bit-identical results, then again out of order.
func check_schedule_purity(schedule_steps: int) -> void:
	var biome_distance: float = BiomeDirector.BIOME_DISTANCE
	var start_x: float = biome_distance * SWEEP_START_MULTIPLE
	var end_x: float = biome_distance * SWEEP_END_MULTIPLE
	var step: float = (end_x - start_x) / float(maxi(schedule_steps, 1))

	var forward_progress: PackedFloat64Array = PackedFloat64Array()
	var forward_index: PackedInt32Array = PackedInt32Array()

	for sample_index: int in range(schedule_steps + 1):
		var world_x: float = start_x + (float(sample_index) * step)
		var biome_index: int = get_biome_index(world_x)
		var progress: float = get_transition_progress(world_x)

		if progress < -EPSILON or progress > 1.0 + EPSILON:
			failures.append("progress %.6f out of [0,1] at world_x=%.1f" % [progress, world_x])
		if BiomeDirector.BIOME_CYCLE[posmod(biome_index, BiomeDirector.BIOME_CYCLE.size())] == null:
			failures.append("cycle index %d resolves to null at world_x=%.1f" % [biome_index, world_x])

		forward_progress.append(progress)
		forward_index.append(biome_index)

	# Backwards, so any hidden per-call state (a cached index, a "last biome") shows up as a
	# mismatch rather than passing because the sweep happened to be monotonic.
	for sample_index: int in range(schedule_steps, -1, -1):
		var world_x: float = start_x + (float(sample_index) * step)
		if get_biome_index(world_x) != forward_index[sample_index]:
			failures.append("biome index not pure in world_x at %.1f" % world_x)
			break
		if absf(get_transition_progress(world_x) - forward_progress[sample_index]) > 0.0:
			failures.append("transition progress not pure in world_x at %.1f" % world_x)
			break

	# Every biome in the cycle must actually be reached over a sweep this long, or a palette
	# is authored but unreachable.
	var seen: Dictionary[int, bool] = {}
	for biome_index: int in forward_index:
		seen[posmod(biome_index, BiomeDirector.BIOME_CYCLE.size())] = true
	if seen.size() != BiomeDirector.BIOME_CYCLE.size():
		failures.append("only %d of %d biomes reachable over the sweep"
			% [seen.size(), BiomeDirector.BIOME_CYCLE.size()])


# The session biome phase (BiomeDirector.session_biome_phase) is added to world_x before the
# cycle maths, so a run resumes where the last one in this sitting died. Three claims, none
# of which the sweep above can see because it drives the pure function directly:
#
#   1. Both the static and the instance copy default to 0. That is what keeps every OTHER
#      check in this file independent of the phase, and what makes a fresh launch open on
#      BIOME_CYCLE[0] -- the deliberate first impression.
#   2. The offset shifts the schedule by exactly itself -- one BIOME_DISTANCE of phase means
#      exactly one biome further along, not "roughly".
#   3. get_persisted_phase() folds into one cycle. Without the fposmod it is an accumulator
#      that grows by a run's distance on every death, and a long sitting of short runs
#      compounds it until float precision starts quantising the cycle position.
func check_phase_offset() -> void:
	var director: BiomeDirector = BiomeDirector.new()
	var biome_distance: float = BiomeDirector.BIOME_DISTANCE
	var cycle_length: float = biome_distance * float(BiomeDirector.BIOME_CYCLE.size())

	if absf(BiomeDirector.session_biome_phase) > EPSILON:
		failures.append("BiomeDirector.session_biome_phase starts at %.3f, not 0 -- a fresh launch would not open on BIOME_CYCLE[0]"
			% BiomeDirector.session_biome_phase)
	if absf(director.biome_phase_offset) > EPSILON:
		failures.append("BiomeDirector.biome_phase_offset defaults to %.3f, not 0 -- every gate in this file would then depend on it"
			% director.biome_phase_offset)

	# Claim 2, at a few positions including one inside a transition window.
	for start_multiple: float in [0.0, 0.25, 0.97, 3.5]:
		var world_x: float = biome_distance * start_multiple
		var shifted_index: int = get_biome_index(world_x + biome_distance)
		if shifted_index != get_biome_index(world_x) + 1:
			failures.append("a phase offset of one BIOME_DISTANCE moved the schedule to index %d, not %d, at world_x=%.1f"
				% [shifted_index, get_biome_index(world_x) + 1, world_x])
		if absf(get_transition_progress(world_x + biome_distance) - get_transition_progress(world_x)) > EPSILON:
			failures.append("a phase offset of one BIOME_DISTANCE changed transition progress at world_x=%.1f -- the shift is not a whole biome"
				% world_x)

	# Claim 3, and it is the one that keeps the opening biome a one-shot. The phase must NEVER
	# fold back toward 0: if it did, absolute index 0 would come around again and the intro
	# would replay mid-session. Checked as strict monotonicity in world_x, plus the specific
	# case that broke the earlier fposmod version -- a run longer than a full cycle.
	for stored_phase: float in [0.0, cycle_length * 0.6]:
		director.biome_phase_offset = stored_phase
		var previous_phase: float = -1.0
		for world_x: float in [0.0, 1234.5, cycle_length, cycle_length * 7.3]:
			var phase: float = director.get_persisted_phase(world_x)
			if not is_finite(phase) or phase < 0.0:
				failures.append("get_persisted_phase(%.1f) with offset %.1f returned %.3f -- a phase must be finite and non-negative"
					% [world_x, stored_phase, phase, ])
			if phase < previous_phase:
				failures.append("get_persisted_phase went BACKWARDS (%.1f -> %.1f) by world_x=%.1f with offset %.1f -- the opening biome would replay once the phase wrapped past index 0"
					% [previous_phase, phase, world_x, stored_phase])
			previous_phase = phase
	director.free()

	# Claim 4: the intro occupies absolute index 0 and nothing else, so every later lap
	# through that slot resolves to the real BIOME_CYCLE[0]. This is the whole feature in
	# two assertions.
	var live_director: BiomeDirector = BiomeDirector.new()
	if live_director.get_cycle_base_palette(0) != BiomeDirector.PALETTE_FIRST_LIGHT:
		failures.append("cycle index 0 is not first_light -- the opening biome never plays")
	# Which palette occupies the intro's slot on later laps depends on this session's rotation,
	# so the assertion is against that rather than against BIOME_CYCLE[0].
	var cycle_size: int = BiomeDirector.BIOME_CYCLE.size()
	var slot_zero: BiomePalette = BiomeDirector.BIOME_CYCLE[posmod(BiomeDirector.get_session_cycle_rotation(), cycle_size)]
	for lap: int in [1, 2, 5]:
		var wrapped_index: int = lap * cycle_size
		if live_director.get_cycle_base_palette(wrapped_index) != slot_zero:
			failures.append("cycle index %d does not resolve to this session's slot 0 (%s) -- the intro is recurring instead of being a one-shot"
				% [wrapped_index, slot_zero.resource_path.get_file().get_basename()])
	live_director.free()


func check_channel_curves() -> void:
	var director: BiomeDirector = BiomeDirector.new()

	for channel_index: int in range(BiomePalette.CHANNEL_COUNT):
		var previous_weight: float = -1.0
		for step_index: int in range(101):
			var progress: float = float(step_index) / 100.0
			var weight: float = director.get_channel_weight(channel_index, progress)
			if weight < -EPSILON or weight > 1.0 + EPSILON:
				failures.append("channel %d weight %.6f out of [0,1] at progress %.2f"
					% [channel_index, weight, progress])
			if weight < previous_weight - EPSILON:
				failures.append("channel %d weight decreased at progress %.2f" % [channel_index, progress])
			previous_weight = weight

		# Both ends must LAND, not merely approach: a channel that is still at 0.98 when the
		# window closes leaves a permanent colour error that accumulates across biomes.
		if absf(director.get_channel_weight(channel_index, 0.0)) > EPSILON:
			failures.append("channel %d does not start at 0" % channel_index)
		if absf(director.get_channel_weight(channel_index, 1.0) - 1.0) > EPSILON:
			failures.append("channel %d does not finish at 1" % channel_index)

	# The point of five channels is that they are offset. If they ever collapse onto one
	# curve this is a plain crossfade wearing a more complicated implementation, so assert
	# the spread is real: at the midpoint the leading and trailing channels must differ.
	var mid_weights: Array[float] = []
	for channel_index: int in range(BiomePalette.CHANNEL_COUNT):
		mid_weights.append(director.get_channel_weight(channel_index, 0.5))
	var spread: float = mid_weights.max() - mid_weights.min()
	if spread < 0.10:
		failures.append("channel curves nearly identical at mid-transition (spread %.3f) -- the staggered fade is doing nothing" % spread)

	director.free()


func check_blending() -> void:
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	var out: BiomePalette = BiomePalette.new()
	var out_id: int = out.get_instance_id()
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(BiomePalette.CHANNEL_COUNT)

	for cycle_index: int in range(cycle.size()):
		var from_palette: BiomePalette = cycle[cycle_index]
		var to_palette: BiomePalette = cycle[(cycle_index + 1) % cycle.size()]
		for step_index: int in range(21):
			var progress: float = float(step_index) / 20.0
			for channel_index: int in range(BiomePalette.CHANNEL_COUNT):
				weights[channel_index] = progress
			BiomePalette.blend_into(from_palette, to_palette, weights, out)

			# blend_into runs every frame of every transition; allocating a Resource there
			# would be the one genuinely hot thing in the whole biome system.
			if out.get_instance_id() != out_id:
				failures.append("blend_into replaced the output instance -- it is allocating per call")
				return

			var label: String = "blend[%d->%d]@%.2f" % [cycle_index, (cycle_index + 1) % cycle.size(), progress]
			for field_name: String in ["sky_top", "sky_mid", "sky_horizon", "glow_color", "celestial_color",
				"scenery_far", "scenery_near", "haze_far", "haze_near", "ice_surface", "ice_depth",
				"snow_tint", "tree_tint", "bird_tint"]:
				assert_color_in_range(label + "." + field_name, out.get(field_name))
			# The blended glow has to be layout-safe too, not just in-range as a colour: it is fed
			# straight to sky_backdrop.position_glow() on every frame of the transition, and a
			# mid-transition value is the one no endpoint check ever looks at.
			check_glow_layout(label, out)
			check_celestial_layout(label, out)

	# The endpoints must be exact, not merely close: at weight 0 the blend IS the source
	# palette, otherwise every biome shows a slightly wrong colour for its whole duration.
	for channel_index: int in range(BiomePalette.CHANNEL_COUNT):
		weights[channel_index] = 0.0
	BiomePalette.blend_into(cycle[0], cycle[1], weights, out)
	if not out.sky_top.is_equal_approx(cycle[0].sky_top) or not out.ice_surface.is_equal_approx(cycle[0].ice_surface):
		failures.append("blend at weight 0 does not reproduce the source palette")

	for channel_index: int in range(BiomePalette.CHANNEL_COUNT):
		weights[channel_index] = 1.0
	BiomePalette.blend_into(cycle[0], cycle[1], weights, out)
	if not out.sky_top.is_equal_approx(cycle[1].sky_top) or not out.ice_surface.is_equal_approx(cycle[1].ice_surface):
		failures.append("blend at weight 1 does not reproduce the destination palette")

	check_blend_carries_fields()
	check_no_adjacent_discs()
	check_disc_positions_are_stationary()
	check_opening_seam()
	check_arc_order_is_preserved()
	check_ice_pattern_crossfade()


# THE INVARIANT THAT MAKES THE SUN/MOON TEXTURE SWAP SAFE. celestial_is_moon is a bool, so it
# cannot be interpolated, and sky_backdrop swaps the texture outright rather than dissolving
# between two stacked nodes the way the ice pattern has to. That is only invisible because
# celestial_strength is 0 at one end of every transition -- i.e. no two ADJACENT biomes both
# have a disc. Author a second disc next to an existing one and the swap becomes a visible pop
# in the middle of the fade, with nothing else in this file noticing.
#
# WALKING BIOME_CYCLE IS STILL THE RIGHT TEST. A session rotates the arc rather than reordering
# it (BiomeDirector.session_cycle_rotation), so every pair the game can ever show is a pair of
# neighbours in this array -- rotation preserves adjacency. The one pair rotation DOES change is
# the opening seam, first_light -> whatever lands at index 1, which check_opening_seam covers.
func check_no_adjacent_discs() -> void:
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	for cycle_index: int in range(cycle.size()):
		var here: BiomePalette = cycle[cycle_index]
		var next: BiomePalette = cycle[(cycle_index + 1) % cycle.size()]
		if here.celestial_strength > 0.0 and next.celestial_strength > 0.0:
			failures.append("%s and %s are adjacent and BOTH have a disc -- celestial_is_moon snaps at the midpoint of the transition, so the sun/moon texture would swap while both are visible. Either drop one disc or give SkyCelestial the two-node dissolve treatment the ice band has"
				% [here.resource_path.get_file().get_basename(), next.resource_path.get_file().get_basename()])


# A disc-less biome still has a celestial_position, and it is not decoration: the disc fades in
# and out AT it, because position interpolates on the same channel as strength. If a neighbour
# disagrees with the biome that owns the disc, the disc flies across the sky while fading --
# which is exactly what shipped in 1b and read as "the moon went from bottom right to top left".
func check_disc_positions_are_stationary() -> void:
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	for cycle_index: int in range(cycle.size()):
		var here: BiomePalette = cycle[cycle_index]
		if here.celestial_strength <= 0.0:
			continue
		for neighbour_offset: int in [-1, 1]:
			var neighbour: BiomePalette = cycle[posmod(cycle_index + neighbour_offset, cycle.size())]
			if here.celestial_position.distance_to(neighbour.celestial_position) > MAX_DISC_DRIFT:
				failures.append("%s has a disc at %s but its neighbour %s puts celestial_position at %s -- the disc will slide across the sky as it fades. A disc-less biome must copy its disc-having neighbour's celestial_position"
					% [here.resource_path.get_file().get_basename(), here.celestial_position,
						neighbour.resource_path.get_file().get_basename(), neighbour.celestial_position])


# THE ONE PAIR THAT IS NOT IN BIOME_CYCLE, and the only thing the per-session rotation can get
# wrong. Absolute index 0 is first_light, index 1 is BIOME_CYCLE[1 + rotation] -- so the biome
# the intro fades into is a different one every launch, and BOTH disc rules have to hold for
# every rotation the game is allowed to draw. BiomeDirector.get_allowed_rotations() is the list
# it draws from; this asserts the list is honest rather than restating it, so the two cannot
# drift apart.
#
# Also asserts the list is not a single entry: a rotation set that collapsed to one would pass
# every other check here while giving the player the same sequence every launch, which is the
# bug the rotation exists to fix.
func check_opening_seam() -> void:
	var allowed: PackedInt32Array = BiomeDirector.get_allowed_rotations()
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	var intro: BiomePalette = BiomeDirector.PALETTE_FIRST_LIGHT

	if allowed.size() < 2:
		failures.append("only %d rotation(s) open safely from first_light -- every launch would enter the arc at the same place, which is the whole point of the rotation"
			% allowed.size())

	for rotation: int in allowed:
		var opening: BiomePalette = cycle[posmod(1 + rotation, cycle.size())]
		var opening_name: String = opening.resource_path.get_file().get_basename()
		if intro.celestial_strength > 0.0 and opening.celestial_strength > 0.0:
			failures.append("rotation %d opens first_light -> %s and both have a disc -- see check_no_adjacent_discs; this is the transition every session plays"
				% [rotation, opening_name])
		elif (intro.celestial_strength > 0.0 or opening.celestial_strength > 0.0) \
			and intro.celestial_position.distance_to(opening.celestial_position) > MAX_DISC_DRIFT:
			failures.append("rotation %d opens first_light (celestial_position %s) -> %s (%s), and one of them owns the disc -- it would slide across the sky as it fades in, on the transition every session plays"
				% [rotation, intro.celestial_position, opening_name, opening.celestial_position])


# THE PROPERTY THE ROTATION EXISTS TO PRESERVE: after the intro, the arc is walked IN ORDER.
# A shuffle was built and reverted on 2026-08-12 for breaking exactly this -- the palettes are
# authored as a day passing, so day -> night -> day inside one session reads as broken rather
# than as variety. Checked through get_cycle_base_palette: a rare variant is a duplicate
# resource, so identity comparisons must run against the pre-roll palette.
# across a lap and a half so the wrap is included.
func check_arc_order_is_preserved() -> void:
	var director: BiomeDirector = BiomeDirector.new()
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	for cycle_index: int in range(1, cycle.size() + cycle.size() / 2):
		var here: BiomePalette = director.get_cycle_base_palette(cycle_index)
		var next: BiomePalette = director.get_cycle_base_palette(cycle_index + 1)
		var expected: BiomePalette = cycle[posmod(cycle.find(here) + 1, cycle.size())]
		if next != expected:
			failures.append("index %d is %s and index %d is %s, but the arc's next step is %s -- the session is not walking BIOME_CYCLE in order"
				% [cycle_index, here.resource_path.get_file().get_basename(), cycle_index + 1,
					next.resource_path.get_file().get_basename(),
					expected.resource_path.get_file().get_basename()])
			break
	director.free()


# The glow's and disc's position/size/strength are the NON-COLOUR fields riding CHANNEL_SKY,
# and a field left out of blend_into() fails in a way nothing else here would notice: `out` is
# a fresh BiomePalette, so an omitted field silently reads as the class default -- a centred,
# strength-0 layer. Every colour check still passes and the layer simply stops moving.
#
# EACH GROUP GETS ITS OWN PAIR, and that is load-bearing. The first version tested the disc
# fields on whatever pair differed on the GLOW fields, and negative-testing found the hole: on
# that pair both palettes happened to share celestial_size = 0.03, which is ALSO the class
# default -- so deleting the celestial_size lerp from blend_into changed nothing observable and
# the gate passed. An omitted field is only detectable against endpoints that actually differ
# from the default, so the pair has to be chosen per group.
# star_density rides CHANNEL_ATMOSPHERE rather than CHANNEL_SKY -- stars are weather, not
# light -- but it is a sky LAYER's strength and fails the same way, so it is asserted here
# with the rest. A single-field group is fine: the pair only has to differ on that one field.
# ice_contrast is the same shape again on CHANNEL_ICE: a bare float whose class default (1.0)
# is also its identity, so an omitted lerp would leave every biome rendering the untouched
# tile -- exactly what shipped before it was authored, and invisible to every colour check.
const BLEND_FIELD_GROUPS: Array[Array] = [
	["glow_position", "glow_radius", "glow_strength"],
	["celestial_position", "celestial_size", "celestial_strength"],
	["star_density"],
	["celestial_is_moon"],
	["ice_contrast"],
]


func check_blend_carries_fields() -> void:
	var out: BiomePalette = BiomePalette.new()
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(BiomePalette.CHANNEL_COUNT)

	for group: Array in BLEND_FIELD_GROUPS:
		var pair: Array[BiomePalette] = find_pair_differing_on(group)
		if pair.is_empty():
			failures.append("no pair of palettes differs on all of %s -- those fields are identical across the whole cycle, so blend_into carrying them is untested"
				% ", ".join(PackedStringArray(group)))
			continue

		for endpoint: int in [0, 1]:
			var expected: BiomePalette = pair[endpoint]
			for channel_index: int in range(BiomePalette.CHANNEL_COUNT):
				weights[channel_index] = float(endpoint)
			BiomePalette.blend_into(pair[0], pair[1], weights, out)
			for field_name: String in group:
				if not values_match(out.get(field_name), expected.get(field_name)):
					failures.append("blend at weight %d lost %s (%s, expected %s) -- the field is missing from blend_into, and reads back as the BiomePalette class default"
						% [endpoint, field_name, out.get(field_name), expected.get(field_name)])


# The first pair of palettes -- ANY two, not necessarily adjacent -- whose values differ on
# EVERY field in the group. All of them, not any of them: a group is asserted as a unit, and
# one shared value is enough to hide an omission behind the class default.
#
# NOT restricted to adjacent pairs, and that matters since celestial_position became
# deliberately CONSTANT across neighbours (check_disc_positions_are_stationary requires it, so
# a disc fades in and out where it belongs instead of sliding across the sky). blend_into is a
# pure function of two palettes and a weight; nothing about testing it needs the two to be
# neighbours in the cycle, and requiring that made a correctness check impossible to satisfy
# for a field whose whole design is not to vary locally.
func find_pair_differing_on(group: Array) -> Array[BiomePalette]:
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	for from_index: int in range(cycle.size()):
		for to_index: int in range(cycle.size()):
			if from_index == to_index:
				continue
			var candidate_from: BiomePalette = cycle[from_index]
			var candidate_to: BiomePalette = cycle[to_index]
			var all_differ: bool = true
			for field_name: String in group:
				if values_match(candidate_from.get(field_name), candidate_to.get(field_name)):
					all_differ = false
					break
			if all_differ:
				var pair: Array[BiomePalette] = [candidate_from, candidate_to]
				return pair
	return []


# Vector2 and float both ride these groups, and neither has a common approx-compare that works
# through a Variant, so dispatch on the type.
func values_match(a: Variant, b: Variant) -> bool:
	if a is Vector2:
		return (a as Vector2).is_equal_approx(b as Vector2)
	if typeof(a) == TYPE_BOOL:
		return bool(a) == bool(b)
	return is_equal_approx(float(a), float(b))


# The ice PATTERN is the one thing a blended palette cannot carry: a Polygon2D samples exactly
# one texture, so dissolving between two tiles needs both endpoints AND the weight, which one
# value cannot express. terrain_generator.gd builds one band per ground run, whose shader takes
# the incoming tile as a second sampler, and is handed the pair directly
# (BiomePalette.ice_texture).
#
# So there are two things to hold here, and neither is visible to any other gate:
#
#   1. blend_into() must not carry ice_texture at ANY weight. Before 2026-08-09 it snapped the
#      field at the midpoint of the ice channel, and terrain_generator read the result. If a
#      snap comes back, the generator's `from` tile silently becomes a value that already
#      jumped, the dissolve runs between a tile and itself for half the window and then between
#      two different ones for the other half, and the hard seam returns -- while every colour
#      check in this file still passes.
#   2. Some adjacent pair must actually differ, or nothing in the game ever exercises the
#      dissolve and (1) is vacuous.
func check_ice_pattern_crossfade() -> void:
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	var from_palette: BiomePalette = null
	var to_palette: BiomePalette = null
	for cycle_index: int in range(cycle.size()):
		var candidate_from: BiomePalette = cycle[cycle_index]
		var candidate_to: BiomePalette = cycle[(cycle_index + 1) % cycle.size()]
		if candidate_from.ice_texture != candidate_to.ice_texture:
			from_palette = candidate_from
			to_palette = candidate_to
			break
	if from_palette == null:
		failures.append("every adjacent biome pair shares one ice_texture -- no pattern ever changes in game, so the crossfade is dead code and untestable here")
		return

	var out: BiomePalette = BiomePalette.new()
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(BiomePalette.CHANNEL_COUNT)

	# Swept rather than probed at the ends: a reintroduced snap fires somewhere in the middle,
	# which is exactly where endpoint-only checks are blind.
	for step_index: int in range(ICE_CROSSFADE_PROBE_STEPS + 1):
		var ice: float = float(step_index) / float(ICE_CROSSFADE_PROBE_STEPS)
		for channel_index: int in range(BiomePalette.CHANNEL_COUNT):
			weights[channel_index] = ice
		BiomePalette.blend_into(from_palette, to_palette, weights, out)
		if out.ice_texture != null:
			failures.append("blend_into wrote ice_texture at ice weight %.4f -- a blended palette must not carry the pattern, or terrain_generator dissolves from an already-snapped tile and the hard seam comes back" % ice)
			return


# Mirrors biome_director.apply_palette_for_world_x's index maths. Duplicated rather than
# called because that function pushes into the scene tree, which this gate has none of.
func get_biome_index(world_x: float) -> int:
	return int(floor(world_x / BiomeDirector.BIOME_DISTANCE))


func get_transition_progress(world_x: float) -> float:
	var cycle_position: float = world_x / BiomeDirector.BIOME_DISTANCE
	var distance_into_biome: float = (cycle_position - floor(cycle_position)) * BiomeDirector.BIOME_DISTANCE
	var transition_start: float = BiomeDirector.BIOME_DISTANCE - BiomeDirector.TRANSITION_DISTANCE
	if distance_into_biome <= transition_start:
		return 0.0
	return clampf((distance_into_biome - transition_start) / BiomeDirector.TRANSITION_DISTANCE, 0.0, 1.0)


# Indexed rather than by name: Color is a built-in Variant, not an Object, so it has no
# get() -- but it does support [0..3] for r/g/b/a.
const COLOR_COMPONENT_NAMES: Array[String] = ["r", "g", "b", "a"]


func assert_color_in_range(label: String, value: Variant) -> void:
	var color: Color = value as Color
	for component_index: int in range(4):
		var component: float = color[component_index]
		if component < -EPSILON or component > 1.0 + EPSILON:
			failures.append("%s.%s = %.4f out of [0,1]"
				% [label, COLOR_COMPONENT_NAMES[component_index], component])


# Rec. 601 luma, the same weighting a luminance-tinting shader would use.
func get_luminance(color: Color) -> float:
	return (color.r * 0.299) + (color.g * 0.587) + (color.b * 0.114)


func get_int_argument(argument_name: String, default_value: int) -> int:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_int()
	return default_value
