extends Node2D

class_name ObstacleSpawner

# Same reasoning as CoinSpawner: a child of TerrainGenerator so world rebasing
# (which shifts TerrainGenerator.position.y directly in main.gd) carries every
# spawned obstacle along for free.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")

# Debug/testing aid, same pattern as Main.world_rebase_enabled / Player.
# DEBUG_LOG_FREEZE_REPRO / GameManager.require_start_screen: a plain script var,
# not @export (so it can't get silently serialized into main.tscn), checked
# directly in _physics_process(). Deliberately NOT done via set_physics_process(
# false) -- that call does not reliably suppress this node's _physics_process in
# the headless debug-harness contexts that need it (verified: is_physics_processing()
# reported false while _physics_process kept firing every frame regardless).
# Harnesses that run long enough to reach a pattern's trigger time
# (freeze_search.gd, freeze_ab_runner.gd, stall_recovery_probe.gd,
# camera_shake_probe.gd, floor_flicker_probe.gd, freeze_replay_runner.gd) set this
# to true before add_child(main).
var debug_spawning_disabled: bool = false

const OBSTACLE_SCENE: PackedScene = preload("res://scenes/obstacles/obstacle.tscn")
# Half of obstacle.tscn's RectangleShape2D size (32x32), so the box sits on top of
# the surface rather than centered on it or floating above it.
const OBSTACLE_HALF_HEIGHT: float = 16.0
# What the scenes' own ColorRects are authored in, for a node spawned before any biome push.
const DEFAULT_OBSTACLE_COLOR: Color = Color(1.0, 0.1, 0.1, 1.0)
# Only place on close-to-flat ground: an obstacle glued to a slope reads as
# unfair (its hitbox stops matching what the eye expects the moment the surface
# tilts under it), and a steep approach also eats into the player's reaction
# window. get_slope_angle_at_x is the analytic (cosmetic) angle -- fine here,
# unlike Player.get_slope_tangent(), since nothing physical rides on this value.
const OBSTACLE_MAX_SLOPE_ANGLE: float = deg_to_rad(6.0)
# How finely the footprint guard walks a pattern's span for slope and lake. Half a hitbox,
# so no piece can sit on a sample-free stretch.
const FOOTPRINT_SAMPLE_STEP: float = 16.0
# Chasm exclusion around a pattern's span. AHEAD covers the longest jump a player can take off
# the last piece: max upgrade with the sqrt(2) jump powerup, 1.13s of airtime, 848px at
# MAX_SPEED, plus margin. It was 700 until 2026-09-27, which covered only the unboosted 600px,
# so a late boosted jump over an obstacle 700-850px before a void could land in it. BEHIND only
# has to stop a piece sitting on the landing side of a far lip. It covers a SINGLE jump on
# purpose: a double jump (up to 1,697px) off the last piece is a second tap the player chose,
# the same call as taking one into a chasm (Player.try_double_jump).
const OBSTACLE_VOID_CLEARANCE_AHEAD: float = 950.0
const OBSTACLE_VOID_CLEARANCE_BEHIND: float = 200.0
# Clamp on how close to spawn a pattern can ever land: the old hand-placed
# obstacle at (68,56) killed the player mid-jump at t=0.10s
# (docs/development/dead_code.md) because it sat inside the player's very
# first few physics steps. FIRST_PATTERN_TIME being 20s already keeps well
# clear of this in practice; this is just a floor.
const MIN_SAFE_START_WORLD_X: float = 900.0

# Pattern cadence is timed against Player.speed_manager.elapsed_time, not a
# fixed world_x spacing: with the two-phase speed ramp (SpeedManager), a fixed
# world_x interval would take wildly different real time to reach depending on
# when in the ramp it falls, which is exactly the "not actually once a minute"
# bug this replaces.
#
# FIRST_PATTERN_TIME is left untouched: terrain_invariant_check derives the slowest speed a
# pattern is ever judged against from this constant (check_obstacle_clearance() and
# check_pattern_fairness()), and lowering it tightens those windows rather than loosening them.
const FIRST_PATTERN_TIME: float = 20.0
# Cadence ramps up in OBSTACLE_RAMP_WINDOW-second steps: ~1 pattern in the
# first window, ~2 in the second, ~3 in the third, and so on, each window's
# patterns spread by a randomized interval (not evenly spaced) drawn around
# that window's average. target_count is clamped at OBSTACLE_RAMP_MAX_COUNT
# so the density stops climbing once it's already denser than the speed ramp
# (which caps at t=120s, MAX_SPEED) can justify -- otherwise an endless run
# eventually asks for an impossible obstacle-per-second rate.
const OBSTACLE_RAMP_WINDOW: float = 30.0
const OBSTACLE_RAMP_MAX_COUNT: int = 6
# Absolute floor under tier 1's random interval regardless of how dense the ramp above wants to
# go. Tier 1 is the original ramp, start to start; every later tier uses TIERS' breathing room.
const RECURRING_PATTERN_MIN_INTERVAL_FLOOR: float = 4.0
# How long an illegal footprint waits before trying again, from 2026-09-27. Until then a slot
# that failed the guard was simply LOST, and the guard fails ~60% of the time (measured over
# three seeds: 37-41% of x positions pass), so most scheduled obstacles never appeared. Same
# retry shape as RareCoinSpawner's, which found the same problem first.
const FOOTPRINT_RETRY_DELAY: float = 1.0
# Before a retry, the guard is also asked at points further ahead, up to this far past the
# lookahead: a single fits ~92% of attempts within 500px. The pattern then arrives later by the
# same distance, which the next breathing room is measured from.
const FOOTPRINT_SEARCH_DISTANCE: float = 600.0
const FOOTPRINT_SEARCH_STEP: float = 50.0

# Beyond the forward view, so a pattern is never seen popping into existence. 800 was
# already short of a 20:9 phone's ~860px, and Main.PLAYER_SCREEN_X_FRACTION now shows
# ~1,270px ahead on 21:9. terrain_invariant_check's check_spawn_lookahead() asserts it.
const SPAWN_LOOKAHEAD_WORLD_X: float = 1500.0
# Well behind the player is safe to free -- a pattern this far back is done
# regardless of whether it was cleared or hit.
const DESPAWN_BEHIND_WORLD_X: float = 1500.0

# WHAT CAN BE PLACED. A piece kind is a scene PATH plus the two numbers that place it: half its
# hitbox width (its footprint along the ground) and how high its CENTRE sits above the surface.
# half_height is the hitbox's own, and only terrain_invariant_check reads it -- the fairness
# model needs the full rect, and check_spawn_placement() compares both against the real shape.
# All three kinds run obstacle.gd, so a hit, a shield and a boost break-through behave the same.
#
#   * SPIKE: 32x32 on the ground. Jump it.
#   * FLOE: an ice island with an icicle hanging to head height. Its hitbox is ONE column from
#     the icicle tip, 64px up (the standing capsule's 48 + 16 of margin), to 200px, and the
#     placeholder art is exactly that column. Staying grounded always passes under it; any jump
#     near it hits it. The floating-island look without a surface to stand on (HANDOFF, "Ideas
#     flagged and NOT planned", for why standing on one is out).
#   * SHARD: 32x32 floating at 64-96px. Levels 0-2 must stay under it; levels 3-4 can also
#     clear it (feet above 96), so an upgrade opens a route rather than only easing one.
#   * THIN ICE: a stretch of ground, not a body (ThinIce). A piece of this kind has a "length"
#     in seconds, and its footprint is that whole stretch. Keep hopping.
#
# "floating" marks kinds a glider could fly into: patterns holding one wait out a glide.
#
# PATHS, LOADED ON FIRST SPAWN, NOT preload(). Preloading floe.tscn and shard.tscn here made a
# load cycle: when this script is the first thing loaded, obstacle.gd is still mid-load (for
# OBSTACLE_SCENE) when those two ask for it, and they come back with NO SCRIPT -- a floe that
# never hurts anyone, with no error in the game. Measured 2026-09-27; main.tscn's own load
# order happened to hide it. load() is cached after the first call.
const PIECE_SPIKE: StringName = &"spike"
const PIECE_FLOE: StringName = &"floe"
const PIECE_SHARD: StringName = &"shard"
const PIECE_THIN_ICE: StringName = &"thin_ice"
const PIECE_KINDS: Dictionary = {
	PIECE_SPIKE: {"scene": "res://scenes/obstacles/obstacle.tscn", "half_width": 16.0, "half_height": OBSTACLE_HALF_HEIGHT,
		"center_height": OBSTACLE_HALF_HEIGHT, "floating": false},
	PIECE_FLOE: {"scene": "res://scenes/obstacles/floe.tscn", "half_width": 16.0, "half_height": 68.0,
		"center_height": 132.0, "floating": true},
	PIECE_SHARD: {"scene": "res://scenes/obstacles/shard.tscn", "half_width": 16.0, "half_height": 16.0,
		"center_height": 80.0, "floating": true},
	PIECE_THIN_ICE: {"scene": "", "half_width": 0.0, "half_height": 0.0,
		"center_height": 0.0, "floating": false},
}

# TIERS: a new idea about every minute, and less room between patterns. "start" is when a tier's
# patterns join the draw, in run seconds -- the speed there is the slowest its patterns are ever
# met at, which check_pattern_fairness() reads. "room" is the BREATHING ROOM, from one pattern's
# last piece to the next pattern's first, jittered +/-BREATHING_ROOM_JITTER. Tier 1 keeps the
# original interval ramp instead (room -1). The last tier's room keeps shrinking to the floor.
# Starting values from the HANDOFF plan, to be tuned by playing.
const TIERS: Array[Dictionary] = [
	{"start": FIRST_PATTERN_TIME, "room": -1.0},
	{"start": 60.0, "room": 6.0},
	{"start": 105.0, "room": 5.0},
	{"start": 150.0, "room": 4.0},
	{"start": 210.0, "room": 3.5},
	{"start": 300.0, "room": 3.5},
]
const BREATHING_ROOM_JITTER: float = 0.3
const BREATHING_ROOM_SHRINK_PER_SECOND: float = 0.25 / 60.0
# terrain_invariant_check asserts this stays above the longest jump plus a margin, so the end of
# one pattern can never land the player inside the next and the per-pattern proofs compose.
const BREATHING_ROOM_FLOOR: float = 2.5
# The first time a kind appears in a run it comes ALONE -- a solo pattern stands in for whatever
# was drawn -- with this much extra room before and after it. That is the whole tutorial.
const FIRST_APPEARANCE_EXTRA_ROOM: float = 1.5

# WHAT ARRIVES TOGETHER. A pattern is a few pieces timed in SECONDS from the first, placed
# at the current speed. On flat ground a jump's height over time does not depend on speed, so
# terrain_invariant_check's check_pattern_fairness() can prove every row beatable at every jump
# level from this table alone -- a new row is only legal once it passes there.
#
# The multi-obstacle "clusters" this replaces (1-5 boxes with a tight/wide gap) were cut in
# favour of frequent singles, because they were spaced in pixels and nothing proved them
# beatable. A row here is the same idea with the proof attached.
const PATTERNS: Array[Dictionary] = [
	{"id": &"spike", "tier": 1, "weight": 2, "pieces": [{"kind": PIECE_SPIKE, "at": 0.0}]},
	{"id": &"floe", "tier": 2, "weight": 1, "pieces": [{"kind": PIECE_FLOE, "at": 0.0}]},
	{"id": &"shard", "tier": 2, "weight": 1, "pieces": [{"kind": PIECE_SHARD, "at": 0.0}]},
	# Short: one jump clears it. Long: the skip.
	{"id": &"ice_short", "tier": 3, "weight": 2, "pieces": [{"kind": PIECE_THIN_ICE, "at": 0.0, "length": 0.3}]},
	{"id": &"ice_long", "tier": 3, "weight": 1, "pieces": [{"kind": PIECE_THIN_ICE, "at": 0.0, "length": 1.2}]},
	# COMBOS ARE SHORT ON PURPOSE. Their whole span must be flat for the proof to hold, and this
	# terrain rarely is: 400px of flat fits ~15-19% of the ground, 1,200px ~3-4% (HANDOFF, "Step 5
	# decision"). A combo that does not fit falls back to its first piece alone.
	# Jump early so you land before the floe / the shard (or clear the shard at level 3+).
	{"id": &"spike_floe", "tier": 4, "weight": 1, "pieces": [{"kind": PIECE_SPIKE, "at": 0.0}, {"kind": PIECE_FLOE, "at": 0.5}]},
	{"id": &"spike_shard", "tier": 4, "weight": 1, "pieces": [{"kind": PIECE_SPIKE, "at": 0.0}, {"kind": PIECE_SHARD, "at": 0.5}]},
	# Stay under, then jump right after.
	{"id": &"floe_spike", "tier": 4, "weight": 1, "pieces": [{"kind": PIECE_FLOE, "at": 0.0}, {"kind": PIECE_SPIKE, "at": 0.5}]},
	{"id": &"shard_spike", "tier": 4, "weight": 1, "pieces": [{"kind": PIECE_SHARD, "at": 0.0}, {"kind": PIECE_SPIKE, "at": 0.5}]},
	# Two jumps, or one long one. Closer than ~0.6s it cannot be beaten at every level.
	{"id": &"spike_spike", "tier": 4, "weight": 1, "pieces": [{"kind": PIECE_SPIKE, "at": 0.0}, {"kind": PIECE_SPIKE, "at": 0.7}]},
	# Skip off the ice, then jump.
	{"id": &"ice_spike", "tier": 4, "weight": 1, "pieces": [{"kind": PIECE_THIN_ICE, "at": 0.0, "length": 0.5}, {"kind": PIECE_SPIKE, "at": 0.8}]},
	{"id": &"spike_floe_spike", "tier": 5, "weight": 1, "pieces": [{"kind": PIECE_SPIKE, "at": 0.0}, {"kind": PIECE_FLOE, "at": 0.5}, {"kind": PIECE_SPIKE, "at": 1.0}]},
	{"id": &"floe_spike_shard", "tier": 5, "weight": 1, "pieces": [{"kind": PIECE_FLOE, "at": 0.0}, {"kind": PIECE_SPIKE, "at": 0.5}, {"kind": PIECE_SHARD, "at": 1.0}]},
]

const HASH_MASK: int = 0x7fffffff
# Distinct multiplier pair from both TerrainGenerator.get_segment_hash and
# CoinSpawner.get_slot_hash so none of the hash sequences correlate, even
# though all three ultimately key off the same session_seed.
const HASH_INDEX_MULTIPLIER: int = 2654435761
const HASH_MIX_MULTIPLIER: int = 1274126177
const HASH_CHANNEL_INTERVAL: int = 0
const HASH_CHANNEL_PATTERN: int = 1

var terrain_generator: TerrainGenerator
var player: Player
var next_pattern_time: float = FIRST_PATTERN_TIME
var next_pattern_index: int = 0
var active_obstacles: Array[Node2D] = []
# Kinds this run has already shown, for the first-appearance rule. Per run: a restart reloads
# the scene.
var introduced_kinds: Dictionary = {}
var is_first_appearance_room_taken: bool = false

# The current biome's obstacle colour, pushed by BiomeDirector.push_palette(). Same contract
# as CoinSpawner's pair -- see the comment there -- with one extra reason it is absolute and
# not a modulate: this is the one object in the game a player must read as DANGER inside a
# fraction of a second at 750 px/s, so a biome is allowed to shift it and never to tint it
# toward its own scheme. biome_schedule_check enforces that from the data side.
var has_biome_color: bool = false
var biome_obstacle_color: Color = Color.WHITE


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as Player
	if terrain_generator == null or player == null:
		push_error("ObstacleSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	# Explicit null guard rather than trusting _ready()'s set_physics_process(false):
	# that call is documented (docs/development/debugging.md) as not reliably
	# suppressing _physics_process in headless harness runs, and everything below
	# dereferences both of these.
	if terrain_generator == null or player == null:
		return

	if debug_spawning_disabled:
		return

	# not player.is_boosting: a boost forces the grounded model and suppresses jump
	# input for its full 3s (player.gd, is_boosting), so a pattern landing inside one
	# is unavoidable death (CLAUDE.md Known Issues). Withholding next_pattern_time's
	# advance, rather than skipping the pattern outright, means the wait ends the
	# instant the boost does -- and try_place_pattern always places
	# SPAWN_LOOKAHEAD_WORLD_X ahead of wherever the player currently is, so one
	# spawned right as the boost ends still gets the same reaction-time lookahead as
	# any other.
	var elapsed_time: float = player.speed_manager.elapsed_time
	if elapsed_time >= next_pattern_time and not player.is_boosting:
		schedule_pattern(elapsed_time)

	var despawn_world_x: float = player.global_position.x - DESPAWN_BEHIND_WORLD_X
	for index: int in range(active_obstacles.size() - 1, -1, -1):
		var obstacle: Node2D = active_obstacles[index]
		if not is_instance_valid(obstacle):
			active_obstacles.remove_at(index)
		elif obstacle.position.x < despawn_world_x:
			# queue_free(), not free(): this runs inside _physics_process and an obstacle
			# is an Area2D. Same reasoning as TerrainGenerator.remove_chunk(). It is
			# dropped from active_obstacles in the same step, so the extra frame it
			# survives is not observable here.
			obstacle.queue_free()
			active_obstacles.remove_at(index)


# One scheduling decision, taken when a pattern is due. The pattern is drawn from
# next_pattern_index, which only advances on success, so a retry asks for the SAME pattern
# further along rather than re-rolling past it.
func schedule_pattern(elapsed_time: float) -> void:
	var pattern: Dictionary = get_pattern(next_pattern_index, get_tier(elapsed_time))
	var new_kind: StringName = get_unintroduced_kind(pattern)
	if new_kind != &"":
		pattern = get_solo_pattern(new_kind)
		if not is_first_appearance_room_taken:
			is_first_appearance_room_taken = true
			next_pattern_time += FIRST_APPEARANCE_EXTRA_ROOM
			return
	# A glider steers its own altitude and could fly into a floating piece, so those patterns
	# wait out the glide the same way every pattern waits out a boost. That only covers pieces
	# placed DURING a glide; the ones already ahead when it starts are why a glider passes
	# through floating pieces (Obstacle.is_floating).
	if player.is_glide_active and has_floating_piece(pattern):
		return

	var search_offset: float = try_place_pattern(pattern)
	if search_offset < 0.0 and pattern["pieces"].size() > 1:
		pattern = get_solo_pattern(pattern["pieces"][0]["kind"])
		search_offset = try_place_pattern(pattern)
	if search_offset < 0.0:
		next_pattern_time += FOOTPRINT_RETRY_DELAY
		return

	next_pattern_index += 1
	var speed: float = player.speed_manager.current_speed
	var room_bounds: Vector2 = get_breathing_room_bounds(elapsed_time)
	var room: float = room_bounds.x + get_pattern_hash(next_pattern_index, HASH_CHANNEL_INTERVAL) * (room_bounds.y - room_bounds.x)
	if new_kind != &"":
		introduced_kinds[new_kind] = true
		is_first_appearance_room_taken = false
		room += FIRST_APPEARANCE_EXTRA_ROOM
	for piece: Dictionary in pattern["pieces"]:
		introduced_kinds[piece["kind"]] = true
	# Measured from where the pattern really ends: a forward search placed it later.
	next_pattern_time = elapsed_time + search_offset / speed + get_pattern_duration(pattern) + room


# The room before the next pattern: tier 1's original interval ramp, then each tier's breathing
# room, shrinking in the last tier, never below BREATHING_ROOM_FLOOR.
func get_breathing_room_bounds(elapsed_time: float) -> Vector2:
	var tier: int = get_tier(elapsed_time)
	if tier == 1:
		return get_interval_bounds(elapsed_time)
	var room: float = float(TIERS[tier - 1]["room"])
	if tier == TIERS.size():
		room -= (elapsed_time - float(TIERS[tier - 1]["start"])) * BREATHING_ROOM_SHRINK_PER_SECOND
	room = maxf(room, BREATHING_ROOM_FLOOR)
	return Vector2(maxf(BREATHING_ROOM_FLOOR, room * (1.0 - BREATHING_ROOM_JITTER)), room * (1.0 + BREATHING_ROOM_JITTER))


# The randomized interval band for the window elapsed_time currently falls in --
# see the ramp comment above OBSTACLE_RAMP_WINDOW. +/-30% jitter around the
# window's average keeps the cadence from reading as a metronome while still
# landing roughly the target pattern count per window.
func get_interval_bounds(elapsed_time: float) -> Vector2:
	var window: int = int(elapsed_time / OBSTACLE_RAMP_WINDOW)
	var target_count: int = mini(window + 1, OBSTACLE_RAMP_MAX_COUNT)
	var average_interval: float = OBSTACLE_RAMP_WINDOW / float(target_count)
	var min_interval: float = maxf(RECURRING_PATTERN_MIN_INTERVAL_FLOOR, average_interval * 0.7)
	var max_interval: float = maxf(min_interval + 0.1, average_interval * 1.3)
	return Vector2(min_interval, max_interval)


# The highest tier whose start time has passed.
static func get_tier(elapsed_time: float) -> int:
	var tier: int = 1
	for index: int in range(TIERS.size()):
		if elapsed_time >= float(TIERS[index]["start"]):
			tier = index + 1
	return tier


# Weighted draw over the PATTERNS open at this tier, a pure function of (session_seed,
# pattern_index, tier).
func get_pattern(pattern_index: int, tier: int) -> Dictionary:
	var total_weight: int = 0
	for pattern: Dictionary in PATTERNS:
		if int(pattern["tier"]) <= tier:
			total_weight += int(pattern["weight"])
	var remaining_weight: int = int(get_pattern_hash(pattern_index, HASH_CHANNEL_PATTERN) * float(total_weight))
	var drawn: Dictionary = PATTERNS[0]
	for pattern: Dictionary in PATTERNS:
		if int(pattern["tier"]) > tier:
			continue
		drawn = pattern
		remaining_weight -= int(pattern["weight"])
		if remaining_weight < 0:
			break
	return drawn


# The first kind in the pattern this run has not shown yet, or &"".
func get_unintroduced_kind(pattern: Dictionary) -> StringName:
	for piece: Dictionary in pattern["pieces"]:
		if not introduced_kinds.has(piece["kind"]):
			return piece["kind"]
	return &""


# The first single-piece row of this kind: what a combo falls back to, and how a kind first
# appears.
static func get_solo_pattern(kind: StringName) -> Dictionary:
	for pattern: Dictionary in PATTERNS:
		if pattern["pieces"].size() == 1 and pattern["pieces"][0]["kind"] == kind:
			return pattern
	return PATTERNS[0]


# Seconds from the first piece's arrival to the last piece's end.
static func get_pattern_duration(pattern: Dictionary) -> float:
	var duration: float = 0.0
	for piece: Dictionary in pattern["pieces"]:
		duration = maxf(duration, float(piece["at"]) + float(piece.get("length", 0.0)))
	return duration


static func has_body_piece(pattern: Dictionary) -> bool:
	for piece: Dictionary in pattern["pieces"]:
		if piece["kind"] != PIECE_THIN_ICE:
			return true
	return false


static func has_floating_piece(pattern: Dictionary) -> bool:
	for piece: Dictionary in pattern["pieces"]:
		if bool(PIECE_KINDS[piece["kind"]]["floating"]):
			return true
	return false


# Places every piece of the pattern or none of them, at the first legal start from the lookahead
# out to FOOTPRINT_SEARCH_DISTANCE further. Returns how much further it went, or -1.0 when the
# guard rejected every start, so the caller retries instead of losing the pattern.
func try_place_pattern(pattern: Dictionary) -> float:
	var speed: float = player.speed_manager.current_speed
	var nominal_x: float = maxf(MIN_SAFE_START_WORLD_X, player.global_position.x + SPAWN_LOOKAHEAD_WORLD_X)
	var offset: float = find_legal_offset(terrain_generator, pattern, nominal_x, speed)
	if offset < 0.0:
		return offset
	var start_x: float = nominal_x + offset
	for piece: Dictionary in pattern["pieces"]:
		var piece_x: float = start_x + float(piece["at"]) * speed
		if piece["kind"] == PIECE_THIN_ICE:
			spawn_thin_ice(piece_x, piece_x + float(piece["length"]) * speed)
		else:
			spawn_obstacle(piece_x, piece["kind"])
	return offset


# The forward search itself, static so terrain_invariant_check measures exactly what the game
# does: the first offset in [0, FOOTPRINT_SEARCH_DISTANCE] whose footprint is legal, or -1.0.
static func find_legal_offset(terrain: TerrainGenerator, pattern: Dictionary, nominal_x: float, speed: float) -> float:
	var offset: float = 0.0
	while offset <= FOOTPRINT_SEARCH_DISTANCE:
		if is_footprint_legal(terrain, pattern, nominal_x + offset, speed):
			return offset
		offset += FOOTPRINT_SEARCH_STEP
	return -1.0


# World-x extent of every piece's hitbox, for a pattern whose first piece sits at start_x.
static func get_pattern_span(pattern: Dictionary, start_x: float, speed: float) -> Vector2:
	var span: Vector2 = Vector2(INF, -INF)
	for piece: Dictionary in pattern["pieces"]:
		var piece_x: float = start_x + float(piece["at"]) * speed
		var half_width: float = float(PIECE_KINDS[piece["kind"]]["half_width"])
		span.x = minf(span.x, piece_x - half_width)
		span.y = maxf(span.y, piece_x + float(piece.get("length", 0.0)) * speed + half_width)
	return span


# THE ONE FOOTPRINT GUARD, for a whole pattern. It replaced four checks scattered over
# spawn_cluster() that each looked at a single x. Static, so terrain_invariant_check measures
# the real rule rather than a copy of it. Every clause is safety-critical except the slope one:
#
#   * SLOPE, across the whole span. A piece glued to a slope reads as unfair, and the fairness
#     proof assumes the ground between pieces is flat too (see OBSTACLE_MAX_SLOPE_ANGLE). EXCEPT
#     a pattern made only of thin ice: it never touches physics, so a slope only lengthens or
#     shortens the hops across it, and terrain_invariant_check asserts even the weakest hop
#     leaves the steepest terrain. Held to 6 degrees, a 1.2s patch would fit ~5% of the ground.
#   * LAKE, across the whole span. Jumping is disabled across the frozen lake, so a hazard there
#     is unavoidable death. The lake is far longer than any span, so the samples cannot miss it.
#   * GROUND over the whole span. A piece within one jump reach BEFORE a chasm's near lip is
#     unavoidable death: clearing it commits the player to a landing in the void.
#   * AURORA, over the whole span. Its flat is a protected passage. spawn_obstacle() and
#     spawn_thin_ice() check again, so the rule holds for callers that bypass this guard.
static func is_footprint_legal(terrain: TerrainGenerator, pattern: Dictionary, start_x: float, speed: float) -> bool:
	var span: Vector2 = get_pattern_span(pattern, start_x, speed)
	if not is_span_clear(terrain, span.x, span.y, has_body_piece(pattern)):
		return false
	if not terrain.has_ground_over_world_x_span(span.x - OBSTACLE_VOID_CLEARANCE_BEHIND, span.y + OBSTACLE_VOID_CLEARANCE_AHEAD):
		return false
	return not terrain.overlaps_aurora_flat(span.x - AuroraDirector.BODY_CLEARANCE, span.y + AuroraDirector.BODY_CLEARANCE)


# Walks [from_x, to_x] every FOOTPRINT_SAMPLE_STEP: never the lake, and within
# OBSTACLE_MAX_SLOPE_ANGLE when needs_flat.
static func is_span_clear(terrain: TerrainGenerator, from_x: float, to_x: float, needs_flat: bool) -> bool:
	var sample_x: float = from_x
	while true:
		if needs_flat and absf(terrain.get_slope_angle_at_x(sample_x)) > OBSTACLE_MAX_SLOPE_ANGLE:
			return false
		if terrain.is_lake_world_x(sample_x):
			return false
		if sample_x >= to_x:
			return true
		sample_x = minf(sample_x + FOOTPRINT_SAMPLE_STEP, to_x)
	return true


# The unconditional placer: one piece at world_x, no guard but the Aurora's. Probes call it
# directly with the default kind.
func spawn_obstacle(world_x: float, kind: StringName = PIECE_SPIKE) -> void:
	# Include collision extent and a little approach clearance at both seams.
	# Keep this in the final placement path so every caller obeys the reservation.
	if terrain_generator.overlaps_aurora_flat(
			world_x - AuroraDirector.BODY_CLEARANCE, world_x + AuroraDirector.BODY_CLEARANCE):
		return
	var kind_spec: Dictionary = PIECE_KINDS[kind]
	var world_y: float = terrain_generator.ground_y + terrain_generator.get_terrain_height(world_x) \
		- float(kind_spec["center_height"])
	var obstacle: Obstacle = (load(String(kind_spec["scene"])) as PackedScene).instantiate() as Obstacle
	obstacle.position = Vector2(world_x, world_y)
	obstacle.is_floating = bool(kind_spec["floating"])
	if has_biome_color:
		obstacle.set_visual_color(biome_obstacle_color)
	add_child(obstacle)
	active_obstacles.append(obstacle)


# A thin-ice stretch from start_x to end_x. Same Aurora rule as spawn_obstacle(), over the span.
func spawn_thin_ice(start_x: float, end_x: float) -> void:
	if terrain_generator.overlaps_aurora_flat(
			start_x - AuroraDirector.BODY_CLEARANCE, end_x + AuroraDirector.BODY_CLEARANCE):
		return
	var thin_ice: ThinIce = ThinIce.new()
	thin_ice.setup(player, terrain_generator, start_x, end_x,
		biome_obstacle_color if has_biome_color else DEFAULT_OBSTACLE_COLOR)
	add_child(thin_ice)
	active_obstacles.append(thin_ice)


# Repaints the obstacles already on screen along with every one spawned from here on, so a
# crossfade never leaves two generations of obstacle on screen in different reds.
func apply_biome_color(color: Color) -> void:
	if has_biome_color and biome_obstacle_color.is_equal_approx(color):
		return
	has_biome_color = true
	biome_obstacle_color = color
	for node: Node2D in active_obstacles:
		if not is_instance_valid(node):
			continue
		var obstacle: Obstacle = node as Obstacle
		if obstacle != null:
			obstacle.set_visual_color(color)
		var thin_ice: ThinIce = node as ThinIce
		if thin_ice != null:
			thin_ice.set_visual_color(color)


# Pure function of (session_seed, pattern_index, channel) -> [0, 1). Same style as
# TerrainGenerator.get_segment_hash / CoinSpawner.get_slot_hash, with its own multiplier pair
# so this sequence doesn't correlate with either; channel separates the interval draw from the
# pattern draw, the way PowerupSpawner separates interval from kind.
func get_pattern_hash(pattern_index: int, channel: int) -> float:
	var session_seed: int = terrain_generator.get_session_seed()
	var mixed_value: int = (session_seed ^ (((pattern_index * 2 + channel) + 1) * HASH_INDEX_MULTIPLIER)) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 13)) & HASH_MASK
	mixed_value = (mixed_value * HASH_MIX_MULTIPLIER) & HASH_MASK
	mixed_value = (mixed_value ^ (mixed_value >> 15)) & HASH_MASK
	return float(mixed_value) / float(HASH_MASK)
