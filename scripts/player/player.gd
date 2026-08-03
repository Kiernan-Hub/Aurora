extends CharacterBody2D

class_name Player

signal died
signal debug_freeze_detected(session_seed: int)
signal debug_stall_recovered(session_seed: int, world_x: float)
signal debug_stuck_detected(session_seed: int, world_x: float)

const SPEED_MANAGER_SCRIPT: Script = preload("res://scripts/systems/speed_manager.gd")
const GRAVITY: float = 1600.0
const JUMP_VELOCITY: float = -640.0
const COYOTE_TIME_DURATION: float = 0.12
const JUMP_BUFFER_DURATION: float = 0.12
const FLOOR_SNAP_LENGTH: float = 18.0
const ROTATION_SMOOTHNESS: float = 12.0
const DEBUG_SLOPE_LOGGING: bool = false
# Fast enough to sweep the full INITIAL_SPEED..MAX_SPEED range in well under a
# second, since the point is skipping the ~62s automatic ramp during testing.
const MANUAL_SPEED_ADJUST_RATE: float = 300.0
# Consecutive stalled physics frames before the body is re-seated on the terrain
# height field. 4 frames is ~67ms: long enough that the known one-frame
# landing-depenetration false positive cannot trigger it, short enough that a
# recovery reads as a hitch rather than a dead run.
const STALL_RECOVERY_FRAME_THRESHOLD: int = 4
# Clearance above the sampled surface when re-seating, so the recovered body is not
# born inside the collision polyline. Floor snap (18px) pulls it back down.
const STALL_RECOVERY_CLEARANCE: float = 1.0
# "Stuck" here means near-zero NET progress over a real window, not a single frame
# reading exactly 0 -- catches jittering-in-place (small back-and-forth motion that
# never clears a hard freeze threshold) as well as a flat stall. 60 frames = ~1s.
const STUCK_WINDOW_FRAME_COUNT: int = 60
# Even on the steepest face this generator could produce back when mega_drop was
# enabled (~40.5 degrees) minimum forward speed (300 px/s) along-surface still
# advanced ~228 px/s in x; a legitimate slope has no reason to produce under 20px
# of net motion in a full second. mega_drop is disabled as of 2026-08-01 and the
# steepest slope is now 20.13 degrees, so this threshold has MORE headroom than
# when it was chosen, not less -- it stays valid either way, and stays correct if
# mega_drop is ever restored.
const STUCK_NET_PROGRESS_THRESHOLD: float = 20.0

@export var DEBUG_ALLOW_MANUAL_SPEED_CONTROL: bool = true
@export var DEBUG_SHOW_PLAYER_STATE: bool = true
@export var DEBUG_LOG_FREEZE_REPRO: bool = true
@export_range(10, 20, 1) var DEBUG_FREEZE_HISTORY_FRAME_COUNT: int = 20

@onready var color_rect: ColorRect = $ColorRect
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var terrain_generator: TerrainGenerator = get_node_or_null("../TerrainGenerator") as TerrainGenerator

var speed_manager: RefCounted
var is_dead: bool = false
# Powerup boost: ground-locked speed override driven externally by
# PowerupManager (start_boost/end_boost). Deliberately not part of
# SpeedManager -- the boost speed exceeds SpeedManager.MAX_SPEED and jump is
# disabled for the duration, both of which are player-state concerns, not
# ramp-state concerns.
var is_boosting: bool = false
var boost_speed: float = 0.0
# Powerup jump boost: multiplies JUMP_VELOCITY's magnitude. Independent of
# is_boosting/boost_speed -- the two powerups can be active at once and don't
# interact (a boosted jump would be a contradiction of "no airtime" anyway, but
# nothing currently prevents picking up a jump ball mid speed-boost).
var jump_boost_multiplier: float = 1.0
var debug_rotation_timer: float = 0.0
var airborne_rotation: float = 0.0
var was_grounded_last_frame: bool = false
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var debug_state_label: Label
var last_physics_displacement: Vector2 = Vector2.ZERO
var debug_physics_frame: int = 0
var debug_freeze_event_count: int = 0
var debug_freeze_reported: bool = false
var debug_frame_history: Array[String] = []
var capsule_half_height: float = 24.0
var stalled_frame_count: int = 0
var debug_stall_recovery_count: int = 0
var stuck_motion_x_window: Array[float] = []
var stuck_event_reported: bool = false
var debug_stuck_event_count: int = 0
# Which of the two velocity models ran this frame. Stored rather than re-derived:
# apply_grounded_floor_snap() needs it after move_and_slide(), and an external probe
# cannot reconstruct the choice from post-move state, because move_and_slide()
# rewrites velocity on any grounded frame that found a contact.
var is_using_grounded_model: bool = false
# True from a jump impulse until the apex. Replaces reading `velocity.y < 0.0` as a
# proxy for "ascending", which an uphill surface tangent also satisfies.
var is_jump_ascending: bool = false
var debug_forced_floor_snap_count: int = 0
var debug_forced_floor_snap_max_y: float = 0.0
var debug_forced_floor_snap_last_y: float = 0.0
# Read-only instrumentation (2026-07-30) for the residual sub-pixel bounce
# investigation. No behavior depends on these -- they only record where the body was
# immediately after move_and_slide() and again after apply_grounded_floor_snap(), so
# an external probe can split each frame's vertical motion into its slide-resolution
# component and its snap-correction component instead of only seeing the combined
# total (last_physics_displacement). Do not read these to make gameplay decisions.
var debug_position_after_slide: Vector2 = Vector2.ZERO
var debug_position_after_snap: Vector2 = Vector2.ZERO
# Same rationale, added (2026-07-30) for the "why does move_and_slide()'s contact
# report flicker" follow-up: velocity immediately before and after move_and_slide(),
# since move_and_slide() can rewrite velocity (sliding response) and an external
# probe otherwise only sees the value already overwritten by the NEXT frame's model.
var debug_velocity_before_slide: Vector2 = Vector2.ZERO
var debug_velocity_after_slide: Vector2 = Vector2.ZERO

const DEBUG_FREEZE_MIN_VELOCITY_X: float = 1.0
const DEBUG_FREEZE_MAX_MOTION_X: float = 0.01


func _ready() -> void:
	if not is_in_group("player"):
		add_to_group("player")
	speed_manager = SPEED_MANAGER_SCRIPT.new() as RefCounted
	capsule_half_height = get_capsule_half_height()
	floor_snap_length = FLOOR_SNAP_LENGTH
	floor_stop_on_slope = false
	floor_constant_speed = true
	velocity = Vector2(speed_manager.current_speed, 0.0)
	color_rect.color = Color(0.85, 0.93, 1.0)
	color_rect.pivot_offset = color_rect.size * 0.5
	airborne_rotation = color_rect.rotation
	if terrain_generator == null:
		push_error("Player requires a TerrainGenerator sibling.")
	setup_debug_state_label()


# Jump entry point for input paths that can't go through the "ui_accept" action.
# Touch on Android is one: measured on device (2026-08-02), a tap's action state
# never produced a just_pressed edge inside _physics_process, so the poll below
# can't see it. Setting the buffer directly reuses the exact same coyote/buffer
# gate a keyboard jump uses -- only the delivery differs.
func buffer_jump() -> void:
	jump_buffer_timer = JUMP_BUFFER_DURATION


func _physics_process(delta: float) -> void:
	speed_manager.update(delta)
	if DEBUG_ALLOW_MANUAL_SPEED_CONTROL:
		apply_manual_speed_input(delta)

	if is_on_floor():
		coyote_timer = COYOTE_TIME_DURATION
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("ui_accept"):
		jump_buffer_timer = JUMP_BUFFER_DURATION
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	if not is_boosting and coyote_timer > 0.0 and jump_buffer_timer > 0.0:
		velocity.y = JUMP_VELOCITY * jump_boost_multiplier
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		is_jump_ascending = true
	elif is_jump_ascending and velocity.y >= 0.0:
		# Apex: past here the jump is an ordinary fall, so a floor contact means a
		# landing and the grounded model may take over again.
		is_jump_ascending = false

	# The gate is "on the floor and not climbing out of a jump", NOT the former
	# `velocity.y >= 0.0`. That test was trying to let a jump escape the grounded
	# model, but it also caught every rising frame, because the grounded model's own
	# velocity is the surface tangent and an uphill tangent points up. Measured before
	# this changed: on gentle_uphill 76% of frames where the body was genuinely on the
	# floor ran the airborne gravity model instead of following the surface.
	# is_boosting forces the grounded model even off a small bump: jump input is
	# already suppressed above, and apply_grounded_floor_snap() below is relaxed to
	# pull the body back down regardless of velocity.y while boosting, so this is the
	# only other place "no airtime during a boost" needs to be enforced.
	is_using_grounded_model = is_boosting or (is_on_floor() and not is_jump_ascending)
	var current_speed: float = boost_speed if is_boosting else speed_manager.current_speed
	if is_using_grounded_model:
		var slope_tangent: Vector2 = get_slope_tangent()
		velocity = slope_tangent * current_speed
	else:
		velocity.x = current_speed
		velocity.y += GRAVITY * delta

	var position_before_move: Vector2 = global_position
	debug_velocity_before_slide = velocity
	move_and_slide()
	debug_position_after_slide = global_position
	debug_velocity_after_slide = velocity
	apply_grounded_floor_snap()
	debug_position_after_snap = global_position
	# Measured after the snap deliberately: the snap is part of this frame's motion,
	# and the stall/stuck watchdogs downstream must see where the body actually ended.
	last_physics_displacement = global_position - position_before_move
	update_stall_recovery(delta)
	update_stuck_detection(delta)
	if TerrainGenerator.DEBUG_TERRAIN_LOGGING or DEBUG_SLOPE_LOGGING:
		var slide_collision_count: int = get_slide_collision_count()
		print("slide_collision_count=", slide_collision_count)
		if slide_collision_count > 0:
			for collision_index: int in range(slide_collision_count):
				var collision: KinematicCollision2D = get_slide_collision(collision_index)
				print("slide_collision[", collision_index, "] collider=", collision.get_collider().name, " normal=", collision.get_normal(), " position=", collision.get_position())
	update_visual_rotation(delta)
	update_debug_state_label()
	record_freeze_repro_frame()


func update_visual_rotation(delta: float) -> void:
	if terrain_generator == null:
		return

	var is_grounded: bool = is_on_floor()
	var logged_target_angle: float = color_rect.rotation
	if is_grounded:
		var terrain_angle: float = terrain_generator.get_slope_angle_at_x(global_position.x)
		# This exponential response is always in [0, 1), unlike smoothness * delta.
		# Clamp it to the current target's side of upright so a rapidly reversing
		# slope cannot leave the sprite tilted farther than the sampled terrain.
		var interpolation_weight: float = 1.0 - exp(-ROTATION_SMOOTHNESS * delta)
		var smoothed_rotation: float = lerp_angle(color_rect.rotation, terrain_angle, interpolation_weight)
		if terrain_angle >= 0.0:
			color_rect.rotation = clampf(smoothed_rotation, 0.0, terrain_angle)
		else:
			color_rect.rotation = clampf(smoothed_rotation, terrain_angle, 0.0)
		airborne_rotation = color_rect.rotation
		logged_target_angle = terrain_angle
	elif was_grounded_last_frame:
		airborne_rotation = color_rect.rotation

	if not is_grounded:
		color_rect.rotation = airborne_rotation

	if DEBUG_SLOPE_LOGGING:
		debug_rotation_timer += delta
		if debug_rotation_timer >= 0.5:
			debug_rotation_timer = 0.0
			print("player x=", global_position.x, " target_angle=", logged_target_angle, " rotation=", color_rect.rotation, " grounded=", is_grounded, " velocity=", velocity)

	was_grounded_last_frame = is_grounded


func apply_manual_speed_input(delta: float) -> void:
	if Input.is_action_pressed("ui_up"):
		speed_manager.apply_manual_adjustment(MANUAL_SPEED_ADJUST_RATE * delta)
	if Input.is_action_pressed("ui_down"):
		speed_manager.apply_manual_adjustment(-MANUAL_SPEED_ADJUST_RATE * delta)


func get_slope_tangent() -> Vector2:
	if terrain_generator == null:
		return Vector2.RIGHT
	# Aimed along the actual collision chord underfoot (get_collision_chord_slope_angle),
	# not the continuous height field's +/-2px analytic tangent: the two can disagree
	# by a couple of degrees on curved terrain since the physical collision surface is
	# a 16px-ish polyline, not the exact field, and driving velocity along an angle
	# that doesn't match the surface the body is actually sliding on injects spurious
	# vertical velocity every chord -- a source of jitter distinct from the
	# now-fixed float32 freeze bug. atan2's dx argument is always positive (chord
	# samples are ordered left-to-right), so cos(terrain_angle) is always > 0 — no
	# sign flip needed.
	#
	# Deliberately NOT damped over time (measured, 2026-07-29): exponentially smoothing
	# this angle the way update_visual_rotation() smooths the sprite makes contact
	# WORSE, because on a piecewise-linear floor the correct heading IS the current
	# chord's heading -- lagging it aims the body into the floor on concave stretches
	# and off it on convex ones. A/B over 9000 frames of seed 941462462: mean
	# surface-gap wobble 0.210px -> 0.270px, vertical-velocity reversals 4.09% ->
	# 7.43% of grounded frames, and ~20% more time airborne. Smoothing is correct for
	# the cosmetic sprite angle and wrong for the vector that determines contact.
	#
	# ALSO TRIED (2026-07-30) and reverted, do not retry without new evidence: aiming
	# along the chord spanning the step's endpoints (global_position.x to
	# +speed*delta) instead of a single start-sampled tangent, on the theory that a
	# curved-terrain step ends off the sampled surface and gets caught by floor
	# snapping. Measured (scripts/debug/chord_aim_probe.gd, seed 941462462, 9000
	# frames): no clear improvement -- medium_hill/medium_valley residual dropped
	# ~4-10%, small_hill rose ~9%, and the no-contact-frame fraction the fix targeted
	# was unchanged (0.361 vs 0.366 on medium_hill). The mechanism this comment
	# describes for the residual bounce remains correct per the investigation; this
	# particular fix for it does not work.
	# ALSO TRIED (2026-07-30) and reverted, do not retry without new evidence: aiming
	# along the ACTUAL last-reported contact direction (get_floor_normal(), resolved
	# by the PREVIOUS frame's move_and_slide()) instead of this analytic chord angle,
	# to A/B test whether the residual bounce is triggered by this function's own
	# tangent choice diverging from Godot's contact model. Measured (chord_aim_probe.gd
	# + contact_instability_probe.gd, 4 seeds, 9000/3500 frames): residual got WORSE
	# on every segment, including the near-constant-slope sustained_downhill control
	# (0.147px mean -> 0.218px, +48%; medium_hill 0.357px -> 0.433px, +21%), while the
	# slide_collision_count flip rate that drives it was essentially unchanged (67-73%
	# of high-residual frames before vs 71-81% after). get_floor_normal() reflects the
	# PREVIOUS frame's resolved contact, one frame stale on continuously-curving
	# terrain -- the same lag mechanism the 2026-07-29 temporal-smoothing experiment
	# above was reverted for. Confirms the residual is not caused by (and is not fixed
	# by chasing) any particular tangent choice; it is closer to inherent per-frame
	# solver behavior on curved terrain than to a tangent-selection bug.
	var terrain_angle: float = terrain_generator.get_collision_chord_slope_angle(global_position.x)
	return Vector2(cos(terrain_angle), sin(terrain_angle))


# Closes the sub-pixel gap that Godot declines to close itself. CharacterBody2D's
# own floor snapping early-returns whenever the velocity faces up_direction
# (_snap_on_floor -> vel_dir_facing_up), and on this terrain that is every rising
# frame, since the grounded model aims velocity along the surface. The step is then
# tangential, move_and_slide() reports no contact at all (slide_collision_count == 0),
# and nothing re-seats the body: is_on_floor() goes false while the capsule sits
# ~0.4px off the terrain, and the next frame runs the gravity model to fall that
# 0.4px back down. That two-frame cycle was the measured is_on_floor() flicker --
# ~60% of gentle_uphill frames, ~36% of all rising frames, against <1% on falling
# ground. The body never actually left the surface; only the engine's floor
# bookkeeping did. apply_floor_snap() has no velocity gate.
#
# Deliberately scoped to exactly the suppressed case. When velocity faces down,
# Godot's stock snapping already runs and this must not second-guess it -- and note
# that stock snapping glues the body over the same FLOOR_SNAP_LENGTH in that
# direction, so this cannot cancel airtime the engine would otherwise have granted.
#
# While boosting, the velocity.y gate is dropped entirely: a boost is meant to be
# ground-locked with zero airtime, including the brief upward hop a bump can impart,
# not just the tangential-velocity case this function was originally written for.
func apply_grounded_floor_snap() -> void:
	if not is_using_grounded_model or is_on_floor():
		return
	if not is_boosting and velocity.y >= 0.0:
		return

	var snap_start_y: float = global_position.y
	apply_floor_snap()
	if not is_on_floor():
		return

	debug_forced_floor_snap_count += 1
	debug_forced_floor_snap_last_y = absf(global_position.y - snap_start_y)
	debug_forced_floor_snap_max_y = maxf(debug_forced_floor_snap_max_y, debug_forced_floor_snap_last_y)


func get_capsule_half_height() -> float:
	var capsule: CapsuleShape2D = collision_shape.shape as CapsuleShape2D
	if capsule == null:
		push_error("Player requires a CapsuleShape2D on CollisionShape2D.")
		return capsule_half_height
	return capsule.height * 0.5


# The stall the whole freeze investigation is about: grounded, still being driven
# forward, but going nowhere. Shared by the recovery watchdog and the freeze logger
# so the two can never disagree about what a stall is.
func is_stalled_this_frame() -> bool:
	return (
		is_on_floor()
		and absf(velocity.x) >= DEBUG_FREEZE_MIN_VELOCITY_X
		and absf(last_physics_displacement.x) <= DEBUG_FREEZE_MAX_MOTION_X
	)


func update_stall_recovery(delta: float) -> void:
	if not is_stalled_this_frame():
		stalled_frame_count = 0
		return

	stalled_frame_count += 1
	if stalled_frame_count >= STALL_RECOVERY_FRAME_THRESHOLD:
		recover_from_stall(delta)


# Last-resort unwedge. The collision polyline is a discretisation that the physics
# solver can occasionally produce a nonsense contact normal for; the height field it
# was sampled from is exact, so re-seat the body on that instead and let normal
# physics resume. No terrain in this generator presents an uphill face steeper than
# ~34 degrees, so a sustained grounded stall is always a bug, never level geometry.
#
# Deliberately loud: the regression harness asserts debug_stall_recovery_count == 0,
# so this can never quietly paper over a real regression.
func recover_from_stall(delta: float) -> void:
	stalled_frame_count = 0
	debug_stall_recovery_count += 1
	if terrain_generator == null:
		return

	var recovered_x: float = global_position.x + (speed_manager.current_speed * delta)
	var surface_world_y: float = terrain_generator.get_surface_world_y(recovered_x)
	global_position = Vector2(recovered_x, surface_world_y - capsule_half_height - STALL_RECOVERY_CLEARANCE)
	velocity = get_slope_tangent() * speed_manager.current_speed
	print("STALL_RECOVERY seed=", get_terrain_session_seed(), " world_x=", recovered_x, " count=", debug_stall_recovery_count)
	debug_stall_recovered.emit(get_terrain_session_seed(), recovered_x)


# Broader than is_stalled_this_frame(), and the reason that predicate alone is not
# enough: a jittering stall (small back-and-forth motion) never strings together
# STALL_RECOVERY_FRAME_THRESHOLD consecutive near-zero frames, so the per-frame
# watchdog never fires while the player is nonetheless going nowhere. Measured at
# seed 222894852 / world_x 1,166,358: 600 frames, net progress 1.6px, recoveries 0.
# This catches it on NET progress instead, and recovers through the same path.
func update_stuck_detection(delta: float) -> void:
	stuck_motion_x_window.append(last_physics_displacement.x)
	if stuck_motion_x_window.size() > STUCK_WINDOW_FRAME_COUNT:
		stuck_motion_x_window.pop_front()
	if stuck_motion_x_window.size() < STUCK_WINDOW_FRAME_COUNT:
		return

	var net_progress: float = 0.0
	for windowed_motion_x: float in stuck_motion_x_window:
		net_progress += windowed_motion_x

	if not (is_on_floor() and net_progress < STUCK_NET_PROGRESS_THRESHOLD):
		stuck_event_reported = false
		return

	if stuck_event_reported:
		return

	stuck_event_reported = true
	debug_stuck_event_count += 1
	print("STUCK_DETECTED seed=", get_terrain_session_seed(), " world_x=%.3f" % global_position.x, " event=", debug_stuck_event_count, " net_progress_over_%d_frames=%.3f" % [STUCK_WINDOW_FRAME_COUNT, net_progress])
	debug_stuck_detected.emit(get_terrain_session_seed(), global_position.x)
	recover_from_stall(delta)
	# Clearing the window both resets the measurement against fresh post-recovery
	# data and acts as a ~1s cooldown, so a location that re-sticks gets rescued
	# repeatedly rather than once.
	stuck_motion_x_window.clear()
	stuck_event_reported = false


func setup_debug_state_label() -> void:
	if not DEBUG_SHOW_PLAYER_STATE:
		return

	var canvas_layer: CanvasLayer = get_node_or_null("../CanvasLayer") as CanvasLayer
	if canvas_layer == null:
		push_error("Player debug overlay requires a CanvasLayer sibling.")
		return

	debug_state_label = Label.new()
	debug_state_label.name = "PlayerStateDebugLabel"
	debug_state_label.offset_left = 8.0
	debug_state_label.offset_top = 8.0
	debug_state_label.offset_right = 360.0
	debug_state_label.offset_bottom = 120.0
	debug_state_label.add_theme_font_size_override("font_size", 12)
	canvas_layer.add_child(debug_state_label)


func update_debug_state_label() -> void:
	if debug_state_label == null:
		return

	var grounded: bool = is_on_floor()
	var floor_normal_text: String = "none"
	if grounded:
		floor_normal_text = str(get_floor_normal())
	var slide_collision_count: int = get_slide_collision_count()

	debug_state_label.text = (
		"velocity.x: %.3f\n" % velocity.x
		+ "velocity.y: %.3f\n" % velocity.y
		+ "motion.x: %.3f\n" % last_physics_displacement.x
		+ "is_on_floor: %s\n" % str(grounded)
		+ "floor_normal: %s\n" % floor_normal_text
		+ "world_x: %.3f\n" % global_position.x
		+ "segment: %s" % get_current_terrain_segment_label()
		+ "\nsession_seed: %d" % get_terrain_session_seed()
		+ "\nslide_collisions: %d" % slide_collision_count
		+ "\nfloor_collision: %s" % get_floor_collision_text(floor_normal_text)
	)


func get_current_terrain_segment_label() -> String:
	return get_terrain_segment_label_at_x(global_position.x)


func get_terrain_segment_label_at_x(world_x: float) -> String:
	if terrain_generator == null:
		return "unknown"

	terrain_generator.ensure_segment_cache_for_world_x(world_x)
	var segment_index: int = terrain_generator.find_segment_index_at_x(world_x)
	return terrain_generator.get_segment_selection_label(segment_index)


func get_terrain_session_seed() -> int:
	if terrain_generator == null:
		return 0
	return terrain_generator.get_session_seed()


func get_floor_collision_text(floor_normal_text: String) -> String:
	var floor_collision: Dictionary = get_floor_collision_data()
	if floor_collision.is_empty():
		return "none"

	var collision_position: Vector2 = floor_collision["position"]
	return "x: %.3f, normal: %s, chunk: %d, segment: %s" % [
		collision_position.x,
		str(floor_collision["normal"]),
		floor_collision["chunk_index"],
		floor_collision["segment_label"],
	]


func get_floor_collision_data() -> Dictionary:
	var floor_collision_data: Dictionary = {}
	if not is_on_floor() or get_slide_collision_count() == 0:
		return floor_collision_data

	var floor_normal: Vector2 = get_floor_normal()
	var best_floor_collision: KinematicCollision2D
	var best_normal_match: float = -1.0
	for collision_index: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(collision_index)
		var normal_match: float = collision.get_normal().dot(floor_normal)
		if normal_match > best_normal_match:
			best_floor_collision = collision
			best_normal_match = normal_match

	if best_floor_collision == null:
		return floor_collision_data

	var collision_position: Vector2 = best_floor_collision.get_position()
	var collision_normal: Vector2 = best_floor_collision.get_normal()
	floor_collision_data["position"] = collision_position
	floor_collision_data["normal"] = collision_normal
	floor_collision_data["chunk_index"] = get_terrain_chunk_index_at_x(collision_position.x)
	floor_collision_data["segment_label"] = get_terrain_segment_label_at_x(collision_position.x)
	return floor_collision_data


func get_terrain_chunk_index_at_x(world_x: float) -> int:
	if terrain_generator == null:
		return 0
	return floori(world_x / terrain_generator.chunk_width)


func record_freeze_repro_frame() -> void:
	if not DEBUG_LOG_FREEZE_REPRO:
		return

	debug_physics_frame += 1
	var grounded: bool = is_on_floor()
	var floor_normal_text: String = "none"
	if grounded:
		floor_normal_text = str(get_floor_normal())
	var floor_collision: Dictionary = get_floor_collision_data()
	var floor_collision_text: String = "none"
	if not floor_collision.is_empty():
		var collision_position: Vector2 = floor_collision["position"]
		floor_collision_text = "point=(%.3f, %.3f) normal=%s chunk=%d segment=%s" % [
			collision_position.x,
			collision_position.y,
			str(floor_collision["normal"]),
			floor_collision["chunk_index"],
			floor_collision["segment_label"],
		]

	var frame_record: String = "frame=%d world_x=%.3f velocity_x=%.3f motion_x=%.6f on_floor=%s floor_normal=%s slide_collisions=%d floor_collision=%s" % [
		debug_physics_frame,
		global_position.x,
		velocity.x,
		last_physics_displacement.x,
		str(grounded),
		floor_normal_text,
		get_slide_collision_count(),
		floor_collision_text,
	]
	debug_frame_history.append(frame_record)
	var history_limit: int = maxi(DEBUG_FREEZE_HISTORY_FRAME_COUNT, 1)
	if debug_frame_history.size() > history_limit:
		debug_frame_history.pop_front()

	var freeze_detected: bool = is_stalled_this_frame()
	if freeze_detected and not debug_freeze_reported:
		debug_freeze_reported = true
		debug_freeze_event_count += 1
		print("FREEZE_REPRO seed=", get_terrain_session_seed(), " event=", debug_freeze_event_count)
		for history_record: String in debug_frame_history:
			print("FREEZE_REPRO ", history_record)
		debug_freeze_detected.emit(get_terrain_session_seed())
	elif not freeze_detected:
		debug_freeze_reported = false


func start_jump_boost(new_jump_boost_multiplier: float) -> void:
	jump_boost_multiplier = new_jump_boost_multiplier


func end_jump_boost() -> void:
	jump_boost_multiplier = 1.0


func start_boost(new_boost_speed: float) -> void:
	is_boosting = true
	boost_speed = new_boost_speed
	# Clear any in-flight jump state so a boost that starts mid-air/mid-jump snaps
	# straight into the ground-locked grounded model next frame instead of finishing
	# the jump arc first.
	is_jump_ascending = false
	coyote_timer = 0.0
	jump_buffer_timer = 0.0


func end_boost() -> void:
	is_boosting = false


func die() -> void:
	if is_dead:
		return

	is_dead = true
	died.emit()
