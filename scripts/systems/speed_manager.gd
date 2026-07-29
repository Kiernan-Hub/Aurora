extends RefCounted

class_name SpeedManager

const ACCELERATION: float = 3.2
const MAX_SPEED: float = 500.0
const INITIAL_SPEED: float = 300.0

var current_speed: float = INITIAL_SPEED


func update(delta: float) -> void:
	current_speed = min(current_speed + (ACCELERATION * delta), MAX_SPEED)


# Debug/testing aid: nudge current_speed within the same [INITIAL_SPEED, MAX_SPEED]
# bounds the normal ramp already respects, so manual control can't push speed (and
# therefore world_x/world_y progression) outside anything already exercised.
func apply_manual_adjustment(delta_amount: float) -> void:
	current_speed = clampf(current_speed + delta_amount, INITIAL_SPEED, MAX_SPEED)
