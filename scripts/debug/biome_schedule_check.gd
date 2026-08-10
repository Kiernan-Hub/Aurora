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


func check_palettes() -> void:
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	if cycle.is_empty():
		failures.append("BIOME_CYCLE is empty")
		return

	for cycle_index: int in range(cycle.size()):
		var palette: BiomePalette = cycle[cycle_index]
		if palette == null:
			failures.append("BIOME_CYCLE[%d] failed to load" % cycle_index)
			continue
		var label: String = "palette[%d]" % cycle_index

		for field_name: String in [
			"sky_top", "sky_mid", "sky_horizon", "glow_color",
			"scenery_far", "scenery_near", "haze_far", "haze_near",
			"tree_tint", "bird_tint",
			"ice_surface", "ice_depth",
			"snow_tint", "coin_color", "obstacle_color",
		]:
			assert_color_in_range(label + "." + field_name, palette.get(field_name))

		check_glow_authoring(label, palette)
		check_glow_layout(label, palette)

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
			for field_name: String in ["sky_top", "sky_mid", "sky_horizon", "glow_color",
				"scenery_far", "scenery_near", "haze_far", "haze_near", "ice_surface", "ice_depth",
				"snow_tint", "tree_tint", "bird_tint"]:
				assert_color_in_range(label + "." + field_name, out.get(field_name))
			# The blended glow has to be layout-safe too, not just in-range as a colour: it is fed
			# straight to sky_backdrop.position_glow() on every frame of the transition, and a
			# mid-transition value is the one no endpoint check ever looks at.
			check_glow_layout(label, out)

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

	check_blend_carries_glow()
	check_ice_pattern_crossfade()


# glow_position, glow_radius and glow_strength are the first NON-COLOUR, non-scalar fields to
# ride a channel, and a field left out of blend_into() fails in a way nothing else here would
# notice: `out` is a fresh BiomePalette, so an omitted field silently reads as the class
# default -- a centred, strength-0 glow. Every colour check still passes and the glow simply
# stops moving. So assert both endpoints reproduce exactly.
func check_blend_carries_glow() -> void:
	var cycle: Array[BiomePalette] = BiomeDirector.BIOME_CYCLE
	var out: BiomePalette = BiomePalette.new()
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(BiomePalette.CHANNEL_COUNT)

	# A pair that actually differs on every glow field, or the assertion is vacuous.
	var from_palette: BiomePalette = null
	var to_palette: BiomePalette = null
	for cycle_index: int in range(cycle.size()):
		var candidate_from: BiomePalette = cycle[cycle_index]
		var candidate_to: BiomePalette = cycle[(cycle_index + 1) % cycle.size()]
		if candidate_from.glow_position != candidate_to.glow_position \
				and candidate_from.glow_radius != candidate_to.glow_radius \
				and not is_equal_approx(candidate_from.glow_strength, candidate_to.glow_strength):
			from_palette = candidate_from
			to_palette = candidate_to
			break
	if from_palette == null:
		failures.append("no adjacent biome pair differs on all of glow_position/glow_radius/glow_strength -- the glow never moves in game, so blend_into carrying it is untested")
		return

	for endpoint: int in [0, 1]:
		var expected: BiomePalette = from_palette if endpoint == 0 else to_palette
		for channel_index: int in range(BiomePalette.CHANNEL_COUNT):
			weights[channel_index] = float(endpoint)
		BiomePalette.blend_into(from_palette, to_palette, weights, out)
		if not out.glow_position.is_equal_approx(expected.glow_position):
			failures.append("blend at weight %d lost glow_position (%s, expected %s) -- the field is missing from blend_into" % [endpoint, out.glow_position, expected.glow_position])
		if not out.glow_radius.is_equal_approx(expected.glow_radius):
			failures.append("blend at weight %d lost glow_radius (%s, expected %s) -- the field is missing from blend_into" % [endpoint, out.glow_radius, expected.glow_radius])
		if not is_equal_approx(out.glow_strength, expected.glow_strength):
			failures.append("blend at weight %d lost glow_strength (%.4f, expected %.4f) -- the field is missing from blend_into" % [endpoint, out.glow_strength, expected.glow_strength])


# The ice PATTERN is the one thing a blended palette cannot carry: a Polygon2D samples exactly
# one texture, so dissolving between two tiles needs both endpoints AND the weight, which one
# value cannot express. terrain_generator.gd stacks two bands per ground run and is handed the
# pair directly (BiomePalette.ice_texture).
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
