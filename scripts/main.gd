extends Node2D

class_name Main

@onready var player: CharacterBody2D = $Player
@onready var camera_2d: Camera2D = $Camera2D
@onready var terrain_generator: TerrainGenerator = $TerrainGenerator
@onready var timer_label: Label = $CanvasLayer/TimerLabel
@onready var stuck_time_label: Label = $CanvasLayer/StuckTimeLabel
@onready var pause_button: Button = $CanvasLayer/PauseButton

const WORLD_REBASER_SCRIPT: Script = preload("res://scripts/systems/world_rebaser.gd")
const VERTICAL_FOLLOW_MARGIN: float = 72.0
const VERTICAL_FOLLOW_SMOOTHNESS: float = 6.0
# Horizontal follow was a rigid `camera.x = player.x` until 2026-08-01. The
# terrain is static in world space, so the on-screen motion of the ENTIRE view
# is exactly the camera's per-frame displacement -- a rigid follow therefore
# transmits every bit of move_and_slide()'s per-frame x resolution noise
# straight to the screen as world judder. Measured (camera_shake_probe.gd,
# seed 941462462): mean per-frame camera jerk 0.0008 px/frame^2 on flat but
# 0.478 on mega_drop, with the scroll rate REVERSING DIRECTION on 52% of
# mega_drop frames -- a ~30Hz stutter of the whole world. That matches the
# playtest report exactly (flat clean, gentle crests barely there, mega_drop
# unplayable) and explains why the sprite still looks perfectly glued to the
# terrain throughout: sprite-vs-terrain is a pure world-space relationship
# that never involves the camera, so only the shared view shakes.
#
# Measured A/B at this seed (mean camera jerk px/frame^2, mega_drop): rigid
# 0.382 -> 0.062 here, an 84% reduction, with peak jerk 2.13 -> 0.34. Softer
# settings (6.0) measure marginally better still but were not taken: the lead
# term below needs SCROLL_RATE_SMOOTHNESS to stay SLOWER than this constant,
# and at 6.0 the two are equal, which showed up as the follow distance's peak
# excursion growing (10.6px -> 11.4px) as the lead began chasing noise.
const HORIZONTAL_FOLLOW_SMOOTHNESS: float = 8.0
# EMA constant for the scroll-rate estimate that feeds the lead term. Must stay
# slower (lower) than HORIZONTAL_FOLLOW_SMOOTHNESS: the lead multiplies this
# estimate by (1-w)/w (~7x at 8.0), so any frame-to-frame noise left in it is
# amplified straight back into the position this filter exists to smooth.
const SCROLL_RATE_SMOOTHNESS: float = 6.0

# Deliberately not @export: this is the freeze fix, not a tuning knob. While it was
# exported, scenes/main.tscn serialised `world_rebase_enabled = false` and silently
# disabled the fix, which is how the freeze regressed after 5bbc577. Debug harnesses
# still set this directly in code before add_child (see scripts/debug/*.gd).
var world_rebase_enabled: bool = true

var camera_baseline_y: float = 0.0
var camera_y: float = 0.0
var camera_x: float = 0.0
# Sweepable copy of HORIZONTAL_FOLLOW_SMOOTHNESS. Deliberately a plain var and
# NOT @export: main.tscn silently serialising an @export is exactly how
# world_rebase_enabled regressed the freeze fix for weeks. Debug harnesses set
# this in code before add_child (see scripts/debug/camera_shake_probe.gd);
# 0.0 restores the old rigid follow for A/B measurement.
var camera_horizontal_smoothness: float = HORIZONTAL_FOLLOW_SMOOTHNESS
# Smoothed estimate of the player's per-frame x advance, used to cancel the
# follow filter's steady-state lag. Same no-@export reasoning as above.
var camera_scroll_rate: float = 0.0
var camera_lead_enabled: bool = true
var previous_player_x: float = 0.0
var has_previous_player_x: bool = false
var total_world_rebase_shift: float = 0.0
var elapsed_time: float = 0.0


func _ready() -> void:
	InputSetup.configure()
	camera_baseline_y = camera_2d.global_position.y
	camera_y = camera_baseline_y
	camera_x = player.global_position.x
	camera_2d.make_current()
	camera_2d.global_position = Vector2(camera_x, camera_y)
	if terrain_generator == null:
		push_error("Main requires a TerrainGenerator child for world rebasing.")
	if not world_rebase_enabled:
		push_warning("World rebasing is DISABLED - the terrain freeze bug will return.")
	(player as Player).debug_stuck_detected.connect(_on_player_stuck_detected)


# Touch jump. Handled in _input, and by calling Player directly rather than by
# pressing "ui_accept" -- both choices are forced by what the device actually does
# (measured 2026-08-02 via adb logcat on a Galaxy S21, Godot 4.7):
#
#   * Every pointer event reaches _input, and NOT ONE reaches _unhandled_input --
#     not touches, not the emulated mouse buttons, not motion. A fix living in
#     _unhandled_input is attached to a callback that never runs.
#   * "ui_accept" never produced a just_pressed edge inside _physics_process even
#     though correctly-bound InputEventMouseButton events were arriving and
#     emulate_mouse_from_touch was confirmed true. Going through the action at all
#     is therefore unreliable here, so touch bypasses it.
#
# Not consumed with set_input_as_handled(): nothing downstream needs suppressing
# during play, and leaving the event alone keeps every GUI path exactly as it was.
# No explicit "is the game running" check is needed either -- Main uses the default
# process_mode, so while GameManager holds get_tree().paused on the start, pause and
# death screens this callback does not fire at all, and a menu tap cannot leak in as a
# jump. Keyboard and desktop mouse still go the old way, via player.gd's poll of
# the action, which InputSetup binds; only touch takes this path.
#
# The ONE live Control during play is the pause button, and paused-ness cannot cover
# it: it is only visible while the game is running, which is exactly when this
# callback fires. Both input paths leak a jump through it, for DIFFERENT reasons, so
# both are handled by is_pause_button_press() below:
#
#   * Touch takes the path below and would buffer a jump directly -- a hit test is
#     enough to suppress that.
#   * Desktop mouse does NOT take the path below at all. It goes through "ui_accept"
#     (InputSetup binds left-click to it) which player.gd polls in _physics_process,
#     so a hit test here suppresses nothing on its own. Worse, BaseButton emits
#     `pressed` on mouse-UP by default, so the jump already fired on mouse-DOWN a
#     frame before the pause screen appeared. Measured on desktop 2026-08-03: a
#     touch-only hit test did not fix this, which is what exposed the two paths.
#
# The desktop half is fixed the same way the start screen's free jump was -- release
# the action so the poll sees nothing -- and it lands in time because _input runs
# during event flush, before this frame's _physics_process. Not consumed with
# set_input_as_handled(): the Button still needs the event to fire `pressed`.
func _input(event: InputEvent) -> void:
	if is_pause_button_press(event):
		Input.action_release(&"ui_accept")
		return

	var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
	if touch_event == null or not touch_event.pressed:
		return
	(player as Player).buffer_jump()


# True for a press (not a release) of either pointer kind landing inside the pause
# button. Android's emulated-mouse events go down the mouse branch and are covered
# too, so a tap there is suppressed even if it arrives in that form rather than as a
# touch. Returns false whenever the button is hidden, which is every state except
# PLAYING -- the other screens are covered by the tree being paused.
func is_pause_button_press(event: InputEvent) -> bool:
	if pause_button == null or not pause_button.visible:
		return false

	var press_position: Vector2
	var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
	if touch_event != null:
		if not touch_event.pressed:
			return false
		press_position = touch_event.position
	else:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return false
		press_position = mouse_event.position

	return pause_button.get_global_rect().has_point(press_position)


func _physics_process(delta: float) -> void:
	# Runs before Player/TerrainGenerator (tree order), so this sees the fully
	# settled state of the previous physics frame.
	apply_world_rebase()

	var target_camera_y: float = get_vertical_camera_target()
	var interpolation_weight: float = 1.0 - exp(-VERTICAL_FOLLOW_SMOOTHNESS * delta)
	camera_y = lerpf(camera_y, target_camera_y, interpolation_weight)

	var player_x: float = player.global_position.x
	update_camera_scroll_rate(player_x, delta)
	if camera_horizontal_smoothness > 0.0:
		var horizontal_weight: float = 1.0 - exp(-camera_horizontal_smoothness * delta)
		# An exponential follow settles at a lag of (per-frame advance) *
		# (1-w)/w behind its target -- ~38px at cap speed here, which on an
		# auto-runner is forward reaction distance the player can't afford to
		# lose. Leading the target by exactly that amount cancels it, so the
		# filter costs judder rejection only, not visibility. The lead is built
		# from the SMOOTHED scroll rate, never the raw per-frame delta, so it
		# cannot reintroduce the noise being filtered out.
		var lead: float = 0.0
		if camera_lead_enabled:
			lead = camera_scroll_rate * (1.0 - horizontal_weight) / horizontal_weight
		camera_x = lerpf(camera_x, player_x + lead, horizontal_weight)
	else:
		camera_x = player_x

	camera_2d.global_position = Vector2(camera_x, camera_y)

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


# X is never world-rebased (world_rebaser.gd rebases Y only), so this estimate
# needs no rebase correction -- unlike camera_y / camera_baseline_y.
func update_camera_scroll_rate(player_x: float, delta: float) -> void:
	if not has_previous_player_x:
		previous_player_x = player_x
		has_previous_player_x = true
		return

	var raw_scroll_rate: float = player_x - previous_player_x
	previous_player_x = player_x
	var rate_weight: float = 1.0 - exp(-SCROLL_RATE_SMOOTHNESS * delta)
	camera_scroll_rate = lerpf(camera_scroll_rate, raw_scroll_rate, rate_weight)


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
