extends SceneTree

# Interactive, WINDOWED visual diagnostic for the mega_drop shake investigation
# (2026-07-31 follow-up to mega_drop_probe.gd). That probe found WHERE the
# shake comes from numerically (concave-half depenetration spikes); this one
# is for looking at it directly, because a fix that measured a 42% reduction
# in the probe's jitter metric (presentation-layer smoothing) produced ZERO
# perceptual improvement in playtest. The metric and the eye are tracking
# different things -- this tool exists to find out what the eye is actually
# tracking before trying another mitigation.
#
# Draws four channels every physics frame: physics body (CharacterBody2D
# global_position), sprite/render position (color_rect.global_position),
# resolved terrain contact point (get_floor_collision_data(), falling back to
# the analytic surface height when airborne), and camera position. Two views:
#   - true-scale markers at their real on-screen positions (dots + labels)
#   - a magnified inset panel (top-right) plotting each channel's deviation
#     from a slow-moving baseline of the physics position, scaled up by
#     --zoom, with a fading trail so a repeating pattern (vs. a one-off
#     spike) is visible at a glance
# plus a numeric readout of each channel's frame-to-frame delta.
#
# 2026-08-01: previously forced mega_drop-only (mega_drop chained directly to
# mega_drop) to isolate the segment instead of waiting for it to come up
# naturally -- but that meant three full probing rounds only ever measured a
# mega_drop -> mega_drop chain, NEVER the entry transition from a different
# segment type, which is how mega_drop is actually encountered in normal
# mixed play. User confirmed real, unchanged visible shake in normal play
# after that mega_drop-only interior investigation found nothing shake-sized
# there. Switched back to the natural default segment mix (mega_drop is
# ~9% of it) so each occurrence has a real, varied lead-in segment, and the
# probe now specifically logs that entry boundary (MEGA_DROP_ENTRY_CONTEXT /
# entered_from=<label> below).
#
# Usage (do NOT pass --headless -- this needs a real window):
#   Godot --path . --script res://scripts/debug/mega_drop_visual_probe.gd -- \
#       [--seed=941462462] [--zoom=20] [--trail=90]
#
# Close the window to quit. ui_up/ui_down still adjust speed manually
# (player.gd DEBUG_ALLOW_MANUAL_SPEED_CONTROL); ui_accept still jumps.
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const INSET_SIZE: Vector2 = Vector2(260, 260)
const INSET_MARGIN: float = 16.0
# Slow exp weight so the baseline tracks the segment's overall descent, not
# the frame-to-frame shake being measured against it.
const BASELINE_SMOOTHING: float = 2.0

var main: Node
var player: Player
var terrain_generator: TerrainGenerator
var camera_2d: Camera2D
var overlay: Control
var label: Label
# CONTACT_ANOMALY lines are written here directly (flushed every line),
# instead of relying solely on redirected stdout: repeated test runs produced
# an identical 5-line file no matter how long the probe played, which points
# to Godot's stdout being block-buffered when piped to a file and only
# flushed on a clean process exit -- something a force-closed window may
# skip. A self-flushing file survives that regardless. print() is kept too,
# for live viewing when the terminal isn't redirected.
var log_file: FileAccess
const LOG_FILE_PATH: String = "res://scripts/debug/mega_drop_visual_probe_output.log"

var baseline_position: Vector2 = Vector2.ZERO
var has_baseline: bool = false
var zoom: float = 20.0
var trail_length: int = 90


# One slide_collision candidate, read-only snapshot of exactly what
# get_floor_collision_data()'s selection loop (player.gd) looks at, so the
# probe can show the whole tie instead of just the winner it picked.
class ContactCandidate:
	var position: Vector2
	var normal: Vector2
	var normal_match: float


class Sample:
	var physics_pos: Vector2
	var sprite_pos: Vector2
	var contact_pos: Vector2
	var has_contact: bool
	var camera_pos: Vector2
	var floor_normal: Vector2
	# color_rect.rotation, and the contact point re-expressed in the sprite's
	# OWN rotated frame (contact_pos - sprite_pos, un-rotated by -rotation).
	# 2026-08-01: playtest reports the contact marker sliding between the
	# sprite's bottom-right and bottom-middle -- a position RELATIVE TO THE
	# ROTATING RECTANGLE, not necessarily a world-space jump. If contact_pos
	# is nearly stationary in world space (world-frame anomaly ~0, already
	# measured) while the rectangle itself swings, re-expressing the same
	# roughly-fixed world offset in a different rotated basis each frame will
	# itself produce a large apparent shift here -- exactly the reported
	# visual, and distinct from an actual physics/collision anomaly.
	var rotation: float
	var contact_local: Vector2
	# 2026-08-01 landing-snap decomposition: player.gd's own per-stage debug
	# snapshots, copied in verbatim so a single-frame position jump can be
	# attributed to move_and_slide()'s own resolution (velocity_before_slide ->
	# position_after_slide) vs. this project's apply_grounded_floor_snap()
	# (position_after_slide -> position_after_snap), instead of only seeing the
	# combined per-frame result.
	var velocity_before_slide: Vector2
	var velocity_after_slide: Vector2
	var position_after_slide: Vector2
	var position_after_snap: Vector2
	# Every slide collision this frame, not just get_floor_collision_data()'s
	# best-normal-match winner -- to test whether the flickering contact point
	# is actually a near-tied choice between two simultaneous contacts (e.g.
	# adjacent polyline segments on the concave half) rather than real motion.
	var all_contacts: Array[ContactCandidate] = []
	var winner_index: int = -1


var history: Array[Sample] = []
var previous_sample: Sample = null
# Tracks the segment label across frames (independent of is_on_mega_drop's
# gating) so a transition INTO mega_drop from something else can be caught
# and logged with what preceded it, plus a few frames of pre-transition
# context pulled from `history`.
var previous_segment_label: String = ""
var current_mega_drop_entered_from: String = "?"
const ENTRY_CONTEXT_FRAME_COUNT: int = 8
# 2026-08-01 hitch check: the one observed ~5px landing-snap spike (world_x
# 7247.563, this seed) didn't reproduce across three same-seed reruns after
# ruling out apply_grounded_floor_snap() as its source (see
# docs/development/debugging.md) -- next candidate is a real frame-timing
# hitch (GC/compile stall, disk I/O) rather than a geometric artifact of the
# segment. Wall-clock gap between physics_frame awaits is independent of
# Engine's fixed-timestep `delta`, so a stall shows up here even though it
# wouldn't perturb the physics math itself.
var last_wall_time_usec: int = -1


func _init() -> void:
	var seed_text: String = get_string_argument("--seed", "941462462")
	zoom = get_float_argument("--zoom", 20.0)
	trail_length = get_int_argument("--trail", 90)

	log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)
	if log_file == null:
		push_error("mega_drop_visual_probe: failed to open log file at " + LOG_FILE_PATH + " (error " + str(FileAccess.get_open_error()) + ")")

	main = MAIN_SCENE.instantiate()
	terrain_generator = main.get_node("TerrainGenerator") as TerrainGenerator
	player = main.get_node("Player") as Player
	terrain_generator.debug_replay_session_seed = seed_text.to_int()
	# Natural default segment mix -- see the file-header note above for why
	# this is no longer forced mega_drop-only.
	root.add_child(main)
	# main.camera_2d (and player.color_rect) are @onready vars -- not set until
	# main's _ready() runs, which (like mega_drop_probe.gd) doesn't happen
	# synchronously with add_child() here; it needs a frame boundary first.
	await physics_frame
	camera_2d = main.camera_2d

	build_overlay()

	log_line("MEGA_DROP_VISUAL_PROBE_BEGIN seed=%s zoom=%.1f trail=%d log_file=%s" % [seed_text, zoom, trail_length, LOG_FILE_PATH])
	while true:
		await physics_frame
		update_sample()


func log_line(text: String) -> void:
	print(text)
	if log_file != null:
		log_file.store_line(text)
		log_file.flush()


func build_overlay() -> void:
	var canvas_layer: CanvasLayer = CanvasLayer.new()
	canvas_layer.layer = 100
	root.add_child(canvas_layer)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_on_overlay_draw)
	canvas_layer.add_child(overlay)

	label = Label.new()
	# player.gd's own debug_state_label occupies roughly y=8..260 in the top
	# left (velocity/motion/floor/segment/slide_collisions/floor_collision
	# text) -- start well below it so the two don't overlap.
	label.position = Vector2(8, 280)
	label.add_theme_font_size_override("font_size", 12)
	overlay.add_child(label)


func update_sample() -> void:
	var wall_time_usec: int = Time.get_ticks_usec()
	var wall_gap_ms: float = 0.0
	if last_wall_time_usec >= 0:
		wall_gap_ms = float(wall_time_usec - last_wall_time_usec) / 1000.0
	last_wall_time_usec = wall_time_usec

	var sample: Sample = Sample.new()
	sample.physics_pos = player.global_position
	sample.sprite_pos = player.color_rect.global_position
	sample.camera_pos = camera_2d.global_position

	var floor_collision: Dictionary = player.get_floor_collision_data()
	if floor_collision.is_empty():
		var world_x: float = player.global_position.x
		sample.contact_pos = Vector2(world_x, terrain_generator.get_surface_world_y(world_x))
		sample.has_contact = false
	else:
		sample.contact_pos = floor_collision["position"]
		sample.has_contact = true

	sample.rotation = player.color_rect.rotation
	sample.contact_local = (sample.contact_pos - sample.sprite_pos).rotated(-sample.rotation)
	sample.velocity_before_slide = player.debug_velocity_before_slide
	sample.velocity_after_slide = player.debug_velocity_after_slide
	sample.position_after_slide = player.debug_position_after_slide
	sample.position_after_snap = player.debug_position_after_snap

	# Mirrors get_floor_collision_data()'s own best-normal-match selection
	# (player.gd), read-only, so all_contacts[winner_index] always equals
	# sample.contact_pos above -- this is purely to see the candidates that
	# selection was choosing between, not to change the selection.
	if player.is_on_floor() and player.get_slide_collision_count() > 0:
		sample.floor_normal = player.get_floor_normal()
		var best_normal_match: float = -1.0
		for collision_index: int in range(player.get_slide_collision_count()):
			var collision: KinematicCollision2D = player.get_slide_collision(collision_index)
			var candidate: ContactCandidate = ContactCandidate.new()
			candidate.position = collision.get_position()
			candidate.normal = collision.get_normal()
			candidate.normal_match = candidate.normal.dot(sample.floor_normal)
			sample.all_contacts.append(candidate)
			if candidate.normal_match > best_normal_match:
				best_normal_match = candidate.normal_match
				sample.winner_index = collision_index

	if not has_baseline:
		baseline_position = sample.physics_pos
		has_baseline = true
	else:
		var physics_delta_time: float = 1.0 / float(Engine.get_physics_ticks_per_second())
		var weight: float = 1.0 - exp(-BASELINE_SMOOTHING * physics_delta_time)
		baseline_position = baseline_position.lerp(sample.physics_pos, weight)

	history.append(sample)
	while history.size() > trail_length:
		history.pop_front()

	var current_segment_label: String = get_segment_label_at(sample.physics_pos.x)
	if current_segment_label == "mega_drop" and previous_segment_label != "mega_drop" and previous_segment_label != "":
		log_entry_context(previous_segment_label)
		current_mega_drop_entered_from = previous_segment_label
	previous_segment_label = current_segment_label

	log_mega_drop_frame(sample, wall_gap_ms)
	update_label(sample)
	previous_sample = sample
	overlay.queue_redraw()


func get_segment_label_at(world_x: float) -> String:
	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	var segment_index: int = terrain_generator.find_segment_index_at_x(world_x)
	return String(terrain_generator.get_segment_spec(segment_index)["label"])


# Dumps the last ENTRY_CONTEXT_FRAME_COUNT pre-transition samples (the tail
# end of the segment that led into this mega_drop occurrence), so the entry
# boundary can be inspected without needing to have gated logging on in
# advance -- the transition frame itself is unpredictable ahead of time.
func log_entry_context(entered_from_label: String) -> void:
	log_line("MEGA_DROP_ENTRY entered_from=%s" % entered_from_label)
	var context_start: int = maxi(0, history.size() - 1 - ENTRY_CONTEXT_FRAME_COUNT)
	for sample_index: int in range(context_start, history.size() - 1):
		var sample: Sample = history[sample_index]
		var prev: Sample = history[sample_index - 1] if sample_index > 0 else null
		var slide_delta: Vector2 = Vector2.ZERO
		if prev != null:
			slide_delta = sample.position_after_slide - prev.physics_pos
		log_line("  MEGA_DROP_ENTRY_CONTEXT world_x=%.3f  on_floor=%s  rotation=%.5f  slide_delta=(%.4f,%.4f)  vel_before=(%.2f,%.2f)" % [
			sample.physics_pos.x, str(sample.has_contact), sample.rotation,
			slide_delta.x, slide_delta.y,
			sample.velocity_before_slide.x, sample.velocity_before_slide.y,
		])


# True anywhere on a mega_drop segment (not just the concave back half): a
# prior run with confirmed visible shaking logged zero anomalies gated to
# progress >= 0.5, so the location assumption may itself be wrong -- widen to
# the whole segment rather than risk missing it again on a boundary guess.
# Read-only: mirrors terrain_generator's own segment lookup (also used by
# mega_drop_probe.gd and player.gd), doesn't affect terrain, player, or
# collision behavior.
func is_on_mega_drop(world_x: float) -> bool:
	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	var segment_index: int = terrain_generator.find_segment_index_at_x(world_x)
	var spec: Dictionary = terrain_generator.get_segment_spec(segment_index)
	return String(spec["label"]) == "mega_drop"


# 2026-08-01: three straight confirmed-shake runs logged ZERO events under
# thresholded gating (multi-contact tie, world-space contact anomaly > 3px,
# rotation-relative shift > 3px). Rather than guess at another threshold,
# stop thresholding: the inset panel is drawn at 20x zoom, so a genuinely
# sub-pixel real motion (well under 1px, consistent with the project's
# already-documented residual sub-pixel bounce on curved terrain --
# docs/research/terrain_jitter.md) would still look dramatic magnified 20x
# on screen while sailing under any px-scale world threshold. Logging every
# frame unconditionally removes that guesswork; mega_drop is short enough
# (one segment, forced-only terrain) that this stays a few hundred to ~1500
# lines per run instead of the whole-run flood a wall-clock gate produced.
func log_mega_drop_frame(sample: Sample, wall_gap_ms: float) -> void:
	if previous_sample == null:
		return
	if not is_on_mega_drop(sample.physics_pos.x):
		return

	var contact_delta: Vector2 = Vector2.ZERO
	var contact_anomaly: Vector2 = Vector2.ZERO
	var local_delta: Vector2 = Vector2.ZERO
	# contact_pos (and therefore contact_local, which is derived from it)
	# switches source across a has_contact transition -- real collision
	# position vs. the airborne fallback (analytic surface height). Those two
	# differ numerically at the same location, so a transition frame produces
	# an artificial jump with no relation to actual motion; only compare when
	# both frames used the same (real-collision) source.
	if sample.has_contact and previous_sample.has_contact:
		contact_delta = sample.contact_pos - previous_sample.contact_pos
		contact_anomaly = contact_delta - (sample.physics_pos - previous_sample.physics_pos)
		local_delta = sample.contact_local - previous_sample.contact_local
	var rotation_delta: float = sample.rotation - previous_sample.rotation

	# Stage decomposition for this frame: position_before_move is not itself
	# exposed by player.gd, but the probe samples once per physics frame with
	# nothing else moving the body in between, so last frame's resolved
	# physics_pos IS this frame's pre-move position.
	var position_before_move: Vector2 = previous_sample.physics_pos
	var slide_delta: Vector2 = sample.position_after_slide - position_before_move
	var snap_delta: Vector2 = sample.position_after_snap - sample.position_after_slide

	log_line("MEGA_DROP_FRAME world_x=%.3f  entered_from=%s  on_floor=%s  contacts=%d  contact_anomaly_len=%.4f  local_delta_len=%.4f  rotation=%.5f  rotation_delta=%.5f  contact_delta=(%.4f,%.4f)  local_delta=(%.4f,%.4f)  vel_before=(%.2f,%.2f)  vel_after=(%.2f,%.2f)  slide_delta=(%.4f,%.4f)  snap_delta=(%.4f,%.4f)  wall_gap_ms=%.3f" % [
		sample.physics_pos.x,
		current_mega_drop_entered_from,
		str(sample.has_contact),
		sample.all_contacts.size(),
		contact_anomaly.length(),
		local_delta.length(),
		sample.rotation, rotation_delta,
		contact_delta.x, contact_delta.y,
		local_delta.x, local_delta.y,
		sample.velocity_before_slide.x, sample.velocity_before_slide.y,
		sample.velocity_after_slide.x, sample.velocity_after_slide.y,
		slide_delta.x, slide_delta.y,
		snap_delta.x, snap_delta.y,
		wall_gap_ms,
	])


func format_candidate(candidate_index: int, candidate: ContactCandidate) -> String:
	return "[%d] pos=(%.3f,%.3f) normal=(%.5f,%.5f) match=%.6f" % [
		candidate_index, candidate.position.x, candidate.position.y,
		candidate.normal.x, candidate.normal.y, candidate.normal_match,
	]


func update_label(sample: Sample) -> void:
	var physics_delta: Vector2 = Vector2.ZERO
	var sprite_delta: Vector2 = Vector2.ZERO
	var contact_delta: Vector2 = Vector2.ZERO
	var camera_delta: Vector2 = Vector2.ZERO
	var rotation_delta: float = 0.0
	var contact_local_delta: Vector2 = Vector2.ZERO
	if previous_sample != null:
		physics_delta = sample.physics_pos - previous_sample.physics_pos
		sprite_delta = sample.sprite_pos - previous_sample.sprite_pos
		contact_delta = sample.contact_pos - previous_sample.contact_pos
		camera_delta = sample.camera_pos - previous_sample.camera_pos
		rotation_delta = sample.rotation - previous_sample.rotation
		contact_local_delta = sample.contact_local - previous_sample.contact_local
	label.text = (
		"physics  x=%.3f y=%.3f  d=(%.3f, %.3f)\n" % [sample.physics_pos.x, sample.physics_pos.y, physics_delta.x, physics_delta.y]
		+ "sprite   x=%.3f y=%.3f  d=(%.3f, %.3f)\n" % [sample.sprite_pos.x, sample.sprite_pos.y, sprite_delta.x, sprite_delta.y]
		+ "contact  x=%.3f y=%.3f  d=(%.3f, %.3f)  on_floor=%s\n" % [sample.contact_pos.x, sample.contact_pos.y, contact_delta.x, contact_delta.y, str(sample.has_contact)]
		+ "camera   x=%.3f y=%.3f  d=(%.3f, %.3f)\n" % [sample.camera_pos.x, sample.camera_pos.y, camera_delta.x, camera_delta.y]
		+ "rotation %.5f  d=%.5f\n" % [sample.rotation, rotation_delta]
		+ "contact_local(rel. to sprite, un-rotated)  x=%.3f y=%.3f  d=(%.3f, %.3f)\n" % [sample.contact_local.x, sample.contact_local.y, contact_local_delta.x, contact_local_delta.y]
		+ "segment  %s\n" % player.get_current_terrain_segment_label()
		+ "floor_normal=(%.5f,%.5f)\n" % [sample.floor_normal.x, sample.floor_normal.y]
		+ "slide_collisions=%d winner=%d\n" % [sample.all_contacts.size(), sample.winner_index]
		+ format_contact_list(sample)
	)


# One line per candidate: position, normal, and its dot-product match against
# floor_normal -- the exact quantity get_floor_collision_data()'s
# `normal_match > best_normal_match` tie-break (player.gd) compares. A 2-way
# near-tie reads as two match scores within float noise of each other.
func format_contact_list(sample: Sample) -> String:
	var lines: PackedStringArray = []
	for contact_index: int in range(sample.all_contacts.size()):
		var marker: String = "*" if contact_index == sample.winner_index else " "
		lines.append("  %s%s" % [marker, format_candidate(contact_index, sample.all_contacts[contact_index])])
	return "\n".join(lines)


func _on_overlay_draw() -> void:
	if history.is_empty():
		return
	draw_true_scale_markers()
	draw_inset_panel()


# Camera has no rotation and (per main.gd) tracks player.x exactly, so a
# viewport-center projection matches what the camera actually shows without
# needing the CanvasLayer's own (independent, identity) canvas transform.
func world_to_screen(world_pos: Vector2) -> Vector2:
	var viewport_size: Vector2 = overlay.get_viewport_rect().size
	return viewport_size * 0.5 + (world_pos - camera_2d.global_position) * camera_2d.zoom


func draw_true_scale_markers() -> void:
	var latest: Sample = history[history.size() - 1]
	for contact_index: int in range(latest.all_contacts.size()):
		if contact_index == latest.winner_index:
			continue
		overlay.draw_circle(world_to_screen(latest.all_contacts[contact_index].position), 3.0, Color(1.0, 0.6, 0.0, 0.4))
	draw_marker(world_to_screen(latest.physics_pos), Color.WHITE, "physics")
	draw_marker(world_to_screen(latest.sprite_pos), Color.CYAN, "sprite")
	draw_marker(world_to_screen(latest.contact_pos), Color.ORANGE, "contact")
	draw_marker(world_to_screen(latest.camera_pos), Color.MAGENTA, "camera")


func draw_marker(screen_pos: Vector2, color: Color, label_text: String) -> void:
	overlay.draw_circle(screen_pos, 4.0, color)
	overlay.draw_string(ThemeDB.fallback_font, screen_pos + Vector2(6, -6), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)


func draw_inset_panel() -> void:
	var viewport_size: Vector2 = overlay.get_viewport_rect().size
	var panel_origin: Vector2 = Vector2(viewport_size.x - INSET_SIZE.x - INSET_MARGIN, INSET_MARGIN)
	var panel_rect: Rect2 = Rect2(panel_origin, INSET_SIZE)
	var panel_center: Vector2 = panel_origin + INSET_SIZE * 0.5
	overlay.draw_rect(panel_rect, Color(0, 0, 0, 0.55), true)
	overlay.draw_rect(panel_rect, Color(1, 1, 1, 0.4), false, 1.0)
	overlay.draw_string(ThemeDB.fallback_font, panel_origin + Vector2(6, 14), "deviation from current physics pos, x%.0f" % zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

	# baseline_position is a slow EMA meant for tracking drift, not framing this
	# panel: on a level that scrolls at ~300-500px/s it steady-state-lags the
	# real position by roughly velocity/2, which at this zoom is thousands of
	# screen px -- enough to land outside the panel entirely (and, incidentally,
	# back inside the main view's own coordinate range). Re-center on this
	# frame's actual physics position instead, so the panel always shows recent
	# relative motion, not distance from a lagging anchor. This only changes
	# what's drawn, not baseline_position itself or anything it's used for
	# elsewhere (e.g. the numeric label).
	var latest: Sample = history[history.size() - 1]
	var anchor: Vector2 = latest.physics_pos

	draw_all_contacts_trail(panel_center, anchor, panel_rect)
	draw_trail(panel_center, anchor, panel_rect, func(sample: Sample) -> Vector2: return sample.physics_pos, Color.WHITE)
	draw_trail(panel_center, anchor, panel_rect, func(sample: Sample) -> Vector2: return sample.sprite_pos, Color.CYAN)
	draw_trail(panel_center, anchor, panel_rect, func(sample: Sample) -> Vector2: return sample.contact_pos, Color.ORANGE)
	draw_trail(panel_center, anchor, panel_rect, func(sample: Sample) -> Vector2: return sample.camera_pos, Color.MAGENTA)


# Every non-winning candidate contact, dim and unlabeled -- if the flicker is
# a near-tied choice between two fixed polyline points, this will show two
# stable clusters that the (bright orange, winner-only) contact trail jumps
# between, rather than one cluster with genuine spread.
func draw_all_contacts_trail(panel_center: Vector2, anchor: Vector2, panel_rect: Rect2) -> void:
	for sample in history:
		for contact_index: int in range(sample.all_contacts.size()):
			var deviation: Vector2 = sample.all_contacts[contact_index].position - anchor
			var inset_pos: Vector2 = panel_center + deviation * zoom
			if not panel_rect.has_point(inset_pos):
				continue
			var color: Color = Color(1.0, 0.6, 0.0, 0.5 if contact_index == sample.winner_index else 0.12)
			overlay.draw_circle(inset_pos, 1.5, color)


func draw_trail(panel_center: Vector2, anchor: Vector2, panel_rect: Rect2, extractor: Callable, color: Color) -> void:
	var point_count: int = history.size()
	for sample_index: int in range(point_count):
		var sample: Sample = history[sample_index]
		var deviation: Vector2 = (extractor.call(sample) as Vector2) - anchor
		var inset_pos: Vector2 = panel_center + deviation * zoom
		if not panel_rect.has_point(inset_pos):
			continue
		var age_fraction: float = float(sample_index) / maxf(float(point_count - 1), 1.0)
		var alpha: float = lerpf(0.15, 1.0, age_fraction)
		var radius: float = lerpf(1.5, 3.5, age_fraction)
		overlay.draw_circle(inset_pos, radius, Color(color.r, color.g, color.b, alpha))


func get_string_argument(argument_name: String, default_value: String) -> String:
	var prefix: String = argument_name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return default_value


func get_int_argument(argument_name: String, default_value: int) -> int:
	var raw_value: String = get_string_argument(argument_name, "")
	if raw_value.is_empty():
		return default_value
	return raw_value.to_int()


func get_float_argument(argument_name: String, default_value: float) -> float:
	var raw_value: String = get_string_argument(argument_name, "")
	if raw_value.is_empty():
		return default_value
	return raw_value.to_float()
