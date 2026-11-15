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
#   save_history       record_run() adds up the all-time stats, the loader rejects bad ones, and
#                      a reset clears them (the Stats screen, 2026-10-29).
#   stats_screen       Stats opens over START with every stat and achievement row, and both its
#                      Back button and the Android back gesture return to START.
#   skins              every Skins row loads as a 4-frame "skate" animation the original's size,
#                      and every one but the default has a shop track; an unknown or wrong-typed
#                      saved skin reads as the default; a locked skin cannot be picked, buying
#                      one wears it, and a reset un-buys it back to the default.
#   sparkles           every sparkle's unlocking achievement exists; a locked one cannot be
#                      picked, an earned one can, and a reset relocks it back to Ice.
#   chests             every chest reward is inside ChestRewards.TABLE's ranges, a skater is only
#                      ever one the player lacks and never twice in a run; the chest hangs above
#                      a standing player and within the weakest jump; granting adds coins and the
#                      skater without a write; a death rolls one reward per chest and the reveal opens each.
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
	await chests()
	await death_pickups()
	await reload_banking()
	save_history()
	await stats_screen()
	await skins()
	await sparkles()

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
	var at_death: String = stats_line(3) + " / " + stats_line(4)
	game_manager._on_buy_pressed(UpgradeStore.SLAM_UPGRADE_ID)
	var after_buy: String = stats_line(3) + " / " + stats_line(4)
	game_manager._on_reset_progress_confirmed()
	var after_reset: String = stats_line(3) + " / " + stats_line(4)
	var expected_after_buy: String = "Best: 50 / Wallet: %d" % (1000 - UpgradeStore.SLAM_UPGRADE_COST)
	expect("death_stats", at_death == "Best: 50 / Wallet: 1000" and after_buy == expected_after_buy
		and after_reset == "Best: 0 / Wallet: 0",
		"at death [%s], after buy [%s], after reset [%s]" % [at_death, after_buy, after_reset])


func chests() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var lowest: int = ChestRewards.TABLE[0]["coins_min"]
	var highest: int = ChestRewards.TABLE[ChestRewards.JACKPOT_ROW]["coins_max"]
	var rolls_ok: bool = true
	var skins_seen: int = 0
	for _roll: int in range(4000):
		var reward: Dictionary = ChestRewards.roll(["teen"], rng)
		if reward["skin"] != "":
			skins_seen += 1
			rolls_ok = rolls_ok and reward["skin"] == "teen" and reward["coins"] == 0
		else:
			rolls_ok = rolls_ok and reward["coins"] >= lowest and reward["coins"] <= highest
		rolls_ok = rolls_ok and ChestRewards.roll([], rng)["skin"] == ""
	var run_skins: Array[String] = []
	for reward: Dictionary in ChestRewards.roll_all(400, ["teen", "mom"], rng):
		if reward["skin"] != "":
			run_skins.append(reward["skin"])
	var no_repeat: bool = run_skins.size() == 2 and run_skins[0] != run_skins[1]

	var chest: Node = RareCoinSpawner.CHEST_SCENE.instantiate()
	var radius: float = ((chest.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius
	var is_coin: bool = chest is Coin
	chest.free()
	var hitbox_bottom: float = RareCoinSpawner.CHEST_CLEARANCE - radius
	var weakest_top: float = 48.0 + pow(Player.JUMP_VELOCITY * UpgradeStore.get_min_jump_multiplier(), 2.0) / (2.0 * Player.GRAVITY)
	var reach_ok: bool = hitbox_bottom > 48.0 + 8.0 and weakest_top >= hitbox_bottom + 16.0

	await new_scene()
	store.coin_wallet = 100
	store.upgrade_levels.clear()
	var writes_before: int = store.writes
	store.grant_chest_rewards([{"coins": 40, "skin": "", "jackpot": false}, {"coins": 0, "skin": "teen", "jackpot": false}])
	var grant_ok: bool = store.coin_wallet == 140 and store.upgrade_levels.get("skin_teen", 0) == 1 and store.writes == writes_before

	game_manager._on_chest_collected()
	game_manager._on_chest_collected()
	var hud: String = game_manager.coin_label.text
	player.die()
	var death_ok: bool = hud.begins_with("Chests: 2") and game_manager.chest_rewards.size() == 2 \
		and game_manager.chest_reveal.visible
	# Let the reveal run on the paused tree: both rows must have opened into what they held.
	if death_ok:
		await game_manager.chest_reveal.reveal_tween.finished
	var opened_rows: int = 0
	for row: Node in game_manager.chest_reveal.get_children():
		if row is Label and row.visible and (row.text.contains("coins") or row.text.contains("SKATER")):
			opened_rows += 1
	death_ok = death_ok and opened_rows == 2 and game_manager.chest_reveal.stage.is_open
	expect("chests", rolls_ok and skins_seen > 0 and no_repeat and is_coin and reach_ok and grant_ok and death_ok,
		"rolls=%s skins_seen=%d no_repeat=%s is_coin=%s reach=%s (bottom %.0f, weakest top %.0f) grant=%s death=%s hud=[%s]" % [
			rolls_ok, skins_seen, no_repeat, is_coin, reach_ok, hitbox_bottom, weakest_top, grant_ok, death_ok, hud])


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


func save_history() -> void:
	var history: MemorySaveStore = MemorySaveStore.new()
	history.record_run(40, 30.0, 1200.0)
	history.record_run(10, 12.0, 300.0)
	var added: bool = history.total_runs == 2 and history.total_coins_earned == 50 \
		and is_equal_approx(history.total_distance_meters, 1500.0) and is_equal_approx(history.best_distance_meters, 1200.0)
	var totals: String = "runs=%d coins=%d distance=%.0f best=%.0f" % [
		history.total_runs, history.total_coins_earned, history.total_distance_meters, history.best_distance_meters]
	var loaded: MemorySaveStore = MemorySaveStore.new()
	loaded.load_from_data(JSON.parse_string("""{"version": 3, "total_runs": -3, "total_coins_earned": 1e309,
		"total_distance_meters": -5.0, "best_distance_meters": "far"}"""))
	var rejected: bool = loaded.total_runs == 0 and loaded.total_coins_earned == 0 \
		and loaded.total_distance_meters == 0.0 and loaded.best_distance_meters == 0.0
	history.reset_progress()
	var cleared: bool = history.total_runs == 0 and history.total_distance_meters == 0.0
	expect("save_history", added and rejected and cleared, "%s; bad fields rejected=%s; reset cleared=%s" % [totals, rejected, cleared])


func stats_screen() -> void:
	await new_scene()
	game_manager.set_state(GameManager.State.START)
	game_manager._on_stats_pressed()
	var opened: bool = game_manager.state == GameManager.State.STATS and game_manager.stats_screen.visible \
		and game_manager.start_screen.visible
	var stat_rows: int = game_manager.stats_grid.get_child_count() / 2
	var achievement_rows: int = game_manager.achievements_grid.get_child_count() / 2
	game_manager._on_stats_close_pressed()
	var closed: bool = game_manager.state == GameManager.State.START and not game_manager.stats_screen.visible
	game_manager._on_stats_pressed()
	game_manager._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var backed: bool = game_manager.state == GameManager.State.START
	expect("stats_screen", opened and closed and backed and stat_rows == 8
		and achievement_rows == AchievementManager.ACHIEVEMENTS.size(),
		"opened=%s stat rows=%d achievement rows=%d closed=%s back gesture=%s" % [opened, stat_rows, achievement_rows, closed, backed])


func skins() -> void:
	var original: Texture2D = (load(String(Skins.SKINS[0]["frames"])) as SpriteFrames).get_frame_texture(&"skate", 0)
	var broken: Array[String] = []
	for skin: Dictionary in Skins.SKINS:
		var frames: SpriteFrames = load(String(skin["frames"])) as SpriteFrames
		if frames == null or not frames.has_animation(&"skate") or frames.get_frame_count(&"skate") != 4:
			broken.append(String(skin["id"]))
			continue
		for index: int in range(4):
			if frames.get_frame_texture(&"skate", index).get_size() != original.get_size():
				broken.append("%s frame %d" % [skin["id"], index])
		var track: Dictionary = UpgradeStore.get_track(Skins.get_track_id(skin["id"]))
		if skin["id"] != Skins.DEFAULT_ID and (track.get("skin", "") != skin["id"] or UpgradeStore.get_max_level(track.get("id", "")) != 1):
			broken.append("%s has no one-level shop track" % skin["id"])
	var loaded: MemorySaveStore = MemorySaveStore.new()
	loaded.load_from_data(JSON.parse_string("""{"version": 3, "selected_skin": 7}"""))
	var typed_default: bool = loaded.selected_skin == Skins.DEFAULT_ID
	var unknown_default: bool = Skins.get_skin("retired_skin")["id"] == Skins.DEFAULT_ID
	await new_scene()
	store.upgrade_levels.clear()
	store.coin_wallet = 1000
	store.selected_skin = Skins.DEFAULT_ID
	game_manager._on_skins_pressed()
	var buttons: int = game_manager.skins_row.get_child_count()
	var locked_shown: bool = game_manager.skin_buttons["dad"].disabled and not game_manager.skin_buttons[Skins.DEFAULT_ID].disabled
	game_manager._on_skin_picked("dad")
	var locked_refused: bool = store.selected_skin == Skins.DEFAULT_ID
	game_manager._on_buy_pressed(Skins.get_track_id("dad"))
	var bought_worn: bool = store.selected_skin == "dad" and game_manager.get_worn_skin_id() == "dad" \
		and store.coin_wallet == 1000 - UpgradeStore.SKIN_PARENT_COST
	game_manager._on_reset_progress_confirmed()
	var reset_default: bool = game_manager.get_worn_skin_id() == Skins.DEFAULT_ID
	store.selected_skin = Skins.DEFAULT_ID
	expect("skins", broken.is_empty() and typed_default and unknown_default and buttons == Skins.SKINS.size()
		and locked_shown and locked_refused and bought_worn and reset_default,
		"broken=%s wrong-typed->default=%s unknown->default=%s buttons=%d locked shown=%s refused=%s bought+worn=%s reset->default=%s" % [
			broken, typed_default, unknown_default, buttons, locked_shown, locked_refused, bought_worn, reset_default])


func sparkles() -> void:
	var unknown: Array[String] = []
	for sparkle: Dictionary in Skins.SPARKLES:
		var achievement: String = sparkle["achievement"]
		if not achievement.is_empty() and not AchievementManager.ACHIEVEMENTS.has(achievement):
			unknown.append("%s needs '%s'" % [sparkle["id"], achievement])
	await new_scene()
	store.achievements.clear()
	store.selected_sparkle = Skins.DEFAULT_SPARKLE_ID
	game_manager._on_skins_pressed()
	var buttons: int = game_manager.sparkles_row.get_child_count()
	game_manager._on_sparkle_picked("amber")
	var locked_refused: bool = store.selected_sparkle == Skins.DEFAULT_SPARKLE_ID and game_manager.sparkle_buttons["amber"].disabled
	store.achievements[Skins.get_sparkle("amber")["achievement"]] = true
	game_manager.refresh_skin_buttons()
	game_manager._on_sparkle_picked("amber")
	var earned_picked: bool = store.selected_sparkle == "amber" and game_manager.get_worn_sparkle_id() == "amber"
	game_manager._on_reset_progress_confirmed()
	var reset_relocked: bool = game_manager.get_worn_sparkle_id() == Skins.DEFAULT_SPARKLE_ID
	store.selected_sparkle = Skins.DEFAULT_SPARKLE_ID
	expect("sparkles", unknown.is_empty() and buttons == Skins.SPARKLES.size() and locked_refused and earned_picked and reset_relocked,
		"unknown achievements=%s buttons=%d locked refused=%s earned picked=%s reset relocked=%s" % [
			unknown, buttons, locked_refused, earned_picked, reset_relocked])


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
