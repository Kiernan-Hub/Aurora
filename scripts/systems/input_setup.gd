extends RefCounted

class_name InputSetup

# Godot's built-in "ui_accept" action ships with keyboard/gamepad bindings only --
# there is no native "touch" binding path in the InputMap. Rather than scatter
# platform checks ("is this running on a phone?") through gameplay code, this adds
# ONE mouse-button binding to the exact same action Player already polls
# (Input.is_action_just_pressed("ui_accept") in player.gd's jump check, unchanged).
#
# This binding covers DESKTOP POINTER INPUT ONLY. It does NOT cover touch.
# Touch was assumed to ride along for free via Godot's "Emulate Mouse From Touch"
# setting synthesizing a left-click for every tap -- that assumption was wrong and
# was the Android input bug (2026-08-02): the game started fine (Buttons handle
# touch natively through the GUI) but jump was dead for the whole run. On-device
# measurement (adb logcat, Galaxy S21) showed emulate_mouse_from_touch WAS true and
# the emulated InputEventMouseButton events DID arrive at Main._input -- but this
# action's just_pressed edge never fired in _physics_process regardless, and no
# pointer event of any kind ever reached _unhandled_input. Root cause of either was
# never isolated further; going through "ui_accept" for touch is simply unreliable
# on Android. Touch is therefore handled independently in Main._input (main.gd),
# which calls Player.buffer_jump() directly instead of pressing this action.
# Desktop testing cannot catch any of this: a real mouse click never touches the
# emulation path this action depends on for phones.
#
# static, not per-instance: this only needs to run once per engine process, and a
# plain module-level guard (not an @export, not project.godot) means restarting
# the run (get_tree().reload_current_scene()) can't re-trigger or lose it the way
# a serialized scene property could.
static var has_configured: bool = false


static func configure() -> void:
	if has_configured:
		return
	has_configured = true

	if not InputMap.has_action(&"ui_accept"):
		push_error("InputSetup: built-in action 'ui_accept' is missing; touch/mouse jump input was not registered.")
		return

	var mouse_event: InputEventMouseButton = InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event(&"ui_accept", mouse_event)
