extends Node2D

class_name Main

@onready var player: CharacterBody2D = $Player
@onready var camera_2d: Camera2D = $Camera2D
@onready var terrain_generator: TerrainGenerator = $TerrainGenerator
@onready var timer_label: Label = $CanvasLayer/TimerLabel
@onready var stuck_time_label: Label = $CanvasLayer/StuckTimeLabel

const WORLD_REBASER_SCRIPT: Script = preload("res://scripts/systems/world_rebaser.gd")
const VERTICAL_FOLLOW_MARGIN: float = 72.0
const VERTICAL_FOLLOW_SMOOTHNESS: float = 6.0

# Deliberately not @export: this is the freeze fix, not a tuning knob. While it was
# exported, scenes/main.tscn serialised `world_rebase_enabled = false` and silently
# disabled the fix, which is how the freeze regressed after 5bbc577. Debug harnesses
# still set this directly in code before add_child (see scripts/debug/*.gd).
var world_rebase_enabled: bool = true

var camera_baseline_y: float = 0.0
var camera_y: float = 0.0
var total_world_rebase_shift: float = 0.0
var elapsed_time: float = 0.0


func _ready() -> void:
	camera_baseline_y = camera_2d.global_position.y
	camera_y = camera_baseline_y
	camera_2d.make_current()
	camera_2d.global_position = Vector2(player.global_position.x, camera_y)
	if terrain_generator == null:
		push_error("Main requires a TerrainGenerator child for world rebasing.")
	if not world_rebase_enabled:
		push_warning("World rebasing is DISABLED - the terrain freeze bug will return.")
	(player as Player).debug_stuck_detected.connect(_on_player_stuck_detected)


func _physics_process(delta: float) -> void:
	# Runs before Player/TerrainGenerator (tree order), so this sees the fully
	# settled state of the previous physics frame.
	apply_world_rebase()

	var target_camera_y: float = get_vertical_camera_target()
	var interpolation_weight: float = 1.0 - exp(-VERTICAL_FOLLOW_SMOOTHNESS * delta)
	camera_y = lerpf(camera_y, target_camera_y, interpolation_weight)
	camera_2d.global_position = Vector2(player.global_position.x, camera_y)

	elapsed_time += delta
	timer_label.text = format_elapsed_time(elapsed_time)


# Stamps the real session clock at the moment the player stops making progress, and
# leaves it on screen -- elapsed_time / timer_label keep running normally, this is a
# separate label so "when did it stop" survives even if you looked away and came
# back later. Overwrites on each new stuck event, but every event is also printed
# to the console by Player, so the full history isn't lost.
func _on_player_stuck_detected(session_seed: int, world_x: float) -> void:
	stuck_time_label.visible = true
	stuck_time_label.text = "stuck @ %s (x=%.0f)" % [format_elapsed_time(elapsed_time), world_x]
	print("Player stuck at elapsed=", format_elapsed_time(elapsed_time), " seed=", session_seed, " world_x=", world_x)


func format_elapsed_time(total_seconds: float) -> String:
	var whole_seconds: int = int(total_seconds)
	var minutes: int = whole_seconds / 60
	var seconds: int = whole_seconds % 60
	return "%d:%02d" % [minutes, seconds]


func get_vertical_camera_target() -> float:
	var descent_camera_y: float = player.global_position.y - VERTICAL_FOLLOW_MARGIN
	return maxf(camera_baseline_y, descent_camera_y)


# Shifts the whole play area back toward y=0 so physics contacts keep float
# precision. See world_rebaser.gd for why this is necessary.
#
# Terrain chunks are children of TerrainGenerator, so moving that one node moves
# every chunk that currently exists AND every chunk spawned afterwards. Player and
# camera move by the identical amount, so all relative geometry is preserved and
# the shift is invisible in play.
func apply_world_rebase() -> void:
	if not world_rebase_enabled or terrain_generator == null:
		return

	var shift: float = WORLD_REBASER_SCRIPT.get_rebase_shift(player.global_position.y)
	if shift == 0.0:
		return

	terrain_generator.position.y += shift
	player.global_position.y += shift
	camera_2d.global_position.y += shift
	# Camera follow state is stored in absolute world Y, so it must move too or the
	# camera snaps on the next frame.
	camera_y += shift
	camera_baseline_y += shift
	total_world_rebase_shift += shift
