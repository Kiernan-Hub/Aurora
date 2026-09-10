extends SceneTree
var main: Node
func _init() -> void:
	call_deferred("run")
func settle() -> void:
	for i: int in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
func capture() -> Image:
	await settle()
	return root.get_texture().get_image()
func run() -> void:
	BiomeDirector.session_cycle_rotation = 0
	BiomeDirector.session_variant_salt = 1234
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("GameManager").require_start_screen = false
	main.get_node("TerrainGenerator").debug_chasm_disabled = true
	main.get_node("TerrainGenerator/ObstacleSpawner").debug_spawning_disabled = true
	main.get_node("TerrainGenerator/PowerupSpawner").debug_spawning_disabled = true
	main.get_node("AuroraDirector").debug_aurora_interval_override = 0.0
	root.add_child(main)
	for i: int in range(90):
		main.get_node("GameManager").set_state(GameManager.State.PLAYING)
		await process_frame
	main.get_node("GameManager").set_state(GameManager.State.PAUSED)
	main.get_node("CanvasLayer").visible = false
	var b: BiomeDirector = main.get_node("BiomeDirector")
	b.set_process(false)
	main.get_node("AuroraDirector").set_physics_process(false)
	var sky: Node = main.get_node("SkyBackdrop")
	root.size = Vector2i(1152,648)
	b.apply_palette_for_world_x(7*75000.0)
	for scenery: bool in [true,false]:
		main.get_node("ParallaxBackground").visible = scenery
		for elapsed: float in [8.0,20.0,36.0,52.0]:
			sky.apply_aurora(0.0,elapsed)
			var off: Image = await capture()
			var label: String = "bands_%s_%d" % [str(scenery),int(elapsed)]
			off.save_png("/private/tmp/aura-aurora-audit/%s_off.png" % label)
			for selected: int in range(3):
				sky.apply_aurora(1.0,elapsed)
				for i: int in range(3):
					sky.aurora_bands[i].visible = i == selected
				var on: Image = await capture()
				on.save_png("/private/tmp/aura-aurora-audit/%s_%d.png" % [label,selected])
				if elapsed == 20.0 and scenery:
					print("BAND_RECT ",selected," rect=",sky.aurora_bands[selected].get_rect())
	quit()
