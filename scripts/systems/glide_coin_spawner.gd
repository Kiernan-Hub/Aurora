extends Node2D

class_name GlideCoinSpawner

# Coins that only exist while the glide powerup is active (player.is_glide_active) -- 30
# of them pop in individually, at random times, over the first FIELD_SPAWN_DURATION
# seconds of the glide, plus one oversized bonus coin the instant the glide ends. Reuses
# scenes/pickups/coin.tscn rather than a new scene: a coin is a coin, this just controls
# when and where one appears.
#
# ANCHORED TO THE TERRAIN, NOT THE PLAYER. An early version placed each coin at the
# player's OWN altitude at spawn time -- looked fine while the player held a level glide,
# but a real climb (player.y swinging over hundreds of px, see player.gd's
# GLIDE_MAX_RISE_SPEED) left a straight vertical column of coins hanging wherever the
# player happened to be, disconnected from the ground below. That also worked against the
# mechanic's own point: per CLAUDE.md, an unbounded glide is the one thing this game does
# that Alto's doesn't. Every coin's y is terrain_generator.get_terrain_height(x) (a
# randomised clearance above it), same local-space technique CoinSpawner's own ground
# coins use.
#
# SCATTERED, NOT LINED UP. Two earlier versions still read as a shape once plotted: one
# coin every fixed x-distance reads as a path (smooth or randomised height, walking x in
# steps always does); one batch clamped to a narrow shared altitude reads as a tight
# cluster. This version spawns coins one at a time on independently randomised timers
# across FIELD_SPAWN_DURATION (so they pop in through the whole early glide, not all at
# once), at a wide-open clearance range (TRAIL_CLEARANCE_MIN/MAX) so the full field's
# vertical spread lands in the thousand-plus-px range, and rejects a candidate spot that
# lands too close to any already-placed coin (MIN_COIN_SEPARATION) so nothing clusters or
# overlaps.
#
# A child of TerrainGenerator, same reasoning as coin_spawner.gd's header comment: world
# rebasing (main.gd, ~every 26s) shifts TerrainGenerator.position.y directly, and every
# descendant inherits that shift for free -- and since this node sits directly under
# TerrainGenerator with no offset of its own, a coin's local (position.x, position.y) IS
# already TerrainGenerator-local, the same frame get_terrain_height()'s return value is
# expressed in. No global_position conversion needed.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")
@export var camera_path: NodePath = NodePath("../../Camera2D")

signal coin_collected(value: int)

const COIN_SCENE: PackedScene = preload("res://scenes/pickups/coin.tscn")
# The end-of-glide bonus reuses the rare coin's own scene rather than a tinted regular
# coin -- it now IS the diamond, not a coin styled to look bonus-y.
const BONUS_COIN_SCENE: PackedScene = preload("res://scenes/pickups/rare_coin.tscn")
const TRAIL_COIN_VALUE: int = 1
const COIN_FIELD_COUNT: int = 30
# All 30 pop-in times are drawn from [0, FIELD_SPAWN_DURATION) at glide start, then popped
# off as the glide's own clock reaches them -- see spawn_timer / pending_spawn_times.
const FIELD_SPAWN_DURATION: float = 7.0
# How far PAST the visible right edge of the screen (see get_visible_right_edge_x()) a
# coin spawns, not a fixed distance ahead of the player. An earlier version used a fixed
# lead from the player's own x, which was well inside the camera's view at ordinary zoom
# and scroll speed -- coins were popping into existence in plain sight a few hundred px in
# front of the player instead of entering from off-screen the way the rest of the world's
# scenery does. Anchoring to the screen edge instead of the player is also naturally
# correct as speed ramps over a run: the same fixed px lead is a shrinking time margin as
# MAX_SPEED climbs, while a screen-edge margin never is.
const EDGE_SPAWN_MARGIN_MIN: float = 40.0
const EDGE_SPAWN_MARGIN_MAX: float = 360.0
# How far above the terrain's own height field a coin sits, same local-y units
# get_terrain_height() uses (see CoinSpawner.COIN_SURFACE_CLEARANCE for the ordinary-coin
# equivalent). Independently randomised per coin, and deliberately wide: across 30 coins
# this is what puts ~1000-2000px between the highest and lowest coin in a glide, per the
# brief -- a narrow range here was tried and just produced a tight, low cluster instead.
const TRAIL_CLEARANCE_MIN: float = 60.0
const TRAIL_CLEARANCE_MAX: float = 1900.0
# Minimum euclidean distance between any two field coins. Checked against every
# still-active coin at candidate time, with a bounded number of retries so a crowded late
# glide can't spin forever -- see spawn_trail_coin().
const MIN_COIN_SEPARATION: float = 220.0
const MIN_COIN_SEPARATION_SQUARED: float = MIN_COIN_SEPARATION * MIN_COIN_SEPARATION
const MAX_PLACEMENT_ATTEMPTS: int = 6
# Every air coin renders at this scale, trail and bonus alike -- at the ordinary 16px
# size they read as barely-there specks against how spread out and far away the field
# already is; bigger is what actually makes a coin poking out of that empty sky readable.
const AIR_COIN_SCALE: float = 1.9
# THE BONUS DIAMOND IS SPAWNED AT 1.0, NOT AT AIR_COIN_SCALE, and it must stay that way while
# it shares rare_coin.tscn with RareCoinSpawner (2026-08-15).
#
# Node scale here scales the Area2D, so it moves the art and the CollisionShape2D together --
# that lockstep is the design (visuals.md's art-swap traps) and it is why the trail coins'
# 38px art matches their 38px pickup exactly. The consequence is that a scale is not a look,
# it is a size: at AIR_COIN_SCALE this diamond rendered 42x59 against the 22x31 diamond
# RareCoinSpawner hangs, so the SAME ART meant two values with the bigger one worth LESS (15
# against 25). Matching the rare coin's scale is what makes one diamond mean one thing.
#
# Scaling the rare coin UP to 1.9 instead was rejected: its pickup circle would grow from r10
# to r19, dropping the collectible edge 9px into the ~24px gap between the top two jump levels
# that makes it max-jump-only (physics.md, CLAUDE.md). Scaling only the child Sprite2D would
# dodge that, and is worse -- it breaks the art/hitbox lockstep and leaves a diamond that looks
# collectible 10px before it is.
#
# AIR_COIN_SCALE's own "barely-there specks" reasoning does not carry over: it was measured on
# the 20px round coin, and this diamond is already read in the air at 174px clearance every
# time RareCoinSpawner hangs one.
const BONUS_DIAMOND_SCALE: float = 1.0
const BONUS_COIN_VALUE: int = 15
const BONUS_COIN_LEAD_DISTANCE: float = 200.0
const BONUS_SURFACE_CLEARANCE: float = 130.0
# A field coin the player flew past without collecting has no despawn trigger of its own
# (unlike CoinSpawner's chunk-indexed groups) -- this is what frees it instead.
const DESPAWN_BEHIND_DISTANCE: float = 700.0

var terrain_generator: TerrainGenerator
var player: CharacterBody2D
var camera: Camera2D
var was_glide_active: bool = false
var spawn_timer: float = 0.0
var pending_spawn_times: Array[float] = []
var active_coins: Array[Coin] = []

# The current biome's coin colour, pushed by BiomeDirector.push_palette(). Same contract and
# same reasoning as CoinSpawner's pair -- see the comment there.
var has_biome_color: bool = false
var biome_coin_color: Color = Color.WHITE


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as CharacterBody2D
	camera = get_node_or_null(camera_path) as Camera2D
	if terrain_generator == null or player == null or camera == null:
		push_error("GlideCoinSpawner requires a valid terrain_generator_path, player_path and camera_path.")
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	# Explicit null guard rather than trusting _ready()'s set_physics_process(false): that call
	# is documented (docs/development/debugging.md) as not reliably suppressing _physics_process
	# in headless harness runs, and everything below dereferences all three. Same guard, for the
	# same reason, as ObstacleSpawner and PowerupSpawner.
	if terrain_generator == null or player == null or camera == null:
		return

	var is_glide_active: bool = player.is_glide_active

	if is_glide_active and not was_glide_active:
		start_coin_field()

	if is_glide_active:
		spawn_timer += delta
		while not pending_spawn_times.is_empty() and pending_spawn_times[0] <= spawn_timer:
			pending_spawn_times.remove_at(0)
			spawn_trail_coin()

	if was_glide_active and not is_glide_active:
		pending_spawn_times.clear()
		spawn_bonus_coin(player.global_position.x + BONUS_COIN_LEAD_DISTANCE)

	was_glide_active = is_glide_active
	despawn_trailing_coins()


func start_coin_field() -> void:
	spawn_timer = 0.0
	pending_spawn_times.clear()
	for _coin_index: int in range(COIN_FIELD_COUNT):
		pending_spawn_times.append(randf_range(0.0, FIELD_SPAWN_DURATION))
	pending_spawn_times.sort()


func spawn_trail_coin() -> void:
	var right_edge_x: float = get_visible_right_edge_x()
	# Last candidate that was on real ground but too close to an existing coin -- the fallback
	# below. A candidate that failed the VOID check is deliberately never eligible: it is not a
	# crowding problem and placing it anyway is the one outcome this function must never have.
	var fallback_position: Vector2 = Vector2.ZERO
	var has_fallback: bool = false

	for _attempt: int in range(MAX_PLACEMENT_ATTEMPTS):
		var world_x: float = right_edge_x + randf_range(EDGE_SPAWN_MARGIN_MIN, EDGE_SPAWN_MARGIN_MAX)
		# A coin over a chasm void has no ground to hover above: get_terrain_height() only
		# returns the lip height there, and baiting the player toward a fatal void is
		# exactly what this mechanic should not do.
		if not terrain_generator.has_ground_at_world_x(world_x):
			continue
		# Unreachable in practice -- a glide cannot start on the lake, since the powerup that
		# grants it is suppressed there and is_glide_input_held() reads false while input is
		# locked -- but a glide begun just before the seam can still be placing coins as the
		# player crosses it. Guarded for that, and for symmetry with the other five.
		if terrain_generator.is_lake_world_x(world_x):
			continue
		var clearance: float = randf_range(TRAIL_CLEARANCE_MIN, TRAIL_CLEARANCE_MAX)
		var local_y: float = terrain_generator.get_terrain_height(world_x) - clearance
		if is_far_enough_from_active_coins(world_x, local_y):
			spawn_coin(world_x, local_y, TRAIL_COIN_VALUE, AIR_COIN_SCALE, null)
			return
		fallback_position = Vector2(world_x, local_y)
		has_fallback = true

	# Every attempt landed too close to something else -- place the last candidate anyway rather
	# than silently dropping the coin. Rare: MIN_COIN_SEPARATION is small next to
	# TRAIL_CLEARANCE_MAX's spread.
	#
	# This branch was MISSING until 2026-08-10 while the comment above claimed it existed, so a
	# crowded late glide quietly dropped coins from its field. has_fallback stays false when
	# every attempt failed the void check instead, which is the case that must still drop.
	if has_fallback:
		spawn_coin(fallback_position.x, fallback_position.y, TRAIL_COIN_VALUE, AIR_COIN_SCALE, null)


# zoom.x, not a hardcoded viewport size: project.godot pins no window/size/viewport_* and
# stretches with aspect="expand" (same reasoning as background_generator.gd's own
# apply_viewport_size()), so both the viewport rect and the camera's zoom are read live
# rather than assumed.
func get_visible_right_edge_x() -> float:
	var viewport_width: float = get_viewport_rect().size.x
	var zoom_x: float = camera.zoom.x if camera.zoom.x > 0.0 else 1.0
	return camera.global_position.x + ((viewport_width * 0.5) / zoom_x)


func is_far_enough_from_active_coins(world_x: float, local_y: float) -> bool:
	for coin: Coin in active_coins:
		if not is_instance_valid(coin):
			continue
		if coin.position.distance_squared_to(Vector2(world_x, local_y)) < MIN_COIN_SEPARATION_SQUARED:
			return false
	return true


func spawn_bonus_coin(world_x: float) -> void:
	if not terrain_generator.has_ground_at_world_x(world_x):
		world_x = terrain_generator.get_next_ground_world_x(world_x)
	# Skipped, not nudged, for the same reason PowerupSpawner skips: the lake is 7500px of
	# perfectly good ground, so a nudge would walk the coin onto the ice rather than past it.
	if terrain_generator.is_lake_world_x(world_x):
		return
	var local_y: float = terrain_generator.get_terrain_height(world_x) - BONUS_SURFACE_CLEARANCE
	spawn_coin(world_x, local_y, BONUS_COIN_VALUE, BONUS_DIAMOND_SCALE, null, BONUS_COIN_SCENE)


# null means "whatever this coin's colour should be right now", which is the biome's once one
# has been pushed and coin.tscn's authored gold before that. A Color overrides it outright.
# scene defaults to the ordinary trail coin; the bonus call passes BONUS_COIN_SCENE, which is
# never tinted below -- same reasoning as RareCoinSpawner: no spawner pushes a colour into the
# diamond, so it keeps its own authored modulate.
func spawn_coin(world_x: float, local_y: float, coin_value: int, coin_scale: float, tint: Variant, scene: PackedScene = COIN_SCENE) -> void:
	var coin: Coin = scene.instantiate() as Coin
	coin.value = coin_value
	coin.collected.connect(_on_coin_collected)
	coin.position = Vector2(world_x, local_y)
	if coin_scale != 1.0:
		coin.scale = Vector2(coin_scale, coin_scale)
	if tint is Color:
		coin.set_visual_color(tint)
	elif has_biome_color and scene != BONUS_COIN_SCENE:
		coin.set_visual_color(biome_coin_color)
	add_child(coin)
	active_coins.append(coin)


# Repaints the field coins already hanging in the air along with every one spawned from here
# on. The bonus coin is skipped -- it is the diamond now, not a tinted field coin, and is told
# apart by its value (the only coin either spawner ever gives a value other than 1).
func apply_biome_color(color: Color) -> void:
	if has_biome_color and biome_coin_color.is_equal_approx(color):
		return
	has_biome_color = true
	biome_coin_color = color
	for coin: Coin in active_coins:
		if not is_instance_valid(coin):
			continue
		if coin.value == BONUS_COIN_VALUE:
			continue
		coin.set_visual_color(color)


func despawn_trailing_coins() -> void:
	var still_active: Array[Coin] = []
	for coin: Coin in active_coins:
		if not is_instance_valid(coin):
			continue
		# X is never world-rebased (world_rebaser.gd rebases Y only), so position.x is
		# directly comparable to player.global_position.x with no conversion.
		if player.global_position.x - coin.position.x > DESPAWN_BEHIND_DISTANCE:
			coin.queue_free()
			continue
		still_active.append(coin)
	active_coins = still_active


func _on_coin_collected(value: int) -> void:
	coin_collected.emit(value)
