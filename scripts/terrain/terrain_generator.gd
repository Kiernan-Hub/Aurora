extends Node2D

class_name TerrainGenerator

const CHUNK_SCENE: PackedScene = preload("res://scenes/terrain/terrain_chunk.tscn")

@export var player_path: NodePath
@export var chunk_width: float = 512.0
@export var chunk_count_ahead: int = 6
@export var chunk_count_behind: int = 2
@export var ground_y: float = 192.0
@export var surface_y_offset: float = -32.0
@export var height_sample_count: int = 32
@export var debug_log_segment_selection: bool = false
@export var debug_replay_session_seed: int = -1
# Complexity dial for bisecting terrain bugs to a single feature: set any weight to 0
# to remove that shape from the world entirely, using the same weight<=0 skip already
# present in get_non_flat_segment_selection/get_weighted_segment_selection. Ladder
# example -- flat-only: zero every weight below except debug_weight_flat. +hills: also
# raise debug_weight_medium_hill_valley_mix. +downhill/uphill: also raise those two.
# +mega_drop: also raise debug_weight_mega_drop. Defaults reproduce the shipping mix.
@export var debug_weight_flat: int = DEFAULT_WEIGHT_FLAT
@export var debug_weight_small_hill: int = DEFAULT_WEIGHT_SMALL_HILL
@export var debug_weight_medium_hill_valley_mix: int = DEFAULT_WEIGHT_MEDIUM_HILL_VALLEY_MIX
@export var debug_weight_big_downhill: int = DEFAULT_WEIGHT_BIG_DOWNHILL
@export var debug_weight_gentle_uphill: int = DEFAULT_WEIGHT_GENTLE_UPHILL
@export var debug_weight_mega_drop: int = MEGA_DROP_SELECTION_WEIGHT

# Harness opt-out for chasms, same contract as ObstacleSpawner/PowerupSpawner.debug_spawning_disabled.
# Every long no-input probe must set this true before add_child(main): with it false the
# player runs off the first lip, dies, GameManager pauses the tree, and the probe prints a
# confident, meaningless number instead of failing (docs/development/debugging.md).
#
# Deliberately NOT @export, unlike debug_weight_*: an exported bool can be serialised into
# main.tscn by the editor and silently disable the feature for weeks, which is exactly what
# happened to Main.world_rebase_enabled (CLAUDE.md, "Things that break silently").
var debug_chasm_disabled: bool = false

# Playtest knob for the drop chasm: forces EVERY chasm to be the chasm_drop variant and
# tightens the placement window, so a session meets one every ~5-13s instead of every ~30-90s.
# Flip this to true, play, flip it back -- it is the only thing that needs changing.
#
# Affects placement and variant choice only; the shapes themselves are untouched, so what you
# are rehearsing is exactly what ships. Every gate runs with it false, so a run left on cannot
# quietly become the measured configuration.
#
# Plain var, not @export, for the same reason debug_chasm_disabled is: an exported bool can be
# serialised into main.tscn and silently persist (CLAUDE.md, "Things that break silently").
var debug_drop_chasm_rehearsal: bool = false

var player: CharacterBody2D
var next_chunk_index: int = 0
var active_chunks: Dictionary[int, Node2D] = {}
var session_seed: int = 0
var session_floor_max_angle: float = 0.0
var segment_start_x_cache: Dictionary[int, float] = {}
var segment_length_cache: Dictionary[int, float] = {}
var segment_baseline_cache: Dictionary[int, float] = {}
var segment_spec_cache: Dictionary[int, Dictionary] = {}
var lowest_cached_segment_index: int = 0
var highest_cached_segment_index: int = 0
var segment_selection_weight_table: Array[Dictionary] = []
# Per-chunk collision polyline samples, keyed by chunk index: the world_x of every
# vertex and the terrain height there. Built once per chunk (see
# ensure_chunk_collision_samples) and read every physics frame by
# get_collision_chord_slope_angle(), which used to rebuild the whole array from
# scratch on every single call.
#
# PackedFloat64Array, never PackedFloat32Array: get_terrain_height() returns a
# GDScript float (a double), and narrowing terrain geometry to float32 is the exact
# shape of an already-fixed freeze bug (docs/research/freeze_bug.md). Float64 stores
# these values bit-exactly, so the cache cannot perturb the height field.
var chunk_collision_sample_xs: Dictionary[int, PackedFloat64Array] = {}
var chunk_collision_sample_heights: Dictionary[int, PackedFloat64Array] = {}

const LIGHT_CHUNK_COLOR: Color = Color(0.92, 0.97, 1.0)
const DARK_CHUNK_COLOR: Color = Color(0.78, 0.86, 0.93)
const SLOPE_SAMPLE_DISTANCE: float = 2.0
const MAX_COLLISION_SEGMENT_LENGTH: float = 16.0
# How far from the most recently requested chunk the collision-sample cache keeps
# entries. Must exceed the live window (chunk_count_behind + chunk_count_ahead = 8) so
# ordinary play never evicts a chunk it is about to ask for again. Bounding it here
# rather than only in remove_chunk() keeps the cache finite for callers that sample
# arbitrary world_x without spawning anything -- an endless runner must not accumulate
# a dictionary entry per chunk forever.
const CHUNK_COLLISION_SAMPLE_CACHE_RADIUS: int = 10
const SEGMENT_TYPE_FLAT: int = 0
const SEGMENT_TYPE_HILL: int = 1
const SEGMENT_TYPE_VALLEY: int = 2
const SEGMENT_TYPE_DOWNHILL: int = 3
const SEGMENT_TYPE_UPHILL: int = 4
const SEGMENT_SELECTION_FLAT: int = 0
const SEGMENT_SELECTION_SMALL_HILL: int = 1
const SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX: int = 2
const SEGMENT_SELECTION_BIG_DOWNHILL: int = 3
const SEGMENT_SELECTION_GENTLE_UPHILL: int = 4
const SEGMENT_SELECTION_MEGA_DROP: int = 5
const SEGMENT_TIER_SMALL: int = 0
const SEGMENT_TIER_MEDIUM: int = 1
const SMALL_SEGMENT_LENGTH: float = 480.0
const MEDIUM_SEGMENT_LENGTH: float = 640.0
const SUSTAINED_DOWNHILL_LENGTH: float = 960.0
const SUSTAINED_DOWNHILL_DROP: float = 160.0
const GENTLE_UPHILL_LENGTH: float = SUSTAINED_DOWNHILL_LENGTH
const GENTLE_UPHILL_RISE: float = 28.0
const MEGA_DROP_TOTAL_VERTICAL_DROP: float = 1080.0
const MEGA_DROP_FLOOR_ANGLE_FRACTION: float = 0.9
# 0 = mega_drop is never generated (2026-08-01). It is the steepest feature in
# the game (floor_max_angle * 0.9 = 40.5 deg) and carried a persistent visible
# shake that survived every fix attempted: camera-follow smoothing (measured
# -84% camera jerk, imperceptible), MSAA 2D and Polygon2D.antialiased (each
# ~-55% rendered-edge jerk, imperceptible), plus ruled-out floor-snap,
# frame-pacing, segment-entry and grounded/airborne hypotheses. Full history:
# docs/research/camera_shake.md.
#
# The mechanism is angle-dependent -- rendered-edge quantisation scales with
# edge steepness -- so cutting the steepest segment cuts the worst case. It
# does NOT remove the effect from hills/valleys, which measure ~0.12-0.14
# camera jerk against flat's 0.0005 and are still mildly affected.
#
# The generator code below is intentionally left intact rather than deleted:
# this is a game-feel judgement that may be revisited, and debug harnesses
# still force the segment through debug_weight_mega_drop to study it. Restore
# by setting this back to 10.
const MEGA_DROP_SELECTION_WEIGHT: int = 0
const TERRAIN_FILL_DEPTH_MARGIN: float = 4096.0
# --- Chasm -------------------------------------------------------------------------
# A chasm is a FLAT segment with a span of x in the middle where there is no ground.
# get_terrain_height() still returns the LIP height inside that span, so the height field
# stays single-valued, continuous, finite and flat, and every existing consumer -- the fill,
# the collision samples, get_collision_chord_slope_angle, get_slope_angle_at_x, player tilt,
# get_surface_world_y, recover_from_stall, the three spawners, terrain_invariant_check --
# keeps working untouched. has_ground_at_world_x() is the ONLY thing in the project that
# knows the ground is not really there.
#
# Why this is the safe way to add a dramatic feature, and a steep face is not: any surface
# at or above floor_max_angle (45 deg) is classified by CharacterBody2D as a WALL and wedges
# the player at the lip. That is the large_valley bug (80.4 deg face, three weeks,
# docs/research/freeze_bug.md), and the height field cannot represent anything steeper than
# vertical at all. A void has NO surface, so a chasm adds ZERO slope to the world: the
# steepest terrain in the game stays 20.13 deg, exactly as it was without this feature.
#
# Both lips are exactly horizontal, and that is free rather than engineered: every profile
# in evaluate_segment_offset has zero derivative at progress 0 and 1
# (sin^2(pi*p) -> pi*sin(2*pi*p); 0.5-0.5cos(pi*p) -> 0.5*pi*sin(pi*p)), so every segment
# boundary in this generator is already a flat tangent point.
const CHASM_SEGMENT_LENGTH: float = 1600.0
# Run-up before the near lip. Sized so that NO jump taken before the chasm's own segment can
# carry the player into the void: the void is only ever reachable by a jump taken within the
# run-up itself, i.e. within sight of the thing that kills you.
#
# That requires the lead-in to exceed the maximum jump reach, and the maximum is a
# JUMP-BOOSTED one, which the v1 value of 640 did not account for: PowerupManager's
# JUMP_BOOST_VELOCITY_MULTIPLIER (sqrt 2) takes airtime from 0.8s to 1.131s, so reach at
# MAX_SPEED is 848px, not the 600px the old comment derived. A jump-boosted player who jumped
# at the first pixel of a 640px run-up landed 208px past the near lip -- inside the void.
# 900 restores the invariant with ~50px of margin, and terrain_invariant_check's
# CHASM_LEAD_IN_TOO_SHORT now asserts it instead of a comment claiming it.
#
# Note what this does NOT buy, because the old comment overclaimed it: there is always some
# window INSIDE the run-up from which a maximum-reach jump lands in the void (for any
# lead-in L and reach R, that window is (L - R, L + width - R), which is never empty).
# Jumping much too early is a mistake the player makes and can see; that is gameplay, not a
# geometry bug. The invariant is only about jumps taken before the run-up exists.
const CHASM_LEAD_IN_LENGTH: float = 900.0
# The void itself, as a table of width variants. Airtime on level lips is exactly
# 2 * 640 / 1600 = 0.8s (JUMP_VELOCITY / GRAVITY, player.gd), so reach is 0.8 * speed and the
# maximum width terrain_invariant_check will accept at a given world_x is
# CHASM_MAX_REACH_FRACTION (0.55) of it.
#
# That fraction, not taste, is what fixes this table. The SpeedManager ramp only reaches
# ~545 px/s by the earliest position a chasm may occupy, which allows at most a 240px void
# there -- so "wider than the v1 220" is not something a chasm can be ANYWHERE. Each variant
# therefore carries its own min_segment_index, and the wide one is simply not drawn until the
# ramp has produced the speed that clears it. terrain_invariant_check derives the required
# minimum from the real ramp and the real jump arithmetic and fails the build if a
# min_segment_index here is too low, so these are checked numbers, not estimates.
#
# min_segment_index is a HARD world_x bound via SMALL_SEGMENT_LENGTH (the shortest segment
# possible), the same conservative trick CHASM_MIN_SEGMENT_INDEX uses, and for the same
# reason: build_segment_spec cannot read segment_start_x_cache.
#
#   narrow    160  from index 28   (the global minimum; legal as early as chasms exist)
#   standard  220  from index 28   the v1 chasm, unchanged
#   wide      280  from index 112  the checker derives 76 as the hard minimum; 112 is two full
#                                  windows, chosen so the wide variant clears the 0.55 fraction
#                                  with ~26px of width to spare rather than sitting exactly on
#                                  it. Being late is also the right call on its own terms --
#                                  it is the widest hazard in the game.
#
# Every entry's min_segment_index must be >= CHASM_MIN_SEGMENT_INDEX for at least one variant,
# or get_chasm_variant() would have nothing legal to draw. The two 28s guarantee that.
#
# exit_drop and must_be_jumped are what phase 3 adds. The first three are HAZARDS: level
# lips, cleared by jumping, and terrain_invariant_check holds them to CHASM_MAX_REACH_FRACTION
# and to CHASM_TRIVIALLY_CLEARABLE. chasm_drop is not a hazard and is not meant to be -- it is
# the "big fall" spectacle beat, crossed by simply running off the near lip, and the checker
# asserts the OPPOSITE property for it (see check_one_chasm).
#
#   drop      320  from index 28   800px lower far lip. Running off at the slowest speed this
#                                  can appear at (545 px/s) covers 545px against a 320px void,
#                                  and 750px at cap -- so it is cleared with margin at every
#                                  speed, and segment_length carries enough landing flat for
#                                  the longest of those crossings.
const CHASM_VARIANTS: Array[Dictionary] = [
	{"label": "chasm_narrow", "void_length": 160.0, "min_segment_index": 28, "weight": 3, "exit_drop": 0.0, "must_be_jumped": true, "segment_length": 1600.0},
	{"label": "chasm", "void_length": 220.0, "min_segment_index": 28, "weight": 4, "exit_drop": 0.0, "must_be_jumped": true, "segment_length": 1600.0},
	{"label": "chasm_wide", "void_length": 280.0, "min_segment_index": 112, "weight": 3, "exit_drop": 0.0, "must_be_jumped": true, "segment_length": 1600.0},
	{"label": "chasm_drop", "void_length": 320.0, "min_segment_index": 28, "weight": 3, "exit_drop": 800.0, "must_be_jumped": false, "segment_length": 2400.0},
]
# Default far-lip height for a variant that does not state one. Kept at 0 so the hazard
# variants above stay exactly as phase 2 shipped them.
#
# HOW A NON-ZERO DROP IS REPRESENTED (phase 3): the height field stays flat at NEAR-lip height
# across the entire void and steps down once, exactly AT the far lip -- see
# get_exit_drop_offset(). It is deliberately not a ramp across the void. A ramp would have
# been continuous, but 800px over 320px is a 68deg chord, and get_collision_chord_slope_angle()
# would then aim a boosting player straight down it instead of returning 0, silently breaking
# the skim that carries a boost across any void at all (player.gd, LOAD-BEARING FOR CHASMS).
# Keeping the void flat means every existing query is bit-identical to phase 2 and no void
# guards are needed anywhere in this file.
#
# The step is the only height-field discontinuity in the generator. It is safe because nothing
# spans it: the far lip is already a forced collision vertex (add_lip_sample_world_x) and a
# fill-run boundary (split_surface_into_ground_runs), so no chord and no polygon edge crosses
# it. terrain_invariant_check allows a step ONLY at a far lip and asserts it equals that
# variant's exit_drop, which is a stronger check than the blanket one it replaces.
#
# The other half of phase 3 is Player.is_boost_gliding_over_drop(), which hands a boosting
# player to gravity the moment ground reappears below them instead of hovering at near-lip
# height until the boost timer expires.
# Height of the far lip relative to the near lip. Still 0: level lips are the only
# configuration where the height field inside the void is indistinguishable from ordinary flat
# ground, so terrain_invariant_check needs no exemption for the void span and every existing
# consumer is trivially unaffected.
#
# Phase 2 deliberately varied WIDTH ONLY and left this alone. A non-zero drop is not a data
# change: the field would need a step at the far lip (invisible to geometry, since no chord or
# fill edge survives inside a void, but visible to the 1px sweep, to get_slope_angle_at_x and
# to get_collision_chord_slope_angle, all of which would need void guards) -- and, decisively,
# a boosting player skims the void at NEAR-lip height on a gravity-free grounded model and
# would arrive above a lower far lip with only FLOOR_SNAP_LENGTH (18px) of snap to catch them,
# hovering in mid-air until the boost expired. Deferred to Phase 3 with that fix.
const CHASM_EXIT_DROP: float = 0.0
# Placement: exactly one chasm per window of CHASM_WINDOW_SEGMENT_COUNT segments, at a
# hash-chosen offset constrained to the window's middle. The edge margin is what turns "one
# per window" into a real minimum spacing -- without it the last segment of one window and
# the first of the next could both be chasms.
#
#   offsets in [14, 41]  ->  min spacing (56-41)+14 = 29 segments
#                            max spacing (56-14)+41 = 83 segments
#
# At the shipping mix's ~640px mean segment length and 600-750 px/s that is roughly 31-89s,
# but the BOUND is in segments; the seconds figure is an estimate that terrain_invariant_check
# reports as measured min/max world_x spacing rather than assuming.
#
# A weight-table entry cannot express this: a weight permits two chasms in a row, and instant
# death is not a shape that may repeat adjacently. So the chasm bypasses the weight table.
const CHASM_WINDOW_SEGMENT_COUNT: int = 56
const CHASM_WINDOW_EDGE_MARGIN_SEGMENTS: int = 14
# debug_drop_chasm_rehearsal's window. Offsets in [2, 7] -> spacing 5-15 segments, roughly
# 5-13s at cruising speed. Same edge-margin rule as above, so the spacing bound still holds.
const CHASM_REHEARSAL_WINDOW_SEGMENT_COUNT: int = 10
const CHASM_REHEARSAL_WINDOW_EDGE_MARGIN_SEGMENTS: int = 2
# No chasm before this segment index. The shortest segment is SMALL_SEGMENT_LENGTH, so this
# is a HARD lower bound of 28 * 480 = 13,440 world_x, which the SpeedManager ramp puts at
# speed >= ~545 px/s and a reach of ~436px -- 220 is 0.50 of that, inside
# terrain_invariant_check's 0.55 CHASM_MAX_REACH_FRACTION with room to spare.
#
# It is set to half a window rather than a whole one on purpose. Suppression only bites in
# window 0, so a value at or above CHASM_WINDOW_SEGMENT_COUNT - CHASM_WINDOW_EDGE_MARGIN_SEGMENTS
# would empty window 0 entirely and push the FIRST chasm of every run out to ~90-110s, well
# past the intended cadence. At 28, half of window 0's legal offsets survive: roughly half of
# runs meet a chasm around t~35-50s and the rest around t~90s.
#
# Expressed in segments rather than world_x because build_segment_spec must not read
# segment_start_x_cache: cache_previous_segment() computes a segment's length BEFORE writing
# its start_x, and negative indices are real (initialize_chunks spawns from chunk -2), so
# that entry does not exist yet while this runs.
const CHASM_MIN_SEGMENT_INDEX: int = 28
# How far past a far lip get_next_ground_world_x() places a nudged item, so a powerup pushed
# out of a void does not sit on the lip vertex itself.
const CHASM_LIP_CLEARANCE: float = 32.0
const CHASM_HASH_INDEX_MULTIPLIER: int = 1597334677
const CHASM_HASH_MIX_MULTIPLIER: int = 2654435761
# Salt for the width draw, so which variant a chasm gets is uncorrelated with where the chasm
# was placed -- the placement hash is keyed on the WINDOW and would otherwise hand every chasm
# in a window the same draw.
const CHASM_VARIANT_HASH_SALT: int = 0x5f3a71c9
const SMALL_HILL_AMPLITUDE: float = 56.0
const MEDIUM_HILL_AMPLITUDE: float = 74.0
const DEFAULT_WEIGHT_FLAT: int = 16
const DEFAULT_WEIGHT_SMALL_HILL: int = 16
const DEFAULT_WEIGHT_MEDIUM_HILL_VALLEY_MIX: int = 42
const DEFAULT_WEIGHT_BIG_DOWNHILL: int = 16
const DEFAULT_WEIGHT_GENTLE_UPHILL: int = 10
const HASH_MASK: int = 0x7fffffff
const HASH_INDEX_MULTIPLIER: int = 374761393
const HASH_MIX_MULTIPLIER: int = 668265263
const DEBUG_TERRAIN_LOGGING: bool = false
const DEBUG_SEGMENT_SELECTION_LOG_COUNT: int = 80


func _ready() -> void:
	player = get_node(player_path) as CharacterBody2D
	if player == null:
		push_error("TerrainGenerator requires a valid player_path.")
		set_physics_process(false)
		return

	session_seed = get_initial_session_seed()
	session_floor_max_angle = player.floor_max_angle
	segment_selection_weight_table = build_segment_selection_weight_table()
	initialize_segment_cache()
	if debug_log_segment_selection:
		log_debug_segment_selection(0, DEBUG_SEGMENT_SELECTION_LOG_COUNT)
	initialize_chunks()


func get_initial_session_seed() -> int:
	if debug_replay_session_seed >= 0:
		print("Terrain replay seed: ", debug_replay_session_seed)
		return debug_replay_session_seed
	return create_session_seed()


func get_session_seed() -> int:
	return session_seed


func build_segment_selection_weight_table() -> Array[Dictionary]:
	return [
		{"selection": SEGMENT_SELECTION_FLAT, "weight": debug_weight_flat},
		{"selection": SEGMENT_SELECTION_SMALL_HILL, "weight": debug_weight_small_hill},
		{"selection": SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX, "weight": debug_weight_medium_hill_valley_mix},
		{"selection": SEGMENT_SELECTION_BIG_DOWNHILL, "weight": debug_weight_big_downhill},
		{"selection": SEGMENT_SELECTION_GENTLE_UPHILL, "weight": debug_weight_gentle_uphill},
		{"selection": SEGMENT_SELECTION_MEGA_DROP, "weight": debug_weight_mega_drop},
	]


func _physics_process(_delta: float) -> void:
	if player == null:
		return

	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	var target_chunk_index: int = player_chunk_index + chunk_count_ahead
	var despawn_chunk_index: int = player_chunk_index - chunk_count_behind

	while next_chunk_index <= target_chunk_index:
		spawn_chunk(next_chunk_index)
		next_chunk_index += 1

	var chunk_indices: Array[int] = active_chunks.keys()
	for chunk_index: int in chunk_indices:
		if chunk_index < despawn_chunk_index:
			remove_chunk(chunk_index)


func initialize_chunks() -> void:
	var player_chunk_index: int = int(floor(player.global_position.x / chunk_width))
	next_chunk_index = player_chunk_index - chunk_count_behind
	for chunk_index: int in range(player_chunk_index - chunk_count_behind, player_chunk_index + chunk_count_ahead + 1):
		spawn_chunk(chunk_index)
	next_chunk_index = player_chunk_index + chunk_count_ahead + 1


func spawn_chunk(chunk_index: int) -> void:
	if active_chunks.has(chunk_index):
		return

	var chunk: StaticBody2D = CHUNK_SCENE.instantiate() as StaticBody2D
	if chunk == null:
		push_error("Failed to instance terrain chunk scene.")
		return

	chunk.position = Vector2((float(chunk_index) * chunk_width) + (chunk_width * 0.5), ground_y)
	build_chunk_surface(chunk, chunk_index)
	apply_chunk_color(chunk, chunk_index)
	add_child(chunk)
	active_chunks[chunk_index] = chunk
	if DEBUG_TERRAIN_LOGGING:
		print("spawn chunk ", chunk_index)


func remove_chunk(chunk_index: int) -> void:
	if not active_chunks.has(chunk_index):
		return

	var chunk: Node2D = active_chunks[chunk_index]
	active_chunks.erase(chunk_index)
	# queue_free(), not free(): this runs inside _physics_process and the chunk is a
	# StaticBody2D carrying a ConcavePolygonShape2D, i.e. exactly the case Godot
	# documents as unsafe to destroy synchronously during a physics callback. The old
	# free() was justified by the chunk being >=1024px behind the player, but that is a
	# distance margin, not a guarantee. Erasing from active_chunks first means the extra
	# frame the node survives is invisible: next_chunk_index only increases, so this
	# index can never be re-spawned into a duplicate overlapping body.
	chunk.queue_free()
	if DEBUG_TERRAIN_LOGGING:
		print("free chunk ", chunk_index)


func build_chunk_surface(chunk: StaticBody2D, chunk_index: int) -> void:
	var collision_shape: CollisionShape2D = chunk.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var terrain_fill: Polygon2D = chunk.get_node_or_null("TerrainFill") as Polygon2D
	if collision_shape == null or terrain_fill == null:
		push_error("TerrainChunk requires CollisionShape2D and TerrainFill nodes.")
		return

	var surface_points: PackedVector2Array = PackedVector2Array()
	var segment_points: PackedVector2Array = PackedVector2Array()
	var chunk_start_x: float = float(chunk_index) * chunk_width
	var chunk_end_x: float = chunk_start_x + chunk_width
	var visual_sample_count: int = maxi(height_sample_count, 2)
	var visual_sample_world_xs: Array[float] = get_chunk_surface_sample_world_xs(chunk_start_x, chunk_end_x, visual_sample_count, true)
	# The collision vertices come from the shared cache, so the shape built here and the
	# slope angle the player steers along are literally the same numbers.
	ensure_chunk_collision_samples(chunk_index)
	var collision_sample_world_xs: PackedFloat64Array = chunk_collision_sample_xs[chunk_index]
	var collision_sample_heights: PackedFloat64Array = chunk_collision_sample_heights[chunk_index]
	var previous_collision_point: Vector2 = Vector2.ZERO

	for world_x: float in visual_sample_world_xs:
		var local_x: float = world_x - chunk_start_x - (chunk_width * 0.5)
		var surface_point: Vector2 = Vector2(local_x, get_terrain_height(world_x))
		surface_points.append(surface_point)

	var previous_collision_world_x: float = 0.0
	for sample_index: int in range(collision_sample_world_xs.size()):
		var world_x: float = collision_sample_world_xs[sample_index]
		var local_x: float = world_x - chunk_start_x - (chunk_width * 0.5)
		var point: Vector2 = Vector2(local_x, collision_sample_heights[sample_index])
		if sample_index > 0:
			# Chord MIDPOINT, not either endpoint. add_lip_sample_world_x has forced a vertex
			# exactly on each lip, so a chord is either wholly inside the void or wholly outside
			# it and its midpoint decides without ambiguity; an endpoint test would have to
			# answer "is the lip x itself in the void", which is a tie-break rather than a fact.
			# This is what guarantees no partial chord is ever left hanging over the gap.
			#
			# ConcavePolygonShape2D.set_segments() takes a segment SOUP, not a polyline, so
			# dropping interior chords leaves a valid shape with a hole in it.
			var chord_midpoint_world_x: float = (previous_collision_world_x + world_x) * 0.5
			if has_ground_at_world_x(chord_midpoint_world_x):
				segment_points.append(previous_collision_point)
				segment_points.append(point)
		previous_collision_point = point
		previous_collision_world_x = world_x

	# The sample ARRAYS above keep their void entries deliberately -- only chord EMISSION is
	# filtered. get_collision_chord_slope_angle() reads those same arrays and falls back to the
	# chunk's first and last vertex when nothing brackets world_x, so dropping the entries would
	# make it return an arbitrary 512px-chord angle over a void instead of the correct 0. That 0
	# is load-bearing: it is what carries a speed-boosting player across a chasm (see the boost
	# note in player.gd's velocity model and PowerupManager.can_end_speed_boost).
	var collision: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
	collision.set_segments(segment_points)
	collision_shape.shape = collision
	# Unreachable while CHASM_VOID_LENGTH < chunk_width, but the void length is a tunable and an
	# empty ConcavePolygonShape2D on a live StaticBody2D is not a case this project has exercised.
	collision_shape.disabled = segment_points.is_empty()

	build_chunk_fill(chunk, terrain_fill, surface_points, visual_sample_world_xs)


# One Polygon2D per contiguous run of ground. The visual sample list carries a vertex at every
# lip (add_lip_sample_world_x), so a run always begins and ends exactly on a lip and the void
# renders as a clean slot of background rather than a filled notch.
#
# The existing TerrainFill node keeps run 0, so the common case adds no node at all, and each
# run closes on ITS OWN x extent rather than +/- chunk_width * 0.5. On a chunk with no void
# there is exactly one run whose first and last samples ARE the chunk edges, so this produces a
# byte-identical polygon to the code it replaced -- that equivalence is the whole no-regression
# argument, and the disabled-chasm gate runs are what prove it.
#
# fill_bottom_y stays computed over the WHOLE chunk's surface points rather than per run, so
# neighbouring runs close at the same depth. Never hardcode it: baselines drift thousands of px
# down over a run (see TERRAIN_FILL_DEPTH_MARGIN).
func build_chunk_fill(chunk: StaticBody2D, terrain_fill: Polygon2D, surface_points: PackedVector2Array, surface_world_xs: Array[float]) -> void:
	var fill_bottom_y: float = get_fill_bottom_y(surface_points)
	var ground_runs: Array[PackedVector2Array] = split_surface_into_ground_runs(surface_points, surface_world_xs)
	if ground_runs.is_empty():
		terrain_fill.polygon = PackedVector2Array()
		return

	terrain_fill.polygon = close_fill_run(ground_runs[0], fill_bottom_y)
	for run_index: int in range(1, ground_runs.size()):
		var extra_fill: Polygon2D = Polygon2D.new()
		extra_fill.name = "TerrainFill%d" % run_index
		extra_fill.polygon = close_fill_run(ground_runs[run_index], fill_bottom_y)
		chunk.add_child(extra_fill)


# A run breaks between two consecutive samples whose midpoint has no ground -- the same test
# build_chunk_surface applies to the collision chords, so the fill and the collision shape cut
# at exactly the same places.
func split_surface_into_ground_runs(surface_points: PackedVector2Array, surface_world_xs: Array[float]) -> Array[PackedVector2Array]:
	var ground_runs: Array[PackedVector2Array] = []
	var current_run: PackedVector2Array = PackedVector2Array()
	for sample_index: int in range(surface_points.size()):
		if sample_index > 0:
			var chord_midpoint_world_x: float = (surface_world_xs[sample_index - 1] + surface_world_xs[sample_index]) * 0.5
			if not has_ground_at_world_x(chord_midpoint_world_x):
				if current_run.size() >= 2:
					ground_runs.append(current_run)
				current_run = PackedVector2Array()
		current_run.append(surface_points[sample_index])

	if current_run.size() >= 2:
		ground_runs.append(current_run)
	return ground_runs


func close_fill_run(run_points: PackedVector2Array, fill_bottom_y: float) -> PackedVector2Array:
	var fill_points: PackedVector2Array = run_points.duplicate()
	fill_points.append(Vector2(run_points[run_points.size() - 1].x, fill_bottom_y))
	fill_points.append(Vector2(run_points[0].x, fill_bottom_y))
	return fill_points


func get_fill_bottom_y(surface_points: PackedVector2Array) -> float:
	var max_surface_y: float = surface_points[0].y
	for surface_point: Vector2 in surface_points:
		max_surface_y = maxf(max_surface_y, surface_point.y)
	return max_surface_y + TERRAIN_FILL_DEPTH_MARGIN


# Builds (once per chunk) the exact vertex list the chunk's ConcavePolygonShape2D is
# made of, plus the terrain height at each vertex.
#
# This is the single source of both the collision shape and the slope angle the player
# steers along. build_chunk_surface() and get_collision_chord_slope_angle() previously
# each called get_chunk_surface_sample_world_xs() separately and trusted a comment that
# the two agreed; now they read the same array, so agreement is structural.
#
# Safe to cache because everything feeding it is pure in (session_seed, world_x):
# session_seed is assigned in _ready() before initialize_chunks(), so no entry can be
# built against a stale seed, and get_terrain_height() is a documented pure function.
func ensure_chunk_collision_samples(chunk_index: int) -> void:
	if chunk_collision_sample_xs.has(chunk_index):
		return

	var chunk_start_x: float = float(chunk_index) * chunk_width
	var chunk_end_x: float = chunk_start_x + chunk_width
	var collision_sample_count: int = maxi(ceili(chunk_width / MAX_COLLISION_SEGMENT_LENGTH), 2)
	var sample_world_xs: Array[float] = get_chunk_surface_sample_world_xs(chunk_start_x, chunk_end_x, collision_sample_count, true)

	var cached_world_xs: PackedFloat64Array = PackedFloat64Array()
	var cached_heights: PackedFloat64Array = PackedFloat64Array()
	cached_world_xs.resize(sample_world_xs.size())
	cached_heights.resize(sample_world_xs.size())
	for sample_index: int in range(sample_world_xs.size()):
		var world_x: float = sample_world_xs[sample_index]
		cached_world_xs[sample_index] = world_x
		cached_heights[sample_index] = get_terrain_height(world_x)

	chunk_collision_sample_xs[chunk_index] = cached_world_xs
	chunk_collision_sample_heights[chunk_index] = cached_heights
	prune_chunk_collision_samples(chunk_index)


func prune_chunk_collision_samples(around_chunk_index: int) -> void:
	if chunk_collision_sample_xs.size() <= (CHUNK_COLLISION_SAMPLE_CACHE_RADIUS * 2) + 1:
		return

	var cached_chunk_indices: Array[int] = chunk_collision_sample_xs.keys()
	for cached_chunk_index: int in cached_chunk_indices:
		if absi(cached_chunk_index - around_chunk_index) > CHUNK_COLLISION_SAMPLE_CACHE_RADIUS:
			chunk_collision_sample_xs.erase(cached_chunk_index)
			chunk_collision_sample_heights.erase(cached_chunk_index)


func get_chunk_surface_sample_world_xs(chunk_start_x: float, chunk_end_x: float, sample_count: int, include_segment_boundaries: bool) -> Array[float]:
	var sample_world_xs: Array[float] = []
	var safe_sample_count: int = maxi(sample_count, 2)
	for sample_index: int in range(safe_sample_count + 1):
		var progress: float = float(sample_index) / float(safe_sample_count)
		add_unique_sample_world_x(sample_world_xs, chunk_start_x + (progress * (chunk_end_x - chunk_start_x)))

	if include_segment_boundaries:
		add_segment_boundary_sample_world_xs(sample_world_xs, chunk_start_x, chunk_end_x)

	sample_world_xs.sort()
	return sample_world_xs


func add_segment_boundary_sample_world_xs(sample_world_xs: Array[float], chunk_start_x: float, chunk_end_x: float) -> void:
	ensure_segment_cache_for_world_x(chunk_start_x)
	ensure_segment_cache_for_world_x(chunk_end_x)
	var first_segment_index: int = find_segment_index_at_x(chunk_start_x)
	var last_segment_index: int = find_segment_index_at_x(chunk_end_x - 0.001)
	for segment_index: int in range(first_segment_index + 1, last_segment_index + 1):
		add_unique_sample_world_x(sample_world_xs, segment_start_x_cache[segment_index])

	# A vertex EXACTLY on each chasm lip, for the same reason segment starts get one: it is
	# what guarantees no chord or fill edge ever half-spans the void, so the midpoint tests in
	# build_chunk_surface and split_surface_into_ground_runs decide on a fact rather than a
	# tie-break. Both the collision samples and the visual samples come through here, so the
	# two cut at literally the same x.
	#
	# Note this range STARTS at first_segment_index, unlike the loop above: a chasm segment can
	# begin before this chunk and still place a lip inside it.
	for segment_index: int in range(first_segment_index, last_segment_index + 1):
		var void_span: Dictionary = get_void_span_for_segment(segment_index)
		if void_span.is_empty():
			continue
		add_lip_sample_world_x(sample_world_xs, float(void_span["start_x"]), chunk_start_x, chunk_end_x)
		add_lip_sample_world_x(sample_world_xs, float(void_span["end_x"]), chunk_start_x, chunk_end_x)


# Strictly interior: a lip outside this chunk is already cut by the chunk's own boundary
# sample, and adding an out-of-range x would push the sample list past the chunk's extent and
# break both the chord bracketing and the fill's x span.
func add_lip_sample_world_x(sample_world_xs: Array[float], lip_world_x: float, chunk_start_x: float, chunk_end_x: float) -> void:
	if lip_world_x > chunk_start_x and lip_world_x < chunk_end_x:
		add_unique_sample_world_x(sample_world_xs, lip_world_x)


func add_unique_sample_world_x(sample_world_xs: Array[float], world_x: float) -> void:
	for existing_world_x: float in sample_world_xs:
		if absf(existing_world_x - world_x) <= 0.001:
			return
	sample_world_xs.append(world_x)


# Single dispatch point for terrain shape. Every other place that used to branch on
# segment_type/tier independently (baseline_delta, length, the selection label) now
# reads the same SegmentSpec this builds, so there is exactly one place that decides
# what a segment looks like.
func get_terrain_height(world_x: float) -> float:
	ensure_segment_cache_for_world_x(world_x)
	var segment_index: int = find_segment_index_at_x(world_x)
	var segment_start_x: float = segment_start_x_cache[segment_index]

	var segment_x: float = world_x - segment_start_x
	var spec: Dictionary = get_segment_spec(segment_index)
	var segment_baseline: float = get_segment_baseline(segment_index)
	var segment_progress: float = segment_x / float(spec["length"])
	return segment_baseline + evaluate_segment_offset(spec, segment_progress)


# Whether there is collidable ground at world_x. Pure in (session_seed, world_x), the same
# contract as get_terrain_height(), and deliberately ORTHOGONAL to it: get_terrain_height()
# returns the lip height inside a void, so "how high is the surface" and "is there a surface"
# are two independent facts. False only inside a chasm's void span.
#
# Half-open [void_start_x, void_end_x): the lip x itself counts as ground, which is what lets
# build_chunk_surface decide each collision chord by its MIDPOINT rather than by a tie-break
# at the endpoint.
func has_ground_at_world_x(world_x: float) -> bool:
	var void_span: Dictionary = get_void_span_at_world_x(world_x)
	if void_span.is_empty():
		return true
	return world_x < float(void_span["start_x"]) or world_x >= float(void_span["end_x"])


# The void span of the segment containing world_x, or {} if that segment has none.
func get_void_span_at_world_x(world_x: float) -> Dictionary:
	ensure_segment_cache_for_world_x(world_x)
	return get_void_span_for_segment(find_segment_index_at_x(world_x))


# Dictionary of GDScript floats (doubles), never a Vector2: Vector2 is float32, and at
# world_x = 200,000 its ulp is 0.0156px, which would move a lip vertex relative to the
# float64 chunk_collision_sample_xs. Narrowing terrain geometry to float32 is the exact
# shape of an already-fixed freeze bug -- see the comment on that cache above.
func get_void_span_for_segment(segment_index: int) -> Dictionary:
	var spec: Dictionary = get_segment_spec(segment_index)
	var void_length: float = float(spec.get("void_length", 0.0))
	if void_length <= 0.0:
		return {}

	ensure_segment_cache_through(segment_index)
	var void_start_x: float = segment_start_x_cache[segment_index] + float(spec["void_start_offset"])
	return {"start_x": void_start_x, "end_x": void_start_x + void_length}


# True only if there is ground across the WHOLE span. Walks segments rather than
# point-sampling, so it cannot step over a void narrower than a sample stride.
func has_ground_over_world_x_span(from_world_x: float, to_world_x: float) -> bool:
	ensure_segment_cache_for_world_x(from_world_x)
	ensure_segment_cache_for_world_x(to_world_x)
	var first_segment_index: int = find_segment_index_at_x(from_world_x)
	var last_segment_index: int = find_segment_index_at_x(to_world_x)
	for segment_index: int in range(first_segment_index, last_segment_index + 1):
		var void_span: Dictionary = get_void_span_for_segment(segment_index)
		if void_span.is_empty():
			continue
		if from_world_x < float(void_span["end_x"]) and to_world_x >= float(void_span["start_x"]):
			return false
	return true


# world_x itself if it is on ground, otherwise the first ground x past the void it sits in.
# For PowerupSpawner, which has exactly one candidate position per scheduled spawn and must
# nudge rather than silently drop a scheduled reward.
func get_next_ground_world_x(world_x: float) -> float:
	# Guard on has_ground_at_world_x, not on "world_x < start_x". A chasm segment continues for
	# several hundred px PAST its far lip, so a world_x on that exit flat still resolves to this
	# segment's void span while being perfectly good ground -- pushing it to end_x would move
	# the item BACKWARDS, potentially behind the player.
	if has_ground_at_world_x(world_x):
		return world_x

	var void_span: Dictionary = get_void_span_at_world_x(world_x)
	return float(void_span["end_x"]) + CHASM_LIP_CLEARANCE


# O(1) in segment_index: one integer division and one hash. No neighbour lookback, no
# recursive segment lookup (mega_drop's mutual recursion was a measured frame-time spike),
# and no read of segment_start_x_cache -- see the comment in build_segment_spec.
func is_chasm_segment_index(segment_index: int) -> bool:
	if debug_chasm_disabled or segment_index < CHASM_MIN_SEGMENT_INDEX:
		return false

	# CHASM_MIN_SEGMENT_INDEX > 0, so the guard above means segment_index is positive here
	# and GDScript's sign-following % cannot bite. Negative indices are real: initialize_chunks
	# spawns from chunk_count_behind chunks before the player.
	var window_segment_count: int = CHASM_REHEARSAL_WINDOW_SEGMENT_COUNT if debug_drop_chasm_rehearsal else CHASM_WINDOW_SEGMENT_COUNT
	var edge_margin_segments: int = CHASM_REHEARSAL_WINDOW_EDGE_MARGIN_SEGMENTS if debug_drop_chasm_rehearsal else CHASM_WINDOW_EDGE_MARGIN_SEGMENTS
	var window_index: int = segment_index / window_segment_count
	var offset_in_window: int = segment_index % window_segment_count
	var usable_offset_count: int = window_segment_count - (2 * edge_margin_segments)
	var chasm_offset: int = edge_margin_segments + (get_chasm_hash(window_index) % usable_offset_count)
	return offset_in_window == chasm_offset


# Separate hash from get_segment_hash: it is keyed on the WINDOW, not the segment, and using
# distinct multipliers keeps chasm placement uncorrelated with the shape draw of the segment
# it replaces.
func get_chasm_hash(window_index: int) -> int:
	var mixed_value: int = (session_seed ^ ((window_index + 1) * CHASM_HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * CHASM_HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return mixed_value


# Which width variant this chasm gets. Weighted draw restricted to the variants legal at this
# segment index, so a wide chasm can never appear before the speed ramp can clear it -- the
# gate is structural rather than a check that happens to pass.
#
# O(1) (a fixed 3-entry table), pure in (session_seed, segment_index), and reads no cache, for
# the same reasons is_chasm_segment_index() does none of those things.
func get_chasm_variant(segment_index: int) -> Dictionary:
	if debug_drop_chasm_rehearsal:
		for variant: Dictionary in CHASM_VARIANTS:
			if float(variant.get("exit_drop", 0.0)) > 0.0:
				return variant

	var total_weight: int = 0
	for variant: Dictionary in CHASM_VARIANTS:
		if segment_index >= int(variant["min_segment_index"]):
			total_weight += int(variant["weight"])

	# Only reachable if every variant's min_segment_index were raised above
	# CHASM_MIN_SEGMENT_INDEX, which the constants block forbids. Falling back to the narrowest
	# variant rather than dividing by zero keeps a future edit from crashing the generator.
	if total_weight <= 0:
		return CHASM_VARIANTS[0]

	var remaining_weight: int = get_chasm_variant_hash(segment_index) % total_weight
	for variant: Dictionary in CHASM_VARIANTS:
		if segment_index < int(variant["min_segment_index"]):
			continue
		remaining_weight -= int(variant["weight"])
		if remaining_weight < 0:
			return variant

	return CHASM_VARIANTS[0]


# Keyed on the SEGMENT, unlike get_chasm_hash() which is keyed on the window. See the salt.
func get_chasm_variant_hash(segment_index: int) -> int:
	var mixed_value: int = (session_seed ^ CHASM_VARIANT_HASH_SALT ^ ((segment_index + 1) * CHASM_HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * CHASM_HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return mixed_value


# The height offset from baseline at a given progress [0, 1] through the segment.
# Evaluating this at progress=1.0 is exactly the segment's baseline delta -- see
# get_segment_baseline_delta() -- so continuity between segments is guaranteed by
# construction instead of by a hand-maintained duplicate of each shape's endpoint.
func evaluate_segment_offset(spec: Dictionary, segment_progress: float) -> float:
	var segment_type: int = int(spec["type"])
	var magnitude: float = float(spec["magnitude"])
	if segment_type == SEGMENT_TYPE_FLAT:
		return get_exit_drop_offset(spec, segment_progress)
	if segment_type == SEGMENT_TYPE_DOWNHILL:
		return get_transition_profile(segment_progress) * magnitude
	if segment_type == SEGMENT_TYPE_UPHILL:
		return -get_transition_profile(segment_progress) * magnitude
	if segment_type == SEGMENT_TYPE_HILL:
		# Godot's Y axis points down, so subtracting raises the hill visually.
		return -get_curve_profile(segment_progress) * magnitude

	# Adding the same profile mirrors the hill into a valley below baseline.
	return get_curve_profile(segment_progress) * magnitude


# 0 everywhere up to a drop chasm's far lip, exit_drop from the far lip onward -- so the void
# itself reads as ordinary flat ground at NEAR-lip height and only the far lip steps down. See
# the CHASM_EXIT_DROP block for why a step beats a ramp here.
#
# Evaluating this at progress 1.0 yields exit_drop, which is exactly the segment's baseline
# delta, so the following segment starts at the lower height with no separate bookkeeping --
# the same "derive the delta from the shape" contract every other profile honours.
#
# Non-chasm flat segments carry no exit_drop key and return 0.0 through the first branch, so
# this is a no-op for them.
# How much further down real ground lies than get_terrain_height() reports at this world_x.
# Non-zero ONLY inside a drop chasm's void, where the field deliberately reads NEAR-lip height
# but the ground the player is falling toward is the far lip, exit_drop below.
#
# Player.update_fall_death() adds this to the surface it measures against. Without it a drop
# chasm kills the player mid-crossing for doing exactly what the feature asks: at 545 px/s a
# 320px void takes 0.587s, which is a 276px fall against a FALL_DEATH_DEPTH of 200.
#
# Exactly 0 for a level-lipped chasm, so the hazard variants' death behaviour -- the thing
# that makes them hazards -- is bit-identical to phase 2.
func get_pending_exit_drop_at_world_x(world_x: float) -> float:
	var void_span: Dictionary = get_void_span_at_world_x(world_x)
	if void_span.is_empty():
		return 0.0
	if world_x < float(void_span["start_x"]) or world_x >= float(void_span["end_x"]):
		return 0.0

	var spec: Dictionary = get_segment_spec(find_segment_index_at_x(world_x))
	return float(spec.get("exit_drop", 0.0))


func get_exit_drop_offset(spec: Dictionary, segment_progress: float) -> float:
	var exit_drop: float = float(spec.get("exit_drop", 0.0))
	if exit_drop <= 0.0:
		return 0.0

	var void_end_offset: float = float(spec["void_start_offset"]) + float(spec["void_length"])
	# Half-open to match has_ground_at_world_x: the far lip x is ground, and it is the first x
	# at the LOWER height.
	if (segment_progress * float(spec["length"])) < void_end_offset:
		return 0.0
	return exit_drop


# World-space Y of the terrain surface at world_x. get_terrain_height() alone is a
# local offset from ground_y; this adds the generator's own Y, which world rebasing
# moves, so callers outside the chunk hierarchy get a coordinate they can compare
# against global_position.
func get_surface_world_y(world_x: float) -> float:
	return global_position.y + ground_y + get_terrain_height(world_x)


func get_segment_baseline(segment_index: int) -> float:
	ensure_segment_cache_through(segment_index)
	return segment_baseline_cache[segment_index]


func initialize_segment_cache() -> void:
	segment_start_x_cache.clear()
	segment_length_cache.clear()
	segment_baseline_cache.clear()
	segment_spec_cache.clear()
	segment_start_x_cache[0] = 0.0
	segment_length_cache[0] = get_segment_length(0)
	segment_baseline_cache[0] = surface_y_offset
	lowest_cached_segment_index = 0
	highest_cached_segment_index = 0


func ensure_segment_cache_for_world_x(world_x: float) -> void:
	if world_x >= 0.0:
		while world_x >= get_cached_segment_end_x(highest_cached_segment_index):
			cache_next_segment()
	else:
		while world_x < segment_start_x_cache[lowest_cached_segment_index]:
			cache_previous_segment()


func ensure_segment_cache_through(segment_index: int) -> void:
	while highest_cached_segment_index < segment_index:
		cache_next_segment()
	while lowest_cached_segment_index > segment_index:
		cache_previous_segment()


func cache_next_segment() -> void:
	var previous_segment_index: int = highest_cached_segment_index
	var segment_index: int = previous_segment_index + 1
	var segment_start_x: float = get_cached_segment_end_x(previous_segment_index)
	segment_start_x_cache[segment_index] = segment_start_x
	segment_length_cache[segment_index] = get_segment_length(segment_index)
	segment_baseline_cache[segment_index] = segment_baseline_cache[previous_segment_index] + get_segment_baseline_delta(previous_segment_index)
	highest_cached_segment_index = segment_index


func cache_previous_segment() -> void:
	var next_segment_index: int = lowest_cached_segment_index
	var segment_index: int = next_segment_index - 1
	var segment_length: float = get_segment_length(segment_index)
	segment_start_x_cache[segment_index] = segment_start_x_cache[next_segment_index] - segment_length
	segment_length_cache[segment_index] = segment_length
	segment_baseline_cache[segment_index] = segment_baseline_cache[next_segment_index] - get_segment_baseline_delta(segment_index)
	lowest_cached_segment_index = segment_index


func get_cached_segment_end_x(segment_index: int) -> float:
	return segment_start_x_cache[segment_index] + segment_length_cache[segment_index]


func find_segment_index_at_x(world_x: float) -> int:
	var lower_index: int = lowest_cached_segment_index
	var upper_index: int = highest_cached_segment_index
	while lower_index <= upper_index:
		var middle_index: int = floori(float(lower_index + upper_index) / 2.0)
		var middle_start_x: float = segment_start_x_cache[middle_index]
		var middle_end_x: float = get_cached_segment_end_x(middle_index)
		if world_x < middle_start_x:
			upper_index = middle_index - 1
		elif world_x >= middle_end_x:
			lower_index = middle_index + 1
		else:
			return middle_index
	return clampi(lower_index, lowest_cached_segment_index, highest_cached_segment_index)


# Derived, not hand-written: evaluating the segment's own shape function at
# progress=1.0 is its endpoint value by definition, so this cannot drift out of sync
# with evaluate_segment_offset the way a separately-maintained delta could.
func get_segment_baseline_delta(segment_index: int) -> float:
	return evaluate_segment_offset(get_segment_spec(segment_index), 1.0)


func get_segment_tier(segment_index: int) -> int:
	return int(get_segment_spec(segment_index)["tier"])


func get_segment_length(segment_index: int) -> float:
	return float(get_segment_spec(segment_index)["length"])


func get_segment_type(segment_index: int) -> int:
	return int(get_segment_spec(segment_index)["type"])


func get_segment_selection_label(segment_index: int) -> String:
	return String(get_segment_spec(segment_index)["label"])


# mega_drop is a single segment (not the old 4-linear-segment chain), so this is a
# direct label check with no recursion or neighbour lookback.
func is_mega_drop_segment(segment_index: int) -> bool:
	return String(get_segment_spec(segment_index)["label"]) == "mega_drop"


func get_segment_spec(segment_index: int) -> Dictionary:
	if not segment_spec_cache.has(segment_index):
		segment_spec_cache[segment_index] = build_segment_spec(segment_index)
	return segment_spec_cache[segment_index]


# The one place that decides what a segment IS: its shape, length, magnitude (drop
# depth / rise height / hill-or-valley amplitude -- one field, since evaluate_segment_offset
# uses it identically per type), tier, and debug label. Everything else in this file
# reads this instead of re-deriving it.
func build_segment_spec(segment_index: int) -> Dictionary:
	# Chasm overrides the weighted selection entirely rather than joining the weight table:
	# its rarity is a guaranteed minimum SPACING, which a weight cannot express. See the
	# CHASM_ constants block and is_chasm_segment_index().
	#
	# SEGMENT_TYPE_FLAT with magnitude 0 means evaluate_segment_offset needs no new branch
	# and get_segment_baseline_delta() derives 0.0 from it, so C0 continuity across the
	# seams stays guaranteed by construction. The two extra keys are read only through
	# .get(key, default), so the other six spec literals below stay untouched.
	#
	# This also leaves the "no two flats in a row" rule alone: get_segment_selection()
	# consults get_unconstrained_segment_selection(), which never comes through here, so a
	# chasm is invisible to its neighbours' selection.
	if is_chasm_segment_index(segment_index):
		var chasm_variant: Dictionary = get_chasm_variant(segment_index)
		return {
			"type": SEGMENT_TYPE_FLAT,
			"tier": SEGMENT_TIER_MEDIUM,
			"length": float(chasm_variant.get("segment_length", CHASM_SEGMENT_LENGTH)),
			"magnitude": 0.0,
			"label": String(chasm_variant["label"]),
			"void_start_offset": CHASM_LEAD_IN_LENGTH,
			"void_length": float(chasm_variant["void_length"]),
			"exit_drop": float(chasm_variant.get("exit_drop", CHASM_EXIT_DROP)),
			"must_be_jumped": bool(chasm_variant.get("must_be_jumped", true)),
		}

	var segment_selection: int = get_segment_selection(segment_index)

	if segment_selection == SEGMENT_SELECTION_MEGA_DROP:
		return {
			"type": SEGMENT_TYPE_DOWNHILL,
			"tier": SEGMENT_TIER_MEDIUM,
			"length": get_mega_drop_length(),
			"magnitude": MEGA_DROP_TOTAL_VERTICAL_DROP,
			"label": "mega_drop",
		}
	if segment_selection == SEGMENT_SELECTION_FLAT:
		return {
			"type": SEGMENT_TYPE_FLAT,
			"tier": SEGMENT_TIER_MEDIUM,
			"length": MEDIUM_SEGMENT_LENGTH,
			"magnitude": 0.0,
			"label": "flat",
		}
	if segment_selection == SEGMENT_SELECTION_BIG_DOWNHILL:
		return {
			"type": SEGMENT_TYPE_DOWNHILL,
			"tier": SEGMENT_TIER_MEDIUM,
			"length": SUSTAINED_DOWNHILL_LENGTH,
			"magnitude": SUSTAINED_DOWNHILL_DROP,
			"label": "sustained_downhill",
		}
	if segment_selection == SEGMENT_SELECTION_GENTLE_UPHILL:
		return {
			"type": SEGMENT_TYPE_UPHILL,
			"tier": SEGMENT_TIER_MEDIUM,
			"length": GENTLE_UPHILL_LENGTH,
			"magnitude": GENTLE_UPHILL_RISE,
			"label": "gentle_uphill",
		}
	if segment_selection == SEGMENT_SELECTION_SMALL_HILL:
		return {
			"type": SEGMENT_TYPE_HILL,
			"tier": SEGMENT_TIER_SMALL,
			"length": SMALL_SEGMENT_LENGTH,
			"magnitude": SMALL_HILL_AMPLITUDE,
			"label": "small_hill",
		}

	# SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX
	var segment_type: int = get_medium_mix_segment_type(segment_index)
	var label: String = "medium_hill" if segment_type == SEGMENT_TYPE_HILL else "medium_valley"
	return {
		"type": segment_type,
		"tier": SEGMENT_TIER_MEDIUM,
		"length": MEDIUM_SEGMENT_LENGTH,
		"magnitude": MEDIUM_HILL_AMPLITUDE,
		"label": label,
	}


func get_mega_drop_angle() -> float:
	return session_floor_max_angle * MEGA_DROP_FLOOR_ANGLE_FRACTION


# Length whose PEAK chord angle (of the same ease-in/out profile every other feature
# uses) lands exactly at get_mega_drop_angle(). Same derivation the old large_valley
# floor-angle minimum used: the ease curve's steepest point has slope
# (TOTAL_VERTICAL_DROP / length) * (PI / 2), solved for length at the target angle.
# floor_max_angle > 0 always in this project (see CLAUDE.md), so no zero-angle guard.
func get_mega_drop_length() -> float:
	return (MEGA_DROP_TOTAL_VERTICAL_DROP * PI) / (2.0 * tan(get_mega_drop_angle()))


func create_session_seed() -> int:
	var seed_generator: RandomNumberGenerator = RandomNumberGenerator.new()
	seed_generator.randomize()
	return int(seed_generator.randi())


func get_segment_selection(segment_index: int) -> int:
	var segment_selection: int = get_unconstrained_segment_selection(segment_index)
	if segment_selection != SEGMENT_SELECTION_FLAT:
		return segment_selection

	var previous_segment_selection: int = get_unconstrained_segment_selection(segment_index - 1)
	if previous_segment_selection != SEGMENT_SELECTION_FLAT:
		return segment_selection

	# The "no two flats in a row" rule assumes some other shape has weight to spend --
	# true whenever the shipping mix is in play. At the flat-only complexity level
	# every non-flat weight is 0, so there is no alternative to fall back to; without
	# this guard get_non_flat_segment_selection's fallback would force a hill in
	# anyway, breaking flat-only bisection. get_segment_selection_total_weight floors
	# at 1 for safe division elsewhere, so the raw sum is checked directly here.
	if not has_any_non_flat_weight():
		return segment_selection

	return get_non_flat_segment_selection(segment_index)


func has_any_non_flat_weight() -> bool:
	for entry: Dictionary in segment_selection_weight_table:
		var selection: int = int(entry["selection"])
		var weight: int = int(entry["weight"])
		if selection != SEGMENT_SELECTION_FLAT and weight > 0:
			return true
	return false


func get_unconstrained_segment_selection(segment_index: int) -> int:
	return get_weighted_segment_selection(get_segment_hash(segment_index))


func get_non_flat_segment_selection(segment_index: int) -> int:
	var total_weight: int = get_segment_selection_total_weight(false)
	var random_value: int = (get_segment_hash(segment_index) >> 8) % total_weight
	var accumulated_weight: int = 0
	for entry: Dictionary in segment_selection_weight_table:
		var selection: int = int(entry["selection"])
		var weight: int = int(entry["weight"])
		if selection == SEGMENT_SELECTION_FLAT or weight <= 0:
			continue
		accumulated_weight += weight
		if random_value < accumulated_weight:
			return selection
	return SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX


func get_weighted_segment_selection(random_value: int) -> int:
	var total_weight: int = get_segment_selection_total_weight(true)
	var weighted_value: int = random_value % total_weight
	var accumulated_weight: int = 0
	for entry: Dictionary in segment_selection_weight_table:
		var weight: int = int(entry["weight"])
		if weight <= 0:
			continue
		accumulated_weight += weight
		if weighted_value < accumulated_weight:
			return int(entry["selection"])
	return SEGMENT_SELECTION_MEDIUM_HILL_VALLEY_MIX


func get_segment_selection_total_weight(include_flat: bool) -> int:
	var total_weight: int = 0
	for entry: Dictionary in segment_selection_weight_table:
		var selection: int = int(entry["selection"])
		var weight: int = int(entry["weight"])
		if weight <= 0:
			continue
		if not include_flat and selection == SEGMENT_SELECTION_FLAT:
			continue
		total_weight += weight
	return maxi(total_weight, 1)


func get_medium_mix_segment_type(segment_index: int) -> int:
	var random_value: int = get_segment_hash(segment_index) >> 8
	if random_value % 2 == 0:
		return SEGMENT_TYPE_HILL
	return SEGMENT_TYPE_VALLEY


func get_segment_hash(segment_index: int) -> int:
	var mixed_value: int = (session_seed ^ (segment_index * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return mixed_value


func get_curve_profile(segment_progress: float) -> float:
	return pow(sin(segment_progress * PI), 2.0)


func get_transition_profile(segment_progress: float) -> float:
	return 0.5 - (0.5 * cos(segment_progress * PI))


func log_debug_segment_selection(start_segment_index: int, segment_count: int) -> void:
	print("Terrain segment selection debug: session_seed=", session_seed)
	for segment_index: int in range(start_segment_index, start_segment_index + segment_count):
		print(
			"segment ",
			segment_index,
			": ",
			get_segment_selection_label(segment_index)
		)


func get_slope_angle_at_x(world_x: float) -> float:
	var left_height: float = get_terrain_height(world_x - SLOPE_SAMPLE_DISTANCE)
	var right_height: float = get_terrain_height(world_x + SLOPE_SAMPLE_DISTANCE)
	return atan2(right_height - left_height, SLOPE_SAMPLE_DISTANCE * 2.0)


# The slope of the actual 16px-ish chord the collision polyline uses at world_x, not
# the continuous height field. get_slope_angle_at_x's +/-2px finite difference is an
# analytic approximation that can disagree with the physical chord underfoot by a
# couple of degrees on curved terrain -- the player was being aimed along that
# analytic angle while physically resting on the chord, injecting spurious vertical
# velocity every chord. Reuses the identical sample-point construction
# build_chunk_surface feeds into ConcavePolygonShape2D, so the two can't disagree.
# Called once per physics frame by Player.get_slope_tangent(), so it is the hottest
# terrain query in the game. It used to rebuild the chunk's entire sample array on every
# call -- a fresh allocation, an O(n^2) uniqueness scan (~545 float comparisons), a
# sort, two segment-cache ensures and two binary searches -- purely to read two
# neighbouring vertices of a polyline that was already built when the chunk spawned.
# Now it indexes the cache built at chunk-build time: no allocation, no rebuild.
#
# The bracketing search below is deliberately still linear rather than a binary search.
# It is a scan of ~33 entries, it is no longer the expensive part, and keeping it
# preserves the original tie-breaking exactly: the FIRST bracketing pair wins, and a
# world_x outside the sampled range falls back to the chunk's first and last vertex.
# Verified byte-identical over 20,000 samples before and after this change.
func get_collision_chord_slope_angle(world_x: float) -> float:
	var chunk_index: int = int(floor(world_x / chunk_width))
	ensure_chunk_collision_samples(chunk_index)
	var sample_world_xs: PackedFloat64Array = chunk_collision_sample_xs[chunk_index]
	var sample_heights: PackedFloat64Array = chunk_collision_sample_heights[chunk_index]

	var last_sample_index: int = sample_world_xs.size() - 1
	var left_sample_index: int = 0
	var right_sample_index: int = last_sample_index
	for sample_index: int in range(last_sample_index):
		if world_x >= sample_world_xs[sample_index] and world_x <= sample_world_xs[sample_index + 1]:
			left_sample_index = sample_index
			right_sample_index = sample_index + 1
			break

	return atan2(
		sample_heights[right_sample_index] - sample_heights[left_sample_index],
		sample_world_xs[right_sample_index] - sample_world_xs[left_sample_index],
	)


# Every Polygon2D child, not just TerrainFill: a chunk containing a chasm lip carries one
# extra fill per contiguous ground run (build_chunk_fill).
func apply_chunk_color(chunk: StaticBody2D, chunk_index: int) -> void:
	var chunk_color: Color = LIGHT_CHUNK_COLOR if chunk_index % 2 == 0 else DARK_CHUNK_COLOR
	for child: Node in chunk.get_children():
		var terrain_fill: Polygon2D = child as Polygon2D
		if terrain_fill != null:
			terrain_fill.color = chunk_color
