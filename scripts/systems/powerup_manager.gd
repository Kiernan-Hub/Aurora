extends Node

class_name PowerupManager

@export var player_path: NodePath = NodePath("../Player")
@export var powerup_spawner_path: NodePath = NodePath("../TerrainGenerator/PowerupSpawner")
@export var powerup_label_path: NodePath = NodePath("../CanvasLayer/PowerupLabel")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")

signal speed_boost_started
signal speed_boost_ended
signal jump_boost_started
signal jump_boost_ended

const SPEED_BOOST_DURATION: float = 3.0
const SPEED_BOOST_SPEED: float = 1000.0
const COIN_MULTIPLIER: float = 2.0

const JUMP_BOOST_DURATION: float = 3.0
# sqrt(2): jump height is proportional to velocity SQUARED
# (h = v^2 / (2*GRAVITY)), so doubling the HEIGHT the player asked for means
# multiplying JUMP_VELOCITY by sqrt(2), not by 2.
const JUMP_BOOST_VELOCITY_MULTIPLIER: float = 1.4142135

var player: Player
var powerup_spawner: PowerupSpawner
var powerup_label: Label
var terrain_generator: TerrainGenerator
var is_speed_boost_active: bool = false
var speed_boost_time_remaining: float = 0.0
var is_jump_boost_active: bool = false
var jump_boost_time_remaining: float = 0.0
var coin_multiplier: float = 1.0


func _ready() -> void:
	player = get_node_or_null(player_path) as Player
	powerup_spawner = get_node_or_null(powerup_spawner_path) as PowerupSpawner
	powerup_label = get_node_or_null(powerup_label_path) as Label
	# The generator the PowerupSpawner already hangs off, resolved separately because
	# can_end_speed_boost() needs it. Not added to the required set below: a null one only
	# costs the chasm guard, and can_end_speed_boost() degrades to today's behaviour.
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	if player == null or powerup_spawner == null or powerup_label == null:
		push_error("PowerupManager requires a Player, a PowerupSpawner at %s, and a powerup label at %s." % [powerup_spawner_path, powerup_label_path])
		set_process(false)
		return

	powerup_spawner.powerup_collected.connect(_on_powerup_collected)
	powerup_label.visible = false


func _process(delta: float) -> void:
	var label_lines: Array[String] = []

	if is_speed_boost_active:
		speed_boost_time_remaining -= delta
		if speed_boost_time_remaining <= 0.0 and can_end_speed_boost():
			end_speed_boost()
		elif speed_boost_time_remaining > 0.0:
			label_lines.append("BOOST! %.1fs" % speed_boost_time_remaining)

	if is_jump_boost_active:
		jump_boost_time_remaining -= delta
		if jump_boost_time_remaining <= 0.0:
			end_jump_boost()
		else:
			label_lines.append("JUMP x2! %.1fs" % jump_boost_time_remaining)

	powerup_label.visible = not label_lines.is_empty()
	if powerup_label.visible:
		powerup_label.text = "\n".join(label_lines)


func _on_powerup_collected(effect: StringName) -> void:
	match effect:
		&"speed_boost":
			start_speed_boost()
		&"jump_boost":
			start_jump_boost()


func start_speed_boost() -> void:
	is_speed_boost_active = true
	speed_boost_time_remaining = SPEED_BOOST_DURATION
	coin_multiplier = COIN_MULTIPLIER
	player.start_boost(SPEED_BOOST_SPEED)
	speed_boost_started.emit()


# A speed boost must not expire while the player is over a chasm.
#
# The boost forces Player's grounded, gravity-free velocity model whether or not there is a
# floor (see the LOAD-BEARING FOR CHASMS note at player.gd's is_using_grounded_model), which
# is exactly what carries a boosting player across a void -- and it has to, because jump input
# is suppressed for the boost's full 3s. Dropping the boost mid-void restores gravity at lip
# height with no way to jump: unavoidable death, the same class as the obstacle/boost issue in
# CLAUDE.md's Known issues. Extending by the <=0.25s it takes to cross the void at 1000 px/s is
# invisible and removes the failure mode outright.
func can_end_speed_boost() -> bool:
	if terrain_generator == null:
		return true
	return terrain_generator.has_ground_at_world_x(player.global_position.x)


func end_speed_boost() -> void:
	is_speed_boost_active = false
	coin_multiplier = 1.0
	player.end_boost()
	speed_boost_ended.emit()


func start_jump_boost() -> void:
	is_jump_boost_active = true
	jump_boost_time_remaining = JUMP_BOOST_DURATION
	player.start_jump_boost(JUMP_BOOST_VELOCITY_MULTIPLIER)
	jump_boost_started.emit()


func end_jump_boost() -> void:
	is_jump_boost_active = false
	player.end_jump_boost()
	jump_boost_ended.emit()
