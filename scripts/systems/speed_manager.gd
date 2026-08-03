extends RefCounted

class_name SpeedManager

const INITIAL_SPEED: float = 100.0
# Phase 1: quick ramp up to a comfortably fast cruising speed.
const PHASE1_TARGET_SPEED: float = 500.0
const PHASE1_DURATION: float = 10.0
const PHASE1_ACCELERATION: float = (PHASE1_TARGET_SPEED - INITIAL_SPEED) / PHASE1_DURATION
# Phase 2: much slower ramp from there up to the final cap, so the run keeps
# creeping up in difficulty long after the initial ramp feels "done".
const MAX_SPEED: float = 750.0
const PHASE2_DURATION: float = 120.0 - PHASE1_DURATION
const PHASE2_ACCELERATION: float = (MAX_SPEED - PHASE1_TARGET_SPEED) / PHASE2_DURATION

var current_speed: float = INITIAL_SPEED
var elapsed_time: float = 0.0


func update(delta: float) -> void:
	elapsed_time += delta
	# Incremental (current_speed + accel*delta), not a value recomputed fresh from
	# elapsed_time each call: several debug probes (freeze_ab_runner.gd,
	# stall_recovery_probe.gd, freeze_search.gd) pin current_speed directly to
	# MAX_SPEED right after spawn to sample cap-speed behavior without waiting out
	# the ramp. A formula keyed purely on elapsed_time would silently overwrite
	# that pin on the very next physics frame.
	var acceleration: float = PHASE1_ACCELERATION if elapsed_time < PHASE1_DURATION else PHASE2_ACCELERATION
	current_speed = min(current_speed + (acceleration * delta), MAX_SPEED)


# Debug/testing aid: nudge current_speed within the same [INITIAL_SPEED, MAX_SPEED]
# bounds the normal ramp already respects, so manual control can't push speed (and
# therefore world_x/world_y progression) outside anything already exercised.
func apply_manual_adjustment(delta_amount: float) -> void:
	current_speed = clampf(current_speed + delta_amount, INITIAL_SPEED, MAX_SPEED)
