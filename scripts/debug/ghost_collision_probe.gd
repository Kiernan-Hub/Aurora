extends SceneTree

# TEMPORARY audit tool (E3). Isolates the question: does Godot's 2D solver report
# collision normals that do not match the surface, on a PROVABLY FLAT
# ConcavePolygonShape2D built from short line segments?
#
# No TerrainGenerator is involved. The polyline is constructed here, perfectly
# flat, from exactly-representable floats. Therefore the only correct normal any
# contact can have is (0, -1). Any deviation is a solver artifact.
#
# Player conditions are replicated exactly from player.tscn / player.gd:
#   CapsuleShape2D r16 h48, safe_margin 1.0, floor_snap_length 18,
#   floor_stop_on_slope false, floor_constant_speed true, max_slides 4,
#   velocity = get_slope_tangent() * current_speed, speed ramp 300->500 @3.2.

const SEGMENT_LENGTH: float = 16.0
const CHUNK_WIDTH: float = 512.0
const GROUND_Y: float = 192.0
const CAPSULE_RADIUS: float = 16.0
const CAPSULE_HEIGHT: float = 48.0
const CAPSULE_HALF_HEIGHT: float = CAPSULE_HEIGHT * 0.5
const NORMAL_TOLERANCE_DEG: float = 0.05
const STALL_MIN_VELOCITY_X: float = 1.0
const STALL_MAX_MOTION_X: float = 0.01
const MAX_ANOMALY_SAMPLES: int = 6


class ProbeConfig:
	var name: String
	var start_world_x: float
	var surface_local_y: float
	var safe_margin: float
	var segment_length: float
	var chunked: bool
	var frames: int
	var use_tangent_model: bool

	func _init(
		config_name: String,
		config_start_world_x: float,
		config_surface_local_y: float,
		config_safe_margin: float,
		config_segment_length: float,
		config_chunked: bool,
		config_frames: int,
		config_use_tangent_model: bool
	) -> void:
		name = config_name
		start_world_x = config_start_world_x
		surface_local_y = config_surface_local_y
		safe_margin = config_safe_margin
		segment_length = config_segment_length
		chunked = config_chunked
		frames = config_frames
		use_tangent_model = config_use_tangent_model


func _init() -> void:
	var frame_budget: int = get_int_argument("--frames", 2400)
	var configs: Array[ProbeConfig] = [
		# name, start_world_x, surface_local_y, safe_margin, segment_length, chunked, frames, tangent_model
		ProbeConfig.new("A  x=64        y=0        margin=1.00 seg=16 chunked", 64.0, 0.0, 1.0, 16.0, true, frame_budget, true),
		ProbeConfig.new("B  x=226368    y=37212    margin=1.00 seg=16 chunked  [case-1 coords]", 226368.0, 37212.0, 1.0, 16.0, true, frame_budget, true),
		ProbeConfig.new("C  x=226368    y=0        margin=1.00 seg=16 chunked  [far x, small y]", 226368.0, 0.0, 1.0, 16.0, true, frame_budget, true),
		ProbeConfig.new("D  x=64        y=37212    margin=1.00 seg=16 chunked  [near x, large y]", 64.0, 37212.0, 1.0, 16.0, true, frame_budget, true),
		ProbeConfig.new("E  x=386112    y=65724    margin=1.00 seg=16 chunked  [case-2 coords]", 386112.0, 65724.0, 1.0, 16.0, true, frame_budget, true),
		ProbeConfig.new("F  x=226368    y=37212    margin=0.08 seg=16 chunked  [margin control]", 226368.0, 37212.0, 0.08, 16.0, true, frame_budget, true),
		ProbeConfig.new("G  x=226368    y=37212    margin=1.00 seg=16 SINGLE   [seam control]", 226368.0, 37212.0, 1.0, 16.0, false, frame_budget, true),
		ProbeConfig.new("H  x=226368    y=37212    margin=1.00 seg=32 chunked  [seg-len control]", 226368.0, 37212.0, 1.0, 32.0, true, frame_budget, true),
		ProbeConfig.new("I  x=226368    y=37212    margin=1.00 seg=16 chunked  CONSTANT-X model", 226368.0, 37212.0, 1.0, 16.0, true, frame_budget, false),
		ProbeConfig.new("J  x=1000000   y=150000   margin=1.00 seg=16 chunked  [extreme far]", 1000000.0, 150000.0, 1.0, 16.0, true, frame_budget, true),
	]

	print("PROBE_BEGIN\tgodot=%s\tphysics_hz=%d" % [Engine.get_version_info()["string"], Engine.physics_ticks_per_second])
	for config: ProbeConfig in configs:
		await run_probe(config)
	print("PROBE_END")
	quit(0)


func run_probe(config: ProbeConfig) -> void:
	var world_root: Node2D = Node2D.new()
	root.add_child(world_root)

	var travel_distance: float = 520.0 * (float(config.frames) / 60.0) + 4096.0
	build_flat_world(world_root, config, travel_distance)

	var body: CharacterBody2D = CharacterBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.safe_margin = config.safe_margin
	body.floor_snap_length = 18.0
	body.floor_stop_on_slope = false
	body.floor_constant_speed = true
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var body_shape: CollisionShape2D = CollisionShape2D.new()
	body_shape.shape = capsule
	body.add_child(body_shape)
	body.global_position = Vector2(
		config.start_world_x,
		GROUND_Y + config.surface_local_y - CAPSULE_HALF_HEIGHT
	)
	world_root.add_child(body)

	await physics_frame

	var current_speed: float = 300.0
	var anomaly_frames: int = 0
	var floor_normal_anomaly_frames: int = 0
	var stall_frames: int = 0
	var max_deviation_deg: float = 0.0
	var max_floor_deviation_deg: float = 0.0
	var anomaly_samples: Array[String] = []
	var floor_samples: Array[String] = []
	var max_slide_count: int = 0
	var grounded_frames: int = 0
	var motion_x_sum: float = 0.0

	for frame_index: int in range(config.frames):
		current_speed = minf(current_speed + (3.2 / 60.0), 500.0)

		if body.is_on_floor() and body.velocity.y >= 0.0:
			if config.use_tangent_model:
				var floor_normal: Vector2 = body.get_floor_normal()
				var tangent: Vector2 = Vector2(-floor_normal.y, floor_normal.x).normalized()
				if tangent.x < 0.0:
					tangent = -tangent
				body.velocity = tangent * current_speed
			else:
				body.velocity = Vector2(current_speed, 0.0)
		else:
			body.velocity.x = current_speed
			body.velocity.y += 1600.0 / 60.0

		var position_before: Vector2 = body.global_position
		body.move_and_slide()
		var motion: Vector2 = body.global_position - position_before

		var grounded: bool = body.is_on_floor()
		if grounded:
			grounded_frames += 1
		motion_x_sum += motion.x

		var slide_count: int = body.get_slide_collision_count()
		max_slide_count = maxi(max_slide_count, slide_count)

		var frame_has_anomaly: bool = false
		var frame_worst_deg: float = 0.0
		for collision_index: int in range(slide_count):
			var collision: KinematicCollision2D = body.get_slide_collision(collision_index)
			var normal: Vector2 = collision.get_normal()
			var deviation_deg: float = rad_to_deg(absf(atan2(normal.x, -normal.y)))
			if deviation_deg > NORMAL_TOLERANCE_DEG:
				frame_has_anomaly = true
				frame_worst_deg = maxf(frame_worst_deg, deviation_deg)

		if frame_has_anomaly:
			anomaly_frames += 1
			max_deviation_deg = maxf(max_deviation_deg, frame_worst_deg)
			if anomaly_samples.size() < MAX_ANOMALY_SAMPLES:
				anomaly_samples.append(describe_frame(body, frame_index, motion, current_speed))

		if grounded:
			var floor_normal_now: Vector2 = body.get_floor_normal()
			var floor_deviation_deg: float = rad_to_deg(absf(atan2(floor_normal_now.x, -floor_normal_now.y)))
			if floor_deviation_deg > NORMAL_TOLERANCE_DEG:
				floor_normal_anomaly_frames += 1
				max_floor_deviation_deg = maxf(max_floor_deviation_deg, floor_deviation_deg)
				if floor_samples.size() < MAX_ANOMALY_SAMPLES:
					floor_samples.append("FLOORNORM dev=%.6f deg n=(%.6f,%.6f) %s" % [
						floor_deviation_deg, floor_normal_now.x, floor_normal_now.y,
						describe_frame(body, frame_index, motion, current_speed),
					])

		if grounded and absf(body.velocity.x) >= STALL_MIN_VELOCITY_X and absf(motion.x) <= STALL_MAX_MOTION_X:
			stall_frames += 1
			if anomaly_samples.size() < MAX_ANOMALY_SAMPLES:
				anomaly_samples.append("STALL " + describe_frame(body, frame_index, motion, current_speed))

		await physics_frame

	print("PROBE_RESULT\t%s" % config.name)
	print("    frames=%d  grounded=%d  max_slide_collisions=%d  mean_motion_x=%.4f (expected ~%.4f)" % [
		config.frames, grounded_frames, max_slide_count,
		motion_x_sum / float(config.frames), 0.5 * (300.0 + current_speed) / 60.0,
	])
	print("    frames with a non-(0,-1) contact normal : %d" % anomaly_frames)
	print("    frames with a non-(0,-1) FLOOR normal   : %d  (max dev %.6f deg)" % [floor_normal_anomaly_frames, max_floor_deviation_deg])
	print("    stalled frames (motion.x~0, grounded)   : %d" % stall_frames)
	print("    max normal deviation from vertical      : %.6f deg" % max_deviation_deg)
	for sample: String in anomaly_samples:
		print("      %s" % sample)
	for sample: String in floor_samples:
		print("      %s" % sample)

	world_root.queue_free()
	await process_frame


func describe_frame(body: CharacterBody2D, frame_index: int, motion: Vector2, current_speed: float) -> String:
	var normals_text: String = ""
	for collision_index: int in range(body.get_slide_collision_count()):
		var collision: KinematicCollision2D = body.get_slide_collision(collision_index)
		normals_text += " n%d=(%.6f,%.6f)@x=%.4f" % [
			collision_index,
			collision.get_normal().x,
			collision.get_normal().y,
			collision.get_position().x,
		]
	return "frame=%d x=%.4f vx=%.3f motion.x=%.6f speed=%.2f slides=%d%s" % [
		frame_index, body.global_position.x, body.velocity.x, motion.x,
		current_speed, body.get_slide_collision_count(), normals_text,
	]


func build_flat_world(world_root: Node2D, config: ProbeConfig, travel_distance: float) -> void:
	if config.chunked:
		var first_chunk: int = int(floor(config.start_world_x / CHUNK_WIDTH)) - 1
		var last_chunk: int = int(floor((config.start_world_x + travel_distance) / CHUNK_WIDTH)) + 1
		for chunk_index: int in range(first_chunk, last_chunk + 1):
			var chunk_start_x: float = float(chunk_index) * CHUNK_WIDTH
			var body_x: float = chunk_start_x + (CHUNK_WIDTH * 0.5)
			var points: PackedVector2Array = PackedVector2Array()
			var sample_x: float = chunk_start_x
			while sample_x <= chunk_start_x + CHUNK_WIDTH + 0.0001:
				points.append(Vector2(sample_x - body_x, config.surface_local_y))
				sample_x += config.segment_length
			world_root.add_child(make_static_body(points, Vector2(body_x, GROUND_Y)))
	else:
		var span_start: float = config.start_world_x - CHUNK_WIDTH
		var span_end: float = config.start_world_x + travel_distance + CHUNK_WIDTH
		var body_x: float = span_start
		var points: PackedVector2Array = PackedVector2Array()
		var sample_x: float = span_start
		while sample_x <= span_end:
			points.append(Vector2(sample_x - body_x, config.surface_local_y))
			sample_x += config.segment_length
		world_root.add_child(make_static_body(points, Vector2(body_x, GROUND_Y)))


func make_static_body(points: PackedVector2Array, body_position: Vector2) -> StaticBody2D:
	var segments: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(1, points.size()):
		segments.append(points[point_index - 1])
		segments.append(points[point_index])
	var shape: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
	shape.set_segments(segments)
	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	collision_shape.shape = shape
	var static_body: StaticBody2D = StaticBody2D.new()
	static_body.collision_layer = 1
	static_body.collision_mask = 1
	static_body.position = body_position
	static_body.add_child(collision_shape)
	return static_body


func get_int_argument(argument_name: String, default_value: int) -> int:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_int()
	return default_value
