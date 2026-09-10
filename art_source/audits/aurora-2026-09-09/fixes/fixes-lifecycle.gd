extends SceneTree
var failures: int = 0
var checks: int = 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)
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
	BiomeDirector.session_cycle_rotation = 0
	b.biome_phase_offset = 450000.0 - b.player.global_position.x
	b.apply_palette_for_world_x(450000.0)
	d._physics_process(1.0/60.0)
	expect(s.next_aurora_due_seconds == 1800.0,"reset UI schedules without reload")
	main.elapsed_time = 1800.0
	expect(d.is_aurora_due() and d.is_sky_ready(),"reset event due in full night")
	gm.set_state(GameManager.State.PAUSED)
	for kind: int in range(3):
		s.aurora_count = 0
		s.next_aurora_due_seconds = -1.0
		d.debug_aurora_interval_override = 10.0 if kind == 0 else 0.0
		d.debug_aurora_ignore_night = kind == 1
		b.debug_biome_seconds = 10.0 if kind == 2 else 0.0
		d.schedule_if_unscheduled()
		expect(s.next_aurora_due_seconds == -1.0,"preview does not initialize deadline")
		d.begin_aurora()
		d.debug_aurora_interval_override = 0.0
		d.debug_aurora_ignore_night = false
		b.debug_biome_seconds = 0.0
		d.finish_aurora()
		expect(s.aurora_count == 0 and s.next_aurora_due_seconds == -1.0,"preview latch prevents completion write")
	s.total_playtime_seconds = 36000.0
	main.elapsed_time = 2400.0
	gm.banked_run_seconds = 0.0
	d.begin_aurora()
	d.finish_aurora()
	var reloaded := SaveStore.new()
	reloaded.load_from_disk()
	expect(reloaded.total_playtime_seconds == 38400.0,"completion banks clock in snapshot")
	expect(reloaded.next_aurora_due_seconds == 40200.0,"completion deadline snapshot")
	expect(reloaded.aurora_count == 1,"completion counted once")
	expect(gm.banked_run_seconds == 2400.0 and not gm.bank_playtime(),"no double banking after completion")
	d.finish_aurora()
	expect(s.aurora_count == 1,"repeat completion idempotent")
	d.begin_aurora()
	d.active_elapsed = 20.0
	d.push_blend(1.0)
	await create_timer(0.1,true).timeout
	expect(d.active_elapsed == 20.0,"pause freezes event")
	d._on_player_died()
	for band: TextureRect in main.get_node("SkyBackdrop").aurora_bands:
		expect(not band.visible,"death hides curtain")
	# Verify prediction against actual applied palettes throughout the admitted span,
	# across all rotations, including transitions and the one-shot opening biome.
	for rotation: int in range(8):
		BiomeDirector.session_cycle_rotation = rotation
		for start_x: float in [0.0, 50000.0, 450000.0, 510000.0, 570000.0, 582000.0, 590000.0]:
			b.biome_phase_offset = start_x - b.player.global_position.x
			var predicted: float = b.get_minimum_night_ahead(61.0,1000.0)
			var actual_min: float = 1.0
			for second: int in range(62):
				b.apply_palette_for_world_x(start_x+second*1000.0)
				actual_min = minf(actual_min,b.get_night_amount())
			expect(predicted <= actual_min + 0.00001,"night prediction bounds actual palette sweep")
	BiomeDirector.session_cycle_rotation = 0
	b.biome_phase_offset = 582000.0 - b.player.global_position.x
	b.apply_palette_for_world_x(582000.0)
	expect(not d.is_sky_ready(),"late night rejected")
	b.biome_phase_offset = 450000.0 - b.player.global_position.x
	b.apply_palette_for_world_x(450000.0)
	expect(d.is_sky_ready(),"full night admitted")
	b.debug_biome_seconds = 10.0
	b.debug_biome_elapsed = 60.0
	expect(b.get_minimum_night_ahead(61.0,1000.0) < 0.8,"accelerated intervening daytime detected")
	print("AURORA_LIFECYCLE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
