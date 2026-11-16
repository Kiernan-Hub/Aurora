extends RefCounted

class_name MeltRound

# Isolated bonus-course simulation. No scene, save, normal-run timers or upgrades.
# One-button jumps at a fixed level keep every platform reachable for every skater.
const SPEED: float = 250.0
const GRAVITY: float = 1500.0
const JUMP_SPEED: float = -600.0
const HALF_WIDTH: float = 12.0
const STEP_PITCH: float = 230.0
const PLATFORM_WIDTH: float = 180.0
const RISES: Array[float] = [40.0, 55.0, 45.0, 60.0, 35.0, 50.0]
const MAX_SECONDS: float = 60.0
const CRUMBLE_SECONDS: float = 0.6
const RARE_SECONDS: float = 15.0
const AURORA_SECONDS: float = 30.0

var elapsed: float = 0.0
var x: float = 80.0
var feet_y: float = 0.0
var velocity_y: float = 0.0
var lava_y: float = 180.0
var grounded_index: int = 0
var coyote: float = 0.0
var jump_buffer: float = 0.0
var started: bool = false
var finished: bool = false
var platforms: Array[Dictionary] = [{"index": 0, "x": 0.0, "y": 0.0, "width": 350.0, "stood": 0.0}]
var last_index: int = 0
var last_y: float = 0.0


func request_jump() -> void:
	if not finished:
		jump_buffer = 0.12


func start() -> void:
	started = true


func advance(delta: float) -> void:
	if not started or finished:
		return
	# Fixed-size steps also make slow rendered frames obey the collision sweep.
	var remaining: float = minf(delta, 0.1)
	while remaining > 0.00001 and not finished:
		var step: float = minf(remaining, 1.0 / 120.0)
		_step(step)
		remaining -= step


func _step(delta: float) -> void:
	elapsed += delta
	# Platforms climb ~52px/s. The melt accelerates past that pace, so survival
	# always ends; the rift closes at 60s even with perfect jumps.
	lava_y -= (30.0 + elapsed * 1.4) * delta
	ensure_course()
	jump_buffer = maxf(jump_buffer - delta, 0.0)
	if grounded_index >= 0:
		coyote = 0.10
	else:
		coyote = maxf(coyote - delta, 0.0)
	if jump_buffer > 0.0 and coyote > 0.0:
		velocity_y = JUMP_SPEED
		grounded_index = -1
		coyote = 0.0
		jump_buffer = 0.0
	var before_y: float = feet_y
	x += SPEED * delta
	velocity_y += GRAVITY * delta
	feet_y += velocity_y * delta
	grounded_index = -1
	if velocity_y >= 0.0:
		for platform: Dictionary in platforms:
			if float(platform["stood"]) >= crumble_limit(int(platform["index"])):
				continue
			var top: float = float(platform["y"])
			if x + HALF_WIDTH >= float(platform["x"]) and x - HALF_WIDTH <= float(platform["x"]) + float(platform["width"]) \
					and before_y <= top + 0.01 and feet_y >= top:
				feet_y = top
				velocity_y = 0.0
				grounded_index = int(platform["index"])
				platform["stood"] = float(platform["stood"]) + delta
				break
	if feet_y >= lava_y - 5.0 or elapsed >= MAX_SECONDS:
		finished = true
	while platforms.size() > 1 and float(platforms[0]["x"]) < x - 1500.0:
		platforms.pop_front()


func ensure_course() -> void:
	while 400.0 + last_index * STEP_PITCH < x + 2000.0:
		last_y -= RISES[last_index % RISES.size()]
		last_index += 1
		platforms.append({"index": last_index, "x": 400.0 + (last_index - 1) * STEP_PITCH,
			"y": last_y, "width": PLATFORM_WIDTH, "stood": 0.0})


func bonus_coins() -> int:
	return 10 + mini(int(elapsed) * 2, 120)


static func crumble_limit(index: int) -> float:
	# The starting shelf gives time to read the first gap and learn the rhythm.
	return 2.0 if index == 0 else CRUMBLE_SECONDS


func chest_tier() -> int:
	if elapsed >= AURORA_SECONDS:
		return ChestTypes.Tier.AURORA
	return ChestTypes.Tier.RARE if elapsed >= RARE_SECONDS else -1
