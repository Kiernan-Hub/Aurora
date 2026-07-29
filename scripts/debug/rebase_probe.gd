extends SceneTree

# TEMPORARY audit tool (E3b). Two questions, on a provably flat, code-built
# ConcavePolygonShape2D — no TerrainGenerator involved:
#
#   Q1. WHICH coordinate drives the anomalous floor normals: the shape's LOCAL y,
#       the body's WORLD y, or (per E3) neither x?
#   Q2. Does rebasing (shifting everything back toward y=0 mid-run) actually
#       eliminate them? Measured as before/after within a single run.
#
# Surface world y = chunk_body_y + surface_local_y. Varying those two
# independently separates local-coordinate magnitude from world-coordinate
# magnitude, which imply different fixes:
#   - local y is the culprit  -> park each chunk node at its own terrain height
#                                (cheap, no global rebase)
#   - world y is the culprit  -> periodic global origin shift

const CHUNK_WIDTH: float = 512.0
const CAPSULE_RADIUS: float = 16.0
const CAPSULE_HEIGHT: float = 48.0
const CAPSULE_HALF_HEIGHT: float = CAPSULE_HEIGHT * 0.5
const SEGMENT_LENGTH: float = 16.0
const NORMAL_TOLERANCE_DEG: float = 0.05
const STALL_MIN_VELOCITY_X: float = 1.0
const STALL_MAX_MOTION_X: float = 0.01
const MAX_SAMPLES_PER_PHASE: int = 3


class PhaseStats:
	var label: String
	var frames: int = 0
	var grounded: int = 0
	var floor_anomalies: int = 0
	var contact_anomalies: int = 0
	var stalls: int = 0
	var max_floor_dev_deg: float = 0.0
	var max_contact_dev_deg: float = 0.0
	var motion_x_sum: float = 0.0
	var max_slides: int = 0
	var samples: Array[String] = []

	func _init(phase_label: String) -> void:
		label = phase_label

	func report() -> String:
		return ("      %-22s frames=%-5d grounded=%-5d floor_anom=%-5d contact_anom=%-5d stalls=%-5d max_floor_dev=%8.4f deg  mean_motion_x=%.4f  max_slides=%d"
			% [label, frames, grounded, floor_anomalies, contact_anomalies, stalls,
			   max_floor_dev_deg, motion_x_sum / maxf(float(frames), 1.0), max_slides])


class ProbeConfig:
	var name: String
	var start_world_x: float
	var chunk_body_y: float
	var surface_local_y: float
	var frames: int
	var rebase_at_frame: int

	func _init(n: String, sx: float, body_y: float, local_y: float, f: int, rebase: int) -> void:
		name = n
		start_world_x = sx
		chunk_body_y = body_y
		surface_local_y = local_y
		frames = f
		rebase_at_frame = rebase


func _init() -> void:
	var budget: int = get_int_argument("--frames", 4000)
	var half: int = budget / 2
	var configs: Array[ProbeConfig] = [
		# --- Q1: isolate which coordinate matters (surface world y noted in name) ---
		ProbeConfig.new("K1 local_y=0      world_y=192     [both small - control]", 64.0, 192.0, 0.0, budget, 0),
		ProbeConfig.new("K2 local_y=0      world_y=37404   [LARGE world, tiny local]", 64.0, 37404.0, 0.0, budget, 0),
		ProbeConfig.new("K3 local_y=37212  world_y=37404   [LARGE both - E3 config D]", 64.0, 192.0, 37212.0, budget, 0),
		ProbeConfig.new("K4 local_y=37212  world_y=192     [LARGE local, small world]", 64.0, -37020.0, 37212.0, budget, 0),
		# --- separate x from y in the catastrophic E3 config J ---
		ProbeConfig.new("K5 x=1e6  local_y=0  world_y=192  [huge x, small y]", 1000000.0, 192.0, 0.0, budget, 0),
		ProbeConfig.new("K6 x=1e6  local_y=150000          [huge x AND y - E3 J]", 1000000.0, 192.0, 150000.0, budget, 0),
		# --- Q2: does rebasing actually fix it? before/after within one run ---
		ProbeConfig.new("R1 large y, NO rebase   [baseline]", 64.0, 192.0, 37212.0, budget, 0),
		ProbeConfig.new("R2 large y, REBASE at midpoint", 64.0, 192.0, 37212.0, budget, half),
		ProbeConfig.new("R3 extreme y, REBASE at midpoint", 1000000.0, 192.0, 150000.0, budget, half),
	]

	print("REBASE_PROBE_BEGIN\tgodot=%s" % Engine.get_version_info()["string"])
	for config: ProbeConfig in configs:
		await run_probe(config)
	print("REBASE_PROBE_END")
	quit(0)


func run_probe(config: ProbeConfig) -> void:
	var world_root: Node2D = Node2D.new()
	root.add_child(world_root)

	var travel: float = 520.0 * (float(config.frames) / 60.0) + 4096.0
	build_flat_world(world_root, config, travel)

	var body: CharacterBody2D = make_probe_body()
	body.global_position = Vector2(
		config.start_world_x,
		config.chunk_body_y + config.surface_local_y - CAPSULE_HALF_HEIGHT
	)
	world_root.add_child(body)
	await physics_frame

	var before: PhaseStats = PhaseStats.new("before" if config.rebase_at_frame > 0 else "whole run")
	var after: PhaseStats = PhaseStats.new("after rebase")
	var current_speed: float = 300.0
	var did_rebase: bool = false

	for frame_index: int in range(config.frames):
		if config.rebase_at_frame > 0 and frame_index == config.rebase_at_frame and not did_rebase:
			var shift_y: float = -(config.chunk_body_y + config.surface_local_y)
			apply_rebase(world_root, shift_y)
			did_rebase = true
			print("      >>> REBASE applied at frame %d: shift_y=%.1f  new surface world y=%.1f" % [
				frame_index, shift_y, config.chunk_body_y + config.surface_local_y + shift_y,
			])
			await physics_frame

		var stats: PhaseStats = after if did_rebase else before
		current_speed = minf(current_speed + (3.2 / 60.0), 500.0)

		if body.is_on_floor() and body.velocity.y >= 0.0:
			var floor_normal: Vector2 = body.get_floor_normal()
			var tangent: Vector2 = Vector2(-floor_normal.y, floor_normal.x).normalized()
			if tangent.x < 0.0:
				tangent = -tangent
			body.velocity = tangent * current_speed
		else:
			body.velocity.x = current_speed
			body.velocity.y += 1600.0 / 60.0

		var position_before: Vector2 = body.global_position
		body.move_and_slide()
		var motion: Vector2 = body.global_position - position_before

		stats.frames += 1
		stats.motion_x_sum += motion.x
		stats.max_slides = maxi(stats.max_slides, body.get_slide_collision_count())
		var grounded: bool = body.is_on_floor()
		if grounded:
			stats.grounded += 1

		var worst_contact_deg: float = 0.0
		for collision_index: int in range(body.get_slide_collision_count()):
			var normal: Vector2 = body.get_slide_collision(collision_index).get_normal()
			worst_contact_deg = maxf(worst_contact_deg, rad_to_deg(absf(atan2(normal.x, -normal.y))))
		if worst_contact_deg > NORMAL_TOLERANCE_DEG:
			stats.contact_anomalies += 1
			stats.max_contact_dev_deg = maxf(stats.max_contact_dev_deg, worst_contact_deg)

		if grounded:
			var fn: Vector2 = body.get_floor_normal()
			var floor_dev: float = rad_to_deg(absf(atan2(fn.x, -fn.y)))
			if floor_dev > NORMAL_TOLERANCE_DEG:
				stats.floor_anomalies += 1
				stats.max_floor_dev_deg = maxf(stats.max_floor_dev_deg, floor_dev)
				if stats.samples.size() < MAX_SAMPLES_PER_PHASE:
					stats.samples.append("dev=%8.4f deg n=(%.6f,%.6f) frame=%d world_y=%.1f motion.x=%.4f" % [
						floor_dev, fn.x, fn.y, frame_index, body.global_position.y, motion.x,
					])

		if grounded and absf(body.velocity.x) >= STALL_MIN_VELOCITY_X and absf(motion.x) <= STALL_MAX_MOTION_X:
			stats.stalls += 1

		await physics_frame

	print("REBASE_RESULT\t%s" % config.name)
	print(before.report())
	for sample: String in before.samples:
		print("          %s" % sample)
	if config.rebase_at_frame > 0:
		print(after.report())
		for sample: String in after.samples:
			print("          %s" % sample)

	world_root.queue_free()
	await process_frame


func apply_rebase(world_root: Node2D, shift_y: float) -> void:
	for child: Node in world_root.get_children():
		var node_2d: Node2D = child as Node2D
		if node_2d != null:
			node_2d.position += Vector2(0.0, shift_y)


func make_probe_body() -> CharacterBody2D:
	var body: CharacterBody2D = CharacterBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.safe_margin = 1.0
	body.floor_snap_length = 18.0
	body.floor_stop_on_slope = false
	body.floor_constant_speed = true
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	shape_node.shape = capsule
	body.add_child(shape_node)
	return body


func build_flat_world(world_root: Node2D, config: ProbeConfig, travel: float) -> void:
	var first_chunk: int = int(floor(config.start_world_x / CHUNK_WIDTH)) - 1
	var last_chunk: int = int(floor((config.start_world_x + travel) / CHUNK_WIDTH)) + 1
	for chunk_index: int in range(first_chunk, last_chunk + 1):
		var chunk_start_x: float = float(chunk_index) * CHUNK_WIDTH
		var body_x: float = chunk_start_x + (CHUNK_WIDTH * 0.5)
		var segments: PackedVector2Array = PackedVector2Array()
		var sample_x: float = chunk_start_x
		var previous: Vector2 = Vector2(sample_x - body_x, config.surface_local_y)
		sample_x += SEGMENT_LENGTH
		while sample_x <= chunk_start_x + CHUNK_WIDTH + 0.0001:
			var point: Vector2 = Vector2(sample_x - body_x, config.surface_local_y)
			segments.append(previous)
			segments.append(point)
			previous = point
			sample_x += SEGMENT_LENGTH
		var shape: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
		shape.set_segments(segments)
		var collision_shape: CollisionShape2D = CollisionShape2D.new()
		collision_shape.shape = shape
		var static_body: StaticBody2D = StaticBody2D.new()
		static_body.collision_layer = 1
		static_body.collision_mask = 1
		static_body.position = Vector2(body_x, config.chunk_body_y)
		static_body.add_child(collision_shape)
		world_root.add_child(static_body)


func get_int_argument(argument_name: String, default_value: int) -> int:
	var argument_prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix).to_int()
	return default_value
