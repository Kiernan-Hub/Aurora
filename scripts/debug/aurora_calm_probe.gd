extends SceneTree

# Geometry proof plus explicitly enabled live lifecycle cases. Geometry traversals
# detach Services; integration cases inject an in-memory SaveStore. Never use a real
# save for lifecycle tests. Obstacles/powerups stay ON in the integration cases.
# Camera/flight are not yet implemented or covered here.
# godot --headless --fixed-fps 60 --path . --script res://scripts/debug/aurora_calm_probe.gd
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEEDS: Array[int] = [941462462, 2160065702, 3188032853, 222894852, 12345, 987654321, 1, 683407368]
const EVENT_SECONDS: float = 61.0
const MARGIN: float = 4096.0
const LENGTH: float = EVENT_SECONDS * PowerupManager.SPEED_BOOST_SPEED + MARGIN * 2.0
const MAX_FRAMES: int = 7000
var failures: Array[String] = []
var assertions: int = 0


class MemorySaveStore extends SaveStore:
	var writes: int = 0
	var saved_achievements: Dictionary[String, bool] = {}
	func save_to_disk() -> void:
		writes += 1
		saved_achievements = achievements.duplicate()


func _init() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition and failures.size() < 30:
		failures.append(message)


func make_terrain(seed_value: int) -> TerrainGenerator:
	var terrain: TerrainGenerator = TerrainGenerator.new()
	terrain.session_seed = seed_value
	terrain.segment_selection_weight_table = terrain.build_segment_selection_weight_table()
	terrain.initialize_segment_cache()
	return terrain


func run() -> void:
	if not "--integration-only" in OS.get_cmdline_user_args():
		for seed_value: int in SEEDS:
			check_geometry(seed_value)
		for seed_value: int in [941462462, 2160065702]:
			await check_traversal(seed_value, false)
			await check_traversal(seed_value, true)
		if DisplayServer.get_name() == "headless":
			await check_headless_death_isolation()
	await check_entry_failures()
	await check_live_encounter(true)
	await check_live_encounter(false)
	for failure: String in failures:
		print("  ", failure)
	print("AURORA_CALM_CHECK ", "PASS" if failures.is_empty() else "FAIL",
		" assertions=", assertions, " integration_cases=2")
	quit(0 if failures.is_empty() else 1)


func check_headless_death_isolation() -> void:
	var main: Main = MAIN_SCENE.instantiate() as Main
	main.get_node("Player").DEBUG_LOG_FREEZE_REPRO = false
	root.add_child(main)
	var manager: GameManager = main.get_node("GameManager")
	var memory_services: GameServices = GameServices.new()
	var memory_save: MemorySaveStore = MemorySaveStore.new()
	memory_save.coin_wallet = 123
	memory_services.save_store = memory_save
	manager.services = memory_services
	manager.coin_count = 50
	manager._on_player_died()
	expect(memory_save.writes == 0 and memory_save.coin_wallet == 123,
		"Headless death wrote or mutated saved progression")
	main.queue_free()
	await process_frame
	memory_services.free()


func check_geometry(seed_value: int) -> void:
	var terrain: TerrainGenerator = make_terrain(seed_value)
	for invalid: float in [0.0, -1.0, 479.0, INF, -INF, NAN]:
		expect(not terrain.arm_aurora_flat(invalid), "Invalid length accepted")
		expect(terrain.aurora_segment_index == -1 and terrain.aurora_segment_length == 0.0,
			"Rejected arm mutated reservation")
	terrain.ensure_segment_cache_for_world_x(120000.0)
	var old_end: float = terrain.get_cached_segment_end_x(terrain.highest_cached_segment_index)
	var heights: Array[float] = []
	for sample: int in range(4000):
		heights.append(terrain.get_terrain_height(old_end * float(sample) / 4000.0))
	# Spec-only readers may get far ahead without advancing the contiguous watermark.
	var sparse_index: int = terrain.highest_cached_segment_index + 30
	terrain.get_segment_spec(sparse_index)
	var specs: Dictionary = terrain.segment_spec_cache.duplicate(true)
	expect(terrain.arm_aurora_flat(LENGTH), "Reservation rejected seed=%d" % seed_value)
	var reserved_index: int = terrain.aurora_segment_index
	expect(reserved_index > sparse_index, "Reservation overwrote a sparse spec")
	for index: int in specs:
		expect(terrain.get_segment_spec(index) == specs[index], "Cached spec changed index=%d" % index)
	for sample: int in range(4000):
		expect(terrain.get_terrain_height(old_end * float(sample) / 4000.0) == heights[sample],
			"Previously sampled height changed seed=%d" % seed_value)
	var start: float = terrain.get_aurora_flat_start_x()
	var end: float = terrain.get_aurora_flat_end_x()
	var height: float = terrain.get_terrain_height(start)
	expect(end - start == LENGTH, "Wrong reserved length")
	expect(not terrain.is_aurora_flat_world_x(start - 0.01) and terrain.is_aurora_flat_world_x(start)
		and terrain.is_aurora_flat_world_x(end - 0.01) and not terrain.is_aurora_flat_world_x(end), "Wrong span boundaries")
	for x: float in range(int(start), int(end), 17):
		if x < start:
			continue
		expect(terrain.get_terrain_height(x) == height, "Reserved ground is not flat")
		expect(terrain.has_ground_at_world_x(x), "Void inside reserved flat")
	for edge: float in [start, end]:
		expect(absf(terrain.get_terrain_height(edge - 0.01) - terrain.get_terrain_height(edge + 0.01)) < 0.01,
			"Discontinuous flat seam")
	for index: int in range(reserved_index - 1, reserved_index + 2):
		expect(not terrain.is_chasm_segment_index(index), "Chasm at reserved segment or neighbour")
	expect(not terrain.arm_aurora_flat(LENGTH * 2.0), "Second arm accepted")
	expect(terrain.aurora_segment_index == reserved_index and terrain.aurora_segment_length == LENGTH,
		"Second arm changed reservation")
	expect(terrain.arm_lake(), "Later lake geometry failed to reserve")
	expect(terrain.get_lake_start_x() > end, "Later lake overlaps Aurora geometry")
	# Rebuilding spec caches must retain the same reserved geometry after a sighting.
	terrain.initialize_segment_cache()
	expect(terrain.get_aurora_flat_start_x() == start and terrain.get_aurora_flat_end_x() == end,
		"Cache rebuild changed reserved bounds")
	expect(terrain.get_terrain_height(start + LENGTH * 0.5) == height, "Cache rebuild changed flat height")
	terrain.free()
	var lake_first: TerrainGenerator = make_terrain(seed_value)
	expect(lake_first.arm_lake(), "Control lake failed to arm")
	var lake_end: float = lake_first.get_lake_end_x()
	expect(lake_first.arm_aurora_flat(LENGTH), "Later Aurora geometry failed to reserve")
	expect(lake_first.get_aurora_flat_start_x() > lake_end, "Later Aurora overlaps lake geometry")
	lake_first.free()


func check_traversal(seed_value: int, boosted: bool) -> void:
	var main: Main = MAIN_SCENE.instantiate() as Main
	var terrain: TerrainGenerator = main.get_node("TerrainGenerator")
	var player: Player = main.get_node("Player")
	var manager: GameManager = main.get_node("GameManager")
	terrain.debug_replay_session_seed = seed_value
	# Keep chasms enabled: direct checks and an ordinary traversal must expose a void.
	main.get_node("TerrainGenerator/ObstacleSpawner").debug_spawning_disabled = true
	main.get_node("TerrainGenerator/PowerupSpawner").debug_spawning_disabled = true
	player.DEBUG_LOG_FREEZE_REPRO = false
	player.DEBUG_SHOW_PLAYER_STATE = false
	manager.require_start_screen = false
	root.add_child(main)
	# The autoload node can exist under --headless --script. Null it out here rather
	# than trusting headless guards on every future death/coin path in GameManager.
	manager.services = null
	await physics_frame
	# Reserve deep into an ordinary run so the warp exercises real Y rebasing too.
	terrain.ensure_segment_cache_for_world_x(120000.0)
	expect(terrain.arm_aurora_flat(LENGTH), "Traversal reservation failed")
	var start: float = terrain.get_aurora_flat_start_x()
	var end: float = terrain.get_aurora_flat_end_x()
	# Cross both seams on real generated collision, not just sample the flat's centre.
	var entry_x: float = start - 128.0
	player.speed_manager.elapsed_time = 130.0
	player.speed_manager.current_speed = SpeedManager.MAX_SPEED
	player.global_position = Vector2(entry_x, terrain.get_surface_world_y(entry_x) - player.capsule_half_height)
	player.velocity = Vector2.ZERO
	if boosted:
		player.start_boost(PowerupManager.SPEED_BOOST_SPEED)
	for index: int in terrain.active_chunks.keys():
		terrain.remove_chunk(index)
	# Let queued old collision bodies leave before creating their replacements.
	await process_frame
	terrain.initialize_chunks()
	var frames: int = 0
	var event_frames: int = 0
	var event_entered: bool = false
	var coverage_checked: bool = false
	var peak_chunks: int = 0
	while frames < MAX_FRAMES and not player.is_dead and player.global_position.x < end + 128.0:
		await physics_frame
		frames += 1
		peak_chunks = maxi(peak_chunks, terrain.active_chunks.size())
		if not event_entered and player.global_position.x >= start + MARGIN:
			event_entered = true
		if event_entered:
			event_frames += 1
		if event_frames == int(EVENT_SECONDS * 60.0):
			coverage_checked = true
			expect(end - player.global_position.x >= MARGIN - 20.0, "Insufficient margin after 61 seconds")
		if player.global_position.x > start + 64.0 and player.global_position.x < end - 64.0:
			expect(terrain.has_ground_at_world_x(player.global_position.x), "Traversal crossed a void")
			expect(absf(player.global_position.y + player.capsule_half_height
				- terrain.get_surface_world_y(player.global_position.x)) < 4.0, "Player lost flat contact")
	expect(not player.is_dead and player.global_position.x >= end + 128.0, "Traversal failed to cross both seams")
	expect(coverage_checked, "Traversal never proved full event duration")
	expect(main.total_world_rebase_shift != 0.0, "Deep traversal did not exercise world rebasing")
	expect(peak_chunks <= terrain.chunk_count_ahead + terrain.chunk_count_behind + 2,
		"Long flat allocated more than the normal chunk window")
	expect(player.debug_stall_recovery_count == 0 and player.debug_stuck_event_count == 0, "Traversal needed watchdog recovery")
	expect(not player.has_shield and (boosted or not player.is_boosting), "Ordinary traversal acquired protection")
	print("AURORA_FLAT_TRAVERSAL seed=", seed_value, " boosted=", boosted, " frames=", frames)
	main.queue_free()
	await process_frame


class ControlledNight extends BiomeDirector:
	var night_ready: bool = true
	func get_night_amount() -> float:
		return 1.0 if night_ready else 0.0
	func get_minimum_night_ahead(_seconds: float, _speed: float) -> float:
		return get_night_amount()


func make_case(preview: bool) -> Dictionary:
	var main: Main = MAIN_SCENE.instantiate() as Main
	main.get_node("Player").DEBUG_LOG_FREEZE_REPRO = false
	main.get_node("Player").DEBUG_SHOW_PLAYER_STATE = false
	main.get_node("TerrainGenerator").debug_replay_session_seed = 941462462
	main.get_node("GameManager").require_start_screen = false
	root.add_child(main)
	var director: AuroraDirector = main.get_node("AuroraDirector")
	director.set_physics_process(false)
	expect(director.resolve_dependencies(), "Integration dependencies missing")
	var memory_services: GameServices = GameServices.new()
	var save: MemorySaveStore = MemorySaveStore.new()
	save.total_playtime_seconds = 36000.0
	save.next_aurora_due_seconds = 77.0 if preview else 0.0
	memory_services.save_store = save
	director.services = memory_services
	main.game_manager.services = memory_services
	var achievements: AchievementManager = main.get_node("AchievementManager") as AchievementManager
	# _ready() connected the triggers already; replace only the persistence target before this
	# headless probe deliberately drives completion signals.
	achievements.services = memory_services
	var night: ControlledNight = ControlledNight.new()
	night.debug_biome_seconds = 0.0
	director.biome_director = night
	director.debug_aurora_interval_override = 10.0 if preview else 0.0
	director.debug_aurora_ignore_night = preview
	main.elapsed_time = 130.0
	# Lake normally hard-skips headless; resolve it for direct arbitration assertions.
	director.lake.player = director.player
	director.lake.terrain_generator = director.terrain
	director.lake.main_node = main
	director.lake.services = memory_services
	director.lake.set_physics_process(false)
	if not director.player.died.is_connected(director._on_player_died):
		director.player.died.connect(director._on_player_died)
	return {"main": main, "director": director, "night": night, "services": memory_services,
		"save": save, "achievements": achievements}


func close_case(context: Dictionary) -> void:
	(context["director"] as AuroraDirector).set_physics_process(false)
	(context["main"] as Main).queue_free()
	await process_frame
	(context["night"] as ControlledNight).free()
	(context["services"] as GameServices).free()


func warp_case(context: Dictionary, world_x: float) -> void:
	var director: AuroraDirector = context["director"]
	var terrain: TerrainGenerator = director.terrain
	var player: Player = director.player
	(context["main"] as Main).game_manager.set_state(GameManager.State.PLAYING)
	player.speed_manager.elapsed_time = 130.0
	player.speed_manager.current_speed = SpeedManager.MAX_SPEED
	player.global_position = Vector2(world_x, terrain.get_surface_world_y(world_x) - player.capsule_half_height)
	player.velocity = Vector2.ZERO
	for index: int in terrain.active_chunks.keys():
		terrain.remove_chunk(index)
	await process_frame
	terrain.initialize_chunks()
	for frame: int in range(4):
		await physics_frame
		resume_external_pause(context)


func resume_external_pause(context: Dictionary) -> void:
	# Desktop focus loss legitimately pauses gameplay while the harness keeps getting
	# physics_frame signals. Resume through the real state owner during traversal;
	# never call this inside the explicit pause assertion below.
	var manager: GameManager = (context["main"] as Main).game_manager
	if manager.state == GameManager.State.PAUSED:
		print("AURORA_PROBE resuming external focus pause")
		manager.set_state(GameManager.State.PLAYING)


func check_entry_failures() -> void:
	var context: Dictionary = make_case(false)
	var director: AuroraDirector = context["director"]
	var night: ControlledNight = context["night"]
	# Simultaneous eligibility gives Aurora priority without relying on node order.
	expect(director.blocks_lake_arming(), "Due night Aurora does not claim priority")
	director.lake.try_arm()
	expect(director.terrain.lake_segment_index == -1, "Lake stole simultaneous due slot")
	director.lake.phase = FrozenLakeDirector.Phase.ARMED
	expect(not director.try_reserve(), "Aurora reserved during armed lake")
	director.lake.phase = FrozenLakeDirector.Phase.ACTIVE
	expect(not director.try_reserve(), "Aurora reserved during active lake")
	director.lake.phase = FrozenLakeDirector.Phase.DONE
	night.night_ready = false
	expect(not director.wants_reservation(), "Daytime reserves Aurora")
	night.night_ready = true
	expect(director.try_reserve(), "Failed to reserve after lake completion")
	await warp_case(context, director.flat_start_x + director.recovery_distance + 64.0)
	night.night_ready = false
	director._physics_process(1.0 / 60.0)
	expect(director.phase == AuroraDirector.Phase.RECOVERY and director.get_aurora_blend() == 0.0,
		"Late-night entry did not abandon appearance")
	expect((context["save"] as MemorySaveStore).aurora_count == 0, "Failed entry earned credit")
	await close_case(context)

	context = make_case(false)
	director = context["director"]
	expect(director.try_reserve(), "Late-entry setup failed")
	await warp_case(context, director.flat_end_x - 1000.0)
	director._physics_process(1.0 / 60.0)
	expect(director.phase == AuroraDirector.Phase.RECOVERY, "Too-short remaining passage started event")
	await close_case(context)

	context = make_case(false)
	director = context["director"]
	expect(director.try_reserve(), "Conflict setup failed")
	await warp_case(context, director.flat_start_x + director.recovery_distance + 64.0)
	# Deliberately bypass the spawner guard to prove entry inspects actual bodies.
	var obstacle: Obstacle = ObstacleSpawner.OBSTACLE_SCENE.instantiate() as Obstacle
	obstacle.position.x = director.player.global_position.x + 500.0
	director.obstacle_spawner.add_child(obstacle)
	director._physics_process(1.0 / 60.0)
	expect(director.phase == AuroraDirector.Phase.RECOVERY, "Existing obstacle was ignored at entry")
	await close_case(context)

	# Death during pending or active must leave the due deadline and count untouched.
	for active: bool in [false, true]:
		context = make_case(false)
		director = context["director"]
		expect(director.try_reserve(), "Death setup failed")
		if active:
			await warp_case(context, director.flat_start_x + director.recovery_distance + 64.0)
			director.begin_aurora()
			expect(director.phase == AuroraDirector.Phase.ACTIVE, "Active death setup never entered")
			director.finish_aurora()
			expect(director.phase == AuroraDirector.Phase.ACTIVE, "Early finish credited a partial event")
		director._on_player_died()
		expect(director.phase == AuroraDirector.Phase.DONE and director.get_aurora_blend() == 0.0,
			"Death left active Aurora presentation")
		expect((context["save"] as MemorySaveStore).aurora_count == 0 \
			and (context["save"] as MemorySaveStore).next_aurora_due_seconds == 0.0, "Death changed due progress")
		expect(not (context["save"] as MemorySaveStore).achievements.get(
			AchievementManager.UNDER_THE_AURORA, false), "Partial/dead encounter awarded achievement")
		await close_case(context)


func check_live_encounter(preview: bool) -> void:
	var context: Dictionary = make_case(preview)
	var main: Main = context["main"]
	var director: AuroraDirector = context["director"]
	var terrain: TerrainGenerator = director.terrain
	var save: MemorySaveStore = context["save"]
	var achievements: AchievementManager = context["achievements"]
	var counts: Array[int] = [0, 0]
	var achievement_grants: Array[int] = [0]
	director.aurora_started.connect(func() -> void: counts[0] += 1)
	director.aurora_finished.connect(func(_total: int) -> void: counts[1] += 1)
	achievements.achievement_granted.connect(func(id: String, _name: String) -> void:
		if id == AchievementManager.UNDER_THE_AURORA:
			achievement_grants[0] += 1)
	# Real existing nodes, far beyond ordinary spawn lookahead, must push entry ahead.
	director.obstacle_spawner.spawn_obstacle(20000.0)
	var old_obstacle: Node2D = director.obstacle_spawner.active_obstacles.back()
	old_obstacle.scale = Vector2(3.0, 3.0)
	for row: Dictionary in PowerupSpawner.POWERUP_TABLE:
		if row["effect"] == PowerupManager.EFFECT_GLIDE:
			director.powerup_spawner.spawn_powerup(row["scene"], 22000.0, row["effect"])
	var old_edge: float = maxf(director.get_furthest_body_edge(director.obstacle_spawner),
		director.get_furthest_body_edge(director.powerup_spawner))
	director._physics_process(1.0 / 60.0)
	expect(director.phase == AuroraDirector.Phase.PENDING_ENTRY, "Due Aurora did not reserve")
	expect(director.flat_start_x > old_edge + AuroraDirector.BODY_CLEARANCE,
		"Flat starts before existing collision extent")
	expect(is_instance_valid(old_obstacle) and old_obstacle.visible, "Reservation removed visible obstacle")
	# Both seam-overlapping obstacles and movement pickups are excluded by final placers.
	var old_count: int = director.obstacle_spawner.active_obstacles.size()
	for x: float in [director.flat_start_x - 8.0, director.flat_start_x + 500.0, director.flat_end_x + 8.0]:
		director.obstacle_spawner.spawn_obstacle(x)
	expect(director.obstacle_spawner.active_obstacles.size() == old_count, "Obstacle body overlaps flat seam")
	for row: Dictionary in PowerupSpawner.POWERUP_TABLE:
		var before: int = director.powerup_spawner.active_powerups.size()
		director.powerup_spawner.spawn_powerup(row["scene"], director.flat_start_x + 500.0, row["effect"])
		var expected: int = before if PowerupManager.is_aurora_excluded_effect(row["effect"]) else before + 1
		expect(director.powerup_spawner.active_powerups.size() == expected, "Powerup admission mismatch")
	# Grant an existing effect BEFORE entry. It must expire normally, not be confiscated.
	var held_effect: StringName = PowerupManager.EFFECT_GLIDE if preview else PowerupManager.EFFECT_SPEED_BOOST
	director.powerups.start_effect(held_effect)
	await warp_case(context, director.flat_start_x + director.recovery_distance + 64.0)
	director._physics_process(1.0 / 60.0)
	expect(director.phase == AuroraDirector.Phase.PENDING_ENTRY and director.powerups.is_effect_active(held_effect),
		"Existing effect was cancelled or admitted into active Aurora")
	if preview:
		# Turning preview off while waiting cannot turn this reservation into progression.
		director.debug_aurora_interval_override = 0.0
		director.debug_aurora_ignore_night = false
	director.set_physics_process(true)
	var frames: int = 0
	while frames < 900 and director.phase == AuroraDirector.Phase.PENDING_ENTRY and not director.player.is_dead:
		await physics_frame
		resume_external_pause(context)
		frames += 1
	expect(director.phase == AuroraDirector.Phase.ACTIVE, "Safe grounded entry never started")
	expect(counts[0] == 1 and not director.player.is_boosting and not director.player.is_glide_active,
		"Active event has movement powerup or repeated start")
	var frozen_time: float = director.active_elapsed
	main.game_manager.set_state(GameManager.State.PAUSED)
	for frame: int in range(10):
		await physics_frame
	expect(director.active_elapsed == frozen_time, "Aurora timer advanced while paused")
	main.game_manager.set_state(GameManager.State.PLAYING)
	# Direct grants and the real trick reward path obey the same admission guard.
	director.powerups.start_effect(PowerupManager.EFFECT_SPEED_BOOST)
	director.powerups.start_effect(PowerupManager.EFFECT_GLIDE)
	var coins_before: int = main.game_manager.coin_count
	main.game_manager._on_player_trick_completed(1)
	expect(not director.player.is_boosting and not director.player.is_glide_active, "Movement powerup bypassed flat exclusion")
	expect(main.game_manager.coin_count > coins_before, "Trick coin reward was removed")
	# Keyboard and buffered (touch consumer) jumps are still allowed on the flat.
	director.player.buffer_jump()
	for frame: int in range(5):
		await physics_frame
	expect(not director.player.is_on_floor(), "Aurora suppressed normal jump input")
	frames = 0
	while frames < 4000 and director.phase == AuroraDirector.Phase.ACTIVE and not director.player.is_dead:
		await physics_frame
		resume_external_pause(context)
		frames += 1
		expect(not director.has_existing_conflict(), "Live spawner placed a hazard/movement pickup during Aurora")
		expect(not director.player.is_boosting and not director.player.is_glide_active, "Live movement effect escaped exclusion")
	expect(director.phase == AuroraDirector.Phase.RECOVERY and not director.player.is_dead, "Live encounter did not finish safely")
	print("AURORA_LIVE_FINISH preview=", preview, " phase=", director.phase, " dead=", director.player.is_dead,
		" elapsed=", director.active_elapsed, " frames=", frames, " x=", director.player.global_position.x,
		" end=", director.flat_end_x, " speed=", director.player.speed_manager.current_speed)
	expect(director.flat_end_x - director.player.global_position.x >= director.recovery_distance,
		"Encounter ran past recovery margin")
	expect(main.game_manager.coin_count > coins_before + main.game_manager.TRICK_COIN_REWARD, "Coins did not keep spawning/collecting")
	expect(save.aurora_count == (0 if preview else 1) and counts[1] == (0 if preview else 1), "Completion credit mismatch")
	expect(bool(save.achievements.get(AchievementManager.UNDER_THE_AURORA, false)) == not preview,
		"Preview/completion achievement mismatch")
	expect(achievement_grants[0] == (0 if preview else 1), "Achievement grant signal mismatch")
	if preview:
		expect(save.next_aurora_due_seconds == 77.0, "Preview advanced deadline")
	else:
		expect(save.saved_achievements.get(AchievementManager.UNDER_THE_AURORA, false),
			"Completed Aurora achievement was absent from the saved snapshot")
		expect(absf(save.next_aurora_due_seconds - director.get_total_playtime_seconds() - 1800.0) < 0.1,
			"Completion deadline used the wrong clock")
		if DisplayServer.get_name() != "headless":
			expect(absf(save.total_playtime_seconds - director.get_total_playtime_seconds()) < 0.1,
				"Native completion did not bank the clock before saving")
	director.finish_aurora()
	expect(save.aurora_count == (0 if preview else 1), "Repeated finish double-credited")
	expect(achievement_grants[0] == (0 if preview else 1), "Repeated finish re-granted achievement")
	expect(director.blocks_lake_arming(), "Lake enters during recovery")
	# Exit far enough to restore normal admission and release scheduling arbitration.
	director.set_physics_process(false)
	await warp_case(context, director.flat_end_x + 512.0)
	director._physics_process(1.0 / 60.0)
	print("AURORA_LIVE_EXIT preview=", preview, " phase=", director.phase, " dead=", director.player.is_dead,
		" x=", director.player.global_position.x, " end=", director.flat_end_x, " floor=", director.player.is_on_floor())
	expect(director.phase == AuroraDirector.Phase.DONE and not director.blocks_lake_arming(), "Recovery did not release lake")
	director.powerups.start_effect(PowerupManager.EFFECT_SPEED_BOOST)
	expect(director.player.is_boosting, "Boost did not restore after flat")
	director.powerups.end_effect(PowerupManager.EFFECT_SPEED_BOOST)
	var before_exit_obstacles: int = director.obstacle_spawner.active_obstacles.size()
	director.obstacle_spawner.spawn_obstacle(director.flat_end_x + 1024.0)
	expect(director.obstacle_spawner.active_obstacles.size() == before_exit_obstacles + 1, "Obstacles did not resume")
	director.lake.try_arm()
	expect(director.lake.phase == FrozenLakeDirector.Phase.ARMED and terrain.get_lake_start_x() > director.flat_end_x,
		"Deferred lake did not arm after recovery")
	print("AURORA_LIVE_CASE preview=", preview, " starts=", counts[0], " completions=", counts[1], " PASS_IF_NO_FAILURES_ABOVE")
	await close_case(context)
