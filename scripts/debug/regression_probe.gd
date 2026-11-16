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


class TierSpawner extends RareCoinSpawner:
	var tier_roll: float = 0.0
	func get_coin_hash(_index: int) -> float:
		return tier_roll


class ShoreTerrain extends TerrainGenerator:
	func get_surface_world_y(_x: float) -> float:
		return 0.0
	func is_lake_world_x(x: float) -> bool:
		return x >= 1000.0 and x < 8500.0


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

	if OS.get_cmdline_user_args().has("--ui-only"):
		if DisplayServer.get_name() == "headless":
			push_error("--ui-only requires a renderer")
			quit(1)
			return
		# Keep automated desktop previews quiet without changing saved game volumes.
		AudioServer.set_bus_volume_db(0, -24.0)
		DevMode.is_loaded = true
		DevMode.is_enabled = false
		DevMode.is_invincible = false
		await pause_pointer()
		await dev_speed()
		await chests()
		await chest_tiers()
		await mission_lifecycle()
		await glide_achievement()
		await glide_milestones()
		await melt_lifecycle()
		await collection()
		await rig_lifecycle()
		await menu_layout()
		await lake_exit()
		main.queue_free()
		await process_frame
		print("REGRESSION_UI_RESULT cases=%d failures=%d status=%s" % [cases, failures, "PASS" if failures == 0 else "FAIL"])
		quit(0 if failures == 0 else 1)
		return

	rig_motion()
	glide_milestone_model()
	purchase_rollback()
	save_numbers()
	save_containers()
	await touch_hold()
	await death_stats()
	await chests()
	await chest_tiers()
	mission_model()
	melt_model()
	lake_exit_approach()
	await glide_achievement()
	await death_pickups()
	await reload_banking()
	save_history()
	await stats_screen()
	await skins()
	await sparkles()
	await collection()

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
	# Waiting does not open a chest; tapping opens one, and extra taps during its animation
	# cannot skip the next one. Rewards are already banked independently of these taps.
	if death_ok:
		var reveal: ChestReveal = game_manager.chest_reveal
		await create_timer(0.8).timeout
		death_ok = death_ok and not reveal.stage.is_open and reveal.next_reward == 0
		for index: int in range(2):
			if DisplayServer.get_name() == "headless":
				reveal.open_button.pressed.emit()
			else:
				var at: Vector2 = reveal.open_button.get_global_rect().get_center()
				send_pointer(at, true, true)
				send_pointer(at, false, true)
			reveal.open_button.pressed.emit()
			death_ok = death_ok and reveal.next_reward == index + 1
			await reveal.reveal_tween.finished
	var opened_rows: int = 0
	for row: Node in game_manager.chest_reveal.get_children():
		if row is Label and row.visible and (row.text.contains("coins") or row.text.contains("NEW ")):
			opened_rows += 1
	death_ok = death_ok and opened_rows == 2 and game_manager.chest_reveal.stage.is_open
	expect("chests", rolls_ok and skins_seen > 0 and no_repeat and is_coin and reach_ok and grant_ok and death_ok,
		"rolls=%s skins_seen=%d no_repeat=%s is_coin=%s reach=%s (bottom %.0f, weakest top %.0f) grant=%s death=%s hud=[%s]" % [
			rolls_ok, skins_seen, no_repeat, is_coin, reach_ok, hitbox_bottom, weakest_top, grant_ok, death_ok, hud])


func chest_tiers() -> void:
	var counts: Array[int] = [0, 0, 0]
	for index: int in range(100):
		counts[ChestTypes.from_roll((index + 0.5) / 100.0)] += 1
	var weights_ok: bool = counts == [70, 25, 5]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var normal_cosmetics: int = 0
	var rare_cosmetics: int = 0
	var guaranteed: bool = true
	for trial: int in range(2000):
		normal_cosmetics += int(ChestRewards.roll([], rng, ["charm_moon"], ChestTypes.Tier.NORMAL)["cosmetic"] != "")
		rare_cosmetics += int(ChestRewards.roll([], rng, ["charm_moon"], ChestTypes.Tier.RARE)["cosmetic"] != "")
		var reward: Dictionary = ChestRewards.roll([], rng, ["charm_moon"], ChestTypes.Tier.AURORA)
		guaranteed = guaranteed and reward["cosmetic"] == "charm_moon" and reward["tier"] == ChestTypes.Tier.AURORA
	var fallback: Dictionary = ChestRewards.roll([], rng, [], ChestTypes.Tier.AURORA)
	guaranteed = guaranteed and fallback["jackpot"] and fallback["coins"] >= 200 and fallback["coins"] <= 300
	var auroras: Array[int] = []
	auroras.resize(Cosmetics.ITEMS.size() + 1)
	auroras.fill(ChestTypes.Tier.AURORA)
	var guaranteed_run: Array[Dictionary] = ChestRewards.roll_all(auroras.size(), [], rng, Cosmetics.get_unowned({}), auroras)
	var found: Array[String] = []
	for reward: Dictionary in guaranteed_run:
		if reward["cosmetic"] != "":
			guaranteed = guaranteed and not found.has(reward["cosmetic"])
			found.append(reward["cosmetic"])
	guaranteed = guaranteed and found.size() == Cosmetics.ITEMS.size() and guaranteed_run[-1]["jackpot"]
	await new_scene()
	store.mission_id = "distance"
	store.mission_progress = 0.0
	game_manager.prepare_mission()
	var spawner: TierSpawner = TierSpawner.new()
	spawner.debug_spawning_disabled = true
	main.get_node("TerrainGenerator").add_child(spawner)
	spawner.chest_collected.connect(game_manager._on_chest_collected)
	var placement_ok: bool = true
	for tier: int in range(3):
		spawner.tier_roll = [0.2, 0.8, 0.98][tier]
		var placed: bool = false
		for world_x: int in range(int(START_X) + 1500, int(START_X) + 40000, 50):
			if spawner.try_spawn_chest(float(world_x)):
				placed = true
				break
		placement_ok = placement_ok and placed
		if not placed:
			continue
		var chest: ChestPickup = spawner.active_coins.back() as ChestPickup
		var radius: float = ((chest.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius
		placement_ok = placement_ok and chest.tier == tier and chest.scale == Vector2.ONE and radius == 16.0
		chest._on_body_entered(player)
	placement_ok = placement_ok and game_manager.collected_chest_tiers == [0, 1, 2]
	player.die()
	placement_ok = placement_ok and game_manager.chest_rewards.size() == 3
	for index: int in range(mini(game_manager.chest_rewards.size(), 3)):
		placement_ok = placement_ok and game_manager.chest_rewards[index]["tier"] == index
	expect("chest_tiers", weights_ok and guaranteed and placement_ok and normal_cosmetics > 500 and normal_cosmetics < 700 \
		and rare_cosmetics > 1100 and rare_cosmetics < 1300,
		"weights=%s cosmetic normal=%d rare=%d/2000 guarantee/fallback=%s real spawn/collect/death tiers=%s" % [
			counts, normal_cosmetics, rare_cosmetics, guaranteed, placement_ok])


func mission_model() -> void:
	var saved: MemorySaveStore = MemorySaveStore.new()
	saved.load_from_data({"version": 4, "coin_wallet": 125, "cosmetics": {"trail_comet": true}})
	var compatible: bool = saved.mission_id == "coins" and saved.mission_progress == 0.0 \
		and saved.coin_wallet == 125 and saved.cosmetics.get("trail_comet", false)
	var mission: Dictionary = Missions.prepare(saved, false)
	Missions.bank(saved, mission, 60.0)
	Missions.bank(saved, mission, -40.0)
	var partial: bool = saved.mission_progress == 60.0 and not Missions.claim(saved, mission, false)
	Missions.bank(saved, mission, 80.0)
	var pending: MemorySaveStore = MemorySaveStore.new()
	pending.load_from_data(JSON.parse_string(JSON.stringify(saved.to_data())))
	var durable: bool = pending.mission_progress == 100.0 and pending.mission_id == "coins"
	var claimed: bool = Missions.claim(pending, Missions.prepare(pending, false), false)
	var once: bool = claimed and not Missions.claim(pending, mission, false) and pending.missions_completed == 1 \
		and pending.mission_id == "distance" and pending.mission_progress == 0.0 and pending.writes == 0
	pending.mission_id = "geodes"
	pending.mission_progress = 2.0
	var gated: bool = Missions.prepare(pending, false)["id"] != "geodes" and pending.mission_progress == 0.0
	pending.mission_id = "geodes"
	gated = gated and Missions.prepare(pending, true)["id"] == "geodes"
	pending.mission_id = "future_goal"
	pending.mission_progress = 99.0
	gated = gated and Missions.prepare(pending, true)["id"] == "coins" and pending.mission_progress == 0.0
	var bad: MemorySaveStore = MemorySaveStore.new()
	bad.load_from_data({"version": 5, "mission_id": [], "mission_progress": INF, "missions_completed": -1})
	var valid: bool = bad.mission_id == "coins" and bad.mission_progress == 0.0 and bad.missions_completed == 0
	pending.reset_progress()
	var reset: bool = pending.mission_id == "coins" and pending.mission_progress == 0.0 and pending.missions_completed == 0
	expect("mission_model", compatible and partial and durable and once and gated and valid and reset,
		"v4=%s partial=%s pending survived JSON=%s once=%s eligibility=%s malformed=%s reset=%s" % [
			compatible, partial, durable, once, gated, valid, reset])


# Real death/pause banking uses the production guards, so this integration runs with a
# renderer and an injected MemorySaveStore; headless gates never mutate the developer's save.
func mission_lifecycle() -> void:
	store.mission_id = "coins"
	store.mission_progress = 70.0
	store.missions_completed = 0
	await new_scene()
	game_manager.coin_count = 0
	game_manager.prepare_mission()
	game_manager.coin_count = 10
	var before: int = store.writes
	game_manager.set_state(GameManager.State.PAUSED)
	var partial: bool = store.mission_progress == 80.0 and store.writes == before + 1
	game_manager.set_state(GameManager.State.PLAYING)
	# Resuming flushes settings through the existing save path. Count only the
	# following pause when checking that unchanged mission progress adds no write.
	var partial_writes: int = store.writes
	game_manager.set_state(GameManager.State.PAUSED)
	partial = partial and store.mission_progress == 80.0 and store.writes == partial_writes
	game_manager.set_state(GameManager.State.PLAYING)
	game_manager.coin_count = 30
	game_manager.set_state(GameManager.State.PAUSED)
	var completed: bool = store.mission_progress == 100.0 and game_manager.get_mission_progress() == 100.0
	var banked_writes: int = store.writes
	game_manager.set_state(GameManager.State.PAUSED)
	var no_repeat: bool = store.mission_progress == 100.0 and store.writes == banked_writes
	await new_scene()
	game_manager.coin_count = 0
	before = store.writes
	player.die()
	var paid: bool = store.missions_completed == 1 and store.mission_id == "distance" and store.mission_progress == 0.0 \
		and store.writes == before + 1 and game_manager.chest_rewards.size() == 1 \
		and game_manager.chest_rewards[0]["tier"] == ChestTypes.Tier.RARE and game_manager.chest_rewards[0].get("mission", false)
	await new_scene()
	game_manager.set_state(GameManager.State.PAUSED)
	store.mission_id = "distance"
	store.mission_progress = 500.0
	game_manager.prepare_mission()
	game_manager.set_state(GameManager.State.PLAYING)
	player.position.x += 32.0 * 60.0
	game_manager.set_state(GameManager.State.PAUSED)
	var distance_ok: bool = is_equal_approx(store.mission_progress, 560.0)
	store.mission_id = "chests"
	store.mission_progress = 1.0
	game_manager.prepare_mission()
	game_manager.set_state(GameManager.State.PLAYING)
	game_manager._on_chest_collected(ChestTypes.Tier.AURORA)
	game_manager.set_state(GameManager.State.PAUSED)
	var chests_ok: bool = store.mission_progress == 2.0
	store.upgrade_levels[UpgradeStore.SLAM_UPGRADE_ID] = 1
	store.mission_id = "geodes"
	store.mission_progress = 1.0
	game_manager.prepare_mission()
	game_manager.set_state(GameManager.State.PLAYING)
	game_manager._on_geode_broken(10)
	game_manager.set_state(GameManager.State.PAUSED)
	var geodes_ok: bool = store.mission_progress == 2.0
	expect("mission_lifecycle", partial and completed and no_repeat and paid and distance_ok and chests_ok and geodes_ok,
		"pause delta=%s complete=%s no duplicate=%s one death write/reward=%s distance=%s chests=%s geodes=%s" % [
			partial, completed, no_repeat, paid, distance_ok, chests_ok, geodes_ok])


# Rendered input delivery: root.push_input dispatches _input and GUI; parse_input_event
# alone bypasses _input in a --script run, even with a renderer. Headless cannot cover this.
func pause_pointer() -> void:
	await new_scene()
	var accidental_actions: Array[int] = [0]
	game_manager.pause_home_button.pressed.disconnect(game_manager._on_home_pressed)
	game_manager.pause_home_button.pressed.connect(func(): accidental_actions[0] += 1)
	var passed: bool = true
	for touch: bool in [true, false]:
		for hold_frames: int in [0, 3]:
			game_manager.set_state(GameManager.State.PLAYING)
			var at: Vector2 = game_manager.pause_button.get_global_rect().get_center()
			send_pointer(at, true, touch)
			passed = passed and game_manager.state == GameManager.State.PAUSED
			for frame: int in range(hold_frames):
				await process_frame
			send_pointer(at, false, touch)
			await process_frame
			passed = passed and paused and accidental_actions[0] == 0 and game_manager.state == GameManager.State.PAUSED
			if not passed:
				break
			# A fresh gesture on Resume works without holding Pause.
			at = game_manager.resume_button.get_global_rect().get_center()
			send_pointer(at, true, touch)
			send_pointer(at, false, touch)
			passed = passed and game_manager.state == GameManager.State.PLAYING
			if not passed:
				break
		if not passed:
			break
	expect("pause_pointer", passed, "touch/mouse, quick/held Pause release stays paused; fresh Resume works")


func send_pointer(at: Vector2, down: bool, touch: bool) -> void:
	var event: InputEvent
	if touch:
		var tap: InputEventScreenTouch = InputEventScreenTouch.new()
		tap.position = at
		tap.index = 0
		tap.pressed = down
		event = tap
	else:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = at
		click.global_position = at
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		event = click
	root.push_input(event, true)


func dev_speed() -> void:
	DevMode.is_enabled = true
	await new_scene()
	var capped: bool = player.speed_manager.current_speed == SpeedManager.MAX_SPEED and main.elapsed_time < 1.0
	capped = capped and (main.get_node("TerrainGenerator/RareCoinSpawner") as RareCoinSpawner).debug_cycle_chest_tiers
	DevMode.is_enabled = false
	await new_scene()
	expect("dev_speed", capped and player.speed_manager.current_speed < SpeedManager.MAX_SPEED
		and not (main.get_node("TerrainGenerator/RareCoinSpawner") as RareCoinSpawner).debug_cycle_chest_tiers,
		"dev starts at cap without advancing the run clock; normal run retains its ramp")


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
	expect("stats_screen", opened and closed and backed and stat_rows == 11
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


func collection() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var ids: Array[String] = Cosmetics.get_unowned({})
	var seen: Array[String] = []
	var rewards: Array[Dictionary] = ChestRewards.roll_all(400, [], rng, ids)
	var unique: bool = true
	for item: Dictionary in Cosmetics.ITEMS:
		unique = unique and ResourceLoader.exists(item.get("icon", Cosmetics.ICONS[item["kind"]]))
	unique = unique and ids.size() == Cosmetics.ITEMS.size()
	for reward: Dictionary in rewards:
		var id: String = reward["cosmetic"]
		if not id.is_empty():
			unique = unique and ids.has(id) and not seen.has(id) and reward["coins"] == 0
			unique = unique and ChestReveal.describe([reward]).contains(Cosmetics.get_item(id)["name"]) and ChestReveal.is_big_reward([reward])
			seen.append(id)
	var exhausted: bool = ChestReveal.describe(rewards).length() < 120
	for index: int in range(100):
		exhausted = exhausted and ChestRewards.roll([], rng, [])["cosmetic"] == ""
	var old: MemorySaveStore = MemorySaveStore.new()
	old.load_from_data({"version": 3, "coin_wallet": 125, "upgrades": {"skin_mom": 1}})
	var compatible: bool = old.cosmetics.is_empty() and old.coin_wallet == 125 and old.upgrade_levels.get("skin_mom", 0) == 1
	var bad: MemorySaveStore = MemorySaveStore.new()
	bad.load_from_data({"version": 4, "coin_wallet": 42, "cosmetics": {"trail_comet": true, "bad": 1, "future_item": true},
		"selected_cosmetics": {"trail": "trail_comet", "outfit": 17}})
	var validated: bool = bad.coin_wallet == 42 and bad.cosmetics.size() == 2 and bad.selected_cosmetics.size() == 1
	var malformed: MemorySaveStore = MemorySaveStore.new()
	malformed.load_from_data({"version": 4, "cosmetics": [], "selected_cosmetics": 7, "coin_wallet": 42})
	validated = validated and malformed.cosmetics.is_empty() and malformed.selected_cosmetics.is_empty() and malformed.coin_wallet == 42
	await new_scene()
	store.cosmetics.clear()
	store.selected_cosmetics.clear()
	game_manager._on_skins_pressed()
	var buttons_ok: bool = game_manager.collection_buttons.size() == ids.size() + 2
	game_manager._on_cosmetic_picked("trail", "trail_comet")
	var locked_refused: bool = game_manager.get_worn_cosmetic("trail").is_empty()
	var writes_before: int = store.writes
	store.grant_chest_rewards(rewards)
	var grant_ok: bool = store.cosmetics.size() == ids.size() and store.writes == writes_before
	game_manager._on_cosmetic_picked("trail", "trail_comet")
	game_manager._on_cosmetic_picked("outfit", "outfit_glacier")
	game_manager._on_cosmetic_picked("charm", "charm_moon")
	game_manager._on_cosmetic_picked("outfit", "trail_comet")
	var selected: bool = game_manager.get_worn_cosmetic("trail") == "trail_comet" and game_manager.get_worn_cosmetic("outfit") == "outfit_glacier" \
		and not store.selected_cosmetics.has("charm")
	store.succeed = false
	game_manager._on_cosmetic_picked("trail", "trail_ribbon")
	var rolled_back: bool = game_manager.get_worn_cosmetic("trail") == "trail_comet"
	store.succeed = true
	var loaded: MemorySaveStore = MemorySaveStore.new()
	loaded.load_from_data(JSON.parse_string(JSON.stringify(store.to_data())))
	var persisted: bool = loaded.cosmetics == store.cosmetics and loaded.selected_cosmetics == store.selected_cosmetics
	var applied: bool = true
	if DisplayServer.get_name() != "headless":
		applied = player.flight_trail.cosmetic_active and player.flight_trail.streak_length == 26.0 \
			and player.animated_sprite.material is ShaderMaterial
		game_manager.apply_sparkle()
		applied = applied and player.flight_trail.modulate == Cosmetics.get_item("trail_comet")["color"]
		var emitted: bool = false
		for frame: int in range(8):
			game_manager.set_state(GameManager.State.PLAYING)
			await process_frame
			emitted = emitted or player.flight_trail.get_child_count() > 0
		applied = applied and emitted
		game_manager.set_state(GameManager.State.SKINS)
	game_manager._on_reset_progress_confirmed()
	var reset_ok: bool = store.cosmetics.is_empty() and store.selected_cosmetics.is_empty() and game_manager.get_worn_cosmetic("trail").is_empty()
	if DisplayServer.get_name() != "headless":
		reset_ok = reset_ok and not player.flight_trail.cosmetic_active and player.animated_sprite.material == null
	expect("collection", unique and seen.size() == ids.size() and exhausted and compatible and validated and buttons_ok \
		and locked_refused and grant_ok and selected and rolled_back and persisted and applied and reset_ok,
		"unique=%s found=%d compatible=%s validated=%s buttons=%s locked=%s grant=%s picks=%s rollback=%s persisted=%s applied=%s reset=%s" % [
			unique, seen.size(), compatible, validated, buttons_ok, locked_refused, grant_ok, selected, rolled_back, persisted, applied, reset_ok])


# Real renderer/layout check at the base viewport and the owner's phone aspect ratio.
# Headless's 64px viewport cannot establish either visibility or usable menu geometry.
func menu_layout() -> void:
	await new_scene()
	var original_size: Vector2i = root.size
	var passed: bool = true
	for size: Vector2i in [Vector2i(1152, 648), Vector2i(1404, 648)]:
		root.size = size
		game_manager.set_state(GameManager.State.START)
		for frame: int in range(3):
			await process_frame
		var primary: StyleBoxFlat = game_manager.start_button.get_theme_stylebox("normal") as StyleBoxFlat
		passed = passed and primary != null and primary.bg_color.a > 0.5 and not game_manager.coin_label.visible
		game_manager._on_start_shop_pressed()
		for frame: int in range(3):
			await process_frame
		for row: Dictionary in game_manager.shop_rows.values():
			passed = passed and ui_rect_fits(row["card"])
		passed = passed and ui_rect_fits(game_manager.reset_progress_button)
		game_manager._on_shop_close_pressed()
		game_manager._on_skins_pressed()
		game_manager.collection_tabs.current_tab = 1
		for frame: int in range(3):
			await process_frame
		for button: Button in game_manager.collection_buttons.values():
			passed = passed and ui_rect_fits(button)
		passed = passed and ui_rect_fits(game_manager.skins_close_button)
	root.size = original_size
	expect("menu_layout", passed, "primary button style applied; HUD hidden on menus; shop/collection fit 16:9 and phone")


func ui_rect_fits(control: Control) -> bool:
	return root.get_visible_rect().grow(0.5).encloses(control.get_global_rect())


# A fresh scene, settled on the ground at START_X with nothing spawning. Frees the previous one.
func new_scene(lake_index: int = -1) -> void:
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	paused = false
	main = MAIN_SCENE.instantiate() as Main
	var terrain: TerrainGenerator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	game_manager = main.get_node("GameManager") as GameManager
	terrain.debug_replay_session_seed = SEED
	terrain.debug_force_lake_segment_index = lake_index
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


func melt_model() -> void:
	var idle: MeltRound = MeltRound.new()
	idle.advance(1.0)
	var frozen: bool = idle.elapsed == 0.0
	idle.start()
	for frame: int in range(7200):
		idle.advance(1.0 / 120.0)
		if idle.finished:
			break
	var falls: bool = idle.finished and idle.elapsed < 10.0
	var fair: bool = true
	var times: Array[float] = []
	for lead: float in [45.0, 70.0, 90.0]:
		var round: MeltRound = MeltRound.new()
		round.start()
		for frame: int in range(7300):
			for platform: Dictionary in round.platforms:
				if int(platform["index"]) == round.grounded_index and float(platform["x"]) + float(platform["width"]) - round.x <= lead:
					round.request_jump()
			round.advance(1.0 / 120.0)
			if round.finished:
				break
		times.append(round.elapsed)
		fair = fair and round.finished and round.elapsed >= MeltRound.AURORA_SECONDS \
			and round.elapsed <= MeltRound.MAX_SECONDS + 0.01 and round.platforms.size() < 24
	var air: MeltRound = MeltRound.new()
	air.start()
	air.request_jump()
	air.advance(0.05)
	var up: float = air.velocity_y
	air.request_jump()
	air.advance(0.05)
	var no_air_jump: bool = air.velocity_y > up and air.feet_y < 0.0
	var saved: MemorySaveStore = MemorySaveStore.new()
	saved.coin_wallet = 40
	saved.mission_progress = 15.0
	saved.best_melt_seconds = 12.0
	var reward: Array[Dictionary] = [{"coins": 35, "cosmetic": "trail_comet", "skin": ""}]
	saved.succeed = false
	var failed: bool = not saved.bank_bonus(10, reward, 31.0) and saved.coin_wallet == 40 \
		and not saved.cosmetics.get("trail_comet", false) and saved.mission_progress == 15.0 and saved.best_melt_seconds == 12.0
	saved.succeed = true
	var banked: bool = saved.bank_bonus(10, reward, 31.0) and saved.coin_wallet == 85 \
		and saved.cosmetics.get("trail_comet", false) and saved.total_coins_earned == 45 and saved.best_melt_seconds == 31.0
	saved.bank_bonus(0, [], 20.0)
	var restored: MemorySaveStore = MemorySaveStore.new()
	restored.load_from_data(JSON.parse_string(JSON.stringify(saved.to_data())))
	var best_ok: bool = restored.best_melt_seconds == 31.0
	for invalid: Variant in [INF, -2.0, "bad"]:
		var bad: MemorySaveStore = MemorySaveStore.new()
		bad.load_from_data({"version": 5, "best_melt_seconds": invalid})
		best_ok = best_ok and bad.best_melt_seconds == 0.0
	restored.reset_progress()
	best_ok = best_ok and restored.best_melt_seconds == 0.0
	expect("melt_model", frozen and falls and fair and no_air_jump and failed and banked and best_ok,
		"idle=%s no-input loss=%s valid jump windows end at %s bounded/fair=%s no air jump=%s atomic rollback/retry=%s best JSON/validation/reset=%s" % [
			frozen, falls, times, fair, no_air_jump, failed and banked, best_ok])


func lake_exit_approach() -> void:
	# Flat dry ground removes slope/height as alternative reasons for rejection.
	var terrain: ShoreTerrain = ShoreTerrain.new()
	var spike: Dictionary = {"pieces": [{"kind": ObstacleSpawner.PIECE_SPIKE, "at": 0.0}]}
	var unsafe_rejected: bool = true
	var dry_allowed: bool = true
	for speed: float in [SpeedManager.MAX_SPEED, PowerupManager.SPEED_BOOST_SPEED]:
		var reach: float = 2.0 * -Player.JUMP_VELOCITY * UpgradeStore.get_min_jump_multiplier() / Player.GRAVITY * speed
		unsafe_rejected = unsafe_rejected and not ObstacleSpawner.is_spike_approach_clear(terrain, spike, 8530.0, speed)
		dry_allowed = dry_allowed and ObstacleSpawner.is_spike_approach_clear(terrain, spike, 8500.0 + reach + 1.0, speed)
	terrain.free()
	expect("lake_exit_approach", unsafe_rejected and dry_allowed,
		"spike beyond shore with locked takeoff rejected=%s; dry approach allowed=%s at cap and boost" % [unsafe_rejected, dry_allowed])


func lake_exit() -> void:
	var clipped: bool = true
	var jumps: bool = true
	var completed_once: bool = true
	var outside_changes: Array[int] = []
	for width: int in [1152, 1404]:
		root.size = Vector2i(width, 648)
		await new_scene(200)
		game_manager.set_state(GameManager.State.PAUSED)
		var terrain: TerrainGenerator = main.get_node("TerrainGenerator")
		var lake: FrozenLakeDirector = main.get_node("FrozenLakeDirector")
		var reflection: LakeReflection = main.get_node("LakeReflection")
		lake.lake_start_x = terrain.get_lake_start_x()
		lake.lake_end_x = terrain.get_lake_end_x()
		player.global_position.x = lake.lake_end_x - 600.0
		var surface: float = terrain.get_surface_world_y(player.global_position.x)
		player.global_position.y = surface - player.capsule_half_height
		for chunk_index: int in terrain.active_chunks.keys():
			terrain.remove_chunk(chunk_index)
		terrain.initialize_chunks()
		lake.begin_lake()
		var camera: Camera2D = main.get_node("Camera2D")
		var view_size: Vector2 = Vector2(root.size) / camera.zoom
		camera.global_position = Vector2(player.global_position.x + (0.5 - Main.PLAYER_SCREEN_X_FRACTION) * view_size.x,
			surface + (0.5 - Main.LAKE_HORIZON_FRACTION) * view_size.y)
		camera.force_update_scroll()
		main.get_node("CanvasLayer").visible = false
		reflection._physics_process(0.0)
		reflection.visible = false
		for frame: int in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var bare: Image = root.get_texture().get_image()
		reflection.visible = true
		for frame: int in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var mirrored: Image = root.get_texture().get_image()
		var edge: Vector2 = main.get_global_transform_with_canvas() * Vector2(lake.lake_end_x, surface)
		var changed: int = 0
		var checked: int = 0
		for x: int in range(ceili(edge.x) + 8, mirrored.get_width() - 8, 4):
			for y: int in range(ceili(edge.y) + 8, mirrored.get_height() - 8, 4):
				var a: Color = bare.get_pixel(x, y)
				var b: Color = mirrored.get_pixel(x, y)
				checked += 1
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.025:
					changed += 1
		outside_changes.append(changed)
		clipped = clipped and checked > 100 and changed == 0
		if OS.get_cmdline_user_args().has("--lake-capture"):
			bare.save_png("/tmp/aura-lake-exit-%d-bare.png" % width)
			mirrored.save_png("/tmp/aura-lake-exit-%d-mirror.png" % width)
		main.get_node("CanvasLayer").visible = true
		# Hills become visible during the fade, before the physical shore. A press
		# here must already work, rather than needing another press after exit.
		game_manager.set_state(GameManager.State.PLAYING)
		var fade_x: float = lake.lake_end_x - 1200.0
		player.global_position = Vector2(fade_x, terrain.get_surface_world_y(fade_x) - player.capsule_half_height)
		player.velocity = Vector2(SpeedManager.MAX_SPEED, 0.0)
		player.is_jump_ascending = false
		player.jump_buffer_timer = 0.0
		lake.begin_lake()
		send_pointer(Vector2(width * 0.5, 120.0), true, true)
		for frame: int in range(2):
			await physics_frame
		jumps = jumps and player.is_jump_ascending and player.velocity.y < 0.0
		send_pointer(Vector2(width * 0.5, 120.0), false, true)
		# A single real input just before the first beyond-shore tick must not be lost.
		for touch: bool in [true, false]:
			game_manager.set_state(GameManager.State.PLAYING)
			var current_surface: float = terrain.get_surface_world_y(lake.lake_end_x - 75.0)
			player.global_position = Vector2(lake.lake_end_x - 75.0, current_surface - player.capsule_half_height)
			player.velocity = Vector2(SpeedManager.MAX_SPEED, 0.0)
			player.speed_manager.current_speed = SpeedManager.MAX_SPEED
			player.is_jump_ascending = false
			var count: int = store.frozen_lake_count
			lake.begin_lake()
			for frame: int in range(4):
				game_manager.set_state(GameManager.State.PLAYING)
				await physics_frame
			if touch:
				send_pointer(Vector2(width * 0.5, 120.0), true, true)
			else:
				Input.action_press(&"ui_accept")
			for frame: int in range(2):
				await physics_frame
			jumps = jumps and not player.is_jump_suppressed and player.is_jump_ascending and player.velocity.y < 0.0
			if touch:
				send_pointer(Vector2(width * 0.5, 120.0), false, true)
			else:
				Input.action_release(&"ui_accept")
			for frame: int in range(3):
				await physics_frame
			completed_once = completed_once and lake.phase == FrozenLakeDirector.Phase.DONE \
				and not player.is_jump_suppressed and terrain.lake_ice_blend == 0.0 and store.frozen_lake_count == count + 1
			game_manager.set_state(GameManager.State.PAUSED)
	expect("lake_exit", clipped and jumps and completed_once,
		"outside-lake changed pixels=%s clip=%s real touch/key shore jumps=%s unlock/finish=%s at16:9 and phone" % [
			outside_changes, clipped, jumps, completed_once])


func glide_achievement() -> void:
	store.achievements.erase(AchievementManager.REALLY)
	await new_scene()
	game_manager.set_state(GameManager.State.PAUSED)
	var before: int = store.writes
	player.start_glide()
	Input.action_press(&"ui_accept")
	for frame: int in range(200):
		player.track_glide_ascent(1.0 / 60.0, -10.0)
	player.end_glide()
	var short_refused: bool = not store.achievements.get(AchievementManager.REALLY, false)
	player.start_glide()
	for frame: int in range(410):
		player.track_glide_ascent(1.0 / 60.0, -10.0)
	Input.action_release(&"ui_accept")
	player.track_glide_ascent(1.0 / 60.0, -10.0)
	player.end_glide()
	var release_refused: bool = not store.achievements.get(AchievementManager.REALLY, false)
	# Touch follows its own path on Android. Track local displacement, not absolute Y.
	store.succeed = false
	player.start_glide()
	main.held_touch_indices[7] = true
	for frame: int in range(410):
		player.track_glide_ascent(1.0 / 60.0, -10.0)
	player.end_glide()
	main.held_touch_indices.clear()
	var headless: bool = DisplayServer.get_name() == "headless"
	var failed_save: bool = not store.achievements.get(AchievementManager.REALLY, false)
	store.succeed = true
	player.start_glide()
	main.held_touch_indices[7] = true
	for frame: int in range(410):
		player.track_glide_ascent(1.0 / 60.0, -10.0)
	player.end_glide()
	main.held_touch_indices.clear()
	var awarded: bool = store.achievements.get(AchievementManager.REALLY, false) == not headless \
		and store.writes == before + (0 if headless else 2)
	player.end_glide()
	var once: bool = store.writes == before + (0 if headless else 2)
	var restored: MemorySaveStore = MemorySaveStore.new()
	restored.load_from_data(JSON.parse_string(JSON.stringify(store.to_data())))
	var durable: bool = restored.achievements.get(AchievementManager.REALLY, false) == not headless
	expect("glide_achievement", short_refused and release_refused and failed_save and awarded and once and durable,
		"short/interrupted refused=%s failed save retries=%s touch ascent=%s once=%s JSON=%s headless=%s" % [
			short_refused and release_refused, failed_save, awarded, once, durable, headless])


func glide_milestone_model() -> void:
	var saved: MemorySaveStore = MemorySaveStore.new()
	var previous_save: SaveStore = services.save_store
	services.save_store = saved
	var manager: AchievementManager = AchievementManager.new()
	manager.services = services
	var earned: Array[String] = []
	var receipts: Array[Dictionary] = []
	manager.achievement_granted.connect(func(id: String, _name: String) -> void: earned.append(id))
	manager.chest_reward_granted.connect(func(reward: Dictionary) -> void: receipts.append(reward))
	saved.succeed = false
	manager.record_high_glide()
	var rollback: bool = saved.high_glide_count == 0 and saved.achievements.is_empty() and earned.is_empty()
	saved.succeed = true
	for ascent: int in range(9):
		manager.record_high_glide()
	var before_ten: bool = saved.high_glide_count == 9 and saved.achievements.get(AchievementManager.REALLY, false) 		and not saved.achievements.get(AchievementManager.STILL, false)
	manager.record_high_glide()
	var tenth: bool = saved.high_glide_count == 10 and earned.count(AchievementManager.STILL) == 1 		and receipts.is_empty() and saved.coin_wallet == 0
	for ascent: int in range(39):
		manager.record_high_glide()
	var before_fifty: bool = saved.high_glide_count == 49 and not saved.achievements.get(AchievementManager.FINE_HERE_YOU_GO, false)
	saved.succeed = false
	manager.record_high_glide()
	rollback = rollback and saved.high_glide_count == 49 and saved.coin_wallet == 0 and saved.cosmetics.is_empty() 		and not saved.achievements.get(AchievementManager.FINE_HERE_YOU_GO, false) and receipts.is_empty()
	saved.succeed = true
	var writes: int = saved.writes
	manager.record_high_glide()
	var fiftieth: bool = saved.high_glide_count == 50 and saved.coin_wallet == 1000 and saved.total_coins_earned == 1000 		and saved.cosmetics.size() == 3 and receipts.size() == 1 and saved.writes == writes + 1 		and earned.count(AchievementManager.FINE_HERE_YOU_GO) == 1
	if receipts.size() == 1:
		fiftieth = fiftieth and ChestRewards.get_loot(receipts).size() == 4 			and ChestRewards.get_total_coins(receipts) == 1000 and ChestReveal.describe(receipts).contains("3 new finds")
	var loaded: MemorySaveStore = MemorySaveStore.new()
	loaded.load_from_data(JSON.parse_string(JSON.stringify(saved.to_data())))
	services.save_store = loaded
	manager.record_high_glide()
	var once: bool = loaded.high_glide_count == 51 and loaded.coin_wallet == 1000 		and loaded.cosmetics.size() == 3 and receipts.size() == 1 and earned.count(AchievementManager.STILL) == 1
	loaded.reset_progress()
	var reset: bool = loaded.high_glide_count == 0 and loaded.achievements.is_empty()
	var legacy: MemorySaveStore = MemorySaveStore.new()
	legacy.load_from_data({"version": 5, "achievements": {"really": true}})
	var migration: bool = legacy.high_glide_count == 1
	for bad: Variant in [-1, INF, "bad", null, 1e30]:
		var malformed: MemorySaveStore = MemorySaveStore.new()
		malformed.load_from_data({"version": 5, "high_glide_count": bad})
		migration = migration and malformed.high_glide_count == 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var exhausted: Array[Dictionary] = [ChestRewards.roll_glide_chest([], rng, [])]
	var fallback: bool = ChestRewards.get_total_coins(exhausted) >= 1600 and ChestRewards.get_total_coins(exhausted) <= 1900
	services.save_store = previous_save
	manager.free()
	expect("glide_milestone_model", before_ten and tenth and before_fifty and rollback and fiftieth and once and reset and migration and fallback,
		"10/50 thresholds=%s atomic count/flags/loot retry=%s three unique finds +1000=%s one write=%s JSON/no repeat=%s reset=%s legacy/malformed=%s exhausted fallback=%s" % [
			before_ten and tenth and before_fifty, rollback, fiftieth, saved.writes == writes + 1, once, reset, migration, fallback])


func glide_milestones() -> void:
	await new_scene()
	game_manager.set_state(GameManager.State.PAUSED)
	store.high_glide_count = 49
	store.achievements[AchievementManager.REALLY] = true
	store.achievements[AchievementManager.STILL] = true
	store.achievements.erase(AchievementManager.FINE_HERE_YOU_GO)
	store.cosmetics.clear()
	store.coin_wallet = 40
	store.mission_id = "coins"
	store.mission_progress = 0.0
	game_manager.prepare_mission()
	var before: int = store.writes
	player.start_glide()
	main.held_touch_indices[7] = true
	for frame: int in range(410):
		player.track_glide_ascent(1.0 / 60.0, -10.0)
	player.end_glide()
	main.held_touch_indices.clear()
	var paid: bool = store.high_glide_count == 50 and store.coin_wallet == 1040 and store.cosmetics.size() == 3 		and store.writes == before + 1 and game_manager.earned_chest_rewards.size() == 1
	player.end_glide()
	paid = paid and store.writes == before + 1
	game_manager._on_player_died()
	var no_double_pay: bool = store.coin_wallet == 1040 and game_manager.chest_rewards.size() == 1 		and game_manager.earned_chest_rewards.is_empty() and game_manager.coin_count == 0
	var reveal: ChestReveal = game_manager.chest_reveal
	var label_ok: bool = reveal.open_label.text.contains(ChestRewards.GLIDE_CHEST_NAME)
	var original_size: Vector2i = root.size
	for width: int in [1152, 1404]:
		root.size = Vector2i(width, 648)
		for frame: int in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		label_ok = label_ok and ui_rect_fits(reveal.open_button) and ui_rect_fits(game_manager.restart_button) \
			and reveal.open_label.get_minimum_size().x <= reveal.open_button.size.x \
			and reveal.open_label.get_minimum_size().y <= reveal.open_label.size.y
		root.get_texture().get_image().save_png("/tmp/aura-glide-chest-%d.png" % width)
	var banked_writes: int = store.writes
	reveal.open_next()
	await reveal.reveal_tween.finished
	var description: String = (reveal.get_child(-1) as Label).text
	var opens: bool = reveal.next_reward == 1 and description.contains("3 new finds") and description.contains("1000") 		and store.writes == banked_writes and store.coin_wallet == 1040
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/aura-glide-milestone-chest.png")
	root.size = original_size
	expect("glide_milestones", paid and no_double_pay and label_ok and opens,
		"real completed glide pays once=%s death only reveals=%s named bundle=%s tap opens all loot/no save=%s" % [paid, no_double_pay, label_ok, opens])


func melt_lifecycle() -> void:
	await new_scene()
	game_manager.set_state(GameManager.State.PLAYING)
	var director: MeltDirector = main.get_node("MeltDirector")
	var spawner: RareCoinSpawner = main.get_node("TerrainGenerator/RareCoinSpawner")
	var terrain: TerrainGenerator = main.get_node("TerrainGenerator")
	director.debug_first_seconds = 12.0
	director.due = -1.0
	main.elapsed_time = 11.0
	director._process(0.0)
	var schedule_ok: bool = not director.portal_spawned and director.due == 12.0
	main.elapsed_time = 12.0
	for candidate: int in range(20000, 60000, 64):
		player.global_position = Vector2(float(candidate), terrain.get_surface_world_y(float(candidate)) - player.capsule_half_height)
		director._process(0.0)
		if director.portal_spawned:
			break
	schedule_ok = schedule_ok and director.portal_spawned
	var portal_count: int = spawner.active_coins.size()
	director._process(0.0)
	schedule_ok = schedule_ok and spawner.active_coins.size() == portal_count
	if not director.portal_spawned:
		expect("melt_lifecycle", false, "no legal scheduled portal found")
		return
	var portal: MeltPortal = spawner.active_coins[-1] as MeltPortal
	player.global_position = portal.global_position
	player.velocity = Vector2.ZERO
	for chunk_index: int in terrain.active_chunks.keys():
		terrain.remove_chunk(chunk_index)
	terrain.initialize_chunks()
	for frame: int in range(8):
		await physics_frame
		if game_manager.state == GameManager.State.BONUS:
			break
	var entered_ok: bool = game_manager.state == GameManager.State.BONUS and paused and director.view.visible
	var world_x: Vector2 = player.position
	var clock: float = main.elapsed_time
	for frame: int in range(20):
		await physics_frame
	var frozen: bool = player.position == world_x and main.elapsed_time == clock
	var view: MeltView = director.view
	send_pointer(Vector2(400.0, 240.0), true, true)
	send_pointer(Vector2(400.0, 240.0), false, true)
	for frame: int in range(12):
		await physics_frame
	var moved: bool = view.round.elapsed > 0.0
	var at: Vector2 = view.pause_button.get_global_rect().get_center()
	send_pointer(at, true, true)
	send_pointer(at, false, true)
	var bonus_time: float = view.round.elapsed
	for frame: int in range(10):
		await physics_frame
	var pause_ok: bool = game_manager.state == GameManager.State.PAUSED and view.round.elapsed == bonus_time
	game_manager._on_resume_pressed()
	var resume_ok: bool = game_manager.state == GameManager.State.BONUS and paused
	game_manager._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	pause_ok = pause_ok and game_manager.state == GameManager.State.PAUSED
	game_manager._on_resume_pressed()
	view.round.finished = true
	view.round.elapsed = 31.0
	store.cosmetics.clear()
	var wallet: int = store.coin_wallet
	store.succeed = false
	director.settle_reward()
	var cosmetic: String = director.reward_roll[0]["cosmetic"]
	var rollback: bool = not director.reward_paid and store.coin_wallet == wallet and store.cosmetics.is_empty()
	store.succeed = true
	var writes: int = store.writes
	director.settle_reward()
	var paid: bool = director.reward_paid and store.coin_wallet == wallet + view.round.bonus_coins() \
		and store.cosmetics.get(cosmetic, false) and store.writes == writes + 1
	director.settle_reward()
	paid = paid and store.writes == writes + 1
	director._on_reward_requested()
	view._physics_process(2.1)
	var returned: bool = game_manager.state == GameManager.State.PLAYING and not paused \
		and not view.visible and player.position == world_x and main.elapsed_time == clock and player.jump_buffer_timer == 0.0
	expect("melt_lifecycle", schedule_ok and entered_ok and frozen and moved and pause_ok and resume_ok and rollback and paid and returned,
		"schedule/once=%s real portal=%s world frozen=%s plays=%s pause/focus=%s resume=%s rollback=%s once=%s return pose/clock=%s" % [
			schedule_ok, entered_ok, frozen, moved, pause_ok, resume_ok, rollback, paid, returned])


# Catch a visible snap at either foot's recovery boundary or cycle wrap, across all skins.
func rig_motion() -> void:
	var passed: bool = true
	var max_step: float = 0.0
	var max_ground_error: float = 0.0
	for skin: Dictionary in Skins.SKINS:
		for style: int in range(SkaterRig.STROKES.size()):
			var data: Dictionary = SkaterRig.create_draw_data(load(skin["frames"]), style)
			passed = passed and data["skin"] == skin["id"]
			for near: bool in [false, true]:
				var leg: Dictionary = data["near" if near else "rear"]
				var previous: Dictionary = SkaterRig.leg_pose(data, near, 0.0, 1.0)
				var min_sweep: float = INF
				var max_sweep: float = -INF
				var coast: Dictionary = SkaterRig.leg_pose(data, near, 0.0, 0.0)
				for frame: int in range(1, ceili(data["stroke"]["cycle"] * 120.0) + 2):
					var seconds: float = frame / 120.0
					var pose: Dictionary = SkaterRig.leg_pose(data, near, seconds, 1.0)
					for joint: String in ["hip", "knee", "ankle"]:
						passed = passed and (pose[joint] as Vector2).is_finite()
						max_step = maxf(max_step, pose[joint].distance_to(previous[joint]))
					passed = passed and absf(pose["hip"].distance_to(pose["knee"]) - leg["upper"]) < 0.001 \
						and absf(pose["knee"].distance_to(pose["ankle"]) - leg["lower"]) < 0.001
					min_sweep = minf(min_sweep, pose["ankle"].x - pose["hip"].x)
					max_sweep = maxf(max_sweep, pose["ankle"].x - pose["hip"].x)
					var phase: float = fposmod(seconds / data["stroke"]["cycle"] + (0.0 if near else 0.5), 1.0)
					var planted: bool = (phase < SkaterRig.DRIVE_END * 0.5 or phase >= SkaterRig.RETURN_END * 0.5) \
						if data["stroke"].get("phrased", false) else phase < 0.65
					if data["stroke"].get("gliding", false):
						planted = phase < SkaterRig.GLIDE_DRIVE_END * 0.5 or phase >= SkaterRig.GLIDE_RETURN_END * 0.5
					if planted and style > 0:
						max_ground_error = maxf(max_ground_error, absf(pose["ankle"].y - (SkaterRig.GROUND_Y - (13.0 if near else 9.4))))
					var still: Dictionary = SkaterRig.leg_pose(data, near, seconds, 0.0)
					passed = passed and still["ankle"].is_equal_approx(coast["ankle"])
					SkaterRig.skin_leg(data, near, pose)
					for vertex: Vector2 in leg["draw_vertices"]:
						passed = passed and vertex.is_finite() and vertex.length() < 200.0
					previous = pose
				if style > 0:
					passed = passed and max_sweep - min_sweep > 40.0
				for boundary: float in [0.0, 0.06, 0.14, 0.15, 0.18, 0.29, 0.31, 0.33, 0.47, 0.475, 0.5, 0.56, 0.64, 0.65, 0.68, 0.79, 0.81, 0.83, 0.97, 0.975, 1.0]:
					var before: Dictionary = SkaterRig.leg_pose(data, near, boundary * data["stroke"]["cycle"] - 0.00001, 1.0)
					var after: Dictionary = SkaterRig.leg_pose(data, near, boundary * data["stroke"]["cycle"] + 0.00001, 1.0)
					passed = passed and before["ankle"].distance_to(after["ankle"]) < 0.01 \
						and before["knee"].distance_to(after["knee"]) < 0.01
	expect("rig_motion", passed and max_step < 1.5 and max_ground_error < 0.75,
		"five skins/all styles; fixed bones, coast, full-cycle continuity, >40px strong sweep; max step %.3fpx, planted error %.3fpx" % [max_step, max_ground_error])
	# A quicker accelerating push, visible knee lift, and planting exactly into the
	# next push distinguish skating from equal-speed sliding or an airborne handoff.
	var data: Dictionary = SkaterRig.create_draw_data(load(Skins.SKINS[0]["frames"]))
	var rhythm: bool = true
	var half_cycle: float = SkaterRig.CYCLE_SECONDS * 0.5
	for near: bool in [true, false]:
		var start: float = 0.0 if near else half_cycle
		var early_a: Dictionary = SkaterRig.leg_pose(data, near, start + half_cycle * SkaterRig.GLIDE_DRIVE_END * 0.1, 1.0)
		var early_b: Dictionary = SkaterRig.leg_pose(data, near, start + half_cycle * SkaterRig.GLIDE_DRIVE_END * 0.2, 1.0)
		var fast_a: Dictionary = SkaterRig.leg_pose(data, near, start + half_cycle * SkaterRig.GLIDE_DRIVE_END * 0.55, 1.0)
		var fast_b: Dictionary = SkaterRig.leg_pose(data, near, start + half_cycle * SkaterRig.GLIDE_DRIVE_END * 0.65, 1.0)
		var early_distance: float = absf((early_b["ankle"].x - early_b["hip"].x) - (early_a["ankle"].x - early_a["hip"].x))
		var fast_distance: float = absf((fast_b["ankle"].x - fast_b["hip"].x) - (fast_a["ankle"].x - fast_a["hip"].x))
		rhythm = rhythm and fast_distance > early_distance * 3.0
		var planted: Dictionary = SkaterRig.leg_pose(data, near, start + half_cycle, 1.0)
		var sole: float = SkaterRig.GROUND_Y - (13.0 if near else 9.4)
		var highest_knee: float = INF
		var max_lift: float = 0.0
		for frame: int in range(1, 101):
			var phase: float = lerpf(SkaterRig.GLIDE_DRIVE_END, 1.0, frame / 100.0)
			var recovery: Dictionary = SkaterRig.leg_pose(data, near, start + half_cycle * phase, 1.0)
			highest_knee = minf(highest_knee, recovery["knee"].y - recovery["hip"].y)
			max_lift = maxf(max_lift, sole - recovery["ankle"].y)
		rhythm = rhythm and highest_knee < planted["knee"].y - planted["hip"].y - 3.0 \
			and max_lift > 10.0 and max_lift < 13.0
		var seconds: float = start + half_cycle
		var incoming: Dictionary = SkaterRig.leg_pose(data, not near, seconds, 1.0)
		var incoming_next: Dictionary = SkaterRig.leg_pose(data, not near, seconds + 1.0 / 60.0, 1.0)
		rhythm = rhythm and absf(planted["ankle"].y - sole) < 0.001 \
			and is_equal_approx(planted["ankle"].x - planted["hip"].x, data["stroke"]["forward"]) \
			and incoming_next["ankle"].x - incoming_next["hip"].x < incoming["ankle"].x - incoming["hip"].x
	var quiet_frames: int = 0
	var longest_quiet: int = 0
	var push_speed: float = 0.0
	var return_speed: float = 0.0
	for frame: int in range(ceili(SkaterRig.CYCLE_SECONDS * 120.0)):
		var combined_speed: float = 0.0
		for near: bool in [true, false]:
			var before: Dictionary = SkaterRig.leg_pose(data, near, frame / 120.0, 1.0)
			var after: Dictionary = SkaterRig.leg_pose(data, near, (frame + 1) / 120.0, 1.0)
			var speed: float = absf((after["ankle"].x - after["hip"].x) - (before["ankle"].x - before["hip"].x)) * 120.0
			combined_speed += speed
			var phrase: float = fposmod(frame / 120.0 / SkaterRig.CYCLE_SECONDS + (0.0 if near else 0.5), 1.0) * 2.0
			if phrase < SkaterRig.GLIDE_DRIVE_END:
				push_speed = maxf(push_speed, speed)
			elif phrase < 1.0:
				return_speed = maxf(return_speed, speed)
		quiet_frames = quiet_frames + 1 if combined_speed < 2.0 else 0
		longest_quiet = maxi(longest_quiet, quiet_frames)
	expect("rig_rhythm", rhythm and push_speed > return_speed * 2.0 and longest_quiet <= 4,
		"accelerating push %.1fpx/s vs recovery %.1f; modest knee lift; planted next-push handoff; longest quiet span %d/120s" % [push_speed, return_speed, longest_quiet])


func rig_lifecycle() -> void:
	await new_scene()
	game_manager.set_state(GameManager.State.PAUSED)
	var rig: SkaterRig = player.animated_sprite.get_node("SkaterRig") as SkaterRig
	var passed: bool = rig != null and not rig.data.is_empty() and rig.use_parent_material 		and player.animated_sprite.self_modulate.a == 0.0
	var clock: float = rig.elapsed
	for frame: int in range(4):
		await process_frame
	passed = passed and rig.elapsed == clock
	for skin: Dictionary in Skins.SKINS:
		store.upgrade_levels[Skins.get_track_id(skin["id"])] = 1
		store.selected_skin = skin["id"]
		game_manager.apply_skin()
		passed = passed and rig.data["skin"] == skin["id"]
	var pose: Vector2 = player.position
	var velocity: Vector2 = player.velocity
	var sprite_transform: Transform2D = player.animated_sprite.transform
	rig.stride_amount = 1.0
	player.is_jump_suppressed = true
	rig._process(0.1)
	passed = passed and rig.stride_amount < 1.0 and player.position == pose and player.velocity == velocity 		and player.animated_sprite.transform == sprite_transform
	player.is_jump_suppressed = false
	game_manager.set_state(GameManager.State.PLAYING)
	for frame: int in range(4):
		await process_frame
	passed = passed and rig.elapsed > clock
	game_manager.set_state(GameManager.State.PAUSED)
	store.selected_skin = Skins.DEFAULT_ID
	game_manager.apply_skin()
	expect("rig_lifecycle", passed, "real player rig; pause freezes, all skin swaps, smooth coast, physics/transform unchanged")
