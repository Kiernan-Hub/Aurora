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
#   2. The rim stays bright in every biome. The surface rim is the single strongest read
#      of "this is the edge you ride on", so a dark biome dimming it is a playability bug,
#      not an art choice.
#   3. Far scenery stays separated from near scenery, so the depth read survives every
#      palette (the far/near lerp in BiomePalette.get_scenery_color assumes it).
#   4. The schedule is pure in world_x: same x always yields the same biome and progress,
#      progress stays in [0, 1], and the cycle wraps in both directions.
#   5. Channel weights are monotonic, land exactly on 0 and 1 at the window ends, and
#      genuinely lead/trail each other rather than all moving together.
#   6. Blending never produces an out-of-range colour, and never allocates -- blend_into
#      must write into the caller's instance.
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

# The rim core is what the player actually tracks the surface by. 0.80 is comfortably below
# the darkest shipped value (starlit_night, ~0.95) and comfortably above anything that
# would read as a dim edge.
const MIN_RIM_CORE_LUMINANCE: float = 0.80
# Far and near scenery must differ by at least this much luminance or the parallax layers
# collapse into one flat mass and the depth cue is gone.
const MIN_SCENERY_SEPARATION: float = 0.08
# Float slop on smoothstep endpoints and colour lerps.
const EPSILON: float = 0.0005

var failures: Array[String] = []


func _init() -> void:
	var schedule_steps: int = get_int_argument("--steps", DEFAULT_SCHEDULE_STEPS)

	check_palettes()
	check_schedule_purity(schedule_steps)
	check_channel_curves()
	check_blending()

	print("")
	if failures.is_empty():
		print("BIOME_CHECK PASS  palettes=", BiomeDirector.BIOME_CYCLE.size(),
			" biome_distance=", BiomeDirector.BIOME_DISTANCE,
			" transition=", BiomeDirector.TRANSITION_DISTANCE,
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
			"sky_top", "sky_mid", "sky_horizon",
			"scenery_far", "scenery_near", "haze_far", "haze_near",
			"tree_tint", "bird_tint",
			"ice_surface", "ice_depth", "rim_core", "rim_glow",
			"snow_tint", "coin_color", "obstacle_color",
		]:
			assert_color_in_range(label + "." + field_name, palette.get(field_name))

		if get_luminance(palette.rim_core) < MIN_RIM_CORE_LUMINANCE:
			failures.append("%s.rim_core too dark (%.3f < %.3f) -- the ride surface edge stops reading"
				% [label, get_luminance(palette.rim_core), MIN_RIM_CORE_LUMINANCE])

		var separation: float = absf(get_luminance(palette.scenery_far) - get_luminance(palette.scenery_near))
		if separation < MIN_SCENERY_SEPARATION:
			failures.append("%s scenery_far/near separation %.3f < %.3f -- parallax depth collapses"
				% [label, separation, MIN_SCENERY_SEPARATION])


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
			for field_name: String in ["sky_top", "sky_mid", "sky_horizon", "scenery_far",
				"scenery_near", "haze_far", "haze_near", "ice_surface", "ice_depth",
				"rim_core", "rim_glow", "snow_tint", "tree_tint", "bird_tint"]:
				assert_color_in_range(label + "." + field_name, out.get(field_name))

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
