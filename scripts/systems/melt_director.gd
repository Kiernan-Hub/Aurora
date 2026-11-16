extends Node

class_name MeltDirector

# The normal world stays intact on a paused tree. Only the isolated view/model runs
# during GameManager.BONUS; no teleport, scene reload or terrain cache mutation.
const PORTAL_SCENE: PackedScene = preload("res://scenes/pickups/melt_portal.tscn")
const VIEW_SCRIPT: Script = preload("res://scripts/ui/melt_view.gd")
const FIRST_SECONDS: float = 240.0
const RANDOM_DELAY_SECONDS: float = 180.0
var debug_first_seconds: float = 0.0

var main: Main
var player: Player
var gm: Node
var terrain: TerrainGenerator
var spawner: RareCoinSpawner
var lake: FrozenLakeDirector
var aurora: AuroraDirector
var services: GameServices
var view: MeltView
var due: float = -1.0
var portal_spawned: bool = false
var entered: bool = false
var entry_pending: bool = false
var reward_paid: bool = false
var reward_roll: Array[Dictionary] = []
var reward_prepared: bool = false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	main = get_parent() as Main
	player = get_node_or_null("../Player") as Player
	gm = get_node_or_null("../GameManager")
	terrain = get_node_or_null("../TerrainGenerator") as TerrainGenerator
	spawner = get_node_or_null("../TerrainGenerator/RareCoinSpawner") as RareCoinSpawner
	lake = get_node_or_null("../FrozenLakeDirector") as FrozenLakeDirector
	aurora = get_node_or_null("../AuroraDirector") as AuroraDirector
	services = GameServices.resolve(self)
	if main == null or player == null or gm == null or terrain == null or spawner == null or services == null:
		push_warning("The Melt disabled: missing scene dependency.")
		set_process(false)
		return
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	view = VIEW_SCRIPT.new() as MeltView
	view.visible = false
	layer.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gm.melt_view = view
	view.pause_requested.connect(gm._on_pause_pressed)
	view.round_finished.connect(settle_reward)
	view.reward_requested.connect(_on_reward_requested)
	view.return_finished.connect(return_to_run)


func _process(_delta: float) -> void:
	if gm.state != GameManager.State.PLAYING:
		return
	if entry_pending:
		begin()
		return
	if portal_spawned:
		return
	if due < 0.0:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = terrain.session_seed ^ 0x4d454c54
		due = debug_first_seconds if debug_first_seconds > 0.0 else FIRST_SECONDS + rng.randf() * RANDOM_DELAY_SECONDS
	if main.elapsed_time < due or not can_enter():
		return
	var x: float = player.global_position.x + RareCoinSpawner.SPAWN_LOOKAHEAD_WORLD_X
	# Use the same proven jump-reachable placement and hazard/void checks as chests.
	# Give the return pose extra quiet space; the normal world cannot advance inside.
	if not terrain.has_ground_over_world_x_span(x, x + 1100.0):
		return
	var obstacles: ObstacleSpawner = get_node("../TerrainGenerator/ObstacleSpawner")
	for offset: float in [0.0, 500.0, 1000.0]:
		if not obstacles.is_clear_for_pickup(x + offset):
			return
	portal_spawned = spawner.try_spawn(x, PORTAL_SCENE, 84.0, _on_portal_collected)
	if portal_spawned:
		(spawner.active_coins[-1] as MeltPortal).entry_guard = entry_is_clear


func can_enter() -> bool:
	return not entered and not player.is_dead and not player.is_glide_active and not player.is_boosting \
		and (lake == null or lake.phase == FrozenLakeDirector.Phase.IDLE or lake.phase == FrozenLakeDirector.Phase.DONE) \
		and (aurora == null or aurora.phase == AuroraDirector.Phase.IDLE or aurora.phase == AuroraDirector.Phase.DONE)


func _on_portal_collected(_value: int) -> void:
	# Area2D signals arrive during the physics flush. Pause after that flush completes.
	entry_pending = true
	begin.call_deferred()


func entry_is_clear() -> bool:
	if not can_enter() or not terrain.has_ground_over_world_x_span(player.global_position.x, player.global_position.x + 1100.0):
		return false
	var obstacles: ObstacleSpawner = get_node("../TerrainGenerator/ObstacleSpawner")
	for offset: float in [0.0, 500.0, 1000.0]:
		if not obstacles.is_clear_for_pickup(player.global_position.x + offset):
			return false
	return true


func begin() -> void:
	if gm.state != GameManager.State.PLAYING:
		return
	if not can_enter():
		entry_pending = false
		return
	entry_pending = false
	entered = true
	reward_paid = false
	reward_prepared = false
	reward_roll.clear()
	view.begin(player.animated_sprite.sprite_frames, services.save_store.best_melt_seconds)
	gm.set_state(GameManager.State.BONUS)
	clear_run_input()


func settle_reward() -> void:
	if reward_paid or not entered or not view.round.finished:
		return
	var coins: int = view.round.bonus_coins()
	var tier: int = view.round.chest_tier()
	# A failed save retries the same prepared roll instead of rerolling the chest.
	if not reward_prepared:
		reward_prepared = true
		if tier >= 0:
			reward_roll.append(ChestRewards.roll(gm.get_unowned_skin_ids(), RandomNumberGenerator.new(),
				Cosmetics.get_unowned(services.save_store.cosmetics), tier))
	var new_best: bool = view.round.elapsed > services.save_store.best_melt_seconds
	if not services.save_store.bank_bonus(coins, reward_roll, view.round.elapsed):
		view.show_reward("Your bonus is ready.\nSaving failed; tap to try again.", false)
		return
	reward_paid = true
	var text: String = "%.1fs survived\n+%d coins" % [view.round.elapsed, coins]
	if new_best:
		text = "New best · " + text
	if not reward_roll.is_empty():
		var reward: Dictionary = reward_roll[0]
		text += "\n%s chest · " % ChestTypes.get_type(tier)["name"]
		if not String(reward.get("cosmetic", "")).is_empty():
			text += String(Cosmetics.get_item(reward["cosmetic"])["name"])
		elif not String(reward.get("skin", "")).is_empty():
			text += "New skater"
		else:
			text += "+%d coins" % int(reward["coins"])
	view.show_reward(text, true)


func _on_reward_requested() -> void:
	if not reward_paid:
		settle_reward()
		return
	view.start_return()


func return_to_run() -> void:
	if not reward_paid or gm.state != GameManager.State.BONUS:
		return
	clear_run_input()
	gm.set_state(GameManager.State.PLAYING)


func clear_run_input() -> void:
	main.held_touch_indices.clear()
	player.jump_buffer_timer = 0.0
	Input.action_release(&"ui_accept")
	Input.action_release(Player.SLAM_ACTION)
