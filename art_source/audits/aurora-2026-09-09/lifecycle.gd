extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.get_node("TerrainGenerator").debug_replay_session_seed = 1
	main.get_node("TerrainGenerator").debug_chasm_disabled = true
	main.get_node("TerrainGenerator/ObstacleSpawner").debug_spawning_disabled = true
	main.get_node("TerrainGenerator/PowerupSpawner").debug_spawning_disabled = true
	root.add_child(main)
	var gm: GameManager = main.get_node("GameManager")
	var d: AuroraDirector = main.get_node("AuroraDirector")
	var b: BiomeDirector = main.get_node("BiomeDirector")
	var s: SaveStore = gm.services.save_store
	gm._on_start_shop_pressed()
	gm._on_reset_progress_confirmed()
	gm._on_shop_close_pressed()
	gm._on_start_pressed()
	b.set_process(false)
	b.blended.star_density = 1.0
	main.elapsed_time = 1900.0
	print("RESET_UI_REPRO state=",gm.state," deadline=",s.next_aurora_due_seconds," elapsed=",main.elapsed_time," due=",d.is_aurora_due())
	main.elapsed_time = 0.0
	d.begin_aurora()
	d.active_elapsed = 20.0
	d.push_blend(d.get_aurora_blend())
	gm.set_state(GameManager.State.PAUSED)
	var elapsed_before: float = d.active_elapsed
	await create_timer(0.25,true).timeout
	print("PAUSE elapsed_before=",elapsed_before," elapsed_after=",d.active_elapsed)
	d._on_player_died()
	var showing: int = 0
	for band: TextureRect in main.get_node("SkyBackdrop").aurora_bands:
		if band.visible: showing += 1
	print("DEATH phase=",d.phase," bands_showing=",showing," count=",s.aurora_count)
	# Simulate a persisted completion followed by reload before playtime is banked.
	s.total_playtime_seconds = 36000.0
	main.elapsed_time = 2400.0
	gm.banked_run_seconds = 0.0
	d.begin_aurora()
	d.finish_aurora()
	var reloaded := SaveStore.new()
	reloaded.load_from_disk()
	print("COMPLETION_RELOAD saved_clock=",reloaded.total_playtime_seconds," saved_deadline=",reloaded.next_aurora_due_seconds," seconds_until_next=",reloaded.next_aurora_due_seconds-reloaded.total_playtime_seconds)
	quit()
