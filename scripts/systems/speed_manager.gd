extends RefCounted

class_name SpeedManager

const ACCELERATION: float = 2.0
const MAX_SPEED: float = 500.0

var current_speed: float = 220.0


func update(delta: float) -> void:
	current_speed = min(current_speed + (ACCELERATION * delta), MAX_SPEED)