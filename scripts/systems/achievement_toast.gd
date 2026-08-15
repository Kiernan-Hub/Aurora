extends Control

class_name AchievementToast

# The game's first transient UI. A quiet two-line notice that fades up near the bottom of the
# screen, holds, and fades out -- "ACHIEVEMENT" over the achievement's name.
#
# WHY THIS IS NOT A GameManager.State AND NOT A SCREEN. GameManager.set_state() is the only thing
# in the project allowed to touch get_tree().paused or a screen's visibility (CLAUDE.md, hard
# rule). Every other Control under CanvasLayer is either a full-screen modal that set_state()
# owns, or a permanent HUD label that is simply always there. This is neither: the game stays
# PLAYING throughout, exactly as the frozen lake itself does, and this node owns its own
# visibility the way LakeReflection owns the mirror's. Nothing here reaches for GameManager.
#
# DIVISION OF LABOUR, matching the lake's. AchievementManager owns WHETHER and WHEN and is the
# only writer of save data; this file owns nothing but the look, and is handed a display name it
# never has to look up. It does not import the ACHIEVEMENTS table and must not start.
#
# THE CHILDREN ARE BUILT IN CODE, not authored in main.tscn, so the whole notice is one node in
# the scene and its layout cannot drift from the constants below. SkateTrack building its core
# line as a child is the precedent.

# Bottom-centre, clear of the terrain the player is actually reading. The HUD's own labels are
# all top-right (TimerLabel, CoinLabel, PowerupLabel), so nothing collides.
const BOTTOM_MARGIN: float = 60.0
const TOAST_HEIGHT: float = 50.0

# Fade up, hold, fade down. Deliberately gentle at both ends: this fires at the far shore of a
# set piece tuned over three revisions, and a hard cut would be the loudest event in it.
const FADE_IN_TIME: float = 0.35
const HOLD_TIME: float = 2.60
const FADE_OUT_TIME: float = 0.60

# Font sizes. The HUD sits at 12 and the modal titles at 32; this lands between, with the kicker
# smaller than the name so the name is what the eye lands on.
const KICKER_FONT_SIZE: int = 11
const NAME_FONT_SIZE: int = 22

# ================= WHY THE TEXT IS OUTLINED AND NOT JUST COLOURED =================
#
# THIS CAN APPEAR OVER ANY OF THE NINE BIOMES, so it can rely on no background colour whatsoever.
# The palettes run from `starlit_night` to `pale_morning`, and the lake surface itself measures
# (182,208,238) -- luma 205, bright enough that plain white text would nearly vanish into it,
# while plain dark text would vanish into a night biome. An outline is the only treatment that
# survives both ends, and it is why this does not simply take a colour from the active palette:
# the notice must be legible before it is pretty, and it has to be legible during a transition
# between two palettes as well.
const OUTLINE_SIZE: int = 5
const OUTLINE_COLOR: Color = Color(0.04, 0.06, 0.10, 0.85)
# Pale ice blue rather than pure white -- the same family as the lake and the ice everywhere else,
# so the notice reads as part of this game rather than as a system dialog.
const NAME_COLOR: Color = Color(0.93, 0.97, 1.0)
# Dimmer, and the kicker is the label rather than the content.
const KICKER_COLOR: Color = Color(0.72, 0.82, 0.92)

@export var achievement_manager_path: NodePath = NodePath("../../AchievementManager")

var achievement_manager: AchievementManager
var kicker_label: Label
var name_label: Label

# This node's own clock, advanced in _process. Not Time.get_ticks_msec(), which keeps running
# while the tree is paused and would age a notice out behind the pause menu -- the same reasoning
# SkateTrack.track_time and LakeReflection.wobble_time are built on.
var toast_time: float = 0.0

# Names still waiting to be shown. Two achievements landing in one frame is not reachable today
# with a single trigger, but it is reachable the moment there are two, and the alternative is
# that one of them is silently overwritten mid-fade.
var pending_names: PackedStringArray = PackedStringArray()


func _ready() -> void:
	visible = false
	set_process(false)

	# A full-width Control across the bottom of the screen would otherwise sit in front of
	# anything placed there and swallow touches. Nothing here is interactive.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Locally computed, never services.is_headless, which is assigned in GameServices._ready()
	# and can still read false here -- the ordering trap CLAUDE.md records twice.
	if DisplayServer.get_name() == "headless":
		return

	layout_toast()
	build_labels()

	achievement_manager = get_node_or_null(achievement_manager_path) as AchievementManager
	if achievement_manager == null:
		# Null-guarded rather than fatal, like the four lake files: a missing notice is a quieter
		# unlock, not a broken game. The achievement itself is still recorded -- that is the
		# manager's job and it does not depend on this node existing.
		push_warning("AchievementToast disabled: no AchievementManager at %s." % achievement_manager_path)
		return

	achievement_manager.achievement_granted.connect(_on_achievement_granted)


# Anchored to the BOTTOM EDGE rather than given a fixed y, because the viewport is
# aspect="expand": the pinned 1152x648 base is a MINIMUM, so a 20:9 phone is taller in world
# units than the editor window and a hard-coded y would float in the middle of it.
func layout_toast() -> void:
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -(BOTTOM_MARGIN + TOAST_HEIGHT)
	offset_bottom = -BOTTOM_MARGIN


func build_labels() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	add_child(column)

	kicker_label = make_label("ACHIEVEMENT", KICKER_FONT_SIZE, KICKER_COLOR)
	column.add_child(kicker_label)

	name_label = make_label("", NAME_FONT_SIZE, NAME_COLOR)
	column.add_child(name_label)


func make_label(text_value: String, font_size: int, font_color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	# Godot's outline is drawn at HALF this value in each direction, so the constant reads as a
	# total thickness. See the header for why an outline is not optional here.
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	return label


func _on_achievement_granted(_id: String, display_name: String) -> void:
	pending_names.append(display_name)
	# Only start the queue if nothing is on screen; a notice already fading gets to finish, and
	# show_next_name() picks the new one up when it does.
	if not visible:
		show_next_name()


func show_next_name() -> void:
	if pending_names.is_empty():
		visible = false
		set_process(false)
		return

	name_label.text = pending_names[0]
	pending_names.remove_at(0)
	toast_time = 0.0
	modulate.a = 0.0
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	toast_time += delta

	var fade_out_start: float = FADE_IN_TIME + HOLD_TIME
	if toast_time < FADE_IN_TIME:
		modulate.a = toast_time / FADE_IN_TIME
	elif toast_time < fade_out_start:
		modulate.a = 1.0
	elif toast_time < fade_out_start + FADE_OUT_TIME:
		modulate.a = 1.0 - (toast_time - fade_out_start) / FADE_OUT_TIME
	else:
		modulate.a = 0.0
		# Straight into the next queued name if there is one, so a pair of simultaneous unlocks
		# reads as two notices in sequence rather than one of them being lost.
		show_next_name()
