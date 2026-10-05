extends SceneTree

# Regression gate for the save, shop, death-screen and input paths no physics gate reaches
# (audit.md A4, 2026-10-04). Each case pins a bug that shipped or was reproduced once. Every
# save goes to an in-memory SaveStore swapped into the Services autoload before the scene
# exists, so the developer's own save.dat is never read for a verdict and never written.
#
#   purchase_rollback  a purchase whose save fails restores wallet and level and returns false;
#                      one that succeeds charges and grants (audit A1).
#   save_numbers       the loader rejects INF, out-of-range and negative counts field by field,
#                      and keeps the aurora's negative "unscheduled" sentinel (audit A17).
#   save_containers    a wrong-typed container (upgrades as a list, achievements as a string,
#                      settings as a number) loses only itself (2026-09-20 audit, P2).
#   touch_hold         lifting one finger keeps the glide hold while another is down, and each
#                      screen half buffers its own side (2026-09-20 audit, P2).
#   death_stats        the death screen's best and wallet follow a shop purchase and a reset, and
#                      the run is not banked again (audit A2, the 2026-10-04 phone bug).
#   death_pickups      a coin touched in the death step counts only if it came first, and the
#                      death screen agrees with the score either way (audit A15).
#   reload_banking     Home and Restart from PAUSED bank the biome phase, unpause and really
#                      reload; only Restart sets the quick-restart flag (2026-09-20 audit P2,
#                      audit A8). Each reload's fresh scene is freed at once.
#
# Usage:
#   godot --headless --fixed-fps 60 --path . --script res://scripts/debug/regression_probe.gd

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const OBSTACLE_SCENE: PackedScene = preload("res://scenes/obstacles/obstacle.tscn")
const COIN_SCENE: PackedScene = preload("res://scenes/pickups/coin.tscn")
const SEED: int = 683407368
const START_X: float = 20000.0


class MemorySaveStore extends SaveStore:
	var succeed: bool = true
	var writes: int = 0
	func save_to_disk() -> bool:
		writes += 1
		return succeed


var services: GameServices
var store: MemorySaveStore = MemorySaveStore.new()
var main: Main
var player: Player
var game_manager: GameManager
var failures: int = 0
var cases: int = 0


func _init() -> void:
	call_deferred("run")


func run() -> void:
	services = root.get_node_or_null(GameServices.AUTOLOAD_PATH) as GameServices
	if services == null:
		print("REGRESSION_PROBE_RESULT status=FAIL (no Services autoload)")
		quit(1)
		return
	services.save_store = store
	services.upgrades.save_store = store

	purchase_rollback()
	save_numbers()
	save_containers()
	await touch_hold()
	await death_stats()
	await death_pickups()
	await reload_banking()

	print("REGRESSION_PROBE_RESULT cases=%d failures=%d status=%s" % [cases, failures, "PASS" if failures == 0 else "FAIL"])
	quit(0 if failures == 0 else 1)


func expect(case_name: String, passed: bool, detail: String) -> void:
	cases += 1
	if not passed:
		failures += 1
	print("  REGRESSION_CASE %-17s %s  %s" % [case_name, "PASS" if passed else "*** FAIL ***", detail])


func purchase_rollback() -> void:
	var failing: MemorySaveStore = MemorySaveStore.new()
	failing.succeed = false
	failing.coin_wallet = 1000
	failing.upgrade_levels[UpgradeStore.JUMP_UPGRADE_ID] = 1
	var upgrades: UpgradeStore = UpgradeStore.new()
	upgrades.save_store = failing
	var new_track: bool = upgrades.purchase(UpgradeStore.SLAM_UPGRADE_ID)
	var old_track: bool = upgrades.purchase(UpgradeStore.JUMP_UPGRADE_ID)
	var rolled_back: bool = not new_track and not old_track and failing.coin_wallet == 1000 \
		and not failing.upgrade_levels.has(UpgradeStore.SLAM_UPGRADE_ID) \
		and failing.upgrade_levels[UpgradeStore.JUMP_UPGRADE_ID] == 1
	failing.succeed = true
	var bought: bool = upgrades.purchase(UpgradeStore.SLAM_UPGRADE_ID)
	expect("purchase_rollback", rolled_back and bought
		and failing.coin_wallet == 1000 - UpgradeStore.SLAM_UPGRADE_COST
		and failing.upgrade_levels[UpgradeStore.SLAM_UPGRADE_ID] == 1,
		"failed save rolled back=%s; good save bought=%s wallet=%d" % [rolled_back, bought, failing.coin_wallet])


func save_numbers() -> void:
	var loaded: MemorySaveStore = MemorySaveStore.new()
	loaded.load_from_data(JSON.parse_string("""{"version": 3, "best_score": -42, "best_time": 1e309,
		"coin_wallet": 1e30, "upgrades": {"slam": 1e309, "jump": 2, "future_track": 1},
		"total_playtime_seconds": -1e309, "frozen_lake_count": 3, "aurora_count": -1,
		"next_aurora_due_seconds": -1.0, "achievements": {"lake": true}}"""))
	var unscheduled_kept: bool = loaded.next_aurora_due_seconds == -1.0
	var infinite_due: MemorySaveStore = MemorySaveStore.new()
	infinite_due.load_from_data(JSON.parse_string("""{"version": 3, "next_aurora_due_seconds": 1e309}"""))
	expect("save_numbers", loaded.best_score == 0 and loaded.best_time == 0.0 and loaded.coin_wallet == 0
		and loaded.upgrade_levels == {"jump": 2, "future_track": 1} and loaded.total_playtime_seconds == 0.0
		and loaded.frozen_lake_count == 3 and loaded.aurora_count == 0 and unscheduled_kept
		and loaded.achievements.get("lake", false) and infinite_due.next_aurora_due_seconds == -1.0,
		"best=%d time=%.1f wallet=%d upgrades=%s playtime=%.1f lakes=%d auroras=%d due=%.1f inf_due=%.1f" % [
			loaded.best_score, loaded.best_time, loaded.coin_wallet, loaded.upgrade_levels,
			loaded.total_playtime_seconds, loaded.frozen_lake_count, loaded.aurora_count,
			loaded.next_aurora_due_seconds, infinite_due.next_aurora_due_seconds])


func save_containers() -> void:
	var loaded: MemorySaveStore = MemorySaveStore.new()
	loaded.load_from_data(JSON.parse_string("""{"version": 3, "best_score": 9, "coin_wallet": 500,
		"upgrades": [1, 2], "achievements": "lake", "settings": 7, "frozen_lake_count": 2}"""))
	expect("save_containers", loaded.best_score == 9 and loaded.coin_wallet == 500 and loaded.upgrade_levels.is_empty()
		and loaded.achievements.is_empty() and loaded.music_volume == SaveStore.DEFAULT_MUSIC_VOLUME
		and loaded.frozen_lake_count == 2,
		"best=%d wallet=%d upgrades=%s achievements=%s music=%.2f lakes=%d" % [
			loaded.best_score, loaded.coin_wallet, loaded.upgrade_levels, loaded.achievements,
			loaded.music_volume, loaded.frozen_lake_count])


func touch_hold() -> void:
	await new_scene()
	var size: Vector2 = main.get_viewport().get_visible_rect().size
	var left: Vector2 = Vector2(100.0, size.y - 50.0)
	var right: Vector2 = Vector2(size.x - 100.0, size.y - 50.0)
	main._input(touch(0, true, right))
	var right_side_is_jump: bool = not player.is_buffered_tap_slam
	main._input(touch(1, true, left))
	var left_side_is_slam: bool = player.is_buffered_tap_slam
	main._input(touch(1, false, left))
	var held_after_one_lift: bool = main.is_touch_held()
	main._input(touch(0, false, right))
	var released: bool = not main.is_touch_held()
	expect("touch_hold", right_side_is_jump and left_side_is_slam and held_after_one_lift and released,
		"right=jump %s left=slam %s held after one lift %s released %s" % [
			right_side_is_jump, left_side_is_slam, held_after_one_lift, released])


func touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event


func death_stats() -> void:
	await new_scene()
	store.best_score = 50
	store.coin_wallet = 1000
	store.upgrade_levels.clear()
	player.die()
	var at_death: String = stats_line(2) + " / " + stats_line(3)
	game_manager._on_buy_pressed(UpgradeStore.SLAM_UPGRADE_ID)
	var after_buy: String = stats_line(2) + " / " + stats_line(3)
	game_manager._on_reset_progress_confirmed()
	var after_reset: String = stats_line(2) + " / " + stats_line(3)
	var expected_after_buy: String = "Best: 50 / Wallet: %d" % (1000 - UpgradeStore.SLAM_UPGRADE_COST)
	expect("death_stats", at_death == "Best: 50 / Wallet: 1000" and after_buy == expected_after_buy
		and after_reset == "Best: 0 / Wallet: 0",
		"at death [%s], after buy [%s], after reset [%s]" % [at_death, after_buy, after_reset])


func stats_line(line: int) -> String:
	return game_manager.death_stats_label.text.get_slice("\n", line)


func death_pickups() -> void:
	var results: Array[String] = []
	var passed: bool = true
	for hazard_first: bool in [true, false]:
		await new_scene()
		var obstacle: Node2D = OBSTACLE_SCENE.instantiate() as Node2D
		var coin: Coin = COIN_SCENE.instantiate() as Coin
		obstacle.position = player.position + Vector2(15.0, 0.0)
		coin.position = player.position + Vector2(15.0, 0.0)
		coin.collected.connect(game_manager._on_coin_collected)
		main.add_child(obstacle if hazard_first else coin)
		main.add_child(coin if hazard_first else obstacle)
		for frame: int in range(3):
			await physics_frame
		var shown: int = stats_line(0).trim_prefix("Coins: ").to_int()
		var expected_coins: int = 0 if hazard_first else 1
		passed = passed and player.is_dead and game_manager.coin_count == expected_coins and shown == expected_coins
		results.append("%s: dead=%s coins=%d shown=%d" % [
			"hazard first" if hazard_first else "coin first", player.is_dead, game_manager.coin_count, shown])
	expect("death_pickups", passed, ", ".join(results))


func reload_banking() -> void:
	var outcomes: Array[String] = []
	var passed: bool = true
	for quick_start: bool in [false, true]:
		await new_scene()
		current_scene = main
		game_manager.set_state(GameManager.State.PAUSED)
		BiomeDirector.session_biome_phase = 0.0
		GameManager.pending_quick_restart = not quick_start
		var expected_phase: float = player.global_position.x
		if quick_start:
			game_manager._on_quick_restart_pressed()
		else:
			game_manager._on_home_pressed()
		var banked: bool = is_equal_approx(BiomeDirector.session_biome_phase, expected_phase)
		var flag: bool = GameManager.pending_quick_restart
		var was_unpaused: bool = not paused
		# The old scene leaves the tree at once; the fresh one is added a frame or two later and
		# is freed straight away.
		for frame: int in range(3):
			await process_frame
		var reloaded: Node = current_scene
		var did_reload: bool = reloaded != null and reloaded != main
		if reloaded != null:
			reloaded.queue_free()
		await process_frame
		passed = passed and banked and was_unpaused and flag == quick_start and did_reload
		outcomes.append("%s: banked=%s unpaused=%s quick=%s reloaded=%s" % [
			"restart" if quick_start else "home", banked, was_unpaused, flag, did_reload])
	expect("reload_banking", passed, ", ".join(outcomes))


# A fresh scene, settled on the ground at START_X with nothing spawning. Frees the previous one.
func new_scene() -> void:
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	paused = false
	main = MAIN_SCENE.instantiate() as Main
	var terrain: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	game_manager = main.get_node("GameManager") as GameManager
	terrain.debug_replay_session_seed = SEED
	terrain.debug_chasm_disabled = true
	player.DEBUG_SHOW_PLAYER_STATE = false
	player.DEBUG_LOG_FREEZE_REPRO = false
	game_manager.require_start_screen = false
	(main.get_node("TerrainGenerator/ObstacleSpawner") as ObstacleSpawner).debug_spawning_disabled = true
	(main.get_node("TerrainGenerator/PowerupSpawner") as PowerupSpawner).debug_spawning_disabled = true
	root.add_child(main)
	await physics_frame
	player.global_position = Vector2(START_X, terrain.get_surface_world_y(START_X) - player.capsule_half_height)
	for chunk_index: int in terrain.active_chunks.keys():
		terrain.remove_chunk(chunk_index)
	terrain.initialize_chunks()
	for frame: int in range(10):
		await physics_frame
