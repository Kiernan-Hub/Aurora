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
	for width: int in [1152,1440]:
		root.size = Vector2i(width,648)
		for test: Array in [["twilight",6*75000.0,20.0],["night",7*75000.0,20.0],["dawn",8*75000.0,20.0]]:
			b.apply_palette_for_world_x(test[1])
			sky.apply_aurora(0.0,test[2])
			var off: Image = await capture()
			sky.apply_aurora(1.0,test[2])
			var on: Image = await capture()
			var label: String = "%s_%d" % [test[0],width]
			off.save_png("/private/tmp/aura-aurora-audit/%s_off.png" % label)
			on.save_png("/private/tmp/aura-aurora-audit/%s_on.png" % label)
			print("VISUAL_CAPTURE ",label," size=",on.get_size()," bands=",sky.aurora_bands.size())
	# Verify rendered exact handback after a running event, without any palette change.
	sky.apply_aurora(0.0,61.0)
	var clean: Image = await capture()
	clean.save_png("/private/tmp/aura-aurora-audit/cleared.png")
	quit()
