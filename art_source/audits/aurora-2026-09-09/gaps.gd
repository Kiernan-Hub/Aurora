extends SceneTree
func _init() -> void:
	# Measure Route B using exact authored segment lengths and actual void edges.
	var gap_count: int = 0
	var qualifying: int = 0
	var max_gap: float = 0.0
	var eligible_distance: float = 0.0
	var total_distance: float = 0.0
	var max_seed: int = 0
	for seed_index: int in range(256):
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
	print("GAP_MEASUREMENT seeds=256 segments_per_seed=5600 gaps=",gap_count," qualifying_61000=",qualifying," max_gap=",max_gap," max_seed=",max_seed," eligible_distance_fraction=",eligible_distance/total_distance)
	quit()
