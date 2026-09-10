extends SceneTree

var checks: int = 0
var failed: int = 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("FAIL ", label)

func _init() -> void:
	var svc := GameServices.new()
	var main := Main.new()
	var gm := GameManager.new()
	gm.main = main
	gm.services = svc
	main.game_manager = gm
	var d := AuroraDirector.new()
	d.services = svc
	d.main_node = main
	d.debug_aurora_interval_override = 0.0
	var b := BiomeDirector.new()
	b.channel_weights.resize(BiomePalette.CHANNEL_COUNT)
	BiomeDirector.session_cycle_rotation = 0
	BiomeDirector.session_variant_salt = 1234
	d.biome_director = b
	var s := svc.save_store
	expect(not d.is_aurora_due(), "unscheduled is not due")
	s.total_playtime_seconds = 36000.0
	d.schedule_if_unscheduled()
	expect(s.next_aurora_due_seconds == 37800.0, "legacy 10-hour save scheduled from now")
	var loaded := SaveStore.new()
	loaded.load_from_disk()
	expect(loaded.next_aurora_due_seconds == 37800.0, "deadline persisted")
	s.total_playtime_seconds = 36500.0
	d.schedule_if_unscheduled()
	expect(s.next_aurora_due_seconds == 37800.0, "ready does not postpone deadline")
	main.elapsed_time = 1299.0
	expect(not d.is_aurora_due(), "before deadline")
	main.elapsed_time = 1300.0
	expect(d.is_aurora_due(), "at deadline")
	s.total_playtime_seconds = 37000.0
	gm.banked_run_seconds = 500.0
	expect(d.get_total_playtime_seconds() == 37800.0, "pause bookkeeping not double counted")
	for density: float in [0.0, 0.28, 0.3, 0.799, 0.8, 0.85, 1.0]:
		b.blended.star_density = density
		expect(d.is_sky_ready() == (density >= 0.8), "density %f" % density)
	d.begin_aurora()
	for pair: Vector2 in [Vector2(0,0),Vector2(4,0.5),Vector2(8,1),Vector2(30,1),Vector2(53,1),Vector2(57,0.5),Vector2(61,0),Vector2(62,0)]:
		d.active_elapsed = pair.x
		expect(is_equal_approx(d.get_aurora_blend(),pair.y), "ramp %s" % pair)
	s.total_playtime_seconds = 36000.0
	main.elapsed_time = 2400.0
	gm.banked_run_seconds = 0.0
	d.finish_aurora()
	expect(s.next_aurora_due_seconds == 40200.0, "completion schedules from full uninterrupted run")
	expect(s.aurora_count == 1, "one completion counted")
	d._physics_process(10000.0)
	expect(s.aurora_count == 1, "DONE terminal")
	d.begin_aurora()
	d._on_player_died()
	expect(d.phase == AuroraDirector.Phase.DONE and s.aurora_count == 1, "death aborts without credit")
	s.reset_progress()
	expect(s.next_aurora_due_seconds == -1.0 and not d.is_aurora_due(), "reset unschedules")
	d.schedule_if_unscheduled()
	expect(s.next_aurora_due_seconds == 1800.0, "reset reschedules from zero")
	# Reproduce late-night launch with SHIPPING biome speed, no debug bypass.
	var start_x: float = 7 * BiomeDirector.BIOME_DISTANCE + 57000.0
	b.apply_palette_for_world_x(start_x)
	d.phase = AuroraDirector.Phase.IDLE
	s.next_aurora_due_seconds = 0.0
	d._physics_process(1.0 / 60.0)
	print("NIGHT_REPRO start_night=", b.get_night_amount(), " phase=", d.phase, " sky_top=", b.blended.sky_top)
	for elapsed: float in [8.0, 20.0, 30.0, 53.0]:
		b.apply_palette_for_world_x(start_x + 750.0 * elapsed)
		d.active_elapsed = elapsed
		print("NIGHT_REPRO elapsed=",elapsed," night=",b.get_night_amount()," blend=",d.get_aurora_blend()," sky_top=",b.blended.sky_top)
	# Debug read bypass still flows into real completion persistence.
	s.total_playtime_seconds = 100.0
	s.next_aurora_due_seconds = 1900.0
	s.aurora_count = 0
	main.elapsed_time = 71.0
	d.debug_aurora_interval_override = 10.0
	d.begin_aurora()
	d.finish_aurora()
	loaded = SaveStore.new()
	loaded.load_from_disk()
	print("DEBUG_PERSIST_REPRO old_deadline=1900 saved_deadline=",loaded.next_aurora_due_seconds," saved_count=",loaded.aurora_count)
	# Benchmark the real bake, independently of skipped headless _ready.
	var sky: Node = load("res://scripts/systems/sky_backdrop.gd").new()
	var before: int = Time.get_ticks_usec()
	sky.build_aurora_bands()
	print("BAKE three_bands_ms=",float(Time.get_ticks_usec()-before)/1000.0)
	expect(sky.aurora_bands.size()==3,"three bands built")
	for t: float in [0.0, 8.0, 16.0, 30.0, 53.0, 61.0]:
		sky.apply_aurora(1.0,t)
		for band: TextureRect in sky.aurora_bands:
			expect(band.anchor_left < 0.0 and band.anchor_right > 1.0,"horizontal coverage")
	sky.apply_aurora(0.0,61.0)
	for band: TextureRect in sky.aurora_bands:
		expect(not band.visible and band.mouse_filter == Control.MOUSE_FILTER_IGNORE,"hidden/input transparent")
	# Measure Route B using exact authored segment lengths and actual void edges.
	var gap_count: int = 0
	var qualifying: int = 0
	var max_gap: float = 0.0
	var eligible_distance: float = 0.0
	var total_distance: float = 0.0
	var max_seed: int = 0
	for seed_index: int in range(32):
		var terrain := TerrainGenerator.new()
		terrain.session_seed = seed_index * 7919 + 1
		var x: float = 0.0
		var last_void_end: float = -1.0
		for index: int in range(5600):
			var spec: Dictionary = terrain.get_segment_spec(index)
			if spec.has("void_start_offset"):
				var void_start: float = x + float(spec["void_start_offset"])
				if last_void_end >= 0:
					var gap: float = void_start - last_void_end
					gap_count += 1
					if gap > max_gap:
						max_gap = gap
						max_seed = terrain.session_seed
					if gap >= 61000.0:
						qualifying += 1
						eligible_distance += gap - 61000.0
				last_void_end = void_start + float(spec["void_length"])
			x += float(spec["length"])
		total_distance += x
		terrain.free()
	print("GAP_MEASUREMENT seeds=32 segments_per_seed=5600 gaps=",gap_count," qualifying_61000=",qualifying," max_gap=",max_gap," max_seed=",max_seed," eligible_distance_fraction=",eligible_distance/total_distance)
	print("AUDIT_CHECKS ",checks," assertions, ",failed," failures")
	sky.free()
	d.free()
	b.free()
	gm.free()
	main.free()
	svc.free()
	quit(1 if failed else 0)
