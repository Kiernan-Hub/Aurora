extends CharacterBody2D

class_name Player

signal died
signal jumped
# Emitted on the is_on_floor() false->true edge only -- see was_on_floor below.
signal landed
# Emitted when a held shield absorbs an obstacle hit instead of dying. PowerupManager
# listens so it can clear its own bookkeeping without owning has_shield itself.
signal shield_consumed
signal debug_freeze_detected(session_seed: int)
signal debug_stall_recovered(session_seed: int, world_x: float)
signal debug_stuck_detected(session_seed: int, world_x: float)
# Purely cosmetic: emitted once per landing, and only when at least one full spin
# completed in the air. GameManager scores it; nothing here reads a physics surface.
signal trick_completed(spin_count: int)

const SPEED_MANAGER_SCRIPT: Script = preload("res://scripts/systems/speed_manager.gd")
const GRAVITY: float = 1600.0
const JUMP_VELOCITY: float = -640.0
const COYOTE_TIME_DURATION: float = 0.12
const JUMP_BUFFER_DURATION: float = 0.12
const FLOOR_SNAP_LENGTH: float = 18.0
const ROTATION_SMOOTHNESS: float = 12.0
const DEBUG_SLOPE_LOGGING: bool = false
# No-tint modulate: animated_sprite shows its real art. PLAYER_SHIELD_COLOR below is
# the only actual tint, applied as a modulate multiply while has_shield is true.
const PLAYER_DEFAULT_COLOR: Color = Color(1.0, 1.0, 1.0)
const PLAYER_SHIELD_COLOR: Color = Color(0.4, 0.85, 1.0)
# Purely cosmetic scale punch on animated_sprite, eased back to sprite_base_scale by
# play_squash_stretch(). Jump reads as a stretch (thin/tall), landing as a squash
# (wide/short) -- same trick, opposite axis bias. Values are multipliers of
# sprite_base_scale, not absolute scale.
const JUMP_STRETCH_SCALE: Vector2 = Vector2(0.72, 1.35)
const LAND_SQUASH_SCALE: Vector2 = Vector2(1.35, 0.72)
const SQUASH_STRETCH_DURATION: float = 0.28
# Glide lives entirely in the airborne (gravity) branch of _physics_process -- see the
# LOAD-BEARING FOR CHASMS note below. is_using_grounded_model is never touched by it, so a
# boosting player is unaffected and the chasm contract can't move by construction.
# Real acceleration, not an eased target speed: GRAVITY always applies, exactly like an
# ordinary fall, and holding ADDS a stronger opposing acceleration on top of it. That is
# what makes deceleration, crossing zero, and climbing read as one continuous physical
# motion instead of three special-cased states -- and it means "don't touch anything"
# free-falls with the same accelerating feel as a normal jump's descent, not a slow float.
# Net accel while held: GLIDE_THRUST_ACCELERATION - GRAVITY = 1200 px/s^2 upward.
const GLIDE_THRUST_ACCELERATION: float = 2800.0
const GLIDE_MAX_RISE_SPEED: float = -600.0
const GLIDE_MAX_FALL_SPEED: float = 550.0
# Liftoff impulse when a grounded pickup starts a glide (see start_glide()). Still gentler
# than JUMP_VELOCITY (-640) -- the glide takeoff is not a jump and shouldn't read as one --
# but strong enough to clear a noticeably higher hop than the original -350 before the
# hold/thrust math takes over.
const GLIDE_LAUNCH_VELOCITY: float = -480.0
# Airborne trick spin (Phase 4): spins animated_sprite only, same as the rest of
# update_visual_rotation -- collision_shape is never touched, so this has zero physics
# surface. Shares is_glide_input_held() rather than a separate poll: hold means glide
# while a glide effect is active and spin otherwise, one input, resolved where the two
# branches meet in update_visual_rotation().
#
# Rate is tuned against real airtime, not picked for feel: a period of 0.9s (400 deg/s)
# sits just above a flat grounded jump's airtime (2*JUMP_VELOCITY/GRAVITY = 0.8s, 0
# flips) and just under a hill-into-valley jump's (0.95-0.99s at SMALL/MEDIUM_HILL_
# AMPLITUDE, 1 flip). The old TAU*1.5 (0.67s/spin) landed inside the flat-jump window,
# which is why every ordinary jump could complete one -- that was the bug, not a taste
# choice. A clean 2nd flip would need ~1.6s+ of airtime; the tallest reachable combo
# today (jump_boost powerup off a medium hill into a medium valley) only reaches
# ~1.28s, so two flips stays a near-miss (~1.4 spins) rather than a guarantee. Hill/
# valley amplitude was deliberately NOT raised to close that gap -- SMALL_HILL_AMPLITUDE
# and MEDIUM_HILL_AMPLITUDE already sit right at the ~20.13deg slope this project
# proved is the rideable ceiling (three failed steep-terrain attempts, see CLAUDE.md);
# closing it would need a 5-10x amplitude increase, well past that.
const TRICK_SPIN_PERIOD: float = 0.9
const TRICK_SPIN_RATE: float = TAU / TRICK_SPIN_PERIOD
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
# How far below the terrain height field the body must fall to die in a chasm.
#
# 200px is ~0.5s of fall. The player is ALWAYS above the surface on real ground -- a jump arcs
# over it, and the grounded model pins them to it -- so the only thing this has to clear is
# landing depenetration, which is sub-pixel. 200 is ~200x that, and there is no terminal
# velocity in this project, so a deeper threshold only costs responsiveness.
#
# Why not deeper: at MAX_SPEED the player crosses a 220px void in 0.29s having fallen only
# ~69px, so the death always registers somewhere PAST the far lip, with the body descending
# behind the terrain fill (TerrainGenerator draws after Player, so it reads as falling into the
# hole and vanishing). A 360px threshold pushed that to 0.67s and ~310px past the lip, which is
# a noticeably late death screen for no benefit. Measured with chasm_probe.gd.
const FALL_DEATH_DEPTH: float = 200.0

# Debug instrumentation, OFF in exported release builds and ON everywhere a developer
# or a probe runs (editor play, --headless --script, debug export templates).
#
# These were plain `= true` @exports until 2026-08-03, which meant the shipping APK ran
# the full probe rig every physics frame: update_debug_state_label() and
# record_freeze_repro_frame() each do a get_floor_collision_data() pass and a terrain
# segment lookup, and between them allocate ~25 transient Strings -- roughly 3,600
# refcounted heap allocations per second that nobody in a shipped build will ever read.
# DEBUG_ALLOW_MANUAL_SPEED_CONTROL shipping true also left the arrow keys as a live
# speed cheat on any desktop build.
#
# Deriving from OS.is_debug_build() rather than hardcoding false keeps every headless
# gate working untouched (they run on the editor binary, which is a debug build) while
# making it impossible to ship the instrumentation by forgetting to flip a flag.
#
# Deliberately NOT @export anymore, matching Main.world_rebase_enabled and
# GameManager.require_start_screen: an @export is exactly what main.tscn silently
# serialised to reintroduce the freeze bug for weeks, and these four now control whether
# the game does thousands of allocations per second. Probes still set them directly in
# code, which works the same on a plain var.
var DEBUG_ALLOW_MANUAL_SPEED_CONTROL: bool = OS.is_debug_build()
var DEBUG_SHOW_PLAYER_STATE: bool = OS.is_debug_build()
var DEBUG_LOG_FREEZE_REPRO: bool = OS.is_debug_build()
var DEBUG_FREEZE_HISTORY_FRAME_COUNT: int = 20

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var flight_trail: FlightTrail = $FlightTrail
@onready var terrain_generator: TerrainGenerator = get_node_or_null("../TerrainGenerator") as TerrainGenerator
# For is_glide_input_held(): touch has no "ui_accept" action edge to poll (see Main's
# _input comment), so held-state has to come from Main's own touch tracking.
@onready var main_node: Main = get_node_or_null("..") as Main

var speed_manager: RefCounted
var is_dead: bool = false
# One-hit shield: consumed by absorb_hit(), never timed. update_fall_death() and both
# stall/stuck watchdogs must stay untouched by this -- a shield that swallowed fall-death
# would leave the player sliding forever below the world with no recovery, which is worse
# than the death it prevented. Obstacle collisions only.
var has_shield: bool = false
# Timed effect, driven entirely by PowerupManager.start_glide()/end_glide(); see the
# airborne branch of _physics_process for what it actually does.
var is_glide_active: bool = false
# Latches on with the glide and stays on for the rest of the airborne arc, same pattern
# as Main's is_glide_vertical_follow_active -- the effect (and therefore is_glide_active)
# can end mid-air, well before landing. Grants a short obstacle-only shield on touchdown
# so removing GLIDE_MAX_ALTITUDE (flight can go off-screen from the ground) doesn't turn
# every landing into a blind coin-flip.
var is_glide_landing_shield_pending: bool = false
# Only ticks while true, so a shield actually EARNED via a shield powerup mid-flight is
# never clipped by this timer -- absorb_hit() clears it same as it clears has_shield.
var is_shield_from_glide_landing: bool = false
var glide_landing_shield_timer: float = 0.0
const GLIDE_LANDING_SHIELD_DURATION: float = 1.0
# Powerup boost: ground-locked speed override driven externally by
# PowerupManager (start_boost/end_boost). Deliberately not part of
# SpeedManager -- the boost speed exceeds SpeedManager.MAX_SPEED and jump is
# disabled for the duration, both of which are player-state concerns, not
# ramp-state concerns.
var is_boosting: bool = false
var boost_speed: float = 0.0
# Set piece input lock, driven externally by FrozenLakeDirector while the player crosses
# the frozen lake. The player keeps auto-running; every input they could give is ignored.
#
# A SEPARATE BOOL RATHER THAN REUSING is_boosting, which already means "jump suppressed"
# and would have been the obvious reuse. It is not, because is_boosting does a second
# thing: it forces the grounded, gravity-free velocity model (see the branch marked
# LOAD-BEARING FOR CHASMS below). Borrowing it for the lake would hand the lake that
# gravity override too, so a player who entered airborne would sail flat across the lake
# instead of landing on it.
#
# Deliberately does NOT touch get_tree().paused: the game is still PLAYING during the
# lake, and GameManager.set_state() is the project's only owner of paused-ness.
var is_jump_suppressed: bool = false
# Powerup jump boost: multiplies JUMP_VELOCITY's magnitude. Independent of
# is_boosting/boost_speed -- the two powerups can be active at once and don't
# interact (a boosted jump would be a contradiction of "no airtime" anyway, but
# nothing currently prevents picking up a jump ball mid speed-boost).
var jump_boost_multiplier: float = 1.0
# Persistent meta-progression jump multiplier, set once per run by
# GameManager.apply_upgrades() from the save file. SEPARATE from jump_boost_multiplier
# on purpose: end_jump_boost() resets that one to 1.0 ABSOLUTELY, so sharing the var
# would silently wipe a purchased upgrade the moment a jump powerup expired. The two
# compose multiplicatively at the jump site.
#
# Defaults to 1.0, which is the fully-upgraded value and therefore today's physics
# exactly. That default is what every --headless --script probe measures:
# GameManager.apply_upgrades() deliberately skips headless runs, so no gate can be
# perturbed by whatever is in the developer's own save.dat. See the comment there.
var upgrade_jump_multiplier: float = 1.0
var debug_rotation_timer: float = 0.0
var airborne_rotation: float = 0.0
# Reset every time a new airborne arc begins (see update_visual_rotation()'s takeoff
# branch), so a trick can only ever be scored for spins completed since leaving the
# ground, not carried over from a previous jump.
var trick_rotation_progress: float = 0.0
var trick_spin_count: int = 0
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
var debug_stuck_event_count: int = 0
# Which of the two velocity models ran this frame. Stored rather than re-derived:
# apply_grounded_floor_snap() needs it after move_and_slide(), and an external probe
# cannot reconstruct the choice from post-move state, because move_and_slide()
# rewrites velocity on any grounded frame that found a contact.
var is_using_grounded_model: bool = false
# True from a jump impulse until the apex. Replaces reading `velocity.y < 0.0` as a
# proxy for "ascending", which an uphill surface tangent also satisfies.
var is_jump_ascending: bool = false
# Tracked separately from is_on_floor() so the landing squash only fires on the
# false->true edge, not every grounded frame.
var was_on_floor: bool = false
var squash_stretch_tween: Tween
# animated_sprite's rest scale, as authored in player.tscn. play_squash_stretch()
# multiplies against this rather than Vector2.ONE, since the sprite's rest scale
# isn't 1:1 (it's sized down from the source art's native resolution).
var sprite_base_scale: Vector2 = Vector2.ONE
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
	animated_sprite.modulate = PLAYER_DEFAULT_COLOR
	sprite_base_scale = animated_sprite.scale
	airborne_rotation = animated_sprite.rotation
	if terrain_generator == null:
		push_error("Player requires a TerrainGenerator sibling.")
	setup_debug_state_label()


# Jump entry point for input paths that can't go through the "ui_accept" action.
# Touch on Android is one: measured on device (2026-08-02), a tap's action state
# never produced a just_pressed edge inside _physics_process, so the poll below
# can't see it. Setting the buffer directly reuses the exact same coyote/buffer
# gate a keyboard jump uses -- only the delivery differs.
#
# Gated on is_jump_suppressed as well as the poll below, and BOTH are load-bearing:
# gating only the "ui_accept" poll would leave touch jumps fully working on Android,
# which is the platform this ships to.
func buffer_jump() -> void:
	if is_jump_suppressed:
		return
	jump_buffer_timer = JUMP_BUFFER_DURATION


func _physics_process(delta: float) -> void:
	speed_manager.update(delta)
	if DEBUG_ALLOW_MANUAL_SPEED_CONTROL:
		apply_manual_speed_input(delta)

	if is_on_floor():
		coyote_timer = COYOTE_TIME_DURATION
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("ui_accept") and not is_jump_suppressed:
		jump_buffer_timer = JUMP_BUFFER_DURATION
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	# not is_jump_ascending guards against a real double-launch: is_on_floor() still reads
	# true for one frame after start_glide()'s liftoff (move_and_slide() hasn't run yet to
	# reflect the new upward velocity), so if "ui_accept" is freshly pressed on exactly that
	# frame -- which holding-to-glide does by construction, since it's the same action --
	# coyote_timer and jump_buffer_timer both got refreshed at the top of this function and
	# this branch would re-fire a full ordinary jump on top of the glide launch, discarding
	# it. is_jump_ascending is already true from the glide launch at that point, so this
	# also can't retrigger a genuine mid-jump the same way.
	#
	# is_jump_suppressed is checked here as well as at both input sites, and it is not
	# redundant: a jump buffered in the frames just BEFORE the lake's seam would otherwise
	# still fire once the player is on it, since JUMP_BUFFER_DURATION outlives the crossing
	# of a segment boundary.
	if not is_jump_suppressed and not is_boosting and not is_jump_ascending and coyote_timer > 0.0 and jump_buffer_timer > 0.0:
		velocity.y = JUMP_VELOCITY * upgrade_jump_multiplier * jump_boost_multiplier
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		is_jump_ascending = true
		jumped.emit()
		play_squash_stretch(JUMP_STRETCH_SCALE)
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
	#
	# LOAD-BEARING FOR CHASMS: because is_boosting forces the grounded model whether or not
	# there is a floor, and the grounded branch applies no gravity, a boosting player skims
	# across a chasm at lip height on velocity = (boost_speed, 0) and lands on the far lip.
	# That is what makes a chasm survivable during a boost, when jump input is suppressed for
	# the full 3s -- unlike the obstacle/boost issue in CLAUDE.md's Known issues. It depends on
	# get_collision_chord_slope_angle() returning 0 over a void, which in turn depends on
	# TerrainGenerator keeping the void's entries in chunk_collision_sample_xs. Splitting the
	# boost out of this gate, or pruning those samples, silently turns every boosted chasm into
	# unavoidable death. PowerupManager.can_end_effect() / VOID_GUARDED_EFFECTS covers the
	# other half.
	is_using_grounded_model = (is_boosting and not is_boost_gliding_over_drop()) or (is_on_floor() and not is_jump_ascending)
	var current_speed: float = boost_speed if is_boosting else speed_manager.current_speed
	if is_using_grounded_model:
		var slope_tangent: Vector2 = get_slope_tangent()
		velocity = slope_tangent * current_speed
	else:
		velocity.x = current_speed
		if is_glide_active:
			velocity.y = get_glide_velocity_y(delta)
		else:
			velocity.y += GRAVITY * delta

	var position_before_move: Vector2 = global_position
	debug_velocity_before_slide = velocity
	move_and_slide()
	debug_position_after_slide = global_position
	debug_velocity_after_slide = velocity
	apply_grounded_floor_snap()
	debug_position_after_snap = global_position
	if is_on_floor() and not was_on_floor:
		landed.emit()
		play_squash_stretch(LAND_SQUASH_SCALE)
	was_on_floor = is_on_floor()
	# Measured after the snap deliberately: the snap is part of this frame's motion,
	# and the stall/stuck watchdogs downstream must see where the body actually ended.
	last_physics_displacement = global_position - position_before_move
	# Before the watchdogs, so a player who has just died in a chasm never enters one.
	update_fall_death()
	update_glide_landing_shield(delta)
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


# Purely cosmetic: scales animated_sprite from scale_multiplier * sprite_base_scale
# back to sprite_base_scale around its own centered origin (AnimatedSprite2D is
# centered=true, so no pivot_offset is needed the way ColorRect required one).
# Killing any in-flight tween before restarting means a jump landed on immediately
# after take-off (or vice versa) always reads as one clean punch, not two tweens
# fighting over the same property.
func play_squash_stretch(scale_multiplier: Vector2) -> void:
	if squash_stretch_tween:
		squash_stretch_tween.kill()
	animated_sprite.scale = sprite_base_scale * scale_multiplier
	squash_stretch_tween = create_tween()
	squash_stretch_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	squash_stretch_tween.tween_property(animated_sprite, "scale", sprite_base_scale, SQUASH_STRETCH_DURATION)


func update_visual_rotation(delta: float) -> void:
	if terrain_generator == null:
		return

	var is_grounded: bool = is_on_floor()
	var logged_target_angle: float = animated_sprite.rotation
	if is_grounded:
		# Landing: score whatever spun since the last takeoff, win or not -- no fail
		# state, a missed rotation just scores nothing (see trick_completed's callers).
		if not was_grounded_last_frame and trick_spin_count > 0:
			trick_completed.emit(trick_spin_count)
		trick_spin_count = 0
		trick_rotation_progress = 0.0
		var terrain_angle: float = terrain_generator.get_slope_angle_at_x(global_position.x)
		# This exponential response is always in [0, 1), unlike smoothness * delta.
		# Clamp it to the current target's side of upright so a rapidly reversing
		# slope cannot leave the sprite tilted farther than the sampled terrain.
		var interpolation_weight: float = 1.0 - exp(-ROTATION_SMOOTHNESS * delta)
		var smoothed_rotation: float = lerp_angle(animated_sprite.rotation, terrain_angle, interpolation_weight)
		if terrain_angle >= 0.0:
			animated_sprite.rotation = clampf(smoothed_rotation, 0.0, terrain_angle)
		else:
			animated_sprite.rotation = clampf(smoothed_rotation, terrain_angle, 0.0)
		airborne_rotation = animated_sprite.rotation
		logged_target_angle = terrain_angle
	else:
		if was_grounded_last_frame:
			airborne_rotation = animated_sprite.rotation
			trick_rotation_progress = 0.0
			trick_spin_count = 0
		# Precedence, written down per the plan: hold means glide while a glide effect
		# is active (existing behavior below, sprite locked to airborne_rotation) and
		# spin otherwise.
		if not is_glide_active and is_glide_input_held():
			var spin_delta: float = TRICK_SPIN_RATE * delta
			animated_sprite.rotation += spin_delta
			trick_rotation_progress += spin_delta
			while trick_rotation_progress >= TAU:
				trick_rotation_progress -= TAU
				trick_spin_count += 1
			airborne_rotation = animated_sprite.rotation
		else:
			animated_sprite.rotation = airborne_rotation

	if DEBUG_SLOPE_LOGGING:
		debug_rotation_timer += delta
		if debug_rotation_timer >= 0.5:
			debug_rotation_timer = 0.0
			print("player x=", global_position.x, " target_angle=", logged_target_angle, " rotation=", animated_sprite.rotation, " grounded=", is_grounded, " velocity=", velocity)

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


# The one case where a boost must NOT force the grounded model: the player has skimmed
# across a void and the ground that reappeared is a drop chasm's far lip, far below.
#
# The grounded branch applies no gravity, so without this the body holds its near-lip
# height and glides forward over open air until the boost timer expires -- a visible hover,
# and the reason CHASM_EXIT_DROP stayed 0 through phase 2 (docs/development/terrain.md).
# Releasing the model here hands the body to gravity the instant there is something to fall
# to, so a boosted drop chasm reads as a fall like any other.
#
# Deliberately narrow. It returns false while the player is still OVER the void, because
# that skim is what carries a boosting player across at all (see the LOAD-BEARING FOR
# CHASMS note above), and false within snap reach of the surface, preserving "no airtime
# during a boost" over ordinary bumps. Only a gap the snap cannot close releases the model.
func is_boost_gliding_over_drop() -> bool:
	if not is_boosting or is_dead or terrain_generator == null or is_on_floor():
		return false
	if not terrain_generator.has_ground_at_world_x(global_position.x):
		return false

	var surface_world_y: float = terrain_generator.get_surface_world_y(global_position.x)
	var gap_below_feet: float = (surface_world_y - global_position.y) - get_capsule_half_height()
	return gap_below_feet > FLOOR_SNAP_LENGTH


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


# Death by falling into a chasm.
#
# Deliberately expressed as depth below the height FIELD rather than as an absolute Y or a
# captured lip height, which buys two things:
#
#  * It needs no knowledge of chasms at all. The height field is single-valued and the body is
#    always above the surface on real ground, so a positive depth can only mean a void -- and
#    because get_terrain_height() returns the LIP height across a void, this is exactly "how
#    far below the lip am I", for free.
#  * It is STATELESS, which is what makes it correct across a world rebase. Main.apply_world_rebase
#    runs earlier in tree order and shifts TerrainGenerator.position.y and the body by the same
#    amount in the same frame, and get_surface_world_y() reads the generator's live
#    global_position.y, so this difference is invariant. A captured lip Y would go stale by a
#    full rebase quantum the moment one landed mid-fall.
func update_fall_death() -> void:
	if is_dead or terrain_generator == null or is_on_floor():
		return

	# Inside a DROP chasm's void the field reads near-lip height while the ground being fallen
	# toward is the far lip, exit_drop below it, so measure against that instead. Returns 0 for
	# a level-lipped chasm, leaving the hazard variants' death behaviour untouched.
	var surface_world_y: float = terrain_generator.get_surface_world_y(global_position.x)
	surface_world_y += terrain_generator.get_pending_exit_drop_at_world_x(global_position.x)
	if global_position.y - surface_world_y > FALL_DEATH_DEPTH:
		die()


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
		return

	debug_stuck_event_count += 1
	print("STUCK_DETECTED seed=", get_terrain_session_seed(), " world_x=%.3f" % global_position.x, " event=", debug_stuck_event_count, " net_progress_over_%d_frames=%.3f" % [STUCK_WINDOW_FRAME_COUNT, net_progress])
	debug_stuck_detected.emit(get_terrain_session_seed(), global_position.x)
	recover_from_stall(delta)
	# Clearing the window both resets the measurement against fresh post-recovery
	# data and acts as a ~1s cooldown, so a location that re-sticks gets rescued
	# repeatedly rather than once. It is the ONLY thing preventing a re-report on the
	# next frame -- a `stuck_event_reported` latch used to sit alongside it and was
	# provably dead (set and cleared inside this one call, so its guard could never
	# fire and its reset never had anything to reset). Removed 2026-09-03. If this
	# clear is ever dropped, the latch has to come back with it.
	stuck_motion_x_window.clear()


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


func play_flight_effect(duration: float) -> void:
	flight_trail.play(duration)


# Most pickups happen while grounded (this is a runner, not a platformer), and requiring
# a separate jump press before glide does anything read as "the powerup didn't do
# anything." Same launch mechanism a real jump uses -- is_jump_ascending forces the
# airborne branch below even on the frame is_on_floor() still reads true -- just with
# GLIDE_LAUNCH_VELOCITY instead of JUMP_VELOCITY, and skipped entirely if the pickup
# happened mid-air already (an active jump or a fall), where forcing a snap to launch
# velocity would read as a stutter, not a liftoff.
func start_glide() -> void:
	is_glide_active = true
	if is_on_floor() and not is_jump_ascending:
		velocity.y = GLIDE_LAUNCH_VELOCITY
		is_jump_ascending = true
		coyote_timer = 0.0
		jump_buffer_timer = 0.0


func end_glide() -> void:
	is_glide_active = false


# Reads false while input is suppressed, so no airborne trick spin can be started on the lake
# (update_visual_rotation's spin branch is this function's other caller).
#
# A GLIDE ALREADY IN THE AIR IS EXEMPT, and it was not at first. The original version cut
# thrust the instant the lake began, on the argument that landing on flat, void-free,
# obstacle-free ground is safe by construction -- which is true, and still beside the point:
# the owner hit it in play on 2026-08-14 and what it reads as is the game confiscating a
# powerup they were in the middle of using. Letting the glide keep its thrust costs nothing
# the lake cares about (it is flat, so there is nothing to glide over that matters) and it
# expires on its own timer through can_end_effect() a few seconds later, on the one
# bookkeeping-safe path. Jumping stays blocked regardless -- that is gated separately, at all
# three of its own input sites -- so this cannot become a way to jump on the lake, and the
# spin branch already requires is_glide_active to be false, so no trick can start either.
func is_glide_input_held() -> bool:
	if is_jump_suppressed and not is_glide_active:
		return false
	if Input.is_action_pressed(&"ui_accept"):
		return true
	return main_node != null and main_node.is_touch_held()


# Gravity always applies; holding adds thrust on top of it (net accel upward). Either
# way the result is clamped to the two speed caps, same as GRAVITY's implicit cap is
# usually the level ending before terminal velocity matters anywhere else in this
# project. No altitude cap: chasm-blind flight is an accepted risk (see CLAUDE.md),
# and landing after a glide grants a short obstacle-only shield instead.
func get_glide_velocity_y(delta: float) -> float:
	var new_velocity_y: float = velocity.y + GRAVITY * delta
	if is_glide_input_held():
		new_velocity_y -= GLIDE_THRUST_ACCELERATION * delta
	return clampf(new_velocity_y, GLIDE_MAX_RISE_SPEED, GLIDE_MAX_FALL_SPEED)


# is_shield_from_glide_landing is cleared here, not just in absorb_hit(): a shield granted
# from ANY other source replaces the glide-landing one, and leaving the flag set would let
# update_glide_landing_shield()'s timer expire the replacement. See that function's comment
# for the failure this prevents. update_glide_landing_shield() sets the flag back to true
# immediately after its own call, which is the one case where it should stay set.
func gain_shield() -> void:
	has_shield = true
	is_shield_from_glide_landing = false
	animated_sprite.modulate = PLAYER_SHIELD_COLOR


# Called by obstacle.gd instead of die() on every obstacle hit. Returns whether the
# player survived, so the caller doesn't need to know about has_shield -- it just
# self-disables either way. Obstacle collisions only: fall death and both watchdogs
# call die()/recovery directly and are never routed through here.
func absorb_hit() -> bool:
	if has_shield:
		has_shield = false
		is_shield_from_glide_landing = false
		animated_sprite.modulate = PLAYER_DEFAULT_COLOR
		shield_consumed.emit()
		return true

	die()
	return false


# Grants GLIDE_LANDING_SHIELD_DURATION of has_shield the instant a glide-or-fall-from-
# glide touches down, and expires it on its own timer -- it does NOT go through
# PowerupManager, so a real shield powerup is untouched by it.
#
# THAT CLAIM NEEDS BOTH ORDERINGS GUARDED, and each was a separate bug. A shield powerup is
# UNTIMED -- it sits in PowerupManager.active_effects at INF until an obstacle spends it -- so
# player and manager only stay in sync if every path that clears has_shield either emits
# shield_consumed or is provably looking at a shield this function granted.
#
#   * GLIDE LANDS SECOND (fixed 2026-08-10): the `not has_shield` guard below. Without it,
#     landing while already holding a powerup shield set is_shield_from_glide_landing on a
#     shield this function did not grant. Skipping the grant entirely is right rather than
#     refreshing the timer -- an untimed shield outlasts any 1s window, so there is nothing to
#     add.
#   * GLIDE LANDS FIRST (fixed 2026-08-13): the clear in gain_shield(). Collecting a shield
#     powerup inside the 1s glide-landing window left the flag set, so the expiry below then
#     cleared has_shield on the POWERUP shield.
#
# Either way the old failure was identical: the expiry cleared has_shield while PowerupManager
# still had EFFECT_SHIELD at INF and nothing emitted shield_consumed, so the two disagreed, the
# tint was gone, and the next obstacle killed a player who had paid for a shield.
func update_glide_landing_shield(delta: float) -> void:
	if is_glide_active:
		is_glide_landing_shield_pending = true
	elif is_glide_landing_shield_pending and is_on_floor():
		is_glide_landing_shield_pending = false
		if not has_shield:
			gain_shield()
			is_shield_from_glide_landing = true
			glide_landing_shield_timer = GLIDE_LANDING_SHIELD_DURATION

	if is_shield_from_glide_landing:
		glide_landing_shield_timer -= delta
		if glide_landing_shield_timer <= 0.0:
			has_shield = false
			is_shield_from_glide_landing = false
			animated_sprite.modulate = PLAYER_DEFAULT_COLOR


func die() -> void:
	if is_dead:
		return

	is_dead = true
	died.emit()
